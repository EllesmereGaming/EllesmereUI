if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local ConfigShare = {}
addon.ConfigShare = ConfigShare

local OPCODE = "config_offer"
local MAX_RESPONSES = 7
local MAX_COUNCIL = 40
local MAX_TEXT = 100


local pending


function ConfigShare:MaySend()
    if addon.PlayerIsMasterLooter() then return true end
    return addon.IsMasterLooter(addon.Player:GetFullName("player"))
end


function ConfigShare:CouncilRecipients()
    local out = {}
    local me = addon.Player:GetFullName("player")
    for name in pairs(addon.Council:GetActive()) do
        if not addon.Player:IsSame(name, me) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end





local function CouncilPart()
    local members = {}
    for _, identity in ipairs(addon.db.council or {}) do
        local record = addon.Player:Get(identity)
        local name = record.fullName
            or (not addon.Player:IsGUID(identity) and identity) or nil
        if name then
            members[#members + 1] = {
                n = name,
                g = record.guid and addon.Player:ForTransmit(record.guid) or nil,
            }
        end
    end
    local ranks = {}
    for _, rank in ipairs(addon.Council:GetConfiguredRanks()) do
        ranks[#ranks + 1] = rank.name
    end
    local guild = addon.RaidTeam and addon.RaidTeam:GetGuildName() or nil
    return { m = members, rk = ranks, gd = guild }
end

local function ResponsesPart()
    local out = {}
    for index, entry in ipairs(addon.db.responses or {}) do
        out[index] = {
            id = entry.id, t = entry.text, w = entry.whisper,
            r = entry.r, g = entry.g, b = entry.b,
        }
    end
    return out
end

function ConfigShare:Build(includeCouncil, includeResponses)
    return {
        c = includeCouncil and CouncilPart() or nil,
        rs = includeResponses and ResponsesPart() or nil,
    }
end








function ConfigShare:Send(audience, includeCouncil, includeResponses, name)
    if not ConfigShare:MaySend() then return nil, "authority" end
    if not includeCouncil and not includeResponses then return nil, "empty" end
    local offer = ConfigShare:Build(includeCouncil, includeResponses)

    local target, count
    if audience == "player" then
        target = addon.Player:Qualify(name and name:trim() or "")
        if not target then return nil, "nobody" end
        if addon.Player:IsSelf(target) then return nil, "self" end
        local record = addon.Player:Get(target)
        target, count = record.fullName or target, 1
    elseif not IsInGroup() then
        return nil, "group"
    elseif audience == "council" then
        local to = {}
        for _, member in ipairs(ConfigShare:CouncilRecipients()) do
            local short = addon.Player:ForTransmit(member)
            if short then to[#to + 1] = short end
        end
        if #to == 0 then return nil, "nobody" end
        offer.to, count = to, #to
    else
        count = 0
        for member in pairs(addon.GetCandidates()) do
            if not addon.Player:IsSelf(member) then count = count + 1 end
        end
        if count == 0 then return nil, "nobody" end
    end


    addon.Comms:Send(OPCODE, offer, target, true)
    addon.Log:I("ConfigShare", "offered", audience, tostring(target or ""), count,
        "recipient(s), council", tostring(includeCouncil), "responses",
        tostring(includeResponses))
    return count, nil, target
end





local function Text(value)
    if type(value) ~= "string" then return nil end
    value = value:trim()
    if value == "" or #value > MAX_TEXT then return nil end
    return value
end

local function Channel(value)
    value = tonumber(value)
    if not value or value ~= value then return nil end
    return math.max(0, math.min(1, value))
end

local function ParseCouncil(part)
    if type(part) ~= "table" or type(part.m) ~= "table" then return nil end
    local members = {}
    for _, entry in ipairs(part.m) do
        if #members >= MAX_COUNCIL then break end
        local name = type(entry) == "table" and addon.Player:Qualify(Text(entry.n) or "")
        if name then
            members[#members + 1] = {
                name = name,
                guid = type(entry.g) == "string" and ("Player-" .. entry.g) or nil,
            }
        end
    end
    local ranks = {}
    if type(part.rk) == "table" then
        for _, rank in ipairs(part.rk) do
            local text = Text(rank)
            if text then ranks[#ranks + 1] = text end
        end
    end
    return { members = members, ranks = ranks, guild = Text(part.gd) }
end

local function ParseResponses(part)
    if type(part) ~= "table" then return nil end
    local out = {}
    for _, entry in ipairs(part) do
        if #out >= MAX_RESPONSES then break end
        local text = type(entry) == "table" and Text(entry.t)
        local r, g, b = text and Channel(entry.r), text and Channel(entry.g), text and Channel(entry.b)
        if text and r and g and b then
            out[#out + 1] = {
                id = Text(entry.id), text = text, whisper = Text(entry.w),
                r = r, g = g, b = b,
            }
        end
    end

    if #out == 0 then return nil end
    return out
end


function ConfigShare.Parse(args, sender)
    if type(args) ~= "table" then return nil, "malformed" end
    if addon.Player:IsSelf(sender) then return nil, "own_echo" end
    if type(args.to) == "table" then
        local me = addon.Player:ForTransmit(UnitGUID("player"))
        local named = false
        for _, short in ipairs(args.to) do
            if short == me then named = true break end
        end
        if not named then return nil, "not_addressed" end
    end


    local record = addon.Player:Get(sender)
    local inGroup = IsInGroup() and record.fullName and addon.GetCandidates()[record.fullName]
    if inGroup and not addon.IsMasterLooter(sender) then return nil, "not_loot_master" end

    local council = args.c ~= nil and ParseCouncil(args.c) or nil
    local responses = args.rs ~= nil and ParseResponses(args.rs) or nil
    if not council and not responses then return nil, "nothing_usable" end
    return {
        from = record.fullName or sender,
        council = council,
        responses = responses,
    }
end

function ConfigShare:GetPending()
    return pending
end

local function SetPending(offer)
    pending = offer
    addon.Callbacks:Fire("ConfigOfferChanged")
end

local function OnOffer(args, sender)
    local offer, why = ConfigShare.Parse(args, sender)
    if not offer then
        addon.Log:D("ConfigShare", "offer from", tostring(sender), "ignored -", why)
        return
    end
    addon.Log:I("ConfigShare", "offer from", offer.from, "council",
        tostring(offer.council ~= nil), "responses", tostring(offer.responses ~= nil))
    SetPending(offer)
end



function ConfigShare:AcceptBlocker(offer)
    offer = offer or pending
    if offer and offer.responses and addon.Session:IsRunning() then
        return "run"
    end
    return nil
end

local function ApplyCouncil(part)
    local old = addon.db.council or {}
    for _, identity in ipairs(old) do
        if addon.Player:IsGUID(identity) then addon.Player:SetCouncil(identity, false) end
    end
    local list, seen = {}, {}
    for _, member in ipairs(part.members) do
        local record = addon.Player:Get(member.guid or member.name)
        if not record.guid then record = addon.Player:Get(member.name) end
        local identity = record.guid or member.name
        local key = addon.Player:NameKey(record.fullName or member.name) or identity
        if not seen[key] then
            seen[key] = true
            list[#list + 1] = identity
            if record.guid then addon.Player:SetCouncil(record.guid, true) end
        end
    end
    addon.db.council = list


    local guild = addon.RaidTeam and addon.RaidTeam:GetGuildName()
    local ranksApplied = false
    if guild and part.guild == guild then
        local set = {}
        for _, rank in ipairs(part.ranks) do set[rank] = true end
        addon.db.councilRanks = addon.db.councilRanks or {}
        addon.db.councilRanks[guild] = set
        ranksApplied = true
    end
    return #list, ranksApplied
end

local function ApplyResponses(list)
    local out = {}
    for index, entry in ipairs(list) do
        out[index] = {
            id = entry.id or ("CUSTOM" .. index), text = entry.text,
            whisper = entry.whisper, r = entry.r, g = entry.g, b = entry.b,
            sort = index,
        }
    end
    addon.db.responses = out
    return #out
end


function ConfigShare:Accept()
    local offer = pending
    if not offer then return nil end
    local blocked = ConfigShare:AcceptBlocker(offer)
    if blocked then return nil, blocked end

    local members, ranksApplied, buttons
    if offer.council then members, ranksApplied = ApplyCouncil(offer.council) end
    if offer.responses then buttons = ApplyResponses(offer.responses) end
    addon.Log:I("ConfigShare", "accepted from", offer.from, "council",
        tostring(members), "ranks", tostring(ranksApplied), "responses", tostring(buttons))

    SetPending(nil)
    addon.Callbacks:Fire("CouncilChanged")

    if ConfigShare:MaySend() then addon.Council:RequestBroadcast() end
    if addon.UI and addon.UI.Options and addon.UI.Options.Refresh then
        addon.UI.Options:Refresh()
    end
    return true, members, ranksApplied, buttons, offer
end

function ConfigShare:Decline()
    if not pending then return end
    addon.Log:I("ConfigShare", "declined offer from", pending.from)
    SetPending(nil)
end

function ConfigShare:Init()
    addon.Comms:Register(OPCODE, "any", OnOffer)

    for _, event in ipairs({ "RunStarted", "RunEnded" }) do
        addon.Callbacks:Register(event, function()
            if pending then addon.Callbacks:Fire("ConfigOfferChanged") end
        end)
    end
end
