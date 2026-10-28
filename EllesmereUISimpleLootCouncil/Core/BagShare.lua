if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local BagShare = {}
addon.BagShare = BagShare


local caches = {}


local PUSH_DELAY = 2
local pushPending = false



function BagShare.ItemKey(link)
    return type(link) == "string" and (link:match("|H(item:[^|]*)") or link) or nil
end



local function StageKey(link)
    local key = BagShare.ItemKey(link)
    if key and key:sub(1, 5) == "item:" then return addon.Storage.CanonicalItemString(key) end
    return key
end





function BagShare.LinkFromItemString(value)
    if type(value) ~= "string" or not value:match("^item:[^|]*$") then return value end
    local name, link, quality = C_Item.GetItemInfo(value)
    if not name then return nil end
    if BagShare.ItemKey(link) == value then return link end
    local hex = quality and select(4, C_Item.GetItemQualityColor(quality)) or "ffffffff"
    return ("|c%s|H%s|h[%s]|h|r"):format(hex, value, name)
end



function BagShare:Reconcile(items, owner)
    if addon.Session:IsRunning() then return end
    local budget = {}
    for _, entry in ipairs(items) do
        local key = StageKey(entry.link)
        if key then budget[key] = (budget[key] or 0) + 1 end
    end
    local queue = addon.Session:GetItems()
    local changed = false
    local index = 1
    while index <= #queue do
        local item = queue[index]
        local key = StageKey(item.link)
        if not item.simulated and addon.Player:IsSame(item.owner, owner) then
            local available = budget[key] or 0
            if item.bagItem and available == 0 then
                table.remove(queue, index)
                changed = true
            else
                if available > 0 then budget[key] = available - 1 end
                index = index + 1
            end
        else
            index = index + 1
        end
    end
    if changed then

        for i, item in ipairs(queue) do item.session = i end
        addon.Callbacks:Fire("SessionChanged", nil, "item")
    end
end


function BagShare:IsSharing()
    if addon.PlayerIsMasterLooter() then return true end
    if not addon.Config:CouncilBagsShared() then return false end
    local me = addon.Player:GetFullName("player")
    return me ~= nil and addon.Council ~= nil and addon.Council:Contains(me)
end



function BagShare:ShouldWatch()
    return IsInGroup() and addon.Loot ~= nil and addon.Loot.handling == true
        and BagShare:IsSharing()
end



local function MayShow(owner)
    if not owner then return false end
    if addon.IsMasterLooter and addon.IsMasterLooter(owner) then return true end
    return addon.Config:CouncilBagsShared()
        and addon.Council ~= nil and addon.Council:Contains(owner)
end


local QUEUE_REFUSED = addon.Locale.Texts{
    active = T["could not queue %s - a run is in progress, and only the Loot Master can add to it."],
    council = T["could not queue %s - only the Loot Master and council members can queue items."],
    mode = T["could not queue %s - the group leader has not let council members manage the loot queue."],
    lootmaster = T["could not queue %s - only the Loot Master can queue items."],
    queued = T["could not queue %s - every copy is already queued."],
    gone = T["could not queue %s - it is no longer in the holder's bags with an active trade timer."],
}

function BagShare.RefusalText(why, link)
    return addon.Locale.Format(QUEUE_REFUSED[why] or QUEUE_REFUSED.gone, link)
end






function BagShare:AddToQueue(link, owner)
    if addon.Session:IsRunning() and not addon.PlayerIsMasterLooter() then
        return nil, "active"
    end
    local refusal = addon.Session:StageRefusal()
    if refusal then return nil, refusal end

    local me = addon.Player:GetFullName("player")
    if not owner then
        owner = addon.PlayerIsMasterLooter() and me
            or (addon.GetMasterLooter and addon.GetMasterLooter())
    end
    if not owner then return nil, "gone" end

    local items
    if addon.Player:IsSame(owner, me) then
        items = addon.Storage:GetTradeableItems()
        owner = me
    else
        local shared = MayShow(owner) and BagShare:Get(owner)
        if not shared then return nil, "gone" end
        items, owner = shared.items, shared.owner
    end
    BagShare:Reconcile(items, owner)

    local key = StageKey(link)
    local queued = 0
    for _, item in ipairs(addon.Session:GetItems()) do
        if not item.simulated and addon.Player:IsSame(item.owner, owner)
            and StageKey(item.link) == key then
            queued = queued + 1
        end
    end
    local held = 0
    for _, entry in ipairs(items) do
        if StageKey(entry.link) == key then
            held = held + 1
            if held > queued then
                local boss, encounterID =
                    addon.Encounter:ForTradeableItem(entry.secondsLeft)


                local link = BagShare.LinkFromItemString(entry.link) or entry.link
                local index = addon.Session:AddItem(link, owner, boss, encounterID)
                if not index then return nil, "council" end
                local item = addon.Session:GetItems()[index]
                item.bagItem = true
                addon.Callbacks:Fire("SessionChanged", index, "item")

                BagShare:StagedSoon(owner)
                return index
            end
        end
    end
    BagShare:StagedSoon(owner)
    return nil, held > 0 and "queued" or "gone"
end


local function StagedCounts(owner)
    local staged = {}
    for _, item in ipairs(addon.Session:GetItems()) do
        local key = StageKey(item.link)
        if key and not item.simulated and addon.Player:IsSame(item.owner, owner) then
            staged[key] = (staged[key] or 0) + 1
        end
    end
    return staged
end



function BagShare.Unstaged(items, owner)
    local staged = StagedCounts(owner)
    local hidden = {}
    for _, markedPass in ipairs({ false, true }) do
        for _, entry in ipairs(items) do
            local key = StageKey(entry.link)
            if key and ((entry.owed or entry.won) and true or false) == markedPass
                and (staged[key] or 0) > 0 then
                staged[key] = staged[key] - 1
                hidden[entry] = true
            end
        end
    end
    local out = {}
    for _, entry in ipairs(items) do
        if not hidden[entry] then out[#out + 1] = entry end
    end
    return out
end



function BagShare.FreeToStage(items, owner)
    local picks, skipped, won = {}, 0, 0
    for _, entry in ipairs(BagShare.Unstaged(items, owner)) do
        if entry.eligible and not entry.kept then
            if entry.owed then
                skipped = skipped + 1
            elseif entry.won then
                won = won + 1
            else
                picks[#picks + 1] = entry
            end
        end
    end
    return picks, skipped, won
end






local watching = false


local function BuildPayload()
    local items = {}
    for _, entry in ipairs(addon.Storage:GetTradeableItems(watching)) do
        items[#items + 1] = {
            l = entry.link,
            s = entry.secondsLeft and math.floor(entry.secondsLeft) or nil,

            e = entry.eligible and true or nil,

            o = entry.owed and (entry.owedTo or "") or nil,
        }
    end
    return { items = items }
end



function BagShare.WirePayload(payload)
    local items = {}
    for index, entry in ipairs(payload.items) do
        items[index] = { l = BagShare.ItemKey(entry.l), s = entry.s, e = entry.e, o = entry.o }
    end
    return { items = items }
end





local lastDigest = nil

function BagShare.Digest(items)
    local parts = {}
    for index, entry in ipairs(items or {}) do
        parts[index] = (entry.l or "") .. (entry.e and "+" or "-")
            .. (entry.o and ("@" .. entry.o) or "")
    end
    return table.concat(parts, "\n")
end

function BagShare:Push(force)
    if not BagShare:IsSharing() then return end

    local payload = BuildPayload()
    local wire = BagShare.WirePayload(payload)


    local digest = BagShare.Digest(wire.items)
    if force or digest ~= lastDigest then
        lastDigest = digest
        addon.Log:D("BagShare", "sharing", #payload.items, "items")
        if IsInGroup() then addon.Comms:Send("bags", wire) end
    else
        addon.Log:D("BagShare", "unchanged,", #payload.items, "items, not re-sent")
    end



    BagShare:Apply(payload, addon.Player:GetFullName("player"))
end



local pushForce = false


local function PushAfterCombat() BagShare:PushSoon(pushForce) end


function BagShare:PushSoon(force)
    if force then
        pushForce = true
    elseif not BagShare:ShouldWatch() then
        return
    end
    if pushPending then return end
    pushPending = true
    C_Timer.After(PUSH_DELAY, function()
        pushPending = false
        if InCombatLockdown() then
            addon.CombatQueue.Defer("BagShare.PushSoon", PushAfterCombat)
            return
        end
        local forced = pushForce
        pushForce = false
        if not forced and not BagShare:ShouldWatch() then return end
        BagShare:Push(forced)
    end)
end



local ownPending = false

function BagShare:StagedSoon(owner)
    if not BagShare:IsSharing() then return end
    if BagShare:ShouldWatch() then
        BagShare:PushSoon()
        return
    end
    local me = addon.Player:GetFullName("player")
    if ownPending or not addon.Player:IsSame(owner, me) then return end
    ownPending = true
    C_Timer.After(PUSH_DELAY, function()
        ownPending = false
        BagShare:Apply(BuildPayload(), me)
    end)
end


local function PushNow()
    if InCombatLockdown() then
        BagShare:PushSoon(true)
    else
        BagShare:Push(true)
    end
end





local MAX_SHARED_ITEMS = 200
local MAX_TRADE_SECONDS = 2 * 60 * 60 + 60

local function ValidSeconds(value)
    if type(value) ~= "number" or value ~= value then return nil end
    if value < 0 or value > MAX_TRADE_SECONDS then return nil end
    return value
end

local function ValidItemText(value)
    if type(value) ~= "string" then return false end
    return value:match("^item:[^|]*$") ~= nil or value:find("|Hitem:", 1, true) ~= nil
end

function BagShare:Apply(payload, sender)
    if type(payload) ~= "table" or type(payload.items) ~= "table" then return end

    local items, loading = {}, nil
    for index, entry in ipairs(payload.items) do
        if index > MAX_SHARED_ITEMS then
            addon.Log:W("BagShare", "list from", tostring(sender), "is too long, rest ignored")
            break
        end
        if type(entry) == "table" and ValidItemText(entry.l) then

            local link = BagShare.LinkFromItemString(entry.l)
            if not link then
                loading = loading or {}
                loading[entry.l] = true
            end
            local owed = type(entry.o) == "string"
            items[#items + 1] = {
                link = link or entry.l,
                secondsLeft = ValidSeconds(entry.s),
                eligible = entry.e and true or false,
                owed = owed or nil,
                owedTo = owed and entry.o ~= "" and entry.o or nil,
            }
        end
    end

    if not sender then return end
    local snapshot = { owner = sender, at = GetTime(), items = items }
    caches[sender] = snapshot



    for itemString in pairs(loading or {}) do
        Item:CreateFromItemLink(itemString):ContinueOnItemLoad(function()
            if caches[sender] ~= snapshot then return end
            local link = BagShare.LinkFromItemString(itemString)
            if not link then return end
            for _, item in ipairs(snapshot.items) do
                if item.link == itemString then item.link = link end
            end
            addon.Callbacks:Fire("BagShareChanged")
        end)
    end


    local function Expire()
        if caches[sender] ~= snapshot then return end
        local current = BagShare:Get(sender)
        BagShare:Reconcile(current.items, current.owner)
        addon.Callbacks:Fire("BagShareChanged")
        local nextExpiry
        for _, entry in ipairs(current.items) do
            if entry.secondsLeft then
                nextExpiry = math.min(nextExpiry or entry.secondsLeft, entry.secondsLeft)
            end
        end
        if nextExpiry then C_Timer.After(math.max(0.1, nextExpiry), Expire) end
    end
    Expire()
    addon.Log:D("BagShare", "cached", #items, "items from", tostring(sender))
end


function BagShare:Get(owner)
    owner = owner or (addon.GetMasterLooter and addon.GetMasterLooter())
    local cache = owner and caches[owner]
    if not cache then


        for key, entry in pairs(caches) do
            if owner and addon.Player:IsSame(key, owner) then cache = entry break end
        end
    end
    if not cache then return nil end

    local elapsed = GetTime() - cache.at
    local out = { owner = cache.owner, items = {} }
    for _, item in ipairs(cache.items) do
        local remaining = item.secondsLeft and math.max(0, item.secondsLeft - elapsed)


        if not item.secondsLeft or remaining > 0 then
            out.items[#out.items + 1] = {
                link = item.link,
                secondsLeft = remaining,
                eligible = item.eligible,
                owed = item.owed,
                owedTo = item.owedTo,
            }
        end
    end
    return out
end




function BagShare:Holders(readOwn)
    local me = addon.Player:GetFullName("player")
    local ml = addon.PlayerIsMasterLooter() and me
        or (addon.GetMasterLooter and addon.GetMasterLooter())
    local out = {}

    local function Add(owner, isML)
        if addon.Player:IsSame(owner, me) then
            out[#out + 1] = { owner = me,
                items = readOwn and readOwn() or addon.Storage:GetTradeableItems(),
                mine = true, lootMaster = isML }
        else
            local shared = BagShare:Get(owner)
            out[#out + 1] = { owner = owner, items = shared and shared.items or {},
                mine = false, lootMaster = isML, known = shared ~= nil }
        end
    end

    if ml then Add(ml, true) end
    if not addon.Config:CouncilBagsShared() or not addon.Council then return out end

    local others = {}
    local selfListed = false
    for fullName in pairs(addon.Council:GetActive()) do
        if not (ml and addon.Player:IsSame(fullName, ml)) then
            if addon.Player:IsSame(fullName, me) then
                selfListed = true
            else
                others[#others + 1] = fullName
            end
        end
    end
    table.sort(others, function(a, b)
        return Ambiguate(a, "short") < Ambiguate(b, "short")
    end)
    if selfListed then Add(me, false) end
    for _, fullName in ipairs(others) do Add(fullName, false) end
    return out
end



function BagShare:Request()
    if addon.PlayerIsMasterLooter() and not addon.Config:CouncilBagsShared() then
        PushNow()
        return
    end


    addon.Comms:Send("bags_request", {})
end




local MISSING_SETTLE = 5
local MISSING_COOLDOWN = 30
local missingDue, missingAskedAt = nil, {}

local function NoOwnScan() return {} end

local function AskMissingNow()
    if not IsInGroup() then return end
    local now = GetTime()
    for _, holder in ipairs(BagShare:Holders(NoOwnScan)) do
        local owner = holder.owner
        local at = missingAskedAt[owner]
        if not holder.mine and not holder.known and (not at or now - at >= MISSING_COOLDOWN) then
            missingAskedAt[owner] = now
            addon.Log:D("BagShare", "no list from", tostring(owner), "- asking for it")
            addon.Comms:Send("bags_request", {}, owner)
        end
    end
end

function BagShare:AskMissing()
    local armed = missingDue ~= nil
    missingDue = GetTime() + MISSING_SETTLE
    if armed then return end
    local function Due()
        local wait = missingDue - GetTime()
        if wait > 0 then
            C_Timer.After(wait, Due)
            return
        end
        missingDue = nil
        AskMissingNow()
    end
    C_Timer.After(MISSING_SETTLE, Due)
end




local seenMembers = nil

local function Joined()
    if not IsInGroup() or not BagShare:IsSharing() then
        seenMembers = nil
        return false
    end
    local current = addon.GetCandidates()
    local joined = false
    if seenMembers then
        for name in pairs(current) do
            if not seenMembers[name] then joined = true end
        end
    end
    seenMembers = current
    return joined
end



local UpdateWatch = function() end



local MOST_WHISPERED = 2

local function WhisperTo(names)
    if InCombatLockdown() then
        BagShare:PushSoon(true)
        return
    end
    local wire = BagShare.WirePayload(BuildPayload())
    for _, name in ipairs(names) do
        addon.Log:D("BagShare", "sharing", #wire.items, "items with", tostring(name))
        addon.Comms:Send("bags", wire, name)
    end
end

function BagShare:OnRosterChanged(_, gained, newly, joiners)
    UpdateWatch()


    local joined = Joined()
    if not (gained or joined) or not BagShare:IsSharing() then return end
    if not newly and joiners and #joiners > 0 and #joiners <= MOST_WHISPERED then
        WhisperTo(joiners)
        return
    end
    lastDigest = nil
    BagShare:PushSoon()
end



local REQUEST_COOLDOWN = 10
local answeredAt, answerHeld = {}, false

local function AnswerRequest(sender)
    local now = GetTime()
    for who, at in pairs(answeredAt) do
        if now - at >= REQUEST_COOLDOWN then answeredAt[who] = nil end
    end
    local last = answeredAt[sender]
    if not last then
        answeredAt[sender] = now
        addon.Log:D("BagShare", "bags requested by", tostring(sender))
        PushNow()
        return
    end
    if answerHeld then return end
    answerHeld = true
    addon.Log:D("BagShare", "bags requested again by", tostring(sender),
        "- answering when the cooldown ends")
    C_Timer.After(REQUEST_COOLDOWN - (now - last), function()
        answerHeld = false
        answeredAt[sender] = GetTime()
        if BagShare:IsSharing() then PushNow() end
    end)
end





function BagShare:Init()


    addon.Comms:Register("bags", "council", function(args, sender)

        if addon.Player:IsSame(sender, addon.Player:GetFullName("player")) then return end
        local record = addon.Player:Get(sender)
        local owner = record.fullName or sender
        if not MayShow(owner) then
            addon.Log:D("BagShare", "ignoring bags from", tostring(owner),
                "- council bags are off")
            return
        end
        BagShare:Apply(args, owner)
    end)


    addon.Comms:OnResume("bags", PushNow)
    addon.Comms:OnResume("bags_request", function() BagShare:Request() end)

    addon.Comms:Register("bags_request", "any", function(_, sender)
        if not BagShare:IsSharing() then return end
        AnswerRequest(addon.Player:Get(sender).fullName or sender)
    end)


    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, bagID)
        if event == "BAG_UPDATE" then
            addon.Storage:InvalidateBags(bagID)
        elseif BagShare:ShouldWatch() then
            BagShare:PushSoon()
        else
            UpdateWatch()
        end
    end)



    UpdateWatch = function()
        local want = BagShare:ShouldWatch()
        if want == watching then return end
        watching = want
        addon.Storage:InvalidateBags()
        if want then
            f:RegisterEvent("BAG_UPDATE")
            f:RegisterEvent("BAG_UPDATE_DELAYED")
            seenMembers = addon.GetCandidates()
            lastDigest = nil
            BagShare:PushSoon()
        else
            f:UnregisterEvent("BAG_UPDATE")
            f:UnregisterEvent("BAG_UPDATE_DELAYED")
            seenMembers = nil
        end
        addon.Log:D("BagShare", want and "watching the bags" or "not watching the bags")
    end
    addon.Callbacks:Register("HandlingChanged", function() UpdateWatch() end)
    addon.Callbacks:Register("LootMasterChanged", function() UpdateWatch() end)
    addon.Callbacks:Register("SharedConfigChanged", function() UpdateWatch() end)


    addon.Callbacks:Register("CouncilChanged", function()
        UpdateWatch()
        for owner in pairs(caches) do
            if not MayShow(owner) and not addon.Player:IsSelf(owner) then
                caches[owner] = nil
            end
        end
        addon.Callbacks:Fire("BagShareChanged")
    end)



    addon.Callbacks:Register("StorageChanged", function() BagShare:PushSoon() end)


    addon.Callbacks:Register("ItemDelivered", function() BagShare:PushSoon() end)

    UpdateWatch()
    addon.Log:I("BagShare", "ready")
end
