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

-- Per-cooldownID cache of the last CLEAN frame:GetSpellID(). On an ACTIVE
-- buff/HoT/DoT viewer frame GetSpellID()/GetAuraSpellID() return secret values,
-- so while the aura is up we cannot read the live talent form (e.g. 432496
-- Holy Bulwark) -- resolution would otherwise degrade to the generic
-- cooldownInfo.spellID (e.g. 137029 Holy Paladin, a spec aura with a generic
-- icon). We reuse the clean value captured when this same cooldownID's frame
-- was last seen INACTIVE, so the picker/preview agree on the displayed spell
-- regardless of aura state and never offer the generic variant. Shared (ns) so
-- the reanchor pass can prime it at login. Self-heals: any later clean read
-- overwrites the entry, so a re-talented cooldownID re-resolves on next scan.
ns._cdmCleanSidByCDID = ns._cdmCleanSidByCDID or {}
local _cleanSidByCDID = ns._cdmCleanSidByCDID

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
        if _IsUsableSID(sid) then
            -- Clean read: cache it by cooldownID so an active (secret) read of
            -- this same frame later still resolves to the live talent form.
            local cdid = frame.cooldownID
            if type(cdid) == "number" then _cleanSidByCDID[cdid] = sid end
            return sid
        end
    end

    -- 1b. frame:GetAuraSpellID() -- buff bar frames expose the actual aura
    -- variant here (e.g. Eclipse Solar vs Eclipse Lunar) while GetSpellID
    -- may not exist on these frame types.
    local fnGetAura = frame.GetAuraSpellID
    if type(fnGetAura) == "function" then
        local sid = fnGetAura(frame)
        if _IsUsableSID(sid) then return sid end
    end

    -- 1c. Active-frame fallback: GetSpellID/GetAuraSpellID returned secret/nil
    -- (the aura is up). Reuse the clean GetSpellID captured for this cooldownID
    -- while the frame was inactive, instead of degrading to the generic
    -- cooldownInfo.spellID below.
    local cdid = frame.cooldownID
    if type(cdid) == "number" then
        local cached = _cleanSidByCDID[cdid]
        if cached then return cached end
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
                    -- Dedup identity. In the BUFF viewer each slot is a distinct
                    -- cooldownID, and Blizzard can report the SAME canonical
                    -- spellID for two DIFFERENT cooldownIDs (Diabolist: the
                    -- Demonic Art slot reports Diabolic Ritual's id) -- deduping
                    -- by sid there wrongly merges the two into one, so the user
                    -- can't see or style them individually. Key on cooldownID so
                    -- both survive. CD/util viewers keep sid-dedup to collapse a
                    -- spell that shows up in two viewers. Non-colliding specs are
                    -- unaffected: there a unique sid implies a unique cooldownID.
                    local cd = frame.cooldownID
                    local dkey = (includeBuffViewer and type(cd) == "number")
                        and ("c" .. cd) or sid
                    if _IsUsableSID(sid) and dkey ~= nil and not seen[dkey] then
                        seen[dkey] = true
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
    -- Mutual exclusivity with the ghost bar: putting a spell on a VISIBLE bar
    -- un-hides it. The route map gives the ghost the highest priority, so a spell
    -- left in both would stay hidden; remove it from __ghost_cd so it shows.
    if barKey ~= ns.GHOST_CD_BAR_KEY and ns.RemoveSpellFromBar then
        ns.RemoveSpellFromBar(ns.GHOST_CD_BAR_KEY, spellID)
    end
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
    if sd.spellDurations       then sd.spellDurations[removed]       = nil end
    if sd.customSpellIDs       then sd.customSpellIDs[removed]       = nil end
    if sd.customSpellGroups then
        for variantID, primaryID in pairs(sd.customSpellGroups) do
            if primaryID == removed then sd.customSpellGroups[variantID] = nil end
        end
    end
    -- Default buffs bar: scrub the removed custom buff's stable order key.
    -- Absent keys are otherwise kept forever as gaps (the talent-swap feature),
    -- but a user-removed custom buff never returns to fill its gap -- and the
    -- accumulated orphans desync the preview's rendered slots from the array.
    -- Blizzard-tracked buffs key as "c"..cooldownID and are unaffected.
    if barKey == "buffs" and type(removed) == "number" and removed > 0
       and type(sd.buffDisplayOrder) == "table" then
        local t = sd.buffDisplayOrder
        local skey = "s" .. removed
        for i = #t, 1, -1 do
            if t[i] == skey then table.remove(t, i) end
        end
    end
    -- Hosted-buff bookkeeping. Removing the MARKER (or a legacy plain entry
    -- that represents the buff: flag set, no marker in the list) un-hosts the
    -- buff. Without this, the flag is orphaned and the options self-heal
    -- re-appends the spell to this bar -- the "removed spell comes back and
    -- shows on two bars" bug. Removing a plain entry while a marker exists is
    -- a cooldown-only removal: the hosted buff stays.
    local hostedSid = ns.HostedBuffMarkerToSpell and ns.HostedBuffMarkerToSpell(removed)
    if not hostedSid and removed and removed > 0
       and sd.hostedBuffSpellIDs and sd.hostedBuffSpellIDs[removed]
       and not (ns.ListHasHostedMarker and ns.ListHasHostedMarker(sd.assignedSpells, removed)) then
        hostedSid = removed
    end
    if hostedSid and sd.hostedBuffSpellIDs then sd.hostedBuffSpellIDs[hostedSid] = nil end
    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    return removed
end

-------------------------------------------------------------------------------
--  EnumerateCDMSettingsCatalog
--
--  Arrangement-aware, talent-independent enumeration of the player's tracked
--  CD/utility cooldowns, read from the Blizzard CDM settings panel's data
--  provider. Unlike the live viewer pools, the catalog includes spells the
--  player has NOT talented into (they never get a viewer frame); unlike the
--  static category API, it respects the user's arrangement -- a spell the
--  user moved to Not Displayed reads as a Hidden category and is skipped, and
--  the returned order is the user's arranged order.
--
--  READ-ONLY: getter calls only, every step pcall-guarded. Returns nil when
--  the provider or any expected method is missing so callers fall back to the
--  live-pool behavior unchanged (hard zero-impact fallback).
--
--  Returns: array of { cdID, sid, category } in the user's arranged order,
--  Essential and Utility categories only.
-------------------------------------------------------------------------------
function ns.EnumerateCDMSettingsCatalog(wantSet)
    local evc = Enum and Enum.CooldownViewerCategory
    if not evc then return nil end
    -- Default (no arg): CD/utility catalog (Essential + Utility), preserving the
    -- original behavior for existing callers. Buff (TrackedBuff = 2) and
    -- tracked-bar (TrackedBar = 3) callers pass an explicit { [catValue] = true }
    -- set so each bar type scopes its own catalog and never cross-contaminates.
    if wantSet == nil then
        if evc.Essential == nil or evc.Utility == nil then return nil end
        wantSet = { [evc.Essential] = true, [evc.Utility] = true }
    end
    local settings = _G.CooldownViewerSettings
    if not settings or type(settings.GetDataProvider) ~= "function" then return nil end
    local okP, provider = pcall(settings.GetDataProvider, settings)
    if not okP or type(provider) ~= "table" then return nil end
    if type(provider.GetOrderedCooldownIDs) ~= "function"
       or type(provider.GetCooldownInfoForID) ~= "function" then return nil end
    local okO, ordered = pcall(provider.GetOrderedCooldownIDs, provider)
    if not okO or type(ordered) ~= "table" then return nil end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not gci then return nil end

    local result = {}
    for _, cdID in ipairs(ordered) do
        local okI, pInfo = pcall(provider.GetCooldownInfoForID, provider, cdID)
        local category
        if okI and type(pInfo) == "table" then category = pInfo.category end
        if category ~= nil and wantSet[category] then
            -- Resolve the spell id from the C_CooldownViewer info (the same
            -- shape the migration and spell caches use). Prefer the override
            -- form only when the player actually has it -- CDM info can
            -- report a stale override after the talent providing it is gone.
            local info = gci(cdID)
            local sid
            if info then
                local ovr = info.overrideSpellID
                if ovr and ovr > 0 and IsPlayerSpell and IsPlayerSpell(ovr) then
                    sid = ovr
                else
                    sid = info.spellID
                end
            end
            if _IsUsableSID(sid) then
                result[#result + 1] = { cdID = cdID, sid = sid, category = category }
            end
        end
    end
    return result
end

--- Returns array of { cdID, spellID, name, icon, cdmCat, cdmCatGroup, onEUIBar, isKnown }
--- Sorted by viewer order (Essential before Utility), then alpha.
---
--- Walks Blizzard's CDM viewer pools (the live frames the user actually
--- sees), NOT the static category API. This is the same source of truth
--- the route map uses, so the picker contents always match what gets
--- routed to bars at reanchor time. For CD/utility bars, tracked spells
--- with no live frame (untalented) are appended from the settings catalog
--- so whole layouts can be arranged without swapping talents.
function ns.GetCDMSpellsForBar(barKey, includeUntalented)
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
                -- Live viewer pool members are always learned. Catalog
                -- entries appended below may not be.
                isKnown     = true,
            }
        end
    end

    -- CD/utility bars: also list tracked spells that currently have NO live
    -- viewer frame -- untalented spells, plus conditionally-pooled ones that
    -- Blizzard hides based on combat/buff/target state. Sourced from the
    -- settings catalog, which respects the user's arrangement (Not Displayed
    -- spells never appear). When the provider is unavailable the catalog is
    -- nil and nothing is appended (identical to the old behavior). Buff
    -- pickers are untouched.
    if not isBuffType and ns.EnumerateCDMSettingsCatalog then
        local catalog = ns.EnumerateCDMSettingsCatalog()
        if catalog then
            local evc = Enum and Enum.CooldownViewerCategory
            local seenCd, seenSid = {}, {}
            for _, e in ipairs(entries) do
                if e.cdID ~= nil then seenCd[e.cdID] = true end
                StoreVariantValue(seenSid, e.sid, true, false)
            end
            for _, ce in ipairs(catalog) do
                if not seenCd[ce.cdID]
                   and not ResolveVariantValue(seenSid, ce.sid) then
                    local name = C_Spell.GetSpellName(ce.sid)
                    local tex  = C_Spell.GetSpellTexture(ce.sid)
                    if name then
                        local known = false
                        if IsPlayerSpell and IsPlayerSpell(ce.sid) then known = true end
                        spells[#spells + 1] = {
                            cdID        = ce.cdID,
                            spellID     = ce.sid,
                            name        = name,
                            icon        = tex,
                            -- Match the live entries' viewer grouping values
                            -- so catalog spells sort beside learned peers.
                            cdmCat      = (evc and ce.category == evc.Utility) and 10000 or 0,
                            cdmCatGroup = "cooldown",
                            onEUIBar    = (ResolveVariantValue(ourPool, ce.sid) == true),
                            isKnown     = known,
                        }
                        StoreVariantValue(seenSid, ce.sid, true, false)
                    end
                end
            end
        end
    end

    -- Buff bars: also list tracked-but-untalented buffs (no live BuffIcon
    -- frame) from the settings catalog (TrackedBuff category). Picker-only
    -- (includeUntalented) so BarGlows and other consumers stay live-only. When
    -- the provider is unavailable nothing is appended (identical to the old
    -- behavior). Same variant-aware dedup as the CD/util path above.
    if isBuffType and includeUntalented and ns.EnumerateCDMSettingsCatalog then
        local evc = Enum and Enum.CooldownViewerCategory
        local buffCat = evc and (evc.TrackedBuff or 2)
        local catalog = buffCat and ns.EnumerateCDMSettingsCatalog({ [buffCat] = true })
        if catalog then
            local seenCd, seenSid = {}, {}
            for _, e in ipairs(entries) do
                if e.cdID ~= nil then seenCd[e.cdID] = true end
                StoreVariantValue(seenSid, e.sid, true, false)
            end
            for _, ce in ipairs(catalog) do
                if not seenCd[ce.cdID]
                   and not ResolveVariantValue(seenSid, ce.sid) then
                    local name = C_Spell.GetSpellName(ce.sid)
                    local tex  = C_Spell.GetSpellTexture(ce.sid)
                    if name then
                        local known = false
                        if IsPlayerSpell and IsPlayerSpell(ce.sid) then known = true end
                        spells[#spells + 1] = {
                            cdID        = ce.cdID,
                            spellID     = ce.sid,
                            name        = name,
                            icon        = tex,
                            cdmCat      = 0,  -- single buff viewer bucket
                            cdmCatGroup = "buff",
                            onEUIBar    = (ResolveVariantValue(ourPool, ce.sid) == true),
                            isKnown     = known,
                        }
                        StoreVariantValue(seenSid, ce.sid, true, false)
                    end
                end
            end
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

--- One-time per-spec pass that serves TWO purposes with the same logic:
---
---   1. Legacy migration: convert pre-refactor "assignedSpells as content
---      filter" data on default CD/utility bars into the new "ghost-bar
---      diversion" model, preserving the user's original visual state.
---
---   2. Import-authoritative ghosting (_importGhostMode, set on every imported
---      spec): make a freshly imported layout the single source of truth. The
---      import strips all ghost data, so the ghost starts EMPTY -- this pass then
---      ghosts EVERY spell the importer tracks in Blizzard CDM and leaves only
---      the ones the layout assigns to a visible bar (those aren't ghosted), so a
---      cooldown the importer tracks but the layout doesn't place gets hidden
---      instead of spilling onto the default bar.
---
--- Both reduce to the same operation: ghost (tracked spells) MINUS (spells
--- assigned to any visible bar) MINUS (already ghosted). Spells from the
--- Essential and Utility viewer categories that are NOT in any bar's
--- assignedSpells (and NOT already ghosted) are added to __ghost_cd.
---
--- Per-spec lazy because the spell category APIs are spec-dependent. Runs
--- once per spec via the prof._barFilterModelV6 flag, stamped after a
--- successful pass. Skipped if the user has no populated assignedSpells on
--- default CD/utility bars (clean install -- nothing to preserve) UNLESS
--- _importGhostMode is set (an imported layout must run even with empty
--- default bars, e.g. a custom-bar-only layout).
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
    -- EXCEPTION: imported layouts (_importGhostMode) always run. A layout that
    -- intentionally leaves the default bars empty (custom-only) still needs every
    -- tracked spell it doesn't place ghosted, not spilled onto the default bar.
    local cdBs = prof.barSpells.cooldowns
    local utBs = prof.barSpells.utility
    local hasCDList = cdBs and cdBs.assignedSpells and #cdBs.assignedSpells > 0
    local hasUTList = utBs and utBs.assignedSpells and #utBs.assignedSpells > 0
    if not hasCDList and not hasUTList and not prof._importGhostMode then
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
    prof._importGhostMode = nil  -- import-authoritative ghosting done for this spec
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
    -- Buff-family bars seed by the DISPLAYED / canonical id (the same id the
    -- per-icon settings and options preview key off), not fc.spellID -- which for
    -- buffs is the cooldownInfo base / a shared ability id. CD/utility keep
    -- fc.spellID (their icon IS the ability, so the two ids coincide).
    local isBuff = ns.IsBarBuffFamily and ns.IsBarBuffFamily(barKey)
    for i = 1, #icons do
        local icon = icons[i]
        if icon then
            local fc = fcCache and fcCache[icon]
            local sid
            if isBuff then
                sid = (ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(icon))
                    or (fc and fc.spellID)
            else
                sid = fc and fc.spellID
            end
            if type(sid) == "number" and sid > 0 then
                -- A hosted buff seeds as its MARKER: the plain id would register
                -- the same spell's COOLDOWN form on this bar.
                if fc and fc.isHostedBuff and ns.HostedBuffMarker then
                    sd.assignedSpells[#sd.assignedSpells + 1] = ns.HostedBuffMarker(sid)
                else
                    sd.assignedSpells[#sd.assignedSpells + 1] = sid
                end
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

--- Stable display-order key for a Blizzard-tracked buff (cooldownID) or custom.
local function BuffDisplayStableKey(sid, cdID)
    if type(cdID) == "number" then return "c" .. cdID end
    if type(sid) == "number" and sid > 0 then return "s" .. sid end
    return nil
end
ns.BuffDisplayStableKey = BuffDisplayStableKey

--- Spell ids associated with a stored buffDisplayOrder key ("c"..cdID / "s"..sid).
local function SpellIdsForBuffOrderKey(key)
    if type(key) ~= "string" then return nil end
    local pfx, num = string.sub(key, 1, 1), tonumber(string.sub(key, 2))
    if not num or num <= 0 then return nil end
    if pfx == "s" then return num end
    if pfx == "c" and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(num)
        if not info then return nil end
        if _IsUsableSID(info.overrideSpellID) then return info.overrideSpellID end
        if _IsUsableSID(info.spellID) then return info.spellID end
    end
    return nil
end

--- True when a live buff entry matches a stored buffDisplayOrder key, including
--- hero-talent / override variants (cooldownID can drift across talent swaps).
local function BuffOrderKeyMatchesEntry(key, sid, cdID, frame)
    if not key then return false end
    local stable = BuffDisplayStableKey(sid, cdID)
    if stable and stable == key then return true end
    local storedSid = SpellIdsForBuffOrderKey(key)
    if not storedSid then return false end
    if sid and IsVariantOf(storedSid, sid) then return true end
    if frame and ns.GetCanonicalSpellIDForFrame then
        local canon = ns.GetCanonicalSpellIDForFrame(frame)
        if canon and IsVariantOf(storedSid, canon) then return true end
    end
    if cdID and type(cdID) == "number" and ns._cdmCleanSidByCDID then
        local clean = ns._cdmCleanSidByCDID[cdID]
        if clean and IsVariantOf(storedSid, clean) then return true end
    end
    return false
end

--- Enumerate default-buffs-bar entries (viewer pool + this bar's customs/items),
--- minus spells diverted to other buff-family or hosted CD/utility bars.
function ns.CollectDefaultBuffTrackEntries()
    local diverted = {}
    local p = ECME and ECME.db and ECME.db.profile
    if p and p.cdmBars and p.cdmBars.bars then
        for _, otherBd in ipairs(p.cdmBars.bars) do
            if otherBd.enabled and otherBd.key ~= "buffs" then
                local otherSd = ns.GetBarSpellData(otherBd.key)
                if otherBd.barType == "buffs" or otherBd.barType == "custom_buff" then
                    if otherSd and otherSd.assignedSpells then
                        for _, sid in ipairs(otherSd.assignedSpells) do
                            if type(sid) == "number" and sid > 0 then diverted[sid] = true end
                        end
                    end
                elseif otherSd and otherSd.hostedBuffSpellIDs then
                    for sid in pairs(otherSd.hostedBuffSpellIDs) do
                        if type(sid) == "number" and sid > 0 then diverted[sid] = true end
                    end
                end
            end
        end
    end

    local out = {}
    local seen = {}
    local entries = ns.EnumerateCDMViewerSpells and ns.EnumerateCDMViewerSpells(true) or {}
    for _, e in ipairs(entries) do
        -- Dedup on the stable (cooldownID-derived) key, not e.sid: two viewer
        -- slots can share a canonical spellID but are distinct cooldownIDs
        -- (Diabolist Demonic Art vs Diabolic Ritual). Keying on sid here would
        -- re-merge what EnumerateCDMViewerSpells now keeps separate.
        local key = BuffDisplayStableKey(e.sid, e.cdID)
        if e.sid and not diverted[e.sid] and key and not seen[key] then
            seen[key] = true
            out[#out + 1] = {
                key         = key,
                sid         = e.sid,
                cdID        = e.cdID,
                layoutIndex = e.layoutIndex or 0,
            }
        end
    end

    local sdSelf = ns.GetBarSpellData("buffs")
    if sdSelf and sdSelf.assignedSpells then
        local extra = 5000
        if sdSelf.spellDurations then
            for _, sid in ipairs(sdSelf.assignedSpells) do
                if type(sid) == "number" and sid > 0 and (sdSelf.spellDurations[sid] or 0) > 0 then
                    local key = BuffDisplayStableKey(sid, nil)
                    if key and not seen[key] then
                        seen[key] = true
                        out[#out + 1] = { key = key, sid = sid, cdID = nil, layoutIndex = extra }
                        extra = extra + 1
                    end
                end
            end
        end
        extra = 6000
        for _, sid in ipairs(sdSelf.assignedSpells) do
            if type(sid) == "number" and sid <= -100 then
                local key = BuffDisplayStableKey(sid, nil)
                if key and not seen[key] then
                    seen[key] = true
                    out[#out + 1] = { key = key, sid = sid, cdID = nil, layoutIndex = extra }
                    extra = extra + 1
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
        return (a.key or "") < (b.key or "")
    end)
    return out
end

-------------------------------------------------------------------------------
--  Same-spellID buff disambiguation (Diabolist Demonic Art vs Diabolic Ritual)
--
--  Blizzard can report the SAME canonical spellID on two DIFFERENT buff-viewer
--  slots (cooldownIDs). Per-icon buff settings are keyed by spellID, so those
--  two collide onto one entry. We let a COLLIDED slot key its settings by
--  "c"..cooldownID instead, giving each its own entry. Only collided slots do
--  this: keying every buff by cooldownID would regress non-collided buffs,
--  whose settings must survive talent swaps (cooldownID drifts; spellID does
--  not). Collided slots trade that away -- their per-slot settings are
--  session-stable but may not follow a talent-loadout swap, which is
--  unavoidable when the two share every identity except the drifting id.
-------------------------------------------------------------------------------

--- Set of canonical spellIDs that map to 2+ distinct buff-viewer cooldownIDs.
--- Cold path (settings popup); recomputed per call from the live viewer pool.
function ns.CollidedBuffSids()
    local counts, out = {}, {}
    local entries = ns.EnumerateCDMViewerSpells and ns.EnumerateCDMViewerSpells(true) or {}
    for _, e in ipairs(entries) do
        if e.sid and type(e.cdID) == "number" then
            counts[e.sid] = (counts[e.sid] or 0) + 1
        end
    end
    for sid, n in pairs(counts) do if n > 1 then out[sid] = true end end
    return out
end

function ns.IsCollidedBuffSid(sid)
    if type(sid) ~= "number" or sid <= 0 then return false end
    return ns.CollidedBuffSids()[sid] == true
end

-- Runtime hot-path gate: true only when the current spec's buffs store holds at
-- least one "c"..cooldownID key. Cached by store-table identity, so a spec or
-- profile swap (which hands back a different store table) recomputes for free
-- without any explicit invalidation hook.
local _cdKeyGate
function ns.BuffFamHasCdKey(store)
    -- The runtime resolver already holds the buffs store; accept it to skip a
    -- second spec/profile lookup per buff-frame resolve.
    store = store or (ns.GetSpellSettingsStore and ns.GetSpellSettingsStore("buffs"))
    if not store then return false end
    if _cdKeyGate and _cdKeyGate.store == store then return _cdKeyGate.has end
    local hit = false
    for k in pairs(store) do
        if type(k) == "string" and string.byte(k, 1) == 99 then hit = true; break end  -- 'c'
    end
    _cdKeyGate = { store = store, has = hit }
    return hit
end

--- Called when a "c"..cooldownID buff entry is first persisted, so the hot-path
--- gate flips on without waiting for the store-identity cache to expire.
function ns.MarkBuffFamHasCdKey()
    local store = ns.GetSpellSettingsStore and ns.GetSpellSettingsStore("buffs")
    _cdKeyGate = { store = store, has = true }
end

--- Reorder present keys to match Blizzard viewer order while absent keys (talent
--- gaps, untalented catalog entries) keep their stored slots.
local function SyncPresentBuffOrderToBlizzard(order, present, entries)
    if not order or #order == 0 or not entries or #entries == 0 then return order end
    local blizzRank = {}
    for i, e in ipairs(entries) do
        if blizzRank[e.key] == nil then blizzRank[e.key] = i end
    end
    local sortedPresent = {}
    for _, key in ipairs(order) do
        if present[key] then sortedPresent[#sortedPresent + 1] = key end
    end
    table.sort(sortedPresent, function(a, b)
        return (blizzRank[a] or 99999) < (blizzRank[b] or 99999)
    end)
    local pi = 1
    local synced = {}
    for _, key in ipairs(order) do
        if present[key] then
            synced[#synced + 1] = sortedPresent[pi]
            pi = pi + 1
        else
            synced[#synced + 1] = key
        end
    end
    return synced
end

--- Dirty flag gating the reconcile in the hot reanchor path: the tracked
--- CATALOG (viewer pool incl. inactive + diversions) only changes on rebuilds
--- and repopulate, not when buffs merely appear/disappear -- so combat
--- reanchors skip the full enumeration/sorts. Set true wherever composition
--- can change (FullCDMRebuild wrapper, RepopulateFromBlizzard); an unreconciled
--- newcomer still renders correctly via the layoutIndex spillover fallback
--- until the next rebuild. Starts true for the login seed pass.
ns._cdmBuffOrderDirty = true

--- Keep stored buffDisplayOrder across talent/spec gaps, seed on first stable
--- pass, and insert newly-tracked buffs by Blizzard layoutIndex (not at tail).
function ns.ReconcileBuffDisplayOrder()
    if ns._cdmSpecRebuildStale then return end
    local sd = ns.GetBarSpellData("buffs")
    if not sd then return end

    local order = sd.buffDisplayOrder
    if order and type(order[1]) == "number" then
        sd.buffDisplayOrder = nil
        order = nil
    end

    local entries = ns.CollectDefaultBuffTrackEntries()
    if #entries == 0 then return end

    local present = {}
    for _, e in ipairs(entries) do
        if present[e.key] == nil then
            present[e.key] = { sid = e.sid, cdID = e.cdID, layoutIndex = e.layoutIndex or 0 }
        end
    end

    if not order or #order == 0 then
        local seeded = {}
        for _, e in ipairs(entries) do seeded[#seeded + 1] = e.key end
        sd.buffDisplayOrder = seeded
        ns._spellOrderDirty = true
        return
    end

    local newOrder, seen = {}, {}
    for _, key in ipairs(order) do
        if not seen[key] then
            seen[key] = true
            newOrder[#newOrder + 1] = key
        end
    end

    local newcomers = {}
    for _, e in ipairs(entries) do
        if not seen[e.key] then
            newcomers[#newcomers + 1] = e
        end
    end
    if #newcomers > 0 then
        table.sort(newcomers, function(a, b)
            if a.layoutIndex ~= b.layoutIndex then return a.layoutIndex < b.layoutIndex end
            return (a.key or "") < (b.key or "")
        end)
        local blizzRank = {}
        for i, e in ipairs(entries) do blizzRank[e.key] = i end
        for _, e in ipairs(newcomers) do
            local insertAt = #newOrder + 1
            for i, key in ipairs(newOrder) do
                local rank = blizzRank[key]
                if rank and rank > blizzRank[e.key] then
                    insertAt = i
                    break
                end
            end
            table.insert(newOrder, insertAt, e.key)
            seen[e.key] = true
        end
    end

    if not sd._buffDisplayOrderUserModified then
        newOrder = SyncPresentBuffOrderToBlizzard(newOrder, present, entries)
    end

    local changed = (#newOrder ~= #order)
    if not changed then
        for i = 1, #newOrder do
            if newOrder[i] ~= order[i] then changed = true; break end
        end
    end
    if changed then
        sd.buffDisplayOrder = newOrder
        ns._spellOrderDirty = true
    end
end

--- Resolve a buff bar entry's sort index from buffDisplayOrder (variant-aware).
function ns.ResolveBuffDisplaySortIndex(entry, buffOrder, isDefaultBuffs)
    if not buffOrder or not entry then return nil end
    if isDefaultBuffs then
        local cd = entry.frame and entry.frame.cooldownID
        local sid = entry.spellID
        -- Steady state: the stable key matches directly -- O(1), zero
        -- allocations. The variant scan below walks every stored key and can
        -- call GetCooldownViewerCooldownInfo (allocates) per miss, so it is
        -- reserved for genuine talent-gap frames whose cooldownID drifted.
        local stable = BuffDisplayStableKey(sid, cd)
        local direct = stable and buffOrder[stable]
        if direct then return direct end
        for key, idx in pairs(buffOrder) do
            if BuffOrderKeyMatchesEntry(key, sid, cd, entry.frame) then return idx end
        end
        return nil
    end
    local ef = entry.frame
    local canon = ef and ns.GetCanonicalSpellIDForFrame and ns.GetCanonicalSpellIDForFrame(ef)
    return (canon and buffOrder[canon])
        or (entry.spellID and buffOrder[entry.spellID])
        or (entry.baseSpellID and buffOrder[entry.baseSpellID])
end

--- Default buffs bar DISPLAY-ORDER reorder helpers.
---
--- The default "buffs" bar's assignedSpells is shared with routing + custom
--- injection (RebuildSpellRouteMap Pass 4 diverts it at highest priority), so it
--- CANNOT carry the full buff order without clobbering buffs the user diverted to
--- other bars. Instead the display order lives in a dedicated buffDisplayOrder
--- array of STABLE keys ("c"..cooldownID for Blizzard buffs, "s"..spellID for
--- customs) that only the sort + preview + drag read -- routing never touches it.
--- cooldownID is used (not the canonical spellID) because a buff's canonical id
--- flips between ability/aura form across active<->inactive.
---
--- KEY-BASED, not index-based: the stored array keeps ABSENT keys in their
--- slots (talent-gapped buffs reclaim their position on return), while the
--- preview renders only PRESENT keys -- so a preview slot index does not map
--- 1:1 onto the array whenever any gap precedes it. Callers pass the stable
--- keys of the rendered slots (pf._buffSlotKeys); positions are resolved
--- against the live array at call time.
local function BuffOrderIndexOf(t, key)
    for i = 1, #t do
        if t[i] == key then return i end
    end
    return nil
end

local function FinishBuffOrderWrite(sd)
    sd._buffDisplayOrderUserModified = true
    ns._spellOrderDirty = true
    local frame = cdmBarFrames["buffs"]
    if frame then frame._blizzCache = nil end
    if ns.QueueReanchor then ns.QueueReanchor() end
end

function ns.SwapBuffDisplayKeys(key1, key2)
    if not key1 or not key2 or key1 == key2 then return false end
    local sd = ns.GetBarSpellData("buffs")
    local t = sd and sd.buffDisplayOrder
    if not t then return false end
    local i1, i2 = BuffOrderIndexOf(t, key1), BuffOrderIndexOf(t, key2)
    if not i1 or not i2 then return false end
    t[i1], t[i2] = t[i2], t[i1]
    FinishBuffOrderWrite(sd)
    return true
end

--- Move dragKey so it renders immediately before beforeKey; nil beforeKey
--- appends after everything (drop past the last rendered slot).
function ns.MoveBuffDisplayKey(dragKey, beforeKey)
    if not dragKey or dragKey == beforeKey then return false end
    local sd = ns.GetBarSpellData("buffs")
    local t = sd and sd.buffDisplayOrder
    if not t then return false end
    local from = BuffOrderIndexOf(t, dragKey)
    if not from then return false end
    local val = table.remove(t, from)
    local to
    if beforeKey then to = BuffOrderIndexOf(t, beforeKey) end
    if not to then to = #t + 1 end
    table.insert(t, to, val)
    FinishBuffOrderWrite(sd)
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
--- trackType scopes the check to one track family: nil/"buff" = buff bars,
--- "cooldown" = cooldown-tracking bars. A bar of a different track type
--- never blocks a pick (a buff bar and a cooldown bar for the same spell
--- are distinct, legitimate picks).
function ns.SpellUsedOnAnyOtherTBB(spellID, excludeIdx, trackType)
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    if not tbb or not tbb.bars then return nil end
    for i, cfg in ipairs(tbb.bars) do
        if i ~= excludeIdx then
            if (cfg.trackType or "buff") ~= (trackType or "buff") then
                -- Different track type never blocks a pick.
            else
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

    -- Check bar type. Buff-family bars use the same cast-timer custom-buff path
    -- as custom_buff (Auras) bars: store the primary spellID + a hardcoded
    -- duration; the buff phase injects an own-frame and the buff tick drives it.
    local bd = barDataByKey[barKey]
    local isCustomBuff = bd and (bd.barType == "custom_buff" or bd.barType == "buffs")

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
    -- Negative IDs auto-move within whichever family the target bar belongs to
    -- (the sweep keys off IsBarBuffFamily, no positivity gate): trinkets stay on
    -- CD/util bars, while custom items can live on either family and sweep only
    -- their own.
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
    ns._spellOrderDirty = true

    if sd.removedSpells then sd.removedSpells[id] = nil end

    local frame = cdmBarFrames[barKey]
    if frame then frame._blizzCache = nil; frame._prevVisibleCount = nil end
    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
    if ns.QueueReanchor then ns.QueueReanchor() end
    return true
end

--- Place a BUFF on a CD/utility bar. The buff is HOSTED: RebuildSpellRouteMap
--- diverts its real Blizzard buff-viewer frame onto this bar, and the reanchor
--- reparents that frame into the bar's layout when active / a placeholder when
--- inactive -- exactly how the buffs bar works, just on a CD/util bar. Blizzard's
--- CDM stays the source of truth (icon, duration, stacks, active state), so real
--- auras, DoTs, totems and pet-summons all work with no detection code and get
--- the normal buff per-icon settings. It is NOT a custom injected spell -- Phase 3
--- must never draw its own frame for it. Additive: only our own data table is
--- written (variant-keyed so any live form of the spell resolves).
function ns.AddBuffToCDUtilBar(barKey, spellID)
    if type(spellID) ~= "number" or spellID <= 0 then return false end
    local sd = ns.GetBarSpellData(barKey)
    if not sd then return false end
    -- Already hosted here (marker entry, or a legacy plain entry from before
    -- the marker model): idempotent no-op.
    if sd.hostedBuffSpellIDs and sd.hostedBuffSpellIDs[spellID] and sd.assignedSpells
       and (ns.ListHasHostedMarker(sd.assignedSpells, spellID)
            or ns.FindVariantIndexInList(sd.assignedSpells, spellID)) then
        return true
    end
    -- Claim the slot via the hosted MARKER, never the plain spellID: the plain
    -- id is the COOLDOWN form's identity, and one spell can be both a cooldown
    -- and a buff (same id). The marker gives the hosted buff its own slot, so
    -- the two coexist on one bar and add/remove/reorder independently.
    -- AddTrackedSpell also auto-moves the marker off any other CD/util bar.
    ns.AddTrackedSpell(barKey, ns.HostedBuffMarker(spellID))
    -- Flag keyed by the picked/canonical spellID, so the route-map pass, the
    -- drop-pass keep test, and the self-heal all match it directly. The route
    -- map itself expands variants when it writes the diversion, so the LIVE
    -- frame still resolves regardless of its talent/override form.
    if not sd.hostedBuffSpellIDs then sd.hostedBuffSpellIDs = {} end
    sd.hostedBuffSpellIDs[spellID] = true
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
    ns._spellOrderDirty = true

    -- Hosted-buff removal? Either the entry is a MARKER, or it is a legacy
    -- plain entry that represents the buff (flag set, no marker anywhere in
    -- the list). A plain entry WITH a marker present is the same spell's
    -- COOLDOWN slot -- the hosted buff stays.
    local hostedSid = removedID and ns.HostedBuffMarkerToSpell(removedID)
    if not hostedSid and removedID and removedID > 0
       and sd.hostedBuffSpellIDs and sd.hostedBuffSpellIDs[removedID]
       and not ns.ListHasHostedMarker(list, removedID) then
        hostedSid = removedID
    end
    if hostedSid then
        -- Un-host: clear the flag so the route map stops diverting the buff
        -- here (it returns to the buffs bar). Never ghost-route a hosted
        -- buff -- the ghost bar hides by spellID, so it would also hide the
        -- spell's COOLDOWN form everywhere.
        if sd.hostedBuffSpellIDs then sd.hostedBuffSpellIDs[hostedSid] = nil end
    else
        -- Auxiliary metadata cleanup (kept here so the wrapper exposes the
        -- same side effects RemoveSpellFromBar does for symmetry with
        -- index-based removal).
        if removedID and sd.customSpellDurations then sd.customSpellDurations[removedID] = nil end
        if removedID and sd.spellDurations       then sd.spellDurations[removedID]       = nil end
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
            -- Max Icons overflow: clear targets that pointed at the removed
            -- bar (runtime already fail-safes on a dangling key; this is
            -- config hygiene on the explicit delete).
            for _, b in ipairs(p.cdmBars.bars) do
                if b.overflowTarget == key then b.overflowTarget = nil end
            end
            -- Bar deletion shifts every later bar's array index: captured
            -- override paths into cdmBars.bars would now point at the WRONG
            -- bars. Drop them all (users re-capture) -- honest beats corrupt.
            if EllesmereUI.SpecOverrides_OnCDMBarsRestructured then
                EllesmereUI.SpecOverrides_OnCDMBarsRestructured()
            end

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

