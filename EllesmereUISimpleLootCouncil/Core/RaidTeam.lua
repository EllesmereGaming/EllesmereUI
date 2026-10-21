if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local RaidTeam = {}
addon.RaidTeam = RaidTeam



local ROSTER_TTL = 60

local roster, rosterAt = nil, 0

local lastReadable, unreadable = nil, false


local presenceStale = false







local IsSecret = addon.IsSecret







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



local classNames = {}
local function ClassOf(classID)
    local known = classNames[classID]
    if not known then
        local classInfo = C_CreatureInfo.GetClassInfo(classID)
        if not classInfo then return nil, nil end
        known = { classInfo.classFile, classInfo.className }
        classNames[classID] = known
    end
    return known[1], known[2]
end


local function BuildMember(was, guid, name, classFile, className, level, zone, rank,
        rankOrder, online, mobile, note, officerNote)
    if not name or name == "" then return nil end


    if not note or note == "" or IsSecret(note) then note = nil end
    if not officerNote or officerNote == "" or IsSecret(officerNote) then officerNote = nil end


    local fullName = addon.Player:Qualify(name) or name
    if was and was.guid == guid and was.name == name and was.fullName == fullName
        and was.classFile == classFile and was.className == className
        and was.level == level and was.zone == zone and was.rank == rank
        and was.rankOrder == rankOrder and was.online == online and was.mobile == mobile
        and was.note == note and was.officerNote == officerNote then
        return was
    end

    return {
        guid        = guid,
        name        = name,
        fullName    = fullName,
        classFile   = classFile,
        className   = className,
        level       = level,
        zone        = zone,
        rank        = rank,
        rankOrder   = rankOrder,
        online      = online,
        mobile      = mobile,
        note        = note,
        officerNote = officerNote,
    }
end

local function FromClub(info, canViewOfficer, was)
    if IsSecret(info.name, info.guid, info.guildRank) then return nil end
    local classFile, className
    if info.classID and not IsSecret(info.classID) then
        classFile, className = ClassOf(info.classID)
    end

    return BuildMember(was, info.guid, info.name, classFile, className, info.level, info.zone,
        info.guildRank, info.guildRankOrder or 99,
        ONLINE_PRESENCE[info.presence] and true or false,
        info.presence == Presence.OnlineMobile, info.memberNote,
        canViewOfficer and info.officerNote or nil)
end



local listSuffix, listSuffixOf = nil, nil
local function RosterListSize()
    if addon.IsForever or not GetGuildRosterInfo or not GetNumGuildMembers then return nil end
    local total = GetNumGuildMembers()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if IsSecret(total, realm) or type(total) ~= "number" or total == 0
        or type(realm) ~= "string" or realm == "" then
        return nil
    end
    if realm ~= listSuffixOf then listSuffix, listSuffixOf = "-" .. realm, realm end
    return total, listSuffix
end



local function ReadRosterList(canViewOfficer, previous)

    local total, suffix = RosterListSize()
    if not total then return nil end
    local built = {}
    for i = 1, total do
        local name, rank, rankIndex, level, className, zone, note, officerNote, isOnline, _,
            classFile, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)

        if type(name) ~= "string" or IsSecret(name, rank, rankIndex, guid, classFile, className)
            or type(rankIndex) ~= "number" then
            return nil
        end
        if name:sub(-#suffix) == suffix then name = name:sub(1, -#suffix - 1) end
        local member = BuildMember(previous[guid], guid, name, classFile, className, level, zone,
            rank, rankIndex + 1, (isOnline or isMobile) and true or false, isMobile and true or false,
            note, canViewOfficer and officerNote or nil)
        if member then built[#built + 1] = member end
    end
    return built
end


local function Unreadable()
    unreadable = true
    return lastReadable or {}, false
end



local lastAsked = nil


local guidIndex, guidIndexOf = {}, nil
local function GuidIndex(list)
    if list ~= guidIndexOf then
        guidIndex, guidIndexOf = {}, list
        for _, member in ipairs(list or {}) do
            if member.guid then guidIndex[member.guid] = member end
        end
    end
    return guidIndex
end



local reported = {}


local function Read(force, ranksOnly)
    if roster and not force and (ranksOnly or not presenceStale)
        and (GetTime() - rosterAt) < ROSTER_TTL then
        return roster, true
    end

    local built = {}

    if IsInGuild() then


        local canViewOfficer = C_GuildInfo and C_GuildInfo.CanViewOfficerNote
            and C_GuildInfo.CanViewOfficerNote() or false

        local previous = GuidIndex(lastReadable)

        local list = ReadRosterList(canViewOfficer, previous)
        if list then
            built = list
        else

            local clubId = C_Club.GetGuildClubId()
            if not clubId then return Unreadable() end


            local ids = C_Club.GetClubMembers(clubId)

            if IsSecret(ids) or type(ids) ~= "table" or #ids == 0 then return Unreadable() end
            for _, memberId in ipairs(ids) do
                local info = C_Club.GetMemberInfo(clubId, memberId)

                if IsSecret(info) or (info and IsSecret(info.name, info.guid, info.guildRank)) then
                    return Unreadable()
                end
                local member = info and FromClub(info, canViewOfficer, previous[info.guid])
                if member then built[#built + 1] = member end
            end
        end
    end

    roster, rosterAt = built, GetTime()
    lastReadable, unreadable = built, false
    presenceStale = false
    for guid in pairs(reported) do reported[guid] = nil end
    return roster, true
end




function RaidTeam:GetRoster(force)
    lastAsked = GetTime()
    return Read(force)
end



local index, indexOf = {}, nil
function RaidTeam:GetRosterIndex()


    local list, readable = Read(false, true)
    if list ~= indexOf then
        index, indexOf = {}, list
        for _, member in ipairs(list) do
            if member.fullName then index[member.fullName] = member end
        end
    end
    return index, readable
end



local function Compare(old, new)
    if not old or #old ~= #new then return "identity" end
    local byGUID = {}
    for _, member in ipairs(old) do
        if member.guid then byGUID[member.guid] = member end
    end
    local what
    for _, member in ipairs(new) do
        local was = member.guid and byGUID[member.guid]
        if not was or was.name ~= member.name or was.rank ~= member.rank
            or was.rankOrder ~= member.rankOrder or was.classFile ~= member.classFile then
            return "identity"
        end
        if not what and (was.online ~= member.online or was.mobile ~= member.mobile
            or was.level ~= member.level or was.zone ~= member.zone or was.note ~= member.note
            or was.officerNote ~= member.officerNote) then
            what = "presence"
        end
    end
    return what
end
RaidTeam.Compare = Compare

local function PresenceDiffers(m, online, mobile, level, zone, note, officerNote)
    return m.online ~= online or m.mobile ~= mobile or m.level ~= level or m.zone ~= zone
        or m.note ~= note or m.officerNote ~= officerNote
end




local function Walk(old)
    local total, suffix = RosterListSize()
    if not total then return false end
    local canViewOfficer = C_GuildInfo and C_GuildInfo.CanViewOfficerNote
        and C_GuildInfo.CanViewOfficerNote() or false
    local byGUID = GuidIndex(old)
    local count, what = 0, nil
    for i = 1, total do
        local name, rank, rankIndex, level, className, zone, note, officerNote, isOnline, _,
            classFile, _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
        if type(name) ~= "string" or IsSecret(name, rank, rankIndex, guid, classFile, className)
            or type(rankIndex) ~= "number" then
            return false
        end

        if name ~= "" then
            count = count + 1

            if name:find(suffix, -#suffix, true) then name = name:sub(1, -#suffix - 1) end
            local was = byGUID[guid]
            if not was or was.name ~= name or was.rank ~= rank
                or was.rankOrder ~= rankIndex + 1 or was.classFile ~= classFile then
                return "identity"
            end
            local online, mobile = (isOnline or isMobile) and true or false, isMobile and true or false
            if not note or note == "" or IsSecret(note) then note = nil end
            officerNote = canViewOfficer and officerNote or nil
            if not officerNote or officerNote == "" or IsSecret(officerNote) then officerNote = nil end
            local seen = reported[guid]
            if PresenceDiffers(seen or was, online, mobile, level, zone, note, officerNote) then
                what = "presence"
                if not PresenceDiffers(was, online, mobile, level, zone, note, officerNote) then
                    reported[guid] = nil
                else
                    seen = seen or {}
                    seen.online, seen.mobile, seen.level, seen.zone = online, mobile, level, zone
                    seen.note, seen.officerNote = note, officerNote
                    reported[guid] = seen
                end
            end
        end
    end
    if count ~= #old then return "identity" end
    return what
end



function RaidTeam:GetMembers()
    local members = {}
    local set = Selection(false)
    if not set then return members end
    for _, member in ipairs(RaidTeam:GetRoster()) do
        if member.rank and set[member.rank] then
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

    local keyOf = {}

    addon.History.EachEntry(function(entry)
        local winner = entry.winner
        if not winner then return end
        local key = keyOf[winner]
        if key == nil then
            local main = foldAlts and addon.Player:Main(winner)
                or addon.Player:Qualify(winner) or winner
            key = main and addon.Player:NameKey(main) or false
            keyOf[winner] = key
        end
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


local NO_LOOT = {}
function RaidTeam:LootFor(index, member)
    if not index or not member or not member.fullName then return NO_LOOT end

    local key = member.nameKey
    if key == nil or member.nameKeyOf ~= member.fullName then
        key = addon.Player:NameKey(member.fullName) or false
        member.nameKey, member.nameKeyOf = key, member.fullName
    end
    return (key and index[key]) or NO_LOOT
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
    local year, month, day
    local a, b, c = text:match("^%s*(%d+)[/%-%.](%d+)[/%-%.](%d+)%s*$")
    if a and #a == 4 then
        year, month, day = tonumber(a), tonumber(b), tonumber(c)
    elseif a and #c == 4 then
        year, month, day = tonumber(c), tonumber(b), tonumber(a)
    else
        local digits = text:match("^%s*(%d+)%s*$")
        if not digits or #digits ~= 8 then return nil end
        year, month, day = tonumber(digits:sub(1, 4)), tonumber(digits:sub(5, 6)),
            tonumber(digits:sub(7, 8))
    end
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







local CHECK_SETTLE, CHECK_INTERVAL, CHECK_INTEREST = 2, 10, 300
local checkPending, lastCheck = false, nil

local function ReaderAsked()
    return lastAsked ~= nil and GetTime() - lastAsked < CHECK_INTEREST
end


local function InUse()
    if IsInGroup() and addon.Council and addon.Council.HasRankRule
        and addon.Council:HasRankRule() then
        return true
    end
    return ReaderAsked()
end

local function CheckRoster()

    if InCombatLockdown() then
        addon.CombatQueue.Defer("RaidTeam.check", CheckRoster)
        return
    end
    checkPending, lastCheck = false, GetTime()


    if roster and not unreadable and not ReaderAsked() then
        local what = Walk(roster)
        if what == nil or what == "presence" then
            rosterAt = GetTime()
            if what == "presence" then
                presenceStale = true
                addon.Callbacks:Fire("GuildPresenceChanged")
            end
            return
        end
    end
    local old = roster or lastReadable
    local new, readable = Read(true)

    if not readable then return end
    local what = Compare(old, new)
    if what == "identity" then
        addon.Log:D("RaidTeam", "guild roster changed -", #new, "members")
        addon.Callbacks:Fire("RaidTeamChanged")
    elseif what == "presence" then
        addon.Callbacks:Fire("GuildPresenceChanged")
    end
end
RaidTeam.CheckRoster = CheckRoster

local function OnRosterUpdate()
    if not InUse() then
        RaidTeam:Invalidate()
        return
    end
    if checkPending then return end
    checkPending = true
    local wait = CHECK_SETTLE
    if lastCheck then wait = math.max(wait, lastCheck + CHECK_INTERVAL - GetTime()) end
    C_Timer.After(wait, CheckRoster)
end

function RaidTeam:Init()
    addon.db.raidTeam = addon.db.raidTeam or {}

    local f = CreateFrame("Frame")
    f:RegisterEvent("GUILD_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_GUILD_UPDATE")

    f:RegisterEvent("INITIAL_CLUBS_LOADED")
    f:SetScript("OnEvent", function(_, event)

        if event == "GUILD_ROSTER_UPDATE" then return OnRosterUpdate() end

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
