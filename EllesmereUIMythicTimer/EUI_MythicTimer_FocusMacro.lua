if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EUI_MythicTimer_FocusMacro.lua
--  Kick Tracker (Mythic+ Tools), the Set Focus macro.
--
--  The Set Focus macro (EUI_Focus, an account macro) is written from the
--  Kick Tracker's Focus Marker, so changing the marker rewrites the macro and
--  nobody edits a marker number by hand. Its body: /focus on a hostile
--  mouseover (else the target), then, while a marker is set,
--  /tm [@focus] ~N (the ~ declines to overwrite a marker a group member
--  already placed), and with Ping Focus on, /ping [@focus] 3 (the numeric
--  alias, On My Way: the word forms only match on English clients). The
--  party is told the marker by Focus Announce's ready-check line alone
--  (EUI_MythicTimer_KickPlates.lua), never by the macro.
--
--  The macro is written from KT_Refresh (a settings write, a profile switch,
--  the module's enable) and, for an account that has it from here, once the
--  session's macros are in; only when its body changed, and in combat the
--  write waits for combat to end. Nothing runs on WoW Forever (no Set Focus
--  macro there: /tm's ~ is a retail extension).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local MACRO_NAME = "EUI_Focus"
local MACRO_ICON = 236203
local FOCUS_LINE = "/focus [@mouseover,harm,nodead] []"

local function Cfg()
    local db = _G._EMT_AceDB
    local p = db and db.profile
    return p and p.kickTracker
end

-- A stored marker as 1-8, or nil (None, or a value edited out of range).
local function ValidMarker(v)
    v = tonumber(v)
    if v and v >= 1 and v <= 8 and v == math.floor(v) then return v end
    return nil
end

local function Body(cfg)
    local lines = { FOCUS_LINE }
    local mark = cfg and ValidMarker(cfg.focusMarker)
    local ping = cfg and cfg.focusMacroPing == true
    if mark or ping then
        -- Every trailing line acts on the focus: none acquired, none runs.
        lines[#lines + 1] = "/stopmacro [@focus,noexists]"
        if mark then lines[#lines + 1] = "/tm [@focus] ~" .. mark end
        if ping then lines[#lines + 1] = "/ping [@focus] 3" end
    end
    return table.concat(lines, "\n")
end

function ns.FM_Exists()
    return not EllesmereUI.IS_FOREVER and GetMacroIndexByName(MACRO_NAME) ~= 0
end

-- The macro brought in line with the settings, if the player has it.
local function Sync()
    if EllesmereUI.IS_FOREVER then return end
    local idx = GetMacroIndexByName(MACRO_NAME)
    if idx == 0 then return end
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("KickTracker:FocusMacro", Sync)
        return
    end
    local body = Body(Cfg())
    if GetMacroBody(idx) ~= body then EditMacro(idx, nil, nil, body) end
end

-- EllesmereUIDB.kickFocusMacro: true once this account has the macro from
-- here (made on this page, or carried over from the Macro Factory), cleared
-- when it is deleted here. Only then does a login look for it (below).
local function SetMacroMade(v)
    if type(EllesmereUIDB) ~= "table" then EllesmereUIDB = {} end
    EllesmereUIDB.kickFocusMacro = v or nil
end

-- Create and Delete run from a click, never in combat (both are protected
-- there); each answers whether it went through.
function ns.FM_Create()
    if EllesmereUI.IS_FOREVER or InCombatLockdown() then return false end
    if GetMacroIndexByName(MACRO_NAME) == 0 then
        CreateMacro(MACRO_NAME, MACRO_ICON, Body(Cfg()), nil)
    end
    local made = GetMacroIndexByName(MACRO_NAME) ~= 0
    if made then SetMacroMade(true) end
    return made
end

function ns.FM_Delete()
    if InCombatLockdown() then return false end
    if GetMacroIndexByName(MACRO_NAME) ~= 0 then DeleteMacro(MACRO_NAME) end
    SetMacroMade(false)
    return true
end

-- The Set Focus toggles used to live on the Macro Factory's Set Focus button
-- (EllesmereUIDB.macroFactory.EUI_Focus, account-wide). Moved once into the
-- profile in use: Auto Mark carries its marker over while no Focus Marker is
-- set (the macro marks whenever one is), Announce Focus is gone (Focus
-- Announce tells the party instead). A marker carried over was the macro's
-- alone, so Focus Announce starts off for it: the update posts no party line
-- that was not posted before.
local migrated = false
local function Migrate(cfg)
    if migrated then return end
    migrated = true
    local mf = type(EllesmereUIDB) == "table" and EllesmereUIDB.macroFactory
    local old = type(mf) == "table" and mf[MACRO_NAME]
    if type(old) ~= "table" then return end
    mf[MACRO_NAME] = nil
    SetMacroMade(true)
    if old.autoMark and not ValidMarker(cfg.focusMarker) then
        cfg.focusMarker = ValidMarker(old.markIcon) or 8
        cfg.focusAnnounce = false
    end
    if old.ping then cfg.focusMacroPing = true end
end

-- At login the macros are not in when the module enables, so the first sync
-- finds no macro. The frame is inert: the first refresh registers it only
-- for an account with the macro from here, for one look on the first
-- loading screen and the first macro update; then nothing listens. Later
-- refreshes find the macros in and write at once.
local login = CreateFrame("Frame")
login:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent(event)
    Sync()
end)
local firstRefresh = true

-- From KT_Refresh, ahead of Focus Announce reading the marker.
function ns.FM_Refresh(cfg)
    if not cfg or EllesmereUI.IS_FOREVER then return end
    Migrate(cfg)
    if firstRefresh then
        firstRefresh = false
        if type(EllesmereUIDB) == "table" and EllesmereUIDB.kickFocusMacro == true then
            login:RegisterEvent("PLAYER_ENTERING_WORLD")
            login:RegisterEvent("UPDATE_MACROS")
        end
    end
    Sync()
end
