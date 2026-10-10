if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_Store.lua
--
--  The spell assignment store (EllesmereUIDB.spellAssignments), the per-spell
--  stores, markers and the cooldown claim set.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- The main file or an earlier CDM file failed to load.
if not I or I.broken then return end
I.broken = true

local ECME = I.ECME

-------------------------------------------------------------------------------
--  Dedicated spell assignment store helpers
--  Lives at EllesmereUIDB.spellAssignments; spell/bar data is per-profile at
--  spellAssignments.profiles[name].specProfiles[specKey]. Top-level (not inside
--  the profile blob) so it never travels with profile export/module sync, but
--  IS forked/dropped/renamed with the profile (EllesmereUI_Profiles.lua). Active
--  bucket resolves live via ns.GetActiveSpecProfiles(). One local table (Lua 5.1's 200-local cap).
-------------------------------------------------------------------------------
local SpellStore = {}

function SpellStore.Get()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.spellAssignments then
        EllesmereUIDB.spellAssignments = { profiles = {} }
    end
    return EllesmereUIDB.spellAssignments
end

-- Active profile name for the per-profile spell store; read live so a profile switch auto-follows the next CDM rebuild, no repoint step.
function ns.GetActiveProfileName()
    return (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
end

-- Per-profile spell store: copying a profile forks its CDM; deleting a bar never crosses
-- profiles. Until the seeding migration (cdm_per_profile_spell_store_v1) completes (_perProfileSeeded),
-- fork the legacy shared spellAssignments.specProfiles on first access so a profile never reads empty mid-migration.
function ns.GetSpecProfilesForProfile(profileName)
    local sa = SpellStore.Get()
    if not sa.profiles then sa.profiles = {} end
    local bucket = sa.profiles[profileName]
    if not bucket then
        bucket = { specProfiles = {} }
        if not sa._perProfileSeeded and type(sa.specProfiles) == "table" and next(sa.specProfiles) then
            local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy
            if DeepCopy then bucket.specProfiles = DeepCopy(sa.specProfiles) end
        end
        sa.profiles[profileName] = bucket
    end
    if not bucket.specProfiles then bucket.specProfiles = {} end
    return bucket.specProfiles
end

-- Cross-spec broadcast set for Tracking Bars: bar identities (preset key/custom spellID)
-- pushed to every spec via "Add Bar to All Specs". Lives on the profile bucket OUTSIDE
-- specProfiles (survives spec switches/reloads, forks with profile); drives the Add/Remove toggle label.
function ns.GetActiveTBBBroadcastSet()
    local name = ns.GetActiveProfileName()
    -- Ensure the bucket exists (with legacy seeding) via the canonical accessor.
    ns.GetSpecProfilesForProfile(name)
    local sa = SpellStore.Get()
    local bucket = sa.profiles and sa.profiles[name]
    if not bucket then return {} end
    if not bucket.tbbBroadcast then bucket.tbbBroadcast = {} end
    return bucket.tbbBroadcast
end

-- Smooth-fill switches for Tracking Bars (Bar Layout > Smooth Bars). ONE setting for ALL
-- bars in EVERY spec: profile bucket OUTSIDE specProfiles (same home as the broadcast set).
-- Keys buffs/cooldowns; absent buffs reads ENABLED, absent cooldowns reads DISABLED (defaults).
function ns.GetTBBSmoothSettings()
    local name = ns.GetActiveProfileName()
    ns.GetSpecProfilesForProfile(name)
    local sa = SpellStore.Get()
    local bucket = sa.profiles and sa.profiles[name]
    if not bucket then return nil end
    if not bucket.tbbSmooth then bucket.tbbSmooth = {} end
    return bucket.tbbSmooth
end

-- Active SPELL LAYOUT name. Layouts are an account-wide library (spellAssignments.profiles[name])
-- with a SINGLE account-wide active pointer (spellAssignments.activeLayout), DETACHED from EUI
-- profiles: a profile only changes the active layout via an opt-in binding
-- (spellAssignments.profileBindings) applied by ns.ApplyProfileBinding on profile load. Self-heals to a valid layout.
function ns.GetActiveLayoutName()
    local sa = SpellStore.Get()
    if not sa.profiles then sa.profiles = {} end
    local name = sa.activeLayout
    if type(name) ~= "string" or type(sa.profiles[name]) ~= "table" then
        -- Self-heal: prefer a layout named after the current profile, else any existing layout, else the profile name (creates it).
        local cur = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
        name = nil
        if type(sa.profiles[cur]) == "table" then
            name = cur
        else
            for n, v in pairs(sa.profiles) do
                if type(v) == "table" then name = n; break end
            end
        end
        name = name or cur
        sa.activeLayout = name
    end
    return name
end

-- specProfiles for the active PROFILE (the live CDM bucket): spell content is per-EUI-profile,
-- no account-wide layout pointer mediates rendering. Combat-hot and CACHED (re-deriving cost
-- ~20ms/min of combat CPU): invalidated by the spec-key cache lifecycle (ProcessSpecChange /
-- InvalidateSpecKey) plus BuildAllCDMBars' head as belt -- every profile apply, import, layout
-- switch and options rebuild passes through one of those.
function ns.GetActiveSpecProfiles()
    local sp = ns._cachedSpecProfiles
    if sp then return sp end
    sp = ns.GetSpecProfilesForProfile(ns.GetActiveProfileName())
    ns._cachedSpecProfiles = sp
    return sp
end

function SpellStore.GetSpecProfiles()
    return ns.GetActiveSpecProfiles()
end

-- (SpellStore.GetBarGlows removed -- Bar Glows disabled pending rewrite)

-------------------------------------------------------------------------------
--  Direct spell data accessor (single source of truth)
--  Returns the spell table for a bar key under the current spec, creating
--  it if needed. All spell reads/writes go through this -- no copies.
-------------------------------------------------------------------------------
-- Reference memo for combat-hot store fetches (this + the per-spell settings stores below).
-- LIVE validity: records the specProfiles ROOT table + specKey, re-checked every call, so
-- profile applies/imports/spec swaps (which change one of those two) can't be missed. Cached
-- values are TABLE REFERENCES (options edits stay visible); nil is never cached (self-heals
-- next call). Belt: BuildAllCDMBars' head drops the memo for structural ops (delete/reset) that replace an inner table.
function ns.GetBarSpellData(barKey)
    local specKey = ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return nil end
    local sp = SpellStore.GetSpecProfiles()
    local memo = ns._cdmStoreMemo
    if memo and memo.root == sp and memo.spec == specKey then
        local hit = memo.sd[barKey]
        if hit then return hit end
    else
        memo = { root = sp, spec = specKey, sd = {} }
        ns._cdmStoreMemo = memo
    end
    local prof = sp[specKey]
    if not prof then
        prof = { barSpells = {} }
        sp[specKey] = prof
    end
    if not prof.barSpells then prof.barSpells = {} end
    local bs = prof.barSpells[barKey]
    if not bs then
        bs = {}
        prof.barSpells[barKey] = bs
    end
    memo.sd[barKey] = bs
    return bs
end

-------------------------------------------------------------------------------
--  Tiered per-spell settings stores
--
--  Per-spell icon settings live in FAMILY stores on the spec profile (siblings of
--  barSpells), keyed by spellID -- NOT nested under a bar, so moving a spell within
--  its family keeps its settings:
--      specProf.spellSettingsCD[sid]   -- cooldown/utility family
--      specProf.spellSettingsBuff[sid] -- buff family
--  Bar-level tiers below the per-spell entries ("Apply to Bar"):
--      barSpells[barKey].barSettings   -- this bar, this spec
--      bd.barSpellSettings             -- this bar, EVERY spec (profile-level bar
--                                         def; specs with no CDM data yet inherit it)
--  Effective value per key: spell entry > barSettings > barSpellSettings > defaults,
--  via metatable __index links ResolveSpellSettings re-asserts lazily on every lookup
--  (self-heals across moves/spec swaps/profile swaps; metatables never serialize).
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Hosted-buff markers
--
--  A buff placed on a CD/utility bar ("hosted") gets its own assignedSpells entry,
--  encoded as a negative marker so it never collides with the same spell's cooldown
--  entry (one spellID can be in BOTH the Essential/Utility and Tracked Buffs catalogs,
--  e.g. Divine Shield 642). The marker is an independent slot -- own position,
--  remove/move, per-icon settings -- even when the cooldown form is on the same bar.
--
--  Encoding: -(BASE + spellID). BASE sits far below the item-preset range (<= -100,
--  negated itemIDs) and the trinket slots (-13/-14), so existing negative-id branches
--  keep working; anything <= -BASE is a marker.
-------------------------------------------------------------------------------
ns.HOSTED_BUFF_MARKER_BASE = 2000000000

-------------------------------------------------------------------------------
--  Equipment-slot entries: a bar entry can store a negated INVENTORY SLOT id (-1..-19)
--  to track whatever item is equipped there; trinket slots (-13/-14) and user-added slots
--  (belt -6, cloak -15, ...) share the same frame/update machinery. Range is safe: item
--  presets are <= -100 and the custom-item popup rejects IDs below 100, so nothing else
--  occupies -1..-19. INV_SLOT_NAMES is keyed by slot id; slot 18 (obsolete ranged) is
--  deliberately absent -- SlotIDFromKey treats absence as "not a slot".
-------------------------------------------------------------------------------
ns.INV_SLOT_NAMES = {
    [1] = HEADSLOT,   [2] = NECKSLOT,      [3] = SHOULDERSLOT, [4] = SHIRTSLOT,
    [5] = CHESTSLOT,  [6] = WAISTSLOT,     [7] = LEGSSLOT,     [8] = FEETSLOT,
    [9] = WRISTSLOT,  [10] = HANDSSLOT,    [11] = FINGER0SLOT, [12] = FINGER1SLOT,
    [13] = TRINKET0SLOT, [14] = TRINKET1SLOT, [15] = BACKSLOT,
    [16] = MAINHANDSLOT, [17] = SECONDARYHANDSLOT, [19] = TABARDSLOT,
}

-- Decode an equipment-slot entry to its inventory slot id; nil for anything else.
function ns.SlotIDFromKey(key)
    if type(key) == "number" and key < 0 and ns.INV_SLOT_NAMES[-key] then
        return -key
    end
    return nil
end

function ns.HostedBuffMarker(spellID)
    return -(ns.HOSTED_BUFF_MARKER_BASE + spellID)
end

-- Decode a hosted-buff marker to its spellID; nil otherwise. Bounded by CD_CLAIM_MARKER_BASE so a cd-claim marker never misdecodes as a spellID.
function ns.HostedBuffMarkerToSpell(id)
    if type(id) == "number" and id <= -ns.HOSTED_BUFF_MARKER_BASE
       and id > -ns.CD_CLAIM_MARKER_BASE then
        return -id - ns.HOSTED_BUFF_MARKER_BASE
    end
    return nil
end

-- True when the list already holds the hosted marker for spellID.
function ns.ListHasHostedMarker(list, spellID)
    if not list then return false end
    local marker = -(ns.HOSTED_BUFF_MARKER_BASE + spellID)
    for i = 1, #list do
        if list[i] == marker then return true end
    end
    return false
end

-------------------------------------------------------------------------------
--  Empty Slot markers: a purely decorative placeholder (no spell/item behind
--  it) that reserves a grid position on a CD/utility bar. Unlike every other
--  marker kind, there is no natural id to encode -- each Add mints a fresh one
--  so every instance is globally unique and AddTrackedSpell/RemoveTrackedSpell/
--  ReplaceTrackedSpell (dedup, cross-bar sweep, index-based remove/reorder) all
--  handle it with zero special-casing, same as any other tracked entry.
--
--  Encoding: -(EMPTY_SLOT_MARKER_BASE + seq). BASE sits above the item-preset
--  range (<= -100, real itemIDs never approach it) and below
--  HOSTED_BUFF_MARKER_BASE, so it can never collide with either.
--
--  seq is derived from the data itself (highest existing seq across every
--  spec's bars and saved slot settings, +1) rather than a saved counter: the
--  markers live in the per-spec spell store (SpellStore), but a counter lives in a
--  DIFFERENT table -- an import/sync can bring in markers the counter never
--  saw, so a freshly minted one could collide with an already-saved marker
--  (the Add then either no-ops as a "duplicate" or steals the slot from
--  whichever bar already held that id). Scanning is collision-proof by
--  construction and only runs on an explicit Add (cold path).
-------------------------------------------------------------------------------
ns.EMPTY_SLOT_MARKER_BASE = 1000000000

function ns.NewEmptySlotMarker()
    local maxSeq = 0
    local sp = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if sp then
        for _, prof in pairs(sp) do
            -- Removed slots can leave saved conditions behind; never reuse their id.
            local settings = prof and prof.spellSettingsCD
            if settings then
                for id in pairs(settings) do
                    if ns.IsEmptySlotMarker(id) then
                        local seq = -id - ns.EMPTY_SLOT_MARKER_BASE
                        if seq > maxSeq then maxSeq = seq end
                    end
                end
            end
            local barSpells = prof and prof.barSpells
            if barSpells then
                for _, bs in pairs(barSpells) do
                    local assigned = bs and bs.assignedSpells
                    if assigned then
                        for _, id in ipairs(assigned) do
                            if ns.IsEmptySlotMarker(id) then
                                local seq = -id - ns.EMPTY_SLOT_MARKER_BASE
                                if seq > maxSeq then maxSeq = seq end
                            end
                        end
                    end
                end
            end
        end
    end
    return -(ns.EMPTY_SLOT_MARKER_BASE + maxSeq + 1)
end

-- True for any Empty Slot marker; bounded above HOSTED_BUFF_MARKER_BASE so it never misreads a hosted-buff marker.
function ns.IsEmptySlotMarker(id)
    return type(id) == "number" and id <= -ns.EMPTY_SLOT_MARKER_BASE
        and id > -ns.HOSTED_BUFF_MARKER_BASE
end

-------------------------------------------------------------------------------
--  Cd-claim markers: a collided buff (two Blizzard buff-viewer slots sharing one canonical
--  spellID, e.g. Diabolist Demonic Art vs Diabolic Ritual) can't be told apart by spellID, so
--  a claimed slot is tracked by its cooldownID instead, using the same marker-in-assignedSpells
--  pattern as hosted-buff markers (add/remove/drag/reorder reuse the existing machinery).
--
--  Encoding: -(BASE + cooldownID). BASE sits beyond HOSTED_BUFF_MARKER_BASE (+ max plausible
--  spellID), so every hosted-buff-marker check (bounded at HOSTED_BUFF_MARKER_BASE) already excludes cd-claim markers.
-------------------------------------------------------------------------------
ns.CD_CLAIM_MARKER_BASE = 3000000000

function ns.CdClaimMarker(cdID)
    return -(ns.CD_CLAIM_MARKER_BASE + cdID)
end

-- Decode a cd-claim marker to its cooldownID; nil for anything else.
function ns.CdClaimMarkerToCdID(id)
    if type(id) == "number" and id <= -ns.CD_CLAIM_MARKER_BASE then
        return -id - ns.CD_CLAIM_MARKER_BASE
    end
    return nil
end

-- Every cd-claim marker in a bar's assignedSpells as a set ({[cdID]=true,...}), or nil if none.
function ns.CollectCdClaimSet(sd)
    if not sd or not sd.assignedSpells then return nil end
    local set
    for _, id in ipairs(sd.assignedSpells) do
        local cd = ns.CdClaimMarkerToCdID(id)
        if cd then
            set = set or {}
            set[cd] = true
        end
    end
    return set
end

-- Family store key for a bar ("spellSettingsBuff" for buff-family bars, "spellSettingsCD" for everything else, including the ghost CD bar).
function ns.SettingsFamilyKey(barKeyOrBd)
    if ns.IsBarBuffFamily and ns.IsBarBuffFamily(barKeyOrBd) then
        return "spellSettingsBuff"
    end
    return "spellSettingsCD"
end

-- Family per-spell store for an explicit spec profile table.
function ns.GetSpellSettingsStoreForProf(prof, famKey, create)
    if not prof then return nil end
    local st = prof[famKey]
    if not st and create then st = {}; prof[famKey] = st end
    return st
end

-- Family per-spell store for the ACTIVE spec, resolved from a bar. Same live-validity
-- reference memo as GetBarSpellData: keyed by family under the shared memo, nil never
-- cached, and create=true refreshes the entry so a first-write store is immediately visible to readers.
function ns.GetSpellSettingsStore(barKeyOrBd, create)
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return nil end
    local sp = SpellStore.GetSpecProfiles()
    if not sp then return nil end
    local famKey = ns.SettingsFamilyKey(barKeyOrBd)
    local memo = ns._cdmStoreMemo
    if memo and memo.root == sp and memo.spec == specKey then
        if not create then
            local hit = memo[famKey]
            if hit then return hit end
        end
    else
        memo = { root = sp, spec = specKey, sd = {} }
        ns._cdmStoreMemo = memo
    end
    local prof = sp[specKey]
    if not prof then
        if not create then return nil end
        prof = { barSpells = {} }
        sp[specKey] = prof
    end
    local st = ns.GetSpellSettingsStoreForProf(prof, famKey, create)
    if st then memo[famKey] = st end
    return st
end

-- Chain child.__index -> parent (or clear the link when parent is nil), so every read of a
-- per-spell table falls through to the bar tiers per KEY. Cheap: one getmetatable + compare.
function ns.ChainSettings(child, parent)
    if not child then return end
    local mt = getmetatable(child)
    if parent then
        if not mt then
            setmetatable(child, { __index = parent })
        elseif mt.__index ~= parent then
            mt.__index = parent
        end
    elseif mt and mt.__index ~= nil then
        mt.__index = nil
    end
end

-- Bar-tier chain head for a bar: barSettings (chained to the profile-level bd.barSpellSettings) when present, else bd.barSpellSettings, else nil.
function ns.GetBarTierSettings(sd, barKey)
    local bd = barKey and ns.barDataByKey and ns.barDataByKey[barKey]
    local abs = bd and bd.barSpellSettings
    local bs = sd and sd.barSettings
    if bs then
        ns.ChainSettings(bs, abs)
        return bs
    end
    return abs
end

-- True when any per-icon settings could apply on this bar: family store has ANY entry
-- (over-approximate -- keyed by spell, not bar) or either bar tier is non-empty. Gates "re-resolve appearance" passes.
function ns.BarHasAnySpellSettings(barKey, sd)
    local st = ns.GetSpellSettingsStore(barKey)
    if st and next(st) ~= nil then return true end
    sd = sd or ns.GetBarSpellData(barKey)
    if sd then
        if sd.barSettings and next(sd.barSettings) ~= nil then return true end
        -- Legacy shape safety net (pre-migration data; should not happen since migration runs before this addon loads).
        if sd.spellSettings and next(sd.spellSettings) ~= nil then return true end
    end
    local bd = ns.barDataByKey and ns.barDataByKey[barKey]
    if bd and bd.barSpellSettings and next(bd.barSpellSettings) ~= nil then return true end
    return false
end

-- Iterate every SAVED settings block that can hold per-spell setting keys: all specs'
-- family-store entries + per-bar barSettings, plus the active profile's bar-level
-- barSpellSettings. fn(ss) returning true stops the walk. Used by login gate scans ("does anyone use feature X anywhere").
function ns.ForEachSavedSettingsBlock(fn)
    if not EllesmereUIDB then return false end
    local sp = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if sp then
        for _, prof in pairs(sp) do
            if type(prof) == "table" then
                local stCD = prof.spellSettingsCD
                if type(stCD) == "table" then
                    for _, ss in pairs(stCD) do
                        if type(ss) == "table" and fn(ss) then return true end
                    end
                end
                local stBuff = prof.spellSettingsBuff
                if type(stBuff) == "table" then
                    for _, ss in pairs(stBuff) do
                        if type(ss) == "table" and fn(ss) then return true end
                    end
                end
                local barSpells = prof.barSpells
                if type(barSpells) == "table" then
                    for _, bs in pairs(barSpells) do
                        local bset = type(bs) == "table" and bs.barSettings
                        if type(bset) == "table" and fn(bset) then return true end
                        -- Legacy shape safety net (pre-migration data; should not happen since migration runs before this addon loads).
                        local ssAll = type(bs) == "table" and bs.spellSettings
                        if type(ssAll) == "table" then
                            for _, ss in pairs(ssAll) do
                                if type(ss) == "table" and fn(ss) then return true end
                            end
                        end
                    end
                end
            end
        end
    end
    local p = ECME and ECME.db and ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    if type(bars) == "table" then
        for _, bd in ipairs(bars) do
            local abs = type(bd) == "table" and bd.barSpellSettings
            if type(abs) == "table" and fn(abs) then return true end
        end
    end
    return false
end

-- One-time copy of a user CUSTOM spell/buff (customSpellIDs-tagged) plus its per-spell settings
-- onto the SAME bar in other specs of the active profile (bar defs are profile-level, so the bar
-- exists in every spec). A target spec that already has the spell on ANY bar is skipped whole
-- (never duplicates within a spec). Custom Active State is NOT copied: it lives in the
-- profile-level customActiveStates store, already shared across specs. Returns the count copied to.
function ns.CopyCustomSpellToSpecs(barKey, spellID, specKeys)
    if not barKey or type(spellID) ~= "number" or spellID == 0 then return 0 end
    if type(specKeys) ~= "table" then return 0 end
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return 0 end
    local curKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local famKey = ns.SettingsFamilyKey(barKey)
    local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy

    -- Source metadata from the ACTIVE spec (the bar the menu was opened on).
    local srcSd = ns.GetBarSpellData(barKey)
    local dur = srcSd and srcSd.spellDurations and srcSd.spellDurations[spellID]
    local srcStore = ns.GetSpellSettingsStore(barKey)
    local srcSettings = srcStore and srcStore[spellID]

    local copied = 0
    for key, on in pairs(specKeys) do
        if on and key ~= curKey and key ~= "0" then
            local prof = sp[key]
            if not prof then prof = { barSpells = {} }; sp[key] = prof end
            if not prof.barSpells then prof.barSpells = {} end
            -- Present anywhere in this spec? Skip the whole spec.
            local exists = false
            for _, bs in pairs(prof.barSpells) do
                if type(bs) == "table" and type(bs.assignedSpells) == "table" then
                    for _, id in ipairs(bs.assignedSpells) do
                        if id == spellID then exists = true; break end
                    end
                end
                if exists then break end
            end
            if not exists then
                local bs = prof.barSpells[barKey]
                if not bs then bs = {}; prof.barSpells[barKey] = bs end
                if not bs.assignedSpells then bs.assignedSpells = {} end
                bs.assignedSpells[#bs.assignedSpells + 1] = spellID
                if not bs.customSpellIDs then bs.customSpellIDs = {} end
                bs.customSpellIDs[spellID] = true
                if dur and dur > 0 then
                    if not bs.spellDurations then bs.spellDurations = {} end
                    bs.spellDurations[spellID] = dur
                end
                if type(srcSettings) == "table" and DeepCopy then
                    -- pairs()-based DeepCopy takes OWN keys only (no __index follow): own
                    -- settings, not bar-tier inherits. Copy is unchained; renderer re-chains on first resolve.
                    local store = prof[famKey]
                    if not store then store = {}; prof[famKey] = store end
                    if store[spellID] == nil then
                        store[spellID] = DeepCopy(srcSettings)
                        -- New entry (belt: one integer bump on a user click).
                        ns._cdmResGen = ns._cdmResGen + 1
                    end
                end
                copied = copied + 1
            end
        end
    end
    return copied
end

-- Set of OTHER specs (this class, active profile) with the spell on ANY bar. Drives the
-- per-spell menu's Copy/Remove label + the Remove picker's pre-check. Excludes the active spec.
function ns.SpecsWithCustomSpell(spellID)
    local out = {}
    if type(spellID) ~= "number" or spellID == 0 then return out end
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return out end
    local curKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    for key, prof in pairs(sp) do
        -- WoW Forever: the player's class is one spec there, so its other
        -- stored keys are not other specs (no picker row reaches them).
        if key ~= curKey and key ~= "0" and type(prof) == "table"
           and type(prof.barSpells) == "table"
           and not (EllesmereUI.IS_FOREVER and ns._playerClass
                    and EllesmereUI.SpecClassOf(tonumber(key)) == ns._playerClass) then
            local found = false
            for _, bs in pairs(prof.barSpells) do
                if type(bs) == "table" and type(bs.assignedSpells) == "table" then
                    for _, id in ipairs(bs.assignedSpells) do
                        if id == spellID then found = true; break end
                    end
                end
                if found then break end
            end
            if found then out[key] = true end
        end
    end
    return out
end

-- Inverse of CopyCustomSpellToSpecs: remove the spell + its per-spell settings from the picked
-- specs (scans every bar). Never touches the active spec or the profile-level customActiveState
-- (that stays while the spell exists on ANY spec, incl. the current one). Returns the count removed.
function ns.RemoveCustomSpellFromSpecs(spellID, specKeys)
    if type(spellID) ~= "number" or spellID == 0 then return 0 end
    if type(specKeys) ~= "table" then return 0 end
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    if not sp then return 0 end
    local curKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local removed = 0
    for key, on in pairs(specKeys) do
        if on and key ~= curKey and key ~= "0" then
            local prof = sp[key]
            if type(prof) == "table" and type(prof.barSpells) == "table" then
                local didRemove = false
                for _, bs in pairs(prof.barSpells) do
                    if type(bs) == "table" and type(bs.assignedSpells) == "table" then
                        local hitHere = false
                        for i = #bs.assignedSpells, 1, -1 do
                            if bs.assignedSpells[i] == spellID then
                                table.remove(bs.assignedSpells, i)
                                hitHere = true; didRemove = true
                            end
                        end
                        -- Clean the per-id metadata on the bar it lived on.
                        if hitHere then
                            if bs.customSpellIDs then bs.customSpellIDs[spellID] = nil end
                            if bs.spellDurations then bs.spellDurations[spellID] = nil end
                            if bs.customSpellDurations then bs.customSpellDurations[spellID] = nil end
                            if bs.customSpellGroups then
                                for variantID, primaryID in pairs(bs.customSpellGroups) do
                                    if primaryID == spellID or variantID == spellID then
                                        bs.customSpellGroups[variantID] = nil
                                    end
                                end
                            end
                        end
                    end
                end
                if didRemove then
                    -- Drop the per-spell settings entry (keyed by spellID, so clearing both family stores is safe -- only one holds it).
                    if prof.spellSettingsCD then prof.spellSettingsCD[spellID] = nil end
                    if prof.spellSettingsBuff then prof.spellSettingsBuff[spellID] = nil end
                    -- Entry deletion (belt: non-active specs by contract).
                    ns._cdmResGen = ns._cdmResGen + 1
                    removed = removed + 1
                end
            end
        end
    end
    return removed
end

-- Custom Active State store, keyed by spellID at the PROFILE level (shared across every
-- bar and spec) so state travels with the spell wherever placed. Key matches assignedSpells:
-- positive = racial/custom spell, negative = item/trinket-slot preset. Entry shape: { duration,
-- activeSwipeMode, activeSwipeClassColor, activeSwipeR/G/B/A, activeGlow, glowColor, glowColorR/G/B }.
function ns.GetCustomActiveStates()
    local p = ECME and ECME.db and ECME.db.profile
    if not p then return nil end
    if not p.customActiveStates then p.customActiveStates = {} end
    return p.customActiveStates
end

-- Read (or, with create=true, lazily create) the entry for one spell key.
function ns.GetCustomActiveState(spellID, create)
    local store = ns.GetCustomActiveStates()
    if not store then return nil end
    local e = store[spellID]
    if not e and create then e = {}; store[spellID] = e end
    return e
end

-- Map an icon's identity token to its SETTINGS key. Equipment SLOTS key their per-spell
-- settings by the EQUIPPED item (-itemID) so each item tracks separately; bar allocation
-- stays slot-based. Everything else (item presets, racials, custom spells) keys by its own token.
function ns.ResolveCustomActiveKey(frameKey)
    local slot = ns.SlotIDFromKey(frameKey)
    if slot then
        local itemID = GetInventoryItemID("player", slot)
        if itemID then return -itemID end
    end
    return frameKey
end

-- EFFECTIVE Custom Active State for an icon token -- READ paths only. Non-slot tokens
-- resolve their own entry. Equipment SLOTS resolve the EQUIPPED item's entry (per-item,
-- written via ResolveCustomActiveKey), chained per-key over the SLOT entry -- the "Apply to
-- Bar" stamp -- so one bar application covers whatever is equipped without an entry per item.
-- Chain re-asserted lazily every resolve (metatables never serialize), mirroring
-- ResolveSpellSettings. An explicit false own value renders like nil but BLOCKS the slot
-- value from showing through (per-item "None"); cdStateEffect consumers normalize false to nil.
function ns.GetEffectiveCustomActiveState(frameKey)
    local store = ns.GetCustomActiveStates()
    if not store then return nil end
    local slot = ns.SlotIDFromKey(frameKey)
    if slot then
        local slotE = store[frameKey]
        local itemID = GetInventoryItemID("player", slot)
        local itemE = itemID and store[-itemID] or nil
        if itemE then
            ns.ChainSettings(itemE, slotE)
            return itemE
        end
        return slotE
    end
    return store[frameKey]
end

-- Preset menus store cooldown effects in customActiveStates, including None.
-- Never revive an old spell-family/bar-tier effect behind that menu's back.
function ns.GetSpellCdStateEffect(frame, settings)
    if frame and ns.CdmIsInjectedFrame and ns.CdmIsInjectedFrame(frame) then return nil end
    return settings and settings.cdStateEffect
end

-- The hide effects by saved value: the base mode the evaluators run, plus
-- shift (the bar closes the gap: Shift Icons), usable (an unusable spell also
-- hides: Hidden Until Usable) and form (only the spell's form or stance
-- decides, whatever its cooldown: Hidden Outside Form/Stance). A new hide
-- effect is one entry here.
ns.CD_STATE_HIDE = {
    hiddenOnCD          = { base = "hiddenOnCD" },
    hiddenReady         = { base = "hiddenReady" },
    hiddenUnusable      = { base = "hiddenOnCD", usable = true },
    hiddenForm          = { base = "hiddenOnCD", form = true },
    hiddenOnCDShift     = { base = "hiddenOnCD", shift = true },
    hiddenReadyShift    = { base = "hiddenReady", shift = true },
    hiddenUnusableShift = { base = "hiddenOnCD", shift = true, usable = true },
    hiddenFormShift     = { base = "hiddenOnCD", shift = true, form = true },
}

-- True for a Shift Icons effect
function ns.CdStateShifts(eff)
    local m = eff and ns.CD_STATE_HIDE[eff]
    return m and m.shift or false
end

-- CD Ready glow style (CDM saved numbering), read from the same settings table as
-- the effect: the explicit pick, else what the effect name implies (pixel* =
-- Pixel Glow, button* = Action Button Glow), so older settings render unchanged.
function ns.CdReadyGlowStyle(cse, settings)
    local st = settings and settings.cdStateGlowStyle
    if type(st) == "number" and st >= 1 and st <= #ns.GLOW_STYLES then return st end
    if cse == "pixelGlowReady" or cse == "pixelGlowReadyUsable" then return 1 end
    if cse == "glowOnCD" then return 8 end  -- Blackout: the default look for this effect
    return 3
end

-- CD Ready glow color: the icon's pick, else white for the drawn styles (their
-- long-standing look) and nil for FlipBooks (the atlas's own untinted look).
function ns.CdReadyGlowColor(style, settings)
    local r, g, b = ns.ResolveGlowColor(settings)
    if r then return r, g, b end
    local e = ns.GLOW_STYLES[style]
    if e and not (e.procedural or e.buttonGlow or e.autocast or e.shapeGlow) then return nil end
    return 1, 1, 1
end

-- CD Ready / On CD glow opacity (Blackout only; other styles ignore it).
-- nil = fully opaque, matches StartSolidFill's own default.
function ns.CdReadyGlowAlpha(settings)
    return settings and settings.cdStateGlowAlpha
end

-- Does this icon have a custom Cooldown State Effect (preset cd-state)? Appearance refresh
-- uses this so it doesn't clear a preset's _cdStateHidden flag: presets store cdState in customActiveStates, not per-bar spellSettings.
function ns.PresetHasCdState(frame)
    local fc = ns._ecmeFC and ns._ecmeFC[frame]
    if not fc or not fc.spellID then return false end
    -- Only frames WE inject can own a custom active state -- same gate the
    -- Fake-Active engine applies before honoring one. Without it an orphaned
    -- profile-level entry both hid a plain tracked spell and stopped the
    -- appearance refresh from ever clearing the flag it set.
    -- Racials are the one exception: the Presets cog is their ONLY cd-state
    -- config surface (no separate per-spell settings menu, unlike custom
    -- spells), so a racial natively tracked by Blizzard's CDM must still honor it.
    if ns.CdmIsInjectedFrame and not ns.CdmIsInjectedFrame(frame)
       and not (ns._myRacialsSet and ns._myRacialsSet[fc.spellID]) then
        return false
    end
    local cas = ns.GetEffectiveCustomActiveState(fc.spellID)
    local eff = cas and cas.cdStateEffect
    if eff == false then eff = nil end  -- blocking-false = no effect
    return eff ~= nil
end

-- Max Stacks Glow gate: set ns._cdmAnyMaxStacksGlow once if any saved spell (any spec) has
-- the glow enabled, so RefreshCDMIconAppearance skips its per-icon watch check entirely for
-- non-users -- 0 cost when off. Monotonic + scanned-once: runtime enables come from the option's setValue, so this only discovers already-saved settings at/after login.
function ns.RescanMaxStacksGlowFlag()
    if ns._cdmAnyMaxStacksGlow or ns._maxStacksFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._maxStacksFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.maxStacksGlow and ss.maxStacksGlow > 0 then
            ns._cdmAnyMaxStacksGlow = true
            return true
        end
    end)
end

-- Audio on Buff Gain/Loss gate: set ns._cdmAnyBuffSound once if any saved buff icon or
-- tracking bar (any spec) has a gain OR loss sound chosen, so DecorateFrame/RefreshCDMIconAppearance
-- skip attaching the apply-edge sound hook for non-users. The icon half keeps the scanned-once +
-- runtime-enable contract of RescanMaxStacksGlowFlag. ns._tbbAnyBuffSound is the tracking-bar
-- half on its own, so icon-only users skip the tracking-bar lookup on every buff alert. Its scan
-- is O(specs x bars) with no allocation, so it repeats on every rebuild until it finds a sound,
-- which also picks up bar sounds a live profile switch brings in.
function ns.RescanBuffSoundFlag()
    if not EllesmereUIDB then return end
    if not ns._buffSoundFlagScanned then
        ns._buffSoundFlagScanned = true
        if not ns._cdmAnyBuffSound then
            ns.ForEachSavedSettingsBlock(function(ss)
                if (ss.buffActiveSoundKey and ss.buffActiveSoundKey ~= "none")
                    or (ss.buffLostSoundKey and ss.buffLostSoundKey ~= "none") then
                    ns._cdmAnyBuffSound = true
                    return true
                end
            end)
        end
    end
    -- Tracking Bars keep the same two keys on their bar configs, which the
    -- settings-block walk above never visits. EnsureTBBSoundHooks flips both
    -- gates and hooks the frames already out of the buff viewer pools.
    if not ns._tbbAnyBuffSound and ns.TBBAnyBuffSound and ns.TBBAnyBuffSound() then
        ns.EnsureTBBSoundHooks()
    end
end

-- Resolve the configured buff gain/loss sound key for a spell id in the CURRENT
-- spec by SEARCHING saved bar spellSettings -- independent of per-frame
-- decoration state (_ecmeFC): the first buff gain after login fires its aura
-- alert BEFORE DecorateFrame populates that state, so this must resolve purely
-- from the id. O(bars): spellSettings is keyed by id.
function ns.FindBuffSoundKey(sid, field)
    if not sid then return nil end
    local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not specKey or specKey == "0" then return nil end
    local sp = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    local prof = sp and sp[specKey]
    if not prof then return nil end
    -- Per-spell tier: buff family store (explicit false = inherited bar-level
    -- sound turned OFF for this one buff -- treat as silent).
    local st = prof.spellSettingsBuff
    local own = st and st[sid]
    if own then
        local v = rawget(own, field)
        if v ~= nil then
            if v and v ~= "none" then return v end
            return nil
        end
    end
    -- Bar tier: the buff bar this spell renders on. Extra buff bars claim
    -- their spells via assignedSpells; everything else lives on "buffs".
    local homeKey = "buffs"
    local barSpells = prof.barSpells
    if barSpells then
        for barKey, bs in pairs(barSpells) do
            if barKey ~= "buffs" and ns.IsBarBuffFamily and ns.IsBarBuffFamily(barKey)
               and type(bs.assignedSpells) == "table" then
                for _, asid in ipairs(bs.assignedSpells) do
                    if asid == sid then homeKey = barKey; break end
                end
            end
        end
    end
    local bsHome = barSpells and barSpells[homeKey]
    local tier = ns.GetBarTierSettings(bsHome, homeKey)
    local key = tier and tier[field]
    if key and key ~= "none" then return key end
    return nil
end

-- Audio Effect on CD Ready gate: set ns._cdmAnyCdReadySound once if any saved
-- cd/utility icon (any spec) has a CD-ready sound chosen, so the per-frame
-- SetDesaturated edge hook no-ops entirely for non-users. Same monotonic,
-- scanned-once contract as RescanBuffSoundFlag.
function ns.RescanCdReadySoundFlag()
    if ns._cdmAnyCdReadySound or ns._cdReadySoundFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._cdReadySoundFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.cdReadySoundKey and ss.cdReadySoundKey ~= "none" then
            ns._cdmAnyCdReadySound = true
            return true
        end
    end)
end

-- "Replace with Buff" gate: set ns._cdmAnyBuffReplace once if any saved cd/utility
-- icon (any spec) names a replacement buff, so the route map's Pass 3c and the
-- collect pass's identity swap and compaction stay skipped for non-users. Same
-- scanned-once contract as RescanCdReadySoundFlag.
function ns.RescanBuffReplaceFlag()
    if ns._cdmAnyBuffReplace or ns._buffReplaceFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._buffReplaceFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if type(ss.replaceBuffID) == "number" and ss.replaceBuffID > 0 then
            ns._cdmAnyBuffReplace = true
            return true
        end
    end)
end

-- "Hide CD Text (Charges)" gate: set ns._cdmAnyChargeHideCdText once if any saved spell
-- (any spec) has the toggle on; RefreshCDMIconAppearance then skips its per-icon watch
-- check for non-users. Same contract as RescanMaxStacksGlowFlag.
function ns.RescanChargeCdTextFlag()
    if ns._cdmAnyChargeHideCdText or ns._chargeCdTextFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._chargeCdTextFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.chargeHideCdText then
            ns._cdmAnyChargeHideCdText = true
            return true
        end
    end)
end

-- Per-spell Duration Text gate: set ns._cdmAnySpellDurationText once if any saved spell
-- (any spec) overrides showCooldownText either way. ~= nil, not truthiness: a per-spell
-- ON must beat a bar that is OFF, same as the options resolver reads it.
function ns.RescanSpellDurationTextFlag()
    if ns._cdmAnySpellDurationText or ns._spellDurationTextFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._spellDurationTextFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.showCooldownText ~= nil then
            ns._cdmAnySpellDurationText = true
            return true
        end
    end)
end

-- "Hide Charge Text" gate: set ns._cdmAnyHideChargeText once if any saved spell
-- (any spec) has the toggle on. The appearance pass consults it to reach
-- WatchZeroChargeTextIfEnabled for users of neither the bar-level zero-charge
-- feature nor an active watch -- without it the per-spell hide never runs.
-- Same monotonic, scanned-once contract as RescanChargeCdTextFlag.
function ns.RescanHideChargeTextFlag()
    if ns._cdmAnyHideChargeText or ns._hideChargeTextFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._hideChargeTextFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.hideChargeText then
            ns._cdmAnyHideChargeText = true
            return true
        end
    end)
end

-- Per-spell Suppress GCD gate: the entry-B re-arm and the preset-frame GCD
-- swipe pass resolve per-spell settings only behind this flag. Same
-- monotonic, scanned-once contract as RescanChargeCdTextFlag.
function ns.RescanSuppressGcdFlag()
    if ns._cdmAnySuppressGcd or ns._suppressGcdFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._suppressGcdFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.suppressGCD then
            ns._cdmAnySuppressGcd = true
            return true
        end
    end)
end

-- Charge style gate: set ns._cdmAnyChargeStyle once if any saved spell (any spec)
-- has Hide Swipe (Charges) or Hide Recharge Edge enabled. Same monotonic,
-- scanned-once contract as RescanChargeCdTextFlag.
--
-- This flag is the one charge gate that had no priming pass: it was set only from
-- inside the SetSwipeColor hook, i.e. not until the first cooldown re-push after
-- login, which is already after the rebuild has run RefreshCDMIconAppearance. So
-- the rebuild's ReapplyChargeStyle was skipped, and ApplyCdmChargeStyle itself
-- gates its whole Hide Swipe / Hide Recharge Edge block on the flag -- meaning a
-- charge spell already recharging at login kept its swipe until something pushed
-- its cooldown again. Priming here closes that window; the reactive hooks then
-- carry it as before.
function ns.RescanChargeStyleFlag()
    if ns._cdmAnyChargeStyle or ns._chargeStyleFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._chargeStyleFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.chargeHideSwipe or ss.hideRechargeEdge then
            ns._cdmAnyChargeStyle = true
            return true
        end
    end)
end

-- Custom Item gate: set ns._cdmAnyCustomItem once if any saved bar (any spec) tracks a custom
-- item (assignedSpells entry <= -100); the buff-bar injection pass is skipped entirely for non-users. Same contract as the flags above.
function ns.RescanCustomItemFlag()
    if ns._cdmAnyCustomItem or ns._customItemFlagScanned then return end
    local sp = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if not sp then return end
    ns._customItemFlagScanned = true
    for _, prof in pairs(sp) do
        local barSpells = prof and prof.barSpells
        if barSpells then
            for _, bs in pairs(barSpells) do
                local assigned = bs and bs.assignedSpells
                if assigned then
                    for _, sid in ipairs(assigned) do
                        -- Hosted-buff and Empty Slot markers are also <= -100; they are not items.
                        if type(sid) == "number" and sid <= -100
                           and sid > -ns.EMPTY_SLOT_MARKER_BASE then
                            ns._cdmAnyCustomItem = true
                            return
                        end
                    end
                end
            end
        end
    end
end

-- "Show Charges" (custom CD/utility spells) gate. Same contract as the flags above; zero cost in ProcessPresetCooldowns unless a custom spell opted in.
function ns.RescanCustomForceCountFlag()
    if ns._cdmAnyCustomForceCount or ns._customForceCountScanned then return end
    local sp = SpellStore and SpellStore.GetSpecProfiles and SpellStore.GetSpecProfiles()
    if not sp then return end
    ns._customForceCountScanned = true
    for _, prof in pairs(sp) do
        local barSpells = prof and prof.barSpells
        if barSpells then
            for _, bs in pairs(barSpells) do
                if bs and type(bs.customSpellForceCount) == "table" and next(bs.customSpellForceCount) then
                    ns._cdmAnyCustomForceCount = true
                    return
                end
            end
        end
    end
end

-- "Out of Range Coloring" (spells added by Spell ID) gate. Same contract as the flags above;
-- lives in the profile customActiveStates. Zero cost in the preset pass (and no range check
-- armed, no listener events) unless a custom spell opted in.
function ns.RescanCustomRangeColorFlag()
    if ns._cdmAnyCustomRangeColor or ns._customRangeColorScanned then return end
    local cas = ns.GetCustomActiveStates()
    if not cas then return end
    ns._customRangeColorScanned = true
    for _, e in pairs(cas) do
        if type(e) == "table" and e.outOfRangeColoring then
            ns._cdmAnyCustomRangeColor = true
            -- Arming rides the Show edge; icons already shown missed it.
            ns.RefreshCustomSpellRange()
            return
        end
    end
end


-- Reverse Swipe gate: set ns._cdmAnyReverseSwipe once if any saved spell (any spec) has
-- per-spell reverseSwipe on; the reverse-apply in RefreshCDMIconAppearance is skipped for
-- non-users. Also gates hideCDSwipe -- both monotonic per-spell swipe flags scanned in one pass, costing nothing until used.
function ns.RescanReverseSwipeFlag()
    if ns._reverseSwipeFlagScanned then return end
    if ns._cdmAnyReverseSwipe and ns._cdmAnyHideCDSwipe then return end
    if not EllesmereUIDB then return end
    ns._reverseSwipeFlagScanned = true
    -- Regular per-spell settings (family stores + bar tiers, every spec).
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.reverseSwipe then ns._cdmAnyReverseSwipe = true end
        if ss.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
    end)
    -- Preset / custom cd-utility spells (profile-level customActiveStates).
    local cas = ns.GetCustomActiveStates and ns.GetCustomActiveStates()
    if cas then
        for _, e in pairs(cas) do
            if e then
                if e.reverseSwipe then ns._cdmAnyReverseSwipe = true end
                if e.hideCDSwipe then ns._cdmAnyHideCDSwipe = true end
            end
        end
    end
end

-- Glow When Visible gate: set ns._cdmAnyGlowVisible once if any saved spell (any spec) has
-- the per-spell toggle on; the cd-state and buff glow paths skip it for non-users.
function ns.RescanGlowVisibleFlag()
    if ns._cdmAnyGlowVisible or ns._glowVisibleFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._glowVisibleFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if ss.glowWhenVisible then
            ns._cdmAnyGlowVisible = true
            return true
        end
    end)
end

-- Threshold Text gate: set ns._cdmAnyThresholdText once if any saved spell (any spec) has
-- Threshold Seconds armed -- per-spell family stores, bar tiers, or preset/custom
-- customActiveStates entries. Skips the formatter attach in RefreshCDMIconAppearance (and the fake-active/custom-buff attach sites) for non-users. Same monotonic, scanned-once contract.
function ns.RescanThresholdTextFlag()
    if ns._cdmAnyThresholdText or ns._thresholdTextFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._thresholdTextFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if (tonumber(ss.thresholdSeconds) or 0) > 0 then
            ns._cdmAnyThresholdText = true
            return true
        end
    end)
    if not ns._cdmAnyThresholdText then
        local cas = ns.GetCustomActiveStates and ns.GetCustomActiveStates()
        if cas then
            for _, e in pairs(cas) do
                if type(e) == "table" and (tonumber(e.thresholdSeconds) or 0) > 0 then
                    ns._cdmAnyThresholdText = true
                    break
                end
            end
        end
    end
end

-- Custom Icon gate: set ns._cdmAnyCustomIcon once if any saved spell (any spec) has a
-- per-spell replacement icon. Skips the DecorateFrame re-stamp and the RefreshSpellTexture
-- post-hooks for non-users. Same monotonic, scanned-once contract; customIcon is never written to bar tiers.
function ns.RescanCustomIconFlag()
    if ns._cdmAnyCustomIcon or ns._customIconFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._customIconFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if type(ss.customIcon) == "number" and ss.customIcon > 0 then
            ns._cdmAnyCustomIcon = true
            return true
        end
    end)
end

-- Active State Glow gate: set ns._cdmAnyActiveGlow once if any saved spell (any spec) has
-- per-spell activeGlow set. Skips the buff ticker's active-glow integrity pass (safety net
-- that lights the glow when Blizzard skips the SetSwipeColor call that normally drives it) for non-users. Same monotonic, scanned-once contract.
function ns.RescanActiveGlowFlag()
    if ns._cdmAnyActiveGlow or ns._activeGlowFlagScanned then return end
    if not EllesmereUIDB then return end
    ns._activeGlowFlagScanned = true
    ns.ForEachSavedSettingsBlock(function(ss)
        if (tonumber(ss.activeGlow) or 0) > 0 then
            ns._cdmAnyActiveGlow = true
            return true
        end
    end)
end

I.SpellStore = SpellStore
I.broken = false
