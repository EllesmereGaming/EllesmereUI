if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Storage = {}
addon.Storage = Storage



Storage.TO_TRADE = "to_trade"
Storage.AWARD_LATER = "award_later"
Storage.KEPT = "kept"

Storage.UNTRADEABLE_KEEP = 24 * 60 * 60
Storage.TRADE_WINDOW = 2 * 60 * 60







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



local function LinkIfId(bag, slot, wanted)
    if C_Container.GetContainerItemID(bag, slot) ~= wanted then return nil end
    local link = C_Container.GetContainerItemLink(bag, slot)
    if ItemID(link) == wanted then return link end
    return nil
end



function Storage:FindInBags(link, skip)
    local function Skipped(bag, slot)
        if not skip then return false end
        for _, entry in ipairs(skip) do
            if entry.bag == bag and entry.slot == slot then return true end
        end
        return false
    end

    local wanted = ItemID(link)



    local candidates
    if wanted then
        candidates = {}
        for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
            local slots = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, slots do
                local present = LinkIfId(bag, slot, wanted)
                if present then candidates[#candidates + 1] = { bag, slot, present } end
            end
        end
        if #candidates == 0 then return nil end
    end

    local function Scan(matches)
        local best
        local function Consider(bag, slot, present)
            if Skipped(bag, slot) or not matches(present) then return nil end
            local secondsLeft = Storage:GetSlotTradeInfo(bag, slot)

            if secondsLeft and secondsLeft > 0 then return secondsLeft end
            best = best or { bag = bag, slot = slot, link = present }
            return nil
        end
        if candidates then
            for _, c in ipairs(candidates) do
                local secondsLeft = Consider(c[1], c[2], c[3])
                if secondsLeft then return c[1], c[2], secondsLeft, c[3] end
            end
        else
            for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
                local slots = C_Container.GetContainerNumSlots(bag) or 0
                for slot = 1, slots do
                    local present = C_Container.GetContainerItemLink(bag, slot)
                    local secondsLeft = Consider(bag, slot, present)
                    if secondsLeft then return bag, slot, secondsLeft, present end
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
            if LinkIfId(bag, slot, wanted) then count = count + 1 end
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
            if LinkIfId(bag, slot, wanted) then
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



local slotLocation
local function SlotFacts(bag, slot)
    if ItemLocation and C_Item and C_Item.IsBound then
        slotLocation = slotLocation or ItemLocation:CreateEmpty()
        slotLocation:SetBagAndSlot(bag, slot)
        if not C_Item.DoesItemExist(slotLocation) then return nil end
        return C_Item.IsBound(slotLocation), C_Item.GetItemQuality(slotLocation), slotLocation
    end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.isBound, info.quality end
end


local function IsEpicBoE(bag, slot, bonding)
    if bonding ~= Enum.TooltipDataItemBinding.BindOnEquip then return false end
    local bound, quality = SlotFacts(bag, slot)
    return quality == Enum.ItemQuality.Epic and not bound
end




local timeless = {}
local TIMELESS_TTL, TIMELESS_SPREAD = 300, 60
local SOULBOUND_TTL, SOULBOUND_SPREAD = 3600, 600


local function PruneTimeless()
    local now = GetTime()
    for guid, reading in pairs(timeless) do
        if now > reading.expires then timeless[guid] = nil end
    end
end



local KEPT_TTL, KEPT_MAX = 7 * 86400, 600


local function Settled(bonding)
    local bind = Enum.TooltipDataItemBinding
    return bonding ~= nil and (bonding == bind.Soulbound or bonding == bind.Account
        or bonding == bind.BnetAccount)
end

function Storage:KeepReading(guid, reading)
    local db = addon.db
    if not db then return end
    if type(db.bagReadings) ~= "table" then db.bagReadings = {} end
    local store, n = db.bagReadings, 0
    for _ in pairs(store) do n = n + 1 end
    if n >= KEPT_MAX then wipe(store) end
    store[guid] = { link = reading.link, bound = reading.bound, bonding = reading.bonding,
        at = GetServerTime() }
end


function Storage:ResumeReading(guid, link, bound)
    local store = addon.db and addon.db.bagReadings
    local saved = type(store) == "table" and store[guid]
    if type(saved) ~= "table" then return nil end
    if type(saved.at) ~= "number" or GetServerTime() - saved.at > KEPT_TTL then
        store[guid] = nil
        return nil
    end
    if saved.link ~= link or saved.bound ~= bound
        or not Settled(saved.bonding) then
        return nil
    end
    local reading = { link = link, bound = bound, bonding = saved.bonding,
        expires = GetTime() + SOULBOUND_TTL - math.random() * SOULBOUND_SPREAD }
    timeless[guid] = reading
    return reading
end



local function ReadSlot(bag, slot, link)
    local bound, quality, location = SlotFacts(bag, slot)
    if bound == false and quality and quality < Enum.ItemQuality.Epic then
        return nil, nil
    end
    local guid = location and C_Item.GetItemGUID(location)
    local kept = guid and timeless[guid]
    if guid and (not kept or GetTime() > kept.expires) then
        kept = Storage:ResumeReading(guid, link, bound) or kept
    end
    local same = kept and kept.link == link and kept.bound == bound
    if same and GetTime() <= kept.expires then
        return nil, kept.bonding
    end
    local secondsLeft, bonding = Storage:GetSlotTradeInfo(bag, slot)
    if guid and secondsLeft == nil and bonding ~= nil then


        local soulbound = Settled(bonding)
            and same and kept.bonding == bonding
        timeless[guid] = { link = link, bound = bound, bonding = bonding,
            expires = GetTime() + (soulbound and SOULBOUND_TTL or TIMELESS_TTL)
                - math.random() * (soulbound and SOULBOUND_SPREAD or TIMELESS_SPREAD) }
        if soulbound then Storage:KeepReading(guid, timeless[guid]) end
    end
    return secondsLeft, bonding
end



local slotCache, dirtyBags = {}, nil


function Storage:InvalidateBags(bag)
    if bag == nil then
        dirtyBags = nil
        wipe(slotCache)
    elseif dirtyBags then
        dirtyBags[bag] = true
    end
end


local function RefreshBag(bag)
    local cached = slotCache[bag] or {}
    local fresh = { n = C_Container.GetContainerNumSlots(bag) or 0 }
    for slot = 1, fresh.n do
        local link = C_Container.GetContainerItemLink(bag, slot)
        if link then
            local old = cached[slot]
            if old and old.link == link then
                fresh[slot] = old
            else
                local seconds, bonding = ReadSlot(bag, slot, link)
                fresh[slot] = { link = link, seconds = seconds, bonding = bonding,
                    at = GetTime() }
            end
        end
    end
    slotCache[bag] = fresh
    return fresh
end


local sharedScan, sharing = nil, false

local function CopyReadings(list)
    local out = {}
    for i, item in ipairs(list) do
        out[i] = { link = item.link, bag = item.bag, slot = item.slot,
            secondsLeft = item.secondsLeft, eligible = item.eligible, boe = item.boe }
    end
    return out
end



function Storage:ShareLiveScan(fn)
    if sharing then return fn() end
    sharing = true
    local ok, err = pcall(fn)
    sharing, sharedScan = false, nil
    if not ok then error(err, 0) end
end


local function Scan(cached)
    local found = {}
    for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local readings
        if cached then
            readings = (dirtyBags and not dirtyBags[bag] and slotCache[bag]) or RefreshBag(bag)
        end
        for slot = 1, readings and readings.n or C_Container.GetContainerNumSlots(bag) or 0 do
            local link, secondsLeft, bonding
            if readings then
                local reading = readings[slot]
                if reading then
                    link, bonding = reading.link, reading.bonding
                    secondsLeft = reading.seconds and reading.seconds - (GetTime() - reading.at)
                end
            else
                link = C_Container.GetContainerItemLink(bag, slot)
                if link then secondsLeft, bonding = ReadSlot(bag, slot, link) end
            end
            if link and secondsLeft and secondsLeft > 0 then
                found[#found + 1] = {
                    link = link,
                    bag = bag,
                    slot = slot,
                    secondsLeft = secondsLeft,

                    eligible = addon.Loot and addon.Loot:IsCouncilItem(link) or false,
                }
            elseif link and IsEpicBoE(bag, slot, bonding) then

                found[#found + 1] = {
                    link = link, bag = bag, slot = slot, boe = true, eligible = true,
                }
            end
        end
    end
    if cached then dirtyBags = {} else PruneTimeless() end
    return found
end





function Storage:GetTradeableItems(cached)
    local found
    if cached then
        found = Scan(true)
    elseif sharedScan then
        found = CopyReadings(sharedScan)
    else
        found = Scan(false)
        if sharing then sharedScan = CopyReadings(found) end
    end

    table.sort(found, function(a, b)
        if (a.boe or false) ~= (b.boe or false) then return b.boe or false end
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
            table.insert(copies[id], { link = item.link, seconds = item.secondsLeft or math.huge,
                item = item })
        end
    end
    local ledger = addon.db and addon.db.itemStorage and Storage:GetHeld()
    for entry, copy in pairs(Pair(ledger, copies)) do
        copy.item.owed = true
        copy.item.owedTo = entry.args and entry.args.recipient
        if entry.category == Storage.KEPT then copy.item.kept = true end
    end


    local unowed = {}
    for id, list in pairs(copies) do
        for _, copy in ipairs(list) do
            if not copy.item.owed then
                unowed[id] = unowed[id] or {}
                table.insert(unowed[id], copy)
            end
        end
    end
    for _, copy in pairs(Pair(Storage:GetWon(), unowed)) do
        copy.item.won = true
    end

    return found
end







local WON_TTL = 2 * 60 * 60
local WON_MAX = 64
local wonListening = false

function Storage:GetWon()
    local store = addon.db and addon.db.wonCopies
    if type(store) ~= "table" then return {} end
    local now = GetServerTime()
    for i = #store, 1, -1 do
        local entry = store[i]
        if type(entry) ~= "table" or type(entry.link) ~= "string"
            or type(entry.addedAt) ~= "number" or now - entry.addedAt > WON_TTL then
            table.remove(store, i)
        end
    end
    return store
end

function Storage:RecordWon(link)
    if type(link) ~= "string" or not addon.db then return end
    if type(addon.db.wonCopies) ~= "table" then addon.db.wonCopies = {} end
    local store = addon.db.wonCopies
    if #store >= WON_MAX then table.remove(store, 1) end
    store[#store + 1] = { link = link, addedAt = GetServerTime() }
    addon.Log:D("Storage", "won copy recorded", link)
end







local watches, watchFrame = {}, nil

local function Settle(watch, bag, slot, secondsLeft)
    if watch.done then return end
    watch.done = true
    for i, other in ipairs(watches) do
        if other == watch then table.remove(watches, i) break end
    end
    if #watches == 0 and watchFrame then watchFrame:UnregisterEvent("BAG_UPDATE_DELAYED") end
    watch.onFound(bag, slot, secondsLeft)
end

local function CheckWatches()
    for i = #watches, 1, -1 do
        local watch = watches[i]
        local bag, slot, secondsLeft = Storage:FindInBags(watch.link)
        if bag then Settle(watch, bag, slot, secondsLeft) end
    end
end

function Storage:WatchForItem(link, onFound, attempts, interval)
    local watch = { link = link, onFound = onFound }
    local bag, slot, secondsLeft = Storage:FindInBags(link)
    if bag then
        Settle(watch, bag, slot, secondsLeft)
        return
    end
    if not watchFrame then
        watchFrame = CreateFrame("Frame")
        watchFrame:SetScript("OnEvent", function() if #watches > 0 then CheckWatches() end end)
    end
    watches[#watches + 1] = watch
    watchFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    C_Timer.After((attempts or 5) * (interval or 1), function()
        if watch.done then return end
        local found, foundSlot, foundSeconds = Storage:FindInBags(link)
        if not found then addon.Log:D("Storage", "gave up finding in bags", link) end
        Settle(watch, found, foundSlot, foundSeconds)
    end)
end





local function NextEntryId()
    local db = addon.db
    local seq = (type(db.storageSeq) == "number" and db.storageSeq or 0) + 1
    local stamp = GetServerTime()
    local id = ("%d-%d"):format(stamp, seq)
    local taken = true
    while taken do
        taken = false
        for _, other in ipairs(db.itemStorage) do
            if other.id == id then
                taken = true
                seq = seq + 1
                id = ("%d-%d"):format(stamp, seq)
                break
            end
        end
    end
    db.storageSeq = seq
    return id
end

function Storage:Add(link, category, args)
    local entry = {
        id = NextEntryId(),
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


function Storage:GetHeld()
    local out = {}
    for _, entry in ipairs(addon.db.itemStorage) do
        if entry.category == Storage.TO_TRADE or entry.category == Storage.KEPT then
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
            local id = C_Container.GetContainerItemID(bag, slot)
            local link = id and byId[id] and C_Container.GetContainerItemLink(bag, slot)
            if link and ItemID(link) == id then
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

local function RecordedClock(entry, now)
    if entry.secondsLeft and entry.updatedAt then
        return math.max(0, entry.secondsLeft - ((now or time()) - entry.updatedAt))
    end
    return nil
end


local function Aged(entry, now)
    local since = entry.untradeableAt or entry.addedAt
    return type(since) == "number" and now - since > Storage.UNTRADEABLE_KEEP
end


local function InTradeWindow(entry, now)
    local left = RecordedClock(entry, now)
    if left then return left > 0 end
    return type(entry.addedAt) == "number" and now - entry.addedAt < Storage.TRADE_WINDOW
end



local function ScanHeld(entries)
    local wanted = {}
    for _, entry in ipairs(entries) do
        local id = entry.link and ItemID(entry.link)
        if id then wanted[id] = true end
    end
    local soulbound = Enum.TooltipDataItemBinding.Soulbound
    local copies, counts, totalSlots = {}, {}, 0
    for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        totalSlots = totalSlots + slots
        for slot = 1, slots do
            local id = C_Container.GetContainerItemID(bag, slot)
            local link = id and wanted[id] and C_Container.GetContainerItemLink(bag, slot)
            if link and ItemID(link) == id then
                local secondsLeft, bonding = Storage:GetSlotTradeInfo(bag, slot)
                local count = counts[id]
                if not count then
                    count = { tradeable = 0, bound = 0 }
                    counts[id] = count
                end
                if not (secondsLeft and secondsLeft > 0) and bonding == soulbound then
                    count.bound = count.bound + 1
                else
                    count.tradeable = count.tradeable + 1
                end
                if secondsLeft and secondsLeft > 0 then
                    copies[id] = copies[id] or {}
                    table.insert(copies[id], { link = link, seconds = secondsLeft })
                end
            end
        end
    end
    return copies, counts, totalSlots
end

function Storage:Reconcile(reason)
    local list = addon.db.itemStorage
    local copies, counts, totalSlots = ScanHeld(list)
    if totalSlots == 0 then
        addon.Log:WLogOnly("Storage", "bags not readable - skipping reconcile,",
            #list, "entries kept")
        return {}, {}
    end

    local budget, boundCopies = {}, {}
    for id, count in pairs(counts) do
        budget[id], boundCopies[id] = count.tradeable, count.bound
    end
    local paired = Pair(list, copies)
    local now = time()
    local function Remaining(entry)
        local copy = paired[entry]
        if copy then return copy.seconds end
        return RecordedClock(entry, now)
    end

    local drop = {}
    local marked = {}
    local changed = false

    for i = 1, #list do
        local entry = list[i]
        local id = entry.link and ItemID(entry.link)

        if entry.untradeable then


            if Aged(entry, now) then drop[i] = "aged" end
        elseif not entry.link or not id then
            drop[i] = "unusable"
        elseif entry.category == Storage.TO_TRADE then
            local remaining = Remaining(entry)
            local expired = remaining ~= nil and remaining <= 0
            local handedTo = not expired and not entry.missingAtAdd
                and HandedToOther(id, entry.args and entry.args.recipient)
            if not expired and (budget[id] or 0) > 0 then
                budget[id] = budget[id] - 1
                if entry.missingAtAdd then


                    entry.missingAtAdd = nil
                    changed = true
                    addon.Log:I("Storage", "owed item turned up", entry.link)
                end
            elseif not expired and entry.tradeSeen and not entry.missingAtAdd and not handedTo
                and now - entry.tradeSeen <= Storage.TRADE_EVIDENCE_SECONDS then


                drop[i] = "gone"
            else



                if expired then
                    entry.untradeable = Storage:IsEquipped(entry.link) and "equipped"
                        or entry.missingAtAdd and "missing"
                        or (boundCopies[id] or 0) > 0 and "bound" or "left"
                elseif entry.missingAtAdd then
                    entry.untradeable = "missing"
                elseif handedTo then
                    entry.untradeable = "wrong"
                    entry.untradeableTo = handedTo
                elseif Storage:IsEquipped(entry.link) then
                    entry.untradeable = "equipped"
                elseif (boundCopies[id] or 0) > 0 then
                    entry.untradeable = "bound"
                else
                    entry.untradeable = "left"
                end
                entry.untradeableAt = now
                marked[#marked + 1] = entry
                addon.Log:I("Storage", "no longer tradeable -", entry.untradeable,
                    entry.link, "owed to", tostring(entry.args and entry.args.recipient))
            end
        end
    end
    for i = 1, #list do
        local entry = list[i]
        if not drop[i] and not entry.untradeable and entry.category ~= Storage.TO_TRADE then
            local id = ItemID(entry.link)
            local remaining = Remaining(entry)
            if remaining and remaining <= 0 then
                drop[i] = "expired"
            elseif (budget[id] or 0) > 0 then
                budget[id] = budget[id] - 1
                if entry.missingAtAdd then
                    entry.missingAtAdd = nil
                    changed = true
                end
            else
                drop[i] = "gone"
            end
        end
    end
    for i = 1, #list do
        local entry = list[i]
        local why = entry.untradeable
        if not drop[i] and (why == "missing" or why == "left")
            and entry.category == Storage.TO_TRADE then
            local id = ItemID(entry.link)
            if id and (budget[id] or 0) > 0 and InTradeWindow(entry, now) then
                budget[id] = budget[id] - 1
                entry.untradeable, entry.untradeableTo, entry.untradeableAt = nil, nil, nil
                entry.missingAtAdd = nil
                changed = true
                addon.Log:I("Storage", "owed item is back in the bags -", why, entry.link,
                    "owed to", tostring(entry.args and entry.args.recipient))
            end
        end
    end

    local removed = {}
    for i = #list, 1, -1 do
        if drop[i] then
            local entry = list[i]

            entry.dropped = drop[i]
            removed[#removed + 1] = entry
            table.remove(list, i)
        end
    end

    if #removed > 0 then
        addon.Log:I("Storage", "reconciled", tostring(reason), "-", #removed,
            "entries dropped,", #list, "kept")
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



local function LoginPrune()
    local list = addon.db.itemStorage
    local now = time()
    local expired = 0
    for i = #list, 1, -1 do
        local entry = list[i]
        local id = type(entry) == "table" and entry.link and ItemID(entry.link)
        local why
        if type(entry) ~= "table" then
            why = "unusable"
        elseif entry.untradeable then
            if Aged(entry, now) then why = "aged" end
        elseif not id then
            why = "unusable"
        elseif entry.category ~= Storage.TO_TRADE then
            local remaining = RecordedClock(entry, now)
            if remaining and remaining <= 0 then why = "expired" end
        end
        if why then
            table.remove(list, i)
            expired = expired + 1
            if type(entry) == "table" then
                entry.dropped = why
                addon.Log:D("Storage", "dropped", why, entry.link, "owed to",
                    tostring(entry.args and entry.args.recipient))
            end
        end
    end
    addon.Log:I("Storage", "ready", #list, "held,", expired, "dropped")
    if expired > 0 and addon.Callbacks then addon.Callbacks:Fire("StorageChanged") end
end

function Storage:Init()
    addon.db.itemStorage = addon.db.itemStorage or {}


    C_Timer.After(0, LoginPrune)


    if wonListening then return end
    wonListening = true
    addon.Callbacks:Register("ItemDelivered", function(_, winner, item)
        if type(item) == "table" and not item.simulated and winner
            and addon.Player:IsSelf(winner) then
            Storage:RecordWon(item.link)
        end
    end)
end
