if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_HealthTicks_Options.lua -- Global Settings > Health Ticks. The places
--  that draw ticks and the shared look (EllesmereUI_HealthTicks.lua): marks,
--  steps, tick edge and tick bar style, with presets and a live preview bar in
--  the page header. The preview's health and bar color are session state, never
--  saved. Every look value lives in the active profile's healthTicks table.
--  Module pages put their own switch in a row with EllesmereUI.HealthTicksPlaceCfg.
--  eui-style: allow comment-budget (file header below the client gate)
-------------------------------------------------------------------------------
local HT = EllesmereUI.HealthTicks
local HB = EllesmereUI.HealthBars
if not (HT and HB) then return end

-- The preview bar is ours: it carries tick frames the options page pool must not
-- reset, so it is made with the plain CreateFrame; everything else is pooled
-- (EllesmereUI_FramePool.lua).
local PlainCreateFrame = CreateFrame
local CreateFrame = EllesmereUI._Pool.CreateFrame

local GLOBAL_KEY = "_EUIGlobal"
local PAGE_TICKS = "Health Ticks"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local DEFAULTS = HT.DEFAULTS
local STYLE_KEYS = HT.STYLE_KEYS

local function Get(key) return HT.GetLook(key) end

-- Repaints the header's preview and controls; set by the header builder.
local headerRefresh

local function Repaint()
    if headerRefresh then headerRefresh() end
end

local function Set(key, value)
    HT.SetLook(key, value)
    Repaint()
end

local function SetMany(tbl)
    HT.SetLookMany(tbl)
    Repaint()
end

local function ColorGet(key)
    return function()
        local c = Get(key)
        if type(c) ~= "table" then c = DEFAULTS[key] end
        return c.r or 0, c.g or 0, c.b or 0
    end
end

local function ColorSet(key)
    return function(r, g, b) Set(key, { r = r, g = g, b = b }) end
end

-------------------------------------------------------------------------------
--  Presets. A preset is a table of look keys; the dropdown shows the first
--  preset whose keys all match the look, else Custom. They never set Health
--  Tick Step, Tick Density or Tall Tick Every: those change what a mark means,
--  not its look. healthTickMajorColor = false: Tall Tick Color follows Tick Color.
-------------------------------------------------------------------------------
local C_BLACK = { r = 0, g = 0, b = 0 }
local C_WHITE = { r = 1, g = 1, b = 1 }
local C_PALE  = { r = 0.75, g = 0.75, b = 0.75 }
local C_DARK  = { r = 0.1315082130897071, g = 0.1315082130897071, b = 0.1315082130897071 }
local C_LIGHT = { r = 0.5235710478504771, g = 0.5235710478504771, b = 0.5235710478504771 }

-- Equal setting values: color tables by r, g, b within 0.002, numbers within
-- 0.001, anything else by ==.
local function SameValue(a, b)
    local ta, tb = type(a), type(b)
    if ta == "table" and tb == "table" then
        return math.abs((a.r or 0) - (b.r or 0)) < 0.002
            and math.abs((a.g or 0) - (b.g or 0)) < 0.002
            and math.abs((a.b or 0) - (b.b or 0)) < 0.002
    end
    if ta == "number" and tb == "number" then
        return math.abs(a - b) < 0.001
    end
    return a == b
end

-- The first preset (in order) whose keys all match get(key), or "custom".
local function MatchPreset(presets, order, get)
    for i = 1, #order do
        local name = order[i]
        local ok = true
        for k, v in pairs(presets[name]) do
            if not SameValue(get(k), v) then ok = false; break end
        end
        if ok then return name end
    end
    return "custom"
end

-- Marks: every preset sets these same 10 keys.
local MARK_PRESET_ORDER = { "classic", "subtle", "league", "bold", "tallonly", "framed" }
local MARK_PRESET_NAMES = { classic = "Classic", subtle = "Subtle", league = "League", bold = "Bold",
    tallonly = "Tall Only", framed = "Framed", custom = "Custom" }
local function Marks(w, a, mw, mh, ma, anchor, c, mc, auto, lc)
    return { healthTickWidth = w, healthTickAlpha = a, healthTickMinorWidth = mw,
        healthTickMinorHeight = mh, healthTickMinorAlpha = ma, healthTickMinorAnchor = anchor,
        healthTickColor = c, healthTickMajorColor = mc, healthTickAutoLight = auto,
        healthTickLightColor = lc }
end
local MARK_PRESETS = {
    classic  = Marks(1, 45,  1, 35, 70, "TOP",  C_DARK,  false,  true, C_LIGHT),
    subtle   = Marks(1, 35,  1, 30, 25, "TOP",  C_BLACK, false,  true, C_LIGHT),
    league   = Marks(2, 90,  1, 50, 70, "TOP",  C_BLACK, false,  true, C_LIGHT),
    bold     = Marks(2, 100, 2, 50, 85, "TOP",  C_BLACK, false,  true, C_PALE),
    tallonly = Marks(1, 25,  1, 35, 0,  "TOP",  C_DARK,  false,  true, C_LIGHT),
    framed   = Marks(1, 100, 1, 30, 20, "BOTH", C_BLACK, C_DARK, true, C_WHITE),
}

local EDGE_PRESET_ORDER = { "none", "softshadow", "shadow", "halo", "outline" }
local EDGE_PRESET_NAMES = { none = "None", softshadow = "Soft Shadow", shadow = "Shadow",
    halo = "Halo", outline = "Outline", custom = "Custom" }
local function Edge(mode, a)
    return { healthTickEdge = mode, healthTickEdgeWidth = 1, healthTickEdgeDistance = 0,
        healthTickEdgeAlpha = a, healthTickEdgeAuto = true }
end
local EDGE_PRESETS = {
    none = { healthTickEdge = "NONE" },
    softshadow = Edge("SHADOW", 40),
    shadow     = Edge("SHADOW", 90),
    halo       = Edge("OUTLINE", 30),
    outline    = Edge("OUTLINE", 90),
}
-- The same presets for Short Tick Edge (its own keys). A preset leaves the
-- Shadow side as it is.
local SHORT_EDGE_PRESETS = {}
for name, p in pairs(EDGE_PRESETS) do
    local s = {}
    for k, v in pairs(p) do s[(k:gsub("^healthTickEdge", "healthTickMinorEdge"))] = v end
    SHORT_EDGE_PRESETS[name] = s
end

local STYLE_PRESET_ORDER = { "none", "softpillow", "roundpillow", "softbevel", "glassbevel", "carvedbevel" }
local STYLE_PRESET_NAMES = { none = "Marks Only", softpillow = "Soft Pillow", roundpillow = "Rounded Pillow",
    softbevel = "Soft Bevel", glassbevel = "Glass Bevel", carvedbevel = "Carved Bevel", custom = "Custom" }
-- A style preset also sets Light Direction, the band sizes and softness, Bar
-- Gradient and the light and shade colors and blends to these values. It leaves
-- Gradient Angle, which shows nothing while Bar Gradient is 0.
local STYLE_BASE = { dir = -90, topSize = 55, topSoft = 100, bottomSize = 55, bottomSoft = 100, grad = 0,
    lightColor = C_WHITE, lightBlend = "BLEND", shadeColor = C_BLACK, shadeBlend = "BLEND",
    topColor = C_WHITE, topBlend = "BLEND", bottomColor = C_BLACK, bottomBlend = "BLEND" }
local function Extras(p, style)
    local K = STYLE_KEYS[style]
    for name, v in pairs(STYLE_BASE) do p[K[name]] = v end
    return p
end
local function Pillow(l, split, s, top, bot, a)
    return Extras({ healthTickBarStyle = "PILLOW", healthTickPillowLight = l, healthTickPillowSplit = split,
        healthTickPillowShade = s, healthTickShadeTop = top, healthTickShadeBottom = bot,
        healthTickPillowAlpha = a }, "PILLOW")
end
local function Bevel(l, lw, s, sw, top, bot)
    return Extras({ healthTickBarStyle = "BEVEL", healthTickBevelLight = l, healthTickBevelLightWidth = lw,
        healthTickBevelShade = s, healthTickBevelShadeWidth = sw, healthTickBevelTop = top,
        healthTickBevelBottom = bot, healthTickBevelAlpha = 100 }, "BEVEL")
end
local STYLE_PRESETS = {
    none        = { healthTickBarStyle = "NONE" },
    softpillow  = Pillow(12, 75, 21, 15, 43, 55),
    roundpillow = Pillow(15, 50, 30, 40, 60, 55),
    softbevel   = Bevel(16, 3, 30, 4, 0, 0),
    glassbevel  = Bevel(30, 2, 22, 5, 26, 12),
    carvedbevel = Bevel(10, 2, 55, 2, 0, 30),
}

-- The value a preset compares with. Tall Tick Color: false (follow Tick Color)
-- when it is unset or equals Tick Color, as the presets store it.
local function PresetGet(k)
    if k == "healthTickMajorColor" then
        local c = Get(k)
        if type(c) ~= "table" or SameValue(c, Get("healthTickColor")) then return false end
        return c
    end
    return Get(k)
end

-- A dropdown of presets: shows the preset whose keys all match the look (else
-- Custom, which is not listed) and writes a picked preset to it.
local function PresetRow(label, tooltip, presets, order, names)
    return { type = "dropdown", label = label, tooltip = tooltip,
        values = names, order = order,
        get = function() return MatchPreset(presets, order, PresetGet) end,
        set = function(v)
            if presets[v] then SetMany(presets[v]) end
        end }
end

-------------------------------------------------------------------------------
--  Rows. A row is { type, label, tooltip, get, set, ... } and becomes one half
--  of a W:DualRow; a row with `cog` ({ title, rows, disabled, disabledTooltip })
--  carries a settings popup left of its control.
-------------------------------------------------------------------------------
local function Cfg(row)
    local c = {
        type = row.type, text = row.label, tooltip = row.tooltip,
        disabled = row.disabled, disabledTooltip = row.disabledTooltip, requireState = row.requireState,
        min = row.min, max = row.max, step = row.step,
        values = row.values, order = row.order,
        getValue = row.get,
    }
    local set = row.set
    if row.type == "toggle" or row.type == "dropdown" then
        -- Rows gated by this one follow.
        c.setValue = function(...)
            set(...)
            EllesmereUI:RefreshPage()
        end
    else
        c.setValue = set
    end
    return c
end

-- The rows of a cog popup, copied: a toggle's or dropdown's set also refreshes
-- the page (the popup only redraws itself), so the rows gated by it follow.
local function CogRows(rows)
    local out = {}
    for i, row in ipairs(rows) do
        local c = {}
        for k, v in pairs(row) do c[k] = v end
        if (c.type == "toggle" or c.type == "dropdown") and c.set then
            local set = c.set
            c.set = function(...)
                set(...)
                EllesmereUI:RefreshPage()
            end
        end
        out[i] = c
    end
    return out
end

local function AddCog(rgn, cog)
    EllesmereUI.BuildInlineCog(rgn, {
        title = cog.title, rows = CogRows(cog.rows),
        disabled = cog.disabled, disabledTooltip = cog.disabledTooltip,
    })
end

-- list = { { left, right }, ... }: one DualRow per pair (a missing right is
-- blank), then the cogs of the rows that have one. Returns the new y.
local function Pairs(W, parent, y, list)
    for _, pair in ipairs(list) do
        local l, r = pair[1], pair[2]
        local row, h = W:DualRow(parent, y, Cfg(l), r and Cfg(r) or EllesmereUI.BlankRowCfg())
        if not EllesmereUI._prebuilding then
            if l.cog then AddCog(row._leftRegion, l.cog) end
            if r and r.cog then AddCog(row._rightRegion, r.cog) end
        end
        y = y - h
    end
    return y
end

-- A dropdown value: a saved number that is not listed shows as itself.
local function Listed(values, v)
    local s = tostring(v)
    if values[s] == nil then values[s] = BreakUpLargeNumbers(tonumber(v) or 0) end
    return s
end

local function Slider(label, key, min, max, step, tooltip)
    return { type = "slider", label = label, min = min, max = max, step = step, tooltip = tooltip,
        get = function() return Get(key) end,
        set = function(v) Set(key, v) end }
end

-------------------------------------------------------------------------------
--  MARKS
-------------------------------------------------------------------------------
local function MarkPairs()
    local function autoOff() return not Get("healthTickAutoLight") end
    return {
        { PresetRow("Marks Preset", "Sets the look of the marks, not their spacing.",
              MARK_PRESETS, MARK_PRESET_ORDER, MARK_PRESET_NAMES),
          { type = "colorpicker", label = "Tick Color",
            tooltip = "Color of the short marks, and of the tall marks until Tall Tick Color is set.",
            get = ColorGet("healthTickColor"), set = ColorSet("healthTickColor") } },
        { { type = "colorpicker", label = "Tall Tick Color",
            tooltip = "Color of the tall marks; follows Tick Color until set.",
            get = function()
                local c = Get("healthTickMajorColor")
                if type(c) ~= "table" then c = Get("healthTickColor") end
                return c.r or 0, c.g or 0, c.b or 0
            end,
            set = ColorSet("healthTickMajorColor") },
          { type = "toggle", label = "Light Marks On Dark Bars",
            tooltip = "Bars darker than Dark Bar Below get light marks.",
            get = function() return Get("healthTickAutoLight") end,
            set = function(v) Set("healthTickAutoLight", v) end,
            cog = { title = "Light Marks", disabled = autoOff,
                disabledTooltip = "Light Marks On Dark Bars",
                rows = {
                    { type = "colorpicker", label = "Light Mark Color",
                      get = ColorGet("healthTickLightColor"), set = ColorSet("healthTickLightColor") },
                    Slider("Dark Bar Below", "healthTickDarkBelow", 10, 100, 5,
                        "Bar brightness in percent. Darker bars get the light marks."),
                } } } },
        { Slider("Tall Tick Width", "healthTickWidth", 1, 25, 1, "In screen pixels."),
          Slider("Tall Tick Opacity", "healthTickAlpha", 0, 100, 5, "0 turns the tall marks off.") },
        { Slider("Short Tick Width", "healthTickMinorWidth", 1, 25, 1, "In screen pixels."),
          Slider("Short Tick Height", "healthTickMinorHeight", 0, 100, 5, "Percent of the bar height.") },
        { Slider("Short Tick Opacity", "healthTickMinorAlpha", 0, 100, 5, "0 turns the short marks off."),
          { type = "dropdown", label = "Short Tick Position",
            values = { TOP = "Top", CENTER = "Center", BOTTOM = "Bottom", BOTH = "Top and Bottom" },
            order = { "TOP", "CENTER", "BOTTOM", "BOTH" },
            get = function() return Get("healthTickMinorAnchor") end,
            set = function(v) Set("healthTickMinorAnchor", v) end } },
    }
end

-------------------------------------------------------------------------------
--  STEPS
-------------------------------------------------------------------------------
local STEP_VALUES = { health = "By Health", league = "Fixed", auto = "Auto", ["50"] = "50", ["100"] = "100",
    ["500"] = "500", ["1000"] = "1000", ["5000"] = "5000" }
local STEP_ORDER = { "health", "league", "auto", "50", "100", "500", "1000", "5000" }

-- By Health's values. Every tall value is a whole multiple of every small one.
local SMALL_VALUES = { ["50"] = "50 Health", ["100"] = "100 Health", ["250"] = "250 Health",
    ["500"] = "500 Health" }
local SMALL_ORDER = { "50", "100", "250", "500" }
local TALL_VALUES = { ["500"] = "500 Health", ["1000"] = "1,000 Health", ["2000"] = "2,000 Health",
    ["2500"] = "2,500 Health", ["5000"] = "5,000 Health" }
local TALL_ORDER = { "500", "1000", "2000", "2500", "5000" }
local HIDE_VALUES = { ["2000"] = "2,000 Max Health", ["3000"] = "3,000 Max Health",
    ["5000"] = "5,000 Max Health", ["10000"] = "10,000 Max Health", ["0"] = "Never" }
local HIDE_ORDER = { "2000", "3000", "5000", "10000", "0" }

local NEEDS_BY_HEALTH = "This option requires Health Tick Step: By Health"

local function StepPairs()
    local function byHealth() return Get("healthTickStep") == "health" end
    local function notByHealth() return not byHealth() end
    return {
        { { type = "dropdown", label = "Health Tick Step", values = STEP_VALUES, order = STEP_ORDER,
            tooltip = "By Health uses the rows below, Fixed and Auto follow max health, a number marks every that much health.",
            get = function() return tostring(Get("healthTickStep")) end,
            set = function(v)
                if v == "health" or v == "league" or v == "auto" then Set("healthTickStep", v)
                else Set("healthTickStep", tonumber(v) or "health") end
            end },
          { type = "dropdown", label = "Tick Density",
            values = { ["10"] = "Fewer (10)", ["20"] = "More (20)" }, order = { "10", "20" },
            tooltip = "Marks per step in Auto; fewer switch to a larger step sooner.",
            disabled = function() return Get("healthTickStep") ~= "auto" end,
            disabledTooltip = "This option requires Health Tick Step: Auto",
            get = function() return tostring(Get("healthTickMarks")) end,
            set = function(v) Set("healthTickMarks", tonumber(v) or 20) end } },
        { { type = "dropdown", label = "Small Tick Every",
            values = SMALL_VALUES, order = SMALL_ORDER,
            tooltip = "By Health: a short mark per this much health.",
            disabled = notByHealth, disabledTooltip = NEEDS_BY_HEALTH,
            get = function() return Listed(SMALL_VALUES, Get("healthTickSmallStep")) end,
            set = function(v) Set("healthTickSmallStep", tonumber(v) or 100) end },
          { type = "dropdown", label = "Tall Tick Every",
            values = TALL_VALUES, order = TALL_ORDER,
            tooltip = "By Health: a tall mark per this much health, up to 100 marks.",
            disabled = notByHealth, disabledTooltip = NEEDS_BY_HEALTH,
            get = function() return Listed(TALL_VALUES, Get("healthTickTallStep")) end,
            set = function(v) Set("healthTickTallStep", tonumber(v) or 500) end } },
        { { type = "dropdown", label = "Hide Small Ticks At",
            values = HIDE_VALUES, order = HIDE_ORDER,
            tooltip = "By Health: bars with this much max health or more show only the tall marks.",
            disabled = notByHealth, disabledTooltip = NEEDS_BY_HEALTH,
            get = function() return Listed(HIDE_VALUES, Get("healthTickHideSmallAt")) end,
            set = function(v) Set("healthTickHideSmallAt", tonumber(v) or 5000) end },
          { type = "dropdown", label = "Tall Tick Every Nth",
            values = { ["5"] = "5th", ["10"] = "10th" }, order = { "5", "10" },
            tooltip = "Which marks are tall in Fixed, Auto and number steps.",
            disabled = byHealth, disabledTooltip = "This option requires a Health Tick Step other than By Health",
            get = function() return tostring(Get("healthTickMajorEvery")) end,
            set = function(v) Set("healthTickMajorEvery", tonumber(v) or 5) end } },
        { { type = "toggle", label = "Only On Health",
            tooltip = "Hides the marks on the empty part of the bar.",
            get = function() return Get("healthTickFillOnly") end,
            set = function(v) Set("healthTickFillOnly", v) end },
          { type = "dropdown", label = "Tick Position",
            values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
            order = { "LEFT", "CENTER", "RIGHT" },
            tooltip = "Where each mark sits on its step line.",
            get = function() return Get("healthTickAlign") end,
            set = function(v) Set("healthTickAlign", v) end } },
        { Slider("Tick Offset", "healthTickOffset", -25, 25, 0.5,
              "Moves every mark and its edge left (minus) or right (plus), in 1080p pixels.") },
    }
end

-------------------------------------------------------------------------------
--  TICK EDGE
-------------------------------------------------------------------------------
-- The cog rows of one Tick Edge set (short: Short Tick Edge, else Tall).
local function EdgeCogRows(short)
    local function key(name) return HT.EdgeKey(name, short) end
    local function slider(name, label, min, max, step, tooltip)
        return Slider(label, key(name), min, max, step, tooltip)
    end
    return {
        { type = "dropdown", label = "Shadow Side",
          values = { RIGHT = "Right", LEFT = "Left" }, order = { "RIGHT", "LEFT" },
          tooltip = "Which side of the mark the Shadow is on.",
          hidden = function() return Get(key("")) ~= "SHADOW" end,
          get = function() return Get(key("Side")) end,
          set = function(v) Set(key("Side"), v) end },
        { type = "toggle", label = "Only With Light Marks",
          tooltip = "Draws the edge only on bars dark enough for light marks.",
          disabled = function() return not Get("healthTickAutoLight") end,
          disabledTooltip = "Light Marks On Dark Bars",
          get = function() return Get(key("LightOnly")) end,
          set = function(v) Set(key("LightOnly"), v) end },
        slider("Width", "Edge Width", 1, 10, 1, "In screen pixels."),
        slider("Distance", "Edge Distance", 0, 10, 1, "Gap between a mark and its edge, in screen pixels."),
        slider("Alpha", "Edge Opacity", 0, 100, 5),
        { type = "toggle", label = "Auto Edge Color",
          tooltip = "Black beside light marks, white beside dark marks.",
          get = function() return Get(key("Auto")) end,
          set = function(v) Set(key("Auto"), v) end },
        { type = "colorpicker", label = "Edge Color",
          disabled = function() return Get(key("Auto")) end,
          disabledTooltip = "Auto Edge Color", requireState = "disabled",
          get = ColorGet(key("Color")), set = ColorSet(key("Color")) },
    }
end

-- Tall Tick Edge and Short Tick Edge: two full sets, each with its own cog.
local function EdgePairs()
    local function edgeRow(short)
        local mode = HT.EdgeKey("", short)
        local name = short and "Short Tick Edge" or "Tall Tick Edge"
        return { type = "dropdown", label = name,
            tooltip = "A thin line beside each " .. (short and "short" or "tall")
                .. " mark: a Shadow on one side or an Outline on both.",
            values = { NONE = "None", SHADOW = "Shadow", OUTLINE = "Outline" },
            order = { "NONE", "SHADOW", "OUTLINE" },
            get = function() return Get(mode) end,
            set = function(v) Set(mode, v) end,
            cog = { title = name, disabled = function() return Get(mode) == "NONE" end,
                disabledTooltip = "This option requires a Tick Edge other than None",
                rows = EdgeCogRows(short) } }
    end
    return {
        { edgeRow(false), edgeRow(true) },
        { PresetRow("Tall Edge Preset", "Sets Tall Tick Edge and its details, not the Shadow side.",
              EDGE_PRESETS, EDGE_PRESET_ORDER, EDGE_PRESET_NAMES),
          PresetRow("Short Edge Preset", "Sets Short Tick Edge and its details, not the Shadow side.",
              SHORT_EDGE_PRESETS, EDGE_PRESET_ORDER, EDGE_PRESET_NAMES) },
    }
end

-------------------------------------------------------------------------------
--  TICK BAR STYLE. Pillow and Bevel each keep their own shading values; every
--  row reads and writes the key of the active style.
-------------------------------------------------------------------------------
-- The key of a shading value (a STYLE_KEYS name) of the active style.
local function StyleKey(name)
    return STYLE_KEYS[Get("healthTickBarStyle") == "BEVEL" and "BEVEL" or "PILLOW"][name]
end

local function StyleSlider(name, label, min, max, step, tooltip)
    return { type = "slider", label = label, min = min, max = max, step = step, tooltip = tooltip,
        get = function() return Get(StyleKey(name)) end,
        set = function(v) Set(StyleKey(name), v) end }
end

-- A color picker on a shading color of the active style.
local function StyleColor(name, label, tooltip)
    return { type = "colorpicker", label = label, tooltip = tooltip,
        get = function()
            local c = Get(StyleKey(name))
            if type(c) ~= "table" then c = DEFAULTS[StyleKey(name)] end
            return c.r or 0, c.g or 0, c.b or 0
        end,
        set = function(r, g, b) Set(StyleKey(name), { r = r, g = g, b = b }) end }
end

-- A blend dropdown on a shading part of the active style; other is ADD (a light
-- part) or MOD (a shade part).
local LIGHT_BLENDS = { BLEND = "Blend", ADD = "Add" }
local LIGHT_BLEND_ORDER = { "BLEND", "ADD" }
local SHADE_BLENDS = { BLEND = "Blend", MOD = "Multiply" }
local SHADE_BLEND_ORDER = { "BLEND", "MOD" }
local function StyleBlend(name, label, other, tooltip)
    local light = other == "ADD"
    return { type = "dropdown", label = label, tooltip = tooltip,
        values = light and LIGHT_BLENDS or SHADE_BLENDS,
        order = light and LIGHT_BLEND_ORDER or SHADE_BLEND_ORDER,
        get = function() return HT.BlendOf(Get(StyleKey(name)), DEFAULTS[StyleKey(name)], other) end,
        set = function(v) Set(StyleKey(name), v == other and other or "BLEND") end }
end

-- The tooltips of a light part's and a shade part's color and blend.
local function LightTips(what)
    return "Color of " .. what .. ".",
        "How " .. what .. " mixes with the bar. Blend fades the bar toward the color; Add adds the color's light."
end
local function ShadeTips(what)
    return "Color of " .. what .. ".",
        "How " .. what .. " mixes with the bar. Blend fades the bar toward the color; Multiply darkens it and keeps its hue."
end

-- The side light: Style Opacity, Light Direction, Light, Light Width, Shade,
-- Shade Width, Light Ends. The widths show only for Bevel, Light Ends for Pillow.
local function StyleCogRows()
    local function isBevel() return Get("healthTickBarStyle") == "BEVEL" end
    local function width(key, label, tooltip)
        return { type = "slider", label = label, min = 1, max = 25, step = 1, tooltip = tooltip,
          hidden = function() return not isBevel() end,
          get = function() return Get(key) end,
          set = function(v) Set(key, v) end }
    end
    local lc, lb = LightTips("the light")
    local dc, db = ShadeTips("the shade")
    return {
        StyleSlider("alpha", "Style Opacity", 0, 100, 5, "Scales all the shading at once. 0 hides it."),
        StyleSlider("dir", "Light Direction", -90, 90, 5,
            "Where the side light comes from, in degrees: -90 left, 0 above (no side light), 90 right."),
        StyleSlider("light", "Light", 0, 100, 1, "Strength of the light on the lit side of each block."),
        StyleColor("lightColor", "Light Color", lc),
        StyleBlend("lightBlend", "Light Blend", "ADD", lb),
        width("healthTickBevelLightWidth", "Light Width", "Bevel: width of the light edge, in 1080p pixels."),
        StyleSlider("shade", "Shade", 0, 100, 1, "Strength of the shade on the other side of each block."),
        StyleColor("shadeColor", "Shade Color", dc),
        StyleBlend("shadeBlend", "Shade Blend", "MOD", db),
        width("healthTickBevelShadeWidth", "Shade Width", "Bevel: width of the dark edge, in 1080p pixels."),
        { type = "dropdown", label = "Light Ends",
          values = { ["25"] = "25%", ["50"] = "50%", ["75"] = "75%" },
          order = { "25", "50", "75" },
          tooltip = "Pillow: where the light stops and the shade starts across each block.",
          hidden = isBevel,
          get = function() return tostring(Get("healthTickPillowSplit")) end,
          set = function(v) Set("healthTickPillowSplit", tonumber(v) or 50) end },
    }
end

-- The cog of Top Light (which "top") or Bottom Shade ("bottom"): the band's size
-- and softness, its color and its blend.
local function BandRows(which)
    local top = which == "top"
    local what = top and "Top Light" or "Bottom Shade"
    local ct, bt
    if top then ct, bt = LightTips(what) else ct, bt = ShadeTips(what) end
    return {
        StyleSlider(which .. "Size", what .. " Size", 5, 100, 5, "Band height, in percent of the bar height."),
        StyleSlider(which .. "Soft", what .. " Softness", 0, 100, 5, "100 fades the band out; 0 is one solid band."),
        StyleColor(which .. "Color", what .. " Color", ct),
        StyleBlend(which .. "Blend", what .. " Blend", top and "ADD" or "MOD", bt),
    }
end

-- The cog of Bar Gradient: its angle, blend and two colors.
local function GradientRows()
    return {
        StyleSlider("gradAngle", "Gradient Angle", -180, 180, 5,
            "Where the end side is, in degrees: 0 right, 90 top, 180 left, -90 bottom."),
        { type = "dropdown", label = "Gradient Blend",
          values = LIGHT_BLENDS, order = LIGHT_BLEND_ORDER,
          tooltip = "How the gradient mixes with the bar. Blend fades over the bar color; Add adds light, like a glow.",
          get = function()
              local v = Get(StyleKey("gradBlend"))
              if v ~= "ADD" then v = "BLEND" end
              return v
          end,
          set = function(v) Set(StyleKey("gradBlend"), v == "ADD" and "ADD" or "BLEND") end },
        StyleColor("gradStart", "Start Color", "Color of the start side: the left at Gradient Angle 0."),
        StyleColor("gradEnd", "End Color", "Color of the end side: the right at Gradient Angle 0."),
    }
end

local function StylePairs()
    local function styleOff() return Get("healthTickBarStyle") == "NONE" end
    local NEEDS_STYLE = "This option requires a Tick Bar Style other than Marks Only"
    local function gated(row, cog)
        row.disabled, row.disabledTooltip = styleOff, NEEDS_STYLE
        if cog then
            cog.disabled, cog.disabledTooltip = styleOff, NEEDS_STYLE
            row.cog = cog
        end
        return row
    end
    return {
        { PresetRow("Bar Style Preset", "Sets the style and its shading; Pillow and Bevel keep their own values.",
              STYLE_PRESETS, STYLE_PRESET_ORDER, STYLE_PRESET_NAMES),
          { type = "dropdown", label = "Tick Bar Style",
            tooltip = "Shading between the marks, on the filled part.",
            values = { NONE = "Marks Only", BEVEL = "Bevel", PILLOW = "Pillow" },
            order = { "NONE", "BEVEL", "PILLOW" },
            get = function() return Get("healthTickBarStyle") end,
            set = function(v) Set("healthTickBarStyle", v) end,
            cog = { title = "Side Light", disabled = styleOff, disabledTooltip = NEEDS_STYLE,
                rows = StyleCogRows() } } },
        { gated(StyleSlider("top", "Top Light", 0, 100, 1,
              "Light along the top of the filled part."),
              { title = "Top Light", rows = BandRows("top") }),
          gated(StyleSlider("bottom", "Bottom Shade", 0, 100, 1,
              "Shade along the bottom of the filled part."),
              { title = "Bottom Shade", rows = BandRows("bottom") }) },
        { gated({ type = "dropdown", label = "Shading Blocks",
            tooltip = "What Pillow and Bevel shade as one block: from one tall mark to the next, or from any mark to the next.",
            values = { TALL = "Between Tall Ticks", ALL = "Between All Ticks" },
            order = { "TALL", "ALL" },
            get = function() return Get("healthTickBlocks") end,
            set = function(v) Set("healthTickBlocks", v) end }),
          gated(StyleSlider("grad", "Bar Gradient", 0, 100, 1,
              "Darkens one side of the whole bar and lightens the other, on the filled part. 0 is off."),
              { title = "Bar Gradient", rows = GradientRows() }) },
    }
end

-------------------------------------------------------------------------------
--  SHOW TICKS ON: one switch per place
-------------------------------------------------------------------------------
local function PlaceToggle(def)
    local id = def.id
    return { type = "toggle", text = def.label,
        getValue = function() return HT.PlaceOn(id) end,
        setValue = function(v) HT.SetPlace(id, v) end }
end

local function PlaceRows(W, parent, y)
    local places = HB.PLACES
    for i = 1, #places, 2 do
        local b = places[i + 1]
        local _, h = W:DualRow(parent, y, PlaceToggle(places[i]),
            b and PlaceToggle(b) or EllesmereUI.BlankRowCfg())
        y = y - h
    end
    return y
end

-------------------------------------------------------------------------------
--  Header: the preview bar, a plain StatusBar the size of a nameplate health
--  bar, drawn with HT.Push, and its Preview Health and Preview Bar controls.
--  Session state only: nothing here is saved.
-------------------------------------------------------------------------------
local PV_W, PV_H = 156, 17                       -- a nameplate health bar, in game units
local PV_FILL = 0.7                              -- the share of the bar that is filled
local PV_HEALTH_MIN, PV_HEALTH_MAX, PV_HEALTH_STEP, PV_HEALTH_DEFAULT = 500, 20000, 100, 6000
local PV_BAR_VALUES = { place = "Enemy Plate", dark = "Dark", light = "Light" }
local PV_BAR_ORDER = { "place", "dark", "light" }
local PV_COLOR = { 0.78, 0.16, 0.13 }            -- an enemy plate
local PV_UI_BG = { 0.08, 0.08, 0.08, 0.9 }

local pv = { health = PV_HEALTH_DEFAULT, bar = "place" }
local pvBar, pvStyle, pvCaption

local function PreviewBarFrame()
    if pvBar then return pvBar end
    local bar = PlainCreateFrame("StatusBar", nil, UIParent)
    bar:SetStatusBarTexture(WHITE)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(PV_UI_BG[1], PV_UI_BG[2], PV_UI_BG[3], PV_UI_BG[4])
    pvBar = bar
    return bar
end

-- Dark: the plate color scaled to half of Dark Bar Below. Light: the plate
-- color mixed toward white, to halfway between Dark Bar Below and white. Only
-- while Light Marks On Dark Bars is on.
local function PreviewColor()
    local r, g, b = PV_COLOR[1], PV_COLOR[2], PV_COLOR[3]
    if pv.bar == "place" or not Get("healthTickAutoLight") then return r, g, b end
    local L = 0.299 * r + 0.587 * g + 0.114 * b
    local dark = (tonumber(Get("healthTickDarkBelow")) or 40) / 100
    if pv.bar == "dark" then
        local s = L > 0 and math.min(1, dark * 0.5 / L) or 0
        return r * s, g * s, b * s
    end
    local want = (dark + 1) / 2
    local m = L < want and (want - L) / (1 - L) or 0
    return r + (1 - r) * m, g + (1 - g) * m, b + (1 - b) * m
end

local function PreviewPaint()
    local bar = pvBar
    if not bar or not bar:GetParent() then return end
    local r, g, b = PreviewColor()
    bar:SetStatusBarColor(r, g, b)
    bar:SetMinMaxValues(0, pv.health)
    bar:SetValue(pv.health * PV_FILL)
    pvStyle = HT.MakeStyle(HT.SavedLook(), pvStyle)
    HT.Push(bar, pv.health, HT.TickStep(Get("healthTickStep")), 2, pvStyle)
    if pvCaption then pvCaption:SetText(BreakUpLargeNumbers(pv.health) .. " max health") end
end

-- The bar is as big on screen as a nameplate's: game units in header units.
local function PreviewSize(hdr)
    local hs = hdr:GetEffectiveScale()
    if not hs or hs <= 0 then hs = UIParent:GetEffectiveScale() end
    local k = UIParent:GetEffectiveScale() / hs
    pvBar:SetSize(PV_W * k, PV_H * k)
end

-- A header label with a tooltip.
local function HeaderLabel(hdr, text, tip)
    local lbl = EllesmereUI.MakeFont(hdr, 14, nil, 1, 1, 1, 1)
    lbl:SetText(text)
    local hit = CreateFrame("Frame", nil, hdr)
    hit:SetPoint("TOPLEFT", lbl, "TOPLEFT", 0, 0)
    hit:SetPoint("BOTTOMRIGHT", lbl, "BOTTOMRIGHT", 0, 0)
    hit:SetMouseClickEnabled(false)
    hit:SetMouseMotionEnabled(true)
    hit:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(lbl, tip) end)
    hit:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    return lbl
end

local function HeaderBuilder(hdr)
    local PP = EllesmereUI.PanelPP
    local y = -18

    pvCaption = EllesmereUI.MakeFont(hdr, 11, nil, 1, 1, 1, 0.4)
    PP.Point(pvCaption, "TOP", hdr, "TOP", 0, y)
    y = y - 12 - 10

    local bar = PreviewBarFrame()
    bar:SetParent(hdr)
    bar:SetFrameLevel(hdr:GetFrameLevel() + 5)
    bar:ClearAllPoints()
    bar:SetPoint("TOP", hdr, "TOP", 0, y)
    bar:Show()
    PreviewSize(hdr)
    y = y - bar:GetHeight() - 22

    -- Preview Health, left of the middle.
    local hLbl = HeaderLabel(hdr, "Preview Health",
        "Max health of the preview bar, to see a mob's marks. Preview only.")
    local track, valBox = EllesmereUI.BuildSliderCore(hdr, 160, 4, 14, 52, 26, 13, EllesmereUI.SL_INPUT_A,
        PV_HEALTH_MIN, PV_HEALTH_MAX, PV_HEALTH_STEP,
        function() return pv.health end,
        function(v)
            pv.health = math.floor((tonumber(v) or PV_HEALTH_DEFAULT) / PV_HEALTH_STEP + 0.5) * PV_HEALTH_STEP
            PreviewPaint()
        end, false)
    track:SetFrameLevel(hdr:GetFrameLevel() + 5)
    valBox:SetFrameLevel(hdr:GetFrameLevel() + 6)
    PP.Point(valBox, "TOPRIGHT", hdr, "TOP", -20, y - 2)
    PP.Point(track, "RIGHT", valBox, "LEFT", -12, 0)
    hLbl:SetPoint("RIGHT", track, "LEFT", -14, 0)

    -- Preview Bar, right of the middle.
    local bLbl = HeaderLabel(hdr, "Preview Bar",
        "The preview bar's color, to check Light Marks On Dark Bars. Preview only.")
    bLbl:SetPoint("TOPLEFT", hdr, "TOP", 20, y - 8)
    local dd = EllesmereUI.BuildDropdownControl(hdr, 150, hdr:GetFrameLevel() + 5, PV_BAR_VALUES, PV_BAR_ORDER,
        function() return pv.bar end,
        function(v)
            if not PV_BAR_VALUES[v] then return end
            pv.bar = v
            PreviewPaint()
        end)
    dd:SetPoint("LEFT", bLbl, "RIGHT", 12, 0)
    -- Locked while Light Marks On Dark Bars is off: greyed, with the row lock tooltip.
    local lock = CreateFrame("Frame", nil, hdr)
    lock:SetPoint("TOPLEFT", bLbl, "TOPLEFT", 0, 0)
    lock:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 0, 0)
    lock:SetFrameLevel(dd:GetFrameLevel() + 10)
    lock:EnableMouse(true)
    lock:SetScript("OnEnter", function()
        EllesmereUI.ShowWidgetTooltip(dd, EllesmereUI.DisabledTooltip("Light Marks On Dark Bars"))
    end)
    lock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    y = y - 30 - 18

    headerRefresh = function()
        local locked = not Get("healthTickAutoLight")
        bLbl:SetAlpha(locked and 0.3 or 1)
        dd:SetAlpha(locked and 0.3 or 1)
        dd:EnableMouse(not locked)
        lock:SetShown(locked)
        dd._refreshLabel()
        PreviewSize(hdr)
        PreviewPaint()
    end
    headerRefresh()

    return math.abs(y)
end

function _G._EUI_HealthTicksHeaderBuilder()
    return HeaderBuilder
end

function _G._EUI_HealthTicksRefreshHeader()
    if headerRefresh then headerRefresh() end
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------
function _G._EUI_BuildHealthTicksPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h

    EllesmereUI:SetContentHeader(HeaderBuilder)
    parent._showRowDivider = true

    _, h = W:SectionHeader(parent, "SHOW TICKS ON", y,
        "Not drawn on a bar that fills vertically, right to left or inverted.");  y = y - h
    y = PlaceRows(W, parent, y)

    _, h = W:SectionHeader(parent, "MARKS", y);  y = y - h
    y = Pairs(W, parent, y, MarkPairs())
    _, h = W:SectionHeader(parent, "STEPS", y);  y = y - h
    y = Pairs(W, parent, y, StepPairs())
    _, h = W:SectionHeader(parent, "TICK EDGE", y);  y = y - h
    y = Pairs(W, parent, y, EdgePairs())
    _, h = W:SectionHeader(parent, "TICK BAR STYLE", y);  y = y - h
    y = Pairs(W, parent, y, StylePairs())

    _, h = W:Spacer(parent, y, 20);  y = y - h
    _, h = W:WideButton(parent, "Reset Look to Defaults", y, function()
        EllesmereUI:ShowConfirmPopup({
            title = "Reset Health Ticks Look",
            message = "Reset every Health Ticks look setting to its default? The places stay as they are.",
            confirmText = "Reset",
            cancelText = "Cancel",
            onConfirm = function()
                HT.ResetLook()
                Repaint()
                EllesmereUI:RefreshPage()
            end,
        })
    end, 260);  y = y - h

    return math.abs(y)
end

-------------------------------------------------------------------------------
--  For module pages: the Health Ticks switch of one place, as a W:DualRow slot
--  config. cfg.attach(region) adds an Edit Look button, left of the switch, that
--  opens this page; call it with the row's half (row._leftRegion).
-------------------------------------------------------------------------------
function EllesmereUI.HealthTicksPlaceCfg(place)
    local cfg = {
        type = "toggle", text = "Health Ticks", noCapture = true,
        tooltip = "Marks on this health bar, one per step of health.",
        getValue = function() return HT.PlaceOn(place) end,
        setValue = function(v) HT.SetPlace(place, v) end,
    }
    function cfg.attach(region)
        if not region then return end
        EllesmereUI.BuildInlineButton(region, "Edit Look", function()
            EllesmereUI:NavigateToElementSettings(GLOBAL_KEY, PAGE_TICKS)
        end, { width = 84, tip = "Open the Health Ticks page" })
    end
    return cfg
end
