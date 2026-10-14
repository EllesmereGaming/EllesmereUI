if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local RaidTeam = {}
addon.RaidTeam = RaidTeam

local issecretvalue = issecretvalue


local ROSTER_TTL = 5

local roster, rosterAt = nil, 0

local lastReadable, unreadable = nil, false







local function IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end







local GUILD_LOST_GRACE = 30
local knownGuild, guildLostAt = nil, nil

function RaidTeam:GetGuildName()
    if not IsInGuild() then return nil end
    local name = GetGuildInfo("player")
    if not name or name == "" or IsSecret(name) then return nil end
    knownGuild, guildLostAt = name, nil
    return name
end



function RaidTeam:IsGuildPending()
    if IsInGuild() then return RaidTeam:GetGuildName() == nil end
    if not knownGuild then return false end
    local now = GetTime()
    if not guildLostAt then
        guildLostAt = now
        addon.Log:D("RaidTeam", "guild not readable - holding", knownGuild, "for", GUILD_LOST_GRACE, "s")

        C_Timer.After(GUILD_LOST_GRACE + 0.5, function()
            RaidTeam:Invalidate()
            addon.Callbacks:Fire("RaidTeamChanged")
        end)
    end
    if now - guildLostAt < GUILD_LOST_GRACE then return true end
    addon.Log:I("RaidTeam", "no longer in", knownGuild)
    knownGuild, guildLostAt = nil, nil
    return false
end



function RaidTeam:GetRanks()
    if not IsInGuild() then return {} end

    local ranks, seen = {}, {}

    local count = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    if type(count) == "number" and count > 0 then
        for order = 1, count do
            local name = GuildControlGetRankName(order)
            if name and name ~= "" and not IsSecret(name) and not seen[name] then
                seen[name] = true
                ranks[#ranks + 1] = { name = name, order = order }
            end
        end
    end

    if #ranks > 0 then return ranks end

    for _, member in ipairs(RaidTeam:GetRoster()) do
        if member.rank and not seen[member.rank] then
            seen[member.rank] = true
            ranks[#ranks + 1] = { name = member.rank, order = member.rankOrder or 99 }
        end
    end
    table.sort(ranks, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)

    return ranks
end







local function Selection(create)
    local db = addon.db
    db.raidTeam = db.raidTeam or {}
    db.raidTeam.ranks = db.raidTeam.ranks or {}

    local guild = RaidTeam:GetGuildName()
    if not guild then return nil end

    local set = db.raidTeam.ranks[guild]
    if not set and create then
        set = {}
        db.raidTeam.ranks[guild] = set
    end
    return set
end

function RaidTeam:IsRaiderRank(rankName)
    local set = Selection(false)
    return (set and rankName and set[rankName]) and true or false
end

function RaidTeam:SetRaiderRank(rankName, enabled)
    if not rankName then return end
    local set = Selection(true)
    if not set then return end

    set[rankName] = enabled and true or nil
    addon.Log:I("RaidTeam", "rank", rankName, enabled and "counts as a raider"
        or "no longer counts as a raider")
    addon.Callbacks:Fire("RaidTeamChanged")
end


function RaidTeam:HasSelection()
    local set = Selection(false)
    if not set then return false end
    for _ in pairs(set) do return true end
    return false
end

function RaidTeam:CountSelectedRanks()
    local set = Selection(false)
    if not set then return 0 end
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end







local Presence = Enum and Enum.ClubMemberPresence or {}
local ONLINE_PRESENCE = {
    [Presence.Online or -1] = true,
    [Presence.Away or -2] = true,
    [Presence.Busy or -3] = true,
    [Presence.OnlineMobile or -4] = true,
}

local function BuildMember(info, canViewOfficer)
    if IsSecret(info.name, info.guid, info.guildRank) then return nil end
    if not info.name or info.name == "" then return nil end

    local classFile, className
    if info.classID and not IsSecret(info.classID) then
        local classInfo = C_CreatureInfo.GetClassInfo(info.classID)
        if classInfo then
            classFile, className = classInfo.classFile, classInfo.className
        end
    end


    local note
    if info.memberNote and info.memberNote ~= "" and not IsSecret(info.memberNote) then
        note = info.memberNote
    end


    local officerNote
    if canViewOfficer and info.officerNote and info.officerNote ~= ""
        and not IsSecret(info.officerNote) then
        officerNote = info.officerNote
    end

    return {
        guid        = info.guid,
        name        = info.name,

        fullName    = addon.Player:Qualify(info.name) or info.name,
        classFile   = classFile,
        className   = className,
        level       = info.level,
        zone        = info.zone,
        rank        = info.guildRank,
        rankOrder   = info.guildRankOrder or 99,
        online      = ONLINE_PRESENCE[info.presence] and true or false,
        mobile      = info.presence == Presence.OnlineMobile,
        note        = note,
        officerNote = officerNote,
    }
end


local function Unreadable()
    unreadable = true
    return lastReadable or {}, false
end




function RaidTeam:GetRoster(force)
    if roster and not force and (GetTime() - rosterAt) < ROSTER_TTL then
        return roster, true
    end

    local built = {}

    if IsInGuild() then

        local clubId = C_Club.GetGuildClubId()
        if not clubId then return Unreadable() end



        local canViewOfficer = C_GuildInfo and C_GuildInfo.CanViewOfficerNote
            and C_GuildInfo.CanViewOfficerNote() or false


        local ids = C_Club.GetClubMembers(clubId)

        if IsSecret(ids) or type(ids) ~= "table" or #ids == 0 then return Unreadable() end
        for _, memberId in ipairs(ids) do
            local info = C_Club.GetMemberInfo(clubId, memberId)

            if IsSecret(info) or (info and IsSecret(info.name, info.guid, info.guildRank)) then
                return Unreadable()
            end
            local member = info and BuildMember(info, canViewOfficer)
            if member then built[#built + 1] = member end
        end
    end

    roster, rosterAt = built, GetTime()
    lastReadable, unreadable = built, false
    return roster, true
end


function RaidTeam:GetMembers()
    local members = {}
    for _, member in ipairs(RaidTeam:GetRoster()) do
        if RaidTeam:IsRaiderRank(member.rank) then
            members[#members + 1] = member
        end
    end
    return members
end



function RaidTeam:Request()
    if not IsInGuild() then return end
    C_GuildInfo.GuildRoster()
end

function RaidTeam:Invalidate()
    roster, rosterAt = nil, 0
end



function RaidTeam:NoteFor(name)
    local qualified = addon.Player:Qualify(name)
    if not qualified then return nil end


    local key = addon.Player:NameKey(qualified) or addon.Locale.Fold(qualified)

    for _, member in ipairs(RaidTeam:GetRoster()) do
        if member.fullName and (addon.Player:NameKey(member.fullName)
            or addon.Locale.Fold(member.fullName)) == key then
            return { note = member.note, officerNote = member.officerNote }
        end
    end
    return nil
end


local function BareFold(member)
    local folded = member.bareFold
    if not folded then
        folded = addon.Locale.Fold(member.name:match("^([^-]+)") or member.name)
        member.bareFold = folded
    end
    return folded
end



function RaidTeam:FindMember(input)
    if type(input) ~= "string" or input == "" or IsSecret(input) then return nil end
    local list, readable = RaidTeam:GetRoster()
    if not readable then return nil, "unreadable" end

    local key = addon.Player:NameKey(input)
    local bare = not key and not input:find("-", 1, true)
        and addon.Locale.Fold(input:match("^%s*(.-)%s*$")) or nil
    if not key and (not bare or bare == "") then return nil end

    local found
    for _, member in ipairs(list) do
        if member.guid and ((key and member.fullName
                and addon.Player:NameKey(member.fullName) == key)
            or (bare and BareFold(member) == bare)) then
            if found and found.guid ~= member.guid then return nil, "ambiguous" end
            found = member
        end
    end
    return found
end



function RaidTeam:Suggest(prefix, limit)
    local out = {}
    if type(prefix) ~= "string" or IsSecret(prefix) then return out end
    prefix = prefix:match("^%s*(.-)%s*$")
    if select(2, prefix:gsub("[^\128-\191]", "")) < 2 then return out end
    if not IsInGuild() then return out end

    local list, readable = RaidTeam:GetRoster()
    if not readable then return out end

    local wanted = addon.Locale.Fold(prefix)
    local n = #wanted
    local hits = {}
    for _, member in ipairs(list) do
        if member.guid and BareFold(member):sub(1, n) == wanted then
            hits[#hits + 1] = member
        end
    end
    table.sort(hits, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.rankOrder ~= b.rankOrder then return a.rankOrder < b.rankOrder end
        return BareFold(a) < BareFold(b)
    end)

    for i = 1, math.min(limit or 8, #hits) do
        local m = hits[i]
        out[i] = { name = m.name:match("^([^-]+)") or m.name, fullName = m.fullName,
            guid = m.guid, classFile = m.classFile, rank = m.rank,
            rankOrder = m.rankOrder, online = m.online }
    end
    return out
end








function RaidTeam:BuildLootIndex()
    local index = {}
    local foldAlts = not (addon.db and addon.db.teamShowAlts == false)

    addon.History.EachEntry(function(entry)
        local main = entry.winner
            and (foldAlts and addon.Player:Main(entry.winner)
                or addon.Player:Qualify(entry.winner) or entry.winner)
        local key = main and addon.Player:NameKey(main)
        if not key then return end
        local list = index[key]
        if not list then
            list = {}
            index[key] = list
        end
        list[#list + 1] = entry
    end)


    for _, list in pairs(index) do
        table.sort(list, function(a, b) return (a.epoch or 0) > (b.epoch or 0) end)
    end

    return index
end

function RaidTeam:LootFor(index, member)
    if not index or not member or not member.fullName then return {} end
    local key = addon.Player:NameKey(member.fullName)
    return (key and index[key]) or {}
end









local function CurrentSeasonID()
    if C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID then
        local id = C_SeasonInfo.GetCurrentDisplaySeasonID()
        if type(id) == "number" and id > 0 then return id end
    end


    if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
        local id = C_MythicPlus.GetCurrentSeason()
        if type(id) == "number" and id > 0 then return id end
    end
    return nil
end
RaidTeam.CurrentSeasonID = function() return CurrentSeasonID() end



local function DaysFromCivil(y, m, d)
    y = y - (m <= 2 and 1 or 0)
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function UTCMidnight(year, month, day)
    return DaysFromCivil(year, month, day) * 86400
end



function RaidTeam:ParseDate(text)
    if type(text) ~= "string" then return nil end
    local digits = text:gsub("[^%d]", "")
    if #digits ~= 8 then return nil end

    local year = tonumber(digits:sub(1, 4))
    local month = tonumber(digits:sub(5, 6))
    local day = tonumber(digits:sub(7, 8))
    if not year or not month or not day then return nil end
    if month < 1 or month > 12 or day < 1 or day > 31 then return nil end

    return UTCMidnight(year, month, day)
end



function RaidTeam:GetSeasonStart()
    local value = addon.db.raidTeam and addon.db.raidTeam.seasonStart
    if type(value) ~= "number" or value <= 0 then return nil end
    return value
end

function RaidTeam:SetSeasonStart(epoch)
    addon.db.raidTeam = addon.db.raidTeam or {}
    if type(epoch) ~= "number" or epoch <= 0 then
        addon.db.raidTeam.seasonStart = nil
    else
        addon.db.raidTeam.seasonStart = epoch
    end
    addon.Log:I("RaidTeam", "season start set to",
        epoch and date("!%Y/%m/%d", epoch) or "unset")
    addon.Callbacks:Fire("RaidTeamChanged")
end


function RaidTeam:CheckSeason()
    addon.db.raidTeam = addon.db.raidTeam or {}
    local db = addon.db.raidTeam

    local id = CurrentSeasonID()
    if not id then return end

    if db.seasonId == nil then

        db.seasonId = id
        addon.Log:I("RaidTeam", "season", id, "recorded; start date not yet known")
        return
    end

    if db.seasonId ~= id then
        db.seasonId = id
        db.seasonStart = GetServerTime()
        addon.Log:I("RaidTeam", "season rolled over to", id, "- start date stamped",
            date("!%Y/%m/%d", db.seasonStart))
        addon.Callbacks:Fire("RaidTeamChanged")
    end
end





function RaidTeam:Init()
    addon.db.raidTeam = addon.db.raidTeam or {}

    local f = CreateFrame("Frame")
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_GUILD_UPDATE")

    f:RegisterEvent("INITIAL_CLUBS_LOADED")
    f:SetScript("OnEvent", function(_, event)

        if event == "PLAYER_GUILD_UPDATE" then lastReadable = nil end
        RaidTeam:Invalidate()
        addon.Callbacks:Fire("RaidTeamChanged")
    end)



    if addon.Restrictions then
        addon.Restrictions:OnChange(function(isBlocked)
            if isBlocked or not unreadable then return end
            addon.Log:D("RaidTeam", "blackout lifted after an unreadable roster - reading it again")
            RaidTeam:Invalidate()
            RaidTeam:Request()
            addon.Callbacks:Fire("RaidTeamChanged")
        end)
    end

    RaidTeam:CheckSeason()

    addon.Log:I("RaidTeam", "ready, guild", tostring(RaidTeam:GetGuildName()),
        RaidTeam:CountSelectedRanks(), "rank(s) marked as raiders, season",
        tostring(addon.db.raidTeam.seasonId),
        RaidTeam:GetSeasonStart()
            and ("from " .. date("!%Y/%m/%d", RaidTeam:GetSeasonStart()))
            or "(start date not yet known)")
end
