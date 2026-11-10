if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Settings: a "Messaging" page in EllesmereUIOptions, built with the suite's
--  widget factory. Fonts use the EllesmereUI font picker
--  ("EUI Global Font" = the chat font), colors the EllesmereUI color swatches,
--  with an accent option where the chat window offers one. Every change
--  applies live (ns.Fire "SettingsChanged").
--
--  The builders only create rows and callbacks, so they are safe for the
--  global search's hidden pre-build pass.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS and EllesmereUI._ModuleNS["EllesmereUIMessaging"]
if not ns then return end

local CreateFrame = EllesmereUI._Pool.CreateFrame

local function Changed() ns.Fire("SettingsChanged") end
local function S() return ns.settings end
local function WS() return ns.settings.window end

-- Getter / setter pairs for EllesmereUI widgets
local function Bool(tbl, key)
    return function() return tbl()[key] and true or false end,
           function(v) tbl()[key] = v and true or false; Changed() end
end

local function Number(tbl, key)
    return function() return tbl()[key] end,
           function(v) tbl()[key] = v; Changed() end
end

local function Choice(tbl, key)
    return function() return tbl()[key] end,
           function(v) tbl()[key] = v; Changed() end
end

local function Color(tbl, key, hasAlpha)
    return function()
        local c = tbl()[key]
        return c.r, c.g, c.b, hasAlpha and c.a or nil
    end, function(r, g, b, a)
        local c = tbl()[key]
        c.r, c.g, c.b = r, g, b
        if hasAlpha and a then c.a = a end
        Changed()
    end
end

-------------------------------------------------------------------------------
--  Pages
-------------------------------------------------------------------------------
local POPUP_VALUES = { always = "Always", nocombat = "Not in combat", never = "Never (badge only)" }
local POPUP_ORDER = { "always", "nocombat", "never" }

local LAYOUT_VALUES = { list = "Side list", windows = "Window per person" }
local LAYOUT_ORDER = { "list", "windows" }

local OUTLINE_VALUES ={ __global = "EUI Global", none = "None", outline = "Outline", thick = "Thick Outline" }
local OUTLINE_ORDER = { "__global", "none", "outline", "thick" }

local TIMESTAMP_VALUES = { ["%H:%M "] = "15:04", ["%H:%M:%S "] = "15:04:05", ["%I:%M %p "] = "03:04 PM" }
local TIMESTAMP_ORDER = { "%H:%M ", "%H:%M:%S ", "%I:%M %p " }

local function BuildGeneral(W, parent, y)
    local _, h
    _, h = W:SectionHeader(parent, "MESSAGING", y); y = y - h
    _, h = W:Toggle(parent, "Handle Battle.net whispers", y, Bool(S, "battleNet")); y = y - h

    _, h = W:SectionHeader(parent, "NOTIFICATIONS", y); y = y - h
    local get, set = Choice(S, "popup")
    _, h = W:Dropdown(parent, "Open the window on a new whisper", y, POPUP_VALUES, get, set, POPUP_ORDER); y = y - h
    local note = "Your chat windows that show whispers already do this; the setting covers whispers no chat window shows."
    -- (a call that is not the last argument passes one value: unpack first)
    local getSound, setSound = Bool(S, "sound")
    _, h = W:Toggle(parent, "Play the whisper sound", y, getSound, setSound, note); y = y - h
    local getFlash, setFlash = Bool(S, "flash")
    _, h = W:Toggle(parent, "Flash the taskbar icon", y, getFlash, setFlash, note); y = y - h

    _, h = W:SectionHeader(parent, "MINIMAP", y); y = y - h
    _, h = W:Toggle(parent, "Show the minimap button", y,
        function() return ns.settings.minimap.show end,
        function(v) ns.settings.minimap.show = v; Changed() end); y = y - h
    return math.abs(y)
end

local function BuildWindow(W, parent, y)
    local _, h
    _, h = W:SectionHeader(parent, "WINDOW", y); y = y - h
    local getLayout, setLayout = Choice(WS, "layout")
    _, h = W:Dropdown(parent, "Layout", y, LAYOUT_VALUES, getLayout, setLayout, LAYOUT_ORDER,
        "Side list: one window with your conversations listed on the left. Window per person: each conversation in its own window."); y = y - h
    _, h = W:Toggle(parent, "Lock position and size", y, Bool(WS, "locked")); y = y - h
    _, h = W:ColorPicker(parent, "Background", y, Color(WS, "bgColor", true)); y = y - h
    _, h = W:ColorPicker(parent, "Name and location band", y, Color(WS, "headerBandColor", true)); y = y - h
    _, h = W:Toggle(parent, "Divider uses the accent color", y, Bool(WS, "dividerUseAccent")); y = y - h
    _, h = W:ColorPicker(parent, "Divider", y, Color(WS, "dividerColor", true)); y = y - h
    _, h = W:Toggle(parent, "Border", y, Bool(WS, "border")); y = y - h
    _, h = W:Toggle(parent, "Border uses the accent color", y, Bool(WS, "borderUseAccent")); y = y - h
    _, h = W:ColorPicker(parent, "Border color", y, Color(WS, "borderColor", true)); y = y - h
    _, h = W:WideButton(parent, "Reset position and size", y, function()
        local w = WS()
        w.point, w.width, w.height = nil, ns.DEFAULTS.window.width, ns.DEFAULTS.window.height
        w.personPoints, w.personSize = nil, nil
        ns.Print("the windows' positions and sizes reset with the next /reload.")
    end); y = y - h

    _, h = W:SectionHeader(parent, "TEXT", y); y = y - h
    local fontValues, fontOrder = {}, {}
    if EllesmereUI.BuildFontDropdownData then fontValues, fontOrder = EllesmereUI.BuildFontDropdownData() end
    local get, set = Choice(WS, "font")
    _, h = W:Dropdown(parent, "Font", y, fontValues, get, set, fontOrder); y = y - h
    get, set = Choice(WS, "outline")
    _, h = W:Dropdown(parent, "Outline", y, OUTLINE_VALUES, get, set, OUTLINE_ORDER); y = y - h
    get, set = Number(WS, "fontSize")
    _, h = W:Slider(parent, "Font size", y, 8, 24, 1, get, set); y = y - h
    _, h = W:Toggle(parent, "Timestamps", y, Bool(WS, "timestamps")); y = y - h
    get, set = Choice(WS, "timestampFormat")
    _, h = W:Dropdown(parent, "Timestamp format", y, TIMESTAMP_VALUES, get, set, TIMESTAMP_ORDER); y = y - h
    _, h = W:Toggle(parent, "Use the game's whisper colors", y, Bool(WS, "chatColors")); y = y - h
    _, h = W:ColorPicker(parent, "Incoming whispers", y, Color(WS, "inColor")); y = y - h
    _, h = W:ColorPicker(parent, "Outgoing whispers", y, Color(WS, "outColor")); y = y - h

    _, h = W:SectionHeader(parent, "TITLE BAR", y); y = y - h
    _, h = W:ColorPicker(parent, "Title bar", y, Color(WS, "headerColor", true)); y = y - h
    get, set = Number(WS, "titleFontSize")
    _, h = W:Slider(parent, "Title font size", y, 8, 18, 1, get, set); y = y - h
    _, h = W:Toggle(parent, "Title uses the accent color", y, Bool(WS, "titleUseAccent")); y = y - h
    _, h = W:ColorPicker(parent, "Title color", y, Color(WS, "titleColor", true)); y = y - h

    _, h = W:SectionHeader(parent, "CONVERSATION LIST", y); y = y - h
    get, set = Number(WS, "tabFontSize")
    _, h = W:Slider(parent, "List font size", y, 8, 18, 1, get, set); y = y - h
    get, set = Number(WS, "sidebarWidth")
    _, h = W:Slider(parent, "List width", y, 110, 260, 5, get, set); y = y - h

    _, h = W:SectionHeader(parent, "ICONS", y); y = y - h
    _, h = W:Toggle(parent, "Icons use the accent color", y, Bool(WS, "iconUseAccent")); y = y - h
    _, h = W:ColorPicker(parent, "Icon color", y, Color(WS, "iconColor")); y = y - h
    return math.abs(y)
end

local function BuildHistory(W, parent, y)
    local _, h
    local function H() return ns.settings.history end
    _, h = W:SectionHeader(parent, "HISTORY", y); y = y - h
    _, h = W:Toggle(parent, "Save whisper history", y, Bool(H, "enabled")); y = y - h
    local get, set = Number(H, "keep")
    _, h = W:Slider(parent, "Messages kept per conversation", y, 50, 1000, 50, get, set); y = y - h
    get, set = Number(H, "replay")
    _, h = W:Slider(parent, "Earlier messages shown when a conversation opens", y, 0, 100, 5, get, set); y = y - h
    get, set = Number(H, "days")
    _, h = W:Slider(parent, "Delete conversations idle for (days, 0 = never)", y, 0, 365, 1, get, set); y = y - h
    _, h = W:WideButton(parent, "Open the history", y, function() ns.ShowHistory() end); y = y - h
    _, h = W:WideButton(parent, "Delete all history", y, function()
        EllesmereUI:ShowConfirmPopup({
            title = "Delete All History",
            message = "Delete the whisper history of every character?",
            confirmText = DELETE or "Delete",
            cancelText = CANCEL or "Cancel",
            onConfirm = function() ns.ClearAllHistory() end,
        })
    end); y = y - h
    return math.abs(y)
end

-------------------------------------------------------------------------------
-- Registration
-------------------------------------------------------------------------------
local BUILDERS = { General = BuildGeneral, Window = BuildWindow, History = BuildHistory }

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    EllesmereUI:RegisterModule("EllesmereUIMessaging", {
        title       = "Messaging",
        description = "Messaging windows with history and a minimap button.",
        pages       = { "General", "Window", "History" },
        searchTerms = "messaging messages whisper whispers tell reply battle.net history minimap pin popup",
        buildPage   = function(pageName, parent, yOffset)
            local builder = BUILDERS[pageName]
            if not builder then return 0 end
            return builder(EllesmereUI.Widgets, parent, yOffset)
        end,
        onReset = function()
            ns.ResetSettings()
            if EllesmereUI.InvalidatePageCache then EllesmereUI:InvalidatePageCache() end
        end,
    })
end)
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
