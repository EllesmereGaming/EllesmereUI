-------------------------------------------------------------------------------
--  EllesmereUICdmRPTSync.lua
--  One-time generic CDs/Buffs copy across specs of the ACTIVE PROFILE.
--
--  Synced entries are the spec-independent ones: trinket slots (-13/-14), item
--  presets (negative item IDs from the Potions & Healthstone flyout), the player's
--  racial ability, and built-in BUFF-BAR PRESETS (Bloodlust/Heroism, Time Spiral,
--  Light's Potential, the buff potions). RPT ids copy bar placement + per-icon
--  settings; buff presets are additive-only. No ongoing relationship is stored,
--  so every later edit remains isolated to its own spec container.
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

-- The active EUI profile's spell-store bucket (holds specProfiles).
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
    for _, info in ipairs(EUI and EUI.Spec and EUI.Spec:GetList() or {}) do
        local specID, sName, sIcon = info.id, info.name, info.icon
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

-- { [barKey] = { ids = {id,...}, durations = {[id]=dur} } } of a spec's sync
-- entries: RPT ids (racials/pots/trinkets) PLUS buff presets. `durations` is
-- populated ONLY for buff-preset ids (they need the stored duration to render
-- on the target spec); RPT ids never have a spellDurations entry.
-- Second return: the synced ids' per-spell settings from the spec's FAMILY
-- stores ({ cd = {[id]=copy}, buff = {[id]=copy} }) -- settings are keyed by
-- spell, not bar, in the tiered model.
local function CollectRPT(specProf)
    local out = {}
    if type(specProf) ~= "table" or type(specProf.barSpells) ~= "table" then return out end
    local stCD = specProf.spellSettingsCD
    local stBuff = specProf.spellSettingsBuff
    local settingsCD, settingsBuff
    for barKey, sd in pairs(specProf.barSpells) do
        if barKey ~= "__ghost_cd" and type(sd.assignedSpells) == "table" then
            local ids, durations
            for _, id in ipairs(sd.assignedSpells) do
                if IsRPTId(id) then
                    ids = ids or {}; ids[#ids + 1] = id
                    local s = stCD and stCD[id]
                    if type(s) == "table" then
                        settingsCD = settingsCD or {}
                        settingsCD[id] = DeepCopy(s)
                    end
                elseif IsBuffSyncId(sd, id) then
                    ids = ids or {}; ids[#ids + 1] = id
                    durations = durations or {}
                    durations[id] = sd.spellDurations[id]
                    local s = stBuff and stBuff[id]
                    if type(s) == "table" then
                        settingsBuff = settingsBuff or {}
                        settingsBuff[id] = DeepCopy(s)
                    end
                end
            end
            if ids then
                out[barKey] = { ids = ids, durations = durations }
            end
        end
    end
    return out, { cd = settingsCD, buff = settingsBuff }
end

-- Overwrite targetSpec's RPT (all bars) to match sourceSpec's. Regular spells kept.
local function ApplyRPT(specProfiles, sourceSpecKey, targetSpecKey)
    local srcProf = specProfiles[sourceSpecKey]
    if not srcProf then return end
    local tgtProf = specProfiles[targetSpecKey]
    if not tgtProf then
        tgtProf = ns.GetSpecContainerForProfile
            and ns.GetSpecContainerForProfile(ns.GetActiveProfileName(), targetSpecKey, true)
        if not tgtProf then return end
    end
    if not tgtProf.barSpells then tgtProf.barSpells = {} end
    local srcRPT, srcSettings = CollectRPT(srcProf)

    -- A generic entry may live on a user-created bar. Copy that definition once
    -- so the target has a real, independently editable container for the entry.
    if srcProf.cdmBars and srcProf.cdmBars.bars and tgtProf.cdmBars and tgtProf.cdmBars.bars then
        local targetKeys = {}
        for _, bar in ipairs(tgtProf.cdmBars.bars) do
            if bar.key then targetKeys[bar.key] = true end
        end
        for barKey in pairs(srcRPT) do
            if not targetKeys[barKey] then
                for _, bar in ipairs(srcProf.cdmBars.bars) do
                    if bar.key == barKey then
                        tgtProf.cdmBars.bars[#tgtProf.cdmBars.bars + 1] = DeepCopy(bar)
                        targetKeys[barKey] = true
                        break
                    end
                end
            end
        end
    end

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
                    -- Bar move only: per-spell settings live in the family
                    -- stores now and travel with the id -- nothing to clear.
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
    end

    -- Per-spell settings live in the FAMILY stores (keyed by id, not bar).
    -- RPT settings sync (overwrite); buff-preset settings fill-only so a
    -- spec's own per-icon buff styling is never reset by re-propagation.
    if srcSettings then
        if srcSettings.cd then
            local tgt = tgtProf.spellSettingsCD
            if not tgt then tgt = {}; tgtProf.spellSettingsCD = tgt end
            for id, s in pairs(srcSettings.cd) do
                tgt[id] = DeepCopy(s)
            end
        end
        if srcSettings.buff then
            local tgt = tgtProf.spellSettingsBuff
            if not tgt then tgt = {}; tgtProf.spellSettingsBuff = tgt end
            for id, s in pairs(srcSettings.buff) do
                if tgt[id] == nil then tgt[id] = DeepCopy(s) end
            end
        end
    end
end

-- Copy from sourceSpecKey to the selected targets once. The legacy function name
-- is retained for the options caller, but no persistent sync set is created.
function ns.SetupRPTSync(specsSet, sourceSpecKey)
    local b = GetActiveBucket()
    if not b then return false end
    if not b.specProfiles then b.specProfiles = {} end
    if sourceSpecKey then
        for specKey, selected in pairs(specsSet or {}) do
            if selected and specKey ~= sourceSpecKey then
                ApplyRPT(b.specProfiles, sourceSpecKey, specKey)
            end
        end
    end
    return true
end
