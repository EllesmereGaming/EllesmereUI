-------------------------------------------------------------------------------
--  EllesmereUI_Profiles.lua
--
--  Global profile system: import/export, presets, spec assignment.
--  Handles serialization (LibDeflate + custom serializer) and profile
--  management across all EllesmereUI addons.
--
--  Load order (via TOC):
--    1. Libs/LibDeflate.lua
--    2. EllesmereUI_Lite.lua
--    3. EllesmereUI.lua
--    4. EllesmereUI_Widgets.lua
--    5. EllesmereUI_Presets.lua
--    6. EllesmereUI_Profiles.lua  -- THIS FILE
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI

-------------------------------------------------------------------------------
--  LibDeflate reference (loaded before us via TOC)
--  LibDeflate registers via LibStub, not as a global, so use LibStub to get it.
-------------------------------------------------------------------------------
local LibDeflate = LibStub and LibStub("LibDeflate", true) or _G.LibDeflate

-------------------------------------------------------------------------------
--  Reload popup: uses Blizzard StaticPopup so the button click is a hardware
--  event and ReloadUI() is not blocked as a protected function call.
-------------------------------------------------------------------------------
StaticPopupDialogs["EUI_PROFILE_RELOAD"] = {
    text = "EllesmereUI Profile switched. Reload UI to apply?",
    button1 = "Reload Now",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-------------------------------------------------------------------------------
--  Addon registry: display-order list of all managed addons.
--  Each entry: { folder, display, svName }
--    folder  = addon folder name (matches _dbRegistry key)
--    display = human-readable name for the Profiles UI
--    svName  = SavedVariables name (e.g. "EllesmereUINameplatesDB")
--
--  All addons use _dbRegistry for profile access. Order matters for UI display.
-------------------------------------------------------------------------------
local ADDON_DB_MAP = {
    { folder = "EllesmereUINameplates",        display = "Nameplates",         svName = "EllesmereUINameplatesDB"        },
    { folder = "EllesmereUIActionBars",        display = "Action Bars",        svName = "EllesmereUIActionBarsDB"        },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",        svName = "EllesmereUIUnitFramesDB"        },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",   svName = "EllesmereUICooldownManagerDB"   },
    { folder = "EllesmereUIResourceBars",      display = "Resource Bars",      svName = "EllesmereUIResourceBarsDB"      },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders", svName = "EllesmereUIAuraBuffRemindersDB" },
    { folder = "EllesmereUIBasics",            display = "Basics",             svName = "EllesmereUIBasicsDB"            },
}
EllesmereUI._ADDON_DB_MAP = ADDON_DB_MAP

-------------------------------------------------------------------------------
--  Serializer: Lua table <-> string (no AceSerializer dependency)
--  Handles: string, number, boolean, nil, table (nested), color tables
-------------------------------------------------------------------------------
local Serializer = {}

local function SerializeValue(v, parts)
    local t = type(v)
    if t == "string" then
        parts[#parts + 1] = "s"
        -- Length-prefixed to avoid delimiter issues
        parts[#parts + 1] = #v
        parts[#parts + 1] = ":"
        parts[#parts + 1] = v
    elseif t == "number" then
        parts[#parts + 1] = "n"
        parts[#parts + 1] = tostring(v)
        parts[#parts + 1] = ";"
    elseif t == "boolean" then
        parts[#parts + 1] = v and "T" or "F"
    elseif t == "nil" then
        parts[#parts + 1] = "N"
    elseif t == "table" then
        parts[#parts + 1] = "{"
        -- Serialize array part first (integer keys 1..n)
        local n = #v
        for i = 1, n do
            SerializeValue(v[i], parts)
        end
        -- Then hash part (non-integer keys, or integer keys > n)
        for k, val in pairs(v) do
            local kt = type(k)
            if kt == "number" and k >= 1 and k <= n and k == math.floor(k) then
                -- Already serialized in array part
            else
                parts[#parts + 1] = "K"
                SerializeValue(k, parts)
                SerializeValue(val, parts)
            end
        end
        parts[#parts + 1] = "}"
    end
end

function Serializer.Serialize(tbl)
    local parts = {}
    SerializeValue(tbl, parts)
    return table.concat(parts)
end

-- Deserializer
local function DeserializeValue(str, pos)
    local tag = str:sub(pos, pos)
    if tag == "s" then
        -- Find the colon after the length
        local colonPos = str:find(":", pos + 1, true)
        if not colonPos then return nil, pos end
        local len = tonumber(str:sub(pos + 1, colonPos - 1))
        if not len then return nil, pos end
        local val = str:sub(colonPos + 1, colonPos + len)
        return val, colonPos + len + 1
    elseif tag == "n" then
        local semi = str:find(";", pos + 1, true)
        if not semi then return nil, pos end
        return tonumber(str:sub(pos + 1, semi - 1)), semi + 1
    elseif tag == "T" then
        return true, pos + 1
    elseif tag == "F" then
        return false, pos + 1
    elseif tag == "N" then
        return nil, pos + 1
    elseif tag == "{" then
        local tbl = {}
        local idx = 1
        local p = pos + 1
        while p <= #str do
            local c = str:sub(p, p)
            if c == "}" then
                return tbl, p + 1
            elseif c == "K" then
                -- Key-value pair
                local key, val
                key, p = DeserializeValue(str, p + 1)
                val, p = DeserializeValue(str, p)
                if key ~= nil then
                    tbl[key] = val
                end
            else
                -- Array element
                local val
                val, p = DeserializeValue(str, p)
                tbl[idx] = val
                idx = idx + 1
            end
        end
        return tbl, p
    end
    return nil, pos + 1
end

function Serializer.Deserialize(str)
    if not str or #str == 0 then return nil end
    local val, _ = DeserializeValue(str, 1)
    return val
end

EllesmereUI._Serializer = Serializer

-------------------------------------------------------------------------------
--  Deep copy utility
-------------------------------------------------------------------------------
local function DeepCopy(src, seen)
    if type(src) ~= "table" then return src end
    if seen and seen[src] then return seen[src] end
    if not seen then seen = {} end
    local copy = {}
    seen[src] = copy
    for k, v in pairs(src) do
        -- Skip frame references and other userdata that can't be serialized
        if type(v) ~= "userdata" and type(v) ~= "function" then
            copy[k] = DeepCopy(v, seen)
        end
    end
    return copy
end

local function DeepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            DeepMerge(dst[k], v)
        else
            dst[k] = DeepCopy(v)
        end
    end
end

EllesmereUI._DeepCopy = DeepCopy




-------------------------------------------------------------------------------
--  Profile DB helpers
--  Profiles are stored in EllesmereUIDB.profiles = { [name] = profileData }
--  profileData = {
--      addons = { [folderName] = <snapshot of that addon's profile table> },
--      fonts  = <snapshot of EllesmereUIDB.fonts>,
--      customColors = <snapshot of EllesmereUIDB.customColors>,
--  }
--  EllesmereUIDB.activeProfile = "Default"  (name of active profile)
--  EllesmereUIDB.profileOrder  = { "Default", ... }
--  EllesmereUIDB.specProfiles  = { [specID] = "profileName" }
-------------------------------------------------------------------------------
local function GetProfilesDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if not EllesmereUIDB.profileOrder then EllesmereUIDB.profileOrder = {} end
    if not EllesmereUIDB.specProfiles then EllesmereUIDB.specProfiles = {} end
    return EllesmereUIDB
end
EllesmereUI.GetProfilesDB = GetProfilesDB

-------------------------------------------------------------------------------
--  Anchor offset format conversion
--
--  Anchor offsets were originally stored relative to the target's center
--  (format version 0/nil). The current system stores them relative to
--  stable edges (format version 1):
--    TOP/BOTTOM: offsetX relative to target LEFT edge
--    LEFT/RIGHT: offsetY relative to target TOP edge
--
--- Check if an addon is loaded
local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

--- Re-point all db.profile references to the given profile name.
--- Called when switching profiles so addons see the new data immediately.
local function RepointAllDBs(profileName)
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if type(EllesmereUIDB.profiles[profileName]) ~= "table" then
        EllesmereUIDB.profiles[profileName] = {}
    end
    local profileData = EllesmereUIDB.profiles[profileName]
    if not profileData.addons then profileData.addons = {} end

    local registry = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
    if not registry then return end
    for _, db in ipairs(registry) do
        local folder = db.folder
        if folder then
            if type(profileData.addons[folder]) ~= "table" then
                profileData.addons[folder] = {}
            end
            db.profile = profileData.addons[folder]
            db._profileName = profileName
            -- Re-merge defaults so new profile has all keys
            if db._profileDefaults then
                EllesmereUI.Lite.DeepMergeDefaults(db.profile, db._profileDefaults)
            end
        end
    end
    -- Restore unlock layout from the profile.
    -- If the profile has no unlockLayout yet (e.g. created before this key
    -- existed), leave the live unlock data untouched so the current
    -- positions are preserved. Only restore when the profile explicitly
    -- contains layout data from a previous save.
    local ul = profileData.unlockLayout
    if ul then
        EllesmereUIDB.unlockAnchors     = DeepCopy(ul.anchors      or {})
        EllesmereUIDB.unlockWidthMatch  = DeepCopy(ul.widthMatch   or {})
        EllesmereUIDB.unlockHeightMatch = DeepCopy(ul.heightMatch  or {})
        EllesmereUIDB.phantomBounds     = DeepCopy(ul.phantomBounds or {})
    end
    -- Seed castbar anchor defaults if the profile predates them.
    -- These follow the same per-profile unlockLayout system as all
    -- other elements — this just ensures old profiles get the defaults.
    do
        local anchors = EllesmereUIDB.unlockAnchors
        local wMatch  = EllesmereUIDB.unlockWidthMatch
        if anchors and wMatch then
            local CB_DEFAULTS = {
                { cb = "playerCastbar", parent = "player" },
                { cb = "targetCastbar", parent = "target" },
                { cb = "focusCastbar",  parent = "focus" },
            }
            for _, def in ipairs(CB_DEFAULTS) do
                if not anchors[def.cb] then
                    anchors[def.cb] = { target = def.parent, side = "BOTTOM" }
                end
                if not wMatch[def.cb] then
                    wMatch[def.cb] = def.parent
                end
            end
        end
    end
    -- Restore fonts and custom colors from the profile
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        for k, v in pairs(profileData.fonts) do fontsDB[k] = DeepCopy(v) end
        if fontsDB.global      == nil then fontsDB.global      = "Expressway" end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow"     end
    end
    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k in pairs(colorsDB) do colorsDB[k] = nil end
        for k, v in pairs(profileData.customColors) do colorsDB[k] = DeepCopy(v) end
    end
end

-------------------------------------------------------------------------------
--  ResolveSpecProfile
--
--  Single authoritative function that resolves the current spec's target
--  profile name. Used by both PreSeedSpecProfile (before OnEnable) and the
--  runtime spec event handler.
--
--  Resolution order:
--    1. Cached spec from lastSpecByChar (reliable across sessions)
--    2. Live GetSpecialization() API (available after ADDON_LOADED for
--       returning characters, may be nil for brand-new characters)
--
--  Returns: targetProfileName, resolvedSpecID, charKey  -- or nil if no
--           spec assignment exists or spec cannot be resolved yet.
-------------------------------------------------------------------------------
local function ResolveSpecProfile()
    if not EllesmereUIDB then return nil end
    local specProfiles = EllesmereUIDB.specProfiles
    if not specProfiles or not next(specProfiles) then return nil end

    local charKey = UnitName("player") .. " - " .. GetRealmName()
    if not EllesmereUIDB.lastSpecByChar then
        EllesmereUIDB.lastSpecByChar = {}
    end

    -- Prefer cached spec from last session (always reliable)
    local resolvedSpecID = EllesmereUIDB.lastSpecByChar[charKey]

    -- Fall back to live API if no cached value
    if not resolvedSpecID then
        local specIdx = GetSpecialization and GetSpecialization()
        if specIdx and specIdx > 0 then
            local liveSpecID = GetSpecializationInfo(specIdx)
            if liveSpecID then
                resolvedSpecID = liveSpecID
                EllesmereUIDB.lastSpecByChar[charKey] = resolvedSpecID
            end
        end
    end

    if not resolvedSpecID then return nil end

    local targetProfile = specProfiles[resolvedSpecID]
    if not targetProfile then return nil end

    local profiles = EllesmereUIDB.profiles
    if not profiles or not profiles[targetProfile] then return nil end

    return targetProfile, resolvedSpecID, charKey
end

-------------------------------------------------------------------------------
--  Spec profile pre-seed
--
--  Runs once just before child addon OnEnable calls, after all OnInitialize
--  calls have completed (so all NewDB calls have run).
--  At this point the spec API is available, so we can resolve the current
--  spec and re-point all db.profile references to the correct profile table
--  in the central store before any addon builds its UI.
--
--  This is the sole pre-OnEnable resolution point. NewDB reads activeProfile
--  as-is (defaults to "Default" or whatever was saved from last session).
-------------------------------------------------------------------------------

--- Called by EllesmereUI_Lite just before child addon OnEnable calls fire.
--- Uses ResolveSpecProfile() to determine the correct profile, then
--- re-points all db.profile references via RepointAllDBs.
function EllesmereUI.PreSeedSpecProfile()
    local targetProfile, resolvedSpecID = ResolveSpecProfile()
    if not targetProfile then
        -- No spec assignment resolved; lock auto-save if spec profiles exist
        if EllesmereUIDB and EllesmereUIDB.specProfiles and next(EllesmereUIDB.specProfiles) then
            EllesmereUI._profileSaveLocked = true
        end
        return
    end

    EllesmereUIDB.activeProfile = targetProfile
    RepointAllDBs(targetProfile)
    EllesmereUI._preSeedComplete = true
end

--- Get the live profile table for an addon.
--- All addons use _dbRegistry (which points into
--- EllesmereUIDB.profiles[active].addons[folder]).
local function GetAddonProfile(entry)
    if EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry then
        for _, db in ipairs(EllesmereUI.Lite._dbRegistry) do
            if db.folder == entry.folder then
                return db.profile
            end
        end
    end
    return nil
end

--- Snapshot the current state of all loaded addons into a profile data table
function EllesmereUI.SnapshotAllAddons()
    local data = { addons = {} }
    for _, entry in ipairs(ADDON_DB_MAP) do
        if IsAddonLoaded(entry.folder) then
            local profile = GetAddonProfile(entry)
            if profile then
                data.addons[entry.folder] = DeepCopy(profile)
            end
        end
    end
    -- Include global font and color settings
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    local cc = EllesmereUI.GetCustomColorsDB()
    data.customColors = DeepCopy(cc)
    -- Include unlock mode layout data (anchors, size matches)
    if EllesmereUIDB then
        data.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end
    return data
end

--[[ ADDON-SPECIFIC EXPORT DISABLED
--- Snapshot a single addon's profile
function EllesmereUI.SnapshotAddon(folderName)
    for _, entry in ipairs(ADDON_DB_MAP) do
        if entry.folder == folderName and IsAddonLoaded(folderName) then
            local profile = GetAddonProfile(entry)
            if profile then return DeepCopy(profile) end
        end
    end
    return nil
end

--- Snapshot multiple addons (for multi-addon export)
function EllesmereUI.SnapshotAddons(folderList)
    local data = { addons = {} }
    for _, folderName in ipairs(folderList) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName and IsAddonLoaded(folderName) then
                local profile = GetAddonProfile(entry)
                if profile then
                    data.addons[folderName] = DeepCopy(profile)
                end
                break
            end
        end
    end
    -- Always include fonts and colors
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    data.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    -- Include unlock mode layout data
    if EllesmereUIDB then
        data.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end
    return data
end
--]] -- END ADDON-SPECIFIC EXPORT DISABLED

--- Apply imported profile data into the live db.profile tables.
--- Used by import to write external data into the active profile.
--- For normal profile switching, use SwitchProfile (which calls RepointAllDBs).
function EllesmereUI.ApplyProfileData(profileData)
    if not profileData or not profileData.addons then return end

    -- Build a folder -> db lookup from the Lite registry
    local dbByFolder = {}
    if EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry then
        for _, db in ipairs(EllesmereUI.Lite._dbRegistry) do
            if db.folder then dbByFolder[db.folder] = db end
        end
    end

    for _, entry in ipairs(ADDON_DB_MAP) do
        local snap = profileData.addons[entry.folder]
        if snap and IsAddonLoaded(entry.folder) then
            local db = dbByFolder[entry.folder]
            if db then
                local profile = db.profile
                -- TBB and barGlows are spec-specific (in spellAssignments),
                -- not in profile. No save/restore needed on profile switch.
                for k in pairs(profile) do profile[k] = nil end
                for k, v in pairs(snap) do profile[k] = DeepCopy(v) end
                if db._profileDefaults then
                    EllesmereUI.Lite.DeepMergeDefaults(profile, db._profileDefaults)
                end
                -- Ensure per-unit bg colors are never nil after import
                if entry.folder == "EllesmereUIUnitFrames" then
                    local UF_UNITS = { "player", "target", "focus", "boss", "pet", "totPet" }
                    local DEF_BG = 17/255
                    for _, uKey in ipairs(UF_UNITS) do
                        local s = profile[uKey]
                        if s and s.customBgColor == nil then
                            s.customBgColor = { r = DEF_BG, g = DEF_BG, b = DEF_BG }
                        end
                    end
                end
            end
        end
    end
    -- Apply fonts and colors
    do
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        if profileData.fonts then
            for k, v in pairs(profileData.fonts) do fontsDB[k] = DeepCopy(v) end
        end
        if fontsDB.global      == nil then fontsDB.global      = "Expressway" end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow"     end
    end
    do
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k in pairs(colorsDB) do colorsDB[k] = nil end
        if profileData.customColors then
            for k, v in pairs(profileData.customColors) do colorsDB[k] = DeepCopy(v) end
        end
    end
    -- Restore unlock mode layout data
    if EllesmereUIDB then
        local ul = profileData.unlockLayout
        if ul then
            EllesmereUIDB.unlockAnchors     = DeepCopy(ul.anchors      or {})
            EllesmereUIDB.unlockWidthMatch  = DeepCopy(ul.widthMatch   or {})
            EllesmereUIDB.unlockHeightMatch = DeepCopy(ul.heightMatch  or {})
            EllesmereUIDB.phantomBounds     = DeepCopy(ul.phantomBounds or {})
        end
        -- If profile predates unlockLayout, leave live data untouched
    end
end

--- Trigger live refresh on all loaded addons after a profile apply.
function EllesmereUI.RefreshAllAddons()
    -- ResourceBars (full rebuild)
    if _G._ERB_Apply then _G._ERB_Apply() end
    -- CDM: skip during spec-profile switch. CDM's own PLAYER_SPECIALIZATION_CHANGED
    -- handler will update the active spec key and rebuild with the correct spec
    -- spells via OnSpecChanged's deferred FullCDMRebuild. Running it here
    -- would use a stale active spec key (not yet updated by CDM) and show the
    -- wrong spec's spells until the deferred rebuild overwrites them.
    if not EllesmereUI._specProfileSwitching then
        if _G._ECME_LoadSpecProfile and _G._ECME_GetCurrentSpecKey then
            local curKey = _G._ECME_GetCurrentSpecKey()
            if curKey then _G._ECME_LoadSpecProfile(curKey) end
        end
        if _G._ECME_Apply then _G._ECME_Apply() end
    end
    -- Cursor (style + position)
    if _G._ECL_Apply then _G._ECL_Apply() end
    if _G._ECL_ApplyTrail then _G._ECL_ApplyTrail() end
    if _G._ECL_ApplyGCDCircle then _G._ECL_ApplyGCDCircle() end
    if _G._ECL_ApplyCastCircle then _G._ECL_ApplyCastCircle() end
    -- AuraBuffReminders (refresh + position)
    if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
    if _G._EABR_ApplyUnlockPos then _G._EABR_ApplyUnlockPos() end
    -- ActionBars (style + layout + position)
    if _G._EAB_Apply then _G._EAB_Apply() end
    -- UnitFrames (style + layout + position)
    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    -- Nameplates
    if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
    -- Global class/power colors (updates oUF, nameplates, raid frames)
    if EllesmereUI.ApplyColorsToOUF then EllesmereUI.ApplyColorsToOUF() end
    -- After all addons have rebuilt and positioned their frames from
    -- db.profile.positions, re-apply centralized grow-direction positioning
    -- (handles lazy migration of imported TOPLEFT positions to CENTER format)
    -- and resync anchor offsets so the anchor relationships stay correct for
    -- future drags. Triple-deferred so it runs AFTER debounced rebuilds have
    -- completed and frames are at final positions.
    C_Timer.After(0, function()
        C_Timer.After(0, function()
            C_Timer.After(0, function()
                -- Skip during spec-driven profile switch. _applySavedPositions
                -- iterates registered elements and calls each one's
                -- applyPosition callback, which for CDM bars is BuildAllCDMBars.
                -- That triggers a rebuild + ApplyAllWidthHeightMatches before
                -- CDMFinishSetup has had a chance to run, propagating
                -- transient mid-rebuild sizes through width-match and
                -- corrupting iconSize in saved variables. CDM's OnSpecChanged
                -- handles the rebuild at spec_change + 0.5s; other addons'
                -- positions don't change on spec swap so skipping is safe.
                if EllesmereUI._specProfileSwitching then return end
                -- Re-apply centralized positions (migrates legacy formats)
                if EllesmereUI._applySavedPositions then
                    EllesmereUI._applySavedPositions()
                end
                -- Resync anchor offsets (does NOT move frames)
                if EllesmereUI.ResyncAnchorOffsets then
                    EllesmereUI.ResyncAnchorOffsets()
                end
            end)
        end)
    end)
    -- Note: _specProfileSwitching is cleared by CDM's OnSpecChanged after
    -- its deferred rebuild settles -- not here. CDMFinishSetup runs at
    -- spec_change + 0.5s, which is well after this triple-deferred chain
    -- (~3 frames = ~50ms), so clearing the flag here would let width-match
    -- propagation run against transient mid-rebuild bar sizes once CDM
    -- starts rebuilding and corrupt iconSize in saved variables.
end

-------------------------------------------------------------------------------
--  Profile Keybinds
--  Each profile can have a key bound to switch to it instantly.
--  Stored in EllesmereUIDB.profileKeybinds = { ["Name"] = "CTRL-1", ... }
--  Uses hidden buttons + SetOverrideBindingClick, same pattern as Party Mode.
-------------------------------------------------------------------------------
local _profileBindBtns = {} -- [profileName] = hidden Button

local function GetProfileKeybinds()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profileKeybinds then EllesmereUIDB.profileKeybinds = {} end
    return EllesmereUIDB.profileKeybinds
end

local function EnsureProfileBindBtn(profileName)
    if _profileBindBtns[profileName] then return _profileBindBtns[profileName] end
    local safeName = profileName:gsub("[^%w]", "")
    local btn = CreateFrame("Button", "EllesmereUIProfileBind_" .. safeName, UIParent)
    btn:Hide()
    btn:SetScript("OnClick", function()
        local active = EllesmereUI.GetActiveProfileName()
        if active == profileName then return end
        local _, profiles = EllesmereUI.GetProfileList()
        local fontWillChange = EllesmereUI.ProfileChangesFont(profiles and profiles[profileName])
        EllesmereUI.SwitchProfile(profileName)
        EllesmereUI.RefreshAllAddons()
        if fontWillChange then
            EllesmereUI:ShowConfirmPopup({
                title       = "Reload Required",
                message     = "Font changed. A UI reload is needed to apply the new font.",
                confirmText = "Reload Now",
                cancelText  = "Later",
                onConfirm   = function() ReloadUI() end,
            })
        else
            EllesmereUI:RefreshPage()
        end
    end)
    _profileBindBtns[profileName] = btn
    return btn
end

function EllesmereUI.SetProfileKeybind(profileName, key)
    local kb = GetProfileKeybinds()
    -- Clear old binding for this profile
    local oldKey = kb[profileName]
    local btn = EnsureProfileBindBtn(profileName)
    if oldKey then
        ClearOverrideBindings(btn)
    end
    if key then
        kb[profileName] = key
        SetOverrideBindingClick(btn, true, key, btn:GetName())
    else
        kb[profileName] = nil
    end
end

function EllesmereUI.GetProfileKeybind(profileName)
    local kb = GetProfileKeybinds()
    return kb[profileName]
end

--- Called on login to restore all saved profile keybinds
function EllesmereUI.RestoreProfileKeybinds()
    local kb = GetProfileKeybinds()
    for profileName, key in pairs(kb) do
        if key then
            local btn = EnsureProfileBindBtn(profileName)
            SetOverrideBindingClick(btn, true, key, btn:GetName())
        end
    end
end

--- Update keybind references when a profile is renamed
function EllesmereUI.OnProfileRenamed(oldName, newName)
    local kb = GetProfileKeybinds()
    local key = kb[oldName]
    if key then
        local oldBtn = _profileBindBtns[oldName]
        if oldBtn then ClearOverrideBindings(oldBtn) end
        _profileBindBtns[oldName] = nil
        kb[oldName] = nil
        kb[newName] = key
        local newBtn = EnsureProfileBindBtn(newName)
        SetOverrideBindingClick(newBtn, true, key, newBtn:GetName())
    end
end

--- Clean up keybind when a profile is deleted
function EllesmereUI.OnProfileDeleted(profileName)
    local kb = GetProfileKeybinds()
    if kb[profileName] then
        local btn = _profileBindBtns[profileName]
        if btn then ClearOverrideBindings(btn) end
        _profileBindBtns[profileName] = nil
        kb[profileName] = nil
    end
end

--- Returns true if applying profileData would change the global font or outline mode.
--- Used to decide whether to show a reload popup after a profile switch.
function EllesmereUI.ProfileChangesFont(profileData)
    if not profileData or not profileData.fonts then return false end
    local cur = EllesmereUI.GetFontsDB()
    local curFont    = cur.global      or "Expressway"
    local curOutline = cur.outlineMode or "shadow"
    local newFont    = profileData.fonts.global      or "Expressway"
    local newOutline = profileData.fonts.outlineMode or "shadow"
    -- "none" and "shadow" are both drop-shadow (no outline) -- treat as identical
    if curOutline == "none" then curOutline = "shadow" end
    if newOutline == "none" then newOutline = "shadow" end
    return curFont ~= newFont or curOutline ~= newOutline
end

--[[ ADDON-SPECIFIC EXPORT DISABLED
--- Apply a partial profile (specific addons only) by merging into active
function EllesmereUI.ApplyPartialProfile(profileData)
    if not profileData or not profileData.addons then return end
    for folderName, snap in pairs(profileData.addons) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName and IsAddonLoaded(folderName) then
                local profile = GetAddonProfile(entry)
                if profile then
                    for k, v in pairs(snap) do
                        profile[k] = DeepCopy(v)
                    end
                end
                break
            end
        end
    end
    -- Always apply fonts and colors if present
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k, v in pairs(profileData.fonts) do
            fontsDB[k] = DeepCopy(v)
        end
    end
    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k, v in pairs(profileData.customColors) do
            colorsDB[k] = DeepCopy(v)
        end
    end
end
--]] -- END ADDON-SPECIFIC EXPORT DISABLED

-------------------------------------------------------------------------------
--  Export / Import
--  Format: !EUI_<base64 encoded compressed serialized data>
--  The data table contains:
--    { version = 3, type = "full"|"partial", data = profileData }
-------------------------------------------------------------------------------
local EXPORT_PREFIX = "!EUI_"

function EllesmereUI.ExportProfile(profileName)
    local db = GetProfilesDB()
    local profileData = db.profiles[profileName]
    if not profileData then return nil end
    -- If exporting the active profile, ensure fonts/colors/layout are current
    if profileName == (db.activeProfile or "Default") then
        profileData.fonts = DeepCopy(EllesmereUI.GetFontsDB())
        profileData.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
        profileData.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end
    local exportData = DeepCopy(profileData)
    -- Exclude spec-specific data from export (bar glows, tracking bars)
    exportData.trackedBuffBars = nil
    exportData.tbbPositions = nil
    -- Include spell assignments from the dedicated store on the export copy
    -- (barGlows and trackedBuffBars excluded from export -- spec-specific)
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    if sa then
        local spCopy = DeepCopy(sa.specProfiles or {})
        -- Strip spec-specific non-exportable data from each spec profile
        for _, prof in pairs(spCopy) do
            prof.barGlows = nil
            prof.trackedBuffBars = nil
            prof.tbbPositions = nil
        end
        exportData.spellAssignments = {
            specProfiles = spCopy,
        }
    end
    local payload = { version = 3, type = "full", data = exportData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

--[[ ADDON-SPECIFIC EXPORT DISABLED
function EllesmereUI.ExportAddons(folderList)
    local profileData = EllesmereUI.SnapshotAddons(folderList)
    local sw, sh = GetPhysicalScreenSize()
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    local payload = { version = 3, type = "partial", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end
--]] -- END ADDON-SPECIFIC EXPORT DISABLED

-------------------------------------------------------------------------------
--  CDM spec profile helpers for export/import spec picker
-------------------------------------------------------------------------------

--- Get info about which specs have data in the CDM specProfiles table.
--- Returns: { { key="250", name="Blood", icon=..., hasData=true }, ... }
--- Includes ALL specs for the player's class, with hasData indicating
--- whether specProfiles contains data for that spec.
function EllesmereUI.GetCDMSpecInfo()
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    local specProfiles = sa and sa.specProfiles or {}
    local result = {}
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID, sName, _, sIcon = GetSpecializationInfo(i)
        if specID then
            local key = tostring(specID)
            result[#result + 1] = {
                key     = key,
                name    = sName or ("Spec " .. key),
                icon    = sIcon,
                hasData = specProfiles[key] ~= nil,
            }
        end
    end
    return result
end

--- Filter specProfiles in an export snapshot to only include selected specs.
--- Reads from snapshot.spellAssignments (the dedicated store copy on the payload).
--- Modifies the snapshot in-place. selectedSpecs = { ["250"] = true, ... }
function EllesmereUI.FilterExportSpecProfiles(snapshot, selectedSpecs)
    if not snapshot or not snapshot.spellAssignments then return end
    local sp = snapshot.spellAssignments.specProfiles
    if not sp then return end
    for key in pairs(sp) do
        if not selectedSpecs[key] then
            sp[key] = nil
        end
    end
end

--- After a profile import, apply only selected specs' specProfiles from the
--- imported data into the dedicated spell assignment store.
--- importedSpellAssignments = the spellAssignments object from the import payload.
--- selectedSpecs = { ["250"] = true, ... }
function EllesmereUI.ApplyImportedSpecProfiles(importedSpellAssignments, selectedSpecs)
    if not importedSpellAssignments or not importedSpellAssignments.specProfiles then return end
    if not EllesmereUIDB.spellAssignments then
        EllesmereUIDB.spellAssignments = { specProfiles = {} }
    end
    local sa = EllesmereUIDB.spellAssignments
    if not sa.specProfiles then sa.specProfiles = {} end
    for key, data in pairs(importedSpellAssignments.specProfiles) do
        if selectedSpecs[key] then
            sa.specProfiles[key] = DeepCopy(data)
        end
    end
    -- If the current spec was imported, reload it live
    if _G._ECME_GetCurrentSpecKey and _G._ECME_LoadSpecProfile then
        local currentKey = _G._ECME_GetCurrentSpecKey()
        if currentKey and selectedSpecs[currentKey] then
            _G._ECME_LoadSpecProfile(currentKey)
        end
    end
end

--- Get the list of spec keys that have data in imported spell assignments.
--- Returns same format as GetCDMSpecInfo but based on imported data.
--- Accepts either the new spellAssignments format or legacy CDM snapshot.
function EllesmereUI.GetImportedCDMSpecInfo(importedSpellAssignments)
    if not importedSpellAssignments then return {} end
    -- Support both new format (spellAssignments.specProfiles) and legacy (cdmSnap.specProfiles)
    local specProfiles = importedSpellAssignments.specProfiles
    if not specProfiles then return {} end
    local result = {}
    for specKey in pairs(specProfiles) do
        local specID = tonumber(specKey)
        local name, icon
        if specID and specID > 0 and GetSpecializationInfoByID then
            local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
            name = sName
            icon = sIcon
        end
        result[#result + 1] = {
            key     = specKey,
            name    = name or ("Spec " .. specKey),
            icon    = icon,
            hasData = true,
        }
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

-------------------------------------------------------------------------------
--  CDM Spec Picker Popup
--  Thin wrapper around ShowSpecAssignPopup for CDM export/import.
--
--  opts = {
--      title    = string,
--      subtitle = string,
--      confirmText = string (button label),
--      specs    = { { key, name, icon, hasData, checked }, ... },
--      onConfirm = function(selectedSpecs)  -- { ["250"]=true, ... }
--      onCancel  = function() (optional)
--  }
--  specs[i].hasData = false grays out the row and shows disabled tooltip.
--  specs[i].checked = initial checked state (only for hasData=true rows).
-------------------------------------------------------------------------------
do
    -- Dummy db/dbKey/presetKey for the assignments table
    local dummyDB = { _cdmPick = { _cdm = {} } }

    function EllesmereUI:ShowCDMSpecPickerPopup(opts)
        local specs = opts.specs or {}

        -- Reset assignments
        dummyDB._cdmPick._cdm = {}

        -- Build a set of specIDs that are in the caller's list
        local knownSpecs = {}
        for _, sp in ipairs(specs) do
            local numID = tonumber(sp.key)
            if numID then knownSpecs[numID] = sp end
        end

        -- Build disabledSpecs map (specID -> tooltip string)
        -- Any spec NOT in the caller's list gets disabled too
        local disabledSpecs = {}
        -- Build preCheckedSpecs set
        local preCheckedSpecs = {}

        for _, sp in ipairs(specs) do
            local numID = tonumber(sp.key)
            if numID then
                if not sp.hasData then
                    disabledSpecs[numID] = "Create a CDM spell layout for this spec first"
                end
                if sp.checked then
                    preCheckedSpecs[numID] = true
                end
            end
        end

        -- Disable all specs not in the caller's list (other classes, etc.)
        local SPEC_DATA = EllesmereUI._SPEC_DATA
        if SPEC_DATA then
            for _, cls in ipairs(SPEC_DATA) do
                for _, spec in ipairs(cls.specs) do
                    if not knownSpecs[spec.id] then
                        disabledSpecs[spec.id] = "Not available for this operation"
                    end
                end
            end
        end

        EllesmereUI:ShowSpecAssignPopup({
            db              = dummyDB,
            dbKey           = "_cdmPick",
            presetKey       = "_cdm",
            title           = opts.title,
            subtitle        = opts.subtitle,
            buttonText      = opts.confirmText or "Confirm",
            disabledSpecs   = disabledSpecs,
            preCheckedSpecs = preCheckedSpecs,
            onConfirm       = opts.onConfirm and function(assignments)
                -- Convert numeric specID assignments back to string keys
                local selected = {}
                for specID in pairs(assignments) do
                    selected[tostring(specID)] = true
                end
                opts.onConfirm(selected)
            end,
            onCancel        = opts.onCancel,
        })
    end
end

function EllesmereUI.ExportCurrentProfile(selectedSpecs)
    local profileData = EllesmereUI.SnapshotAllAddons()
    -- Include spell assignments from the dedicated store
    local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
    if sa then
        profileData.spellAssignments = {
            specProfiles = DeepCopy(sa.specProfiles or {}),
            -- barGlows excluded from export (spec-specific, stored in specProfiles)
        }
        -- Filter by selected specs if provided
        if selectedSpecs and profileData.spellAssignments.specProfiles then
            for key in pairs(profileData.spellAssignments.specProfiles) do
                if not selectedSpecs[key] then
                    profileData.spellAssignments.specProfiles[key] = nil
                end
            end
        end
    end
    local sw, sh = GetPhysicalScreenSize()
    -- Use EllesmereUI's own stored scale (UIParent scale), not Blizzard's CVar
    local euiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        euiScale = euiScale,
        screenW  = sw and math.floor(sw) or 0,
        screenH  = sh and math.floor(sh) or 0,
    }
    local payload = { version = 3, type = "full", data = profileData, meta = meta }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

function EllesmereUI.DecodeImportString(importStr)
    if not importStr or #importStr < 5 then return nil, "Invalid string" end
    -- Detect old CDM bar layout strings (format removed in 5.1.2)
    if importStr:sub(1, 9) == "!EUICDM_" then
        return nil, "This is an old CDM Bar Layout string. This format is no longer supported. Use the standard profile import instead."
    end
    if importStr:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return nil, "Not a valid EllesmereUI string. Make sure you copied the entire string."
    end
    if not LibDeflate then return nil, "LibDeflate not available" end
    local encoded = importStr:sub(#EXPORT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return nil, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return nil, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if not payload or type(payload) ~= "table" then
        return nil, "Failed to deserialize data"
    end
    if not payload.version or payload.version < 3 then
        return nil, "This profile was created before the beta wipe and is no longer compatible. Please create a new export."
    end
    if payload.version > 3 then
        return nil, "This profile was created with a newer version of EllesmereUI. Please update your addon."
    end
    return payload, nil
end

--- Reset class-dependent fill colors in Resource Bars after a profile import.
--- The exporter's class color may be baked into fillR/fillG/fillB; this
--- resets them to the importer's own class/power colors and clears
--- customColored so the bars use runtime class color lookup.
local function FixupImportedClassColors()
    local rbEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUIResourceBars" then rbEntry = e; break end
    end
    if not rbEntry or not IsAddonLoaded(rbEntry.folder) then return end
    local profile = GetAddonProfile(rbEntry)
    if not profile then return end

    local _, classFile = UnitClass("player")
    -- CLASS_COLORS and POWER_COLORS are local to ResourceBars, so we
    -- use the same lookup the addon uses at init time.
    local classColors = EllesmereUI.CLASS_COLOR_MAP
    local cc = classColors and classColors[classFile]

    -- Health bar: reset to importer's class color
    if profile.health and not profile.health.darkTheme then
        profile.health.customColored = false
        if cc then
            profile.health.fillR = cc.r
            profile.health.fillG = cc.g
            profile.health.fillB = cc.b
        end
    end
end

--- Import a profile string. Returns: success, errorMsg
--- The caller must provide a name for the new profile.
function EllesmereUI.ImportProfile(importStr, profileName)
    local payload, err = EllesmereUI.DecodeImportString(importStr)
    if not payload then return false, err end

    local db = GetProfilesDB()

    if payload.type == "cdm_spells" then
        return false, "This is a CDM Bar Layout string, not a profile string."
    end

    -- Check if current spec has an assigned profile (blocks auto-apply)
    local specLocked = false
    do
        local si = GetSpecialization and GetSpecialization() or 0
        local sid = si and si > 0 and GetSpecializationInfo(si) or nil
        if sid then
            local assigned = db.specProfiles and db.specProfiles[sid]
            if assigned then specLocked = true end
        end
    end

    if payload.type == "full" then
        -- Full profile: store as a new named profile
        local stored = DeepCopy(payload.data)
        -- Strip spell assignment data from stored profile (lives in dedicated store)
        if stored.addons and stored.addons["EllesmereUICooldownManager"] then
            stored.addons["EllesmereUICooldownManager"].specProfiles = nil
            stored.addons["EllesmereUICooldownManager"].barGlows = nil
        end
        stored.spellAssignments = nil
        -- Snap all positions to the physical pixel grid (imported profiles
        -- may come from a different version without pixel snapping)
        if EllesmereUI.SnapProfilePositions then
            EllesmereUI.SnapProfilePositions(stored)
        end
        db.profiles[profileName] = stored
        -- Add to order if not present
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        -- Write spell assignments to dedicated store
        if payload.data.spellAssignments then
            if not EllesmereUIDB.spellAssignments then
                EllesmereUIDB.spellAssignments = { specProfiles = {} }
            end
            local sa = EllesmereUIDB.spellAssignments
            local imported = payload.data.spellAssignments
            if imported.specProfiles then
                for key, data in pairs(imported.specProfiles) do
                    sa.specProfiles[key] = DeepCopy(data)
                end
            end
            if imported.barGlows and next(imported.barGlows) then
                -- barGlows is now per-spec in specProfiles, not global. Skip import.
            end
        end
        -- Backward compat: extract specProfiles from CDM addon data (pre-migration format)
        if payload.data.addons and payload.data.addons["EllesmereUICooldownManager"] then
            local cdm = payload.data.addons["EllesmereUICooldownManager"]
            if cdm.specProfiles then
                if not EllesmereUIDB.spellAssignments then
                    EllesmereUIDB.spellAssignments = { specProfiles = {} }
                end
                for key, data in pairs(cdm.specProfiles) do
                    if not EllesmereUIDB.spellAssignments.specProfiles[key] then
                        EllesmereUIDB.spellAssignments.specProfiles[key] = DeepCopy(data)
                    end
                end
            end
            if cdm.barGlows then
                if not EllesmereUIDB.spellAssignments then
                    EllesmereUIDB.spellAssignments = { specProfiles = {} }
                end
                if not next(EllesmereUIDB.spellAssignments.barGlows or {}) then
                    -- barGlows is now per-spec in specProfiles, not global. Skip import.
                end
            end
        end
        if specLocked then
            return true, nil, "spec_locked"
        end
        -- Make it the active profile and re-point db references
        db.activeProfile = profileName
        RepointAllDBs(profileName)
        -- Apply imported data into the live db.profile tables
        EllesmereUI.ApplyProfileData(payload.data)
        FixupImportedClassColors()
        -- Reload UI so every addon rebuilds from scratch with correct data
        ReloadUI()
        return true, nil
    --[[ ADDON-SPECIFIC EXPORT DISABLED
    elseif payload.type == "partial" then
        -- Partial: deep-copy current profile, overwrite the imported addons
        local current = db.activeProfile or "Default"
        local currentData = db.profiles[current]
        local merged = currentData and DeepCopy(currentData) or {}
        if not merged.addons then merged.addons = {} end
        if payload.data and payload.data.addons then
            for folder, snap in pairs(payload.data.addons) do
                local copy = DeepCopy(snap)
                -- Strip spell assignment data from CDM profile (lives in dedicated store)
                if folder == "EllesmereUICooldownManager" and type(copy) == "table" then
                    copy.specProfiles = nil
                    copy.barGlows = nil
                end
                merged.addons[folder] = copy
            end
        end
        if payload.data.fonts then
            merged.fonts = DeepCopy(payload.data.fonts)
        end
        if payload.data.customColors then
            merged.customColors = DeepCopy(payload.data.customColors)
        end
        -- Store as new profile
        merged.spellAssignments = nil
        db.profiles[profileName] = merged
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        -- Write spell assignments to dedicated store
        if payload.data and payload.data.spellAssignments then
            if not EllesmereUIDB.spellAssignments then
                EllesmereUIDB.spellAssignments = { specProfiles = {} }
            end
            local sa = EllesmereUIDB.spellAssignments
            local imported = payload.data.spellAssignments
            if imported.specProfiles then
                for key, data in pairs(imported.specProfiles) do
                    sa.specProfiles[key] = DeepCopy(data)
                end
            end
            if imported.barGlows and next(imported.barGlows) then
                -- barGlows is now per-spec in specProfiles, not global. Skip import.
            end
        end
        -- Backward compat: extract specProfiles from CDM addon data (pre-migration format)
        if payload.data and payload.data.addons and payload.data.addons["EllesmereUICooldownManager"] then
            local cdm = payload.data.addons["EllesmereUICooldownManager"]
            if cdm.specProfiles then
                if not EllesmereUIDB.spellAssignments then
                    EllesmereUIDB.spellAssignments = { specProfiles = {} }
                end
                for key, data in pairs(cdm.specProfiles) do
                    if not EllesmereUIDB.spellAssignments.specProfiles[key] then
                        EllesmereUIDB.spellAssignments.specProfiles[key] = DeepCopy(data)
                    end
                end
            end
            if cdm.barGlows then
                if not EllesmereUIDB.spellAssignments then
                    EllesmereUIDB.spellAssignments = { specProfiles = {} }
                end
                if not next(EllesmereUIDB.spellAssignments.barGlows or {}) then
                    -- barGlows is now per-spec in specProfiles, not global. Skip import.
                end
            end
        end
        if specLocked then
            return true, nil, "spec_locked"
        end
        db.activeProfile = profileName
        RepointAllDBs(profileName)
        EllesmereUI.ApplyProfileData(merged)
        FixupImportedClassColors()
        -- Reload UI so every addon rebuilds from scratch with correct data
        ReloadUI()
        return true, nil
    --]] -- END ADDON-SPECIFIC EXPORT DISABLED
    end

    return false, "Unknown profile type"
end

-------------------------------------------------------------------------------
--  Profile management
-------------------------------------------------------------------------------
function EllesmereUI.SaveCurrentAsProfile(name)
    local db = GetProfilesDB()
    local current = db.activeProfile or "Default"
    local src = db.profiles[current]
    -- Deep-copy the current profile into the new name
    local copy = src and DeepCopy(src) or {}
    -- Ensure fonts/colors/unlock layout are current
    copy.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    copy.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    copy.unlockLayout = {
        anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
        widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
        heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
        phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
    }
    db.profiles[name] = copy
    local found = false
    for _, n in ipairs(db.profileOrder) do
        if n == name then found = true; break end
    end
    if not found then
        table.insert(db.profileOrder, 1, name)
    end
    -- Switch to the new profile using the standard path so the outgoing
    -- profile's state is properly saved before repointing.
    EllesmereUI.SwitchProfile(name)
end

function EllesmereUI.DeleteProfile(name)
    local db = GetProfilesDB()
    db.profiles[name] = nil
    for i, n in ipairs(db.profileOrder) do
        if n == name then table.remove(db.profileOrder, i); break end
    end
    -- Clean up spec assignments
    for specID, pName in pairs(db.specProfiles) do
        if pName == name then db.specProfiles[specID] = nil end
    end
    -- Clean up keybind
    EllesmereUI.OnProfileDeleted(name)
    -- If deleted profile was active, fall back to Default
    if db.activeProfile == name then
        db.activeProfile = "Default"
        RepointAllDBs("Default")
    end
end

function EllesmereUI.RenameProfile(oldName, newName)
    local db = GetProfilesDB()
    if not db.profiles[oldName] then return end
    db.profiles[newName] = db.profiles[oldName]
    db.profiles[oldName] = nil
    for i, n in ipairs(db.profileOrder) do
        if n == oldName then db.profileOrder[i] = newName; break end
    end
    for specID, pName in pairs(db.specProfiles) do
        if pName == oldName then db.specProfiles[specID] = newName end
    end
    if db.activeProfile == oldName then
        db.activeProfile = newName
        RepointAllDBs(newName)
    end
    -- Update keybind reference
    EllesmereUI.OnProfileRenamed(oldName, newName)
end

function EllesmereUI.SwitchProfile(name)
    local db = GetProfilesDB()
    if not db.profiles[name] then return end
    -- Save current fonts/colors into the outgoing profile before switching
    local outgoing = db.profiles[db.activeProfile or "Default"]
    if outgoing then
        outgoing.fonts = DeepCopy(EllesmereUI.GetFontsDB())
        outgoing.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
        -- Save unlock layout into outgoing profile
        outgoing.unlockLayout = {
            anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
            widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
            heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
            phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
        }
    end
    db.activeProfile = name
    RepointAllDBs(name)
end

-------------------------------------------------------------------------------
--  SwitchKeybindProfile
--
--  Snapshots the outgoing spec's keybinds and restores the incoming spec's
--  keybind profile. If no profile exists for the incoming spec, one is
--  created automatically from the current keybinds.
-------------------------------------------------------------------------------
local function SwitchKeybindProfile(outgoingSpecID, incomingSpecID)
    if not EllesmereUIDB then return end
    if not EllesmereUIDB.specKeybindProfiles then EllesmereUIDB.specKeybindProfiles = {} end
    if not EllesmereUIDB.keybindProfiles then EllesmereUIDB.keybindProfiles = {} end

    -- Snapshot outgoing spec's keybinds
    if outgoingSpecID then
        local outName = EllesmereUIDB.specKeybindProfiles[outgoingSpecID]
        if outName then
            EllesmereUI:SnapshotKeybinds(outName)
        end
    end

    -- Resolve incoming profile
    local inName = EllesmereUIDB.specKeybindProfiles[incomingSpecID]
    if not inName then
        -- First time on this spec: create profile from current keybinds
        local specIdx = GetSpecialization and GetSpecialization()
        local specName
        if specIdx and specIdx > 0 then
            _, specName = GetSpecializationInfo(specIdx)
        end
        inName = specName or ("Spec " .. incomingSpecID)
        EllesmereUI:SnapshotKeybinds(inName)
        EllesmereUIDB.specKeybindProfiles[incomingSpecID] = inName
    end

    -- Restore incoming keybinds
    if EllesmereUIDB.keybindProfiles[inName] then
        EllesmereUI:RestoreKeybinds(inName)
    end
end

EllesmereUI._SwitchKeybindProfile = SwitchKeybindProfile

function EllesmereUI.GetActiveProfileName()
    local db = GetProfilesDB()
    return db.activeProfile or "Default"
end

function EllesmereUI.GetProfileList()
    local db = GetProfilesDB()
    return db.profileOrder, db.profiles
end

function EllesmereUI.AssignProfileToSpec(profileName, specID)
    local db = GetProfilesDB()
    db.specProfiles[specID] = profileName
end

function EllesmereUI.UnassignSpec(specID)
    local db = GetProfilesDB()
    db.specProfiles[specID] = nil
end

function EllesmereUI.GetSpecProfile(specID)
    local db = GetProfilesDB()
    return db.specProfiles[specID]
end

-------------------------------------------------------------------------------
--  AutoSaveActiveProfile: no-op in single-storage mode.
--  Addons write directly to EllesmereUIDB.profiles[active].addons[folder],
--  so there is nothing to snapshot. Kept as a stub so existing call sites
--  (keybind buttons, options panel hooks) do not error.
-------------------------------------------------------------------------------
function EllesmereUI.AutoSaveActiveProfile()
    -- Intentionally empty: single-storage means data is always in sync.
end

-------------------------------------------------------------------------------
--  Spec auto-switch handler
--
--  Single authoritative runtime handler for spec-based profile switching.
--  Uses ResolveSpecProfile() for all resolution. Defers the entire switch
--  during combat via pendingSpecSwitch / PLAYER_REGEN_ENABLED.
-------------------------------------------------------------------------------
do
    local specFrame = CreateFrame("Frame")
    local lastKnownSpecID = nil
    local lastKnownCharKey = nil
    local pendingSpecSwitch = false   -- true when a switch was deferred by combat
    local specRetryTimer = nil        -- retry handle for new characters

    specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    specFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    specFrame:SetScript("OnEvent", function(_, event, unit)
        ---------------------------------------------------------------
        --  PLAYER_REGEN_ENABLED: handle deferred spec switch
        ---------------------------------------------------------------
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingSpecSwitch then
                pendingSpecSwitch = false
                -- Re-resolve after combat ends (spec may have changed again)
                local targetProfile = ResolveSpecProfile()
                if targetProfile then
                    local current = EllesmereUIDB and EllesmereUIDB.activeProfile or "Default"
                    if current ~= targetProfile then
                        local fontWillChange = EllesmereUI.ProfileChangesFont(
                            EllesmereUIDB.profiles[targetProfile])
                        EllesmereUI._specProfileSwitching = true
                        EllesmereUI.SwitchProfile(targetProfile)
                        EllesmereUI.RefreshAllAddons()
                        if fontWillChange then
                            EllesmereUI:ShowConfirmPopup({
                                title       = "Reload Required",
                                message     = "Font changed. A UI reload is needed to apply the new font.",
                                confirmText = "Reload Now",
                                cancelText  = "Later",
                                onConfirm   = function() ReloadUI() end,
                            })
                        end
                    end
                end
                -- Always switch keybind profile on deferred spec change
                local _, deferredSpecID = ResolveSpecProfile()
                if deferredSpecID then
                    SwitchKeybindProfile(nil, deferredSpecID)
                end
            end
            return
        end

        ---------------------------------------------------------------
        --  Filter: only handle "player" for PLAYER_SPECIALIZATION_CHANGED
        ---------------------------------------------------------------
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
            return
        end

        ---------------------------------------------------------------
        --  Resolve the current spec via live API
        ---------------------------------------------------------------
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local specID = specIdx and specIdx > 0
            and GetSpecializationInfo(specIdx) or nil

        if not specID then
            -- Spec info not available yet (common on brand new characters).
            -- Start a short polling retry so we can assign the correct
            -- profile once the server sends spec data.
            if not specRetryTimer and (lastKnownSpecID == nil) then
                local attempts = 0
                specRetryTimer = C_Timer.NewTicker(1, function(ticker)
                    attempts = attempts + 1
                    local idx = GetSpecialization and GetSpecialization() or 0
                    local sid = idx and idx > 0
                        and GetSpecializationInfo(idx) or nil
                    if sid then
                        ticker:Cancel()
                        specRetryTimer = nil
                        -- Record the spec so future events use the fast path
                        lastKnownSpecID = sid
                        local ck = UnitName("player") .. " - " .. GetRealmName()
                        lastKnownCharKey = ck
                        if not EllesmereUIDB then EllesmereUIDB = {} end
                        if not EllesmereUIDB.lastSpecByChar then
                            EllesmereUIDB.lastSpecByChar = {}
                        end
                        EllesmereUIDB.lastSpecByChar[ck] = sid
                        EllesmereUI._profileSaveLocked = false
                        -- Resolve via the unified function
                        local target = ResolveSpecProfile()
                        if target then
                            local cur = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
                            if cur ~= target then
                                local fontChange = EllesmereUI.ProfileChangesFont(
                                    EllesmereUIDB.profiles[target])
                                EllesmereUI._specProfileSwitching = true
                                EllesmereUI.SwitchProfile(target)
                                EllesmereUI.RefreshAllAddons()
                                if fontChange then
                                    EllesmereUI:ShowConfirmPopup({
                                        title       = "Reload Required",
                                        message     = "Font changed. A UI reload is needed to apply the new font.",
                                        confirmText = "Reload Now",
                                        cancelText  = "Later",
                                        onConfirm   = function() ReloadUI() end,
                                    })
                                end
                            end
                        end
                    elseif attempts >= 10 then
                        ticker:Cancel()
                        specRetryTimer = nil
                    end
                end)
            end
            return
        end

        -- Spec resolved -- cancel any pending retry
        if specRetryTimer then
            specRetryTimer:Cancel()
            specRetryTimer = nil
        end

        local charKey = UnitName("player") .. " - " .. GetRealmName()
        local isFirstLogin = (lastKnownSpecID == nil)
        -- charChanged is true when the active character is different from the
        -- last session (alt-swap). On a plain /reload the charKey stays the same.
        local charChanged = (lastKnownCharKey ~= nil) and (lastKnownCharKey ~= charKey)

        -- On PLAYER_ENTERING_WORLD (reload/zone-in), skip if same character
        -- and same spec -- a plain /reload should not override the user's
        -- active profile selection.
        if event == "PLAYER_ENTERING_WORLD" then
            if not isFirstLogin and not charChanged and specID == lastKnownSpecID then
                return -- same char, same spec, nothing to do
            end
        end
        local oldSpecID = lastKnownSpecID  -- capture before overwrite for keybind switching
        lastKnownSpecID = specID
        lastKnownCharKey = charKey

        -- Persist the current spec so PreSeedSpecProfile can guarantee the
        -- correct profile is loaded on next login via ResolveSpecProfile().
        if not EllesmereUIDB then EllesmereUIDB = {} end
        if not EllesmereUIDB.lastSpecByChar then EllesmereUIDB.lastSpecByChar = {} end
        EllesmereUIDB.lastSpecByChar[charKey] = specID

        -- Spec resolved successfully -- unlock auto-save if it was locked
        -- during PreSeedSpecProfile when spec was unavailable.
        EllesmereUI._profileSaveLocked = false

        ---------------------------------------------------------------
        --  Defer entire switch during combat
        ---------------------------------------------------------------
        if InCombatLockdown() then
            pendingSpecSwitch = true
            return
        end

        ---------------------------------------------------------------
        --  Resolve target profile via the unified function
        ---------------------------------------------------------------
        local db = GetProfilesDB()
        local targetProfile = ResolveSpecProfile()
        if targetProfile then
            local current = db.activeProfile or "Default"
            if current ~= targetProfile then
                local function doSwitch()
                    EllesmereUI._specProfileSwitching = true
                    local fontWillChange = EllesmereUI.ProfileChangesFont(db.profiles[targetProfile])
                    EllesmereUI.SwitchProfile(targetProfile)
                    EllesmereUI.RefreshAllAddons()
                    if not isFirstLogin and fontWillChange then
                        EllesmereUI:ShowConfirmPopup({
                            title       = "Reload Required",
                            message     = "Font changed. A UI reload is needed to apply the new font.",
                            confirmText = "Reload Now",
                            cancelText  = "Later",
                            onConfirm   = function() ReloadUI() end,
                        })
                    end
                end
                if isFirstLogin then
                    -- Defer two frames: one frame lets child addon OnEnable
                    -- callbacks run, a second frame lets any deferred
                    -- registrations inside OnEnable (e.g. SetupOptionsPanel)
                    -- complete before SwitchProfile tries to rebuild frames.
                    C_Timer.After(0, function()
                        C_Timer.After(0, doSwitch)
                    end)
                else
                    doSwitch()
                end
            elseif isFirstLogin or charChanged then
                -- activeProfile already matches the target. If the pre-seed
                -- already injected the correct data into each child SV, the
                -- addons built with the right values and no further action is
                -- needed. Only call SwitchProfile if the pre-seed did not run
                -- (e.g. first session after update, no lastSpecByChar entry).
                if not EllesmereUI._preSeedComplete then
                    C_Timer.After(0, function()
                        C_Timer.After(0, function()
                            EllesmereUI.SwitchProfile(targetProfile)
                        end)
                    end)
                end
            end
        elseif isFirstLogin or charChanged then
            -- No spec assignment for this character. If the current
            -- activeProfile is spec-assigned (left over from a previous
            -- character), switch to the last non-spec profile so this
            -- character doesn't inherit another spec's layout.
            local current = db.activeProfile or "Default"
            local currentIsSpecAssigned = false
            if db.specProfiles then
                for _, pName in pairs(db.specProfiles) do
                    if pName == current then currentIsSpecAssigned = true; break end
                end
            end
            if currentIsSpecAssigned then
                -- Find the best fallback: lastNonSpecProfile, or any profile
                -- that isn't spec-assigned, or Default as last resort.
                local fallback = db.lastNonSpecProfile
                if not fallback or not db.profiles[fallback] then
                    -- Walk profileOrder to find first non-spec-assigned profile
                    local specAssignedSet = {}
                    if db.specProfiles then
                        for _, pName in pairs(db.specProfiles) do
                            specAssignedSet[pName] = true
                        end
                    end
                    for _, pName in ipairs(db.profileOrder or {}) do
                        if not specAssignedSet[pName] and db.profiles[pName] then
                            fallback = pName
                            break
                        end
                    end
                end
                fallback = fallback or "Default"
                if fallback ~= current and db.profiles[fallback] then
                    C_Timer.After(0, function()
                        C_Timer.After(0, function()
                            EllesmereUI.SwitchProfile(fallback)
                        end)
                    end)
                end
            end
        end

        -- Switch keybind profile on spec change, independent of UI profile.
        -- Delay slightly so Blizzard's action bar texture rebuild finishes first.
        if specID and not InCombatLockdown() then
            local capturedOld = oldSpecID
            local capturedNew = specID
            C_Timer.After(0.5, function()
                if not InCombatLockdown() then
                    SwitchKeybindProfile(capturedOld, capturedNew)
                end
            end)
        end
    end)
end

-------------------------------------------------------------------------------
--  Popular Presets & Weekly Spotlight
--  Hardcoded profile strings that ship with the addon.
--  To add a new preset: add an entry to POPULAR_PRESETS with name + string.
--  To update the weekly spotlight: change WEEKLY_SPOTLIGHT.
-------------------------------------------------------------------------------
EllesmereUI.POPULAR_PRESETS = {
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_T33wZTTTwJ(xPpEopepKG3PFYYXonJZTTJABYE2ZOHwI2IFrMuFKujXnJ)VFWATaabib1fhNSBp1zMwBlrcSUFfx(2fn(P3M3MX)L408nfVFE2Q8sNJc9sG)fheM4hNC8fnrPnZRZZl)1sxFFhTp4pkzbHohFpmsT3ToN)JR3SAf8aFoVUPOQS07y4lxKHtJllDt5QQ5F6vz3vTP9BWdMvoFzvDd9TxxnFtZPznTxLvZ)KW02S6BYBBcOVbE(QRVUjV9JC40ZZliiYLfN4eYcW5PPyro)TM82PtF7R7E6pu(mVJCcCJcIIDzb5pZjaaAx30FpFzX8v5N91Iw95lk91zfLtYQnNrMFscquy(m344Uz0lD6BFN(05gfEuyyyGNVpZl2tmzN9VMoBAD28pLBGC(P8jk0CMCddJc98Cccd9Dc7Mj)0xD25tnWmCMss4queHvmXat)F9zs(l6ZL7rCKk2pY3L56K4VfKkm4Oypp)KqNepXu5LE6ZF9S5vvRwu9LYg95IJVW3TPTyvr7Dgy3wrhxa31rhxI3peBSiu4c0IWGq)eFxd62aKjWrGa0GzrMZgX6zOuNhZZnj2j0HTDHoCkKdZofVEwWr(UHboE9eNdsV8LV4xnisrh5e7XcCtc84IZWS4LUUpRE9QS7YR7b9a1zWmyvHrWTd5QyHUrmcvOX8bJkwy3Xhff44e664f4geItts6zxoz27Q(I5m5gHF(PRYAAUmVPAt98CtLgWQLxCsOFSpiGUD8Z5ihhh3ypxNa)quwdKhCs)sXI2LVoRD(YHMK6e50GXramqFh(u(BYPoJ9q9K)uylj4VmV4MLTkGXWcIYSrFLWEAEKu(6LzLTv3oPAt5IMVDpYmZwSOc1zzHPNTAvEZT515)2lpvmqVoRm7gKfeLoFXTasapRBADvBwl32(VMVADE9zLzxTkFX54xTKtUNSHtI)JL5LVSmBEBXNZ5mC3K0nn5twv8N)zw9c4jGHdEhVEd3lwv9L33Eh3reXabIY3aK3p9Zfn)kF8)1QnnfL3mf)mY7X7QAkGHG)8RYVUfqo(7n5MjOTgoPN7S5TxFzw5n5VL7yIleFoGvLBU9YQV0u6EmY5B(sX68twbKkNJIq3C5eYnf8q(P87UQOCXjGG2XOObohNPEeo40SeGEo)5uoHU9CKN1O(7xqZelDDw5I8BlMdi75642RHhdjMrPxvvViVwGcbYN4nvtrbeTh5s8r8sVcWxULHJbOTyEv57l(Z8sVeWGk3Dsa3Pfo)UiyE6syCAMI0hDa69RZZxu6t0eefjAc(U(sYWBLQ6SJhmcNwTQcKBCtVIG(0BO3oTM)ts0wmmii66mCmEvrzEtzmH7eEoL7Q(t8pTbI2yzrjcoZr048QYwAOKyOIOpbNAjT6e8V8GPNRdR0zqDesw6TAEP4FiNa87fnfxH6sGsZQVKDh88HQ3UBYzejQBYnGjsB4KYIBFbNpfh0)tVeHn)0YSBZ5a3PAaNocrpMsEuiuzc(FGa)qbwJwDqUcOY5OnNgFdNstFdxeUf)A(0CLqPfMsAkMwbazvjy)koDjPocYMDQcsY9lkTWAj1BaQtiX0LzyOJIH0r8UeTthvjmNJvCDH3wU6UxwYPkLZZB2HXhE8N5nzTBQ5y1Blp95t1v5Et1zL53Ehne6GPsCRKjuVavFiMcU1mUvK2cE8YVTUiVKSFDocAOQLGZnn)RTtPx9sPMPbRuiL1tP6d4ekutNYhR2I1N3twHmlOOmKqUWQ3LIVdOT)7QQBLtnahVq(hINvWG0bQpO(i(0Fbn(O1MM1zZ5CAo0D)pydYi(FOgK7jZTFgJn5npm7W9ufhZqmtJS(KX3OuvMb)an9k04oilVrP)McY2ID3jhQD3ofixIWUnBTBXi9iMC7fpY5dfT(hMzxBUREmn(omoUFW2F7I27WT)2xSDxwGFyHepMO5(zl(huGXM6D6gKd6OZ)ZYGSq4d4BbhB3(mFAaD6l(rAD(bfyCq6ebG9yguCpN2dSCye)YGingAN7X107qt7paJX)0m8(JlE3D408hQ93X8iF42ITXl2FDxtB02uD5SlOEPv3oZFglYlooEMFa7cR2ZTQDRBKFCZHw59BXWqe8ntHUeWXkbac2yEqMm6R5Btjufp37Qq6VL0sT5eCF9wnMkUf3yJepyphzBt02QFoRgtSAzWW8MP(5aJpJ59KDSzDLS790Ih7VF7m2cLBl(bTyY5qDjBZZr)CyT7G(r1i0qd)wdX6(V1tPTVwyqAz(NPMbyeHNx6n1vF55f15ZrvevVge6oCaGpplYl)fHt3oXbhtXbHKJqdxf9GWIKx6Sz3SSQPDMmQcN0IMxaFYe(R8qHFtOrmxoQ5A(ITHIJc8g1fusiCKeItF(qW)(EGpJ8dl0ENEpkUs1qx5n4BxOpr8)kiDDvrj05Mtp7ntp7sacRZx9oJp8(lK0wu89UYNf6a9Pb6utINtO)XwFnBJUB6xlPMGz1FHy8DdPEQf5WIDypGrxLOVeGtcGoV44WCzE(UHh2qgYokaEzxVKWKyFQPnS02RUQJWsK7wSnjQEnq9pPjFfxmG)Pz1IykL9xiMlkLVA1lFEZ3kzX8udk9yUXSJlJD8c8oUKf6Zjc8pnXXloK)Zyxph3Jl999Dcz4pzbrht9qc1JB6CyfGcrKontOMpDzDo325QfAk3bCz1SfGLpJp085bt3XQbLSVX879qVo7RAdHdNwUEZQS6lWYEF1QQQfR4SCyqUUy1kyitccJd584iqeiSZsfyMO)OxsznOjX3hibtCu8Usmc(egztRV7XrZ1jAiwjspQ)8nrmFe(a)velX31nk2j2ZNHFdOUtKReYd)6S6pPhNWVMxxv0CBhc3OeQ4rOWXbWcuOORCLmFYce(GspeTf3Mx)bLNtuIIKNu(DvZ)u4zNQElc0iW8dYSSWVrbfbP1WudJDfy4R9ozehagmiqtHx)JrvCt61uUtZMgN0buFTa86tJprgPfaHt6cAONNagzdcGOonajDsgGzlpCXn1DHTiddWNaw7HbKqKJUrTt66sH01wJ1y0OaQfE)LrbCfz6QB4NO05W2dxYIe6fKHZNdHDcR2fFIwaC33WX)TLjijPkOPUQzI7OcD282lF5)(TVz6jVshmupnqSFErd0oEfjKgqqnlWpXXnj0ZpI5fgYTrkIOHIVCD(CWmGBQd(PCMWNkeSZguBGl2o)BalHHEbItVnB9AUtw0oPsR)CuUldDQoztBlh7jgn3p37xv1ks3v8ac7TCuPF4xhjj9CkmYKKXGjul9CWe()fGE(l)FYVj9xEEXN5Mi(L3TPEDvt()xCzmvHT5)KtN(YF)m50OfsoLy851v3E6ZF953tEiKodEnHE0ScyD4)aXAxh))XH1S0WGFWiDNLffkt0H)RH0aR(hnw)xpwnOwh)poSMlG)pnBz43ePVEMMK1umxS(s)F3K302TemTxSeR1NZjnBtB1jZNNVgliKx6668740HvzRBiAzc(it3ux(YY3VS4623)PI1t7fOSSkNRHWCPcM8LQ6vlmgjV0)K7s34J4CLQBxVkhkPIzjc97(gt2cvHgTsBWdrsUKkBYN3nmWA0vfwRFawxWaIw1yaeoaHzyL940Ikz(OUU(h5ff4eZIy(rWiFaz3XJw)iwOJxOxCadYUtpO5rAg0ngLZ0wzYabfon)paY8)crQUEsH)9lBZVTzQE8YXPvx9)ysnJykP8iMIGslmsoR3iHFsaJkKXS5zRHqDx8wU4fjbWh7E8qpIAdacfdTS6NCq8DC5S(G9)MlEO(mzqPEoMKjrTOjj6f5R(SHefxADvXnL3YdRKJ4TvR1Z4lgeqmX)qmUEPAUVIc44lZ6Tt6NKvAlAxLBoi(rQXiXv3ubMQd)X1R)lw8GBlkl4wV(2Oi2qv1W0nL3uxTznK9pywdx3I(62eEnnQAw94SWxvC1ZN8sEK1UoZMS5M3ZzILe7nczVNwNDDlFEFleQSwbCvrLphwA7Clj8NDQmjVtHpRVrGGu(NIzmOACiz5LdtI1kcMvVdoVNaRtZt564z1Ta7IWr13iWXZ7aHZRQVnd4QUSLiMvaPUYTJdaWKwrAA0mQxqCoeN958fu5kpgeSAWAlhM28)UjRMwVQsiN2TaUh5gmUUPE9TDG9max(dgDIgyrtLriGr)6cqufEnbMo9IEvTwuwb6X4wv55wsudqIeEX3UHwqaRfzilSvrM6oa7tjbHgRG677WYlLzSpqFFeJMca(fqAI8SAphae4dEDwXQbKIpsIy0tGMx4YHe5y6fJ4gZpfLfSiU9bjhbNbtgjJwwWkPerNVb)rkjBGxsT(PEbk3rW1LzflEEX1xxmFZQ27i)yBAYnx9kG3k(RXnQnVa3GiIIeEnKP)IMdZPSVqfJpbGElzmSTyv(lKCd0oqZWfM4jIGzWQwarzW5mqii1LMQQj4WjDXqEuj3jxMFdh8LtRMI0robhVv2E2COwsifr615s1RfWzks6feWudvpzoD8e81MMD1ut)EuDjAiU4X91n01YvZIQDqbcqfqiQeaks4evtj4FhxUzLiEfB6T0BCPuScI6drayoccH5G5Ph)eYRFz5NlAjER2R8cvuKE4m)Bst5tVyhEa6S8O6XI(IByIgNrnByTud9oEmz1RLb)wwMx3C(9qCsZ3u3GU084Hm9v(h4C6Zzjp3oOytS1Gzz1m4yYowWFd)kCn6SM2tlQNVkxda9o)KOZphGDOosBA4rkOlZ4qE8ZABZMVehOa(uccxXoKjHgOsP6kr1qpUXXUe81ScFQcH6kO6Ar7x3jiqjXs0J264QPZxObVNJ)tdErFv7l82bDC7Eu5s3nWDEpGBeJq7CCqKuwCtUYdakZiAeMq08LzTJBJZMY)a5xDD)WTicnVA9DKlIZ7B3BGbbxytwv2Y9tcQ5uDHj)tC7nNZHPLBrSmbNkQS9uGlgPykxukQOuGDDytt2n5VxR5DCFiIp98m91owmcyKPm0xKnLmhSWWCc5TRB07eowL)8S65l78v6XPXfZ)em()2LVYSN1AUwqJ81T5LNUeu(x1WLoRGfRGnl9iiUmBbpXo7AP2SUeOJWqia8yEDWgAXC1JvfeewVkJBQKcJL8uU6U3ZrUNNFDg3zlkRqtdi7bjVFji5JmX8SvTlFZMBVc6EbNBWd1hEaY9okafj2KtaK1r5zS0ffqlmG6w)Bn5qVrvaprBpxakV5DNIR)igA)zsw9VvIHCwVzDBXvOTir8)Yusv)An9Ru(8qBlay7duCkY0(wKdD88LQgmes2RfZ1Vs5T6grYXscapfBUKzoWpbYdTaE2uNjRvpeLyxgyCqV421CgEwjUxS6AfIhrH4unj09I6QV0Uu1LfFK93eeK(saN5UmY)p8aZFBzZ)rJl(FUnFrr2)bF0)ZzFDn38qdx95OPtph9ok5QaSc2f(OGe8m5YgN2xyVxZeiKeaYCHEq3RFkCQg346IxZTBlds2NghSPH603ytzg9e2Kf2XmvnEwgZH5B3pzSo3qNPYCjlD4gO7uShk9QDHsoj23yizGw40SYpDYn8adupFSRw65HDf8a2MU3JKdHyVbQpARVyPMsCclpkH6lZZwCNAY7MAVoH6ezLb0HxnTlhkL)xxDLUE354UXBGOyxFS8igVgDD3SbpQTHDA9(AA9If(K0JIa9xw0Ev1xrPTpif3inUPDTGtKJAhN8SBx3Exh8iwLS9OrDfpbPqXyk(xv10OONjXDLAG57PE(a3yr64a3zQrRrvAOOyhOOJlGR9tonOBxEkTM4ieqUQI7442bgL80uV4Wahl4tVO5S8Ven78siP9Ri)9uDs96k)H83RXi4jGOZClv4trplnqgJc)jKPnGSqfK0JFRp(7MKaBI8Yp9RznM6zHD8X4ogjTD6zDgFpfBwUUUgxoXWmJHEyGU5vnqMPENxX)YoJBKFM3O6WSWprhVAGFcuvUlQ7KEq6UPhEKm3Ejo5OrPfH1nFuPvoHrA7)DGx(pAkMjr0DpRrAkIFWK6(jU1dOJ)AljF5gn(KAU3SoktK0RANYOIH3vZViXeQ8U2tY0vUEhnSP7e2j(l)9AXV3hbMCJDZioXDcGo6sGXK52qfXKJd9Q9iTEhjzx1l656l0(a59xvbbSzkY72rb0k8BSlz8cKka5iv4aqKJqP54kTsUGyHjO5Xtfiig)PKCrfIGh0ImSHlqjvn9WZ07Ct)LrdtjIkRGksqu2c0fkIslZ3WZ)A1EHMC5qPi0ULdd0qunvoE0KRBEdpy89N6YO8zPKAmYXstbgSmORZiSLVtlwQiu0SwkIStTmB0cGHStOzUjeJKA9av2TSstpYJLmqeuAYy(8EHBeAGIgZCtb0WhTLGdyPRVf2EEf6hGjLlKrmiDQkrDXPhh0ftJBGut1yM0IgWsy0uIHsB0Qiw)dSNfOj6yDZ)9ct0K(3lXaihKtwT65y(bycqrDCfkWM1)EPRipTyTSRLzUqv0stkBNI3mQMJcFktrGSFEf7Eu6Y1PNWtNUJ8lKoS0KtnidMQcFWC46Cjosm)8ai7)nD8IpAYlSVYQeA3Arm(rTigvOZlYwtb0eOp3AI1rg4XUjHez)9ARoDRjX11czb)V46crhmaZ26XnAgr8UHGqrMPOV9D)4(9eMvXZydU7gomzIKe3WqEYmbUjA5qhhZIcyUEEXrSykozYthZn0pWZNL4lo8HI4XRwNF2QI28xAUHKdsxM1SeusFxEnuHzQ6GWNlvvnYWU751szPl)1F16ln6k80fDV9MQEof6cuGzSIcq7K98WLOZfSfHvcQFBK5SUGje(EOqr5czzNpvMPZuSKV8)kxlKOWowqGKhZbvpjFwLN0(iu0z8rtzWf8w2p67UjvFiIsH1HEHwvwC68Y42bEEjcx5s(3oboUC5a2kz22nqy6rxHrwdcCbqxxSoFXZ(mSTJ0cb5JM(KWLcrxyOcl4dZ(fz8exgvAf9R2vScv56)NP3CvkYwL2pqnvHuTPGosHwZbpfblyaLf(T7vsdyvbFxEBdwu65ZrGOlkbtJZ9WrWifqzSMPkl1swpJUXI8e0GpQfxPBIrL4EhEanj2hRiXryGKe)deafziCUQUeuzzvntd1lGYGZI1RejetlSsEUKdBLWYf9BOKk0cSn3c0F4du1(9BW6ps2)QSn3aTUEw9gSlsCAaiI8j63PAQdTOLtpeROHQnLIwAuu(P7MD1QmSn6S0V0mLQ(FD1AUpiCak3C7vf0UUJZQZQBxUcwHr3Gd11Cm6tOA8I8mYLFC6x4iW1BQH)aQFxLyUY4XvvC9D0RgZzWT5ZYw8)qdmFGUnVTQ8Mnu79XVTjRCov03VKNTUQCwE58LeYWT7W1c4diF0ivDavMayc0MAA5xZe72S15ZlYw18MQszhbe1GDDD(15115l(dC8pJgE(GZrR2zBAYx0RJsEDVY5CeZ8j5AhalqS2HFnTORU9UwoLeHWUxfOA6VRmjPvWQTwjais734tvLUmGY0ybnzFdOOGhqynEae7UQGIIiuF1ob7Qds9Hvagu0zeT0rXER(DoNPgkfapDM2mo686ZE(l)n8W(6oPIcA132sxZlkuP7hj(9UamWUdl3840YAhnzLt71rk60o0fbTVQR(tpHEmzIiVuUVOO32HP47HNJo5eFNALwXcOXBVx9cwpdetWcznrUJIiBY6sHN3xLoRyk0QUMpDhQuDf)fWLxbpWGBLBOIBRA)c9T1vL)zUqlRUf0dmewJO2l3UKlm96IMgHUsaA2K2vuAp9qOBQj0XblC1LaXe85QzOTxCwUINMt1xM9L87Q5VAfAeYJ70)AXpxr6)nytC4qkUevyyBLwbb5Y)psl)koGMx)Pz08lg8vfq8bqR(qGTbHGM74gLQArtuO7RRLV09dBYZVvw0EoifJCbkOGRYQFRMCEIA5RGpZWtUW9DdK52)eve3wwSax8eXlGfehftrq81s)e9tvp)JpGzzWXqjon8XN2bxE(oXH(IPXl2dpyf9DtCW1HY(olqr)AuAeX0zDwKNRNdLZhSLXCODWwSJRRFs4bm46LsaOq4jtWbOW1)8FKgfxhA)VbByV4ijbW1xa6HXXXheDwVa8QjHDG2geGQ68DClG6Z8Cf7GVihQMA7lOkpKkPbp8abXNbRVrXwzr2EzPgdjgmTdfMQ4Et7ybt7l7F(aX0PcOCkPNaJQ0baU4c6K3I06aGw0NCFtLYWWe1LykMGKqJg6lS(zZW5QIiIbaIH0bBxpoZKc1wKVc(jIm0(O05ILQSk9MjCE4isuv)1b3x6DjhJCLkBbpTuOvMCkq9Y1xiR)8vDzZjAIiaWKtTpilcH4b7ktNS18WZQAzkSiGUqw(d95KwR4d9poC1mbvsejSNqNCW4tajVPYIhafz5y2zsoUHgpVwvSDsVn7RcEOABhIeYjAwMLjusWerueBkZHKDQ6VybO0qK(uhcdEpS7b76XHWb4H0XxXzA2soRB1(2A3UXqTZ5PD(ypMfnNs5YUnO4v58ySUqlFnLynLOYezL6c0MQtGvICxf0DPrviZf2xKtaydkeNyTQjCicFqSGCPluo9I(6diiM0nKVJhOch2KlZFTNuSdEzgFyhpLC0RjAQLQNykv7RFcWeOON)qzi1PvJIJlf5sKjXri65fRwzguBONwzM1kQEONOM3gIx7wQqa7WcorklJGlbzY9HyNvdHwcUoCPLIm(DRxtBfLVIYaLctjDsbY9ql(YFS8zILEkgCVOSdHYQ3Glza9MeTpnyc4BeRft8HLYwCVGhtFmvUGULwMMlRdsnAR6m9490PqvFfjTNEamFHvJ2AhmgFh2whvC7qC2mUnQHkyM8xh3hm)LyWsVqgVxGB36jiuVDguV)0JqZ(6YZItDQIjdw3y8O6xKtcpsSKoFwIv8rksE63)GQo9TxHv92yfI1X7rg0JrKawwBAjk5f1UoVNtFXYXLdJQLA9UC7hapTy9e1t(0IpMrCDz4aMjMWobFdA1H61NPWAJMLosOakblsoL5jwYWuGhWOWL2b2F0a2)K9KZC4bdmUI(wd4ZvZ40hK0)bRPsQshVNd2tVyB(5TT4tH(22z)R3IESVx)UYOAXT)w8K0Z)p5S2Idugijo5g9mP9HpQt1P9kTJ5bvFa2IzShuaaXWePfsFp3a(ylCdhi(y22BzangfuwrbtukDcC)q90BgKsFh84cSzjHICtb0s8bF0EE1zjJOf0lOzFLzVH(i7S8HxbcszeRo(eGLPfkv4Rdst78lKHk(YY3Lv3E32cjmUZqMHG8Ook7EbJG9hKKxyhrCa6NO9D6ZASKGPlBR1cEH3ZXob26878rzWL6umAmel1Xofyn7Jdt8Bq0A9ZCnUZiLoM0jQ(rzm12fzO6WT1e(ShIKRKwzygxhF1dz6asRtiNL3TEqWXoX0zG03z4XMkmQ9ELEypXYrq(uM5jQBX(JY33MVIdki1HHEV9K2ioH1dAgMJbH9vIDBMEgDdOIdJ9CVtFtfUu)0P1dUu3TLE2Bdcc2RZKI2NU1q4D6Eff2O(ersIJwXhYAJ1K3GGsdtID8syU4XXux8UueSy3NHZ2fNOyFpxVimJolUn0wBqrKMUTu4elvRPlZH2NyUl4CDeMiHT13uPqC)qYhDz9URIFOmLjVpG4)zx8NhE4)6XX(XYbLZ0sCVBLdTxXX33nLsC3wG7(cOriFlpiQge7TLOSnwrDiBsR6DZX1y8llxaRQLQAL8OjZ7GkPe1D150rG(iXMVFrrUVrcmsuKB1OYU2dbkzfZdLcrtKOK5o5QMQ6RoVVWZfwZsXweB7iImUnDdUU4v)(cVARbbzpENV7vPVfp77BqkJglrViW2YrkDVaa0k)Of3Z2CTA3DzS5QaI4DY1wYE5YASOab6TPEjP3k0K7hP9E4pbs1U3iQhl5dSwG)y8Ce1BLKq5g33c4hgy4F8IgmOIj2kdYws78ryPLZn3a9FVdRMwHTFIAlSMbAGYbMib)lMCmLmwIqS5k4At7GlDXWYomAXdEGLiy809TKJ(axqgUY6hMSL0XniFtKUghnZ8hu237rM1wtB7GtHE8O4hl5JdlUQXsiLnGnm0LOvaUxGy9ZtTFnfgAzdNHMqrqB9RCKTuu3ZqWhl7udNzMCrBvaYmf1VJk09yKkRLEkQBBsF1mBnd2HzsoAUR90QuLmWsDphTQQJwq0TLTBSPDETqgSKi7Ovq2wUBhCoRKEN1Cw3ATfT3gGXQrKT9p(JqURxzRAwxzRrbXAH0A2q09TVaXKZnrU3kpB9lA52kA12kT7Huyc9QZg1dXUktyRBR5woOox7tHg7v7O(Lr(bMu6wQJGOJK0Yvr1ak7TAAq1dTMn5Wo3mYY1Oxv727WO3wmdJR1VZQkzPpp73saWAb)hVP)wY7ZQzMTgHHTSa7NGM1M0TLubTha0(12DTm)2)OUhX5GD1TDyP0QnXTRIEVXARBV7560hJI2mivIr71W(2(1XZ7y3Twv2hXdO1QJfI72656iDb5rRBQ9l3K1JKMrdMWscndJZ5rT)OFxf16bM6u)EilpI)2ArUoWgM2p27HDiDpZjBVAr6EhEXwnOoSsBd6JPTLl1doJo7rRDGz5zREY7A5(TZ66nSgBJg4Iz9J26A40ATV6hy3ifPZAqOJ1s0XQs3iUi(51r0r7v7HL35G0w7xcZbndDqUEpgPqo2kcB8vD1pUwHEy1UOxPgCTT2(2wILhswewY18HN6)GekEa5HUVTcXsUh7vPO)5090TvL(TfM43B7uhlZ3)Iv57Tu8plLDz8vqRTeB(X0I02Q2390kCvOLTFwd2QT2FSRWvUneyl2bYENVtaX2ID2CxNDI8O9xSJwwVPHRp0VWX6njj0PBP0gluWWdOaALiaj5IJXV170oKfOURZoBXn59)AqxdFpnDqXja1vM3zA(PCW1dHly3K5l22uUrbSKd80M31lKUAZeV89Irpum6r(hfb7iogZjYXZ9ahChF3JscddcyrE((cxs)Rn5BWB4XUDvwqmTjRybmxNGdefEwONZrrjjjHjbbboHkCG9OqHEMfsehl(98LfZxLF2xl62wFHX4g4ZlYjjio(WMg3OiXEcmjmYVJrelhDVKGJIbwrSNlDMfFaJ(ZCtoYN)U(Woy0lkqn8bkwq4bYCDe2ap7RCfSt0UanuaCeCP8XcCtc8CzhiaZccG32pj0jraVrPVoRauuLtaZH2dE021m5WMah6gdKZS8CctIqPgUM2zLZXCCR7MhFx2rW9EhxWKXyh4PLUJIshPOlbUhX4IRbrSOaVdeSFMFa7ihoz1bPPO7Rjz3Orvcc9pYh2VQXojSWdKShgWfHddt898cs8IPawFDX86k9zGlQctqsOB8bRSg7WqXygF8ts8jpYVhl5L2u4gj3HSXbbHhOQexvrOlbBJuQZ1HPCp86YoXEitiokkHLCGm1N5h5Igu406eFAduG8yFfjIHg0EyMnf7WZqdVfui1hjA8KkkL((kGd(Gk6mZqTLXfxj2qyXWb7gCRpGEsMId1Mg1D2XZZAZahHNBmqMEN3(HfaDhjipq4X7UbbGk8nJNLbmYRMCcuNVbWXRK4Zg4CmYGA8WCmlDU3hw0UHAdosCuqRDlz2z5XeL(oIrqCNBQ7k32jM8wVN7hwbh5bKRXkS)k0OSmmuqsV39FlCBea3WZvL7rmVm6HL5H9mzm8qXbZ4MjWeFWbT31BUOgn2pXV7UcQnf2Cv0qxffu7GcfQHR4Usx0LtkpSFfVLAPAA1BOTCGX3Dd0IjfOF0vSLe9CfewrHmfjljq69JwgzmX7(5nbuJd5mgDGEpDzD1MBwsevlvF22fNSGd8586A4P1Lmi7gDx)78Ntdb1kKsKGU8EmxF1HCUxNKf(WI9IRTliGB5Wvoae0zWlmQ88i1V0NJeR5IEGol9wqURxFkXpR39OUXts5ydhJ866VYZ(OXs6XwMu41dt)AOOzkW6a1)czMLUH2opAAxFOK8BWvwrdQDLJeNSZ0VpTizXE3c6X6WMXXEQIABqFxNDd4FapfQWcXjynsA5ULq7P1lkKrGoCOxAbmlrTjLscstuKWBjAJ447YwSqT6qKYeGCNgQy9QM3sUT7Il5Mw1D3RcC)L8)(p5uc8YEqtOLo1SDuxFmKzy9UBA)293iBREMwfKUhzha(0b0ZJKdGUAZDGuw7UhmTPkavJRmQVhJ(JiwS1LCRng5JLlSFOM)Tyrwup0dXbG9ysS7dyGZI(w)Dzgd5tM)hy(F8irEYlG6WhXsynhIVblXQAAMpwDXBFXwSXB3E(fhwmGKpME1dBO9SX4uwXVr0tSQInQ5Grr7TAS0WgKr9R(7HRnlUFoKuB2F((fpexM2C(z4D8WC7zZpEFUBqAz(NXBmNN869KxVN8693xVE2IK9bNDJU)jIMosUnbPF4DIAU(dXRM8s)1xUy)T5JBVDznv7cGMo8ThLgmG09RV9Yx(VF7BMEYRUyeZnuUt9BVW3jzzmdB7oiG(80(wsTqlV3Sk6)u8P7rgSES8P7jSu(Kp9lEYN(t(0FYN(t(0puF6DRSIFkoaECByLsTApDa4APjppedKFFfU0WJWy3jVdLfouRYhO3UHwQ3IzD7MF)RxhQEYY(tw2)oSS)3TovTLCJ2UdGGFAoa8cp(7ZbGF6SMSpJlKdTSc7LxG4wYCpDlmuSC6dIR995wyeHNd0mEFrGKoC7c7(vgT032mYVfFchQ)PhNebSTsj(XNgaGW)d0zHLGV(b4LyllGN)66QGq(r2JO2cX7qCR8aDh8acTTl2077TcD)P4DW394VpVdw4mItb)Hg(2x)dgXR)t3RWHBwDK(KUNLnLKyFCCjCaQdhOzF76Lwm9JG9JPPFHxNHw13hhaFCBoag3U3F18dm0g)a3ahMn)E(sTLK)pDt)JeFIzKM(cQRT8ASzHF4stESug(zzX)GcW8E9fg)pfpcpLVWt5l8u(cpLVWfpLVWF5ZxOBFX9tX1WtlqSdXVWtntEuFcp1mzdbVF0EfEQLdBXVG4kc6VL9s2DKDp(FZwvuM7q6VtGF3a5pT1VDV9L9(fMHPbYdY)mEGb945FMjSiSN(NTRc8y4e(asrB02eEqXoSfU8H6D9H4bFlbUDGlrGhh31pWu4MEXyoRThW0tUR)VG76)su5V92zThniwZHZMpcBPfzlsXhMR6ERROrCsRF(I8))4Blm9Y81)iXQ)wT20VhpUfvhSfdo8ncuNlhQxbpgI1ogTUmVPAtngSaSn2IWZKoIaNKYhS2PCS5fLYJHo6ic7vIpNMJBQZwaqUH69nZxmHlOViR(UlrIwKWMXjDg3noBGnKQ9sBGZZuWquNz(e1mbWtyKRJNtyONJpDOD0rOJpwh4pH)WjbgV)jcikdpTpjZpbPxxSA1e(d7Xc87UOYoUp6OigjPBkHtE(3vPoqSCJeNprrUbUr0PA7HC(XibJlH5qCnQ5h4KeRraFHmUhnysHJCjZBepGtAlh7HZ5XMlnW3pw(SaFXZEP0PfE27kP5t7MTj4d0r6icKFsKxSNRRFeESCrNwKtlUvErrOM5jcVP0WdN)BQzBQ8zqLKw4L)OfuBI0zjcoe8kECvfAWtpsUYzz(kyuB6beVGe5g4ancpX90p55ascqlfRyuyCFXPpxckNJdIsY8d9incMgN)hfL4g6fg2Jnih5ozZlfKheD6K0LgHyUYdan)aA4WRWeuL5SBPt4X2SBOi61GmIociZenzBHMNRcG5Ha03qdDimloYL7Gt9HbK)9nVO)WceEtEzED2QVTtBzoG1ZP5dVV2mvi1exHJxuCowxxClNr8TlSh35i5V0VAXYtWqDJp6gNIsR0JlHoDs7ognnpid1p2gjWwZoMd(LItuuTZm02LCuFj3V9Lsrt1NqGG0AKWLA(xxNvU4Lx)MkP96ZnFlqTKDCFJektIXAyLu9pgydDo1ewdoYju)FcFwdcDX08G9yJSOVPRelepTmHkTqYQTUv2HwoTyG9EtAZle0g(N95rotG2I4QWIQfWCCTuUjj1SBwTg5N(U5InjL90Z1vyvEeowjnRNagtdtHdZ5ISvWODUU6AG4eNJoXn)PQ9mUYIRUYY5pgklCjgVJpi9c3qtfJWF(kgd9UTNkgwfXhreZI0OM07XpCDGdq89OKq7sWJPx2x(Lhfro3X0cHdGHy109wioeyXtqAzWX7W8VzKQB1(VHi90dv4n0ISBmp8pgCD5646L0Dlj0linJi((9SvBYBACshijBlGvF6er01jYnk6appfrNYK6H7EPoOPP5ftq86I1YlomxC2NVe0twacm((DSQxOunEHCY4V6B3Eyg9QxspfMqJBJyLINB3KoPCCt02mHMaWKSQOoAkSUBrmxHYNysbMy(NaelyqvvZ7yQJB)31V7Bof4iyDm6hjnIOxoU1Qr0Lf5S2xxogOa)HMHLoL4KJVhp5uy6(pA(29ibgdD9KMMIBkVfouSP875F683vxXhHC4tyPHbyEPCygZvbFSeX4nlCMNFKpZBMxOp5JldhW8fIhMZtcGJUuykJ7El)WqNWGzjSVDV(WfW)cFxw0SKOEFtm)BI5V0mNOKVrvuB2SBww10odVWeSp5bEb8mclzmVy3OJlrHo6KXUhkKWrHqNKTHcL8aW79Q(ZybXXEXZcJDT(QdECEkCXCujGzFMCzEHWj9k(lHCpLL8SAfhET8hh5yYlehokl)wm9BT3Xr8x4qX)lliSVN3SGi7qTopZ4TIDyoZcIhb4h7TI8cCNL4hDyVfNzhXz2b2PROaqD(TvF2Kwh3jjXscCJ8Mnk0sYeMtCeFIddcdNfhmYe3do5pTFShh7c)gMS0Mw0uJ9PeobG5oScIcC4)mbScY)PdJb)FUH3YWeF5EukhA2Nb2Im)3N3chmTaVhFfyIcsPB0Q3)LI154H3U8cJJg8D9meGSJNcG9DnqeMTJNcXXT(mwKGCy(Zcd2IowSohmWn0fmTyLjWnjeYzdSOGOi4No(It8wRYtA2FcD5bfaMHs(2qamGB)WDeT6Dp4cCmzgl(a1sI8JcNLe6T)VfyZkXj2HBI1UfB4Xds3IrvxMVRxq8X9TUg6ZSbHUjUZ4gP2FimezH(EZ89gHAawILV6ye3ydGioGRthVFM3DuEwMVyS3aeAeIs28M46d)4WKgmbyU1BUfSDr066FeYR6BKGMRfq2DLTsV3C9uF3qWPHWRs)H3lka5REUXGbk(pyUJAvQhICbuJ)zn3vohVlKeaYulw3Jd5sfHhaj6ErS1qP1PYMBS1r0oeQLvWr(rDX4iRgxMrupEPUZc)23qw)8Eh4Lzy)6qG4LpNBReSWbZDJ4tiDay95bxQl8y7o50PV83pdRrPXbcUaQWUalUEzOwdFV8zXBhMssGcaj39dK4YGIvdGeMekKpUa1dewKglEebMqffYFVOqct9)K4AS9cMIdy)myAKV0GuUw78pX1n4g1fnDYIgJ4GwNaFEsxZ)uJE5XHBmhk9CMl91tTuVnRTMkO3ZJvT)ylFXerEB9BBuxBt6shkkek7ppfD4AZGDSrFy87nULd6HB)z(fdMzSiiXqi1qhxymFgo9fQRCt63f9pjQ3496SVs1MMiCFud4X6J5WhYOeF3iy0HbGLcLBo)2cS3HN3Vbo0nweii98IpxuM)lVFzr(QfD4AJ2nUiDxlPvZnMpE7FK4sxVmKGh(wIcUK0d8Xw6G1ZOtcn0xSqeUwE3z9AsqLSR3VLugnmYSzwSOihVeUszGtSy7HGpR2TGP4oRmkTs)M)FS7M7idI37XM8sfYqVhxdQb4aPGtK15a4StmFyA7fH)jJkzzPX9hQKIkxPjJ1NlFIE)zXjNQw5uo3sBPmB1vc2QlpFEiCHXjhR3VPE0aJfG0XxmCzBaxGeApVAbivsI5uHk9IdWRVe3OqEudXdNMxXffBkPlDeG5)g6EaVpdbTh1vnJ9PRyS(6WCnkn7mUi3O7snMee6Q8bZL56YtrkGtQcuvbP9QR0VCOCtXuksVRK5kAICm)vIp0lQfFg92(CLRKWemyPu5Lovq4rQRIiEYdh2qtPdMkVEMySiO0HrHSqiZ)dESeXNHr3obUQGZZ4HD5n9EkO)RROaIcbVixLTc4jN911CgqZxYUdP6vBAxX55cn)MLz8Gp5V9)Vd" },
}

EllesmereUI.WEEKLY_SPOTLIGHT = nil  -- { name = "...", description = "...", exportString = "!EUI_..." }
-- To set a weekly spotlight, uncomment and fill in:
-- EllesmereUI.WEEKLY_SPOTLIGHT = {
--     name = "Week 1 Spotlight",
--     description = "A clean minimal setup",
--     exportString = "!EUI_...",
-- }


-------------------------------------------------------------------------------
--  Initialize profile system on first login
--  Creates the "Default" profile from current settings if none exists.
--  Also saves the active profile on logout (via Lite pre-logout callback)
--  so SavedVariables are current before StripDefaults runs.
-------------------------------------------------------------------------------
do
    -- Register pre-logout callback to persist fonts, colors, and unlock layout
    -- into the active profile, and track the last non-spec profile.
    -- All addons use _dbRegistry (NewDB), so no manual snapshot is needed --
    -- they write directly to the central store.
    EllesmereUI.Lite.RegisterPreLogout(function()
        if not EllesmereUI._profileSaveLocked then
            local db = GetProfilesDB()
            local name = db.activeProfile or "Default"
            local profileData = db.profiles[name]
            if profileData then
                profileData.fonts = DeepCopy(EllesmereUI.GetFontsDB())
                profileData.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
                profileData.unlockLayout = {
                    anchors       = DeepCopy(EllesmereUIDB.unlockAnchors     or {}),
                    widthMatch    = DeepCopy(EllesmereUIDB.unlockWidthMatch  or {}),
                    heightMatch   = DeepCopy(EllesmereUIDB.unlockHeightMatch or {}),
                    phantomBounds = DeepCopy(EllesmereUIDB.phantomBounds     or {}),
                }
            end
            -- Track the last active profile that was NOT spec-assigned so
            -- characters without a spec assignment can fall back to it.
            local isSpecAssigned = false
            if db.specProfiles then
                for _, pName in pairs(db.specProfiles) do
                    if pName == name then isSpecAssigned = true; break end
                end
            end
            if not isSpecAssigned then
                db.lastNonSpecProfile = name
            end
        end
    end)

    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")

        local db = GetProfilesDB()

        -- On first install, create "Default" from current (default) settings
        if not db.activeProfile then
            db.activeProfile = "Default"
        end
        -- Ensure Default profile exists (empty table -- NewDB fills defaults)
        if not db.profiles["Default"] then
            db.profiles["Default"] = {}
        end
        -- Ensure Default is in the order list
        local hasDefault = false
        for _, n in ipairs(db.profileOrder) do
            if n == "Default" then hasDefault = true; break end
        end
        if not hasDefault then
            table.insert(db.profileOrder, "Default")
        end

        ---------------------------------------------------------------
        --  Note: multiple specs may intentionally point to the same
        --  profile. No deduplication is performed here.
        ---------------------------------------------------------------

        -- Restore saved profile keybinds
        C_Timer.After(1, function()
            EllesmereUI.RestoreProfileKeybinds()
        end)
    end)
end

-------------------------------------------------------------------------------
--  Shared popup builder for Export and Import
--  Matches the info popup look: dark bg, thin scrollbar, smooth scroll.
-------------------------------------------------------------------------------
local SCROLL_STEP  = 45
local SMOOTH_SPEED = 12

local function BuildStringPopup(title, subtitle, readOnly, onConfirm, confirmLabel)
    local POPUP_W, POPUP_H = 520, 310
    local FONT = EllesmereUI.EXPRESSWAY

    -- Dimmer
    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.25)

    -- Popup
    local popup = CreateFrame("Frame", nil, dimmer)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    popup:EnableMouse(true)
    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.08, 0.10, 1)
    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, EllesmereUI.PanelPP)

    -- Title
    local titleFS = EllesmereUI.MakeFont(popup, 15, "", 1, 1, 1)
    titleFS:SetPoint("TOP", popup, "TOP", 0, -20)
    titleFS:SetText(title)

    -- Subtitle
    local subFS = EllesmereUI.MakeFont(popup, 11, "", 1, 1, 1)
    subFS:SetAlpha(0.45)
    subFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -4)
    subFS:SetText(subtitle)

    -- ScrollFrame containing the EditBox
    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT",     popup, "TOPLEFT",     20, -58)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 52)
    sf:SetFrameLevel(popup:GetFrameLevel() + 1)
    sf:EnableMouseWheel(true)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth() or (POPUP_W - 40))
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    local editBox = CreateFrame("EditBox", nil, sc)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(FONT, 11, "")
    editBox:SetTextColor(1, 1, 1, 0.75)
    editBox:SetPoint("TOPLEFT",     sc, "TOPLEFT",     0, 0)
    editBox:SetPoint("TOPRIGHT",    sc, "TOPRIGHT",   -14, 0)
    editBox:SetHeight(1)  -- grows with content

    -- Scrollbar track
    local scrollTrack = CreateFrame("Frame", nil, sf)
    scrollTrack:SetWidth(4)
    scrollTrack:SetPoint("TOPRIGHT",    sf, "TOPRIGHT",    -2, -4)
    scrollTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -2,  4)
    scrollTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
    scrollTrack:Hide()
    local trackBg = scrollTrack:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(1, 1, 1, 0.02)

    local scrollThumb = CreateFrame("Button", nil, scrollTrack)
    scrollThumb:SetWidth(4)
    scrollThumb:SetHeight(60)
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
    scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
    scrollThumb:EnableMouse(true)
    scrollThumb:RegisterForDrag("LeftButton")
    scrollThumb:SetScript("OnDragStart", function() end)
    scrollThumb:SetScript("OnDragStop",  function() end)
    local thumbTex = scrollThumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(1, 1, 1, 0.27)

    local scrollTarget = 0
    local isSmoothing  = false
    local smoothFrame  = CreateFrame("Frame")
    smoothFrame:Hide()

    local function UpdateThumb()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        if maxScroll <= 0 then scrollTrack:Hide(); return end
        scrollTrack:Show()
        local trackH = scrollTrack:GetHeight()
        local visH   = sf:GetHeight()
        local ratio  = visH / (visH + maxScroll)
        local thumbH = math.max(30, trackH * ratio)
        scrollThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
        scrollThumb:ClearAllPoints()
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
    end

    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = sf:GetVerticalScroll()
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            sf:SetVerticalScroll(scrollTarget)
            UpdateThumb()
            isSmoothing = false
            smoothFrame:Hide()
            return
        end
        sf:SetVerticalScroll(cur + diff * math.min(1, SMOOTH_SPEED * elapsed))
        UpdateThumb()
    end)

    local function SmoothScrollTo(target)
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        scrollTarget = math.max(0, math.min(maxScroll, target))
        if not isSmoothing then isSmoothing = true; smoothFrame:Show() end
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = EllesmereUI.SafeScrollRange(self)
        if maxScroll <= 0 then return end
        SmoothScrollTo((isSmoothing and scrollTarget or self:GetVerticalScroll()) - delta * SCROLL_STEP)
    end)
    sf:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

    -- Thumb drag
    local isDragging, dragStartY, dragStartScroll
    local function StopDrag()
        if not isDragging then return end
        isDragging = false
        scrollThumb:SetScript("OnUpdate", nil)
    end
    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isSmoothing = false; smoothFrame:Hide()
        isDragging = true
        local _, cy = GetCursorPosition()
        dragStartY      = cy / self:GetEffectiveScale()
        dragStartScroll = sf:GetVerticalScroll()
        self:SetScript("OnUpdate", function(self2)
            if not IsMouseButtonDown("LeftButton") then StopDrag(); return end
            isSmoothing = false; smoothFrame:Hide()
            local _, cy2 = GetCursorPosition()
            cy2 = cy2 / self2:GetEffectiveScale()
            local trackH   = scrollTrack:GetHeight()
            local maxTravel = trackH - self2:GetHeight()
            if maxTravel <= 0 then return end
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            local newScroll = math.max(0, math.min(maxScroll,
                dragStartScroll + ((dragStartY - cy2) / maxTravel) * maxScroll))
            scrollTarget = newScroll
            sf:SetVerticalScroll(newScroll)
            UpdateThumb()
        end)
    end)
    scrollThumb:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then StopDrag() end
    end)

    -- Reset on hide
    dimmer:HookScript("OnHide", function()
        isSmoothing = false; smoothFrame:Hide()
        scrollTarget = 0
        sf:SetVerticalScroll(0)
        editBox:ClearFocus()
    end)

    -- Auto-select for export (read-only): click selects all for easy copy.
    -- For import (editable): just re-focus so the user can paste immediately.
    if readOnly then
        editBox:SetScript("OnMouseUp", function(self)
            C_Timer.After(0, function() self:SetFocus(); self:HighlightText() end)
        end)
        editBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
    else
        editBox:SetScript("OnMouseUp", function(self)
            self:SetFocus()
        end)
        -- Click anywhere in the scroll area should also focus the editbox
        sf:SetScript("OnMouseDown", function()
            editBox:SetFocus()
        end)
    end

    if readOnly then
        editBox:SetScript("OnChar", function(self)
            self:SetText(self._readOnly or ""); self:HighlightText()
        end)
    end

    -- Resize scroll child to fit editbox content
    local function RefreshHeight()
        C_Timer.After(0.01, function()
            local lineH = (editBox.GetLineHeight and editBox:GetLineHeight()) or 14
            local h = editBox:GetNumLines() * lineH
            local sfH = sf:GetHeight() or 100
            -- Only grow scroll child beyond the visible area when content is taller
            if h <= sfH then
                sc:SetHeight(sfH)
                editBox:SetHeight(sfH)
            else
                sc:SetHeight(h + 4)
                editBox:SetHeight(h + 4)
            end
            UpdateThumb()
        end)
    end
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if readOnly and userInput then
            self:SetText(self._readOnly or ""); self:HighlightText()
        end
        RefreshHeight()
    end)

    -- Buttons
    if onConfirm then
        local confirmBtn = CreateFrame("Button", nil, popup)
        confirmBtn:SetSize(120, 26)
        confirmBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 14)
        confirmBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(confirmBtn, confirmLabel or "Import", 11,
            EllesmereUI.WB_COLOURS, function()
                local str = editBox:GetText()
                if str and #str > 0 then
                    dimmer:Hide()
                    onConfirm(str)
                end
            end)

        local cancelBtn = CreateFrame("Button", nil, popup)
        cancelBtn:SetSize(120, 26)
        cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 14)
        cancelBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(cancelBtn, "Cancel", 11,
            EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)
    else
        local closeBtn = CreateFrame("Button", nil, popup)
        closeBtn:SetSize(120, 26)
        closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
        closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(closeBtn, "Close", 11,
            EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)
    end

    -- Dimmer click to close
    dimmer:SetScript("OnMouseDown", function()
        if not popup:IsMouseOver() then dimmer:Hide() end
    end)

    -- Escape to close
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            dimmer:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    return dimmer, editBox, RefreshHeight
end

-------------------------------------------------------------------------------
--  Export Popup
-------------------------------------------------------------------------------
function EllesmereUI:ShowExportPopup(exportStr)
    local dimmer, editBox, RefreshHeight = BuildStringPopup(
        "Export Profile",
        "Copy the string below and share it",
        true, nil, nil)

    editBox._readOnly = exportStr
    editBox:SetText(exportStr)
    RefreshHeight()

    dimmer:Show()
    C_Timer.After(0.05, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
--  Import Popup
-------------------------------------------------------------------------------
function EllesmereUI:ShowImportPopup(onImport)
    local dimmer, editBox = BuildStringPopup(
        "Import Profile",
        "Paste an EllesmereUI profile string below",
        false,
        function(str) if onImport then onImport(str) end end,
        "Import")

    dimmer:Show()
    C_Timer.After(0.05, function() editBox:SetFocus() end)
end
