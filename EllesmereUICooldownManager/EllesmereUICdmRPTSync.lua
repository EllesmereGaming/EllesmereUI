-------------------------------------------------------------------------------
--  EllesmereUICdmRPTSync.lua
--  Generic CDs/Buffs sync, across chosen specs of the ACTIVE PROFILE.
--
--  Synced entries are the spec-independent ones: trinket slots (-13/-14), item
--  presets (negative item IDs from the Potions & Healthstone flyout), the player's
--  racial ability, and built-in BUFF-BAR PRESETS (Bloodlust/Heroism, Time Spiral,
--  Light's Potential, the buff potions). When specs are synced, editing these on
--  one synced spec auto-copies them to the other synced specs. RPT ids sync bar
--  placement + per-icon settings; buff presets are ADDITIVE-ONLY (added to specs
--  that lack them, never removed by sync). Regular cooldowns, Blizzard-tracked
--  buffs, custom-typed buff IDs, and unsynced specs are never touched.
--
--  Storage rides in the per-profile spell store:
--      spellAssignments.profiles[<euiProfile>].rptSyncSpecs[specKey] = true
--  (extracted from the retired spell-layout experiment; the data layer here is
--  the only part kept, re-pointed at the per-profile model.)
-------------------------------------------------------------------------------
local _, ns = ...

local function DeepCopy(t)
    local fn = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy
    if fn then return fn(t) end
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = DeepCopy(v) end
    return r
end

local function GetSA()
    if not EllesmereUIDB then return nil end
    if not EllesmereUIDB.spellAssignments then
        EllesmereUIDB.spellAssignments = { profiles = {} }
    end
    local sa = EllesmereUIDB.spellAssignments
    if not sa.profiles then sa.profiles = {} end
    return sa
end

-- The active EUI profile's spell-store bucket (holds specProfiles + rptSyncSpecs).
-- Ensure it exists (GetActiveSpecProfiles seeds it), then return it.
local function GetActiveBucket()
    local sa = GetSA(); if not sa then return nil end
    if ns.GetActiveSpecProfiles then ns.GetActiveSpecProfiles() end
    local name = ns.GetActiveProfileName and ns.GetActiveProfileName()
    return name and sa.profiles[name] or nil
end

-- Player's specs + whether each has CDM data, for the sync spec pickers. (Shared
-- helper that used to live in the retired layouts file; the RPT UI needs it.)
function ns.GetCDMSpecInfo()
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local result = {}
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID, sName, _, sIcon = GetSpecializationInfo(i)
        if specID then
            local key = tostring(specID)
            local prof = sp and sp[key]
            local hasData = false
            if type(prof) == "table" then
                if prof.barSpells and next(prof.barSpells) ~= nil then
                    hasData = true
                elseif prof.trackedBuffBars and prof.trackedBuffBars.bars
                       and #prof.trackedBuffBars.bars > 0 then
                    hasData = true
                end
            end
            result[#result + 1] = {
                key = key, name = sName or ("Spec " .. key),
                icon = sIcon, hasData = hasData,
            }
        end
    end
    return result
end

-- Like GetCDMSpecInfo, but for the "Sync From" SOURCE picker: lets you pick a
-- source spec from ANY class, not just the current one. A sync can span classes
-- when one EUI profile is shared across characters (the target spec picker
-- already shows all classes). To keep the source list meaningful (and short --
-- that picker has no scroll), the current class's specs are always listed, and
-- every OTHER class's specs are listed only when this profile actually holds CDM
-- data for them (an empty other-class spec is useless as a source).
function ns.GetAllCDMSpecInfo()
    local sp = ns.GetActiveSpecProfiles and ns.GetActiveSpecProfiles()
    local _, curClassFile = UnitClass("player")
    local result = {}

    local function HasData(prof)
        if type(prof) ~= "table" then return false end
        if prof.barSpells and next(prof.barSpells) ~= nil then return true end
        if prof.trackedBuffBars and prof.trackedBuffBars.bars
           and #prof.trackedBuffBars.bars > 0 then return true end
        return false
    end

    local numClasses = (GetNumClasses and GetNumClasses()) or 0
    for classID = 1, numClasses do
        local className, classFile = GetClassInfo(classID)
        local isCurrentClass = (classFile ~= nil and classFile == curClassFile)
        local numSpecs = (GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(classID)) or 0
        for specIndex = 1, numSpecs do
            local specID, sName, _, sIcon = GetSpecializationInfoForClassID(classID, specIndex)
            if specID then
                local key = tostring(specID)
                local hasData = HasData(sp and sp[key])
                if isCurrentClass or hasData then
                    -- Disambiguate other-class specs (e.g. Frost Mage vs Frost DK)
                    -- by appending the class name; the current class needs no suffix.
                    local nm = sName or ("Spec " .. key)
                    if not isCurrentClass and className then
                        nm = nm .. " (" .. className .. ")"
                    end
                    result[#result + 1] = {
                        key = key, name = nm, icon = sIcon, hasData = hasData,
                    }
                end
            end
        end
    end
    return result
end

local function IsRPTId(id)
    if type(id) ~= "number" then return false end
    if id < 0 then return true end  -- trinket slots (-13/-14) + item presets (-itemID)
    -- Racial slot: match ANY race's racial, not just the current character's
    -- (ns._myRacialsSet). A profile shared across characters of different races
    -- stores a different racial spell ID per character, so the sync must still
    -- recognize, collect, and strip the racial slot regardless of which race's ID
    -- is stored. NormalizeRacialAssignments remaps it to each character's own
    -- racial when that spec is built.
    if id > 0 and ns.ALL_RACIAL_SPELLS and ns.ALL_RACIAL_SPELLS[id] then return true end  -- racial (any race)
    return false
end
ns.IsRPTSyncId = IsRPTId

-- Buff-bar PRESET ids (Bloodlust/Heroism, Time Spiral, Light's Potential, the buff
-- potions), derived from ns.BUFF_BAR_PRESETS. Built lazily so it picks up the
-- faction-resolved Bloodlust/Heroism id. Custom-typed buff IDs and Blizzard-tracked
-- buffs are NOT in this set, so only the built-in presets are ever synced.
local _buffPresetIds
local function BuffPresetIds()
    if not _buffPresetIds then
        _buffPresetIds = {}
        local presets = ns.BUFF_BAR_PRESETS
        if type(presets) == "table" then
            for _, preset in ipairs(presets) do
                if type(preset.spellIDs) == "table" then
                    for _, sid in ipairs(preset.spellIDs) do _buffPresetIds[sid] = true end
                end
            end
        end
    end
    return _buffPresetIds
end

-- COLLECT-ONLY predicate for buff presets. A buff preset's identity is the matched
-- pair (assignedSpells id + spellDurations[id]>0) -- there is no customSpellIDs
-- fallback. This is used ONLY to COLLECT and ADD buff presets across specs. It is
-- NEVER routed into the step-1 strip, and the strip never clears spellDurations, so
-- sync can never remove or duration-orphan a buff preset (additive-only). The
-- duration requirement keeps it to buffs bars (CD/utility presets use
-- customSpellDurations, never spellDurations).
local function IsBuffSyncId(sd, id)
    return BuffPresetIds()[id]
       and type(sd) == "table"
       and type(sd.spellDurations) == "table"
       and (sd.spellDurations[id] or 0) > 0
end

-- Set of buff-preset ids already present anywhere in a spec's bars, so additive
-- sync never seeds a buff preset onto a second bar (cross-bar duplication guard).
local function BuffIdsPresentOnTarget(tgtProf)
    local set = {}
    if type(tgtProf) ~= "table" or type(tgtProf.barSpells) ~= "table" then return set end
    local presetIds = BuffPresetIds()
    for barKey, sd in pairs(tgtProf.barSpells) do
        if barKey ~= "__ghost_cd" and type(sd.assignedSpells) == "table" then
            for _, id in ipairs(sd.assignedSpells) do
                if presetIds[id] then set[id] = true end
            end
        end
    end
    return set
end

-- Active profile's synced-spec set, or nil. Read-only.
function ns.GetRPTSyncSpecs()
    local b = GetActiveBucket()
    return b and b.rptSyncSpecs or nil
end

function ns.HasRPTSync()
    local s = ns.GetRPTSyncSpecs()
    return s ~= nil and next(s) ~= nil
end

-- { [barKey] = { ids = {id,...}, settings = {[id]=copy}, durations = {[id]=dur} } }
-- of a spec's sync entries: RPT ids (racials/pots/trinkets) PLUS buff presets.
-- `durations` is populated ONLY for buff-preset ids (they need the stored duration
-- to render on the target spec); RPT ids never have a spellDurations entry.
local function CollectRPT(specProf)
    local out = {}
    if type(specProf) ~= "table" or type(specProf.barSpells) ~= "table" then return out end
    for barKey, sd in pairs(specProf.barSpells) do
        if barKey ~= "__ghost_cd" and type(sd.assignedSpells) == "table" then
            local ids, durations
            for _, id in ipairs(sd.assignedSpells) do
                if IsRPTId(id) then
                    ids = ids or {}; ids[#ids + 1] = id
                elseif IsBuffSyncId(sd, id) then
                    ids = ids or {}; ids[#ids + 1] = id
                    durations = durations or {}
                    durations[id] = sd.spellDurations[id]
                end
            end
            if ids then
                local settings
                if type(sd.spellSettings) == "table" then
                    for _, id in ipairs(ids) do
                        if sd.spellSettings[id] then
                            settings = settings or {}
                            settings[id] = DeepCopy(sd.spellSettings[id])
                        end
                    end
                end
                out[barKey] = { ids = ids, settings = settings, durations = durations }
            end
        end
    end
    return out
end

-- Overwrite targetSpec's RPT (all bars) to match sourceSpec's. Regular spells kept.
local function ApplyRPT(specProfiles, sourceSpecKey, targetSpecKey)
    local srcProf = specProfiles[sourceSpecKey]
    if not srcProf then return end
    local tgtProf = specProfiles[targetSpecKey]
    if not tgtProf then
        -- Never-played target spec: it is born directly in the bar-filter v6
        -- model, so stamp it migrated. Otherwise the first time the player
        -- actually plays this spec, MigrateSpecToBarFilterModelV6 would see the
        -- seeded racial/pot/trinket entries sitting on the default bars, decide
        -- those bars hold "authored content to preserve," and ghost every real
        -- cooldown the spec tracks (only the RPT ids count as assigned) -- which
        -- wipes the spec's entire visible CDM the first time it is played.
        tgtProf = { barSpells = {}, _barFilterModelV6 = true }
        specProfiles[targetSpecKey] = tgtProf
    end
    if not tgtProf.barSpells then tgtProf.barSpells = {} end
    local srcRPT = CollectRPT(srcProf)

    -- Which bar the source keeps each RPT id on. Bar MEMBERSHIP and per-icon
    -- settings are synced, but the SLOT POSITION (order within a bar) is NOT:
    -- each spec keeps its own icon order so a sync never shoves the
    -- trinket/pot/racial back to default. Preserving existing slots also makes
    -- this pass idempotent, so re-propagation on spec change / logout no longer
    -- resets positions.
    local srcBarOf = {}
    for barKey, data in pairs(srcRPT) do
        for _, id in ipairs(data.ids) do srcBarOf[id] = barKey end
    end

    -- 1. Drop a target RPT id only when the source still carries it but on a
    --    DIFFERENT bar (a move) -- step 2 then re-adds it on the source's bar.
    --    An id the source lacks ENTIRELY (srcBarOf[id] == nil) is LEFT IN PLACE:
    --    an absent source entry is not an authoritative removal -- the source spec
    --    may simply be unconfigured -- so we never strip a configured target down
    --    to match an empty/partial source (that wiped Bloodlust/pots/trinkets off
    --    synced specs). RPT ids that stay on the same bar keep their slot position.
    for barKey, sd in pairs(tgtProf.barSpells) do
        if barKey ~= "__ghost_cd" and type(sd.assignedSpells) == "table" then
            local w = 1
            for r = 1, #sd.assignedSpells do
                local id = sd.assignedSpells[r]
                if IsRPTId(id) and srcBarOf[id] and srcBarOf[id] ~= barKey then
                    if sd.spellSettings then sd.spellSettings[id] = nil end
                else
                    sd.assignedSpells[w] = id; w = w + 1
                end
            end
            for i = w, #sd.assignedSpells do sd.assignedSpells[i] = nil end
        end
    end

    -- 2. ADD source sync ids the target is missing (additive only -- step 2 never
    --    removes). RPT ids append on the source's bar; their settings sync
    --    (overwrite). Buff presets append ONLY when the target has them on NO
    --    buffs-family bar (target-wide presence -> no cross-bar duplication) and are
    --    ALWAYS paired with a spellDurations entry (fill-only), so a buff id can
    --    never become a duration-less invisible orphan. Buff settings are fill-only
    --    so a spec's own per-icon buff styling is never reset by re-propagation.
    --    Ids already present keep their current slot.
    local tgtBuffPresent = BuffIdsPresentOnTarget(tgtProf)
    for barKey, data in pairs(srcRPT) do
        local sd = tgtProf.barSpells[barKey]
        if not sd then sd = { assignedSpells = {} }; tgtProf.barSpells[barKey] = sd end
        if not sd.assignedSpells then sd.assignedSpells = {} end
        local present = {}
        for _, id in ipairs(sd.assignedSpells) do present[id] = true end
        local durs = data.durations
        for _, id in ipairs(data.ids) do
            if durs and durs[id] ~= nil then
                -- Buff preset: add only if absent from EVERY buffs-family bar of the
                -- target, and always pair the duration so it renders.
                if not present[id] and not tgtBuffPresent[id] then
                    sd.assignedSpells[#sd.assignedSpells + 1] = id
                    present[id] = true
                    tgtBuffPresent[id] = true
                    sd.spellDurations = sd.spellDurations or {}
                    sd.spellDurations[id] = sd.spellDurations[id] or durs[id]
                end
            elseif not present[id] then
                sd.assignedSpells[#sd.assignedSpells + 1] = id
                present[id] = true
            end
        end
        if data.settings then
            if not sd.spellSettings then sd.spellSettings = {} end
            for id, s in pairs(data.settings) do
                -- RPT settings sync (overwrite); buff-preset settings fill-only.
                if IsRPTId(id) or sd.spellSettings[id] == nil then
                    sd.spellSettings[id] = DeepCopy(s)
                end
            end
        end
    end
end

-- Propagate RPT from sourceSpecKey to all OTHER synced specs in the active profile.
function ns.PropagateRPTFrom(sourceSpecKey)
    if not sourceSpecKey then return end
    local b = GetActiveBucket()
    if not b or type(b.rptSyncSpecs) ~= "table" or not b.rptSyncSpecs[sourceSpecKey] then return end
    if not b.specProfiles then return end
    -- Never propagate from a source spec that carries NO racial/pot/trinket
    -- entries. An empty source is not an authoritative "remove everything" signal
    -- -- it is usually an unconfigured spec the player just happens to be viewing
    -- -- so propagating it would only ever strip configured targets and create
    -- empty stamped profiles for never-played specs. Require at least one RPT id.
    local srcProf = b.specProfiles[sourceSpecKey]
    if not srcProf or next(CollectRPT(srcProf)) == nil then return end
    for specKey in pairs(b.rptSyncSpecs) do
        if specKey ~= sourceSpecKey then
            ApplyRPT(b.specProfiles, sourceSpecKey, specKey)
        end
    end
end

-- Called after an RPT-affecting edit: if the ACTIVE spec is synced, push its RPT
-- to the other synced specs. The active spec (the one shown) is the source, so
-- no rebuild is needed -- only the off-screen synced specs' data changes.
function ns.MaybePropagateRPT()
    if not ns.HasRPTSync() then return end
    local active = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    if not active or active == "0" then return end
    ns.PropagateRPTFrom(active)
end

-- First-time setup: set the synced-spec set + align ALL of them to sourceSpecKey.
function ns.SetupRPTSync(specsSet, sourceSpecKey)
    local b = GetActiveBucket()
    if not b then return false end
    if not b.specProfiles then b.specProfiles = {} end
    b.rptSyncSpecs = {}
    for k, v in pairs(specsSet) do if v then b.rptSyncSpecs[k] = true end end
    if sourceSpecKey then
        for specKey in pairs(b.rptSyncSpecs) do
            if specKey ~= sourceSpecKey then
                ApplyRPT(b.specProfiles, sourceSpecKey, specKey)
            end
        end
    end
    return true
end

-- Update an existing sync's spec set: align only NEWLY-added specs (from a still-
-- synced source, preferring the active spec); removed specs simply stop syncing.
function ns.UpdateRPTSyncSpecs(specsSet)
    local b = GetActiveBucket()
    if not b then return false end
    if not b.specProfiles then b.specProfiles = {} end
    local old = b.rptSyncSpecs or {}
    local active = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
    local source
    if active and specsSet[active] and old[active] then
        source = active
    else
        for k in pairs(old) do if specsSet[k] then source = k; break end end
    end
    local newSet = {}
    for k, v in pairs(specsSet) do if v then newSet[k] = true end end
    b.rptSyncSpecs = newSet
    if source then
        for k in pairs(newSet) do
            if k ~= source and not old[k] then
                ApplyRPT(b.specProfiles, source, k)
            end
        end
    end
    return true
end

function ns.ClearRPTSync()
    local b = GetActiveBucket()
    if b then b.rptSyncSpecs = nil end
end

-- Auto-propagate RPT after the centralized spell-mutation functions run (covers
-- add / remove / move / preset / replace of racials, pots, trinkets & buff
-- presets). Settings
-- changes are covered by a spell-picker close hook in the options file.
do
    local function Wrap(fnName)
        local orig = ns[fnName]
        if type(orig) ~= "function" then return end
        ns[fnName] = function(...)
            local a, b = orig(...)
            ns.MaybePropagateRPT()
            return a, b
        end
    end
    for _, fnName in ipairs({
        "AddTrackedSpell", "RemoveTrackedSpell", "AddPresetToBar",
        "SwapTrackedSpells", "MoveTrackedSpell", "ReplaceTrackedSpell",
    }) do
        Wrap(fnName)
    end
end
