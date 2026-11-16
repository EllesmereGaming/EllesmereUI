-- Stub harness: Unit Frames, a boss frame follows a slot takeover (EUI_UnitFrames_Engine.lua).
-- An add that turns targetable can take a boss slot with no engage event, and where the game
-- hides unit identity the trackers' GUID probe cannot see the new occupant: the boss frame kept
-- the old name. The engine listens to UNIT_TARGETABLE_CHANGED for it:
--   * only once a boss frame is attached, and not on WoW Forever;
--   * whatever unit token reports the flip (the slot, a nameplate, the target), the boss frames
--     on screen take ONE identity repaint on the next frame, however many events came;
--   * with no boss frame on screen nothing is asked for, and no other unit frame is ever touched.
-- The real engine file is loaded whole over stubbed frames, timers and unit data.
--   lua .tools/tests/test_uf_boss_slot_takeover.lua        (from the repository root)
local ROOT = arg and arg[1] or "."
local ENGINE_PATH = ROOT .. "/EllesmereUIUnitFrames/EUI_UnitFrames_Engine.lua"

local function ReadSource(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local SRC = ReadSource(ENGINE_PATH)
-- The widget methods the engine calls: a mock answers those with a no-op.
local METHODS = {}
for name in SRC:gmatch(":([%a_][%w_]*)%s*%(") do METHODS[name] = true end

-- One client session: the engine loaded fresh. forever: a WoW Forever client.
local function Session(forever)
    local S = { frames = {}, timers = {}, paints = {}, now = 0 }
    local function MakeObj(kind, name)
        local o = { _kind = kind, _name = name, _shown = true, _scripts = {}, _hooks = {}, _events = {}, _attr = {} }
        setmetatable(o, { __index = function(_, k)
            if type(k) ~= "string" or k:sub(1, 1) == "_" then return nil end
            if k == "Show" then return function(self) self._shown = true end end
            if k == "Hide" then return function(self) self._shown = false end end
            if k == "IsShown" then return function(self) return self._shown end end
            if k == "SetScript" then return function(self, s, fn) self._scripts[s] = fn end end
            if k == "GetScript" then return function(self, s) return self._scripts[s] end end
            if k == "HookScript" then
                return function(self, s, fn)
                    local list = self._hooks[s]
                    if not list then list = {}; self._hooks[s] = list end
                    list[#list + 1] = fn
                end
            end
            if k == "RegisterEvent" or k == "RegisterUnitEvent" then
                return function(self, ev) self._events[ev] = true end
            end
            if k == "UnregisterEvent" then return function(self, ev) self._events[ev] = nil end end
            if k == "SetAttribute" then return function(self, a, v) self._attr[a] = v end end
            if k == "GetAttribute" then return function(self, a) return self._attr[a] end end
            if k == "CreateTexture" then return function() return MakeObj("Texture") end end
            if k == "GetFrameLevel" then return function() return 1 end end
            if METHODS[k] then return function() end end
            return nil
        end })
        if kind ~= "Texture" then S.frames[#S.frames + 1] = o end
        return o
    end
    EUI_CLIENT_BLOCKED = nil
    issecretvalue = function() return false end
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    CreateFrame = function(kind, name) return MakeObj(kind, name) end
    UIParent = MakeObj("Frame", "UIParent")
    RegisterStateDriver = function() end
    RegisterUnitWatch = function() end
    SecureButton_GetUnit = function(f) return f._attr.unit end
    SecureButton_GetModifiedUnit = function(f) return f._attr.unit end
    GetTime = function() return S.now end
    UnitExists = function() return true end
    UnitGUID = function() return nil end           -- identity hidden: the GUID probe is blind
    GetRaidTargetIndex = function() return nil end
    SetRaidTargetIconTexture = function() end
    C_Timer = { After = function(_, fn) S.timers[#S.timers + 1] = fn end }
    Enum = { StatusBarInterpolation = { Immediate = 0 } }
    EllesmereUI = { IS_FOREVER = forever or nil, AttachSecureUnitMenu = function() end, SetLeftClickTarget = function() end }

    local ns = {}
    assert(loadstring(SRC, "=EUI_UnitFrames_Engine.lua"))("EllesmereUIUnitFrames", ns)
    local Engine = assert(ns.Engine, "the engine did not load")
    -- every paint: which frame, for what reason
    Engine.SetPainter("health", function(frame, _, event)
        S.paints[#S.paints + 1] = { frame = frame, event = event }
    end)
    for _, f in ipairs(S.frames) do
        if f._events.PLAYER_TARGET_CHANGED and f._events.INSTANCE_ENCOUNTER_ENGAGE_UNIT then S.global = f end
    end
    assert(S.global and S.global._scripts.OnEvent, "the engine's global trigger frame was not found")
    function S.Attach(unit)
        local frame = MakeObj("Button", "Test_" .. unit)
        frame._euiUnit = unit
        Engine.Attach(frame, unit, { "health" })
        return frame
    end
    -- An event as the client delivers it: only to a frame registered for it.
    function S.Fire(event, ...)
        if not S.global._events[event] then return false end
        S.global._scripts.OnEvent(S.global, event, ...)
        return true
    end
    -- The next frame: the clock moves and the timers asked for run.
    function S.NextFrame()
        S.now = S.now + 0.016
        local run = S.timers
        S.timers = {}
        for i = 1, #run do run[i]() end
        return #run
    end
    function S.Count(frame, event)
        local n = 0
        for _, p in ipairs(S.paints) do
            if (frame == nil or p.frame == frame) and (event == nil or p.event == event) then n = n + 1 end
        end
        return n
    end
    function S.Reset() S.paints = {} end
    S.Engine = Engine
    return S
end

-------------------------------------------------------------------------------
-- 1. the event is listened to only once a boss frame exists, and not on Forever
-------------------------------------------------------------------------------
do
    local S = Session(false)
    check(S.global._events.UNIT_TARGETABLE_CHANGED == nil, "the takeover event is registered with no boss frame attached")
    S.Attach("player")
    S.Attach("target")
    check(S.global._events.UNIT_TARGETABLE_CHANGED == nil, "attaching the player and target frames registers the takeover event")
    S.Attach("boss1")
    check(S.global._events.UNIT_TARGETABLE_CHANGED == true, "attaching a boss frame does not register the takeover event")
    check(S.global._events.INSTANCE_ENCOUNTER_ENGAGE_UNIT == true, "the engage event is no longer registered")

    local F = Session(true)
    F.Attach("boss1")
    check(F.global._events.UNIT_TARGETABLE_CHANGED == nil, "WoW Forever registers the takeover event")
    check(F.global._events.INSTANCE_ENCOUNTER_ENGAGE_UNIT == true, "WoW Forever lost the engage event")
end

-------------------------------------------------------------------------------
-- 2. a flip under any token: one next-frame repaint of the boss frames on screen
-------------------------------------------------------------------------------
do
    local S = Session(false)
    local player, target = S.Attach("player"), S.Attach("target")
    local b1, b2, b3 = S.Attach("boss1"), S.Attach("boss2"), S.Attach("boss3")
    b3:Hide()                                   -- no third boss in this fight
    S.Reset()

    -- the add's flip, reported under its boss slot, its nameplate and as your target; and an
    -- unrelated mob going untargetable in the same frame
    for _, token in ipairs({ "boss2", "nameplate7", "target", "nameplate12", "nameplate12", "boss2" }) do
        check(S.Fire("UNIT_TARGETABLE_CHANGED", token), "the takeover event is not delivered")
    end
    check(S.Count() == 0, "a flip repaints at once (" .. S.Count() .. " paints before the next frame)")
    check(#S.timers == 1, "six flips in one frame asked for " .. #S.timers .. " passes")
    S.NextFrame()
    check(S.Count(b1, "UnitChanged") == 1 and S.Count(b2, "UnitChanged") == 1, "the boss frames on screen did not take one identity repaint each ("
        .. S.Count(b1) .. ", " .. S.Count(b2) .. ")")
    check(S.Count(b3) == 0, "a hidden boss frame was repainted")
    check(S.Count(player) == 0 and S.Count(target) == 0, "a flip repainted the player or target frame (" .. S.Count(player) .. ", " .. S.Count(target) .. ")")
    check(S.Count() == 2, "the pass made " .. S.Count() .. " paints, not the 2 boss frames on screen")
    check(S.NextFrame() == 0, "the pass asked for another pass")

    -- each token alone is enough (whichever one the client uses for the add)
    for _, token in ipairs({ "boss2", "nameplate7", "target", "focus" }) do
        S.Reset()
        S.Fire("UNIT_TARGETABLE_CHANGED", token)
        S.NextFrame()
        check(S.Count(b2, "UnitChanged") == 1 and S.Count() == 2, "a flip reported as " .. token .. " did not repaint the boss frames once (" .. S.Count() .. " paints)")
    end

    -- no boss frame on screen: nothing is asked for
    b1:Hide()
    b2:Hide()
    S.Reset()
    S.Fire("UNIT_TARGETABLE_CHANGED", "nameplate3")
    S.Fire("UNIT_TARGETABLE_CHANGED", "boss1")
    check(#S.timers == 0 and S.Count() == 0, "with no boss frame on screen a flip still asks for a pass")
    -- a boss frame that hides between the event and the pass is left alone
    b1:Show()
    S.Reset()
    S.Fire("UNIT_TARGETABLE_CHANGED", "boss1")
    b1:Hide()
    S.NextFrame()
    check(S.Count() == 0, "a boss frame hidden before the pass was repainted")
end

-------------------------------------------------------------------------------
-- 3. the engage event, and both in one frame
-------------------------------------------------------------------------------
do
    local S = Session(false)
    local player = S.Attach("player")
    local b1, b2 = S.Attach("boss1"), S.Attach("boss2")
    S.Reset()
    S.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    check(S.Count(b1, "INSTANCE_ENCOUNTER_ENGAGE_UNIT") == 1 and S.Count(b2, "INSTANCE_ENCOUNTER_ENGAGE_UNIT") == 1, "the engage event does not repaint the boss frames at once")
    check(#S.timers == 1, "the engage event asked for " .. #S.timers .. " settle passes")
    -- a flip and a second engage in the same frame ride the pass already asked for
    S.Fire("UNIT_TARGETABLE_CHANGED", "boss2")
    S.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    check(#S.timers == 1, "an engage and a flip in one frame asked for " .. #S.timers .. " passes")
    S.NextFrame()
    check(S.Count(b1, "UnitChanged") == 1 and S.Count(b2, "UnitChanged") == 1, "the settle pass did not repaint each boss frame once")
    check(S.Count(player) == 0, "the engage event repainted the player frame")
    -- the next burst gets a pass of its own
    S.Reset()
    S.Fire("UNIT_TARGETABLE_CHANGED", "nameplate2")
    check(#S.timers == 1, "a flip after a finished pass asked for " .. #S.timers .. " passes")
    S.NextFrame()
    check(S.Count() == 2, "the second pass made " .. S.Count() .. " paints")

    -- a loading screen still repaints every frame on screen
    S.Reset()
    S.Fire("PLAYER_ENTERING_WORLD")
    check(S.Count(player, "PLAYER_ENTERING_WORLD") == 1 and S.Count(b1, "PLAYER_ENTERING_WORLD") == 1, "a loading screen no longer repaints every frame")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_uf_boss_slot_takeover (%d checks)"):format(count))
