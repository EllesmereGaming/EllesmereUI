if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 






SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local BonusRoll = {}
addon.BonusRoll = BonusRoll


local issecretvalue = issecretvalue
local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end



local RECENT_WINDOW = 15 * 60
BonusRoll.RECENT_WINDOW = RECENT_WINDOW


local recentCoins = {}






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





function BonusRoll:CoinsSpentAtBoss(winner, boss, encounterID, difficultyID,
        excludeItemLink)
    return BonusRoll.CountAtBoss(addon.History:GetForWinner(winner), winner, boss,
        encounterID, difficultyID, excludeItemLink)
end




function BonusRoll:StatusFor(name, item)
    if not item or not item.link then return nil, 0 end
    local coin = BonusRoll.For(addon.Session:GetCoins(), name, item.link)
    if coin then return coin, 0 end
    local difficultyID = item.difficultyID
        or addon.Encounter:DifficultyFor(item.boss, item.encounterID)
    return nil, BonusRoll:CoinsSpentAtBoss(name, item.boss, item.encounterID,
        difficultyID, item.link)
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


local function CandidateName(input, item)
    local qualified = addon.Player:Qualify(input)
    local wanted = qualified and addon.Player:NameKey(qualified)
    if not wanted then return nil end
    for candidate in pairs(item.candidates or {}) do
        if addon.Player:NameKey(candidate) == wanted then return candidate end
    end
    return nil
end



function BonusRoll:ParseTestCoinArgs(args)
    args = (args or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if args:match("^%d+$") then return nil, tonumber(args) end
    if args == "" then return nil, 1 end

    local first = addon.Session:GetItem(1)
    if first and CandidateName(args, first) then return args, 1 end

    local name, number = args:match("^(.-)%s+(%d+)$")
    if name then
        local session = tonumber(number)

        if not first or CandidateName(name, first)
            or addon.Session:GetItem(session) or not args:find("-", 1, true) then
            return name, session
        end
    end
    return args, 1
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
    watcher:SetScript("OnEvent", function(_, _, ...)
        BonusRoll:OnBonusRollResult(...)
    end)


    addon.Comms:Register("coin", "any", function(args, sender)
        if type(args) ~= "table" or type(args.l) ~= "string" then return end
        local record = addon.Player:Get(sender)
        if not record.fullName then return end
        BonusRoll:ApplyCoin(record.fullName, args.l, args.t, args.b, args.e, args.q,
            sender)
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
