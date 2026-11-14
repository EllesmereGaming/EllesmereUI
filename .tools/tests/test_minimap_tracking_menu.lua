-- Stub harness: the Minimap's tracking button and Blizzard's tracking menu.
-- Cuts the tracking button's handlers, the click memory and the Gamepad style
-- hotspot from EUI_Minimap_Layout.lua and plays mouse presses over a model of
-- Blizzard's dropdown button and menu manager (a press closes an open menu the
-- cursor is not over, before the frame under the cursor sees the press).
--   outside the Gamepad style: our click opens the menu, a second click closes
--     it and does not reopen it, and nothing listens while no menu of ours is open
--   under the Gamepad style: the menu is never opened from addon code (closing
--     such a menu there is a blocked action); Blizzard's own button takes the
--     press that opens it, and ours the press that closes it
-- The model is this file's reading of the client, not the client.
--   lua .tools/tests/test_minimap_tracking_menu.lua        (from the repository root)
local TARGET = TM_TARGET or "EllesmereUIMinimap/EUI_Minimap_Layout.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local fh = assert(io.open(TARGET, "rb"))
local src = fh:read("*a"):gsub("\r\n", "\n")
fh:close()

-- The text between `from` and the first `to` after it, both included.
local function Cut(from, to, what)
    local a = assert(src:find(from, 1, true), what .. ": start not found")
    local b, e = src:find(to, a, true)
    assert(b, what .. ": end not found")
    return src:sub(a, e)
end

local CHUNK = "local EBS, _customIndicators, CreateIndicatorBtn, GetFFD, GetCustomTooltipScale, minimap = ...\n"
    .. Cut("-- Outside the gamepad style our click opens the tracking menu.", "\nend\n", "click memory")
    .. Cut('    _customIndicators.tracking = CreateIndicatorBtn("_tracking", minimap,',
        "EllesmereUI.HideWidgetTooltip()\n    end)", "tracking button") .. "\n"
    .. Cut("local SyncTrackingHotspot\ndo\n", "\nend\n", "hotspot")
    .. "return SyncTrackingHotspot\n"
local Build = assert(loadstring(CHUNK, "=TrackingMenu"))

-------------------------------------------------------------------------------
--  The world
-------------------------------------------------------------------------------
local W
local HOME = { name = "MinimapCluster.Tracking" }

local function Fire(event)
    local list = {}
    for _, f in ipairs(W.evFrames) do
        if f._events[event] and f._onEvent then list[#list + 1] = f end
    end
    for _, f in ipairs(list) do f._onEvent(f, event) end
end

local function Listening(event)
    local n = 0
    for _, f in ipairs(W.evFrames) do
        if f._events[event] then n = n + 1 end
    end
    return n
end

-- upFirst: the release tells its listeners before the button's click runs, or
-- after. The client's order is not documented, so every sequence runs both ways.
local function Load(gamepad, upFirst, freeMove)
    W = {
        gamepad = gamepad, upFirst = upFirst, shift = false, over = "away", blizz = false,
        evFrames = {}, ffd = {}, addonOpens = 0, pressOpens = 0, closes = 0, forbidden = 0,
        anchors = 0, clickWrites = 0, tips = 0,
    }
    local mp = { hideTrackingButton = false, freeMoveBtns = freeMove or false }
    W.mp = mp

    -- Blizzard's tracking button (a dropdown button) as the module leaves it
    local bliz = { _parent = HOME, _points = { { "TOPRIGHT", HOME, "TOPRIGHT", -3, -2 } }, _w = 23, _h = 23,
        _alpha = 1, _motion = true, _click = true, _level = 3, _insets = { 0, 0, 0, 0 } }
    function bliz:OpenMenu()
        if self:IsMenuOpen() then return end
        local m = { _shown = true, _points = {}, byAddon = not W.blizz }
        function m:IsShown() return self._shown end
        function m:Hide() self._shown = false end
        function m:ClearAllPoints() self._points = {} end
        function m:SetPoint(...) self._points[#self._points + 1] = { ... } end
        self.menu = m
        if W.blizz then W.pressOpens = W.pressOpens + 1 else W.addonOpens = W.addonOpens + 1 end
    end
    function bliz:IsMenuOpen() return self.menu ~= nil end
    -- Blizzard closes it: the closed callback clears the field. Closing a menu
    -- addon code opened is the blocked action under the Gamepad style.
    function bliz:Closed()
        local m = self.menu
        if not m then return end
        m._shown = false
        self.menu = nil
        W.closes = W.closes + 1
        if m.byAddon and W.gamepad then W.forbidden = W.forbidden + 1 end
    end
    function bliz:SetParent(p) self._parent = p end
    function bliz:GetParent() return self._parent end
    function bliz:ClearAllPoints() self._points = {} end
    function bliz:SetPoint(...) self._points[#self._points + 1] = { ... }; W.anchors = W.anchors + 1 end
    function bliz:GetPoint(i) local p = self._points[i]; if p then return unpack(p) end end
    function bliz:SetSize(w, h) self._w, self._h = w, h end
    function bliz:GetSize() return self._w, self._h end
    function bliz:SetHitRectInsets(...) self._insets = { ... } end
    function bliz:SetAlpha(a) self._alpha = a end
    function bliz:SetFrameLevel(l) self._level = l end
    function bliz:EnableMouse(v) self._motion, self._click = v, v end
    function bliz:SetMouseMotionEnabled(v) self._motion = v end
    function bliz:SetMouseClickEnabled(v) self._click = v; W.clickWrites = W.clickWrites + 1 end
    W.bliz = bliz
    MinimapCluster = { Tracking = { Button = bliz } }

    EllesmereUI = {
        PadGamepadUI = function() return W.gamepad end,
        ShowWidgetTooltip = function() W.tips = W.tips + 1 end,
        HideWidgetTooltip = function() end,
    }
    IsShiftKeyDown = function() return W.shift end
    CreateFrame = function()
        local f = { _events = {} }
        function f:RegisterEvent(e) self._events[e] = true end
        function f:UnregisterEvent(e) self._events[e] = nil end
        function f:SetScript(_, fn) self._onEvent = fn end
        W.evFrames[#W.evFrames + 1] = f
        return f
    end

    local EBS = { db = { profile = { minimap = mp } }, _Grow = { TT = function() return "ANCHOR_LEFT" end } }
    local function CreateIndicatorBtn(_, _, _, _, _, onClick)
        local b = { _scripts = {}, _shown = true, _w = 26, _h = 26, _level = 22 }
        function b:SetScript(k, fn) self._scripts[k] = fn end
        function b:GetScript(k) return self._scripts[k] end
        function b:IsMouseOver() return W.over == "ours" end
        function b:IsShown() return self._shown end
        function b:GetSize() return self._w, self._h end
        function b:GetFrameLevel() return self._level end
        b._scripts.OnEnter = function() end
        b._scripts.OnLeave = function() end
        -- as the module's indicator factory wires a click
        b._scripts.OnClick = function(self)
            if W.ffd.freeMoveJustDragged then return end
            onClick(self)
        end
        W.ours = b
        return b
    end
    W.Sync = Build(EBS, {}, CreateIndicatorBtn, function() return W.ffd end, function() return 1 end, {})
    W.EBS = EBS
    -- a layout pass: the Blizzard originals' mouse goes off, then the hotspot is settled
    function W.Layout()
        bliz:EnableMouse(false)
        W.Sync(mp)
    end
    W.Layout()
end

local function Hover(where)
    local was = W.over
    W.over = where
    if was ~= "ours" and where == "ours" then W.ours._scripts.OnEnter(W.ours) end
    if was == "ours" and where ~= "ours" then W.ours._scripts.OnLeave(W.ours) end
end

-- Blizzard's side of a press: the menu manager first (the top mouse focus over
-- our button is our button: the hotspot takes no mouse motion), then the frame
-- that takes the click there.
local function Press(button)
    button = button or "LeftButton"
    W.blizz = true
    if button == "LeftButton" or button == "RightButton" then
        local claim = W.over == "ours" and rawget(W.ours, "HandlesGlobalMouseEvent")
        if claim then W.claimed = true end
        if not (claim and claim(W.ours, button, "GLOBAL_MOUSE_DOWN")) then
            if W.bliz.menu and W.over ~= "menu" then W.bliz:Closed() end
        end
    end
    local b = W.bliz
    if W.over == "ours" and b._parent == W.ours and b._click then
        W.pressedOn = "hotspot"
        if button == "LeftButton" and not W.shift then
            if b:IsMenuOpen() then b:Closed() else b:OpenMenu() end
        end
    else
        W.pressedOn = W.over
    end
    W.blizz = false
    W.pressButton = button
end

local function Release()
    local function Click()
        if W.pressedOn == "ours" and W.over == "ours" and W.pressButton == "LeftButton" then
            W.ours._scripts.OnClick(W.ours)
        end
    end
    if W.upFirst then Fire("GLOBAL_MOUSE_UP"); Click() else Click(); Fire("GLOBAL_MOUSE_UP") end
    W.pressedOn = nil
end

local function Click(where, button)
    Hover(where)
    Press(button)
    Release()
end

local function Escape()
    W.blizz = true
    W.bliz:Closed()
    W.blizz = false
end

local function Open() return W.bliz.menu ~= nil and W.bliz.menu:IsShown() end

-------------------------------------------------------------------------------
-- 1. Outside the Gamepad style (retail, and WoW Forever without it)
-------------------------------------------------------------------------------
for _, upFirst in ipairs({ true, false }) do
    local tag = upFirst and " (release first)" or " (click first)"
    Load(false, upFirst)
    check(Listening("GLOBAL_MOUSE_UP") == 0 and Listening("MODIFIER_STATE_CHANGED") == 0 and #W.evFrames == 0,
        "nothing listens and no frame is made before a click" .. tag)
    check(W.bliz:GetParent() == HOME and W.clickWrites == 0, "Blizzard's button is left where it is" .. tag)

    Click("ours")
    check(Open() and W.addonOpens == 1, "the first click opens the menu" .. tag)
    local p = W.bliz.menu._points[1]
    check(p and p[1] == "TOPRIGHT" and p[2] == W.ours and p[3] == "TOPLEFT" and p[4] == -4 and p[5] == 0,
        "the menu hangs left of our button, tops level" .. tag)
    check(Listening("GLOBAL_MOUSE_UP") == 1, "one release listener while our menu is open" .. tag)

    Click("ours")
    check(not Open() and W.addonOpens == 1, "the second click closes it and does not reopen it" .. tag)
    check(Listening("GLOBAL_MOUSE_UP") == 0, "nothing listens once it is closed" .. tag)

    Click("ours")
    check(Open() and W.addonOpens == 2, "the third click opens it again" .. tag)

    -- a click on an entry leaves the menu open and changes nothing
    Click("menu")
    check(Open() and W.addonOpens == 2, "a click inside the menu keeps it" .. tag)
    Click("ours")
    check(not Open() and W.addonOpens == 2, "then a click on the button closes it" .. tag)

    -- closed by a click elsewhere: the next click on the button opens
    Click("ours")
    Click("away")
    check(not Open() and Listening("GLOBAL_MOUSE_UP") == 0, "a click elsewhere closes it and is forgotten" .. tag)
    Click("ours")
    check(Open() and W.addonOpens == 4, "the next click on the button opens" .. tag)

    -- pressed elsewhere, released over the button: forgotten on the way in
    Hover("away"); Press(); Hover("ours"); Release()
    check(not Open(), "a press elsewhere closed it" .. tag)
    Click("ours")
    check(Open() and W.addonOpens == 5, "a release over the button after a press elsewhere costs no click" .. tag)

    -- Escape while the mouse is away: forgotten when it comes back
    Hover("away")
    Escape()
    Click("ours")
    check(Open() and W.addonOpens == 6, "Escape with the mouse away costs no click" .. tag)

    -- known limit: closed with no mouse event while the mouse rests on the
    -- button, the next click does nothing once
    Escape()
    Click("ours")
    check(not Open() and W.addonOpens == 6, "limit: after Escape with the mouse resting on it, one click does nothing" .. tag)
    Click("ours")
    check(Open() and W.addonOpens == 7, "limit: the click after that opens" .. tag)

    -- a Free Move drag swallows its click
    Click("away")
    W.ffd.freeMoveJustDragged = true
    Click("ours")
    check(not Open() and W.addonOpens == 7, "a drag's release opens nothing" .. tag)
    W.ffd.freeMoveJustDragged = nil

    check(W.bliz:GetParent() == HOME and W.clickWrites == 0 and Listening("MODIFIER_STATE_CHANGED") == 0,
        "the hotspot never comes on outside the Gamepad style" .. tag)
    check(rawget(W.ours, "HandlesGlobalMouseEvent") == nil and not W.claimed,
        "our button gives Blizzard's menu code no method to call" .. tag)
    check(W.forbidden == 0, "no blocked action" .. tag)
end

-------------------------------------------------------------------------------
-- 2. Under the Gamepad style: the hotspot
-------------------------------------------------------------------------------
for _, upFirst in ipairs({ true, false }) do
    local tag = upFirst and " (release first)" or " (click first)"
    Load(true, upFirst)
    local b = W.bliz
    local p = b._points[1]
    check(b:GetParent() == W.ours and #b._points == 1 and p[1] == "BOTTOMLEFT" and p[2] == W.ours
        and p[3] == "TOPLEFT" and p[4] == -4 and p[5] == 0,
        "Blizzard's button sits on ours, just above it and 4 to the left" .. tag)
    check(b._w == 26 and b._h == 26, "at our button's size" .. tag)
    local i = b._insets
    check(i[1] == 4 and i[2] == -4 and i[3] == 26 and i[4] == -26, "its hit rect is our button's rect" .. tag)
    check(b._alpha == 0 and b._level == 27, "invisible, above ours" .. tag)
    check(b._motion == false and b._click == true, "clicks only: hover stays on ours" .. tag)
    check(Listening("GLOBAL_MOUSE_UP") == 1 and Listening("MODIFIER_STATE_CHANGED") == 0,
        "one release listener, no modifier listener without Free Move" .. tag)
    -- whatever mouse state a sync finds on Blizzard's button: clicks only
    b:EnableMouse(true)
    W.Sync(W.mp)
    check(b._motion == false and b._click == true, "a sync that finds its mouse on leaves clicks only" .. tag)

    Click("ours")
    check(Open() and W.pressOpens == 1 and W.addonOpens == 0, "the first press opens it from Blizzard's own button" .. tag)
    check(b._click == false, "while it is open, Blizzard's button takes no clicks" .. tag)

    Click("ours")
    check(not Open() and W.pressOpens == 1 and W.addonOpens == 0, "the second click closes it and does not reopen it" .. tag)
    check(b._click == true, "closed: Blizzard's button takes clicks again" .. tag)

    Click("ours")
    check(Open() and W.pressOpens == 2, "the third click opens it again" .. tag)
    Click("menu")
    check(Open() and b._click == false, "a click inside the menu keeps it" .. tag)
    Click("away")
    check(not Open() and b._click == true, "a click elsewhere closes it; clicks are back" .. tag)

    -- known limit: closed with no mouse event while the mouse rests on the button
    Click("ours")
    Escape()
    Click("ours")
    check(not Open(), "limit: after Escape with the mouse resting on it, one click does nothing" .. tag)
    Click("ours")
    check(Open(), "limit: the click after that opens" .. tag)
    Click("away")

    -- Escape with the mouse away: settled as the mouse comes back
    Click("ours")
    Hover("away")
    Escape()
    Click("ours")
    check(Open(), "Escape with the mouse away costs no click" .. tag)
    Click("away")

    -- a menu Blizzard opened itself (its gamepad radial): the mouse coming onto our
    -- button settles the click state, so a click there closes it
    Hover("away")
    W.blizz = true; b:OpenMenu(); W.blizz = false
    Click("ours")
    check(not Open() and W.addonOpens == 0, "a menu Blizzard opened itself: a click on our button closes it" .. tag)
    -- known limit: opened that way while the mouse rests on our button, the press closes and reopens it
    W.blizz = true; b:OpenMenu(); W.blizz = false
    Press(); Release()
    check(Open() and W.addonOpens == 0, "limit: opened by Blizzard with the mouse resting on it, a press closes and reopens it" .. tag)
    Click("ours")
    check(not Open(), "limit: the next click closes it" .. tag)

    check(W.addonOpens == 0 and W.forbidden == 0, "the menu is never opened from addon code: no blocked action" .. tag)
    check(rawget(W.ours, "HandlesGlobalMouseEvent") == nil and not W.claimed,
        "our button gives Blizzard's menu code no method to call" .. tag)

    -- our button hides: Blizzard's goes home, mouse off, nothing listens
    W.ours._shown = false
    W.Layout()
    p = b._points[1]
    check(b:GetParent() == HOME and p[1] == "TOPRIGHT" and p[2] == HOME and p[4] == -3 and p[5] == -2,
        "our button hidden: Blizzard's is back on its own parent and anchor" .. tag)
    check(b._w == 23 and b._h == 23 and b._insets[1] == 0 and b._insets[3] == 0 and b._alpha == 1,
        "with its size, hit rect and alpha" .. tag)
    check(b._motion == false and b._click == false, "and its mouse off, as the module keeps it" .. tag)
    check(Listening("GLOBAL_MOUSE_UP") == 0 and Listening("MODIFIER_STATE_CHANGED") == 0, "nothing listens" .. tag)
    W.ours._shown = true
    W.Layout()
    check(b:GetParent() == W.ours and b._click == true and Listening("GLOBAL_MOUSE_UP") == 1, "shown again: on again" .. tag)

    -- the tracking button hidden by its setting
    W.mp.hideTrackingButton = true
    W.Layout()
    check(b:GetParent() == HOME and Listening("GLOBAL_MOUSE_UP") == 0, "Hide Tracking Button: off" .. tag)
    W.mp.hideTrackingButton = false
    W.Layout()
end

-------------------------------------------------------------------------------
-- 3. Gamepad style with Free Move: Shift hands the press to our button
-------------------------------------------------------------------------------
do
    Load(true, true, true)
    local b = W.bliz
    check(Listening("MODIFIER_STATE_CHANGED") == 1 and #W.evFrames == 1, "Free Move: one frame hears the release and the modifier keys")
    local anchors = W.anchors
    W.shift = true
    Fire("MODIFIER_STATE_CHANGED")
    check(b._click == false, "Shift held: Blizzard's button steps aside")
    Hover("ours"); Press(); Release()
    check(not Open() and W.pressOpens == 0, "a Shift press on the button opens nothing (the drag takes it)")
    W.shift = false
    Fire("MODIFIER_STATE_CHANGED")
    check(b._click == true, "Shift released: it takes clicks again")
    check(W.anchors == anchors, "a modifier key only settles the click state: nothing is anchored again")
    -- Free Move turned off: the modifier listener goes
    W.mp.freeMoveBtns = false
    W.Layout()
    check(Listening("MODIFIER_STATE_CHANGED") == 0 and Listening("GLOBAL_MOUSE_UP") == 1, "Free Move off: only the release listener stays")
end

-------------------------------------------------------------------------------
-- 4. The style switched without a reload: our button's enter follows it
-------------------------------------------------------------------------------
do
    Load(true, true)
    W.gamepad = false
    Hover("away"); Hover("ours")
    check(W.bliz:GetParent() == HOME and Listening("GLOBAL_MOUSE_UP") == 0, "style off: the hotspot goes on the next enter")
    check(W.bliz._click == false and W.bliz._motion == false, "and Blizzard's button, back home, takes no mouse")
    Press(); Release()
    check(Open() and W.addonOpens == 1, "and our click opens the menu again")
    Click("ours")
    check(not Open() and W.addonOpens == 1, "with the second click closing it")
    W.gamepad = true
    Hover("away"); Hover("ours")
    check(W.bliz:GetParent() == W.ours and W.bliz._click == true, "style on: the hotspot comes on the next enter")
    Press(); Release()
    check(Open() and W.pressOpens == 1 and W.addonOpens == 1 and W.forbidden == 0, "and Blizzard's own button opens the menu")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_minimap_tracking_menu (" .. count .. " checks)")
