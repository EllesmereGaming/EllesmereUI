--------------------------------------------------------------------------------
--  EllesmereUI_Migration.lua
--  One-time, idempotent data migration for the profile system overhaul.
--  Loaded via TOC after EllesmereUI_Lite.lua, before EllesmereUI_Profiles.lua.
--  Runs at ADDON_LOADED time for "EllesmereUI" (before child addons init).
--------------------------------------------------------------------------------
local _, ns = ...

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = DeepCopy(v)
    end
    return copy
end

--------------------------------------------------------------------------------
--  V1: Stale SV cleanup (deferred until child addons load)
--
--  NOTE: The original V1 also copied Nameplates flat data into the
--  centralized store, but that ran too early (child addon SVs are not
--  loaded at parent ADDON_LOADED time). The flat-SV migration is now
--  handled generically inside NewDB in EllesmereUI_Lite.lua.
--
--  The stale cleanup (removing old profileKeys/profiles from child SVs)
--  is deferred to PLAYER_LOGIN when all addons are loaded.
--------------------------------------------------------------------------------
local function MigrateV1()
    -- Stale cleanup must wait until child addon SVs are loaded.
    -- Schedule it for PLAYER_LOGIN (all ADDON_LOADED events have fired by then).
    local cleanupFrame = CreateFrame("Frame")
    cleanupFrame:RegisterEvent("PLAYER_LOGIN")
    cleanupFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        local staleNames = {
            "EllesmereUIActionBarsDB",
            "EllesmereUIUnitFramesDB",
            "EllesmereUICooldownManagerDB",
            "EllesmereUIResourceBarsDB",
            "EllesmereUIAuraBuffRemindersDB",
            "EllesmereUICursorDB",
        }
        -- Before wiping, rescue any old profile data that the per-addon
        -- NewDB flat-SV migration missed (it only handles the active
        -- profile). Copy ALL old profiles into the centralized store so
        -- users updating from 5.1.8 keep every profile, not just Default.
        local db = EllesmereUIDB
        if db and db.profiles then
            for _, svName in ipairs(staleNames) do
                local sv = _G[svName]
                if sv and type(sv) == "table" and sv.profiles and type(sv.profiles) == "table" then
                    local folder = svName:match("^(.+)DB$") or svName
                    for profName, profData in pairs(sv.profiles) do
                        if type(profData) == "table" then
                            -- Ensure the centralized profile exists
                            if type(db.profiles[profName]) ~= "table" then
                                db.profiles[profName] = {}
                            end
                            if not db.profiles[profName].addons then
                                db.profiles[profName].addons = {}
                            end
                            -- Only copy if the centralized slot is still empty
                            -- (NewDB may have already migrated the active one)
                            local slot = db.profiles[profName].addons[folder]
                            if type(slot) ~= "table" or not next(slot) then
                                db.profiles[profName].addons[folder] = DeepCopy(profData)
                            end
                        end
                    end
                end
            end
        end
        -- Now safe to wipe stale keys from child SVs
        for _, svName in ipairs(staleNames) do
            local sv = _G[svName]
            if sv and type(sv) == "table" then
                sv.profileKeys = nil
                sv.profiles = nil
            end
        end
        -- Run position migration on any rescued profiles. V8-V10 ran at
        -- ADDON_LOADED before child data was available, so rescued profiles
        -- still have old TOPLEFT positions. This is safe to re-run since
        -- MigrateProfilePositions is idempotent (CENTER/CENTER passes through).
        local migrate = EllesmereUI and EllesmereUI.MigrateProfilePositions
        if migrate and db and db.profiles then
            for _, profileData in pairs(db.profiles) do
                if profileData and profileData.addons then
                    migrate(profileData)
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
--  V2: CDM spell assignments to dedicated store
--------------------------------------------------------------------------------
local function MigrateV2()
    local db = EllesmereUIDB
    if not db or not db.profiles then return end

    -- Create the dedicated spell assignment store
    if not db.spellAssignments then
        db.spellAssignments = {}
    end
    local sa = db.spellAssignments
    if not sa.specProfiles then sa.specProfiles = {} end
    if not sa.barGlows then sa.barGlows = {} end

    -- Extract from the active profile's CDM data first (authoritative source)
    local active = db.activeProfile or "Default"
    local prof = db.profiles[active]
    if prof and prof.addons then
        local cdm = prof.addons["EllesmereUICooldownManager"]
        if cdm then
            if cdm.specProfiles and next(cdm.specProfiles) then
                for specKey, data in pairs(cdm.specProfiles) do
                    if not sa.specProfiles[specKey] then
                        sa.specProfiles[specKey] = DeepCopy(data)
                    end
                end
            end
            if cdm.barGlows and next(cdm.barGlows) then
                -- barGlows is a single table, not per-spec keyed
                if not next(sa.barGlows) then
                    sa.barGlows = DeepCopy(cdm.barGlows)
                end
            end
        end
    end

    -- Strip specProfiles and barGlows from ALL profiles' CDM addon data
    for _, profData in pairs(db.profiles) do
        if profData and profData.addons then
            local cdm = profData.addons["EllesmereUICooldownManager"]
            if cdm then
                cdm.specProfiles = nil
                cdm.barGlows = nil
            end
        end
    end
end

--------------------------------------------------------------------------------
--  V3: Phantom bounds initialization
--------------------------------------------------------------------------------
local function MigrateV3()
    local db = EllesmereUIDB
    if not db then return end

    if not db.phantomBounds then
        db.phantomBounds = {}
    end
end

--------------------------------------------------------------------------------
--  V4: (removed -- superseded by per-character activeSpecKey fix)
--------------------------------------------------------------------------------
local function MigrateV4()
    -- Intentionally empty. The V4 corruption fix was replaced by moving
    -- activeSpecKey to per-character storage so shared profiles can never
    -- cause cross-character spell contamination.
end

--------------------------------------------------------------------------------
--  V5: Per-character activeSpecKey + wipe stale live bar spells
--
--  Problem: activeSpecKey and live bar trackedSpells are profile-scoped.
--  When two characters share a profile (e.g. Druid + Paladin both on
--  "Healer"), the Druid's activeSpecKey and spells bleed into the
--  Paladin's session.
--
--  Fix: Move activeSpecKey to per-character storage
--  (EllesmereUIDB.cdmActiveSpec[charKey]). Wipe stale trackedSpells /
--  extraSpells / removedSpells / dormantSpells from ALL profiles' live
--  bars. On next login, LoadSpecProfile restores the correct spells
--  from the global specProfiles store using the real current spec.
--------------------------------------------------------------------------------
local function MigrateV5()
    local db = EllesmereUIDB
    if not db then return end

    -- 1) Create per-character activeSpecKey table
    if not db.cdmActiveSpec then
        db.cdmActiveSpec = {}
    end

    -- 2) Wipe activeSpecKey and stale live bar spells from ALL profiles
    if db.profiles then
        for _, profData in pairs(db.profiles) do
            if profData and profData.addons then
                local cdm = profData.addons["EllesmereUICooldownManager"]
                if cdm then
                    -- Remove profile-scoped activeSpecKey (now per-character)
                    cdm.activeSpecKey = nil

                    -- Wipe live bar spell data (will be restored from
                    -- specProfiles on next login via LoadSpecProfile)
                    if cdm.cdmBars and cdm.cdmBars.bars then
                        for _, barData in pairs(cdm.cdmBars.bars) do
                            barData.trackedSpells = nil
                            barData.extraSpells = nil
                            barData.removedSpells = nil
                            barData.dormantSpells = nil
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
--  V6: Re-wipe live bar spells from all profiles
--
--  V5 wiped live bar spells but they may have been re-saved with
--  corrupted data during the session. Re-wipe so LoadSpecProfile
--  restores from specProfiles (which will be validated at runtime
--  by the per-spec corruption check in CDMFinishSetup).
--------------------------------------------------------------------------------
local function MigrateV6()
    local db = EllesmereUIDB
    if not db then return end

    -- Wipe live bar spells from ALL profiles
    if db.profiles then
        for profName, profData in pairs(db.profiles) do
            if profData and profData.addons then
                local cdm = profData.addons["EllesmereUICooldownManager"]
                if cdm and cdm.cdmBars and cdm.cdmBars.bars then
                    for _, barData in pairs(cdm.cdmBars.bars) do
                        barData.trackedSpells = nil
                        barData.extraSpells = nil
                        barData.removedSpells = nil
                        barData.dormantSpells = nil
                    end
                end
            end
        end
    end

    -- Reset per-spec validation flags so the runtime check runs for
    -- every spec on next login
    db.cdmSpecValidated = nil
end

--------------------------------------------------------------------------------
--  V7: Final spell data separation cleanup
--
--  Spells now live exclusively in the global store
--  (EllesmereUIDB.spellAssignments.specProfiles[specKey].barSpells[barKey]).
--  Strip ALL spell fields from every profile's live bar data so stale
--  copies can never be read by accident. Also reset validation flags
--  so every spec gets re-validated on next login.
--------------------------------------------------------------------------------
local SPELL_FIELDS_TO_STRIP = {
    "trackedSpells", "extraSpells", "removedSpells", "dormantSpells",
    "customSpells", "customSpellDurations", "customSpellGroups",
}

local function MigrateV7()
    local db = EllesmereUIDB
    if not db then return end

    if db.profiles then
        for _, profData in pairs(db.profiles) do
            if profData and profData.addons then
                local cdm = profData.addons["EllesmereUICooldownManager"]
                if cdm and cdm.cdmBars and cdm.cdmBars.bars then
                    for _, barData in pairs(cdm.cdmBars.bars) do
                        for _, field in ipairs(SPELL_FIELDS_TO_STRIP) do
                            barData[field] = nil
                        end
                    end
                end
            end
        end
    end

    -- Reset per-spec validation so runtime check runs fresh
    db.cdmSpecValidated = nil
end

--------------------------------------------------------------------------------
--  V8: Convert all existing profile positions from TOPLEFT to CENTER format
--
--  v5.2.0 changed all position storage from TOPLEFT/TOPLEFT-relative to
--  CENTER/CENTER-relative. MigrateProfilePositions() was written for this
--  but only called during profile IMPORT. Users updating from 5.1.8 had
--  their old TOPLEFT positions interpreted as CENTER offsets, causing
--  everything to shift dramatically ("whole UI exploded").
--
--  This migration calls MigrateProfilePositions on every stored profile.
--  Positions already in CENTER/CENTER format are passed through unchanged,
--  so profiles created in 5.2.0+ are unaffected.
--
--  V9 re-runs the same migration because V8 in 5.2.3 silently failed:
--  MigrateProfilePositions was inside a deferred block and did not exist
--  at ADDON_LOADED time. The function has been moved to file scope so it
--  is now available when the migration runner executes.
--------------------------------------------------------------------------------
local function MigratePositions()
    local db = EllesmereUIDB
    if not db or not db.profiles then return end

    local migrate = EllesmereUI and EllesmereUI.MigrateProfilePositions
    if not migrate then return end

    for _, profileData in pairs(db.profiles) do
        if profileData and profileData.addons then
            migrate(profileData)
        end
    end
end

local function MigrateV8()
    MigratePositions()
end

local function MigrateV9()
    MigratePositions()
end

--  V10 re-runs position migration with updated ConvertPos that stamps
--  CENTER/CENTER on positions missing a point field (saved by 5.2.0+
--  code that omitted the field). V8/V9 skipped these entries.
local function MigrateV10()
    MigratePositions()
end

--------------------------------------------------------------------------------
--  Migration runner (idempotent, version-stamped)
--------------------------------------------------------------------------------
local function RunMigration()
    if not EllesmereUIDB then return end  -- fresh install, nothing to migrate

    local ver = EllesmereUIDB._migrationVersion or 0

    if ver < 1 then
        MigrateV1()
        EllesmereUIDB._migrationVersion = 1
    end

    if ver < 2 then
        MigrateV2()
        EllesmereUIDB._migrationVersion = 2
    end

    if ver < 3 then
        MigrateV3()
        EllesmereUIDB._migrationVersion = 3
    end

    if ver < 4 then
        MigrateV4()
        EllesmereUIDB._migrationVersion = 4
    end

    if ver < 5 then
        MigrateV5()
        EllesmereUIDB._migrationVersion = 5
    end

    if ver < 6 then
        MigrateV6()
        EllesmereUIDB._migrationVersion = 6
    end

    if ver < 7 then
        MigrateV7()
        EllesmereUIDB._migrationVersion = 7
    end

    if ver < 8 then
        MigrateV8()
        EllesmereUIDB._migrationVersion = 8
    end

    if ver < 9 then
        MigrateV9()
        EllesmereUIDB._migrationVersion = 9
    end

    if ver < 10 then
        MigrateV10()
        EllesmereUIDB._migrationVersion = 10
    end
end

--------------------------------------------------------------------------------
--  Hook into ADDON_LOADED for the parent addon (fires before child addons)
--------------------------------------------------------------------------------
local migrationFrame = CreateFrame("Frame")
migrationFrame:RegisterEvent("ADDON_LOADED")
migrationFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "EllesmereUI" then return end
    self:UnregisterEvent("ADDON_LOADED")
    RunMigration()
end)
