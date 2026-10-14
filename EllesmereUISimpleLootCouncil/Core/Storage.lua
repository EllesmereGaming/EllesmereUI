if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Storage = {}
addon.Storage = Storage



Storage.TO_TRADE = "to_trade"
Storage.AWARD_LATER = "award_later"







function Storage:GetSlotTradeInfo(bag, slot)
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    if not data or not data.lines then return nil, nil end

    local secondsLeft, bonding
    for _, line in ipairs(data.lines) do
        if line.type == Enum.TooltipDataLineType.TradeTimeRemaining then
            secondsLeft = line.secondsLeft
        elseif line.type == Enum.TooltipDataLineType.ItemBinding then

            bonding = bonding or line.bonding
        end
    end
    return secondsLeft, bonding
end










local function Canonical(itemString)
    local fields = {}
    for field in (itemString:sub(6) .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    local bonusCount = tonumber(fields[13] or "") or 0
    local modifierAt = 14 + bonusCount
    local pairCount = tonumber(fields[modifierAt] or "") or 0
    if #fields < modifierAt + pairCount * 2 and (bonusCount > 0 or pairCount > 0) then
        return itemString
    end

    fields[9], fields[10] = "", ""
    if bonusCount > 1 then
        local bonuses = {}
        for i = 1, bonusCount do bonuses[i] = tonumber(fields[13 + i]) or 0 end
        table.sort(bonuses)
        for i = 1, bonusCount do fields[13 + i] = tostring(bonuses[i]) end
    end
    if pairCount > 1 then
        local mods = {}
        for i = 1, pairCount do
            local at = modifierAt + (i - 1) * 2 + 1
            mods[i] = { tonumber(fields[at]) or 0, fields[at + 1] or "" }
        end
        table.sort(mods, function(x, y)
            if x[1] ~= y[1] then return x[1] < y[1] end
            return x[2] < y[2]
        end)
        for i = 1, pairCount do
            local at = modifierAt + (i - 1) * 2 + 1
            fields[at], fields[at + 1] = tostring(mods[i][1]), mods[i][2]
        end
    end
    while #fields > 1 and fields[#fields] == "" do fields[#fields] = nil end
    return "item:" .. table.concat(fields, ":")
end
Storage.CanonicalItemString = Canonical

local function ItemsMatch(a, b)
    if not a or not b then return false end
    if a == b then return true end


    local ia = a:match("|H(item:[^|]*)") or a
    local ib = b:match("|H(item:[^|]*)") or b
    if ia == ib then return true end
    if ia:sub(1, 5) ~= "item:" or ib:sub(1, 5) ~= "item:" then return false end
    return Canonical(ia) == Canonical(ib)
end
Storage.ItemsMatch = ItemsMatch



local function ItemID(link)
    if not link then return nil end
    return tonumber(link:match("|Hitem:(%d+)")) or tonumber(link:match("^item:(%d+)"))
end
Storage.ItemID = ItemID



function Storage:FindInBags(link, skip)
    local function Skipped(bag, slot)
        if not skip then return false end
        for _, entry in ipairs(skip) do
            if entry.bag == bag and entry.slot == slot then return true end
        end
        return false
    end

    local function Scan(matches)
        local best
        for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
            local slots = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, slots do
                local present = C_Container.GetContainerItemLink(bag, slot)
                if not Skipped(bag, slot) and matches(present) then
                    local secondsLeft = Storage:GetSlotTradeInfo(bag, slot)

                    if secondsLeft and secondsLeft > 0 then
                        return bag, slot, secondsLeft, present
                    end
                    best = best or { bag = bag, slot = slot, link = present }
                end
            end
        end
        if best then return best.bag, best.slot, nil, best.link end
        return nil
    end

    local bag, slot, secondsLeft = Scan(function(present)
        return ItemsMatch(present, link)
    end)
    if bag then return bag, slot, secondsLeft end

    local wanted = ItemID(link)
    if not wanted then return nil end

    local found, foundSlot, foundSeconds, foundLink = Scan(function(present)
        return ItemID(present) == wanted
    end)
    if not found then return nil end


    addon.Log:WLogOnly("Storage", "matched by item id only",
        "wanted=" .. tostring(link and link:match("|H(item:[^|]*)") or link),
        "found=" .. tostring(foundLink and foundLink:match("|H(item:[^|]*)")
            or foundLink))
    return found, foundSlot, foundSeconds
end



function Storage:CountInBags(link)
    local wanted = ItemID(link)
    if not wanted then return 0 end

    local count = 0
    for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            if ItemID(C_Container.GetContainerItemLink(bag, slot)) == wanted then
                count = count + 1
            end
        end
    end
    return count
end





function Storage:CountTradeable(link)
    local wanted = ItemID(link)
    if not wanted then return 0, 0 end

    local count, bound = 0, 0
    for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            if ItemID(C_Container.GetContainerItemLink(bag, slot)) == wanted then
                local secondsLeft, bonding = Storage:GetSlotTradeInfo(bag, slot)
                if not (secondsLeft and secondsLeft > 0)
                    and bonding == Enum.TooltipDataItemBinding.Soulbound then
                    bound = bound + 1
                else
                    count = count + 1
                end
            end
        end
    end
    return count, bound
end



function Storage:IsEquipped(link)
    if not link then return false end
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        if ItemsMatch(GetInventoryItemLink("player", slot), link) then return true end
    end
    return false
end




local function Pair(entries, copies)
    local byId, order = {}, {}
    for index, entry in ipairs(entries or {}) do
        local id = not entry.untradeable and ItemID(entry.link)
        if id then
            byId[id] = byId[id] or {}
            table.insert(byId[id], entry)
            order[entry] = index
        end
    end

    local paired = {}
    for id, owed in pairs(byId) do
        table.sort(owed, function(a, b)
            local at, bt = a.addedAt or 0, b.addedAt or 0
            if at ~= bt then return at < bt end
            return order[a] < order[b]
        end)
        local held = {}
        for i, copy in ipairs(copies[id] or {}) do held[i] = copy end
        table.sort(held, function(a, b) return a.seconds < b.seconds end)
        local claimed = {}
        for _, exact in ipairs({ true, false }) do
            for _, entry in ipairs(owed) do
                if paired[entry] == nil then
                    for _, copy in ipairs(held) do
                        if not claimed[copy] and (not exact or ItemsMatch(copy.link, entry.link)) then
                            claimed[copy] = true
                            paired[entry] = copy
                            break
                        end
                    end
                end
            end
        end
    end
    return paired
end




function Storage:GetTradeableItems()
    local found = {}

    for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local secondsLeft = Storage:GetSlotTradeInfo(bag, slot)
                if secondsLeft and secondsLeft > 0 then
                    found[#found + 1] = {
                        link = link,
                        bag = bag,
                        slot = slot,
                        secondsLeft = secondsLeft,

                        eligible = addon.Loot and addon.Loot:IsCouncilItem(link) or false,
                    }
                end
            end
        end
    end

    table.sort(found, function(a, b)
        if a.secondsLeft == b.secondsLeft then

            return (a.bag * 100 + a.slot) < (b.bag * 100 + b.slot)
        end
        return a.secondsLeft > b.secondsLeft
    end)

    local copies = {}
    for _, item in ipairs(found) do
        local id = ItemID(item.link)
        if id then
            copies[id] = copies[id] or {}
            table.insert(copies[id], { link = item.link, seconds = item.secondsLeft, item = item })
        end
    end
    local ledger = addon.db and addon.db.itemStorage and Storage:GetAll(Storage.TO_TRADE)
    for entry, copy in pairs(Pair(ledger, copies)) do
        copy.item.owed = true
        copy.item.owedTo = entry.args and entry.args.recipient
    end

    return found
end






function Storage:WatchForItem(link, onFound, attempts, interval)
    attempts = attempts or 5
    interval = interval or 1

    local tries = 0
    local function poll()
        tries = tries + 1
        local bag, slot, secondsLeft = Storage:FindInBags(link)
        if bag then
            onFound(bag, slot, secondsLeft)
            return
        end
        if tries < attempts then
            C_Timer.After(interval, poll)
        else
            addon.Log:D("Storage", "gave up finding in bags", link)
            onFound(nil)
        end
    end
    C_Timer.After(interval, poll)
end





function Storage:Add(link, category, args)
    local entry = {
        id = ("%d-%d"):format(GetServerTime(), math.random(1000, 9999)),
        link = link,
        category = category,
        addedAt = time(),
        args = args or {},
    }

    local bag, _, secondsLeft = Storage:FindInBags(link)
    if bag then


        entry.secondsLeft = secondsLeft
        entry.updatedAt = time()
    end




    local id = ItemID(link)
    local owed = 0
    for _, other in ipairs(addon.db.itemStorage) do

        if not other.missingAtAdd and not other.untradeable
            and ItemID(other.link) == id then
            owed = owed + 1
        end
    end
    local held = Storage:CountInBags(link)
    if owed >= held then
        entry.missingAtAdd = true
        addon.Log:W("Storage", "owed but not held", link,
            ("%d already owed, %d held"):format(owed, held))
    end

    addon.db.itemStorage[#addon.db.itemStorage + 1] = entry
    addon.Log:I("Storage", "stored", category, link)

    if addon.Callbacks then addon.Callbacks:Fire("StorageChanged") end
    return entry
end

function Storage:Remove(id)
    for i, entry in ipairs(addon.db.itemStorage) do
        if entry.id == id then
            table.remove(addon.db.itemStorage, i)
            addon.Log:I("Storage", "removed", entry.link)
            if addon.Callbacks then addon.Callbacks:Fire("StorageChanged") end
            return true
        end
    end
    return false
end



function Storage:MarkUntradeable(entry, why, to)
    if not entry or entry.untradeable then return false end
    entry.untradeable = why
    entry.untradeableTo = to
    entry.untradeableAt = time()
    addon.Log:I("Storage", "no longer tradeable -", why, entry.link, "owed to",
        tostring(entry.args and entry.args.recipient),
        to and ("handed to " .. tostring(to)) or "")
    if addon.Callbacks then addon.Callbacks:Fire("StorageChanged") end
    return true
end

function Storage:GetAll(category)
    local out = {}
    for _, entry in ipairs(addon.db.itemStorage) do
        if not category or entry.category == category then
            out[#out + 1] = entry
        end
    end
    return out
end


function Storage:TimeRemaining(entry)
    local bag, slot = Storage:FindInBags(entry.link)
    if bag then
        local secondsLeft = Storage:GetSlotTradeInfo(bag, slot)
        if secondsLeft then return secondsLeft end
    end

    if entry.secondsLeft and entry.updatedAt then

        return math.max(0, entry.secondsLeft - (time() - entry.updatedAt))
    end
    return nil
end





function Storage:Clocks(entries)
    local clocks, byId = {}, {}
    for _, entry in ipairs(entries or {}) do
        local id = not entry.untradeable and ItemID(entry.link)
        if id then byId[id] = true end
    end
    if next(byId) == nil then return clocks end

    local copies = {}
    for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = C_Container.GetContainerItemLink(bag, slot)
            local id = ItemID(link)
            if id and byId[id] then
                local secondsLeft = Storage:GetSlotTradeInfo(bag, slot)
                if secondsLeft and secondsLeft > 0 then
                    copies[id] = copies[id] or {}
                    table.insert(copies[id], { link = link, seconds = secondsLeft })
                end
            end
        end
    end

    local paired = Pair(entries, copies)
    for _, entry in ipairs(entries) do
        if not entry.untradeable and ItemID(entry.link) then
            local copy = paired[entry]
            if copy then
                clocks[entry] = copy.seconds
            elseif entry.secondsLeft and entry.updatedAt then
                clocks[entry] = math.max(0, entry.secondsLeft - (time() - entry.updatedAt))
            end
        end
    end
    return clocks
end








Storage.TRADE_EVIDENCE_SECONDS = 20




local handedAway = {}

function Storage:NoteHandedAway(link, to)
    local id = ItemID(link)
    if not id or not to then return end
    handedAway[id] = { to = to, at = time() }
end


local function HandedToOther(id, recipient)
    local handed = handedAway[id]
    if not handed or time() - handed.at > Storage.TRADE_EVIDENCE_SECONDS then
        return nil
    end
    if addon.Player and addon.Player:IsSame(handed.to, recipient) then return nil end
    return handed.to
end

function Storage:Reconcile(reason, timeOnly)


    local totalSlots = 0
    for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        totalSlots = totalSlots + (C_Container.GetContainerNumSlots(bag) or 0)
    end
    if totalSlots == 0 and not timeOnly then
        addon.Log:WLogOnly("Storage", "bags not readable - skipping reconcile,",
            #addon.db.itemStorage, "entries kept")
        return {}, {}
    end

    local budget = {}
    local boundCopies = {}
    local drop = {}
    local marked = {}
    local changed = false

    for i = 1, #addon.db.itemStorage do
        local entry = addon.db.itemStorage[i]
        local id = entry.link and ItemID(entry.link)

        if entry.untradeable then


        elseif not entry.link or not id then
            drop[i] = "unusable"
        else
            local remaining = Storage:TimeRemaining(entry)
            if remaining and remaining <= 0 then


                drop[i] = "expired"
            elseif not timeOnly then
                if budget[id] == nil then
                    budget[id], boundCopies[id] = Storage:CountTradeable(entry.link)
                end
                local handedTo = not entry.missingAtAdd
                    and HandedToOther(id, entry.args and entry.args.recipient)
                if budget[id] > 0 then
                    budget[id] = budget[id] - 1
                    if entry.missingAtAdd then


                        entry.missingAtAdd = nil
                        changed = true
                        addon.Log:I("Storage", "owed item turned up", entry.link)
                    end
                elseif entry.tradeSeen and not entry.missingAtAdd and not handedTo
                    and time() - entry.tradeSeen <= Storage.TRADE_EVIDENCE_SECONDS then


                    drop[i] = "gone"
                else


                    if entry.missingAtAdd then
                        entry.untradeable = "missing"
                    elseif handedTo then
                        entry.untradeable = "wrong"
                        entry.untradeableTo = handedTo
                    elseif Storage:IsEquipped(entry.link) then
                        entry.untradeable = "equipped"
                    elseif boundCopies[id] > 0 then
                        entry.untradeable = "bound"
                    else
                        entry.untradeable = "left"
                    end
                    entry.untradeableAt = time()
                    marked[#marked + 1] = entry
                    addon.Log:I("Storage", "no longer tradeable -", entry.untradeable,
                        entry.link, "owed to", tostring(entry.args and entry.args.recipient))
                end
            end


        end
    end

    local removed = {}
    for i = #addon.db.itemStorage, 1, -1 do
        if drop[i] then
            local entry = addon.db.itemStorage[i]

            entry.dropped = drop[i]
            removed[#removed + 1] = entry
            table.remove(addon.db.itemStorage, i)
        end
    end

    if #removed > 0 then
        addon.Log:I("Storage", "reconciled", tostring(reason), "-", #removed,
            "entries dropped,", #addon.db.itemStorage, "kept")
        for _, entry in ipairs(removed) do
            addon.Log:D("Storage", "dropped", entry.dropped, entry.link,
                "owed to", tostring(entry.args and entry.args.recipient))
        end
    end
    if (#removed > 0 or #marked > 0 or changed) and addon.Callbacks then
        addon.Callbacks:Fire("StorageChanged")
    end

    return removed, marked
end

function Storage:Init()
    addon.db.itemStorage = addon.db.itemStorage or {}


    local removed = Storage:Reconcile("login", true)

    addon.Log:I("Storage", "ready", #addon.db.itemStorage, "held,",
        #removed, "expired")
end
