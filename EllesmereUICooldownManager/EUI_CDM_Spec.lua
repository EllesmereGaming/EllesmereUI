if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_Spec.lua
--
--  Spec key cache, spell id resolvers, the available spell pool, spec change
--  handling and the bar roots.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- The main file or an earlier CDM file failed to load.
if not I or I.broken then return end
I.broken = true

local GetTime = GetTime

local ECME, SpellStore = I.ECME, I.SpellStore

-------------------------------------------------------------------------------
--  Spec helpers
--
--  Single source of truth: the live game API, cached on first read. Never nil during
--  normal operation -- transitions atomically old->new key inside ProcessSpecChange.
--  InvalidateSpecKey is for the early-login wakeFrame ONLY (before CDM setup completes),
--  never during spec change processing.
--
--  Returns nil when the spec API isn't ready (very early login); consumers MUST bail on nil rather than fall back to a stored value, so CDM never builds with a wrong/guessed spec.
-------------------------------------------------------------------------------
local _cachedSpecKey = nil

function ns.GetActiveSpecKey()
    if _cachedSpecKey then return _cachedSpecKey end
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex or specIndex == 0 then return nil end
    local specID = select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    if not specID or specID == 0 then return nil end
    _cachedSpecKey = tostring(specID)
    return _cachedSpecKey
end

-- Early-login wakeFrame use only (before CDM setup completes); never called during spec change processing.
function ns.InvalidateSpecKey()
    _cachedSpecKey = nil
    ns._cachedSpecProfiles = nil
    ns._cdmStoreMemo = nil
end

-- Live spec key from the game API without touching the cache; nil if not ready.
local function ComputeLiveSpecKey()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not specIndex or specIndex == 0 then return nil end
    local specID = select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
    if not specID or specID == 0 then return nil end
    return tostring(specID)
end
ns.ComputeLiveSpecKey = ComputeLiveSpecKey

if EllesmereUI.IS_FOREVER then
    -- WoW Forever reports one spec per class. The store key is the Forever
    -- spec's own key if the ACTIVE profile's store holds it (the layout the
    -- client has been showing), else the first retail spec of the class with
    -- a bucket, else the class's first retail spec. Resolved once per store
    -- table: an edit inside a profile never moves the key; a profile switch or
    -- import (a new store table) re-resolves it before the rebuild reads
    -- anything. SPELLS_CHANGED compares against this same memo, so it can
    -- never mistake a data edit for a spec swap. Memo inputs: the store root
    -- and the raw live spec ID. The active key also records the store root it
    -- was resolved for (ns._fvSpecKeyRoot), so a key resolved against one
    -- profile's store is never served against another's.
    ComputeLiveSpecKey = function()
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if not specIndex or specIndex == 0 then return nil end
        local specID = select(1, C_SpecializationInfo.GetSpecializationInfo(specIndex))
        if not specID or specID == 0 then return nil end
        local sp = ns.GetActiveSpecProfiles()
        local m = ns._fvSpecKeyMemo
        if m and m.root == sp and m.raw == specID then return m.key end
        local key = tostring(EllesmereUI.SpecFor(specID, EllesmereUI.SpecHasStringEntry, sp))
        ns._fvSpecKeyMemo = { root = sp, raw = specID, key = key }
        return key
    end
    ns.ComputeLiveSpecKey = ComputeLiveSpecKey
    function ns.GetActiveSpecKey()
        if _cachedSpecKey and ns._fvSpecKeyRoot == ns.GetActiveSpecProfiles() then return _cachedSpecKey end
        local key = ComputeLiveSpecKey()
        if not key then return nil end
        _cachedSpecKey = key
        ns._fvSpecKeyRoot = ns.GetActiveSpecProfiles()
        return key
    end
end

-- Per-character identifier for legacy callers; no longer used for spec storage.
function ns.GetCharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    return name .. "-" .. realm
end

local function EnsureSpec(profile, key)
    profile.spec[key] = profile.spec[key] or { mappings = {}, selectedMapping = 1 }
    return profile.spec[key]
end

local function GetStore()
    local p = ECME.db.profile
    local specKey = ns.GetActiveSpecKey()
    return EnsureSpec(p, specKey)
end

local function EnsureMappings(store)
    if not store.mappings then store.mappings = {} end
    if #store.mappings == 0 then
        store.mappings[1] = {
            enabled = false, name = ns.DEFAULT_MAPPING_NAME,
            actionBar = 1, actionButton = 1, cdmSlot = 1,
            hideFromCDM = false, mode = "ACTIVE",
            glowStyle = 1, glowColor = { r = 1, g = 0.82, b = 0.1 },
        }
    end
    store.selectedMapping = tonumber(store.selectedMapping) or 1
    if store.selectedMapping < 1 then store.selectedMapping = 1 end
    if store.selectedMapping > #store.mappings then store.selectedMapping = #store.mappings end
    for _, m in ipairs(store.mappings) do
        if m.enabled == nil then m.enabled = true end
        if m.hideFromCDM == nil then m.hideFromCDM = false end
        if m.mode ~= "MISSING" then m.mode = "ACTIVE" end
        m.glowStyle = tonumber(m.glowStyle) or 1
        if not m.glowColor then m.glowColor = { r = 1, g = 0.82, b = 0.1 } end
        m.name = tostring(m.name or "")
        if type(m.actionBar) ~= "string" or not ns.CDM_BAR_ROOTS[m.actionBar] then
            m.actionBar = tonumber(m.actionBar) or 1
        end
        m.actionButton = tonumber(m.actionButton) or 1
        m.cdmSlot = tonumber(m.cdmSlot) or 1
    end
end

-- Expose for options
ns.GetStore = GetStore
ns.EnsureMappings = EnsureMappings

-------------------------------------------------------------------------------
--  Per-Spec Profile Helpers
--  Saves/restores spell lists, bar glows, and buff bars per specialization.
--  Bar structure, settings, and positions are shared across all specs.
-------------------------------------------------------------------------------
local MAIN_BAR_KEYS = { cooldowns = true, utility = true, buffs = true }

-- Ghost CD bar: hidden routing sink for CD/utility spells. "Removing" a spell routes it
-- here instead of deleting it, so every spell in Blizzard's viewer pool always has a route -- no allowSet filtering needed during collection.
local GHOST_CD_BAR_KEY = "__ghost_cd"
MAIN_BAR_KEYS[GHOST_CD_BAR_KEY] = true

-------------------------------------------------------------------------------
--  Resolve the best spellID from a CooldownViewerCooldownInfo struct.
--  Priority: overrideSpellID > first linkedSpellID > spellID. The base spellID field
--  can be a spec aura (e.g. 137007 "Unholy Death Knight") while the real tracked spell lives in linkedSpellIDs.
-------------------------------------------------------------------------------
local function ResolveInfoSpellID(info)
    if not info then return nil end
    local sid
    if info.overrideSpellID and info.overrideSpellID > 0 then
        sid = info.overrideSpellID
    else
        local linked = info.linkedSpellIDs
        if linked then
            for i = 1, #linked do
                if linked[i] and linked[i] > 0 then sid = linked[i]; break end
            end
        end
        if not sid and info.spellID and info.spellID > 0 then sid = info.spellID end
    end
    return sid
end

-------------------------------------------------------------------------------
--  Resolve the best spellID from a Blizzard CDM viewer child frame. For buff bars
--  cooldownInfo often holds the wrong spellID (spec aura, not the tracked buff); the
--  child frame knows the correct one via GetAuraSpellID/GetSpellID at runtime. Falls back
--  to ResolveInfoSpellID when those are unavailable. ONLY used in out-of-combat paths (snapshot, dropdown, reconcile).
-------------------------------------------------------------------------------
local function ResolveChildSpellID(child)
    if not child then return nil end
    -- Prefer the aura spellID (most accurate for buff viewers). Comparisons are pcall-wrapped:
    -- these methods can return SECRET numbers in combat, which cannot be compared with > 0.
    if child.GetAuraSpellID then
        local ok, auraID = pcall(child.GetAuraSpellID, child)
        if ok and auraID then
            local cmpOk, gt = pcall(function() return auraID > 0 end)
            if cmpOk and gt then return auraID end
        end
    end
    if child.GetSpellID then
        local ok, fid = pcall(child.GetSpellID, child)
        if ok and fid then
            local cmpOk, gt = pcall(function() return fid > 0 end)
            if cmpOk and gt then return fid end
        end
    end
    local cdID = child.cooldownID or (child.cooldownInfo and child.cooldownInfo.cooldownID)
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
        return ResolveInfoSpellID(info)
    end
    return nil
end

-------------------------------------------------------------------------------
--  Set of currently known (learned) spellIDs across all CDM categories, via
--  GetCooldownViewerCategorySet(cat, false) (learned only), resolving each cdID to its base spellID.
-------------------------------------------------------------------------------
local function BuildAvailableSpellPool()
    local known = {}
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then return known end
    for cat = 0, 3 do
        local knownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, false)
        if knownIDs then
            for _, cdID in ipairs(knownIDs) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info then
                    local primarySid = ResolveInfoSpellID(info)
                    -- Store ALL related spell IDs so reconcile matches whether the bar stores
                    -- the base, override or a linked ID. Guard override-sourced IDs with
                    -- IsPlayerSpell: CDM info can report a stale overrideSpellID after the talent providing it is removed (e.g. Cleave/Whirlwind).
                    local staleOverride = info.overrideSpellID
                        and info.overrideSpellID > 0
                        and IsPlayerSpell
                        and not IsPlayerSpell(info.overrideSpellID)
                    if primarySid and primarySid > 0 then
                        if not (staleOverride and primarySid == info.overrideSpellID) then
                            known[primarySid] = true
                        end
                    end
                    if info.spellID and info.spellID > 0 then
                        known[info.spellID] = true
                    end
                    if info.overrideSpellID and info.overrideSpellID > 0
                       and not staleOverride then
                        known[info.overrideSpellID] = true
                    end
                    if info.linkedSpellIDs then
                        for _, lsid in ipairs(info.linkedSpellIDs) do
                            if lsid and lsid > 0 then
                                known[lsid] = true
                            end
                        end
                    end
                end
            end
        end
    end
    -- Fallback: the full CDM category set (cat, true) covers ALL class spells regardless of
    -- talents. Anything in it that passes IsPlayerSpell is known even if the viewer hasn't updated yet after a talent swap.
    local _IsPlayerSpell = IsPlayerSpell
    if _IsPlayerSpell then
        for cat = 0, 3 do
            local allIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
            if allIDs then
                for _, cdID in ipairs(allIDs) do
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                    if info then
                        local sid = ResolveInfoSpellID(info)
                        if sid and sid > 0 and not known[sid] and _IsPlayerSpell(sid) then
                            known[sid] = true
                        end
                        if info.spellID and info.spellID > 0 and not known[info.spellID] and _IsPlayerSpell(info.spellID) then
                            known[info.spellID] = true
                        end
                        if info.overrideSpellID and info.overrideSpellID > 0 and not known[info.overrideSpellID] and _IsPlayerSpell(info.overrideSpellID) then
                            known[info.overrideSpellID] = true
                        end
                    end
                end
            end
        end
    end
    return known
end

local DeepCopy = EllesmereUI.Lite.DeepCopy

-------------------------------------------------------------------------------
--  Cached bar sizes -- cosmetic hint for pre-sizing frames on login so anchored
--  elements don't jump. Zero impact on spell logic or icons. Stored at
--  EllesmereUIDB.cdmCachedBarSizes[charKey][specKey][barKey] = count
-------------------------------------------------------------------------------
function ns.SaveCachedBarSizes()
    if not EllesmereUIDB then return end
    local charKey = ns.GetCharKey()
    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end
    if not EllesmereUIDB.cdmCachedBarSizes then EllesmereUIDB.cdmCachedBarSizes = {} end
    if not EllesmereUIDB.cdmCachedBarSizes[charKey] then EllesmereUIDB.cdmCachedBarSizes[charKey] = {} end
    local frames = ns.cdmBarFrames
    local iconsByKey = ns.cdmBarIcons
    if not frames or not iconsByKey then return end
    local counts = {}
    for key, frame in pairs(frames) do
        local icons = iconsByKey[key]
        if icons then
            local vis = 0
            for _, icon in ipairs(icons) do
                if icon:IsShown() then vis = vis + 1 end
            end
            if vis > 0 then counts[key] = vis end
        end
    end
    EllesmereUIDB.cdmCachedBarSizes[charKey][specKey] = counts
end

--- Save the current spec's non-spell per-spec data. Spell data lives directly in the global store via ns.GetBarSpellData() and never needs copying.
local function SaveCurrentSpecProfile()
    local p = ECME.db.profile
    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return end
    local specProfiles = SpellStore.GetSpecProfiles()
    if not specProfiles[specKey] then specProfiles[specKey] = { barSpells = {} } end
    local prof = specProfiles[specKey]

    -- Bar Glows and Tracked Buff Bars live in specProfiles[specKey]; GetBarGlows()/GetTrackedBuffBars() read/write there directly, so nothing extra to copy here.

    -- Snapshot visible icon counts for pre-sizing on next login
    ns.SaveCachedBarSizes()
end

--- Spec change processing. NEVER a fixed wall-clock delay: Blizzard's viewer pools repopulate
--- at unpredictable times after a spec swap. SPELLS_CHANGED is the sole trigger -- fires for
--- manual and LFG auto-swaps and guarantees spell data/viewer pools are fully populated.
--- CheckSpecChange compares the live spec key to the cached one on every SPELLS_CHANGED and runs
--- a full talent_reconcile rebuild on a difference. The cached key swaps atomically BEFORE the rebuild so GetBarSpellData always has a valid key. No nil window.
local function ProcessSpecChange(newSpecKey)
    if not newSpecKey then return end
    ns._spellOrderDirty = true  -- force spell order cache rebuild

    -- Atomic swap: write the new key BEFORE rebuilding so every GetBarSpellData call during the rebuild reads the correct spec.
    _cachedSpecKey = newSpecKey
    ns._cachedSpecProfiles = nil
    ns._cdmStoreMemo = nil

    -- Suppress the _ECME_Apply rebuild the profile system fires via RefreshAllAddons: the talent_reconcile rebuild below is strictly stronger.
    ns._specChangeJustRan = true
    -- Time-box stamp for the justRan consume in _ECME_Apply: suppression is honored only while
    -- the spec change is recent, so a flag left armed by a non-consuming path fails OPEN (extra rebuild) instead of eating a needed one.
    ns._specChangeAt = GetTime()

    ns._pendingApplyOnReanchor = true

    -- Full wipe + rebuild: talent_reconcile takes FullCDMRebuild's isFullWipe branch (wipes
    -- icon arrays, _prevIconRefs/_prevVisibleCount, anchor state in _hookFrameData, all FC
    -- caches on viewer pool frames, then a direct synchronous CollectAndReanchor); cdmBarIcons
    -- holds the new spec's icons after this returns. Placeholder injection is HELD across the
    -- synchronous pass: on a spec switch it runs BEFORE the per-spec profile swap, so
    -- barDataByKey still carries the OLD spec's Always-Show/Keep-in-Place flags and injecting
    -- would flash placeholders the new spec never asked for. The following reanchor (profile_import, or the next buff event) re-injects correctly from the active profile.
    if ns.FullCDMRebuild then
        ns._cdmSpecRebuildStale = true
        ns.FullCDMRebuild("talent_reconcile")
        ns._cdmSpecRebuildStale = false
    end

    -- Signal the profile system that CDM's spec rebuild is complete: clears _specProfileSwitching and re-applies width/height matches.
    EllesmereUI.OnSpecSwitchComplete()

    -- Refresh the CDM options pages now that _cachedSpecKey is swapped: their own
    -- PLAYER_SPECIALIZATION_CHANGED watcher can fire before SPELLS_CHANGED, so driving it
    -- here guarantees they rebuild against the new spec instead of keeping the old spec's selected bar.
    if ns.OnTBBSpecChanged then ns.OnTBBSpecChanged() end
end
ns.ProcessSpecChange = ProcessSpecChange

-- Compare live spec to cached; if different, process the change. Called exclusively from
-- SPELLS_CHANGED. Idempotent: after ProcessSpecChange the cached key matches live and subsequent calls are no-ops.
local function CheckSpecChange()
    local liveKey = ComputeLiveSpecKey()
    if liveKey and liveKey ~= _cachedSpecKey then
        ProcessSpecChange(liveKey)
    end
end
ns.CheckSpecChange = CheckSpecChange

-------------------------------------------------------------------------------
--  CDM Bar Roots
-------------------------------------------------------------------------------
ns.CDM_BAR_ROOTS = {
    CDM_COOLDOWN = "EssentialCooldownViewer",
    CDM_UTILITY  = "UtilityCooldownViewer",
}

I.BuildAvailableSpellPool, I.CheckSpecChange = BuildAvailableSpellPool, CheckSpecChange
I.ComputeLiveSpecKey, I.EnsureMappings = ComputeLiveSpecKey, EnsureMappings
I.GetStore, I.GHOST_CD_BAR_KEY, I.MAIN_BAR_KEYS = GetStore, GHOST_CD_BAR_KEY, MAIN_BAR_KEYS
I.ResolveChildSpellID, I.ResolveInfoSpellID = ResolveChildSpellID, ResolveInfoSpellID
I.SaveCurrentSpecProfile = SaveCurrentSpecProfile
I.GetCachedSpecKey = function() return _cachedSpecKey end
I.broken = false
