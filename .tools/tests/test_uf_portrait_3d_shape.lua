-- Stub harness: a detached 3D portrait in a shape (website bug #231). A
-- PlayerModel is a child frame of the portrait backdrop, so it draws over
-- every texture of the backdrop whatever their draw layers, and it takes no
-- mask. With 3D Portrait Below Border on (portrait3dBelowBorder, off by
-- default) the shape ring rests on a frame above the model and the model
-- sits inside the ring; off, nothing changes: the model fills the backdrop
-- over the ring and no holder is built.
-- Loads the Unit Frames portrait file, the cast icon overlay of the cast bar
-- file and the options preview's shape pass, with the frame levels, anchors,
-- parents and masks modelled; a region draws over a frame only when its own
-- frame sits at a higher level.
--   lua .tools/tests/test_uf_portrait_3d_shape.lua        (from the repository root)
-- Each source can be pointed elsewhere through UF3D_PORTRAIT, UF3D_CASTBAR
-- and UF3D_OPTIONS.
local ROOT = arg and arg[1] or "."

local function ReadSource(path)
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local SRC = ReadSource(UF3D_PORTRAIT or (ROOT .. "/EllesmereUIUnitFrames/EUI_UnitFrames_Portrait.lua"))
local CAST_SRC = ReadSource(UF3D_CASTBAR or (ROOT .. "/EllesmereUIUnitFrames/EUI_UnitFrames_Castbar.lua"))
local OPT_SRC = ReadSource(UF3D_OPTIONS or (ROOT .. "/EllesmereUIOptions/EUI_UnitFrames_Options.lua"))

-- Every widget method the sources call: any other answers nothing.
local METHODS = {}
for _, s in ipairs({ SRC, CAST_SRC, OPT_SRC }) do
    for name in s:gmatch(":([%a_][%w_]*)%s*%(") do METHODS[name] = true end
end

local checks = 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then error(msg, 2) end
end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

-------------------------------------------------------------------------------
--  Widgets: frames and regions with levels, sizes, anchors, parents, masks
-------------------------------------------------------------------------------
local created = 0
local MakeObj
local W = {}
function W.Show(self) self._shown = true end
function W.Hide(self) self._shown = false end
function W.SetShown(self, v) self._shown = v and true or false end
function W.IsShown(self) return self._shown end
function W.IsObjectType(self, t) return self._kind == t end
function W.CreateTexture(self, _, layer, _, sub) return MakeObj("Texture", self, layer, sub) end
function W.CreateMaskTexture(self) return MakeObj("MaskTexture", self) end
function W.GetParent(self) return self._parent end
function W.SetParent(self, p)
    if self._parent and self._parent._kids then self._parent._kids[self] = nil end
    self._parent = p
    if p and p._kids and self._isFrame then p._kids[self] = true end
end
function W.GetFrameLevel(self) return self._level end
-- Children keep their offset when a parent's level moves.
function W.SetFrameLevel(self, lvl)
    local d = lvl - self._level
    self._level = lvl
    if d ~= 0 then
        for kid in pairs(self._kids) do W.SetFrameLevel(kid, kid._level + d) end
    end
end
function W.GetFrameStrata(self) return self._strata end
function W.SetFrameStrata(self, s) self._strata = s end
function W.SetSize(self, w, h) self._w, self._h = w, h end
function W.GetWidth(self)
    if self._w then return self._w end
    if self._allOf then return self._allOf:GetWidth() end
    return 0
end
function W.GetHeight(self)
    if self._h then return self._h end
    if self._allOf then return self._allOf:GetHeight() end
    return 0
end
function W.ClearAllPoints(self) self._pts = {}; self._allOf = nil end
function W.SetPoint(self, p, rel, rp, x, y) self._pts[p] = { rel = rel, rp = rp, x = x or 0, y = y or 0 } end
function W.SetAllPoints(self, rel) self._pts = {}; self._allOf = rel or self._parent end
function W.SetScript(self, name, fn) self._scripts[name] = fn end
function W.GetScript(self, name) return self._scripts[name] end
function W.HookScript(self, name, fn) self._hooks[name] = fn end
function W.AddMaskTexture(self, m) self._masks[m] = true end
function W.RemoveMaskTexture(self, m) self._masks[m] = nil end
function W.GetAlpha() return 1 end

function MakeObj(kind, parent, layer, sub)
    local isFrame = kind ~= "Texture" and kind ~= "MaskTexture"
    local o = {
        _kind = kind, _isFrame = isFrame, _shown = true, _scripts = {}, _hooks = {}, _pts = {},
        _masks = {}, _kids = {}, _strata = parent and parent._strata or "MEDIUM", _layer = layer, _sub = sub,
        _level = isFrame and ((parent and parent._level or 0) + 1) or nil,
    }
    setmetatable(o, { __index = function(_, k)
        if type(k) ~= "string" or k:sub(1, 1) == "_" then return nil end
        if W[k] then return W[k] end
        if METHODS[k] then return function() end end
        return nil
    end })
    if isFrame then created = created + 1 end
    W.SetParent(o, parent)
    return o
end

-- The engine on a resize: frames laid over the resized one hear OnSizeChanged.
local everyFrame = {}
local function Resize(obj, w, h)
    obj._w, obj._h = w, h
    for f in pairs(everyFrame) do
        if f._allOf == obj and f._scripts.OnSizeChanged then f._scripts.OnSizeChanged(f, w, h) end
    end
end

-------------------------------------------------------------------------------
--  Game API and EllesmereUI stubs
-------------------------------------------------------------------------------
issecretvalue = function() return false end
C_Secrets = { ShouldUnitIdentityBeSecret = function() return false end }
CreateFrame = function(kind, _, parent)
    local f = MakeObj(kind, parent)
    everyFrame[f] = true
    return f
end
UnitExists = function() return true end
UnitIsConnected = function() return true end
UnitIsVisible = function() return true end
UnitGUID = function() return "Creature-1" end
UnitIsPlayer = function() return false end
UnitClass = function() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = 0.2, g = 0.8, b = 1 } }
GetRaidTargetIndex = function() return nil end
SetPortraitTexture = function() end

local function Point(obj, p, rel, rp, x, y) obj:SetPoint(p, rel, rp, x, y) end
local PP = { Point = Point, Size = function(obj, w, h) obj._w, obj._h = w, h end, mult = 1 }
local MEDIA = "media\\portraits\\"
EllesmereUI = {
    _Pool = { CreateFrame = function(...) return CreateFrame(...) end },
    PP = PP,
    CLASS_ICON_SPRITE_COORDS = { MAGE = { 0, 0.25, 0, 0.25 } },
    SHAPE_MASKS = { square = MEDIA .. "square_mask", circle = MEDIA .. "circle_mask", pixelsCircle = MEDIA .. "circle_mask" },
    SHAPE_BORDERS = { square = MEDIA .. "square_border", circle = MEDIA .. "circle_border", pixelsCircle = MEDIA .. "pixels_circle_border" },
    SHAPE_INSETS = { square = 17, circle = 17, pixelsCircle = 17 },
    UIScaledAlpha = function(a) return a end,
    OnUIAlphaChanged = function() end,
    GetClassColor = function() return { r = 1, g = 1, b = 1 } end,
}

local profile = {}
local db = { profile = profile }
local ns = {
    _internals = {
        frames = {}, dbSetters = {},
        UnsnapTex = function() end,
        GetSettingsForUnit = function(unit) return profile[unit] end,
        UnitToSettingsKey = function(unit) return unit end,
    },
    Engine = { SetPainter = function() end, ElementOn = function() return true end },
    UF_Blizz = function() return false end,
    UF_DarkThemeOn = function() return false end,
}

assert(loadstring(SRC, "=EUI_UnitFrames_Portrait.lua"))("EllesmereUIUnitFrames", ns)
for _, set in ipairs(ns._internals.dbSetters) do set(db) end
local I = ns._internals
local CreatePortrait = assert(I.CreatePortrait)
local ApplyShape = assert(I.ApplyDetachedPortraitShape)

-- The cast icon overlay of Show Icon on Portrait, cut from the cast bar file.
local function Cut(src, from, to, what)
    local a = src:find(from, 1, true)
    assert(a, what .. ": start anchor not found")
    local b = src:find(to, a, true)
    assert(b, what .. ": end anchor not found")
    return src:sub(a, b - 1)
end
local castCut = Cut(CAST_SRC, "local function MoveDecoration(", "-- Show Icon on Portrait: lays the cast icon", "cast icon overlay")
local CastIconPortraitOverlay = assert(loadstring(
    "local POOL = ...\n" .. castCut .. "\nreturn CastIconPortraitOverlay", "=castbar cut"))(EllesmereUI._Pool)

-- The options preview's shape pass, cut from the options file.
local optCut = Cut(OPT_SRC, "local function ApplyPreviewPortraitShape(", "-- Portrait art style dropdown values", "preview shape pass")
local ApplyPreviewPortraitShape = assert(loadstring(
    "local db, PP, PORTRAIT_MASKS_P, PORTRAIT_BORDERS_P, MASK_INSETS, ns = ...\n" .. optCut
    .. "\nreturn ApplyPreviewPortraitShape", "=options cut"))(
    db, PP, EllesmereUI.SHAPE_MASKS, EllesmereUI.SHAPE_BORDERS, EllesmereUI.SHAPE_INSETS, ns)

-------------------------------------------------------------------------------
--  Geometry of the shipped art, read from the TGA files (128 texels each):
--  the square mask opens at texel 10, the circle mask at 13, the square
--  ring's solid band ends at texel 17; the mask sits 1 px inside the backdrop
--  at a ring Size of 1 and above, the ring art grows 7 - Size px per side.
-------------------------------------------------------------------------------
local function MaskOpen(len, texels) return 1 + texels / 128 * (len - 2) end
local function RingInner(len, size) local e = 7 - size; return -e + 17 / 128 * (len + 2 * e) end

-- The model's insets from its anchors: TOPLEFT (x, -y) and BOTTOMRIGHT (-x, y)
-- on the host, or 0 when it fills the host.
local function ModelInsets(model, host)
    if model._allOf == host then return 0, 0 end
    local tl, br = model._pts.TOPLEFT, model._pts.BOTTOMRIGHT
    assert(tl and br and tl.rel == host and br.rel == host, "the model is not anchored to its host")
    assert(near(tl.x, -br.x) and near(tl.y, -br.y), "the model is not centred on its host")
    return tl.x, -tl.y
end
local function RingOverModel(ring, model)
    return ring:GetParent()._level > model._level
end

local function NewFrame(unit, settings)
    profile[unit] = settings
    local frame = CreateFrame("Button")
    frame._euiUnit, frame._euiBaseUnit = unit, unit
    frame.Health = CreateFrame("StatusBar", nil, frame)
    frame.Portrait = CreatePortrait(frame, "right", 46, unit)
    return frame, frame.Portrait.backdrop
end

-------------------------------------------------------------------------------
-- 0. the option off (the default): a detached 3D portrait in a Square keeps
--    the old layout, the model filling the backdrop over the ring
-------------------------------------------------------------------------------
local s0 = { portraitStyle = "detached", portraitMode = "3d", detachedPortraitShape = "square" }
local _, bd0 = NewFrame("target", s0)
check(bd0._3d:IsShown() and bd0._shapeBorderTex:IsShown(), "off: the model or the ring does not show")
check(bd0._shapeBorderTex:GetParent() == bd0 and bd0._ringHome == nil, "off: the ring left the backdrop")
check(bd0._ringLift == nil, "off: a ring holder was built")
check(ModelInsets(bd0._3d, bd0) == 0, "off: the model no longer fills the backdrop")
Resize(bd0, 76, 76)
check(ModelInsets(bd0._3d, bd0) == 0, "off: a resize laid the model inside the ring")
s0.portrait3dBelowBorder = false
I.ApplyDetachedPortraitShape(bd0, s0, "target")
check(bd0._ringLift == nil and ModelInsets(bd0._3d, bd0) == 0, "a stored false reads as on")

-------------------------------------------------------------------------------
-- 1. the option on, a detached 3D portrait in a Square: the ring over the
--    model, the model inside the ring (the reported case)
-------------------------------------------------------------------------------
local s1 = { portraitStyle = "detached", portraitMode = "3d", detachedPortraitShape = "square",
    portrait3dBelowBorder = true }
local frame, bd = NewFrame("target", s1)
local model, ring = bd._3d, bd._shapeBorderTex
check(frame.Portrait == model and model:IsShown(), "3D mode did not show the model")
check(model._parent == bd and model._level == bd._level + 1, "the model is not a child frame one level over the backdrop")
check(ring and ring:IsShown(), "the shape ring does not show")
check(RingOverModel(ring, model), "the shape ring draws under the 3D model (ring frame level "
    .. ring:GetParent()._level .. ", model " .. model._level .. ")")
check(ring._masks[bd._shapeMask], "the lifted ring lost the shape mask")
check(ring:GetParent()._parent == bd, "the ring's frame is not a child of the backdrop")
local L = bd:GetWidth()
check(near(L, 56), "the detached backdrop is not 56 px (46 + 10)")
local ix, iy = ModelInsets(model, bd)
check(ix > 0 and iy > 0, "the 3D model fills the backdrop past the ring")
check(ix >= MaskOpen(L, 10) - 1e-6, "the model reaches past the square's opening")
check(ix <= RingInner(L, 7) + 1e-6, "the model stops short of the ring's inner edge")
check(near(ix, RingInner(L, 7) - 1) and near(iy, ix), "the model edge is not one pixel under the ring's solid band")
-- No mask on the model: it has none to take.
check(next(model._masks) == nil, "a mask was added to the model")

-- 2. the backdrop resizes outside the shape pass (portrait Size, class power):
--    the model follows the new size
Resize(bd, 76, 76)
ix = ModelInsets(model, bd)
check(near(ix, RingInner(76, 7) - 1), "the model was not laid out again for the new backdrop size")
Resize(bd, 56, 56)

-- 3. the cast icon on the portrait takes the ring over the icon and hands it
--    back over the model when the icon hides
local before = ring:GetParent()
CastIconPortraitOverlay(bd, true)
check(ring:GetParent() == bd._castIconOverlay and bd._castIconOverlay._level == bd._level + 3,
    "the cast icon overlay did not take the ring")
-- A shape pass while the icon shows leaves the ring on the overlay.
ApplyShape(bd, s1, "target")
check(ring:GetParent() == bd._castIconOverlay, "a shape pass took the ring off the cast icon overlay")
CastIconPortraitOverlay(bd, false)
check(ring:GetParent() == before and RingOverModel(ring, model),
    "the ring went back under the 3D model when the cast icon hid")

-- 4. repeated passes build nothing new (one holder per backdrop)
local count = created
for _ = 1, 3 do ApplyShape(bd, s1, "target") end
check(created == count, "a shape pass built new frames")

-- 5. Size 1: the solid band is clipped away; the model stops at the opening
s1.detachedPortraitBorderSize = 1
ApplyShape(bd, s1, "target")
ix = ModelInsets(model, bd)
check(ix >= MaskOpen(L, 10) - 1e-6 and near(ix, 1 + 12 / 128 * (L - 2)), "Size 1 laid the model past the opening")
s1.detachedPortraitBorderSize = nil

-- 6. Shape None: no ring, the model fills the backdrop, and a resize keeps it so
s1.detachedPortraitShape = "none"
ApplyShape(bd, s1, "target")
check(not ring:IsShown(), "Shape None kept the ring")
check(ModelInsets(model, bd) == 0, "Shape None did not give the model the whole backdrop")
Resize(bd, 70, 70)
check(ModelInsets(model, bd) == 0, "a resize under Shape None laid the model inside a ring")
Resize(bd, 56, 56)

-- 7. back to a shape, then Attached: the model fills the backdrop again
s1.detachedPortraitShape = "square"
ApplyShape(bd, s1, "target")
check(RingOverModel(ring, model) and ModelInsets(model, bd) > 0, "the shape did not come back over the model")
s1.portraitStyle = "attached"
ApplyShape(bd, s1, "target")
check(ModelInsets(model, bd) == 0 and not ring:IsShown(), "an attached 3D portrait kept the ring layout")
Resize(bd, 60, 60)
check(ModelInsets(model, bd) == 0, "a resize of an attached portrait laid the model inside a ring")
Resize(bd, 56, 56)

-------------------------------------------------------------------------------
-- 8. 2D in a shape: the ring stays on the backdrop over the masked art, as
--    before; a model built for Mirror Portrait's lookup stays full size
-------------------------------------------------------------------------------
local s2 = { portraitStyle = "detached", portraitMode = "2d", detachedPortraitShape = "circle" }
local frame2, bd2 = NewFrame("focus", s2)
local ring2 = bd2._shapeBorderTex
check(frame2.Portrait == bd2._2d and ring2:GetParent() == bd2, "a 2D portrait's ring left the backdrop")
check(bd2._ringLift == nil, "a 2D portrait built a ring holder")
bd2._ensureModel3D()
ApplyShape(bd2, s2, "focus")
check(ModelInsets(bd2._3d, bd2) == 0 and ring2:GetParent() == bd2, "a hidden mirror-lookup model was moved")
CastIconPortraitOverlay(bd2, true)
CastIconPortraitOverlay(bd2, false)
check(ring2:GetParent() == bd2, "the cast icon overlay did not hand a 2D ring back to the backdrop")

-- 9. the same frame switched 3D -> 2D: the ring goes back to the backdrop
s1.portraitStyle, s1.portraitMode = "detached", "2d"
ApplyShape(bd, s1, "target")
check(ring:GetParent() == bd and bd._ringHome == nil, "leaving 3D kept the ring on its holder")
check(ring._masks[bd._shapeMask], "the ring lost its mask on the way back")
CastIconPortraitOverlay(bd, true)
CastIconPortraitOverlay(bd, false)
check(ring:GetParent() == bd, "the cast icon overlay put a 2D ring back on the holder")
s1.portraitMode = "3d"
ApplyShape(bd, s1, "target")
check(RingOverModel(ring, model), "3D again did not lift the ring")

-- 9b. the option turned off on the same frame: the old layout comes back,
--     a resize and the cast icon overlay included; on again lifts the ring
s1.portrait3dBelowBorder = nil
ApplyShape(bd, s1, "target")
check(ring:GetParent() == bd and bd._ringHome == nil and not RingOverModel(ring, model),
    "option off: the ring stayed over the model")
check(ModelInsets(model, bd) == 0, "option off: the model does not fill the backdrop")
Resize(bd, 70, 70)
check(ModelInsets(model, bd) == 0, "option off: a resize laid the model inside the ring")
Resize(bd, 56, 56)
CastIconPortraitOverlay(bd, true)
CastIconPortraitOverlay(bd, false)
check(ring:GetParent() == bd, "option off: the cast icon overlay put the ring on the holder")
s1.portrait3dBelowBorder = true
ApplyShape(bd, s1, "target")
check(RingOverModel(ring, model) and ModelInsets(model, bd) > 0, "option on again did not lift the ring")

-------------------------------------------------------------------------------
-- 10. Pixels Circle (its ring is not masked): inside the ring as well
-------------------------------------------------------------------------------
local s3 = { portraitStyle = "detached", portraitMode = "3d", detachedPortraitShape = "pixelsCircle",
    portrait3dBelowBorder = true }
local _, bd3 = NewFrame("player", s3)
check(RingOverModel(bd3._shapeBorderTex, bd3._3d), "Pixels Circle: the ring draws under the model")
ix = ModelInsets(bd3._3d, bd3)
check(near(ix, 4 + 9 / 128 * (56 - 8) - 1), "Pixels Circle: the model is not one pixel under its ring")

-- 11. the frame level of a detached backdrop moves (frame +15 on every
--     pass): the holder keeps its place over the model
W.SetFrameLevel(bd, bd._level + 7)
check(RingOverModel(ring, model), "the ring fell under the model when the backdrop's level moved")
ApplyShape(bd, s1, "target")
check(ring:GetParent()._level == bd._level + 2, "the ring holder is not two levels over the backdrop")

-------------------------------------------------------------------------------
-- 12. the options preview's shape pass: the same layout on the preview frame
-------------------------------------------------------------------------------
local pFrame = CreateFrame("Frame")
pFrame._w, pFrame._h = 56, 56
pFrame._previewTex = pFrame:CreateTexture(nil, "ARTWORK")
pFrame._previewBg = pFrame:CreateTexture(nil, "BACKGROUND")
pFrame._previewModel = CreateFrame("PlayerModel", nil, pFrame)
pFrame._previewMode = "3d"
local ps = { portraitStyle = "detached", portraitMode = "3d", detachedPortraitShape = "square",
    portrait3dBelowBorder = true }
ApplyPreviewPortraitShape(pFrame, ps)
check(RingOverModel(pFrame._shapeBorderTex, pFrame._previewModel), "the preview's ring draws under its 3D model")
ix = ModelInsets(pFrame._previewModel, pFrame)
check(near(ix, RingInner(56, 7) - 1), "the preview's model does not sit inside its ring")
pFrame._previewMode = "2d"
ApplyPreviewPortraitShape(pFrame, ps)
check(pFrame._shapeBorderTex:GetParent() == pFrame and ModelInsets(pFrame._previewModel, pFrame) == 0,
    "the preview's 2D portrait did not get its ring and model back")
-- the option off: the preview's 3D portrait keeps the old layout too
pFrame._previewMode = "3d"
ApplyPreviewPortraitShape(pFrame, ps)
check(RingOverModel(pFrame._shapeBorderTex, pFrame._previewModel), "the preview did not follow the option on")
ps.portrait3dBelowBorder = nil
ApplyPreviewPortraitShape(pFrame, ps)
check(pFrame._shapeBorderTex:GetParent() == pFrame and ModelInsets(pFrame._previewModel, pFrame) == 0,
    "the preview's 3D portrait left the old layout with the option off")

-------------------------------------------------------------------------------
-- 13. the toggle itself: a row of the Portrait Mode cog's detached rows, off
--     stored as nil (so an untouched profile carries no key)
-------------------------------------------------------------------------------
local SHARED_SRC = ReadSource(UF3D_SHARED or (ROOT .. "/EllesmereUIOptions/UnitFrames_Options/SharedAppearance_Options.lua"))
local rowAt = SHARED_SRC:find('label="3D Portrait Below Border"', 1, true)
check(rowAt, "the Portrait Mode cog has no 3D Portrait Below Border row")
local detachedAt = SHARED_SRC:find('if SVal("portraitStyle", "attached") == "detached" then', 1, true)
local cogAt = SHARED_SRC:find('title = "Portrait Settings"', 1, true)
check(detachedAt and cogAt and detachedAt < rowAt and rowAt < cogAt, "the row is not among the cog's detached rows")
check(SHARED_SRC:find('get=function() return SVal("portrait3dBelowBorder", false) end', rowAt, true),
    "the row does not read portrait3dBelowBorder as off by default")
check(SHARED_SRC:find('SSet("portrait3dBelowBorder", v or nil)', rowAt, true), "the row does not store off as nil")

print(("test_uf_portrait_3d_shape: %d checks passed"):format(checks))
