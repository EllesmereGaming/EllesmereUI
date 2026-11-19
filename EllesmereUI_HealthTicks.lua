if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_HealthTicks.lua
--  Health Ticks: marks on EllesmereUI health bars, a short mark per step of
--  health and a tall one every Nth step, with opacity, edge and shading options.
--  EllesmereUI_HealthBars.lua finds the bars; the look is one table per profile
--  (EllesmereUI.GetHealthTicksDB) and the on/off switch is per place. Per-bar
--  state lives in a weak table here, never as a field on a bar.
--
--  Max health is a secret value, so no Lua math touches it. Each mark rides the
--  fill edge of its own hidden StatusBar (value k * step, max = the unit's max
--  health). A mode with more than one step keeps the finest step whose marks
--  span max health: probe bars (min T, max T + 1, value = max health) fill
--  either empty or full, and clip frames anchored to their fill show one step's
--  marks and hide the others.
--  Step modes: "health" (By Health: a short mark per Small Tick Every, a tall
--  one per Tall Tick Every, only tall marks from Hide Small Ticks At max health
--  on), "league" (Fixed: a mark per 100 health, then per 1000 past 10000, in
--  the tall color), "auto" (50/100/500/1000) or a fixed number.
--  Only On Health: a mask texture anchored to the bar's fill texture hides the
--  marks past the fill; every mark and shading texture takes it.
--  Tick Bar Style PILLOW lights each block on one side and shades the other;
--  BEVEL does the same at a fixed pixel width. Both add a top light, a bottom
--  shade and a bar gradient over the fill, and keep their own values.
--  Tick Edge (tall and short sets): a Shadow beside the mark, or an Outline.
--------------------------------------------------------------------------------
local EllesmereUI = EllesmereUI
local HB = EllesmereUI.HealthBars
if not HB then return end

local HT = {}
EllesmereUI.HealthTicks = HT

local PP = EllesmereUI.PP
local UnitHealthMax = UnitHealthMax
local EMPTY = {}

-- Per-bar state, keyed by the bar (weak: a bar is never collected anyway).
local STATE = setmetatable({}, { __mode = "k" })

local AUTO_STEPS = { 50, 100, 500, 1000 }   -- Auto: style.marks marks per step
local LEAGUE_STEPS = { 100, 1000 }
local LEAGUE_MARKS = { 100, 40 }            -- 100s up to 10000, 1000s up to 40000
local FIXED_MARKS = 100                     -- a fixed step marks up to 100 steps
-- By Health: at most this many marks per tier. Small marks stop at Hide Small
-- Ticks At or at 100 of them (10000 health at 100), whichever comes first;
-- tall marks stop at 100 of them (100000 health at 1000), and a bigger bar
-- shows no marks (as Fixed past 40000).
local HEALTH_MARKS = 100
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Defaults of every healthTick* key, the one place the values live. A look key
-- that is not saved reads from here. healthTickMajorColor has no default: unset
-- it follows healthTickColor. Percent values are plain numbers. Mark and Tick Edge
-- widths and the edge gap are screen pixels (1 is one pixel at any resolution);
-- Tick Offset and Bevel widths are 1080p pixels (2 screen pixels at 4K).
local DEFAULTS = {
    healthTickStep = "health",           -- "health" (By Health), "league" (Fixed), "auto" or a fixed health step (50 ... 5000)
    healthTickSmallStep = 100,           -- By Health: a short mark per this much health
    healthTickTallStep = 500,            -- By Health: a tall mark per this much health (a multiple of the small step)
    healthTickHideSmallAt = 5000,        -- By Health: no short marks from this max health on (0 = never)
    healthTickWidth = 2,                 -- tall marks
    healthTickMinorWidth = 1,            -- short marks
    healthTickAlign = "CENTER",          -- LEFT, CENTER or RIGHT of the step line
    healthTickOffset = 0,                -- 1080p pixels, minus = left, plus = right
    healthTickEdge = "SHADOW",           -- NONE, SHADOW or OUTLINE
    healthTickColor = { r = 0, g = 0, b = 0 },
    healthTickAlpha = 100,               -- percent, tall marks
    healthTickMinorHeight = 50,          -- short mark height, percent of the bar (0 hides them)
    healthTickMinorAnchor = "TOP",       -- TOP, CENTER, BOTTOM or BOTH
    healthTickMajorEvery = 5,            -- every Nth mark is tall (5 or 10): 500 health in Fixed; not By Health
    healthTickMarks = 20,                -- marks per step (10 or 20), Auto only
    healthTickFillOnly = true,           -- hide the marks on the empty part of the bar
    healthTickAutoLight = false,         -- dark bars get the light mark color
    healthTickLightColor = { r = 0.5235710478504771, g = 0.5235710478504771, b = 0.5235710478504771 },
    healthTickDarkBelow = 40,            -- bar brightness percent that counts as dark
    healthTickBarStyle = "PILLOW",       -- NONE, BEVEL or PILLOW (shading between the marks)
    healthTickMinorAlpha = 100,          -- short mark opacity, percent (0 hides them)
    -- Tall Tick Edge (healthTickEdge above and these)
    healthTickEdgeWidth = 4,             -- edge width
    healthTickEdgeDistance = 0,          -- edge gap from the mark
    healthTickEdgeAlpha = 10,            -- edge opacity, percent
    healthTickEdgeAuto = false,          -- edge black or white, opposite the mark
    healthTickEdgeColor = { r = 0, g = 0, b = 0 }, -- edge color when Auto is off
    healthTickEdgeLightOnly = true,      -- edge only on bars with light marks (needs Light Marks On Dark Bars)
    healthTickEdgeSide = "LEFT",         -- Shadow: RIGHT or LEFT of the mark (Outline: both sides)
    -- Short Tick Edge: the same set for the short marks
    healthTickMinorEdge = "SHADOW",
    healthTickMinorEdgeWidth = 1,
    healthTickMinorEdgeDistance = 0,
    healthTickMinorEdgeAlpha = 30,
    healthTickMinorEdgeAuto = false,
    healthTickMinorEdgeColor = { r = 0, g = 0, b = 0 },
    healthTickMinorEdgeLightOnly = true,
    healthTickMinorEdgeSide = "LEFT",
    healthTickBlocks = "TALL",           -- Pillow and Bevel blocks: TALL (tall mark to tall mark) or ALL (mark to mark)
    -- Pillow: each block lit on one side and shaded on the other.
    healthTickPillowLight = 82,          -- percent of the Light color on the lit side of each block
    healthTickPillowSplit = 25,          -- where the light ends: 25, 50 or 75 percent
    healthTickPillowShade = 36,          -- percent of the Shade color on the other side
    healthTickShadeTop = 47,             -- percent of the Top Light along the top of the fill
    healthTickShadeBottom = 30,          -- percent of the Bottom Shade along the bottom of the fill
    healthTickPillowAlpha = 100,         -- Style Opacity, percent (scales all the shading)
    healthTickPillowDirection = 0,       -- Light Direction, degrees: -90 from the left, 0 from above, 90 from the right
    healthTickPillowTopSize = 30,        -- Top Light band, percent of the bar height
    healthTickPillowTopSoft = 100,       -- Top Light softness: 100 fades over the band, 0 one solid band
    healthTickPillowBottomSize = 30,     -- Bottom Shade band, percent of the bar height
    healthTickPillowBottomSoft = 0,      -- Bottom Shade softness
    healthTickPillowGradient = 8,        -- Bar Gradient strength, percent (0 = off)
    healthTickPillowGradientAngle = -180, -- Bar Gradient light side, degrees: 0 right, 90 top, 180 left, -90 bottom
    healthTickPillowGradientBlend = "ADD", -- BLEND (a normal fade) or ADD (adds light)
    healthTickPillowGradientStart = { r = 1, g = 1, b = 1 },  -- the start side's color: left at angle 0
    healthTickPillowGradientEnd = { r = 0, g = 0, b = 0 },    -- the end side's color: right at angle 0
    -- The color and blend of each light and shade part. Light parts: BLEND or
    -- ADD. Shade parts: BLEND or MOD (Multiply).
    healthTickPillowLightColor = { r = 1, g = 1, b = 1 },    -- Side Light: the Light color
    healthTickPillowLightBlend = "BLEND",
    healthTickPillowShadeColor = { r = 0, g = 0, b = 0 },    -- Side Light: the Shade color
    healthTickPillowShadeBlend = "BLEND",
    healthTickPillowTopColor = { r = 1, g = 1, b = 1 },      -- Top Light color
    healthTickPillowTopBlend = "ADD",
    healthTickPillowBottomColor = { r = 0, g = 0, b = 0 },   -- Bottom Shade color
    healthTickPillowBottomBlend = "BLEND",
    -- Bevel: a light edge and a dark edge of a fixed width on each block.
    healthTickBevelLightWidth = 3,       -- light edge width
    healthTickBevelShadeWidth = 4,       -- dark edge width
    healthTickBevelLight = 16,           -- percent white of the light edge
    healthTickBevelShade = 30,           -- percent black of the dark edge
    healthTickBevelTop = 0,              -- percent white along the top of the fill
    healthTickBevelBottom = 0,           -- percent black along the bottom of the fill
    healthTickBevelAlpha = 100,          -- Style Opacity, percent (scales all the shading)
    healthTickBevelDirection = -90,      -- the same values as Pillow's, Bevel's own
    healthTickBevelTopSize = 55,
    healthTickBevelTopSoft = 100,
    healthTickBevelBottomSize = 55,
    healthTickBevelBottomSoft = 100,
    healthTickBevelGradient = 0,
    healthTickBevelGradientAngle = 0,
    healthTickBevelGradientBlend = "BLEND",
    healthTickBevelGradientStart = { r = 0, g = 0, b = 0 },
    healthTickBevelGradientEnd = { r = 1, g = 1, b = 1 },
    healthTickBevelLightColor = { r = 1, g = 1, b = 1 },
    healthTickBevelLightBlend = "BLEND",
    healthTickBevelShadeColor = { r = 0, g = 0, b = 0 },
    healthTickBevelShadeBlend = "BLEND",
    healthTickBevelTopColor = { r = 1, g = 1, b = 1 },
    healthTickBevelTopBlend = "BLEND",
    healthTickBevelBottomColor = { r = 0, g = 0, b = 0 },
    healthTickBevelBottomBlend = "BLEND",
}
HT.DEFAULTS = DEFAULTS

-- Every healthTick* key (the defaults plus the one without a default), sorted.
local TICK_KEYS = { "healthTickMajorColor" }
for k in pairs(DEFAULTS) do TICK_KEYS[#TICK_KEYS + 1] = k end
table.sort(TICK_KEYS)
HT.KEYS = TICK_KEYS
local KEY_SET = {}
for _, k in ipairs(TICK_KEYS) do KEY_SET[k] = true end

local function CopyValue(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = CopyValue(x) end
    return c
end

-- The keys of the shading set that belongs to each Tick Bar Style.
local STYLE_KEYS = {
    PILLOW = { light = "healthTickPillowLight", shade = "healthTickPillowShade",
               top = "healthTickShadeTop", bottom = "healthTickShadeBottom",
               alpha = "healthTickPillowAlpha", dir = "healthTickPillowDirection",
               topSize = "healthTickPillowTopSize", topSoft = "healthTickPillowTopSoft",
               bottomSize = "healthTickPillowBottomSize", bottomSoft = "healthTickPillowBottomSoft",
               grad = "healthTickPillowGradient", gradAngle = "healthTickPillowGradientAngle",
               gradBlend = "healthTickPillowGradientBlend", gradStart = "healthTickPillowGradientStart",
               gradEnd = "healthTickPillowGradientEnd",
               lightColor = "healthTickPillowLightColor", lightBlend = "healthTickPillowLightBlend",
               shadeColor = "healthTickPillowShadeColor", shadeBlend = "healthTickPillowShadeBlend",
               topColor = "healthTickPillowTopColor", topBlend = "healthTickPillowTopBlend",
               bottomColor = "healthTickPillowBottomColor", bottomBlend = "healthTickPillowBottomBlend" },
    BEVEL = { light = "healthTickBevelLight", shade = "healthTickBevelShade",
              top = "healthTickBevelTop", bottom = "healthTickBevelBottom",
              alpha = "healthTickBevelAlpha", dir = "healthTickBevelDirection",
              topSize = "healthTickBevelTopSize", topSoft = "healthTickBevelTopSoft",
              bottomSize = "healthTickBevelBottomSize", bottomSoft = "healthTickBevelBottomSoft",
              grad = "healthTickBevelGradient", gradAngle = "healthTickBevelGradientAngle",
              gradBlend = "healthTickBevelGradientBlend", gradStart = "healthTickBevelGradientStart",
              gradEnd = "healthTickBevelGradientEnd",
              lightColor = "healthTickBevelLightColor", lightBlend = "healthTickBevelLightBlend",
              shadeColor = "healthTickBevelShadeColor", shadeBlend = "healthTickBevelShadeBlend",
              topColor = "healthTickBevelTopColor", topBlend = "healthTickBevelTopBlend",
              bottomColor = "healthTickBevelBottomColor", bottomBlend = "healthTickBevelBottomBlend" },
}
HT.STYLE_KEYS = STYLE_KEYS

-- The key of one Tick Edge value: name "" (the edge type), "Width", "Distance",
-- "Alpha", "Auto", "Color", "LightOnly" or "Side"; short picks Short Tick Edge.
function HT.EdgeKey(name, short)
    return (short and "healthTickMinorEdge" or "healthTickEdge") .. name
end

-- A color's brightness, 0 to 1.
local function Lum(r, g, b)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

-- The edge takes the opposite of a mark's brightness, so a mark shows on any bar color.
local function EdgeOf(r, g, b)
    return Lum(r, g, b) > 0.5 and 0 or 1
end

-- A blend choice: the other mode (ADD for a light part, MOD for a shade part)
-- or BLEND.
local function BlendOf(v, d, other)
    if v == nil then v = d end
    if v == other then return other end
    return "BLEND"
end
HT.BlendOf = BlendOf

-- A shading color at strength a in blend mode m, and its "none" end (where a
-- fade ends). Blend and Add: the color at opacity a, fading to the same color
-- at 0 (Add adds the color times a). Multiply (MOD): the game multiplies the
-- bar by the color and may not use opacity, so the color moves toward white
-- by 1 - a (white changes nothing) at full opacity, fading to white.
local MOD_NONE = CreateColor(1, 1, 1, 1)
local function ShadeColors(r, g, b, a, m)
    if m == "MOD" then
        return CreateColor(1 - a * (1 - r), 1 - a * (1 - g), 1 - a * (1 - b), 1), MOD_NONE
    end
    return CreateColor(r, g, b, a), CreateColor(r, g, b, 0)
end

local function Num(v, d)
    v = tonumber(v)
    if v == nil then return d end
    return v
end

local function Flag(v, d)
    if v == nil then return d end
    return v and true or false
end

local function Rgb(c, d)
    if type(c) ~= "table" then c = d end
    return tonumber(c.r) or 0, tonumber(c.g) or 0, tonumber(c.b) or 0
end

-- A Tick Edge type: NONE, SHADOW or OUTLINE.
local function EdgeMode(v, d)
    if v == nil then v = d end
    if v ~= "SHADOW" and v ~= "OUTLINE" then return "NONE" end
    return v
end

-- A Shadow side: LEFT or RIGHT.
local function Side(v)
    if v == "LEFT" then return "LEFT" end
    return "RIGHT"
end

-- One Tick Edge set as flat style fields (prefix "" tall, "m" short), so the
-- compare in HT.MakeStyle sees them.
local function EdgeFields(s, src, short, p)
    local D = DEFAULTS
    local function key(name) return HT.EdgeKey(name, short) end
    s[p .. "edge"] = EdgeMode(src[key("")], D[key("")])
    s[p .. "ew"] = Num(src[key("Width")], D[key("Width")])
    s[p .. "ed"] = Num(src[key("Distance")], D[key("Distance")])
    s[p .. "ea"] = Num(src[key("Alpha")], D[key("Alpha")]) / 100
    s[p .. "eauto"] = Flag(src[key("Auto")], D[key("Auto")])
    s[p .. "elight"] = Flag(src[key("LightOnly")], D[key("LightOnly")])
    s[p .. "eside"] = Side(src[key("Side")])
    s[p .. "ecr"], s[p .. "ecg"], s[p .. "ecb"] = Rgb(src[key("Color")], D[key("Color")])
end

-- The set as one table, for the drawing (made after the compare).
local function EdgeSet(s, p)
    return { mode = s[p .. "edge"], w = s[p .. "ew"], d = s[p .. "ed"], a = s[p .. "ea"],
        auto = s[p .. "eauto"], light = s[p .. "elight"], side = s[p .. "eside"],
        r = s[p .. "ecr"], g = s[p .. "ecg"], b = s[p .. "ecb"] }
end

-- A percent of the bar height for a band: 1 to 100.
local function Size(v, d)
    v = Num(v, d)
    if v < 1 then return 1 end
    if v > 100 then return 100 end
    return v
end

-- A softness, 0 to 1.
local function Soft(v, d)
    v = Num(v, d) / 100
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- Reads the healthTick* keys of a profile (or proxy); a key that is not set takes
-- its HT.DEFAULTS value. Returns old when nothing changed, so a live bar restyles
-- only on a real change. Call per refresh.
function HT.MakeStyle(src, old)
    local D = DEFAULTS
    local r, g, b = Rgb(src.healthTickColor, D.healthTickColor)
    local mr, mg, mb = r, g, b
    local mc = src.healthTickMajorColor
    if type(mc) == "table" then mr, mg, mb = tonumber(mc.r) or r, tonumber(mc.g) or g, tonumber(mc.b) or b end
    local lr, lg, lb = Rgb(src.healthTickLightColor, D.healthTickLightColor)
    local a = Num(src.healthTickAlpha, D.healthTickAlpha) / 100
    local split = Num(src.healthTickPillowSplit, D.healthTickPillowSplit)
    if split ~= 25 and split ~= 75 then split = 50 end
    -- The shading set belongs to the active style: Pillow and Bevel each keep their own.
    local bar = src.healthTickBarStyle
    if bar == nil then bar = D.healthTickBarStyle end
    if bar ~= "PILLOW" and bar ~= "BEVEL" then bar = "NONE" end
    local K = STYLE_KEYS[bar] or STYLE_KEYS.PILLOW
    -- Style Opacity scales all the shading strengths at once.
    local so = Num(src[K.alpha], D[K.alpha]) / 100
    -- Light Direction: the side light (Light and Shade) is full from the left
    -- (-90, the first look) or the right (90, mirrored), none from above (0).
    local dir = Num(src[K.dir], D[K.dir])
    local side = 1
    if dir > -90 and dir < 90 then side = math.abs(math.sin(math.rad(dir))) end
    -- Bar Gradient: its across part (gx, plus: light on the right) and its up
    -- part (gy, plus: light on top).
    local gr = Num(src[K.grad], D[K.grad]) / 100 * so
    local ga = math.rad(Num(src[K.gradAngle], D[K.gradAngle]))
    local gx, gy = gr * math.cos(ga), gr * math.sin(ga)
    if math.abs(gx) < 0.001 then gx = 0 end
    if math.abs(gy) < 0.001 then gy = 0 end
    -- Its blend and its two colors: start (the dark side, left at angle 0)
    -- and end (the light side, right at angle 0).
    local gb = src[K.gradBlend]
    if gb == nil then gb = D[K.gradBlend] end
    if gb ~= "ADD" then gb = "BLEND" end
    local gsr, gsg, gsb = Rgb(src[K.gradStart], D[K.gradStart])
    local ger, geg, geb = Rgb(src[K.gradEnd], D[K.gradEnd])
    -- The light and shade parts' colors and blends.
    local slr, slg, slb = Rgb(src[K.lightColor], D[K.lightColor])
    local sdr, sdg, sdb = Rgb(src[K.shadeColor], D[K.shadeColor])
    local tcr, tcg, tcb = Rgb(src[K.topColor], D[K.topColor])
    local bcr, bcg, bcb = Rgb(src[K.bottomColor], D[K.bottomColor])
    local align = src.healthTickAlign
    if align ~= "LEFT" and align ~= "RIGHT" then align = "CENTER" end
    local blocks = src.healthTickBlocks
    if blocks == nil then blocks = D.healthTickBlocks end
    if blocks ~= "ALL" then blocks = "TALL" end
    -- By Health: a whole small step of at least 1; the tall step a whole
    -- multiple of it (so every tall mark is also a small mark's place).
    local hs = math.max(1, math.floor(Num(src.healthTickSmallStep, D.healthTickSmallStep) + 0.5))
    local ht = Num(src.healthTickTallStep, D.healthTickTallStep)
    ht = hs * math.max(1, math.floor(ht / hs + 0.5))
    local hh = math.max(0, Num(src.healthTickHideSmallAt, D.healthTickHideSmallAt))
    local s = { width = Num(src.healthTickWidth, D.healthTickWidth),
        align = align, off = Num(src.healthTickOffset, D.healthTickOffset),
        minorW = Num(src.healthTickMinorWidth, D.healthTickMinorWidth),
        r = r, g = g, b = b, mr = mr, mg = mg, mb = mb, alpha = a,
        minorH = Num(src.healthTickMinorHeight, D.healthTickMinorHeight),
        anchor = src.healthTickMinorAnchor or D.healthTickMinorAnchor,
        every = Num(src.healthTickMajorEvery, D.healthTickMajorEvery),
        hs = hs, ht = ht, hh = hh,
        marks = Num(src.healthTickMarks, D.healthTickMarks),
        fill = Flag(src.healthTickFillOnly, D.healthTickFillOnly),
        er = EdgeOf(r, g, b), mer = EdgeOf(mr, mg, mb),
        bar = bar, blocks = blocks,
        lw = Num(src.healthTickBevelLightWidth, D.healthTickBevelLightWidth),
        dw = Num(src.healthTickBevelShadeWidth, D.healthTickBevelShadeWidth),
        pl = Num(src[K.light], D[K.light]) / 100 * so * side,
        split = split,
        pd = Num(src[K.shade], D[K.shade]) / 100 * so * side,
        mir = dir > 0,
        stp = Num(src[K.top], D[K.top]) / 100 * so,
        sbt = Num(src[K.bottom], D[K.bottom]) / 100 * so,
        tsz = Size(src[K.topSize], D[K.topSize]), tsf = Soft(src[K.topSoft], D[K.topSoft]),
        bsz = Size(src[K.bottomSize], D[K.bottomSize]), bsf = Soft(src[K.bottomSoft], D[K.bottomSoft]),
        gx = gx, gy = gy, gb = gb,
        gsr = gsr, gsg = gsg, gsb = gsb, ger = ger, geg = geg, geb = geb,
        slr = slr, slg = slg, slb = slb, slm = BlendOf(src[K.lightBlend], D[K.lightBlend], "ADD"),
        sdr = sdr, sdg = sdg, sdb = sdb, sdm = BlendOf(src[K.shadeBlend], D[K.shadeBlend], "MOD"),
        tcr = tcr, tcg = tcg, tcb = tcb, tcm = BlendOf(src[K.topBlend], D[K.topBlend], "ADD"),
        bcr = bcr, bcg = bcg, bcb = bcb, bcm = BlendOf(src[K.bottomBlend], D[K.bottomBlend], "MOD"),
        auto = Flag(src.healthTickAutoLight, D.healthTickAutoLight),
        lr = lr, lg = lg, lb = lb, ler = EdgeOf(lr, lg, lb),
        dark = Num(src.healthTickDarkBelow, D.healthTickDarkBelow) / 100,
        ma = Num(src.healthTickMinorAlpha, D.healthTickMinorAlpha) / 100 }
    EdgeFields(s, src, false, "")
    EdgeFields(s, src, true, "m")
    if old then
        local same = true
        for k, v in pairs(s) do
            if old[k] ~= v then same = false; break end
        end
        if same then return old end
    end
    -- Gradient end colors and the edge sets (after the compare: new tables
    -- would never match). Each light and shade part: its color at its
    -- strength and its "none" end, for its blend (ShadeColors).
    local lightZ, darkZ
    s.lightC, lightZ = ShadeColors(s.slr, s.slg, s.slb, s.pl, s.slm)
    s.darkC, darkZ = ShadeColors(s.sdr, s.sdg, s.sdb, s.pd, s.sdm)
    s.topC, s.topZ = ShadeColors(s.tcr, s.tcg, s.tcb, s.stp, s.tcm)
    s.botC, s.botZ = ShadeColors(s.bcr, s.bcg, s.bcb, s.sbt, s.bcm)
    -- How dark Bottom Shade makes the bar at its edge (0: not a shade), for
    -- the tick edges that cross it (Rim).
    local bl = Lum(s.bcr, s.bcg, s.bcb)
    if s.bcm == "MOD" then
        s.botDark = s.sbt * (1 - bl)
    elseif bl < 0.5 then
        s.botDark = s.sbt
    else
        s.botDark = 0
    end
    -- The block's left ramp (color cL at the block's left, fading to zL, in
    -- blend bL) and right ramp (zR to cR at its right, blend bR): light left
    -- and dark right, or the other way round with the light from the right.
    -- Light Ends stays the light part's size, so mirrored it is measured from
    -- the right.
    if s.mir then
        s.cL, s.zL, s.bL, s.onL, s.wL = s.darkC, darkZ, s.sdm, s.pd > 0, s.dw
        s.cR, s.zR, s.bR, s.onR, s.wR = s.lightC, lightZ, s.slm, s.pl > 0, s.lw
        s.cut = 100 - s.split
    else
        s.cL, s.zL, s.bL, s.onL, s.wL = s.lightC, lightZ, s.slm, s.pl > 0, s.lw
        s.cR, s.zR, s.bR, s.onR, s.wR = s.darkC, darkZ, s.sdm, s.pd > 0, s.dw
        s.cut = s.split
    end
    -- Bar Gradient: each side's color at its strength, and the same color at
    -- none (where the half fades out, at the bar's middle). The defaults
    -- (black and white) are the first look.
    local ax, ay = math.abs(s.gx), math.abs(s.gy)
    s.gxS, s.gxS0 = CreateColor(s.gsr, s.gsg, s.gsb, ax), CreateColor(s.gsr, s.gsg, s.gsb, 0)
    s.gxE, s.gxE0 = CreateColor(s.ger, s.geg, s.geb, ax), CreateColor(s.ger, s.geg, s.geb, 0)
    s.gyS, s.gyS0 = CreateColor(s.gsr, s.gsg, s.gsb, ay), CreateColor(s.gsr, s.gsg, s.gsb, 0)
    s.gyE, s.gyE0 = CreateColor(s.ger, s.geg, s.geb, ay), CreateColor(s.ger, s.geg, s.geb, 0)
    s.E = EdgeSet(s, "")
    s.ME = EdgeSet(s, "m")
    return s
end

-- A nil style (HT.Push without one) draws the defaults (made on first use).
local defaultStyle

-- An invisible StatusBar over the health bar: its fill edge is the anchor.
local function HiddenBar(parent, bar)
    local sb = CreateFrame("StatusBar", nil, parent)
    sb:SetAllPoints(bar)
    sb:SetStatusBarTexture(WHITE)
    sb:SetStatusBarColor(0, 0, 0, 0)
    return sb
end

local function ClipFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetClipsChildren(true)
    return f
end

-- Only On Health: shows the tiers left of fill (the bar's own fill texture), or
-- over the whole bar when fill is nil. Only the mask moves with health; the
-- frames the marks sit in keep the bar's size.
local function AnchorFill(t, bar, fill)
    local m = t.mask
    m:ClearAllPoints()
    if fill then
        m:SetPoint("TOPLEFT", bar, "TOPLEFT")
        m:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    else
        m:SetAllPoints(bar)
    end
    t.fillTex = fill
end

-- A number the addon may use: not a secret (never tested), a number.
local function Usable(v)
    if issecretvalue and issecretvalue(v) then return false end
    return type(v) == "number"
end

-- Base units are physical pixels (see HT.Push). The bar height in them, or
-- the last one (nil when it never had one). The game raises an error when an
-- addon measures a region anchored to a restricted one, and gives secret
-- values for a secret layout, so each call is tried and its answer checked;
-- then the height set on the bar (GetHeight(true): no layout) is tried. The
-- base ignores its parent's scale (HT.Push), so its effective scale is our own.
local function BarPixels(t, bar)
    local okS, s = pcall(bar.GetEffectiveScale, bar)
    local s2 = t.base:GetEffectiveScale()
    if okS and Usable(s) and Usable(s2) and s2 > 0 then
        local ok, h = pcall(bar.GetHeight, bar)
        if not (ok and Usable(h) and h > 0) then
            ok, h = pcall(bar.GetHeight, bar, true)
        end
        if ok and Usable(h) and h > 0 then return h * s / s2 end
    end
    return t.h
end

-- Short mark height in whole pixels.
local function MinorPixels(t)
    return math.max(1, math.floor(t.h * t.style.minorH / 100 + 0.5))
end

-- A band's height in whole pixels (size percent of the bar height) and its
-- solid part at the bar's edge (softness 1: none, all of it fades).
local function BandPixels(t, size, soft)
    local hh = math.max(1, math.floor(t.h * size / 100 + 0.5))
    return hh, math.floor(hh * (1 - soft) + 0.5)
end

-- Tick Offset in base units (physical pixels), rounded to whole pixels.
local function OffsetPx(t)
    local x = t.style.off * t.mul
    if x < 0 then return -math.floor(-x + 0.5) end
    return math.floor(x + 0.5)
end

-- Where a mark w pixels wide starts, from its step line (Tick Position and
-- Tick Offset). Center may land on a half pixel; the width stays whole.
local function Shift(t, w)
    local align = t.style.align
    local x = OffsetPx(t)
    if align == "CENTER" then
        x = x - w / 2
    elseif align == "LEFT" then
        x = x - w
    end
    return x
end

-- Whether an edge set E (style.E tall, style.ME short) draws. Only With Light
-- Marks (with Light Marks On Dark Bars on): the edge shows only while the bar
-- has light marks (t.light). A dark mark's edge is white, which looks like
-- stripes on a light bar; a light mark's black edge reads as a shadow.
local function EdgeShown(t, E)
    if E.mode == "NONE" or E.a <= 0 then return false end
    if E.light and t.style.auto and not t.light then return false end
    return true
end

-- The sides an edge set draws on: Outline both, Shadow its side.
local function EdgeLeft(E) return E.mode == "OUTLINE" or E.side == "LEFT" end
local function EdgeRight(E) return E.mode == "OUTLINE" or E.side ~= "LEFT" end

-- How far an edge set reaches left of its mark.
local function LeftReach(t, E)
    if EdgeLeft(E) and EdgeShown(t, E) then return E.d + E.w end
    return 0
end

-- How far the marks (with an edge on their left) reach left of their step line.
local function MarkReach(t)
    local st = t.style
    local a = Shift(t, st.width) - LeftReach(t, st.E)
    local b = Shift(t, st.minorW) - LeftReach(t, st.ME)
    if b < a then a = b end
    if a < 0 then return -a end
    return 0
end

-- The marks clip: the tier's area up to the bar's right edge minus t.reach.
local function AnchorMarks(t, tier)
    local c = tier.marks
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", t.bar, "TOPLEFT")
    c:SetPoint("BOTTOMRIGHT", t.bar, "BOTTOMRIGHT", -(t.reach or 0), 0)
end

-- Texture lists per stroke: core, left edge, right edge. Stroke 2 is the
-- bottom half of a short mark at position BOTH.
local KEYS = { { "texs", "rimL", "rimR" }, { "twins", "rimL2", "rimR2" } }

-- One texture of a mark, made on first use (styles that skip it pay nothing).
-- WoW's pixel snap rounds each edge of a thin texture on its own, so a mark
-- whose fill edge lands between pixels could turn 1 px thinner or thicker.
-- Marks (no layer given) go in the marks clip, shading (a layer) in the tier.
local function Tex(tier, key, k, sub, layer)
    local list = tier[key]
    if not list then
        list = {}
        tier[key] = list
    end
    local tx = list[k]
    if not tx then
        tx = (layer and tier.inner or tier.marks):CreateTexture(nil, layer or "OVERLAY", nil, sub)
        if tx.SetSnapToPixelGrid then
            tx:SetSnapToPixelGrid(false)
            tx:SetTexelSnappingBias(0)
        end
        tx:AddMaskTexture(tier.mask)
        list[k] = tx
    end
    return tx
end

local function HideTex(tier, key, k)
    local list = tier[key]
    local tx = list and list[k]
    if tx then tx:Hide() end
end

-- A texture's blend mode, set only on a change (the game's default is BLEND).
local BLENDS = setmetatable({}, { __mode = "k" })
local function SetBlend(tx, mode)
    if (BLENDS[tx] or "BLEND") ~= mode then
        tx:SetBlendMode(mode)
        BLENDS[tx] = mode
    end
end

-- Multiply (MOD) may not use opacity, so the fill mask (an opacity cut) may
-- not hide it past the fill. A Multiply ramp draws in this clip frame
-- instead: the tier's area cut at the fill's right edge (the mask's). Made on
-- first use, at inner's level (under the marks, like the other ramps).
local function ModClip(t, tier)
    local c = tier.modClip
    if not c then
        c = ClipFrame(tier.inner)
        if c.SetUsingParentLevel then c:SetUsingParentLevel(true) end
        c:SetPoint("TOPLEFT", t.bar, "TOPLEFT")
        c:SetPoint("BOTTOMRIGHT", t.mask, "BOTTOMRIGHT")
        tier.modClip = c
    end
    return c
end

-- A Side Light ramp texture of block k ("segL" or "segD") in blend mode:
-- Blend and Add on inner (cut by the fill mask), Multiply in ModClip (its
-- own list, key .. "M"). The other one hides.
local function RampTex(t, tier, key, k, mode)
    if mode ~= "MOD" then
        HideTex(tier, key .. "M", k)
        local tx = Tex(tier, key, k, 0, "ARTWORK")
        SetBlend(tx, mode)
        return tx
    end
    HideTex(tier, key, k)
    local mkey = key .. "M"
    local list = tier[mkey]
    if not list then
        list = {}
        tier[mkey] = list
    end
    local tx = list[k]
    if not tx then
        tx = ModClip(t, tier):CreateTexture(nil, "ARTWORK", nil, 0)
        if tx.SetSnapToPixelGrid then
            tx:SetSnapToPixelGrid(false)
            tx:SetTexelSnappingBias(0)
        end
        SetBlend(tx, "MOD")
        list[k] = tx
    end
    return tx
end

-- An edge line and its cut parts (Rim).
local function HideRim(tier, key, k)
    HideTex(tier, key, k)
    HideTex(tier, key .. "F", k)
    HideTex(tier, key .. "B", k)
end

local function HideStroke(tier, k, s)
    local keys = KEYS[s]
    HideTex(tier, keys[1], k)
    HideRim(tier, keys[2], k)
    HideRim(tier, keys[3], k)
end

-- Puts a line x pixels right of the fill edge. pos FULL spans the bar;
-- TOP, CENTER and BOTTOM are h pixels tall.
local function Place(tx, edge, pos, x, w, h)
    tx:ClearAllPoints()
    tx:SetWidth(w)
    if pos == "FULL" then
        tx:SetPoint("TOPLEFT", edge, "TOPRIGHT", x, 0)
        tx:SetPoint("BOTTOMLEFT", edge, "BOTTOMRIGHT", x, 0)
        return
    end
    tx:SetHeight(h)
    if pos == "CENTER" then
        tx:SetPoint("LEFT", edge, "RIGHT", x, 0)
    elseif pos == "BOTTOM" then
        tx:SetPoint("BOTTOMLEFT", edge, "BOTTOMRIGHT", x, 0)
    else
        tx:SetPoint("TOPLEFT", edge, "TOPRIGHT", x, 0)
    end
end

-- A part of an edge line from y0 to y1 pixels above the bar's bottom. how:
-- "full" holds its top at the bar's top (as a FULL line does), "top" holds
-- its top there with height y1 - y0 (a TOP short mark), else it stands on y0.
local function PlacePart(tx, edge, x, w, y0, y1, how)
    tx:ClearAllPoints()
    tx:SetWidth(w)
    if how == "full" then
        tx:SetPoint("TOPLEFT", edge, "TOPRIGHT", x, 0)
        tx:SetPoint("BOTTOMLEFT", edge, "BOTTOMRIGHT", x, y0)
        return
    end
    tx:SetHeight(y1 - y0)
    if how == "top" then
        tx:SetPoint("TOPLEFT", edge, "TOPRIGHT", x, 0)
    else
        tx:SetPoint("BOTTOMLEFT", edge, "BOTTOMRIGHT", x, y0)
    end
end

-- Scratch colors for a cut edge's fade (SetGradient copies the values).
local CUT_LO, CUT_HI = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0)

-- One edge line of mark k (texture list key), x pixels right of its fill edge,
-- w wide, over pos (FULL, or h pixels at TOP, CENTER or BOTTOM), color r, g, b
-- at opacity a.
-- Double dark: a dark edge over a dark Bottom Shade (Pillow, Bevel) stacks
-- darker than both. In the band the edge keeps only the darkness the band
-- does not give already: none where the band is at least as dark, a fade
-- where the band fades. So no spot is darker than the darker of the two
-- (1 - (1 - band) * (1 - edge) at most the larger; the fade is a straight
-- line under the exact curve, so a bit lighter, never darker). Parts: key
-- above the band, key .. "F" the fade, key .. "B" a solid rest below it.
local function Rim(t, tier, key, k, edge, pos, x, w, h, r, g, b, a, show)
    local st = t.style
    local tx = Tex(tier, key, k, 0)
    local bd = st.botDark
    local H = t.h
    -- the line from lo to hi pixels above the bar's bottom
    local lo, hi, how = 0, H, "full"
    if pos == "TOP" then
        lo, how = H - h, "top"
    elseif pos == "BOTTOM" then
        hi, how = h, "bottom"
    elseif pos == "CENTER" then
        lo, hi, how = (H - h) / 2, (H + h) / 2, "bottom"
    end
    local hh, hard
    if st.bar ~= "NONE" and st.sbt > 0 and bd > 0 and Lum(r, g, b) < 0.5 then
        hh, hard = BandPixels(t, st.bsz, st.bsf)
    end
    if not hh or lo >= hh then
        Place(tx, edge, pos, x, w, h)
        tx:SetColorTexture(r, g, b, a)
        tx:SetShown(show)
        HideTex(tier, key .. "F", k)
        HideTex(tier, key .. "B", k)
        return
    end
    -- The band is bd dark up to hard, then fades to 0 at hh. The edge: a
    -- fade from eLo at gLo up to a at hh, and eLo under gLo.
    local gLo, eLo
    if bd < a then
        gLo, eLo = hard, (a - bd) / (1 - bd)
    else
        -- gone where the band is as dark as the edge: a / bd of the fade down
        -- from its top (not snapped to pixels, like the marks)
        gLo, eLo = hh - (hh - hard) * a / bd, 0
    end
    -- above the band: the edge as it is
    local y0 = math.max(lo, hh)
    if hi - y0 > 0.001 then
        PlacePart(tx, edge, x, w, y0, hi, how)
        tx:SetColorTexture(r, g, b, a)
        tx:SetShown(show)
    else
        tx:Hide()
    end
    -- the fade
    local f0, f1 = math.max(lo, gLo), math.min(hi, hh)
    if f1 - f0 > 0.001 then
        local span = hh - gLo
        local fx = Tex(tier, key .. "F", k, 0)
        PlacePart(fx, edge, x, w, f0, f1, "bottom")
        fx:SetTexture(WHITE)
        CUT_LO:SetRGBA(r, g, b, eLo + (a - eLo) * (f0 - gLo) / span)
        CUT_HI:SetRGBA(r, g, b, eLo + (a - eLo) * (f1 - gLo) / span)
        fx:SetGradient("VERTICAL", CUT_LO, CUT_HI)
        fx:SetShown(show)
    else
        HideTex(tier, key .. "F", k)
    end
    -- below the fade: a solid rest (none when the band is as dark)
    local s1 = math.min(hi, gLo)
    if eLo > 0 and s1 - lo > 0.001 then
        local bx = Tex(tier, key .. "B", k, 0)
        PlacePart(bx, edge, x, w, lo, s1, "bottom")
        bx:SetColorTexture(r, g, b, eLo)
        bx:SetShown(show)
    else
        HideTex(tier, key .. "B", k)
    end
end

-- One line of a mark plus its edge (widths in screen pixels): Shadow adds an edge
-- on its side (right or left), Outline one on each side. tall picks the tall color (and its edge color); a dark
-- bar with Light Marks On Dark Bars on (t.light) takes the light color for both.
-- short: a short mark, which takes Short Tick Edge (else Tall Tick Edge).
local function DrawStroke(t, tier, k, s, pos, w, h, a, show, tall, short)
    local st, edge, keys = t.style, tier.edges[k], KEYS[s]
    local r, g, b, e
    if t.light then
        r, g, b, e = st.lr, st.lg, st.lb, st.ler
    elseif tall then
        r, g, b, e = st.mr, st.mg, st.mb, st.mer
    else
        r, g, b, e = st.r, st.g, st.b, st.er
    end
    -- Opacity 0 draws nothing (the mark is off, only its edge may show).
    local x0 = Shift(t, w)
    if a > 0 then
        local core = Tex(tier, keys[1], k, 1)
        Place(core, edge, pos, x0, w, h)
        core:SetColorTexture(r, g, b, a)
        core:SetShown(show)
    else
        HideTex(tier, keys[1], k)
    end
    -- Edge: ew pixels wide, ed pixels away from the mark, auto (black or white,
    -- the opposite of the mark) or its own color, at its own opacity.
    local E = short and st.ME or st.E
    if not EdgeShown(t, E) then
        HideRim(tier, keys[2], k)
        HideRim(tier, keys[3], k)
        return
    end
    local ew, ed, ea = E.w, E.d, E.a
    local er, eg, eb = e, e, e
    if not E.auto then er, eg, eb = E.r, E.g, E.b end
    if EdgeLeft(E) then
        Rim(t, tier, keys[2], k, edge, pos, x0 - (ed + ew), ew, h, er, eg, eb, ea, show)
    else
        HideRim(tier, keys[2], k)
    end
    if EdgeRight(E) then
        Rim(t, tier, keys[3], k, edge, pos, x0 + w + ed, ew, h, er, eg, eb, ea, show)
    else
        HideRim(tier, keys[3], k)
    end
end

-- Every Nth mark of a tier is tall: By Health sets it per tier, the other
-- modes use Tall Tick Every Nth.
local function Every(t, tier)
    return math.max(1, tier.every or t.style.every)
end

-- Dresses one mark with the bar's current style. Marks past tier.n stay hidden.
-- A "thousands" tier (League past 10000) draws every mark in the tall color.
local function StyleMark(t, tier, k)
    local st = t.style
    local inUse = k <= tier.n
    if k % Every(t, tier) == 0 then
        DrawStroke(t, tier, k, 1, "FULL", st.width, 0, st.alpha, inUse, true)
        HideStroke(tier, k, 2)
        return
    end
    local w, h, a = st.minorW, MinorPixels(t), st.ma
    local show = inUse and st.minorH > 0
    local tall = tier.thousands
    local anchor = st.anchor
    DrawStroke(t, tier, k, 1, anchor == "BOTH" and "TOP" or anchor, w, h, a, show, tall, true)
    if anchor == "BOTH" then
        DrawStroke(t, tier, k, 2, "BOTTOM", w, h, a, show, tall, true)
    else
        HideStroke(tier, k, 2)
    end
end

-- Block k ends at mark k. Shading Blocks "ALL": every mark ends a block, from
-- mark k-1 (the bar's left for k = 1). "TALL": only a tall mark ends one (k a
-- multiple of the tier's Every), from the tall mark before it (the bar's left
-- for the first); the other marks draw no shading. Every tier's mark count is
-- a multiple of its Every (Configure), so the blocks still reach the last mark.
-- Pillow: a mark past max health sits on the bar's right edge, so the last
-- block ends there and the blocks after it have no width. Helper h spans the
-- block; at split 25 or 75 a second helper q spans one half. The light ramp
-- ends and the dark ramp starts at the middle of the last helper.
-- Bevel: the same two ramps at a fixed width (1080p pixels) from each block
-- edge, so a block looks the same at any max health.
-- The ramps' colors, blends, widths and the split come from the style (st.cL
-- ... st.cut: light from the left, or mirrored from the right; HT.MakeStyle).
-- The block edges move with Tick Offset (ox), so the shading stays with the marks.
local function StyleSegment(t, tier, k)
    local st = t.style
    local per = st.blocks == "TALL" and Every(t, tier) or 1
    if st.bar == "NONE" or k > tier.n or k % per ~= 0 then
        HideTex(tier, "segL", k)
        HideTex(tier, "segD", k)
        HideTex(tier, "segLM", k)
        HideTex(tier, "segDM", k)
        return
    end
    local ox = OffsetPx(t)
    local right = tier.edges[k]
    local left, lt, lb, lx = t.bar, "TOPLEFT", "BOTTOMLEFT", 0
    if k > per then left, lt, lb, lx = tier.edges[k - per], "TOPRIGHT", "BOTTOMRIGHT", ox end
    if st.bar == "BEVEL" then
        local l = RampTex(t, tier, "segL", k, st.bL)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", left, lt, lx, 0)
        l:SetPoint("BOTTOMLEFT", left, lb, lx, 0)
        l:SetWidth(st.wL * t.mul)
        l:SetTexture(WHITE)
        l:SetGradient("HORIZONTAL", st.cL, st.zL)
        l:SetShown(st.onL)
        local d = RampTex(t, tier, "segD", k, st.bR)
        d:ClearAllPoints()
        d:SetPoint("TOPRIGHT", right, "TOPRIGHT", ox, 0)
        d:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", ox, 0)
        d:SetWidth(st.wR * t.mul)
        d:SetTexture(WHITE)
        d:SetGradient("HORIZONTAL", st.zR, st.cR)
        d:SetShown(st.onR)
        return
    end
    local h = Tex(tier, "segH", k, 0, "ARTWORK")
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", left, lt, lx, 0)
    h:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", ox, 0)
    h:Hide()
    local mid = h
    if st.cut ~= 50 then
        local q = Tex(tier, "segQ", k, 0, "ARTWORK")
        q:ClearAllPoints()
        if st.cut == 25 then
            q:SetPoint("TOPLEFT", left, lt, lx, 0)
            q:SetPoint("BOTTOMRIGHT", h, "BOTTOM")
        else
            q:SetPoint("TOPLEFT", h, "TOP")
            q:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", ox, 0)
        end
        q:Hide()
        mid = q
    end
    local l = RampTex(t, tier, "segL", k, st.bL)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", left, lt, lx, 0)
    l:SetPoint("BOTTOMRIGHT", mid, "BOTTOM")
    l:SetTexture(WHITE)
    l:SetGradient("HORIZONTAL", st.cL, st.zL)
    l:SetShown(st.onL)
    local d = RampTex(t, tier, "segD", k, st.bR)
    d:ClearAllPoints()
    d:SetPoint("TOPLEFT", mid, "TOP")
    d:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", ox, 0)
    d:SetTexture(WHITE)
    d:SetGradient("HORIZONTAL", st.zR, st.cR)
    d:SetShown(st.onR)
end

-- One shading texture over the fill (on the bar-sized fill clip, cut by the
-- fill mask), made on first use and kept in t[name].
local function FillTex(t, name, sub)
    local tx = t[name]
    if not tx then
        tx = t.fillClip:CreateTexture(nil, "ARTWORK", nil, sub)
        tx:SetTexture(WHITE)
        tx:AddMaskTexture(t.mask)
        t[name] = tx
    end
    return tx
end

local function HideFill(t, name)
    local tx = t[name]
    if tx then tx:Hide() end
end

-- A band along the top (top true) or the bottom of the fill, size percent of
-- the bar height (a plain number: our own frame). Softness 1 fades it from c at
-- the bar's edge to z over the whole band (the first look); less makes the
-- part at the edge (hardName) one solid c and fades only the rest (softName).
-- mode: its blend. A Multiply band ends at the fill's right edge (the mask's),
-- as the mask may not cut it (see ModClip).
local function Band(t, hardName, softName, top, size, soft, c, z, mode)
    local clip = t.fillClip
    local right = mode == "MOD" and t.mask or clip
    local hh, hard = BandPixels(t, size, soft)
    local fade = hh - hard
    local p1, p2, dy = "BOTTOMLEFT", "BOTTOMRIGHT", hard
    if top then p1, p2, dy = "TOPLEFT", "TOPRIGHT", 0 - hard end   -- 0 - hard: never -0
    if hard > 0 then
        local tx = FillTex(t, hardName, -1)
        tx:ClearAllPoints()
        tx:SetPoint(p1, clip, p1)
        tx:SetPoint(p2, right, p2)
        tx:SetHeight(hard)
        tx:SetGradient("VERTICAL", c, c)
        SetBlend(tx, mode)
        tx:Show()
    else
        HideFill(t, hardName)
    end
    if fade > 0 then
        local tx = FillTex(t, softName, -1)
        tx:ClearAllPoints()
        tx:SetPoint(p1, clip, p1, 0, dy)
        tx:SetPoint(p2, right, p2, 0, dy)
        tx:SetHeight(fade)
        if top then tx:SetGradient("VERTICAL", z, c) else tx:SetGradient("VERTICAL", c, z) end
        SetBlend(tx, mode)
        tx:Show()
    else
        HideFill(t, softName)
    end
end

-- One half of the Bar Gradient: name's texture from p1 to p2 of the bar (its
-- points: the halves meet at its middle), a fade along how, from c1 to c2,
-- in blend mode (BLEND or ADD; set only on a change, kept in t.blend).
local function Half(t, name, p1, r1, p2, r2, how, c1, c2, mode)
    local clip = t.fillClip
    local tx = FillTex(t, name, -2)
    tx:ClearAllPoints()
    tx:SetPoint(p1, clip, r1)
    tx:SetPoint(p2, clip, r2)
    tx:SetGradient(how, c1, c2)
    local blend = t.blend
    if not blend then
        blend = {}
        t.blend = blend
    end
    if (blend[name] or "BLEND") ~= mode then
        tx:SetBlendMode(mode)
        blend[name] = mode
    end
    tx:Show()
end

-- Bar Gradient over the whole bar (the fill shows its part): across, the
-- start color at one edge fading to nothing at the middle, then to the end
-- color at the other edge (gx plus: the end color on the right); up the same
-- (gy plus: the end color on top). The two parts add up to a fade at the
-- angle. Each fade is two halves, so no width or height is computed. A half
-- fades to its own color at none, so no other color shows at the middle.
-- Blend ADD adds the colors' light (a dark color adds almost nothing).
local function Gradient(t)
    local st = t.style
    local on = st.bar ~= "NONE"
    local mode = st.gb
    if on and st.gx ~= 0 then
        local S, S0, E, E0 = st.gxS, st.gxS0, st.gxE, st.gxE0
        if st.gx > 0 then
            Half(t, "grL", "TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOM", "HORIZONTAL", S, S0, mode)
            Half(t, "grR", "TOPLEFT", "TOP", "BOTTOMRIGHT", "BOTTOMRIGHT", "HORIZONTAL", E0, E, mode)
        else
            Half(t, "grL", "TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOM", "HORIZONTAL", E, E0, mode)
            Half(t, "grR", "TOPLEFT", "TOP", "BOTTOMRIGHT", "BOTTOMRIGHT", "HORIZONTAL", S0, S, mode)
        end
    else
        HideFill(t, "grL")
        HideFill(t, "grR")
    end
    if on and st.gy ~= 0 then
        -- VERTICAL: the first color at the bottom
        local S, S0, E, E0 = st.gyS, st.gyS0, st.gyE, st.gyE0
        if st.gy > 0 then
            Half(t, "grB", "TOPLEFT", "LEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", "VERTICAL", S, S0, mode)
            Half(t, "grT", "TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "RIGHT", "VERTICAL", E0, E, mode)
        else
            Half(t, "grB", "TOPLEFT", "LEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", "VERTICAL", E, E0, mode)
            Half(t, "grT", "TOPLEFT", "TOPLEFT", "BOTTOMRIGHT", "RIGHT", "VERTICAL", S0, S, mode)
        end
    else
        HideFill(t, "grB")
        HideFill(t, "grT")
    end
end

-- Pillow and Bevel top light, bottom shade and bar gradient over the fill.
local function StyleShade(t)
    local st = t.style
    local on = st.bar ~= "NONE"
    if on and st.stp > 0 then
        Band(t, "shTopH", "shTop", true, st.tsz, st.tsf, st.topC, st.topZ, st.tcm)
    else
        HideFill(t, "shTopH")
        HideFill(t, "shTop")
    end
    if on and st.sbt > 0 then
        Band(t, "shBotH", "shBot", false, st.bsz, st.bsf, st.botC, st.botZ, st.bcm)
    else
        HideFill(t, "shBotH")
        HideFill(t, "shBot")
    end
    Gradient(t)
end

local function StyleTier(t, tier)
    for k = 1, #tier.bars do
        StyleMark(t, tier, k)
        StyleSegment(t, tier, k)
    end
end

-- Short marks follow the bar height (a plain number: our own frame).
-- Tall marks span the bar, but their edges cut at Bottom Shade (Rim) follow
-- its pixel height too.
local function ApplyHeights(t, bar)
    t.h = BarPixels(t, bar)
    local st = t.style
    local all = st.bar ~= "NONE" and st.botDark > 0
    for i = 1, #t.tiers do
        local tier = t.tiers[i]
        local every = Every(t, tier)
        for k = 1, #tier.bars do
            if all or k % every ~= 0 then StyleMark(t, tier, k) end
        end
    end
    StyleShade(t)
end

local function NewTier(t, bar)
    local tier = { bars = {}, edges = {}, texs = {}, twins = {}, rimL = {}, rimR = {}, rimL2 = {}, rimR2 = {},
        segL = {}, segD = {}, segH = {}, segQ = {}, n = 0, mask = t.mask }
    -- outer: shown while max health <= this step's top (its probe empty).
    tier.outer = ClipFrame(t.fillClip)
    tier.outer:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
    -- inner: shown while max health > the finer step's top (anchored on use).
    tier.inner = ClipFrame(tier.outer)
    -- marks: the marks (the shading stays on inner), at inner's level, so they
    -- draw where they did; it stops t.reach short of the bar's right edge.
    tier.marks = ClipFrame(tier.inner)
    if tier.marks.SetUsingParentLevel then tier.marks:SetUsingParentLevel(true) end
    AnchorMarks(t, tier)
    tier.probe = HiddenBar(t.base, bar)
    local fill = tier.probe:GetStatusBarTexture()
    tier.outer:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    return tier
end

-- Makes mark bars up to n (a tier only grows; extra marks stay hidden).
local function GrowTier(t, tier, bar, n)
    for k = #tier.bars + 1, n do
        local sb = HiddenBar(t.base, bar)
        tier.bars[k] = sb
        tier.edges[k] = sb:GetStatusBarTexture()
    end
end

local function OnBarSize(bar)
    local t = STATE[bar]
    if t and t.shown then ApplyHeights(t, bar) end
end

-- Runs after each of these calls on a bar with marks. Some of them make a new
-- fill object: a texture path swap and SetFillStyle do, the others may. The
-- unit frames make these calls on every reload of their settings (options,
-- profile, UI scale). The mask must move to the new fill: on the old one it no
-- longer follows health and can hide every mark. A new unit or max health
-- pushes again and heals it too, but the player frame gets neither for a long
-- time. Only compares the fill object; a hidden bar does nothing.
local FILL_CALLS = { "SetStatusBarTexture", "SetFillStyle", "SetReverseFill", "SetOrientation", "SetRotatesTexture" }
local function OnBarFill(bar)
    local t = STATE[bar]
    if not (t and t.shown and t.fillTex) then return end
    local fill = bar:GetStatusBarTexture()
    if fill == t.fillTex then return end
    AnchorFill(t, bar, fill)
end

-- Light Marks On Dark Bars: true when the bar color is darker than st.dark, nil
-- when the color is secret (a mirrored class color, an off-tank fold, a curve)
-- and cannot be read; the bar then keeps its last look.
local function IsDark(st, r, g, b)
    if issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b)) then return nil end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return (0.299 * r + 0.587 * g + 0.114 * b) < st.dark
end

-- Runs after every SetStatusBarColor on a bar that has had Light Marks On Dark
-- Bars on (the hook is placed then, never before). Recolors only on a flip; a
-- hidden bar does nothing (the next push reads the color).
local function OnBarColor(bar, r, g, b)
    local t = STATE[bar]
    local st = t and t.style
    if not (st and t.shown and st.auto) then return end
    local dark = IsDark(st, r, g, b)
    if dark == nil or dark == t.light then return end
    t.light = dark
    -- An Outline edge that shows only with light marks changes the reach.
    local reach = MarkReach(t)
    if t.reach ~= reach then
        t.reach = reach
        for i = 1, #t.tiers do AnchorMarks(t, t.tiers[i]) end
    end
    for i = 1, #t.tiers do
        local tier = t.tiers[i]
        for k = 1, #tier.bars do StyleMark(t, tier, k) end
    end
end

-- By Health's two tiers (in t.health*): the small step, with every (tall step /
-- small step)th mark tall, shown while max health is below Hide Small Ticks At;
-- then the tall step, every mark tall. A tier's count is a whole multiple of
-- its every, so Shading Blocks "TALL" reaches its last mark; its top (the max
-- health it shows up to) can be lower than count * step.
local function HealthSteps(t, st)
    local s, tl, hide = st.hs, st.ht, st.hh
    local per = math.max(1, math.floor(tl / s + 0.5))
    local n1 = per * math.max(1, math.floor(HEALTH_MARKS / per))
    local top1 = n1 * s
    if hide > 0 then
        -- marks up to the first tall mark at or past Hide Small Ticks At - 1
        local need = per * math.max(1, math.ceil((hide - 1) / s / per))
        if need < n1 then n1 = need end
        top1 = math.min(n1 * s, hide - 1)
    end
    local steps, counts, tops, everys = t.health, t.healthN, t.healthTop, t.healthEvery
    steps[1], counts[1], tops[1], everys[1] = s, n1, top1, per
    steps[2], counts[2], tops[2], everys[2] = tl, HEALTH_MARKS, HEALTH_MARKS * tl, 1
    return steps, counts, tops, everys
end

-- The tiers depend on the mode, the Tick Density (Auto) and, By Health, its
-- three values: a change of any of them sets the tiers up again.
local function ModeKey(mode, st)
    if mode == "health" then return "health:" .. st.hs .. ":" .. st.ht .. ":" .. st.hh end
    if mode == "auto" then return "auto:" .. st.marks end
    return mode
end

-- Points the tiers at the step list for this mode ("health", "league", "auto"
-- or a fixed step).
local function Configure(t, bar, mode, st)
    local steps, counts = t.fixed, t.fixedN
    local tops, everys
    local fixedStep = tonumber(mode)
    if fixedStep then
        steps[1], counts[1] = fixedStep, FIXED_MARKS
    elseif mode == "league" then
        steps, counts = LEAGUE_STEPS, LEAGUE_MARKS
    elseif mode == "health" then
        steps, counts, tops, everys = HealthSteps(t, st)
    else
        steps, counts = AUTO_STEPS, t.autoN
        for i = 1, #steps do counts[i] = st.marks end
    end
    for i = 1, #steps do
        local tier = t.tiers[i]
        if not tier then
            tier = NewTier(t, bar)
            t.tiers[i] = tier
        end
        local n = counts[i]
        tier.step, tier.n = steps[i], n
        tier.every = everys and everys[i] or nil
        tier.thousands = (mode == "league" and i > 1)
        GrowTier(t, tier, bar, n)
        StyleTier(t, tier)
        local top = tops and tops[i] or n * steps[i]
        tier.probe:SetMinMaxValues(top, top + 1)
        tier.inner:ClearAllPoints()
        if i == 1 then
            tier.inner:SetAllPoints(bar)
        else
            local finer = t.tiers[i - 1].probe:GetStatusBarTexture()
            tier.inner:SetPoint("TOPLEFT", bar, "TOPLEFT")
            tier.inner:SetPoint("BOTTOMRIGHT", finer, "BOTTOMRIGHT")
        end
        tier.outer:Show()
    end
    for i = #steps + 1, #t.tiers do t.tiers[i].outer:Hide() end
    t.count, t.mode = #steps, ModeKey(mode, st)
end

function HT.Hide(bar)
    local t = STATE[bar]
    if t then t.base:Hide(); t.shown = false end
end

-- After a loading screen a push can run in the first frame, before the game has
-- laid the frames out. Redo makes the next Push build it all again (tiers,
-- heights, the fill mask), and gives every hidden bar of ours another value
-- first, so the game lays each fill out anew when Push sets the real one. Our
-- own frames only.
function HT.Redo(bar)
    local t = STATE[bar]
    if not t then return end
    t.mode, t.fillTex, t.redo = nil, nil, true
    for i = 1, #t.tiers do
        local tier = t.tiers[i]
        local _, hi = tier.probe:GetMinMaxValues()
        if type(hi) == "number" and not (issecretvalue and issecretvalue(hi)) then tier.probe:SetValue(hi) end
        local bars = tier.bars
        for k = 1, #bars do bars[k]:SetValue(0) end
    end
end

-- maxHP may be secret: it only ever reaches SetMinMaxValues / SetValue.
-- Callers push on a new unit and on a max health change, not per paint.
-- lvl: frame level of the marks above the bar, read on first use only (default 2;
-- the marks draw two levels higher, above Health Animations pieces drawn over the
-- absorbs). style: a table from HT.MakeStyle (built once per settings refresh);
-- nil = defaults.
function HT.Push(bar, maxHP, mode, lvl, style)
    local t = STATE[bar]
    if not t then
        local base = CreateFrame("Frame", nil, bar)
        base:SetAllPoints(bar)
        base:SetFrameLevel(bar:GetFrameLevel() + (lvl or 2))
        -- One base unit = one physical pixel, whatever scale the bar carries (UI
        -- scale, plate scale, target and cast scaling): a mark keeps a whole-pixel
        -- width wherever its fill edge lands. Anchors still follow the bar.
        base:SetIgnoreParentScale(true)
        -- mul: one 1080p pixel in base units (2 at 4K). Only Tick Offset and the
        -- Bevel widths use it; mark and edge widths are plain screen pixels.
        local tall = PP and PP.physicalHeight or 1080
        -- The clip keeps the base's level, so the marks stay at base + 2. It
        -- keeps the bar's size; the fill mask (AnchorFill) does Only On Health.
        local fillClip = ClipFrame(base)
        if fillClip.SetUsingParentLevel then fillClip:SetUsingParentLevel(true) end
        fillClip:SetAllPoints(bar)
        -- Clamp to black: nothing shows past the mask. Nearest: a sharp edge
        -- (a linear filter would fade the 8 texels over 1/16 of the fill).
        local mask = fillClip:CreateMaskTexture()
        mask:SetTexture(WHITE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
        if mask.SetSnapToPixelGrid then
            mask:SetSnapToPixelGrid(false)
            mask:SetTexelSnappingBias(0)
        end
        mask:SetAllPoints(bar)
        t = { base = base, bar = bar, fillClip = fillClip, mask = mask, tiers = {}, fixed = {}, fixedN = {}, autoN = {},
              health = {}, healthN = {}, healthTop = {}, healthEvery = {},
              mul = math.max(1, math.floor(tall / 1080 + 0.5)) }
        STATE[bar] = t
        bar:HookScript("OnSizeChanged", OnBarSize)
        for i = 1, #FILL_CALLS do
            if bar[FILL_CALLS[i]] then hooksecurefunc(bar, FILL_CALLS[i], OnBarFill) end
        end
    end
    local scale = PP and PP.perfect or 1
    if t.scale ~= scale then
        t.base:SetScale(scale)
        t.scale = scale
    end
    local barPx = BarPixels(t, bar)
    if not barPx then
        -- Never read (the game forbids it or hides it): no marks until a
        -- later push can read it.
        t.base:Hide()
        t.shown = false
        return
    end
    if not style then
        defaultStyle = defaultStyle or HT.MakeStyle(EMPTY)
        style = defaultStyle
    end
    local light = false
    if style.auto then
        if not t.hooked then
            hooksecurefunc(bar, "SetStatusBarColor", OnBarColor)
            t.hooked = true
        end
        light = IsDark(style, bar:GetStatusBarColor())
        if light == nil then light = t.light or false end
    end
    if t.style ~= style or t.light ~= light or t.redo then
        t.redo = nil
        t.h = barPx
        t.style = style
        t.light = light
        local reach = MarkReach(t)
        if t.reach ~= reach then
            t.reach = reach
            for i = 1, #t.tiers do AnchorMarks(t, t.tiers[i]) end
        end
        for i = 1, #t.tiers do StyleTier(t, t.tiers[i]) end
        StyleShade(t)
    end
    if t.mode ~= ModeKey(mode, style) then Configure(t, bar, mode, style) end
    -- Pillow and Bevel shading always stay on the fill.
    local fill = (style.fill or style.bar ~= "NONE") and bar:GetStatusBarTexture() or nil
    if t.fillTex ~= fill then AnchorFill(t, bar, fill) end
    t.base:Show()
    t.shown = true
    if t.h ~= barPx then ApplyHeights(t, bar) end
    for i = 1, t.count do
        local tier = t.tiers[i]
        local step = tier.step
        tier.probe:SetValue(maxHP)
        local bars = tier.bars
        for k = 1, tier.n do
            local sb = bars[k]
            sb:SetMinMaxValues(0, maxHP)
            sb:SetValue(k * step)
        end
    end
end

-------------------------------------------------------------------------------
--  Settings: EllesmereUI.GetHealthTicksDB() is the active profile's table,
--  sparse (a missing key is the default). A read never writes.
--    { look = { [healthTick* key] = value }, places = { [placeId] = true } }
--  One look for every place; a place is on only while places[id] == true.
-------------------------------------------------------------------------------
local function ActiveProfile()
    local db = EllesmereUIDB
    local profiles = db and db.profiles
    return profiles and profiles[db.activeProfile or "Default"]
end

function EllesmereUI.GetHealthTicksDB(create)
    local active = ActiveProfile()
    if not active then return nil end
    if create and type(active.healthTicks) ~= "table" then active.healthTicks = {} end
    return active.healthTicks
end

-- The saved look (never nil, read only).
function HT.SavedLook()
    local db = EllesmereUI.GetHealthTicksDB()
    local look = db and db.look
    if type(look) ~= "table" then return EMPTY end
    return look
end

-- A saved value, else the default.
function HT.GetLook(key)
    local v = HT.SavedLook()[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

-- Tall Tick Color false (a preset's "follow Tick Color") is stored as unset.
local function WriteLook(db, key, value)
    if not KEY_SET[key] then return end
    local look = db.look
    if type(look) ~= "table" then
        look = {}
        db.look = look
    end
    if value == false and key == "healthTickMajorColor" then value = nil end
    look[key] = CopyValue(value)
end

function HT.SetLook(key, value)
    local db = EllesmereUI.GetHealthTicksDB(true)
    if not db then return end
    WriteLook(db, key, value)
    HB.QueueRefresh()
end

function HT.SetLookMany(tbl)
    local db = EllesmereUI.GetHealthTicksDB(true)
    if not db then return end
    for k, v in pairs(tbl) do WriteLook(db, k, v) end
    HB.QueueRefresh()
end

function HT.ResetLook()
    local db = EllesmereUI.GetHealthTicksDB()
    if db then db.look = nil end
    HB.QueueRefresh()
end

function HT.PlaceOn(place)
    local db = EllesmereUI.GetHealthTicksDB()
    local places = db and db.places
    return type(places) == "table" and places[place] == true
end

function HT.SetPlace(place, on)
    if not HB.PLACE[place] then return end
    local db = EllesmereUI.GetHealthTicksDB(true)
    if not db then return end
    if type(db.places) ~= "table" then db.places = {} end
    db.places[place] = on and true or nil
    HB.QueueRefresh()
end

-------------------------------------------------------------------------------
--  Bar feature (EllesmereUI.HealthBars): draws on the places that are on
-------------------------------------------------------------------------------
-- Frame levels of the marks above the bar.
local LVL = { enemy = 2, friendly = 2, raid = 5, party = 5 }

-- Health Tick Step as HT.Push takes it: "health", a fixed step, "auto" or
-- "league" (Fixed).
function HT.TickStep(v)
    if v == "health" then return "health" end
    local n = tonumber(v)
    if n then return n end
    if v == "auto" then return "auto" end
    return "league"
end

local CFG = {}                                   -- CFG[place] = { on, step, lvl, style }
local ST = setmetatable({}, { __mode = "k" })    -- ST[bar] = { style, step } drawn with
local sharedStyle                                -- the one look's style, kept while unchanged

local feature = {}

function feature.Resolve()
    local db = EllesmereUI.GetHealthTicksDB()
    local places = db and db.places
    if type(places) ~= "table" then places = EMPTY end
    local style, step
    for _, def in ipairs(HB.PLACES) do
        local id = def.id
        local c = CFG[id]
        if not c then
            c = {}
            CFG[id] = c
        end
        c.on = places[id] == true
        if c.on then
            if not style then
                local look = HT.SavedLook()
                style = HT.MakeStyle(look, sharedStyle)
                sharedStyle = style
                step = HT.TickStep(look.healthTickStep == nil and DEFAULTS.healthTickStep or look.healthTickStep)
            end
            c.step, c.lvl, c.style = step, LVL[id] or 5, style
        end
    end
end

function feature.Wants(place)
    local c = CFG[place]
    return c and c.on or false
end

function feature.Apply(bar, e, force)
    local c = CFG[e.place]
    local st = ST[bar]
    if not st then
        st = {}
        ST[bar] = st
    end
    if force or st.style ~= c.style or st.step ~= c.step then
        HT.Push(bar, UnitHealthMax(e.unit), c.step, c.lvl, c.style)
        st.style, st.step = c.style, c.step
    end
end

function feature.Clear(bar)
    if ST[bar] then
        HT.Hide(bar)
        ST[bar] = nil
    end
end

function feature.Redo(bar)
    if ST[bar] then HT.Redo(bar) end
end

function feature.Drawn(bar)
    return ST[bar] ~= nil
end

HB.AddFeature(feature)
