if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Council = {}
addon.Council = Council



local active = {}



local activeRanks, activeByRank = {}, {}
local activeRankDetailsKnown = false





function Council:Contains(who)

    if addon.IsMasterLooter(who) then return true end

    local record = addon.Player:Get(who)
    if not record.fullName then return false end
    return active[record.fullName] == true
end

function Council:GetActive()
    return active
end

function Council:GetCount()
    local n = 0
    for _ in pairs(active) do n = n + 1 end
    return n
end



function Council:GetActiveRanks()
    return activeRanks
end

function Council:GetActiveByRank()
    return activeByRank
end

function Council:HasActiveRankDetails()
    return activeRankDetailsKnown
end







local function RankSelection(create)
    local db = addon.db
    db.councilRanks = db.councilRanks or {}


    local guild = addon.RaidTeam and addon.RaidTeam:GetGuildName()
    if not guild then
        return nil, addon.RaidTeam ~= nil and addon.RaidTeam:IsGuildPending()
    end

    local set = db.councilRanks[guild]
    if not set and create then
        set = {}
        db.councilRanks[guild] = set
    end
    return set
end

function Council:IsRankEmpowered(rankName)
    local set = RankSelection(false)
    return (set and rankName and set[rankName]) and true or false
end

function Council:SetRankEmpowered(rankName, enabled)
    if not rankName then return false end
    local set = RankSelection(true)
    if not set then return false end

    set[rankName] = enabled and true or nil
    addon.Log:I("Council", "rank", rankName,
        enabled and "carries council power" or "no longer carries council power")
    if addon.Callbacks then addon.Callbacks:Fire("CouncilChanged") end
    return true
end



function Council:GetConfiguredRanks()
    local set = RankSelection(false)
    if not set then return {} end

    local out, seen = {}, {}

    local ranks = addon.RaidTeam and addon.RaidTeam:GetRanks() or {}
    for _, rank in ipairs(ranks) do
        if set[rank.name] then
            seen[rank.name] = true
            out[#out + 1] = { name = rank.name, order = rank.order, known = true }
        end
    end

    local orphans = {}
    for name in pairs(set) do
        if not seen[name] then orphans[#orphans + 1] = name end
    end
    table.sort(orphans)
    for _, name in ipairs(orphans) do
        out[#out + 1] = { name = name, known = false }
    end

    return out
end



local function RanksConfigured()
    local set, pending = RankSelection(false)
    if set then return next(set) ~= nil end
    if not pending then return false end

    for _, ranks in pairs(addon.db.councilRanks) do
        if type(ranks) == "table" and next(ranks) ~= nil then return true end
    end
    return false
end


function Council:HasRankRule()
    return addon.db ~= nil and RanksConfigured()
end



local lastRankMembers, lastRankNames = {}, {}

local rankUnreadable = false

local function SaveKeptRanks()
    addon.db.councilRankKept = {
        guild = addon.RaidTeam and addon.RaidTeam:GetGuildName(),
        owner = UnitGUID("player"), members = lastRankMembers, names = lastRankNames,
    }
end


local function RestoreKeptRanks()
    local kept = addon.db.councilRankKept
    if type(kept) ~= "table" or type(kept.members) ~= "table" then return end
    local guild = addon.RaidTeam and addon.RaidTeam:GetGuildName()
    if guild and kept.guild ~= guild then return end
    if not guild and kept.owner ~= UnitGUID("player") then return end

    local members, names = {}, {}
    for fullName, rank in pairs(kept.members) do
        if type(fullName) == "string" and type(rank) == "string" then members[fullName] = rank end
    end
    for _, name in ipairs(type(kept.names) == "table" and kept.names or {}) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    lastRankMembers, lastRankNames = members, names
end

local function LastRankMembers(candidates)
    local out = {}
    for fullName, rank in pairs(lastRankMembers) do
        if candidates[fullName] then out[fullName] = rank end
    end
    return out
end




function Council:RankMembers()
    local candidates = addon.GetCandidates()
    local set, pending = RankSelection(false)
    if not set then

        if pending and RanksConfigured() then return LastRankMembers(candidates), false end
        lastRankMembers = {}
        return {}, true
    end
    if next(set) == nil then
        lastRankMembers = {}
        return {}, true
    end

    local byName, readable = addon.RaidTeam:GetRosterIndex()
    if readable == false then return LastRankMembers(candidates), false end


    local out = {}
    for fullName in pairs(candidates) do
        local member = byName[fullName]
        if member and member.rank and set[member.rank] then
            out[fullName] = member.rank
        end
    end
    lastRankMembers = out
    return out, true
end






function Council:Add(who)
    local record = addon.Player:Get(who)
    local nameKey = addon.Player:NameKey(who)



    local fromGuild
    if not record.guid then
        local member, why = addon.RaidTeam:FindMember(who)
        if why == "ambiguous" then
            addon.Log:D("Council", "name matches several guild members", tostring(who))
            return false, T["more than one guild member has that name - add their realm, for example Name-Area 52"]
        end
        if member then
            record = addon.Player:Remember(member.guid, member.fullName,
                member.classFile, member.className) or record
            if record.guid then
                fromGuild = true
                nameKey = addon.Player:NameKey(record.fullName)
            end
        end
    end

    if not record.guid and not nameKey then
        addon.Log:WLogOnly("Council", "cannot resolve player", tostring(who))
        return false, addon.Player:NameHint()
    end

    for _, identity in ipairs(addon.db.council) do
        local existing = addon.Player:Get(identity)
        local sameGUID = record.guid and existing.guid == record.guid
        local existingKey = addon.Player:NameKey(existing.fullName or identity)
        if sameGUID or (nameKey and existingKey == nameKey) then
            addon.Log:D("Council", "already a member", record.fullName or who)
            return false, T["already on the council"]
        end
    end


    local identity = record.guid or addon.Player:Qualify(who)
    addon.db.council[#addon.db.council + 1] = identity
    if record.guid then addon.Player:SetCouncil(record.guid, true) end


    addon.Log:I("Council", record.guid and (fromGuild and "added from guild roster" or "added")
        or "added pending", record.fullName or identity, record.guid)
    if addon.Callbacks then addon.Callbacks:Fire("CouncilChanged") end
    return true
end

function Council:Remove(who)
    local record = addon.Player:Get(who)
    local nameKey = addon.Player:NameKey(who)

    for i, identity in ipairs(addon.db.council) do
        local existing = addon.Player:Get(identity)
        local sameGUID = record.guid and existing.guid == record.guid
        local existingKey = addon.Player:NameKey(existing.fullName or identity)
        if sameGUID or (nameKey and existingKey == nameKey) then
            table.remove(addon.db.council, i)
            if existing.guid then addon.Player:SetCouncil(existing.guid, false) end
            addon.Log:I("Council", "removed", existing.fullName or identity)
            if addon.Callbacks then addon.Callbacks:Fire("CouncilChanged") end
            return true
        end
    end
    return false
end




function Council:GetConfigured()
    local out = {}
    for _, identity in ipairs(addon.db.council) do
        local record = addon.Player:Get(identity)
        local copy = {}
        for key, value in pairs(record) do copy[key] = value end


        copy.identity = identity
        copy.pending = not addon.Player:IsGUID(identity)
        out[#out + 1] = copy
    end
    return out
end








function Council:Resolve()
    local candidates = addon.GetCandidates()
    local payload = {}

    for index, identity in ipairs(addon.db.council) do
        local record = addon.Player:Get(identity)
        if record.fullName and candidates[record.fullName] then

            payload[#payload + 1] = addon.Player:ForTransmit(record.guid)


            if record.guid and identity ~= record.guid then
                addon.db.council[index] = record.guid
                addon.Player:SetCouncil(record.guid, true)
                addon.Log:I("Council", "resolved pending member", record.fullName)
            end
        end
    end


    local named = {}
    for _, g in ipairs(payload) do named[g] = true end



    local master = addon.Player:ForTransmit(addon.GetMasterLooter())
    local self_ = addon.Player:ForTransmit(UnitGUID("player"))
    for _, short in pairs({ master = master, broadcaster = self_ }) do
        if not named[short] then
            named[short] = true
            payload[#payload + 1] = short
        end
    end


    local rankPayload, rankOf = {}, {}
    local rankMembers, rankKnown = Council:RankMembers()

    if rankKnown == rankUnreadable then
        rankUnreadable = not rankKnown
        addon.Log:I("Council", rankUnreadable
            and "guild roster unreadable - keeping the last rank members"
            or "guild roster readable again - rank members re-derived")
    end
    for fullName, rank in pairs(rankMembers) do
        local short = addon.Player:ForTransmit(fullName)
        if short and not named[short] then
            named[short] = true
            payload[#payload + 1] = short
            rankPayload[#rankPayload + 1] = short
            rankOf[short] = rank
        end
    end


    table.sort(rankPayload)

    local rankNames = {}
    for _, rank in ipairs(Council:GetConfiguredRanks()) do
        rankNames[#rankNames + 1] = rank.name
    end

    if select(2, RankSelection(false)) then
        rankNames = lastRankNames
    else
        lastRankNames = rankNames
    end
    if rankKnown then SaveKeptRanks() end


    table.sort(payload)
    return payload, rankNames, rankPayload, rankOf
end






local function BuildSharedConfig()
    local responses = {}
    for index, response in ipairs(addon.Config:Responses()) do
        responses[index] = {
            t = response.text,
            r = response.r, g = response.g, b = response.b,
            s = response.sort,

            w = response.whisper,
        }
    end
    local vote = addon.Config:Vote()
    return {
        responses = responses,
        vote = {
            selfVote = vote.selfVote,
            multiVote = vote.multiVote,
            hideVotes = vote.hideVotes,
        },
        noteMax = addon.Config:NoteMax(),

        startRequests = addon.Config:StartRequestsAllowed(),
        councilMayStartRuns = addon.Config:CouncilMayStartRuns(),


        councilBags = addon.Config:CouncilBagsShared(),

        lootMaster = addon.Config:LootMaster()
            and addon.Player:ForTransmit(addon.Config:LootMaster()) or false,
    }
end


local function ApplySharedConfig(config, sender)

    if addon.Player:IsSelf(sender) then
        addon.Log:D("Council", "ignoring our own shared config echo")
        return
    end



    local me = addon.Player:GetFullName("player")
    local leader = addon.GetGroupLeader()
    if me and leader and addon.Player:IsSame(me, leader) then
        addon.Log:D("Council", "we are the group leader - keeping our own rules")
        return
    end

    addon.Config:ApplyShared(config, sender)
end



local lastDigest = ""


local function Joined(list)
    local out = {}
    if type(list) == "table" then
        for _, value in ipairs(list) do
            if type(value) == "string" then out[#out + 1] = value end
        end
    end
    return table.concat(out, ",")
end





local function Digest(payload, config, ranks, rankPayload, rankOf)
    local parts = { Joined(payload) }



    parts[#parts + 1] = Joined(ranks)
    parts[#parts + 1] = Joined(rankPayload)


    if type(rankPayload) == "table" then
        for _, short in ipairs(rankPayload) do
            if type(short) == "string" then
                parts[#parts + 1] = short .. "=" .. tostring(type(rankOf) == "table" and rankOf[short])
            end
        end
    end

    config = type(config) == "table" and config or {}

    for _, response in ipairs(type(config.responses) == "table" and config.responses or {}) do
        if type(response) == "table" then
            parts[#parts + 1] = ("%s~%s~%s~%s~%s~%s"):format(
                tostring(response.t), tostring(response.r), tostring(response.g),
                tostring(response.b), tostring(response.s), tostring(response.w))
        end
    end

    local vote = type(config.vote) == "table" and config.vote or {}
    parts[#parts + 1] = ("%s~%s~%s~%s~%s"):format(
        tostring(vote.selfVote), tostring(vote.multiVote), tostring(vote.hideVotes),
        tostring(config.noteMax), tostring(config.lootMaster))


    parts[#parts + 1] = ("%s~%s~%s"):format(tostring(config.startRequests),
        tostring(config.councilMayStartRuns), tostring(config.councilBags))

    return table.concat(parts, ";")
end
Council.Digest = Digest





local relayed, heardFrom

local function StringList(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, value in ipairs(list) do
        if type(value) == "string" then out[#out + 1] = value end
    end
    return out
end


local function RelayCopy(args, sender)
    local rankOf
    if type(args.rankOf) == "table" then
        rankOf = {}
        for short, rank in pairs(args.rankOf) do
            if type(short) == "string" and type(rank) == "string" then
                rankOf[short] = rank
            end
        end
    end
    return {
        from = sender,
        guids = StringList(args.guids) or {},
        ranks = StringList(args.ranks),
        rguids = StringList(args.rguids),
        rankOf = rankOf,
    }
end


local function IsAuthor()
    if not IsInGroup() then return true end
    return addon.Player:IsSame(addon.Player:GetFullName("player"),
        addon.GetGroupLeader())
end




function Council:Authorship()
    if not IsInGroup() then return "solo" end
    local leader = addon.GetGroupLeader()
    if IsAuthor() then return "leader", leader end
    return addon.Config:HasShared() and "follower" or "waiting", leader
end



local lastPushAt = -math.huge


local appliedDigest



function Council:Broadcast(force, target)


    local me = addon.Player:GetFullName("player")
    if not addon.PlayerIsMasterLooter() and not addon.IsMasterLooter(me) then
        return false
    end

    local payload, rankNames, rankPayload, rankOf
    local relaying = not IsAuthor()
    if relaying then


        local leader = addon.GetGroupLeader()
        if not (relayed and leader and addon.Player:IsSame(relayed.from, leader)) then
            addon.Log:D("Council", "no council from the leader to relay yet")
            return false
        end
        payload, rankNames, rankPayload, rankOf =
            relayed.guids, relayed.ranks, relayed.rguids, relayed.rankOf
    else
        payload, rankNames, rankPayload, rankOf = Council:Resolve()
    end
    local config = BuildSharedConfig()
    local message = {
        guids = payload,


        ranks = rankNames,
        rguids = rankPayload,
        rankOf = rankOf,
        config = config,
    }

    if target then
        addon.Log:I("Council", relaying and "relaying the leader's council to" or "sending the council to",
            tostring(target), #payload, "members", #(rankNames or {}), "rank(s)")

        addon.Comms:Send("council", message, target, true)
        return true
    end



    local digest = Digest(payload, config, rankNames, rankPayload, rankOf)
    if not force and digest == lastDigest then return false end
    lastDigest = digest
    lastPushAt = GetTime()

    addon.Log:I("Council", relaying and "relaying the leader's council," or "broadcasting",
        #payload, "members", #(rankNames or {}), "rank(s)")

    addon.Comms:Send("council", message, nil, true)


    if Council:Apply(payload, addon.Player:GetFullName("player"), rankNames, rankPayload, rankOf) then
        appliedDigest = digest
    end
    return true
end

Council.ApplySharedConfig = function(_, config, sender)
    ApplySharedConfig(config, sender)
end



local COOLDOWN = 5
local lastSent, queued, queuedForce = 0, false, false


local RANK_SETTLE = 2


local function MayBroadcast()
    if addon.PlayerIsMasterLooter() then return true end
    return addon.IsMasterLooter(addon.Player:GetFullName("player"))
end




local RANK_MIN_INTERVAL = 10
local rankResolvePending, lastRankResolve = false, nil
local function ScheduleRankResolve()
    if rankResolvePending or not RanksConfigured() then return end
    rankResolvePending = true
    local wait = RANK_SETTLE
    if lastRankResolve then
        wait = math.max(wait, lastRankResolve + RANK_MIN_INTERVAL - GetTime())
    end
    C_Timer.After(wait, function()
        rankResolvePending, lastRankResolve = false, GetTime()
        if IsInGroup() and IsAuthor() then Council:RequestBroadcast() end
    end)
end








local SYNC_COOLDOWN = 10
local MAX_SYNC_ASKS = 5
local lastSyncAsk, syncAsks = 0, 0
local syncRetryPending = false

local syncAskHeld = false

local function Blocked()
    return addon.Restrictions and addon.Restrictions:IsBlocked() or false
end


local function ResetSyncAsks()
    lastSyncAsk, syncAsks, syncRetryPending, syncAskHeld = 0, 0, false, false
end

local function RetrySyncAsk()
    local remaining = SYNC_COOLDOWN - (GetTime() - lastSyncAsk)
    if remaining > 0 then
        C_Timer.After(remaining + 0.5, RetrySyncAsk)
        return
    end
    syncRetryPending = false
    Council:EnsureShared("no answer")
end


function Council.OnRestrictionChange(isBlocked)
    if isBlocked then return end

    if rankUnreadable then ScheduleRankResolve() end
    if not syncAskHeld then return end
    syncAskHeld, lastSyncAsk = false, GetTime()
    if not syncRetryPending then
        syncRetryPending = true
        C_Timer.After(SYNC_COOLDOWN + 0.5, RetrySyncAsk)
    end
end



function Council:EnsureShared(why)
    if not IsInGroup() then return end
    if addon.Player:IsSame(addon.Player:GetFullName("player"),
        addon.GetGroupLeader()) then
        return
    end
    if addon.Config:HasShared() then return end
    if syncAskHeld then return end


    if syncAsks >= MAX_SYNC_ASKS then return end
    local now = GetTime()
    if lastSyncAsk > 0 and now - lastSyncAsk < SYNC_COOLDOWN then return end
    lastSyncAsk, syncAsks = now, syncAsks + 1

    addon.Log:I("Council", "no shared contract -", tostring(why),
        "- asking the leader", syncAsks .. "/" .. MAX_SYNC_ASKS)

    addon.Comms:Send("council_sync_request", {}, nil, true)
    if Blocked() then syncAskHeld = true end


    if not syncRetryPending then
        syncRetryPending = true


        C_Timer.After(SYNC_COOLDOWN + 0.5, RetrySyncAsk)
    end
end


function Council:RequestBroadcast(force)
    if not MayBroadcast() then return end

    local since = GetTime() - lastSent
    if since >= COOLDOWN then


        if Council:Broadcast(force) then lastSent = GetTime() end
        return
    end

    if queued then


        queuedForce = queuedForce or force or false
        return
    end
    queued, queuedForce = true, force or false
    C_Timer.After(COOLDOWN - since, function()
        local wasForced = queuedForce
        queued, queuedForce = false, false
        if MayBroadcast() then
            if Council:Broadcast(wasForced) then lastSent = GetTime() end
        end
    end)
end


function Council:Apply(guids, sender, ranks, rankGuids, rankOf)
    if type(guids) ~= "table" then return false end
    local complete = true



    addon.Player:ClearAllCouncilFlags()


    for _, identity in ipairs(addon.db.council or {}) do
        if addon.Player:IsGUID(identity) then
            addon.Player:SetCouncil(identity, true)
        end
    end
    active = {}
    activeRanks, activeByRank = {}, {}
    activeRankDetailsKnown = type(rankOf) == "table"

    for _, short in ipairs(guids) do
        local record = addon.Player:Get(short)
        if record.fullName then
            active[record.fullName] = true
            if record.guid then addon.Player:SetCouncil(record.guid, true) end
        end
        if not record.guid then complete = false end
    end


    local validRanks = {}
    if type(ranks) == "table" then
        for _, name in ipairs(ranks) do
            if type(name) == "string" and not validRanks[name] then
                activeRanks[#activeRanks + 1] = name
                validRanks[name] = true
            end
        end
    end
    if type(rankGuids) == "table" then
        for _, short in ipairs(rankGuids) do
            local record = addon.Player:Get(short)

            if record.fullName and active[record.fullName] then
                local rank = type(rankOf) == "table" and rankOf[short]
                if type(rank) == "string" and validRanks[rank] then
                    activeByRank[record.fullName] = rank
                else
                    activeByRank[record.fullName] = true

                    activeRankDetailsKnown = false
                end
            end
        end
    end

    addon.Log:I("Council", "applied", Council:GetCount(), "members",
        #activeRanks, "rank(s), from", tostring(sender))

    if addon.Callbacks then addon.Callbacks:Fire("CouncilChanged") end
    return complete
end








local broadcaster = false

local function RosterGained(diff)
    if not diff.inGroup or not MayBroadcast() then
        broadcaster = false
        return false, false
    end
    local newly = not broadcaster
    broadcaster = true
    return newly or next(diff.joined) ~= nil, newly
end


Council.RosterGained = RosterGained
Council.ResetSyncAsks = ResetSyncAsks






local ASK_WINDOW = 1
local ASK_CROSSING = 1
local MOST_WHISPERED = 2


local ANSWER_COOLDOWN = 8
local askers, asked, firstAskAt = {}, {}, nil
local answeredAt, answeredCount = {}, 0

local function AskKey(name)
    return addon.Player:NameKey(name) or name
end

local function MarkAnswered(list)
    local now = GetTime()

    if answeredCount > 80 then
        for key, at in pairs(answeredAt) do
            if now - at >= ANSWER_COOLDOWN then answeredAt[key] = nil end
        end
        answeredCount = 0
        for _ in pairs(answeredAt) do answeredCount = answeredCount + 1 end
    end
    for _, name in ipairs(list) do
        local key = AskKey(name)
        if not answeredAt[key] then answeredCount = answeredCount + 1 end
        answeredAt[key] = now
    end
end

local function AnswerAsks()
    local list, since = askers, firstAskAt
    askers, asked, firstAskAt = {}, {}, nil
    if #list == 0 or not MayBroadcast() then return end
    MarkAnswered(list)

    if since and lastPushAt >= since - ASK_CROSSING then
        addon.Log:D("Council", #list, "council ask(s) answered by the group push")
        return
    end

    if queued and queuedForce then
        addon.Log:D("Council", #list, "council ask(s) left to the queued group push")
        return
    end
    if #list > MOST_WHISPERED then
        addon.Log:I("Council", #list, "players asked for the council - one group push")
        Council:RequestBroadcast(true)
        return
    end
    for _, name in ipairs(list) do Council:Broadcast(true, name) end
end


local function Collect(name)
    local key = AskKey(name)
    if asked[key] then return false end
    local at = answeredAt[key]
    if at and GetTime() - at < ANSWER_COOLDOWN then
        addon.Log:D("Council", "answered", tostring(name), "moments ago - not again")
        return false
    end
    asked[key] = true
    askers[#askers + 1] = name
    if not firstAskAt then
        firstAskAt = GetTime()
        C_Timer.After(ASK_WINDOW, AnswerAsks)
    end
    return true
end

local function OnSyncRequest(_, sender)
    addon.Log:D("Council", "council requested by", sender)

    if not sender or addon.Player:IsSelf(sender) then return end


    if not MayBroadcast() then return end
    Collect(sender)
end

Council.OnSyncRequest = OnSyncRequest



local function CollectJoiners(joined)
    local me = addon.Player:GetFullName("player")
    for name in pairs(joined) do
        if not addon.Player:IsSame(name, me) then Collect(name) end
    end
end







local function OnCouncil(args, sender)
    if type(args) ~= "table" then return end



    local leader = IsInGroup() and addon.GetGroupLeader()
    if leader and not addon.Player:IsSelf(sender) then
        if addon.Player:IsSame(sender, leader) then
            heardFrom = sender


            if type(args.guids) == "table" then relayed = RelayCopy(args, sender) end
        elseif IsAuthor() then
            addon.Log:D("Council", "we lead - ignoring a council relayed by", tostring(sender))
            return
        elseif heardFrom and addon.Player:IsSame(heardFrom, leader) then
            addon.Log:D("Council", "have the leader's council - ignoring the relay from",
                tostring(sender))
            return
        end
    end



    local digest = Digest(args.guids, args.config, args.ranks, args.rguids, args.rankOf)
    if digest == appliedDigest and (IsAuthor() or addon.Config:HasShared()) then
        if args.config then ResetSyncAsks() end
        addon.Log:D("Council", "council from", tostring(sender), "unchanged - nothing applied")
        return
    end



    if args.config then
        ApplySharedConfig(args.config, sender)

        ResetSyncAsks()
    end

    local complete = Council:Apply(args.guids, sender, args.ranks, args.rguids, args.rankOf)
    appliedDigest = (complete and type(args.config) == "table") and digest or nil
    if addon.Callbacks then addon.Callbacks:Fire("SessionChanged") end
end


Council.OnCouncil = OnCouncil

function Council:Init()
    addon.Comms:Register("council", "ml", OnCouncil)




    addon.Comms:Register("council_sync_request", "any", OnSyncRequest)
    if addon.Restrictions then addon.Restrictions:OnChange(Council.OnRestrictionChange) end



    RestoreKeptRanks()
    if addon.PlayerIsMasterLooter() or IsAuthor() then
        local payload, rankNames, rankPayload, rankOf = Council:Resolve()
        Council:Apply(payload, addon.Player:GetFullName("player"),
            rankNames, rankPayload, rankOf)
    end



    if RanksConfigured() and addon.RaidTeam then addon.RaidTeam:Request() end
    addon.Callbacks:Register("RaidTeamChanged", ScheduleRankResolve)



    local function ForgetDelegation(why)
        if not addon.db.lootMaster then return end
        addon.db.lootMaster = nil
        addon.InvalidateMasterLooter()
        addon.Log:I("Council", "loot delegation forgotten -", why)
        if addon.Callbacks then addon.Callbacks:Fire("CouncilChanged") end
    end



    local function InheritDelegation()
        if not addon.Config:HasShared() then return end
        local delegate = addon.Config:LootMaster()
        local keep = not (addon.db.raidPrompt and addon.db.raidPrompt.dropDelegationOnLead)
        if not keep then delegate = nil end
        addon.db.lootMaster = delegate
        addon.Log:I("Council", "promoted - loot delegation",
            delegate and "kept" or "cleared", tostring(delegate))
        if addon.Callbacks then addon.Callbacks:Fire("CouncilChanged") end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function()
        C_Timer.After(3, function()
            if not IsInGroup() then
                ForgetDelegation("not in a group")
            elseif addon.Loot and addon.Loot.CheckLootMaster then


                addon.Loot:CheckLootMaster("login")
            end
        end)
    end)


    addon.Callbacks:Register("RosterChanged", function(diff)

        if not diff.inGroup then
            addon.Config:ClearShared("left the group")
            ForgetDelegation("left the group")
            relayed, heardFrom, appliedDigest = nil, nil, nil
            answeredAt, answeredCount = {}, 0
        elseif addon.Player:IsSame(addon.Player:GetFullName("player"),
            addon.GetGroupLeader()) then


            InheritDelegation()
            addon.Config:ClearShared("we are the group leader now")
            appliedDigest = nil
        end



        if diff.leaderChanged or not diff.inGroup then
            ResetSyncAsks()
        end



        local gained, newly = RosterGained(diff)
        Council:RequestBroadcast(newly)
        if gained and not newly then CollectJoiners(diff.joined) end
        Council:EnsureShared(diff.leaderChanged and "leader changed" or "roster changed")


        if addon.Loot and addon.Loot.OnRosterChanged then
            addon.Loot:OnRosterChanged("roster", gained, diff.leaderChanged)
        end
        if addon.BagShare and addon.BagShare.OnRosterChanged then
            addon.BagShare:OnRosterChanged("roster", gained)
        end
    end)

    addon.Log:I("Council", "ready", #addon.db.council, "configured",
        #Council:GetConfiguredRanks(), "rank(s)",
        Council:GetCount(), "active")
end
