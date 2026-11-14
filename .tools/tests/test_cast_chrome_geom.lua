-- Stub harness: the seat of the stock (Blizzard Style) cast bar art on our
-- own cast bars. One parent function holds the numbers
-- (EllesmereUI.CastChromeGeom in EllesmereUI_SharedHelpers.lua); Resource Bars
-- and Unit Frames each ask it for their bar (ns.ERB_CastChromeGeom,
-- ns.UF_CastChromeGeom), and their live bars and options previews seat from
-- those. Under the WoW Forever art the frame sits flush on top and on the side
-- an icon stands against the bar, the name and the timer sit a little lower
-- and the spark is taller and thinner; every other look keeps the old 2px
-- reach, no nudge and the 8px spark.
-- Cuts the functions out of their files by their first and last lines (a moved
-- line fails here by name), runs them, and checks that the live bars, the
-- previews and both stale-parent guards use them.
--   lua .tools/tests/test_cast_chrome_geom.lua      (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local n = 0
local function check(cond, msg)
    n = n + 1
    assert(cond, msg)
end
local function Is(what, want, ...)
    local got = { ... }
    check(select("#", ...) == #want, what .. ": " .. select("#", ...) .. " values, expected " .. #want)
    for i = 1, #want do
        check(got[i] == want[i], ("%s: value %d is %s, expected %s"):format(what, i, tostring(got[i]), tostring(want[i])))
    end
end

local SHARED = ReadSource("EllesmereUI_SharedHelpers.lua")
local RB_GROUPS = ReadSource("EllesmereUIResourceBars/EUI_ResourceBars_Groups.lua")
local RB_CAST = ReadSource("EllesmereUIResourceBars/EUI_ResourceBars_CastBar.lua")
local RB_OPT = ReadSource("EllesmereUIOptions/EUI_ResourceBars_Options.lua")
local UF_STOCK = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_StockStyles.lua")
local UF_CAST = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_Castbar.lua")
local UF_OPT = ReadSource("EllesmereUIOptions/UnitFrames_Options/UnitPreview_Options.lua")

-- reach left, reach right, reach top, name Y, timer Y, spark extra height, spark Y, spark width
local STOCK = { 2, 2, 2, 0, 0, 0, 0, 8 }
local FOREVER = { 2, 2, 0, -2, -1, 4, -1, 5 }
local FOREVER_LEFT = { 0, 2, 0, -2, -1, 4, -1, 5 }
local FOREVER_RIGHT = { 2, 0, 0, -2, -1, 4, -1, 5 }

-------------------------------------------------------------------------------
-- 1. the parent's numbers
-------------------------------------------------------------------------------
local EllesmereUI = {}
assert(loadstring("local EllesmereUI = ...\n" .. Cut(SHARED, "function EllesmereUI.CastChromeGeom(forever, iconSide)\n", "\n\n", "the parent function"),
    "=shared-cut"))(EllesmereUI)
local Geom = EllesmereUI.CastChromeGeom
Is("every other look", STOCK, Geom(false))
Is("every other look, no argument", STOCK, Geom())
Is("every other look ignores the icon", STOCK, Geom(false, "left"))
Is("WoW Forever, no flush icon", FOREVER, Geom(true))
Is("WoW Forever, icon on the left", FOREVER_LEFT, Geom(true, "left"))
Is("WoW Forever, icon on the right", FOREVER_RIGHT, Geom(true, "right"))

-------------------------------------------------------------------------------
-- 2. Resource Bars: the bar's art and the side its icon sits on
-------------------------------------------------------------------------------
do
    local forever, iconW, asked = false, 0, 0
    local ns = { ERB_CastForever = function() return forever end, ERB_CastIconW = function() asked = asked + 1; return iconW end }
    assert(loadstring("local ns, EllesmereUI = ...\n" .. Cut(RB_GROUPS, "function ns.ERB_CastChromeGeom(cb)\n", "\n-- Frame art around the bar", "the Resource Bars helper"),
        "=rb-cut"))(ns, EllesmereUI)
    local cb = { iconOnRight = false }
    iconW = 20
    Is("Resource Bars, another look", STOCK, ns.ERB_CastChromeGeom(cb))
    check(asked == 0, "Resource Bars: another look measured the icon")
    forever = true
    Is("Resource Bars, WoW Forever, icon left", FOREVER_LEFT, ns.ERB_CastChromeGeom(cb))
    cb.iconOnRight = true
    Is("Resource Bars, WoW Forever, icon right", FOREVER_RIGHT, ns.ERB_CastChromeGeom(cb))
    iconW = 0
    Is("Resource Bars, WoW Forever, no icon", FOREVER, ns.ERB_CastChromeGeom(cb))
    cb.iconOnRight = nil
    Is("Resource Bars, WoW Forever, no icon, side unset", FOREVER, ns.ERB_CastChromeGeom(cb))
end

-------------------------------------------------------------------------------
-- 3. Unit Frames: the look, and when an icon counts as flush against the bar
-------------------------------------------------------------------------------
do
    local forever = false
    local ns = { UF_Forever = function() return forever end }
    assert(loadstring("local ns, EllesmereUI = ...\n" .. Cut(UF_STOCK, "function ns.UF_CastChromeGeom(iconSide)\n", "\n-- Spell name into the text box", "the Unit Frames helpers"),
        "=uf-cut"))(ns, EllesmereUI)
    Is("Unit Frames, another look", STOCK, ns.UF_CastChromeGeom("left"))
    forever = true
    Is("Unit Frames, WoW Forever, no icon", FOREVER, ns.UF_CastChromeGeom())
    Is("Unit Frames, WoW Forever, icon left", FOREVER_LEFT, ns.UF_CastChromeGeom("left"))
    Is("Unit Frames, WoW Forever, icon right", FOREVER_RIGHT, ns.UF_CastChromeGeom("right"))

    local Side = ns.UF_CastIconSide
    check(Side(true, false, 0, 0) == "left" and Side(true, true, 0, 0) == "right", "a shown icon with no offset is not flush")
    check(Side(true, false) == "left" and Side(true, nil, nil, nil) == "left", "unset offsets do not count as none")
    check(Side(false, true, 0, 0) == nil and Side(nil, false, 0, 0) == nil, "a hidden icon counts as flush")
    check(Side(true, false, 3, 0) == nil and Side(true, true, 0, -2) == nil and Side(true, true, 1, 1) == nil, "an icon nudged away counts as flush")

    local Flush = ns.UF_CastIconFlushSide
    check(Flush(nil) == nil and Flush({}) == nil, "no bar, or a bar with no icon, has a flush side")
    check(Flush({ _icoShown = true }) == "left" and Flush({ _icoShown = true, _icoOnRight = true }) == "right", "a live bar's flush icon")
    check(Flush({ _icoShown = true, _icoOffX = 4 }) == nil and Flush({ _icoShown = true, _icoOnRight = true, _icoOffY = -1 }) == nil,
        "a live bar's nudged icon counts as flush")
    -- the frame keeps its reach on the side of a nudged icon
    Is("Unit Frames, WoW Forever, icon nudged away", FOREVER, ns.UF_CastChromeGeom(Flush({ _icoShown = true, _icoOffX = 4 })))
end

-------------------------------------------------------------------------------
-- 4. the live bars and the previews seat from the helpers
-------------------------------------------------------------------------------
local function Has(src, text, what) check(src:find(text, 1, true) ~= nil, what) end
local function Count(src, text)
    local c, at = 0, 1
    while true do
        local a, b = src:find(text, at, true)
        if not a then return c end
        c, at = c + 1, b + 1
    end
end
-- Resource Bars: the frame art, the name, the timer and the spark, live and in the preview
Has(RB_GROUPS, 'fr:SetPoint("TOPLEFT", clip, "TOPLEFT", -reachL, reachT)', "Resource Bars: the live frame art does not take its reach from the helper")
Has(RB_GROUPS, 'fr:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", reachR, -2)', "Resource Bars: the live frame art's right reach")
Has(RB_GROUPS, "(cb.spellTextY or 0) + textY", "Resource Bars: the live spell name takes no nudge")
Has(RB_CAST, "(cb.timerY or 0) + timerNudge", "Resource Bars: the live timer takes no nudge")
Has(RB_CAST, "spark:SetSize(sparkW, h + sparkExtraH)", "Resource Bars: the live spark's size is not the helper's")
Has(RB_OPT, 'fr:SetPoint("TOPLEFT", pf.barFrame, "TOPLEFT", -reachL, reachT)', "Resource Bars: the preview's frame art does not take its reach from the helper")
Has(RB_OPT, "(cb.spellTextY or 0) + textY", "Resource Bars: the preview's spell name takes no nudge")
Has(RB_OPT, "(cb.timerY or 0) + timerNudge", "Resource Bars: the preview's timer takes no nudge")
Has(RB_OPT, "pf.spark:SetSize(sparkW, h + sparkExtraH)", "Resource Bars: the preview's spark size is not the helper's")
check(Count(RB_CAST, "ns.ERB_CastChromeGeom(cb)") == 2 and Count(RB_OPT, "ns.ERB_CastChromeGeom(cb)") == 3, "Resource Bars: a seat that does not ask the helper")
-- the spark keeps its raised seat through a cast: the per-tick re-anchor
-- reuses the offset the layout chose (it reset it to the centre before)
Has(RB_CAST, "castBarFrame._sparkY = sparkY", "Resource Bars: the layout does not keep the spark's offset")
Has(RB_CAST, 'castBarFrame._spark:SetPoint("CENTER", target, "RIGHT", 0, castBarFrame._sparkY or 0)', "Resource Bars: the per-tick re-anchor drops the spark's offset")
-- the latency zone is masked to the fill's shape, with one mask per bar
Has(RB_CAST, "local m = castBarFrame._latencyMask\n            if not m then", "Resource Bars: the latency mask is made again on every layout")
Has(RB_CAST, "ns.ERB_MaskTex(castBarFrame._latencyOverlayFront, m)", "Resource Bars: a channel's front zone is not masked")

-- Unit Frames: the frame art, the name and the timer, live and in the preview
Has(UF_STOCK, "local reachL, reachR, reachT = ns.UF_CastChromeGeom(ns.UF_CastIconFlushSide(cb))", "Unit Frames: the live frame art does not ask for the icon's side")
Has(UF_STOCK, 'cb._blizzFrame:SetPoint("TOPLEFT", cb, "TOPLEFT", -reachL, reachT)', "Unit Frames: the live frame art's reach")
Has(UF_STOCK, "(cb._nameOY or 0) + nameY", "Unit Frames: the live spell name takes no nudge")
Has(UF_CAST, "(cb._durOY or 0) + timerY", "Unit Frames: the live timer takes no nudge")
Has(UF_OPT, 'fr:SetPoint("TOPLEFT", castbar, "TOPLEFT", -reachL, reachT)', "Unit Frames: the preview's frame art reach")
Has(UF_OPT, "(s.castSpellNameY or 0) + nameY", "Unit Frames: the preview's spell name takes no nudge")
Has(UF_OPT, "(s.castDurationY or 0) + timerY", "Unit Frames: the preview's timer takes no nudge")
-- the preview decides "flush" by the same rule as the live bar, with the unit's own icon offsets
local pv = Cut(UF_OPT, "                local icoX, icoY\n", 'fr:SetPoint("TOPLEFT", castbar, "TOPLEFT", -reachL, reachT)', "the preview's frame art block")
Has(pv, 'if unitKey == "player" then icoX, icoY = s.playerCastIconOffsetX, s.playerCastIconOffsetY', "Unit Frames: the preview does not read the player's icon offsets")
Has(pv, "else icoX, icoY = s.castIconOffsetX, s.castIconOffsetY end", "Unit Frames: the preview does not read the unit's icon offsets")
Has(pv, "ns.UF_CastIconSide(castIconFrame and castIconFrame:IsShown(), onRight, icoX, icoY)", "Unit Frames: the preview does not share the live bar's flush rule")

-- a module that calls the parent's function lists it in its stale-parent guard
for _, f in ipairs({ "EllesmereUIResourceBars/EllesmereUIResourceBars.lua", "EllesmereUIUnitFrames/EllesmereUIUnitFrames.lua" }) do
    local guard = ReadSource(f):match("\nif not %(EllesmereUI and [^\n]*stale%-parent guard[^\n]*")
    check(guard ~= nil and guard:find("EllesmereUI.CastChromeGeom", 1, true) ~= nil, f .. ": the stale-parent guard does not list EllesmereUI.CastChromeGeom")
end
-- and neither module keeps numbers of its own
check(Count(RB_GROUPS, "EllesmereUI.CastChromeGeom(") == 2 and not RB_GROUPS:find("return 2, 2, 2, 0", 1, true), "Resource Bars keeps seat numbers of its own")
check(Count(UF_STOCK, "EllesmereUI.CastChromeGeom(") == 1 and not UF_STOCK:find("return 2, 2, 2, 0", 1, true), "Unit Frames keeps seat numbers of its own")

print(("cast chrome seat harness: %d checks, ok"):format(n))
