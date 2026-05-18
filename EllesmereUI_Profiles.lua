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
    { folder = "EllesmereUIActionBars",        display = "Action Bars",         svName = "EllesmereUIActionBarsDB"        },
    { folder = "EllesmereUINameplates",        display = "Nameplates",          svName = "EllesmereUINameplatesDB"        },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",         svName = "EllesmereUIUnitFramesDB"        },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",    svName = "EllesmereUICooldownManagerDB"   },
    { folder = "EllesmereUIResourceBars",      display = "Resource Bars",       svName = "EllesmereUIResourceBarsDB"      },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders",  svName = "EllesmereUIAuraBuffRemindersDB" },
    -- v6.6 split-out addons (were previously bundled under EllesmereUIBasics).
    -- The old Basics entry is intentionally removed -- it's a shim with no
    -- user-visible profile data and listing it produced a misleading
    -- "Not included: Basics" warning on every imported v6.6+ profile.
    { folder = "EllesmereUIQoL",               display = "Quality of Life",     svName = "EllesmereUIQoLDB"               },
    { folder = "EllesmereUIBlizzardSkin",      display = "Blizz UI Enhanced",   svName = "EllesmereUIBlizzardSkinDB"      },
    { folder = "EllesmereUIFriends",           display = "Friends List",        svName = "EllesmereUIFriendsDB"           },
    { folder = "EllesmereUIMythicTimer",       display = "Mythic+ Timer",       svName = "EllesmereUIMythicTimerDB"       },
    { folder = "EllesmereUIQuestTracker",      display = "Quest Tracker",       svName = "EllesmereUIQuestTrackerDB"      },
    { folder = "EllesmereUIMinimap",           display = "Minimap",             svName = "EllesmereUIMinimapDB"           },
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

    -- Sync: copy synced module data from outgoing profile to incoming.
    -- activeProfile is already set to the new name by callers, so read
    -- the outgoing profile from the db registry (not yet re-pointed).
    local sm = EllesmereUIDB.syncedModules
    if sm then
        local reg = EllesmereUI.Lite and EllesmereUI.Lite._dbRegistry
        local outName = reg and reg[1] and reg[1]._profileName or "Default"
        local outProf = EllesmereUIDB.profiles[outName]
        if outProf and outProf.addons and outName ~= profileName then
            for folder, synced in pairs(sm) do
                if synced and outProf.addons[folder] then
                    profileData.addons[folder] = DeepCopy(outProf.addons[folder])
                end
            end
        end
    end

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
    -- Seed castbar anchor defaults ONLY on brand-new profiles (no unlockLayout
    -- yet). Re-seeding every load would clobber a user's deliberate un-anchor
    -- or manual position with the default "target BOTTOM" anchor the next
    -- time the profile is applied (e.g. via spec profile assignment).
    if not ul then
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
    -- Suppress stale anchor moves on AB bars during the rebuild phase.
    -- LayoutBar positions them from the new profile's barPositions; resize
    -- hooks would reposition them with old-profile offsets (1-frame blink).
    -- Separate flag from _applyingSavedPositions so CDM's early-return in
    -- ApplyAnchorPosition (which checks _applyingSavedPositions) isn't
    -- triggered prematurely by the wider window.
    EllesmereUI._abAnchorSuppressed = true
    -- ResourceBars (full rebuild)
    if _G._ERB_Apply then _G._ERB_Apply() end
    -- CDM: skip during spec-profile switch. CDM's SPELLS_CHANGED handler
    -- will detect the spec key mismatch and rebuild with the correct spec.
    -- Running it here would race with that rebuild.
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
    -- Quest Tracker
    if _G._EQT_RefreshAll then _G._EQT_RefreshAll() end
    -- Chat (sidebar icons, borders, fonts, visibility)
    if _G._ECHAT_RefreshAll then _G._ECHAT_RefreshAll() end
    -- Friends List
    if _G._EFR_ApplyFriends then _G._EFR_ApplyFriends() end
    -- Mythic Timer
    if _G._EMT_Apply then _G._EMT_Apply() end
    -- Damage Meters
    if _G._EDM_Apply then _G._EDM_Apply() end
    -- Dragon Riding HUD
    if _G._EDR_Rebuild then _G._EDR_Rebuild() end
    -- Minimap (flyout button state)
    if _G._EMIN_RefreshFlyout then _G._EMIN_RefreshFlyout() end
    -- Global class/power colors (updates oUF, nameplates, raid frames)
    if EllesmereUI.ApplyColorsToOUF then EllesmereUI.ApplyColorsToOUF() end
    -- Re-register unlock elements for all modules whose bar sets can
    -- differ between profiles. Without this, _applySavedPositions uses
    -- stale registrations from the outgoing profile and anchors fail
    -- for elements that only exist in the incoming profile (they land
    -- at CENTER/CENTER = screen center).
    if _G._ECME_RegisterUnlock then _G._ECME_RegisterUnlock() end
    if _G._ECME_RegisterTBBUnlock then _G._ECME_RegisterTBBUnlock() end
    if _G._ERB_RegisterUnlock then _G._ERB_RegisterUnlock() end
    if _G._EABR_RegisterUnlock then _G._EABR_RegisterUnlock() end
    if _G._ECL_RegisterUnlock then _G._ECL_RegisterUnlock() end
    if _G._EUI_BattleRes_RegisterUnlock then _G._EUI_BattleRes_RegisterUnlock() end
    -- After all addons have rebuilt and positioned their frames from
    -- db.profile.positions, re-apply centralized grow-direction positioning
    -- (handles lazy migration of imported TOPLEFT positions to CENTER format)
    -- and resync anchor offsets so the anchor relationships stay correct for
    -- future drags. Triple-deferred so it runs AFTER debounced rebuilds have
    -- completed and frames are at final positions.
    -- Position re-application and anchor resync are deferred to
    -- OnSpecSwitchComplete (if spec switching) or run inline here
    -- for non-spec profile switches (manual switch from options).
    if not EllesmereUI._specProfileSwitching then
        C_Timer.After(0, function()
            C_Timer.After(0, function()
                if EllesmereUI._applySavedPositions then
                    EllesmereUI._applySavedPositions()
                end
                if EllesmereUI.ResyncAnchorOffsets then
                    EllesmereUI.ResyncAnchorOffsets()
                end
            end)
        end)
    end
    -- If CDM is loaded, it calls OnSpecSwitchComplete from ProcessSpecChange
    -- after its SPELLS_CHANGED rebuild finishes. If CDM is NOT loaded,
    -- complete immediately since there's nothing to wait for.
    local cdmLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("EllesmereUICooldownManager")
    if not cdmLoaded then
        EllesmereUI.OnSpecSwitchComplete()
    end
end

--- Called by CDM (or RefreshAllAddons if CDM not loaded) when the spec
--- switch rebuild is fully settled. Clears the suppression flag and
--- re-applies width/height matches so all matched frames pick up
--- the new profile dimensions.
function EllesmereUI.OnSpecSwitchComplete()
    EllesmereUI._specProfileSwitching = false
    if EllesmereUI.ApplyAllWidthHeightMatches then
        EllesmereUI.ApplyAllWidthHeightMatches()
    end
    if EllesmereUI._applySavedPositions then
        EllesmereUI._applySavedPositions()
    end
    if EllesmereUI.ResyncAnchorOffsets then
        EllesmereUI.ResyncAnchorOffsets()
    end
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
    -- Exclude spec-specific data from export
    exportData.trackedBuffBars = nil
    exportData.tbbPositions = nil
    -- CDM spell assignments are NOT exported -- users share spell layouts
    -- via Blizzard's built-in CDM sharing system instead.
    exportData.spellAssignments = nil
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

        -- Pre-check specs that have data; all specs remain selectable
        local preCheckedSpecs = {}
        for _, sp in ipairs(specs) do
            local numID = tonumber(sp.key)
            if numID and sp.checked then
                preCheckedSpecs[numID] = true
            end
        end

        EllesmereUI:ShowSpecAssignPopup({
            db              = dummyDB,
            dbKey           = "_cdmPick",
            presetKey       = "_cdm",
            title           = opts.title,
            subtitle        = opts.subtitle,
            buttonText      = opts.confirmText or "Confirm",
            disabledSpecs   = {},
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

function EllesmereUI.ExportCurrentProfile()
    local profileData = EllesmereUI.SnapshotAllAddons()
    -- CDM spell assignments are NOT exported -- users share spell layouts
    -- via Blizzard's built-in CDM sharing system instead.
    profileData.spellAssignments = nil
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
        -- CDM spell assignments are NOT written here. The caller shows
        -- a spec picker popup that lets the user choose which specs to
        -- import, then calls ApplyImportedSpecProfiles() with only the
        -- selected specs. Writing here would bypass that selection.
        -- Disable all reskin module syncs so the pre-logout sync
        -- doesn't overwrite other profiles with the imported data.
        if EllesmereUI._reskinModules and EllesmereUIDB then
            if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
            for folder in pairs(EllesmereUI._reskinModules) do
                EllesmereUIDB.syncedModules[folder] = false
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
        -- Don't ReloadUI() here: the caller (options panel import flow)
        -- may need to show the CDM spec picker popup before reloading.
        -- The caller handles the reload/refresh after the popup completes.
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
                        -- _specProfileSwitching disabled (see doSwitch comment)
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
                                -- _specProfileSwitching disabled (see doSwitch comment)
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
                    -- _specProfileSwitching disabled: was causing width/height
                    -- matches to never re-apply because SPELLS_CHANGED fires
                    -- before PLAYER_SPECIALIZATION_CHANGED (CDM completes
                    -- before the flag is set, flag stuck true forever).
                    -- EllesmereUI._specProfileSwitching = true
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
        elseif charChanged then
            -- No spec assignment for this character and character changed
            -- (alt swap). If the current activeProfile is spec-assigned
            -- (left over from the previous character), switch to the last
            -- non-spec profile so this character doesn't inherit another
            -- character's spec layout. Skip on plain /reload (same char)
            -- to respect the user's intentional profile choice.
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
    end)
end

-------------------------------------------------------------------------------
--  Popular Presets & Weekly Spotlight
--  Hardcoded profile strings that ship with the addon.
--  To add a new preset: add an entry to POPULAR_PRESETS with name + string.
--  To update the weekly spotlight: change WEEKLY_SPOTLIGHT.
-------------------------------------------------------------------------------
EllesmereUI.POPULAR_PRESETS = {
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_S3x(YTTrYd)QSVaYfXjbW(xsw(qFX2sRKC2KT2QubrcjHvGaCbbTSsQ9D)RpMtGb8qs254xCvjMMeyo6PV7E6(x)HvHzlk6YHpKKvSU8Iz5vf1tEvC4F)hwnnB1S2II63x7fgoX4l(N1(rXt(7)p8T7ECzb8x3SUQcFJVu0UQSPUoaE8WS550q75NTUUQz29Fi)XM1DW3mnlVE2DnTRWFniRlV92IUxNVQ768w4RIfFJ6d4B0CZnRk6(zy1Ley(hAMwvoVaE6Jo9Ylp9J6N(NQPLPFy2Rp(JxnB9QUMfx5n5k)O0KjHHxL6zoBWkHESMMQ5npuVYCwpGM2q)WKK4jXtN6PN2GSlp9mZ58GPrVk0looz6epVPEP4sWZJg71DLvLDpUFZQVNNFCWe)jjmyL2SdMvXKgfhMg6f6HtAq2YceCBapxwL)yr7WDMFO30KjayjnEZa0dIJFvCCSyAMel2C30Gqx6C0CcJYOFWC(8Wxx9NPByhfg8kRdAem27iYcqon7nNF0vVUkF1QZlw1SUDwXWnQXiUHPMqBGZmAab8YJSXl922u5X7YGyVW0jjPBbKobrxIsJcJsstcdsOj3xqemeOkpohqve5fdVDcIPSH9gFaoneOaau0iXKrNtoibDCcI8c2gjxA2fDanErpaxC2qeWaA9iXOmiSIYo)K39(lTiT8dyKcp)0KeFcsLsNsN18qHfVJTDg9S5JKaSrI9sdIUkDIfFeNBY0xbCe0SeuqWWSp8M3AThhSfrSHjzpuoV7UpM3n7oMLQ5b2k1PuFcKvUbd2O2J8qgawNpbtICxr5T31XlmMcD5D51aJ2JAwxpF1V()GVmolF(8MAKDVpquvvvSArrBXNp5WzDG4cajHKemnBE5Q8RRkEBt7IZYVTS(23sF9Y1RURy(Rj(3VUPQbpO9aziiYIx21OeRjOilVSBj5dibNxwl850PbecEu2Q7AE4OQYF5xozgmJ0aNkg4pVQG4Aqdn8d((YfYf3)yB5CyDOwnW6)oG)lsPaF9H1LlYXTWk4ie36TnZExvZd6fPCr0FXjx0O4jFyiV9UkeooyPmjdy2N3TUnVR406xlKnHlYOmPKQ3m)2I(VOhGfsqTJAANx0Er5VuutGO4SR1qHdRWdlcm6NbcFpRzvjTDivdGZLacs)y9bErtFve8CjzTfvN1uw3bNQV(nF6Y3C(paOFlfFJucSx2xR9eu2t9Mg5NsNd0yg)CgZjHeRvM9flAfyg)1U2CbU06UUMA5mep9vHPPPbGyTWKqC)VL1VChHRF)eIxtSxcWxLL0rRF)NX6)ahafGi6hlURCwvXB(Ajk(Kb4Xmld(pOCY9yP7n1I9MAPNih9qVeIpAyq0KOeuM)ECWEGNyPbsRIIsiDniitKC4JMsdpp6ri54Em8KW34SZlwYspqWr0eE9k(Z2hqZdsAaJY(PZ0JxyQPEi7j0L1oWp7n1ZaECDfTgJRqY)t6utOtnmAtviWSWrjj0EbhpWp1uQJpUQNM9X8sKHRCc8NqkRk1(ypbSKEUkDbPzaWM)hRlwxaY)7wtS1rS5GjHgca93VP5aFp6TNonbMRqsLfBfmykMP8CSZaltCKdcszmmdnlIZoRqO6hnbGM173MWKBO(WnurLeS38uHrbHXPAjg95VRfcXwZrm3NAjR4PjcnnB9QcscAE78Jbt7qX2Oy0yRbNK04)kAA9Yw9FxN3wGICjjKXzlAGrPbSt8cqE8Hvv4a4RKBEjyojyZg9KgZ2fDpckfWdyrvXSoqSgm5g4agQjCzXxbXLf0qXiALW0)VAAwuhrIWar4s50oe3Qef)mu3ieLLAld1hasaVItfwXEaUYafgUMexDgOEeOnbTC9cZ(s5Q3d6y8PM3uxS4rEFZMb8prLajauA213(MAuzP5WdmnRE9IZBEyfFChNHqyqZLIpTEbb8LdnTiEBtDNgh4AHAu3k(7w4VrCm1649WrgRk20ScEkzTDqfH(y(S2geKJFvy29fpEDz9CEBIMFtl(M2YIAGFaQzbOkly5F5VaRH8kcvwQgdok)m)M8lgjvd7sqTNUYLe2MFwE1d5pIqO5f14SMK1SgaSNNxFBbTTu6nAoYBFdht6iYA6DyBlanX5doJYB)XYvLxtMUdYrQlaGlT8UM0T6sq2991fRwH(d5UYAlscewtKeE0HRpnhWs9E8yHvc1Cv(tM7FqvnAcSuoLOLxCDEhsaPXaaOWD85eI6y89rM4cAueyBrJT4jr4yK80tVMfmpyiooHhr4RcaJczI2GOnNAKMpssgrCt0gbyj9dmMb(fHzlqSMDdnmstoCjrdimjW4y6CuZz(SsnWwWCdsVFIWYNcupMCbNqmgitjKMrinHGOfMiGw8OYKyRUlFzbZ91jdvNduq2TaI1XLTatmKAWpB9sceXmcUahtanQUPUGWSnMeJtkGzsfGZD5DTnRV9oCNdNY20aKmg0id2gj0Ui(tObjKDZjipdM5aJBAWC2a)XNHPsgxe8X67eu59O9)zjjSXoGGEOUwkC4E4QsWaZMZN19XqdyLtrEpz0PusbWV806QhpPEf5ZbbBcgIkEshJfGfkLfPndcSAIqSitznEIlwwumhHHeEcSo3ZZ9ytARTWkYYoPrzk9nrWHwpbKz82zzgYs12nkz7txqnoNew7pSDxK6KGUMURe0iYKjLqYgZ8t47bdznwI7gtkZgKcmcN6(suIfs0gNpW(G9SVczK(z0KKAi)LVRsxyTlSLUWSOu6KyiEXTuYVZYygxlM9vuJt2sVWIBS1HcLFmMKMNGCLbY7hiOXsxyH4JVNIzCOESNWOdPUy9uBlgvczBYyyoAdvlE3KPmM0xlZgKXLONf2dppDpAJWqs(19Kg7gtCmobJkSCdS76XNrk4J8sLdZp(MzV03BXEwcw(2iWRVzwU1J4zAH1Zx2N2AQrub(BPOphwW(hkjFJt3(908QxorFFRTY6PimBmbJdmQ1PAi)2j6ZLADFtL79mmNA3f9z4e)VjY8I4WSwhoH0hWTeWDwGgOhBSi(O1EdnMDdMx2ZHzV)0Zp5FD6NU8WpqQQ5WrpUdiXZegnMO(TRVGT5YdzQ6aWsX8r7V9XKxnQl3EbCB63u1agL4BixVxipR6sdQNSzUJO64isT3zseo(bcVgVBUryVCHQtpS7Y8NVJopD)mV9pBc5)EyF7)xxqVTN2cEbSTLhJ92uLxAtF15FXFsnpCOFQ)lBfhg5T)YwXrIb34Ej9pBIr(lBfPKH)fjAC7OTIIGe(CCr6lBy42D7g1zNwV8WGaGpJ0WatBsZ4mgezD9eSZ9MDkMABpvoKe57rO3cZUAv(xOSMXiLp3qQxS3s6Fs5(XU7uYVtHIlvht4FBIg3iSPF2ULCGw3IeSXWYlo3gglJp2pJw(Drm5gYEGYZ(FFL5h)FLqX5iFJ6zLYqoNULl5isC2jd3toeCUSPqNCJMHeSFM02)nzQLNCY91xQsO9LvHsGjRe(7LID9tY9qCIDUx(WzptNGPImKWid040nuKPKgzdGZ0fZDEH5oxSg4Y(niLCQiBH4SfuLgA7vUhSx5n1E7v09ZTD7v68muM0qEzUOGFkoNzy2aJN)Bi1jDKlJK6RdcBJ78mXT8RbxIiCrmIeBhU7fVge7R4hhSnFIzE4i37NESohpCxBkhETDjlcvCPM9UNFHUz66m5kgKFUgztLR8mPxsOnGXQZCB0z6FmiVYnYY(Dst)DZ5ydn01DWtitCORwWFzIJ(wT9xM40pum)Ljo)LjoCsU3YvhHV5j3(FzItnNq7oCo0VRnXHePqxfXxyrkgkDqMKVTlVeLyL7LYP7BO8DDo8szuL99FYkt0DeP)Nzk51ZFKrIy)13OzHbQJCZMCBMXOALTxrKFmvRhnXo2tBfFExSP9Znxpftz2lJdF(x(P)4KDEJEV2CFhOgjgGdSk93UuWBeldTTaHjqDCf5eU2qF5lDNnAMogF3mOypDvJdR22qrx4pyzCws2hlN12iUp8pZf)2tloJyV8Tnn67D743fX3KwX)Epj6gXrGdTr(BJS7(jv)lAg298tM(FBViz9U8Mw15l6sF(SdI1EiA3IH6(ju)pBzkX3JeU7BRjE)Xm16XI1NRIKWOQrVtxYm)b0v7QuFxf3a3c3Jb7(U9pDYenROqFtK0)h3lpaweYMOlPm9RGkErQcMISWaWLTmJk52hFS7UYzxwUGQcF09vT5HZQwV6YhAOVLVLPnx)FWkFWxk67H8jVIlAByHkWO8TroOcgSLvLDxuH14pZlL(KxX35s6TeFuu(ssXY2H4onlQmf4k6u58lkhn0a)28vDdgyX4QlAcHIInwbvuwAANvS6SzDN1SAvu2ho8O3G3nJGm6xbAh7LjTcOvzeVGXQWqGS2lIlmQuVaVhxqtSwQi4dxU9Yeuca3w8LYIh4sIrhcMfGCxxDFSUpOMBbGDErE3D4eCs9LLDCr2rmsV5RllBlMBVrOGOrBe(tu5TJgRGmASwzmqivw5T1hwvHN2aysuphb1mv4bRmkuh8(MWwoQTi)ESkSYL8f1J)U8LCzSBs2nT5lkKvkc0kkFpg6ZNn4uI1rW8oQQHE6N)0LxD2BohR5tKIUD429ZRkoC2SIAQ61WtpbaVRTOqH1ovJkbWK865fZR9XjmkBLUelLWW)tWIR1hkUPtwtCcYWQsX88QM6cazHQ(T4mw0(t1jju8N8J8sJcO06s(B)mmdtFL)Kjt88HpnHQEEPz53Ct5xnGytOLmVfWAciseJv)ffu4d5xxuHBop(jX3NlqgHMalelon7ZF643C(vhD45esGet2cgfYNYdPEdiXDeMH4JeQbTU9dPj)ZlN1SOS(2lqAoUwUqReamQGqSfsISYtrxiGLW2tHi86MflZBl(yZCSEP8Pt)0Bq4tx5S71gz5ZbSfF0QIUI5FSSQQCvXSM65e5p(8ssg8eVhRf3CaWxcWC4dbSW5bZs)v1XfvD541fh3E8z0XeXbpRxxSQtXiIGguDslklkkjd2KPh4n5aVWP)ADuav2bdGFb)xPE)9Appa3R2lA6u4)pnng()baeNlYL(bPzWeOhGGKu4bMehIpCiWmRoc(uyK8fOz0ZCgtXhf(dxe(cN4N55)RWqamUQJNaJMFKpoeHjW)3pEkV(Gj(xRdIGFoDkoaX(4pNKIZwa8nInb8qrWRZlwypzVyJ9XDZO7Vy4nGThciuJbTHtm3WBDnKWGv1MebUX)ADYeeScajylaIsaWfqqIlEQy5GZDmSAh)5aaTCBfBFiM4fGGQay8ttXXCkDckgzbGW(yxCqJWW4q8HtPvCaCCZtcDUiXuINallFa3imfrksWv)KeA74rNp4QFkSO0OqJpYmm2eJW4adbbg)0yWmgwaGb60zBigmSfxDBgsfG76TUt9I945mbGytdrq)KjWHQ)eawa4TCbHfNteZhHiwi8mfe(6BGWrqxSDWoDmblgGjoCWpfPH8HfaCgbeyWzl8f6fdE8iP3HDX22cawaVxTi332Mgj5(16TqPjrWmh6nVfKVHVXIzt8mODDBZdO8CKjQOWOXY(zTGcY6aMYaVZQ5AjE(b2mBj(628T1cI6RUZedr04mG)BGv(wlZrjOcacnn84kkVvvm(tGIilRY7ke1Z(7YxD3hkR3(aJ7rqnfqX2ok5XqWWDf5vD39P1lUMkYCEzDnlXhGRRIeSAQO4pJ16oDvbJRAXllQWcqmi0glaIYkASSKHRQkyrAnsPYtoRjxiW8K1SFgx0Z)CDjQPs76LDLxxvOEDxQDtAGZCNQa9FW1Sv1SdeC2SSf3Md(Pa58juyhOu5TUa4CzZsq4oPqccRjfDYx3MFmwwKlBQr9d0PVmS8lxSSPfuQGAQai8GVqYeQbOEBdOpaVcFhGdcYLdPLmwfBVPPg0unk7eCFFt(SI)9HZNFA9Q)THTo)7ffZlZ)30J(VbvcbS0vpK)4RU8suhSaqZ0YI65v0Af1cqwudpG0Auvmhf1Nt(QMJxuC8Ghr(5cyPUmWfM1Mxo)J5T3lkKZ(KkWEmu7wHotSztEz1WSAvgfbntnrY2k6oGC3h4U13b4czCyzEUdJ2mS4AtfO9(1utSa1zqVY1WBzbOeu7)MBUmV((dV922gfUxcF)hivnNgRTpZlHlC(GQ9mfJfqatvtqZ9fLu95MrhOPddy6n3G1bpMcJ(YWmfE)5f5ZXg2axn90tny9MKSbeQZ8eWZdHIT)CZAJc2xQ1wXGMDs2)DnOn4hBUMaX66UNF8qKyvHMKrKbIAn9XwpHCrvGmPwbYhnyQC6xkARYFuItjar3v2DDZxje2FcLNYU2I2UihBM2JSbBIXP9BwSS7r3fBwx2rY6fcdRcDbnlbD(xxxZcIYfpQOzuvOYvuZWVNq4Tx0Lp7(Dkb8aovQQOVKZdV3GzIMuhCQ0KI4Qdq7fm1OLoXI6KAWIJRZ5k5nvcgdi(zCryu8zvzyKR8Cc22uHULRvRtT3mg3odfcEVIfQj7vnUmCIyr(B9syApuF)7ZxztIfRpEs025pHyVdO5YX71KzSwKzX8Px5mfDlBHNblxdYmy6fyWOfZAgES8hK9PgZcOj1Njgcdz0qI(vBmoiRrmW8ACRuhWsuoLwv6smj(buUDQyioX4GK31ZyhI5czfowKIjodvDWckY7jC)V9f(ud6fRZ2OS7XAek8FgmIKkcqzSUgGbdIQlNW4SAVXjzkdCBn9agU6SL7646HJJ0eQ41Zy)YpJy)4N5ijRj4pYQQSQBVdteOH0yyIscFM9qOeyoW1BHuZqr0ziuSSd8y35byMabWhAWcNRnnGNgcmvtdWf7EdwViIRgjf0ueqxqUgkvkq3BuoV4qGZK84HgoGr5mBPodOSmpotYwuwxEnWYrXwjnr3Zl8bdDKIJI8ibH2cEv93c0he95j0RQlRppmiPIYKQ1Ewrl6VPAUMaqCahtHpdMlgLuwGNTPcjw04KxQQQoUabKIk5QPKB2rDC1WwiRAR0iatjYdVAixS2TXrAni8dKNUovtDAwDX6U28knJ9nHJeOO)26cemQg33VvO3iWq4XIwYzrGo9lx9PI82Dh5efbR0drx6OfaoTgdwh6AgMicT1pXoVJgisho2r(McBekrhLrGnI8qPAGvLaNtumuNCeZ3EfXmQnWfmveantuC9Jr1BjJT2W63KWbVXfMAiJv)Ddnb16ujslyZFSNHL(6JBPPLc3K1LVCzXCT1vkooALezBJsZMty2JRed7UqUUsJKQUmMH0sGRJ131SQR0WYSj61iFxo5qni9rVL2MAZ5MQPhsmIqHxeZIoGpz1MHImE8bJLeiS49Y64IBYxxrcTe(xwzqdB6mz6QMlIf)ancRL0xnBDPPu8nUrHdWCaw(J1EC1ToHLLWM9kwCo4yyPDlhQk5t)PZEnT8TTxGvuMo01w32Z(cnxt5pisPg(exZRxaimisvT0OXQf)M6JAnTSPAxSmFMQ)byXqUVYzsn27voVn0V)NL63htdnkI3PY2GKtnVedYwnZDKtY2z9fqGFkKfNjciqkRwUG9U0Cy0r6DTLaD2bFXhoia1GT0XtR(OW)i7Q4bGDLbr52xXP9SZRxZEk0ZBAC40jrjjSXKSE)GI)(rHPt8sJfAKqMgy)1SZxg49IEZqAQxCmyUBKh6PALYnj(tJ89ccsM6tDkqwrUWj(EXHrbH(PHWxZwiRypV9DlQHekSLmBgz8G(yOq2cVwxYe1sFx0ZboGWR(gxmG1iXc1WRjV35yXAOYgx3R7sGAW9PMEci16C6l1EJfUJ6DP1BvuvP1JTgtMpMTCsdWEb(kbELbdmghgLRr81zooSHq3uoJCrfPtOPXQtZAZBlEtvzh1EuylA42SP5nuNqs0MJj(iYth(iUFaoaxVQP9A(Sbuav0Hwm0tQNRfqhhrGGTE4d4Isw8QtfMzUhN3Q9TAsumNJ1Yl6XaIcWlDiQ7WgShy6DMG99mLU0bO6g00TcnUhy1zzsddaEDvrEnZzN1m1x5hsdtoN6WTkOVONnJoH06Wy7UsRTHRk2hVALpMWcElxoPeARCCNT6fUAudmTbybVP(Ud8p4ugSiKcyIXkCWHsq)yg2ZKgMEIy79Oaaf3WNOS8to82modzOI7CAYvAMAOMPSDbbSEavBEhfoyuciQs0HKEpPup9Hr5XCyc(HA7eKadtBvHuqp7SooCWNxClqpkNd54YZcWD4l6w9I1vjnNcYobwqnZdaQ0ZrRrfJSwVdsdiUstqR4JKRFHAO463kZbgGojFty8HNfNjymGzs0XeS0pKHr8CicYpWESc0xb5c58(dmH0FI2jWU(vK50a)381DnyMeSSJplpP(laVjsziJ3axjrS5tUY(vxxjFFSvojsZI8RfWoCMjyhVb4TQ5eHa3Kyrs0bdGDtWb09mx07iRRbBLEl2wSGnHbgPShWk6UKMU4ind4nd8QNDVcaica1heFpSRtGhQROE2J4ZWQ(hLDBB(CSxgP5)OEmAbZiA(z3oBo1)lZBF8CzhNXa)fOllRQO3Wlkoj2FAy0Kus)swwYflbrSYuibtCwPwTCl1bO4rgPnD5vQyGWykc84q5I3Shrz18MqxosZG2ZIPQThULJN6njysCCWKqU7Ak7AZcM8dqB1VotKAdguqAEVJ4rbkfIMMq(VqblLu5CFJMtBgrpEZUXgU1gINvFaSFRJgWz0OchIE9cp(SzjORGVwDGqC5kOmzexm1tWq0SsEEZT46FU(Gie4j4xq8Uuz50aUeAqidFctNgKe45fonLOeaJpyCs0IlkdNSN7JeChzuiy1WH5uDwZvmSyooOQYhMbYQIzfHSYuLIhxjBN01bKYwxuHKqiVorM0y4KAdaY7eeaO66MX1cbjiqNuvJ5n)UxFSKSrK6msSuE21WhbTtsqW0PG6WbXKvvgZQCK1hW8bdNLxIUVLmLnfnyqJwne6ffKdzX83Syj62Jl6YVL5gYuO4wNoVHTVcVfp1iwfmsUGoaSaqW244YwCrAvpNTywOqc1lB(iHhqKikmnzsqQVGVbN)aS(37Nax2p(997SUh7kASCMIDLDHD5HbWE7(lVRybM2GIaaQkIuQSvuGIQthpv7TcoTKr4NpBWZp53iGDbY(YZCGL4SvyFzsYaP)Bqa)nq)oOadPBQ8hqD8Eko)60htjI3SHLZoZ2HyoBX9Jj5LHMeDIPwn9K0pycvKkcXlkO0zZK(H1a0rcSgrc94y8szsiyvij5va7)(TGlGBG8islBPh6(MkF5mANvKkgrPljkpPC60SLTLlaXPJ1Bqg5Ql98qXfAuj84nXOBmCE(40qelh3nrkO(SW5)bm97(7x(d1(XP)9l7tbKKvqzL6j38PgPopanxAMPWtDhAwkq0rd5LaZmgkRgHs2NTOpuuKbTdjF77lTJOh(ziKsPL8wODCrMy8DsEiUnCz3ir2OqfnLBEBxzELmlr91KvAA6FZO1UTauQMd0XGU3PLWlqjqDcRKKL312mRS7X(klkvDe0gcZEasVlorCfu0o3PJDDe7rthJRHJivjmvFJfGylYIUdAAvP3ibn)22e0BtCLw3wP6iY3arSsaT89bnD9MqzYPuxeHA(2KE2KVSUVHin5E0fWTlUrIKeMvr6hZRwxSA1KSbuUge2bObjSuq7BhQUERzl1ljB2DONkMJANrTBDqI(YYLs)tJJI40IzWWYzm(AHHSH4BDQDxJTpENwsAFfbiRxypTIgwWPCbZGq07oD1nVCARSdBCtX1MSTsk3eiYNyz40bckidJvQ(N8ks9pXv(uUBK30mZit2nyrDMnJdSNZkstYxJ9Iro3GWge98ckEDNCJHubb0N13W2pdMYW12Nswejsfp74rdqbzorYTfBDppxRSAk3VQdnnm)F08bGXsC2S1TRAWGYArL5YdcoKTB5bLrk6F99AqaON8xHjEYRp2p94n4DkL)kiNKW2qHE(91LTZOyTzPCRpyFfOiS2LaQ1gLmrrz5KtjtyCfEje82dN(wqkDCgAzW6vSllNMH9UyGFa8914Dxb7wL(zLIgBQuwra6qfRi7ICE7YNDxXCu9Ga09d9wLQjY3Y)tJVcFl9hZ1ey8Pi(UBDjr2dyUKIY6AZlfD77(7hxosAeDc5OlHwrc4KiW6kgorsuUgMXQcaBFSswJ7gp4CrwKACVAIYKFPvGYWuqc1os22WHTjA3Qzp71cxU)WiTBIQCZAJLnQKCCmB37BVopc0igmWnfwf4jDpQ2ccduOF8Sp85lU6WpD8vNF4ja1rq2sRRRei723JVVsH(HGj3O0b9Dz6GW4jVAc(NGeVWPaD)G8K(Z1LDVfV1w0behfkq09Py0l7EuYBEqEWAQwbW8Tzvj16KXXiq4zCm0lWibF1UQOlaJPGmYEwx6EjFypaBq5F2pXTrC50swkHShzViFrpM(RWruWR0tcYVExx1XzlPCdrTE5deJ1Rx2xRpiGAtX76GcRyvAqUFarZWlakOa620tqW(OSc7jJENho3F752ZmLuvaokuB77YdP)fjG1J1(jwuAiDla7JN0)ezxpga6nlerXaEqWtCe5GdIlyP6xKeituODo6m(EzZlybmN10ISY74wvEcqpY)BcZx(pUau(qNbCMFVWXha1pJjlOCzFrMsrSd1hw4SrqPTURjjDOd7eFjhywatvlcK9kEeOsXQUMfVTSQQxS1gg9Dk9Xn89o5IBoBz8iNXlCYgN5m4L2hZP3tQNJb0f9RRiGfK3eRppVCoNBkuqJrVwQtFvINoNtNsV1lEDpXvb1yl7q)hFmRHSH(C(bP4CYzTSl1G8bl0maHFOHdhT(Wjwe)4bHpfVqVymnnJ2oqa0DD)Zk1ErNA0kxlZmZfAlhoSeFNiCDPvAMygewlSez2fiYrFlqTykrfSWP84Yv4Rc7ZRB6UJ0GdHdCgltNDjzlY)6rywgYxearqR5aJdpwnMdNIxgdwV8gyye3FGwc1W(8IVu0UQar74(zwvroC60dx55NA8GTu40XADtN4GopYnLv8XsWVhZ)gvZ5NVYX9cYowYwSpG3C50LrioKcSHoDBSruuegg3pBVeZQwb5bv44agk11Vbd(iF7bKKpCwcS1uuatuleOG32jmXmAbop)kQeSmdmiBGuzWKmtc4muKJYgnrkKynerTtmCARW(rLokskWu5LFWMlbhHAGVeYcJ49IRgva0OSQdptutL6B0866nIuEIiBflmFWH87IdmsvrJSxoMVp2ycp5IFcPajD8iwPyyM0o)ezWIBeYL)9d(UiMK68e9iyHrQ5zrcZ7lIpIylgHFMU(BAYU6M6cuCGuEIsCab)eRigOH4mkCB7Ge)cKz5GGpmcK6D1LnKgSCMz2Jo3iPuaLBvjmlbvrLL9XInULuefEjyVoX2convsrKYk2onawyKWRRcIkja7(cU3oOWSxcCgnGwJJIo1h9YJDSYnO8EnNVp287GDvp4GZ8fenNWKseo2lQAEGusH(fbZDYXzde3APpGrMclIZmGbD0Tw2ryEaaGen5D31QLN(QfbNLMyw8DvtB7VbxpZu4AaJEEv6G8QFAylX41tehvFdmzLiiMwazNzQzXUGuyQWbV04GFEbSZevIaP0d7fcxSioPgD10J4tklNlOgBhszBfXuRiVMOWfcBmOFPBPPPmxvB(3uBeZR4Okd6i2XSpxOJvBn5g)IJXP7vpjCPCMOrc11zgmbovCDS(Eo9ETvcatxgsdoL6TICTt6HdYjQ4f)qXCMemtm1usG7FhofztS(RpelwkgzGMVAmmDvaL0RuuwrqHMfPadhWPnu3JFqkBTz9pXIIdiH8FExr9j1yg08fkpHc1f)NTIyjen8Z1hiudByLQmrdenbUAGIG1nYKYLCi(6FBUre7ozjArA5G8AeakYW67yKbcI1PGpg9dIK4Hi1bMc9uFwQlQPzfcD618YnZ0A2dgkL9vYZmy9tikk2NaCbfMWNdAjjycbQeHj2Ptfce6PB5qpdDnRjiMKXsdye5fQgZsRfOAJaBFLAiImT0a5LsXm9fWbjauCnL3vAbtbC3yKdsOkPMYIKQSlzRB80gjnoygPP1GICmnH4UJ2pJk4PdMk8nfTlXecDQ8C3M)fFptKwQYytM83f8PnDmGnhA14AX0yBxLz55aNsDQlYSszCPDhaUQHo8mfR4AkkT7qW0xKdYA1unUL7thH4XIFPtuJjOLpIByL62)sqmZdbovxuSp18Ca5BMat20nPatUEnjzusLNh)m)5KuXEk)m8YGltbw5fxrEDS6PRUszawNL(Ii22foe9YGL9z8wJlTkBIjVYdnWwrRYjQMGiWsJ5aKDMQTVdqmtQgrgDOfpbZRiWCob4Osu2RsosB2LolVbExAVegOiSKELvXRJztOsZCbeAyQtVbbUJXq2PL6ckgBsF(UQPwi2cJKF94(IzJkKjlvhYqbkYo3(wWnrtcjMiH7nuGgXXs)VMHyBW8M(VGazyuvECiLXOQtyzj7qChXGpIyjq5INePypKeesWUqx6HpJBg1KxfrAYW3NgS05W8yXlrdDzEJZ6A6oJ9H6FmOqDQY6Us2IB)rpoST1AleLBGe0vB2vRr9qBuyRy7Rb1iKGICUwkNM9DwpEwmENMV4Uy0VbxVEYt3rA29rDyq)edacLt9cUS99UJBc8bV)tGm2HBK)M6lC3U)cDX9llxawPq2bDiv90SM6QhzTumUH4oDdBFlYChXbHB511kuMfZqhJ2ZQNDYNNgosZP3ugH6DtkdRUwuUuwNnA2q3oUEdnQh(n3Lk3Np0P)Geu3K1o8kGItJtfU3KxwgZCTEKSHKHe2JUB)5dMgBQoB)yh4Wsi3o9C0ikWxcJDZHNcVJoqbBh((At2740RwBwFCqWOoSLoiGqpzUrFdSJIs1bTX1HZ4QX4iMFshvuG(pHDFb2RhDh0VEQqSnUNCa62DxRYbkq(8gMSoMy6rC86iwlVr3n5iGHUCa7aDW1Uw1HLEoW4SlldSDFdzdSrFKckIPcqM7G)fyMBaCw0pIKZ91tNBZE0DiqFKhfUd9OG4AiQURXm0yONuXBbsjwxzfYHOBbITpaXCFSx864OEjcGMPRKbqHc(X(bu5Mf3Q5pWYWTkYYHU2JBDKmaqoLBni4zkN76WUFxo3YH(koJhO03pd9vNt5VJO8iwe(TIjS5P9DapgkT22QFp7z3CSiaS98nHHdihr8UtdJFkr(0KMBx9L3MeU8SIjkhYaPRnjeRXuAW05rA3YUB(SRVHaBmMj7F4whrfDgY8eI0kS8gK4aC8u47uMD4v3z3eHLfiZqXtz4hgaqUkwksTU(oME8CtzybMKcoXOEh4PRO)Gu2GVnlyM4n2f75jOZYULUsUDYRvwmjYwPNzEjnQhzgX(FjLKPB1h5i6LnbImYrgvWmgp(uJAxXUPpXZlxICOorVWXmscbPz()uYii9BVNPe0M8X)lDo8SFYN3btzzzDVyPSZlRGMX4sT)C)FYS5)MKqnFFYrgTPFcRTSsnzrbtE)mzA3ZgfrX0Yz02hgKPnNgkBWkiL7Kf3xfoBjDyiehZ5Dj9sOao)sLijp5egzFTuYmFbTdzNRC4GZ7K(geXg6yfbZXYLINvct4k7hChpsqpf358GZeI12rE9In74blsMoh7wMly1xD1Lrg70VXvsl40utHs7dTcYreDgK6oJyfYgZONned)TMpX7LVZ35eqhVTpkdK3vJDg3LIw5PU2ZvoCxYiPTnNsOBpu7JNtjIewz7jUGJ0GzuNsTFPmL)tofcgK2rUC3ROZ3Oto(nKndBjlpglP6jMeQ7hGsaXaNJ0ZEjPxQ3MNJC4bh358Zt1GOXdWCVldJRRiN7OHSrN5UBgg1lng00hoUih)oW0OVd3SIbggTv2GFpSbA)Vpf7Mjs)(5ot4Ga8L)kpmU5sB0jl7GDtFdV2d)b0gkRBKVURFOV3vXdQSr)E3Wk3L8ENjD3adTgepKnEHc234w9BJryp77cqFt1c6Ftz)lZ2mZ0YF)z22(Pbk29De5jVvGt2W9GWzkPUFMa6mGEdsWJRhXiUxcBe7Bi4G0)2LTHdmTBu7c3OXDoYqKnfzG9iazpPu)2T9PVGMMSVwoYTDb3P8(MdFMRQkJJsxYgsPZVnMlosGoCAZ2y2mZTLaTTCUt5y3whTj7(gjUgdJhUz3LOx(BV57w0wnYBdjG)Gu33(238KZ4TnLc62LyoQPsLFDvXCvLZGtNhanvEv(HpkIHg9LCjuarJTQXfCM5Z)O6rOuANUUSooqXRkQvrEgBIn41c58IfL1ZlAPy25LnRPE16f4IKR)ZIfm8z)mQuiddE(6Bxuu3Dv7AQYepnRdlM)3ZFMlim4s2pRcFHOShWQNlNqBL13)4vxxHD1l8bEGR4MyPgBj2YXXbOE9IRXkNdTCkYB7URQ8l8xaqMQ8v4RI36185v4fAlj7bydCZ6w8FGn9VgXCLVyzv5npYVAswBzxXv5Z)pcGzv(IIUM6BxJlBmQEWVUkVgxdEHzpuKVSP(QI6z3XBgaVVTCjmGWOXvbjCRCeUt(xn1IYVLO5iJv3YY8QvFQP(er5(bxsys30wCtrBBX8)jn(VHhErHR9Q1RkM3REsdNPYx5TWgZ(jXKUbocexpE6(zeNTGAE70ku)QiuZ8D5keExEfCmQraOdCQ(YEYX1HXPHCfSHRrQFQP7tffZPQZG4Uddp9zh(Hdp(KpHWNFbadu9Y(xXx5Y7k(B)yt58vyJhNRrCYcPa(Zh(3()TEv3F78IhYBNlQUm2lhvJwKQo9tP(XvvowYizpc9wSJncyu6E2iHWq1ohXf7IZ2S4SwjkUzLE(2QMhWlAUS8gZvWQdPsVeHh2ywkBaQp8QcFrxBExoaL)4Bo(Kp)r8XEKRPc1(uKisZWXTxVMzkLNJCtou8zzFr0UWTEaMh8IoNoSfjmEDBjFA2xfZLiMh9l(M9Dvg3iG2E1FFy9PZNa67rjv5GGxnjYBA00ep)OId42lhqvLxoNU7zCE8Z4rAIcQKuzYHjVe2Za(29iTmWlhEH1my4UfCfqomBrt3d8V22u)li1ls03sC(SQKyCoDEA3DaZTpwUcBly8ZG9cfCfz90dxDewGE1blRMfeNG5fFP5kQHQa7kqGCXQUMhU6HIhBbQDGkG2dx3CJ4VPE2okZnFEZdWkfheK7D5IcGl7kK5bZ05ASYt0E)vid0z0D5eg8QsSDxHvhlctGRqZREe4r20rCmHHEEXnYxIlvtwfp9)b2vkVSf4uXfBiFUpvA8noDDFmNkhuXzEQDnd8tnCBPNAmza9szXxkqjcyZ6PkFjWgJRwai8h5osRaAtcNjfZimsRwrFamkOEZVNUmxIwRowhjUCDlGUCXDL30DX9LlXHii7Qz5lX6g28tfGjwB6lBwI92hEQFOPTcBMW6LtaXHY8RuLe1qUi4pOhcJuPsk3u(JuByr1S7KDJEKzKHrpGQtYFXUDV4lBXl6blGBMuWwOyMEyixQWaqc4DsxXccSqceWgXPEJbSQU()uq3)x9aiIYVggYykgf0WuGscK408fS3ellqyyXP0Z7zu6NMMqvolDjs3v9vwxC7n7Ox8HGRcFdw1Y7OoJaa7fxKue08pXdznYviqiu9fRJybm8maMPFUiMaWcB1SwVPRf8IjwvTXf4UgnBlQ1afe5dcl1xN9uDjhs02dKnc3e8SYgNq0rcjPd8qG4yWhr0cU2pEKOpWiizjUFeXjvDO5UENhoY9WdbKQ7lRniQWcHoMORDfZPIsFiElQb9s09lcas9fGq8JRR6qEXakJrVKqnV89ztwCCdKnrw6usVggRUvNMLJPflXXquexeaAC)WeAgRu1LWrT2rEsITDaFwI0h6BSpkQb24N12Cl2pNXUgXLuTR0sd4pwwxUiFjP1d2qg5p7UAbJ25X3hMoQ08zu4GCvSQrxHuRsPaSqNdd766BBBwVea9R7aXeOeiqHrJUCHybX)mZ6jn7dLxF8r4DJ3BYvhT(2la241mUbyTnGB8628B6aXdNIbXKeOAwL3Pc6q9rWlHZD9CIhc2fNBMDpOBk8(S8e6YpaF3imyJWl7ovSPK1qXd4sQlaZeD7ir9BbxshoFEd23CxckVJhYihzprrmTf0YJQ8(IfHOMAhK55Jv2PuUznNpRdnbraS5AKdwEY4YfOOWVfgf)kDfIMR0QTfvN1adbqGilo2dRzByTDlT3lZeBa6sE3pI9(U38vqvVtQVblUga8j)lfZ)xnnle1VFUorcyz)315TC9KqcGeTSNxrLTVDO4YdkgmRfyNJJoc9DX)ZUCcBxQxPYGmCYz1iTa9LGZbCif4AmPSrXpIeW4lEmqLfv)NafsQWmC2xyW(uxxdo4NskNzlwXOr7GIbBANdSuMvUco34QAa2hQkk(ii3boEjubqoSeRrSC5kaNnoNSQNGp7hv1FuJ9(pZKmj0OrSkbYcEaznUWV)Dyb)b08sCxamPPf9lC27iVgx5IgMdnh2NRaltejxHGIwAesvecw9dAQuit8vxg)oS2YDC5n3uodWXqfOamN(L2wTOisxUytweWYQc0IS(J5153sQZnnB28fQ(IJUexdAMrIoqTV7vIqa1dbtfZbvOY7GZAU0HilreWp220r06VVOAzrRQzXvty0GXcRucKWxcNBwtq2Rs6HJ6ltWpb8GGN5x3ulTGBWkdRlfUyUc67SU70BopV(wQmHbwfs89QxV48MhwjVYMREOCPQPrr3rfMp3zyRC7laccyap3KctYUV4XRlRNtDSdghLkd5wfbkQA7G9MlQ0mZSWOE1f9VzHuQ2mbLZ1pTolbiQHbHhcIKSQzfQ6Ipo6MLj2uJs1jFDCePWpvbVfkEpspZNQ67hz0pRGLTaCO417OfOzRdJNxAAASFOVp8xsRDv64kuWvmQw9xsZfLrJ5ew(Rxck6UA17E9XmxrM3LQfVQR9TaxgABou3h1HdRUYgRT8b4Mg9YJGaBfrAYOLM1n4eX3DzJzrZBdXxaSGfT8eRupwn6o5enqDjnoLHffOzwsCcQ7ljKUOPJpTMGuHK3UHnIKtbUr8TAtUSsc5uz2R3o2eJwC77yV)G6xr45KrXM9vIEqjvNfsKvvwfKj7gXk3G8fDqvE7b0xDeEVvZpu0H4SQnZkAwrXOqAcydO36sMD0yS)uVQsXYEffq1diabyTfJ0UcDb0ha9JRiwHMMm0tMSRu8HDWG8yr0OaKndgckKMbCZaJ6ZRmkx(WErG4Y1t)r75XerQ5bOiP57ro)tCZx22HwtZU80t)WLNCg9lAunvVOt)vmmXQ2ZBuZRXw6UGpi1v4W)HvxcWAfkqw4ZUFG5btyNReEWd0Y8)56UKW(lzeHgwGl8EM)KKwyE6ouabin3jDnBY(3dXe9WIht2GVz1687USbDbTYUma5jfXSlcdEj49BBveZSFA26UYkQdN4Kv)MQFQybqI1eBB8Vjnb2x23tZ(SCP5GrNsU2OSOhxhI9HDDKGtGBUYoKeQfRyaB7jUWLmaUSGqUUVxb4Nz8Q6OKBHr9a5CJym)4YgSoPyW7gz4Ut8V7PojBYJdHb7d3B2HNsPDUyA7q15VxCTh2SAEc6(Vbj4)UKP(qTSEXnaWqW4aqSLfb(dRo3FxTiq728WeSls4NeM6hmv1jZfDV7(nmIxkXcCxOgnCLIWh52HxsZeajsOz1VmYnidob9guC1v1y49wSrugzfVHfTATJ3Uqdlvi2d5e2g9UzHgAjekyOllQCjKG84OlPeo4zB7Rl8f7RtVdUJd8RMPpagLP9lG4H(wlWr3eTkx3lOvhFBrR(TkxOFxbKMhwa7ZqpEPXhw6XBPIkPh)guLBQUXLCb6PAWCaTf27Ks8XKPVlXUQRPf7sl7PaMCF5S7jpwo07qUS23QdajwHY8LG97nz4ggaAmuPI8mqxbjZRNdF3mKte7RVrDuGThNeLpTDuftonnCz6bgrmPJ(67GG3Il5FGGh24eBuXoBpK4MPQnYRnCDt(hyqBxDFDkW42eAZBB7MIVL(4UwqSL5vK9vgoMZFy)BQVyyqtDlChl34paJwuSBfn5hj(MvO0hZjcUNif3eRfHWXi9qRfQd3BbB4uRGSBBBE44Ywmy0ny5V(8tE37rB1t1KMCbZr0uz(WBEl(ZjmmargH9cxJ40(9y)zozjrQxaXSDT4OExyCov7I7fS0KNzhy7FAx2JI1flkEexfEL)0GKKKRcJ8FQCRgrFNXCCX4SM0ISXy2Xlqu9hYkMD1kyzMKz6qvvLSEmEua)YZAqmP)2HK3bh4yEowlJf7ahoZCOh7XEoIbxA2NKpbx57slgxHYZPcmoZ)MnRS)MDd4wyFnAGeenisY20Di2bBNp6yCJWK8NV2T9Qy)BILVl7JTp(CDjET98K7O1BIcGiv2JQoWeVOgq7qGTPGyK1KL(h9jrJYQXMv0qwlsVNYnPs0vxGcpxD1T31SQ7QzZjfrgJt9KSYvVdFWJYXML5ibkqeLbS93xoFEr9F71htwDO6CHViEa4BgNwv2CCvYv(rXEPbrxLoX7PYQD)Dq5UWT1wtRDNvl5WXHEcBtQcEwr7QM68k0I2X9STO3qOt(pl6rHViFYCyDYqyV0iCKuhZWaNbPZaHHRc2GdFQ8nHnRVzERmIp5D7GWEcRwwumNA4zb))lVRMEBBEyW)vYXTBYsYFeNtfTROfOD9fRb7WU8cNg3wJ6yheNamG9NFIKYw2oYPXTWygW7sr7SLfLOOifFEedxH1m7tMgjBhhLTTTSKdP(BL940GynoGUm0ApLFG5fcfo9mntKdynsBzRaU6FAMmdN1wrC2NY077oOXiLdtzLAEatk))5FyJuDfcDJbfR5)TZywpo1W91JW24LOtpbDcVl554zpgbmbXMFGhF2fwdi(yZtwDiZwIeS4Vs7kMo5jADObyTAwB)Ms5K7IOT9Akw7FkdtN)5i)zYE4h37Wg(N(UhfwFnoD6tO0(bFEwoeEYyjo)0H3XoWwsUMM4mnXRvnOPsqERc9WeRFi4IzaNkvxkO46A4oupQaZDyRQhTqnVD6XBPpe5YkbS8Ol8SEGi0JDzf2ZqNI4E0NShgVUl641U6z2NEiva(5H7xzUVYqWfJLK9NEdGwmbipImFfXPXpby9oIyYGbiEbL88Q4pz8aU7Imb3jGVilGjCflY4EspLNjzI5mrGN6NbocMZImPuY8upM6NCxIgemk1ffg0k5IXbOVDT0wCx(6UyLpbPRRPE6QIcjADsC2(g)rS5QEEK)jQ(UkANOnX6gvNUKQh6(OFxRjuM3A0eQ)xQ0i5g(CsAk0IZXQfCaZhoOfWRjdLeudMnFDyLl5aHbDLLjSPQhGiccaqmjqiW8T7iE3U8u(YxqqySD)aqSpb7EqkGFZhODGJFalqiHVgngvrHwR8Ewh6MF4nX7YtkGQePE0SO2DGhrIDipeVs3LGCWnt9aBr1j3aZZu5lgN9jM6vYGquVQovqi8xcOVfcTeGJzJPPLjkTOcwy9XrqkXaAeiFPmMTQOqCtI6rFIh3sKfdyvG6LOUR(xQQjBDGhY2J60KHHsi1pExymjahZnk)LJrvQ)1)ovWxebHvPx76lfF7G)AojdMpGrjdPbboKd887GAbwvjBOR9enmAQb6mPvS04ujRo4(L5nf3BO8cSntAk(KaDpjwDz)m0invT6St1IJRs2bMnU5HFC7VE47lV4o0kY28ThsJ2b59zE4Q0881PQpmAhd6CMIanvDOO2gwN5kXBJgH0Nl88u2iPA)L(KK2g)e0KoHm8VQgKElrRZcaJvP7REcKEZ(mKCPBI2Uv5KjIx5QL8eHRHMuPWB4Nbc(6htZ3RRSn6hqBUTnzqRtNmDzLdO6dwNK0llfmmfUZGr2zFj(LWzxbKFoE2)Dy328I4VsmGez67fxU82F(TsoNAo5snxlUEx(MlV6(RXHdLwTEVG7jXJQotIqUR3al1KiQ6dibyBwo9(Nj1EdTupoNR5tU5AzOJmyOxypgvXDyIj3KnpCWxxp(MQbnC)HEUEmAoZ13FYPHlcDyUtqPM7oFkk1ttxs9MI7xZ9MEoNP2VEOnMn(24sj0Yb2w24tOHanNEt1GuhmWZ1JphsbFugAn8XNuZdhCNWhFcne7H3qRHpkTM5n0(JogLAh2q7JYytQPdtMRZpkcVWciJBWD0z2EDA2YpSpnjlwFbms3ZBq(gEjnFvuQLlPWn5RpqxusQgt9V)o" },
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
