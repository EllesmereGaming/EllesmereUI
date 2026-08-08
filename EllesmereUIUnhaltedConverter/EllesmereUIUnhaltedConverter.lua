-------------------------------------------------------------------------------
--  EllesmereUIUnhaltedConverter.lua
--  Experimental: converts an Unhalted Unit Frames export string (!UUF_...) into
--  an EllesmereUI import string (!EUI_...), mapping frames as faithfully as the
--  two layouts allow. Pure mapping lives in EllesmereUIUnhaltedConverter_Core.lua;
--  this file owns the WoW-side plumbing (decode, live position context, encode,
--  apply).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local Core = ns.ConverterCore
local LibStub = _G.LibStub
local LibDeflate = LibStub and LibStub("LibDeflate", true)
local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)

-- Small DB so the options page can remember the last paste and scope toggles.
local defaults = {
    profile = {
        doSingle = true,
        doGroup = true,
    },
}
local EUC = EllesmereUI.Lite.NewAddon("EllesmereUIUnhaltedConverter")

-- Open the DB from OnInitialize (fired on our ADDON_LOADED by EllesmereUI.Lite),
-- NOT at file scope. Lite.NewDB creates the shared EllesmereUIDB.profiles tables
-- and touches the central store; doing that eagerly at load runs it under this
-- addon's taint before the core's lifecycle has run, and that taint can spread
-- onto Blizzard's Game Menu (a later click of a protected menu button is then
-- blamed on this addon -> ADDON_ACTION_FORBIDDEN). Every sibling module defers
-- this identical call to OnInitialize; match them. All readers of the db handle
-- (the options page, _G._EUC_DB) run after OnInitialize, so nothing needs it
-- earlier.
function EUC:OnInitialize()
    EUC.db = EllesmereUI.Lite.NewDB("EllesmereUIUnhaltedConverterDB", defaults)
    _G._EUC_DB = EUC.db
    ns.db = EUC.db
end

local UUF_PREFIX = "!UUF_"

-------------------------------------------------------------------------------
--  Decode an Unhalted export string -> profile table ({ General=..., Units=... })
-------------------------------------------------------------------------------
function ns.Decode(uufString)
    if type(uufString) ~= "string" then return nil, "No import string provided." end
    uufString = uufString:gsub("^%s+", ""):gsub("%s+$", "")
    if uufString == "" then return nil, "No import string provided." end
    if uufString:sub(1, #UUF_PREFIX) ~= UUF_PREFIX then
        return nil, "This does not look like an Unhalted string (missing the \"!UUF_\" prefix)."
    end
    if not LibDeflate then return nil, "LibDeflate is unavailable." end
    if not AceSerializer then return nil, "AceSerializer is unavailable." end

    local encoded = uufString:sub(#UUF_PREFIX + 1)
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then return nil, "Could not decode the string (corrupt or truncated)." end
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then return nil, "Could not decompress the string (corrupt or truncated)." end
    local ok, data = AceSerializer:Deserialize(serialized)
    if not ok or type(data) ~= "table" then return nil, "Could not read the Unhalted data." end

    -- Unhalted wraps the profile as { profile = <profile> }.
    local profile = data.profile or data
    if type(profile) ~= "table" or type(profile.Units) ~= "table" then
        return nil, "The string decoded, but contains no Unhalted unit-frame data."
    end
    return profile
end

-------------------------------------------------------------------------------
--  Position context. When the Unhalted frames are still loaded, reading their
--  live rects gives an exact placement; otherwise the core falls back to the
--  data-driven resolver / EllesmereUI defaults.
-------------------------------------------------------------------------------
local function frameCenterInUIParent(f)
    if not f or not f.GetCenter then return nil end
    if f.IsForbidden and f:IsForbidden() then return nil end
    local cx, cy = f:GetCenter()
    if not cx then return nil end
    local fs = (f.GetEffectiveScale and f:GetEffectiveScale()) or 1
    local us = UIParent:GetEffectiveScale()
    if us == 0 then return nil end
    return { x = cx * fs / us, y = cy * fs / us }
end

local function frameRectInUIParent(f)
    if not f or not f.GetRect then return nil end
    if f.IsForbidden and f:IsForbidden() then return nil end
    local l, b, w, h = f:GetRect()
    if not l then return nil end
    local fs = (f.GetEffectiveScale and f:GetEffectiveScale()) or 1
    local us = UIParent:GetEffectiveScale()
    if us == 0 then return nil end
    local k = fs / us
    return { left = l * k, bottom = b * k, w = w * k, h = h * k }
end

-- UUF's default profile, for the Core's sparse/old-version back-fill
-- (ctx.uufDefaults). UUF keeps GetDefaultDB on its file-local addon table (never
-- assigned to _G, and NOT the AceAddon object registered as "UnhaltedUnitFrames"),
-- so there is no direct handle -- but its database is AceDB-3.0:New("UUFDB", ...),
-- and AceDB records every database in db_registry with the registered defaults on
-- db.defaults. Matching on db.sv == _G.UUFDB recovers the live defaults whenever
-- UUF is loaded. With UUF disabled, UUFDB isn't loaded and this returns nil --
-- the Core then maps the profile as-is (offline tests / uuf-fuzz pass
-- ctx.uufDefaults from disk instead).
local function uufDefaultProfile()
    local sv = _G.UUFDB
    local AceDB = LibStub and LibStub("AceDB-3.0", true)
    if not (sv and AceDB and AceDB.db_registry) then return nil end
    for db in pairs(AceDB.db_registry) do
        if db.sv == sv then
            return db.defaults and db.defaults.profile
        end
    end
end

local function buildContext()
    return {
        uiWidth = UIParent:GetWidth(),
        uiHeight = UIParent:GetHeight(),
        -- UIParent's live scale, so the Core can warn when the imported profile
        -- was built at a different UI scale (positions would land offset).
        currentUiScale = UIParent:GetScale(),
        uufDefaults = uufDefaultProfile(),
        getLiveUnitRect = function(frameName)
            if not frameName then return nil end
            local f = _G[frameName]
            if not f and frameName == "UUF_Boss" then f = _G["UUF_Boss1"] end
            if not f then return nil end
            -- A placed-but-hidden frame still resolves; GetCenter returns nil
            -- only if it was never anchored, which frameCenterInUIParent handles.
            return frameCenterInUIParent(f)
        end,
        getExternalRect = function(frameName)
            if not frameName then return nil end
            return frameRectInUIParent(_G[frameName])
        end,
        -- Resolves a unit's REAL class color, live, at conversion time -- for
        -- units UnitClass can't answer for the offline/no-context case (Core's
        -- test harness never provides this ctx field, so a raidcolor-prefixed
        -- pet tag there just falls back to EUI's classColor toggle instead).
        -- Mirrors exactly what oUF's own [raidcolor] tag does (UnitClass(u) ->
        -- class color table), so the converted color matches Unhalted's live
        -- render for the unit currently on screen.
        resolveClassColor = function(unit)
            if not unit or not UnitExists(unit) then return nil end
            local _, class = UnitClass(unit)
            if not class then return nil end
            local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
            if not c then return nil end
            return { r = c.r, g = c.g, b = c.b }
        end,
    }
end

-------------------------------------------------------------------------------
--  Convert: string -> payload table + !EUI_ string + warnings
-------------------------------------------------------------------------------
-- opts: { single=bool, group=bool }
-- returns: payload, euiString, warnings, err
function ns.Convert(uufString, opts)
    local profile, err = ns.Decode(uufString)
    if not profile then return nil, nil, nil, err end
    if not Core then return nil, nil, nil, "Converter core failed to load." end

    local res = Core.Convert(profile, opts or { single = true, group = true }, buildContext())

    local addons = {}
    if res.unitFrames then addons.EllesmereUIUnitFrames = res.unitFrames end
    if res.raidFrames then addons.EllesmereUIRaidFrames = res.raidFrames end
    if not next(addons) then
        return nil, nil, res.warnings, "Nothing was selected to convert."
    end

    local payload = {
        version = 3,
        type = "full",
        data = { addons = addons, partialImport = true },
    }

    -- Font face/outline is a profile-global (not an addon key), so it travels
    -- alongside the addon blobs in payload.data.fonts.
    if res.fonts then payload.data.fonts = res.fonts end

    -- Frame sizes: EllesmereUI's unlock width/height-match system otherwise
    -- clobbers the imported frameWidth/healthHeight with the recipient's stale
    -- matches. Carrying an empty unlockLayout makes the import drop the unit-frame
    -- match/anchor entries (only for the imported folders), so imported sizes
    -- stick. Single-frames only -- raid frames don't participate in matching.
    if res.unitFrames then
        payload.data.unlockLayout = { anchors = {}, widthMatch = {}, heightMatch = {}, phantomBounds = {} }
    end

    local euiString
    if EllesmereUI.EncodePayload then
        euiString = EllesmereUI.EncodePayload(payload)
    end
    return payload, euiString, res.warnings, nil
end

-------------------------------------------------------------------------------
--  Apply a converted payload straight into the active profile (partial import,
--  leaves every other module untouched). A reload settles the frames.
-------------------------------------------------------------------------------
function ns.ApplyPayload(payload)
    if type(payload) ~= "table" then return false, "Nothing to apply." end
    if not EllesmereUI.ImportProfile then return false, "EllesmereUI import is unavailable." end
    -- Import INTO the active profile: EllesmereUI.ImportProfile overlays only the
    -- imported modules onto a copy of the named profile and re-activates it, so
    -- every other module keeps its current settings. A profile name is required
    -- (the "full" path writes db.profiles[name]); nil would error.
    local profileName = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    local pcallOk, ok, applyErr = pcall(EllesmereUI.ImportProfile, payload, profileName)
    if not pcallOk then return false, tostring(ok) end
    if ok == false then return false, applyErr or "Import failed." end

    -- Disable Unhalted Unit Frames. Two oUF-based unit-frame addons cannot both be
    -- active: each hooks SetParent on the Blizzard frames via oUF's DisableBlizzard,
    -- and with both enabled those hooks recurse into one another (C stack overflow).
    -- The migration's end state is EllesmereUI-only, so turn Unhalted off; the reload
    -- that follows applies it. Users can re-enable it from the AddOns list any time.
    if C_AddOns and C_AddOns.DisableAddOn then
        pcall(C_AddOns.DisableAddOn, "UnhaltedUnitFrames")
    end
    return true
end

-- Bridge for the options file.
_G._EUC_Convert = ns.Convert
_G._EUC_ApplyPayload = ns.ApplyPayload
