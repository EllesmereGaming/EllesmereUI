-- Stub harness: Raid & Party Frames, the pet frames' Fill Color and Name Color, the party target
-- frames' Custom Dynamic Colors and Text Color, and the Fill Color row the mini and boss unit
-- frames share with them.
--   * the pets follow the Dark Mode of the frames they are styled from until a Fill Color is
--     picked, and a pick is saved only where it differs from what following gives;
--   * every pet Fill Color draws at the frames' Fill Opacity, the gradient modes included, on the
--     full paint and on every health tick; the pets keep a curve of their own;
--   * Name Color colours the pet's name alone, through the text engine, so a health tick never
--     takes it back and Health Text keeps its own colour;
--   * the boss group paints its own colour through the same painter, with no error;
--   * the three-stop curve and its preview twin are one builder (EUI_RaidFrames_Colors.lua).
-- The pieces are cut out of the real files by their first and last lines and run over stubs.
--   lua .tools/tests/test_rf_pet_fill_color.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"), name)
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
-- The text from the line starting `first` up to the line starting `last`.
local function Cut(src, first, last)
    local a = assert(src:find(first, 1, true), "first line not found: " .. first)
    local b = assert(src:find(last, a + #first, true), "last line not found after: " .. first)
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 30 then print("  FAIL: " .. tostring(msg)) end
    end
    return cond
end
local function eq(a, b, msg)
    return check(a == b, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-9 end
local function rgb(r, g, b) return ("%.3f %.3f %.3f"):format(r or -1, g or -1, b or -1) end

local BOSS   = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_BossFrames.lua")
local PETS   = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_PetFrames.lua")
local COLORS = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_Colors.lua")
local TEXT   = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_TextPaint.lua")
local PTSRC  = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_PartyTargets.lua")
local MAIN   = ReadSource("EllesmereUIRaidFrames/EllesmereUIRaidFrames.lua")
local UFMAIN = ReadSource("EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua")
local OPTS   = ReadSource("EllesmereUIOptions/RaidFrames_Options/VisualIndicators_Options.lua")
local RFOPTS = ReadSource("EllesmereUIOptions/EUI_RaidFrames_Options.lua")
local MINI   = ReadSource("EllesmereUIOptions/UnitFrames_Options/MiniFrames_Options.lua")
local ADDONS = ReadSource("EllesmereUIOptions/EllesmereUI_Widgets_RowAddons.lua")

-------------------------------------------------------------------------------
-- The world: units, the engine's curves, bars and font strings that log writes
-------------------------------------------------------------------------------
local SECRET = {}
local world = { hp = {}, class = {}, player = {}, npc = {} }
local CLASSRGB = { HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
                   WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
local palette = { fill = { 0.10, 0.11, 0.12, 0.9 }, bg = { 0.30, 0.31, 0.32, 0.8 } }
local EllesmereUI = { _dmGen = 1 }
function EllesmereUI.GetDarkModeFill() return palette.fill[1], palette.fill[2], palette.fill[3], palette.fill[4] end
function EllesmereUI.GetDarkModeBg() return palette.bg[1], palette.bg[2], palette.bg[3], palette.bg[4] end
function EllesmereUI.GetClassColor(ct)
    assert(ct ~= SECRET, "a secret class token used as a table key")
    return CLASSRGB[ct]
end
function EllesmereUI.GetClassColorForRestrictedUnit() return false end
function EllesmereUI.ResolveActiveAccent() return 0.05, 0.82, 0.62 end

function issecretvalue(v) return v == SECRET end
function UnitExists(u) return world.class[u] ~= nil or world.npc[u] ~= nil end
function UnitClass(u) return "x", world.class[u] end
function UnitIsPlayer(u) return world.player[u] == true end
function UnitInPartyIsAI() return false end
function UnitIsTapDenied(u) return world.npc[u] and world.npc[u].tap or false end
function UnitReaction(u) return world.npc[u] and world.npc[u].re or nil end
function UnitName(u) return u end
function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
FACTION_BAR_COLORS = { [2] = { r = 0.8, g = 0.1, b = 0.1 }, [5] = { r = 0, g = 0.6, b = 0.1 } }
C_ClassColor = { GetClassColor = function() return nil end }
Enum = { LuaCurveType = { Linear = 1 } }

local builds, hpReads = 0, 0
local function Color(r, g, b)
    return { r = r, g = g, b = b, GetRGB = function(self) return self.r, self.g, self.b end }
end
function CreateColor(r, g, b) return Color(r, g, b) end
C_CurveUtil = { CreateColorCurve = function()
    builds = builds + 1
    local cv = { pts = {} }
    function cv:SetType() end
    function cv:AddPoint(x, c) self.pts[#self.pts + 1] = { x, c } end
    return cv
end }
-- the engine's linear evaluation of a colour curve
local function Eval(cv, p)
    local a, b = cv.pts[1], cv.pts[#cv.pts]
    for i = 1, #cv.pts - 1 do
        if p >= cv.pts[i][1] and p <= cv.pts[i + 1][1] then a, b = cv.pts[i], cv.pts[i + 1]; break end
    end
    local t = (b[1] == a[1]) and 0 or (p - a[1]) / (b[1] - a[1])
    return a[2].r + (b[2].r - a[2].r) * t, a[2].g + (b[2].g - a[2].g) * t, a[2].b + (b[2].b - a[2].b) * t
end
function UnitHealthPercent(u, _, cv)
    hpReads = hpReads + 1
    return Color(Eval(cv, world.hp[u] or 1))
end

-- A status bar: the colour's alpha and the fill texture's alpha are one slot (a colour set
-- with three values keeps the alpha it has); writes are counted.
local function Bar()
    local tex = { alpha = 1 }
    function tex:SetAlpha(a) self.alpha = a end
    local h = { tex = tex, writes = 0 }
    function h:GetStatusBarTexture() return tex end
    function h:SetStatusBarColor(r, g, b, a)
        self.r, self.g, self.b = r, g, b
        self.writes = self.writes + 1
        if a ~= nil then tex.alpha = a end
    end
    function h:SetValue() end
    function h:GetOrientation() return "HORIZONTAL" end
    function h:GetReverseFill() return false end
    return h
end
-- The background takes its extent from the painter too (the whole button outside Dark Mode).
local function Button(unit)
    local b = { unit = unit, _health = Bar(), _bg = { n = 0 } }
    function b._bg:SetColorTexture(r, g, bl, a) self.r, self.g, self.b, self.a = r, g, bl, a; self.n = self.n + 1 end
    function b._bg:ClearAllPoints() self.all, self.pts = nil, 0 end
    function b._bg:SetAllPoints() self.all = true end
    function b._bg:SetPoint() self.pts = (self.pts or 0) + 1 end
    return b
end
local function Fill(b) return rgb(b._health.r, b._health.g, b._health.b) .. " @" .. ("%.2f"):format(b._health.tex.alpha) end
local function IsFill(b, r, g, bl, a)
    local h = b._health
    return near(h.r, r) and near(h.g, g) and near(h.b, bl) and near(h.tex.alpha, a)
end

local db = { profile = { friendlyBoss = {}, petFrames = {} } }
local ns = { EllesmereUI = EllesmereUI }
local FB = { txs = setmetatable({}, { __mode = "k" }), src = setmetatable({}, { __mode = "k" }) }
FB.Settings = function() return db.profile.friendlyBoss end
FB.UnitOf = function(b) return b.unit end
local source = {}
FB.Source = function() return source end
local healthPaints = 0
FB.PaintHealth = function() healthPaints = healthPaints + 1 end
local namePaints = 0
FB.PaintName = function() namePaints = namePaints + 1 end
local PF = {}
PF.Raw = function() return db.profile.petFrames end

-------------------------------------------------------------------------------
-- 1. the three-stop curve and its preview twins (EUI_RaidFrames_Colors.lua)
-------------------------------------------------------------------------------
local GetClassicHealthCurve = assert(loadstring(
    Cut(COLORS, "local classicHealthCurve\n", "-- Custom Dynamic Colors: the Classic path with user-chosen stops") .. "\nreturn GetClassicHealthCurve",
    "=Colors.lua (the Classic curve)"))()
assert(loadstring("local ns, db = ...\n"
    .. Cut(COLORS, "do\n    local DEF100 = { r = 0, g = 1, b = 0 }", "-- Class Color Reactive: the Custom Dynamic gradient whose 100% stop"),
    "=Colors.lua (the stop curves)"))(ns, db)
do
    local A, B = {}, {}
    local red, mid, blue = { r = 1, g = 0, b = 0 }, { r = 0.5, g = 0.5, b = 0.5 }, { r = 0, g = 0, b = 1 }
    builds = 0
    local c1 = ns.RF_StopsCurve(A, red, mid, blue)
    eq(builds, 1, "the first ask builds the curve")
    eq(#c1.pts, 3, "a plain three-stop curve has three points")
    check(c1.pts[1][1] == 0 and c1.pts[2][1] == 0.5 and c1.pts[3][1] == 1, "the stops sit at 0, 50 and 100 percent")
    check(c1.pts[1][2].r == 1 and c1.pts[3][2].b == 1 and c1.pts[2][2].g == 0.5, "each stop carries its own colour")
    check(ns.RF_StopsCurve(A, red, mid, blue) == c1 and builds == 1, "the same stops again reuse the curve")
    local c2 = ns.RF_StopsCurve(B, blue, mid, red)
    check(c2 ~= c1 and builds == 2, "another cache builds a curve of its own")
    for _ = 1, 5 do
        ns.RF_StopsCurve(A, red, mid, blue)
        ns.RF_StopsCurve(B, blue, mid, red)
    end
    eq(builds, 2, "two kinds of frame with different stops never rebuild each other's curve")
    -- every one of the nine numbers is an input: one channel of one stop changes at a time
    local stops = { { r = 1, g = 0, b = 0 }, { r = 0.5, g = 0.5, b = 0.5 }, { r = 0, g = 0, b = 1 } }
    ns.RF_StopsCurve(A, stops[1], stops[2], stops[3])
    for si, label in ipairs({ "0%", "50%", "100%" }) do
        for _, ch in ipairs({ "r", "g", "b" }) do
            local before, was = builds, A.curve
            stops[si] = { r = stops[si].r, g = stops[si].g, b = stops[si].b }
            stops[si][ch] = stops[si][ch] + 0.125
            local now = ns.RF_StopsCurve(A, stops[1], stops[2], stops[3])
            check(now ~= was and builds == before + 1, "a changed " .. label .. " stop (" .. ch .. " alone) does not build the curve again")
            check(ns.RF_StopsCurve(A, stops[1], stops[2], stops[3]) == now and builds == before + 1, "the " .. label .. " stop's " .. ch .. " is not remembered")
        end
    end
    local before
    -- a missing stop takes its default
    local d = ns.RF_StopsCurve({}, nil, nil, nil)
    eq(rgb(d.pts[1][2].r, d.pts[1][2].g, d.pts[1][2].b), rgb(0xE3 / 255, 0x30 / 255, 0x30 / 255), "the default 0% stop")
    eq(rgb(d.pts[2][2].r, d.pts[2][2].g, d.pts[2][2].b), rgb(0xEC / 255, 0xEC / 255, 0x32 / 255), "the default 50% stop")
    eq(rgb(d.pts[3][2].r, d.pts[3][2].g, d.pts[3][2].b), rgb(0, 1, 0), "the default 100% stop")
    -- the raid frames' own curve is another cache again
    local s = { dynamicColor0 = red, dynamicColor50 = mid, dynamicColor100 = blue }
    local own = ns.GetCustomDynamicCurve(s)
    before = builds
    ns.RF_StopsCurve(A, blue, blue, blue)
    check(ns.GetCustomDynamicCurve(s) == own and builds == before + 1, "a pet or target curve rebuilds the raid frames' own")
    -- the preview twins say what the curves say
    for _, p in ipairs({ 0, 0.1, 0.25, 0.5, 0.6, 0.75, 1 }) do
        local cv = ns.RF_StopsCurve(B, blue, mid, red)
        eq(rgb(ns.RF_StopsColorAt(blue, mid, red, p)), rgb(Eval(cv, p)), "the three-stop preview colour at " .. p)
        eq(rgb(ns.RF_ClassicColorAt(p)), rgb(Eval(GetClassicHealthCurve(), p)), "the Classic preview colour at " .. p)
    end
    eq(rgb(ns.RF_StopsColorAt(nil, nil, nil, 1)), rgb(0, 1, 0), "the preview twin's default 100% stop")
    eq(rgb(ns.RF_StopsColorAt(nil, nil, nil, 0)), rgb(0xE3 / 255, 0x30 / 255, 0x30 / 255), "the preview twin's default 0% stop")
end

-------------------------------------------------------------------------------
-- The real painter and the pets' colour pieces
-------------------------------------------------------------------------------
local HEAD = "local ns, FB, PF, db, GetClassicHealthCurve = ...\n"
local function Load(text, name, ret)
    return assert(loadstring(HEAD .. text .. (ret or ""), "=" .. name))(ns, FB, PF, db, GetClassicHealthCurve)
end
Load(Cut(BOSS, "FB.Dark = function(s)", "-- Text state of a button built with its texts"), "BossFrames.lua (the painter)")
Load(Cut(PETS, "PF.OWNER_OF = ", "-- Beside Owner pet -> the party frame it sits beside"), "PetFrames.lua (the tables)")
Load(Cut(PETS, "PF.Dark = function(s)", "-- The Party and Raid tabs each keep their own"), "PetFrames.lua (the colours)")
Load(Cut(PETS, "PF.PaintHealth = function(b, u)", "-- The event's pet is on the header button holding it"), "PetFrames.lua (the event slices)")

local CLASS60 = { healthColorMode = "class", healthBarOpacity = 60 }
local DARK60 = { healthColorMode = "dark", healthBarOpacity = 60 }
local GREEN = { 23 / 255, 172 / 255, 49 / 255 }
world.class.player, world.player.player = "MAGE", true
world.class.party1, world.player.party1 = "HUNTER", true
world.class.raid7, world.player.raid7 = "WARRIOR", true
world.class.pet, world.class.partypet1, world.class.raidpet7 = "WARRIOR", "WARRIOR", "MAGE"
world.hp.partypet1 = 0.25

-------------------------------------------------------------------------------
-- 2. the boss group through the shared painter: its own colour, no error
-------------------------------------------------------------------------------
do
    local b = Button("boss1")
    local ok, err = pcall(FB.PaintBarColor, b, FB, CLASS60)
    check(ok, "a friendly boss frame's paint raises: " .. tostring(err))
    check(IsFill(b, GREEN[1], GREEN[2], GREEN[3], 0.6), "a boss frame without a saved colour is not the default green at Fill Opacity: " .. Fill(b))
    db.profile.friendlyBoss.healthColor = { r = 0.9, g = 0.1, b = 0.1 }
    FB.PaintBarColor(b, FB, CLASS60)
    check(IsFill(b, 0.9, 0.1, 0.1, 0.6), "a boss frame does not take Boss Health Color at Fill Opacity: " .. Fill(b))
    -- the pets' own colour settings never reach it
    db.profile.petFrames.healthColorMode = "classic"
    FB.PaintBarColor(b, FB, CLASS60)
    check(IsFill(b, 0.9, 0.1, 0.1, 0.6), "a boss frame follows the pets' Fill Color: " .. Fill(b))
    db.profile.petFrames.healthColorMode = nil
    db.profile.friendlyBoss.healthColor = nil
    check(FB.PaintPetBarColor == nil and PF.PaintPetBarColor == nil and PF.PaintBarColor == nil, "a second painter hook is back")
end

-------------------------------------------------------------------------------
-- 3. the pets' Fill Color, each mode at the frames' Fill Opacity
-------------------------------------------------------------------------------
do
    local pet = db.profile.petFrames
    local b = Button("partypet1")
    -- nothing picked: their own colour beside frames in another mode, Dark Mode with dark frames
    FB.PaintBarColor(b, PF, CLASS60)
    check(IsFill(b, GREEN[1], GREEN[2], GREEN[3], 0.6), "unpicked pets are not the default colour at Fill Opacity: " .. Fill(b))
    FB.PaintBarColor(b, PF, DARK60)
    check(IsFill(b, 0.10, 0.11, 0.12, 0.9), "unpicked pets beside Dark Mode frames are not the palette's fill: " .. Fill(b))
    pet.healthColor = { r = 0.2, g = 0.4, b = 0.6 }
    FB.PaintBarColor(b, PF, CLASS60)
    check(IsFill(b, 0.2, 0.4, 0.6, 0.6), "the pets' saved colour is not painted: " .. Fill(b))
    -- Custom Color picked: that colour beside dark frames too
    pet.healthColorMode = "custom"
    FB.PaintBarColor(b, PF, DARK60)
    check(IsFill(b, 0.2, 0.4, 0.6, 0.6), "pets with Custom Color picked follow the frames into Dark Mode: " .. Fill(b))
    pet.customFillColor = { r = 1, g = 1, b = 1 }
    FB.PaintBarColor(b, PF, CLASS60)
    check(IsFill(b, 0.2, 0.4, 0.6, 0.6), "a second colour key is read for the pets' Custom Color: " .. Fill(b))
    pet.customFillColor = nil
    -- Class Color: the owner's
    pet.healthColorMode = "class"
    FB.PaintBarColor(b, PF, CLASS60)
    check(IsFill(b, 0.67, 0.83, 0.45, 0.6), "a party pet's Class Color is not its owner's (a Hunter): " .. Fill(b))
    local own = Button("pet")
    FB.PaintBarColor(own, PF, CLASS60)
    check(IsFill(own, 0.25, 0.78, 0.92, 0.6), "your pet's Class Color is not yours (a Mage): " .. Fill(own))
    local rp = Button("raidpet7")
    FB.PaintBarColor(rp, PF, CLASS60)
    check(IsFill(rp, 0.78, 0.61, 0.43, 0.6), "a raid pet's Class Color is not its owner's (a Warrior): " .. Fill(rp))
    world.class.party1 = SECRET
    local ok, err = pcall(FB.PaintBarColor, b, PF, CLASS60)
    check(ok and IsFill(b, 0.2, 0.4, 0.6, 0.6), "an owner whose class cannot be read does not fall back to the pets' own colour: " .. (ok and Fill(b) or tostring(err)))
    world.class.party1 = "HUNTER"
    -- the gradient modes: the curve's colour at the pet's health, at Fill Opacity
    pet.healthColorMode = "classic"
    FB.PaintBarColor(b, PF, CLASS60)
    check(IsFill(b, 1, 0.5, 0, 0.6), "Classic at 25% health is not orange at Fill Opacity: " .. Fill(b))
    pet.healthColorMode = "customDynamic"
    FB.PaintBarColor(b, PF, CLASS60)
    local dr, dg, dbl = ns.RF_StopsColorAt(nil, nil, nil, 0.25)
    check(IsFill(b, dr, dg, dbl, 0.6), "Custom Dynamic with no stops saved is not the default gradient at Fill Opacity: " .. Fill(b))
    pet.dynamicColor0, pet.dynamicColor50, pet.dynamicColor100 = { r = 0, g = 0, b = 0 }, { r = 1, g = 1, b = 1 }, { r = 0, g = 0, b = 1 }
    FB.PaintBarColor(b, PF, CLASS60)
    check(IsFill(b, 0.5, 0.5, 0.5, 0.6), "Custom Dynamic does not read the pets' own stops: " .. Fill(b))
    FB.PaintBarColor(b, PF, { healthColorMode = "class" })
    check(IsFill(b, 0.5, 0.5, 0.5, 1), "no Fill Opacity saved is not full opacity: " .. Fill(b))
    -- the pets' curve is their own: painting them never rebuilds the raid frames' curve
    local s = { dynamicColor0 = { r = 1, g = 0, b = 0 }, dynamicColor50 = { r = 0, g = 1, b = 0 }, dynamicColor100 = { r = 0, g = 0, b = 1 } }
    ns.GetCustomDynamicCurve(s)
    builds = 0
    for _ = 1, 4 do
        FB.PaintBarColor(b, PF, CLASS60)
        ns.GetCustomDynamicCurve(s)
    end
    eq(builds, 0, "curves built while pets and raid frames with different stops paint in turn")
    -- a picked gradient or colour never draws dark, a picked Dark Mode always does
    FB.PaintBarColor(b, PF, DARK60)
    check(IsFill(b, 0.5, 0.5, 0.5, 0.6), "pets with a gradient picked follow the frames into Dark Mode: " .. Fill(b))
    pet.healthColorMode = "dark"
    FB.PaintBarColor(b, PF, CLASS60)
    check(IsFill(b, 0.10, 0.11, 0.12, 0.9), "pets with Dark Mode picked are not the palette's fill: " .. Fill(b))
    pet.healthColorMode = nil
end

-------------------------------------------------------------------------------
-- 4. health ticks: the gradient modes recolour, at Fill Opacity; nothing else does
-------------------------------------------------------------------------------
do
    local pet = db.profile.petFrames
    local b = Button("partypet1")
    source = CLASS60
    for _, mode in ipairs({ "classic", "customDynamic" }) do
        pet.healthColorMode = mode
        FB.PaintBarColor(b, PF, CLASS60)
        world.hp.partypet1 = 1
        local writes = b._health.writes
        healthPaints = 0
        PF.PaintHealth(b, "partypet1")
        eq(healthPaints, 1, mode .. ": the health value and texts paint on a tick")
        eq(b._health.writes, writes + 1, mode .. ": colour writes on a tick")
        local r, g, bl
        if mode == "classic" then r, g, bl = 0, 1, 0 else r, g, bl = 0, 0, 1 end
        check(IsFill(b, r, g, bl, 0.6), mode .. ": the tick's colour is not the curve's at full health, at Fill Opacity: " .. Fill(b))
        world.hp.partypet1 = 0.25
    end
    for _, mode in ipairs({ "custom", "class", "dark" }) do
        pet.healthColorMode = mode
        FB.PaintBarColor(b, PF, CLASS60)
        local writes, reads = b._health.writes, hpReads
        PF.PaintHealth(b, "partypet1")
        check(b._health.writes == writes and hpReads == reads, mode .. ": a health tick recolours the bar")
    end
    pet.healthColorMode = nil
    FB.PaintBarColor(b, PF, DARK60)
    local writes, reads = b._health.writes, hpReads
    source = DARK60
    PF.PaintHealth(b, "partypet1")
    check(b._health.writes == writes and hpReads == reads, "nothing picked: a health tick recolours the bar")
    -- a pet that is gone paints nothing
    healthPaints = 0
    pet.healthColorMode = "classic"
    PF.PaintHealth(b, "partypet3")
    check(healthPaints == 0 and b._health.writes == writes, "a tick for a pet that does not exist paints")
    namePaints = 0
    PF.PaintName(b, "partypet1")
    PF.PaintName(b, "partypet3")
    eq(namePaints, 1, "name events paint the name of a pet that exists, and only that")
    pet.healthColorMode = nil
    source = CLASS60
end

-------------------------------------------------------------------------------
-- 5. the preview pets: the same painter over a made-up health, no unit asked
-------------------------------------------------------------------------------
do
    local pet = db.profile.petFrames
    local f = Button(nil)
    hpReads = 0
    pet.healthColorMode = "classic"
    FB.PaintBarColor(f, PF, CLASS60, 0.75)
    check(IsFill(f, 0.5, 1, 0, 0.6), "a Classic preview pet at 75% is not the curve's colour at Fill Opacity: " .. Fill(f))
    pet.healthColorMode = "customDynamic"
    FB.PaintBarColor(f, PF, CLASS60, 0.75)
    check(IsFill(f, 0.5, 0.5, 1, 0.6), "a Custom Dynamic preview pet at 75% does not read the pets' stops: " .. Fill(f))
    pet.healthColorMode = "class"
    FB.PaintBarColor(f, PF, CLASS60, 0.75)
    check(IsFill(f, 0.25, 0.78, 0.92, 0.6), "a Class Color preview pet is not your class colour: " .. Fill(f))
    pet.healthColorMode = nil
    FB.PaintBarColor(f, PF, CLASS60, 0.75)
    check(IsFill(f, 0.2, 0.4, 0.6, 0.6), "an unpicked preview pet is not the pets' own colour: " .. Fill(f))
    FB.PaintBarColor(f, PF, DARK60, 0.75)
    check(IsFill(f, 0.10, 0.11, 0.12, 0.9), "an unpicked preview pet beside dark frames is not dark: " .. Fill(f))
    eq(hpReads, 0, "unit health reads for preview pets")
    check(PETS:find("    FB.PaintBarColor(f, PF, s, pct / 100)\n", 1, true) ~= nil, "the preview pets do not paint through the real painter with their health")
    pet.healthColor, pet.dynamicColor0, pet.dynamicColor50, pet.dynamicColor100 = nil, nil, nil, nil
end

-------------------------------------------------------------------------------
-- 6. Name Color: the pet's name alone, through the text engine
-------------------------------------------------------------------------------
do
    local pet = db.profile.petFrames
    local Tint, TintName = assert(loadstring("local ns = ...\n"
        .. Cut(TEXT, "local function TextColor(e, unit, s, pr, pg, pb)", "-- Show Above Icons per text")
        .. "\nreturn Tint, TintName", "=TextPaint.lua (the tints)"))(ns)
    local function FS(name)
        local fs = { name = name, sets = 0 }
        function fs:SetTextColor(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a; self.sets = self.sets + 1 end
        function fs:SetText() end
        function fs:SetFormattedText() end
        return fs
    end
    local frames = { nameColorMode = "custom", nameColor = { r = 1, g = 1, b = 1 }, hpColorMode = "custom", hpColor = { r = 1, g = 0.9, b = 0.2 } }
    local eName = { kind = "name", k = { ColorMode = "nameColorMode", Color = "nameColor" }, prop = { a = 1 } }
    local eHp = { kind = "hp", k = { ColorMode = "hpColorMode", Color = "hpColor" }, prop = { a = 1 } }
    local d = { _txName = PF.NameRGB }
    local nameFS, hpFS = FS("name"), FS("health")
    local function Full()
        TintName(nameFS, eName, "partypet1", frames, d)
        Tint(hpFS, eHp, "partypet1", frames)
    end
    local function Tick() Tint(hpFS, eHp, "partypet1", frames) end

    -- nothing set: the frames' Name Color
    Full()
    eq(rgb(nameFS.r, nameFS.g, nameFS.b), rgb(1, 1, 1), "no Name Color set: the name")
    eq(rgb(hpFS.r, hpFS.g, hpFS.b), rgb(1, 0.9, 0.2), "no Name Color set: Health Text")
    -- Class Color: the owner's, on the name alone, and a health tick takes nothing back
    pet.textClassColored = true
    Full()
    eq(rgb(nameFS.r, nameFS.g, nameFS.b), rgb(0.67, 0.83, 0.45), "Class Color: the name is its owner's class colour")
    eq(rgb(hpFS.r, hpFS.g, hpFS.b), rgb(1, 0.9, 0.2), "Class Color: Health Text keeps its own colour")
    local sets = nameFS.sets
    for _ = 1, 3 do Tick() end
    eq(rgb(nameFS.r, nameFS.g, nameFS.b), rgb(0.67, 0.83, 0.45), "Class Color: the name after three health ticks")
    eq(rgb(hpFS.r, hpFS.g, hpFS.b), rgb(1, 0.9, 0.2), "Class Color: Health Text after three health ticks")
    Full()
    eq(nameFS.sets, sets, "a repaint with the same name colour sets nothing")
    -- your own pet, and a raid pet
    local mine = FS("mine")
    TintName(mine, eName, "pet", frames, d)
    eq(rgb(mine.r, mine.g, mine.b), rgb(0.25, 0.78, 0.92), "Class Color: your pet's name is your class colour")
    -- an owner whose class cannot be read: the frames' Name Color, nothing secret kept
    world.class.party1 = SECRET
    local ok, err = pcall(Full)
    check(ok, "an unreadable owner class raises: " .. tostring(err))
    eq(rgb(nameFS.r, nameFS.g, nameFS.b), rgb(1, 1, 1), "an unreadable owner class: the name")
    world.class.party1 = "HUNTER"
    -- a custom colour
    pet.textClassColored, pet.customTextColor = nil, { r = 0.3, g = 0.2, b = 0.1 }
    Full()
    eq(rgb(nameFS.r, nameFS.g, nameFS.b), rgb(0.3, 0.2, 0.1), "Custom Color: the name")
    eq(rgb(hpFS.r, hpFS.g, hpFS.b), rgb(1, 0.9, 0.2), "Custom Color: Health Text keeps its own colour")
    -- Class Color wins while both are saved
    pet.textClassColored = true
    Full()
    eq(rgb(nameFS.r, nameFS.g, nameFS.b), rgb(0.67, 0.83, 0.45), "Class Color over a saved custom colour")
    -- turned off again: the frames' Name Color comes back at the next name paint
    pet.textClassColored, pet.customTextColor = nil, nil
    Full()
    eq(rgb(nameFS.r, nameFS.g, nameFS.b), rgb(1, 1, 1), "Name Color turned off: the name")
    -- a frame with no name colour of its own (the raid frames)
    local raidFS = FS("raid")
    pet.textClassColored = true
    TintName(raidFS, eName, "raid7", frames, {})
    eq(rgb(raidFS.r, raidFS.g, raidFS.b), rgb(1, 1, 1), "a frame without a name colour of its own")
    pet.textClassColored = nil

    -- the engine's two name paints ask, the health tick does not
    check(TEXT:find("            PaintName(fs, e, unit, s, fb)\n            TintName(fs, e, unit, s, d)\n", 1, true) ~= nil,
        "the full paint does not tint the name through the frame's own colour")
    check(TEXT:find("            PaintName(pool[e.i], e, unit, s, fb)\n            TintName(pool[e.i], e, unit, s, d)\n", 1, true) ~= nil,
        "the name event does not tint the name through the frame's own colour")
    local tick = Cut(TEXT, "function ns.RF_TextHealth(d, unit, pct, gone, allCustom)", "--  Previews: no unit, made-up values in pv")
    check(tick:find("TintName", 1, true) == nil and tick:find("_txName", 1, true) == nil, "the health tick asks for a name colour")
    -- every pet button's text state asks the pets
    check(PETS:find("    FB.BuildVisuals(b, true)\n    FB.txs[b]._txName = PF.NameRGB\n", 1, true) ~= nil, "a pet button's name does not ask PF.NameRGB")
    check(PETS:find("ApplyTextColor", 1, true) == nil, "the pets paint text colours over the engine's again")

    -- the preview: the name in the colour handed over (pv.nr, pv.ng, pv.nb), other texts untouched
    ns._RFPreviewLevel = function() return 80 end
    ns.RF_HealthTextInto = function() end
    ns.RF_PreviewTextColor = function() return 0.9, 0.8, 0.7 end
    local PvPaint = assert(loadstring("local ns = ...\n"
        .. Cut(TEXT, "local function PvPaint(fs, e, s, pv, fb)", "-- Lays out and paints every shown text of a preview frame")
        .. "\nreturn PvPaint", "=TextPaint.lua (the preview painter)"))(ns)
    local pn, ph = FS("pvname"), FS("pvhealth")
    local pv = { name = "Felhunter", hpPct = 80, nr = 0.67, ng = 0.83, nb = 0.45 }
    PvPaint(pn, eName, frames, pv, true)
    PvPaint(ph, eHp, frames, pv, true)
    eq(rgb(pn.r, pn.g, pn.b), rgb(0.67, 0.83, 0.45), "a preview pet's name in the pets' Name Color")
    eq(rgb(ph.r, ph.g, ph.b), rgb(0.9, 0.8, 0.7), "a preview pet's Health Text keeps the preview's own colour")
    pv.nr, pv.ng, pv.nb = nil, nil, nil
    PvPaint(pn, eName, frames, pv, true)
    eq(rgb(pn.r, pn.g, pn.b), rgb(0.9, 0.8, 0.7), "a preview name with no colour handed over")
    check(PETS:find("    pv.nr, pv.ng, pv.nb = PF.NameRGB()\n    ns.RF_TextPreview(st, s, pv)\n", 1, true) ~= nil, "the preview pets do not hand their Name Color to the text preview")
    -- PF.NameRGB with no unit is a preview pet: yours
    pet.textClassColored = true
    eq(rgb(PF.NameRGB()), rgb(0.25, 0.78, 0.92), "a preview pet's Class Color name")
    pet.textClassColored = nil
    eq(select("#", PF.NameRGB()), 0, "values PF.NameRGB returns with nothing set")
end

-------------------------------------------------------------------------------
-- 7. the options: the pets' Fill Color follows until a pick differs; Name Color
-------------------------------------------------------------------------------
local function OptionsRow(text, head, args)
    -- text: a piece of an options builder that makes one DualRow and hands a config to
    -- EllesmereUI.BuildFillColorSwatches. Returns the two halves' configs and that config.
    local got = {}
    local W = {}
    function W:DualRow(_, _, left, right)
        got.left, got.right = left, right
        return { _leftRegion = "left region", _rightRegion = "right region" }, 40
    end
    local E = { calls = {} }
    setmetatable(E, { __index = EllesmereUI })
    function E:RefreshPage(force) E.calls[#E.calls + 1] = force and "RefreshPage(true)" or "RefreshPage" end
    function E.BuildFillColorSwatches(rgn, opts) got.rgn, got.swatches = rgn, opts end
    got.E = E
    assert(loadstring("local W, EllesmereUI, parent, y, row, h, " .. head .. " = ...\n" .. text, "=the options row"))(
        W, E, {}, 0, nil, nil, unpack(args, 1, #args))
    return got
end
do
    local pet = db.profile.petFrames
    local calls = {}
    local function Called(name) calls[#calls + 1] = name end
    local function Seen() local s = table.concat(calls, ","); calls = {}; return s end
    local ons = { PF_FollowMode = ns.PF_FollowMode }
    ons.PF_Apply = function(restyle) Called(restyle and "PF_Apply(true)" or "PF_Apply") end
    ons.PF_PartyRestyle = function() Called("PF_PartyRestyle") end
    ons._PF_RefreshVisible = function() Called("_PF_RefreshVisible") end
    local text = Cut(OPTS, "        local function PetColors(restyle)", "        row, h = W:DualRow(parent, y,\n            { type=\"slider\", text=\"Extra Width\"")
    local function Row(tab)
        return OptionsRow(text, "ns, PFSet, tabKey, PFRefreshPreview, UnitClass",
            { ons, function() return pet end, tab, function() Called("preview") end, function() return "x", "MAGE" end })
    end
    local raidFrames, partyFrames = { healthColorMode = "class" }, { healthColorMode = "class" }
    ns._scaledProfile = raidFrames
    PF.PartySource = function() return partyFrames end

    local got = Row("raid")
    local dd = got.left
    eq(dd.type, "dropdown", "the left half's type")
    eq(dd.text, "Fill Color", "the left half's label")
    eq(table.concat(dd.order, ","), "class,dark,classic,custom,customDynamic", "the Fill Color entries")
    eq(dd.values.dark, "Dark Mode", "the Dark Mode entry")
    -- what it shows with nothing picked: what following this tab's frames gives
    eq(dd.getValue(), "custom", "nothing picked, raid frames in Class Color")
    raidFrames.healthColorMode = "dark"
    eq(dd.getValue(), "dark", "nothing picked, raid frames in Dark Mode")
    partyFrames.healthColorMode = "dark"
    raidFrames.healthColorMode = "class"
    eq(dd.getValue(), "custom", "the raid tab reads the raid frames, not the party frames")
    local pdd = Row("party").left
    eq(pdd.getValue(), "dark", "the party tab reads the party frames")
    -- a pick is saved only where it differs from that
    raidFrames.healthColorMode = "dark"
    Seen()
    dd.setValue("dark")
    eq(pet.healthColorMode, nil, "picking what the pets already follow saves nothing")
    eq(Seen(), "PF_Apply(true),PF_PartyRestyle,_PF_RefreshVisible,preview", "a Fill Color pick runs the restyle checks, then repaints")
    eq(table.concat(got.E.calls, ","), "RefreshPage", "a Fill Color pick refreshes the page")
    dd.setValue("custom")
    eq(pet.healthColorMode, "custom", "Custom Color beside dark frames is saved")
    eq(dd.getValue(), "custom", "and shown")
    dd.setValue("classic")
    eq(pet.healthColorMode, "classic", "a gradient pick is saved")
    dd.setValue("dark")
    eq(pet.healthColorMode, nil, "back to what following gives: the pick is dropped, the pets follow again")
    raidFrames.healthColorMode = "class"
    eq(dd.getValue(), "custom", "and they leave Dark Mode with the frames")
    dd.setValue("custom")
    eq(pet.healthColorMode, nil, "Custom Color beside frames in another mode saves nothing")
    dd.setValue("dark")
    eq(pet.healthColorMode, "dark", "Dark Mode beside frames in another mode is saved")
    partyFrames.healthColorMode = "class"
    raidFrames.healthColorMode = "dark"
    pdd.setValue("dark")
    eq(pet.healthColorMode, "dark", "the party tab saves a pick that differs from the party frames (the raid frames' mode is not asked)")
    pdd.setValue("custom")
    eq(pet.healthColorMode, nil, "and drops one that is what following the party frames gives")
    dd.setValue("custom")
    eq(pet.healthColorMode, "custom", "the raid tab compares with the raid frames")
    dd.setValue("dark")
    eq(pet.healthColorMode, nil, "and drops what following them gives")
    raidFrames.healthColorMode = "class"

    -- Name Color: two swatches, neither lit until one is picked
    local nc = got.right
    eq(nc.type, "multiSwatch", "the right half's type")
    eq(nc.text, "Name Color", "the right half's label")
    local custom, class = nc.swatches[1], nc.swatches[2]
    eq(custom.tooltip .. "|" .. class.tooltip, "Custom Color|Class Color", "the two swatches")
    eq(custom.refreshAlpha() .. "|" .. class.refreshAlpha(), "0.3|0.3", "nothing set: both swatches dim")
    Seen()
    custom.onClick({})
    check(pet.customTextColor and pet.customTextColor.r == 1 and pet.textClassColored == nil, "a first click on Custom Color does not start from white")
    eq(custom.refreshAlpha() .. "|" .. class.refreshAlpha(), "1|0.3", "Custom Color lit")
    eq(Seen(), "_PF_RefreshVisible,preview", "a Name Color pick repaints without the restyle checks")
    local opened = 0
    custom.onClick({ _eabOrigClick = function() opened = opened + 1 end })
    eq(opened, 1, "a click on the lit Custom Color opens the colour picker")
    custom.setValue(0.3, 0.2, 0.1)
    eq(rgb(custom.getValue()), rgb(0.3, 0.2, 0.1), "the picked name colour")
    pet.textClassColored = true
    custom.setValue(0.3, 0.2, 0.1)
    eq(pet.textClassColored, nil, "a custom name colour edit leaves Class Color on")
    class.onClick()
    check(pet.textClassColored == true and pet.customTextColor == nil, "Class Color does not replace the custom colour")
    eq(custom.refreshAlpha() .. "|" .. class.refreshAlpha(), "0.3|1", "Class Color lit")
    eq(rgb(class.getValue()), rgb(0.25, 0.78, 0.92), "the Class Color swatch shows your class colour")
    class.onClick()
    check(pet.textClassColored == nil and pet.customTextColor == nil, "a second click on the lit Class Color does not turn Name Color off")
    eq(custom.refreshAlpha() .. "|" .. class.refreshAlpha(), "0.3|0.3", "off again: both swatches dim")
    pet.textClassColored = true
    custom.onClick({})
    check(pet.textClassColored == nil and pet.customTextColor ~= nil, "Custom Color does not take over from Class Color")
    pet.customTextColor = nil

    -- the swatches: the pets' one colour key and their three stops
    local sw = got.swatches
    eq(got.rgn, "left region", "the swatches sit on the Fill Color half")
    raidFrames.healthColorMode = "dark"
    eq(sw.mode(), "dark", "the swatches follow the shown mode")
    raidFrames.healthColorMode = "class"
    eq(rgb(sw.getCustom()), rgb(GREEN[1], GREEN[2], GREEN[3]), "the Custom Color swatch's default")
    Seen()
    sw.setCustom(0.1, 0.2, 0.3)
    check(pet.healthColor and pet.healthColor.g == 0.2 and pet.customFillColor == nil, "the Custom Color swatch does not write the pets' one colour key")
    eq(Seen(), "_PF_RefreshVisible,preview", "a colour edit repaints without the restyle checks")
    eq(rgb(sw.getCustom()), rgb(0.1, 0.2, 0.3), "the Custom Color swatch reads it back")
    eq(table.concat(sw.keys, ","), "dynamicColor100,dynamicColor50,dynamicColor0", "the stop keys, 100% first")
    eq(sw.getStop("dynamicColor50"), nil, "an unsaved stop")
    sw.setStop("dynamicColor50", 0.4, 0.5, 0.6)
    check(pet.dynamicColor50 and pet.dynamicColor50.b == 0.6 and sw.getStop("dynamicColor50") == pet.dynamicColor50, "a stop edit is not saved under its key")
    eq(Seen(), "_PF_RefreshVisible,preview", "a stop edit repaints without the restyle checks")
    pet.healthColor, pet.dynamicColor50 = nil, nil
    check(OPTS:find("PF_SyncColors", 1, true) == nil and OPTS:find("dynDefs", 1, true) == nil, "the pets' options carry the hand-built colour sync or swatch block again")
end

-------------------------------------------------------------------------------
-- 8. the options: the mini and boss unit frames' Fill Color, a view over the saved keys
-------------------------------------------------------------------------------
do
    local text = Cut(MINI, "        local function FillMode()", "        -- Dark Mode draws a flat dark bar")
    local reloads = 0
    local function Row(unitKey, settings)
        local ons = { UF_DarkThemeOn = function() return settings._dark == true end }
        return OptionsRow(text, "ns, settingsTable, unitKey, ReloadAndUpdate, MGet, MVal, MSet",
            { ons, settings, unitKey, function() reloads = reloads + 1 end,
              function(k) return settings[k] end,
              function(k, def) local v = settings[k]; if v == nil then return def end; return v end,
              function(k, v) settings[k] = v; reloads = reloads + 1 end })
    end
    -- Target of Target as a new profile has it: Class Color, nothing written
    local tot = { healthClassColored = false }
    local got = Row("targettarget", tot)
    local dd = got.left
    eq(dd.text, "Fill Color", "the left half's label")
    eq(table.concat(dd.order, ","), "class,classic,custom,customDynamic", "the Fill Color entries (Dark Mode is the unit frames' own switch)")
    eq(dd.getValue(), "class", "an untouched Target of Target reads as Class Color")
    eq(got.right.text, "Fill Opacity", "the right half's label")
    eq(got.right.getValue(), 90, "Fill Opacity's default")
    tot._dark = true
    eq(got.right.disabled(), true, "Fill Opacity greys out in Dark Mode")
    tot._dark = nil
    dd.setValue("custom")
    check(tot.healthClassColored == false and tot.healthColorMode == "none", "Custom Color does not clear Class Color and the gradient mode")
    eq(rgb(tot.customFillColor.r, tot.customFillColor.g, tot.customFillColor.b), rgb(37 / 255, 193 / 255, 29 / 255), "Custom Color's starting colour")
    eq(dd.getValue(), "custom", "then reads as Custom Color")
    eq(table.concat(got.E.calls, ","), "RefreshPage", "a pick refreshes the page")
    tot.customFillColor = { r = 0.3, g = 0.3, b = 0.9 }
    dd.setValue("classic")
    eq(tot.healthColorMode, "classic", "Classic is the gradient mode key")
    eq(dd.getValue(), "classic", "and reads back")
    dd.setValue("customDynamic")
    eq(dd.getValue(), "customDynamic", "Custom Dynamic Colors reads back")
    dd.setValue("class")
    check(tot.healthClassColored == true and tot.healthColorMode == "none", "Class Color does not set Class Color and clear the gradient mode")
    eq(dd.getValue(), "class", "then reads as Class Color")
    check(tot.customFillColor and tot.customFillColor.b == 0.9, "Class Color throws the saved custom colour away")
    dd.setValue("custom")
    eq(rgb(tot.customFillColor.r, tot.customFillColor.g, tot.customFillColor.b), rgb(0.3, 0.3, 0.9), "back to Custom Color: the saved colour is still there")
    -- the swatches
    local sw = got.swatches
    eq(sw.mode(), "custom", "the swatches follow the shown mode")
    tot.healthClassColored, tot.healthColorMode = true, "classic"
    sw.setCustom(0.5, 0.6, 0.7)
    check(tot.customFillColor.g == 0.6 and tot.healthClassColored == false and tot.healthColorMode == "none", "a Custom Color edit does not make the frame Custom Color")
    eq(table.concat(sw.keys, ","), "dynamicColor100,dynamicColor50,dynamicColor0", "the stop keys, 100% first")
    sw.setStop("dynamicColor0", 0.1, 0.1, 0.1)
    check(tot.dynamicColor0 and tot.dynamicColor0.r == 0.1 and sw.getStop("dynamicColor0") == tot.dynamicColor0, "a stop edit is not saved under its key")
    -- the boss frames: Class Color as shipped, hostile red as the custom starting colour
    local boss = { healthClassColored = true }
    got = Row("boss", boss)
    eq(got.left.getValue(), "class", "the boss frames as shipped read as Class Color")
    eq(rgb(got.swatches.getCustom()), rgb(0.8, 0.2, 0.2), "the boss frames' Custom Color swatch before a pick")
    got.left.setValue("custom")
    eq(rgb(boss.customFillColor.r, boss.customFillColor.g, boss.customFillColor.b), rgb(0.8, 0.2, 0.2), "the boss frames' Custom Color starts hostile red")
    check(MINI:find('        if unitKey == "boss" then\n            AddDarkModeBlock(bgRow._leftRegion, function() return settingsTable end)\n', 1, true) ~= nil,
        "the boss frames' Bar Background no longer greys out in Dark Mode")
    local chunk = Cut(MINI, "    -- Row 2: Fill Color | Fill Opacity", "    local smoothBarsWidget")
    check(chunk:find("dynDefs", 1, true) == nil and chunk:find("isBoss", 1, true) == nil, "the mini frames' colour row carries the hand-built swatch block again")
end

-------------------------------------------------------------------------------
-- 9. the shared swatch builder (EllesmereUI_Widgets_RowAddons.lua)
-------------------------------------------------------------------------------
do
    local made, points, refreshers, tips = {}, {}, {}, {}
    local function Swatch(get, set, size)
        local s = { get = get, set = set, size = size, shown = true, alpha = 1, scripts = {}, updates = 0 }
        function s:SetShown(v) self.shown = v and true or false end
        function s:SetAlpha(a) self.alpha = a end
        function s:GetFrameLevel() return 7 end
        function s:HookScript(name, fn) self.scripts[name] = fn end
        made[#made + 1] = s
        return s, function() s.updates = s.updates + 1 end
    end
    local block
    local E = { _prebuilding = false }
    local env = {
        EllesmereUI = E,
        BuildColorSwatch = function(_, _, get, set, _, size) return Swatch(get, set, size) end,
        PP = { Point = function(f, point, rel, relPoint, x, y) points[f] = { point, rel, relPoint, x, y } end },
        CreateFrame = function(_, _, parent)
            block = { parent = parent, shown = true, scripts = {} }
            function block:SetAllPoints() end
            function block:SetFrameLevel(l) self.level = l end
            function block:EnableMouse(v) self.mouse = v end
            function block:SetScript(name, fn) self.scripts[name] = fn end
            function block:SetShown(v) self.shown = v and true or false end
            return block
        end,
        ShowWidgetTooltip = function(_, text) tips[#tips + 1] = text end,
        HideWidgetTooltip = function() tips[#tips + 1] = "(hidden)" end,
        RegisterWidgetRefresh = function(fn) refreshers[#refreshers + 1] = fn end,
    }
    local Build = setfenv(assert(loadstring(
        Cut(ADDONS, "local FILL_STOPS = {", "EllesmereUI.BuildFillColorSwatches = BuildFillColorSwatches")
        .. "\nreturn BuildFillColorSwatches", "=RowAddons.lua (the Fill Color swatches)")), setmetatable(env, { __index = _G }))()
    check(ADDONS:find("\nEllesmereUI.BuildFillColorSwatches = BuildFillColorSwatches\n", 1, true) ~= nil, "the builder is not published")

    local mode, saved, wrote = "class", {}, {}
    local control = { name = "the dropdown" }
    local rgn = { _control = control, GetFrameLevel = function() return 4 end }
    Build(rgn, {
        mode = function() return mode end,
        getCustom = function() return 0.1, 0.2, 0.3 end,
        setCustom = function(r, g, b) wrote.custom = rgb(r, g, b) end,
        keys = { "k100", "k50", "k0" },
        getStop = function(key) return saved[key] end,
        setStop = function(key, r, g, b) wrote[key] = rgb(r, g, b) end,
    })
    eq(#made, 4, "swatches built (Custom Color and three stops)")
    local custom, s0, s50, s100 = made[1], made[2], made[3], made[4]
    eq(custom.size, 20, "the Custom Color swatch's size")
    eq(s0.size .. "," .. s50.size .. "," .. s100.size, "18,18,18", "the stop swatches' size")
    -- left to right they read 100% | 50% | 0%, the 0% stop beside the control
    check(points[s0][2] == control and points[s0][4] == -8, "the 0% stop is not 8 left of the control")
    check(points[s50][2] == s0 and points[s50][4] == -6, "the 50% stop is not 6 left of the 0% stop")
    check(points[s100][2] == s50 and points[s100][4] == -6, "the 100% stop is not 6 left of the 50% stop")
    check(points[custom][2] == control and points[custom][4] == -8, "the Custom Color swatch is not 8 left of the control")
    eq(rgn._lastInline, custom, "the next inline item chains from the Custom Color swatch")
    eq(rgb(custom.get()), rgb(0.1, 0.2, 0.3), "the Custom Color swatch's colour")
    eq(select(4, custom.get()), 1, "the Custom Color swatch's alpha")
    eq(rgb(s100.get()), rgb(0, 1, 0), "the 100% stop's default")
    eq(rgb(s50.get()), rgb(0xEC / 255, 0xEC / 255, 0x32 / 255), "the 50% stop's default")
    eq(rgb(s0.get()), rgb(0xE3 / 255, 0x30 / 255, 0x30 / 255), "the 0% stop's default")
    saved.k50 = { r = 0.4, g = 0.5, b = 0.6 }
    eq(rgb(s50.get()), rgb(0.4, 0.5, 0.6), "a saved stop")
    s100.set(1, 0, 0); s50.set(0, 1, 0); s0.set(0, 0, 1)
    eq(tostring(wrote.k100) .. "|" .. tostring(wrote.k50) .. "|" .. tostring(wrote.k0), rgb(1, 0, 0) .. "|" .. rgb(0, 1, 0) .. "|" .. rgb(0, 0, 1), "each stop writes its own key")
    custom.set(0.7, 0.8, 0.9)
    eq(wrote.custom, rgb(0.7, 0.8, 0.9), "the Custom Color swatch writes through setCustom")
    -- per mode
    local function State()
        return (custom.shown and ("custom " .. custom.alpha .. (block.shown and " blocked" or "")) or "custom hidden")
            .. " | stops " .. ((s100.shown and s50.shown and s0.shown) and "shown" or ((s100.shown or s50.shown or s0.shown) and "MIXED" or "hidden"))
    end
    eq(State(), "custom 0.3 blocked | stops hidden", "Class Color")
    eq(#refreshers, 1, "page refresh callbacks registered")
    mode = "custom"; refreshers[1]()
    eq(State(), "custom 1 | stops hidden", "Custom Color")
    mode = "classic"; refreshers[1]()
    eq(State(), "custom 0.3 blocked | stops hidden", "Classic")
    mode = "dark"; refreshers[1]()
    eq(State(), "custom 0.3 blocked | stops hidden", "Dark Mode")
    mode = "customDynamic"; refreshers[1]()
    eq(State(), "custom hidden | stops shown", "Custom Dynamic Colors")
    -- a refresh reads the shown swatches' colours again
    local u = s50.updates
    refreshers[1]()
    eq(s50.updates, u + 1, "a refresh re-reads a shown stop")
    u = custom.updates
    refreshers[1]()
    eq(custom.updates, u, "a refresh re-reads the hidden Custom Color swatch")
    mode = "custom"; refreshers[1]()
    eq(custom.updates, u + 1, "a refresh re-reads the shown Custom Color swatch")
    -- hover texts
    block.scripts.OnEnter()
    eq(tips[#tips], "Only available with Custom fill color", "the blocked swatch's tooltip")
    s100.scripts.OnEnter(); eq(tips[#tips], "Health bar color at full (100%) health", "the 100% stop's tooltip")
    s50.scripts.OnEnter(); eq(tips[#tips], "Health bar color at half (50%) health", "the 50% stop's tooltip")
    s0.scripts.OnEnter(); eq(tips[#tips], "Health bar color at empty (0%) health", "the 0% stop's tooltip")
    s0.scripts.OnLeave(); eq(tips[#tips], "(hidden)", "leaving a stop hides the tooltip")
    -- after another inline item (a cog), everything chains from it
    made, points = {}, {}
    local cog = { name = "a cog" }
    local rgn2 = { _control = control, _lastInline = cog, GetFrameLevel = function() return 4 end }
    Build(rgn2, { mode = function() return "custom" end, getCustom = function() return 1, 1, 1 end, setCustom = function() end,
                  keys = { "a", "b", "c" }, getStop = function() end, setStop = function() end })
    check(points[made[1]][2] == cog and points[made[2]][2] == cog, "the swatches do not chain from the inline item before them")
    -- nothing in the search pre-build
    made = {}
    E._prebuilding = true
    Build(rgn, { mode = function() return "custom" end })
    eq(#made, 0, "swatches built in the search pre-build")
end

-------------------------------------------------------------------------------
-- 10. the party target frames: Custom Dynamic Colors and Text Color
-------------------------------------------------------------------------------
do
    local PT = { stops = {} }
    local PT_Paint, PT_PaintValue = assert(loadstring("local PT, EUI, ns, GetClassicHealthCurve, GetSafeHealthPercent = ...\n"
        .. Cut(PTSRC, "local function PT_ClassRGB(u, frame)", "-- Every target frame on screen, in full")
        .. "\nreturn PT_Paint, PT_PaintValue", "=PartyTargets.lua (the paints)"))(PT, EllesmereUI, ns, GetClassicHealthCurve, function() return 50 end)
    local function Frame(unit)
        local f = Button(unit)
        f._ptUnit = unit
        local name = { sets = 0 }
        function name:SetText(t) self.text = t end
        function name:SetTextColor(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a; self.sets = self.sets + 1 end
        f._nameText = name
        return f
    end
    world.npc.boar = { re = 2 }
    world.npc.wolf = { re = 2, tap = true }
    world.hp.boar, world.hp.party1target = 0.25, 0.25
    world.class.party1target, world.player.party1target = "HUNTER", true
    PT.br, PT.bgg, PT.bb, PT.bgA = 0.1, 0.1, 0.1, 0.5

    -- Custom Dynamic Colors: the target frames' own curve, on the identity paint and the value paint
    PT.mode = "customDynamic"
    PT.curve = ns.RF_StopsCurve(PT.stops, { r = 0, g = 0, b = 0 }, { r = 1, g = 0.5, b = 0 }, { r = 0, g = 0, b = 1 })
    local f = Frame("boar")
    PT_Paint(f)
    check(IsFill(f, 0.5, 0.25, 0, 1), "a Custom Dynamic target at 25% is not the curve's colour: " .. Fill(f))
    world.hp.boar = 1
    PT_PaintValue(f, "boar")
    check(IsFill(f, 0, 0, 1, 1), "the value paint does not move a Custom Dynamic target along the curve: " .. Fill(f))
    world.hp.boar = 0.25
    check(PTSRC:find("        PT.curve = ns.RF_StopsCurve(PT.stops, p.partyTargetDynamicColor0, p.partyTargetDynamicColor50,\n            p.partyTargetDynamicColor100)\n", 1, true) ~= nil,
        "the target frames do not build their curve with the shared builder, in a cache of their own")
    check(PTSRC:find("ns.RF_StopsColorAt(s.partyTargetDynamicColor0, s.partyTargetDynamicColor50,\n                s.partyTargetDynamicColor100, mock.hp / 100)", 1, true) ~= nil,
        "the target preview does not use the curve's preview twin")
    check(PTSRC:find("CreateColorCurve", 1, true) == nil, "the target frames build a curve by hand again")
    -- Text Color: white until set; a custom colour; Class Color (the class, the reaction, grey for a tapped mob)
    eq(rgb(f._nameText.r, f._nameText.g, f._nameText.b), rgb(1, 1, 1), "no Text Color set: a target's name")
    PT.tr, PT.tg, PT.tb = 0.3, 0.2, 0.1
    PT_Paint(f)
    eq(rgb(f._nameText.r, f._nameText.g, f._nameText.b), rgb(0.3, 0.2, 0.1), "Custom Color: a target's name")
    PT.textClass = true
    PT_Paint(f)
    eq(rgb(f._nameText.r, f._nameText.g, f._nameText.b), rgb(0.8, 0.1, 0.1), "Class Color: a hostile mob's name is its reaction colour")
    check(f._ptNpc == true, "a mob named by its reaction is not re-checked by the ticker")
    local p = Frame("party1target")
    PT_Paint(p)
    eq(rgb(p._nameText.r, p._nameText.g, p._nameText.b), rgb(0.67, 0.83, 0.45), "Class Color: a player's name is the class colour")
    check(p._ptNpc == nil, "a player target is re-checked by the ticker")
    local w = Frame("wolf")
    PT_Paint(w)
    eq(rgb(w._nameText.r, w._nameText.g, w._nameText.b), rgb(0.6, 0.6, 0.6), "Class Color: a tapped mob's name is grey")
    world.class.party1target = SECRET
    PT_Paint(p)
    eq(rgb(p._nameText.r, p._nameText.g, p._nameText.b), rgb(0.5, 0.5, 0.5), "Class Color: a class that cannot be resolved names in grey")
    world.class.party1target = "HUNTER"
    -- the other fills still paint with a Text Color set
    PT.mode = "custom"; PT.fr, PT.fg, PT.fb = 0.2, 0.3, 0.4
    PT_Paint(p)
    check(IsFill(p, 0.2, 0.3, 0.4, 1), "Custom Color fill with Class Color text: " .. Fill(p))
    PT.mode = "dark"
    PT_Paint(p)
    check(IsFill(p, 0.10, 0.11, 0.12, 0.9), "Dark Mode fill with Class Color text: " .. Fill(p))
    eq(rgb(p._nameText.r, p._nameText.g, p._nameText.b), rgb(0.67, 0.83, 0.45), "Dark Mode keeps the Class Color name")
    PT.mode = "class"
    PT_Paint(p)
    check(IsFill(p, 0.67, 0.83, 0.45, 1), "Class Color fill: " .. Fill(p))
end

-------------------------------------------------------------------------------
-- 11. defaults and the reload passes
-------------------------------------------------------------------------------
do
    local block = Cut(MAIN, "        petFrames = {", "            extraWidth  = 0,")
    local t = assert(loadstring("return {" .. block:gsub("^%s*petFrames = {", "") .. "}", "=the pet defaults"))()
    eq(t.healthColorMode, nil, "a default pet Fill Color (unset is what follows the frames)")
    eq(t.customFillColor, nil, "a second default colour key for the pets")
    check(t.healthColor and near(t.healthColor.g, 172 / 255), "the pets' own colour lost its default")
    check(t.dynamicColor100 and t.dynamicColor50 and t.dynamicColor0, "the pets' gradient stops lost their defaults")
    eq(t.textClassColored, nil, "a default pet Name Color")
    eq(t.customTextColor, nil, "a default pet name colour")
    -- the mini and boss unit frames: the dynamic keys stay unset, as on the main frames
    check(UFMAIN:find('\n            healthColorMode = "none",\n', 1, true) == nil, "a unit frame defaults its gradient mode")
    check(UFMAIN:find("\n            customFillColor = { r = 0.8, g = 0.2, b = 0.2 },\n", 1, true) == nil, "the boss frames default a custom fill colour")
    -- a raid reload restyles only the pets styled from the raid settings; the party reload does the rest
    check(PETS:find("        PF.OwnerLayout(edge)\n", 1, true) ~= nil, "the master apply checks the Beside Owner pets' style on every raid reload")
    check(PETS:find('    PF.Layout((restyle and PF.Ctx() == "raid") or edge)\n', 1, true) ~= nil, "the master apply restyles the party pets on every raid reload")
    check(PETS:find('        restyled = PF.StyleChanged("owner", s, texPath)\n', 1, true) ~= nil, "the Beside Owner pets' style check carries extra inputs")
    check(PETS:find('        restyled = PF.StyleChanged("hdr", ss, ResolveHealthTexture(ss), PF.CompactStyleInput, PF.STYLE_N + 1)\n', 1, true) ~= nil,
        "the header pets' style check carries extra inputs")
    check(PETS:find("SyncColors", 1, true) == nil, "the pets cache their colours again")
    check(RFOPTS:find("dynDefs", 1, true) == nil and RFOPTS:find("EllesmereUI.BuildFillColorSwatches(row._leftRegion, {\n        mode = function() return PV(\"partyTargetHealthColorMode\", \"class\") end,", 1, true) ~= nil,
        "the party targets' options do not use the shared swatch builder")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_rf_pet_fill_color (%d checks)"):format(count))
