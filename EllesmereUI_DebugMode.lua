if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Debug Mode (Global Settings > General): turns other addons off for this character,
-- noted at EllesmereUIDB.debugAddOns[GUID] so exiting restores only those.
local ADDON_NAME = ...
local ERRORS_MAX = 50

-- The AddOns API names a character by GUID (as Blizzard's AddOn List does); also the store key.
local function Who()
    local guid = UnitGUID("player")
    return guid, guid
end

local function MyList()
    local t = type(EllesmereUIDB) == "table" and EllesmereUIDB.debugAddOns
    if type(t) ~= "table" then return nil end
    local _, key = Who()
    local list = t[key]
    return type(list) == "table" and list or nil
end

function EllesmereUI.DebugModeActive()
    return MyList() ~= nil
end

-- Turns off every non-EllesmereUI addon on for this character and shows Lua errors; the caller reloads.
function EllesmereUI.EnterDebugMode()
    if MyList() or type(EllesmereUIDB) ~= "table" then return end
    local me, key = Who()
    local list = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and not name:find("^EllesmereUI")
           and C_AddOns.GetAddOnEnableState(name, me) > 0 then
            list[#list + 1] = name
            C_AddOns.DisableAddOn(name, me)
        end
    end
    local was = GetCVar("scriptErrors")
    if was ~= "1" and EllesmereUI.HoldCVar("scriptErrors", "1") then list.scriptErrorsWas = was end
    if type(EllesmereUIDB.debugAddOns) ~= "table" then EllesmereUIDB.debugAddOns = {} end
    EllesmereUIDB.debugAddOns[key] = list
    EllesmereUIDB.debugErrors = nil
    C_AddOns.SaveAddOns()
end

-- Turns back on what EnterDebugMode turned off (skipping removed ones); the caller reloads.
function EllesmereUI.ExitDebugMode()
    local list = MyList()
    if not list then return end
    local me, key = Who()
    for _, name in ipairs(list) do
        if C_AddOns.DoesAddOnExist(name) then C_AddOns.EnableAddOn(name, me) end
    end
    if list.scriptErrorsWas then EllesmereUI.ReleaseCVar("scriptErrors", list.scriptErrorsWas) end
    local t = EllesmereUIDB.debugAddOns
    t[key] = nil
    if next(t) == nil then EllesmereUIDB.debugAddOns = nil end
    C_AddOns.SaveAddOns()
end

-- Uninstall turns EllesmereUI off: give this character its addons back first.
EllesmereUI.OnUninstall(EllesmereUI.ExitDebugMode)

-- Saved Lua errors (EllesmereUIDB.debugErrors), oldest first; nil when there are none.
function EllesmereUI.DebugErrors()
    local e = type(EllesmereUIDB) == "table" and EllesmereUIDB.debugErrors
    return type(e) == "table" and #e > 0 and e or nil
end

function EllesmereUI.DebugErrorsText()
    local e = EllesmereUI.DebugErrors()
    if not e then return "" end
    local parts = {}
    for i, d in ipairs(e) do
        parts[i] = ("Message: %s\nTime: %s\nCount: %s\nStack:\n%s\nLocals:\n%s"):format(
            d.message or "", d.time or "", d.count or 1, d.stack or "", d.locals or "")
    end
    return table.concat(parts, "\n\n----------\n\n")
end

-- Saved errors from earlier sessions, and this session's frame entries already cleared.
local kept, skip = 0, 0

-- Blizzard's error frame dedupes and counts this session's errors: copy them after earlier sessions'.
local function SaveErrors(frame)
    local data = frame.errorData
    if type(data) ~= "table" or type(EllesmereUIDB) ~= "table" then return end
    local out = EllesmereUIDB.debugErrors
    if type(out) ~= "table" then out = {}; EllesmereUIDB.debugErrors = out end
    for i = #out, kept + 1, -1 do out[i] = nil end
    for i, d in ipairs(data) do
        if #out >= ERRORS_MAX then break end
        local m, s, l = d.message, d.stack, d.locals
        if i > skip and d.messageType == 0 and not issecretvalue(m) and not issecretvalue(s) and not issecretvalue(l) then
            out[#out + 1] = { message = m, stack = s, locals = l, time = d.time, count = d.count }
        end
    end
    if #out == 0 then EllesmereUIDB.debugErrors = nil end
end

function EllesmereUI.ClearDebugErrors()
    if type(EllesmereUIDB) == "table" then EllesmereUIDB.debugErrors = nil end
    local data = ScriptErrorsFrame and ScriptErrorsFrame.errorData
    kept, skip = 0, type(data) == "table" and #data or 0
end

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self, event, name)
        if event == "ADDON_LOADED" then
            if name ~= ADDON_NAME then return end
            self:UnregisterEvent("ADDON_LOADED")
            -- Error capture only while Debug Mode is on (on any character of the account).
            local t = type(EllesmereUIDB) == "table" and EllesmereUIDB.debugAddOns
            local frame = ScriptErrorsFrame
            if type(t) ~= "table" or not next(t) or not frame or not frame.DisplayMessageInternal then return end
            kept = EllesmereUI.DebugErrors() and #EllesmereUIDB.debugErrors or 0
            hooksecurefunc(frame, "DisplayMessageInternal", function(fr) pcall(SaveErrors, fr) end)
            pcall(SaveErrors, frame)
            return
        end
        -- Login reminder while it is on, so the missing addons are no surprise.
        self:UnregisterAllEvents()
        local list = MyList()
        if not list then return end
        EllesmereUI.Print("|cff0cd29dEllesmereUI:|r " .. EllesmereUI.Lf(
            "Debug Mode is on: %d other addons are turned off. Deactivate it in Global Settings > General.", #list))
    end)
end
