-- Run from the repository root with Lua 5.1:
-- lua .tools/test-cdm-keybind-style.lua
-- These mocks cover display lifecycle, not WoW's protected-frame engine.
local checks = 0
local function eq(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

-- Any event, frame, hook or timer introduced by the style module fails here.
CreateFrame = function() error("keybind styling must not create frames") end
hooksecurefunc = function() error("keybind styling must not install hooks") end
C_Timer = setmetatable({}, { __index = function() error("keybind styling must not use timers") end })
EllesmereUI = {
    ApplyIconTextFont = function(text, path, size)
        text:SetFont(path, size, "module-outline")
        text.shadow = "module-shadow"
    end,
    ResolveFontName = function(name) return "resolved/" .. name end,
    PrimeFontShadow = function(text, shadow) text.shadow = shadow end,
    SlugFlag = function(flag) return flag end,
}
local ns = {}
assert(loadfile("EllesmereUICooldownManager/EllesmereUICdmKeybindStyle.lua"))("CDM", ns)

local textures = {}
local function region()
    local r = { shown = false, points = {} }
    function r:ClearAllPoints() self.points = {} end
    function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function r:SetColorTexture(...) self.color = { ... } end
    function r:SetHeight(v) self.height = v end
    function r:SetWidth(v) self.width = v end
    function r:SetShown(v) self.shown = v end
    function r:Hide() self.shown = false end
    function r:Show() self.shown = true end
    function r:IsShown() return self.shown end
    return r
end
local parent = {}
function parent:CreateTexture(_, layer)
    local r = region(); r.layer = layer
    textures[#textures + 1] = r
    return r
end
local text = region()
function text:GetParent() return parent end
function text:SetFont(...) self.font = { ... } end
function text:SetJustifyH(v) self.justify = v end
function text:SetTextColor(...) self.color = { ... } end
function text:SetText(v) self.value = v end
function text:GetText() return self.value end
-- A read-only Blizzard icon: styling may anchor to it but cannot store fields.
local anchor = setmetatable({}, { __newindex = function() error("write to Blizzard icon") end })

local bd = { showKeybind = false, keybindBackgroundA = 1, keybindBorderA = 1 }
ns.StyleCDMKeybind(text, bd, anchor, 1, "cdm-font")
ns.RefreshCDMKeybindBadge(text, bd)
eq(#textures, 0, "disabled decorations allocate nothing")
eq(text.font, nil, "disabled keybind does no font work")

bd = { showKeybind = true, keybindAlign = "right" }
text:SetText("S-1"); text:Show()
ns.StyleCDMKeybind(text, bd, anchor, 0.5, "cdm-font")
eq(text.font[1], "cdm-font", "default font unchanged")
eq(text.font[2], 5, "font scale compensation")
eq(text.font[3], "module-outline", "default outline unchanged")
eq(text.color[4], 0.9, "default text opacity unchanged")
eq(text.points[1][1], "TOPRIGHT", "legacy right alignment")
eq(text.points[1][4], -1, "legacy mirrored X offset")
eq(text.points[1][5], -1, "scaled Y offset")
eq(#textures, 0, "default keybind has no badge allocation")

bd.keybindFont = "Skurri"; bd.keybindOutline = "NONE"; bd.keybindA = 0
ns.StyleCDMKeybind(text, bd, anchor, 1, "cdm-font")
eq(text.font[1], "resolved/Skurri", "per-bar font")
eq(text.font[3], "SLUG", "explicit no outline")
eq(text.shadow, false, "no inherited shadow with no outline")
eq(text.color[4], 0, "zero text alpha retained")
eq(#textures, 0, "font-only setting creates no decorations")
bd.keybindOutline = "THICKOUTLINE"
ns.StyleCDMKeybind(text, bd, anchor, 1, "cdm-font")
eq(text.font[3], "THICKOUTLINE, SLUG", "thick outline")

for _, point in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
    bd.keybindAnchor = point
    ns.StyleCDMKeybind(text, bd, anchor, 1, "cdm-font")
    eq(text.points[1][1], point, "anchor " .. point)
    eq(text.points[1][2], anchor, "anchor owner " .. point)
end
bd.keybindAnchor = "invalid"
ns.StyleCDMKeybind(text, bd, anchor, 1, "cdm-font")
eq(text.points[1][1], "TOPRIGHT", "invalid anchor falls back")

bd.keybindBackgroundA = 0.6; bd.keybindBorderA = 0.8
bd.keybindBorderSize = 2; bd.keybindPadding = 4
ns.StyleCDMKeybind(text, bd, anchor, 0.5, "cdm-font")
eq(#textures, 5, "one lazy badge")
eq(textures[1].shown, true, "background visible")
eq(textures[1].color[4], 0.6, "background alpha")
eq(textures[2].color[4], 0.8, "border alpha independent")
eq(textures[1].points[1][4], -2, "scaled badge padding")
eq(textures[2].height, 1, "scaled border thickness")
for i = 1, 100 do
    text:SetText(i % 2 == 0 and "1" or "CTRL-M4")
    ns.RefreshCDMKeybindBadge(text, bd)
end
eq(#textures, 5, "binding changes reuse textures")
eq(textures[2].height, 1, "binding refresh retains scale")
eq(textures[1].points[2][2], text, "badge follows changing text width")

text:Hide(); ns.RefreshCDMKeybindBadge(text, bd)
for i = 1, 5 do eq(textures[i].shown, false, "unbound icon hides texture " .. i) end
text:Show(); text:SetText(""); ns.RefreshCDMKeybindBadge(text, bd)
eq(textures[1].shown, false, "empty text has no badge")
text:SetText("2"); ns.RefreshCDMKeybindBadge(text, bd)
eq(textures[1].shown, true, "rebinding restores badge")

bd.keybindBackgroundA = 0
ns.RefreshCDMKeybindBadge(text, bd)
eq(textures[1].shown, false, "transparent background")
eq(textures[2].shown, true, "border remains independently visible")
bd.keybindBackgroundA = 0.4; bd.keybindBorderA = 0
ns.RefreshCDMKeybindBadge(text, bd)
eq(textures[1].shown, true, "background without border")
eq(textures[2].shown, false, "transparent border")
bd.keybindBorderA = 1; bd.keybindBorderSize = 0
ns.RefreshCDMKeybindBadge(text, bd)
eq(textures[2].shown, false, "zero border width")

bd = { showKeybind = true } -- reused icon in a default bar/profile
ns.StyleCDMKeybind(text, bd, anchor, 1, "other-cdm-font")
for i = 1, 5 do eq(textures[i].shown, false, "profile switch clears texture " .. i) end
eq(text.font[1], "other-cdm-font", "profile font restored")
eq(text.font[3], "module-outline", "profile outline restored")
eq(text.points[1][1], "TOPLEFT", "profile anchor restored")
bd.showKeybind = false
ns.StyleCDMKeybind(text, bd, anchor, 1, "other-cdm-font")
eq(text.shown, false, "disable hides keybind")
eq(#textures, 5, "profile switch creates no extra textures")
ns.RefreshCDMKeybindBadge(text, nil)
eq(textures[1].shown, false, "missing bar data clears badge")
print("PASS: " .. checks .. " keybind style checks")
