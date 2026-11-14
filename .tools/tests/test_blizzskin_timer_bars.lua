-- Stub harness: Blizzard Skins+, Reskin Timer Bars (EUI_BlizzardSkin_HUD.lua and the Tooltips &
-- Menus page). Off by default; on, Blizzard's breath, fatigue and feign death bars
-- (MirrorTimerContainer) are drawn as house bars, and a TIMER BARS section holds their look.
-- Rules checked here:
--   - off: one login event that drops itself, nothing hooked, no bar touched;
--   - on: every bar is skinned once, a timer start re-skins just its own frame after Blizzard's
--     art, pieces are built once, and Default keeps the thin edge while a picked style takes the
--     configured border and (Solid, Glow, Shadow only) rounded corners;
--   - the Accent fill is Window Skins' bar fill, and the options' Accent swatch (and Custom with
--     no color picked) shows that same color;
--   - the Corner Radius cog stands beside Border Size with the color swatches left of it, and is
--     locked under Border Style Default, where nothing rounds;
--   - the Bar Texture list is made on every page build from tables that stay the same, so a
--     texture another addon registers later is listed.
-- Driven here: the real HUD file loaded whole over recording frames shaped like Blizzard's
-- timer code, and the real TIMER BARS section and border controls helper of the options page.
--   lua .tools/tests/test_blizzskin_timer_bars.lua        (from the repository root)
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

local checks, fails = 0, 0
local function ok(cond, msg)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local HUD = ReadSource("EllesmereUIBlizzardSkin/EUI_BlizzardSkin_HUD.lua")
local OPTIONS = ReadSource("EllesmereUIOptions/EUI_BlizzardSkin_Options.lua")
assert(loadstring(OPTIONS, "=EUI_BlizzardSkin_Options.lua"), "the options file does not compile")

-------------------------------------------------------------------------------
--  Recording objects: explicit methods win, every other method is a recorded no-op
-------------------------------------------------------------------------------
local calls = {}
local function rec(obj, name, ...)
    local t = calls[obj]; if not t then t = {}; calls[obj] = t end
    t[#t + 1] = { name = name, n = select("#", ...), ... }
end
local function count(obj, name)
    local n = 0
    for _, c in ipairs(calls[obj] or {}) do if c.name == name then n = n + 1 end end
    return n
end
local function Obj(kind)
    local o = { _kind = kind, _shown = true, _regions = {}, _children = {} }
    return setmetatable(o, { __index = function(t, k)
        return function(self, ...) rec(self, k, ...) end
    end })
end

local frames = {}
local function NewTexture(parent, layer)
    local t = Obj("Texture")
    t._layer = layer or "ARTWORK"
    t.IsObjectType = function(self, k) return k == "Texture" end
    t.GetDrawLayer = function(self) return self._layer end
    t.SetShown = function(self, v) rec(self, "SetShown", v); self._shown = v and true or false end
    t.IsShown = function(self) return self._shown end
    if parent then parent._regions[#parent._regions + 1] = t end
    return t
end
local function NewFontString(parent)
    local fs = Obj("FontString")
    fs.IsObjectType = function(self, k) return k == "FontString" end
    fs.SetFont = function(self, path, size, flags) rec(self, "SetFont", path, size, flags); self._font = path; self._size = size end
    fs.SetText = function(self, v)
        rec(self, "SetText", v)
        if not self._font then error("Font not set") end
        self._text = v
    end
    fs.GetText = function(self) return self._text end
    fs.GetFont = function(self) return self._font, self._size, "" end
    fs.SetShown = function(self, v) rec(self, "SetShown", v); self._shown = v and true or false end
    if parent then parent._regions[#parent._regions + 1] = fs end
    return fs
end
local function NewFrame(kind, parent)
    local f = Obj(kind or "Frame")
    f._level = 5
    f._events = {}
    f.RegisterEvent = function(self, e) rec(self, "RegisterEvent", e); self._events[e] = true end
    f.UnregisterEvent = function(self, e) self._events[e] = nil end
    f.UnregisterAllEvents = function(self) rec(self, "UnregisterAllEvents"); self._events = {} end
    f.SetScript = function(self, s, fn) rec(self, "SetScript", s, fn); self["_s_" .. s] = fn end
    f.GetScript = function(self, s) return self["_s_" .. s] end
    f.HookScript = function(self, s, fn) rec(self, "HookScript", s, fn) end
    f.CreateTexture = function(self, name, layer) return NewTexture(self, layer) end
    f.CreateFontString = function(self) return NewFontString(self) end
    f.CreateMaskTexture = function(self) return NewTexture(self, "ARTWORK") end
    f.GetRegions = function(self) return unpack(self._regions) end
    f.GetChildren = function(self) return unpack(self._children) end
    f.GetFrameLevel = function(self) return self._level end
    f.SetFrameLevel = function(self, l) rec(self, "SetFrameLevel", l); self._level = l end
    f.IsForbidden = function() return false end
    f.SetShown = function(self, v) self._shown = v and true or false end
    f.Show = function(self) rec(self, "Show"); self._shown = true end
    f.Hide = function(self) rec(self, "Hide"); self._shown = false end
    f.IsShown = function(self) return self._shown end
    f.SetSize = function(self, w, h) rec(self, "SetSize", w, h); self._w, self._h = w, h end
    if parent then parent._children[#parent._children + 1] = f end
    frames[#frames + 1] = f
    return f
end

_G.CreateFrame = function(kind, name, parent) return NewFrame(kind, parent) end
_G.hooksecurefunc = function(a, b, c)
    if type(a) == "table" then
        local orig = a[b]
        a[b] = function(...)
            local r = { orig(...) }
            c(...)
            return unpack(r)
        end
    else
        local orig = _G[a]
        _G[a] = function(...) local r = { orig(...) }; b(...); return unpack(r) end
    end
end
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
_G.C_Timer = { After = function() end }
_G.issecretvalue = nil
_G.EUI_CLIENT_BLOCKED = nil

-- Blizzard's MirrorTimerContainer (the shape of Blizzard_MirrorTimer's Mainline code)
local FLAT = "Interface\\Buttons\\WHITE8X8"
local container = NewFrame("Frame")
container.activeTimers = {}
container.mirrorTimers = {}
for i = 1, 3 do
    local t = NewFrame("Frame", container)
    t.timer = false
    t.StatusBar = NewFrame("StatusBar", t)
    t.StatusBar.SetStatusBarTexture = function(self, tex) rec(self, "SetStatusBarTexture", tex); self._tex = tex end
    t.StatusBar.SetStatusBarColor = function(self, r, g, b, a) rec(self, "SetStatusBarColor", r, g, b, a); self._col = { r, g, b, a } end
    t.TextBorder = NewTexture(t, "BACKGROUND")
    NewTexture(t, "BACKGROUND")
    t.Text = NewFontString(t)
    t.Text._font = "GameFontHighlightSmall"
    t.Border = NewTexture(t, "OVERLAY")
    t.Setup = function(self, timer, value, maxvalue, paused, label)
        self.timer = timer
        self.StatusBar:SetStatusBarTexture("atlas:" .. timer)
        self.Text:SetText(label)
    end
    t.HasTimer = function(self) return self.timer end
    container.mirrorTimers[i] = t
end
function container:GetActiveTimer(timer) return self.activeTimers[timer] end
function container:GetAvailableTimer(timer)
    local a = self:GetActiveTimer(timer)
    if a then return a end
    for _, f in ipairs(self.mirrorTimers) do
        if not f:HasTimer() then return f end
    end
end
function container:SetupTimer(timer, value, maxvalue, paused, label)
    local f = self:GetAvailableTimer(timer)
    if not f then return end
    f:Setup(timer, value, maxvalue, paused, label)
    self.activeTimers[timer] = f
end
_G.MirrorTimerContainer = container
local origSetup = container.SetupTimer

-- The parent's and the module's pieces the file reads
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(f) local d = FFD[f]; if not d then d = {}; FFD[f] = d end; return d end
local roundCalls, borderApply, borderHide = {}, {}, {}
local STYLE_OK = { solid = true, glow = true, shadow = true }
_G.EllesmereUIDB = {}
_G.EllesmereUI = {
    ELLESMERE_GREEN = { r = 0.05, g = 0.8, b = 0.6 },
    IS_FOREVER = false,
    ResolveTexturePath = function(t, key, fb) return (t and t[key]) or fb end,
    BuildBarTextureTables = function() return { melli = "MELLI" }, { none = "None", melli = "Melli" }, { "none", "melli" } end,
    GetClassColor = function(c) return { r = 0.78, g = 0.61, b = 0.43 } end,
    RoundedStyleOK = function(s) return STYLE_OK[s or "solid"] == true end,
    RoundCorners = function(owner, radius, opts)
        roundCalls[#roundCalls + 1] = { owner = owner, radius = radius, border = opts and opts.border, style = opts and opts.style }
    end,
}
EllesmereUI._applyBlizzardConfiguredBorder = function(owner, prefix, size)
    local d = GetFFD(owner)
    if not d.configBorder then d.configBorder = NewFrame("Frame", owner) end
    borderApply[#borderApply + 1] = { owner = owner, prefix = prefix }
end
EllesmereUI._hideBlizzardConfiguredBorder = function(owner)
    borderHide[#borderHide + 1] = owner
    local d = FFD[owner]; if d and d.configBorder then d.configBorder:Hide() end
end
local lookCbs = {}
local barFill = { 0.1, 0.2, 0.3 }
local WSkin = {
    Theme = { fontPath = "HOUSE" },
    Font = function(fs, r, g, b, size) fs:SetFont("HOUSE", size or 12, ""); if r then fs:SetTextColor(r, g, b) end end,
    BarFillColor = function() return barFill[1], barFill[2], barFill[3], 0.95 end,
    OnLooksChanged = function(fn) lookCbs[#lookCbs + 1] = fn end,
}
local ns = { _internals = { last = "TooltipVisibility", GetFFD = GetFFD }, WSkin = WSkin }

local nBefore = #frames
assert(loadstring(HUD, "=EUI_BlizzardSkin_HUD.lua"))("EllesmereUIBlizzardSkin", ns)
ok(ns._internals.last == "HUD", "the file did not load to its end")
local TB = EllesmereUI.TIMER_BARS
ok(type(TB) == "table" and type(TB.AccentFill) == "function", "the timer bars constants or their accent fill are not published")
ok(type(EllesmereUI._TimerBarsInstall) == "function", "the install seam is not published")
ok(EllesmereUI._TimerBarsRefresh == nil, "the refresh seam exists before the reskin is installed")

-- the frame the file made for PLAYER_LOGIN
local mtEv
for i = #frames, nBefore + 1, -1 do
    if rawget(frames[i], "_events") and frames[i]._events["PLAYER_LOGIN"] then mtEv = frames[i]; break end
end
assert(mtEv, "the timer bars login frame was not found")

-------------------------------------------------------------------------------
--  1. Off at login: one event, dropped; nothing hooked or skinned
-------------------------------------------------------------------------------
local events = 0
for _ in pairs(mtEv._events) do events = events + 1 end
ok(events == 1, "off: the login frame registered " .. events .. " events")
mtEv._s_OnEvent(mtEv, "PLAYER_LOGIN")
ok(next(mtEv._events) == nil, "off: the login frame keeps an event")
ok(rawget(mtEv, "_s_OnEvent") == nil, "off: the login frame keeps its script")
ok(container.SetupTimer == origSetup, "off: SetupTimer is hooked")
ok(EllesmereUI._TimerBarsRefresh == nil, "off: the refresh seam exists")
for i = 1, 3 do
    ok(count(container.mirrorTimers[i].StatusBar, "SetStatusBarTexture") == 0, "off: bar " .. i .. " was touched")
end
container:SetupTimer("BREATH", 1, 1, 0, "Breath")
ok(container.mirrorTimers[1].StatusBar._tex == "atlas:BREATH", "off: Blizzard's art did not stay")

-------------------------------------------------------------------------------
--  2. Turned on from the options: installed once, every bar skinned
-------------------------------------------------------------------------------
EllesmereUIDB.reskinTimerBars = true
EllesmereUI._TimerBarsInstall()
ok(container.SetupTimer ~= origSetup, "on: SetupTimer is not hooked")
ok(type(EllesmereUI._TimerBarsRefresh) == "function", "on: no refresh seam")
ok(#lookCbs == 1, "on: " .. #lookCbs .. " looks callbacks")
for i = 1, 3 do
    local f = container.mirrorTimers[i]
    local b = f.StatusBar
    ok(b._tex == FLAT, "on: bar " .. i .. " is not the flat texture")
    ok(b._col and math.abs(b._col[4] - 0.95) < 1e-9, "on: bar " .. i .. " is not at the default fill opacity")
    ok(b._w == 195 and b._h == 13, "on: bar " .. i .. " is not the default size")
    ok(f.TextBorder._shown == true and count(f.TextBorder, "SetAlpha") >= 1, "on: frame " .. i .. " keeps Blizzard's art")
    local d = GetFFD(b)
    ok(d.thinEdges and #d.thinEdges == 4, "on: bar " .. i .. " has no thin edge")
    for e = 1, 4 do ok(d.thinEdges and d.thinEdges[e] and d.thinEdges[e]._shown, "on: bar " .. i .. " edge " .. e .. " is hidden") end
    ok(count(f.Text, "SetAlpha") == 1, "on: Blizzard's text is not hidden once")
    ok(GetFFD(f).tbLabel ~= nil, "on: no label was built")
end
ok(GetFFD(container.mirrorTimers[1]).tbLabel._text == "Breath", "on: the label does not copy the running timer's name")
EllesmereUI._TimerBarsInstall()
ok(#lookCbs == 1, "a second install registered again")

-------------------------------------------------------------------------------
--  3. The Accent fill: Window Skins' bar fill, from one function
-------------------------------------------------------------------------------
do
    local c = container.mirrorTimers[1].StatusBar._col
    ok(c[1] == 0.1 and c[2] == 0.2 and c[3] == 0.3, "accent mode does not draw Window Skins' bar fill")
    local r, g, b, extra = TB.AccentFill()
    ok(r == 0.1 and g == 0.2 and b == 0.3 and extra == nil, "the accent fill is not Window Skins' bar fill as three numbers")
    barFill[1], barFill[2], barFill[3] = 0.6, 0.5, 0.4
    EllesmereUI._TimerBarsRefresh()
    c = container.mirrorTimers[2].StatusBar._col
    ok(c[1] == 0.6 and c[2] == 0.5 and c[3] == 0.4, "a new Window Skins bar fill does not reach the bars")
    -- without the window engine's bar fill: the accent at 80%
    local keep = WSkin.BarFillColor
    WSkin.BarFillColor = nil
    r, g, b = TB.AccentFill()
    ok(math.abs(r - 0.04) < 1e-9 and math.abs(g - 0.64) < 1e-9 and math.abs(b - 0.48) < 1e-9, "with no bar fill to read, the accent fill is not the accent at 80%")
    WSkin.BarFillColor = keep
    barFill[1], barFill[2], barFill[3] = 0.1, 0.2, 0.3
    EllesmereUI._TimerBarsRefresh()
end

-------------------------------------------------------------------------------
--  4. A timer start re-skins exactly its frame, after Blizzard's art
-------------------------------------------------------------------------------
local b2 = container.mirrorTimers[2].StatusBar
local before = count(b2, "SetStatusBarTexture")
container:SetupTimer("EXHAUSTION", 1, 1, 0, "Fatigue")
ok(count(b2, "SetStatusBarTexture") == before + 2, "a timer start is not Blizzard's art plus one reskin")
ok(b2._tex == FLAT, "the reskin does not win over Blizzard's art")
ok(GetFFD(container.mirrorTimers[2]).tbLabel._text == "Fatigue", "the label does not follow the new timer")
local b3Writes = count(container.mirrorTimers[3].StatusBar, "SetStatusBarTexture")
container:SetupTimer("FEIGNDEATH", 1, 1, 0, "Feign Death")
ok(count(b2, "SetStatusBarTexture") == before + 2, "another timer's start repainted this bar")
ok(count(container.mirrorTimers[3].StatusBar, "SetStatusBarTexture") == b3Writes + 2, "the third timer's start did not skin its own frame")
ok(pcall(container.SetupTimer, container, "DEATH", 1, 1, 0, "Death"), "a timer with no free frame raised")

-------------------------------------------------------------------------------
--  5. Colors
-------------------------------------------------------------------------------
EllesmereUIDB.timerBarsTypeColors = true
EllesmereUI._TimerBarsRefresh()
local c1 = container.mirrorTimers[1].StatusBar._col
ok(c1[1] == 0 and c1[2] == 0.5 and c1[3] == 1, "Color by Timer Type: breath is not blue")
local c2 = container.mirrorTimers[2].StatusBar._col
ok(c2[1] == 1 and c2[2] == 0.9, "Color by Timer Type: fatigue is not yellow")
EllesmereUIDB.timerBarsTypeColors = false
EllesmereUIDB.timerBarsFillMode = "class"
EllesmereUI._TimerBarsRefresh()
ok(container.mirrorTimers[1].StatusBar._col[1] == 0.78, "class mode does not draw the class color")
EllesmereUIDB.timerBarsFillMode = "custom"
EllesmereUI._TimerBarsRefresh()
ok(container.mirrorTimers[1].StatusBar._col[3] == 0.3, "Custom with no color picked does not fall back to the accent fill")
EllesmereUIDB.timerBarsFillColor = { r = 0.9, g = 0.1, b = 0.1 }
EllesmereUI._TimerBarsRefresh()
ok(container.mirrorTimers[1].StatusBar._col[1] == 0.9, "the custom color is not drawn")

-------------------------------------------------------------------------------
--  6. Border Style: Default, a picked style, rounding
-------------------------------------------------------------------------------
EllesmereUIDB.timerBarsBorderTexture = "solid"
EllesmereUIDB.timerBarsCornerRadius = 4
EllesmereUI._TimerBarsRefresh()
ok(#borderApply == 3, "a picked style: the configured border was applied to " .. #borderApply .. " bars")
ok(borderApply[1] and borderApply[1].prefix == "timerBars", "a picked style: not under the timerBars prefix")
local d1 = GetFFD(container.mirrorTimers[1].StatusBar)
for e = 1, 4 do ok(d1.thinEdges[e]._shown == false, "a picked style: thin edge " .. e .. " still shows") end
local rounded = 0
for _, c in ipairs(roundCalls) do if c.radius == 4 then rounded = rounded + 1 end end
ok(rounded == 3, "Solid at radius 4: " .. rounded .. " bars were rounded")
ok(roundCalls[1] and roundCalls[1].border == d1.configBorder, "the rounding does not get the configured border")
-- a style that does not round: the radius drops back to 0 once
EllesmereUIDB.timerBarsBorderTexture = "pixel"
roundCalls = {}
EllesmereUI._TimerBarsRefresh()
local zero = 0
for _, c in ipairs(roundCalls) do if c.radius == 0 then zero = zero + 1 end end
ok(zero == 3, "a style that does not round: the corners were not put back once per bar")
roundCalls = {}
EllesmereUI._TimerBarsRefresh()
ok(#roundCalls == 0, "a style that does not round, again: the corners were written again")
-- back to Default
EllesmereUIDB.timerBarsBorderTexture = nil
EllesmereUI._TimerBarsRefresh()
ok(#borderHide == 3, "Default: the configured border was hidden on " .. #borderHide .. " bars")
for e = 1, 4 do ok(d1.thinEdges[e]._shown == true, "Default: thin edge " .. e .. " is not back") end
ok(d1.configBorder._shown == false, "Default: the border frame still shows")
-- Default with a saved radius: nothing rounds
EllesmereUIDB.timerBarsCornerRadius = 8
roundCalls = {}
EllesmereUI._TimerBarsRefresh()
ok(#roundCalls == 0, "Default with a saved radius rounded a bar")

-------------------------------------------------------------------------------
--  7. Size, the name, and pieces built once
-------------------------------------------------------------------------------
EllesmereUIDB.timerBarsWidth = 999; EllesmereUIDB.timerBarsHeight = 1
EllesmereUI._TimerBarsRefresh()
ok(b2._w == 206 and b2._h == 4, "the size is not capped at Blizzard's timer frame")
EllesmereUIDB.timerBarsShowText = false
EllesmereUI._TimerBarsRefresh()
ok(GetFFD(container.mirrorTimers[1]).tbLabel._shown == false, "Show Name off does not hide the label")
local nFrames = #frames
for _ = 1, 20 do EllesmereUI._TimerBarsRefresh() end
ok(#frames == nFrames, "refreshes built new frames")
local troughs = 0
for _, r in ipairs(container.mirrorTimers[1].StatusBar._regions) do
    if r._layer == "BACKGROUND" then troughs = troughs + 1 end
end
ok(troughs == 1, "a bar has " .. troughs .. " troughs")

-------------------------------------------------------------------------------
--  8. The border controls helper: a cog built before it keeps its place beside the control
-------------------------------------------------------------------------------
local Attach
do
    local points = {}
    local OEUI = {
        _prebuilding = false,
        PanelPP = { Point = function(frame, point, anchor, rel, x, y) points[frame] = anchor end },
        ELLESMERE_GREEN = { r = 0.05, g = 0.8, b = 0.6 },
        RESKIN = { BRD_ALPHA = 0.18 },
        BuildColorSwatch = function() return NewFrame("Button"), function() end end,
        RegisterWidgetRefresh = function() end,
        BuildInlineCog = function() end,
        ShowWidgetTooltip = function() end, HideWidgetTooltip = function() end,
        RefreshPage = function() end,
    }
    Attach = assert(loadstring("local EllesmereUI = ...\n"
        .. Cut(OPTIONS, "    local function AttachBorderControls(row, prefix, disabledFn, allowBehind, opts)\n",
            "    -- Header builder for runtime-painted samples", "the border controls helper")
        .. "\nreturn AttachBorderControls", "=EUI_BlizzardSkin_Options.lua (border controls)"))(OEUI)
    _G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    local function Row()
        local control = NewFrame("Slider")
        return { _leftRegion = { GetFrameLevel = function() return 1 end },
                 _rightRegion = { _control = control, GetFrameLevel = function() return 1 end } }, control
    end
    -- no cog: the first swatch hangs off the control, as on every other border row
    local row, control = Row()
    Attach(row, "loot", function() return false end, false, {})
    local first
    for frame, anchor in pairs(points) do if anchor == control then first = frame end end
    ok(first ~= nil, "with no cog before it, no swatch hangs off the control")
    ok(row._rightRegion._lastInline ~= nil and row._rightRegion._lastInline ~= first, "the helper does not leave its last swatch as the half's last inline item")
    -- a cog first: the first swatch hangs off the cog, nothing but the cog off the control
    for k in pairs(points) do points[k] = nil end
    row, control = Row()
    local cog = NewFrame("Button")
    row._rightRegion._lastInline = cog
    Attach(row, "timerBars", function() return false end, false, {})
    local offCog, offControl = 0, 0
    for _, anchor in pairs(points) do
        if anchor == cog then offCog = offCog + 1 end
        if anchor == control then offControl = offControl + 1 end
    end
    ok(offCog == 1 and offControl == 0, "with a cog before it, the swatches do not chain left of the cog (" .. offCog .. " off the cog, " .. offControl .. " off the control)")
    OEUI._prebuilding = true
    row = Row()
    Attach(row, "timerBars", function() return false end, false, {})
    ok(row._rightRegion._lastInline == nil, "the helper built swatches during the search prebuild")
end

-------------------------------------------------------------------------------
--  9. The TIMER BARS section of the options page
-------------------------------------------------------------------------------
do
    local order = {}                                   -- what was built on which half, in build order
    local rows, headers, cogs, swatches = {}, {}, {}, {}
    local refreshes, forced, applied = 0, 0, 0
    local consumers = {}                               -- the SharedMedia appender's registered tables, by texture table
    local appendCalls = 0
    local function LateTexture(name, path)             -- another addon registers a texture: every consumer gets it
        for tex, c in pairs(consumers) do
            if not c.sep then c.order[#c.order + 1] = "---"; c.sep = true end
            tex["sm:" .. name], c.names["sm:" .. name] = path, name
            c.order[#c.order + 1] = "sm:" .. name
        end
    end
    local OEUI = {
        TIMER_BARS = TB,
        ELLESMERE_GREEN = { r = 0.05, g = 0.8, b = 0.6 },
        _prebuilding = false,
        ROUNDED_MAX_RADIUS = 12,
        _TimerBarsRefresh = function() applied = applied + 1 end,
        RefreshPage = function(_, force) refreshes = refreshes + 1; if force then forced = forced + 1 end end,
        BlankRowCfg = function() return { type = "label", text = "" } end,
        GetClassColor = function() return { r = 0.78, g = 0.61, b = 0.43 } end,
        RoundedStyleOK = function(s) return STYLE_OK[s or "solid"] == true end,
        RoundedCornerRows = function(list) return list end,
        BuildBarTextureTables = function() return { melli = "MELLI" }, { none = "None", melli = "Melli" }, { "none", "melli" } end,
        AppendSharedMediaTextures = function(names, texOrder, _, tex)
            appendCalls = appendCalls + 1
            if not consumers[tex] then consumers[tex] = { names = names, order = texOrder } end
        end,
        ResolveTexturePath = function(t, key, fb) return (t and t[key]) or fb end,
        BuildInlineCog = function(rgn, opts) cogs[#cogs + 1] = opts; order[#order + 1] = { rgn, "cog:" .. tostring(opts.title) } end,
        BuildInlineSwatches = function(rgn, list) swatches[#swatches + 1] = list; order[#order + 1] = { rgn, "swatches" } end,
    }
    local W = {}
    function W:SectionHeader(_, text) headers[#headers + 1] = text; return {}, 30 end
    function W:DualRow(_, _, left, right)
        local row = { left = left, right = right, _leftRegion = {}, _rightRegion = {} }
        rows[#rows + 1] = row
        return row, 40
    end
    local optNS = {}
    local section = Cut(OPTIONS, "        local TB = EllesmereUI.TIMER_BARS\n", "        return math.abs(y)\n", "the TIMER BARS section")
    local Build = assert(loadstring(
        "local ns, EllesmereUI, W, parent, BorderSizeSlider, BorderOffsetCfgs, DefaultableBorderValues, SetDefaultableBorderStyle, AttachBorderControls = ...\n"
        .. "local y, h, _ = 0\n" .. section .. "\nreturn y", "=EUI_BlizzardSkin_Options.lua (TIMER BARS)"))
    local styleWrites = {}
    local function Run()
        order, rows, headers, cogs, swatches = {}, {}, {}, {}, {}
        return Build(optNS, OEUI, W, {},
            function(prefix, text, off, apply, tip) return { type = "slider", text = text, disabled = off, disabledTooltip = tip } end,
            function() return nil end,
            function() return { default = "Default", solid = "Solid" }, { "default", "solid" } end,
            function(prefix, v) styleWrites[#styleWrites + 1] = prefix .. "=" .. tostring(v) end,
            function(row, prefix) order[#order + 1] = { row._rightRegion, "borderSwatches:" .. prefix } end)
    end
    local function RowOf(text)
        for _, row in ipairs(rows) do
            if row.left.text == text then return row, row.left end
            if row.right.text == text then return row, row.right end
        end
    end
    local function CogOf(title)
        for _, c in ipairs(cogs) do if c.title == title then return c end end
    end

    -- off: nothing of the section is built
    for k in pairs(EllesmereUIDB) do EllesmereUIDB[k] = nil end
    Run()
    ok(#headers == 0 and #rows == 0 and appendCalls == 0, "with the reskin off the section built rows or asked for textures")

    EllesmereUIDB.reskinTimerBars = true
    Run()
    ok(#headers == 1 and headers[1] == "TIMER BARS", "with the reskin on there is no TIMER BARS section")
    ok(#rows == 5, "the section has " .. #rows .. " rows, not five (fill, type colors, size, border, name)")

    -- the Accent swatch, and Custom with no color picked, show the fill the bar draws
    local fill = swatches[1] or {}
    local custom, class, accent = fill[1] or {}, fill[2] or {}, fill[3] or {}
    ok(custom.tooltip == "Custom Color" and class.tooltip == "Class Color" and accent.tooltip == "Accent Color", "the fill swatches are not Custom, Class, Accent")
    local r, g, b, a = accent.getValue()
    ok(r == 0.1 and g == 0.2 and b == 0.3 and a == 1, "the Accent swatch does not show the fill the bar draws (" .. tostring(r) .. ", " .. tostring(g) .. ", " .. tostring(b) .. ")")
    r, g, b, a = custom.getValue()
    ok(r == 0.1 and g == 0.2 and b == 0.3 and a == 1, "Custom with no color picked does not show the fill the bar draws")
    EllesmereUIDB.timerBarsFillColor = { r = 0.9, g = 0.1, b = 0.1 }
    r, g, b = custom.getValue()
    ok(r == 0.9 and g == 0.1 and b == 0.1, "the Custom swatch does not show the picked color")
    EllesmereUIDB.timerBarsFillColor = nil

    -- the border row: the Corner Radius cog first, the color swatches after it, on the Border Size half
    local borderRow, styleCfg = RowOf("Border Style")
    ok(borderRow ~= nil and borderRow.right.text == "Border Size", "the border row is not Border Style | Border Size")
    local cogAt, swAt
    for i, entry in ipairs(order) do
        if borderRow and entry[1] == borderRow._rightRegion then
            if entry[2] == "cog:Corner Radius" then cogAt = i end
            if entry[2] == "borderSwatches:timerBars" then swAt = i end
        end
    end
    ok(cogAt ~= nil and swAt ~= nil and cogAt < swAt, "the Corner Radius cog is not built before the color swatches on the Border Size half")
    -- locked under Default and under a style that does not round
    local cog = CogOf("Corner Radius") or {}
    ok(cog.disabled and cog.disabled() == true, "the Corner Radius cog is live under Border Style Default")
    ok(type(cog.disabledTooltip) == "string" and #cog.disabledTooltip > 0, "the locked Corner Radius cog does not say why")
    EllesmereUIDB.timerBarsBorderTexture = "solid"
    ok(cog.disabled and cog.disabled() == false, "the Corner Radius cog is locked under Solid")
    EllesmereUIDB.timerBarsBorderTexture = "pixel"
    ok(cog.disabled and cog.disabled() == true, "the Corner Radius cog is live under a style that does not round")
    EllesmereUIDB.timerBarsBorderTexture = nil
    -- a style pick writes through the shared setter, repaints the bars and rebuilds the page
    if styleCfg then styleCfg.setValue("solid") end
    ok(styleWrites[1] == "timerBars=solid" and applied == 1 and forced == 1, "a Border Style pick does not write, repaint and rebuild")

    -- Bar Texture: lists made per build over tables that stay; a texture registered later is listed
    local _, texCfg = RowOf("Color by Timer Type")
    texCfg = texCfg and RowOf("Color by Timer Type").right or {}
    ok(texCfg.text == "Bar Texture", "Bar Texture is not beside Color by Timer Type")
    local v1, o1 = texCfg.values or {}, texCfg.order or {}
    ok(v1.none == "None" and v1.melli == "Melli" and #o1 == 2, "the texture list is not the bar catalogue")
    ok(type(v1._menuOpts) == "table" and v1._menuOpts.background and v1._menuOpts.background("melli") == "MELLI"
        and v1._menuOpts.background("none") == nil, "a texture entry does not preview its own texture")
    local kept = optNS.timerBarTex
    local n = 0
    for _ in pairs(consumers) do n = n + 1 end
    ok(kept ~= nil and n == 1 and consumers[kept.tex] ~= nil, "the catalogue tables are not kept on the module namespace and handed to the SharedMedia appender")
    LateTexture("Smooth", "SMOOTH")
    Run()
    n = 0
    for _ in pairs(consumers) do n = n + 1 end
    ok(optNS.timerBarTex == kept and n == 1, "a second page build made new catalogue tables (one more SharedMedia consumer per build)")
    texCfg = RowOf("Color by Timer Type").right
    local v2, o2 = texCfg.values, texCfg.order
    ok(v2 ~= v1 and v2["sm:Smooth"] == "Smooth", "a texture registered after the first build is not listed")
    ok(o2[3] == "---" and o2[4] == "sm:Smooth" and v2["---"] == nil, "the divider before the shared textures is missing, or is offered as a choice")
    ok(v2._menuOpts.background("sm:Smooth") == "SMOOTH", "a shared texture does not preview")
    ok(texCfg.getValue() == "none", "with no texture picked the dropdown does not read None")
    texCfg.setValue("sm:Smooth")
    ok(EllesmereUIDB.timerBarsTexture == "sm:Smooth" and applied == 2, "a texture pick is not saved and applied")
end

-------------------------------------------------------------------------------
--  10. The toggle: off by default, alone until it is on
-------------------------------------------------------------------------------
do
    local toggle = Cut(OPTIONS, '            { type="toggle", text="Reskin Timer Bars",', "        -- The regions the inline controls below sit on", "the Reskin Timer Bars toggle")
    ok(toggle:find("EllesmereUIDB.reskinTimerBars == true", 1, true), "the toggle does not read off while unset")
    ok(toggle:find("EllesmereUI._TimerBarsInstall()", 1, true) and toggle:find("EllesmereUI:RefreshPage(true)", 1, true),
        "turning it on does not install the reskin and rebuild the page for its section")
    ok(toggle:find("reload      = true", 1, true), "turning it off does not ask for the reload")
end

if fails > 0 then error(fails .. " of " .. checks .. " check(s) failed") end
print(("PASS test_blizzskin_timer_bars (%d checks)"):format(checks))
