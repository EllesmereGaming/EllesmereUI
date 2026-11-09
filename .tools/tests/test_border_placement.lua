-- Run from the repository root: lua .tools/tests/test_border_placement.lua
-- EllesmereUI.BorderPlacement is ApplyBorderStyle's textured placement (edge,
-- reach and shift, pixel snap included), read by BorderReach and by the engine
-- aura tooltip's backdrop (SyncAuraTooltipSkin, PR #3210), which cannot be drawn
-- through ApplyBorderStyle. 1: on every built-in texture, size step, exact size,
-- offset, shift and scale normalization, it gives the edge and anchors the real
-- ApplyBorderStyle gives its backdrop; 2: BorderReach is that placement less the
-- texture's ink, nil where nothing is drawn outside; 3: the aura tooltip backdrop
-- takes its edge, anchors and fill insets from it, a solid border its pixel line,
-- None no edge, and the color and opacity the tooltip border resolves.
EUI_CLIENT_BLOCKED = false

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end
local function near(a, b) return a and b and math.abs(a - b) < 1e-9 end

-------------------------------------------------------------------------------
-- A frame stub that records its anchors and backdrop
-------------------------------------------------------------------------------
local UI_SCALE = 0.6   -- 1 UI unit is not a whole pixel: the snaps matter
local stub = function() end
local NewFrame
-- Widget methods (capitalized) not listed below do nothing; fields stay nil.
local M = setmetatable({}, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then return stub end
end })
function M:SetPoint(point, _, _, x, y) self.points[point] = { x, y } end
function M:SetBackdrop(info) self.backdrop = info end
function M:GetEffectiveScale() return self.es end
function M:GetScale() return UI_SCALE end
function M:GetFrameLevel() return self.level end
function M:GetWidth() return 120 end
function M:GetHeight() return 60 end
function M:GetSize() return 120, 60 end
function M:CreateTexture() return NewFrame(self.es) end
function M:CreateFontString() return NewFrame(self.es) end
function M:CreateMaskTexture() return NewFrame(self.es) end
local MT = { __index = M }
NewFrame = function(es) return setmetatable({ points = {}, es = es or UI_SCALE, level = 1 }, MT) end

local any = setmetatable({}, { __call = stub })
getmetatable(any).__index = function() return any end
setmetatable(_G, { __index = function() return any end })
UIParent = NewFrame(UI_SCALE)
-- A child takes its parent's effective scale (a normalized border's owner is scaled).
CreateFrame = function(_, _, parent) return NewFrame(parent and parent.es or UI_SCALE) end
GetPhysicalScreenSize = function() return 1920, 1080 end
issecretvalue = function() return false end
InCombatLockdown = function() return false end
hooksecurefunc = stub
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
EllesmereUI = {}
EllesmereUIDB = {}

assert(loadfile("EllesmereUI_PixelPerfect.lua"))("EllesmereUI", {})
local E, PP = EllesmereUI, EllesmereUI.PP
assert(E.ApplyBorderStyle and E.BorderPlacement and E.BorderReach, "EllesmereUI_PixelPerfect.lua did not load")
PP.mult = PP.perfect / UI_SCALE

-------------------------------------------------------------------------------
-- 1. BorderPlacement == ApplyBorderStyle's backdrop placement
-------------------------------------------------------------------------------
local TEX = {}
for _, entry in ipairs(E._builtinBorderTextures) do
    if E.ResolveBorderTexture(entry.key) then TEX[#TEX + 1] = entry.key end
end
check(#TEX >= 3, "too few built-in textures resolved: " .. #TEX)
local OFFSETS = { { nil, nil, nil, nil }, { 1.3, -0.4, 0.7, -1.1 }, { 0, 2, -2, 0 } }
local cases = 0
for _, tex in ipairs(TEX) do
    for step = 1, 4 do
        local key = E.BORDER_LABEL_OF_STEP[step]
        for _, edgePx in ipairs({ false, 3, 5 }) do
            for _, o in ipairs(OFFSETS) do
                for _, norm in ipairs({ false, true }) do
                    -- A module's own defaults, and the texture's global ones (no module key).
                    for _, ak in ipairs({ "blizzardSkin", false }) do
                        local addonKey, sizeKey = ak or nil, ak and key or nil
                        local owner = NewFrame(norm and UI_SCALE * 2 or UI_SCALE)
                        local px = edgePx or nil
                        E.ApplyBorderStyle(owner, step, 1, 1, 1, 1, tex, o[1], o[2], o[3], o[4],
                            addonKey, sizeKey, norm or nil, px)
                        local bd = E._bdBorderData[owner]
                        local tl, br = bd and bd.points.TOPLEFT, bd and bd.points.BOTTOMRIGHT
                        local ratio = norm and (UI_SCALE / (UI_SCALE * 2)) or nil
                        local edge, ox, oy, sx, sy = E.BorderPlacement(step, tex, o[1], o[2], o[3], o[4],
                            addonKey, sizeKey, px, ratio, bd and bd.es)
                        local tag = tex .. " step " .. step .. " px " .. tostring(px) .. " off " .. tostring(o[1])
                            .. (norm and " normalized" or "") .. (ak and "" or " global defaults")
                        check(tl and br and bd.backdrop, "ApplyBorderStyle drew no backdrop: " .. tag)
                        if tl and br and bd.backdrop then
                            check(near(bd.backdrop.edgeSize, edge), "edge differs: " .. tag)
                            check(near(tl[1], -ox + sx) and near(tl[2], oy + sy), "TOPLEFT differs: " .. tag)
                            check(near(br[1], ox + sx) and near(br[2], -oy + sy), "BOTTOMRIGHT differs: " .. tag)
                        end
                        cases = cases + 1
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- 2. BorderReach is the placement less the ink
-------------------------------------------------------------------------------
for _, tex in ipairs(TEX) do
    if tex ~= "shadow" then
        local edge, ox, oy, sx, sy = E.BorderPlacement(2, tex, 1.3, nil, 0.7, nil, "blizzardSkin", "normal")
        local ink = E._borderInk[tex] or { 0, 0, 0, 0 }
        local l, r, t, b = E.BorderReach(2, tex, 1.3, nil, 0.7, nil, "blizzardSkin", "normal")
        check(near(l, ox - sx - ink[1] * edge) and near(r, ox + sx - ink[2] * edge)
            and near(t, oy + sy - ink[3] * edge) and near(b, oy - sy - ink[4] * edge), "BorderReach differs: " .. tex)
    end
end
check(E.BorderReach(2, "solid") == nil, "BorderReach: solid draws inside")
check(E.BorderReach(0, TEX[1]) == nil, "BorderReach: size 0")
check(E.BorderReach(2, TEX[1], nil, nil, nil, nil, nil, nil, nil, nil, 0) == nil, "BorderReach: alpha 0")
check(E.BorderReach(2, "no-such-texture") == nil, "BorderReach: unresolvable texture")

-------------------------------------------------------------------------------
-- 3. The engine aura tooltip backdrop (SyncAuraTooltipSkin)
-------------------------------------------------------------------------------
local fh = assert(io.open("EllesmereUIBlizzardSkin/EUI_BlizzardSkin_TooltipSkin.lua", "rb"))
local SRC = fh:read("*a"):gsub("\r\n", "\n")
fh:close()
local function Cut(head)
    local s = assert(SRC:find(head, 1, true), head .. " not found")
    local _, e = SRC:find("\n    end\n", s, true)
    return SRC:sub(s, e)
end
local CHUNK = Cut("    local function _enabled()") .. Cut("    local function _resolveConfiguredBorder(")
    .. Cut("    function EllesmereUI.SyncAuraTooltipSkin()") .. "return EllesmereUI.SyncAuraTooltipSkin\n"
local sent
E._repaintTooltipPreview = stub
E.GetTooltipBg = function() return 0.1, 0.1, 0.1, 0.9 end
E.GetTooltipBorder = function() return 1, 1, 1, 0.18, 1 end
E.RESKIN = { BRD_ALPHA = 0.18 }
E.ELLESMERE_GREEN = { r = 0.1, g = 0.8, b = 0.4 }
AuraContainerInbound = { SetTooltipBackdrop = function(info) sent = info end, ResetTooltipStyle = stub }
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
UnitClass = function() return "Mage", "MAGE" end
local fn = assert(loadstring(CHUNK, "@TooltipSkin"))
local Sync = fn()

local function Run(db)
    EllesmereUIDB = db
    sent = nil
    Sync()
    return sent
end
local function Same4(t, a, b, c, d)
    return t and near(t.left, a) and near(t.right, b) and near(t.top, c) and near(t.bottom, d)
end

local tex = "pixels-textured"
local info = Run({ tooltipBorderTexture = tex, tooltipBorderThickness = "normal",
    tooltipBorderOffsetX = 1.3, tooltipBorderShiftX = 0.7, tooltipBorderShiftY = -1.6,
    tooltipBorderColorMode = "custom", tooltipBorderColor = { r = 0.2, g = 0.3, b = 0.4 }, tooltipBorderOpacity = 0.7 })
local edge, ox, oy, sx, sy = E.BorderPlacement(2, tex, 1.3, nil, 0.7, -1.6, "blizzardSkin", "normal")
check(sx ~= 0 and sy ~= 0, "aura tooltip: the case needs a shift on both axes")
check(info and info.backdropInfo.edgeFile == E.ResolveBorderTexture(tex), "aura tooltip: texture")
check(info and near(info.backdropInfo.edgeSize, edge), "aura tooltip: edge")
check(info and Same4(info.anchorOffsets, sx - ox, sx + ox, sy + oy, sy - oy), "aura tooltip: anchors")
check(info and Same4(info.backdropInfo.insets, ox - sx, ox + sx, oy + sy, oy - sy), "aura tooltip: fill insets")
check(info and info.borderColor.r == 0.2 and info.borderColor.a == 0.7, "aura tooltip: custom color and opacity")

-- An exact size scales the step's defaults, as on the game tooltip.
info = Run({ tooltipBorderTexture = tex, tooltipBorderThickness = "thin",
    tooltipBorderThicknessPx = E.BorderPxString(4, 1, tex) })
edge, ox, oy, sx, sy = E.BorderPlacement(1, tex, nil, nil, nil, nil, "blizzardSkin", "thin", 4)
check(info and near(info.backdropInfo.edgeSize, edge) and Same4(info.anchorOffsets, sx - ox, sx + ox, sy + oy, sy - oy),
    "aura tooltip: exact size")

-- Solid: the pixel line inside the tooltip.
info = Run({ tooltipBorderThickness = "heavy", tooltipBorderColorMode = "accent" })
check(info and info.backdropInfo.edgeFile == "Interface\\Buttons\\WHITE8X8", "aura tooltip: solid texture")
check(info and near(info.backdropInfo.edgeSize, 3 * PP.mult), "aura tooltip: solid edge in pixels")
check(info and Same4(info.anchorOffsets, 0, 0, 0, 0) and Same4(info.backdropInfo.insets, 0, 0, 0, 0),
    "aura tooltip: solid sits on the tooltip")
check(info and info.borderColor.g == 0.8 and info.borderColor.a == 0.5, "aura tooltip: accent color, its opacity")

-- Class color; untouched profile: white at the house opacity, one pixel.
info = Run({ tooltipBorderColorMode = "class" })
check(info and info.borderColor.b == 0.92, "aura tooltip: class color")
info = Run({})
check(info and near(info.backdropInfo.edgeSize, PP.mult) and info.borderColor.r == 1 and info.borderColor.a == 0.18,
    "aura tooltip: defaults")

-- None: no edge at all.
info = Run({ tooltipBorderThickness = "none" })
check(info and info.backdropInfo.edgeFile == nil and info.anchorOffsets == nil and info.borderColor == nil,
    "aura tooltip: None draws no edge")

if fails > 0 then error(fails .. " check(s) failed") end
print("test_border_placement: all checks passed (" .. cases .. " placement cases)")
