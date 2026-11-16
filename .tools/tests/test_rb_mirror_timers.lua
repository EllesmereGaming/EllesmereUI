-- Stub harness: the Resource Bars timer bars (Breath, Fatigue, Feign Death,
-- Battle Start, Group Countdown) and their OTHER BARS options section. Loads
-- the real EUI_ResourceBars_MirrorTimer.lua and MirrorTimerPage_Options.lua
-- over stand-ins for the game: frames that record what they are told, a clock
-- the test moves, timers it fires by hand, and Blizzard's own timer frames.
--   lua .tools/tests/test_rb_mirror_timers.lua        (from the repository root)
local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 40 then print("  FAIL: " .. tostring(msg)) end
    end
    return cond
end
local function eq(a, b, msg)
    return check(a == b, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function near(a, b, msg)
    return check(type(a) == "number" and math.abs(a - b) < 1e-6, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return s
end
local RUNTIME = Read("EllesmereUIResourceBars/EUI_ResourceBars_MirrorTimer.lua")
local PAGE = Read("EllesmereUIOptions/ResourceBars_Options/MirrorTimerPage_Options.lua")
local HELPERS = Read("EllesmereUI_SharedHelpers.lua")
-- A file-scope function of a source file: from its first line to the "end" in
-- column 0 that closes it.
local function Cut(src, first)
    local a = assert(src:find(first, 1, true), "not found: " .. first)
    local b = assert(src:find("\nend\n", a, true), "no closing end: " .. first)
    return src:sub(a, b + 4)
end
local PARENT_SRC = Cut(HELPERS, "function EllesmereUI.IsSecret(v)")
    .. Cut(HELPERS, "function EllesmereUI.CastChromeGeom(forever, iconSide)")

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local ALL_EVENTS = { "MIRROR_TIMER_START", "MIRROR_TIMER_PAUSE", "MIRROR_TIMER_STOP", "PLAYER_ENTERING_WORLD",
    "START_TIMER", "STOP_TIMER_OF_TYPE", "START_PLAYER_COUNTDOWN", "CANCEL_PLAYER_COUNTDOWN" }

-------------------------------------------------------------------------------
--  The world: one load of the runtime file
-------------------------------------------------------------------------------
-- o: on = { id = true } (bars turned on), lowWarn = { id = percent }, style
-- ("eui" / "blizzard" / "classic"), foreverArt, castBar (overrides)
local function World(o)
    o = o or {}
    local w = { now = 100, created = 0, blizzWrites = 0, progress = {}, info = {}, frames = {}, bindings = {}, secrets = {} }

    local function Obj(kind, name, parent)
        local t = { _kind = kind, _name = name, _parent = parent, _alpha = 1, _shown = true, _level = 1,
                    _children = {}, _regions = {}, _points = {} }
        return setmetatable(t, { __index = function(_, k)
            -- Methods are CamelCase; anything else is a field that is not set.
            if type(k) ~= "string" or not k:find("^%u") then return nil end
            if k == "GetFrameLevel" then return function(s) return s._level end end
            if k == "SetFrameLevel" then return function(s, v) s._level = v end end
            if k == "CreateTexture" or k == "CreateFontString" then
                return function(s) local r = Obj("region", nil, s); s._regions[#s._regions + 1] = r; return r end
            end
            if k == "GetStatusBarTexture" then return function(s) s._fill = s._fill or Obj("region", nil, s); return s._fill end end
            if k == "GetParent" then return function(s) return s._parent end end
            if k == "SetParent" then return function(s, p) s._parent = p end end
            if k == "CreateAnimationGroup" then return function(s) s._anim = Obj("anim"); return s._anim end end
            if k == "CreateAnimation" then return function() return Obj("anim") end end
            if k == "IsPlaying" then return function(s) return s._playing or false end end
            if k == "Play" then return function(s) s._playing = true end end
            if k == "Stop" then return function(s) s._playing = false end end
            if k == "SetAlpha" then return function(s, a) s._alpha = a; if s._blizz then w.blizzWrites = w.blizzWrites + 1 end end end
            if k == "Show" then return function(s) s._shown = true; if s._blizz then w.blizzWrites = w.blizzWrites + 1 end end end
            if k == "Hide" then return function(s) s._shown = false; if s._blizz then w.blizzWrites = w.blizzWrites + 1 end end end
            if k == "IsShown" then return function(s) return s._shown end end
            if k == "GetLeft" then return function() return 10 end end
            if k == "SetText" then return function(s, v) s._text = v end end
            if k == "SetSize" then return function(s, a, b) s._w, s._h = a, b end end
            if k == "ClearAllPoints" then return function(s) s._points = {} end end
            if k == "SetPoint" then return function(s, ...) s._points[#s._points + 1] = { ... } end end
            if k == "SetStatusBarColor" then return function(s, r, g, b, a) s._color = { r, g, b, a } end end
            if k == "SetTimerDuration" then return function(s, dur, _, dir) s._dur, s._dir = dur, dir end end
            if k == "RegisterEvent" then return function(s, e) s._events = s._events or {}; s._events[e] = true end end
            if k == "UnregisterEvent" then return function(s, e) if s._events then s._events[e] = nil end end end
            if k == "UnregisterAllEvents" then return function(s) s._events = {} end end
            if k == "SetScript" then return function(s, n, fn) s["_on" .. n] = fn end end
            if k == "SetFontString" then return function(s, fs) s._fs = fs end end
            if k == "SetEnabled" then return function(s, v) s._enabled = v end end
            return function() end
        end })
    end
    w.Obj = Obj

    local profile = {
        castBar = { width = 220, height = 20, showSpark = true },
        mirrorTimer = {},
    }
    for k, v in pairs(o.castBar or {}) do profile.castBar[k] = v end
    for _, id in ipairs({ "breath", "fatigue", "feign", "pvp", "countdown" }) do
        local warn = o.lowWarn and o.lowWarn[id]
        profile.mirrorTimer[id] = { enabled = o.on and o.on[id] or false, fillR = 0.2, fillG = 0.4, fillB = 0.6, fillA = 1,
            lowWarn = warn and true or false, lowWarnAt = warn or 30 }
    end
    w.profile = profile

    local timers = {}
    w.timers = timers
    local E = {
        L = function(s) return s end,
        PP = { CreateBorder = function() end, mult = 1 },
        ApplyBorderStyle = function() end, BorderPx = function() return 1 end,
        ResolveTexturePath = function() return "tex" end, RoundCorners = function() end, StockAtlas = function() end,
        AuraKit = { GetDurationFormatter = function() return {} end },
        SetElementVisibility = function(f, on) f._vis = on end,
        _unlockActive = false,
    }
    function E:RegisterUnlockModeListener(key, fn) w.unlockListener = fn; w.unlockKey = key end
    w.E = E
    local ns = { ERB = { db = { profile = profile } }, SPARK_TEX = "spark",
        SetRBFont = function() end, GetRBFont = function() return "font" end,
        SnapXY = function(x, y) return x, y end,
        ERB_CastStyle = function() return o.style or "eui" end,
        ERB_CastForever = function() return o.foreverArt or false end,
        ERB_BlizzAtlas = function(key) return "atlas-" .. key end,
        ERB_StockAtlas = function(tex, name) tex._atlas = name end,
        ERB_EuiBorderPad = function() return 0, 0 end,
        ERB_SeatClassicChrome = function(tex) tex._classic = true end,
        ERB_ClassicFrameK = function() return 1 end,
        ERB_CLASSIC = { spark = "classic-spark", sparkSize = 32, barH = 16, sparkY = 2 },
    }
    w.ns = ns

    local env = setmetatable({
        EllesmereUI = E,
        GetTime = function() return w.now end,
        -- restricted: the SECRET token, or a plain value the test marks for a while
        issecretvalue = function(v) return v == SECRET or (v ~= nil and w.secrets[v] == true) end,
        CreateFrame = function(kind, name, parent)
            local f = Obj(kind, name, parent)
            w.created = w.created + 1
            w.frames[#w.frames + 1] = f
            if parent and parent._children then parent._children[#parent._children + 1] = f end
            if name then w[name] = f end
            return f
        end,
        UIParent = Obj("Frame", "UIParent"),
        Enum = { StartTimerType = { PvPBeginTimer = 0, ChallengeModeCountdown = 1, PlayerCountdown = 2 },
                 StatusBarInterpolation = { Immediate = 0 },
                 StatusBarTimerDirection = { ElapsedTime = "ELAPSED", RemainingTime = "REMAINING" } },
        C_DurationUtil = {
            CreateDuration = function()
                local d = {}
                function d:SetTimeFromStart(s, total) self.start, self.total, self.finish = s, total, s + total end
                function d:SetTimeFromEnd(e, total) self.finish, self.total, self.start = e, total, e - total end
                return d
            end,
            CreateDurationTextBinding = function() local b = Obj("binding"); w.bindings[#w.bindings + 1] = b; return b end,
        },
        C_Spell = { GetSpellName = function() return "Feign Death" end },
        C_Timer = {
            After = function(_, fn) timers[#timers + 1] = { fn = fn, after = true } end,
            NewTimer = function(sec, fn)
                local t = { sec = sec, fn = fn, at = w.now + sec }
                function t:Cancel() self.cancelled = true end
                timers[#timers + 1] = t
                return t
            end,
        },
        BREATH_LABEL = "Breath", EXHAUSTION_LABEL = "Fatigue",
        GetMirrorTimerProgress = function(t) local v = w.progress[t]; w.progressReads = (w.progressReads or 0) + 1; return v end,
        GetMirrorTimerInfo = function(i) local t = w.info[i]; if t then return unpack(t) end return "UNKNOWN", 0, 0, 0, 0, "" end,
    }, { __index = _G })
    local function Blizz() local f = Obj("Frame"); f._blizz = true; return f end
    env.MirrorTimerContainer = { mirrorTimers = { Blizz(), Blizz(), Blizz() } }
    env.TimerTracker = { timerList = {} }
    env._G = env
    w.env = env
    w.blizz = env.MirrorTimerContainer.mirrorTimers
    w.tracker = env.TimerTracker.timerList
    function w.Tracker(type) local t = { type = type, bar = Blizz() }; w.tracker[#w.tracker + 1] = t; return t end

    setfenv(assert(loadstring(PARENT_SRC, "=parent helpers")), env)()
    setfenv(assert(loadstring(RUNTIME, "=MirrorTimer")), env)("EllesmereUIResourceBars", ns)

    for _, f in ipairs(w.frames) do if f._onOnEvent then w.ev = f end end
    function w.Fire(e, ...) w.ev._onOnEvent(w.ev, e, ...) end
    function w.Events() local n = 0 for _ in pairs(w.ev._events or {}) do n = n + 1 end return n end
    -- the next frame: every C_Timer.After(0, ...) asked for so far
    function w.NextFrame()
        local list = {}
        for i = #timers, 1, -1 do if timers[i].after then table.insert(list, 1, table.remove(timers, i)) end end
        for _, t in ipairs(list) do t.fn() end
    end
    -- the one-shot timers still pending, soonest first
    function w.Pending()
        local list = {}
        for _, t in ipairs(timers) do if not t.after and not t.cancelled and not t.fired then list[#list + 1] = t end end
        table.sort(list, function(a, b) return a.at < b.at end)
        return list
    end
    function w.FireTimer(t) t.fired = true; t.fn() end
    function w.Frame(id) return w["ERB_Mirror_" .. id] end
    -- the parts of a built bar, by the order BuildBar makes them
    function w.Parts(id)
        local f = assert(w.Frame(id), "no bar frame: " .. id)
        local clip, art, textFrame = f._children[2], f._children[3], f._children[4]
        local p = { frame = f, clip = clip, bar = clip._children[1], spark = clip._children[2]._regions[1],
            frameTex = art._regions[1], label = textFrame._regions[1], time = textFrame._regions[2], pulse = clip._anim }
        for _, b in ipairs(w.bindings) do if b._fs == p.time then p.binding = b end end
        return p
    end
    -- what the engine was told to show: seconds left (draining) or seconds in (filling)
    function w.Left(id) local b = w.Parts(id).bar; return b._dur.finish - w.now, b._dur.total, b._dir end
    function w.Shown(id) local f = w.Frame(id); return f and f._vis or false end
    -- runs fn while the game holds v back
    function w.Restricted(v, fn, ...)
        w.secrets[v] = true
        local ok, err = pcall(fn, ...)
        w.secrets[v] = nil
        return ok, err
    end
    return w
end

-------------------------------------------------------------------------------
-- 1. Off: nothing is built, registered, timed or touched
-------------------------------------------------------------------------------
do
    local w = World()
    eq(w.Events(), 0, "no bar on: events after the load")
    eq(w.created, 1, "no bar on: frames made by the load (the one event frame)")
    w.ns.MT_Apply()
    w.ns.MT_Apply()
    eq(w.Events(), 0, "no bar on: events after two applies")
    eq(w.created, 1, "no bar on: frames after two applies")
    eq(#w.timers, 0, "no bar on: timers asked for")
    eq(w.blizzWrites, 0, "no bar on: writes to Blizzard's timer frames")
    eq(w.progressReads or 0, 0, "no bar on: reads of the game's timers")
    eq(w.ERB_MirrorBars, nil, "no bar on: no stack frame")
    -- Blizzard's frames are not even looked at
    local looked = false
    w.env.MirrorTimerContainer = setmetatable({}, { __index = function() looked = true end })
    w.env.TimerTracker = setmetatable({}, { __index = function() looked = true end })
    w.ns.MT_Apply()
    eq(looked, false, "no bar on: Blizzard's timer frames are not read")
end

-------------------------------------------------------------------------------
-- 2. A bar turned on: the events, the frames once, and all of it released
-------------------------------------------------------------------------------
do
    local w = World({ on = { breath = true } })
    w.ns.MT_Apply()
    eq(w.Events(), #ALL_EVENTS, "Breath on: events registered")
    for _, e in ipairs(ALL_EVENTS) do check(w.ev._events[e], "Breath on: listens to " .. e) end
    check(w.Frame("breath") ~= nil, "Breath on: its bar is built")
    eq(w.Frame("fatigue"), nil, "Breath on: no bar for Fatigue")
    check(w.ERB_MirrorBars ~= nil, "Breath on: the stack frame is made")
    eq(w.Shown("breath"), false, "Breath on, no timer: the bar is hidden")
    local made = w.created
    w.ns.MT_Apply()
    w.ns.MT_Apply()
    eq(w.created, made, "later applies build nothing again")

    w.profile.mirrorTimer.breath.enabled = false
    w.ns.MT_Apply()
    eq(w.Events(), 0, "Breath off again: every event released")
    eq(w.created, made, "Breath off again: nothing new built")
    eq(w.Shown("breath"), false, "Breath off again: hidden")
end

-------------------------------------------------------------------------------
-- 3. A breath: the engine gets the event's numbers; Blizzard's bar is hidden
-------------------------------------------------------------------------------
do
    local w = World({ on = { breath = true } })
    w.ns.MT_Apply()
    w.progress.BREATH = 5000   -- must not be read at the start: the event brings the value
    w.blizz[1].timer = "BREATH"
    w.Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath (label)")
    local left, total, dir = w.Left("breath")
    near(left, 180, "a 3 minute breath: seconds left")
    near(total, 180, "a 3 minute breath: of")
    eq(dir, "REMAINING", "a draining bar counts down")
    local p = w.Parts("breath")
    eq(p.label._text, "Breath (label)", "the bar is named by the event's label")
    eq(p.binding._enabled, true, "the engine writes the seconds")
    eq(w.Shown("breath"), true, "the bar shows")
    eq(w.blizz[1]._alpha, 1, "Blizzard's frame is untouched inside the event")
    w.NextFrame()
    eq(w.blizz[1]._alpha, 0, "Blizzard's frame for that timer is hidden on the next frame")
    eq(w.blizz[2]._alpha, 1, "Blizzard's other frames keep their alpha")
    eq(w.blizzWrites, 1, "one write to Blizzard's frames: the hidden one")
    local c = p.bar._color
    check(c[1] == 0.2 and c[2] == 0.4 and c[3] == 0.6, "the fill is the bar's own colour")

    -- a timer of a kind that is off: no bar, and Blizzard's frame for it stays
    w.blizz[2].timer = "EXHAUSTION"
    w.Fire("MIRROR_TIMER_START", "EXHAUSTION", 60000, 60000, -1, 0, "Fatigue")
    w.NextFrame()
    eq(w.Frame("fatigue"), nil, "Fatigue off: no bar built by its timer")
    eq(w.blizz[2]._alpha, 1, "Fatigue off: Blizzard's bar for it shows")
    eq(w.blizz[1]._alpha, 0, "Breath's stays hidden meanwhile")
end

-------------------------------------------------------------------------------
-- 4. A later apply reads where the timer stands (it does not restart the bar
--    from the start event's value)
-------------------------------------------------------------------------------
do
    local w = World({ on = { breath = true }, lowWarn = { breath = 30 } })
    w.ns.MT_Apply()
    w.Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath")
    local warn = w.Pending()
    eq(#warn, 1, "Low Warning on: one timer armed at the start")
    near(warn[1].sec, 126, "armed for when 30% is left")

    w.now = 160                    -- 60 s later
    w.progress.BREATH = 120000     -- the game: 120 s of breath left
    w.ns.MT_Apply()                -- a roster change, the options opening, Unlock Mode...
    local left, total = w.Left("breath")
    near(left, 120, "after a settings apply 60 s in: seconds left")
    near(total, 180, "after a settings apply: of")
    warn = w.Pending()
    eq(#warn, 1, "the warning is armed once")
    near(warn[1].sec, 66, "and from where the timer stands")

    -- the game gives no answer (or a restricted one): the bar keeps its last reading
    w.now = 170
    w.progress.BREATH = nil
    w.ns.MT_Apply()
    near((w.Left("breath")), 110, "no answer from the game: the last value read stands (120 s as of 160)")
    w.now = 175
    w.progress.BREATH = SECRET
    local ok, err = pcall(w.ns.MT_Apply)
    check(ok, "a restricted answer raises nothing (" .. tostring(err) .. ")")
    near((w.Left("breath")), 105, "a restricted answer: the bar goes on from its last reading")

    -- every apply path lands here: the world apply after a loading screen too
    w.progress.BREATH = 90000
    w.now = 190
    w.ns.MT_Apply()
    near((w.Left("breath")), 90, "a later apply reads again")
end

-------------------------------------------------------------------------------
-- 5. Low Warning
-------------------------------------------------------------------------------
do
    local w = World({ on = { breath = true }, lowWarn = { breath = 30 } })
    w.ns.MT_Apply()
    w.Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath")
    local p = w.Parts("breath")
    eq(p.pulse._playing or false, false, "above the threshold: no blink")
    w.now = w.now + 126
    w.FireTimer(w.Pending()[1])
    local c = p.bar._color
    check(c[1] == 1 and c[2] == 0.1 and c[3] == 0.1, "at the threshold the fill turns red")
    eq(p.pulse._playing, true, "and blinks")

    -- a timer that starts already below the threshold warns at once
    w.Fire("MIRROR_TIMER_STOP", "BREATH")
    eq(p.pulse._playing, false, "the blink stops with the timer")
    w.Fire("MIRROR_TIMER_START", "BREATH", 30000, 180000, -1, 0, "Breath")
    eq(p.bar._color[1], 1, "started under the threshold: red at once")
    eq(p.pulse._playing, true, "started under the threshold: blinking")
    eq(#w.Pending(), 0, "started under the threshold: no timer to wait for")

    -- a refilling bar never warns
    w.Fire("MIRROR_TIMER_START", "BREATH", 30000, 180000, 10, 0, "Breath")
    eq(p.bar._color[1], 0.2, "refilling: the fill colour")
    eq(p.pulse._playing, false, "refilling: no blink")
    eq(#w.Pending(), 0, "refilling: no warning timer")

    -- paused under the threshold: red, not blinking
    w.Fire("MIRROR_TIMER_START", "BREATH", 30000, 180000, -1, 1, "Breath")
    eq(p.bar._color[1], 1, "paused under the threshold: red")
    eq(p.pulse._playing, false, "paused under the threshold: not blinking")

    -- off: no timer, no red
    w = World({ on = { breath = true } })
    w.ns.MT_Apply()
    w.Fire("MIRROR_TIMER_START", "BREATH", 30000, 180000, -1, 0, "Breath")
    eq(#w.Pending(), 0, "Low Warning off: no timer")
    eq(w.Parts("breath").bar._color[1], 0.2, "Low Warning off: the fill colour")
end

-------------------------------------------------------------------------------
-- 6. Pause, resume, refill, stop
-------------------------------------------------------------------------------
do
    local w = World({ on = { breath = true }, lowWarn = { breath = 30 } })
    w.ns.MT_Apply()
    w.blizz[1].timer = "BREATH"
    w.Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath")
    w.NextFrame()
    local p = w.Parts("breath")
    w.now = 130
    w.progress.BREATH = 150000
    w.Fire("MIRROR_TIMER_PAUSE", "BREATH", 1)
    eq(p.binding._enabled, false, "paused: the engine stops writing the seconds")
    eq(p.time._text, "2:30", "paused: the seconds where the timer stands")
    eq(p.bar._dir, "ELAPSED", "paused: a standing fill")
    near((w.now - p.bar._dur.start) / p.bar._dur.total, 150 / 180, "paused: the fill where the timer stands")
    eq(#w.Pending(), 0, "paused: no warning timer runs")
    w.now = 140
    w.Fire("MIRROR_TIMER_PAUSE", "BREATH", 0)
    eq(p.binding._enabled, true, "resumed: the engine writes the seconds again")
    near((w.Left("breath")), 150, "resumed: from where the timer stands")
    near(w.Pending()[1].sec, 96, "resumed: the warning is armed from there")

    -- a pause for a timer that is not ours, or a restricted one, is ignored
    w.Fire("MIRROR_TIMER_PAUSE", "EXHAUSTION", 1)
    w.Fire("MIRROR_TIMER_PAUSE", SECRET, 1)
    w.Fire("MIRROR_TIMER_PAUSE", "BREATH", SECRET)
    w.Restricted("BREATH", w.Fire, "MIRROR_TIMER_PAUSE", "BREATH", 1)
    w.Restricted(1, w.Fire, "MIRROR_TIMER_PAUSE", "BREATH", 1)
    eq(p.binding._enabled, true, "a pause that is not this bar's changes nothing")

    -- a pause the game gives no reading for: the bar stands where its rate had
    -- carried it, and stays there through later applies
    w.progress.BREATH = nil
    w.now = 170                       -- 30 s after the resume at 150 s left
    w.Fire("MIRROR_TIMER_PAUSE", "BREATH", 1)
    eq(p.time._text, "2:00", "paused with no reading: where the rate had carried it")
    w.now = 200
    w.ns.MT_Apply()
    eq(p.time._text, "2:00", "a paused timer does not move through a later apply")
    near((w.now - p.bar._dur.start) / p.bar._dur.total, 120 / 180, "its fill stands too")
    w.Fire("MIRROR_TIMER_PAUSE", "BREATH", 0)

    -- refilling at the surface: a new start with a rate above 0
    w.progress.BREATH = 60000
    w.Fire("MIRROR_TIMER_START", "BREATH", 60000, 180000, 10, 0, "Breath")
    eq(p.bar._dir, "ELAPSED", "refilling: the bar fills up")
    near(p.bar._dur.total, 18, "refilling: the whole bar takes max / rate")
    near(w.now - p.bar._dur.start, 6, "refilling: it stands where the value is")
    near(p.bar._dur.finish - w.now, 12, "refilling: seconds to full")

    -- stop: the bar goes, the warning timer too, and Blizzard's frame comes back
    w.Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath")
    eq(#w.Pending(), 1, "running again: a warning timer")
    w.Fire("MIRROR_TIMER_STOP", "EXHAUSTION")
    eq(w.Shown("breath"), true, "another timer's stop leaves the bar")
    w.Fire("MIRROR_TIMER_STOP", SECRET)
    w.Restricted("BREATH", w.Fire, "MIRROR_TIMER_STOP", "BREATH")
    eq(w.Shown("breath"), true, "a restricted stop leaves the bar")
    w.NextFrame()                    -- everything asked for so far has run
    eq(w.blizz[1]._alpha, 0, "running: Blizzard's frame is hidden")
    w.Fire("MIRROR_TIMER_STOP", "BREATH")
    eq(w.Shown("breath"), false, "stopped: the bar hides")
    eq(#w.Pending(), 0, "stopped: the warning timer is cancelled")
    eq(w.blizz[1]._alpha, 0, "stopped: Blizzard's frame is still as we left it inside the event")
    w.blizz[1].timer = nil          -- Blizzard's own handler frees the frame
    w.NextFrame()
    eq(w.blizz[1]._alpha, 1, "stopped: Blizzard's free frame gets its alpha back on the next frame")

    -- a restricted start shows nothing and raises nothing
    for i = 1, 6 do
        local a = { "BREATH", 170000, 180000, -1, 0, "Breath" }
        local plain = a[i]
        a[i] = SECRET
        local ok, err = pcall(w.Fire, "MIRROR_TIMER_START", unpack(a))
        check(ok, "a start with a restricted argument " .. i .. " raises nothing (" .. tostring(err) .. ")")
        eq(w.Shown("breath"), false, "a start with a restricted argument " .. i .. " shows no bar")
        -- the same, the value being one the game holds back
        a[i] = plain
        ok, err = w.Restricted(plain, w.Fire, "MIRROR_TIMER_START", unpack(a))
        check(ok, "a start with a held-back argument " .. i .. " raises nothing (" .. tostring(err) .. ")")
        eq(w.Shown("breath"), false, "a start with a held-back argument " .. i .. " shows no bar")
    end

    -- Feign Death's bar also shows the DEATH timer; a stop names its own timer
    w = World({ on = { feign = true } })
    w.ns.MT_Apply()
    w.Fire("MIRROR_TIMER_START", "FEIGNDEATH", 360000, 360000, -1, 0, "Feign Death")
    eq(w.Shown("feign"), true, "Feign Death: its bar shows")
    w.Fire("MIRROR_TIMER_STOP", "DEATH")
    eq(w.Shown("feign"), true, "the stop of the bar's other timer leaves it")
    w.Fire("MIRROR_TIMER_STOP", "FEIGNDEATH")
    eq(w.Shown("feign"), false, "its own stop ends it")
    w.Fire("MIRROR_TIMER_START", "DEATH", 360000, 360000, -1, 0, "Release")
    eq(w.Shown("feign"), true, "the DEATH timer shows on the same bar")
end

-------------------------------------------------------------------------------
-- 7. Blizzard's frame reused for a timer that is not ours
-------------------------------------------------------------------------------
do
    local w = World({ on = { breath = true } })
    w.ns.MT_Apply()
    w.blizz[1].timer = "BREATH"
    w.Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath")
    w.NextFrame()
    eq(w.blizz[1]._alpha, 0, "Breath: Blizzard's frame hidden")
    w.blizz[1].timer = "EXHAUSTION"   -- no stop seen: the frame went straight to another timer
    w.Fire("MIRROR_TIMER_START", "EXHAUSTION", 60000, 60000, -1, 0, "Fatigue")
    w.NextFrame()
    eq(w.blizz[1]._alpha, 1, "the frame now shows a timer that is not ours: its alpha is back")

    -- the last bar turned off while Blizzard's frame is hidden: handed back at once
    w.blizz[1].timer = "BREATH"
    w.Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath")
    w.NextFrame()
    eq(w.blizz[1]._alpha, 0, "hidden again")
    eq(w.Shown("breath"), true, "the bar is up")
    w.profile.mirrorTimer.breath.enabled = false
    w.ns.MT_Apply()
    eq(w.blizz[1]._alpha, 1, "Breath turned off: Blizzard's bar shows again")
    eq(w.Shown("breath"), false, "Breath turned off mid-timer: its bar hides")
    local writes = w.blizzWrites
    w.ns.MT_Apply()
    eq(w.blizzWrites, writes, "and later applies write nothing to Blizzard's frames")

    -- a bar built earlier and now off takes no timer (another bar keeps the events)
    w = World({ on = { breath = true, fatigue = true }, lowWarn = { breath = 30 } })
    w.ns.MT_Apply()
    w.profile.mirrorTimer.breath.enabled = false
    w.ns.MT_Apply()
    eq(w.Events(), #ALL_EVENTS, "Fatigue still on: the events stay")
    w.Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath")
    eq(w.Shown("breath"), false, "Breath off: its timer shows no bar")
    eq(#w.Pending(), 0, "Breath off: its timer arms nothing")
end

-------------------------------------------------------------------------------
-- 8. The countdowns
-------------------------------------------------------------------------------
do
    local w = World({ on = { countdown = true, pvp = true } })
    w.ns.MT_Apply()
    local tb = w.Tracker(2)
    w.Fire("START_PLAYER_COUNTDOWN", "guid", 60, 60, true, "Lead")
    local left, total, dir = w.Left("countdown")
    near(left, 60, "a 60 s countdown: seconds left")
    near(total, 60, "a 60 s countdown: of")
    eq(dir, "REMAINING", "a countdown counts down")
    eq(w.Shown("countdown"), true, "the bar shows")
    eq(tb.bar._shown, true, "Blizzard's countdown bar is untouched inside the event")
    w.NextFrame()
    eq(tb.bar._shown, false, "Blizzard's countdown bar is hidden on the next frame")
    local step = w.Pending()
    eq(#step, 1, "one timer: the step aside")
    near(step[1].sec, 29, "at 31 s left, where the game's numbers take over")
    w.now = w.now + 29
    w.FireTimer(step[1])
    eq(w.Shown("countdown"), false, "under the numbers: our bar steps aside")

    -- a short countdown never shows a bar (the numbers start at once)
    w.Fire("START_PLAYER_COUNTDOWN", "guid", 10, 10, true, "Lead")
    eq(w.Shown("countdown"), false, "a 10 s countdown: no bar")
    eq(#w.Pending(), 0, "a 10 s countdown: no timer")

    -- a cancel: the bar goes and Blizzard's bar comes back
    w.Fire("START_PLAYER_COUNTDOWN", "guid", 60, 60, true, "Lead")
    w.NextFrame()
    eq(w.Shown("countdown"), true, "a new countdown shows again")
    eq(tb.bar._shown, false, "and hides Blizzard's bar")
    w.Fire("CANCEL_PLAYER_COUNTDOWN", "guid", true, "Lead")
    eq(w.Shown("countdown"), false, "cancelled: our bar hides")
    eq(tb.bar._shown, true, "cancelled: Blizzard's bar is shown again")
    eq(#w.Pending(), 0, "cancelled: no timer left")

    -- a cancel that comes as a start with no time left
    w.Fire("START_PLAYER_COUNTDOWN", "guid", 60, 60, true, "Lead")
    w.NextFrame()
    eq(w.Shown("countdown"), true, "running again")
    eq(tb.bar._shown, false, "Blizzard's bar hidden again")
    w.Fire("START_PLAYER_COUNTDOWN", "guid", 0, 0, true, "Lead")
    eq(w.Shown("countdown"), false, "a start with no time: our bar hides")
    eq(tb.bar._shown, true, "a start with no time: Blizzard's bar is shown again")

    -- restricted numbers (the chat lockdown): no bar of ours, Blizzard's stays
    local ok, err = pcall(w.Fire, "START_PLAYER_COUNTDOWN", SECRET, SECRET, SECRET, SECRET, SECRET)
    check(ok, "a restricted countdown raises nothing (" .. tostring(err) .. ")")
    w.NextFrame()
    eq(w.Shown("countdown"), false, "a restricted countdown: no bar of ours")
    eq(tb.bar._shown, true, "a restricted countdown: Blizzard's bar stays")
    for _, held in ipairs({ 61, 62 }) do
        ok, err = w.Restricted(held, w.Fire, "START_PLAYER_COUNTDOWN", "guid", 61, 62, true, "Lead")
        check(ok, "a held-back countdown number raises nothing (" .. tostring(err) .. ")")
        w.NextFrame()
        eq(w.Shown("countdown"), false, "a held-back countdown number: no bar of ours")
        eq(tb.bar._shown, true, "a held-back countdown number: Blizzard's bar stays")
    end

    -- the battleground start: steps aside at 11 s; STOP_TIMER_OF_TYPE ends it
    local pv = w.Tracker(0)
    w.Fire("START_TIMER", 0, 120, 120)
    w.NextFrame()
    near((w.Left("pvp")), 120, "the battleground start: seconds left")
    near(w.Pending()[1].sec, 109, "it steps aside at 11 s left")
    eq(pv.bar._shown, false, "Blizzard's bar for it is hidden")
    w.Fire("START_TIMER", 0, 60, 120)      -- the game corrects the time
    eq(#w.Pending(), 1, "a corrected time: one step timer")
    near(w.Pending()[1].sec, 49, "a corrected time: re-armed")
    near((w.Left("pvp")), 60, "a corrected time: the bar follows")
    w.Fire("STOP_TIMER_OF_TYPE", 0)
    eq(w.Shown("pvp"), false, "stopped: the bar hides")
    eq(pv.bar._shown, true, "stopped: Blizzard's bar is shown again")
    -- a type we draw no bar for
    w.Fire("START_TIMER", 1, 10, 10)
    w.NextFrame()
    eq(w.Shown("pvp"), false, "a Mythic+ start countdown draws no bar")
    w.Fire("STOP_TIMER_OF_TYPE", SECRET)
    w.Fire("START_TIMER", SECRET, 10, 10)

    -- Blizzard reuses a hidden bar's frame for a type that is not ours
    w.Fire("START_PLAYER_COUNTDOWN", "guid", 60, 60, true, "Lead")
    w.NextFrame()
    eq(tb.bar._shown, false, "hidden for our countdown")
    tb.type = 1
    w.Fire("START_TIMER", 1, 10, 10)
    w.NextFrame()
    eq(tb.bar._shown, true, "the frame now runs another type: its bar is shown again")
end

-------------------------------------------------------------------------------
-- 9. A loading screen: the timers are read again; a group countdown lives on
-------------------------------------------------------------------------------
do
    local w = World({ on = { breath = true, pvp = true, countdown = true } })
    w.ns.MT_Apply()
    w.Fire("START_TIMER", 0, 120, 120)
    w.Fire("START_PLAYER_COUNTDOWN", "guid", 90, 90, true, "Lead")
    w.Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath")
    eq(w.Shown("pvp") and w.Shown("countdown") and w.Shown("breath"), true, "three bars up")
    w.now = 110
    w.info[2] = { "BREATH", 180000, 180000, -1, 0, "Breath" }
    w.progress.BREATH = 170000
    w.Fire("PLAYER_ENTERING_WORLD")
    eq(w.Shown("pvp"), false, "a loading screen drops the battleground start")
    eq(w.Shown("countdown"), true, "the group countdown lives through it")
    eq(w.Shown("breath"), true, "a breath still running is read again")
    near((w.Left("breath")), 170, "from where the game says it stands")
    w.info[2] = nil
    w.Fire("PLAYER_ENTERING_WORLD")
    eq(w.Shown("breath"), false, "no breath running after the next one: the bar is gone")

    -- a bar turned on under water picks the running timer up
    w = World()
    w.info[1] = { "BREATH", 180000, 180000, -1, 0, "Breath" }
    w.progress.BREATH = 100000
    w.profile.mirrorTimer.breath.enabled = true
    w.ns.MT_Apply()
    eq(w.Shown("breath"), true, "turned on mid-timer: the bar shows")
    near((w.Left("breath")), 100, "turned on mid-timer: where the timer stands")
end

-------------------------------------------------------------------------------
-- 10. The stack and its one mover; samples in Unlock Mode
-------------------------------------------------------------------------------
do
    local w = World({ on = { breath = true, fatigue = true, countdown = true } })
    local els = w.ns.MT_MakeUnlockElements(function(def) return def end)
    eq(#els, 1, "one unlock element for every timer bar")
    local el = els[1]
    eq(el.key, "ERB_MirrorBars", "its key")
    eq(w.ns.MT_UNLOCK_KEY, "ERB_MirrorBars", "the key the options read")
    eq(el.noResize, true, "it is not resized from the mover")
    eq(el.isHidden(), false, "bars on: the mover shows")
    w.ns.MT_Apply()
    local sw, sh = el.getSize()
    eq(sw, 220, "the stack is as wide as the cast bar")
    eq(sh, 3 * 20 + 2 * 3, "and as tall as the bars turned on, stacked")
    eq(el.getFrame(), w.ERB_MirrorBars, "the mover's frame is the stack")

    -- live: only the bars up take a slot, in the fixed order
    w.Fire("MIRROR_TIMER_START", "EXHAUSTION", 60000, 60000, -1, 0, "Fatigue")
    local pt = w.Frame("fatigue")._points[1]
    check(pt[1] == "TOP" and pt[2] == w.ERB_MirrorBars and pt[5] == 0, "one bar up: it sits at the stack's top")
    w.Fire("MIRROR_TIMER_START", "BREATH", 180000, 180000, -1, 0, "Breath")
    eq(w.Frame("breath")._points[1][5], 0, "Breath joins: it takes the top (its place in the order)")
    eq(w.Frame("fatigue")._points[1][5], -23, "Fatigue moves one slot down")
    w.Fire("MIRROR_TIMER_STOP", "BREATH")
    eq(w.Frame("fatigue")._points[1][5], 0, "Breath ends: the stack closes up")

    -- Unlock Mode: every bar turned on shows a standing sample
    eq(w.unlockKey, "ERB_Mirror", "the Unlock Mode listener is registered with the element")
    w.unlockListener(true)
    eq(w.Shown("breath") and w.Shown("fatigue") and w.Shown("countdown"), true, "Unlock Mode: the three bars on show")
    eq(w.Frame("feign"), nil, "Unlock Mode: a bar that is off shows no sample")
    local p = w.Parts("breath")
    eq(p.label._text, "Breath", "a sample is named as the live bar")
    eq(p.binding._enabled, false, "a sample stands still")
    near((w.now - p.bar._dur.start) / p.bar._dur.total, 0.7, "a sample's fill")
    eq(w.Frame("countdown")._points[1][5], -46, "the samples stack in order")
    w.unlockListener(false)
    eq(w.Shown("breath"), false, "Unlock Mode closed: the sample goes")
    eq(w.Shown("fatigue"), true, "Unlock Mode closed: the live timer is back")

    -- the saved position
    el.savePos("ERB_MirrorBars", "TOP", "TOP", 5, -80)
    local pos = w.profile.mirrorTimer.unlockPos
    check(pos and pos.point == "TOP" and pos.x == 5 and pos.y == -80, "the mover's position is saved on the timer bars")
    local got = el.loadPos()
    check(got and got.point == "TOP" and got.relPoint == "TOP" and got.x == 5 and got.y == -80, "and read back")
    el.clearPos()
    eq(w.profile.mirrorTimer.unlockPos, nil, "and cleared")

    w = World()
    el = w.ns.MT_MakeUnlockElements(function(def) return def end)[1]
    eq(el.isHidden(), true, "no bar on: the mover is hidden")
    eq(el.getFrame(), nil, "no bar on: no frame")
    local ok, err = pcall(el.applyPos)
    check(ok, "no bar on: applying a position raises nothing (" .. tostring(err) .. ")")
end

-------------------------------------------------------------------------------
-- 11. The stock art's seat is the cast bar's (the parent's numbers)
-------------------------------------------------------------------------------
for _, c in ipairs({
    { "the EllesmereUI look", { style = "eui" }, nil, 8, 20, 0, 0 },
    { "Blizzard Style", { style = "blizzard" }, { -2, 2, 2, -2 }, 8, 20, 0, 0 },
    { "the WoW Forever art", { style = "blizzard", foreverArt = true }, { -2, 0, 2, -2 }, 5, 24, -1, -1 },
}) do
    local o = c[2]
    o.on = { breath = true }
    local w = World(o)
    w.ns.MT_Apply()
    local p = w.Parts("breath")
    if c[3] then
        eq(p.frameTex._shown, true, c[1] .. ": the frame art shows")
        local a, b = p.frameTex._points[1], p.frameTex._points[2]
        check(a[1] == "TOPLEFT" and a[4] == c[3][1] and a[5] == c[3][2], c[1] .. ": the art's top-left reach (" .. tostring(a[4]) .. ", " .. tostring(a[5]) .. ")")
        check(b[1] == "BOTTOMRIGHT" and b[4] == c[3][3] and b[5] == c[3][4], c[1] .. ": the art's bottom-right reach (" .. tostring(b[4]) .. ", " .. tostring(b[5]) .. ")")
    else
        eq(p.frameTex._shown, false, c[1] .. ": no frame art")
    end
    eq(p.spark._w, c[4], c[1] .. ": the spark's width")
    eq(p.spark._h, c[5], c[1] .. ": the spark's height")
    eq(p.spark._points[1][5], c[6], c[1] .. ": the spark's nudge")
    eq(p.time._points[1][5], c[7], c[1] .. ": the timer text's nudge")
end

-------------------------------------------------------------------------------
-- 12. The OTHER BARS options section
-------------------------------------------------------------------------------
local function Page(o)
    local w = World(o.world)
    local rec = { sections = {}, calls = {}, jumps = {} }
    local function Called(name) rec.calls[name] = (rec.calls[name] or 0) + 1 end
    rec.Calls = function(name) return rec.calls[name] or 0 end
    rec.Forget = function() rec.calls = {} end
    local function Frame() return w.Obj("Frame") end
    local W = {}
    function W:SectionHeader(_, title)
        local s = Frame()
        s.title, s.rows, s._label = title, {}, Frame()
        rec.sections[#rec.sections + 1] = s
        rec.cur = s
        return s, 30
    end
    function W:DualRow(_, _, left, right)
        local row = Frame()
        row.left, row.right = left, right
        row._leftRegion, row._rightRegion = Frame(), Frame()
        row._leftRegion.built, row._rightRegion.built = {}, {}
        rec.cur.rows[#rec.cur.rows + 1] = row
        return row, 40
    end
    function W:Spacer() return Frame(), 16 end
    local E = w.E
    E._prebuilding = o.prebuild or false
    E._ModuleNS = { EllesmereUIResourceBars = w.ns }
    E.Widgets = W
    E.BlankRowCfg = function() return { type = "label", text = "" } end
    E.BuildInlineCog = function(rgn, opts) rgn.built[#rgn.built + 1] = { kind = "cog", opts = opts } end
    E.BuildInlineSwatches = function(rgn, list, opts) rgn.built[#rgn.built + 1] = { kind = "swatches", list = list, opts = opts } end
    E.BuildSectionUnlockJump = function(hdr, opts) rec.jumps[#rec.jumps + 1] = { hdr = hdr, opts = opts } end
    E.NotifyElementResized = function(key) Called("NotifyElementResized:" .. tostring(key)) end
    function E:RefreshPage() Called("RefreshPage") end
    w.ns._ERB_OptEnv = { DB = function() return w.profile end }
    local apply = w.ns.MT_Apply
    w.ns.MT_Apply = function() Called("MT_Apply"); return apply() end
    w.env._ERB_Apply = function() Called("_ERB_Apply") end
    setfenv(assert(loadstring(PAGE, "=MirrorTimerPage")), w.env)()
    assert(w.ns.ERB_BuildTimerBarRows, "the options file did not load")
    rec.y = w.ns.ERB_BuildTimerBarRows(Frame(), -100)
    rec.w = w
    rec.Forget()
    return rec
end

do
    local rec = Page({})
    eq(#rec.sections, 1, "one section")
    local sec = rec.sections[1]
    eq(sec.title, "OTHER BARS", "its title")
    eq(#sec.rows, 3, "five bars, two per row")
    local names = {}
    for _, row in ipairs(sec.rows) do
        names[#names + 1] = row.left.text
        names[#names + 1] = row.right.text
    end
    eq(table.concat(names, " | "), "Breath | Fatigue | Feign Death | Battle Start | Group Countdown | ", "the bars, in order, with a blank last half")
    eq(sec.rows[3].right.type, "label", "the odd last half is a blank label")
    eq(rec.y, -100 - 16 - 30 - 3 * 40, "the section reports the y under it")

    -- the Move in Unlock Mode button on the title
    eq(#rec.jumps, 1, "one unlock jump")
    local jump = rec.jumps[1] or { opts = { disabled = function() end } }
    eq(jump.hdr, sec, "on the section's title")
    eq(jump.opts.key, "ERB_MirrorBars", "to the timer bars' mover")
    eq(jump.opts.disabled(), true, "greyed while no bar is on (the mover is hidden)")
    check(type(jump.opts.disabledTooltip) == "string", "and says why")

    -- each bar's half: the cog first (nearest the switch), then the swatch
    for i, row in ipairs(sec.rows) do
        for _, half in ipairs({ { row._leftRegion, row.left }, { row._rightRegion, row.right } }) do
            local rgn, cfg = half[1], half[2]
            if cfg.type == "toggle" then
                eq(#rgn.built, 2, cfg.text .. ": a cog and a swatch")
                eq(rgn.built[1] and rgn.built[1].kind, "cog", cfg.text .. ": the cog is built first")
                eq(rgn.built[2] and rgn.built[2].kind, "swatches", cfg.text .. ": the swatch after it")
                local cog, sw = rgn.built[1] or {}, rgn.built[2] or {}
                eq(sw.kind == "swatches" and sw.opts, nil, cfg.text .. ": the swatch takes the standard size")
                eq(cog.kind == "cog" and cog.opts.disabled(), true, cfg.text .. ": the cog is greyed while the bar is off")
                eq(sw.kind == "swatches" and sw.list[1].disabled(), true, cfg.text .. ": the swatch too")
            else
                eq(#rgn.built, 0, "row " .. i .. ": the blank half holds nothing")
            end
        end
    end

    -- the switch: saved, the timer bars' own apply, a resize notice, a page refresh
    local w = rec.w
    local row = sec.rows[1]
    eq(row.left.getValue(), false, "Breath reads off")
    row.left.setValue(true)
    eq(w.profile.mirrorTimer.breath.enabled, true, "the switch is saved")
    eq(rec.Calls("MT_Apply"), 1, "the switch runs the timer bars' apply")
    eq(rec.Calls("_ERB_Apply"), 0, "and not the whole Resource Bars apply")
    eq(rec.Calls("NotifyElementResized:ERB_MirrorBars"), 1, "the stack's new size is reported")
    eq(rec.Calls("RefreshPage"), 1, "the page refreshes (the cog and swatch come alive)")
    check(w.Frame("breath") ~= nil, "and the bar is built")
    if not (row._leftRegion.built[1].kind == "cog" and row._leftRegion.built[2].kind == "swatches") then
        error(fails .. " of " .. count .. " check(s) failed (a half is not built cog first)")
    end
    eq(row._leftRegion.built[1].opts.disabled(), false, "Breath on: its cog is live")
    eq(row._leftRegion.built[2].list[1].disabled(), false, "Breath on: its swatch is live")
    eq(row._rightRegion.built[1].opts.disabled(), true, "Fatigue's cog stays greyed")
    eq(jump.opts.disabled(), false, "a bar on: the unlock jump is live")

    -- the fill colour
    rec.Forget()
    local sw = row._leftRegion.built[2].list[1]
    local r, g, b, a = sw.getValue()
    check(r == 0.2 and g == 0.4 and b == 0.6 and a == 1, "the swatch reads the bar's fill colour")
    sw.setValue(0.9, 0.8, 0.7, 0.5)
    local c = w.profile.mirrorTimer.breath
    check(c.fillR == 0.9 and c.fillG == 0.8 and c.fillB == 0.7 and c.fillA == 0.5, "a colour pick is saved")
    eq(rec.Calls("MT_Apply"), 1, "a colour pick runs the timer bars' apply")
    eq(rec.Calls("_ERB_Apply"), 0, "a colour pick runs no Resource Bars apply")
    eq(rec.Calls("NotifyElementResized:ERB_MirrorBars"), 0, "a colour pick reports no resize")
    eq(rec.Calls("RefreshPage"), 0, "a colour pick refreshes no page")
    eq(w.Parts("breath").bar._color[1], 0.9, "and the bar takes the colour")

    -- the cog: Low Warning and Warn When Left
    rec.Forget()
    local rows = row._leftRegion.built[1].opts.rows
    eq(#rows, 2, "two rows in the cog")
    eq(rows[1].label, "Low Warning", "the first row")
    eq(rows[2].label, "Warn When Left", "the second row")
    eq(rows[1].get(), false, "Low Warning reads off")
    eq(rows[2].disabled(), true, "Warn When Left is greyed while Low Warning is off")
    rows[1].set(true)
    eq(c.lowWarn, true, "Low Warning is saved")
    eq(rows[2].disabled(), false, "Warn When Left comes alive")
    eq(rows[2].get(), 30, "Warn When Left reads 30")
    rows[2].set(45)
    eq(c.lowWarnAt, 45, "Warn When Left is saved")
    eq(rec.Calls("MT_Apply"), 2, "both run the timer bars' apply")
    eq(rec.Calls("_ERB_Apply"), 0, "neither runs the Resource Bars apply")
    eq(rec.Calls("NotifyElementResized:ERB_MirrorBars"), 0, "neither reports a resize")

    -- the search pre-build: the rows, and no cog, swatch or jump
    rec = Page({ prebuild = true })
    eq(#rec.sections[1].rows, 3, "the search pre-build builds the rows")
    for _, r2 in ipairs(rec.sections[1].rows) do
        eq(#r2._leftRegion.built + #r2._rightRegion.built, 0, "the search pre-build builds no cog or swatch")
    end
end

-------------------------------------------------------------------------------
-- 13. Source pins
-------------------------------------------------------------------------------
check(not RUNTIME:find("issecretvalue", 1, true), "the runtime file keeps no secret test of its own")
check(RUNTIME:find("local IsSecret = EllesmereUI.IsSecret", 1, true), "it imports the parent's")
check(not RUNTIME:find("or {})", 1, true), "no list is made just to be walked")
check(not PAGE:find("_ERB_Apply", 1, true), "the options section never runs the whole Resource Bars apply")
check(not RUNTIME:find("OnUpdate", 1, true), "no per-frame script")
check(not RUNTIME:find("NewTicker", 1, true), "no ticker")

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_rb_mirror_timers (%d checks)"):format(count))
