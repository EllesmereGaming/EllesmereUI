if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end





SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Trade = {}
addon.Trade = Trade

local issecretvalue = issecretvalue



local function UsableTradeSlots()
    return (MAX_TRADE_ITEMS or 7) - 1
end


local lastAttemptedTarget

local inTrade = false
local staged = {}
local snapshot = nil



local windowRecipient



local stagedBefore = {}



local tradeSession = 0



local confirmPending = 0


local fill


local HELD_KINDS = { addon.Storage.TO_TRADE, addon.Storage.KEPT }


local function SameObligation(entry, runId, session)
    local args = entry and entry.args
    return args and args.runId == runId and args.session == session
end

local function RemoveObligation(runId, session, why)
    for _, kind in ipairs(HELD_KINDS) do
        for _, entry in ipairs(addon.Storage:GetAll(kind)) do
            if SameObligation(entry, runId, session) then
                addon.Storage:Remove(entry.id)
                addon.Log:I("Trade", why or "obligation replaced", entry.link)
            end
        end
    end
end



local HANDED_MAX_AGE = 6 * 60 * 60

local function HandedKey(runId, session)
    return tostring(runId) .. "|" .. tostring(session)
end

local function HandedStore()
    if not addon.db then return {} end
    if type(addon.db.tradeHanded) ~= "table" then addon.db.tradeHanded = {} end
    return addon.db.tradeHanded
end

local function NoteHanded(session, winner, link, runId)
    if not runId or not session or not winner then return end
    local store = HandedStore()
    local now = GetServerTime()
    for key, record in pairs(store) do
        if type(record) ~= "table" or type(record.at) ~= "number"
            or now - record.at > HANDED_MAX_AGE then
            store[key] = nil
        end
    end
    store[HandedKey(runId, session)] = { s = session, w = winner, l = link, i = runId, at = now }
end


local function Deliver(session, winner, link, runId)
    addon.Comms:Send("delivered", {
        s = session, w = winner, l = link, i = runId,
    }, nil, true)
    NoteHanded(session, winner, link, runId)
    addon.Session:ApplyDelivered(session, winner,
        addon.Player:GetFullName("player"), link, runId)
end







local function TradeTarget()


    local name, realm

    if addon.IsForever then name = addon.Player:GetFullName("NPC") end
    if not name and TradeFrameRecipientNameText then
        name = TradeFrameRecipientNameText:GetText()
        if issecretvalue and issecretvalue(name) then name = nil end
    end

    if not name or name == "" then

        name, realm = UnitName("NPC")
        if issecretvalue and (issecretvalue(name) or issecretvalue(realm)) then
            name, realm = nil, nil
        end
        name, realm = addon.Player.UnitNameParts(name, realm)
        if name and realm and realm ~= "" and not name:find("-", 1, true) then
            name = name .. "-" .. realm
        end
    end

    if not name or name == "" then
        if lastAttemptedTarget then
            addon.Log:W("Trade", "falling back to last attempted target")
            return lastAttemptedTarget, true
        end
        addon.Log:E("Trade", "cannot identify trade target")
        return nil
    end


    name = name:gsub("%s*%(%*%)$", "")
    local record = addon.Player:Get(name)
    return record.fullName or name
end







function Trade:GetOwedTo(recipient)
    local out = {}
    for _, entry in ipairs(addon.Storage:GetAll(addon.Storage.TO_TRADE)) do
        if not entry.untradeable and entry.args and entry.args.recipient
            and addon.Player:IsSame(entry.args.recipient, recipient) then
            out[#out + 1] = entry
        end
    end
    return out
end





local function PlaceOne(entry, index)


    local bag, slot = addon.Storage:FindInBags(entry.link, staged)
    if not bag then
        addon.Log:W("Trade", "no longer in bags", entry.link)
        return false, "gone"
    end


    local present = C_Container.GetContainerItemLink(bag, slot)
    if addon.Storage.ItemID(present) ~= addon.Storage.ItemID(entry.link) then
        addon.Log:W("Trade", "slot contents changed under us", entry.link)
        return false
    end

    ClearCursor()
    C_Container.PickupContainerItem(bag, slot)
    ClickTradeButton(index)
    ClearCursor()

    staged[#staged + 1] = { bag = bag, slot = slot, link = entry.link, entry = entry }

    local id = addon.Storage.ItemID(entry.link) or entry.link
    if stagedBefore[id] == nil then
        stagedBefore[id] = addon.Storage:CountInBags(entry.link)
    end

    addon.Log:D("Trade", "placed", entry.link, "in slot", index)
    return true
end



local function Placeable(owed)
    local taken, out = {}, {}
    for _, entry in ipairs(owed) do
        local bag, slot = addon.Storage:FindInBags(entry.link, taken)
        if bag then
            taken[#taken + 1] = { bag = bag, slot = slot }
            out[#out + 1] = entry
        end
    end
    return out
end


local FILL_PACE = 0.2
local FILL_SETTLE = 1
local FILL_TRIES = 3
local FillStep

local function EndFill(state)
    if fill == state then fill = nil end
end

local function FillSoon(state, delay, fn)
    C_Timer.After(delay, function()
        if fill == state then fn(state) end
    end)
end

local function FreeTradeSlot(state)
    for index = 1, UsableTradeSlots() do
        if not state.reserved[index] and not GetTradePlayerItemLink(index) then return index end
    end
    return nil
end

local function Holds(index, entry)
    local link = index and GetTradePlayerItemLink(index)
    if not link then return false end
    if addon.Storage.ItemsMatch(link, entry.link) then return true end
    local id = addon.Storage.ItemID(link)
    return id ~= nil and id == addon.Storage.ItemID(entry.link)
end

local function Unstage(entry)
    for i = #staged, 1, -1 do
        if staged[i].entry == entry then table.remove(staged, i) end
    end
end

local function FinishFill(state)
    EndFill(state)
    local placed, missing = 0, 0
    for _, entry in ipairs(state.owed) do
        if Holds(state.slotOf[entry], entry) then
            placed = placed + 1
        elseif not state.gone[entry] then
            missing = missing + 1
        end
    end
    addon.Log:I("Trade", "filled", placed, "of", #state.owed, "items")
    if missing > 0 then
        addon.Chat.Warn(addon.Locale.Format(addon.Locale.Plural{
            one = "%d owed item did not go into the trade window - add it by hand.",
            other = "%d owed items did not go into the trade window - add them by hand.",
        }, missing, missing))
    end
end

local function FillCheck(state)
    if not inTrade or state.session ~= tradeSession then
        EndFill(state)
        return
    end
    local again = false
    for _, entry in ipairs(state.owed) do
        local index = state.slotOf[entry]
        if not state.gone[entry] and not state.full[entry] and not Holds(index, entry) then
            if index then
                state.reserved[index], state.slotOf[entry] = nil, nil
                Unstage(entry)
            end
            if (state.tries[entry] or 0) < FILL_TRIES then
                addon.Log:W("Trade", "the trade dropped", entry.link, "- placing it again")
                state.queue[#state.queue + 1] = entry
                again = true
            end
        end
    end
    if again then
        state.pace = state.pace * 2
        FillStep(state)
    else
        FinishFill(state)
    end
end

FillStep = function(state)
    if not inTrade or state.session ~= tradeSession then
        EndFill(state)
        return
    end
    local entry = table.remove(state.queue, 1)
    if not entry then
        FillSoon(state, FILL_SETTLE, FillCheck)
        return
    end
    local index = FreeTradeSlot(state)
    if not index then
        addon.Log:W("Trade", "no free trade slot for", entry.link)
        state.full[entry] = true
    else
        state.tries[entry] = (state.tries[entry] or 0) + 1
        Trade:SuppressTransmogWarning(state.pace + FILL_SETTLE + 1)
        local placed, why = PlaceOne(entry, index)
        if placed then
            state.slotOf[entry], state.reserved[index] = index, true
        elseif why == "gone" then
            state.gone[entry] = true
        end
    end
    FillSoon(state, state.pace, FillStep)
end

function Trade:FillWindow(recipient, owed)
    owed = owed or Placeable(Trade:GetOwedTo(recipient))
    if #owed == 0 then return 0 end

    local limit = math.min(#owed, UsableTradeSlots())
    local list, queue = {}, {}
    for i = 1, limit do list[i], queue[i] = owed[i], owed[i] end

    if fill then EndFill(fill) end
    local state = {
        session = tradeSession, owed = list, queue = queue, pace = FILL_PACE,
        tries = {}, slotOf = {}, reserved = {}, gone = {}, full = {},
    }
    fill = state

    Trade:SuppressTransmogWarning(FILL_PACE + FILL_SETTLE + 1)
    FillSoon(state, 0.1, FillStep)

    addon.Log:I("Trade", "filling", limit, "items for", tostring(recipient))
    return limit
end








local suppressUntil = 0

function Trade:SuppressTransmogWarning(seconds)
    if not (addon.db and addon.db.suppressTradeWarnings) then return end
    suppressUntil = math.max(suppressUntil, GetTime() + (seconds or 2))
end


local function PadGamepadStyle()
    if addon.EDITION ~= "eui" then return false end
    local EUI = EllesmereUI
    return type(EUI) == "table" and type(EUI.PadGamepadUI) == "function"
        and EUI.PadGamepadUI() and true or false
end








local UNDELIVERABLE_TEXT = addon.Locale.Texts{
    equipped = {
        master = T["%s was equipped, so it can no longer be traded to %s. Re-award or strike it."],
        other = T["%s was equipped, so it can no longer be traded to %s. The Loot Master has been told."],
    },


    bound = {
        master = T["%s can no longer be traded to %s - its trade window has ended. Re-award or strike it."],
        other = T["%s can no longer be traded to %s - its trade window has ended. The Loot Master has been told."],
    },
    left = {
        master = T["%s left your bags without a trade to %s. Re-award or strike it."],
        other = T["%s left your bags without a trade to %s. The Loot Master has been told."],
    },

    missing = {
        master = T["%s was awarded to %s, but it is not in your bags - there is nothing to trade. Re-award or strike it."],
        other = T["%s was awarded to %s, but it is not in your bags - there is nothing to trade. The Loot Master has been told."],
    },
    wrong = {
        master = T["%s was awarded to %s, but the trade handed it to %s. Re-award it to %s if they may keep it, or strike it."],
        other = T["%s was awarded to %s, but the trade handed it to %s. The Loot Master has been told."],
    },
}

local function ReportUndeliverable(entry)
    local why = entry.untradeable
    local winner = entry.args.recipient
    local to = entry.untradeableTo
    addon.Log:W("Trade", "not delivered -", why, entry.link, "owed to", tostring(winner),
        to and ("handed to " .. tostring(to)) or "")

    local forms = UNDELIVERABLE_TEXT[why] or UNDELIVERABLE_TEXT.left
    local sentence = addon.PlayerIsMasterLooter() and forms.master or forms.other
    local given = Ambiguate(to or "?", "short")
    addon.Chat.Error(addon.Locale.Format(sentence, entry.link,
        Ambiguate(winner or "?", "short"), given, given))
    addon.Comms:Send("undelivered", {
        s = entry.args.session, w = winner, l = entry.link,
        i = entry.args.runId, r = why, t = to,
    }, nil, true)
end



local function ClaimOwed(link, recipient, claimed)
    local owed = addon.Storage:GetAll(addon.Storage.TO_TRADE)
    local id = addon.Storage.ItemID(link)
    for pass = 1, 2 do
        for _, entry in ipairs(owed) do
            local args = entry.args
            if not claimed[entry] and args and args.recipient
                and addon.Player:IsSame(args.recipient, recipient)
                and (pass == 1 and addon.Storage.ItemsMatch(entry.link, link)
                    or pass == 2 and id ~= nil and addon.Storage.ItemID(entry.link) == id) then
                claimed[entry] = true
                return entry
            end
        end
    end
    return nil
end






local function ConfirmDeliveries(recipient, links, before)
    if not links or #links == 0 then return end
    before = before or {}


    local groups, order = {}, {}
    for _, record in ipairs(links) do
        local id = addon.Storage.ItemID(record.link) or record.link
        if not groups[id] then
            groups[id] = {}
            order[#order + 1] = id
        end
        table.insert(groups[id], record)
    end

    local settled = {}
    for _, id in ipairs(order) do
        local group = groups[id]
        local remaining = addon.Storage:CountInBags(group[1].link)
        local delivered = math.max(0, (before[id] or #group) - remaining)

        for index, record in ipairs(group) do
            if index <= delivered then
                settled[record] = true
            else
                addon.Log:I("Trade", "not delivered, still in bags", record.link)
            end
        end

        if delivered < #group then
            addon.Log:D("Trade", "delivered", delivered, "of", #group, "copies")
        end
    end

    local claimed = {}
    for _, record in ipairs(links) do
        if record.entry then claimed[record.entry] = true end
    end

    for _, record in ipairs(links) do
        if settled[record] then
            local entry = record.entry
            if not entry and recipient then
                entry = ClaimOwed(record.link, recipient, claimed)
                if entry then
                    addon.Log:I("Trade", "trade settles an owed entry it did not place",
                        record.link, entry.untradeable and ("was " .. tostring(entry.untradeable)) or "")
                end
            end
            local intended = entry and entry.args and entry.args.recipient

            if intended and recipient
                and not addon.Player:IsSame(intended, recipient) then


                addon.Log:E("Trade", "delivered to the WRONG player", record.link,
                    "intended", tostring(intended), "got", tostring(recipient))
                if entry and addon.Storage:MarkUntradeable(entry, "wrong", recipient)
                    and entry.args.session then
                    ReportUndeliverable(entry)
                end
            else
                addon.Log:I("Trade", "delivered", record.link, "to", tostring(recipient))
                if entry and entry.args and entry.args.session then

                    Deliver(entry.args.session, intended, record.link, entry.args.runId)
                end
                if entry then
                    addon.Storage:Remove(entry.id)
                elseif recipient then


                    addon.Storage:NoteHandedAway(record.link, recipient)
                end
            end
        end
    end
end









local reconcileQueued = false

local seenEntries = {}


local LOGIN_SETTLE_SECONDS = 10

local ReconcileSoon

local function ReconcileAfterCombat()
    reconcileQueued = false
    ReconcileSoon()
end


ReconcileSoon = function()
    if reconcileQueued then return end


    if not addon.db or #(addon.db.itemStorage or {}) == 0 then return end
    reconcileQueued = true



    C_Timer.After(2, function()
        if InCombatLockdown() then
            addon.CombatQueue.Defer("Trade.Reconcile", ReconcileAfterCombat)
            return
        end
        reconcileQueued = false

        if inTrade or confirmPending > 0 then
            addon.Log:D("Trade", "reconcile deferred, trade in flight")
            ReconcileSoon()
            return
        end

        local removed, marked = addon.Storage:Reconcile("bags changed")
        for _, entry in ipairs(removed) do

            if entry.dropped == "gone" and entry.category == addon.Storage.TO_TRADE
                and entry.args and entry.args.session then
                local winner = entry.args.recipient
                addon.Log:I("Trade", "settling by bag check", entry.link,
                    "to", tostring(winner))
                Deliver(entry.args.session, winner, entry.link, entry.args.runId)
            end
        end
        for _, entry in ipairs(marked) do
            if entry.category == addon.Storage.TO_TRADE
                and entry.args and entry.args.session then
                ReportUndeliverable(entry)
            end
        end
    end)
end





local WARN_BELOW = 20 * 60
local lastWarned = 0

local IsSecret = addon.IsSecret

local function CheckExpiring()


    if InCombatLockdown() then
        addon.CombatQueue.Defer("Trade.CheckExpiring", CheckExpiring)
        return
    end
    if GetTime() - lastWarned < 120 then return end

    local warned, due = false, false
    local owed = addon.Storage:GetAll(addon.Storage.TO_TRADE)

    local clocks = addon.Storage:Clocks(owed)
    for _, entry in ipairs(owed) do
        local remaining = clocks[entry]
        if remaining and remaining <= 0 then
            due = true
        elseif remaining and remaining < WARN_BELOW then
            local who = entry.args and entry.args.recipient
            local minutes = math.floor(remaining / 60)
            addon.Chat.Warn(addon.Locale.Format(addon.Locale.Plural{
                one = "%s owed to %s - %d minute left",
                other = "%s owed to %s - %d minutes left",
            }, minutes, entry.link, who and Ambiguate(who, "short") or "?", minutes))
            warned = true
        end
    end
    if warned then lastWarned = GetTime() end


    if due then ReconcileSoon() end
end



local expiryTicker

local function SyncExpiryTicker()
    local owed = #addon.Storage:GetAll(addon.Storage.TO_TRADE) > 0
    if owed and not expiryTicker then
        expiryTicker = C_Timer.NewTicker(300, CheckExpiring)
    elseif not owed and expiryTicker then
        expiryTicker:Cancel()
        expiryTicker = nil
    end
end








local OTHERS_MAX_AGE = 2 * 60 * 60

local function OthersKey(runId, session)
    return tostring(runId) .. "|" .. tostring(session)
end

local function OthersStore()
    if not addon.db then return {} end
    if type(addon.db.owedByOthers) ~= "table" then addon.db.owedByOthers = {} end
    return addon.db.owedByOthers
end

local function OthersChanged()
    if addon.Callbacks then addon.Callbacks:Fire("OwedByOthersChanged") end
end



local function SharedSecondsLeft(holder, link)
    local shared = addon.BagShare and addon.BagShare:Get(holder)
    if not shared or type(shared.items) ~= "table" then return nil end
    local key = addon.BagShare.ItemKey(link)
    local best
    for _, entry in ipairs(shared.items) do
        local left = entry.secondsLeft


        if left and left > 0 and addon.BagShare.ItemKey(entry.link) == key
            and (not best or left < best) then
            best = left
        end
    end
    return best
end


function Trade:OwedByOthers()
    local store = OthersStore()
    local now = GetServerTime()
    local out = {}
    for key, record in pairs(store) do
        local expired = type(record) ~= "table" or not record.at
            or (not record.untradeable and not record.expiresAt
                and now - record.at > OTHERS_MAX_AGE)
            or (record.untradeable and (type(record.untradeableAt) == "number"
                and time() - record.untradeableAt or now - record.at)
                > addon.Storage.UNTRADEABLE_KEEP)
        if expired then
            store[key] = nil
        else
            if record.expiresAt and not record.untradeable and now >= record.expiresAt then


                record.untradeable = "bound"
                record.untradeableAt = time()
                addon.Log:I("Trade", "trade window ended for an award held by",
                    tostring(record.holder), record.link, "owed to", tostring(record.winner))
            end
            record.key = key
            out[#out + 1] = record
        end
    end
    table.sort(out, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.key < b.key
    end)
    return out
end

function Trade:GetOwedByOthers(key)
    local record = key and OthersStore()[key]
    return type(record) == "table" and record or nil
end


function Trade:ForgetOwedByOthers(key)
    local store = OthersStore()
    if not key or not store[key] then return false end
    store[key] = nil
    addon.Log:I("Trade", "stopped tracking an award held by someone else", key)
    OthersChanged()
    return true
end

local function TrackOthers()
    addon.Callbacks:Register("ItemAwarded", function(session, winner, item)
        if not item or item.simulated or not item.owner or not winner then return end
        if addon.Player:IsSelf(item.owner) then return end
        if addon.Player:IsSame(winner, item.owner) then return end
        if not addon.PlayerIsMasterLooter() then return end
        local runId = addon.Session:GetRunId()
        if not runId then return end
        local left = SharedSecondsLeft(item.owner, item.link)
        OthersStore()[OthersKey(runId, session)] = {
            link = item.link, holder = item.owner, winner = winner,
            runId = runId, session = session, at = GetServerTime(),
            expiresAt = left and (GetServerTime() + math.floor(left)) or nil,
        }
        addon.Log:I("Trade", "owed by", tostring(item.owner), item.link,
            "to", tostring(winner))
        OthersChanged()
    end)

    local function ForgetOthers(runId, session, winner, why)
        local key = OthersKey(runId, session)
        local record = OthersStore()[key]
        if not record then return end


        if winner and not addon.Player:IsSame(record.winner, winner) then return end
        OthersStore()[key] = nil
        addon.Log:D("Trade", "no longer owed by", tostring(record.holder), "-", why, record.link)
        OthersChanged()
    end
    addon.Callbacks:Register("ItemUnawarded", function(session, previous, _, runId)
        ForgetOthers(runId or addon.Session:GetRunId(), session, previous, "award moved")
    end)
    addon.Callbacks:Register("ItemDelivered", function(session, winner, _, runId)
        ForgetOthers(runId or addon.Session:GetRunId(), session, winner, "delivered")
    end)
    addon.Callbacks:Register("ItemUndelivered", function(session, winner, _, _, runId, why, to)
        local record = OthersStore()[OthersKey(runId or addon.Session:GetRunId(), session)]
        if not record or not addon.Player:IsSame(record.winner, winner) then return end
        if record.untradeable ~= (why or "left") then record.untradeableAt = time() end
        record.untradeable = why or "left"
        record.untradeableTo = to
        OthersChanged()
    end)
end






function Trade:RangeState(recipient)
    local unit = addon.Player:UnitFor(recipient)
    if not unit then return "unknown" end

    local connected = UnitIsConnected(unit)
    if IsSecret(connected) then return "unknown" end
    if not connected then return "offline" end

    local dead = UnitIsDeadOrGhost(unit)
    if IsSecret(dead) then return "unknown" end
    if dead then return "outOfRange", true end


    if InCombatLockdown() then return "combat" end

    local inRange = CheckInteractDistance(unit, 2)
    if IsSecret(inRange) then return "unknown" end
    return inRange and "inRange" or "outOfRange", false, unit
end

function Trade:RangeBand(state)
    if state == "inRange" then return 1 end
    if state == "outOfRange" then return 2 end
    return 3
end

function Trade:RangeLabel(state, dead, count)
    local Locale = addon.Locale
    if state == "inRange" then
        return Locale.Format(Locale.Plural{ one = "%d item \194\183 in range", other = "%d items \194\183 in range" },
            count, count), "accent"
    end
    if state == "offline" then
        return Locale.Format(Locale.Plural{ one = "%d item \194\183 offline", other = "%d items \194\183 offline" },
            count, count), "textFaint"
    end
    if state == "combat" then
        return Locale.Format(Locale.Plural{ one = "%d item \194\183 combat", other = "%d items \194\183 combat" },
            count, count), "bad"
    end
    if state == "outOfRange" then


        local forms = dead
            and Locale.Plural{ one = "%d item \194\183 out of range (dead)",
                other = "%d items \194\183 out of range (dead)" }
            or Locale.Plural{ one = "%d item \194\183 out of range", other = "%d items \194\183 out of range" }
        return Locale.Format(forms, count, count), "textFaint"
    end
    return Locale.Format(Locale.Plural{ one = "%d item", other = "%d items" },
        count, count), "textMuted"
end


function Trade:SortByRange(groups)
    for index, group in ipairs(groups) do
        group.rangeBand = self:RangeBand(group.rangeState)
        group.rangeOrder = index
    end
    table.sort(groups, function(a, b)
        if a.rangeBand ~= b.rangeBand then return a.rangeBand < b.rangeBand end
        return a.rangeOrder < b.rangeOrder
    end)
    return groups
end

function Trade:Initiate(recipient)
    lastAttemptedTarget = recipient


    local unit = addon.Player:UnitFor(recipient)
    if not unit then
        addon.Chat.Warn(addon.Locale.Format(T["%s is not in your group."],
            Ambiguate(recipient, "short")))
        return false
    end

    InitiateTrade(unit)
    return true
end





local handedTo = {}

local function ForgetSession(runId, session, why)
    for _, entry in ipairs(addon.Storage:GetAll(addon.Storage.TO_TRADE)) do
        if entry.untradeable == "wrong" and entry.untradeableTo
            and SameObligation(entry, runId, session) then
            handedTo[HandedKey(runId, session)] = entry.untradeableTo
        end
    end
    RemoveObligation(runId, session, why)
end


local NONE = {}

local function ReconcileRun()
    if not addon.Session:IsRunning() then return end
    local runId = addon.Session:GetRunId()
    if not runId then return end

    local bySession = {}
    for _, kind in ipairs(HELD_KINDS) do
        for _, entry in ipairs(addon.Storage:GetAll(kind)) do
            local args = entry.args
            if args and args.runId == runId and args.session then
                local list = bySession[args.session]
                if not list then
                    list = {}
                    bySession[args.session] = list
                end
                list[#list + 1] = entry
            end
        end
    end
    local handed = HandedStore()

    for session, item in ipairs(addon.Session:GetItems()) do
        if item.link and not item.simulated and item.owner
            and addon.Player:IsSelf(item.owner) then
            local entries = bySession[session] or NONE
            local winner = item.awarded
            local given = handed[HandedKey(runId, session)]
            if type(given) ~= "table" then given = nil end

            if not winner then


                if #entries > 0 and (tonumber(item.awardSeq) or 0) > 0 then
                    ForgetSession(runId, session, "award struck while away")
                end
            elseif addon.Player:IsSame(winner, item.owner) then
                if not item.delivered then
                    local kept
                    for _, entry in ipairs(entries) do
                        if not kept and entry.category == addon.Storage.KEPT then
                            kept = entry
                        else
                            addon.Storage:Remove(entry.id)
                            addon.Log:I("Trade", "award moved to the holder while away", entry.link)
                        end
                    end
                    if not kept then
                        addon.Storage:Add(item.link, addon.Storage.KEPT, {
                            recipient = winner, session = session, runId = runId,
                        })
                    end
                    Deliver(session, winner, item.link, runId)
                end
            elseif item.delivered then
                if #entries > 0 then
                    RemoveObligation(runId, session, "delivered while away")
                end
            elseif given and given.w and addon.Player:IsSame(given.w, winner) then
                if #entries > 0 then
                    RemoveObligation(runId, session, "already handed over")
                end
                Deliver(session, winner, item.link, runId)
            else
                local keep, handover
                for _, entry in ipairs(entries) do
                    local to = entry.args and entry.args.recipient
                    if not keep and entry.category == addon.Storage.TO_TRADE and to
                        and addon.Player:IsSame(to, winner) then
                        keep = entry
                    end
                    if entry.untradeable == "wrong" and entry.untradeableTo
                        and addon.Player:IsSame(entry.untradeableTo, winner) then
                        handover = true
                    end
                end
                for _, entry in ipairs(entries) do
                    if entry ~= keep or handover then
                        addon.Storage:Remove(entry.id)
                        addon.Log:I("Trade", "obligation replaced after recovery", entry.link,
                            "now owed to", tostring(winner))
                    end
                end
                if handover then
                    Deliver(session, winner, item.link, runId)
                elseif not keep then
                    local entry = addon.Storage:Add(item.link, addon.Storage.TO_TRADE, {
                        recipient = winner,
                        session = session,
                        runId = runId,
                    })
                    addon.Log:I("Trade", "obligation rebuilt after recovery", item.link,
                        "to", tostring(winner))
                    if given and given.w then
                        if addon.Storage:MarkUntradeable(entry, "wrong", given.w) then
                            ReportUndeliverable(entry)
                        end
                    elseif entry.missingAtAdd then
                        ReconcileSoon()
                    end
                end
            end
        end
    end
end

local runCheckQueued = false

local function ReconcileRunSoon()
    if runCheckQueued then return end
    runCheckQueued = true
    C_Timer.After(0, function()
        runCheckQueued = false
        ReconcileRun()
    end)
end



local RESYNC_COOLDOWN = 10
local resyncedAt = {}

local function ResendHandovers(runId)
    if not runId then return end
    local now = GetTime()
    if resyncedAt[runId] and now - resyncedAt[runId] < RESYNC_COOLDOWN then return end
    resyncedAt[runId] = now

    local live = addon.Session:IsRunning() and addon.Session:GetRunId() == runId
    local sent = 0
    for _, record in pairs(HandedStore()) do
        if type(record) == "table" and record.i == runId and record.s and record.w
            and (live or not addon.Player:IsSelf(record.w)) then
            addon.Comms:Send("delivered", {
                s = record.s, w = record.w, l = record.l, i = runId,
            }, nil, true)
            sent = sent + 1
        end
    end
    for _, entry in ipairs(addon.Storage:GetAll(addon.Storage.TO_TRADE)) do
        local args = entry.args
        if entry.untradeable and args and args.runId == runId and args.session then
            addon.Comms:Send("undelivered", {
                s = args.session, w = args.recipient, l = entry.link,
                i = runId, r = entry.untradeable, t = entry.untradeableTo,
            }, nil, true)
            sent = sent + 1
        end
    end
    if sent > 0 then
        addon.Log:I("Trade", "re-sent", sent, "handover report(s) for run", tostring(runId))
    end
end





function Trade:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("TRADE_SHOW")
    f:RegisterEvent("TRADE_ACCEPT_UPDATE")
    f:RegisterEvent("TRADE_CLOSED")
    f:RegisterEvent("TRADE_POTENTIAL_REMOVE_TRANSMOG")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")

    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "TRADE_SHOW" then
            inTrade = true
            tradeSession = tradeSession + 1
            wipe(staged)
            wipe(stagedBefore)
            snapshot = nil
            if fill then EndFill(fill) end

            local recipient = TradeTarget()
            windowRecipient = recipient
            if not recipient then return end

            local owed = Placeable(Trade:GetOwedTo(recipient))
            if #owed == 0 then return end



            for _, entry in ipairs(owed) do entry.tradeSeen = time() end
            seenEntries = owed

            addon.Chat.Print(addon.Locale.Format(addon.Locale.Plural{
                one = "%d item is owed to %s - adding it to the trade. Press Trade to send it.",
                other = "%d items are owed to %s - adding them to the trade. Press Trade to send them.",
            }, #owed, #owed, Ambiguate(recipient, "short")))
            Trade:FillWindow(recipient, owed)

        elseif event == "TRADE_POTENTIAL_REMOVE_TRANSMOG" then


            if GetTime() < suppressUntil and not PadGamepadStyle() then
                C_Timer.After(0, function()
                    if InCombatLockdown() or type(StaticPopup_ForEachShownDialog) ~= "function" then return end
                    local shown = 0
                    StaticPopup_ForEachShownDialog(function() shown = shown + 1 end)
                    if shown == 1 and StaticPopup_Visible("TRADE_POTENTIAL_REMOVE_TRANSMOG") then
                        StaticPopup_Hide("TRADE_POTENTIAL_REMOVE_TRANSMOG")
                    end
                end)
            end

        elseif event == "TRADE_ACCEPT_UPDATE" then


            if arg1 == 1 then

                local target, guessed = TradeTarget()
                snapshot = {
                    recipient = (not guessed and target) or windowRecipient or target,
                    links = {},
                }

                for _, s in ipairs(staged) do s.paired = nil end
                for slot = 1, UsableTradeSlots() do
                    local link = GetTradePlayerItemLink(slot)
                    if link then


                        local matched
                        for _, s in ipairs(staged) do
                            if not s.paired
                                and addon.Storage.ItemsMatch(s.link, link) then
                                s.paired = true
                                matched = s.entry
                                break
                            end
                        end
                        snapshot.links[#snapshot.links + 1] =
                            { link = link, entry = matched }

                    end
                end
                addon.Log:D("Trade", "snapshot", #snapshot.links, "items")
            end

        elseif event == "TRADE_CLOSED" then
            inTrade = false
            if fill then EndFill(fill) end
            local captured = snapshot


            for _, entry in ipairs(seenEntries) do
                if entry.tradeSeen then entry.tradeSeen = time() end
            end
            seenEntries = {}



            if not captured and #staged > 0 then
                captured = { recipient = windowRecipient or lastAttemptedTarget,
                    links = {} }
                for _, s in ipairs(staged) do
                    captured.links[#captured.links + 1] =
                        { link = s.link, entry = s.entry }
                end
                addon.Log:D("Trade", "no accept seen, checking staged items")
            end

            snapshot = nil
            wipe(staged)

            if captured then

                local before = CopyTable(stagedBefore)
                confirmPending = confirmPending + 1
                C_Timer.After(1, function()
                    ConfirmDeliveries(captured.recipient, captured.links, before)
                    confirmPending = confirmPending - 1
                end)
            end

        elseif event == "BAG_UPDATE_DELAYED" then
            ReconcileSoon()

        elseif event == "PLAYER_ENTERING_WORLD" then



            if arg2 then
                ReconcileSoon()
            elseif arg1 then
                C_Timer.After(LOGIN_SETTLE_SECONDS, ReconcileSoon)
            end
        end
    end)





    addon.Callbacks:Register("ItemAwarded", function(session, winner, item)
        if item and item.simulated then return end
        if not item or not item.owner then return end
        if not addon.Player:IsSelf(item.owner) then return end

        local runId = addon.Session:GetRunId()


        RemoveObligation(runId, session, "obligation replaced by re-award")

        local given = handedTo[HandedKey(runId, session)]
        handedTo[HandedKey(runId, session)] = nil
        if given and addon.Player:IsSame(given, winner) then
            addon.Log:I("Trade", "re-awarded to the player a trade already handed it to",
                item.link, tostring(winner))


            local link = item.link
            C_Timer.After(0, function()
                local current = addon.Session:GetRunId() == runId
                    and addon.Session:GetItem(session)
                if not current or not addon.Player:IsSame(current.awarded, winner) then
                    addon.Log:D("Trade", "re-award handover moved on before it settled", link)
                    return
                end
                Deliver(session, winner, link, runId)
            end)
            return
        end

        if addon.Player:IsSame(winner, item.owner) then


            addon.Storage:Add(item.link, addon.Storage.KEPT, {
                recipient = winner,
                session = session,
                runId = runId,
            })
            Deliver(session, winner, item.link, runId)
            return
        end

        local entry = addon.Storage:Add(item.link, addon.Storage.TO_TRADE, {
            recipient = winner,
            session = session,
            runId = runId,
        })



        if entry.missingAtAdd then
            ReconcileSoon()
            return
        end



        local announced = addon.db.announce and addon.db.announce.awards
            and addon.PlayerIsMasterLooter()
        if not announced then
            addon.Chat.Print(addon.Locale.Format(T["trade %s to %s."],
                item.link, Ambiguate(winner, "short")))
        end
    end)



    addon.Callbacks:Register("ItemUnawarded", function(session, previous, item, runId)
        if item and item.simulated then return end
        runId = runId or addon.Session:GetRunId()
        ForgetSession(runId, session, "obligation cancelled for " .. tostring(previous))
    end)


    addon.Callbacks:Register("RunStarted", ReconcileRunSoon)
    addon.Callbacks:Register("RunRecovered", ReconcileRunSoon)
    addon.Callbacks:Register("RunResyncRequested", ResendHandovers)

    addon.Callbacks:Register("StorageChanged", SyncExpiryTicker)
    SyncExpiryTicker()

    TrackOthers()

    addon.Log:I("Trade", "ready")
end
