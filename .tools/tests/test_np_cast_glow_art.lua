-- Stub harness: Nameplates, the Modern WoW Glow style on a cast bar (EUI_Nameplates_Cast.lua).
-- On an icon that style is the action bar proc art. It is square art: stretched to a cast bar it
-- reached over both ends, across the spell name and the timer. On a nameplate cast bar the style
-- now draws Blizzard's own nameplate cast bar art (Blizzard_NamePlateCastingBar.xml / .lua):
--   Important Cast Glow    ui-hud-nameplates-importantcast: 3 above and below the bar and, on the
--                          art retail ships (264 x 16), 26 past the left end and 25 past the
--                          right, Blizzard's own offsets; on the older art WoW Forever ships
--                          (248 x 16), 18 and 17. It pulses between half and full alpha over two
--                          seconds (Blizzard's own goes down to none)
--   Cast Targets You Glow  ui-hud-nameplates-targetedbyenemy (218 x 19): 4 past every edge; steady
-- Blizzard draws each art at one bar size. Stretched whole onto our bars its ends stood off the
-- bar and its lines lay over it, and the slice margins the game offers did not slice this art in
-- game. So the art is cut here into eight pieces on one frame per glow overlay, from the sheet
-- file and its coordinates: the four corners keep their own size, the two lines stretch along the
-- bar and the two end pieces up it, and the frame sits on the bar's edges at any bar size.
-- Every other style still goes to the glow engine, unchanged. A colour tints the art as it tints
-- the other art styles; the Default colour is the art's own. A client without the art keeps the
-- engine's Modern WoW Glow.
-- The art shows above everything else on the plate, borders included: its frame sits on the
-- strata the plate's custom borders and texts use (the cast bar's own while Casts In Front of
-- Nameplates lifts the bar), above their levels. And a spell icon standing beside the bar counts
-- as part of the bar while it is not Full Sized and its Y offset is within 2 either way: the art
-- then goes around the icon and the bar together.
-- Driven here: the real cast glow functions, and the glow engine's real flat-settings reader and
-- style list, over stubbed frames, textures and animations.
--   lua .tools/tests/test_np_cast_glow_art.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local CAST = ReadSource("EllesmereUINameplates/EUI_Nameplates_Cast.lua")
local GLOWS = ReadSource("EllesmereUI_Glows.lua")
local LAYOUT = ReadSource("EllesmereUINameplates/EUI_Nameplates_Layout.lua")
local MAIN = ReadSource("EllesmereUINameplates/EllesmereUINameplates.lua")

-------------------------------------------------------------------------------
-- The glow engine: its real style names, flat keys and spec reader; starts and
-- stops are counted
-------------------------------------------------------------------------------
local G = { STYLES = {} }
do
    local block = assert(GLOWS:match("local GLOW_STYLES = (%b{})"), "the style list was not found")
    for name in block:gmatch('{ name = "([^"]+)"') do G.STYLES[#G.STYLES + 1] = { name = name } end
    check(G.STYLES[1].name == "Pixel Glow" and #G.STYLES >= 7, "the style list was not read (" .. #G.STYLES .. ")")
    assert(loadstring("local G, EllesmereUI = ...\n" ..
        Cut(GLOWS, "    function G.ResolveColor(mode, r, g, b, defR, defG, defB)", "    -- Legacy sites store a class-color boolean", "ResolveColor") ..
        Cut(GLOWS, "    local _flatKeys = {}", "    -- Options previews sit in the panel", "the flat schema"), "=EllesmereUI_Glows.lua"))(
        G, { GetClassColor = function() return { r = 0.5, g = 0.5, b = 0.5 } end })
end
local MODERN
for i, e in ipairs(G.STYLES) do if e.name == "Modern WoW Glow" then MODERN = i end end
local starts, stops = {}, {}
function G.StartSpecGlow(ov, spec, w, h, host)
    starts[#starts + 1] = { ov = ov, style = spec.style, r = spec.r, g = spec.g, b = spec.b, w = w, h = h, host = host }
    ov._euiGlowActive = true
end
function G.StopAllGlows(ov) stops[#stops + 1] = ov end

-- The nameplate module's style list: its positions in the shared list.
local toShared = {}
for n in assert(LAYOUT:match("ns%.NP_GLOW_VIEW = EllesmereUI%.Glows%.MakeView%((%b{})"), "the nameplate glow view was not found"):gmatch("%d+") do
    toShared[#toShared + 1] = tonumber(n)
end
local NP_MODERN, NP_PIXEL
for i, s in ipairs(toShared) do
    if s == MODERN then NP_MODERN = i end
    if s == 1 then NP_PIXEL = i end
end
check(NP_MODERN ~= nil and NP_PIXEL == 1, "the nameplate style list holds no Modern WoW Glow")

-------------------------------------------------------------------------------
-- Frames, textures, animations. A texture has no slice-margin methods: the art
-- must not lean on the engine's slicing.
-------------------------------------------------------------------------------
local built = { textures = 0, groups = 0, frames = 0 }
local function NewTexture()
    built.textures = built.textures + 1
    local t = { shown = true, points = {}, tints = 0 }
    function t:SetTexture(file) self.file = file end
    function t:SetTexCoord(l, r, tp, b) self.coords = { l, r, tp, b } end
    function t:SetSize(w, h) self.w, self.h = w, h end
    function t:SetSnapToPixelGrid(v) self.snap = v end
    function t:SetTexelSnappingBias(v) self.bias = v end
    function t:SetPoint(point, rel, relPoint, x, y) self.points[point] = { rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 } end
    function t:SetDesaturated(v) self.desat = v end
    function t:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b; self.tints = self.tints + 1 end
    return t
end
local function CreateFrame(_, _, parent)
    built.frames = built.frames + 1
    local f = { parent = parent, shown = true, textures = {}, points = {}, children = {}, writes = 0,
                strata = parent and parent.strata or "LOW" }
    if parent and parent.children then parent.children[#parent.children + 1] = f end
    function f:SetAllPoints(rel) self.allPoints = rel end
    function f:SetPoint(point, rel, relPoint, x, y)
        self.points[point] = { rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
        self.writes = self.writes + 1
    end
    function f:SetFrameLevel(l) self.level = l; self.writes = self.writes + 1 end
    function f:GetFrameLevel() return self.level end
    -- A strata change drops a frame's level, as in the game.
    function f:SetFrameStrata(s) self.strata = s; self.level = 0; self.writes = self.writes + 1 end
    function f:GetFrameStrata() return self.strata end
    function f:EnableMouse(v) self.mouse = v end
    function f:CreateTexture(_, layer)
        local t = NewTexture()
        t.layer = layer
        self.textures[#self.textures + 1] = t
        return t
    end
    function f:CreateAnimationGroup()
        built.groups = built.groups + 1
        local ag = { anims = {}, playing = false, plays = 0 }
        function ag:SetLooping(v) self.looping = v end
        function ag:CreateAnimation(kind)
            local a = { kind = kind }
            function a:SetOrder(v) self.order = v end
            function a:SetDuration(v) self.duration = v end
            function a:SetFromAlpha(v) self.from = v end
            function a:SetToAlpha(v) self.to = v end
            self.anims[#self.anims + 1] = a
            return a
        end
        function ag:Play() self.playing = true; self.plays = self.plays + 1 end
        function ag:Stop() self.playing = false end
        self.group = ag
        return ag
    end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetAlpha(a) self.alpha = a end
    function f:SetAlphaFromBoolean(v) self.alphaFrom = v; self.alpha = v and 1 or 0 end
    return f
end

-- The settings: the module's real defaults for the two glows, and a profile over them.
local defaults = {}
for line in MAIN:gmatch("[^\n]+") do
    -- "    <key> = <value>,  -- note": the value runs to the line's last comma
    local code = line:gsub("%s*%-%-.*$", "")
    local key, value = code:match("^    (importantCastGlow%w*) = (.+),%s*$")
    if not key then key, value = code:match("^    (castTargetGlow%w*) = (.+),%s*$") end
    if not key then key, value = code:match("^    (castIcon%w*) = (.+),%s*$") end
    if not key then key, value = code:match("^    (showCastIcon) = (.+),%s*$") end
    if key then defaults[key] = assert(loadstring("return " .. value))() end
end
check(defaults.importantCastGlowStyle == 1 and type(defaults.importantCastGlowColor) == "table" and defaults.castTargetGlow == false,
    "the module's cast glow defaults were not read")
check(defaults.showCastIcon == true and defaults.castIconFullSize == false and defaults.castIconOnRight == false
    and defaults.castIconScale == 1 and defaults.castIconOffsetX == 0 and defaults.castIconOffsetY == 0,
    "the module's spell icon defaults were not read")
local profile = {}
local targetsMe = true
local classic = false

-- The game's atlas records of the two arts, as each client holds them (name -> size in
-- pixels, sheet file, sheet coordinates). Retail's sheet is 512 x 128, WoW Forever's 256 x 256.
local IMP, TGT = "ui-hud-nameplates-importantcast", "ui-hud-nameplates-targetedbyenemy"
local function Info(w, h, sheetW, sheetH, left, top)
    return { width = w, height = h, file = 7241122, leftTexCoord = left / sheetW, rightTexCoord = (left + w) / sheetW,
             topTexCoord = top / sheetH, bottomTexCoord = (top + h) / sheetH }
end
local RETAIL = { [IMP] = Info(264, 16, 512, 128, 1, 63), [TGT] = Info(218, 19, 512, 128, 1, 81) }
local FOREVER = { [IMP] = Info(248, 16, 256, 256, 1, 84), [TGT] = Info(218, 19, 256, 256, 1, 63) }

-- A fresh load of the cast glows on a client whose atlases are `atlases` (nil for an art the
-- client lacks). Returns the plate methods, the module namespace the load wrote into, and a
-- counter of the atlas questions asked.
local function Load(atlases)
    local NF, ns, asks = {}, { NP_TO_SHARED_GLOW = toShared }, { n = 0 }
    -- the layout file's spell icon getters, over the same settings
    local function Setting(key)
        local v = profile[key]
        if v == nil then v = defaults[key] end
        return v
    end
    ns.GetShowCastIcon = function() return Setting("showCastIcon") end
    ns.GetCastIconFullSize = function() return Setting("castIconFullSize") end
    ns.GetCastIconOnRight = function() return Setting("castIconOnRight") end
    ns.GetCastIconScale = function() return Setting("castIconScale") end
    ns.NP_Classic = function() return classic end
    assert(loadstring(
        "local EllesmereUI, CreateFrame, defaults, p, ns, NameplateFrame, PANDEMIC_GLOW_STYLES, C_Texture, C_Spell, PlayerIsSpellTarget, C_CurveUtil = ...\n" ..
        Cut(CAST, "local function EnsureCastGlowOverlay(self, field, levelOffset)", "-- A cast glow setting changed (its options row", "the cast glows"),
        "=EUI_Nameplates_Cast.lua"))(
        { Glows = G }, CreateFrame, defaults, profile, ns, NF, toShared,
        { GetAtlasInfo = function(name) asks.n = asks.n + 1; return atlases[name] end },
        { IsSpellImportant = function() return true end },
        function() return targetsMe end,
        { EvaluateColorValueFromBoolean = function(v, a, b) if v then return a end return b end })
    return NF, ns, asks
end
local NameplateFrame, liveNS, atlasAsks = Load(RETAIL)
check(liveNS.NP_CAST_ART_STYLE == MODERN, "the module does not tell the options which shared style is drawn as the nameplate art")

local function Plate(methods, w, h)
    local cast = { level = 10, children = {}, strata = "LOW" }
    function cast:GetFrameLevel() return self.level end
    function cast:GetFrameStrata() return self.strata end
    function cast:GetWidth() return w or 150 end
    function cast:GetHeight() return h or 16 end
    return setmetatable({ cast = cast, unit = "nameplate1", _castImportant = true }, { __index = methods or NameplateFrame })
end
-- A clean profile. Without `icon` the spell icon is off, so the art is the bar's alone
-- (sections 1 to 6); section 8 turns it on.
local function Reset(icon)
    for k in pairs(profile) do profile[k] = nil end
    if not icon then profile.showCastIcon = false end
    starts, stops = {}, {}
end
local function Point(region, point) return region.points[point] or {} end

-- A piece's cut of the art, in the art's own pixels to a hundredth: "x0-x1,y0-y1".
local function Px(n) return ("%.2f"):format(n) end
local function CutOf(tex, info)
    local c = tex.coords
    if not c then return "none" end
    local function px(v, a, b, n) return Px((v - a) / (b - a) * n) end
    return px(c[1], info.leftTexCoord, info.rightTexCoord, info.width) .. "-" .. px(c[2], info.leftTexCoord, info.rightTexCoord, info.width) .. "," ..
        px(c[3], info.topTexCoord, info.bottomTexCoord, info.height) .. "-" .. px(c[4], info.topTexCoord, info.bottomTexCoord, info.height)
end
-- The eight pieces of an art frame against what the art asks for: its width and height in
-- pixels, corner width capL / capR and line height capT / capB. Returns the first fault.
local function PiecesFault(f, info, capL, capT, capR, capB)
    local p = f._pieces
    if type(p) ~= "table" or #p ~= 8 or #f.textures ~= 8 then return "the art is not eight pieces" end
    local W, H = info.width, info.height
    local function Box(x0, x1, y0, y1) return Px(x0) .. "-" .. Px(x1) .. "," .. Px(y0) .. "-" .. Px(y1) end
    local want = {
        Box(0, capL, 0, capT), Box(capL, W - capR, 0, capT), Box(W - capR, W, 0, capT),
        Box(0, capL, capT, H - capB), Box(W - capR, W, capT, H - capB),
        Box(0, capL, H - capB, H), Box(capL, W - capR, H - capB, H), Box(W - capR, W, H - capB, H),
    }
    for i = 1, 8 do
        local t = p[i]
        if t.file ~= info.file then return "piece " .. i .. " is not drawn from the art's sheet" end
        if CutOf(t, info) ~= want[i] then return "piece " .. i .. " cuts " .. CutOf(t, info) .. " of the art, not " .. want[i] end
        if t.snap ~= false or t.bias ~= 0 then return "piece " .. i .. " snaps to the pixel grid (the pieces would part)" end
        if t.layer ~= "OVERLAY" then return "piece " .. i .. " is not on the overlay layer" end
    end
    -- the four corners keep their own size at the frame's corners
    local corners = { { 1, "TOPLEFT", capL, capT }, { 3, "TOPRIGHT", capR, capT }, { 6, "BOTTOMLEFT", capL, capB }, { 8, "BOTTOMRIGHT", capR, capB } }
    for _, c in ipairs(corners) do
        local t, pt = p[c[1]], Point(p[c[1]], c[2])
        if t.w ~= c[3] or t.h ~= c[4] then return "corner " .. c[1] .. " is " .. tostring(t.w) .. " x " .. tostring(t.h) .. ", not its own " .. c[3] .. " x " .. c[4] end
        if pt.rel ~= f or pt.relPoint ~= c[2] or pt.x ~= 0 or pt.y ~= 0 then return "corner " .. c[1] .. " is not at the frame's " .. c[2] end
    end
    -- the lines and the end pieces span between the corners, and are given no size of their own
    local spans = { { 2, 1, "TOPRIGHT", 3, "BOTTOMLEFT" }, { 7, 6, "TOPRIGHT", 8, "BOTTOMLEFT" }, { 4, 1, "BOTTOMLEFT", 6, "TOPRIGHT" }, { 5, 3, "BOTTOMLEFT", 8, "TOPRIGHT" } }
    for _, s in ipairs(spans) do
        local t = p[s[1]]
        local a, b = Point(t, "TOPLEFT"), Point(t, "BOTTOMRIGHT")
        if a.rel ~= p[s[2]] or a.relPoint ~= s[3] or b.rel ~= p[s[4]] or b.relPoint ~= s[5] or a.x ~= 0 or a.y ~= 0 or b.x ~= 0 or b.y ~= 0 then
            return "piece " .. s[1] .. " does not span between pieces " .. s[2] .. " and " .. s[4]
        end
        if t.w ~= nil or t.h ~= nil then return "piece " .. s[1] .. " has a fixed size (it must stretch)" end
    end
    return nil
end

-------------------------------------------------------------------------------
-- 1. Important Cast Glow on Modern WoW Glow: Blizzard's important cast art
-------------------------------------------------------------------------------
do
    Reset()
    profile.importantCastGlowStyle = NP_MODERN
    local plate = Plate()
    plate:UpdateImportantCastGlow()
    local ov = plate._importantCastOverlay
    check(ov ~= nil and ov.parent == plate.cast and ov.allPoints == plate.cast and ov.level == 15, "the important glow's overlay is not on the cast bar, five levels up")
    check(#starts == 0, "Modern WoW Glow on a cast bar still starts the engine's glow (the action bar art)")
    local f = ov.children[1]
    check(#ov.children == 1 and f ~= nil and #ov.textures == 0, "the overlay does not hold the one art frame")
    if f then
        check(f.parent == ov and f.strata == "MEDIUM" and f.level == 950, "the art frame is not on the overlay, on the plate's top layer (" .. tostring(f.strata) .. " " .. tostring(f.level) .. ")")
        local tl, br = Point(f, "TOPLEFT"), Point(f, "BOTTOMRIGHT")
        check(tl.rel == ov and tl.relPoint == "TOPLEFT" and tl.x == -26 and tl.y == 3, "the art's top left is not 26 past the left end and 3 above the bar")
        check(br.rel == ov and br.relPoint == "BOTTOMRIGHT" and br.x == 25 and br.y == -3, "the art's bottom right is not 25 past the right end and 3 below the bar")
        -- cut into its own pieces: corners 32 wide and 3 tall (the flare and the frame's end,
        -- the line), which keep their size while the stretches between them follow the bar
        local fault = PiecesFault(f, RETAIL[IMP], 32, 3, 32, 3)
        check(fault == nil, tostring(fault))
        check(f.shown == true, "the art is not shown")
        -- the pulse, on the art's frame: half to full alpha over a second and back, looping
        local ag = f.group
        check(ag ~= nil and ag.looping == "REPEAT" and #ag.anims == 2, "the important cast art has no looping two-step pulse")
        if ag and #ag.anims == 2 then
            local up, down = ag.anims[1], ag.anims[2]
            check(up.kind == "Alpha" and up.order == 1 and up.duration == 1 and up.from == 0.5 and up.to == 1, "the pulse does not rise from half alpha to full over a second first")
            check(down.kind == "Alpha" and down.order == 2 and down.duration == 1 and down.from == 1 and down.to == 0.5, "the pulse does not fall back to half alpha over a second after")
            check(ag.playing == true and ag.plays == 1, "the pulse is not playing")
        end
        -- the colour setting tints every piece, as it tints the other art styles (the default: red)
        local c = defaults.importantCastGlowColor
        local tinted = 0
        for _, t in ipairs(f.textures) do if t.desat == true and t.r == c.r and t.g == c.g and t.b == c.b then tinted = tinted + 1 end end
        check(tinted == 8, "a custom colour tints " .. tinted .. " of the art's 8 pieces")
    end
    -- the secret "important" flag still only drives the overlay's alpha
    check(ov.shown == true and ov.alphaFrom == true, "the overlay is not shown through the important flag")
    plate._castImportant = false
    plate:UpdateImportantCastGlow()
    check(ov.alphaFrom == false, "a cast that is not important keeps the overlay visible")
    plate._castImportant = true

    -- the next cast: nothing is built or repainted again, and the pulse is not restarted
    local texBefore, groupsBefore, framesBefore = built.textures, built.groups, built.frames
    local tex = f and f.textures[5]
    local tints = tex and tex.tints
    plate:UpdateImportantCastGlow()
    plate:UpdateImportantCastGlow()
    check(built.textures == texBefore and built.groups == groupsBefore and built.frames == framesBefore, "a new cast builds the art again")
    check(tex and tex.tints == tints, "a new cast repaints an unchanged colour")
    check(f and f.group.plays == 1, "a new cast restarts a running pulse")
    check(#stops == 0 and #starts == 0, "a new cast touches the glow engine")

    -- the Default colour: the art's own colours, on every piece
    profile.importantCastGlowColorMode = "default"
    plate:UpdateImportantCastGlow()
    local own = 0
    for _, t in ipairs(f and f.textures or {}) do if t.desat == false and t.r == 1 and t.g == 1 and t.b == 1 then own = own + 1 end end
    check(own == 8, "the Default colour shows the art's own colours on " .. own .. " of its 8 pieces")
    profile.importantCastGlowColorMode = "custom"
    profile.importantCastGlowColor = { r = 0.1, g = 0.9, b = 0.3 }
    plate:UpdateImportantCastGlow()
    check(tex and tex.desat == true and tex.r == 0.1 and tex.g == 0.9 and tex.b == 0.3, "a new custom colour does not reach the art")
    -- from one custom colour to another (the art stays tinted throughout)
    profile.importantCastGlowColor = { r = 0.7, g = 0.2, b = 0.9 }
    plate:UpdateImportantCastGlow()
    check(tex and tex.r == 0.7 and tex.g == 0.2 and tex.b == 0.9, "a second custom colour does not reach the art")

    -- the cast ends: art hidden, pulse stopped, overlay parked; the next cast brings both back
    plate:ClearImportantCastGlow()
    check(f and f.shown == false and f.group.playing == false, "a finished cast leaves the art shown or its pulse running")
    check(ov.shown == false and ov.alpha == 0 and plate._importantGlowActive == false, "a finished cast does not park the overlay")
    plate:UpdateImportantCastGlow()
    check(f and f.shown == true and f.group.playing == true and built.textures == texBefore, "the next cast does not show the same art again")

    -- a bar of another size takes the same reach and the same corners: nothing follows the
    -- bar's size but the stretches between the corners
    Reset()
    profile.importantCastGlowStyle = NP_MODERN
    local wide = Plate(nil, 320, 24)
    wide:UpdateImportantCastGlow()
    local wf = wide._importantCastOverlay.children[1]
    check(wf and Point(wf, "TOPLEFT").x == -26 and Point(wf, "BOTTOMRIGHT").x == 25 and PiecesFault(wf, RETAIL[IMP], 32, 3, 32, 3) == nil,
        "a larger bar changes how far the art reaches or the size of its corners")
end

-------------------------------------------------------------------------------
-- 2. Cast Targets You Glow on Modern WoW Glow: Blizzard's targeted art, steady
-------------------------------------------------------------------------------
do
    Reset()
    profile.importantCastGlow = false
    profile.castTargetGlow = true
    profile.castTargetGlowStyle = NP_MODERN
    local plate = Plate()
    plate:UpdateImportantCastGlow()
    plate:UpdateCastTargetGlow()
    local ov = plate._castTargetOverlay
    check(ov ~= nil and ov.level == 16, "the targeted glow's overlay is not six levels above the cast bar")
    local f = ov and ov.children[1]
    check(f ~= nil and #starts == 0, "the targeted glow on Modern WoW Glow still starts the engine's glow")
    if f then
        local tl, br = Point(f, "TOPLEFT"), Point(f, "BOTTOMRIGHT")
        check(tl.x == -4 and tl.y == 4 and br.x == 4 and br.y == -4, "the targeted art does not reach 4 past every edge of the bar")
        -- its corners are 9 wide and its glowing line 8 tall
        local fault = PiecesFault(f, RETAIL[TGT], 9, 8, 9, 8)
        check(fault == nil, "the targeted art: " .. tostring(fault))
        check(f.group == nil, "the targeted art pulses (Blizzard's is steady)")
        local c = defaults.castTargetGlowColor
        local t = f.textures[1]
        check(t and t.desat == true and t.r == c.r and t.g == c.g and t.b == c.b, "the targeted art does not take its colour")
    end
    check(ov and ov.alphaFrom == true, "the targeted overlay is not shown through the targets-you flag")
    targetsMe = false
    plate:UpdateCastTargetGlow()
    check(ov and ov.alphaFrom == false, "a cast at someone else keeps the targeted overlay visible")
    targetsMe = true
    plate:ClearCastTargetGlow()
    check(f and f.shown == false and ov.shown == false, "a finished cast leaves the targeted art shown")
end

-------------------------------------------------------------------------------
-- 3. every other style still goes to the glow engine, as before
-------------------------------------------------------------------------------
do
    for np, shared in ipairs(toShared) do
        if shared ~= MODERN then
            Reset()
            profile.importantCastGlowStyle = np
            local plate = Plate()
            plate:UpdateImportantCastGlow()
            local s = starts[1]
            check(#starts == 1 and s.style == shared and s.host == "bar" and s.w == 150 and s.h == 16 and s.ov == plate._importantCastOverlay,
                G.STYLES[shared].name .. " does not start the engine's glow on the bar as before")
            check(#plate._importantCastOverlay.children == 0, G.STYLES[shared].name .. " builds the nameplate art")
        end
    end
end

-------------------------------------------------------------------------------
-- 4. switching the style while a cast shows
-------------------------------------------------------------------------------
do
    Reset()
    profile.importantCastGlowStyle = NP_PIXEL
    local plate = Plate()
    plate:UpdateImportantCastGlow()
    local ov = plate._importantCastOverlay
    check(#starts == 1 and #stops == 0, "Pixel Glow does not start the engine once")
    -- to Modern WoW Glow: the engine's glow stops, the art shows
    profile.importantCastGlowStyle = NP_MODERN
    plate:UpdateImportantCastGlow()
    local f = ov.children[1]
    check(#stops == 1 and stops[1] == ov, "switching to Modern WoW Glow leaves the engine's glow running (" .. #stops .. " stops)")
    check(f ~= nil and f.shown == true and #starts == 1, "switching to Modern WoW Glow does not show the art")
    plate:UpdateImportantCastGlow()
    check(#stops == 1, "the engine's glow is stopped again on every cast")
    -- back to Pixel Glow: the art goes, the engine starts again
    profile.importantCastGlowStyle = NP_PIXEL
    plate:UpdateImportantCastGlow()
    check(f and f.shown == false and f.group.playing == false, "switching away from Modern WoW Glow leaves the art up")
    check(#starts == 2, "switching back to Pixel Glow does not start the engine's glow")
end

-------------------------------------------------------------------------------
-- 5. a client without the art keeps the engine's Modern WoW Glow
-------------------------------------------------------------------------------
do
    Reset()
    profile.importantCastGlowStyle = NP_MODERN
    check(atlasAsks.n == 2, "the client was asked for the art " .. atlasAsks.n .. " times so far (once per art)")
    local NF2, _, asks = Load({})
    local plate = Plate(NF2)
    plate:UpdateImportantCastGlow()
    plate:UpdateImportantCastGlow()
    plate:UpdateImportantCastGlow()
    check(#starts == 3 and starts[1].style == MODERN and starts[1].host == "bar", "without the art the engine's Modern WoW Glow is not used")
    check(#plate._importantCastOverlay.children == 0, "without the art its frame is still built")
    check(asks.n == 1, "the client is asked for a missing art on every cast (" .. asks.n .. ")")

    -- an atlas record that names no sheet file cannot be cut: the engine's glow again
    Reset()
    profile.importantCastGlowStyle = NP_MODERN
    local noFile = Info(264, 16, 512, 128, 1, 63)
    noFile.file = nil
    local NF5 = Load({ [IMP] = noFile })
    local bare = Plate(NF5)
    bare:UpdateImportantCastGlow()
    check(#starts == 1 and #bare._importantCastOverlay.children == 0, "an art with no sheet file is not left to the engine's glow")
end

-------------------------------------------------------------------------------
-- 6. the older important cast art (WoW Forever): shorter end flares
-------------------------------------------------------------------------------
do
    Reset()
    profile.importantCastGlowStyle = NP_MODERN
    profile.castTargetGlow = true
    profile.castTargetGlowStyle = NP_MODERN
    local NF3 = Load(FOREVER)
    local plate = Plate(NF3)
    plate:UpdateImportantCastGlow()
    local f = plate._importantCastOverlay.children[1]
    check(f ~= nil and #starts == 0, "the older art is not drawn")
    if f then
        local tl, br = Point(f, "TOPLEFT"), Point(f, "BOTTOMRIGHT")
        check(tl.x == -18 and tl.y == 3 and br.x == 17 and br.y == -3, "the older art does not reach 18 and 17 past the bar's ends (" .. tostring(tl.x) .. ", " .. tostring(br.x) .. ")")
        local fault = PiecesFault(f, FOREVER[IMP], 24, 3, 24, 3)
        check(fault == nil, "the older art: " .. tostring(fault))
        check(f.group ~= nil and f.group.playing == true, "the older art does not pulse")
    end
    -- the targeted art is the same on both clients (its sheet coordinates are not)
    plate._castImportant = false
    plate:UpdateCastTargetGlow()
    local tf = plate._castTargetOverlay.children[1]
    check(tf and Point(tf, "TOPLEFT").x == -4 and PiecesFault(tf, FOREVER[TGT], 9, 8, 9, 8) == nil, "the targeted art differs on the older client")

    -- the two revisions are told apart by their proportions: a record of the older art that
    -- reports half its pixels (a high-resolution sheet) is still the older art
    Reset()
    profile.importantCastGlowStyle = NP_MODERN
    local half = Info(248, 16, 256, 256, 1, 84)
    half.width, half.height = 124, 8
    local NF6 = Load({ [IMP] = half })
    local hp = Plate(NF6)
    hp:UpdateImportantCastGlow()
    local hf = hp._importantCastOverlay.children[1]
    check(hf and Point(hf, "TOPLEFT").x == -18 and Point(hf, "BOTTOMRIGHT").x == 17, "the older art is not recognized by its proportions")
    check(hf and PiecesFault(hf, FOREVER[IMP], 24, 3, 24, 3) == nil, "the older art's cut follows the reported size instead of its own pixels")

    -- an art of other proportions takes retail's numbers
    local NF4 = Load({ [IMP] = Info(300, 16, 512, 128, 1, 63) })
    local other = Plate(NF4)
    other:UpdateImportantCastGlow()
    local of = other._importantCastOverlay.children[1]
    check(of and Point(of, "TOPLEFT").x == -26 and Point(of, "BOTTOMRIGHT").x == 25 and of.textures[1].w == 32,
        "an art of other proportions does not take retail's reach")
end

-------------------------------------------------------------------------------
-- 7. the art's seat: above everything else on the plate, borders included
-------------------------------------------------------------------------------
do
    Reset()
    profile.importantCastGlowStyle = NP_MODERN
    profile.castTargetGlow = true
    profile.castTargetGlowStyle = NP_MODERN
    local plate = Plate()
    plate:UpdateImportantCastGlow()
    plate:UpdateCastTargetGlow()
    local f, tf = plate._importantCastOverlay.children[1], plate._castTargetOverlay.children[1]
    -- the plate's custom borders and texts sit on MEDIUM, the texts at 900 and the name marker at 901
    check(f.strata == "MEDIUM" and f.level == 950 and tf.strata == "MEDIUM" and tf.level == 950,
        "an art is not on the strata of the plate's borders and texts, above their levels")
    check(f.level > 901, "the art is not above the plate's text tier")
    -- the overlays themselves stay where the engine glows need them
    check(plate._importantCastOverlay.level == 15 and plate._importantCastOverlay.strata == "LOW", "the overlay left the cast bar's own layer")
    -- the next casts write nothing while nothing moved
    local w, tw = f.writes, tf.writes
    plate:UpdateImportantCastGlow()
    plate:UpdateCastTargetGlow()
    plate:UpdateImportantCastGlow()
    check(f.writes == w and tf.writes == tw, "a new cast seats an art that has not moved again")
    -- the cast bar's own strata change takes its children along (the game resets them): the next cast seats the art again
    f.strata, f.level = "LOW", 16
    plate:UpdateImportantCastGlow()
    check(f.strata == "MEDIUM" and f.level == 950, "an art the game dropped back to the bar's layer is not seated again by the next cast")
    -- Casts In Front of Nameplates lifts the bar: the art follows onto the bar's strata, at once
    plate._castOverlayLifted, plate.cast.strata = true, "HIGH"
    f.strata, f.level, tf.strata, tf.level = "HIGH", 16, "HIGH", 17
    liveNS.NP_PlaceCastGlowArt(plate)
    check(f.strata == "HIGH" and f.level == 950 and tf.strata == "HIGH" and tf.level == 950, "a lifted cast bar's art is not on the bar's strata, on top")
    -- each art keeps its own reach when it is seated again
    check(Point(f, "TOPLEFT").x == -26 and Point(f, "BOTTOMRIGHT").x == 25 and Point(tf, "TOPLEFT").x == -4 and Point(tf, "BOTTOMRIGHT").x == 4,
        "seating the arts again gave one the other's reach")
    -- and lowered again
    plate._castOverlayLifted, plate.cast.strata = nil, "LOW"
    f.strata, f.level = "LOW", 16
    liveNS.NP_PlaceCastGlowArt(plate)
    check(f.strata == "MEDIUM" and f.level == 950, "a lowered cast bar's art is not back on the plate's top layer")
    -- an art that is not showing is left alone, and a plate with no overlays is fine
    plate:ClearImportantCastGlow()
    f.strata, f.level = "LOW", 16
    w = f.writes
    liveNS.NP_PlaceCastGlowArt(plate)
    check(f.writes == w, "an art that is not showing was seated")
    liveNS.NP_PlaceCastGlowArt(Plate())
    check(true, "a plate with no glow overlays")
end

-------------------------------------------------------------------------------
-- 7b. Casts In Front of Nameplates, the real file: lifting and lowering the bar
--     seats a showing art again
-------------------------------------------------------------------------------
do
    Reset()
    profile.importantCastGlowStyle = NP_MODERN
    local plate = Plate()
    -- The game: a frame's strata change takes its children along and drops their levels.
    local function Sink(frame, strata)
        for _, c in ipairs(frame.children or {}) do
            c.strata, c.level = strata, 0
            Sink(c, strata)
        end
    end
    function plate.cast:SetParent(parent) self.parent = parent end
    function plate.cast:GetParent() return self.parent end
    function plate.cast:SetFrameStrata(s) self.strata = s; Sink(self, s) end
    function plate:GetEffectiveScale() return 1 end
    function plate:GetFrameStrata() return "LOW" end
    plate.cast.parent = plate
    local asks = 0
    local ons = { db = { profile = { castOverlayEnabled = false } } }
    function ons.NP_PlaceCastGlowArt(pl) asks = asks + 1; return liveNS.NP_PlaceCastGlowArt(pl) end
    function ons.ApplyCastIconBorder() end
    local chunk = assert(loadstring(ReadSource("EllesmereUINameplates/EllesmereUINameplates_CastOverlay.lua"), "=EllesmereUINameplates_CastOverlay.lua"))
    setfenv(chunk, setmetatable({
        UIParent = {},
        CreateFrame = function(...)
            local lift = CreateFrame(...)
            function lift:SetIgnoreParentScale() end
            function lift:SetSize() end
            function lift:SetScale(s) self.scale = s end
            return lift
        end,
    }, { __index = _G }))
    chunk("EllesmereUINameplates", ons)
    check(type(ons.RefreshCastOverlay) == "function", "the Casts In Front of Nameplates file did not load")

    plate:UpdateImportantCastGlow()
    local f = plate._importantCastOverlay.children[1]
    check(f.strata == "MEDIUM" and f.level == 950, "the art is not seated before the lift")
    ons.RefreshCastOverlay(plate)
    check(plate._castOverlayLifted == nil and f.strata == "MEDIUM" and f.level == 950 and asks == 0, "a pass with the setting off moved the art or asked for its seat")
    ons.db.profile.castOverlayEnabled = true
    ons.RefreshCastOverlay(plate)
    check(plate._castOverlayLifted == true and plate.cast.strata == "HIGH" and plate.cast.parent ~= plate, "the bar was not lifted")
    check(f.strata == "HIGH" and f.level == 950, "lifting the bar leaves a showing art off the top of the lifted bar (" .. tostring(f.strata) .. " / " .. tostring(f.level) .. ")")
    check(asks == 1, "the lift asked for the art's seat " .. asks .. " times")
    local w = f.writes
    ons.RefreshCastOverlay(plate)
    check(f.writes == w and asks == 1, "a pass over a bar that is lifted already seated the art again")
    ons.db.profile.castOverlayEnabled = false
    ons.RefreshCastOverlay(plate)
    check(plate._castOverlayLifted == nil and plate.cast.strata == "LOW" and plate.cast.parent == plate, "the bar was not lowered")
    check(f.strata == "MEDIUM" and f.level == 950, "lowering the bar leaves a showing art under the plate's borders (" .. tostring(f.strata) .. " / " .. tostring(f.level) .. ")")
    check(asks == 2, "the lowering asked for the art's seat " .. (asks - 1) .. " times")
    -- an art that is not showing is left where the bar's move put it, and seated by its next cast
    plate:ClearImportantCastGlow()
    ons.db.profile.castOverlayEnabled = true
    ons.RefreshCastOverlay(plate)
    check(f.strata == "HIGH" and f.level == 0, "an art that is not showing was seated by the lift")
    plate:UpdateImportantCastGlow()
    check(f.strata == "HIGH" and f.level == 950, "the next cast on a lifted bar does not seat its art")
end

-------------------------------------------------------------------------------
-- 8. the spell icon as part of the bar: not Full Sized, Y offset within 2 either way
-------------------------------------------------------------------------------
do
    -- The art frame's reach past the bar: left, top, right, bottom.
    local function Reach(f)
        local tl, br = Point(f, "TOPLEFT"), Point(f, "BOTTOMRIGHT")
        return -tl.x .. " " .. tl.y .. " " .. br.x .. " " .. -br.y
    end
    local function Important(set, w, h)
        Reset(true)
        profile.importantCastGlowStyle = NP_MODERN
        for k, v in pairs(set or {}) do profile[k] = v end
        local plate = Plate(nil, w, h)
        plate:UpdateImportantCastGlow()
        return Reach(plate._importantCastOverlay.children[1]), plate
    end
    local function Is(set, want, what, w, h)
        local got = Important(set, w, h)
        check(got == want, what .. ": the art reaches " .. got .. " past the bar, expected " .. want)
    end
    -- the module's defaults: the icon on the left, a square of the bar's height (16)
    Is(nil, "42 3 25 3", "the default icon")
    Is({ castIconOnRight = true }, "26 3 41 3", "the icon on the right")
    -- a bar of another height has an icon of that height
    Is(nil, "50 3 25 3", "a 24 tall bar", 200, 24)
    -- the Y offset: within 2 either way the icon is part of the bar, and the art takes in what stands out
    Is({ castIconOffsetY = 2 }, "42 5 25 3", "the icon 2 up")
    Is({ castIconOffsetY = -2 }, "42 3 25 5", "the icon 2 down")
    Is({ castIconOffsetY = 1, castIconOnRight = true }, "26 4 41 3", "the icon on the right, 1 up")
    Is({ castIconOffsetY = 3 }, "26 3 25 3", "the icon 3 up")
    Is({ castIconOffsetY = -3 }, "26 3 25 3", "the icon 3 down")
    Is({ castIconOffsetY = 2.5 }, "26 3 25 3", "the icon 2.5 up")
    Is({ castIconOffsetY = 20 }, "26 3 25 3", "the icon far above the bar")
    -- Full Sized, hidden, or seated in Classic WoW UI's own border: the bar alone
    Is({ castIconFullSize = true }, "26 3 25 3", "a Full Sized icon")
    Is({ showCastIcon = false }, "26 3 25 3", "no icon")
    classic = true
    Is(nil, "26 3 25 3", "Classic WoW UI")
    classic = false
    -- the X offset moves the icon's outer edge, and the art with it; an icon pushed wholly into the bar adds nothing
    Is({ castIconOffsetX = -4 }, "46 3 25 3", "the left icon 4 further out")
    Is({ castIconOffsetX = 5 }, "37 3 25 3", "the left icon 5 into the bar")
    Is({ castIconOffsetX = 20, castIconOffsetY = 2 }, "26 5 25 3", "the left icon wholly inside the bar's length, 2 up")
    Is({ castIconOffsetX = 20 }, "26 3 25 3", "the left icon wholly inside the bar's length")
    Is({ castIconOffsetX = 4, castIconOnRight = true }, "26 3 45 3", "the right icon 4 further out")
    Is({ castIconOffsetX = -16, castIconOnRight = true }, "26 3 25 3", "the right icon wholly inside the bar")
    -- the icon's own scale: its size and its offsets are in its own units, hung from the bar's top
    Is({ castIconScale = 1.5 }, "50 3 25 11", "an icon at 150%")
    Is({ castIconScale = 1.5, castIconOffsetY = 2 }, "50 6 25 8", "an icon at 150%, 2 up")
    Is({ castIconScale = 0.5 }, "34 3 25 3", "an icon at 50%")
    Is({ castIconScale = 0.5, castIconOffsetY = -2 }, "34 3 25 3", "an icon at 50%, 2 down")
    -- the targeted art goes around the icon by the same rule
    do
        Reset(true)
        profile.importantCastGlow = false
        profile.castTargetGlow = true
        profile.castTargetGlowStyle = NP_MODERN
        local plate = Plate()
        plate:UpdateImportantCastGlow()
        plate:UpdateCastTargetGlow()
        local tf = plate._castTargetOverlay.children[1]
        check(Reach(tf) == "20 4 4 4", "the targeted art reaches " .. Reach(tf) .. " past the bar, expected 20 4 4 4")
        check(PiecesFault(tf, RETAIL[TGT], 9, 8, 9, 8) == nil, "going around the icon changed the targeted art's pieces")
    end
    -- a setting changed while the cast shows: the icon's layout asks, the art follows, and nothing is built
    local got, plate = Important(nil)
    local f = plate._importantCastOverlay.children[1]
    local texBefore, framesBefore = built.textures, built.frames
    profile.castIconOffsetY = 3
    liveNS.NP_PlaceCastGlowArt(plate)
    check(Reach(f) == "26 3 25 3", "an icon moved 3 up during a cast keeps the art around it")
    profile.castIconOffsetY = 0
    profile.castIconOnRight = true
    liveNS.NP_PlaceCastGlowArt(plate)
    check(Reach(f) == "26 3 41 3", "an icon moved to the right during a cast is not followed")
    check(built.textures == texBefore and built.frames == framesBefore and PiecesFault(f, RETAIL[IMP], 32, 3, 32, 3) == nil,
        "following the icon rebuilt the art or changed its pieces")
    -- and nothing is written while the reach stays
    local w = f.writes
    liveNS.NP_PlaceCastGlowArt(plate)
    plate:UpdateImportantCastGlow()
    check(f.writes == w, "an unchanged reach was anchored again")
    -- the anchors are written again for a change of any one of the four reaches
    do
        local function Step(set, want, what)
            for k in pairs(profile) do if k:find("^castIcon") then profile[k] = nil end end
            for k, v in pairs(set) do profile[k] = v end
            liveNS.NP_PlaceCastGlowArt(plate)
            check(Reach(f) == want, what .. ": the art reaches " .. Reach(f) .. " past the bar, expected " .. want)
        end
        Step({}, "42 3 25 3", "back to the default icon")
        Step({ castIconOffsetY = 2 }, "42 5 25 3", "the top reach alone")
        Step({}, "42 3 25 3", "the top reach alone, back")
        Step({ castIconOffsetY = -2 }, "42 3 25 5", "the bottom reach alone")
        Step({}, "42 3 25 3", "the bottom reach alone, back")
        Step({ castIconOffsetX = -4 }, "46 3 25 3", "the left reach alone")
        Step({ castIconOnRight = true }, "26 3 41 3", "the icon on the right")
        Step({ castIconOnRight = true, castIconOffsetX = 4 }, "26 3 45 3", "the right reach alone")
    end
    -- the options' Scale slider resizes the live icons itself, with no icon layout: it asks for the seat too
    profile.castIconOnRight, profile.castIconOffsetX = nil, nil
    profile.castIconScale = 1.5
    liveNS.NP_PlaceCastGlowArt(plate)
    check(Reach(f) == "50 3 25 11", "an icon resized during a cast is not followed (" .. Reach(f) .. ")")
    local scaleRow = Cut(ReadSource("EllesmereUIOptions/Nameplates_Options/DisplayBars_Options.lua"),
        '{ type="slider", label="Scale", min=0.5, max=2, step=0.1,', '{ type="slider", label="X Offset"', "the Scale slider")
    local resize = scaleRow:find("plate.castIconFrame:SetScale(v)", 1, true)
    check(resize and scaleRow:find("ns.NP_PlaceCastGlowArt(plate)", resize, true), "the Scale slider resizes the live icons without placing a showing art again")
end

-------------------------------------------------------------------------------
-- 9. the real spell icon layout: it places a showing art again, and the art is
--    the box around the bar and the icon as the layout placed it
-------------------------------------------------------------------------------
do
    local iconLayout = Cut(LAYOUT, "function ns.LayoutCastIcon(plate, castH)", "-- How far the cast icon protrudes past the bar edge", "the icon layout")
    liveNS.NP_CLASSIC = { icon = 1.25 }
    liveNS.NP_ClassicIconOffset = function() return -14, -6 end
    assert(loadstring("local ns, p, defaults, GetHealthBarHeight, GetCastIconScale = ...\n" .. iconLayout, "=EUI_Nameplates_Layout.lua"))(
        liveNS, profile, defaults, function() return 20 end, liveNS.GetCastIconScale)
    local BAR_W = 150
    local function IconPlate(barH)
        local plate = Plate(nil, BAR_W, barH)
        local icon = { points = {}, scale = 1 }
        function icon:ClearAllPoints() self.points = {} end
        function icon:SetScale(s) self.scale = s end
        function icon:SetSize(w, h) self.w, self.h = w, h end
        function icon:SetWidth(w) self.w = w end
        function icon:SetPoint(point, rel, relPoint, x, y) self.points[point] = { rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 } end
        plate.castIconFrame, plate.health = icon, {}
        return plate, icon
    end
    -- The icon's box in the bar's units, x from the bar's left end, y up from the bar's top
    -- (a frame's size and anchor offsets are in its own scale).
    local function IconBox(icon, plate)
        local s = icon.scale
        local tr, tl = icon.points.TOPRIGHT, icon.points.TOPLEFT
        if tr and tr.rel == plate.cast and tr.relPoint == "TOPLEFT" then
            return tr.x * s - icon.w * s, tr.x * s, tr.y * s, tr.y * s - icon.h * s
        elseif tl and tl.rel == plate.cast and tl.relPoint == "TOPRIGHT" then
            return BAR_W + tl.x * s, BAR_W + tl.x * s + icon.w * s, tl.y * s, tl.y * s - icon.h * s
        end
    end
    local function Near(a, b) return math.abs(a - b) < 1e-9 end
    local cases, wrapped = 0, 0
    for _, barH in ipairs({ 10, 16, 40 }) do
        for _, scale in ipairs({ 0.5, 1, 1.3, 2 }) do
            for _, x in ipairs({ -50, -7, 0, 5, 16, 30, 50 }) do
                for _, y in ipairs({ -3, -2, -1, 0, 1, 2, 3 }) do
                    for _, onRight in ipairs({ false, true }) do
                        Reset(true)
                        profile.importantCastGlowStyle = NP_MODERN
                        local plate, icon = IconPlate(barH)
                        liveNS.LayoutCastIcon(plate, barH)
                        plate:UpdateImportantCastGlow()
                        local f = plate._importantCastOverlay.children[1]
                        -- the settings change while the cast shows; the layout runs, as the options' refresh does
                        profile.castIconScale, profile.castIconOffsetX, profile.castIconOffsetY, profile.castIconOnRight = scale, x, y, onRight
                        liveNS.LayoutCastIcon(plate, barH)
                        local left, right, top, bottom = IconBox(icon, plate)
                        local l, t, r, b = 26, 3, 25, 3
                        if left and y >= -2 and y <= 2 then
                            wrapped = wrapped + 1
                            l = l + math.max(0, -left)
                            r = r + math.max(0, right - BAR_W)
                            t = t + math.max(0, top)
                            b = b + math.max(0, -barH - bottom)
                        end
                        local tl, br = Point(f, "TOPLEFT"), Point(f, "BOTTOMRIGHT")
                        cases = cases + 1
                        if not (left and tl.x and Near(-tl.x, l) and Near(tl.y, t) and Near(br.x, r) and Near(-br.y, b)) then
                            check(false, ("a %d tall bar, the icon at %s, x %d, y %d, %s: the art reaches %s %s %s %s past the bar, expected %s %s %s %s")
                                :format(barH, tostring(scale), x, y, onRight and "right" or "left", tostring(tl.x and -tl.x), tostring(tl.y), tostring(br.x),
                                        tostring(br.y and -br.y), tostring(l), tostring(t), tostring(r), tostring(b)))
                        end
                    end
                end
            end
        end
    end
    check(cases == 1176 and wrapped == 840, "the icon layout sweep did not run whole (" .. cases .. " cases, " .. wrapped .. " around the icon)")
    -- a Full Sized icon, no icon and Classic WoW UI's icon leave the art on the bar alone, through the real layout too
    local function Bare(set, what)
        Reset(true)
        profile.importantCastGlowStyle = NP_MODERN
        local plate = IconPlate(16)
        liveNS.LayoutCastIcon(plate, 16)
        plate:UpdateImportantCastGlow()
        local f = plate._importantCastOverlay.children[1]
        check(Point(f, "TOPLEFT").x == -42, what .. ": the default icon is not taken in first")
        for k, v in pairs(set) do profile[k] = v end
        liveNS.LayoutCastIcon(plate, 16)
        local tl, br = Point(f, "TOPLEFT"), Point(f, "BOTTOMRIGHT")
        check(tl.x == -26 and tl.y == 3 and br.x == 25 and br.y == -3, what .. ": the art does not go back to the bar alone")
    end
    Bare({ castIconFullSize = true }, "the icon made Full Sized during a cast")
    Bare({ showCastIcon = false }, "the icon hidden during a cast")
    -- Classic WoW UI seats the icon in its own border (the look is fixed for the session): the bar alone throughout
    classic = true
    do
        Reset(true)
        profile.importantCastGlowStyle = NP_MODERN
        local plate, icon = IconPlate(16)
        liveNS.LayoutCastIcon(plate, 16)
        plate:UpdateImportantCastGlow()
        local f = plate._importantCastOverlay.children[1]
        check(icon.points.CENTER ~= nil and Point(f, "TOPLEFT").x == -26 and Point(f, "BOTTOMRIGHT").x == 25, "Classic WoW UI's icon is taken into the art")
    end
    classic = false
    -- a plate that shows no art costs the layout nothing
    do
        Reset(true)
        local plate = IconPlate(16)
        liveNS.LayoutCastIcon(plate, 16)
        check(plate._importantCastOverlay == nil and plate._castTargetOverlay == nil, "the icon layout built a glow overlay")
    end
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_cast_glow_art (%d checks)"):format(count))
