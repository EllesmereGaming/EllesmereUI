if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_BuffBarStore.lua
--
--  Per-spec unlock-link views and the bar list: add, remove, reorder within a
--  group and broadcast a tracking bar across specs.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._buffBarInternals
-- EllesmereUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local max = math.max

local TBB_DEFAULT_BAR = I.TBB_DEFAULT_BAR

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
I.ecmeSetters[#I.ecmeSetters + 1] = function(v) ECME = v end

-------------------------------------------------------------------------------
--  Per-spec unlock-link views (anchor / width-match / height-match entries)
--
--  Unlock links are stored account-globally by element key, but TBB keys by
--  BAR INDEX ("TBB_1") while bar lists are per-spec -- a raw global entry
--  would glue bar 1 of every spec to one link. Fix: each (profile, spec)
--  keeps its own copy of the TBB child-role entries in a bucket next to
--  tbbPositions. The global stores hold exactly ONE spec's entries -- the
--  "owner", stamped in EllesmereUIDB._tbbLinkOwner -- maintained by
--  SyncTBBUnlockLinks: owner==active banks live->bucket (live stores are
--  that spec's working truth); owner~=active banks the old owner then swaps
--  the active spec's bucket in; force (profile restore replaced the stores
--  wholesale) swaps in only, NEVER banks -- live entries no longer belong to
--  the stamped owner. A spec's first-ever view seeds from live entries,
--  keeping only slots with a bar on that spec.
--
--  Entries where a TBB bar is the TARGET stay under the child's key
--  untouched ("follow whatever bar 1 is on this spec"); the fallback-anchor
--  system covers an empty slot.
-------------------------------------------------------------------------------
do
    local CopyEntry = EllesmereUI.Lite.DeepCopy

    local function LiveStores(create)
        local db = EllesmereUIDB
        if not db then return nil end
        if create then
            db.unlockAnchors     = db.unlockAnchors     or {}
            db.unlockWidthMatch  = db.unlockWidthMatch  or {}
            db.unlockHeightMatch = db.unlockHeightMatch or {}
        end
        return db.unlockAnchors, db.unlockWidthMatch, db.unlockHeightMatch
    end

    local function Bucket(profileName, specKey, create)
        if not profileName or not specKey then return nil end
        local sp = ns.GetSpecProfilesForProfile and ns.GetSpecProfilesForProfile(profileName)
        if not sp then return nil end
        local prof = sp[specKey]
        if not prof then
            if not create then return nil end
            prof = { barSpells = {} }
            sp[specKey] = prof
        end
        if not prof.tbbUnlockLinks and create then
            prof.tbbUnlockLinks = { anchors = {}, wm = {}, hm = {} }
        end
        return prof.tbbUnlockLinks
    end

    -- Copy a live store's TBB child entries into a bucket table (slot-keyed).
    local function BankOne(store, dest)
        wipe(dest)
        if not store then return end
        for k, v in pairs(store) do
            if type(k) == "string" then
                local slot = k:match("^TBB_(%d+)$")
                if slot then dest[slot] = CopyEntry(v) end
            end
        end
    end

    -- A TBB child's Extra Width / Height rides its bucket beside its link (wmx /
    -- hmx; liveField = the account store). The live stores can exist empty
    -- (profile restores write them), so a missing bucket table is created only
    -- once the store holds a TBB entry.
    local function BankExtra(b, field, liveField)
        local db = EllesmereUIDB
        local store = db and db[liveField]
        local dest = b[field]
        if not dest then
            if not store then return end
            local any
            for k in pairs(store) do
                if type(k) == "string" and k:find("^TBB_%d+$") then any = true; break end
            end
            if not any then return end
            dest = {}
            b[field] = dest
        end
        BankOne(store, dest)
    end

    local function Bank(profileName, specKey)
        -- WoW Forever: never recreate a missing bucket here. The saved owner
        -- can name a key the class no longer resolves to, and a recreated
        -- bucket would steer which key the next session reads; a missing
        -- bucket has nothing live to bank.
        if EllesmereUI.IS_FOREVER then
            local sp = profileName and specKey and ns.GetSpecProfilesForProfile
                and ns.GetSpecProfilesForProfile(profileName)
            if not (sp and sp[specKey]) then return end
        end
        local b = Bucket(profileName, specKey, true)
        if not b then return end
        local an, wm, hm = LiveStores(false)
        BankOne(an, b.anchors)
        BankOne(wm, b.wm)
        BankOne(hm, b.hm)
        BankExtra(b, "wmx", "unlockWidthMatchExtra")
        BankExtra(b, "hmx", "unlockHeightMatchExtra")
    end

    -- Replace a live store's TBB child entries with a bucket table's.
    local function SwapOne(store, src)
        local kill
        for k in pairs(store) do
            if type(k) == "string" and k:match("^TBB_%d+$") then
                kill = kill or {}
                kill[#kill + 1] = k
            end
        end
        if kill then
            for _, k in ipairs(kill) do store[k] = nil end
        end
        for slot, v in pairs(src) do
            store["TBB_" .. slot] = CopyEntry(v)
        end
    end

    -- Swap a bucket's extras into the account store: a spec without extras (no
    -- wmx / hmx, or empty) clears every live TBB extra, and a missing store is
    -- created only to hold one. NO_EXTRA is read-only (SwapOne never writes src).
    local NO_EXTRA = {}
    local function SwapExtra(liveField, src)
        local db = EllesmereUIDB
        local store = db[liveField]
        if not store then
            if not src or next(src) == nil then return end
            store = {}
            db[liveField] = store
        end
        SwapOne(store, src or NO_EXTRA)
    end

    local function SwapIn(profileName, specKey)
        local an, wm, hm = LiveStores(true)
        if not an then return end
        local b = Bucket(profileName, specKey, false)
        if not b then
            b = Bucket(profileName, specKey, true)
            if not b then return end
            -- First view for this spec: seed from live entries, keeping only slots that have a bar here.
            BankOne(an, b.anchors)
            BankOne(wm, b.wm)
            BankOne(hm, b.hm)
            local t = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
            local bars = (t and t.bars) or {}
            local sets = { b.anchors, b.wm, b.hm }
            for i = 1, 3 do
                local set, drop = sets[i], nil
                for slot in pairs(set) do
                    if not bars[tonumber(slot)] then
                        drop = drop or {}
                        drop[#drop + 1] = slot
                    end
                end
                if drop then
                    for _, slot in ipairs(drop) do set[slot] = nil end
                end
            end
            -- Extras seed and prune like their links.
            BankExtra(b, "wmx", "unlockWidthMatchExtra")
            BankExtra(b, "hmx", "unlockHeightMatchExtra")
            local xsets = { b.wmx, b.hmx }
            for i = 1, 2 do
                local set = xsets[i]
                if set then
                    for slot in pairs(set) do
                        if not bars[tonumber(slot)] then set[slot] = nil end
                    end
                end
            end
        end
        SwapOne(an, b.anchors)
        SwapOne(wm, b.wm)
        SwapOne(hm, b.hm)
        SwapExtra("unlockWidthMatchExtra", b.wmx)
        SwapExtra("unlockHeightMatchExtra", b.hmx)
        -- Modules memoize views over the anchor DB (extent watch etc.).
        EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
    end

    function ns.SyncTBBUnlockLinks(force)
        if not EllesmereUIDB then return end
        local profName = ns.GetActiveProfileName and ns.GetActiveProfileName()
        local specKey  = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
        if not profName or not specKey then return end
        local own  = EllesmereUIDB._tbbLinkOwner
        local same = own and own.profile == profName and own.spec == specKey
        if force then
            SwapIn(profName, specKey)
        elseif same then
            Bank(profName, specKey)
            return
        else
            if own then Bank(own.profile, own.spec) end
            SwapIn(profName, specKey)
        end
        EllesmereUIDB._tbbLinkOwner = { profile = profName, spec = specKey }
    end

    -- Called by profile-restore choke points right after they replace the live unlock
    -- stores wholesale from an unlockLayout snapshot: the snapshot's TBB entries are stale
    -- copies of whichever spec last saved unlock mode, so the active spec's own entries are re-asserted here.
    EllesmereUI._TBBRestoreUnlockLinks = function()
        ns.SyncTBBUnlockLinks(true)
    end

    -- Unlock Save & Exit: bank the active spec's live TBB links and extras into its
    -- bucket (only while live belongs to it), so a profile restore before the next
    -- bar build cannot swap an older bucket over them.
    EllesmereUI._TBBBankUnlockLinks = function()
        if not EllesmereUIDB then return end
        local own = EllesmereUIDB._tbbLinkOwner
        local profName = ns.GetActiveProfileName and ns.GetActiveProfileName()
        local specKey  = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
        if own and own.profile == profName and own.spec == specKey then
            Bank(profName, specKey)
        end
    end
end

-- Create a new bar config (no rebuild). `targetGid`: nil = follow the last
-- bar's group (quick-add default), 0 = independent, N = that group. Style
-- comes from the group's style source so the bar lands looking like its
-- group; independent bars copy the last bar. Spell identity and stack fields
-- always start fresh.
local function AddTrackedBuffBarCore(tbb, targetGid)
    local bars = tbb.bars
    local gid
    if targetGid ~= nil then
        gid = targetGid
    elseif #bars > 0 then
        gid = ns.TBBBarGroupID(bars[#bars])
    else
        gid = 1
    end

    -- Style priority: 1) preset on a bar already in the target group, 2) the target
    -- group's current look (style source bar), 3) a preset on any bar of this spec
    -- else any saved preset, 4) the last bar's look (legacy inherit), 5) defaults.
    local preset, styleSrc
    if gid ~= 0 and ns.ResolveTBBGroupPreset then
        preset = ns.ResolveTBBGroupPreset(tbb, gid)
    end
    if not preset and gid ~= 0 and ns.TBBGroupStyleSource then
        styleSrc = ns.TBBGroupStyleSource(gid)
    end
    if not preset and not styleSrc and ns.ResolveTBBFallbackPreset then
        preset = ns.ResolveTBBFallbackPreset(tbb)
    end
    if not preset and not styleSrc and #bars > 0 then
        styleSrc = bars[#bars]
    end

    -- Base from pure defaults (spell identity, enable state and stack-threshold numbers
    -- start fresh), then dress it: the style key set is the authoritative visual copy.
    local newBar = {}
    for k, v in pairs(TBB_DEFAULT_BAR) do newBar[k] = v end
    if preset then
        ns.ApplyTBBStylePresetToCfg(preset, newBar)
    elseif styleSrc then
        ns.CopyTBBStyle(styleSrc, newBar)
    end
    newBar.spellID = 0
    newBar.name = "Bar " .. (#bars + 1)
    newBar.popularKey = nil
    newBar.spellIDs = nil
    newBar.baseSpellID = nil
    newBar.customDuration = nil
    newBar.glowBased = nil
    newBar.trackType = nil
    newBar.enabled = true
    ns.TBBSetBarGroup(newBar, gid)
    bars[#bars + 1] = newBar
    tbb.selectedBar = #bars

    -- Vertical bars read better side by side: when a vertical bar FOUNDS a group whose grow direction was never chosen, default it to RIGHT rather than the global DOWN.
    if gid ~= 0 and newBar.verticalOrientation and ns.TBBGroupedCount(gid) <= 1 then
        local g = tbb.groups and tbb.groups[tostring(gid)]
        local hasStored = (g and g.grow) or (gid == 1 and tbb.groupGrowDirection)
        if not hasStored then
            ns.TBBSetGroupGrow(gid, "RIGHT")
        end
    end

    -- Auto-position adjacent to the previous bar; matters only for independent bars (grouped bars chain off their group anchor).
    local p = ECME and ECME.db and ECME.db.profile
    if p then
        local _tbbPos = ns.GetTBBPositions()
        local prevIdx = #bars - 1
        if prevIdx >= 1 then
            local prevPos = _tbbPos[tostring(prevIdx)]
            local prevCfg = bars[prevIdx]
            if prevPos and prevPos.point then
                local px, py = prevPos.x or 0, prevPos.y or 0
                if newBar.verticalOrientation then
                    -- Step sideways by the previous bar's on-screen width (width/height are always VISUAL dimensions).
                    local barW = (prevCfg and prevCfg.width or 24) + 4
                    _tbbPos[tostring(#bars)] = {
                        point = prevPos.point, relPoint = prevPos.relPoint or prevPos.point,
                        x = px + barW, y = py,
                    }
                else
                    local barH = (prevCfg and prevCfg.height or 24) + 4
                    _tbbPos[tostring(#bars)] = {
                        point = prevPos.point, relPoint = prevPos.relPoint or prevPos.point,
                        x = px, y = py + barH,
                    }
                end
            end
        end
    end

    return #bars
end

function ns.AddTrackedBuffBar(targetGid)
    local tbb = ns.GetTrackedBuffBars()
    local idx = AddTrackedBuffBarCore(tbb, targetGid)
    ns.BuildTrackedBuffBars()
    return idx
end

function ns.RemoveTrackedBuffBar(idx)
    local tbb = ns.GetTrackedBuffBars()
    if idx < 1 or idx > #tbb.bars then return end
    local oldCount = #tbb.bars
    table.remove(tbb.bars, idx)
    -- Positions are keyed by bar index: re-key so bars after the removed index keep their coordinates.
    local pos = ns.GetTBBPositions()
    for j = idx, oldCount - 1 do
        pos[tostring(j)] = pos[tostring(j + 1)]
    end
    pos[tostring(oldCount)] = nil
    -- Re-key element-anchor / size-match links the same way (TBB_3 -> TBB_2) so anchors
    -- keep tracking the same visual bar; links pointing AT the deleted bar are severed.
    if EllesmereUI and EllesmereUI.ShiftIndexedAnchorKeys then
        EllesmereUI.ShiftIndexedAnchorKeys("TBB_", idx, oldCount)
    end
    if tbb.selectedBar > #tbb.bars then tbb.selectedBar = max(1, #tbb.bars) end
    ns.BuildTrackedBuffBars()
end

-- Move a grouped bar to place `pos` among its group's members (1 = first). The
-- members trade the slots they already hold, so bars outside the group keep
-- their indices and positions / unlock links stay with their slot: the group
-- stays put and whatever is anchored to it stays anchored. Style is untouched.
-- Returns the bar's new index.
function ns.MoveTrackedBuffBarInGroup(idx, pos)
    local tbb = ns.GetTrackedBuffBars()
    local bars = tbb.bars
    local cfg = bars[idx]
    local gid = ns.TBBBarGroupID(cfg)
    if gid == 0 then return idx end
    local slots, members, from = {}, {}, nil
    for j, c in ipairs(bars) do
        if ns.TBBBarGroupID(c) == gid then
            slots[#slots + 1] = j
            members[#members + 1] = c
            if j == idx then from = #slots end
        end
    end
    pos = max(1, math.min(pos, #slots))
    if pos == from then return idx end
    local oldAnchor = ns.TBBGroupAnchorIndex(gid)
    table.remove(members, from)
    table.insert(members, pos, cfg)
    for k, j in ipairs(slots) do bars[j] = members[k] end
    -- A disabled member can hand the anchor role to another slot: carry the
    -- group origin there, as the group mover's save does for every member.
    local newAnchor = ns.TBBGroupAnchorIndex(gid)
    local posDB = ns.GetTBBPositions()
    local origin = oldAnchor and posDB[tostring(oldAnchor)]
    if newAnchor and newAnchor ~= oldAnchor and origin then
        posDB[tostring(newAnchor)] = { point = origin.point, relPoint = origin.relPoint, x = origin.x, y = origin.y }
    end
    ns.BuildTrackedBuffBars()
    return slots[pos]
end

-- Stable identity for the broadcast toggle and the single source of truth for whether a
-- bar can broadcast across specs: only when it targets a spec-agnostic buff -- a preset
-- (popularKey, keyed "p:<key>") or a custom buff ID (keyed "s:<spellID>"). A Blizzard
-- CDM tracked spell is spec/class- specific and must NEVER be broadcastable; it's told
-- apart from a custom buff by having NO customDuration (custom-buff popup always sets
-- one, CDM picker clears it). Freshly-added empty bars return nil.
function ns.TBBBroadcastKey(cfg)
    if type(cfg) ~= "table" then return nil end
    if cfg.popularKey and cfg.popularKey ~= "" then return "p:" .. cfg.popularKey end
    if cfg.spellID and cfg.spellID > 0
       and type(cfg.customDuration) == "number" and cfg.customDuration > 0 then
        return "s:" .. tostring(cfg.spellID)
    end
    return nil
end

-- Broadcastable only when TBBBroadcastKey yields an identity (preset or custom buff); Blizzard CDM spells and empty bars are excluded.
function ns.IsTrackedBuffBarBroadcastable(cfg)
    return ns.TBBBroadcastKey(cfg) ~= nil
end

-- True when the bar's buff is marked broadcast to all specs (button reads "Remove Bar from All Specs"). Read from the persistent per-profile set.
function ns.IsTrackedBuffBarBroadcast(cfg)
    local key = ns.TBBBroadcastKey(cfg)
    if not key then return false end
    local set = ns.GetActiveTBBBroadcastSet and ns.GetActiveTBBBroadcastSet()
    return set ~= nil and set[key] == true
end

-- Copy a configured bar (preset or custom buff) into every OTHER spec of the player's
-- class; config and position are deep-copied so it appears identically everywhere.
-- Specs already holding it are skipped, so repeated clicks never pile up duplicates.
-- Returns the number of specs added to.
function ns.AddBarToAllSpecs(srcIdx)
    local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy
    if not DeepCopy then return 0 end
    local activeKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not activeKey then return 0 end

    local srcTbb = ns.GetTrackedBuffBars()
    local srcBar = srcTbb and srcTbb.bars and srcTbb.bars[srcIdx]
    if not ns.IsTrackedBuffBarBroadcastable(srcBar) then return 0 end

    local srcPos = ns.GetTBBPositions()[tostring(srcIdx)]

    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return 0 end

    local function HasSameBar(bars)
        for _, b in ipairs(bars) do
            -- A cooldown-tracking bar is never the same bar as a buff bar for the same spell: track types must match first.
            if (b.trackType or "buff") == (srcBar.trackType or "buff") then
                if srcBar.popularKey and srcBar.popularKey ~= "" then
                    if b.popularKey == srcBar.popularKey then return true end
                elseif (not b.popularKey or b.popularKey == "")
                       and b.spellID and b.spellID == srcBar.spellID then
                    return true
                end
            end
        end
        return false
    end

    local added = 0
    -- WoW Forever: the class has no other spec to copy into (the store key it
    -- runs on is the only one it reads).
    local numSpecs = (not EllesmereUI.IS_FOREVER) and GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID = C_SpecializationInfo.GetSpecializationInfo(i)
        if specID then
            local key = tostring(specID)
            if key ~= activeKey then
                if not sp[key] then sp[key] = { barSpells = {} } end
                local prof = sp[key]
                if not prof.trackedBuffBars then
                    prof.trackedBuffBars = { selectedBar = 1, bars = {} }
                end
                local tbb = prof.trackedBuffBars
                if not HasSameBar(tbb.bars) then
                    local newBar = DeepCopy(srcBar)
                    -- Join the target spec's group only when its bars all live in ONE
                    -- group (mirrors quick-add); otherwise start independent so its layout
                    -- stays undisturbed. Empty spec starts the bar in group 1.
                    local gid
                    if #tbb.bars == 0 then
                        gid = 1
                    else
                        gid = ns.TBBBarGroupID(tbb.bars[1])
                        for j = 2, #tbb.bars do
                            if ns.TBBBarGroupID(tbb.bars[j]) ~= gid then gid = 0; break end
                        end
                    end
                    ns.TBBSetBarGroup(newBar, gid)
                    local newIdx = #tbb.bars + 1
                    tbb.bars[newIdx] = newBar
                    if srcPos then
                        if not prof.tbbPositions then prof.tbbPositions = {} end
                        prof.tbbPositions[tostring(newIdx)] = DeepCopy(srcPos)
                    end
                    added = added + 1
                end
            end
        end
    end

    -- Mark broadcast so the button flips to "Remove..." in every spec; set even when added == 0 (all specs already held it).
    -- WoW Forever copies nowhere (see above), so nothing is marked there.
    local set = (not EllesmereUI.IS_FOREVER) and ns.GetActiveTBBBroadcastSet and ns.GetActiveTBBBroadcastSet()
    if set then
        local key = ns.TBBBroadcastKey(srcBar)
        if key then set[key] = true end
    end

    return added
end

-- Inverse of AddBarToAllSpecs: remove the bar's buff from every OTHER spec and clear the
-- broadcast flag. The CURRENT spec's bar is left untouched. Returns specs removed from.
function ns.RemoveBarFromAllSpecs(srcIdx)
    local activeKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not activeKey then return 0 end

    local srcTbb = ns.GetTrackedBuffBars()
    local srcBar = srcTbb and srcTbb.bars and srcTbb.bars[srcIdx]
    local broadcastKey = ns.TBBBroadcastKey(srcBar)
    if not broadcastKey then return 0 end

    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return 0 end

    local function Matches(b)
        -- Track types must match: a broadcast buff bar for spell X must NEVER delete a cooldown-tracking bar for the same spell.
        if (b.trackType or "buff") ~= (srcBar.trackType or "buff") then
            return false
        end
        if srcBar.popularKey and srcBar.popularKey ~= "" then
            return b.popularKey == srcBar.popularKey
        else
            return (not b.popularKey or b.popularKey == "")
                   and b.spellID and b.spellID == srcBar.spellID
        end
    end

    local removed = 0
    local numSpecs = (not EllesmereUI.IS_FOREVER) and GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID = C_SpecializationInfo.GetSpecializationInfo(i)
        if specID then
            local specKey = tostring(specID)
            if specKey ~= activeKey then
                local prof = sp[specKey]
                local tbb = prof and prof.trackedBuffBars
                if tbb and tbb.bars and #tbb.bars > 0 then
                    -- Rebuild excluding matches, re-keying positions so compacted indices and
                    -- tbbPositions stay aligned (plain table.remove would strand stale indices).
                    local oldPos = prof.tbbPositions or {}
                    local newBars, newPos = {}, {}
                    local didRemove = false
                    for j, b in ipairs(tbb.bars) do
                        if Matches(b) then
                            didRemove = true
                        else
                            newBars[#newBars + 1] = b
                            local p = oldPos[tostring(j)]
                            if p then newPos[tostring(#newBars)] = p end
                        end
                    end
                    if didRemove then
                        tbb.bars = newBars
                        prof.tbbPositions = newPos
                        if tbb.selectedBar and tbb.selectedBar > #newBars then
                            tbb.selectedBar = math.max(1, #newBars)
                        end
                        removed = removed + 1
                    end
                end
            end
        end
    end

    -- Clear the broadcast flag so the button flips back to "Add...".
    local set = ns.GetActiveTBBBroadcastSet and ns.GetActiveTBBBroadcastSet()
    if set then set[broadcastKey] = nil end

    return removed
end

I.AddTrackedBuffBarCore = AddTrackedBuffBarCore
I.broken = false
