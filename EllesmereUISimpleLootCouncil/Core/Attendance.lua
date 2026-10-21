if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end






SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Attendance = {}
addon.Attendance = Attendance


local DIFFICULTY_RAID_TIMEWALKER = 33

local tracking = false
local function OnEncounterEnded(entry)
    Attendance:RecordPull(entry)
end







local NIGHT_GAP = 4 * 60 * 60


local RETENTION = 365 * 24 * 60 * 60



local function NormaliseAgainstStore(store, name)
    if type(name) ~= "string" or name == "" then return name end
    if name:find("-", 1, true) then return name end



    local Fold = addon.Locale.Fold
    local wanted = Fold(name)
    for _, night in ipairs((store and store.nights) or {}) do
        for member in pairs(night.members or {}) do
            local bare = member:match("^([^%-]+)")
            if bare and Fold(bare) == wanted then return member end
        end
    end
    return name
end
Attendance.NormaliseAgainstStore = NormaliseAgainstStore




function Attendance.Apply(store, pull)
    if type(store) ~= "table" or type(pull) ~= "table" then return false end
    if type(pull.id) ~= "string" or pull.id == "" then return false end

    store.nights = store.nights or {}
    local nights = store.nights

    for _, night in ipairs(nights) do
        if night.seen and night.seen[pull.id] then return false end
    end

    local epoch = tonumber(pull.id:match("^(%d+)")) or 0

    local night = nights[#nights]
    if not night or not night.endedAt or (epoch - night.endedAt) > NIGHT_GAP then
        night = {
            startedAt = epoch, endedAt = epoch,
            pulls = 0, kills = 0, members = {}, memberKills = {}, seen = {},
        }
        nights[#nights + 1] = night
    end

    night.seen[pull.id] = true
    night.pulls = night.pulls + 1
    if pull.k == 1 or pull.k == true then
        night.kills = night.kills + 1
    end
    if epoch > (night.endedAt or 0) then night.endedAt = epoch end

    night.members = night.members or {}

    local memberKills = (pull.k == 1 or pull.k == true) and night.memberKills
    if type(pull.p) == "table" then
        for _, member in ipairs(pull.p) do
            if type(member) == "string" and member ~= "" then
                night.members[member] = (night.members[member] or 0) + 1
                if memberKills then
                    memberKills[member] = (memberKills[member] or 0) + 1
                end
            end
        end
    end

    return true
end


function Attendance.Prune(store, now)
    if type(store) ~= "table" then return 0 end
    store.nights = store.nights or {}
    local nights = store.nights
    local cutoff = (now or 0) - RETENTION
    local dropped = 0

    while #nights > 0 do
        local night = nights[1]
        if (night.endedAt or night.startedAt or 0) >= cutoff then break end
        table.remove(nights, 1)
        dropped = dropped + 1
    end

    return dropped
end

local WEEK = 7 * 24 * 60 * 60
Attendance.WEEK = WEEK


function Attendance.WeekStart(epoch, anchor)
    return anchor + math.floor(((epoch or 0) - anchor) / WEEK) * WEEK
end



function Attendance.Weeks(store, anchor)
    local weeks, byStart = {}, {}
    local nights = (store and store.nights) or {}
    for i = #nights, 1, -1 do
        local night = nights[i]
        local start = Attendance.WeekStart(night.startedAt or 0, anchor)
        local week = byStart[start]
        if not week then
            week = { start = start, finish = start + WEEK, nights = {}, pulls = 0, kills = 0 }
            byStart[start] = week
            weeks[#weeks + 1] = week
        end
        week.nights[#week.nights + 1] = night
        week.pulls = week.pulls + (night.pulls or 0)
        week.kills = week.kills + (night.kills or 0)
    end
    table.sort(weeks, function(a, b) return a.start > b.start end)
    return weeks
end





function Attendance.Clear(store, nights, match, removed)
    if type(store) ~= "table" or type(store.nights) ~= "table" then return 0, 0 end

    local chosen
    if nights then
        chosen = {}
        for _, night in ipairs(nights) do chosen[night] = true end
    end

    local removedNights, removedEntries = 0, 0
    local kept = {}
    for _, night in ipairs(store.nights) do
        local inScope = not chosen or chosen[night]
        if inScope and not match then
            removedNights = removedNights + 1
            if removed then removed(night) end
        else
            if inScope then
                for name in pairs(night.members or {}) do
                    if match(name) then
                        night.members[name] = nil
                        if night.memberKills then night.memberKills[name] = nil end
                        removedEntries = removedEntries + 1
                        if removed then removed(night, name) end
                    end
                end
            end
            kept[#kept + 1] = night
        end
    end
    store.nights = kept
    return removedNights, removedEntries
end



function Attendance.Compute(store, name, since)
    name = NormaliseAgainstStore(store, name)
    local nights = (store and store.nights) or {}

    local firstSeen
    for _, night in ipairs(nights) do
        if night.members and night.members[name] then
            firstSeen = night.startedAt
            break
        end
    end

    if not firstSeen then
        return { nights = 0, attended = 0, pulls = 0, pullsAttended = 0, firstSeen = nil }
    end

    local totalNights, attendedNights = 0, 0
    local totalPulls, pullsAttended = 0, 0

    for _, night in ipairs(nights) do
        local started = night.startedAt or 0
        if started >= firstSeen and (not since or started >= since) then
            totalNights = totalNights + 1
            totalPulls = totalPulls + (night.pulls or 0)
            local present = night.members and night.members[name]
            if present then
                attendedNights = attendedNights + 1
                pullsAttended = pullsAttended + present
            end
        end
    end

    return {
        nights = totalNights,
        attended = attendedNights,
        pulls = totalPulls,
        pullsAttended = pullsAttended,
        firstSeen = firstSeen,
    }
end






function Attendance:For(name, since)

    return Attendance.Compute(addon.db.attendance or { nights = {} },
        addon.Player:Qualify(name), since)
end

function Attendance:GetNights()
    return (addon.db.attendance and addon.db.attendance.nights) or {}
end



function Attendance:WeekAnchor()
    local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
        and C_DateAndTime.GetSecondsUntilWeeklyReset()

    if type(untilReset) == "number" then return math.floor((GetServerTime() + untilReset) / 60 + 0.5) * 60 end
    return 4 * 24 * 60 * 60
end

function Attendance:GetWeeks()
    return Attendance.Weeks(addon.db.attendance, Attendance:WeekAnchor())
end



function Attendance.Matcher(roster, ranks, players)
    ranks, players = ranks or {}, players or {}
    if not next(ranks) and not next(players) then return nil end
    local keys = {}
    for _, member in ipairs(roster or {}) do
        if member.rank and ranks[member.rank] then
            local key = addon.Player:NameKey(member.fullName)
            if key then keys[key] = true end
        end
    end
    return function(name)
        return players[name] == true or keys[addon.Player:NameKey(name) or ""] == true
    end
end


local function Forget(night, name)
    local shared = addon.SharedSaved
    local key = shared and shared.NightKey(night)
    if not key then return end
    if name then
        shared.Forget(addon.db, "members", shared.MemberKey(key, name))
    else
        shared.Forget(addon.db, "nights", key)
    end
end


function Attendance:ClearNights(nights, match)
    local store = addon.db.attendance
    local removedNights, removedEntries = Attendance.Clear(store, nights, match, Forget)
    addon.Log:I("Attendance", "cleared", removedNights, "night(s),",
        removedEntries, "player entr(ies)")
    if removedNights + removedEntries > 0 then
        addon.Callbacks:Fire("AttendanceChanged")
    end
    return removedNights, removedEntries
end

function Attendance:ClearAll()
    local store = addon.db.attendance
    local count = store and store.nights and #store.nights or 0
    for _, night in ipairs(store and store.nights or {}) do Forget(night) end
    addon.db.attendance = { nights = {} }
    addon.Log:I("Attendance", "cleared all,", count, "night(s)")
    if count > 0 then addon.Callbacks:Fire("AttendanceChanged") end
    return count
end






function Attendance:ApplyReceived(payload, sender)
    if type(payload) ~= "table" or type(payload.id) ~= "string" then return end

    addon.db.attendance = addon.db.attendance or { nights = {} }
    local store = addon.db.attendance

    local names, unresolved, total = {}, 0, 0
    if type(payload.p) == "table" then
        for _, short in ipairs(payload.p) do
            total = total + 1
            local record = addon.Player:Get(short)

            if record.guid and not record.unresolved then
                names[#names + 1] = record.fullName
            else
                unresolved = unresolved + 1
            end
        end
    end

    local applied = Attendance.Apply(store, {
        id = payload.id, e = payload.e, n = payload.n,
        d = payload.d, k = payload.k, p = names,
    })

    Attendance.Prune(store, GetServerTime())

    if applied then
        if unresolved > 0 then
            addon.Log:WLogOnly("Attendance", ("%d of %d names unresolved, pull %s")
                :format(unresolved, total, payload.id))
        end
        addon.Log:I("Attendance", "recorded pull", tostring(payload.n),
            #names, "present, from", tostring(sender))
        if addon.Callbacks then addon.Callbacks:Fire("AttendanceChanged") end
    end
end



function Attendance:RecordPull(entry)
    if not entry or not entry.id then return end
    if not addon.PlayerIsMasterLooter() then return end


    if not addon.db.recordAttendance then return end


    local _, instanceType, difficultyID = GetInstanceInfo()
    if not IsInRaid() or instanceType ~= "raid" then
        addon.Log:D("Attendance", "not a raid pull - not recorded", tostring(entry.name),
            tostring(instanceType))
        return
    end

    local legacy = C_Loot and C_Loot.IsLegacyLootModeEnabled and C_Loot.IsLegacyLootModeEnabled()
    if legacy or difficultyID == DIFFICULTY_RAID_TIMEWALKER then
        addon.Log:D("Attendance", "old-content raid pull - not recorded", tostring(entry.name),
            legacy and "legacy loot" or "timewalking")
        return
    end

    local transmit = {}
    for name in pairs(addon.GetCandidates()) do
        local short = addon.Player:ForTransmit(name)
        if short then transmit[#transmit + 1] = short end
    end


    table.sort(transmit)

    local payload = {
        id = ("%d-%d"):format(GetServerTime(), entry.id),
        e = entry.id,
        n = entry.name,
        d = entry.difficultyID,
        k = entry.success and 1 or 0,
        p = transmit,
    }

    addon.Comms:Send("pull", payload, nil, true)

    Attendance:ApplyReceived(payload, addon.Player:GetFullName("player"))
end


function Attendance:SetEnabled(enabled)
    enabled = enabled and true or false
    if enabled == tracking then return end

    tracking = enabled
    if tracking then
        addon.Callbacks:Register("EncounterEnded", OnEncounterEnded)
    else
        addon.Callbacks:Unregister("EncounterEnded", OnEncounterEnded)
    end
end





function Attendance:Init()
    addon.db.attendance = addon.db.attendance or { nights = {} }
    Attendance.Prune(addon.db.attendance, GetServerTime())

    addon.Comms:Register("pull", "ml", function(payload, sender)
        Attendance:ApplyReceived(payload, sender)
    end)

    Attendance:SetEnabled(addon.db.recordAttendance)

    addon.Log:I("Attendance", "ready,", #addon.db.attendance.nights, "night(s) recorded")
end
