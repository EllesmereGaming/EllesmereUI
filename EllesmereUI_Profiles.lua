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
    -- Keys managed by CDM's internal spec profile system -- never include
    -- in layout snapshots so they are not overwritten on profile switch.
    local CDM_INTERNAL = {
        specProfiles = true,
        activeSpecKey = true,
        barGlows = true,
        trackedBuffBars = true,
        spec = true,
    }
    for k, v in pairs(src) do
        if CDM_INTERNAL[k] then
            -- Omit -- managed by CDM's own spec system
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
    -- Keys managed by CDM's internal spec profile system -- never overwrite
    -- from a layout snapshot so spell assignments survive profile switches.
    local CDM_INTERNAL = {
        specProfiles = true,
        _capturedOnce = true,
        activeSpecKey = true,
        barGlows = true,
        trackedBuffBars = true,
        spec = true,
    }
    -- Apply top-level non-spell keys
    for k, v in pairs(snap) do
        if CDM_INTERNAL[k] then
            -- Skip -- managed by CDM's own spec system
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
                    -- Ensure per-unit bg colors are never nil after a profile load
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
    return CDM_LAYOUT_PREFIX .. encoded
end

--- Import CDM spell profiles from a string. Overwrites matching spec profiles.
function EllesmereUI.ImportCDMSpellLayouts(importStr)
    -- Detect profile strings pasted into the wrong import
    if importStr and importStr:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        return false, "This is a UI Profile string, not a CDM Spell Profile. Use the Profile import instead."
    end
    if not importStr or #importStr < 5 then
        return false, "Invalid string"
    end
    if importStr:sub(1, #CDM_LAYOUT_PREFIX) ~= CDM_LAYOUT_PREFIX then
        return false, "Not a valid CDM Spell Profile string. Make sure you copied the entire string."
    end
    if not LibDeflate then return false, "LibDeflate not available" end

    local encoded = importStr:sub(#CDM_LAYOUT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return false, "Failed to decode string" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return false, "Failed to decompress data" end
    local payload = Serializer.Deserialize(decompressed)
    if not payload or type(payload) ~= "table" then
        return false, "Failed to deserialize data"
    end
    if payload.version ~= 1 then
        return false, "Unsupported CDM spell profile version"
    end
    if payload.type ~= "cdm_spells" or not payload.data then
        return false, "Invalid CDM spell profile data"
    end

    local cdmEntry
    for _, e in ipairs(ADDON_DB_MAP) do
        if e.folder == "EllesmereUICooldownManager" then cdmEntry = e; break end
    end
    if not cdmEntry then return false, "Cooldown Manager not found" end
    local profile = GetAddonProfile(cdmEntry)
    if not profile then return false, "Cooldown Manager profile not available" end

    if not profile.specProfiles then profile.specProfiles = {} end

    -- Build a set of spellIDs the importing user actually has in their CDM
    -- viewer. Spells not in this set are "not displayed" and should be
    -- filtered out so the user is not given spells they cannot track.
    local userCDMSpells
    if _G._ECME_GetCDMSpellSet then
        userCDMSpells = _G._ECME_GetCDMSpellSet()
    end

    -- Helper: filter an array of spellIDs, keeping only those in the user's CDM
    local function FilterSpellList(list)
        if not list or not userCDMSpells then return list end
        local filtered = {}
        for _, sid in ipairs(list) do
            if userCDMSpells[sid] then
                filtered[#filtered + 1] = sid
            end
        end
        return filtered
    end

    -- Helper: filter a removedSpells table (spellID keys, boolean values)
    local function FilterSpellMap(map)
        if not map or not userCDMSpells then return map end
        local filtered = {}
        for sid, v in pairs(map) do
            if userCDMSpells[sid] then
                filtered[sid] = v
            end
        end
        return filtered
    end

    -- Overwrite matching spec profiles from the imported data, filtering spells
    local count = 0
    for specKey, specData in pairs(payload.data) do
        local data = DeepCopy(specData)

        -- Filter barSpells
        if data.barSpells then
            for barKey, barSpells in pairs(data.barSpells) do
                if barSpells.trackedSpells then
                    barSpells.trackedSpells = FilterSpellList(barSpells.trackedSpells)
                end
                if barSpells.extraSpells then
                    barSpells.extraSpells = FilterSpellList(barSpells.extraSpells)
                end
                if barSpells.removedSpells then
                    barSpells.removedSpells = FilterSpellMap(barSpells.removedSpells)
                end
                if barSpells.dormantSpells then
                    barSpells.dormantSpells = FilterSpellMap(barSpells.dormantSpells)
                end
                if barSpells.customSpells then
                    barSpells.customSpells = FilterSpellList(barSpells.customSpells)
                end
            end
        end

        -- Filter tracked buff bars
        if data.trackedBuffBars and data.trackedBuffBars.bars then
            local kept = {}
            for _, tbb in ipairs(data.trackedBuffBars.bars) do
                if not tbb.spellID or tbb.spellID <= 0
                   or not userCDMSpells
                   or userCDMSpells[tbb.spellID] then
                    kept[#kept + 1] = tbb
                end
            end
            data.trackedBuffBars.bars = kept
        end

        profile.specProfiles[specKey] = data
        count = count + 1
    end

    -- If the user's current spec matches one of the imported specs, apply it
    -- to the live bars immediately so it takes effect without a /reload.
    if _G._ECME_GetCurrentSpecKey and _G._ECME_LoadSpecProfile then
        local currentKey = _G._ECME_GetCurrentSpecKey()
        if currentKey and payload.data[currentKey] then
            _G._ECME_LoadSpecProfile(currentKey)
            -- Rebuild visual CDM bar frames with the newly loaded data
            if _G._ECME_Apply then _G._ECME_Apply() end
        end
    end

    return true, nil, count
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
        return nil, "This is a CDM Spell Profile string. Use the CDM Spell Profile import instead."
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
        db.profiles[profileName] = DeepCopy(payload.data)
        -- Add to order if not present
        local found = false
        for _, n in ipairs(db.profileOrder) do
            if n == profileName then found = true; break end
        end
        if not found then
            table.insert(db.profileOrder, 1, profileName)
        end
        if specLocked then
            -- Save the profile but do not activate or apply it
            return true, nil, "spec_locked"
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
        if specLocked then
            return true, nil, "spec_locked"
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
    local pendingReload = false
    specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    specFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    specFrame:SetScript("OnEvent", function(_, event, unit)
        -- Deferred reload: fire once combat ends
        if event == "PLAYER_REGEN_ENABLED" then
            if pendingReload then
                pendingReload = false
                StaticPopup_Show("EUI_PROFILE_RELOAD")
            end
            return
        end

        -- PLAYER_ENTERING_WORLD has no unit arg; PLAYER_SPECIALIZATION_CHANGED
        -- fires with "player" as unit. For PEW, always check current spec.
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
            return
        end
        local specIdx = GetSpecialization and GetSpecialization() or 0
        local specID = specIdx and specIdx > 0
            and GetSpecializationInfo(specIdx) or nil
        if not specID then return end

        local isFirstLogin = (lastKnownSpecID == nil)

        -- On PLAYER_ENTERING_WORLD (reload/zone-in), only switch if the spec
        -- actually changed. A plain /reload should not override the user's
        -- active profile selection.
        if event == "PLAYER_ENTERING_WORLD" then
            if not isFirstLogin and specID == lastKnownSpecID then
                return -- spec unchanged on reload/zone-in, skip
            end
        end
        lastKnownSpecID = specID

        local db = GetProfilesDB()
        local targetProfile = db.specProfiles[specID]
        if targetProfile and db.profiles[targetProfile] then
            local current = db.activeProfile or "Custom"
            if current ~= targetProfile then
                -- Auto-save current before switching (skip on first login,
                -- SavedVariables already has the previous character's save)
                if not isFirstLogin then
                    db.profiles[current] = EllesmereUI.SnapshotAllAddons()
                end
                if isFirstLogin then
                    -- On first login, addons already loaded correct state from
                    -- SavedVariables. Just update the active profile name so the
                    -- UI shows the right profile -- don't apply snapshot data on
                    -- top, which would overwrite positions with stale values.
                    db.activeProfile = targetProfile
                else
                    EllesmereUI.SwitchProfile(targetProfile)
                    if InCombatLockdown() then
                        pendingReload = true
                    else
                        StaticPopup_Show("EUI_PROFILE_RELOAD")
                    end
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
    { name = "EllesmereUI (2k)", description = "The default EllesmereUI look", exportString = "!EUI_T31wZTnoY6)kZJNZdrfVFlpz7yNKYtsC5OzNKTMQCrjrBXtKj1ssfhpP8)9t3ObibibOKSD8KzhpvT16qrIl9LV(RBac(9tR9sAUDDg8)D5MvRoTom5Rzv15Lff2Ve)XfPnPWD5NCzzrtn8xbjxTQCw6QABRKJ)26QS66BsV90AB7KYnnRYlYEx5cS9kklYUdUUtY8n1nLxFu5QYQAwBnFvAD93V7oS1sxSOSaVStqYXRwLvFDwv2V92JklxTO8MI3LwKEvw13zn0SnxE5HPvFCE6Qm24lsCjSbItQxwEZ0CObMItKzLvlYQoSW6LS)1vhSA9Y0cRjESj2S0Qxd)Jih4Fbtf6M)y(FsnS4PpN)01RtNNxCvbE3bjRkN)LSfNWEWlZx1KvXMZUjPOimkjFEzb1uryR7MSPo7iCoZKbN018hW6S2w5xZRBQTsWFV8YlRZA(uHRfnaYksNTI1N(j3KVOzzHd7xyteyoojGgAxvvEZVTM1fxN(nuYuejnFEnB(eKSml)QLn04t0zFU4fsTjmZNy5ZKXOy9TWuA6D4VvVoBoQUsc8)o(RxNUEniAQ)(3vhNG(kDEdyjD4MMgU9uyY8fx)XvLnS)vS4gsR4)BW06gMmc13jZGHat(KCvRMkbVv24Oi9AqKBLCiyb8lVh(h)Y)t2vj)YRY)kyd(lNTPADzD2)lENxJkNGKdoA6B)xhl6Mp2Cl3icSCxMVi7KkWg9vV7e0S02pPoBv28MSfVJMEuV6M4e49pYzTZp4znDvL5mji(lAwJ)qqYCokKcOJJFYfxNFvvk8eFaqlRGg8JRZwT6TVQEkZDhaf)sEXHmpo8soEDpXzamq(x79axmpDDZMkO9kMNnLjp30KVkV52UULjp5qDTY(PCVvMgbMjKx(0L5Z)sbGmJO7lZlqpEeM4kcm02lz(Y0QRYobW0jCkUSPUjD(xoQCtrZH8(SyZ1NxEtnj8cri(pC55PfxLHZ8vP3oL9COU9RzhuKF95kWNe(MBYxYUfufcPzndYR(M81zcm5qAyb33S8IfFGd(5WE4z4WEIfhknTy(YYQpWrS4theH6JTJ9tufqrIM91SrdxuCU4zv6ted8LspYbqphtYg(vi5f7z7Sp6eK0tpt2Err(WI54t9myPMcADWQ4dfh9QPTg6Xjh1jPurUbvm1wWSTH1GyVTk)p)Z0Qf9uHNxmqRssamskkcoU1)ffYN3kKd4DP2qwKjuexpmTe(bUPkPjA7RodlhYPdDER)9LzfVTGMdtz2bSHczhyll65dFxwiTxLxLXWpaz0VE8j8NunMTJLKCwzSJYaKAaivBYXGJsHO9SEz7nCeZROEA)i(GeH9ZCTY0SV1mLeAO9raEhXiVPMCqP)HQ8Scq7ad2tgyX(jbBej2fkAiUjDuYYYn1q))gqWDCRPmiGPw7SY6CU4yv2Ln9mYe6iUK8qoIlBoVmDTGDMqo8VllVwO8Xj1Rf)dURYRhom)uHKy7uQBOzl8e)R868zmtcKF3kGEy9DJdp1BOQdO5KthhGY5L9r52nyjvZxnaq6GQ6mp42OdrL6H6idinWCufssJpSjX6PpTatHj)Mqw1dwspmQoK5Fm4rBdx8jayYp583(63SNitkr3KqLCS7CV6qL0cM8aaN6Hdzc0rd(KrCiPadcqgnqtgyG8uar1l0(EcmDpzoPamnGCHoyjFwMT1NQdg7EIiPhEtgysXA8VlGs(SScgYuAhHK6BG)peiPEHNgJHKRt3n8FJyr6jB8uGfzkUWwaLEusMthOdmEOA1DH3f2EUor22xeghCQ(010HXOqZzeactGbg8kgX93Xj5i2y(xAtA6xGSK)f7(acH4OzkwRt1mrh68)JWvFuAqBZ9vnhydzHVx1Wu29o4PW9UFw3MtJPV)ToV4biHMWlgbo9hGdE)qz9cI8xLBnOu4U1(OBDSLLZfH(pHE19LlM9Mb9i3BMPY07jVv)PFqUXADjgquWaeMQp8JUZQPa)3Fp2901rxKztbX1qKzOpUrmcfOKhOhRgy4U4eCo4)v522fnoG72gEHNL3tOF7(hnwN)RZ90)1uiOhQF8afSoVyvpWTga(KT7tB2jDR(39rYUVU068BhlHdnU0pmxxticpMU0dZNu1dFVCNVhfIC7UZHG7SNVFq0fbUopHUZ7ryy)K3LxppB1Q0ImqHPjgSg(RpDUWArq2H4U9kRVbW6F(DKvzt)Jkx5b(67jLGhOJSoqzbYDustvEXxYAQzRuRn(dVk7Y0nRyBsLF8v0t1dxFP12zh7XCMhXytT4pAQtOE0Rb1Fu1AAFjdSZ1RtR(ufszyvd3jyMrSlF0tcW8kZPRCJJrRxtwSpcRCWtt688oqUEHdQN4dc7zyD6ucm)JaUPF15ggKH2oBmtnUbXuAdKq7mJ2j23p1e5D2ED5wW2g88SdcTd9DIDzkWQSvNvMx0aJZJo(9tp(CCNETU3vSt(wXlSJcMe6fh5f6z7yZ2Hmg4wi6n7jH(wwX2((oHUE7z35ehmjg(VGyVihphS7KkGgVlErC4KOixBxy645hUNDHNZKWGGOWahhRqlxSl4uZfnVF8Kq7apxRGapRaN9R9TWguFrqesiFsef64fg74VFn)lCDIM4zhe4h4f7z7H9w7QkljFcJJJSSIcDIS2tvEG)epqdyhybIPGxY31snvP42q8WUDajAcZ3ktI9zfF3bXEexbY26S5NImstc8zw0nZM1z7EhNO4RxbX6Ogf3YsxvCDgTdqDtSVWMTFJSODYPasQ)MTYWUXA32QBiwjBlsv444gzhs82Fc7XyqoFNwzkr34JznnI9cx)Xva1umH5whtJT13uNG3DxVKaIAhBh0QIeesAh10wYlKmBcv2KTBQQzdc3KLzFdgIwh9kN4xHMH1TPjWm0YxXc5C18fs39jS)dNTvPlY3utRAD7ZArzJL2aaOlzJxi0klwxefmeyWDfe0bU8kC3OYmfZlaC5I5aNHvSmT0T3zf77W70(eGQiTU5O8Q5RYKgSUNCqOYG11ApgSq)aHUR(sxa)UHFae)P660v7Y4FAVXFVu6gEVnqq5nvzOnh2FxqD1DmopsAsCprUEfqyH5XcZ506L)AErMoRmBUjgZadUxSlW9P55OsG9WzPRAwEww1CWCIzU3uUgVdgbdhgXGWKllb8uw7lXcIyuCcYvyXQBF)zhvJvs0HPsa3NFRaa3YQQ2SUjFgt9GdmRjE(TEa8)Cg9Neshsta7)prSxOW1X4OQchZd(jxr)9g(2CoK8AfZ0PLRbpRSISRVffCenlGQ6Rq6QaiiYesIHBmWLfJgX2A5TaLHy)tey8ODhVVFYBXP3LPZZ(JdwS4df1)HKo6pUoBrE6FWU1)OBRZpz6uug5MCPqQbdj085Z8P0lC4K1i9cmTMYnkKk4c4IU4DGbkN7OJhnJXS5)SSObykV(9BUEgBIit3A(CSv3U9IdXzeKVSTeoZqKH9Dw5naX6UT6)qSnVwnllepmQ52vkJWWK1PflYUoFogbcIvLTOWJCbrLWBB3ImEeoxRf15zPlUT1Kk2PTJD7mPy0xSdvT57s3aSd(pBYQBEx5mzl7tyIFjRNTlMCtAnnLgTCVgEUyYVqcWpvLwLDmWziRBkYhtDY3JVEDZTY9ooLeZth1PzuY15f5Za1C796tVqc0D752E)azsUGzu7CiEd6MWyeVBwl(CycWCr4lAX1YZkH4sxRX3TZugnrJADZz)iZP9TfhvE9S0M25v3SY2nSDwH)nni4(VWq(3xcc4tydaLPIs1T5MLkJRaf4MoDkOEumMuEiGAvAXxEtA9bxbzX3oCT6G7Kc4hqgNG6EUQrE)UqXDXxOE6zQ50(m)k8JDE6ewmIXiLLTNK2qcKNWrzdg5f1Sf4e1pUy)ZgJk2V90PcX)UyXairMmaHErGsEggT7Zdr9XX127LqjFQpPko)soyra)pLOAnyI0nhuvbisY7iFkmtRInSvV2H1fZ7WwPwpZnBrnju8QTc6AlXFpJ)39NahEvVNnQdtWsYad)BEQdGv5VwIvXq1WmQdTouIjAmbNGkr0cPRC(a9jiz4dahjHqeFk1icT8zQNknBzuAXGWI4JNYIOl5TiH96OesGUIWIsQavbjgPd0oCED6AQ4lUTk6TBT4MCbL50zqq3SgCw0oU3KZgolwx)(S0QDxCc(CTweBFeeR4nRy2tvP4O2zikEIuaREny12Sei0kGrJABTJYWONsibrYH5(SkFlzQDG73T0l3I0yJATTpBOH8uMpfQrjweQTsFx725hc6eWXRyIEnGFr09NFz(CgHoMvRAGmjuZEglkmaA1L2(DoKr(sKud9BDQeZhY4EGvIFlTCLDlqlTUFN9E9f0Pupy1QxXICvZsCbrBYKc872zE5B3H3eqdOag5V1dGjd7UoXdz9)QWMhsksonwUMEQYiNNvaL9KK1clW0218Q2X9qEf6JEd3ovV4h4XHwUMpAqtIwRBWssgTODfaONsM3XNvJVJs83W0feb5t6BN0ZTJiv0fQMxWuzgEcI64kb0uLVoBXl(kUIF2e5d5Ib7l74j5qgQiX2Ue2LnpogHwodGQKnX6Gl5Za0GI8cv6q5zW27Wa5SJ26TdwFzBAQsxTRGKQOcD8ycL4j(zPGpGSfWI7r5sYrr0dCN2wNp5ufD8APz8rqyYxyjePUwnvT3O7P7Lbd61qVeUygOqaU3xQFO5in7dBPc2lgNABBirR22X1jMQIeQP)OuLo6txRhLYodJTQqDSKVB5Ix0kD3nIF4Bbjl7rki73pvFDmM17XRkEi1XqLchrxtig94TpsR7Ut1ruBMbIAvse1C5UhY2OJxqeEPpAhg(TT5txbr2DYEBV6iJqhKx4KWWrlCsxXT25YPC)4zowjw0Y4utbw2lsO(sxujfRb0j5yINQIuYXph3nC)QydvEgr)e5P4K1NRjTWN6QIZ9IIP2I5q1ZqmGC78gID2vIxJX2txzA0ZjBKI3OpJQTPZmYTrHQNGtNOz8TBBgKbiPw0fjVx9Fe15r0oI6)iQlepEOoEEJvckv1t3u0HJ(zK4(2Q10OfcWCLOmfFWuLO4xVDUe0nzI6Mnw(uRyMpOHcIRR0hMdHnsPV0hu2CtnSqzIsIjMEI)MkGgfHBaTuJm8n1ZgQtQPB3eBtt3)UXVE0I7zGqPbUGgl8NgIMZitbjIMIH9qMFCAEIB3rzPihTOIJKdLM6noMnnRRglX7XQ8OgsL9BQrg2k(oA55QV(wI6yjMpwYtOOTuE)9ROOkXP6LQQ(C10wVujcbAs4CAxHfz5QzQCUwCwwmkz8AUosLxm5(mCDEmDN6RcU(K0H4vZzdSUsmPsgTNn1iR12wRCJP8HnmpCSh0BB9z0xOgDLx2udOTOubkJCHzdbQDXCSnhVkJHjllRBYLw2u3oYf2IKPa3arfNLSK4LauWLhsazqkSethBFsH2KUgqtB7jj6hT9JOmt7H594ieATX9PnQfeqs5T6YSs1u(LgDNLzaiI1FQkCz3YZSxM6qF2TYtAPXO3M40bRcA3byKU8jHMbLhg7LqsgYdStyt(CTu)vDMsCFyAjOVuK8woatee37rNddsyKk2asa4x9MRrnLYbve83oj0wr0bgSxH7uLlQ2uKr7Ybm69xO)M2bf4ore8IQzBeJBk3uWFXHYl(YTxmBfgyhVHBWBa32gvLRxMpFkFB6od3AgSHdKevZYv45e1vSM6syIHpkw1QuQ6Mrj3atGl3uDlpJ0sEFLE96v5xEl9OrG(Uj7I0f)Fuddn01znLfxTH2(ZSFToTyoLt0nzPRllUiRy(sAYaHlbckqdcTgHVItLdXzY)UeRpjEUV5W3YHRZMNNUQ(9LfVLVFsyM9ojqwUxcjiLT43zT)XuZdnomTAUytD2c1nVdyU0(iNatm17eu0Ok4v51q613(oABkD9TnGKKnc7EuuQj)SIeVGUPPZaGtNq5QT7IbMbxyYcQZ(okrrBFCtgJcB5ZsWi2UEc3O3Ch0AP1CReTIBULME4HliUhMoGTVDy7oOBfogwelLHBam3WGwh8q(F3fGKTXsfNLc0MLKHKL9n(zfaoQ7MvSX03KD6P7qgHHd90YUHIBVLWi3H33Mc8SgeCQz33TfVW1nEsKl8F4ov8Lk7IWWKPF4m6WrsSncLUeUpcTTcczpDGtCmUrczgUqohhk2RLeQTSD3j9DItZNI7QQ6VClZnAg8aBAMs7ZTMBORvvw8NzCVPQg0ExXOmK1lFOzjy08U86AUpHpdfJoIiRLjq1FmnvDmb5yvUIguLxtUU1ltxuEd05xpL(9lj3YzqpMv9LlOgI5wUi7RLxWGpX)v9Ta4rzddkHfq6sX9Y2nGQ76QFRiV5KkSSWFNC1GjlioBOYq0TBYyBdtEE4EjlHqfR2TKPS1vYrHTl)oT4moe73pDouSX2nsPs7dscWV4ubJokekerUOH)oaDkBRUZih0vojrzYyr7KFgWGlRA5AMmJ1teBcIlb7cFseJV3oCVDOrfC4ZcEMSloLbquDDkVhwVM19YpaRHIjSa0o5mUo4KHUDi(P0tsL)IxLmEJ(5IxW3noZz8t6jxezlqYfEAIUC2DTPp(bocfVyYJxvrHndd91jXHErJPNGdmljD5dtCvj4ZcmUGQeHObiMBN0jnLgACjpYODwx(UEd1hT7nE2f53yaPjVen9LtauCnovYaofJ(do(0)ofQxaWEHyzL5l65u2ATigJ5lY69UDaoJlYipmHwNEJaIALQOlT4V)KOqnZAMXYDyL0UkvstWmySmAAUZ(KXTEwFQWAm5nmEyJf2(MrKSm)w7775Z3f7NKVAv3iivyRX6B(yzINBSJTFODCqCCefMdd)ffG)xORNJDuap)JohAfHcT8icE2BhVYPDklLkVlVMF4LbtqsytKyBtljDttzB)XoBm7sg3Maemctz0aJPS68J)KQsDiuOfttq5Li4VZxsQ(LHivotiDkFDEmdkepx3lvGCoPg4QhELSVQhEPodWMU9RFxfv7S343OoCkNGb(mQRwqe26S6MOIHePQA2QTWwbLKK2TVGqcpZ(iUJgXrxyQPcABFe(3KKM0K9vIHD5ZAhI8QC9cI8CdLRWuiCb8vgXnoURg(7su3ozPIBLJLIl)VwsL6OBL2Cu(DzXGS7OKfZGGUGlDR0vPVJeY4U3Xs(qSR5WY93f9tbqWTtri5HhOmEPFGVqkDnKYYMHQM3wCgKC2Tdc(YgIstLOoxF5XsC7iNmFCCgyztNaVtpD)JZAletkczMBPAUeMx6ddbD1fICV4eogDcDXKJvHFfXEqePoryBy(o9f3PmqYqQNBPcZoNqdI)DioPq3092Wkzo1cM1fFErMu5xAJNRLZJeds53R5ECqTBrMXxW4thNn3UW(KGC0qKsYVuz826x(zblLriGA15f2ESm0EfU6i2G6O1y0IRE5enujuWk4Lu5fLQYEuGlhFxFhWejHsIkvYQIIlnDzgyOYsukG9gsvvCAhXGdyVqOKQcnE5aJw4HApNDiVqzwCSKZH0yNoKZplMcx273bh3tIAoZG7OIHIvX0al1tgJL6j)fXs1me()azL2Ze5VZesvCaC4y2)Lt00krYNvUWZ9yG6HJUDGbA32gtsOiW7ndnVVuu)XqkC)j(gX(uDiPsh)v9Yej5hqYkA4xZELqwEQXecuPxBKz69KH89MmXog3BaNJhxg0MzR8uqGEaVwjD5Jbv6TeIEVyjRJO9Erhwpn7(mBvlcP2YuSNCNnKsHgg0gOZoZqkE6PxAijx6LY4qE1YGwTGETS6DSBncjEJms3fAYJqY2aT8DJM8wZqMI4OjA9dI0CVKZODM(pxmK7LNq)CL35It(dGNmG8Mw9f2O(ecHT74qb1YmsZCJhXYz5qldn7q6y4PFXD4A3SMyEJ3DKR9e)ixxRih74yB(tgg4Hh)gXb(ErEST60GL)6o5vGHwgn)joEXrobquCNqElzhA5oXoi0kmW2MDOXORLSD4je0Lwa2KHE(aTax7yRy7W42Me4hmbUGxKfWHWutkVfeW5zyioJ88D8Sc5BzZVveheIDGNtONtSPPPCYkSrvOnorJDc9DS48AGrLtq0eq2dZ9ilFtTLT82(SvJ5Sfnwaxtp(iiGuL(X(W1nkxW1zhfmQZPiFhu84hybSZSCfZjRGa8qCbsFi2Xs)CcBspH)SszzSzMhI19LvwgiXTlOPcTlwEh)l4eb0kYesbqW3UB)1g43TvLTPtfMr4U6Ki3vMt1eceO4i1573luWULPG2v4WtTlEaljhT0T0C4Gz1LvZozqN(jbLddildy34jV1at7IPpmvJ(3kNDZ2iOhRo)5TOort75OLoyCJSWc7Tl6PCqhKfqOKWJ3FK0tx(6MwRw9r0mKFQmE7ErcBFwUu2XR0GKEhRu)JVAP9JKPLi34fnDipNDmk6Oo0JM4ZGfRUNMYA0ImyM4lUBLBo7zv4FhuHsrkF4RZ9(uXqTa8Akm4pVLauBgCMlw3y2oAQiNXySdRi32YuzBVRvTYK(FOpBld32wwxks3wkA2iH0mgMAS6uX3YlgRAKs1Hg71hIFWxULQeSJ5VowDAgGX0Vgko4bFk(YY82If4MpVuJ6Yu9L32oHHI7QpP1i1xrksZj29Zdb2mcxHsz1XpL7ipBYHBeRTNoC8Gwehgo8sw9ZuAXg4uPNV2ULR7GLKz)wNfJVblYw8B5nzbapWT)z3SAAjB7go9uvQTmjhMdfggrvJ1ArfZTBaPWP7)sOS7lzYqZqwRJBCEM70PJV(iMxmenzVmWJvjYv22xTd9jiyCHp6ViTMw3JDyjoM9OSjBmx8oJltq)kgD)kq)GDoG2QGVFf7UxAEpg1QEK6tQRWZJYb2W(5ylLd3qb83hQ5kHpvTJgR(0gxsgTBYd95V3BzmAl)Q(uWV)laLuTliOf9LXEK1CD357R8YTWcJ0wDZDBTJmvl(9PK3ZgUIarewpV46Da9da5AbFuxv7OELlqS0VMxPHhJAZOeMt5nhwF5lEaRS3wkBZGL0t)c0mCH((HSkW716GrryfhlSIxOaQI1t7YtCABHIN2vOxuhOuLuYKtUc1t5L1Hx8AfRrILH8R1f7ZmWH8du6WK1BQbDvFQWYKycS6k6zKBB2EtIdD5XOO2436Dq(AZ(EaCM0Qe4La9RROmV2qoIS3wfhR4GaS)2Vx2L4qq4gggez557ftzvbTFaV9d9MeAzzztN549A(TDICBB5zpbgv0jQU4WZ84VbcvUaKDQllMk(Hr0mjYXl0kCVNkorGXgmwda7n6CLHnvCKevUtqluiNARaV9U99ITNeggg5gg64f12(rI23ng0e4aiY12YFFpF0TJN4bpRxGh6(4328ItF9xe4ZMEwUrWnfVNNE8m3TWK3LMJwTIMmYhxmGy7GGylVW924bSDNeyB7y565J2EKNZXfZXVdaSyETJDUQ1noi2Mf5DV6iBqEJf(iYnWhFJUeYMWwvRD4e744yF4pSJI2pzZl8CyI7aOjVsAqddup2rkFCKvSZ2Th7z8h64pXY1fMWSdJ)7Wh)D5ZRkv6IWq23nG4a7iF39SlCcCrPsOJJTvqSlXr4JSxelzLmmocaPMf4fA3)y7F7Y(ql7jEr2HEEGkMwHMGKZYAK6bNi3joO0p0j03nEFL(H2talWah)4Wa)GwLR4ZaXlaaiMHVhGsrbw2JMhEu2QGX(Oda6bFXj8ob3Yl0f7TOeBzh)2VAdhV4QSbOXb8NtkzCpk4FlvvnpJCtsvhGoF9J7EQEnOnEqFLUghBl(a9s4bmCBV7(dBOL2u3(924vPnPySjSZvoy(5aI0L)pBsRyhRz8p9jRRk7DCPTTxduN2NHnqWP0JXH8TDBZoqugQikVxrAL(aO4pruIEE)1DGuilSFaH15FyjKdA7KWGhPx81Un)cls4zPlwirnKO0If4P7ewasMr5BdK8NBjmJd2NGfqUU1eM0KmG0etmPeti2tm473eNbj9zy6n5lwKvqjO39fvI168x08aXZVtdqPpeB8VZo6(QcrvvxQDvk1nnY(ilTjuaxZxBqHusnHBsCmWGdvcQ9iKdZ(K4M2cuwJlorFw9Btd0)7CLtYg6L7rQ1u(2MHFgE4FSEO0CKm(i9N8hxHi0CIbjioGv795AIxnqPERREK4R2macv(vitPUpwtbj4fQGHX7fnTdz1mFfE0cVSQCZvljKkYjO3xmv)(gtTqt2TEE2T(DItOltFyZGEPS7B0eQzwc)7)emfyFAkKMd0zQpEK2Y9q7lCd6U3J7(wv0XE(zh993r3((4MpWk))6CWL8lT5LIAGTxVptkA80FmCN1aPkkRIEaid(0g9pVpU7Q(0rTFn2oD)CO7bjns2Qd9e0Qqm4zB0axVTO55WqmunknL0GFgtA)XKUNKp(NfQ0l7b)O3FqhOKjOJhbWktCpEezAyap8jHaYq8QU8MFGo6ger)e4X37l72JUVE0Z(67vkg7UJ(qO69XfxgSXXOlVAaQ7Lh9iUUgC2)H7rh9ZPhTo6hp5ES2p7VUTyZMZyyh8t37qX3hC()7ZtwlC5DYlPZpF(Z3hn3tU)(ZrOFoc9FH(1dJqRSOQp7uFpDQJF2PElHX5VQypn(YJKv()e8P9t(0zTE0pOs9P3kZp5g2oRYJ2QC6REH6WAkUS7l5BDXOxo2uCGK5nF483(V)W7NEWVEQbNmIoF)DUXdCU)xszodFkGH5H32dy4FkYvIdM9mm7iWSrpey2Ntw6EbaBkzj5nK1FZWIu3Qx)nBW3BtK9Jgn9zsT)ZcT95mvp9jauDiRw5TT5pF(0)uWqY(zp2NRM8pF(YMjiDE26hhog)Djr17yBqy0HdFDPGF9GI8RPgyktlj2lVTpb7f(vAZhFEwD5Mkg7g6JVe(gaYfI(G5F6cCmP4lYK7hWMTk4pUj14BHA3RTizRjAJxxqVctDxr0gPS3dsYfXp5Y8vRoeU3qx2np4ZztKDe(scez7fhfA37TBy77G)yVGj4rgrGRRLp9bTrmNEnBe0QVCSKgDFU4f(4MBgShV6C29rVaISp3Ot7AJd5)MyoEybvJE5ppn0t(X14rFg7TYcBJU3pyvSlrdFU43BfYFMhcOP3XtboepafGSUI1460hNZ1hYnjPdWg4qU2GS4PtWl(ivwrHnsCa)zET0pq6wWOw0Dak6aJAxUGG37trvj7nuKEpePwcTB89j90vzfz0hc(iUHHia8y(owyiT(hIhQMDsQz8n2K1zRRaFPk2xuyyMVeE2LLRwOe2x(76eN1W8U9hVwhMs54b0bkr3bwG65HN85pXGO9w8pfw9owTS6gPNtQaPRqJbHlw)F9qUbHb3b2lCTy8lChySf6q)4EhtScK)VWx23)q5J10wm55wJAAZwdD)EZebutR5lDGx50DhNnN)DkMB3QP1h3Os2kV1v4LTgf9(if(1868z5RYBUfKNuKPHM3IJPJFGgCMTVuqZpPV9L0PM0oBEXrW3hlSavlSGFiwyw)D2cJaBFagzqSNmaDDXyaBbOi)qEiangD8F)aor8rr4CO31BU55OqCdiuOySHV6AHw(rroU(oXEId9lJgFbAS9cS9dIcCc98TIjIdSq4uOhvJsjZq3itMH2JB25LSoF9hmRHJWF)3LTF6zHjMR2Hb0lKkzPoeJes9RCE3Olkz(s814Mj28Wwog7Q3iXRryzB3PpFDrN5QsRGdLWq5RqcBhPHlEKiLNUc)CGszR2(lhHzbv4oInkCDy01(buSBejMC8E9qjv8a)cohAn(f9IU05re)Y7W)7))p" },
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

        ---------------------------------------------------------------
        --  Migration: clean up duplicate spec assignments
        --  An older version allowed multiple specs to be assigned to
        --  the same profile. The guardrails now prevent this in the UI,
        --  but existing corrupted data needs to be fixed. For each
        --  profile name, only the FIRST specID found is kept; the rest
        --  are unassigned so the user can reassign them properly.
        ---------------------------------------------------------------
        if db.specProfiles and next(db.specProfiles) then
            local profileToSpec = {}  -- profileName -> first specID seen
            local toRemove = {}
            for specID, pName in pairs(db.specProfiles) do
                if not profileToSpec[pName] then
                    profileToSpec[pName] = specID
                else
                    -- Duplicate: this spec also points to the same profile
                    toRemove[#toRemove + 1] = specID
                end
            end
            for _, specID in ipairs(toRemove) do
                db.specProfiles[specID] = nil
            end
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
