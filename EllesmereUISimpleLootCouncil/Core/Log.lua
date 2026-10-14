if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Log = {}
addon.Log = Log


local issecretvalue = issecretvalue
local debugstack = debugstack



local entries = {}
local head, count = 1, 0
local maxEntries = 10000
local echoToChat = false


local chatWarnings = true
local repeats = {}
local clockSecond, clockText

local function Clock()
    local second = time()
    if second ~= clockSecond then
        clockSecond, clockText = second, date("%H:%M:%S")
    end
    return clockText
end

local function Append(line)
    if maxEntries < 1 then return end
    if count < maxEntries then
        entries[(head + count - 1) % maxEntries + 1] = line
        count = count + 1
    else
        entries[head] = line
        head = head % maxEntries + 1
    end
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







local function Sanitise(value)
    if issecretvalue and issecretvalue(value) then
        return "<secret>"
    end
    local t = type(value)
    if t == "string" or t == "number" or t == "boolean" or t == "nil" then
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
Log.CHAT_PREFIX = {
    accent = LEVEL_COLOR.INFO .. "SimpleLootCouncil:|r ",
    warn = LEVEL_COLOR.WARN .. "SimpleLootCouncil:|r ",
    error = LEVEL_COLOR.ERROR .. "SimpleLootCouncil:|r ",
}



local function Write(level, prefix, message, detail, logOnly)
    local line = ("%s %-5s [%s] %s"):format(Clock(), level, tostring(prefix), message)
    if not Fold(level, prefix, message, line, detail) then
        Append(detail and (line .. detail) or line)
    end

    if not echoToChat then
        if logOnly or level ~= "ERROR" and level ~= "WARN" or not chatWarnings then return end
        local key = ("%s [%s] %s"):format(level, tostring(prefix), message)
        local seen = repeats[key]
        repeats[key] = (seen or -1) + 1
        if seen then return end
    end

    local chatLine = prefix == "Taint" and line:gsub("|", "||") or line
    print(("%sSimpleLootCouncil|r %s"):format(LEVEL_COLOR[level] or "", chatLine))
end






function Log:D(prefix, ...) Write("DEBUG", prefix, Join(...)) end
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
    for i = 0, count - 1 do
        ordered[#ordered + 1] = entries[(head + i - 1) % maxEntries + 1]
    end
    return ordered
end


local SESSION_MARKER = "session start ---"


function Log:GetSessionEntries()
    local ordered = self:GetEntries()
    local start = 1
    for i = #ordered, 1, -1 do
        local line = ordered[i]
        if type(line) == "string" and line:find(SESSION_MARKER, 1, true) then
            start = i
            break
        end
    end

    local out = {}
    for i = start, #ordered do
        out[#out + 1] = ordered[i]
    end
    return out
end

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
            print(Log.CHAT_PREFIX.error .. addon.Locale.Format(
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






function Log:Init(db)
    db.log = db.log or {}
    maxEntries = db.logMaxEntries or maxEntries
    echoToChat = not not db.debug
    chatWarnings = db.chatWarnings ~= false

    local pending = self:GetEntries()
    entries, head, count = {}, 1, 0
    for _, line in ipairs(db.log) do Append(line) end
    for _, line in ipairs(pending) do
        Append(line)
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

    Log:I("Log", "initialised", ("%d entries, cap %d"):format(count, maxEntries))
end
