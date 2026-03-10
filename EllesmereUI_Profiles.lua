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
--  Addon registry: maps addon folder names to their DB accessor info.
--  Each entry: { svName, globalName, isFlat }
--    svName    = SavedVariables name (e.g. "EllesmereUINameplatesDB")
--    globalName = global variable holding the AceDB object (e.g. "_ECME_AceDB")
--    isFlat    = true if the DB is a flat table (Nameplates), false if AceDB
--
--  Order matters for UI display.
-------------------------------------------------------------------------------
local ADDON_DB_MAP = {
    { folder = "EllesmereUINameplates",        display = "Nameplates",         svName = "EllesmereUINameplatesDB",        globalName = nil,            isFlat = true  },
    { folder = "EllesmereUIActionBars",        display = "Action Bars",        svName = "EllesmereUIActionBarsDB",        globalName = nil,            isFlat = false },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",        svName = "EllesmereUIUnitFramesDB",        globalName = nil,            isFlat = false },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",   svName = "EllesmereUICooldownManagerDB",   globalName = "_ECME_AceDB",  isFlat = false },
    { folder = "EllesmereUIResourceBars",      display = "Resource Bars",      svName = "EllesmereUIResourceBarsDB",      globalName = "_ERB_AceDB",   isFlat = false },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders", svName = "EllesmereUIAuraBuffRemindersDB", globalName = "_EABR_AceDB",  isFlat = false },
    { folder = "EllesmereUICursor",            display = "Cursor",             svName = "EllesmereUICursorDB",            globalName = "_ECL_AceDB",   isFlat = false },
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
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        copy[k] = DeepCopy(v)
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
--  CDM spell-layout fields: excluded from main profile snapshots/applies.
--  These are managed exclusively by the CDM Spell Profile export/import.
-------------------------------------------------------------------------------
local CDM_SPELL_KEYS = {
    trackedSpells = true,
    extraSpells   = true,
    removedSpells = true,
    dormantSpells = true,
    customSpells  = true,
}

--- Deep-copy a CDM profile, stripping only spell-layout data.
--- Removes per-bar spell lists and specProfiles (CDM spell profiles).
--- Positions (cdmBarPositions, tbbPositions) ARE included in the copy
--- because they belong to the visual/layout profile, not spell assignments.
local function DeepCopyCDMStyleOnly(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do
        if k == "specProfiles" then
            -- Omit entirely -- spell-layout only
        elseif k == "cdmBars" and type(v) == "table" then
            -- Deep-copy cdmBars but strip spell fields from each bar entry
            local barsCopy = {}
            for bk, bv in pairs(v) do
                if bk == "bars" and type(bv) == "table" then
                    local barList = {}
                    for i, bar in ipairs(bv) do
                        local barCopy = {}
                        for fk, fv in pairs(bar) do
                            if not CDM_SPELL_KEYS[fk] then
                                barCopy[fk] = DeepCopy(fv)
                            end
                        end
                        barList[i] = barCopy
                    end
                    barsCopy[bk] = barList
                else
                    barsCopy[bk] = DeepCopy(bv)
                end
            end
            copy[k] = barsCopy
        else
            copy[k] = DeepCopy(v)
        end
    end
    return copy
end

--- Merge a CDM style-only snapshot back into the live profile,
--- preserving all existing spell-layout fields.
--- Positions (cdmBarPositions, tbbPositions) ARE applied from the snapshot
--- because they belong to the visual/layout profile.
local function ApplyCDMStyleOnly(profile, snap)
    -- Apply top-level non-spell keys
    for k, v in pairs(snap) do
        if k == "specProfiles" then
            -- Never overwrite specProfiles from a style snapshot
        elseif k == "_capturedOnce" then
            -- Never overwrite -- once captured, always captured
        elseif k == "cdmBars" and type(v) == "table" then
            if not profile.cdmBars then profile.cdmBars = {} end
            for bk, bv in pairs(v) do
                if bk == "bars" and type(bv) == "table" then
                    if not profile.cdmBars.bars then profile.cdmBars.bars = {} end
                    for i, barSnap in ipairs(bv) do
                        if not profile.cdmBars.bars[i] then
                            profile.cdmBars.bars[i] = {}
                        end
                        local liveBar = profile.cdmBars.bars[i]
                        for fk, fv in pairs(barSnap) do
                            if not CDM_SPELL_KEYS[fk] then
                                liveBar[fk] = DeepCopy(fv)
                            end
                        end
                    end
                else
                    profile.cdmBars[bk] = DeepCopy(bv)
                end
            end
        else
            profile[k] = DeepCopy(v)
        end
    end
end

-------------------------------------------------------------------------------
--  Profile DB helpers
--  Profiles are stored in EllesmereUIDB.profiles = { [name] = profileData }
--  profileData = {
--      addons = { [folderName] = <snapshot of that addon's profile table> },
--      fonts  = <snapshot of EllesmereUIDB.fonts>,
--      customColors = <snapshot of EllesmereUIDB.customColors>,
--  }
--  EllesmereUIDB.activeProfile = "Custom"  (name of active profile)
--  EllesmereUIDB.profileOrder  = { "Custom", ... }
--  EllesmereUIDB.specProfiles  = { [specID] = "profileName" }
-------------------------------------------------------------------------------
local function GetProfilesDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if not EllesmereUIDB.profileOrder then EllesmereUIDB.profileOrder = {} end
    if not EllesmereUIDB.specProfiles then EllesmereUIDB.specProfiles = {} end
    return EllesmereUIDB
end

--- Check if an addon is loaded
local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

--- Get the live profile table for an addon
local function GetAddonProfile(entry)
    if entry.isFlat then
        -- Flat DB (Nameplates): the global IS the profile
        return _G[entry.svName]
    else
        -- AceDB-style: profile lives under .profile
        local aceDB = entry.globalName and _G[entry.globalName]
        if aceDB and aceDB.profile then return aceDB.profile end
        -- Fallback for Lite.NewDB addons: look up the current character's profile
        local raw = _G[entry.svName]
        if raw and raw.profiles then
            -- Determine the profile name for this character
            local profileName = "Default"
            if raw.profileKeys then
                local charKey = UnitName("player") .. " - " .. GetRealmName()
                profileName = raw.profileKeys[charKey] or "Default"
            end
            if raw.profiles[profileName] then
                return raw.profiles[profileName]
            end
        end
        return nil
    end
end

--- Snapshot the current state of all loaded addons into a profile data table
function EllesmereUI.SnapshotAllAddons()
    local data = { addons = {} }
    for _, entry in ipairs(ADDON_DB_MAP) do
        if IsAddonLoaded(entry.folder) then
            local profile = GetAddonProfile(entry)
            if profile then
                if entry.folder == "EllesmereUICooldownManager" then
                    data.addons[entry.folder] = DeepCopyCDMStyleOnly(profile)
                else
                    data.addons[entry.folder] = DeepCopy(profile)
                end
            end
        end
    end
    -- Include global font and color settings
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    local cc = EllesmereUI.GetCustomColorsDB()
    data.customColors = DeepCopy(cc)
    return data
end

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
                    if folderName == "EllesmereUICooldownManager" then
                        data.addons[folderName] = DeepCopyCDMStyleOnly(profile)
                    else
                        data.addons[folderName] = DeepCopy(profile)
                    end
                end
                break
            end
        end
    end
    -- Always include fonts and colors
    data.fonts = DeepCopy(EllesmereUI.GetFontsDB())
    data.customColors = DeepCopy(EllesmereUI.GetCustomColorsDB())
    return data
end

--- Apply a profile data table to all loaded addons
function EllesmereUI.ApplyProfileData(profileData)
    if not profileData or not profileData.addons then return end
    for _, entry in ipairs(ADDON_DB_MAP) do
        local snap = profileData.addons[entry.folder]
        if snap and IsAddonLoaded(entry.folder) then
            local profile = GetAddonProfile(entry)
            if profile then
                if entry.folder == "EllesmereUICooldownManager" then
                    -- Style-only: preserve all spell-layout fields
                    ApplyCDMStyleOnly(profile, snap)
                elseif entry.isFlat then
                    -- Flat DB: wipe and copy
                    local db = _G[entry.svName]
                    if db then
                        for k in pairs(db) do
                            if not k:match("^_") then
                                db[k] = nil
                            end
                        end
                        for k, v in pairs(snap) do
                            if not k:match("^_") then
                                db[k] = DeepCopy(v)
                            end
                        end
                    end
                else
                    -- AceDB: wipe profile and copy
                    for k in pairs(profile) do profile[k] = nil end
                    for k, v in pairs(snap) do
                        profile[k] = DeepCopy(v)
                    end
                end
            end
        end
    end
    -- Apply fonts and colors
    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for k in pairs(fontsDB) do fontsDB[k] = nil end
        for k, v in pairs(profileData.fonts) do
            fontsDB[k] = DeepCopy(v)
        end
    end
    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for k in pairs(colorsDB) do colorsDB[k] = nil end
        for k, v in pairs(profileData.customColors) do
            colorsDB[k] = DeepCopy(v)
        end
    end
end

--- Trigger live refresh on all loaded addons after a profile apply
function EllesmereUI.RefreshAllAddons()
    -- ResourceBars
    if _G._ERB_Apply then _G._ERB_Apply() end
    -- CDM
    if _G._ECME_Apply then _G._ECME_Apply() end
    -- Cursor (main dot + trail + GCD/cast circles)
    if _G._ECL_Apply then _G._ECL_Apply() end
    if _G._ECL_ApplyTrail then _G._ECL_ApplyTrail() end
    if _G._ECL_ApplyGCDCircle then _G._ECL_ApplyGCDCircle() end
    if _G._ECL_ApplyCastCircle then _G._ECL_ApplyCastCircle() end
    -- AuraBuffReminders
    if _G._EABR_RequestRefresh then _G._EABR_RequestRefresh() end
    -- ActionBars: use the full apply which includes bar positions
    if _G._EAB_Apply then _G._EAB_Apply() end
    -- UnitFrames
    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    -- Nameplates
    if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
    -- Global class/power colors (updates oUF, nameplates, raid frames)
    if EllesmereUI.ApplyColorsToOUF then EllesmereUI.ApplyColorsToOUF() end
end

--- Snapshot current font settings; returns a function that checks if they
--- changed and shows a reload popup if so.
function EllesmereUI.CaptureFontState()
    local fontsDB = EllesmereUI.GetFontsDB()
    local prevFont = fontsDB.global
    local prevOutline = fontsDB.outlineMode
    return function()
        local cur = EllesmereUI.GetFontsDB()
        if cur.global ~= prevFont or cur.outlineMode ~= prevOutline then
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

--- Apply a partial profile (specific addons only) by merging into active
function EllesmereUI.ApplyPartialProfile(profileData)
    if not profileData or not profileData.addons then return end
    for folderName, snap in pairs(profileData.addons) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName and IsAddonLoaded(folderName) then
                local profile = GetAddonProfile(entry)
                if profile then
                    if folderName == "EllesmereUICooldownManager" then
                        ApplyCDMStyleOnly(profile, snap)
                    elseif entry.isFlat then
                        local db = _G[entry.svName]
                        if db then
                            for k, v in pairs(snap) do
                                if not k:match("^_") then
                                    db[k] = DeepCopy(v)
                                end
                            end
                        end
                    else
                        for k, v in pairs(snap) do
                            profile[k] = DeepCopy(v)
                        end
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

-------------------------------------------------------------------------------
--  Export / Import
--  Format: !EUI_<base64 encoded compressed serialized data>
--  The data table contains:
--    { version = 1, type = "full"|"partial", data = profileData }
-------------------------------------------------------------------------------
local EXPORT_PREFIX = "!EUI_"
local CDM_LAYOUT_PREFIX = "!EUICDM_"

function EllesmereUI.ExportProfile(profileName)
    local db = GetProfilesDB()
    local profileData = db.profiles[profileName]
    if not profileData then return nil end
    local payload = { version = 1, type = "full", data = profileData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

function EllesmereUI.ExportAddons(folderList)
    local profileData = EllesmereUI.SnapshotAddons(folderList)
    local payload = { version = 1, type = "partial", data = profileData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

--- Export CDM spell profiles for selected spec keys.
--- specKeys = { "250", "251", ... } (specID strings)
function EllesmereUI.ExportCDMSpellLayouts(specKeys)
    local cdmEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUICooldownManager" then cdmEntry = e; break end
    end
    if not cdmEntry then return nil end
    local profile = GetAddonProfile(cdmEntry)
    if not profile or not profile.specProfiles then return nil end
    local exported = {}
    for _, key in ipairs(specKeys) do
        if profile.specProfiles[key] then
            exported[key] = DeepCopy(profile.specProfiles[key])
        end
    end
    if not next(exported) then return nil end
    local payload = { version = 1, type = "cdm_spells", data = exported }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

--- Import CDM spell profiles from a string. Overwrites matching spec profiles.
function EllesmereUI.ImportCDMSpellLayouts(importStr)
    -- Detect profile strings pasted into the wrong import
    if importStr and importStr:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        return false, "This is a UI Profile string, not a CDM Spell Profile. Use the Profile import instead."
    end
    local layoutData, err = EllesmereUI.DecodeCDMLayoutString(importStr)
    if not layoutData then return false, err end

    local cdmEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUICooldownManager" then cdmEntry = e; break end
    end
    if not cdmEntry then return false, "Cooldown Manager not found" end
    local profile = GetAddonProfile(cdmEntry)
    if not profile then return false, "Cooldown Manager profile not available" end

    -- Apply bar spell assignments from the decoded layout
    if not profile.cdmBars then profile.cdmBars = {} end
    if not profile.cdmBars.bars then profile.cdmBars.bars = {} end

    if layoutData.bars then
        for _, importedBar in ipairs(layoutData.bars) do
            -- Find matching bar by key, or append
            local found = false
            for _, existingBar in ipairs(profile.cdmBars.bars) do
                if existingBar.key == importedBar.key then
                    -- Overwrite spell assignments only
                    existingBar.trackedSpells  = importedBar.trackedSpells and DeepCopy(importedBar.trackedSpells) or existingBar.trackedSpells
                    existingBar.extraSpells    = importedBar.extraSpells and DeepCopy(importedBar.extraSpells) or existingBar.extraSpells
                    existingBar.removedSpells  = importedBar.removedSpells and DeepCopy(importedBar.removedSpells) or existingBar.removedSpells
                    existingBar.dormantSpells  = importedBar.dormantSpells and DeepCopy(importedBar.dormantSpells) or existingBar.dormantSpells
                    existingBar.customSpells   = importedBar.customSpells and DeepCopy(importedBar.customSpells) or existingBar.customSpells
                    found = true
                    break
                end
            end
            if not found then
                profile.cdmBars.bars[#profile.cdmBars.bars + 1] = DeepCopy(importedBar)
            end
        end
    end

    -- Apply tracked buff bar assignments
    if layoutData.buffBars then
        if not profile.trackedBuffBars then profile.trackedBuffBars = {} end
        profile.trackedBuffBars.bars = DeepCopy(layoutData.buffBars)
    end

    return true, nil, (layoutData.bars and #layoutData.bars or 0)
end

--- Get a list of saved CDM spec profile keys with display info.
--- Returns: { { key="250", name="Blood", icon=... }, ... }
function EllesmereUI.GetCDMSpecProfiles()
    local cdmEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUICooldownManager" then cdmEntry = e; break end
    end
    if not cdmEntry then return {} end
    local profile = GetAddonProfile(cdmEntry)
    if not profile or not profile.specProfiles then return {} end
    local result = {}
    for specKey in pairs(profile.specProfiles) do
        local specID = tonumber(specKey)
        local name, icon
        if specID and specID > 0 and GetSpecializationInfoByID then
            local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
            name = sName
            icon = sIcon
        end
        result[#result + 1] = {
            key  = specKey,
            name = name or ("Spec " .. specKey),
            icon = icon,
        }
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

function EllesmereUI.ExportCurrentProfile()
    local profileData = EllesmereUI.SnapshotAllAddons()
    local payload = { version = 1, type = "full", data = profileData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded
end

function EllesmereUI.DecodeImportString(importStr)
    if not importStr or #importStr < 5 then return nil, "Invalid string" end
    -- Detect CDM layout strings pasted into the wrong import
    if importStr:sub(1, #CDM_LAYOUT_PREFIX) == CDM_LAYOUT_PREFIX then
        return nil, "This is a CDM bar layout string, not a profile string."
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
    if payload.version ~= 1 then
        return nil, "Unsupported profile version"
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
        return false, "This is a CDM Spell Profile string. Use the CDM Spell Profile import instead."
    end

    if payload.type == "full" then
        -- Full profile: store as a new named profile
        db.profiles[profileName] = DeepCopy(payload.data)
        -- Add to order if not present
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        -- Make it the active profile
        db.activeProfile = profileName
        EllesmereUI.ApplyProfileData(payload.data)
        FixupImportedClassColors()
        -- Re-snapshot after fixup so the stored profile has correct colors
        db.profiles[profileName] = EllesmereUI.SnapshotAllAddons()
        return true, nil
    elseif payload.type == "partial" then
        -- Partial: copy current profile, overwrite the imported addons
        local currentSnap = EllesmereUI.SnapshotAllAddons()
        -- Merge imported addon data over current
        if payload.data and payload.data.addons then
            for folder, snap in pairs(payload.data.addons) do
                currentSnap.addons[folder] = DeepCopy(snap)
            end
        end
        -- Merge fonts/colors if present
        if payload.data.fonts then
            currentSnap.fonts = DeepCopy(payload.data.fonts)
        end
        if payload.data.customColors then
            currentSnap.customColors = DeepCopy(payload.data.customColors)
        end
        -- Store as new profile
        db.profiles[profileName] = currentSnap
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        db.activeProfile = profileName
        EllesmereUI.ApplyProfileData(currentSnap)
        FixupImportedClassColors()
        -- Re-snapshot after fixup
        db.profiles[profileName] = EllesmereUI.SnapshotAllAddons()
        return true, nil
    end

    return false, "Unknown profile type"
end

-------------------------------------------------------------------------------
--  Profile management
-------------------------------------------------------------------------------
function EllesmereUI.SaveCurrentAsProfile(name)
    local db = GetProfilesDB()
    db.profiles[name] = EllesmereUI.SnapshotAllAddons()
    local found = false
    for _, n in ipairs(db.profileOrder) do
        if n == name then found = true; break end
    end
    if not found then
        table.insert(db.profileOrder, 1, name)
    end
    db.activeProfile = name
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
    -- If deleted profile was active, fall back to Custom
    if db.activeProfile == name then
        db.activeProfile = "Custom"
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
    end
end

function EllesmereUI.SwitchProfile(name)
    local db = GetProfilesDB()
    local profileData = db.profiles[name]
    if not profileData then return end
    db.activeProfile = name
    EllesmereUI.ApplyProfileData(profileData)
end

function EllesmereUI.GetActiveProfileName()
    local db = GetProfilesDB()
    return db.activeProfile or "Custom"
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
--  Auto-save active profile on setting changes
--  Called by addons after any setting change to keep the active profile
--  in sync with live settings.
-------------------------------------------------------------------------------
function EllesmereUI.AutoSaveActiveProfile()
    if EllesmereUI._profileSaveLocked then return end
    local db = GetProfilesDB()
    local name = db.activeProfile or "Custom"
    db.profiles[name] = EllesmereUI.SnapshotAllAddons()
end

-------------------------------------------------------------------------------
--  Spec auto-switch handler
-------------------------------------------------------------------------------
do
    local specFrame = CreateFrame("Frame")
    local lastKnownSpecID = nil
    specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    specFrame:SetScript("OnEvent", function(_, event, unit)
        -- PLAYER_ENTERING_WORLD has no unit arg; PLAYER_SPECIALIZATION_CHANGED
        -- fires with "player" as unit. For PEW, always check current spec.
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
            return
        end
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local specID = specIdx and specIdx > 0
            and GetSpecializationInfo(specIdx) or nil
        if not specID then return end

        -- On PLAYER_ENTERING_WORLD (reload/zone-in), only switch if the spec
        -- actually changed. A plain /reload should not override the user's
        -- active profile selection.
        if event == "PLAYER_ENTERING_WORLD" then
            if lastKnownSpecID == nil then
                -- First login: record spec but don't force-switch.
                -- The user's activeProfile from SavedVariables is correct.
                lastKnownSpecID = specID
                return
            end
            if specID == lastKnownSpecID then
                return -- spec unchanged, skip
            end
        end
        lastKnownSpecID = specID

        local db = GetProfilesDB()
        local targetProfile = db.specProfiles[specID]
        if targetProfile and db.profiles[targetProfile] then
            local current = db.activeProfile or "Custom"
            if current ~= targetProfile then
                -- Auto-save current before switching
                db.profiles[current] = EllesmereUI.SnapshotAllAddons()
                EllesmereUI.SwitchProfile(targetProfile)
                ReloadUI()
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
    { name = "EllesmereUI", description = "The default EllesmereUI look", exportString = "!EUI_T31wZTnoY6)kZJNZdrfVFZpz7yNKYtID5OzNKTMQCrlrBXtKj1ksnoEs5)7NUrdqaqcsjQeNjzhpvT16qrIl9LV(RBac(LZQ8sQFyvg8)DZMLlpRkm5pZwxLxwuyFa(JZtRtH7Yp5MYI6k4VcsUDz51PlRSTso5ZRwNvvDF6dNvzBNuUPEzEr2BlNJTxrzr2JW1DsMTPQU8UJlxwUUI1wZwMwv9LhFeBT05ZllWl7eKCYYLzv3LTo73EZXLLlNxEFXBtlsVnB9xyn01BU5MJsx)(zPlZyJViXLWgioPAr59tZHgykorUUC98S1hvyDa7FD7HlxTiTWAIhBIDD66xb)Jih4Fbtf6MFF(FrnS4PVK)0vRsNLxCBbE3bjllN9PS5NYEWBYxwNTMnNDtsrryus(SYcQPIWw3nztv2X4CMjdov28hY6SMw5xZRQRSsWFV8MBQYQ)qHRfnaYksVEjRp9tUpFE9Ich2VWMiWCCsan0UDD59)2kwxCx6NrjtrKY85vS5tqYIS8BxutJprN9XIxO0MWmFILptgJI13atPPpYK4GGBz59Oeh05WKk)2I7YiJd3e7RS)ctxawj3ZMU49LCn0ASPAYTnc9K1WS)rX9((6h4kvVK7qPzqYHhp9n)RtyYNz6sVQvzlx(Mxw444gzhEWJFN7X4dEenEHPFv2YSz1zZbbnPkTr5Z7ZQRbRLktsc(9PoQOH6Jgghbu)c(kDht6tcC80yLaM)2rnJTdBurux7jh1BQRbp9qQVHUAg6hMe4)furFx6QvIzHQbi4iMoRgGi4po5VmB(DVFzj1fXIBGlvgJUbaosVd8LSsocCT)L3b)JF5)j72KF5L5)jaU8lxSz9QYQS)xdsR2QvqzSiFE2PRbWNx(2tzQm)Mj)BPPh1RUjobE)JCw78epRh2E)7)Sg)b3eiS1NYloIHjwbUloEjxDx(TRtHB(cet7pZEp5XJ)k8axnlDv9M1zZpVyw2uwJdsbysFrzvoo)zHWS4X6Uk4kBp3ylRWR8S8yYHhkSTSMeBheAh67e7YqwxNT8IYCa7mi54tE30tUeH3x16k2jFU4f2rbtc9IJ8c9SDSzspzVfc9MNVFq0vbUoIEZEsOVLvSTVVtOR3i7oN4GjXW)fe7f545qGMZ4XKR4DXlIdNef5A7cthp)Wr2fEotcdcIcdCCScTCXUWNfoVP59JNeAh4744asT4r2(otcc4YAyYeJnVDSqG5Zvpoxf6lKx(Kal0Xlm2XFCD2lCDIM4zhe4h4f7z7DadnEtD(Y86huKw2U7P0kWEsKDGNvamYiOEY6R6l6W(Sq3mVyWaLc5pDr(Spva00qQElYlWOkiNHBjMrq4GzlsxFB2PabpI0c3FQQoD2NoUCtr9rC)(In3Dje5Nt96tzpCDEX8dbV5yQH4x5Co3fNdAZ0XfVfvljL25vcUqv3NVktqwlKAzKcY7BgpNYCjtlMTOC95CUlwSM)ACwnXIO1OenmejNE(nxMwCB25ad3LPpmTrqCPqqOn(r6qhW6i4M(x5v5xZ0MiL1LaJ3kMmI)eKCJ1kbntoPa15aoXjjZvK6eGB(NzhwKFhJiQpngauUuaObaIoV44xoTbKmo5yPqtNohOQP2cKq1Sge7TL5)1FLUEElv5LfD0UCbVdjmoPb7hLMxkKMW8I6sJ8yjtPiUkzAP04N0En9L0aZHaSrG)QFFrwXBkO5WuMnaBOq2aAgB8HVlJN7lZxNXI9aYOF9Kt5pPorEaKukN1g7OmaZxaKQ15iJzfE7Ewh0CdhZ8oQM2onaqIW(zUwzA2NRNscn0Ji4agEdyQvNdk9ZxNd8VsXbBxJ3pisrrjLdnnezDdu6wuUPc6)xdcUtKg3E8wRjuKxYYSBQBzKj0rCj5r8O1S58I0vIu2eYH)Dz5DcLpoPEL4FWDAEv3H5hkueBNrDZPTgfOc8XHHNAnen57E6zddq5CqBuU2JbZit6MTgGZmbpjnl42MDbMAbYPbn12muhuYGV7piasHj)Mqw1coQhGutO4pj4qBdp87aGKFYLV5vVEKisAHVuqJCSLUvs0iJGiFfGsTWF6dSXaUuV4pkbeeGlgGK6HbY3dOPwKygjW0EYCsdyQdnktWsCEXNzcgBprK6JTMeysZA8NfqjFwMKDziTJqsTnW)hcKuBo4dWmY1rEd)3iwKzYgFpWI6lUWwaL0P5yopNTcjzc0rwEbpmBzNiB7RcJdoZCkAMWy0O5maaXUcg0VBVJtYXSX6V0KK0Vazh)l2gac2jsi9yp)v7N3bjPhpFnW3Ec0OdcnQLWq1HoOhh6(qp2FVAtErdbXnIuGmGg21DVxSbTOBFd8RBfCmeFKP4QSPu5Jr5wVNmnm5wBUiy)q6vdABUxnZ8WShTu4QYsQTd9tra7bXreAETkgmIqY6EV9LzqVoVFtJgpGpA)8c3N4XD8I7ZF)PiESzG42i2)D522Zsl8tJFRZZ(Tp73(ZIF7EuXXT73QTiD)y636N828QzzlxMwKbQpd0NnK5)3r2ZMCE7r93Rl7UWSEBU1JKmDBqS91Fw3P9PkP4ooZdaJ8u4p3jfjzKIOK615fFkRUIV9BGF4Lz3KUzjB3h90x6oDpCZ1qBNDShYzUxZ32v5XqbbnJE1PqJ6wt9HE0N)1oxyoJ6tDiLULhCNGzgWU8BoTH(x6nt1vCi0cdbl)gSebFFiuW7a1cd2PWHFvypDliNwG5Nc4M2LHRBqgAtSYm14getPlXxRqLyR(aavkU3qpsUTuXEO1UeKVln47fjUH3QSzNHegsc8zTE91xl3BrpQ5IQShyXFiuBJZUzDfBRx5MSi7ZW8364x6e)sCJLu1mqzJZ8LmdQBNnx5UpL9FOCBD688nv0Ip18SS9hkO5QbXZcMla44WSKJitDaF(wWKcU8sChMYMj5fGuVygGiSKXJY0(HvSLZE04taKOsRQpoF9SLzkdw3tpmuBW6AnIbl0pGJ56pjDNLd)aW6A9DPl3LX)0wJ)we26EV1Gl3M1zOLb2FxrD1JmenfnjUD4wTeGJywrGf4QlYwpdChbZcyMSMlFDzThUF8UeVcEHfzPlRxWVBMfyD5k8oyyfomF8WKBkbMPSrLcGgboCk62pF5dV7IJRWejCyYFWS73kYlQZwVEZQ68Rz6cCh(znXJb)Z2KF8)8A6pP9Hh6XJ9)hiGibYW8mmZV30SoNSbMROVEnFpkhsUPIz50Yvaqqwr2DpGsicTeI48smQd4SGaAkbQcX5UO)FfeuTErdeKhTR299tEdoRUjDw2FC485Nxu9hk6H)4US55P)b7w)d5wEFY0POOXn5gHWcgnOjYh5tYx4WHBj1bmJMYv8kvKeCdN)wWiKJ(74rtwKp(hvfwqSUvVBZDxNHaPQaMZMHTQP9BPnxpqGerQcqv9ay0X2xXxuEpeIuUv97U7n9AuSSDRhm65MvAJ0WKvPfZZUlFgUnXbyTS5fEK7MU2MFrHUr5Ia8egcR(vIT4jorZeAKn5mD()ztwv9BlVw1c(uAIkv4AgCUKptRoJ7iWzkP(sca)0601zNaG8zYHntMzPiZo5Uv1pOkYSM40i0K74v2MOeTUBEqutICtQbroR3q5d79xOb4VX6LnXqZCwGPDtL7ZDXb3jHVKfxfrDQjjuJ9io6yYsjqdZP7nfhxE31P1nt2OMjRTByZ0f)BAqqE54q(3xasYtzdaTPII7AJnL24kOzCOR8a9Gg4N2dbHqtl(0RtRo8wGmDZW1scvPSFKdyQhhjmZXziKGQLD7otZQ3x1QtZ(w8m)k8JshxcrfHmuO96POx6GiYSaLunCKqGOMYf7F2yuZKTL2vOi2fBhayPptrOxeGExGbO(OEViMzBVxcv8g(GU48tqkCtH)NwSjcw4W1amUuuekcy0OIdB0WsiRyEh2i1Az4zlssqZr2kq2wI)(A(F3EcC0TTE2ijmGLIPg(3KigTp)1smTcDt0ijOBOYwMNnfOx5j0cPjmgUr3b2PhcUucHi(u6a7nuqQMQmBj01yj46zi7Fv)MtuFxaur2PRiSOuYymqcZ2Y8toCEv6krPvfk6TBT4MCfXv(cigAwDNGcWWz(QQ3LLUE3fNGpxJfX2hbXAEZQM9CSwfugLaNTHzSJ0WZ4SsKu6IAHcPareWOgSQJxNxsdXSlZsN)qZajwAe6kzMrddik2SwXJPSFM2e(L87q0AulBmUKVIEvRoJS0mB(PtzTKcjKTlUd6WTIOuRf6VzMA7l9vJ8vyHgs0qDObehkLAj8kNG6)la7jk7Vg2A)o71SdrGHmVMX84KQOanlbffKlpE3hv8ebyIgTgXZy1)QWMhjks916IpDNYeRlsRw8R5fzsxWoXN0CWS4DnBOYdiOq(UflnPst8dmHFSiEDV8qcumryqXvuiDzSl1EcbTxTkBEJAsg(vQI8LEfghT(Q2nsHniwZ2azYUC3C1Pb(Rz6xIlnXxusqX48nutvVDRwBICJAnFewvsKslswF1mS52cSMod1TpaI1UFrshyDjRxNdQIx8NoSXeg2KuJACq0TWKuwcvihQzDBJWUT4zz3vlZd614FPLFNVIeARZqLKUETPwZXszUPL8nMhjeC7DLMhRok2mHnqKTIV5R24BBOgZU53RuqI2u0gi5PEYdRzm66iy1O(uiKb9w)ILcGJHS1bQJxJm99GxcVS6iUBfvZJRO1XIms)Y4A89SifJHz3(XFZeA9tt1o2p2EJVAig4hoCbs2kG)a8i5fqjmCWcOilK1oxwL9JG6qLAXivvdfAzuSx7H6ZEWdDaiRo8w27k2mosQMlVZaCt1kXKohaCULPuFexL4d2sp5a)MmJgU(pJUkpg51zU6t7fv62SDjgCMslRVaVduhkJub37sq1lJWTv(jw)LFt(mgmcdI5PQ(u9qoTFgIJlZcde6hS0xJkK)3ccJduMqZvi7PHJ4G1PRhAI7EjP7RQE9ssCFQO3qvi0yctJKH4ExYWUmd7TiI9x2bt8t)kRjLPeTgxzm7DPgu8myIdT0MnuJtLyXTC2nKb6W5gRlc75NONB7gUJiHNOK7YlYVgCHB0b(2YkM7452OdIJ84WhgxzUXu92ynpRp2A2Q8tTOOoqnFv0QmD32he716f4y3HR6U0t7EjNLXs5PEqlACpf05rmjKfLv15k0)DJLZaj5fRydIETfAZPBwRexeBF(qqHj(2Nj94Dasq1SbB2luSNESmXgWTXN2lfqilfJ0XAKSxQ7E5zYzHD4YLVKjizzUoGVq)WrBLStRv5uEo00J91EHdWeWCEbeSO)EIyfRTS(xaH8XZ9gubePULdqUQ4wx5syIbZoX(xbqLR2ChQK1oVrG)2jH2OroGA8w8iM6Q1BkYOD5aYK4t0Ft7GcCFgbmURyBeJ7l3uWF1DYl(0dxD9sKKbEd3J3aUTnwxUcmENY3eExJBnd2WbsSQEXs8ic6wwtDdOQWhf9FsPQNgLCpmbUzZ6h4zPwY7R07wTm)MhOhnc8GQZUkD()h1WqdDxwDzXTBOn3i7xRslWXayBDFw6QYIRYkMTGMmqiCGSe0GqRrjbGtLJWzY)Ue95WZYnh(gkAv2S80LvVRS4n89tcoKaqbiZ3BG0nYM)7S2)eQ5HghMw1xTPkBU(M3bG7AEKtHjM(DcgGOk4L5vqk3p8w6ut6UhQbjjBekFuuQP(SImVGUPwAaWP4OD1MD4aZCmmzo1zFbLOOLjUfcrHT65dye7aBc3gNmFp1juysjAJx)an9WdmqCpmDiBF7W2DqpiYFYIyo19G1YnmOXzkK)3RBcxZ22yIxjA6SqIXGi7Z8x5xCulNvSX0NvrkO7qf)Jdc1q7I8jvhu6EISbZJ49TPap)aHySS77HIx46gpjYf(p8OhI10nNlqHjtp)c6SnrCWaPCj8KbY2kiK90boXXbbhW6cmvg2(Ie7cITKQD3PTDItZNI7QQQpXpvCGhyt9u6y3Q(E6ARll(RmU306A0ExZOmK1lNxVamAEBEvf3NWNHVth7JvQm7ApMMQpMa2oLlPbv5DKRB1I05L3dD(DtPF)gYT8AOhZw)PROgI5wop7plVITOv4)Q6ba8OSMbLW48FJ4EzhJF676QFRiV(01yzp)c5QbtwqCwt1HqUBYy7IpoCUxYci(Xs9iEgnaoZuHkVMSXqBx(Ds1k3PzJdAYHIn2UxHSMpija)IZez4tbtH4df18D4)zSnYkJ7HSetIsNXcrQ(mGbx26fRyYmwprKvWXyaDHpiYbP1(xTzOrra)OGWa7ItzaeRVlL3dRwX6E1hG1qXewaANCbxhCAx3oe)u5jPsIXRCgVr)yXl47MNzSOLTKlIezi5cpFt2bMMA9epNJqXpRRgUsJcBgg6RtIZ8ZKf8MdmRiD5dtSQ78zbgxqxIqloLyUDQuAQm04sEKG31YeN96QpA25RSlYVXastEdA6RLuk)ACMQbCMQThC8P)JAfzea2leSn4mYMYw9gXymFEwRDUn4mopJ8WeADA)(g1ivrxAXF)HMAxvFnRyllv2vPkAcMbJvVMM7SpzCJN1henNz5nmEyJf2MWrK5f)wB775ZFfHonF5s5iivyRX6B(yzINBSJTFODCqCCefMdd)ffG)xORNJDuaNXN0HwtOqlQIGX92XRCAMYk1yWLxpk8YGjijSPSxA2JLPBQlB6p2PPOSobCQY9ct1Rbgtzj9J)GUsTluOfttq1dOqqTNwiR21hjvl3DdkFtEmM2ubn9OYC1bV6r3Q6R6HxsAawl3U3YQ9jT343OjCkNGo(m6RGqe26SuC0XqI0vnB1wyRGsks7MT)VWZSnI7GrCmfMAQG227H)njPjnzBLyOS482HiVkxVGip3q1sFfcxaFpADJJ5xFhJ6kLLAUvowAU8)AjL3OCpA5O97QIbv3rflMobDbx6gPRwFhjKXY3Gk(qu2C4YfiJ(Pbi4kvekE4bAJx6h4lpISH0wknu18MIlGKZEOtWx2quzQejD9vhlXnJCY8XXPJLnDMTo9SXhN1wiM0eYm3s9CjAV0j0YPqPhzmORPqKJIt4q0jmftowh(ve7brKKIWMW8s9f3PmqXqQLBPgZoNWEe)7qCsHUr(UUPyo1aMjJppptzXyAINBKZJcds13AXwCqTBqMXxFWZgMn3UW(KGCmqKsXVuB824x(rblLbiGAj9c53UYv4QJ4EuhngJwC1lNOHoHc2IIOu7YiP1DuGlhF3ChWejHkIkDYQI1bF6ImWqLLOua7aBEDXzsIbhYEDVivfA8YbgTWdQEo7qE13S4yjxcPXoTlNFwmfUS3xch3sI2FMbps7knC1d6HL6PdXs90)MyP2pe()azL2Ye5NzcPAoaoCm7)2jAALO4ZQw57wmq9Wr3oWavU9(uekYDtBFqZJLI6tdPWXt8nI953qrLo8RbwFKK)kswXa)A27xYIZ6nHaD619YmDpziV3Kj2X4ED4C8TLbD)Sv(EqGUdVwfD53cQ0Bje9OyjBIO9OOdBMMDBMT6fH0yzkgj35EsPWad6EOZEDpP4zMEzpj5sRv3r8QLbTAb9oE16S9Eas89YiDxOjpaj7EOLVB0K3AgYuehdrR)Qin3k5mApy(Jfd5w5j0ox5DU4Kpb8KbK301FInQpLqyLFTtqTmJ0m34rSCwo0IuN8zwp3(7zbvIfI9TKdo(CHEbqmyxhF7yFxY)fxFlpli0SLLBqGJTv8bgwimgFEAO00wH2tC8IJDc9DS4H()CrGR9e)ix)yF46rr90w4cbJvWwF0f57GFHp8dSa6dwUIrNvqa(zdb43g7y50tlQUVBXMkmeBkpFhpRq(E09ZfXbH403Zj0ZjUVwsnVL(NN2obrta1aifJS87RTSv3bPnkpNTO8KR6fT0L(y)h5eamNCcf9FOL7e7GqRWaBBR(KZG5JI4LunUwro2XX28gkmWdLuXb(ErEbMNi4mXt4pRvwgB2qvSUVSYYajUDfzPq7ES3Y)M)qaTImH0ae8PO2maHa(RvgIiytFMxgG7QtIAx1FQMqGanhjPVFRqb7wMcgxHdp9U4Ryj5OLULMdhEDv56RpTtN(bbLJEqw6WUXtDplMkJP3nvJ23kNDZ2iOhRp)5TOjrtZPKJjy8EzHf2A)Ft5G2jlGqfHhV)iPNP817BTAnhrRN8tvD0gfjSXSCPSVxsDs6DOs9p8QL2osMrICdx00U8C2XOOd6qpyIpDwS6wAkRblYq)eFX9jD9fpRc)zqfQqe5RFDUhtfdncWBOWG)4wcqJzW1FX6gY2Xqf56ngB3kYTTmvg89VsXKSZ34XMYWTTL1LI0TLIMnqiTEdtnuDQ4B5LERAKw1Hg61pIFS2TLQeSJ5VouDA6GX0Ugko4zMgU5ZFtXCCN8wAqD1x9L32oHHI7AoP1i9xFhsZjEbt6cS1lCfkL1h)uUJ8Sj7UrS2E6WXDArCy4Wlz1psPf3dNkZ812TCD7SKmJBDw69vRr1I30RyJ4vV5rg4bU9pLZQPLSTB40Z0P2YKCyQtyyeDnwJfvm3UbKcNn(Lqz3xYKUMHSwhFBcyUtNn86J0)IHyi7LoESArUY2(QDyobHEx4J2lsBFR7XoSehx)nzt20FX76DzcAxXO9Ra9D25agRc(4k2DR08(wuR6bQpPPcppih4E2phBPC49ua)Xqnxl8PUD0q1NU3LKX4M8WC(7TwgJMYVAof89FbOuQDbbTyUm2dSMR7oFFT3dFwyKMQBUBRDuF1IFmL8(6URiqeH1ZlUUeOVdixd4J(QAh1QCbIL(T)vA4BrTz0cZP9AjBU8fFfRS3wkBtNL0Z8c00DH(Eswf4rToyuewXXcR4fkGQE6uzEItBQo8uz1DrDGwrOjto1IMpLxwh(rrSM1iXYq916IDiIFe)8iomz1Mkqx1MkSkjMalzrpJCBY2BsCOlpgf1g)wRdYxh)MdP4tMFBw7F2oq7NjQNSpk(8dZB0OcpGukYVJY5I8wOotHsPhzc3a42PJyN64xOSAfEjW83vuUzBixv2BnJJvCqaoag3lDtCiOKdddIS889IPS7G2pG3(HEtcTSSSPpT5TA(T9T(22YZEcmQOpC7I3fWt(mOC5ks23IFXuXpmIMjroEHwHJEQ4eXwFf7aWUNovCytfhfrL7e0tbYT3kWB0TVxS9KWWWi3WqhVOM2ps0(UXGMaharU2w(J9dVUD8ep4z9c8q3y)MMx8zD)fb(SPNLBeCtJ9Jip)fa(TP5O3JOjJ8X18j2oii2YlC0gpGp0KaBBhlxpF02J8GpPygEAJZI92m25Qw34GyBgdGr1r2G8glatKBGp(MLjKnHnQw7Wj2XXX(WFyhfnozZl8CyI7aOjVvzqdduVjEqRghzf7SD7Xwg)Ho(tSCDHjm(1UNwwZ3MpBDPwxegob7H4a7iF3r2fobUOuj0XX2ki2L4Q8E2leMQs2HuY(GEk2A0M9Hw2t8ISd98avmTsrbjxKvR0dorUtCqPFOtOVB8yL(H2talWah)4Wa)GgLRNO5dP1nfSqbdawGSr08WJYwStVypMEWNcOflrCBbgBJhqyPRWYWn)C61Wd442C38k0XE9pzHjJXZfDX5P)ltRtXOtN(n5i5gRc0)zt6A2PRg)ZGWQ1LTor122lnQtZZWg08CjOarTNn4RCp)M7eikulI3EfTv5tCG)erz659N80YqvC)veAN)TjqnGPtcdAIE5xLBagwuOlsNpxHEirRflYJ8KkcsOr7R)H6hufmRd2hzbqtU1KMmKqGYetmPeti2t05l0cNfj9Hw515ZNNvqjPl)MPWAD(lBEG453PbOYNAj(xsdtF3qOkRR0UAL7MgzVNL6ekG5N(Ensj9KUjXrhdoujO3JqEmJj5nJfPScxGI2m73MgO9xYgNKn0l4JsRP91lcPbY)CCqP6Oy8r6p1pWcrO5eZrVGV6WT(GSWRiOsVjRjj(6ndWqL)jKTK8ZXsqcEH1WW4DIM2HSAMTepRIxSUCZTliGgYjq)lsc0BTmMAaCSB88SB87I4zW23NUiOxkLFfwqnZc4F)xGPa7ZtHYCGoR9XdcxUhABHBG8Epr(9QqYC9zh9X7OBVpU5DSY)VohCf)sXbxDhBVwFQum4P)TWD2aK60ZgcaQhF6E9p3h3DDF6OMV3sNnoh6wqsdKPyxpbJkKE8S71a3STy)ZHUyOguAAPG(mM04XK2tYh)Zcv6GwWpM9hmbk1h0X3aWQ(4E8nKPrp4HFxiG0fVsMZ6xPJEpIOFa841SYEc81JE2xFuPyS7o6DHQhJlUkyJtVU86bO2lp6bCD7Xz)j3Jo6htpAt0p(U7XA)S)62In3Fgd7GF6OdfVp48)3NNSr4YhvxoLF88N3hn33D)9NJq)Ce6)g9R7gHwBbnF2PEpDQJF2PElHX5VUyFF8LhiR8)j4t7N8HlA8O)Qk1NzRm)K7z7UkpA7YzU6f6dRP4sEVGV9fJoyOPyhjZRp)Y38Vp)Dtp8xpRhNmIoF7DnXx5C)VLYCg(9agMhEBeWW)qKRehm7zy2bGzJ(AGzFozP9caUVKLu3mu)KHfPVnR(jBW3AdC9uJM(mP2)zH2(CMQN9DauTlRw1Tm5pE(0)qWqY(zp2NRM8pE(Y9tq6YSvFB4y8ZsIQu4FXBKjUpNPD3ctdj2hVn3n7f(vzRoFzwv5M1mMn0hFj8naKla9bt)0544rZpKjZpKnt1WECtQW3cv5RTizNjAJxvqVctYRiAJu27bj5E4NCt(YLhb3BOl7M785SjYoc3C(r2EXrH2TERc2(oNp2lycEKre46A5tFqBeZPxXgbn6khlLr3hlEHpUXMbBXBVKDF0lGi7JP2uzBCe)3eZXJkO6ZR(5PHEY3Vcp6ZyVvwyBiF)G1XTen8LIFVri)ro8FDRJNcCiEyb9XSoMACt6Jl56d1MK0bydCexBqw70X2fFKQQOWgjoG)mVs5hiDlyyk6oabTJbTlxqW79POQK9gksVhIulH2n((KE62SIm67XFe3Wqe8Di)glmCw7dXdDZof1m(gBY6SvRZVlDn77ZlmZxap7IYLZ1c5R(DDIZyyMCVXB0HPunwaDGsipWc0pp8up)j6eP3I)PWQ1XQLLCKEjPcuUcngeUyT)1J4ge94oWEHRfJFH7aJPGe5J7DmXkq9)cpOT)H2hRPTyYZTgn0Mng6(TMjcOMgZx6aVYrEhxmJ)HZJB3AO1h2Os1kVXv4GgJIwFhy)Z8Q8RZxMx)aipPOsDnVfhthpHgC9BFPHMFAB7lLtnPD28IJGpglSaDlSGNelmRFMTWiW2VcJmi2tgGUoFiGTauKFepeGbJo(VFiNe(GiCo076n38CqiUoek0m2WxzSql)OihxFNypXH(vVgFbgS9cS9dIcCc98TIjIdSq4uOhDJsfZq3O(mdTh2SZlzv(QZ7xdhH)(VRA)0YctmxTddOxeuYsTlgjK2x5m5Olkz2c814Mj28Wwog7QxRWRryzBl1NVQqAUQ1k4qjmu9kKW2rz4Ihjs5PlpVy5duMQn)YXygqfUdyJcxhgDnFafLJiXKJ3RhPOI74xW5pBWVOv0fPhr8bpI)3))p" },
    { name = "Spin the Wheel", description = "Randomize all settings", exportString = nil },
}

EllesmereUI.WEEKLY_SPOTLIGHT = nil  -- { name = "...", description = "...", exportString = "!EUI_..." }
-- To set a weekly spotlight, uncomment and fill in:
-- EllesmereUI.WEEKLY_SPOTLIGHT = {
--     name = "Week 1 Spotlight",
--     description = "A clean minimal setup",
--     exportString = "!EUI_...",
-- }

-------------------------------------------------------------------------------
--  Spin the Wheel: global randomizer
--  Randomizes all addon settings except X/Y offsets, scale, and enable flags.
--  Does not touch Party Mode.
-------------------------------------------------------------------------------
function EllesmereUI.SpinTheWheel()
    local function rColor()
        return { r = math.random(), g = math.random(), b = math.random() }
    end
    local function rBool() return math.random() > 0.5 end
    local function pick(t) return t[math.random(#t)] end
    local function rRange(lo, hi) return lo + math.random() * (hi - lo) end
    local floor = math.floor

    -- Randomize each loaded addon (except Nameplates which has its own randomizer)
    for _, entry in ipairs(ADDON_DB_MAP) do
        if IsAddonLoaded(entry.folder) and entry.folder ~= "EllesmereUINameplates" then
            local profile = GetAddonProfile(entry)
            if profile then
                EllesmereUI._RandomizeProfile(profile, entry.folder)
            end
        end
    end

    -- Nameplates: use the existing randomizer keys from the preset system
    if IsAddonLoaded("EllesmereUINameplates") then
        local db = _G.EllesmereUINameplatesDB
        if db then
            EllesmereUI._RandomizeNameplates(db)
        end
    end

    -- Randomize global fonts
    local fontsDB = EllesmereUI.GetFontsDB()
    local validFonts = {}
    for _, name in ipairs(EllesmereUI.FONT_ORDER) do
        if name ~= "---" then validFonts[#validFonts + 1] = name end
    end
    fontsDB.global = pick(validFonts)
    local outlineModes = { "none", "outline", "shadow" }
    fontsDB.outlineMode = pick(outlineModes)

    -- Randomize class colors
    local colorsDB = EllesmereUI.GetCustomColorsDB()
    colorsDB.class = {}
    for token in pairs(EllesmereUI.CLASS_COLOR_MAP) do
        colorsDB.class[token] = rColor()
    end
end

--- Generic profile randomizer for AceDB-style addons.
--- Skips keys containing "offset", "Offset", "scale", "Scale", "X", "Y",
--- "pos", "Pos", "position", "Position", "anchor", "Anchor" (position-related),
--- and boolean keys that look like enable/disable toggles.
function EllesmereUI._RandomizeProfile(profile, folderName)
    local function rColor()
        return { r = math.random(), g = math.random(), b = math.random() }
    end
    local function rBool() return math.random() > 0.5 end

    local function IsPositionKey(k)
        local kl = k:lower()
        if kl:find("offset") then return true end
        if kl:find("scale") then return true end
        if kl:find("position") then return true end
        if kl:find("anchor") then return true end
        if kl == "x" or kl == "y" then return true end
        if kl == "offsetx" or kl == "offsety" then return true end
        if kl:find("unlockpos") then return true end
        return false
    end

    -- Boolean keys that control whether a feature/element is enabled.
    -- These should never be randomized — users want their frames to stay visible.
    local function IsEnableKey(k)
        local kl = k:lower()
        if kl == "enabled" then return true end
        if kl:sub(1, 6) == "enable" then return true end
        if kl:sub(1, 4) == "show" then return true end
        if kl:sub(1, 4) == "hide" then return true end
        if kl:find("enabled$") then return true end
        if kl:find("visible") then return true end
        return false
    end

    local function RandomizeTable(tbl, depth)
        if depth > 5 then return end  -- safety limit
        for k, v in pairs(tbl) do
            if type(k) == "string" and IsPositionKey(k) then
                -- Skip position/scale keys
            elseif type(k) == "string" and type(v) == "boolean" and IsEnableKey(k) then
                -- Skip enable/show/hide toggle keys
            elseif type(v) == "table" then
                -- Check if it's a color table
                if v.r and v.g and v.b then
                    tbl[k] = rColor()
                    if v.a then tbl[k].a = v.a end  -- preserve alpha
                else
                    RandomizeTable(v, depth + 1)
                end
            elseif type(v) == "boolean" then
                tbl[k] = rBool()
            elseif type(v) == "number" then
                -- Randomize numbers within a reasonable range of their current value
                if v == 0 then
                    -- Leave zero values alone (often flags)
                elseif v >= 0 and v <= 1 then
                    tbl[k] = math.random() -- 0-1 range (likely alpha/ratio)
                elseif v > 1 and v <= 50 then
                    tbl[k] = math.random(1, math.floor(v * 2))
                end
            end
        end
    end

    -- Snapshot visibility settings that must survive randomization
    local savedVis = {}

    if folderName == "EllesmereUIUnitFrames" and profile.enabledFrames then
        savedVis.enabledFrames = {}
        for k, v in pairs(profile.enabledFrames) do
            savedVis.enabledFrames[k] = v
        end
    elseif folderName == "EllesmereUICooldownManager" and profile.cdmBars then
        savedVis.cdmBars = {}
        if profile.cdmBars.bars then
            for i, bar in ipairs(profile.cdmBars.bars) do
                savedVis.cdmBars[i] = bar.barVisibility
            end
        end
    elseif folderName == "EllesmereUIResourceBars" then
        savedVis.secondary = profile.secondary and profile.secondary.visibility
        savedVis.health    = profile.health    and profile.health.visibility
        savedVis.primary   = profile.primary   and profile.primary.visibility
    elseif folderName == "EllesmereUIActionBars" and profile.bars then
        savedVis.bars = {}
        for key, bar in pairs(profile.bars) do
            savedVis.bars[key] = {
                alwaysHidden      = bar.alwaysHidden,
                mouseoverEnabled  = bar.mouseoverEnabled,
                mouseoverAlpha    = bar.mouseoverAlpha,
                combatHideEnabled = bar.combatHideEnabled,
                combatShowEnabled = bar.combatShowEnabled,
            }
        end
    end

    RandomizeTable(profile, 0)

    -- Restore visibility settings
    if folderName == "EllesmereUIUnitFrames" and savedVis.enabledFrames then
        if not profile.enabledFrames then profile.enabledFrames = {} end
        for k, v in pairs(savedVis.enabledFrames) do
            profile.enabledFrames[k] = v
        end
    elseif folderName == "EllesmereUICooldownManager" and savedVis.cdmBars then
        if profile.cdmBars and profile.cdmBars.bars then
            for i, vis in pairs(savedVis.cdmBars) do
                if profile.cdmBars.bars[i] then
                    profile.cdmBars.bars[i].barVisibility = vis
                end
            end
        end
    elseif folderName == "EllesmereUIResourceBars" then
        if profile.secondary then profile.secondary.visibility = savedVis.secondary end
        if profile.health    then profile.health.visibility    = savedVis.health    end
        if profile.primary   then profile.primary.visibility   = savedVis.primary   end
    elseif folderName == "EllesmereUIActionBars" and savedVis.bars then
        if profile.bars then
            for key, vis in pairs(savedVis.bars) do
                if profile.bars[key] then
                    profile.bars[key].alwaysHidden      = vis.alwaysHidden
                    profile.bars[key].mouseoverEnabled   = vis.mouseoverEnabled
                    profile.bars[key].mouseoverAlpha     = vis.mouseoverAlpha
                    profile.bars[key].combatHideEnabled  = vis.combatHideEnabled
                    profile.bars[key].combatShowEnabled  = vis.combatShowEnabled
                end
            end
        end
    end
end

--- Nameplate-specific randomizer (reuses the existing logic from the
--- commented-out preset system in the nameplates options file)
function EllesmereUI._RandomizeNameplates(db)
    local function rColor()
        return { r = math.random(), g = math.random(), b = math.random() }
    end
    local function rBool() return math.random() > 0.5 end
    local function pick(t) return t[math.random(#t)] end

    local borderOptions = { "ellesmere", "simple" }
    local glowOptions = { "ellesmereui", "vibrant", "none" }
    local cpPosOptions = { "bottom", "top" }
    local timerOptions = { "topleft", "center", "topright", "none" }

    -- Aura slots: exclusive pick
    local auraSlots = { "top", "left", "right", "topleft", "topright", "bottom" }
    local function pickAuraSlot()
        if #auraSlots == 0 then return "none" end
        local i = math.random(#auraSlots)
        local s = auraSlots[i]
        table.remove(auraSlots, i)
        return s
    end

    db.borderStyle = pick(borderOptions)
    db.borderColor = rColor()
    db.targetGlowStyle = pick(glowOptions)
    db.showTargetArrows = rBool()
    db.showClassPower = rBool()
    db.classPowerPos = pick(cpPosOptions)
    db.classPowerClassColors = rBool()
    db.classPowerGap = math.random(0, 6)
    db.classPowerCustomColor = rColor()
    db.classPowerBgColor = rColor()
    db.classPowerEmptyColor = rColor()

    -- Text slots
    local textPool = { "enemyName", "healthPercent", "healthNumber",
        "healthPctNum", "healthNumPct" }
    local function pickText()
        if #textPool == 0 then return "none" end
        local i = math.random(#textPool)
        local e = textPool[i]
        table.remove(textPool, i)
        return e
    end
    db.textSlotTop = pickText()
    db.textSlotRight = pickText()
    db.textSlotLeft = pickText()
    db.textSlotCenter = pickText()
    db.textSlotTopColor = rColor()
    db.textSlotRightColor = rColor()
    db.textSlotLeftColor = rColor()
    db.textSlotCenterColor = rColor()

    db.healthBarHeight = math.random(10, 24)
    db.healthBarWidth = math.random(2, 10)
    db.castBarHeight = math.random(10, 24)
    db.castNameSize = math.random(8, 14)
    db.castNameColor = rColor()
    db.castTargetSize = math.random(8, 14)
    db.castTargetClassColor = rBool()
    db.castTargetColor = rColor()
    db.castScale = math.random(10, 40) * 5
    db.showCastIcon = math.random() > 0.3
    db.castIconScale = math.floor((0.5 + math.random() * 1.5) * 10 + 0.5) / 10

    db.debuffSlot = pickAuraSlot()
    db.buffSlot = pickAuraSlot()
    db.ccSlot = pickAuraSlot()
    db.debuffYOffset = math.random(0, 8)
    db.sideAuraXOffset = math.random(0, 8)
    db.auraSpacing = math.random(0, 6)

    db.topSlotSize = math.random(18, 34)
    db.rightSlotSize = math.random(18, 34)
    db.leftSlotSize = math.random(18, 34)
    db.toprightSlotSize = math.random(18, 34)
    db.topleftSlotSize = math.random(18, 34)

    local timerPos = pick(timerOptions)
    db.debuffTimerPosition = timerPos
    db.buffTimerPosition = timerPos
    db.ccTimerPosition = timerPos

    db.auraDurationTextSize = math.random(8, 14)
    db.auraDurationTextColor = rColor()
    db.auraStackTextSize = math.random(8, 14)
    db.auraStackTextColor = rColor()
    db.buffTextSize = math.random(8, 14)
    db.buffTextColor = rColor()
    db.ccTextSize = math.random(8, 14)
    db.ccTextColor = rColor()

    db.raidMarkerPos = pickAuraSlot()
    db.classificationSlot = pickAuraSlot()

    db.textSlotTopSize = math.random(8, 14)
    db.textSlotRightSize = math.random(8, 14)
    db.textSlotLeftSize = math.random(8, 14)
    db.textSlotCenterSize = math.random(8, 14)

    db.hashLineEnabled = math.random() > 0.7
    db.hashLinePercent = math.random(10, 50)
    db.hashLineColor = rColor()
    db.focusCastHeight = 100 + math.random(0, 4) * 25

    -- Font
    local validFonts = {}
    for _, f in ipairs(EllesmereUI.FONT_ORDER) do
        if f ~= "---" then validFonts[#validFonts + 1] = f end
    end
    db.font = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\"
        .. (EllesmereUI.FONT_FILES[pick(validFonts)] or "Expressway.TTF")

    -- Colors
    db.focusColorEnabled = true
    db.tankHasAggroEnabled = true
    db.focus = rColor()
    db.caster = rColor()
    db.miniboss = rColor()
    db.enemyInCombat = rColor()
    db.castBar = rColor()
    db.interruptReady = rColor()
    db.castBarUninterruptible = rColor()
    db.tankHasAggro = rColor()
    db.tankLosingAggro = rColor()
    db.tankNoAggro = rColor()
    db.dpsHasAggro = rColor()
    db.dpsNearAggro = rColor()

    -- Bar texture (skip texture key randomization — texture list is addon-local)
    db.healthBarTextureClassColor = math.random() > 0.5
    if not db.healthBarTextureClassColor then
        db.healthBarTextureColor = rColor()
    end
    db.healthBarTextureScale = math.random(5, 20) / 10
    db.healthBarTextureFit = math.random() > 0.3
end

-------------------------------------------------------------------------------
--  Initialize profile system on first login
--  Creates the "Custom" profile from current settings if none exists.
--  Also saves the active profile on logout (via Lite pre-logout callback)
--  so SavedVariables are current before StripDefaults runs.
-------------------------------------------------------------------------------
do
    -- Register pre-logout save via Lite so it runs BEFORE StripDefaults
    EllesmereUI.Lite.RegisterPreLogout(function()
        if not EllesmereUI._profileSaveLocked then
            local db = GetProfilesDB()
            local name = db.activeProfile or "Custom"
            db.profiles[name] = EllesmereUI.SnapshotAllAddons()
        end
    end)

    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")

        local db = GetProfilesDB()
        -- On first install, create "Custom" from current (default) settings
        if not db.activeProfile then
            db.activeProfile = "Custom"
        end
        -- Ensure Custom profile exists with current settings
        if not db.profiles["Custom"] then
            -- Delay slightly to let all addons initialize their DBs
            EllesmereUI._profileSaveLocked = true
            C_Timer.After(0.5, function()
                db.profiles["Custom"] = EllesmereUI.SnapshotAllAddons()
                EllesmereUI._profileSaveLocked = false
            end)
        end
        -- Ensure Custom is in the order list
        local hasCustom = false
        for _, n in ipairs(db.profileOrder) do
            if n == "Custom" then hasCustom = true; break end
        end
        if not hasCustom then
            table.insert(db.profileOrder, "Custom")
        end

        -- Auto-save active profile when the settings panel closes
        C_Timer.After(1, function()
            if EllesmereUI._mainFrame and not EllesmereUI._profileAutoSaveHooked then
                EllesmereUI._profileAutoSaveHooked = true
                EllesmereUI._mainFrame:HookScript("OnHide", function()
                    EllesmereUI.AutoSaveActiveProfile()
                end)
            end

            -- Debounced auto-save on every settings change (RefreshPage call).
            -- Uses a 2-second timer so rapid slider drags collapse into one save.
            if not EllesmereUI._profileRefreshHooked then
                EllesmereUI._profileRefreshHooked = true
                local _saveTimer = nil
                local _origRefresh = EllesmereUI.RefreshPage
                EllesmereUI.RefreshPage = function(self, ...)
                    _origRefresh(self, ...)
                    if _saveTimer then _saveTimer:Cancel() end
                    _saveTimer = C_Timer.NewTimer(2, function()
                        _saveTimer = nil
                        EllesmereUI.AutoSaveActiveProfile()
                    end)
                end
            end
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
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
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
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
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
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
        scrollTarget = math.max(0, math.min(maxScroll, target))
        if not isSmoothing then isSmoothing = true; smoothFrame:Show() end
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = tonumber(self:GetVerticalScrollRange()) or 0
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
            local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
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

-------------------------------------------------------------------------------
--  CDM Spell Profiles
--  Separate import/export system for CDM ability assignments only.
--  Captures which spells are assigned to which bars and tracked buff bars,
--  but NOT bar glows, visual styling, or positions.
--
--  Export format: !EUICDM_<base64 encoded compressed serialized data>
--  Payload: { version = 1, bars = { ... }, buffBars = { ... } }
--
--  On import, the system:
--    1. Decodes and validates the string
--    2. Analyzes which spells need to be tracked/enabled in CDM
--    3. Prints required spells to chat
--    4. Blocks import until all spells are verified as tracked
--    5. Applies the layout once verified
-------------------------------------------------------------------------------

--- Snapshot the current CDM spell profile (spell assignments only, no styling/glows)
function EllesmereUI.ExportCDMLayout()
    local aceDB = _G._ECME_AceDB
    if not aceDB or not aceDB.profile then return nil, "CDM not loaded" end
    local p = aceDB.profile
    if not p.cdmBars or not p.cdmBars.bars then return nil, "No CDM bars found" end

    local layoutData = { bars = {}, buffBars = {} }

    -- Capture bar definitions and spell assignments
    for _, barData in ipairs(p.cdmBars.bars) do
        local entry = {
            key      = barData.key,
            name     = barData.name,
            barType  = barData.barType,
            enabled  = barData.enabled,
        }
        -- Spell assignments depend on bar type
        if barData.trackedSpells then
            entry.trackedSpells = DeepCopy(barData.trackedSpells)
        end
        if barData.extraSpells then
            entry.extraSpells = DeepCopy(barData.extraSpells)
        end
        if barData.removedSpells then
            entry.removedSpells = DeepCopy(barData.removedSpells)
        end
        if barData.dormantSpells then
            entry.dormantSpells = DeepCopy(barData.dormantSpells)
        end
        if barData.customSpells then
            entry.customSpells = DeepCopy(barData.customSpells)
        end
        layoutData.bars[#layoutData.bars + 1] = entry
    end

    -- Capture tracked buff bars (spellID assignments only, not visual settings)
    if p.trackedBuffBars and p.trackedBuffBars.bars then
        for i, tbb in ipairs(p.trackedBuffBars.bars) do
            layoutData.buffBars[#layoutData.buffBars + 1] = {
                spellID = tbb.spellID,
                name    = tbb.name,
                enabled = tbb.enabled,
            }
        end
    end

    local payload = { version = 1, data = layoutData }
    local serialized = Serializer.Serialize(payload)
    if not LibDeflate then return nil, "LibDeflate not available" end
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return CDM_LAYOUT_PREFIX .. encoded
end

--- Decode a CDM spell profile import string without applying it
function EllesmereUI.DecodeCDMLayoutString(importStr)
    if not importStr or #importStr < 5 then
        return nil, "Invalid string"
    end
    -- Detect profile strings pasted into the wrong import
    if importStr:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        return nil, "This is a UI Profile string, not a CDM bar layout string."
    end
    if importStr:sub(1, #CDM_LAYOUT_PREFIX) ~= CDM_LAYOUT_PREFIX then
        return nil, "Not a valid CDM spell profile string. Make sure you copied the entire string."
    end
    if not LibDeflate then return nil, "LibDeflate not available" end
    local encoded = importStr:sub(#CDM_LAYOUT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return nil, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return nil, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if not payload or type(payload) ~= "table" then
        return nil, "Failed to deserialize data"
    end
    if payload.version ~= 1 then
        return nil, "Unsupported CDM spell profile version"
    end
    if not payload.data or not payload.data.bars then
        return nil, "Invalid CDM spell profile data"
    end
    return payload.data, nil
end

--- Collect all unique spellIDs from a decoded CDM spell profile
local function CollectLayoutSpellIDs(layoutData)
    local spells = {}  -- { [spellID] = barName }
    for _, bar in ipairs(layoutData.bars) do
        local barName = bar.name or bar.key or "Unknown"
        if bar.trackedSpells then
            for _, sid in ipairs(bar.trackedSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        if bar.extraSpells then
            for _, sid in ipairs(bar.extraSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        if bar.customSpells then
            for _, sid in ipairs(bar.customSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        -- dormantSpells are talent-dependent, include them too
        if bar.dormantSpells then
            for _, sid in ipairs(bar.dormantSpells) do
                if sid and sid > 0 then spells[sid] = barName end
            end
        end
        -- removedSpells are intentionally excluded from bars, don't require them
    end
    -- Buff bar spells
    if layoutData.buffBars then
        for _, tbb in ipairs(layoutData.buffBars) do
            if tbb.spellID and tbb.spellID > 0 then
                spells[tbb.spellID] = "Buff Bar: " .. (tbb.name or "Unknown")
            end
        end
    end
    return spells
end

--- Check which spells from a layout are currently tracked in CDM
--- Returns: missingSpells (table of {spellID, name, barName}), allPresent (bool)
function EllesmereUI.AnalyzeCDMLayoutSpells(layoutData)
    local aceDB = _G._ECME_AceDB
    if not aceDB or not aceDB.profile then
        return {}, false
    end
    local p = aceDB.profile

    -- Build set of all currently tracked spellIDs across all bars
    local currentlyTracked = {}
    if p.cdmBars and p.cdmBars.bars then
        for _, barData in ipairs(p.cdmBars.bars) do
            if barData.trackedSpells then
                for _, sid in ipairs(barData.trackedSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.extraSpells then
                for _, sid in ipairs(barData.extraSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.removedSpells then
                for _, sid in ipairs(barData.removedSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.customSpells then
                for _, sid in ipairs(barData.customSpells) do
                    currentlyTracked[sid] = true
                end
            end
            if barData.dormantSpells then
                for _, sid in ipairs(barData.dormantSpells) do
                    currentlyTracked[sid] = true
                end
            end
        end
    end
    -- Also check buff bars
    if p.trackedBuffBars and p.trackedBuffBars.bars then
        for _, tbb in ipairs(p.trackedBuffBars.bars) do
            if tbb.spellID and tbb.spellID > 0 then
                currentlyTracked[tbb.spellID] = true
            end
        end
    end

    -- Compare against layout requirements
    local requiredSpells = CollectLayoutSpellIDs(layoutData)
    local missing = {}
    for sid, barName in pairs(requiredSpells) do
        if not currentlyTracked[sid] then
            local spellName
            if C_Spell and C_Spell.GetSpellName then
                spellName = C_Spell.GetSpellName(sid)
            end
            missing[#missing + 1] = {
                spellID = sid,
                name    = spellName or ("Spell #" .. sid),
                barName = barName,
            }
        end
    end

    -- Sort by bar name then spell name for readability
    table.sort(missing, function(a, b)
        if a.barName == b.barName then return a.name < b.name end
        return a.barName < b.barName
    end)

    return missing, #missing == 0
end

--- Print missing spells to chat
function EllesmereUI.PrintCDMLayoutMissingSpells(missing)
    local EG = "|cff0cd29f"
    local WHITE = "|cffffffff"
    local YELLOW = "|cffffff00"
    local GRAY = "|cff888888"
    local R = "|r"

    print(EG .. "EllesmereUI|r: CDM Spell Profile Import - Spell Check")
    print(EG .. "----------------------------------------------|r")

    if #missing == 0 then
        print(EG .. "All spells are already tracked. Ready to import.|r")
        return
    end

    print(YELLOW .. #missing .. " spell(s) need to be enabled in CDM before importing:|r")
    print(" ")

    local lastBar = nil
    for _, entry in ipairs(missing) do
        if entry.barName ~= lastBar then
            lastBar = entry.barName
            print(EG .. "  [" .. entry.barName .. "]|r")
        end
        print(WHITE .. "    - " .. entry.name .. GRAY .. " (ID: " .. entry.spellID .. ")" .. R)
    end

    print(" ")
    print(YELLOW .. "Enable these spells in CDM, then click Import again.|r")
end

--- Apply a decoded CDM spell profile to the current profile
function EllesmereUI.ApplyCDMLayout(layoutData)
    local aceDB = _G._ECME_AceDB
    if not aceDB or not aceDB.profile then return false, "CDM not loaded" end
    local p = aceDB.profile
    if not p.cdmBars or not p.cdmBars.bars then return false, "No CDM bars found" end

    -- Build a lookup of existing bars by key
    local existingByKey = {}
    for i, barData in ipairs(p.cdmBars.bars) do
        existingByKey[barData.key] = barData
    end

    -- Apply spell assignments from the layout
    for _, importBar in ipairs(layoutData.bars) do
        local target = existingByKey[importBar.key]
        if target then
            -- Bar exists: update spell assignments only
            if importBar.trackedSpells then
                target.trackedSpells = DeepCopy(importBar.trackedSpells)
            end
            if importBar.extraSpells then
                target.extraSpells = DeepCopy(importBar.extraSpells)
            end
            if importBar.removedSpells then
                target.removedSpells = DeepCopy(importBar.removedSpells)
            end
            if importBar.dormantSpells then
                target.dormantSpells = DeepCopy(importBar.dormantSpells)
            end
            if importBar.customSpells then
                target.customSpells = DeepCopy(importBar.customSpells)
            end
            target.enabled = importBar.enabled
        end
        -- If bar doesn't exist (custom bar from another user), skip it.
        -- We only apply to matching bar keys.
    end

    -- Apply tracked buff bars
    if layoutData.buffBars and #layoutData.buffBars > 0 then
        if not p.trackedBuffBars then
            p.trackedBuffBars = { selectedBar = 1, bars = {} }
        end
        -- Merge: update existing buff bars by index, add new ones
        for i, importTBB in ipairs(layoutData.buffBars) do
            if p.trackedBuffBars.bars[i] then
                -- Update existing buff bar's spell assignment
                p.trackedBuffBars.bars[i].spellID = importTBB.spellID
                p.trackedBuffBars.bars[i].name = importTBB.name
                p.trackedBuffBars.bars[i].enabled = importTBB.enabled
            else
                -- Add new buff bar with default visual settings + imported spell
                local newBar = {}
                -- Use TBB defaults if available
                local defaults = {
                    spellID = importTBB.spellID,
                    name = importTBB.name or ("Bar " .. i),
                    enabled = importTBB.enabled ~= false,
                    height = 24, width = 270,
                    verticalOrientation = false,
                    texture = "none",
                    fillR = 0.05, fillG = 0.82, fillB = 0.62, fillA = 1,
                    bgR = 0, bgG = 0, bgB = 0, bgA = 0.4,
                    gradientEnabled = false,
                    gradientR = 0.20, gradientG = 0.20, gradientB = 0.80, gradientA = 1,
                    gradientDir = "HORIZONTAL",
                    opacity = 1.0,
                    showTimer = true, timerSize = 11, timerX = 0, timerY = 0,
                    showName = true, nameSize = 11, nameX = 0, nameY = 0,
                    showSpark = true,
                    iconDisplay = "none", iconSize = 24, iconX = 0, iconY = 0,
                    iconBorderSize = 0,
                }
                for k, v in pairs(defaults) do newBar[k] = v end
                p.trackedBuffBars.bars[#p.trackedBuffBars.bars + 1] = newBar
            end
        end
    end

    -- Save to current spec profile
    local specKey = p.activeSpecKey
    if specKey and specKey ~= "0" and p.specProfiles then
        -- Update the spec profile's barSpells to match
        if not p.specProfiles[specKey] then p.specProfiles[specKey] = {} end
        local prof = p.specProfiles[specKey]
        prof.barSpells = {}
        for _, barData in ipairs(p.cdmBars.bars) do
            local key = barData.key
            if key then
                local entry = {}
                if barData.trackedSpells then
                    entry.trackedSpells = DeepCopy(barData.trackedSpells)
                end
                if barData.extraSpells then
                    entry.extraSpells = DeepCopy(barData.extraSpells)
                end
                if barData.removedSpells then
                    entry.removedSpells = DeepCopy(barData.removedSpells)
                end
                if barData.dormantSpells then
                    entry.dormantSpells = DeepCopy(barData.dormantSpells)
                end
                if barData.customSpells then
                    entry.customSpells = DeepCopy(barData.customSpells)
                end
                prof.barSpells[key] = entry
            end
        end
        -- Update buff bars in spec profile
        if p.trackedBuffBars then
            prof.trackedBuffBars = DeepCopy(p.trackedBuffBars)
        end
    end

    return true, nil
end
