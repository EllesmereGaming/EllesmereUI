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
--  LibDeflate lookup
--
--  Release packages include `LibDeflate` via `.pkgmeta`, but depending on how
--  the addon is installed the library can be exposed either as `_G.LibDeflate`
--  or as a `LibStub` library. Resolve it lazily so export/import works in both
--  cases.
-------------------------------------------------------------------------------
local function GetLibDeflate()
    if _G.LibDeflate then
        return _G.LibDeflate
    end

    local libStub = _G.LibStub
    if libStub and libStub.GetLibrary then
        local ok, library = pcall(libStub.GetLibrary, libStub, "LibDeflate", true)
        if ok and library then
            return library
        end
    end

    return nil
end

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
local MAX_DESERIALIZE_DEPTH = 64

local function DeserializeValue(str, pos, depth)
    depth = depth or 0
    if depth > MAX_DESERIALIZE_DEPTH then
        return nil, pos, "max_depth_exceeded"
    end

    local tag = str:sub(pos, pos)
    if tag == "" then
        return nil, pos, "unexpected_end"
    end

    if tag == "s" then
        -- Strings carry an explicit byte length. Reject truncated payloads so a
        -- partial import cannot masquerade as valid profile data.
        local colonPos = str:find(":", pos + 1, true)
        if not colonPos then return nil, pos, "invalid_string" end
        local len = tonumber(str:sub(pos + 1, colonPos - 1))
        if not len then return nil, pos, "invalid_string" end

        local valueEnd = colonPos + len
        if valueEnd > #str then return nil, pos, "unexpected_end" end
        local val = str:sub(colonPos + 1, valueEnd)
        return val, valueEnd + 1, nil
    elseif tag == "n" then
        local semi = str:find(";", pos + 1, true)
        if not semi then return nil, pos, "invalid_number" end

        local value = tonumber(str:sub(pos + 1, semi - 1))
        if value == nil then return nil, pos, "invalid_number" end
        return value, semi + 1, nil
    elseif tag == "T" then
        return true, pos + 1, nil
    elseif tag == "F" then
        return false, pos + 1, nil
    elseif tag == "N" then
        return nil, pos + 1, nil
    elseif tag == "{" then
        local tbl = {}
        local idx = 1
        local p = pos + 1
        while p <= #str do
            local c = str:sub(p, p)
            if c == "}" then
                return tbl, p + 1, nil
            elseif c == "K" then
                -- Key-value pairs recurse into the same value parser so the
                -- table format stays compact, but each level carries a depth
                -- bound to keep malformed payloads from blowing the Lua stack.
                local key, val, err
                key, p, err = DeserializeValue(str, p + 1, depth + 1)
                if err then return nil, pos, err end
                val, p, err = DeserializeValue(str, p, depth + 1)
                if err then return nil, pos, err end
                if key ~= nil then
                    tbl[key] = val
                end
            else
                local val, err
                val, p, err = DeserializeValue(str, p, depth + 1)
                if err then return nil, pos, err end
                tbl[idx] = val
                idx = idx + 1
            end
        end
        return nil, pos, "unexpected_end"
    end

    return nil, pos, "invalid_tag"
end

function Serializer.Deserialize(str)
    if not str or #str == 0 then return nil end

    local val, nextPos, err = DeserializeValue(str, 1, 0)
    if err or nextPos ~= (#str + 1) then
        return nil
    end

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

local function DeepEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end

    if type(left) ~= "table" then
        return left == right
    end

    for key, leftValue in pairs(left) do
        if not DeepEqual(leftValue, right[key]) then
            return false
        end
    end

    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end

    return true
end

EllesmereUI._DeepCopy = DeepCopy

-------------------------------------------------------------------------------
--  Profile DB helpers
--  Profiles are stored in `EllesmereUIDB.profiles = { [name] = profileData }`.
--
--  This is a suite-snapshot system, not native per-addon AceDB switching.
--  Every named profile therefore needs two safeguards before we write it back
--  into live SavedVariables:
--    1. migrate older snapshots forward to the current schema
--    2. re-normalize each addon's data against today's defaults
--
--  That extra work is what keeps old exports usable after schema drift.
-------------------------------------------------------------------------------
local PROFILE_PAYLOAD_VERSION = 2
local PROFILE_SCHEMA_VERSION = 2
local RESERVED_PROFILE_NAME = "Custom"
local PROFILE_NAME_MAX_LENGTH = 60

local DEFAULT_FONT_SETTINGS = {
    global = "Expressway",
    outlineMode = "shadow",
}

local function GetProfilesDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.profiles then EllesmereUIDB.profiles = {} end
    if not EllesmereUIDB.profileOrder then EllesmereUIDB.profileOrder = {} end
    if not EllesmereUIDB.specProfiles then EllesmereUIDB.specProfiles = {} end
    return EllesmereUIDB
end

local function GetCurrentAddonVersion()
    return EllesmereUI.VERSION or "unknown"
end

local function GetCurrentTimestamp()
    if type(time) == "function" then
        return time()
    end
    return 0
end

local function TrimString(text)
    if type(text) ~= "string" then return nil end
    return text:match("^%s*(.-)%s*$")
end

local function NormalizeProfileName(name)
    local trimmed = TrimString(name)
    if not trimmed or trimmed == "" then return nil end
    return trimmed
end

local function IsReservedProfileName(name)
    return name == RESERVED_PROFILE_NAME
end

EllesmereUI.NormalizeProfileName = NormalizeProfileName
EllesmereUI.IsReservedProfileName = IsReservedProfileName
EllesmereUI.PROFILE_NAME_MAX_LENGTH = PROFILE_NAME_MAX_LENGTH
EllesmereUI.PROFILE_SCHEMA_VERSION = PROFILE_SCHEMA_VERSION
EllesmereUI.PROFILE_PAYLOAD_VERSION = PROFILE_PAYLOAD_VERSION

local function DeepMergeDefaults(dest, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(dest[key]) ~= "table" then
                dest[key] = {}
            end
            DeepMergeDefaults(dest[key], value)
        elseif dest[key] == nil then
            dest[key] = DeepCopy(value)
        end
    end
end

local function IsColorTable(value)
    return type(value) == "table"
        and type(value.r) == "number"
        and type(value.g) == "number"
        and type(value.b) == "number"
end

local function CopyColorTable(value)
    local copy = { r = value.r, g = value.g, b = value.b }
    if type(value.a) == "number" then
        copy.a = value.a
    end
    return copy
end

local function CopyNonInternalTable(src)
    if type(src) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(src) do
        if not (type(key) == "string" and key:match("^_")) then
            copy[key] = DeepCopy(value)
        end
    end
    return copy
end

local function CopyKnownFlatProfileTable(src, defaults)
    if type(src) ~= "table" then return nil end
    if type(defaults) ~= "table" then
        return CopyNonInternalTable(src)
    end

    local copy = {}
    for key, value in pairs(src) do
        if defaults[key] ~= nil
            and not (type(key) == "string" and key:match("^_")) then
            copy[key] = DeepCopy(value)
        end
    end
    return copy
end

local function IsKnownFontName(fontName)
    if type(fontName) ~= "string" then return false end
    return EllesmereUI.FONT_FILES[fontName] ~= nil
        or EllesmereUI.FONT_BLIZZARD[fontName] ~= nil
end

local function NormalizeFontsData(fontsData, preserveMissing)
    if fontsData == nil and preserveMissing then
        return nil
    end

    local normalized = DeepCopy(DEFAULT_FONT_SETTINGS)
    if type(fontsData) ~= "table" then
        return normalized
    end

    if IsKnownFontName(fontsData.global) then
        normalized.global = fontsData.global
    end

    -- The profile layer must accept every outline mode the runtime and options
    -- UI expose, including the legacy `none` alias and the current `thick`
    -- mode. Otherwise save/import would silently rewrite valid font settings.
    if EllesmereUI.FONT_OUTLINE_MODES and EllesmereUI.FONT_OUTLINE_MODES[fontsData.outlineMode] then
        normalized.outlineMode = fontsData.outlineMode
    end

    return normalized
end

local function NormalizeCustomColorsData(colorsData, preserveMissing)
    if colorsData == nil and preserveMissing then
        return nil
    end

    local normalized = {}
    if type(colorsData) ~= "table" then
        return normalized
    end

    local validMaps = {
        class = EllesmereUI.CLASS_COLOR_MAP or {},
        power = EllesmereUI.DEFAULT_POWER_COLORS or {},
        resource = EllesmereUI.DEFAULT_RESOURCE_COLORS or {},
    }

    for bucket, validKeys in pairs(validMaps) do
        local srcBucket = colorsData[bucket]
        if type(srcBucket) == "table" then
            for key in pairs(validKeys) do
                local color = srcBucket[key]
                if IsColorTable(color) then
                    normalized[bucket] = normalized[bucket] or {}
                    normalized[bucket][key] = CopyColorTable(color)
                end
            end
        end
    end

    return normalized
end

local function NormalizeProfileOrder(db)
    local seen = {}
    local ordered = {}

    for _, name in ipairs(db.profileOrder) do
        if type(name) == "string" and db.profiles[name] and not seen[name] then
            ordered[#ordered + 1] = name
            seen[name] = true
        end
    end

    for name in pairs(db.profiles) do
        if type(name) == "string" and not seen[name] then
            ordered[#ordered + 1] = name
            seen[name] = true
        end
    end

    db.profileOrder = ordered
end

local function RemoveProfileFromOrder(db, name)
    for i = #db.profileOrder, 1, -1 do
        if db.profileOrder[i] == name then
            table.remove(db.profileOrder, i)
        end
    end
end

local function EnsureProfileInOrder(db, name, moveToFront)
    RemoveProfileFromOrder(db, name)
    if moveToFront then
        table.insert(db.profileOrder, 1, name)
    else
        table.insert(db.profileOrder, name)
    end
end

local function RemoveSpecAssignmentsForProfile(db, name)
    for specID, profileName in pairs(db.specProfiles) do
        if profileName == name then
            db.specProfiles[specID] = nil
        end
    end
end

local function CanonicalizeSpecAssignmentKey(specID)
    local numericSpecID = tonumber(specID)
    if not numericSpecID then
        return specID
    end

    -- Preserve compatibility with assignments saved against older spec IDs.
    -- This lets existing characters recover automatically on the next login
    -- instead of forcing users to reassign specs by hand.
    local legacySpecAliases = {
        [1456] = 1480, -- Demon Hunter `Devourer`
    }
    if legacySpecAliases[numericSpecID] then
        return legacySpecAliases[numericSpecID]
    end

    -- Older test builds stored assignments as spec indexes (`1`, `2`, `3`)
    -- instead of stable spec IDs (`577`, `1467`, ...). Fold those legacy keys
    -- into the current class's spec IDs so existing assignments keep working.
    if numericSpecID >= 1 and numericSpecID <= 4 then
        local _, classToken = UnitClass("player")
        local specData = EllesmereUI and EllesmereUI._SPEC_DATA
        if classToken and type(specData) == "table" then
            for _, classInfo in ipairs(specData) do
                if classInfo.class == classToken and type(classInfo.specs) == "table" then
                    local specInfo = classInfo.specs[numericSpecID]
                    if specInfo and specInfo.id then
                        return specInfo.id
                    end
                    break
                end
            end
        end
    end

    return numericSpecID
end

local function NormalizeSpecProfileAssignments(db)
    local normalizedAssignments = {}
    if type(db.specProfiles) ~= "table" then
        db.specProfiles = normalizedAssignments
        return
    end

    for rawSpecID, profileName in pairs(db.specProfiles) do
        local normalizedSpecID = CanonicalizeSpecAssignmentKey(rawSpecID)
        if normalizedSpecID ~= nil and type(profileName) == "string" then
            normalizedAssignments[normalizedSpecID] = profileName
        end
    end

    db.specProfiles = normalizedAssignments
end

local function GetAssignedProfileForSpec(db, specID)
    local canonicalSpecID = CanonicalizeSpecAssignmentKey(specID)
    if canonicalSpecID == nil then
        return nil
    end

    return db.specProfiles[canonicalSpecID]
        or db.specProfiles[tostring(canonicalSpecID)]
end

local function GetCurrentSpecID()
    local specIdx = GetSpecialization and GetSpecialization() or 0
    if not (specIdx and specIdx > 0 and GetSpecializationInfo) then
        return nil
    end
    return CanonicalizeSpecAssignmentKey(GetSpecializationInfo(specIdx))
end

-- Keep raw invalid records around for recovery, but never let automatic
-- activation paths treat them as safe profile targets.
local invalidStoredProfiles = {}

local function MarkInvalidStoredProfile(name, err, code)
    if type(name) == "string" then
        invalidStoredProfiles[name] = {
            error = err,
            errorCode = code,
        }
    end
end

local function ClearInvalidStoredProfile(name)
    if type(name) == "string" then
        invalidStoredProfiles[name] = nil
    end
end

local function IsStoredProfileUsable(db, name)
    return type(name) == "string"
        and type(db.profiles[name]) == "table"
        and not invalidStoredProfiles[name]
end

local function ResolveStoredProfileName(db, preferredName, excludedName)
    if preferredName ~= excludedName and IsStoredProfileUsable(db, preferredName) then
        return preferredName
    end

    local seen = {}
    if RESERVED_PROFILE_NAME ~= excludedName then
        seen[RESERVED_PROFILE_NAME] = true
        if preferredName ~= RESERVED_PROFILE_NAME
            and IsStoredProfileUsable(db, RESERVED_PROFILE_NAME) then
            return RESERVED_PROFILE_NAME
        end
    end

    for _, name in ipairs(db.profileOrder) do
        if type(name) == "string" and not seen[name] then
            seen[name] = true
            if name ~= excludedName and IsStoredProfileUsable(db, name) then
                return name
            end
        end
    end

    for name in pairs(db.profiles) do
        if not seen[name] and name ~= excludedName and IsStoredProfileUsable(db, name) then
            return name
        end
    end

    return nil
end

local function ResolveActiveProfileName(db)
    db = db or GetProfilesDB()
    return ResolveStoredProfileName(db, db.activeProfile)
end

local function EnsureActiveProfileName(db)
    db = db or GetProfilesDB()
    db.activeProfile = ResolveActiveProfileName(db)
    return db.activeProfile
end

local function ClearManualProfileOverride()
    if EllesmereUIDB then
        EllesmereUIDB._manualProfileOverride = nil
    end
end

local function GetManualProfileOverride(db)
    if not EllesmereUIDB then
        return nil
    end

    local override = EllesmereUIDB._manualProfileOverride
    if type(override) ~= "table" then
        return nil
    end

    local profileName = NormalizeProfileName(override.profileName)
    local specID = CanonicalizeSpecAssignmentKey(override.specID)
    if not profileName or not specID then
        ClearManualProfileOverride()
        return nil
    end

    if db and not IsStoredProfileUsable(db, profileName) then
        ClearManualProfileOverride()
        return nil
    end

    override.profileName = profileName
    override.specID = specID
    return override
end

local function SetManualProfileOverride(profileName, specID)
    local normalizedName = NormalizeProfileName(profileName)
    local canonicalSpecID = CanonicalizeSpecAssignmentKey(specID)
    if not normalizedName or not canonicalSpecID then
        ClearManualProfileOverride()
        return
    end

    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB._manualProfileOverride = {
        profileName = normalizedName,
        specID = canonicalSpecID,
    }
end

local function UpdateManualProfileOverrideForCurrentSpec(db, profileName)
    local specID = GetCurrentSpecID()
    local assignedProfile = specID and GetAssignedProfileForSpec(db, specID) or nil

    -- The dropdown is an explicit "use this now" action. Keep it in front of
    -- the current spec's auto-assignment until the player actually changes
    -- specs, but do not create extra state when the chosen profile already
    -- matches the spec assignment.
    if specID and assignedProfile and assignedProfile ~= profileName then
        SetManualProfileOverride(profileName, specID)
    else
        ClearManualProfileOverride()
    end
end

local function ClearManualProfileOverrideIfSpecChanged(specID)
    local override = GetManualProfileOverride(GetProfilesDB())
    if override and specID and override.specID ~= specID then
        ClearManualProfileOverride()
    end
end

local function ChooseFallbackProfileName(db, deletedName)
    if deletedName ~= RESERVED_PROFILE_NAME and IsStoredProfileUsable(db, RESERVED_PROFILE_NAME) then
        return RESERVED_PROFILE_NAME
    end

    return ResolveStoredProfileName(db, db.activeProfile, deletedName)
end

local function ValidateProfileName(db, name, opts)
    opts = opts or {}

    local normalized = NormalizeProfileName(name)
    if not normalized then
        return nil, "Enter a profile name.", "invalid_profile_name"
    end

    if normalized:find("[%c]") then
        return nil, "Profile names cannot contain control characters.", "invalid_profile_name"
    end

    if #normalized > PROFILE_NAME_MAX_LENGTH then
        return nil, "Profile names must be " .. PROFILE_NAME_MAX_LENGTH .. " characters or fewer.", "profile_name_too_long"
    end

    if IsReservedProfileName(normalized)
        and normalized ~= opts.currentName
        and not opts.allowReserved then
        return nil,
            "\"" .. normalized .. "\" is reserved for the built-in fallback profile.",
            "reserved_profile_name"
    end

    local exists = db.profiles[normalized] ~= nil
    if exists and normalized ~= opts.currentName and not opts.allowOverwrite then
        return nil,
            "A profile named \"" .. normalized .. "\" already exists.",
            "profile_exists"
    end

    return normalized, nil, nil
end

--- Check if an addon is loaded.
local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    if _G.IsAddOnLoaded then return _G.IsAddOnLoaded(name) end
    return false
end

--- Get the live profile table for an addon.
local function GetAddonProfile(entry)
    if entry.isFlat then
        -- Flat DB (Nameplates): the global table is the live settings table.
        return _G[entry.svName]
    end

    local aceDB = entry.globalName and _G[entry.globalName]
    if aceDB and aceDB.profile then
        return aceDB.profile
    end

    -- Lite.NewDB addons do not always export a global handle, so we fall back to
    -- the active profile inside the raw SavedVariables table.
    local raw = _G[entry.svName]
    if raw and raw.profiles then
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

local function GetWritableAddonProfile(entry)
    if entry.isFlat then
        return _G[entry.svName]
    end

    local aceDB = entry.globalName and _G[entry.globalName]
    if aceDB and aceDB.profile then
        return aceDB.profile
    end

    local raw = _G[entry.svName]
    if type(raw) ~= "table" then
        return nil
    end

    local charKey = UnitName("player") .. " - " .. GetRealmName()
    if type(raw.profileKeys) ~= "table" then
        raw.profileKeys = {}
    end
    local profileName = raw.profileKeys[charKey] or "Default"
    raw.profileKeys[charKey] = profileName

    if type(raw.profiles) ~= "table" then
        raw.profiles = {}
    end
    if type(raw.profiles[profileName]) ~= "table" then
        raw.profiles[profileName] = {}
    end

    return raw.profiles[profileName]
end

local function GetAddonDefaults(entry)
    if entry.isFlat then
        local ns = _G.EllesmereNameplates_NS
        return ns and ns.defaults or nil
    end

    local lite = EllesmereUI and EllesmereUI.Lite
    if lite and lite.GetRegisteredDB then
        local registeredDB = lite.GetRegisteredDB(entry.svName)
        if registeredDB and registeredDB._profileDefaults then
            return registeredDB._profileDefaults
        end
    end

    local aceDB = entry.globalName and _G[entry.globalName]
    if aceDB and aceDB._profileDefaults then
        return aceDB._profileDefaults
    end

    return nil
end

local function BuildIncludedAddonFolderList(addonsData)
    local includedFolders = {}
    for _, entry in ipairs(ADDON_DB_MAP) do
        local folderName = entry.folder
        if type(addonsData[folderName]) == "table" then
            includedFolders[#includedFolders + 1] = folderName
        end
    end

    return includedFolders
end

local function BuildCurrentScopeDetails(folderFilterSet)
    local details = {
        includedFolders = {},
        includedDisplays = {},
        missingFolders = {},
        missingDisplays = {},
    }

    for _, entry in ipairs(ADDON_DB_MAP) do
        if not folderFilterSet or folderFilterSet[entry.folder] then
            if IsAddonLoaded(entry.folder) then
                details.includedFolders[#details.includedFolders + 1] = entry.folder
                details.includedDisplays[#details.includedDisplays + 1] = entry.display
            else
                details.missingFolders[#details.missingFolders + 1] = entry.folder
                details.missingDisplays[#details.missingDisplays + 1] = entry.display
            end
        end
    end

    return details
end

local function BuildCurrentScopeFolderList(folderFilterSet)
    return BuildCurrentScopeDetails(folderFilterSet).includedFolders
end

function EllesmereUI.GetCurrentProfileScopeDetails(folderList)
    local folderFilterSet
    if type(folderList) == "table" then
        folderFilterSet = {}
        for _, folderName in ipairs(folderList) do
            if type(folderName) == "string" then
                folderFilterSet[folderName] = true
            end
        end
    end

    return BuildCurrentScopeDetails(folderFilterSet)
end

function EllesmereUI.GetProfileAddonDisplayNames(folderList)
    local displayNames = {}
    if type(folderList) ~= "table" then
        return displayNames
    end

    local requestedSet = {}
    for _, folderName in ipairs(folderList) do
        if type(folderName) == "string" then
            requestedSet[folderName] = true
        end
    end

    for _, entry in ipairs(ADDON_DB_MAP) do
        if requestedSet[entry.folder] then
            displayNames[#displayNames + 1] = entry.display
        end
    end

    return displayNames
end

local function NormalizeAddonSnapshot(entry, snapshot)
    if type(snapshot) ~= "table" then return nil end

    local defaults = GetAddonDefaults(entry)
    local normalized = entry.isFlat
        and CopyKnownFlatProfileTable(snapshot, defaults)
        or DeepCopy(snapshot)
    if defaults then
        DeepMergeDefaults(normalized, defaults)
    end

    return normalized
end

local function MigrateProfileData(profileData)
    if type(profileData) ~= "table" then
        return nil, "Profile data is missing or corrupt.", "invalid_profile_data"
    end

    local migrated = DeepCopy(profileData)
    local schemaVersion = tonumber(migrated.schemaVersion) or 1
    schemaVersion = math.floor(schemaVersion)

    if schemaVersion > PROFILE_SCHEMA_VERSION then
        return nil,
            "This profile was saved by a newer version of EllesmereUI and cannot be loaded here.",
            "newer_schema_version"
    end

    while schemaVersion < PROFILE_SCHEMA_VERSION do
        if schemaVersion == 1 then
            -- Schema v1 was the original unversioned snapshot format. The data
            -- layout stays the same here; later normalization fills in the new
            -- metadata fields and re-merges current defaults.
            schemaVersion = 2
        else
            return nil,
                "Unsupported profile schema version.",
                "unsupported_schema_version"
        end
    end

    migrated.schemaVersion = schemaVersion
    return migrated, nil, nil
end

local function NormalizeProfileData(profileData, opts)
    opts = opts or {}

    if type(profileData) ~= "table" then
        return nil, "Profile data is missing or corrupt.", "invalid_profile_data"
    end

    local normalized = {
        schemaVersion = profileData.schemaVersion,
        createdFromAddonVersion = profileData.createdFromAddonVersion,
        updatedFromAddonVersion = profileData.updatedFromAddonVersion,
        createdAt = profileData.createdAt,
        updatedAt = profileData.updatedAt,
        addons = {},
        includedAddons = {},
        fonts = NormalizeFontsData(profileData.fonts, opts.preserveMissingSharedData),
        customColors = NormalizeCustomColorsData(profileData.customColors, opts.preserveMissingSharedData),
    }

    local addons = type(profileData.addons) == "table" and profileData.addons or {}
    for _, entry in ipairs(ADDON_DB_MAP) do
        local snapshot = addons[entry.folder]
        if type(snapshot) == "table" then
            normalized.addons[entry.folder] = NormalizeAddonSnapshot(entry, snapshot)
        end
    end

    normalized.includedAddons = BuildIncludedAddonFolderList(normalized.addons)

    return normalized, nil, nil
end

local function CoerceStoredProfileRecord(profileData)
    local migrated, err, code = MigrateProfileData(profileData)
    if not migrated then return nil, err, code end

    local normalized, normalizeErr, normalizeCode = NormalizeProfileData(migrated)
    if not normalized then return nil, normalizeErr, normalizeCode end

    local now = GetCurrentTimestamp()
    local currentVersion = GetCurrentAddonVersion()
    local previousSchemaVersion = tonumber(profileData and profileData.schemaVersion) or 1

    normalized.schemaVersion = PROFILE_SCHEMA_VERSION
    if type(normalized.createdFromAddonVersion) ~= "string"
        or normalized.createdFromAddonVersion == "" then
        normalized.createdFromAddonVersion = currentVersion
    end
    if type(normalized.createdAt) ~= "number" then
        normalized.createdAt = now
    end
    if type(normalized.updatedFromAddonVersion) ~= "string"
        or normalized.updatedFromAddonVersion == "" then
        normalized.updatedFromAddonVersion = normalized.createdFromAddonVersion
    end
    if type(normalized.updatedAt) ~= "number" then
        normalized.updatedAt = normalized.createdAt
    end

    if previousSchemaVersion < PROFILE_SCHEMA_VERSION then
        normalized.updatedFromAddonVersion = currentVersion
        normalized.updatedAt = now
    end

    return normalized, nil, nil
end

local function CanSkipLoginProfileNormalization(profileData)
    if type(profileData) ~= "table" then
        return false
    end

    -- Login only deep-normalizes records that are stale or structurally suspect.
    -- Profiles already stamped by this addon build keep their current tables so
    -- opening the game with many saved profiles does not allocate and copy each
    -- one before the player even uses it.
    local schemaVersion = tonumber(profileData.schemaVersion)
    if not schemaVersion or math.floor(schemaVersion) ~= PROFILE_SCHEMA_VERSION then
        return false
    end
    if type(profileData.updatedFromAddonVersion) ~= "string"
        or profileData.updatedFromAddonVersion == "" then
        return false
    end
    if type(profileData.createdFromAddonVersion) ~= "string"
        or profileData.createdFromAddonVersion == "" then
        return false
    end
    if type(profileData.createdAt) ~= "number"
        or type(profileData.updatedAt) ~= "number" then
        return false
    end
    if type(profileData.addons) ~= "table"
        or type(profileData.includedAddons) ~= "table" then
        return false
    end
    if profileData.fonts ~= nil and type(profileData.fonts) ~= "table" then
        return false
    end
    if profileData.customColors ~= nil and type(profileData.customColors) ~= "table" then
        return false
    end

    for _, entry in ipairs(ADDON_DB_MAP) do
        local snapshot = profileData.addons[entry.folder]
        if snapshot ~= nil and type(snapshot) ~= "table" then
            return false
        end
    end

    return true
end

local function StampStoredProfileRecord(profileData, existingProfile)
    local normalized, err, code = NormalizeProfileData(profileData)
    if not normalized then return nil, err, code end

    local now = GetCurrentTimestamp()
    local currentVersion = GetCurrentAddonVersion()

    normalized.schemaVersion = PROFILE_SCHEMA_VERSION
    normalized.createdFromAddonVersion = existingProfile
        and existingProfile.createdFromAddonVersion
        or normalized.createdFromAddonVersion
        or currentVersion
    normalized.createdAt = existingProfile
        and existingProfile.createdAt
        or normalized.createdAt
        or now
    normalized.updatedFromAddonVersion = currentVersion
    normalized.updatedAt = now

    return normalized, nil, nil
end

local function GetCurrentStoredProfileRecord(db)
    db = db or GetProfilesDB()
    local currentName = ResolveActiveProfileName(db)
    return currentName and db.profiles[currentName] or nil
end

local function GetPendingProfileSyncDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if type(EllesmereUIDB._pendingProfileAddonSync) ~= "table" then
        EllesmereUIDB._pendingProfileAddonSync = {}
    end
    return EllesmereUIDB._pendingProfileAddonSync
end

local function GetAddonEntryBySavedVariables(svName)
    for _, entry in ipairs(ADDON_DB_MAP) do
        if entry.svName == svName then
            return entry
        end
    end
    return nil
end

local function PreserveUnavailableAddonSnapshots(snapshotData, sourceProfileData)
    if type(snapshotData) ~= "table" or type(sourceProfileData) ~= "table" then
        return snapshotData
    end

    local sourceAddons = type(sourceProfileData.addons) == "table"
        and sourceProfileData.addons
        or nil
    if not sourceAddons then
        return snapshotData
    end

    for _, entry in ipairs(ADDON_DB_MAP) do
        if not snapshotData.addons[entry.folder]
            and not IsAddonLoaded(entry.folder)
            and type(sourceAddons[entry.folder]) == "table" then
            snapshotData.addons[entry.folder] = DeepCopy(sourceAddons[entry.folder])
        end
    end

    snapshotData.includedAddons = BuildIncludedAddonFolderList(snapshotData.addons)
    return snapshotData
end

local function SnapshotCurrentProfileData(folderFilterSet, sourceProfileData)
    local data = {
        addons = {},
        includedAddons = BuildCurrentScopeFolderList(folderFilterSet),
    }

    for _, entry in ipairs(ADDON_DB_MAP) do
        if (not folderFilterSet or folderFilterSet[entry.folder])
            and IsAddonLoaded(entry.folder) then
            local profile = GetAddonProfile(entry)
            if profile then
                data.addons[entry.folder] = entry.isFlat
                    and CopyKnownFlatProfileTable(profile, GetAddonDefaults(entry))
                    or DeepCopy(profile)
            end
        end
    end

    data.includedAddons = BuildIncludedAddonFolderList(data.addons)
    data.fonts = NormalizeFontsData(EllesmereUI.GetFontsDB())
    data.customColors = NormalizeCustomColorsData(EllesmereUI.GetCustomColorsDB())
    return PreserveUnavailableAddonSnapshots(data, sourceProfileData)
end

local function BuildComparableProfileContentFromNormalized(normalized)
    -- Dirty-state comparison should only look at user-controlled profile
    -- content. Metadata like timestamps and addon versions changes whenever we
    -- save, but those fields do not mean the visible settings actually drifted.
    return {
        addons = normalized.addons or {},
        includedAddons = normalized.includedAddons or {},
        fonts = normalized.fonts or NormalizeFontsData(nil),
        customColors = normalized.customColors or {},
    }, nil, nil
end

local function BuildComparableProfileContent(profileData)
    local normalized, err, code = NormalizeProfileData(profileData)
    if not normalized then
        return nil, err, code
    end

    return BuildComparableProfileContentFromNormalized(normalized)
end

local dirtyStateStoredComparableCache

local function GetStoredProfileComparableContent(profileName, storedProfile)
    local cache = dirtyStateStoredComparableCache
    if cache
        and cache.profileName == profileName
        and cache.storedProfile == storedProfile
        and cache.updatedAt == storedProfile.updatedAt then
        return cache.comparable, cache.normalized, cache.error, cache.errorCode
    end

    local normalizedStored, err, code = CoerceStoredProfileRecord(storedProfile)
    if not normalizedStored then
        dirtyStateStoredComparableCache = {
            profileName = profileName,
            storedProfile = storedProfile,
            updatedAt = storedProfile.updatedAt,
            error = err,
            errorCode = code,
        }
        return nil, nil, err, code
    end

    local comparable = BuildComparableProfileContentFromNormalized(normalizedStored)
    dirtyStateStoredComparableCache = {
        profileName = profileName,
        storedProfile = storedProfile,
        updatedAt = storedProfile.updatedAt,
        normalized = normalizedStored,
        comparable = comparable,
    }
    return comparable, normalizedStored, nil, nil
end

function EllesmereUI.GetActiveProfileDirtyState()
    local db = GetProfilesDB()
    local activeName = EllesmereUI.GetActiveProfileName()
    local storedProfile = GetCurrentStoredProfileRecord(db)
    if type(storedProfile) ~= "table" then
        return {
            profileName = activeName,
            isDirty = false,
            hasStoredProfile = false,
        }
    end

    local storedComparable, normalizedStored, storedErr, storedCode =
        GetStoredProfileComparableContent(activeName, storedProfile)
    if not storedComparable then
        return {
            profileName = activeName,
            isDirty = false,
            hasStoredProfile = true,
            comparisonFailed = true,
            error = storedErr,
            errorCode = storedCode,
        }
    end

    local currentSnapshot = SnapshotCurrentProfileData(nil, normalizedStored)
    local currentComparable, currentErr, currentCode = BuildComparableProfileContent(currentSnapshot)
    if not currentComparable then
        return {
            profileName = activeName,
            isDirty = false,
            hasStoredProfile = true,
            comparisonFailed = true,
            error = currentErr,
            errorCode = currentCode,
        }
    end

    return {
        profileName = activeName,
        isDirty = not DeepEqual(currentComparable, storedComparable),
        hasStoredProfile = true,
    }
end

function EllesmereUI.IsActiveProfileDirty()
    local state = EllesmereUI.GetActiveProfileDirtyState()
    return state and state.isDirty or false
end

local function FinalizeLiveSnapshot(snapshotData)
    local snapshot = StampStoredProfileRecord(snapshotData)
    if snapshot then
        return snapshot
    end

    -- Fall back to the raw snapshot shape rather than throwing a user-facing
    -- Lua error while exporting or auto-saving. The raw snapshot still carries
    -- the current scope; it just skips the metadata stamp.
    local fallback = DeepCopy(snapshotData)
    local now = GetCurrentTimestamp()
    local version = GetCurrentAddonVersion()
    fallback.schemaVersion = PROFILE_SCHEMA_VERSION
    fallback.createdFromAddonVersion = version
    fallback.updatedFromAddonVersion = version
    fallback.createdAt = now
    fallback.updatedAt = now
    return fallback
end

local function CanApplyProfileData()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false,
            "Profiles can only be switched, imported, or re-applied out of combat because EllesmereUI needs to reload.",
            "combat_lockdown"
    end
    return true, nil, nil
end

local function ApplyAddonSnapshot(entry, snapshot)
    if type(snapshot) ~= "table" then
        return false
    end

    local profile = GetWritableAddonProfile(entry)
    if not profile then
        return false
    end

    if entry.isFlat then
        local db = _G[entry.svName]
        if not db then
            return false
        end
        for key in pairs(db) do
            if not (type(key) == "string" and key:match("^_")) then
                db[key] = nil
            end
        end
        for key, value in pairs(snapshot) do
            if not (type(key) == "string" and key:match("^_")) then
                db[key] = DeepCopy(value)
            end
        end
        return true
    end

    for key in pairs(profile) do
        profile[key] = nil
    end
    for key, value in pairs(snapshot) do
        profile[key] = DeepCopy(value)
    end
    return true
end

function EllesmereUI.ApplyPendingProfileSync(svName)
    local entry = GetAddonEntryBySavedVariables(svName)
    if not entry then return false end

    local pendingSync = GetPendingProfileSyncDB()
    if not pendingSync[entry.folder] then return false end

    local currentProfile = GetCurrentStoredProfileRecord(GetProfilesDB())
    local normalized = currentProfile and CoerceStoredProfileRecord(currentProfile) or nil
    local snapshot = normalized and normalized.addons and normalized.addons[entry.folder] or nil

    pendingSync[entry.folder] = nil
    if not snapshot then
        return false
    end

    return ApplyAddonSnapshot(entry, snapshot)
end

local function ApplyFullProfileData(profileData)
    local pendingSync = GetPendingProfileSyncDB()

    for _, entry in ipairs(ADDON_DB_MAP) do
        local snapshot = profileData.addons[entry.folder]
        if snapshot then
            if ApplyAddonSnapshot(entry, snapshot) then
                pendingSync[entry.folder] = nil
            else
                pendingSync[entry.folder] = true
            end
        else
            pendingSync[entry.folder] = nil
        end
    end

    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for key in pairs(fontsDB) do
            fontsDB[key] = nil
        end
        for key, value in pairs(profileData.fonts) do
            fontsDB[key] = DeepCopy(value)
        end
    end

    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for key in pairs(colorsDB) do
            colorsDB[key] = nil
        end
        for key, value in pairs(profileData.customColors) do
            colorsDB[key] = DeepCopy(value)
        end
    end
end

local function ApplyPartialProfileData(profileData)
    local pendingSync = GetPendingProfileSyncDB()

    for folderName, snapshot in pairs(profileData.addons or {}) do
        for _, entry in ipairs(ADDON_DB_MAP) do
            if entry.folder == folderName then
                if ApplyAddonSnapshot(entry, snapshot) then
                    pendingSync[entry.folder] = nil
                else
                    pendingSync[entry.folder] = true
                end
                break
            end
        end
    end

    if profileData.fonts then
        local fontsDB = EllesmereUI.GetFontsDB()
        for key, value in pairs(profileData.fonts) do
            fontsDB[key] = DeepCopy(value)
        end
    end

    if profileData.customColors then
        local colorsDB = EllesmereUI.GetCustomColorsDB()
        for key, value in pairs(profileData.customColors) do
            colorsDB[key] = DeepCopy(value)
        end
    end
end

--- Snapshot the current state of all profiled addons into a versioned profile.
function EllesmereUI.SnapshotAllAddons()
    local db = GetProfilesDB()
    return FinalizeLiveSnapshot(SnapshotCurrentProfileData(nil, GetCurrentStoredProfileRecord(db)))
end

--- Snapshot a single addon's current profile table.
function EllesmereUI.SnapshotAddon(folderName)
    for _, entry in ipairs(ADDON_DB_MAP) do
        if entry.folder == folderName and IsAddonLoaded(folderName) then
            local profile = GetAddonProfile(entry)
            if profile then
                return entry.isFlat
                    and CopyKnownFlatProfileTable(profile, GetAddonDefaults(entry))
                    or DeepCopy(profile)
            end
        end
    end
    return nil
end

--- Snapshot multiple addons plus the shared font/color profile state.
function EllesmereUI.SnapshotAddons(folderList)
    local folderFilterSet = {}
    for _, folderName in ipairs(folderList) do
        folderFilterSet[folderName] = true
    end

    return FinalizeLiveSnapshot(SnapshotCurrentProfileData(folderFilterSet))
end

--- Apply a full profile to live SavedVariables.
function EllesmereUI.ApplyProfileData(profileData)
    local canApply, err, code = CanApplyProfileData()
    if not canApply then return false, err, code end

    local normalized, normalizeErr, normalizeCode = CoerceStoredProfileRecord(profileData)
    if not normalized then return false, normalizeErr, normalizeCode end

    ApplyFullProfileData(normalized)
    return true, normalized, nil
end

--- Apply a partial profile by merging only the supplied addon buckets.
function EllesmereUI.ApplyPartialProfile(profileData)
    local canApply, err, code = CanApplyProfileData()
    if not canApply then return false, err, code end

    local migrated, migrateErr, migrateCode = MigrateProfileData(profileData)
    if not migrated then return false, migrateErr, migrateCode end

    local normalized, normalizeErr, normalizeCode = NormalizeProfileData(
        migrated,
        { preserveMissingSharedData = true }
    )
    if not normalized then return false, normalizeErr, normalizeCode end

    ApplyPartialProfileData(normalized)
    return true, normalized, nil
end

-------------------------------------------------------------------------------
--  Export / Import
--
--  Preferred format: `!EUI_<base64 encoded compressed serialized data>`.
--  Fallback format:  `!EUIRAW_<serialized data>`.
--
--  The raw fallback keeps local/dev installs usable even when the packaged
--  `LibDeflate` external is missing, while the compressed format remains the
--  normal shipping path for short shareable strings.
-------------------------------------------------------------------------------
local EXPORT_PREFIX = "!EUI_"
local RAW_EXPORT_PREFIX = "!EUIRAW_"

local function EncodePayload(payload)
    local serialized = Serializer.Serialize(payload)
    local libDeflate = GetLibDeflate()
    if not libDeflate then
        return RAW_EXPORT_PREFIX .. serialized, nil, "raw_export_fallback"
    end

    local compressed = libDeflate:CompressDeflate(serialized)
    local encoded = libDeflate:EncodeForPrint(compressed)
    return EXPORT_PREFIX .. encoded, nil, nil
end

local function BuildPayload(payloadType, profileData)
    return {
        version = PROFILE_PAYLOAD_VERSION,
        type = payloadType,
        data = profileData,
    }
end

local function StoreProfileRecord(db, name, profileData, opts)
    opts = opts or {}

    local existingProfile = db.profiles[name]
    local stored, err, code = StampStoredProfileRecord(profileData, existingProfile)
    if not stored then return nil, err, code end

    db.profiles[name] = stored
    ClearInvalidStoredProfile(name)

    if existingProfile then
        if opts.moveToFront then
            EnsureProfileInOrder(db, name, true)
        else
            NormalizeProfileOrder(db)
        end
    else
        EnsureProfileInOrder(db, name, opts.moveToFront ~= false)
    end

    NormalizeProfileOrder(db)

    if opts.setActive ~= false then
        db.activeProfile = name
    end

    return stored, nil, nil, existingProfile ~= nil
end

local function BuildImportedProfileRecord(payload, existingProfile, sourceProfile)
    if payload.type == "full" then
        local imported, err, code = CoerceStoredProfileRecord(payload.data)
        if not imported then return nil, err, code end
        return StampStoredProfileRecord(imported, existingProfile)
    end

    if payload.type == "partial" then
        local migrated, err, code = MigrateProfileData(payload.data)
        if not migrated then return nil, err, code end

        local importedPartial, normalizeErr, normalizeCode = NormalizeProfileData(
            migrated,
            { preserveMissingSharedData = true }
        )
        if not importedPartial then
            return nil, normalizeErr, normalizeCode
        end

        local merged = SnapshotCurrentProfileData(nil, sourceProfile)
        for folderName, snapshot in pairs(importedPartial.addons or {}) do
            merged.addons[folderName] = snapshot
        end
        merged.includedAddons = BuildIncludedAddonFolderList(merged.addons)
        if importedPartial.fonts then
            merged.fonts = importedPartial.fonts
        end
        if importedPartial.customColors then
            merged.customColors = importedPartial.customColors
        end

        return StampStoredProfileRecord(merged, existingProfile)
    end

    return nil, "Unsupported profile type.", "unsupported_payload_type"
end

local function GetSpecDisplayName(specID)
    local canonicalSpecID = CanonicalizeSpecAssignmentKey(specID)
    if not canonicalSpecID then
        return nil
    end

    if GetSpecializationInfoByID then
        local _, specName = GetSpecializationInfoByID(canonicalSpecID)
        if type(specName) == "string" and specName ~= "" then
            return specName
        end
    end

    local specData = EllesmereUI and EllesmereUI._SPEC_DATA
    if type(specData) == "table" then
        for _, classInfo in ipairs(specData) do
            for _, specInfo in ipairs(classInfo.specs or {}) do
                if specInfo.id == canonicalSpecID then
                    return specInfo.name
                end
            end
        end
    end

    return nil
end

local function AnnounceLoadedProfile(name, opts)
    if opts and opts.announce == false then
        return
    end

    local message = "Loaded profile: " .. name .. "."
    if opts and opts.reason == "spec" then
        local specName = GetSpecDisplayName(opts.specID)
        if specName then
            message = "Loaded profile: " .. name .. " (" .. specName .. ")."
        end
    end

    print("|cff0CD29DEllesmereUI:|r " .. message)
end

local function ActivateStoredProfile(db, name, profileData, opts)
    opts = opts or {}

    if opts.saveCurrent ~= false then
        local currentName = ResolveActiveProfileName(db) or RESERVED_PROFILE_NAME
        if currentName ~= name and db.profiles[currentName] then
            EllesmereUI.AutoSaveActiveProfile()
        end
    end

    local ok, normalizedOrErr, code = EllesmereUI.ApplyProfileData(profileData)
    if not ok then
        return nil, normalizedOrErr, code
    end

    db.profiles[name] = normalizedOrErr
    ClearInvalidStoredProfile(name)
    db.activeProfile = name
    AnnounceLoadedProfile(name, opts)
    return normalizedOrErr, nil, nil
end

local function RunLiveProfileApplyHook(hookFn)
    if type(hookFn) ~= "function" then
        return
    end

    local errorHandler = geterrorhandler and geterrorhandler()
    if type(errorHandler) == "function" then
        xpcall(hookFn, errorHandler)
    else
        pcall(hookFn)
    end
end

local function RunLiveProfileApplyHooks()
    -- Reload-free spec switching only works when runtime modules re-read the DB
    -- values we just copied in. Each hook is isolated so one module's refresh
    -- error cannot abort the whole profile activation.
    RunLiveProfileApplyHook(_G._ECL_Apply)
    RunLiveProfileApplyHook(_G._ECL_ApplyGCDCircle)
    RunLiveProfileApplyHook(_G._ECL_ApplyCastCircle)
    RunLiveProfileApplyHook(_G._ECL_ApplyTrail)
    RunLiveProfileApplyHook(_G._ECL_UpdateVisibility)

    RunLiveProfileApplyHook(_G._ERB_Apply)
    RunLiveProfileApplyHook(_G._ECME_Apply)
    RunLiveProfileApplyHook(_G._EABR_RequestRefresh)
    RunLiveProfileApplyHook(_G._EAB_Apply)
    RunLiveProfileApplyHook(_G._EUF_Apply)

    local npNS = _G.EllesmereNameplates_NS
    if npNS and npNS.RefreshAllSettings then
        RunLiveProfileApplyHook(function()
            npNS.RefreshAllSettings()
        end)
    end

    if EllesmereUI and EllesmereUI.ApplyColorsToOUF then
        RunLiveProfileApplyHook(EllesmereUI.ApplyColorsToOUF)
    end
end

function EllesmereUI.ExportProfile(profileName)
    local db = GetProfilesDB()
    local normalizedName = NormalizeProfileName(profileName)
    if not normalizedName or not db.profiles[normalizedName] then
        return nil, "That profile does not exist.", "profile_missing"
    end

    local profileData, err, code = CoerceStoredProfileRecord(db.profiles[normalizedName])
    if not profileData then return nil, err, code end

    db.profiles[normalizedName] = profileData
    return EncodePayload(BuildPayload("full", profileData))
end

function EllesmereUI.ExportAddons(folderList)
    return EncodePayload(BuildPayload("partial", EllesmereUI.SnapshotAddons(folderList)))
end

function EllesmereUI.ExportCurrentProfile()
    return EncodePayload(BuildPayload("full", EllesmereUI.SnapshotAllAddons()))
end

function EllesmereUI.DecodeImportString(importStr)
    if not importStr or #importStr < #EXPORT_PREFIX then
        return nil, "Invalid string.", "invalid_import_string"
    end

    local payload
    if importStr:sub(1, #RAW_EXPORT_PREFIX) == RAW_EXPORT_PREFIX then
        payload = Serializer.Deserialize(importStr:sub(#RAW_EXPORT_PREFIX + 1))
        if not payload or type(payload) ~= "table" then
            return nil,
                "Failed to deserialize the raw profile data.",
                "deserialize_failed"
        end
    elseif importStr:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        local libDeflate = GetLibDeflate()
        if not libDeflate then
            return nil,
                "Compressed profile strings require LibDeflate, but the library is not loaded.",
                "missing_libdeflate"
        end

        local encoded = importStr:sub(#EXPORT_PREFIX + 1)
        local decoded = libDeflate:DecodeForPrint(encoded)
        if not decoded then
            return nil, "Failed to decode the profile string.", "decode_failed"
        end

        local decompressed = libDeflate:DecompressDeflate(decoded)
        if not decompressed then
            return nil, "Failed to decompress the profile data.", "decompress_failed"
        end

        payload = Serializer.Deserialize(decompressed)
        if not payload or type(payload) ~= "table" then
            return nil, "Failed to deserialize the profile data.", "deserialize_failed"
        end
    else
        return nil,
            "Not a valid EllesmereUI profile string.",
            "invalid_import_string"
    end

    local payloadVersion = tonumber(payload.version)
    if not payloadVersion then
        return nil,
            "The profile string is missing a payload version.",
            "unsupported_payload_version"
    end
    if payloadVersion > PROFILE_PAYLOAD_VERSION then
        return nil,
            "This profile string was exported by a newer version of EllesmereUI.",
            "newer_payload_version"
    end
    if payloadVersion < 1 then
        return nil,
            "Unsupported profile payload version.",
            "unsupported_payload_version"
    end
    if payload.type ~= "full" and payload.type ~= "partial" then
        return nil, "Unsupported profile type.", "unsupported_payload_type"
    end
    if type(payload.data) ~= "table" then
        return nil,
            "The profile string does not contain any settings data.",
            "invalid_payload_data"
    end

    return payload, nil, nil
end

--- Import a profile string. Returns `ok, resultOrError, errorCode`.
function EllesmereUI.ImportProfile(importStr, profileName, opts)
    opts = opts or {}

    local payload, err, code = EllesmereUI.DecodeImportString(importStr)
    if not payload then return false, err, code end

    local db = GetProfilesDB()
    local normalizedName, nameErr, nameCode = ValidateProfileName(db, profileName, {
        allowOverwrite = opts.allowOverwrite,
    })
    if not normalizedName then return false, nameErr, nameCode end

    local canApply, applyErr, applyCode = CanApplyProfileData()
    if not canApply then return false, applyErr, applyCode end

    local existingProfile = db.profiles[normalizedName]
    local importedProfile, importErr, importCode = BuildImportedProfileRecord(
        payload,
        existingProfile,
        GetCurrentStoredProfileRecord(db)
    )
    if not importedProfile then return false, importErr, importCode end

    db.profiles[normalizedName] = importedProfile
    ClearInvalidStoredProfile(normalizedName)
    if existingProfile then
        if opts.moveToFront then
            EnsureProfileInOrder(db, normalizedName, true)
        else
            NormalizeProfileOrder(db)
        end
    else
        EnsureProfileInOrder(db, normalizedName, true)
    end
    NormalizeProfileOrder(db)

    local activatedProfile, activateErr, activateCode = ActivateStoredProfile(
        db,
        normalizedName,
        importedProfile,
        {
            saveCurrent = opts.saveCurrent,
            reason = "manual",
        }
    )
    if not activatedProfile then return false, activateErr, activateCode end

    UpdateManualProfileOverrideForCurrentSpec(db, normalizedName)

    return true, {
        profileName = normalizedName,
        importType = payload.type,
        overwritten = existingProfile ~= nil,
        requiresReload = true,
    }, nil
end

-------------------------------------------------------------------------------
--  Profile management
-------------------------------------------------------------------------------
function EllesmereUI.SaveCurrentAsProfile(name, opts)
    opts = opts or {}

    local db = GetProfilesDB()
    local normalizedName, err, code = ValidateProfileName(db, name, {
        currentName = opts.currentName,
        allowOverwrite = opts.allowOverwrite,
        allowReserved = opts.allowReserved,
    })
    if not normalizedName then return false, err, code end

    local stored, storeErr, storeCode, overwritten = StoreProfileRecord(
        db,
        normalizedName,
        SnapshotCurrentProfileData(nil, GetCurrentStoredProfileRecord(db)),
        {
            moveToFront = opts.moveToFront,
            setActive = opts.setActive,
        }
    )
    if not stored then return false, storeErr, storeCode end

    return true, {
        profileName = normalizedName,
        overwritten = overwritten,
    }, nil
end

function EllesmereUI.DeleteProfile(name)
    local db = GetProfilesDB()
    local normalizedName = NormalizeProfileName(name)
    if not normalizedName or not db.profiles[normalizedName] then
        return false, "That profile does not exist.", "profile_missing"
    end
    if IsReservedProfileName(normalizedName) then
        return false,
            "The built-in Custom profile cannot be deleted.",
            "reserved_profile_name"
    end

    local deletingActiveProfile = (ResolveActiveProfileName(db) == normalizedName)
    local fallbackName

    if deletingActiveProfile then
        local canApply, applyErr, applyCode = CanApplyProfileData()
        if not canApply then return false, applyErr, applyCode end

        fallbackName = ChooseFallbackProfileName(db, normalizedName)
        if not fallbackName or not IsStoredProfileUsable(db, fallbackName) then
            return false,
                "No fallback profile is available.",
                "missing_fallback_profile"
        end

        local activatedProfile, activateErr, activateCode = ActivateStoredProfile(
            db,
            fallbackName,
            db.profiles[fallbackName],
            { saveCurrent = false }
        )
        if not activatedProfile then return false, activateErr, activateCode end
    end

    db.profiles[normalizedName] = nil
    ClearInvalidStoredProfile(normalizedName)
    RemoveProfileFromOrder(db, normalizedName)
    RemoveSpecAssignmentsForProfile(db, normalizedName)
    NormalizeProfileOrder(db)

    if db.activeProfile == normalizedName then
        EnsureActiveProfileName(db)
    end

    return true, {
        deletedProfile = normalizedName,
        activeProfile = db.activeProfile,
        fallbackProfile = deletingActiveProfile and fallbackName or nil,
        requiresReload = deletingActiveProfile,
    }, nil
end

function EllesmereUI.RenameProfile(oldName, newName, opts)
    opts = opts or {}

    local db = GetProfilesDB()
    local normalizedOldName = NormalizeProfileName(oldName)
    if not normalizedOldName or not db.profiles[normalizedOldName] then
        return false, "That profile does not exist.", "profile_missing"
    end
    if IsReservedProfileName(normalizedOldName) then
        return false,
            "The built-in Custom profile cannot be renamed.",
            "reserved_profile_name"
    end

    local normalizedNewName, err, code = ValidateProfileName(db, newName, {
        currentName = normalizedOldName,
        allowOverwrite = opts.allowOverwrite,
    })
    if not normalizedNewName then return false, err, code end

    if normalizedNewName == normalizedOldName then
        return true, {
            profileName = normalizedOldName,
            overwritten = false,
            noOp = true,
        }, nil
    end

    local oldInvalidState = invalidStoredProfiles[normalizedOldName]
    local overwritingProfile = db.profiles[normalizedNewName]
    local activeProfileName = ResolveActiveProfileName(db)
    if overwritingProfile
        and activeProfileName == normalizedNewName
        and activeProfileName ~= normalizedOldName then
        return false,
            "Rename would overwrite the active profile. Switch away from it first.",
            "profile_exists_active"
    end

    if overwritingProfile then
        db.profiles[normalizedNewName] = nil
        ClearInvalidStoredProfile(normalizedNewName)
        RemoveProfileFromOrder(db, normalizedNewName)
        RemoveSpecAssignmentsForProfile(db, normalizedNewName)
    end

    db.profiles[normalizedNewName] = db.profiles[normalizedOldName]
    db.profiles[normalizedOldName] = nil
    ClearInvalidStoredProfile(normalizedOldName)
    if oldInvalidState then
        invalidStoredProfiles[normalizedNewName] = oldInvalidState
    end

    local replacedInOrder = false
    for i, orderedName in ipairs(db.profileOrder) do
        if orderedName == normalizedOldName then
            db.profileOrder[i] = normalizedNewName
            replacedInOrder = true
            break
        end
    end
    if not replacedInOrder then
        EnsureProfileInOrder(db, normalizedNewName, false)
    end

    for specID, profileName in pairs(db.specProfiles) do
        if profileName == normalizedOldName then
            db.specProfiles[specID] = normalizedNewName
        end
    end
    if db.activeProfile == normalizedOldName then
        db.activeProfile = normalizedNewName
    end

    NormalizeProfileOrder(db)

    return true, {
        profileName = normalizedNewName,
        overwritten = overwritingProfile ~= nil,
    }, nil
end

function EllesmereUI.SwitchProfile(name, opts)
    opts = opts or {}

    local db = GetProfilesDB()
    local normalizedName = NormalizeProfileName(name)
    if not normalizedName or not db.profiles[normalizedName] then
        return false, "That profile does not exist.", "profile_missing"
    end
    if not IsStoredProfileUsable(db, normalizedName) then
        return false,
            "That profile is unavailable because its saved data is corrupt.",
            "profile_invalid"
    end

    local requiresReload = opts.requiresReload ~= false
    if ResolveActiveProfileName(db) == normalizedName then
        return true, {
            profileName = normalizedName,
            requiresReload = false,
            noOp = true,
        }, nil
    end

    local activatedProfile, err, code = ActivateStoredProfile(
        db,
        normalizedName,
        db.profiles[normalizedName],
        {
            saveCurrent = opts.saveCurrent,
            announce = opts.announce,
            reason = opts.reason,
            specID = opts.specID,
        }
    )
    if not activatedProfile then return false, err, code end

    if opts.reason == "manual" then
        UpdateManualProfileOverrideForCurrentSpec(db, normalizedName)
    end

    if not requiresReload then
        RunLiveProfileApplyHooks()
    end

    return true, {
        profileName = normalizedName,
        requiresReload = requiresReload,
    }, nil
end

function EllesmereUI.GetActiveProfileName()
    return ResolveActiveProfileName(GetProfilesDB())
end

function EllesmereUI.IsProfileUsable(name)
    return IsStoredProfileUsable(GetProfilesDB(), NormalizeProfileName(name))
end

function EllesmereUI.GetProfileList()
    local db = GetProfilesDB()
    NormalizeProfileOrder(db)
    return db.profileOrder, db.profiles
end

function EllesmereUI.AssignProfileToSpec(profileName, specID)
    local db = GetProfilesDB()
    db.specProfiles[CanonicalizeSpecAssignmentKey(specID)] = profileName
end

function EllesmereUI.UnassignSpec(specID)
    local db = GetProfilesDB()
    db.specProfiles[CanonicalizeSpecAssignmentKey(specID)] = nil
end

function EllesmereUI.GetSpecProfile(specID)
    local db = GetProfilesDB()
    return GetAssignedProfileForSpec(db, specID)
end

-------------------------------------------------------------------------------
--  Auto-save active profile on setting changes
--  Called by addons after any setting change to keep the active profile
--  in sync with live settings.
-------------------------------------------------------------------------------
function EllesmereUI.AutoSaveActiveProfile()
    local db = GetProfilesDB()
    local name = ResolveActiveProfileName(db) or RESERVED_PROFILE_NAME

    local ok, resultOrErr, code = EllesmereUI.SaveCurrentAsProfile(name, {
        currentName = name,
        allowOverwrite = true,
        allowReserved = true,
        setActive = false,
        moveToFront = false,
    })
    if ok then
        db.activeProfile = name
    end
    return ok, resultOrErr, code
end

function EllesmereUI.RevertActiveProfile()
    local db = GetProfilesDB()
    local activeName = EllesmereUI.GetActiveProfileName()
    local storedProfile = GetCurrentStoredProfileRecord(db)
    if type(storedProfile) ~= "table" then
        return false, "That profile does not exist.", "profile_missing"
    end

    local canApply, applyErr, applyCode = CanApplyProfileData()
    if not canApply then return false, applyErr, applyCode end

    local ok, normalizedOrErr, code = EllesmereUI.ApplyProfileData(storedProfile)
    if not ok then
        return false, normalizedOrErr, code
    end

    db.profiles[activeName] = normalizedOrErr
    ClearInvalidStoredProfile(activeName)
    db.activeProfile = activeName
    AnnounceLoadedProfile(activeName, { reason = "manual" })

    return true, {
        profileName = activeName,
        requiresReload = true,
    }, nil
end

-------------------------------------------------------------------------------
--  Spec auto-switch handler
-------------------------------------------------------------------------------
-- Spec data is not always settled on the same frame as the login/spec-change
-- event that announces it. Queue a few follow-up checks so the assigned
-- profile follows the final active spec.
--
-- Manual dropdown switches have different UX: they are a direct user choice,
-- so we keep them in front of the current spec's auto-assignment until the
-- player actually changes specs. That avoids the frustrating "I picked a
-- profile and the addon immediately took it back" loop after the forced reload.
local function RefreshVisibleProfilesUI()
    if EllesmereUI._mainFrame
        and EllesmereUI._mainFrame:IsShown() then
        EllesmereUI:InvalidatePageCache()
        EllesmereUI:RefreshPage(true)
    end
end

local function ApplyAssignedProfileForCurrentSpec(opts)
    opts = opts or {}

    local specID = CanonicalizeSpecAssignmentKey(opts.specID or GetCurrentSpecID())
    if not specID then return false end

    ClearManualProfileOverrideIfSpecChanged(specID)

    local db = GetProfilesDB()
    local manualOverride = GetManualProfileOverride(db)
    if manualOverride and manualOverride.specID == specID then
        return true
    end

    local targetProfile = GetAssignedProfileForSpec(db, specID)
    if not (targetProfile and IsStoredProfileUsable(db, targetProfile)) then
        return false
    end

    local currentProfile = ResolveActiveProfileName(db)
    if currentProfile == targetProfile then
        return true
    end

    local ok = EllesmereUI.SwitchProfile(targetProfile, {
        requiresReload = false,
        reason = opts.reason or "spec",
        specID = specID,
    })
    if not ok then
        return false
    end

    RefreshVisibleProfilesUI()
    return true
end

local function QueueAssignedProfileApply(reason)
    local generation = (EllesmereUI._specProfileApplyGeneration or 0) + 1
    EllesmereUI._specProfileApplyGeneration = generation

    -- Spec data often settles a little after the triggering event. Retry in a
    -- short sequence, but only schedule the next follow-up when the previous
    -- attempt still could not find/apply the assigned profile.
    local absoluteRetryDelays = { 0, 0.1, 0.35, 0.75 }
    local function QueueRetry(index)
        local absoluteDelay = absoluteRetryDelays[index]
        if not absoluteDelay then
            return
        end

        local previousDelay = absoluteRetryDelays[index - 1] or 0
        local delay = absoluteDelay - previousDelay
        C_Timer.After(delay, function()
            if EllesmereUI._specProfileApplyGeneration ~= generation then
                return
            end
            if ApplyAssignedProfileForCurrentSpec({ reason = reason or "spec" }) then
                return
            end
            QueueRetry(index + 1)
        end)
    end

    QueueRetry(1)
end

do
    local specFrame = CreateFrame("Frame")
    specFrame:RegisterEvent("PLAYER_LOGIN")
    specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    specFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
            return
        end

        QueueAssignedProfileApply("spec")
    end)
end

-------------------------------------------------------------------------------
--  Popular Presets & Weekly Spotlight
--  Hardcoded profile strings that ship with the addon.
--  To add a new preset: add an entry to POPULAR_PRESETS with name + string.
--  To update the weekly spotlight: change WEEKLY_SPOTLIGHT.
-------------------------------------------------------------------------------
EllesmereUI.POPULAR_PRESETS = {
    -- { name = "Preset Name", description = "Short description", exportString = "!EUI_..." },
    -- EllesmereUI default is handled specially (applies defaults, no string needed)
    { name = "EllesmereUI", description = "The default EllesmereUI look", exportString = nil },
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
--  Randomizes all addon settings except X/Y offsets and Scale.
--  Party Mode is hard-set to enabled.
-------------------------------------------------------------------------------
function EllesmereUI.SpinTheWheel()
    local function rColor()
        return { r = math.random(), g = math.random(), b = math.random() }
    end
    local function rBool() return math.random() > 0.5 end
    local function pick(t) return t[math.random(#t)] end
    local function rRange(lo, hi) return lo + math.random() * (hi - lo) end
    local floor = math.floor

    -- Party Mode: hard-set to enabled
    if EllesmereUIDB then
        EllesmereUIDB.partyMode = true
    end

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
    local outlineModes = EllesmereUI.FONT_OUTLINE_MODE_ORDER or { "shadow", "outline", "thick" }
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
--- "pos", "Pos", "position", "Position", "anchor", "Anchor" (position-related).
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

    local function RandomizeTable(tbl, depth)
        if depth > 5 then return end  -- safety limit
        for k, v in pairs(tbl) do
            if type(k) == "string" and IsPositionKey(k) then
                -- Skip position/scale keys
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

    RandomizeTable(profile, 0)
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
--  Also handles _pendingPresetReset for the "EllesmereUI (Default)" button.
-------------------------------------------------------------------------------
do
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")

        -- Handle pending preset reset (EllesmereUI Default button)
        -- This wipes all addon SVs so they re-init with built-in defaults,
        -- then reloads once more.
        if EllesmereUIDB and EllesmereUIDB._pendingPresetReset == "ellesmereui" then
            EllesmereUIDB._pendingPresetReset = nil
            -- Wipe each addon's saved variables so they re-init with defaults
            for _, entry in ipairs(ADDON_DB_MAP) do
                local sv = _G[entry.svName]
                if sv then
                    if entry.isFlat then
                        -- Flat DB: wipe all non-internal keys
                        for k in pairs(sv) do
                            if type(k) == "string" and not k:match("^_") then
                                sv[k] = nil
                            end
                        end
                    else
                        -- AceDB: wipe the profiles table so it re-creates Default
                        if sv.profiles then
                            sv.profiles = nil
                        end
                    end
                end
            end
            -- Reset fonts and colors to defaults
            if EllesmereUIDB.fonts then
                EllesmereUIDB.fonts = nil
            end
            if EllesmereUIDB.customColors then
                EllesmereUIDB.customColors = nil
            end
            -- Keep profile metadata but update the active profile snapshot after reload
            EllesmereUIDB._pendingDefaultSnapshot = true
            C_Timer.After(0, function() ReloadUI() end)
            return
        end

        -- After a default reset reload, snapshot the fresh defaults as the
        -- active profile so the fallback record keeps a versioned baseline.
        if EllesmereUIDB and EllesmereUIDB._pendingDefaultSnapshot then
            EllesmereUIDB._pendingDefaultSnapshot = nil
            C_Timer.After(0.5, function()
                local db = GetProfilesDB()
                local name = db.activeProfile or RESERVED_PROFILE_NAME
                EllesmereUI.SaveCurrentAsProfile(name, {
                    currentName = name,
                    allowOverwrite = true,
                    allowReserved = true,
                    setActive = false,
                    moveToFront = false,
                })
            end)
        end

        local db = GetProfilesDB()

        -- Repair stored profiles that are stale or structurally suspect before
        -- the player interacts with them. Fully current records skip the deep
        -- copy/normalize pass here and are still normalized again on-demand by
        -- apply/export/dirty-check code paths.
        local invalidProfileNames = {}
        for profileName, profileData in pairs(db.profiles) do
            if CanSkipLoginProfileNormalization(profileData) then
                ClearInvalidStoredProfile(profileName)
            else
                local normalizedProfile, err, code = CoerceStoredProfileRecord(profileData)
                if normalizedProfile then
                    db.profiles[profileName] = normalizedProfile
                    ClearInvalidStoredProfile(profileName)
                else
                    MarkInvalidStoredProfile(profileName, err, code)
                    invalidProfileNames[#invalidProfileNames + 1] = profileName
                end
            end
        end
        if #invalidProfileNames > 0 then
            table.sort(invalidProfileNames)
            print(
                "|cff0CD29DEllesmereUI:|r Some saved profiles are unavailable because their data is corrupt: "
                    .. table.concat(invalidProfileNames, ", ")
                    .. "."
            )
        end
        NormalizeSpecProfileAssignments(db)

        -- On first install, create the built-in fallback profile from the
        -- current settings after the addons finish their DB initialization.
        if not db.profiles[RESERVED_PROFILE_NAME] then
            C_Timer.After(0.5, function()
                EllesmereUI.SaveCurrentAsProfile(RESERVED_PROFILE_NAME, {
                    currentName = RESERVED_PROFILE_NAME,
                    allowOverwrite = true,
                    allowReserved = true,
                    setActive = false,
                    moveToFront = false,
                })
            end)
        end

        NormalizeProfileOrder(db)
        EnsureActiveProfileName(db)

        -- Auto-save active profile when the settings panel closes
        C_Timer.After(1, function()
            if EllesmereUI._mainFrame and not EllesmereUI._profileAutoSaveHooked then
                EllesmereUI._profileAutoSaveHooked = true
                EllesmereUI._mainFrame:HookScript("OnHide", function()
                    EllesmereUI.AutoSaveActiveProfile()
                end)
            end
        end)
    end)
end

-------------------------------------------------------------------------------
--  Shared profile-string text box
--
--  Export strings can be a single uninterrupted token, especially when we fall
--  back to the raw serializer in local/dev installs. Wrapping the EditBox in a
--  clipped container keeps that long string visually contained to the text area
--  instead of painting across the rest of the popup.
-------------------------------------------------------------------------------
local function CreateProfileStringBox(parent, font, opts)
    opts = opts or {}

    local PP = EllesmereUI.PanelPP
    local box = CreateFrame("Frame", nil, parent)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -70)
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, 60)
    box:SetFrameLevel(parent:GetFrameLevel() + 1)
    box:EnableMouse(true)
    box:SetClipsChildren(true)

    local boxBg = box:CreateTexture(nil, "BACKGROUND")
    boxBg:SetAllPoints()
    boxBg:SetColorTexture(0.03, 0.05, 0.07, 0.95)
    EllesmereUI.MakeBorder(box, 1, 1, 1, 0.12, PP)

    local editBox = CreateFrame("EditBox", nil, box)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(font, 11, EllesmereUI.GetFontOutlineFlag())
    editBox:SetTextColor(1, 1, 1, 0.75)
    editBox:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
    editBox:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -10, 8)
    editBox:SetText(opts.initialText or "")

    local function FocusBox(selectAll)
        C_Timer.After(0, function()
            editBox:SetFocus()
            if selectAll then
                editBox:HighlightText()
            end
        end)
    end

    if opts.readOnly then
        editBox._readOnlyText = opts.initialText or ""
        editBox:SetScript("OnChar", function(self)
            if self._readOnlyText then
                self:SetText(self._readOnlyText)
                self:HighlightText()
            end
        end)
        editBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput and self._readOnlyText then
                self:SetText(self._readOnlyText)
                self:HighlightText()
            end
        end)
        editBox:SetScript("OnMouseUp", function()
            FocusBox(true)
        end)
        box:SetScript("OnMouseUp", function()
            FocusBox(true)
        end)
    else
        editBox:SetScript("OnMouseUp", function()
            FocusBox(false)
        end)
        box:SetScript("OnMouseUp", function()
            FocusBox(false)
        end)
    end

    return box, editBox
end

-------------------------------------------------------------------------------
--  Export Popup: shows a read-only text box with the export string
-------------------------------------------------------------------------------
function EllesmereUI:ShowExportPopup(exportStr)
    local POPUP_W, POPUP_H = 520, 260
    local FONT = EllesmereUI.EXPRESSWAY
    local EG = EllesmereUI.ELLESMERE_GREEN
    local PP = EllesmereUI.PanelPP

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
    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, PP)

    -- Title
    local title = EllesmereUI.MakeFont(popup, 18, nil, 1, 1, 1)
    title:SetPoint("TOP", popup, "TOP", 0, -20)
    title:SetText("Export Profile")

    -- Subtitle
    local sub = EllesmereUI.MakeFont(popup, 12, nil, 1, 1, 1)
    sub:SetAlpha(0.45)
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetText("Copy the string below and share it")

    -- Long profile strings stay clipped to this dedicated text box so they do
    -- not overflow the popup when compression is unavailable or the payload is
    -- simply too large to fit on one visible line.
    local _, editBox = CreateProfileStringBox(popup, FONT, {
        initialText = exportStr,
        readOnly = true,
    })

    -- Close button
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(120, 32)
    closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
    closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    EllesmereUI.MakeStyledButton(closeBtn, "Close", 13,
        EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)

    -- Dimmer click to close
    dimmer:SetScript("OnMouseDown", function(self)
        if not popup:IsMouseOver() then self:Hide() end
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

    dimmer:Show()
    C_Timer.After(0.05, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
--  Import Popup: shows an editable text box for pasting import strings
--  onImport(str) is called with the pasted string
-------------------------------------------------------------------------------
function EllesmereUI:ShowImportPopup(onImport)
    local POPUP_W, POPUP_H = 520, 260
    local FONT = EllesmereUI.EXPRESSWAY
    local EG = EllesmereUI.ELLESMERE_GREEN
    local PP = EllesmereUI.PanelPP

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
    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, PP)

    -- Title
    local title = EllesmereUI.MakeFont(popup, 18, nil, 1, 1, 1)
    title:SetPoint("TOP", popup, "TOP", 0, -20)
    title:SetText("Import Profile")

    -- Subtitle
    local sub = EllesmereUI.MakeFont(popup, 12, nil, 1, 1, 1)
    sub:SetAlpha(0.45)
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetText("Paste an EllesmereUI profile string below")

    -- Use the same clipped text box as export so very long profile strings stay
    -- visually contained while pasting or reviewing imports.
    local _, editBox = CreateProfileStringBox(popup, FONT, {
        initialText = "",
        readOnly = false,
    })

    -- Import button
    local importBtn = CreateFrame("Button", nil, popup)
    importBtn:SetSize(120, 32)
    importBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 14)
    importBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    local importBg, importBrd, importLbl = EllesmereUI.MakeStyledButton(
        importBtn, "Import", 13, EllesmereUI.WB_COLOURS, function()
            local str = editBox:GetText()
            if str and #str > 0 then
                dimmer:Hide()
                if onImport then onImport(str) end
            end
        end)

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, popup)
    cancelBtn:SetSize(120, 32)
    cancelBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 14)
    cancelBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    EllesmereUI.MakeStyledButton(cancelBtn, "Cancel", 13,
        EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)

    -- Dimmer click to close
    dimmer:SetScript("OnMouseDown", function(self)
        if not popup:IsMouseOver() then self:Hide() end
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

    dimmer:Show()
    C_Timer.After(0.05, function()
        editBox:SetFocus()
    end)
end
