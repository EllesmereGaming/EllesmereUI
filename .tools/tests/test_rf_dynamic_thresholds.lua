-- Stub harness: Raid & Party Frames, Custom Dynamic Colors' Gradient Thresholds
-- (the Fill Color row's cog: dynamicLow 0-20, dynamicHigh 80-100). At or below
-- Low the 0% color holds, at or above High the 100% color holds, in the live
-- curve (ns.GetCustomDynamicCurve) and in the preview's twin
-- (ns.ResolveDynamicColor).
-- Loads EUI_RaidFrames_Colors.lua whole over stubs. The curve stub is a model:
-- piecewise linear between its sorted points, flat past the ends, which is what
-- a Linear curve is taken to do in the engine. The swatch tooltips are cut out
-- of VisualBars_Options.lua by their first and last lines (a moved line fails
-- here by name).
--   lua .tools/tests/test_rf_dynamic_thresholds.lua   (from the repository root)
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

-------------------------------------------------------------------------------
-- Stubs
-------------------------------------------------------------------------------
local builds, clamps, mathCalls = 0, 0, 0
C_CurveUtil = {
    CreateColorCurve = function()
        builds = builds + 1
        local c = { pts = {} }
        function c:SetType(t) self.t = t end
        function c:AddPoint(x, col) self.pts[#self.pts + 1] = { x = x, c = col } end
        function c:Eval(x)
            local p = self.pts
            table.sort(p, function(a, b) return a.x < b.x end)
            if x <= p[1].x then return p[1].c.r, p[1].c.g, p[1].c.b end
            for i = 2, #p do
                if x <= p[i].x then
                    local a, b = p[i - 1], p[i]
                    local t = (x - a.x) / (b.x - a.x)
                    return a.c.r + (b.c.r - a.c.r) * t, a.c.g + (b.c.g - a.c.g) * t, a.c.b + (b.c.b - a.c.b) * t
                end
            end
            local l = p[#p]
            return l.c.r, l.c.g, l.c.b
        end
        return c
    end,
}
Enum = { LuaCurveType = { Linear = 0 } }
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
-- the game's own clamp
Clamp = function(value, lo, hi)
    clamps = clamps + 1
    if value > hi then return hi elseif value < lo then return lo end
    return value
end
local realMax, realMin = math.max, math.min
math.max = function(...) mathCalls = mathCalls + 1; return realMax(...) end
math.min = function(...) mathCalls = mathCalls + 1; return realMin(...) end
-- what the rest of the file reads as it loads
EllesmereUI = setmetatable({
    TextTags = {
        UNIT = { keys = setmetatable({}, { __index = function() return { sample = 0, reads = "" } end }) },
        Bind = function() return {} end, Parse = function() return {} end,
    },
}, { __index = function() return function() end end })

local I = { dbSetters = {} }
local ns = { _internals = I, EllesmereUI = { AbbreviateValue = function() end } }
do
    local chunk = assert(loadstring(ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_Colors.lua"), "=Colors"))
    chunk("EllesmereUIRaidFrames", ns)
    assert(I.broken == false, "EUI_RaidFrames_Colors.lua did not load to its end")
end

local C0 = { r = 0.9, g = 0.1, b = 0.2 }
local C50 = { r = 0.8, g = 0.7, b = 0.1 }
local C100 = { r = 0.05, g = 0.95, b = 0.3 }
local function S(lo, hi)
    return { dynamicColor0 = C0, dynamicColor50 = C50, dynamicColor100 = C100, dynamicLow = lo, dynamicHigh = hi }
end
local function Xs(curve)
    local xs = {}
    for i, p in ipairs(curve.pts) do xs[i] = p.x end
    return table.concat(xs, " ")
end
local function Same(p, c) return p.c.r == c.r and p.c.g == c.g and p.c.b == c.b end
local function Near(r, g, b, c)
    return math.abs(r - c.r) < 1e-12 and math.abs(g - c.g) < 1e-12 and math.abs(b - c.b) < 1e-12
end

-------------------------------------------------------------------------------
-- 1. unset thresholds, and 0 / 100: the plain three-stop curve
-------------------------------------------------------------------------------
for _, s in ipairs({ S(nil, nil), S(0, 100) }) do
    local c = ns.GetCustomDynamicCurve(s)
    check(Xs(c) == "0 0.5 1", "the default curve's points: " .. Xs(c))
    check(Same(c.pts[1], C0) and Same(c.pts[2], C50) and Same(c.pts[3], C100), "the default curve's colors")
    for i = 0, 200 do
        local p = i / 200
        local r, g, b = ns.ResolveDynamicColor(s, p)
        local er, eg, eb
        if p >= 0.5 then
            local t = (p - 0.5) / 0.5
            er, eg, eb = C50.r + (C100.r - C50.r) * t, C50.g + (C100.g - C50.g) * t, C50.b + (C100.b - C50.b) * t
        else
            local t = p / 0.5
            er, eg, eb = C0.r + (C50.r - C0.r) * t, C0.g + (C50.g - C0.g) * t, C0.b + (C50.b - C0.b) * t
        end
        check(math.abs(r - er) < 1e-12 and math.abs(g - eg) < 1e-12 and math.abs(b - eb) < 1e-12,
            "the default preview color at " .. p)
    end
end
-- no colors saved: the built-in stops
do
    local c = ns.GetCustomDynamicCurve({})
    check(Xs(c) == "0 0.5 1" and c.pts[3].c.g == 1 and c.pts[3].c.r == 0 and c.pts[1].c.r == 0xE3 / 255, "the built-in stops")
end

-------------------------------------------------------------------------------
-- 2. the live curve and the preview agree, with flat ends, at every pair
-------------------------------------------------------------------------------
do
    local worst = 0
    for _, lo in ipairs({ 0, 1, 5, 10, 20 }) do
        for _, hi in ipairs({ 80, 90, 95, 99, 100 }) do
            local s = S(lo, hi)
            local c = ns.GetCustomDynamicCurve(s)
            local want = "0" .. (lo > 0 and (" " .. lo / 100) or "") .. " 0.5" .. (hi < 100 and (" " .. hi / 100) or "") .. " 1"
            check(Xs(c) == want, ("points at %d / %d: %s"):format(lo, hi, Xs(c)))
            for i = 0, 1000 do
                local p = i / 1000
                local cr, cg, cb = c:Eval(p)
                local rr, rg, rb = ns.ResolveDynamicColor(s, p)
                local d = realMax(math.abs(cr - rr), math.abs(cg - rg), math.abs(cb - rb))
                if d > worst then worst = d end
            end
            -- the model blends up to a point, so its value there is the color within rounding
            local r, g, b = c:Eval(lo / 100)
            check(Near(r, g, b, C0), ("the curve at Low %d is not the 0%% color"):format(lo))
            r, g, b = c:Eval(hi / 100)
            check(Near(r, g, b, C100), ("the curve at High %d is not the 100%% color"):format(hi))
            r, g, b = c:Eval(lo / 200)
            check(Near(r, g, b, C0), ("the curve under Low %d is not the 0%% color"):format(lo))
            r, g, b = c:Eval((hi + 100) / 200)
            check(Near(r, g, b, C100), ("the curve over High %d is not the 100%% color"):format(hi))
            r, g, b = ns.ResolveDynamicColor(s, lo / 200)
            check(r == C0.r and g == C0.g and b == C0.b, ("the preview under Low %d is not the 0%% color"):format(lo))
            r, g, b = ns.ResolveDynamicColor(s, (hi + 100) / 200)
            check(r == C100.r and g == C100.g and b == C100.b, ("the preview over High %d is not the 100%% color"):format(hi))
            r, g, b = c:Eval(0.5)
            check(Near(r, g, b, C50), ("the 50%% stop moved at %d / %d"):format(lo, hi))
        end
    end
    check(worst < 1e-12, "the curve and the preview differ by " .. worst)
end

-------------------------------------------------------------------------------
-- 3. a saved value outside its slider's range (an import, a hand edit) is
--    held to the range, so the stops stay in order
-------------------------------------------------------------------------------
check(Xs(ns.GetCustomDynamicCurve(S(50, 40))) == "0 0.2 0.5 0.8 1", "Low 50 / High 40: " .. Xs(ns.GetCustomDynamicCurve(S(50, 40))))
check(Xs(ns.GetCustomDynamicCurve(S(-5, 150))) == "0 0.5 1", "Low -5 / High 150: " .. Xs(ns.GetCustomDynamicCurve(S(-5, 150))))
do
    local r, g, b = ns.ResolveDynamicColor(S(50, 40), 0.2)
    check(r == C0.r and g == C0.g and b == C0.b, "the preview at 20% with Low 50")
    r, g, b = ns.ResolveDynamicColor(S(50, 40), 0.8)
    check(r == C100.r and g == C100.g and b == C100.b, "the preview at 80% with High 40")
end

-------------------------------------------------------------------------------
-- 4. the curve is built once per change of an input, and a paint that changes
--    nothing builds, clamps and computes nothing
-------------------------------------------------------------------------------
do
    local s = S(10, 90)
    s.dynamicColor0 = { r = C0.r, g = C0.g, b = C0.b }
    s.dynamicColor50 = { r = C50.r, g = C50.g, b = C50.b }
    s.dynamicColor100 = { r = C100.r, g = C100.g, b = C100.b }
    ns.GetCustomDynamicCurve(s)
    builds, clamps, mathCalls = 0, 0, 0
    local first = ns.GetCustomDynamicCurve(s)
    for _ = 1, 50 do check(ns.GetCustomDynamicCurve(s) == first, "an unchanged paint built a new curve") end
    check(builds == 0, "unchanged paints built " .. builds .. " curves")
    check(clamps == 0 and mathCalls == 0, ("unchanged paints clamped %d times and made %d math calls"):format(clamps, mathCalls))
    local function Moves(what, change)
        builds = 0
        change()
        local c = ns.GetCustomDynamicCurve(s)
        ns.GetCustomDynamicCurve(s); ns.GetCustomDynamicCurve(s)
        check(builds == 1, what .. ": " .. builds .. " builds")
        return c
    end
    check(Xs(Moves("Low moved", function() s.dynamicLow = 12 end)) == "0 0.12 0.5 0.9 1", "Low moved: the points")
    check(Xs(Moves("High moved", function() s.dynamicHigh = 85 end)) == "0 0.12 0.5 0.85 1", "High moved: the points")
    check(Xs(Moves("Low cleared", function() s.dynamicLow = nil end)) == "0 0.5 0.85 1", "Low cleared: the points")
    check(Xs(Moves("High cleared", function() s.dynamicHigh = nil end)) == "0 0.5 1", "High cleared: the points")
    for _, key in ipairs({ "dynamicColor0", "dynamicColor50", "dynamicColor100" }) do
        for _, ch in ipairs({ "r", "g", "b" }) do
            Moves(key .. "." .. ch, function() s[key][ch] = s[key][ch] * 0.5 end)
        end
    end
end
-- no settings table handed in: the profile
do
    local profile = S(5, 95)
    for i = 1, #I.dbSetters do I.dbSetters[i]({ profile = profile }) end
    check(Xs(ns.GetCustomDynamicCurve()) == "0 0.05 0.5 0.95 1", "the profile's thresholds: " .. Xs(ns.GetCustomDynamicCurve()))
    local r, g, b = ns.ResolveDynamicColor(nil, 0.97)
    check(r == C100.r and g == C100.g and b == C100.b, "the profile's High in the preview")
end
math.max, math.min = realMax, realMin

-------------------------------------------------------------------------------
-- 5. the options row: the 100% and 0% swatch tooltips name a moved threshold
--    in Custom Dynamic alone (Class Reactive shows the 0% swatch too, and its
--    curve ends at 0%), through format keys a locale can translate
-------------------------------------------------------------------------------
do
    local OPT = ReadSource("EllesmereUIOptions/RaidFrames_Options/VisualBars_Options.lua")
    local TIPS = Cut(OPT, "        local function Thresholded() return SVal(", "        local dynSwatches = {}\n", "the swatch tooltips")
    local function Tips(vals)
        local keys = {}
        local env = setmetatable({
            SVal = function(key, def)
                local v = vals[key]
                if v == nil then return def end
                return v
            end,
            EllesmereUI = { Lf = function(fmt, ...) keys[#keys + 1] = fmt; return fmt:format(...) end },
        }, { __index = _G })
        local chunk = assert(loadstring(TIPS .. "\nreturn dynDefs\n", "=swatch-tooltips"))
        setfenv(chunk, env)
        local defs = chunk()
        check(#defs == 3 and defs[1].key == "dynamicColor100" and defs[3].key == "dynamicColor0", "the three stop swatches")
        return defs[1].tip(), defs[2].tip(), defs[3].tip(), keys
    end
    local FULL, HALF, EMPTY = "Health bar color at full (100%) health", "Health bar color at half (50%) health", "Health bar color at empty (0%) health"
    local hi, mid, lo, keys = Tips({ healthColorMode = "customDynamic" })
    check(hi == FULL and mid == HALF and lo == EMPTY and #keys == 0, "unmoved thresholds: the plain tooltips")
    hi, mid, lo, keys = Tips({ healthColorMode = "customDynamic", dynamicLow = 10, dynamicHigh = 90 })
    check(hi == "Health bar color at 90% health and above", "the 100% swatch with High 90: " .. hi)
    check(lo == "Health bar color at 10% health and below", "the 0% swatch with Low 10: " .. lo)
    check(mid == HALF, "the 50% swatch")
    check(#keys == 2 and keys[1] == "Health bar color at %d%% health and above" and keys[2] == "Health bar color at %d%% health and below",
        "the threshold tooltips are not format keys")
    hi, mid, lo, keys = Tips({ healthColorMode = "customDynamic", dynamicLow = 10 })
    check(hi == FULL and lo == "Health bar color at 10% health and below", "Low alone moved")
    for _, mode in ipairs({ "classReactive", "class", "custom", "classic", "dark" }) do
        hi, mid, lo, keys = Tips({ healthColorMode = mode, dynamicLow = 10, dynamicHigh = 90 })
        check(hi == FULL and lo == EMPTY and #keys == 0, "saved thresholds are named in the tooltips under Fill Color " .. mode)
    end
    -- the mode unset reads as Class
    hi, mid, lo = Tips({ dynamicLow = 10, dynamicHigh = 90 })
    check(hi == FULL and lo == EMPTY, "the mode unset")
    -- the cog refreshes itself: the swatch refresh does not reach into it
    check(not OPT:find("_euiCogState", 1, true), "the page calls the cog helper's own refresh")
    for _, s in ipairs({ 'title = "Gradient Thresholds"', 'label="Low Threshold (%)", min=0, max=20, step=1', 'label="High Threshold (%)", min=80, max=100, step=1',
        'disabled = function() return SVal("healthColorMode", "class") ~= "customDynamic" end' }) do
        check(OPT:find(s, 1, true) ~= nil, "the cog: " .. s)
    end
end

print(("rf dynamic thresholds harness: %d checks, ok"):format(n))
