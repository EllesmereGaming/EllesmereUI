-- Stub harness: loads the popup file outside the game and drives the input
-- popup's colour swatch (opts.swatch): built on its first use, painted from the
-- caller's colour, a click handed to the caller with a repaint function, and
-- an open colour picker closed with the popup, before the caller's own
-- confirm or cancel runs.
--   lua .tools/tests/test_input_popup_swatch.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local SRC = ReadSource("EllesmereUI_Popups.lua")

-------------------------------------------------------------------------------
--  Game stubs: a frame answers the few calls the test reads back, takes any
--  other method call and reads nil for a field that was never set
-------------------------------------------------------------------------------
local T = { tips = 0, hides = 0, solid = {} }
local MT, SPECIAL = {}, {}
local function Obj(kind, parent)
    return setmetatable({ _kind = kind, _parent = parent, _scripts = {}, _hooks = {}, _shown = true, _text = "" }, MT)
end
local function Fire(self, name)
    local script = self._scripts[name]
    if script then script(self) end
    local hooks = self._hooks[name]
    if hooks then
        for i = 1, #hooks do hooks[i](self) end
    end
end
function SPECIAL.SetScript(self, name, fn) self._scripts[name] = fn end
function SPECIAL.GetScript(self, name) return self._scripts[name] end
function SPECIAL.HookScript(self, name, fn)
    local hooks = self._hooks[name] or {}
    self._hooks[name] = hooks
    hooks[#hooks + 1] = fn
end
function SPECIAL.Show(self)
    if not self._shown then
        self._shown = true
        Fire(self, "OnShow")
    end
end
function SPECIAL.Hide(self)
    if self._shown then
        self._shown = false
        Fire(self, "OnHide")
    end
end
function SPECIAL.SetShown(self, shown) if shown then self:Show() else self:Hide() end end
function SPECIAL.IsShown(self) return self._shown end
function SPECIAL.CreateTexture(self) return Obj("Texture", self) end
function SPECIAL.CreateFontString(self) return Obj("FontString", self) end
function SPECIAL.SetText(self, s) self._text = tostring(s) end
function SPECIAL.GetText(self) return self._text end
function SPECIAL.SetColorTexture(self, r, g, b, a) self._rgba = { r, g, b, a } end
function SPECIAL.SetPoint(self, ...) self._point = { ... } end
function SPECIAL.GetFrameLevel() return 5 end
function SPECIAL.GetWidth() return 270 end
function SPECIAL.GetHeight() return 28 end
function SPECIAL.GetStringWidth() return 40 end
function SPECIAL.GetEffectiveScale() return 1 end
function SPECIAL.GetScale() return 1 end
function SPECIAL.IsMouseOver() return false end
MT.__index = function(_, k)
    local fn = SPECIAL[k]
    if fn then return fn end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
end

UIParent = Obj("Frame")
function CreateFrame(kind, name, parent)
    local o = Obj(kind, parent)
    if name then _G[name] = o end
    return o
end
C_Timer = { After = function(_, fn) fn() end }
function InCombatLockdown() return false end
function GetPhysicalScreenSize() return 2560, 1440 end
function GetScreenWidth() return 1600 end
function GetTime() return 0 end
function IsShiftKeyDown() return false end
strlenutf8 = string.len

EllesmereUIDB = {}
EllesmereUI = {
    PanelPP = {
        Size = function(f, w, h) f._w, f._h = w, h end,
        Point = function(f, ...) f._point = { ... } end,
        Width = function() end,
        Height = function() end,
    },
    MakeFont = function(parent) return Obj("FontString", parent) end,
    MakeBorder = function(f) return Obj("Border", f) end,
    MakeRoundedBorder = function(f) return Obj("Border", f) end,
    RoundBody = function() end,
    SolidTex = function(parent, _, r, g, b, a)
        local t = Obj("Texture", parent)
        t._rgba = { r, g, b, a }
        T.solid[#T.solid + 1] = t
        return t
    end,
    lerp = function(a, b, t) return a + (b - a) * t end,
    ELLESMERE_GREEN = { r = 0.05, g = 0.82, b = 0.62 },
    BORDER_COLOR = { r = 1, g = 1, b = 1 },
    TEXT_DIM = { r = 1, g = 1, b = 1, a = 0.5 },
    EXPRESSWAY = "Fonts\\Expressway.ttf",
    L = function(s) return s end,
    RegisterEscapeClose = function() end,
    PadHint = function() end,
    PadFocus = function() end,
    PadCP = function() return false end,
    PadInUse = function() return false end,
    PadGamepadUI = function() return false end,
    PadCursorShown = function() return false end,
    ShowWidgetTooltip = function(anchor, text)
        T.tips, T.lastTip, T.tipAnchor = T.tips + 1, text, anchor
    end,
    HideWidgetTooltip = function() T.hides = T.hides + 1 end,
}
_G.EllesmereUI = EllesmereUI

assert(loadstring(SRC, "=EllesmereUI_Popups.lua"))("EllesmereUI", {})

-------------------------------------------------------------------------------
--  Scenarios
-------------------------------------------------------------------------------
-- 1. a popup with no swatch builds none, and confirms as it always did
local confirmed
EllesmereUI:ShowInputPopup({ title = "Plain", onConfirm = function(text) confirmed = text end })
local popup = EllesmereUI._inputPopup
assert(popup and popup._dimmer._shown, "the input popup did not show")
assert(popup._swatch == nil and popup._closePicker == nil, "a swatch was built for a popup that asked for none")
popup._editBox:SetText("abc")
popup._tryConfirm()
assert(confirmed == "abc" and not popup._dimmer._shown, "a plain popup did not confirm")

-- 2. a popup with a swatch: built once, left of the input, painted from the caller's colour
local color = { 0.2, 0.4, 0.6 }
local clicks, cancelled = {}, 0
local function Swatch()
    return {
        get = function() return color[1], color[2], color[3] end,
        onClick = function(button, repaint) clicks[#clicks + 1] = { button, repaint } end,
        tooltip = "Color",
    }
end
EllesmereUI:ShowInputPopup({ title = "Edit", initialText = "Raid", swatch = Swatch(),
    onConfirm = function(text) confirmed = text end, onCancel = function() cancelled = cancelled + 1 end })
local sw = popup._swatch
assert(sw and sw._kind == "Button" and sw._parent == popup and sw._shown, "no swatch on a popup that asked for one")
assert(sw._w == 20 and sw._h == 20, "the swatch is not the inline swatch size")
assert(sw._point[1] == "RIGHT" and sw._point[2] == popup._inputFrame and sw._point[3] == "LEFT" and sw._point[4] == -8,
    "the swatch is not left of the input")
local fill
for _, t in ipairs(T.solid) do
    if t._parent == sw then fill = t end
end
assert(fill and fill._rgba[1] == 0.2 and fill._rgba[2] == 0.4 and fill._rgba[3] == 0.6 and fill._rgba[4] == 1,
    "the swatch does not show the caller's colour")
assert(popup._editBox._text == "Raid")
-- a click is the caller's, with the swatch and a repaint function
sw._scripts.OnClick(sw)
assert(#clicks == 1 and clicks[1][1] == sw and type(clicks[1][2]) == "function", "the click did not reach the caller")
color = { 1, 0, 0 }
assert(fill._rgba[1] == 0.2, "the swatch repainted before it was asked to")
clicks[1][2]()
assert(fill._rgba[1] == 1 and fill._rgba[2] == 0 and fill._rgba[3] == 0, "repaint did not take the new colour")
-- its tooltip is ours, and goes when the pointer leaves or the swatch hides
sw._scripts.OnEnter(sw)
assert(T.tips == 1 and T.lastTip == "Color" and T.tipAnchor == sw, "no tooltip on the swatch")
sw._scripts.OnLeave(sw)
assert(T.hides == 1)
sw._scripts.OnLeave(sw)
assert(T.hides == 1, "a tooltip that was not shown was hidden")
sw._scripts.OnEnter(sw)
sw._scripts.OnHide(sw)
assert(T.hides == 2, "the tooltip outlived the swatch")
-- the info badge steps left of the swatch
assert(popup._info._point[2] == sw and popup._info._point[1] == "RIGHT" and popup._info._point[4] == -8)

-- 3. an open colour picker closes with the popup, before the caller's own callback
local order = {}
local picker = Obj("Frame")
picker:SetScript("OnHide", function() order[#order + 1] = "picker" end)
EllesmereUI._colorPickerPopup = picker
popup._editBox:SetText("Raid Team")
popup._tryConfirm()
assert(order[1] == "picker" and #order == 1 and not picker._shown, "a confirm left the colour picker open")
assert(confirmed == "Raid Team" and not popup._dimmer._shown)
-- an empty name keeps the popup, and the picker, open
picker._shown = true
order = {}
EllesmereUI:ShowInputPopup({ title = "Edit", initialText = "", swatch = Swatch(),
    onConfirm = function() order[#order + 1] = "confirm" end, onCancel = function() order[#order + 1] = "cancel" end })
assert(popup._swatch == sw, "a second swatch was built")
popup._tryConfirm()
assert(#order == 0 and picker._shown and popup._dimmer._shown, "a refused confirm closed the colour picker")
-- Escape: the picker's own cancel runs before the caller's
popup._editBox._scripts.OnEscapePressed(popup._editBox)
assert(order[1] == "picker" and order[2] == "cancel" and #order == 2, "the picker did not close before the cancel: "
    .. table.concat(order, ","))
-- a confirm: the picker closes before the callback
picker._shown = true
order = {}
EllesmereUI:ShowInputPopup({ title = "Edit", initialText = "Raid", swatch = Swatch(),
    onConfirm = function() order[#order + 1] = "confirm" end })
popup._tryConfirm()
assert(order[1] == "picker" and order[2] == "confirm" and #order == 2, "the picker did not close before the confirm: "
    .. table.concat(order, ","))
-- the Cancel button
picker._shown = true
order = {}
EllesmereUI:ShowInputPopup({ title = "Edit", initialText = "Raid", swatch = Swatch(),
    onCancel = function() order[#order + 1] = "cancel" end })
popup._cancelBtn._scripts.OnClick(popup._cancelBtn)
assert(order[1] == "picker" and order[2] == "cancel" and #order == 2)

-- 4. the next popup with no swatch: the swatch hides, the badge goes back beside the input, and
--    a colour picker open for something else is left alone
picker._shown = true
order = {}
EllesmereUI:ShowInputPopup({ title = "Plain again", infoTooltip = "About this", onConfirm = function() end })
assert(not sw._shown, "the swatch stayed on a popup that asked for none")
assert(popup._info._point[2] == popup._inputFrame, "the info badge kept its spot beside a hidden swatch")
popup._editBox:SetText("x")
popup._tryConfirm()
assert(picker._shown and #order == 0, "a popup with no swatch closed a colour picker")

-- 5. a colour the caller cannot give paints white, and a swatch with no click handler does nothing
EllesmereUI:ShowInputPopup({ title = "Edit", initialText = "Raid", swatch = { get = function() end } })
assert(sw._shown and fill._rgba[1] == 1 and fill._rgba[2] == 1 and fill._rgba[3] == 1)
sw._scripts.OnClick(sw)
sw._scripts.OnEnter(sw)
assert(T.tips == 2, "a swatch with no tooltip text showed one")

print("input popup swatch harness: ok")
