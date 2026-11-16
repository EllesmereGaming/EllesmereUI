-- Stub harness: Chat, the idle fade's Also Wake On (idleFadeWake). Player chat
-- in a shown window always wakes a faded chat; each ticked group adds its
-- kinds of lines: by event name, and for the lines the game adds with no event
-- name (skill, XP, reputation, honor, loot, money, system, achievements) by
-- the line's chat type id.
-- Cuts the two tables out of EUI_Chat_EditBox.lua and the wake code out of
-- EUI_Chat_Init.lua by their first and last lines (a moved line fails here by
-- name) and checks: with nothing ticked the answer is the one the chat gave
-- before the option existed, for every input; a line that does not wake costs
-- no frame call; each group wakes on its own lines and on nobody else's;
-- secret and odd values raise nothing; a hidden window never wakes.
--   lua .tools/tests/test_chat_idle_wake_on.lua      (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end
local function Cut(src, first, last, what, keepLast)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b, c = src:find(last, a + #first, true)
    assert(b, what .. ": last line not found")
    return src:sub(a, keepLast and c or b - 1)
end

local EDITBOX = ReadSource("EllesmereUIChat/EUI_Chat_EditBox.lua")
local INIT = ReadSource("EllesmereUIChat/EUI_Chat_Init.lua")
local ENGINE = ReadSource("EllesmereUIChat/EllesmereUIChat_Engine.lua")
local OPTIONS = ReadSource("EllesmereUIOptions/EUI_Chat_Options.lua")

local CHAT_MSG_EVENTS, GROUPS = assert(loadstring(
    Cut(EDITBOX, "local CHAT_MSG_EVENTS = {", "\n}\n", "the player chat events", true) .. "\n"
    .. Cut(EDITBOX, "local IDLE_WAKE_GROUPS = {", "\n}\n", "the wake groups", true)
    .. "\nreturn CHAT_MSG_EVENTS, IDLE_WAKE_GROUPS", "=editbox-cut"))()
local WAKE = assert(loadstring(
    "local CHAT_MSG_EVENTS, I, ECHAT, wakeFrame, ChatTypeInfo, issecretvalue = ...\n"
    .. Cut(INIT, "        local _wakeEvents, _wakeTypeIDs = CHAT_MSG_EVENTS, nil", "        SetMessageWake = function(on)", "the wake code")
    .. "\nreturn WakeOnChat", "=init-cut"))

local n = 0
local function check(cond, msg)
    n = n + 1
    assert(cond, msg)
end

-- The chat types the groups name, and a few no group has; each with an id of
-- its own (the game's ids are numbers handed out by the client).
local TYPES = { "SAY", "GUILD", "WHISPER", "TRADESKILLS", "OPENING", "PET_INFO", "COMBAT_MISC_INFO", "BG_SYSTEM_NEUTRAL" }
for _, g in ipairs(GROUPS) do for _, t in ipairs(g.types) do TYPES[#TYPES + 1] = t end end
local ChatTypeInfo = {}
for i, t in ipairs(TYPES) do
    check(ChatTypeInfo[t] == nil, "a chat type is in two groups: " .. t)
    ChatTypeInfo[t] = { id = i }
end
check(#GROUPS == 7, "the groups: " .. #GROUPS)

local SECRET = {}
local secretAsked = 0
local function issecretvalue(v) secretAsked = secretAsked + 1; return rawequal(v, SECRET) end
local function WakeFrame()
    local wf = { shown = false, asked = 0, shows = 0 }
    function wf:IsShown() self.asked = self.asked + 1; return self.shown end
    function wf:Show() self.shown = true; self.shows = self.shows + 1 end
    return wf
end
local windowAsked = 0
local SHOWN = { IsShown = function() windowAsked = windowAsked + 1; return true end }
local HIDDEN = { IsShown = function() windowAsked = windowAsked + 1; return false end }

-- the module's code over one settings table
local function Make(cfg)
    local wf = WakeFrame()
    local ECHAT = { DB = function() return cfg end }
    local wake = WAKE(CHAT_MSG_EVENTS, { IDLE_WAKE_GROUPS = GROUPS }, ECHAT, wf, ChatTypeInfo, issecretvalue)
    check(type(ECHAT.ApplyIdleFadeWake) == "function", "the apply function is gone")
    ECHAT.ApplyIdleFadeWake()
    return wake, ECHAT.ApplyIdleFadeWake, wf
end
-- what the chat did before the option existed
local function Before(wf, cf, event)
    if event == nil or wf:IsShown() then return end
    if issecretvalue(event) then return end
    if CHAT_MSG_EVENTS[event] and cf:IsShown() then wf:Show() end
end

local PLAYER_EVENTS = {}
for e in pairs(CHAT_MSG_EVENTS) do PLAYER_EVENTS[e] = true end
local function EventsUntouched()
    for e in pairs(CHAT_MSG_EVENTS) do if not PLAYER_EVENTS[e] then return false end end
    for e in pairs(PLAYER_EVENTS) do if not CHAT_MSG_EVENTS[e] then return false end end
    return true
end

-- The lines the game adds WITH their event name; every other group type
-- arrives with no event name and is known by its chat type id alone.
local WITH_EVENT = { EMOTE = true, TEXT_EMOTE = true, MONSTER_SAY = true, MONSTER_YELL = true, MONSTER_EMOTE = true,
    MONSTER_WHISPER = true, MONSTER_PARTY = true, RAID_BOSS_EMOTE = true, RAID_BOSS_WHISPER = true }

-------------------------------------------------------------------------------
-- 1. nothing ticked (an empty table, and no table at all): the answer of
--    before, for every event, id, window and wake state
-------------------------------------------------------------------------------
local EVENTS = { false, "CHAT_MSG_SAY", "CHAT_MSG_GUILD", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_LOOT",
    "CHAT_MSG_SYSTEM", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_WHISPER", SECRET }
local IDS = { false, ChatTypeInfo.SAY.id, ChatTypeInfo.LOOT.id, ChatTypeInfo.SYSTEM.id, ChatTypeInfo.EMOTE.id,
    ChatTypeInfo.SKILL.id, SECRET, 9999, "odd", 0 / 0 }
local combos = 0
for _, cfg in ipairs({ { idleFadeWake = {} }, {} }) do
    for _, ev in ipairs(EVENTS) do
        for _, id in ipairs(IDS) do
            for _, pre in ipairs({ false, true }) do
                for _, cf in ipairs({ SHOWN, HIDDEN }) do
                    local event, typeID = ev or nil, id or nil
                    local was = WakeFrame(); was.shown = pre
                    Before(was, cf, event)
                    local wake, _, wf = Make(cfg)
                    wf.shown = pre
                    local ok, err = pcall(wake, cf, event, typeID)
                    combos = combos + 1
                    check(ok, "nothing ticked: raised " .. tostring(err))
                    check(wf.shows == was.shows, ("nothing ticked: event %s, id %s, already waking %s, window shown %s: woke %d times, before %d")
                        :format(tostring(event), tostring(typeID), tostring(pre), tostring(cf == SHOWN), wf.shows, was.shows))
                end
            end
        end
    end
end
check(combos == 800, "combinations: " .. combos)

-------------------------------------------------------------------------------
-- 2. a line that does not wake costs no frame call: with nothing ticked a line
--    with no event name makes none at all, and an event that is not a wake
--    event asks neither frame
-------------------------------------------------------------------------------
do
    local wake, _, wf = Make({ idleFadeWake = {} })
    secretAsked, windowAsked = 0, 0
    wake(SHOWN, nil, ChatTypeInfo.LOOT.id)
    wake(SHOWN, nil, nil)
    check(wf.asked == 0 and windowAsked == 0 and secretAsked == 0, "nothing ticked: a line with no event name made a call")
    wake(SHOWN, "CHAT_MSG_LOOT", ChatTypeInfo.LOOT.id)
    wake(SHOWN, "CHAT_MSG_MONSTER_SAY", ChatTypeInfo.MONSTER_SAY.id)
    check(wf.asked == 0 and windowAsked == 0, "nothing ticked: an event that does not wake asked a frame")
    -- a waking line asks once each, and a second one in the same frame stops at the wake frame
    wake(SHOWN, "CHAT_MSG_SAY", ChatTypeInfo.SAY.id)
    check(wf.shows == 1 and wf.asked == 1 and windowAsked == 1, "a waking line: the frames were not asked once each")
    wake(SHOWN, "CHAT_MSG_GUILD", ChatTypeInfo.GUILD.id)
    check(wf.shows == 1 and wf.asked == 2 and windowAsked == 1, "already waking: the window was asked again")
    -- a group ticked: its own lines only pay for the lookup when they miss
    wake, _, wf = Make({ idleFadeWake = { loot = true } })
    windowAsked = 0
    wake(SHOWN, nil, ChatTypeInfo.SYSTEM.id)
    check(wf.asked == 0 and windowAsked == 0, "a group ticked: another group's line asked a frame")
end

-------------------------------------------------------------------------------
-- 3. each group alone: its lines wake, another group's and a plain line do not
-------------------------------------------------------------------------------
for _, g in ipairs(GROUPS) do
    local wake, _, wf = Make({ idleFadeWake = { [g.key] = true } })
    check(EventsUntouched(), g.key .. ": the player chat events were changed")
    local function Wakes(event, id, cf)
        wf.shown, wf.shows = false, 0
        wake(cf or SHOWN, event, id)
        return wf.shows == 1
    end
    local function LineWakes(t, cf)
        if WITH_EVENT[t] then return Wakes("CHAT_MSG_" .. t, ChatTypeInfo[t].id, cf) end
        return Wakes(nil, ChatTypeInfo[t].id, cf)
    end
    for _, t in ipairs(g.types) do
        check(LineWakes(t), g.key .. ": its " .. t .. " line did not wake")
        check(not LineWakes(t, HIDDEN), g.key .. ": a hidden window woke on " .. t)
    end
    check(Wakes("CHAT_MSG_SAY", ChatTypeInfo.SAY.id), g.key .. ": player chat stopped waking")
    for _, other in ipairs(GROUPS) do
        if other ~= g then
            for _, t in ipairs(other.types) do
                check(not LineWakes(t), g.key .. ": also woke on " .. other.key .. "'s " .. t)
            end
        end
    end
    for _, t in ipairs({ "TRADESKILLS", "OPENING", "PET_INFO", "COMBAT_MISC_INFO", "BG_SYSTEM_NEUTRAL" }) do
        check(not Wakes(nil, ChatTypeInfo[t].id), g.key .. ": woke on " .. t)
    end
    -- a secret chat type id, and ids another addon could hand to AddMessage
    wf.shown, wf.shows = false, 0
    secretAsked = 0
    check(pcall(wake, SHOWN, nil, SECRET) and wf.shows == 0, g.key .. ": a secret chat type id raised or woke")
    check(secretAsked == 1, g.key .. ": a chat type id is looked up before it is tested for secrecy")
    secretAsked = 0
    check(pcall(wake, SHOWN, SECRET, 1) and wf.shows == 0, g.key .. ": a secret event raised or woke")
    check(secretAsked == 1, g.key .. ": an event is looked up before it is tested for secrecy")
    for _, odd in ipairs({ 0 / 0, "x", {}, true, -1 }) do
        check(pcall(wake, SHOWN, nil, odd) and wf.shows == 0, g.key .. ": the id " .. tostring(odd) .. " raised or woke")
    end
end

-------------------------------------------------------------------------------
-- 4. all ticked, then all unticked: back to player chat alone; a key of
--    another build is ignored; a chat type the client lacks is skipped
-------------------------------------------------------------------------------
do
    local cfg = { idleFadeWake = {} }
    for _, g in ipairs(GROUPS) do cfg.idleFadeWake[g.key] = true end
    local wake, apply, wf = Make(cfg)
    wake(SHOWN, nil, ChatTypeInfo.LOOT.id)
    check(wf.shows == 1, "all ticked: loot did not wake")
    for k in pairs(cfg.idleFadeWake) do cfg.idleFadeWake[k] = nil end
    apply()
    wf.shown, wf.shows = false, 0
    wake(SHOWN, nil, ChatTypeInfo.LOOT.id)
    wake(SHOWN, "CHAT_MSG_EMOTE", ChatTypeInfo.EMOTE.id)
    check(wf.shows == 0, "all unticked again: still wakes")
    wake(SHOWN, "CHAT_MSG_SAY", ChatTypeInfo.SAY.id)
    check(wf.shows == 1 and EventsUntouched(), "all unticked again: player chat")
    cfg.idleFadeWake = { notAGroup = true }
    apply()
    wf.shown, wf.shows = false, 0
    wake(SHOWN, nil, ChatTypeInfo.LOOT.id)
    check(wf.shows == 0, "a key that is no group woke")
    -- a client without one of the chat types: the others of the group still work
    local lootID = ChatTypeInfo.CURRENCY
    ChatTypeInfo.CURRENCY = nil
    cfg.idleFadeWake = { loot = true }
    check(pcall(apply), "a chat type the client lacks raised")
    wf.shown, wf.shows = false, 0
    wake(SHOWN, nil, ChatTypeInfo.MONEY.id)
    check(wf.shows == 1, "a chat type the client lacks took its group with it")
    ChatTypeInfo.CURRENCY = lootID
end

-------------------------------------------------------------------------------
-- 5. the wiring: the engine hands the chat type id to the observer, the sets
--    follow a profile change, the options tick is seen by Spec Overrides
-------------------------------------------------------------------------------
check(ENGINE:find("EngineIdleObserver(cf, event, chatTypeID)", 1, true) ~= nil, "the engine does not hand the chat type id to the idle observer")
check(select(2, INIT:gsub("ECHAT%.ApplyIdleFadeWake%(%)", "")) >= 2, "the wake sets are not rebuilt at login and on a profile change")
local row = Cut(OPTIONS, '{ type="dropdown", text="Also Wake On",', "EllesmereUI.RegisterWidgetRefresh(wakeRefresh)", "the options row")
-- the row's own getter, run: it reads every group's key (the keys the checklist
-- writes, which is what marks the slot while one is overridden) and writes none
do
    local getter = Cut(row, "getValue=function()\n", 'return "__placeholder"', "the row's getter", true)
    local body = "return " .. getter:sub(#"getValue=" + 1) .. "\nend"
    local read, wrote = {}, false
    local saved = setmetatable({}, { __index = function(_, k) read[k] = true end, __newindex = function() wrote = true end })
    local asked
    local fn = assert(loadstring("local Cfg, ECHAT = ...\n" .. body, "=getter-cut"))(
        function(k) asked = k; return saved end, { IDLE_WAKE_GROUPS = GROUPS })
    check(fn() == "__placeholder" and asked == "idleFadeWake", "the row's getter does not read the wake setting")
    for _, g in ipairs(GROUPS) do check(read[g.key] == true, "the row's getter does not read the key of " .. g.key) end
    check(wrote == false, "the row's getter writes")
    -- no table saved yet: nothing read, nothing raised
    fn = assert(loadstring("local Cfg, ECHAT = ...\n" .. body, "=getter-cut"))(function() return nil end, { IDLE_WAKE_GROUPS = GROUPS })
    check(fn() == "__placeholder", "the row's getter with nothing saved")
end
check(row:find("notifyWrites = true", 1, true) ~= nil, "a tick is not reported to Spec Overrides as it happens")
check(row:find("ECHAT.ApplyIdleFadeWake()", 1, true) ~= nil, "a tick does not rebuild the wake sets")
check(row:find('t[key] = v and true or nil', 1, true) ~= nil, "an unticked group is not stored as nil")

print(("chat idle fade also wake on harness: %d checks, ok"):format(n))
