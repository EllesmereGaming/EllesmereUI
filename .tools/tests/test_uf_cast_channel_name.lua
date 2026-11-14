-- Stub harness: Unit Frames, the spell name on a channeled cast (EUI_UnitFrames_Engine.lua).
-- WoW Forever reports the generic "Channeling" as a channel's display text (the second return
-- of UnitChannelInfo); the spell's name is the first return. The cast bar shows the name there:
--   * on WoW Forever a channel shows its spell name, on its start event and on every full
--     re-derive of the cast (a show, a forced update, a target swap, a new occupant);
--   * the quest-object cast's " - No Text" tail is still cut from that name;
--   * a normal cast and an empowered cast keep their display text, also right after a channel;
--   * on every other client a channel keeps its display text;
--   * a name or text the game keeps secret is handed on untouched.
-- The real engine file is loaded whole, with its own cast bar painter, over stubbed frames and
-- cast data; the cast name cleaner is cut from the parent's shared helpers.
--   lua .tools/tests/test_uf_cast_channel_name.lua        (from the repository root)
local ROOT = arg and arg[1] or "."
local ENGINE_PATH = ROOT .. "/EllesmereUIUnitFrames/EUI_UnitFrames_Engine.lua"
local HELPERS_PATH = ROOT .. "/EllesmereUI_SharedHelpers.lua"

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
-- A value for a message: a secret one is never turned into text.
local function show(v)
    if type(v) == "string" then return "'" .. v .. "'" end
    return type(v)
end

local SRC = ReadSource(ENGINE_PATH)
local CLEAN = ReadSource(HELPERS_PATH):match("\n(function EllesmereUI%.CleanCastName%(name%)\n.-\nend)\n")
assert(CLEAN, "the cast name cleaner was not found in the shared helpers")
-- The widget methods the engine calls: a mock answers those with a no-op.
local METHODS = {}
for name in SRC:gmatch(":([%a_][%w_]*)%s*%(") do METHODS[name] = true end

local ELAPSED, REMAINING = 0, 1

-- One client session: the engine loaded fresh. forever: what EllesmereUI.IS_FOREVER reads.
-- secret: the one value this session's client keeps secret.
local function Session(forever, secret)
    local S = { frames = {}, cast = {}, channel = {} }
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
    issecretvalue = function(v) return secret ~= nil and rawequal(v, secret) end
    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    CreateFrame = function(kind, name) return MakeObj(kind, name) end
    UIParent = MakeObj("Frame", "UIParent")
    RegisterStateDriver = function() end
    RegisterUnitWatch = function() end
    SecureButton_GetUnit = function(f) return f._attr.unit end
    SecureButton_GetModifiedUnit = function(f) return f._attr.unit end
    GetTime = function() return 0 end
    UnitExists = function() return true end
    UnitGUID = function() return nil end
    GetRaidTargetIndex = function() return nil end
    SetRaidTargetIconTexture = function() end
    C_Timer = { After = function() end }
    Enum = {
        StatusBarInterpolation = { Immediate = 0 },
        StatusBarTimerDirection = { ElapsedTime = ELAPSED, RemainingTime = REMAINING },
    }
    -- The client's cast data, in the order the game returns it.
    UnitCastingInfo = function(unit)
        local c = S.cast[unit]
        if not c then return nil end
        return c.name, c.text, c.texture, c.start, c.finish, c.tradeSkill, "cast-guid", c.notInterruptible, c.spellID, c.castID
    end
    UnitChannelInfo = function(unit)
        local c = S.channel[unit]
        if not c then return nil end
        return c.name, c.text, c.texture, c.start, c.finish, c.tradeSkill, c.notInterruptible, c.spellID, c.empowered, 3, c.castID
    end
    UnitCastingDuration = function(unit) return "cast:" .. unit end
    UnitChannelDuration = function(unit) return "channel:" .. unit end
    UnitEmpoweredChannelDuration = function(unit) return "empower:" .. unit end
    GetUnitEmpowerHoldAtMaxTime = function() return 1000 end
    UnitEmpoweredStagePercentages = function() return {} end
    GetNetStats = function() return 0, 0, 0, 0 end
    EllesmereUI = {
        IS_FOREVER = forever,
        AttachSecureUnitMenu = function() end,
        SetLeftClickTarget = function() end,
        SetCraftBatch = function() end,
    }
    -- To the cleaner a secret reads as a string, as the game's secret strings do, and any
    -- string operation on it raises.
    local cleaner = assert(loadstring(CLEAN, "=CleanCastName"))
    setfenv(cleaner, setmetatable({
        type = function(v)
            if secret ~= nil and rawequal(v, secret) then return "string" end
            return type(v)
        end,
    }, { __index = _G }))
    cleaner()

    local ns = {}
    assert(loadstring(SRC, "=EUI_UnitFrames_Engine.lua"))("EllesmereUIUnitFrames", ns)
    local Engine = assert(ns.Engine, "the engine did not load")

    -- A unit frame with a cast bar, attached for the cast bar channel alone.
    function S.Attach(unit)
        local frame = MakeObj("Button", "Test_" .. unit)
        frame._euiUnit = unit
        local bar = MakeObj("StatusBar")
        bar._shown = false
        bar.Text = { SetText = function(self, t) self.text = t end }
        bar.Time = { SetText = function() end, SetFormattedText = function() end }
        bar.SetTimerDuration = function(self, duration, _, direction)
            self._duration, self._direction = duration, direction
        end
        frame.Castbar = bar
        Engine.Attach(frame, unit, { "castbar" })
        return frame, bar
    end
    -- A unit event as the client delivers it: to the frame's tracker, only while registered.
    function S.Fire(frame, event, ...)
        local tracker
        for _, f in ipairs(S.frames) do
            if f._euiFrame == frame then tracker = f end
        end
        assert(tracker, "the frame has no tracker")
        if not tracker._events[event] then return false end
        tracker._scripts.OnEvent(tracker, event, ...)
        return true
    end
    S.Engine = Engine
    return S
end

-- One cast or channel as the client reports it.
local function Info(name, text, castID, more)
    local c = { name = name, text = text, texture = 135857, start = 1000, finish = 9000, spellID = 42, castID = castID or "c1" }
    if more then for k, v in pairs(more) do c[k] = v end end
    return c
end

-------------------------------------------------------------------------------
-- 1. WoW Forever: a channel shows its spell name
-------------------------------------------------------------------------------
do
    local S = Session(true)
    local frame, bar = S.Attach("target")
    S.channel.target = Info("Blizzard", "Channeling")
    check(S.Fire(frame, "UNIT_SPELLCAST_CHANNEL_START", "target", "guid", 42, "c1"), "the channel start event is not delivered")
    check(bar:IsShown(), "a channel does not show the cast bar")
    check(bar.channeling == true and bar.casting == nil and bar.empowering == nil, "a channel is not filed as a channel")
    check(bar.Text.text == "Blizzard", "WoW Forever: a channel shows " .. show(bar.Text.text) .. ", not its spell name")
    check(bar.spellName == "Blizzard", "WoW Forever: a channel's kept spell name is " .. show(bar.spellName))
    check(bar._direction == REMAINING and bar._duration == "channel:target", "a channel's bar does not run down the channel's own time")
    check(bar.castID == "c1" and bar.spellID == 42, "a channel lost its cast and spell identifiers")

    -- an update of the same channel leaves the name alone
    check(S.Fire(frame, "UNIT_SPELLCAST_CHANNEL_UPDATE", "target", "guid", 42, "c1"), "the channel update event is not delivered")
    check(bar.Text.text == "Blizzard", "a channel update changed the text to " .. show(bar.Text.text))

    -- every full re-derive of the cast writes the name again
    for _, why in ipairs({ "Show", "ForceUpdate", "PLAYER_TARGET_CHANGED", "UnitChanged" }) do
        bar.Text.text = nil
        S.Engine.RepaintAll(frame, why)
        check(bar.Text.text == "Blizzard", "WoW Forever: a full repaint (" .. why .. ") shows " .. show(bar.Text.text) .. " on a channel")
    end

    -- a target swap onto another channeling unit
    S.channel.target = Info("Mind Flay", "Channeling", "c2")
    S.Engine.RepaintAll(frame, "PLAYER_TARGET_CHANGED")
    check(bar.Text.text == "Mind Flay" and bar.spellName == "Mind Flay" and bar.castID == "c2",
        "WoW Forever: the new target's channel shows " .. show(bar.Text.text))

    -- whatever the client's language calls the generic text
    S.channel.target = Info("Blizzard", "Kanalisieren", "c5")
    S.Fire(frame, "UNIT_SPELLCAST_CHANNEL_START", "target", "guid", 42, "c5")
    check(bar.Text.text == "Blizzard", "WoW Forever: a channel under another client language shows " .. show(bar.Text.text))

    -- the quest-object cast: its tail is cut from the name too
    S.channel.target = Info("Opening - No Text", "Channeling", "c3")
    S.Fire(frame, "UNIT_SPELLCAST_CHANNEL_START", "target", "guid", 42, "c3")
    check(bar.Text.text == "Opening", "WoW Forever: the quest-object channel shows " .. show(bar.Text.text))
    check(bar.spellName == "Opening", "WoW Forever: the quest-object channel keeps the name " .. show(bar.spellName))

    -- the channel is over: the bar clears
    S.channel.target = nil
    S.Engine.RepaintAll(frame, "Show")
    check(not bar:IsShown() and bar.spellName == nil and bar.channeling == nil, "with no cast the bar stays up")

    -- the player's own channel (the one frame whose cast clock is read)
    local pframe, pbar = S.Attach("player")
    S.channel.player = Info("Arcane Missiles", "Channeling", "p1")
    S.Fire(pframe, "UNIT_SPELLCAST_CHANNEL_START", "player", "guid", 42, "p1")
    check(pbar.Text.text == "Arcane Missiles", "WoW Forever: your own channel shows " .. show(pbar.Text.text))
    check(pbar.startTime == 1 and pbar.endTime == 9, "your own channel lost its clock")
    check(bar.Text.text == "Opening", "your channel wrote onto the target's bar")
end

-------------------------------------------------------------------------------
-- 2. WoW Forever: a cast and an empowered cast keep their display text
-------------------------------------------------------------------------------
do
    local S = Session(true)
    local frame, bar = S.Attach("target")
    S.cast.target = Info("Frostbolt", "Frostbolt (Rank 3)")
    check(S.Fire(frame, "UNIT_SPELLCAST_START", "target", "guid", 42, "c1"), "the cast start event is not delivered")
    check(bar.casting == true and bar.channeling == nil, "a cast is not filed as a cast")
    check(bar.Text.text == "Frostbolt (Rank 3)", "WoW Forever: a cast shows " .. show(bar.Text.text) .. ", not its display text")
    check(bar.spellName == "Frostbolt (Rank 3)", "WoW Forever: a cast's kept spell name is " .. show(bar.spellName))
    check(bar._direction == ELAPSED and bar._duration == "cast:target", "a cast's bar does not fill with the cast's own time")

    -- a channel, then a cast with no stop event between them
    S.cast.target = nil
    S.channel.target = Info("Blizzard", "Channeling", "c2")
    S.Fire(frame, "UNIT_SPELLCAST_CHANNEL_START", "target", "guid", 42, "c2")
    check(bar.Text.text == "Blizzard", "WoW Forever: the channel before the cast shows " .. show(bar.Text.text))
    S.channel.target = nil
    S.cast.target = Info("Fireball", "Fireball (Rank 7)", "c3")
    S.Fire(frame, "UNIT_SPELLCAST_START", "target", "guid", 43, "c3")
    check(bar.channeling == nil and bar.casting == true, "a cast right after a channel is still filed as a channel")
    check(bar.Text.text == "Fireball (Rank 7)", "WoW Forever: a cast right after a channel shows " .. show(bar.Text.text))
    -- and on a full re-derive
    bar.Text.text = nil
    S.Engine.RepaintAll(frame, "Show")
    check(bar.Text.text == "Fireball (Rank 7)", "WoW Forever: a full repaint shows " .. show(bar.Text.text) .. " on a cast")

    -- an empowered cast is not a plain channel
    S.cast.target = nil
    S.channel.target = Info("Fire Breath", "Fire Breath (display)", "c4", { empowered = true })
    check(S.Fire(frame, "UNIT_SPELLCAST_EMPOWER_START", "target", "guid", 44, "c4"), "the empower start event is not delivered")
    check(bar.empowering == true and bar.channeling == nil and bar.casting == nil, "an empowered cast is not filed as one")
    check(bar.Text.text == "Fire Breath (display)", "WoW Forever: an empowered cast shows " .. show(bar.Text.text))
    check(bar._direction == ELAPSED and bar._duration == "empower:target", "an empowered cast's bar does not fill with its own time")
end

-------------------------------------------------------------------------------
-- 3. every other client: a channel keeps its display text
-------------------------------------------------------------------------------
for _, flag in ipairs({ "unset", "false" }) do
    local S
    if flag == "false" then S = Session(false) else S = Session(nil) end
    local frame, bar = S.Attach("target")
    S.channel.target = Info("Blizzard", "Blizzard (display)")
    S.Fire(frame, "UNIT_SPELLCAST_CHANNEL_START", "target", "guid", 42, "c1")
    check(bar.channeling == true, "another client (" .. flag .. "): a channel is not filed as a channel")
    check(bar.Text.text == "Blizzard (display)", "another client (" .. flag .. "): a channel shows " .. show(bar.Text.text) .. ", not its display text")
    check(bar.spellName == "Blizzard (display)", "another client (" .. flag .. "): a channel's kept spell name is " .. show(bar.spellName))
    -- whatever the display text reads, it is the client's to choose there
    S.channel.target = Info("Penance", "Channeling", "c2")
    S.Engine.RepaintAll(frame, "Show")
    check(bar.Text.text == "Channeling", "another client (" .. flag .. "): a channel's display text was replaced by " .. show(bar.Text.text))
    S.channel.target = Info("Opening", "Opening - No Text", "c3")
    S.Engine.RepaintAll(frame, "Show")
    check(bar.Text.text == "Opening", "another client (" .. flag .. "): the quest-object channel shows " .. show(bar.Text.text))
    -- a cast
    S.channel.target = nil
    S.cast.target = Info("Smite", "Smite (display)", "c4")
    S.Fire(frame, "UNIT_SPELLCAST_START", "target", "guid", 42, "c4")
    check(bar.Text.text == "Smite (display)", "another client (" .. flag .. "): a cast shows " .. show(bar.Text.text))
end

-------------------------------------------------------------------------------
-- 4. secret values pass through untouched
-------------------------------------------------------------------------------
do
    -- Any read of it as text or in arithmetic raises, as the game's secret values do.
    local SECRET = setmetatable({}, { __tostring = function() error("a secret value was read") end })
    local S = Session(true, SECRET)
    local frame, bar = S.Attach("target")
    S.channel.target = Info(SECRET, "Channeling")
    local ok, err = pcall(S.Fire, frame, "UNIT_SPELLCAST_CHANNEL_START", "target", "guid", 42, "c1")
    check(ok, "WoW Forever: a channel with a secret name raised: " .. tostring(err))
    check(rawequal(bar.Text.text, SECRET), "WoW Forever: a channel's secret name is not handed to the text as it is (" .. show(bar.Text.text) .. ")")
    check(rawequal(bar.spellName, SECRET), "WoW Forever: a channel's secret name is not kept as it is")
    check(bar:IsShown(), "a channel with a secret name does not show the bar")

    S.channel.target = nil
    S.cast.target = Info("Frostbolt", SECRET, "c2")
    ok, err = pcall(S.Fire, frame, "UNIT_SPELLCAST_START", "target", "guid", 42, "c2")
    check(ok, "WoW Forever: a cast with a secret display text raised: " .. tostring(err))
    check(rawequal(bar.Text.text, SECRET), "WoW Forever: a cast's secret display text is not handed on as it is (" .. show(bar.Text.text) .. ")")

    local R = Session(nil, SECRET)
    local rframe, rbar = R.Attach("target")
    R.channel.target = Info("Blizzard", SECRET)
    ok, err = pcall(R.Fire, rframe, "UNIT_SPELLCAST_CHANNEL_START", "target", "guid", 42, "c1")
    check(ok, "another client: a channel with a secret display text raised: " .. tostring(err))
    check(rawequal(rbar.Text.text, SECRET), "another client: a channel's secret display text is not handed on as it is (" .. show(rbar.Text.text) .. ")")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_uf_cast_channel_name (%d checks)"):format(count))
