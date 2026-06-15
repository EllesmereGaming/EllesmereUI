-------------------------------------------------------------------------------
--  EllesmereUICdmSpellPicker.lua
--  Interactive Preview Helpers (used by options spell picker)
--  Spell list building, add/remove/swap/move/replace operations, and
--  custom bar creation/removal.
-------------------------------------------------------------------------------
local _, ns = ...

-- Upvalue aliases (tables/functions populated by EllesmereUICooldownManager.lua)
local ECME                   = ns.ECME
local barDataByKey           = ns.barDataByKey
local cdmBarFrames           = ns.cdmBarFrames
local cdmBarIcons            = ns.cdmBarIcons
local ResolveInfoSpellID     = ns.ResolveInfoSpellID
local ComputeTopRowStride    = ns.ComputeTopRowStride

-------------------------------------------------------------------------------
--  SpellVariant helpers
--
--  A "variant family" is the set { spellID, base spell ID, override spell ID,
--  override-of-base spell ID }. Storing/looking up by family lets us treat
--  Heroism (32182) and Bloodlust override variants as the same logical entry
--  without ever calling them duplicates.
--
--  StoreVariantValue(target, spellID, value, preserveExisting):
--      Writes value into target under every key in spellID's variant family.
--      If preserveExisting is true, only writes when target[key] is nil
--      (first-write-wins).
--
--  ResolveVariantValue(sourceMap, spellID):
--      Returns sourceMap[k] for the first k in spellID's variant family
--      that has a value. Returns nil if none match.
--
--  IsVariantOf(spellIDA, spellIDB):
--      True if A and B share any variant family member.
-------------------------------------------------------------------------------
-- Reject secret-tainted numbers BEFORE comparing. In Midnight, frame:GetSpellID()
-- on active CDM viewer frames (DoTs/HoTs/active buffs) can return a secret
-- number flagged by Blizzard's secure infrastructure. Doing `id > 0` on a
-- secret value taints us. issecretvalue detects the flag without touching
-- the value, and type() reads the type tag (also safe).
local function _IsUsableSID(id)
    if type(id) ~= "number" then return false end
    if issecretvalue and issecretvalue(id) then return false end
    return id > 0 and id == math.floor(id)
end

local function _GetBase(sid)
    if not _IsUsableSID(sid) or not C_Spell or not C_Spell.GetBaseSpell then return nil end
    local b = C_Spell.GetBaseSpell(sid)
    if _IsUsableSID(b) and b ~= sid then return b end
    return nil
end

local function _GetOverride(sid)
    if not _IsUsableSID(sid) or not C_Spell or not C_Spell.GetOverrideSpell then return nil end
    local o = C_Spell.GetOverrideSpell(sid)
    if _IsUsableSID(o) and o ~= sid then return o end
    return nil
end

local function _StoreIfValid(target, id, value, preserveExisting)
    if not _IsUsableSID(id) then return end
    if preserveExisting and target[id] ~= nil then return end
    target[id] = value
end

local function StoreVariantValue(target, spellID, value, preserveExisting)
    if type(target) ~= "table" or not _IsUsableSID(spellID) then return end
    _StoreIfValid(target, spellID, value, preserveExisting)
    _StoreIfValid(target, _GetOverride(spellID), value, preserveExisting)
    local baseID = _GetBase(spellID)
    if baseID then
        _StoreIfValid(target, baseID, value, preserveExisting)
        _StoreIfValid(target, _GetOverride(baseID), value, preserveExisting)
    end
end

local function ResolveVariantValue(sourceMap, spellID)
    if type(sourceMap) ~= "table" or not _IsUsableSID(spellID) then return nil end
    local direct = sourceMap[spellID]
    if direct ~= nil then return direct end
    local baseID = _GetBase(spellID)
    if baseID then
        local v = sourceMap[baseID]
        if v ~= nil then return v end
    end
    local overrideID = _GetOverride(spellID)
    if overrideID then
        local v = sourceMap[overrideID]
        if v ~= nil then return v end
    end
    if baseID then
        local baseOverrideID = _GetOverride(baseID)
        if baseOverrideID then
            local v = sourceMap[baseOverrideID]
            if v ~= nil then return v end
        end
    end
    return nil
end

local function IsVariantOf(spellIDA, spellIDB)
    if not _IsUsableSID(spellIDA) or not _IsUsableSID(spellIDB) then return false end
    if spellIDA == spellIDB then return true end
    if _GetBase(spellIDA) == spellIDB or _GetBase(spellIDB) == spellIDA then return true end
    if _GetOverride(spellIDA) == spellIDB or _GetOverride(spellIDB) == spellIDA then return true end
    local baseA = _GetBase(spellIDA)
    local baseB = _GetBase(spellIDB)
    if baseA and baseB and baseA == baseB then return true end
    return false
end

ns.StoreVariantValue   = StoreVariantValue
ns.ResolveVariantValue = ResolveVariantValue
ns.IsVariantOf         = IsVariantOf

-------------------------------------------------------------------------------
--  GetCanonicalSpellIDForFrame
--
--  Returns the preferred spell ID to STORE for a given Blizzard CDM viewer
--  frame. The picker, the migration, and the runtime resolution all use
--  this so they agree on which ID to use for the same logical spell.
--
--  Priority order (first non-nil wins):
--    1. frame:GetSpellID()              (frame method, most authoritative)
--    2. info.overrideSpellID            (current override variant)
--    3. info.spellID                    (base/canonical ID)
--    4. info.linkedSpellIDs[*]          (any linked variant)
--    5. C_Spell.GetBaseSpell of (1)     (normalize-to-base fallback)
--
--  Why frame:GetSpellID() first: under transforms (e.g. Glacial Spike from
--  Frostbolt), Blizzard's per-frame method returns the active variant the
--  user can actually cast. The picker should store the spell that exists
--  in the world, not whatever the static cooldownInfo says.
-------------------------------------------------------------------------------
local function GetCanonicalSpellIDForFrame(frame)
    if not frame then return nil end

    -- 1. frame:GetSpellID()
    local fnGetSpellID = frame.GetSpellID
    if type(fnGetSpellID) == "function" then
        local sid = fnGetSpellID(frame)
        if _IsUsableSID(sid) then return sid end
    end

    -- 1b. frame:GetAuraSpellID() -- buff bar frames expose the actual aura
    -- variant here (e.g. Eclipse Solar vs Eclipse Lunar) while GetSpellID
    -- may not exist on these frame types.
    local fnGetAura = frame.GetAuraSpellID
    if type(fnGetAura) == "function" then
        local sid = fnGetAura(frame)
        if _IsUsableSID(sid) then return sid end
    end

    -- Resolve cooldownInfo (frame.cooldownInfo OR frame:GetCooldownInfo())
    local info = frame.cooldownInfo
    if not info then
        local fnGetInfo = frame.GetCooldownInfo
        if type(fnGetInfo) == "function" then
            info = fnGetInfo(frame)
        end
    end

    if info then
        -- 2. info.overrideSpellID
        if _IsUsableSID(info.overrideSpellID) then return info.overrideSpellID end
        -- 3. info.spellID
        if _IsUsableSID(info.spellID) then return info.spellID end
        -- 4. info.linkedSpellIDs[*]
        if info.linkedSpellIDs then
            for _, lid in ipairs(info.linkedSpellIDs) do
                if _IsUsableSID(lid) then return lid end
            end
        end
    end

    -- 5. base of frame:GetSpellID() if all else failed
    if type(fnGetSpellID) == "function" then
        local raw = fnGetSpellID(frame)
        if _IsUsableSID(raw) then
            local base = _GetBase(raw)
            if base then return base end
            return raw
        end
    end

    return nil
end
ns.GetCanonicalSpellIDForFrame = GetCanonicalSpellIDForFrame

-------------------------------------------------------------------------------
--  EnumerateCDMViewerSpells
--
--  Walks the CD/util viewer pools and returns an array of canonical spell
--  IDs in viewer-then-layoutIndex order. Used by the picker AND the
--  migration so they share a single source of truth -- the same spells the
--  route map will see at reanchor time.
--
--  Returns: { sid, sid, ... } in render order across both viewers.
-------------------------------------------------------------------------------
local function EnumerateCDMViewerSpells(includeBuffViewer)
    local viewers
    if includeBuffViewer then
        viewers = { "BuffIconCooldownViewer" }
    else
        viewers = { "EssentialCooldownViewer", "UtilityCooldownViewer" }
    end

    local result = {}
    local seen = {}
    local viewerOrder = 0
    local entries = {}

    for _, vName in ipairs(viewers) do
        local viewer = _G[vName]
        if viewer and viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
            for frame in viewer.itemFramePool:EnumerateActive() do
                if frame:IsShown() or frame.cooldownInfo then
                    local sid = GetCanonicalSpellIDForFrame(frame)
                    if _IsUsableSID(sid) and not seen[sid] then
                        seen[sid] = true
                        entries[#entries + 1] = {
                            sid          = sid,
                            cdID         = frame.cooldownID,
                            viewerName   = vName,
                            viewerOrder  = viewerOrder,
                            layoutIndex  = frame.layoutIndex or 0,
                        }
                    end
                end
            end
        end
        viewerOrder = viewerOrder + 10000
    end

    table.sort(entries, function(a, b)
        if a.viewerOrder ~= b.viewerOrder then return a.viewerOrder < b.viewerOrder end
        if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
        return a.sid < b.sid
    end)

    for i, e in ipairs(entries) do
        result[i] = e  -- preserve metadata for picker
    end
    return result
end
ns.EnumerateCDMViewerSpells = EnumerateCDMViewerSpells

-------------------------------------------------------------------------------
--  Unified spell list helpers
--
--  ONE add path and ONE remove path for every CDM bar's assignedSpells list
--  (default bars, custom bars, ghost bars). Variant-aware via IsVariantOf so
--  adding the same spell under a different variant ID collapses to a no-op.
--
--  These are the canonical functions; AddTrackedSpell / RemoveTrackedSpell
--  delegate to them.
-------------------------------------------------------------------------------

--- Find the index of an entry in a spell list.
---
--- Positive IDs (real spells) match by variant family -- adding any
--- variant of an already-stored spell is a no-op.
--- Negative IDs (trinkets <= -13/-14, item presets <= -100) match by
--- exact equality -- variant resolution doesn't apply to injection
--- markers and StoreVariantValue refuses non-positives anyway.
local function FindVariantIndex(spellList, spellID)
    if type(spellList) ~= "table" or type(spellID) ~= "number" or spellID == 0 then
        return nil
    end
    if spellID > 0 then
        for i = 1, #spellList do
            local existing = spellList[i]
            if _IsUsableSID(existing) and IsVariantOf(existing, spellID) then
                return i
            end
        end
    else
        for i = 1, #spellList do
            if spellList[i] == spellID then return i end
        end
    end
    return nil
end
ns.FindVariantIndexInList = FindVariantIndex

--- Add a spellID to a bar's assignedSpells list. Idempotent under variant
--- equivalence (re-adding any variant-family member is a no-op). Returns
--- true on add, false if already present or invalid.
function ns.AddSpellToBar(barKey, spellID)
    if not _IsUsableSID(spellID) then return false end
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    if not sd.assignedSpells then sd.assignedSpells = {} end
    if FindVariantIndex(sd.assignedSpells, spellID) then return false end
    sd.assignedSpells[#sd.assignedSpells + 1] = spellID
    ns._spellOrderDirty = true
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    return true
end

--- Remove a spellID from a bar's assignedSpells list (variant-aware).
--- Returns the removed spellID (the actual stored variant, which may differ
--- from the queried one) or nil if not present.
function ns.RemoveSpellFromBar(barKey, spellID)
    -- Accept positive (real spell) AND negative (trinket / item preset)
    -- IDs. FindVariantIndex handles the dispatch internally.
    if type(spellID) ~= "number" or spellID == 0 then return nil end
    local sd = ns.GetBarSpellData(barKey)
    if not sd or not sd.assignedSpells then return nil end
    local idx = FindVariantIndex(sd.assignedSpells, spellID)
    if not idx then return nil end
    local removed = table.remove(sd.assignedSpells, idx)
    ns._spellOrderDirty = true
    -- Clean up auxiliary per-spell metadata for the removed entry
    if sd.customSpellDurations then sd.customSpellDurations[removed] = nil end
    if sd.customSpellIDs       then sd.customSpellIDs[removed]       = nil end
    if sd.customSpellGroups then
        for variantID, primaryID in pairs(sd.customSpellGroups) do
            if primaryID == removed then sd.customSpellGroups[variantID] = nil end
        end
    end
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    return removed
end

--- Returns array of { cdID, spellID, name, icon, cdmCat, cdmCatGroup, onEUIBar, isKnown }
--- Sorted by viewer order (Essential before Utility), then alpha.
---
--- Walks Blizzard's CDM viewer pools (the live frames the user actually
--- sees), NOT the static category API. This is the same source of truth
--- the route map uses, so the picker contents always match what gets
--- routed to bars at reanchor time.
function ns.GetCDMSpellsForBar(barKey)
    -- Pickers walk the buff icon viewer for buff bars, or the Essential +
    -- Utility viewers for CD/util bars. ns.* exports because IsBarBuffFamily
    -- is defined further down in this file (forward reference).
    local isBuffType = ns.IsBarBuffFamily and ns.IsBarBuffFamily(barKey) or false

    -- Variant-keyed lookup of spells already on THIS bar (for onEUIBar flag).
    local ourPool = {}
    local sd = ns.GetBarSpellData(barKey)
    if sd and sd.assignedSpells then
        for _, sid in ipairs(sd.assignedSpells) do
            if sid and sid ~= 0 then
                StoreVariantValue(ourPool, sid, true, false)
            end
        end
    end

    -- Walk viewer pools via shared helper. Returns entries with metadata
    -- (sid, cdID, viewerName, viewerOrder, layoutIndex) sorted by render
    -- order across all relevant viewers. Picker only enumerates pool members,
    -- so every returned spell is by definition tracked by Blizzard's CDM.
    local entries = EnumerateCDMViewerSpells(isBuffType)

    local spells = {}
    for _, e in ipairs(entries) do
        local sid = e.sid
        local name = C_Spell.GetSpellName(sid)
        local tex  = C_Spell.GetSpellTexture(sid)
        if name then
            local isOnThisBar = (ResolveVariantValue(ourPool, sid) == true)
            spells[#spells + 1] = {
                cdID        = e.cdID,
                spellID     = sid,
                name        = name,
                icon        = tex,
                cdmCat      = e.viewerOrder,  -- preserve viewer grouping for sort
                cdmCatGroup = isBuffType and "buff" or "cooldown",
                onEUIBar    = isOnThisBar,
                -- Picker only enumerates live viewer pool members, which are
                -- always learned. Kept for downstream consumers that branch
                -- on this field.
                isKnown     = true,
            }
        end
    end

    -- Sort: viewer order first (preserves Essential before Utility),
    -- then alpha within each viewer.
    table.sort(spells, function(a, b)
        if a.cdmCat ~= b.cdmCat then return (a.cdmCat or 0) < (b.cdmCat or 0) end
        return a.name < b.name
    end)

    return spells
end

-- (ns.GetTBBSpellPool removed -- TBB disabled pending rewrite)

--- Check if a cooldownID has a Blizzard CDM child (is "displayed")
function ns.IsSpellDisplayedInCDM(barKey, cdID)
    local BLIZZ_CDM_FRAMES = ns.BLIZZ_CDM_FRAMES
    local blizzName = BLIZZ_CDM_FRAMES[barKey]
    if not blizzName then return false end
    local blizzFrame = _G[blizzName]
    if not blizzFrame then return false end
    for i = 1, blizzFrame:GetNumChildren() do
        local child = select(i, blizzFrame:GetChildren())
        if child then
            local cid = child.cooldownID
            if not cid and child.cooldownInfo then
                cid = child.cooldownInfo.cooldownID
            end
            if cid == cdID then return true end
        end
    end
    return false
end

--- One-time migration: convert pre-refactor "assignedSpells as content
--- filter" data on default CD/utility bars into the new "ghost-bar diversion"
--- model. Spells from the Essential and Utility viewer categories that are
--- NOT in any bar's assignedSpells (and NOT already ghosted) are added to
--- __ghost_cd so they remain hidden -- preserving the user's original
--- visual state across the refactor.
---
--- Per-spec lazy because the spell category APIs are spec-dependent. Runs
--- once per spec via the prof._barFilterModelV6 flag, stamped after a
--- successful pass. Skipped if the user has no populated assignedSpells on
--- default CD/utility bars (clean install -- nothing to preserve).
---
--- Buff bars are NOT migrated: under the OLD model, the buff path's
--- viewerBarKey fallback already showed everything from BuffIconCooldownViewer
--- regardless of assignedSpells, so the old visual already matches the new
--- model. Ghost buff bar cleanup is handled by EnsureGhostBars.
function ns.MigrateSpecToBarFilterModelV6()
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return end

    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end

    local prof = sp[specKey]
    if not prof or prof._barFilterModelV6 then return end
    if not prof.barSpells then prof._barFilterModelV6 = true; return end

    local p = ECME.db and ECME.db.profile
    local barList = p and p.cdmBars and p.cdmBars.bars
    if type(barList) ~= "table" then return end

    -- Step 1: orphan cleanup -- drop spell data for bars that no longer exist
    local liveBarKeys = {
        ["cooldowns"]    = true,
        ["utility"]      = true,
        ["buffs"]        = true,
        ["__ghost_cd"]   = true,
    }
    for _, bd in ipairs(barList) do
        if bd.key then liveBarKeys[bd.key] = true end
    end
    for barKey in pairs(prof.barSpells) do
        if not liveBarKeys[barKey] then
            prof.barSpells[barKey] = nil
        end
    end

    -- Skip if both default CD/util bars are empty: nothing to preserve.
    local cdBs = prof.barSpells.cooldowns
    local utBs = prof.barSpells.utility
    local hasCDList = cdBs and cdBs.assignedSpells and #cdBs.assignedSpells > 0
    local hasUTList = utBs and utBs.assignedSpells and #utBs.assignedSpells > 0
    if not hasCDList and not hasUTList then
        prof._barFilterModelV6 = true
        return
    end

    -- Bail if viewer pools aren't populated yet -- the migration must use
    -- the same source of truth as the route map (live viewer pools), so
    -- if Blizzard hasn't filled them yet we retry next session.
    local function HasPopulatedPool()
        for _, vName in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer" }) do
            local v = _G[vName]
            if v and v.itemFramePool and v.itemFramePool.EnumerateActive then
                for _ in v.itemFramePool:EnumerateActive() do
                    return true
                end
            end
        end
        return false
    end
    if not HasPopulatedPool() then return end

    -- Step 2: build assignedSet from the LIVE bar list. Default bars
    -- (cooldowns/utility) contribute too -- their assignedSpells under the
    -- new model is "preferred order / explicit assignment" and we want
    -- those spells to remain visible.
    local assignedSet = {}
    for _, bd in ipairs(barList) do
        if bd.enabled and not bd.isGhostBar
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff"
           and bd.key ~= "buffs" then
            local bs = prof.barSpells[bd.key]
            if bs and bs.assignedSpells then
                for _, sid in ipairs(bs.assignedSpells) do
                    if type(sid) == "number" and sid > 0 then
                        StoreVariantValue(assignedSet, sid, true, false)
                    end
                end
            end
        end
    end

    -- Ensure ghost CD bar exists
    local ghostBs = prof.barSpells.__ghost_cd
    if not ghostBs then
        ghostBs = {}
        prof.barSpells.__ghost_cd = ghostBs
    end
    if not ghostBs.assignedSpells then ghostBs.assignedSpells = {} end

    local existingGhost = {}
    for _, sid in ipairs(ghostBs.assignedSpells) do
        if type(sid) == "number" and sid > 0 then
            StoreVariantValue(existingGhost, sid, true, false)
        end
    end

    -- Build the union of every CD/util spell the user could possibly want
    -- to migrate. Two sources, both contribute:
    --
    --   1. LIVE viewer pools (Essential + Utility itemFramePool active set)
    --      via EnumerateCDMViewerSpells. Catches per-spec / Edit Mode
    --      arrangements where Blizzard places a spell in a viewer that
    --      differs from its static category.
    --
    --   2. STATIC category API (GetCooldownViewerCategorySet for Essential
    --      and Utility). Catches spells that aren't in the live pool at
    --      this exact moment because Blizzard hides them based on combat
    --      state, buff state, or target state. Beacon of Light is the
    --      canonical example: it's Essential for Holy Pally always, but
    --      Blizzard only puts a frame in the pool when relevant.
    --
    -- Either source alone misses spells. The union catches everything.
    local sidUnion = {}  -- sid -> true (deduped)

    -- Source 1: viewer pools
    local entries = EnumerateCDMViewerSpells(false)
    for _, e in ipairs(entries) do
        if _IsUsableSID(e.sid) then sidUnion[e.sid] = true end
    end

    -- Source 2: category API (Essential + Utility)
    local gcs = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local evc = Enum and Enum.CooldownViewerCategory
    if gcs and gci and evc then
        for _, cat in ipairs({ evc.Essential, evc.Utility }) do
            local cdIDs = gcs(cat, true)
            if cdIDs then
                for _, cdID in ipairs(cdIDs) do
                    local info = gci(cdID)
                    if info then
                        local sid = info.overrideSpellID or info.spellID
                        if _IsUsableSID(sid) then sidUnion[sid] = true end
                    end
                end
            end
        end
    end

    -- Walk the union, ghost anything that isn't already assigned or ghosted.
    local addedCount = 0
    for sid in pairs(sidUnion) do
        local isAssigned = ResolveVariantValue(assignedSet, sid)
        local isGhosted  = ResolveVariantValue(existingGhost, sid)
        if not isAssigned and not isGhosted then
            ghostBs.assignedSpells[#ghostBs.assignedSpells + 1] = sid
            StoreVariantValue(existingGhost, sid, true, false)
            addedCount = addedCount + 1
        end
    end

    prof._barFilterModelV6 = true
    return addedCount
end

--- One-shot per-spec migration: merge any pre-existing dormantSpells back
--- into assignedSpells at their stored slot index. The old reconcile model
--- evicted "currently-unknown" spells (pet abilities, choice-node talents,
--- etc.) into dormantSpells to preserve their position. Under the new model
--- assignedSpells is pure user intent and is never mutated based on
--- "is this spell currently known", so dormant entries must be folded back
--- in at their saved positions. After this runs, sd.dormantSpells is wiped.
--- Flagged per-spec via prof._dormantMerged so it only runs once.
function ns.MergeDormantSpellsIntoAssigned()
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return end

    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end

    local prof = sp[specKey]
    if not prof or prof._dormantMerged then return end
    if not prof.barSpells then prof._dormantMerged = true; return end

    for _barKey, bs in pairs(prof.barSpells) do
        if type(bs) == "table" and type(bs.dormantSpells) == "table" then
            if not bs.assignedSpells then bs.assignedSpells = {} end

            -- Collect dormant entries sorted by saved slot (lowest first)
            -- so earlier inserts don't shift later slots.
            local returning = {}
            for sid, slot in pairs(bs.dormantSpells) do
                if type(sid) == "number" and sid ~= 0 and type(slot) == "number" then
                    returning[#returning + 1] = { sid = sid, slot = slot }
                end
            end
            table.sort(returning, function(a, b) return a.slot < b.slot end)

            -- Build dedup set for the active list so we don't double-insert
            local activeSet = {}
            for _, sid in ipairs(bs.assignedSpells) do activeSet[sid] = true end

            for _, entry in ipairs(returning) do
                if not activeSet[entry.sid] then
                    local insertAt = entry.slot
                    if insertAt > #bs.assignedSpells + 1 then insertAt = #bs.assignedSpells + 1 end
                    if insertAt < 1 then insertAt = 1 end
                    table.insert(bs.assignedSpells, insertAt, entry.sid)
                    activeSet[entry.sid] = true
                end
            end

            bs.dormantSpells = nil
        end
    end

    prof._dormantMerged = true
end

--- Lazy-seed assignedSpells from the bar's currently rendered icons.
--- Called by reorder helpers (Swap/Move) when the user reorders a bar
--- whose assignedSpells is empty -- captures the current visible order so
--- the reorder has something to manipulate. After this runs, the bar has a
--- populated assignedSpells that mirrors what was visible before.
local function EnsureBarOrderSeeded(barKey, sd)
    if sd.assignedSpells and #sd.assignedSpells > 0 then return end
    if not sd.assignedSpells then sd.assignedSpells = {} end
    local icons = cdmBarIcons and cdmBarIcons[barKey]
    if not icons then return end
    local fcCache = ns._ecmeFC
    for i = 1, #icons do
        local icon = icons[i]
        if icon then
            local fc = fcCache and fcCache[icon]
            local sid = fc and fc.spellID
            if type(sid) == "number" and sid > 0 then
                sd.assignedSpells[#sd.assignedSpells + 1] = sid
            end
        end
    end
end

--- Swap two tracked spell positions
function ns.SwapTrackedSpells(barKey, idx1, idx2)
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    EnsureBarOrderSeeded(barKey, sd)
    local t = sd.assignedSpells
    if idx1 < 1 or idx2 < 1 then return false end
    local maxIdx = math.max(idx1, idx2)
    while #t < maxIdx do t[#t + 1] = 0 end
    t[idx1], t[idx2] = t[idx2], t[idx1]
    while #t > 0 and (t[#t] == 0 or t[#t] == nil) do t[#t] = nil end
    ns._spellOrderDirty = true
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Move a tracked spell from one position to another (insert, not swap)
function ns.MoveTrackedSpell(barKey, fromIdx, toIdx)
    if fromIdx == toIdx then return false end
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    EnsureBarOrderSeeded(barKey, sd)
    local t = sd.assignedSpells
    if fromIdx < 1 or fromIdx > #t then return false end
    if toIdx < 1 then toIdx = 1 end
    while #t < toIdx do t[#t + 1] = 0 end
    local val = table.remove(t, fromIdx)
    table.insert(t, toIdx, val)
    while #t > 0 and (t[#t] == 0 or t[#t] == nil) do t[#t] = nil end
    ns._spellOrderDirty = true
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Single source of truth for "what type is this bar" / "what family is it in".
---
--- The 3 default bars (cooldowns/utility/buffs) have their barType stamped
--- in DEFAULTS, but legacy installs may have nil barType because the field
--- was added later. Both helpers fall back to key-based inference for those
--- legacy entries.
---
--- Pass either a bar key (string) or a bar data table (with .key and
--- .barType fields). Both forms are accepted for caller convenience.
local function ResolveBarType(bdOrKey)
    local bd, key
    if type(bdOrKey) == "table" then
        bd  = bdOrKey
        key = bd.key
    else
        key = bdOrKey
        bd  = barDataByKey[key]
    end

    -- Live field wins
    if bd and bd.barType then return bd.barType end

    -- Legacy fallback: infer from default key
    if key == "cooldowns" then return "cooldowns" end
    if key == "utility"   then return "utility"   end
    if key == "buffs"     then return "buffs"     end

    return nil
end
ns.GetBarType = ResolveBarType

--- True if a bar is in the "buff" family (default buffs bar OR custom buff
--- bar OR ghost buffs bar). False otherwise. Used by AddTrackedSpell's
--- auto-move sweep, render path, route map, and picker source selection.
---
--- Special cases:
---   __ghost_cd    -> non-buff family
---   custom_buff   -> NOT considered a buff bar (separate aura system)
local function IsBarBuffFamily(bdOrKey)
    local bd, key
    if type(bdOrKey) == "table" then
        bd  = bdOrKey
        key = bd.key
    else
        key = bdOrKey
        bd  = barDataByKey[key]
    end

    if key == "__ghost_cd" then return false end

    local barType = ResolveBarType(bd or key)
    return barType == "buffs"
end
ns.IsBarBuffFamily = IsBarBuffFamily

-- Old local alias for backward compat within this file
local GetBarType = ResolveBarType

-------------------------------------------------------------------------------
--  Centralized Spell Assignment Checks
--  Used by spell pickers, overlay system, and options to determine:
--  1. Is a spell already on ANY bar (CDM bars + TBB)?
--  2. Is a spell tracked in the correct Blizzard CDM section for a bar type?
-------------------------------------------------------------------------------

-- (SpellUsedOnAnyOtherBar deleted: no gray-out check is needed for CD/util/
-- buff custom bar pickers because AddTrackedSpell auto-moves the spell from
-- any other bar in the same family. Adding a spell is always a "claim it"
-- action, never a "blocked because it's already on bar X" failure mode.)

--- Same check but for TBB (Tracking Bars check other Tracking Bars only).
function ns.SpellUsedOnAnyOtherTBB(spellID, excludeIdx)
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if not tbb or not tbb.bars then return nil end
    for i, cfg in ipairs(tbb.bars) do
        if i ~= excludeIdx then
            if cfg.spellID and cfg.spellID == spellID then
                return cfg.name or ("Tracking Bar " .. i)
            end
            if cfg.spellIDs then
                for _, sid in ipairs(cfg.spellIDs) do
                    if sid == spellID then return cfg.name or ("Tracking Bar " .. i) end
                end
            end
        end
    end
    return nil
end

--- Check if a spell is tracked in the correct Blizzard CDM section for a bar type.
--- Returns true if the spell is properly tracked (no popup/overlay needed).
---
--- Rules:
---   CD/utility bar: must be in Essential/Utility viewer
---   Buff bar: must be in BuffIcon viewer (not just Tracked Bars)
---   TBB: must be in BuffBar viewer (not just Tracked Buffs)
--- Cached spell lookup sets. Rebuilt once per RebuildCDMSpellCaches() call
--- instead of doing full category scans per-frame.
local _knownSpellSet = {}    -- learned spells (cat, false)
local _allSpellSet = {}      -- all spells including unlearned (cat, true)
local _cdmSpellCacheDirty = true

function ns.MarkCDMSpellCacheDirty()
    _cdmSpellCacheDirty = true
end

local function RebuildCDMSpellCaches()
    if not _cdmSpellCacheDirty then return end
    _cdmSpellCacheDirty = false
    wipe(_knownSpellSet)
    wipe(_allSpellSet)
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then return end
    local gci = C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return end
    for cat = 0, 3 do
        local knownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, false)
        if knownIDs then
            for _, cdID in ipairs(knownIDs) do
                local info = gci(cdID)
                if info then
                    if info.spellID and info.spellID > 0 then
                        _knownSpellSet[info.spellID] = true
                    end
                    if info.overrideSpellID and info.overrideSpellID > 0 then
                        _knownSpellSet[info.overrideSpellID] = true
                    end
                    local sid = ns.ResolveInfoSpellID(info)
                    if sid and sid > 0 then _knownSpellSet[sid] = true end
                end
            end
        end
        local allIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if allIDs then
            for _, cdID in ipairs(allIDs) do
                local info = gci(cdID)
                if info then
                    if info.spellID and info.spellID > 0 then
                        _allSpellSet[info.spellID] = true
                    end
                    if info.overrideSpellID and info.overrideSpellID > 0 then
                        _allSpellSet[info.overrideSpellID] = true
                    end
                    local sid = ns.ResolveInfoSpellID(info)
                    if sid and sid > 0 then _allSpellSet[sid] = true end
                end
            end
        end
    end
end
ns.RebuildCDMSpellCaches = RebuildCDMSpellCaches

function ns.IsSpellKnownInCDM(spellID)
    if not spellID or spellID <= 0 then return false end
    RebuildCDMSpellCaches()
    return _knownSpellSet[spellID] == true
end

function ns.IsSpellInAnyCDMCategory(spellID)
    if not spellID or spellID <= 0 then return false end
    RebuildCDMSpellCaches()
    return _allSpellSet[spellID] == true
end

--- Add a preset group to a bar.
--- For custom_buff bars: adds ALL spell IDs as plain entries (each gets
--- its own C_UnitAuras check — only the active variant shows).
--- For other bars: adds primary ID with duration/group metadata.
function ns.AddPresetToBar(barKey, preset)
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    if not sd.assignedSpells then sd.assignedSpells = {} end
    local spellList = sd.assignedSpells

    -- Check bar type
    local bd = barDataByKey[barKey]
    local isCustomBuff = bd and bd.barType == "custom_buff"

    if isCustomBuff then
        if preset.glowBased then
            -- Glow-based presets removed (Time Spiral etc.)
            return false
        else
            -- Check ALL preset members against existing spells so partial
            -- overlap is rejected (e.g. variant 701 already on bar blocks
            -- adding preset {700, 701, 702}).
            for _, sid in ipairs(preset.spellIDs) do
                for _, existing in ipairs(spellList) do
                    if existing == sid then return false, "exists" end
                end
            end
            local primaryID = preset.spellIDs[1]
            spellList[#spellList + 1] = primaryID
            if not sd.spellDurations then sd.spellDurations = {} end
            sd.spellDurations[primaryID] = preset.duration or 30
        end
    else
        -- Legacy: add primary ID with duration/group metadata
        local primaryID = preset.spellIDs[1]
        for _, existing in ipairs(spellList) do
            if existing == primaryID then return false, "exists" end
        end
        spellList[#spellList + 1] = primaryID
        if not sd.customSpellDurations then sd.customSpellDurations = {} end
        sd.customSpellDurations[primaryID] = preset.duration
        if not sd.customSpellGroups then sd.customSpellGroups = {} end
        for _, sid in ipairs(preset.spellIDs) do
            sd.customSpellGroups[sid] = primaryID
        end
    end

    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    return true
end

--- Add a tracked spell (spellID) to a bar.
--- Picker-driven add path. The picker always treats add as "claim this
--- spell for the target bar" -- the spell is auto-removed from EVERY other
--- bar in the same family (default + custom + matching ghost) before being
--- added. One spell, one home, always.
---
--- The picker passes spell IDs from GetCanonicalSpellIDForFrame, so they're
--- already in the right form (matching what the route map and reanchor see).
--- No override-to-base normalization needed at this layer.
function ns.AddTrackedSpell(barKey, id)
    -- Validate: must be a non-zero integer. Both positive (real spells) and
    -- negative (trinkets, item presets) IDs are valid -- negatives are
    -- injection markers Phase 3 of CollectAndReanchor uses to inject custom
    -- frames (trinkets at -13/-14, item presets at <= -100).
    if type(id) ~= "number" or id == 0 then return false end
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    if not sd.assignedSpells then sd.assignedSpells = {} end

    -- Dedup against THIS bar. Variant-aware for positive spell IDs;
    -- exact-match for negatives (FindVariantIndex bails on non-positives,
    -- so we use a direct linear scan as a fallback for trinkets / items).
    if id > 0 then
        if FindVariantIndex(sd.assignedSpells, id) then return false end
    else
        for _, existing in ipairs(sd.assignedSpells) do
            if existing == id then return false end
        end
    end

    -- Auto-move from any other bar in the same family.
    --
    -- A spell can only have ONE home in its family at a time. Adding it to
    -- bar X removes it from every other bar in the same family, including
    -- the ghost bar (so a previously-hidden spell auto-restores when claimed
    -- elsewhere). Family classification handled by ns.IsBarBuffFamily.
    -- custom_buff bars are a separate system and are never swept.
    --
    -- Negative IDs only auto-move within the non-buff family (trinkets and
    -- items only belong on CD/util bars).
    local targetBd = barDataByKey[barKey]
    local p = ECME.db.profile
    local targetIsBuff = IsBarBuffFamily(barKey)
    if p and p.cdmBars and p.cdmBars.bars then
        for _, b in ipairs(p.cdmBars.bars) do
            if b.key ~= barKey and b.barType ~= "custom_buff" then
                if IsBarBuffFamily(b) == targetIsBuff then
                    ns.RemoveSpellFromBar(b.key, id)
                end
            end
        end
    end

    -- Top-row insertion for multi-row bars.
    local curCount = #sd.assignedSpells
    local stride, _, topRowCount = ComputeTopRowStride(targetBd or {}, curCount)
    if stride < 1 then stride = 1 end
    local newCount = curCount + 1
    local newStride, _, newTopRow = ComputeTopRowStride(targetBd or {}, newCount)
    if newStride < 1 then newStride = 1 end
    if newStride == stride and newTopRow > topRowCount then
        table.insert(sd.assignedSpells, topRowCount + 1, id)
    else
        sd.assignedSpells[newCount] = id
    end

    if sd.removedSpells then sd.removedSpells[id] = nil end

    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Remove a tracked spell by index. Routes positive viewer spells to the
--- ghost CD bar so they stay in the routing system but are hidden.
--- Picker-driven remove path. Wraps RemoveSpellFromBar.
function ns.RemoveTrackedSpell(barKey, idx)
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    local list = sd.assignedSpells
    if not list or idx < 1 or idx > #list then return false end
    local removedID = list[idx]
    table.remove(list, idx)

    -- Auxiliary metadata cleanup (kept here so the wrapper exposes the same
    -- side effects RemoveSpellFromBar does for symmetry with index-based
    -- removal).
    if removedID and sd.customSpellDurations then sd.customSpellDurations[removedID] = nil end
    if removedID and sd.customSpellIDs       then sd.customSpellIDs[removedID]       = nil end
    if removedID and sd.customSpellGroups then
        for variantID, primaryID in pairs(sd.customSpellGroups) do
            if primaryID == removedID then sd.customSpellGroups[variantID] = nil end
        end
    end

    -- Route the removed spell to the ghost CD bar so frames stay in the
    -- routing system but are hidden. Buff-family bars no longer ghost:
    -- buff visibility is managed by Blizzard's CDM settings. Negative
    -- IDs (presets/trinkets) and non-viewer spells (customs, racials) skip
    -- ghost routing entirely.
    local isNonViewer = removedID and removedID > 0
        and ((sd.customSpellIDs and sd.customSpellIDs[removedID])
          or (ns._myRacialsSet and ns._myRacialsSet[removedID]))
    if removedID and removedID > 0 and not isNonViewer
       and not IsBarBuffFamily(barKey) then
        ns.AddSpellToBar(ns.GHOST_CD_BAR_KEY, removedID)
    end

    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Replace a tracked spell at a given index with a new spellID
function ns.ReplaceTrackedSpell(barKey, idx, newID)
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    if not sd.assignedSpells then sd.assignedSpells = {} end
    local list = sd.assignedSpells
    if idx < 1 then return false end
    while #list < idx do list[#list + 1] = 0 end
    -- Remove duplicate if newID already exists at a different index
    for i, existing in ipairs(list) do
        if existing == newID and i ~= idx then
            table.remove(list, i)
            if i < idx then idx = idx - 1 end
            break
        end
    end
    list[idx] = newID
    while #list > 0 and (list[#list] == 0 or list[#list] == nil) do list[#list] = nil end
    if sd.removedSpells then sd.removedSpells[newID] = nil end
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

-- Add a new custom CDM bar
function ns.AddCDMBar(barType, name, numRows)
    local BuildAllCDMBars = ns.BuildAllCDMBars
    local LayoutCDMBar = ns.LayoutCDMBar
    local RegisterCDMUnlockElements = ns.RegisterCDMUnlockElements
    local MAX_CUSTOM_BARS = ns.MAX_CUSTOM_BARS

    local p = ECME.db.profile
    local bars = p.cdmBars.bars
    -- Count existing custom bars (non-default)
    local customCount = 0
    for _, b in ipairs(bars) do
        if b.key ~= "cooldowns" and b.key ~= "utility" and b.key ~= "buffs" and not b.isGhostBar then
            customCount = customCount + 1
        end
    end
    if customCount >= MAX_CUSTOM_BARS then return nil end
    -- Determine bar type label for default name
    barType = barType or "cooldowns"
    local typeLabel = barType == "cooldowns" and "Cooldowns"
                   or barType == "utility" and "Utility"
                   or barType == "buffs" and "Buffs"
                   or barType == "custom_buff" and "Auras"
                   or "Cooldowns"
    -- Count existing custom bars of this type for numbering
    local typeCount = 0
    for _, b in ipairs(bars) do
        if b.barType == barType then typeCount = typeCount + 1 end
    end
    local key = "custom_" .. (#bars + 1) .. "_" .. GetTime()
    key = key:gsub("%.", "_")
    bars[#bars + 1] = {
        key = key, name = name or ("Custom " .. typeLabel .. " Bar " .. (typeCount + 1)),
        barType = barType,
        enabled = true, iconSize = 36, numRows = numRows or 1,
        spacing = 2,
        borderSize = 1, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
        borderClassColor = false, borderThickness = "thin",
        bgR = 0.08, bgG = 0.08, bgB = 0.08, bgA = 0.6,
        iconZoom = 0.08, iconShape = "none",
        verticalOrientation = false, barBgEnabled = false,        barBgR = 0, barBgG = 0, barBgB = 0,
        showCooldownText = true, showItemCount = true, cooldownFontSize = 12,
        showCharges = true, chargeFontSize = 11,
        desaturateOnCD = true, swipeAlpha = 0.7,
        activeStateAnim = "blizzard",
        anchorTo = "none", anchorPosition = "left",
        anchorOffsetX = 0, anchorOffsetY = 0,
        barVisibility = "always", housingHideEnabled = true,
        visHideHousing = true, visOnlyInstances = false,
        visHideMounted = false, visHideNoTarget = false, visHideNoEnemy = false,
        showStackCount = false, stackCountSize = 11,
        stackCountX = 0, stackCountY = 0,
        stackCountR = 1, stackCountG = 1, stackCountB = 1,
        -- Custom bars use a spell list instead of mirroring Blizzard
        outOfRangeOverlay = false,
        pandemicGlow = true,
        pandemicGlowStyle = -1,
        pandemicGlowColor = { r = 1, g = 1, b = 0 },
        pandemicGlowLines = 8,
        pandemicGlowThickness = 2,
        pandemicGlowSpeed = 4,
    }
    -- Initialize spell data in the global store for this custom bar
    local sd = ns.GetBarSpellData(key)
    if sd then sd.assignedSpells = {} end
    BuildAllCDMBars()
    LayoutCDMBar(key)
    if ns.QueueReanchor then ns.QueueReanchor() end
    RegisterCDMUnlockElements()
    return key
end

-- Remove a custom CDM bar (only custom bars, not the 3 defaults).
-- Spells that were on the deleted bar are migrated to the matching ghost
-- bar for their family so they stay hidden -- without this they'd spill
-- back into the default bar for their viewer category, which is the
-- opposite of what the user wanted (they explicitly created the custom
-- bar to put those spells somewhere specific).
function ns.RemoveCDMBar(key)
    if key == "cooldowns" or key == "utility" or key == "buffs" then return false end
    local RegisterCDMUnlockElements = ns.RegisterCDMUnlockElements
    local p = ECME.db.profile
    for i, barData in ipairs(p.cdmBars.bars) do
        if barData.key == key then
            -- Clean up frame
            local frame = cdmBarFrames[key]
            if frame then EllesmereUI.SetElementVisibility(frame, false) end
            cdmBarFrames[key] = nil
            cdmBarIcons[key] = nil
            p.cdmBarPositions[key] = nil
            table.remove(p.cdmBars.bars, i)

            -- Custom bar deletion: free all spells (don't ghost them). Delete
            -- the bar's spell data from every spec of the ACTIVE profile only.
            -- Other profiles own independent spell stores and must keep their
            -- copy of this bar's spells (this is the fix for deleting a copied
            -- profile's bar wiping the origin). Custom bar definitions are
            -- per-profile but spec-independent, so clear all of THIS profile's
            -- specs to avoid orphaned spell data.
            local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
            if sp then
                for _, specData in pairs(sp) do
                    if type(specData) == "table" and specData.barSpells and specData.barSpells[key] then
                        specData.barSpells[key] = nil
                    end
                end
            end

            -- Unregister from unlock mode
            if EllesmereUI and EllesmereUI.UnregisterUnlockElement then
                EllesmereUI:UnregisterUnlockElement("CDM_" .. key)
            end
            -- Re-register remaining bars to update linkedKeys
            RegisterCDMUnlockElements()
            -- Rebuild route maps and reanchor so frames re-route to the
            -- ghost bar (or wherever the diversion set now sends them)
            if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
            if ns.CollectAndReanchor then ns.CollectAndReanchor() end
            return true
        end
    end
    return false
end

