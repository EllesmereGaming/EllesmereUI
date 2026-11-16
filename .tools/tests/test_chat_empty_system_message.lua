-- Stub harness: system messages with no text (WoW Forever sends them) and the
-- timestamp of Timestamp All Messages.
-- Cuts the real code: the engine's StampDisplay with HasTimestampPrefix
-- (EllesmereUIChat_Engine.lua) and the CHAT_MSG_SYSTEM filter of the login pass
-- (EUI_Chat_Init.lua), run through a model of Blizzard's message filter registry
-- (Blizzard_ChatFrameBase/Shared/ChatFrameFilters.lua: filters are skipped for
-- values the caller cannot read, the first true return discards the message, a
-- second return replaces the arguments).
--   lua .tools/tests/test_chat_empty_system_message.lua        (from the repository root)

local function ReadRaw(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = f:read("*a")
    f:close()
    return src
end

local function Count(src, text)
    local n, at = 0, 1
    while true do
        local s, e = src:find(text, at, true)
        if not s then return n end
        n, at = n + 1, e + 1
    end
end

local count, fails = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local ENGINE_RAW = ReadRaw("EllesmereUIChat/EllesmereUIChat_Engine.lua")
local INIT_RAW = ReadRaw("EllesmereUIChat/EUI_Chat_Init.lua")
local ENGINE = ENGINE_RAW:gsub("\r\n", "\n")
local INIT = INIT_RAW:gsub("\r\n", "\n")

-------------------------------------------------------------------------------
--  1. The files: spaces only, and the filters go through ChatFrameUtil
-------------------------------------------------------------------------------
check(Count(ENGINE_RAW, "\t") == 0, "the engine file holds no tab")
check(Count(INIT_RAW, "\t") == 0, "the login pass file holds no tab")
-- ChatFrame_AddMessageEventFilter is an alias Blizzard's deprecated-API addon defines.
check(Count(INIT, "ChatFrame_AddMessageEventFilter") == 0 and Count(ENGINE, "ChatFrame_AddMessageEventFilter") == 0,
    "no filter is registered through the deprecated global")
check(Count(INIT, "ChatFrameUtil.AddMessageEventFilter(") == 2, "two filter registrations in the login pass")
check(Count(INIT, "ChatFrameUtil.AddMessageEventFilter(ev, UrlFilter)") == 1, "the URL filter registers through ChatFrameUtil")

-------------------------------------------------------------------------------
--  World
-------------------------------------------------------------------------------
date = date or os.date
local SECRET = {}
local secretAsks = 0
issecretvalue = function(v)
    secretAsks = secretAsks + 1
    return v == SECRET
end
canaccessvalue = function(...)
    for i = 1, select("#", ...) do
        if select(i, ...) == SECRET then return false end
    end
    return true
end

-------------------------------------------------------------------------------
--  2. The stamp
-------------------------------------------------------------------------------
local function CutStamp()
    local a = ENGINE:find("local function HasTimestampPrefix(msg)", 1, true)
    local b = ENGINE:find("local function ExtractLineID", 1, true)
    assert(a and b and b > a, "the stamp block was not found")
    return assert(loadstring("local _stampAllOn, _protActive, _stampFmt = ...\n" .. ENGINE:sub(a, b - 1)
        .. "\nreturn StampDisplay", "=StampDisplay"))
end
local stampChunk = CutStamp()
local FMT = "%H:%M "
local now = 1700000000
local ts = date(FMT, now)

local stamp = stampChunk(true, false, FMT)
check(stamp("", now) == "", "an empty line stays empty under Timestamp All Messages")
check(stamp("Hello", now) == ts .. "Hello", "a normal line is stamped")
check(stamp(" ", now) == ts .. " ", "a line holding one space is stamped")
check(stamp("12:34 Hello", now) == "12:34 Hello", "a line that carries a stamp is not stamped again")
check(stamp("1:02:03 PM Hello", now) == "1:02:03 PM Hello", "a 12-hour stamp with seconds counts as a stamp")
check(stamp(SECRET, now) == SECRET, "a secret line passes through")
check(stamp(nil, now) == nil, "a missing line passes through")
check(stamp(42, now) == 42, "a number passes through")
secretAsks = 0
stamp("", now)
check(secretAsks == 1, "the secrecy test comes before the empty test")

local off = stampChunk(false, false, FMT)
check(off("", now) == "" and off("Hello", now) == "Hello", "Timestamp All Messages off: nothing is stamped")
local prot = stampChunk(true, true, FMT)
check(prot("Hello", now) == "Hello" and prot("", now) == "", "protected content: nothing is stamped")

-------------------------------------------------------------------------------
--  3. The filter
-------------------------------------------------------------------------------
local registered = {}
ChatFrameUtil = {
    AddMessageEventFilter = function(event, callback)
        registered[#registered + 1] = { event = event, callback = callback }
    end,
}
do
    local first = 'ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM"'
    local a = INIT:find(first, 1, true)
    assert(a, "the system message filter was not found")
    local _, e = INIT:find("\n    end)\n", a, true)
    assert(e, "the system message filter's end was not found")
    assert(loadstring(INIT:sub(a, e), "=system filter"))()
end
check(#registered == 1 and registered[1].event == "CHAT_MSG_SYSTEM", "one filter, on CHAT_MSG_SYSTEM")
local callback = registered[1] and registered[1].callback or function() end

-- Blizzard's ProcessFilters with this one filter registered.
local called
local function Process(chatFrame, event, ...)
    called = false
    if not canaccessvalue(...) then return false, ... end
    called = true
    local results = { callback(chatFrame, event, ...) }
    if results[1] then return true end
    if results[2] then return false, unpack(results, 2) end
    return false, ...
end

local discard, msg, a2, a3 = Process({}, "CHAT_MSG_SYSTEM", "")
check(discard == true, "a system message with no text is discarded")
discard, msg, a2, a3 = Process({}, "CHAT_MSG_SYSTEM", "You are now Away: AFK", "sender", "lang")
check(discard == false and msg == "You are now Away: AFK" and a2 == "sender" and a3 == "lang",
    "a normal system message is kept with its arguments")
discard, msg = Process({}, "CHAT_MSG_SYSTEM", " ")
check(discard == false and msg == " ", "a system message holding one space is kept")
discard, msg = Process({}, "CHAT_MSG_SYSTEM", nil)
check(discard == false and msg == nil, "a system message with no message argument is kept")
discard, msg = Process({}, "CHAT_MSG_SYSTEM", 0)
check(discard == false and msg == 0, "a number is kept")
discard, msg = Process({}, "CHAT_MSG_SYSTEM", SECRET)
check(discard == false and called == false and msg == SECRET, "a secret message never reaches the filter")
-- Called directly with a secret: asked about before it is compared, and kept.
secretAsks = 0
local kept = callback({}, "CHAT_MSG_SYSTEM", SECRET)
check(kept == false, "a secret message handed to the filter is kept")
check(secretAsks == 1, "the filter asks about secrecy before it compares")
-- The filter returns one value: it never replaces a message's arguments.
check(select("#", callback({}, "CHAT_MSG_SYSTEM", "text")) == 1, "the filter returns the discard flag alone")

-- A line the filter kept and the stamp: nothing in between turns it empty.
discard, msg = Process({}, "CHAT_MSG_SYSTEM", "Roll: 57 (1-100)")
check(discard == false and stamp(msg, now) == ts .. "Roll: 57 (1-100)", "a kept system message is stamped as before")

if fails > 0 then error(fails .. " of " .. count .. " checks failed") end
print("PASS test_chat_empty_system_message (" .. count .. " checks)")
