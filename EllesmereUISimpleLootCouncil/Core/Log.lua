if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Log = {}
addon.Log = Log


local issecretvalue = issecretvalue
local debugstack = debugstack



local maxEntries = 10000


local CHUNK, SEP = 64, "\31"
local chunks, sizes, first, last, chunkTotal, tail = {}, {}, 1, 0, 0, {}
local packed = {}
local echoToChat = false


local chatWarnings = true
local repeats = {}
local clockSecond, clockText



local DETAIL = { quiet = 3, normal = 2, verbose = 1 }
local RANK = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
local TRAILER = 30
local detail, floor = "verbose", 1
local recent = {}

local SAME_LINE_MAX = 3
local sameCount = {}

local function Clock()
    local second = time()
    if second ~= clockSecond then
        clockSecond, clockText = second, date("%H:%M:%S")
    end
    return clockText
end


local function Pack(text)
    local api = C_EncodingUtil
    if not (api and api.CompressString and Enum and Enum.CompressionMethod) then return text, false end
    local ok, out = pcall(api.CompressString, text, Enum.CompressionMethod.Deflate)
    if ok and type(out) == "string" and #out < #text then return out, true end
    return text, false
end

local function Text(index)
    local text = chunks[index]
    if not packed[index] then return text end
    local ok, out = pcall(function()
        return C_EncodingUtil.DecompressString(text, Enum.CompressionMethod.Deflate)
    end)
    return ok and type(out) == "string" and out or ""
end

local function Seal()
    local n = #tail
    last = last + 1
    chunks[last], packed[last] = Pack(table.concat(tail, SEP))
    sizes[last] = n
    chunkTotal = chunkTotal + n
    for i = n, 1, -1 do tail[i] = nil end
end

local function Total() return chunkTotal + #tail end


local QUIET_MAX = 3000

local function Append(line)
    if maxEntries < 1 then return end
    if line:find(SEP, 1, true) then line = line:gsub(SEP, " ") end
    tail[#tail + 1] = line
    if #tail >= CHUNK then Seal() end
    while first <= last and Total() - sizes[first] >= maxEntries do
        chunkTotal = chunkTotal - sizes[first]
        chunks[first], sizes[first], packed[first] = nil, nil, nil
        first = first + 1
    end
    if first > last and #tail > maxEntries then table.remove(tail, 1) end
end


local function Split(text, out, skip)
    local pos = 1
    while true do
        local at = text:find(SEP, pos, true)
        local piece = text:sub(pos, (at or 0) - 1)
        if not at then piece = text:sub(pos) end
        if skip > 0 then skip = skip - 1 else out[#out + 1] = piece end
        if not at then break end
        pos = at + 1
    end
    return skip
end



local FOLD = "  >  "
local MAX_HELD = 2000
local holdDepth, heldLine, heldPrefix, heldAt = 0, nil, nil, nil

local function Now() return GetTime and GetTime() or 0 end

local function Flush()
    if heldLine then Append(heldLine) end
    heldLine, heldPrefix = nil, nil
end


local function DropStaleHold()
    if holdDepth > 0 and heldAt ~= Now() then
        Flush()
        holdDepth = 0
    end
end


local function Fold(level, prefix, message, line, detail)
    DropStaleHold()
    if holdDepth == 0 then return false end
    if level ~= "DEBUG" or detail then
        Flush()
        return false
    end
    if not heldLine then
        heldLine, heldPrefix = line, prefix
        return true
    end
    local part = prefix == heldPrefix and message
        or ("[%s] %s"):format(tostring(prefix), message)
    heldLine = heldLine .. FOLD .. part
    if #heldLine > MAX_HELD then Flush() end
    return true
end







local MAX_VALUE = 256
local MAX_MESSAGE = 1024


local function Cap(text, limit)
    local length = #text
    if length <= limit then return text end
    local last = limit
    while last > 0 and text:byte(last + 1) and text:byte(last + 1) >= 0x80
        and text:byte(last + 1) < 0xC0 do
        last = last - 1
    end
    local pipes = 0
    while pipes < last and text:byte(last - pipes) == 124 do pipes = pipes + 1 end
    if pipes % 2 == 1 then last = last - 1 end
    return ("%s...(+%d bytes)"):format(text:sub(1, last), length - last)
end
Log.Cap = Cap



local function Sanitise(value)
    if issecretvalue and issecretvalue(value) then
        return "<secret>"
    end
    local t = type(value)
    if t == "string" then
        return #value > MAX_VALUE and Cap(value, MAX_VALUE) or value
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(value)
    elseif t == "table" then


        return "{table}"
    end
    return tostring(value)
end


local parts = {}

local function Join(...)
    local n = select("#", ...)
    if n == 0 then return "" end
    if n == 1 then return Sanitise((...)) end
    for i = 1, n do
        parts[i] = Sanitise((select(i, ...)))
    end
    return table.concat(parts, "  ", 1, n)
end





local LEVEL_COLOR = {
    DEBUG = "|cff888888",
    INFO  = "|cff478ceb",
    WARN  = "|cffffd100",
    ERROR = "|cffff4040",
}

Log.ECHO_PREFIX = {}
for level, color in pairs(LEVEL_COLOR) do Log.ECHO_PREFIX[level] = color .. "SimpleLootCouncil|r " end
Log.CHAT_PREFIX = {
    accent = LEVEL_COLOR.INFO .. "SimpleLootCouncil:|r ",
    warn = LEVEL_COLOR.WARN .. "SimpleLootCouncil:|r ",
    error = LEVEL_COLOR.ERROR .. "SimpleLootCouncil:|r ",
}



local function Write(level, prefix, message, stack, logOnly)
    local rank = RANK[level]
    local recording = rank >= floor or echoToChat

    if not recording and rank < RANK.INFO then return end
    if #message > MAX_MESSAGE then message = Cap(message, MAX_MESSAGE) end
    local line = ("%s %-5s [%s] %s"):format(Clock(), level, tostring(prefix), message)
    if not recording then
        if #recent >= TRAILER then table.remove(recent, 1) end
        recent[#recent + 1] = line
        return
    end
    local stored = true
    if rank >= RANK.WARN and floor >= 3 and not stack then
        local key = level .. "|" .. tostring(prefix) .. "|" .. message
        local n = (sameCount[key] or 0) + 1
        sameCount[key] = n
        stored = n <= SAME_LINE_MAX
    end
    if stored then
        if rank >= RANK.WARN and recent[1] then
            for i = 1, #recent do Append(recent[i]) end
            recent = {}
        end
        if not Fold(level, prefix, message, line, stack) then
            Append(stack and (line .. stack) or line)
        end
    end

    if not echoToChat then
        if logOnly or level ~= "ERROR" and level ~= "WARN" or not chatWarnings then return end
        local key = ("%s [%s] %s"):format(level, tostring(prefix), message)
        local seen = repeats[key]
        repeats[key] = (seen or -1) + 1
        if seen then return end
    end

    local chatLine = prefix == "Taint" and line:gsub("|", "||") or line
    addon.Chat.Echo(level, chatLine)
end






function Log:D(prefix, ...)
    if floor > 1 and not echoToChat then return end
    Write("DEBUG", prefix, Join(...))
end
function Log:I(prefix, ...) Write("INFO", prefix, Join(...)) end
function Log:W(prefix, ...) Write("WARN", prefix, Join(...)) end
function Log:E(prefix, ...) Write("ERROR", prefix, Join(...)) end

function Log:WLogOnly(prefix, ...) Write("WARN", prefix, Join(...), nil, true) end



function Log:Bug(prefix, message)
    local stack = ""
    if debugstack then


        local raw = debugstack(2, 6, 0)
        stack = (issecretvalue and issecretvalue(raw)) and "<secret stack>" or tostring(raw)
    end
    Write("ERROR", prefix, Sanitise(message), "  \n" .. stack)
end


function Log:Hold()
    DropStaleHold()
    holdDepth = holdDepth + 1
    heldAt = Now()
end

function Log:Release()
    if holdDepth == 0 then return end
    holdDepth = holdDepth - 1
    if holdDepth == 0 then Flush() end
end

function Log:GetEntries()
    DropStaleHold()
    local ordered = {}
    local skip = math.max(Total() - maxEntries, 0)
    for c = first, last do skip = Split(Text(c), ordered, skip) end
    for i = 1, #tail do
        if skip > 0 then skip = skip - 1 else ordered[#ordered + 1] = tail[i] end
    end
    for i = 1, #recent do ordered[#ordered + 1] = recent[i] end
    return ordered
end


local SESSION_MARKER = "session start ---"



function Log:GetSessionEntries()
    DropStaleHold()
    local out = {}
    for i = #tail, 1, -1 do
        if tail[i]:find(SESSION_MARKER, 1, true) then
            for j = i, #tail do out[#out + 1] = tail[j] end
            for j = 1, #recent do out[#out + 1] = recent[j] end
            return out
        end
    end
    for c = last, first, -1 do
        local text, found, pos = Text(c), nil, 1
        while true do
            local at = text:find(SESSION_MARKER, pos, true)
            if not at then break end
            found, pos = at, at + 1
        end
        if found then
            local lineStart = found
            while lineStart > 1 and text:byte(lineStart - 1) ~= 31 do lineStart = lineStart - 1 end
            Split(text:sub(lineStart), out, 0)
            for later = c + 1, last do Split(Text(later), out, 0) end
            for j = 1, #tail do out[#out + 1] = tail[j] end
            for j = 1, #recent do out[#out + 1] = recent[j] end
            return out
        end
    end
    return self:GetEntries()
end


local configuredMax = maxEntries


function Log:SetDetail(mode)
    if not DETAIL[mode] then mode = "quiet" end
    detail, floor = mode, DETAIL[mode]
    maxEntries = floor > 1 and math.min(configuredMax, QUIET_MAX) or configuredMax
    recent = {}
    return mode
end

function Log:GetDetail() return detail end

function Log:SetEcho(enabled)
    echoToChat = not not enabled
end


function Log:SetChatWarnings(enabled)
    chatWarnings = enabled ~= false
end







local blocked = {}
local OWN_ADDON = (...) or "SimpleLootCouncil"



local function OnBlocked(event, isTainted, blockedFunc)
    local key = ("%s|%s|%s"):format(event, tostring(isTainted), tostring(blockedFunc))
    blocked[key] = (blocked[key] or 0) + 1
    if blocked[key] == 1 then
        Log:WLogOnly("Taint", event, isTainted, blockedFunc)
        if isTainted == OWN_ADDON and chatWarnings and not echoToChat then
            local T = addon.Locale.Text
            addon.Chat.Error(addon.Locale.Format(
                T["the game blocked an action by this addon (%s). Please report it with your /slc log."],
                (tostring(blockedFunc):gsub("|", "||"))))
        end
    elseif blocked[key] == 50 then
        Log:WLogOnly("Taint", "suppressing further reports of", key)
    end
end

function Log:GetBlockedCounts()
    return blocked
end





local function IsProblem(line)
    return line:find(" WARN ", 1, true) or line:find(" ERROR ", 1, true)
end


local function Keeps(line)
    return floor < 3 or IsProblem(line)
        or line:find("SUMMARY", 1, true) or line:find(SESSION_MARKER, 1, true)
end


function Log:Init(db)
    db.log = db.log or {}
    configuredMax = db.logMaxEntries or configuredMax
    self:SetDetail(db.logDetail)
    echoToChat = not not db.debug
    chatWarnings = db.chatWarnings ~= false

    local pending = self:GetEntries()
    chunks, sizes, first, last, chunkTotal, tail = {}, {}, 1, 0, 0, {}
    packed = {}
    local lastStart, run = nil, {}
    for _, line in ipairs(db.log) do
        if type(line) == "string" then


            if Keeps(line) then
                if IsProblem(line) then
                    for i = 1, #run do Append(run[i]) end
                end
                run = {}
                Append(line)
            elseif line:find(" INFO ", 1, true) then
                if #run >= TRAILER then table.remove(run, 1) end
                run[#run + 1] = line
            else
                run = {}
            end
            if line:find(SESSION_MARKER, 1, true) then lastStart = line end
        end
    end


    db.log = { lastStart }

    for _, line in ipairs(pending) do
        if Keeps(line) or not line:find(" DEBUG ", 1, true) then Append(line) end
    end

    Append(("--- %s session start ---"):format(date("%Y-%m-%d %H:%M:%S")))

    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_ACTION_BLOCKED")
    f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "PLAYER_LOGOUT" then
            Flush()
            holdDepth = 0


            for key, count in pairs(blocked) do
                if count > 1 then
                    Append(("%s SUMMARY blocked x%d %s"):format(Clock(), count, key))
                end
            end
            for key, count in pairs(sameCount) do
                if count > SAME_LINE_MAX then
                    Append(("%s SUMMARY stored %d of %d %s"):format(Clock(), SAME_LINE_MAX, count, key))
                end
            end
            for key, count in pairs(repeats) do
                if count > 0 then
                    Append(("%s SUMMARY kept from chat x%d %s"):format(Clock(), count, key))
                end
            end
            db.log = Log:GetEntries()
        else
            OnBlocked(event, arg1, arg2)
        end
    end)

    Log:I("Log", "initialised", ("%d entries, cap %d"):format(Total(), maxEntries))
end
