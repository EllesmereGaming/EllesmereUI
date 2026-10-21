if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Roll = {}
addon.Roll = Roll


local LOW, HIGH = 1, 100
Roll.LOW, Roll.HIGH = LOW, HIGH


function Roll.ValidValue(value)
    return type(value) == "number" and value == math.floor(value)
        and value >= LOW and value <= HIGH
end


local function ValidRound(round)
    return round == nil or (type(round) == "number" and round >= 0
        and round == math.floor(round))
end


local refusalLogged = {}
local function Refuse(reason, sender, ...)
    local key = reason .. "|" .. tostring(sender)
    if refusalLogged[key] then return end
    refusalLogged[key] = true
    addon.Log:D("Roll", "refused", reason, "from", tostring(sender), ...)
end


local IsSecret = addon.IsSecret







function Roll.ResolveGrammar(text)
    if type(text) ~= "string" then return text end


    text = text:gsub("|3%-%d+%((.-)%)", "%1")


    return (text:gsub("|1([^;]*);([^;]*);", "%1"))
end


function Roll.BuildPattern(fmt, twoWords)
    if type(fmt) ~= "string" then return nil end
    if twoWords == nil then twoWords = addon.Player and addon.Player.IS_FOREVER end



    local grammar, fixedGrammarByte = "\1", "\2"
    local flat = fmt:gsub("%%(%d+)%$([sd])", "%%%2")
    flat = flat:gsub("|3%-%d+%((.-)%)", "%1")
    flat = flat:gsub("|1([^;]*);([^;]*);", function(one, other)

        if #one == #other then return fixedGrammarByte:rep(#one) end
        return grammar
    end)


    local pattern = flat:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    pattern = pattern:gsub(grammar, ".-")
    pattern = pattern:gsub(fixedGrammarByte, ".")



    pattern = pattern:gsub("%%s", twoWords and "(%%S+ %%S+)" or "([^%%[%%]%%(%%):]+)")
    pattern = pattern:gsub("%%d", "(%%-?%%d+)")

    return "^" .. pattern .. "$"
end



function Roll.Unwrap(message)
    if type(message) ~= "string" then return message end
    if not message:find("|", 1, true) then return message end
    local text = message:gsub("|Hplayer:([^|:]+)[^|]*|h%[.-%]|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")

    text = text:gsub("|cn[^:|]*:", "")
    text = text:gsub("|r", "")
    return text
end



function Roll.ParseSystem(message, pattern)
    if type(message) ~= "string" or type(pattern) ~= "string" then return nil end
    local name, value, low, high = message:match(pattern)
    if not name or not value then return nil end
    return name, tonumber(value), tonumber(low), tonumber(high)
end


local systemPattern







function Roll.NoRepeat(names, low, high)
    low, high = low or LOW, high or HIGH
    local span = high - low + 1
    if #names > span then return nil end

    local pool = {}
    for value = low, high do pool[#pool + 1] = value end
    for index = #pool, 2, -1 do
        local swap = math.random(index)
        pool[index], pool[swap] = pool[swap], pool[index]
    end

    local assigned = {}
    for index, name in ipairs(names) do assigned[name] = pool[index] end
    return assigned
end










function Roll.AskedAt(item, name)
    if not item or not name then return 0 end
    local all = item.rollAskAll or 0
    local mine = item.rollAsk and item.rollAsk[name] or 0
    return all > mine and all or mine
end

function Roll.IsAsked(item, name)
    return Roll.AskedAt(item, name) > 0
end

function Roll.Of(item, name)
    local candidate = item and item.candidates and item.candidates[name]
    if not candidate then return nil end
    return candidate.roll, candidate.rollBy
end


function Roll.UnawardedSessions()
    local sessions = {}
    for _, item in ipairs(addon.Session:GetItems()) do

        if not item.awarded and not item.removed then
            sessions[#sessions + 1] = item.session
        end
    end
    return sessions
end



local function Matching(item, predicate)
    local names = {}
    for name, candidate in pairs(item.candidates or {}) do
        if predicate(name, candidate) then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end


function Roll.WithResponse(item, responseIndex)
    return Matching(item, function(_, candidate)
        return (candidate.realResponse or candidate.response) == responseIndex
    end)
end

function Roll.WithRoll(item, value)
    return Matching(item, function(_, candidate) return candidate.roll == value end)
end










local function Round(item)
    return item.rollRound or 0
end


local function ClearRolls(item)
    for _, candidate in pairs(item.candidates or {}) do
        candidate.roll, candidate.rollBy, candidate.rollSeq = nil, nil, nil
    end
end



local function ApplyUnstamped(item, names)
    local stamp = item.rollAskSeq or 0
    if stamp == 0 then stamp = 1 end
    item.rollAskSeq = stamp

    if names == nil then
        if item.rollAskAll ~= nil then return false end
        item.rollAskAll = stamp
        return true
    end


    if item.rollAskAll ~= nil then return false end

    local widened = false
    item.rollAsk = item.rollAsk or {}
    for _, name in ipairs(names) do
        if not item.rollAsk[name] then
            item.rollAsk[name] = stamp
            widened = true
        end
    end
    return widened
end

function Roll:ApplyAsk(payload, sender)
    if type(payload) ~= "table" or type(payload.ss) ~= "table" then return end
    if (payload.w ~= nil and type(payload.w) ~= "table")
        or (payload.k ~= nil and type(payload.k) ~= "table") then
        Refuse("malformed_roll_ask", sender)
        return
    end



    local touched = {}
    for _, session in ipairs(payload.ss) do
        local item = addon.Session:GetItem(session)
        if item then
            local stamp = payload.k
                and tonumber(payload.k[session] or payload.k[tostring(session)])
            local changed
            if stamp then
                changed = stamp > (item.rollAskSeq or 0)
                if changed then
                    item.rollAskSeq = stamp
                    if payload.w == nil then

                        item.rollAskAll = stamp
                    else
                        item.rollAsk = item.rollAsk or {}
                        for _, name in ipairs(payload.w) do
                            item.rollAsk[name] = stamp
                        end
                    end
                end
            else
                changed = ApplyUnstamped(item, payload.w)
            end
            if changed then touched[#touched + 1] = session end
        end
    end



    if #touched == 0 then return end
    addon.Log:I("Roll", "roll asked for on", #touched, "session(s) by",
        tostring(sender))

    if addon.Callbacks then
        addon.Callbacks:Fire("RollRequested", touched, payload.w)

        addon.Callbacks:Fire("SessionChanged", #touched == 1 and touched[1] or nil, "roll")
    end
end


function Roll:ApplyRoll(session, name, value, round, sender, selfReport)
    if type(name) ~= "string" or not Roll.ValidValue(value) or not ValidRound(round) then
        Refuse("malformed_roll", sender, tostring(value))
        return
    end
    local item = addon.Session:GetItem(session)
    if not item then return end

    local candidate = item.candidates and item.candidates[name]
    if not candidate then
        addon.Log:W("Roll", "roll for a candidate we do not have", tostring(name))
        return
    end



    if round ~= nil and round ~= Round(item) then
        addon.Log:D("Roll", "roll from a stale round discarded", session,
            tostring(name), round, "have", Round(item))
        return
    end



    local asked = Roll.AskedAt(item, name)
    if candidate.roll ~= nil and candidate.rollBy == "player"
        and (candidate.rollSeq or 0) >= asked then
        if candidate.roll ~= value then
            addon.Log:D("Roll", "second roll against one ask ignored",
                tostring(name), value, "keeping", candidate.roll)
        end
        return
    end


    if selfReport and asked == 0 then
        Refuse("unasked_roll", sender, "session", tostring(session))
        return
    end

    if candidate.roll ~= nil then
        addon.Log:I("Roll", "a real roll supersedes",
            candidate.rollBy == "leader" and "the assigned number" or "an older roll",
            tostring(name), value, "was", candidate.roll)
    end

    candidate.roll = value
    candidate.rollBy = "player"


    candidate.rollSeq = asked
    addon.Log:I("Roll", "roll", session, tostring(name), value, "from",
        tostring(sender))
    if addon.Callbacks then addon.Callbacks:Fire("SessionChanged", session, "roll", name) end
end

function Roll:ApplyRolls(session, round, assigned, sender)
    if type(assigned) ~= "table" or not ValidRound(round) then
        Refuse("malformed_rolls", sender)
        return
    end

    for name, value in pairs(assigned) do
        if type(name) ~= "string" or not Roll.ValidValue(value) then
            Refuse("malformed_rolls", sender, tostring(value))
            return
        end
    end
    local item = addon.Session:GetItem(session)
    if not item then return end


    if round ~= nil and round <= Round(item) then
        if round == Round(item) then
            addon.Log:D("Roll", "generated rolls already applied", session, round)
        else
            addon.Log:D("Roll", "stale generated rolls discarded", session, round,
                "have", Round(item))
        end
        return
    end

    item.rollRound = round or (Round(item) + 1)
    ClearRolls(item)


    item.rollAsk, item.rollAskAll = nil, nil

    for name, value in pairs(assigned) do
        local candidate = item.candidates and item.candidates[name]
        if candidate then
            candidate.roll = value
            candidate.rollBy = "leader"
        end
    end

    addon.Log:I("Roll", "generated rolls applied to session", session, "by",
        tostring(sender))
    if addon.Callbacks then addon.Callbacks:Fire("SessionChanged", session, "roll") end
end

function Roll:ApplyClear(payload, sender)
    if type(payload) ~= "table" or type(payload.k) ~= "table" then return end

    local cleared, only = 0, nil
    for session, round in pairs(payload.k) do
        local index = tonumber(session) or session
        local item = addon.Session:GetItem(index)
        if not ValidRound(round) then
            Refuse("malformed_roll_clear", sender)
        elseif item and round > Round(item) then
            item.rollRound = round
            ClearRolls(item)

            cleared = cleared + 1
            only = index
        end
    end

    if cleared == 0 then return end
    addon.Log:I("Roll", "rolls cleared on", cleared, "session(s) by",
        tostring(sender))
    if addon.Callbacks then
        addon.Callbacks:Fire("SessionChanged", cleared == 1 and only or nil, "roll")
    end
end



function Roll:ApplyOne(payload, sender)
    if type(payload) ~= "table" or not payload.s or not payload.c then return end
    local item = addon.Session:GetItem(payload.s)
    local candidate = item and item.candidates and item.candidates[payload.c]
    local q = tonumber(payload.q)
    if not candidate or not q or q <= (candidate.rollGen or 0) then return end

    local value = payload.v
    if value ~= nil and not Roll.ValidValue(value) then
        Refuse("malformed_roll_one", sender, tostring(value))
        return
    end

    candidate.rollGen = q
    if value then
        candidate.roll, candidate.rollBy, candidate.rollSeq = value, "leader", nil

        if item.rollAsk then item.rollAsk[payload.c] = nil end
    else
        candidate.roll, candidate.rollBy, candidate.rollSeq = nil, nil, nil
    end
    addon.Log:I("Roll", value and "generated a roll for" or "cleared the roll of",
        payload.s, tostring(payload.c), value or "", "by", tostring(sender))
    if addon.Callbacks then
        addon.Callbacks:Fire("SessionChanged", payload.s, "roll", payload.c)
    end
end





local function LeaderOnly(what)
    if addon.PlayerIsMasterLooter() then return true end
    addon.Log:W("Roll", "only the loot master can", what)
    return false
end




function Roll:Ask(sessions, names)
    if not LeaderOnly("ask for a roll") then return false end
    if type(sessions) ~= "table" or #sessions == 0 then return false end

    local stamps = {}
    for _, session in ipairs(sessions) do
        local item = addon.Session:GetItem(session)
        if item then stamps[session] = (item.rollAskSeq or 0) + 1 end
    end
    if not next(stamps) then return false end

    local payload = { ss = sessions, w = names, k = stamps }
    addon.Comms:Send("roll_ask", payload, nil, true)
    Roll:ApplyAsk(payload, addon.Player:GetFullName("player"))
    return true
end


function Roll:Random(sessions)
    if not LeaderOnly("generate rolls") then return false end
    if type(sessions) ~= "table" or #sessions == 0 then return false end

    local me = addon.Player:GetFullName("player")
    local any = false

    for _, session in ipairs(sessions) do
        local item = addon.Session:GetItem(session)
        if item then
            local names = {}
            for name in pairs(item.candidates or {}) do names[#names + 1] = name end
            table.sort(names)

            local assigned = Roll.NoRepeat(names, LOW, HIGH)
            if not assigned then
                addon.Log:W("Roll", "too many candidates to give everyone a distinct number", #names)
            else
                local round = Round(item) + 1
                addon.Comms:Send("rolls",
                    { s = session, k = round, r = assigned }, nil, true)
                Roll:ApplyRolls(session, round, assigned, me)
                any = true
            end
        end
    end
    return any
end

function Roll:Clear(sessions)
    if not LeaderOnly("clear rolls") then return false end
    if type(sessions) ~= "table" or #sessions == 0 then return false end

    local rounds = {}
    for _, session in ipairs(sessions) do
        local item = addon.Session:GetItem(session)
        if item then rounds[session] = Round(item) + 1 end
    end
    if not next(rounds) then return false end

    local payload = { k = rounds }
    addon.Comms:Send("roll_clear", payload, nil, true)
    Roll:ApplyClear(payload, addon.Player:GetFullName("player"))
    return true
end


function Roll:SetOne(session, name, generate)
    if not LeaderOnly(generate and "generate a roll" or "clear a roll") then return false end
    local item = addon.Session:GetItem(session)
    local candidate = item and item.candidates and item.candidates[name]
    if not candidate then return false end

    local payload = { s = session, c = name, q = (candidate.rollGen or 0) + 1,
        v = generate and math.random(LOW, HIGH) or nil }
    addon.Comms:Send("roll_one", payload, nil, true)
    Roll:ApplyOne(payload, addon.Player:GetFullName("player"))
    return true
end







function Roll:Roll()
    RandomRoll(LOW, HIGH)
end




function Roll.OwedBy(item, name)
    local asked = Roll.AskedAt(item, name)
    if asked == 0 then return false end
    local candidate = item.candidates and item.candidates[name]
    if not candidate then return false end
    return (candidate.rollSeq or 0) < asked
end







local function Outstanding(name)
    for _, item in ipairs(addon.Session:GetItems()) do
        if not item.awarded and not item.removed and Roll.OwedBy(item, name) then
            return item
        end
    end
    return nil
end


local function Attribute(name, value)
    local item = Outstanding(name)
    if not item then return false end
    local round = Round(item)
    addon.Comms:Send("roll",
        { s = item.session, c = name, v = value, k = round }, nil, true)
    Roll:ApplyRoll(item.session, name, value, round,
        addon.Player:GetFullName("player"))
    return true
end


local function Report(name, value)
    local item = Outstanding(name)
    if not item then return false end
    local round = Round(item)
    addon.Comms:Send("roll_own", { s = item.session, v = value, k = round },
        nil, true)
    Roll:ApplyRoll(item.session, name, value, round, name, true)
    return true
end



local rangeMarker



function Roll.ResolveName(name, members)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) or type(members) ~= "table" then
        return addon.Player:Qualify(name)
    end



    local Fold = addon.Locale.Fold
    local wanted, found = Fold(name), nil
    for full in pairs(members) do
        local short = type(full) == "string" and full:match("^([^-]+)-")
        if short and Fold(short) == wanted then
            if found then return addon.Player:Qualify(name) end
            found = full
        end
    end
    return found or addon.Player:Qualify(name)
end

function Roll:OnSystemMessage(message)
    if not systemPattern then return end
    if not addon.Session:IsRunning() then return end

    if IsSecret(message) then
        addon.Log:D("Roll", "system message is secret, cannot read a roll from it")
        return
    end

    local text = Roll.Unwrap(message)
    local name, value, low, high = Roll.ParseSystem(text, systemPattern)
    if not name or not value then
        if rangeMarker and type(text) == "string"
            and text:find(rangeMarker, 1, true) then
            addon.Log:D("Roll", "roll-shaped message did not parse", text)
        end
        return
    end



    if low ~= LOW or high ~= HIGH then return end


    local full = Roll.ResolveName(name,
        addon.GetCandidates and addon.GetCandidates() or nil)
    if not full then return end


    if addon.PlayerIsMasterLooter() then
        if not Attribute(full, value) then
            addon.Log:D("Roll", "roll ignored, nothing outstanding for",
                tostring(full), value)
        end
        return
    end

    local me = addon.Player:GetFullName("player")
    if not me or not addon.Player:IsSame(full, me) then return end
    if not Report(me, value) then
        addon.Log:D("Roll", "own roll ignored, nothing outstanding", value)
    end
end





function Roll:Init()


    local fmt = RANDOM_ROLL_RESULT
    local pattern = Roll.BuildPattern(fmt)
    if pattern then
        local tester = addon.Player.IS_FOREVER and "Test Raider" or "Tester"
        local ok, sample = pcall(string.format, fmt, tester, 73, LOW, HIGH)
        if ok then
            sample = Roll.ResolveGrammar(sample)
            local name, value, low, high = Roll.ParseSystem(sample, pattern)
            if name == tester and value == 73 and low == LOW and high == HIGH then
                systemPattern = pattern

                local _, after = sample:find("73", 1, true)
                local marker = after and sample:sub(after + 1):match("^%s*(.-)%s*$")
                if marker and marker ~= "" then rangeMarker = marker end
            end
        end
    end

    if not systemPattern then
        addon.Log:E("Roll", "cannot read roll results from chat on this client - RANDOM_ROLL_RESULT did not round-trip")
        addon.Chat.Print(T["this client's roll message could not be parsed, so typed rolls will not be recorded. The Loot Master can still generate rolls."])
    end


    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function(_, _, message)
        Roll:OnSystemMessage(message)
    end)
    local watching = false
    local function Watch()
        local want = systemPattern ~= nil and addon.Session:IsRunning() and true or false
        if want == watching then return end
        watching = want
        if want then
            watcher:RegisterEvent("CHAT_MSG_SYSTEM")
        else
            watcher:UnregisterEvent("CHAT_MSG_SYSTEM")
        end
        addon.Log:D("Roll", want and "listening for rolls" or "stopped listening for rolls")
    end
    Roll.IsWatching = function() return watching end
    addon.Callbacks:Register("RunStarted", Watch)
    addon.Callbacks:Register("RunEnded", Watch)
    Watch()


    for _, command in ipairs({ "roll", "roll_own", "roll_ask", "rolls", "roll_clear", "roll_one" }) do
        addon.Comms:ScopeToRun(command)
    end


    local function RegisterRun(command, authority, handler)
        addon.Comms:Register(command, authority, function(args, sender)
            local Session = addon.Session
            if Session and Session.HoldForRecovery
                and Session:HoldForRecovery(command, args, sender, handler) then
                return
            end
            handler(args, sender)
        end)
    end


    RegisterRun("roll", "ml", function(args, sender)
        if type(args) ~= "table" or not args.s or not args.c or not args.v then return end
        Roll:ApplyRoll(args.s, args.c, args.v, args.k, sender)
    end)



    RegisterRun("roll_own", "any", function(args, sender)
        if type(args) ~= "table" or not args.s or not args.v then return end
        local record = addon.Player:Get(sender)
        if not record.fullName then return end
        Roll:ApplyRoll(args.s, record.fullName, args.v, args.k, sender, true)
    end)

    RegisterRun("roll_ask", "ml", function(args, sender)
        Roll:ApplyAsk(args, sender)
    end)

    RegisterRun("rolls", "ml", function(args, sender)
        if type(args) ~= "table" or not args.s then return end
        Roll:ApplyRolls(args.s, args.k, args.r, sender)
    end)


    RegisterRun("roll_clear", "ml", function(args, sender)
        Roll:ApplyClear(args, sender)
    end)

    RegisterRun("roll_one", "ml", function(args, sender)
        Roll:ApplyOne(args, sender)
    end)

    addon.Log:I("Roll", "ready")
end
