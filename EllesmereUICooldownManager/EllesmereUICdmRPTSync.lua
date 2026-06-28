-------------------------------------------------------------------------------
--  EllesmereUICdmRPTSync.lua
--  Racials / Pots / Trinkets sync, across chosen specs of the ACTIVE PROFILE.
--
--  "RPT" = the character-utility entries: trinket slots (-13/-14), item presets
--  (negative item IDs from the Potions & Healthstone flyout), and the player's
--  racial ability. When specs are synced, editing these on one synced spec
--  auto-copies them (bar placement + per-icon settings) to the other synced
--  specs. Regular cooldowns/buffs and unsynced specs are never touched.
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

-- Active profile's synced-spec set, or nil. Read-only.
function ns.GetRPTSyncSpecs()
    local b = GetActiveBucket()
    return b and b.rptSyncSpecs or nil
end

function ns.HasRPTSync()
    local s = ns.GetRPTSyncSpecs()
    return s ~= nil and next(s) ~= nil
end

-- { [barKey] = { ids = {id,...}, settings = {[id]=copy} } } of a spec's RPT entries.
local function CollectRPT(specProf)
    local out = {}
    if type(specProf) ~= "table" or type(specProf.barSpells) ~= "table" then return out end
    for barKey, sd in pairs(specProf.barSpells) do
        if barKey ~= "__ghost_cd" and type(sd.assignedSpells) == "table" then
            local ids
            for _, id in ipairs(sd.assignedSpells) do
                if IsRPTId(id) then ids = ids or {}; ids[#ids + 1] = id end
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
                out[barKey] = { ids = ids, settings = settings }
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
    -- 1. Strip existing RPT entries (and their settings) from every target bar.
    for barKey, sd in pairs(tgtProf.barSpells) do
        if barKey ~= "__ghost_cd" and type(sd.assignedSpells) == "table" then
            local w = 1
            for r = 1, #sd.assignedSpells do
                local id = sd.assignedSpells[r]
                if IsRPTId(id) then
                    if sd.spellSettings then sd.spellSettings[id] = nil end
                else
                    sd.assignedSpells[w] = id; w = w + 1
                end
            end
            for i = w, #sd.assignedSpells do sd.assignedSpells[i] = nil end
        end
    end
    -- 2. Add the source's RPT to the matching target bars.
    for barKey, data in pairs(srcRPT) do
        local sd = tgtProf.barSpells[barKey]
        if not sd then sd = { assignedSpells = {} }; tgtProf.barSpells[barKey] = sd end
        if not sd.assignedSpells then sd.assignedSpells = {} end
        for _, id in ipairs(data.ids) do
            sd.assignedSpells[#sd.assignedSpells + 1] = id
        end
        if data.settings then
            if not sd.spellSettings then sd.spellSettings = {} end
            for id, s in pairs(data.settings) do sd.spellSettings[id] = DeepCopy(s) end
        end
    end
end

-- Propagate RPT from sourceSpecKey to all OTHER synced specs in the active profile.
function ns.PropagateRPTFrom(sourceSpecKey)
    if not sourceSpecKey then return end
    local b = GetActiveBucket()
    if not b or type(b.rptSyncSpecs) ~= "table" or not b.rptSyncSpecs[sourceSpecKey] then return end
    if not b.specProfiles then return end
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
-- add / remove / move / preset / replace of racials, pots & trinkets). Settings
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
