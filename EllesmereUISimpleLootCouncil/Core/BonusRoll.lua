if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end







SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local BonusRoll = {}
addon.BonusRoll = BonusRoll


local IsSecret = addon.IsSecret



local RECENT_WINDOW = 15 * 60
BonusRoll.RECENT_WINDOW = RECENT_WINDOW


local recentCoins = {}


local MAX_AGE, MAX_AHEAD = RECENT_WINDOW, 2 * 60
local MAX_LINK, MAX_BOSS, MAX_QUANTITY = 255, 80, 20
BonusRoll.MAX_AGE, BonusRoll.MAX_AHEAD = MAX_AGE, MAX_AHEAD


local SEEN_TTL = 2 * RECENT_WINDOW
local seen = {}






function BonusRoll.Matches(entry, itemLink)
    if type(entry) ~= "table" or not entry.link or not itemLink then return false end
    local a = addon.Storage.ItemID(entry.link)
    local b = addon.Storage.ItemID(itemLink)
    return a ~= nil and a == b
end




function BonusRoll.Apply(store, name, link, epoch, boss, encounterID, quantity)
    store = store or {}
    if type(name) ~= "string" or type(link) ~= "string" then return store, false end
    epoch = tonumber(epoch) or 0
    local bucket = math.floor(epoch / 60)

    for _, entry in ipairs(store) do
        if entry.name == name and BonusRoll.Matches(entry, link)
            and math.floor((entry.epoch or 0) / 60) == bucket then
            return store, false
        end
    end

    store[#store + 1] = {
        name = name, link = link, epoch = epoch, boss = boss,
        encounterID = tonumber(encounterID), quantity = quantity,
    }
    return store, true
end


function BonusRoll.ItemStringOf(link)
    if type(link) ~= "string" or #link > MAX_LINK then return nil end
    local itemString = link:match("|H(item:[^|]*)") or link:match("^item:[%-%d:]*$")
    local id = itemString and tonumber(itemString:match("^item:(%d+)"))
    if not id or id <= 0 then return nil end
    return itemString
end

local function WholeNumber(value, low, high)
    return type(value) == "number" and value == math.floor(value)
        and value >= low and value <= high
end



function BonusRoll.ValidateCoin(args, now)
    if type(args) ~= "table" then return nil, "not_a_table" end
    local link = BonusRoll.ItemStringOf(args.l)
    if not link then return nil, "not_an_item" end
    local epoch = args.t
    if type(epoch) ~= "number" or epoch ~= epoch then return nil, "no_time" end
    if epoch < now - MAX_AGE or epoch > now + MAX_AHEAD then return nil, "stale_time" end
    local boss = args.b
    if boss ~= nil and (type(boss) ~= "string" or boss == "" or #boss > MAX_BOSS) then
        return nil, "bad_boss"
    end
    local encounterID = args.e
    if encounterID ~= nil and not WholeNumber(encounterID, 1, 2 ^ 31) then
        return nil, "bad_encounter"
    end
    local quantity = args.q
    if quantity ~= nil and not WholeNumber(quantity, 1, MAX_QUANTITY) then
        return nil, "bad_quantity"
    end
    return { link = link, epoch = math.floor(epoch), boss = boss,
        encounterID = encounterID, quantity = quantity }
end



function BonusRoll.FirstSighting(store, name, itemString, encounterKey, now)
    for key, at in pairs(store) do
        if now - at > SEEN_TTL then store[key] = nil end
    end
    local id = addon.Storage.ItemID(itemString)
    local key = tostring(name) .. "|" .. tostring(id) .. "|" .. tostring(encounterKey)
    if store[key] then return false end
    store[key] = now
    return true
end



function BonusRoll.Recent(store, now)
    local kept = {}
    for _, entry in ipairs(store or {}) do
        if (now - (entry.epoch or 0)) <= RECENT_WINDOW then
            kept[#kept + 1] = entry
        end
    end
    return kept
end


function BonusRoll.For(coins, name, itemLink)
    local best
    for _, entry in ipairs(coins or {}) do
        if entry.name == name and BonusRoll.Matches(entry, itemLink) then
            if not best or (entry.epoch or 0) > (best.epoch or 0) then
                best = entry
            end
        end
    end
    return best
end




function BonusRoll.CountAtBoss(entries, winner, boss, encounterID, difficultyID,
        excludeItemLink)
    if not winner or not (boss or encounterID) then return 0 end
    local excludeID = excludeItemLink and addon.Storage.ItemID(excludeItemLink)

    local count = 0
    for _, entry in ipairs(entries or {}) do
        if entry.coin
            and addon.Encounter.SameBoss(entry.boss, entry.encounterID, boss, encounterID)
            and entry.difficultyID == difficultyID
            and addon.Player:IsSame(entry.winner, winner) then
            local id = addon.Storage.ItemID(entry.link)
            if not excludeID or id ~= excludeID then
                count = count + 1
            end
        end
    end
    return count
end



local REPLAY_WINDOW = 24 * 60 * 60
BonusRoll.REPLAY_WINDOW = REPLAY_WINDOW
function BonusRoll.AlreadyRecorded(entries, winner, link, boss, encounterID,
        difficultyID, epoch)
    local id = addon.Storage.ItemID(link)
    if not id or type(epoch) ~= "number" then return false end
    for _, entry in ipairs(entries or {}) do
        if entry.coin and type(entry.epoch) == "number"
            and math.abs(entry.epoch - epoch) <= REPLAY_WINDOW
            and entry.difficultyID == difficultyID
            and addon.Storage.ItemID(entry.link) == id
            and addon.Encounter.SameBoss(entry.boss, entry.encounterID, boss, encounterID) then
            return true
        end
    end
    return false
end





function BonusRoll:CoinsSpentAtBoss(winner, boss, encounterID, difficultyID,
        excludeItemLink)

    return BonusRoll.CountAtBoss(addon.History:CoinRowsFor(winner), winner, boss,
        encounterID, difficultyID, excludeItemLink)
end




function BonusRoll:StatusFor(name, item)
    if not item or not item.link then return nil, 0 end
    local coin = BonusRoll.For(addon.Session:GetCoins(), name, item.link)
    local difficultyID = item.difficultyID
        or addon.Encounter:DifficultyFor(item.boss, item.encounterID)
    return coin, BonusRoll:CoinsSpentAtBoss(name, item.boss, item.encounterID,
        difficultyID, item.link)
end




local RETRY_DELAY, MAX_TRIES, FORGET_MISS = 5, 3, 60
local possible, asking, missedAt = {}, {}, {}
local classIDs

local function ClassID(classFile)
    if not classIDs then
        classIDs = {}
        for i = 1, (GetNumClasses and GetNumClasses() or 0) do
            local _, file, id = GetClassInfo(i)
            if file then classIDs[file] = id end
        end
    end
    return classFile and classIDs[classFile]
end



local function Answered(key, count)
    if not count or possible[key] then return end
    asking[key], possible[key] = nil, count
    addon.Callbacks:Invalidate("council")
end

local function Ask(key, item, difficultyID, classID, specID, tries)
    asking[key] = true
    C_Timer.After(tries == 1 and 0 or RETRY_DELAY, function()
        if not asking[key] then return end
        local count = addon.Encounter:JournalCoinLoot(item.boss, item.encounterID,
            difficultyID, classID, specID, function(answer) Answered(key, answer) end)
        if count then
            asking[key], possible[key] = nil, count
            addon.Callbacks:Invalidate("council")
        elseif tries < MAX_TRIES then
            Ask(key, item, difficultyID, classID, specID, tries + 1)
        else

            local guideOpen = EncounterJournal and EncounterJournal:IsShown()
            asking[key], possible[key] = nil, false
            missedAt[key] = GetTime() - (guideOpen and (FORGET_MISS + 1) or 0)
        end
    end)
end

function BonusRoll:PossibleFor(name, item)
    if addon.IsForever or not item or not (item.boss or item.encounterID) then return nil end
    local record = addon.Player:Get(name)
    local classID = ClassID(record and record.classFile)
    if not classID then return nil end
    local specID = addon.Specs and record.guid and addon.Specs:Get(record.guid) or 0
    local difficultyID = item.difficultyID
        or addon.Encounter:DifficultyFor(item.boss, item.encounterID)

    local key = table.concat({ tostring(item.encounterID or item.boss),
        tostring(difficultyID), classID, specID }, "|")
    local count = possible[key]
    if count == false and GetTime() - missedAt[key] > FORGET_MISS then count = nil end
    if count == nil and not asking[key] then
        Ask(key, item, difficultyID, classID, specID, 1)
    end
    if not count then return nil end
    return count, specID ~= 0
end



local MAX_EVENT_RETRIES = 3
local eventRetries = {}
function BonusRoll:RetryCoinLoot(fromLootEvent)
    local any = false
    for key, count in pairs(possible) do
        if count == false and not (fromLootEvent
                and (eventRetries[key] or 0) >= MAX_EVENT_RETRIES) then
            if fromLootEvent then eventRetries[key] = (eventRetries[key] or 0) + 1 end
            possible[key], missedAt[key] = nil, nil
            any = true
        end
    end
    if any then addon.Callbacks:Invalidate("council") end
    return any
end


local guideHooked = false
local function HookGuide()
    if guideHooked or not EncounterJournal then return end
    guideHooked = true
    EncounterJournal:HookScript("OnHide", function() BonusRoll:RetryCoinLoot(false) end)
end








function BonusRoll:ApplyCoin(name, link, epoch, boss, encounterID, quantity, sender,
        simulated)
    if type(name) ~= "string" or type(link) ~= "string" then return end
    epoch = tonumber(epoch) or GetServerTime()
    encounterID = tonumber(encounterID)

    local addedRecent = false
    if not simulated then
        local _, added = BonusRoll.Apply(recentCoins, name, link, epoch, boss,
            encounterID, quantity)
        addedRecent = added

        recentCoins = BonusRoll.Recent(recentCoins, GetServerTime())
    end

    local addedToRun = false
    if addon.Session:IsRunning() then
        local _, added = BonusRoll.Apply(
            addon.Session:GetCoins(), name, link, epoch, boss, encounterID, quantity)
        addedToRun = added
    end

    if not addedRecent and not addedToRun then return end

    addon.Log:I("BonusRoll", simulated and "simulated coin" or "coin", name, link,
        "from", tostring(boss or "?"), "encounter", tostring(encounterID),
        "reported by", tostring(sender))


    if addedRecent and not simulated and addon.History then
        addon.History:RecordCoin(name, link, epoch, boss, encounterID, quantity)
    end


    if addedToRun and addon.Callbacks then
        addon.Callbacks:Fire("SessionChanged", nil, "coin", name)
    end
end


local refusalLogged = {}
local function Refuse(reason, sender)
    local key = reason .. "|" .. tostring(sender)
    if refusalLogged[key] then return end
    refusalLogged[key] = true
    addon.Log:D("BonusRoll", "refused coin", reason, "from", tostring(sender))
end



function BonusRoll:ReceiveCoin(args, sender)
    local now = GetServerTime()
    local coin, reason = BonusRoll.ValidateCoin(args, now)
    if not coin then Refuse(reason, sender) return false end
    local record = addon.Player:Get(sender)
    if not record or not record.fullName then return false end

    local logBoss, logID = addon.Encounter:AtTime(coin.epoch)
    if not (logBoss or logID) then Refuse("no_recent_encounter", sender) return false end

    if not coin.boss and not coin.encounterID then
        coin.boss, coin.encounterID = logBoss, logID
    end
    if not BonusRoll.FirstSighting(seen, record.fullName, coin.link,
            tostring(logID or logBoss), now) then
        return false
    end
    BonusRoll:ApplyCoin(record.fullName, coin.link, coin.epoch, coin.boss,
        coin.encounterID, coin.quantity, sender)
    return true
end


local function CandidateName(input, item)
    local qualified = addon.Player:Qualify(input)
    local wanted = qualified and addon.Player:NameKey(qualified)
    if not wanted then return nil end
    for candidate in pairs(item.candidates or {}) do
        if addon.Player:NameKey(candidate) == wanted then return candidate end
    end
    return nil
end




function BonusRoll:ParseFakeCoinArgs(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if args:lower() == "clear" then return { clear = true } end

    local session
    local rest, number = args:match("^(.-)%s*#(%d+)$")
    if not rest then rest, number = args:match("^(.-)%s*[Ii][Tt][Ee][Mm]%s+(%d+)$") end
    if rest then args, session = rest, tonumber(number) end

    local count, name = args:match("^(%d+)%s+(.+)$")
    if not count and args:match("^%d+$") then count = args end
    if not count then name = args end
    if count then count = math.max(1, math.min(20, math.floor(tonumber(count)))) end
    if name == "" then name = nil end
    return { count = count, name = name, session = session }
end



function BonusRoll:FindCandidate(input, session)
    if session then
        local item = addon.Session:GetItem(session)
        return item and CandidateName(input, item)
    end
    for _, item in ipairs(addon.Session:GetItems()) do
        local found = CandidateName(input, item)
        if found then return found end
    end
end

function BonusRoll:TestCoin(name, session)
    if not addon.PlayerIsMasterLooter() or not addon.Session:IsRunning() then
        return false, "master"
    end
    local item = addon.Session:GetItem(session)
    if not item then return false, "item" end
    name = CandidateName(name, item)
    if not name then return false, "candidate" end

    local epoch = GetServerTime()


    local boss, encounterID
    if item.boss ~= "Simulated Loot" and item.boss then
        boss, encounterID = item.boss, item.encounterID
    else
        boss, encounterID = addon.Encounter:Current()
        boss = boss or "Test"
    end
    addon.Comms:Send("test_coin", { s = session, n = name, t = epoch,
        b = boss, e = encounterID }, nil, true)
    BonusRoll:ApplyCoin(name, item.link, epoch, boss, encounterID, 1, "testcoin", true)
    return true, boss, name
end

function BonusRoll:ApplyTestCoin(args, sender)
    if type(args) ~= "table" or type(args.s) ~= "number"
        or type(args.n) ~= "string" or type(args.t) ~= "number"
        or not addon.Session:IsRunning() then return false end
    local item = addon.Session:GetItem(args.s)
    if not item then return false end
    local name = CandidateName(args.n, item)
    if not name then return false end
    BonusRoll:ApplyCoin(name, item.link, args.t, args.b, args.e, 1, sender, true)
    return true
end




local FAKE_MARK = "SLC fake coin (test)"
local FAKE_ITEMS = { 6948, 2589, 2592, 4306 }
local fakeSerial = 0

function BonusRoll.IsFakeCoin(entry)
    return entry ~= nil and entry.coin == true and entry.instance == FAKE_MARK
end


function BonusRoll:ClearTestHistory(name)
    local ids = {}
    addon.History.EachEntry(function(entry)
        if BonusRoll.IsFakeCoin(entry) and (not name or entry.winner == name
                or addon.Player:IsSame(entry.winner, name)) then
            ids[#ids + 1] = entry.id
        end
    end, "history")
    addon.History:DeleteEntries(ids)
    return #ids
end





function BonusRoll:SeedTestHistory(name, perBoss, onlySession)
    BonusRoll:ClearTestHistory(name)
    local seeded, skipped, done = {}, {}, {}
    local now = GetServerTime()
    for session, item in ipairs(addon.Session:GetItems()) do
        local boss, encounterID = item.boss, item.encounterID
        if boss == "Simulated Loot" then boss = nil end
        local difficultyID = item.difficultyID
            or addon.Encounter:DifficultyFor(item.boss, item.encounterID)
        if onlySession and session ~= onlySession then

        elseif not (boss or encounterID) then
            skipped[#skipped + 1] = { session = session, why = "boss" }
        elseif not difficultyID then
            skipped[#skipped + 1] = { session = session, why = "difficulty" }
        else
            local key = tostring(encounterID or boss) .. "|" .. difficultyID
            if not done[key] then
                done[key] = true
                local count = perBoss or ((#seeded % 3) + 1)
                local itemID = addon.Storage.ItemID(item.link)
                for i = 1, count do
                    fakeSerial = fakeSerial + 1
                    local epoch = now - 60 * fakeSerial
                    local coinID = FAKE_ITEMS[(fakeSerial % #FAKE_ITEMS) + 1]
                    if coinID == itemID then coinID = 19019 end
                    addon.History:Record({
                        id = ("%d-%d"):format(epoch, 9000000 + fakeSerial),
                        link = "item:" .. coinID,
                        winner = name,
                        coin = true,
                        responseCode = "COIN",
                        date = date("!%Y/%m/%d", epoch),
                        time = date("!%H:%M:%S", epoch),
                        epoch = epoch,
                        instance = FAKE_MARK,
                        difficultyID = difficultyID,
                        boss = boss,
                        encounterID = tonumber(encounterID),
                        delivered = true,
                        quantity = 1,
                    })
                end
                seeded[#seeded + 1] = { boss = boss or tostring(encounterID),
                    difficultyID = difficultyID, count = count, session = session }
            end
        end
    end
    addon.Callbacks:Invalidate("council")
    return seeded, skipped
end


function BonusRoll:Seed(now)
    return BonusRoll.Recent(recentCoins, now or GetServerTime())
end



function BonusRoll:GetRecent()
    return recentCoins
end





function BonusRoll:OnBonusRollResult(typeIdentifier, itemLink, quantity, specID, sex,
        personalLootToast, currencyID, isSecondaryResult, corrupted)

    addon.Log:D("BonusRoll", "BONUS_ROLL_RESULT", tostring(typeIdentifier),
        tostring(itemLink), tostring(quantity), tostring(specID), tostring(sex),
        tostring(personalLootToast), tostring(currencyID),
        tostring(isSecondaryResult), tostring(corrupted))



    if typeIdentifier ~= "item" then return end

    if IsSecret(itemLink) then
        addon.Log:D("BonusRoll", "item link is secret, cannot report a coin result")
        return
    end

    local itemString = addon.Gear and addon.Gear.ItemString(itemLink)
    if not itemString then return end

    local me = addon.Player:GetFullName("player")
    if not me then return end


    local boss, encounterID
    if addon.Encounter then boss, encounterID = addon.Encounter:Current() end
    local epoch = GetServerTime()

    addon.Comms:Send("coin",
        { l = itemString, t = epoch, b = boss, e = encounterID, q = quantity }, nil, true)
    BonusRoll:ApplyCoin(me, itemString, epoch, boss, encounterID, quantity, me)
end





function BonusRoll:Init()

    if addon.IsForever then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("BONUS_ROLL_RESULT")
    watcher:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(_, event, ...)
        if event == "BONUS_ROLL_RESULT" then
            BonusRoll:OnBonusRollResult(...)
        elseif event == "EJ_LOOT_DATA_RECIEVED" then
            BonusRoll:RetryCoinLoot(true)
        elseif ... == "Blizzard_EncounterJournal" then
            HookGuide()
        end
    end)
    HookGuide()


    addon.Comms:Register("coin", "any", function(args, sender)
        BonusRoll:ReceiveCoin(args, sender)
    end)



    local function ApplyTestCoin(args, sender)
        BonusRoll:ApplyTestCoin(args, sender)
    end
    addon.Comms:ScopeToRun("test_coin")
    addon.Comms:Register("test_coin", "ml", function(args, sender)
        local Session = addon.Session
        if Session and Session.HoldForRecovery
            and Session:HoldForRecovery("test_coin", args, sender, ApplyTestCoin) then
            return
        end
        ApplyTestCoin(args, sender)
    end)

    addon.Log:I("BonusRoll", "ready")
end
