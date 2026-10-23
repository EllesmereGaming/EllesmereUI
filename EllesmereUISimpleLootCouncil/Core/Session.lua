if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Session = {}
addon.Session = Session




local STATUS = addon.Locale.Texts{
    ANNOUNCED = { text = T["Waiting"],     sort = 500 },
    PASS      = { text = T["Pass"],        sort = 800 },
    NOTHING   = { text = T["No response"], sort = 810 },
    NO_ADDON  = { text = T["No addon?"],   sort = 815 },
    AWARDED   = { text = T["Awarded"],     sort = 0.1 },
}
Session.STATUS = STATUS

local run = {
    active = false,
    items = {},


    completed = {},


    deliveredSeen = {},


    coins = {},
    startedAt = nil,
}
Session.run = run

local idCounter = 0
local SNAPSHOT_VERSION = 1
local SNAPSHOT_MAX_AGE = 12 * 60 * 60
local recoveryRefusalKey

local AnnounceRunState


local AnswerHeldForRebuild


local WatchBags


local drops = {}


local Refused = { copy = nil, filled = {} }

local function NextId()
    idCounter = idCounter + 1
    return ("%d-%d"):format(GetServerTime(), idCounter)
end

local function CopyMap(source)
    local copy = {}
    if type(source) ~= "table" then return copy end
    for key, value in pairs(source) do
        local kind = type(value)
        if kind == "string" or kind == "number" or kind == "boolean" then
            copy[key] = value
        elseif kind == "table" then
            copy[key] = CopyMap(value)
        end
    end
    return copy
end

local function GroupKey()
    local names = {}
    for name in pairs(addon.GetCandidates() or {}) do names[#names + 1] = name end
    table.sort(names)
    return table.concat(names, "\0")
end



local refusedSeen = {}
local function Refuse(what, why, sender)
    local key = ("%s\0%s\0%s"):format(tostring(sender), what, why)
    if refusedSeen[key] then return end
    refusedSeen[key] = true
    addon.Log:WLogOnly("Session", what, "refused -", why, "from", tostring(sender))
end



local RESPONSES_MAX = 7


local function ResponseIndex(value)
    if value == nil then return nil end
    local index = tonumber(value)
    if index and index % 1 == 0 and index >= 1 and index <= RESPONSES_MAX then
        return index
    end
    return false
end


local function CleanNote(note)
    if type(note) ~= "string" then return nil end
    note = addon.Locale.Truncate(note, addon.Config:NoteMax())
    return note ~= "" and note or nil
end

local function Snapshot(candidateName)
    if not run.active or type(run.id) ~= "string" then return nil end

    local items = {}
    for index, item in ipairs(run.items) do
        items[index] = CopyMap(item)
        if candidateName then
            items[index].candidates = {}
            if item.candidates and item.candidates[candidateName] then
                items[index].candidates[candidateName] = CopyMap(item.candidates[candidateName])
            end
        end
    end

    return {
        snapshotVersion = SNAPSHOT_VERSION,
        candidateOnly = candidateName,
        runId = run.id,
        items = items,
        lootMaster = run.lootMaster,
        groupKey = run.groupKey,
        timer = run.duration,
        expiresAt = run.expiresAt,
        savedAt = GetServerTime(),


        coins = CopyMap(run.coins),
    }
end



function Session:GetSnapshot(candidateName)
    return Snapshot(candidateName)
end




local function OwnsBackup()
    if not run.active or not run.id then return false end
    local me = addon.Player:GetFullName("player")
    if not me then return false end
    if run.backupOwner and addon.Player:IsSame(run.backupOwner, me) then return true end
    local prior = addon.db and addon.db.activeRun
    return type(prior) == "table" and prior.runId == run.id
        and addon.Player:IsSame(prior.lootMaster, me)
end



local function GroupRun()
    return run.grouped == true
end

local function NoteAuthority()
    if not run.active then return end
    if not IsInGroup() and GroupRun() then return end
    local current = addon.GetMasterLooter and addon.GetMasterLooter()
    if current and not addon.Player:IsSame(run.lootMaster, current) then
        run.lootMaster = current
        addon.Log:I("Session", "run loot master is now", current)
    end
    if addon.PlayerIsMasterLooter() then
        run.backupOwner = addon.Player:GetFullName("player")
    end
end




function Session:SaveRun()
    if not addon.db or not run.active then return end
    local me = addon.Player:GetFullName("player")
    if not me then return end
    NoteAuthority()
    local scrub = addon.Perf and addon.Perf.seededRun == run.id and addon.Perf.ScrubSynthetic
    if (IsInGroup() or not GroupRun()) and (addon.PlayerIsMasterLooter() or OwnsBackup()) then


        run.groupKey = GroupKey()
        local saved = Snapshot() or {}
        saved.lootMaster = me

        if scrub then scrub(saved.items) end
        addon.db.activeRun = saved

        addon.db.runCopy = {}
    else


        addon.db.activeRun = {}


        local council = addon.Council and addon.Council:Contains(me)
        local copy = Snapshot(not council and me or nil) or {}
        if scrub and copy.items then scrub(copy.items) end
        addon.db.runCopy = copy
    end
end

local function ClearPersisted()
    if addon.db then
        addon.db.activeRun = {}
        addon.db.noteDrafts = nil
    end
end

local function SnapshotValid(payload)
    if type(payload) ~= "table"
        or payload.snapshotVersion ~= SNAPSHOT_VERSION
        or type(payload.runId) ~= "string"
        or type(payload.items) ~= "table"
        or #payload.items == 0
        or type(payload.lootMaster) ~= "string"
        or type(payload.groupKey) ~= "string"
        or (payload.candidateOnly ~= nil and type(payload.candidateOnly) ~= "string")
        or type(payload.savedAt) ~= "number"
        or payload.savedAt > GetServerTime() + 60
        or GetServerTime() - payload.savedAt > SNAPSHOT_MAX_AGE then
        return false
    end
    for index, item in ipairs(payload.items) do
        if type(item) ~= "table" or type(item.link) ~= "string"
            or type(item.candidates) ~= "table" then
            return false
        end
        item.session = index
        for name, candidate in pairs(item.candidates) do
            if type(name) ~= "string" or type(candidate) ~= "table" then return false end
            if type(candidate.voters) ~= "table" then candidate.voters = {} end
        end
    end
    return true
end



local RECOVERY_REFUSED_TEXT = addon.Locale.Texts{
    roster = T["could not restore the saved loot run because the group roster changed during the reload; asking the group for a current copy."],
}
local RECOVERY_REFUSED_LOG = {
    roster = "the group roster changed during reload",
}

function Session:RecoverPersisted()
    if run.active or not addon.db then return false end
    local saved = addon.db.activeRun
    if not SnapshotValid(saved) then
        addon.db.activeRun = {}
        return false
    end

    local me = addon.Player:GetFullName("player")
    if not me then return false end
    if not addon.Player:IsSame(saved.lootMaster, me) then


        addon.db.activeRun = {}
        addon.Log:D("Session", "discarded saved run owned by",
            saved.lootMaster, "while recovering as", me)
        return false
    end
    if not IsInGroup() then
        for _, item in ipairs(saved.items) do
            for name in pairs(item.candidates) do
                if not addon.Player:IsSame(name, me) then
                    addon.db.activeRun = {}
                    addon.Log:I("Session", "discarded saved group run", tostring(saved.runId),
                        "- not in a group")
                    return false
                end
            end
        end
    end
    if saved.groupKey ~= GroupKey() then
        local reason = "roster"
        local key = tostring(saved.runId) .. "\0" .. reason
        if recoveryRefusalKey ~= key then
            recoveryRefusalKey = key
            addon.Log:WLogOnly("Session", "saved run not restored -", RECOVERY_REFUSED_LOG[reason],
                "- asking the group for a current copy")
            addon.Chat.Print(addon.Locale.Format(RECOVERY_REFUSED_TEXT[reason]))
        end

        Refused.copy = saved
        return false
    end

    Session:ApplyRunStart(saved, me, true)
    recoveryRefusalKey = nil
    if run.active and IsInGroup() then Session.Split.Resync() end
    return run.active
end







local Split = {

    WHOLE_UP_TO = 10,


    SPREAD = 2,


    FILL_AFTER = 4,
    FILL_WAIT = 30,

    STASH_MAX = 64,

    skeletonOf = {},
}
Session.Split = Split


local assembling

local stash, stashed = {}, 0








local HOLD_SECONDS = 90
local HOLD_MAX = 256
local held, holdUntil, holdOverflowed = {}, 0, false


local function DropHeld(why)
    if #held > 0 then
        addon.Log:I("Session", "discarding", #held, "frame(s) held for a recovery -", why)
    end
    held, holdOverflowed = {}, false

    stash, stashed = {}, 0
end


local function OpenHold()
    holdUntil = GetTime() + HOLD_SECONDS
end



local asked = {}
local function Asked()
    return asked.at ~= nil and GetTime() - asked.at <= HOLD_SECONDS
end


local function CloseAsk(why)
    if asked.at == nil then return end
    asked.at, asked.copyRun, asked.copyMaster = nil, nil, nil
    addon.Log:D("Session", "recovery replies no longer taken -", why)
end

local function CloseHold(why)
    holdUntil = 0
    DropHeld(why)
    CloseAsk(why)
end

local function Holding()
    if run.active then return false end
    if holdUntil == 0 then return false end
    if GetTime() > holdUntil then
        CloseHold("expired")
        return false
    end
    return true
end



function Session:HoldForRecovery(command, args, sender, handler)
    if not Holding() then return false end
    if #held >= HOLD_MAX then
        table.remove(held, 1)
        if not holdOverflowed then
            holdOverflowed = true
            addon.Log:W("Session", "recovery hold full - dropping the oldest held frames")
        end
    end
    held[#held + 1] = { command = command, args = args, sender = sender, handler = handler }
    addon.Log:D("Session", "holding", command, "from", tostring(sender), "until the run arrives")
    return true
end



local function ReplayHeld()
    holdUntil = 0
    if #held == 0 then return end
    local list = held
    held, holdOverflowed = {}, false
    addon.Log:I("Session", "replaying", #list, "frame(s) held during recovery")
    for _, entry in ipairs(list) do
        local stamped = type(entry.args) == "table" and entry.args.i or nil
        if addon.Comms.IsStale and addon.Comms.IsStale(stamped, run.id) then
            addon.Log:I("Session", "stale held", entry.command, "for run", tostring(stamped),
                "- current run is", tostring(run.id))
        else
            local ok, err = pcall(entry.handler, entry.args, entry.sender)
            if not ok then
                addon.Log:Bug("Session", ("held %s failed: %s"):format(
                    tostring(entry.command), tostring(err)))
            end
        end
    end
end









local OWNED = { "note", "gear1", "gear2", "diff", "ilvl", "setCount", "setID",
    "sockets1", "sockets2", "setReplaces" }
local OWNED_SET = {}
for _, key in ipairs(OWNED) do OWNED_SET[key] = true end
local ANSWERS = { RESPONDED = true, PASS = true }

local IsSecret = addon.IsSecret


local ROW_STATUS = { ANNOUNCED = true, RESPONDED = true, PASS = true, NOTHING = true,
    NO_ADDON = true, AWARDED = true }
local ROLL_BY = { player = true, leader = true }

local RAID_MAX = 40

local function Bounded(value, low, high)
    return type(value) == "number" and value >= low and value <= high and value or nil
end



local function CleanAnswer(status, response)
    local index = ResponseIndex(response)
    if index == false then return status == "RESPONDED" and "ANNOUNCED" or status, nil end
    return status, index
end



local function CleanRow(row)
    if type(row) ~= "table" then return nil end
    local clean = { voters = {} }
    clean.status, clean.response = CleanAnswer(
        ROW_STATUS[row.status] and row.status or "ANNOUNCED", row.response)
    if row.realStatus ~= "AWARDED" and ROW_STATUS[row.realStatus] then
        clean.realStatus, clean.realResponse = CleanAnswer(row.realStatus, row.realResponse)
    end
    clean.note = CleanNote(row.note)
    clean.overridden = row.overridden == true or nil
    clean.viaWhisper = row.viaWhisper == true or nil
    local count = 0
    for voter, on in pairs(type(row.voters) == "table" and row.voters or {}) do
        if type(voter) == "string" and on == true and count < RAID_MAX then
            clean.voters[voter], count = true, count + 1
        end
    end
    if addon.Gear then
        for _, key in ipairs(OWNED) do
            if key ~= "note" then clean[key] = addon.Gear.CleanField(key, row[key]) end
        end
    end
    clean.roll = Bounded(row.roll, -2 ^ 31, 2 ^ 31)
    clean.rollBy = ROLL_BY[row.rollBy] and row.rollBy or nil
    clean.rollSeq = Bounded(row.rollSeq, 0, 2 ^ 31)
    clean.rollGen = Bounded(row.rollGen, 0, 2 ^ 31)
    return clean
end
Session.CleanRow = CleanRow



function Split.OwnerRow(candidate)
    if type(candidate) ~= "table" then return nil end
    local row, any = {}, false
    local status = candidate.status
    if ANSWERS[status] then
        row.status, row.response, any = status, candidate.response, true
    elseif status == "AWARDED" and ANSWERS[candidate.realStatus] then
        row.realStatus, row.realResponse, row.response, any =
            candidate.realStatus, candidate.realResponse, candidate.response, true
    end
    for _, key in ipairs(OWNED) do
        if candidate[key] ~= nil then row[key], any = candidate[key], true end
    end
    return any and row or nil
end


local function VotesKept(voters, voting)
    local kept
    for voter in pairs(voters or {}) do
        if not voting[voter] then
            kept = kept or {}
            kept[voter] = true
        end
    end
    return kept
end



local function MasterRow(candidate, voting)
    local row, any = {}, false
    local whispered = candidate.viaWhisper
    local answered = whispered or candidate.overridden
    for key, value in pairs(candidate) do
        local keep
        if key == "voters" or key == "roll" or key == "rollBy" or key == "rollSeq" then
            keep = false
        elseif key == "status" then


            keep = answered or not (ANSWERS[value] or value == "ANNOUNCED")
        elseif key == "realStatus" then

            keep = answered or not ANSWERS[value]
        elseif key == "response" or key == "realResponse" then
            keep = answered
        elseif OWNED_SET[key] then
            keep = whispered
        else
            keep = true
        end
        if keep then
            local kind = type(value)
            if kind == "table" then
                row[key], any = CopyMap(value), true
            elseif kind == "string" or kind == "number" or kind == "boolean" then
                row[key], any = value, true
            end
        end
    end
    local kept = VotesKept(candidate.voters, voting)
    if kept then row.voters, any = kept, true end
    return any and row or nil
end



local function Online(name)
    local unit = addon.Player.UnitFor and addon.Player:UnitFor(name)
    if not unit or not UnitIsConnected then return true end
    local connected = UnitIsConnected(unit)
    if IsSecret(connected) then return true end
    return connected and true or false
end



function Split.Senders(requester)
    local me = addon.Player:GetFullName("player")
    local rows, votes = {}, {}
    for name in pairs(addon.GetCandidates() or {}) do
        if not addon.Player:IsSame(name, me) and not addon.Player:IsSame(name, requester)
            and not (addon.Perf and addon.Perf.IsSynthetic and addon.Perf.IsSynthetic(name))
            and addon.Version and addon.Version:Knows(name) and Online(name) then
            rows[name] = true
            if addon.Council and addon.Council:Contains(name) then votes[name] = true end
        end
    end
    return rows, votes
end




function Split.Skeleton(sending, voting, source)
    local r = source or run
    if not r.active or type(r.id) ~= "string" then return nil, 0, 0 end



    local rollNames, named = {}, {}
    for _, item in ipairs(r.items) do
        for name, candidate in pairs(item.candidates or {}) do
            if sending[name] and candidate.roll ~= nil and not named[name] then
                named[name] = true
                rollNames[#rollNames + 1] = name
            end
        end
    end
    table.sort(rollNames)

    local items, heard, whole = {}, {}, {}
    for index, item in ipairs(r.items) do
        local copy = {}
        for key, value in pairs(item) do
            if key ~= "candidates" then
                local kind = type(value)
                if kind == "table" then
                    copy[key] = CopyMap(value)
                elseif kind == "string" or kind == "number" or kind == "boolean" then
                    copy[key] = value
                end
            end
        end
        local rows = {}
        for name, candidate in pairs(item.candidates or {}) do
            if sending[name] then
                rows[name] = MasterRow(candidate, voting)
                if Split.OwnerRow(candidate) then heard[name] = true end
            else
                local row = CopyMap(candidate)
                row.voters = VotesKept(candidate.voters, voting)
                rows[name] = row
                whole[name] = true
            end
            for voter in pairs(candidate.voters or {}) do
                if voting[voter] then heard[voter] = true end
            end
        end
        copy.candidates = rows
        if #rollNames > 0 then
            local list, any = {}, false
            for i, name in ipairs(rollNames) do
                local candidate = item.candidates and item.candidates[name]
                if candidate and candidate.roll ~= nil then

                    list[i] = { candidate.roll, candidate.rollBy or false,
                        candidate.rollSeq or false }
                    any = true
                else
                    list[i] = 0
                end
            end
            if any then copy.rl = list end
        end
        items[index] = copy
    end

    local expected, voters, wholeCount = {}, {}, 0
    for name in pairs(heard) do expected[#expected + 1] = name end
    table.sort(expected)
    for name in pairs(voting) do voters[#voters + 1] = name end
    table.sort(voters)
    for _ in pairs(whole) do wholeCount = wholeCount + 1 end
    return {
        snapshotVersion = SNAPSHOT_VERSION,
        runId = r.id,
        items = items,
        lootMaster = r.lootMaster,
        groupKey = r.groupKey,
        timer = r.duration,
        expiresAt = r.expiresAt,
        savedAt = GetServerTime(),
        coins = CopyMap(r.coins),
        rn = #rollNames > 0 and rollNames or nil,
        parts = { e = expected, v = voters },
    }, #expected, wholeCount
end



function Split.Send(requester, current)
    local whole = Snapshot()
    if not whole then return false end
    local frames
    if addon.Comms.Measure then
        frames = select(2, addon.Comms:Measure("run_start", whole))
    end
    if frames and frames <= Split.WHOLE_UP_TO then
        addon.Log:D("Session", "full recovery for", requester, "- the run fits one burst,",
            frames, "frame(s)")
        return false
    end
    local sending, voting = Split.Senders(requester)
    local skeleton, expected, wholeRows = Split.Skeleton(sending, voting)
    if not skeleton or expected == 0 then
        addon.Log:D("Session", "full recovery for", requester,
            "- nobody else holds anything to send")
        return false
    end
    skeleton.lootMaster = current or run.lootMaster
    addon.Log:D("Session", "split recovery for", requester, "-", #skeleton.items,
        "items, whole rows for", wholeRows, "candidate(s) from my copy,", expected,
        "holder(s) asked (full:", tostring(frames), "frames)")
    addon.Comms:Send("run_start", skeleton, requester, true)
    addon.Comms:Send("run_help", { w = requester }, nil, true)
    Split.skeletonOf[requester] = run.id
    return true
end




function Split.OwnPart(me, source)
    local r = source or run
    if not r.active or not me then return nil end
    local items, rows, lists = {}, 0, 0
    for index, item in ipairs(r.items) do
        local entry
        local row = Split.OwnerRow(item.candidates and item.candidates[me])
        if row then
            entry = { c = { [me] = row } }
            rows = rows + 1
        end
        local list
        for name, candidate in pairs(item.candidates or {}) do
            if candidate.voters and candidate.voters[me] then
                list = list or {}
                list[#list + 1] = name
            end
        end
        if list then
            table.sort(list)
            entry = entry or {}
            entry.v = { [me] = list }
            lists = lists + 1
        end
        if entry then
            entry.s, entry.id = index, item.id
            items[#items + 1] = entry
        end
    end
    if rows == 0 and lists == 0 then return nil, 0, 0 end
    local voter = lists > 0 or (addon.Council and addon.Council:Contains(me))
    return { p = 1, i = r.id, n = #r.items, items = items,
        vv = voter and { me } or nil }, rows, lists
end



function Split.Measure(snapshot, requester)
    local source = {
        active = true, id = snapshot.runId, items = snapshot.items,
        lootMaster = snapshot.lootMaster, groupKey = snapshot.groupKey,
        duration = snapshot.timer, expiresAt = snapshot.expiresAt, coins = snapshot.coins,
    }
    local sending = {}
    for _, item in ipairs(snapshot.items) do
        for name in pairs(item.candidates or {}) do
            if name ~= snapshot.lootMaster and name ~= requester then sending[name] = true end
        end
    end
    local skeleton = Split.Skeleton(sending, sending, source)
    if not skeleton then return nil end
    local out = { parts = 0, bytes = 0, frames = 0, largestBytes = 0, largestFrames = 0 }
    out.skeletonBytes, out.skeletonFrames = addon.Comms:Measure("run_start", skeleton)
    if not out.skeletonBytes then return nil end
    for name in pairs(sending) do
        local part = Split.OwnPart(name, source)
        if part then
            local bytes, frames = addon.Comms:Measure("run_reply", part)
            if not bytes then return nil end
            out.parts = out.parts + 1
            out.bytes, out.frames = out.bytes + bytes, out.frames + frames
            if bytes > out.largestBytes then
                out.largestBytes, out.largestFrames = bytes, frames
            end
        end
    end
    return out
end



function Split.Fill(names)
    local wanted, list = {}, {}
    for _, name in ipairs(type(names) == "table" and names or {}) do
        if type(name) == "string" and not wanted[name] and #list < 80 then
            wanted[name] = true
            list[#list + 1] = name
        end
    end
    local items = {}
    for index, item in ipairs(run.items) do
        local entry
        for name in pairs(wanted) do
            local row = Split.OwnerRow(item.candidates and item.candidates[name])
            if row then
                entry = entry or {}
                entry.c = entry.c or {}
                entry.c[name] = row
            end
        end
        for name, candidate in pairs(item.candidates or {}) do
            for voter in pairs(candidate.voters or {}) do
                if wanted[voter] then
                    entry = entry or {}
                    entry.v = entry.v or {}
                    entry.v[voter] = entry.v[voter] or {}
                    local votes = entry.v[voter]
                    votes[#votes + 1] = name
                end
            end
        end
        if entry then
            entry.s, entry.id = index, item.id
            items[#items + 1] = entry
        end
    end
    return { p = 1, f = 1, i = run.id, n = #run.items, items = items, vv = list }
end



local function DecodeRolls(names)
    for _, item in ipairs(run.items) do
        local list = item.rl
        item.rl = nil
        if type(list) == "table" and type(names) == "table" then
            for i, name in ipairs(names) do
                local roll = list[i]
                if type(roll) == "table" and type(name) == "string" then
                    local candidate = item.candidates[name]
                    if not candidate then
                        candidate = { status = "ANNOUNCED", voters = {} }
                        item.candidates[name] = candidate
                    end
                    candidate.roll = tonumber(roll[1])
                    candidate.rollBy = type(roll[2]) == "string" and roll[2] or nil
                    candidate.rollSeq = tonumber(roll[3])
                end
            end
        end
    end
end



local function Unfill(session, name)
    local marks = session and Refused.filled[session]
    if marks and name then marks[name] = nil end
end

local function Touch(session, name, answer, note, gear)
    Unfill(session, name)
    local state = assembling
    if not state or not session or not name then return end
    local rows = state.live[session]
    if not rows then
        rows = {}
        state.live[session] = rows
    end
    local cell = rows[name]
    if not cell then
        cell = {}
        rows[name] = cell
    end
    if answer then cell.answer = true end
    if note then cell.note = true end
    if gear then cell.gear = true end
end

local function TouchVote(session, name, voter)
    Unfill(session, name)
    local state = assembling
    if not state or not session or not name or not voter then return end
    state.liveVotes[tostring(session) .. "\0" .. name .. "\0" .. voter] = true
end

local function OpenAssembly(payload, sender)
    local parts = payload.parts
    local expected, count, voters = {}, 0, {}
    for _, name in ipairs(type(parts.e) == "table" and parts.e or {}) do
        if type(name) == "string" and not expected[name] then
            expected[name] = true
            count = count + 1
        end
    end
    for _, name in ipairs(type(parts.v) == "table" and parts.v or {}) do
        if type(name) == "string" then voters[name] = true end
    end
    assembling = {
        runId = run.id,
        sender = sender,
        from = addon.Player:Get(sender).fullName or sender,
        at = GetTime(),
        expected = expected,
        expecting = count,
        voters = voters,
        got = {},
        gotCount = 0,
        live = {},
        liveVotes = {},
    }
    addon.Log:D("Session", "split recovery from", tostring(sender), "- expecting",
        count, "part(s)")
end

local function AssemblyDone(filled)
    local state = assembling
    if not state then return end
    assembling = nil
    addon.Log:I("Session", "run recovered in parts from", tostring(state.from) .. ":",
        state.gotCount .. "/" .. state.expecting, "holder(s)",
        filled and (filled .. " filled by the loot master") or "",
        ("in %.1fs"):format(GetTime() - state.at))
    if addon.Callbacks then addon.Callbacks:Fire("SessionChanged", nil, "run") end
end

local function CheckAssembled()
    local state = assembling
    if not state then return end
    for name in pairs(state.expected) do
        if not state.got[name] then return end
    end
    AssemblyDone()
end



local function Blocked()
    return addon.Restrictions and addon.Restrictions:IsBlocked() or false
end



Split.RESYNC_WAIT = 30

function Split.Resync()
    if not run.active or type(run.id) ~= "string" or not IsInGroup() then return false end
    local me = addon.Player:GetFullName("player")
    if not me then return false end
    if Blocked() then
        Split.resyncFor = run.id
        addon.Log:I("Session", "recovered run: asking the group to re-send after the blackout")
        return false
    end
    Split.resyncFor = nil
    local expected, count, voters = {}, 0, {}
    for name in pairs(addon.GetCandidates() or {}) do
        if not addon.Player:IsSame(name, me) then
            expected[name] = true
            count = count + 1
        end
    end
    if count == 0 then return false end
    for _, item in ipairs(run.items) do
        for _, candidate in pairs(item.candidates or {}) do
            for voter in pairs(candidate.voters or {}) do voters[voter] = true end
        end
    end
    local state = {
        runId = run.id,
        sender = me,
        from = me,
        at = GetTime(),
        expected = expected,
        expecting = count,
        voters = voters,
        got = {},
        gotCount = 0,
        live = {},
        liveVotes = {},
        resync = true,
    }
    assembling = state
    addon.Log:I("Session", "recovered run: asking", count,
        "group member(s) to re-send their answers and votes")
    addon.Comms:Send("run_help", { w = me }, nil, true)
    C_Timer.After(Split.RESYNC_WAIT, function()
        if assembling == state then AssemblyDone() end
    end)
    return true
end



local function ScheduleFill(runId)
    C_Timer.After(Split.FILL_AFTER, function()
        local state = assembling
        if not state or state.runId ~= runId then return end
        if not run.active or run.id ~= runId then
            assembling = nil
            return
        end
        if Blocked() then return ScheduleFill(runId) end
        local missing = {}
        for name in pairs(state.expected) do
            if not state.got[name] then missing[#missing + 1] = name end
        end
        if #missing == 0 then return AssemblyDone() end
        table.sort(missing)
        state.asked = missing
        addon.Log:I("Session", "asking the loot master for", #missing, "missing part(s):",
            table.concat(missing, ", "))
        addon.Comms:Send("run_fill", { w = missing }, state.sender, true)
        local function GiveUp()
            if assembling ~= state then return end
            if Blocked() then return C_Timer.After(Split.FILL_WAIT, GiveUp) end
            assembling = nil
            addon.Log:W("Session", "split recovery incomplete -", #missing,
                "holder(s) never answered and no fill arrived:", table.concat(missing, ", "))
        end
        C_Timer.After(Split.FILL_WAIT, GiveUp)
    end)
end



local function MergeRow(item, index, name, row, fill)
    local candidate = item.candidates[name]
    if not candidate then
        candidate = { status = "ANNOUNCED", voters = {} }
        item.candidates[name] = candidate
    end
    local rows = assembling.live[index]
    local live = rows and rows[name]
    local whispered = candidate.viaWhisper
    if not (live and live.answer) and (fill or not (whispered or candidate.overridden)) then
        local status, response = CleanAnswer(row.status, row.response)
        local realStatus, realResponse = CleanAnswer(row.realStatus, row.realResponse)

        if candidate.status == "AWARDED" then
            if ANSWERS[realStatus] then
                candidate.realStatus, candidate.realResponse = realStatus, realResponse
                candidate.response = response
            elseif ANSWERS[status] then
                candidate.realStatus, candidate.realResponse = status, response
            end
        elseif ANSWERS[status] then
            candidate.status, candidate.response = status, response
        elseif ANSWERS[realStatus] then
            candidate.status, candidate.response = realStatus, realResponse
        end
    end
    if not (live and live.note) and (fill or not whispered) then
        candidate.note = CleanNote(row.note)
    end
    if not (live and live.gear) and (fill or not whispered) and addon.Gear then
        for _, key in ipairs(OWNED) do
            if key ~= "note" then candidate[key] = addon.Gear.CleanField(key, row[key]) end
        end
    end
end



local function MergeVotes(item, index, voter, list)
    local wanted = {}
    if type(list) == "table" then
        for n, name in ipairs(list) do
            if n > RAID_MAX then break end
            if type(name) == "string" then wanted[name] = true end
        end
    end
    local prefix = tostring(index) .. "\0"
    for name, candidate in pairs(item.candidates) do
        if not assembling.liveVotes[prefix .. name .. "\0" .. voter] then
            candidate.voters = candidate.voters or {}
            candidate.voters[voter] = wanted[name] or nil
        end
    end
    for name in pairs(wanted) do
        if not item.candidates[name] then
            item.candidates[name] = { status = "ANNOUNCED", voters = { [voter] = true } }
        end
    end
end



function Session:ApplyRunPart(payload, sender)
    if type(payload) ~= "table" or type(payload.items) ~= "table"
        or type(payload.i) ~= "string" then
        return false
    end

    if not run.active then
        if not Holding() then return false end
        if not stash[sender] then
            if stashed >= Split.STASH_MAX then
                addon.Log:WLogOnly("Session", "too many recovery parts before the run - dropping one from",
                    tostring(sender))
                return false
            end
            stashed = stashed + 1
        end
        stash[sender] = payload
        addon.Log:D("Session", "keeping a recovery part from", tostring(sender),
            "until the run arrives")
        return true
    end

    local state = assembling
    if not state or state.runId ~= run.id or payload.i ~= run.id then
        addon.Log:D("Session", "recovery part from", tostring(sender),
            "ignored - not assembling that run")
        return false
    end
    local from = addon.Player:Get(sender).fullName or sender
    local fill = payload.f and true or false
    if fill then
        if not state.asked or not addon.Player:IsSame(from, state.from) then
            addon.Log:WLogOnly("Session", "recovery fill from", tostring(sender),
                "refused - it was not asked of them")
            return false
        end
    else
        if state.got[from] then
            addon.Log:D("Session", "recovery part from", tostring(sender), "already applied")
            return false
        end
        if not (state.expected[from] or (addon.GetCandidates() or {})[from]) then
            addon.Log:WLogOnly("Session", "recovery part from someone outside the group",
                tostring(sender))
            return false
        end
    end


    local entries = {}
    for _, entry in ipairs(payload.items) do
        local index = type(entry) == "table" and tonumber(entry.s)
        if not index or entries[index]
            or (entry.c ~= nil and type(entry.c) ~= "table")
            or (entry.v ~= nil and type(entry.v) ~= "table") then
            addon.Log:WLogOnly("Session", "malformed recovery part from", tostring(sender))
            return false
        end
        for name, row in pairs(entry.c or {}) do
            if type(name) ~= "string" or type(row) ~= "table" then
                addon.Log:WLogOnly("Session", "malformed recovery part from", tostring(sender))
                return false
            end
            if not fill and not addon.Player:IsSame(name, from) then
                addon.Log:WLogOnly("Session", "recovery part claims another candidate",
                    tostring(name), "from", tostring(sender))
                return false
            end
        end
        for voter, list in pairs(entry.v or {}) do
            if type(voter) ~= "string" or type(list) ~= "table" then
                addon.Log:WLogOnly("Session", "malformed recovery part from", tostring(sender))
                return false
            end
            if not fill and not addon.Player:IsSame(voter, from) then
                addon.Log:WLogOnly("Session", "recovery part claims another voter's votes",
                    tostring(voter), "from", tostring(sender))
                return false
            end
        end
        entries[index] = entry
    end
    local voters = {}
    for _, voter in ipairs(type(payload.vv) == "table" and payload.vv or {}) do
        if type(voter) == "string" then
            if fill then
                voters[voter] = true
            elseif not addon.Player:IsSame(voter, from) then
                addon.Log:WLogOnly("Session", "recovery part claims another voter's votes",
                    tostring(voter), "from", tostring(sender))
                return false
            elseif state.voters[voter]
                or (addon.Council and addon.Council:Contains(voter)) then
                voters[voter] = true
            else
                addon.Log:D("Session", "votes in a recovery part not taken -", tostring(voter),
                    "is not on the council")
            end
        end
    end

    local rows, lists = 0, 0
    local covered = math.min(tonumber(payload.n) or #run.items, #run.items)
    for index = 1, covered do
        local item = run.items[index]
        local entry = entries[index]
        if entry and entry.id ~= item.id then
            addon.Log:WLogOnly("Session", "recovery part item mismatch", index, "from", tostring(sender))
        else
            for name, row in pairs(entry and entry.c or {}) do
                MergeRow(item, index, name, row, fill)
                rows = rows + 1
            end
            for voter in pairs(voters) do
                local list = entry and entry.v and entry.v[voter]
                if list then lists = lists + 1 end
                MergeVotes(item, index, voter, list)
            end
        end
    end

    if fill then
        addon.Log:D("Session", "recovery fill from", tostring(sender), rows, "row(s),",
            lists, "vote list(s)")
        AssemblyDone(#state.asked)
        return true
    end
    state.got[from] = true
    if state.expected[from] then state.gotCount = state.gotCount + 1 end
    addon.Log:D("Session", "recovery part from", tostring(sender), rows, "row(s),", lists,
        "vote list(s)", "(" .. state.gotCount .. "/" .. state.expecting .. ")")
    CheckAssembled()
    if assembling and addon.Callbacks then
        addon.Callbacks:Fire("SessionChanged", nil, "run")
    end
    return true
end


local function MergeStash()
    if stashed == 0 then return end
    local pending = stash
    stash, stashed = {}, 0
    for sender, payload in pairs(pending) do
        if payload.i == run.id then Session:ApplyRunPart(payload, sender) end
    end
end









local RunCopy = {

    BURST = 10,

    VOTES_WAIT = 60,
}
Session.RunCopy = RunCopy



local heldCopy, heldAsk, heldRefused

local pendingVotes




local PRIME = 4294967291
local byte = string.byte


local function StringHash(text, cache)
    local hash = cache[text]
    if hash then return hash end
    local length, i = #text, 1
    hash = length
    while i + 7 <= length do
        local a, b, c, d, e, f, g, h = byte(text, i, i + 7)
        hash = (hash * 1000003 + ((a * 256 + b) * 256 + c) * 256 + d) % PRIME
        hash = (hash * 1000003 + ((e * 256 + f) * 256 + g) * 256 + h) % PRIME
        i = i + 8
    end
    while i <= length do
        hash = (hash * 131 + byte(text, i)) % PRIME
        i = i + 1
    end
    cache[text] = hash
    return hash
end

local function Mix(a, b)
    return (a * 1000003 + b) % PRIME
end



local function NumberText(value)
    if value % 1 == 0 and value > -2 ^ 53 and value < 2 ^ 53 then
        return ("%.0f"):format(value)
    end
    return ("%.10g"):format(value)
end



local function ValueHash(value, cache)
    if IsSecret(value) then return nil end
    local kind = type(value)
    if kind == "string" then return Mix(1, StringHash(value, cache)) end
    if kind == "number" then return Mix(2, StringHash(NumberText(value), cache)) end
    if kind == "boolean" then return value and 3 or 4 end
    if kind ~= "table" then return nil end
    local sum, count = 0, 0
    for key, entry in pairs(value) do
        local hash = ValueHash(entry, cache)
        if hash then
            sum = (sum + Mix(ValueHash(key, cache) or 0, hash)) % PRIME
            count = count + 1
        end
    end
    if count == 0 then return nil end
    return Mix(Mix(5, sum), count)
end


local function RowHash(row, cache)
    if type(row) ~= "table" then return nil end
    local sum, count, blank = 0, 0, true
    for key, value in pairs(row) do
        local hash = ValueHash(value, cache)
        if hash then
            if not (key == "status" and value == "ANNOUNCED") then blank = false end
            sum = (sum + Mix(ValueHash(key, cache) or 0, hash)) % PRIME
            count = count + 1
        end
    end
    if blank then return nil end
    return Mix(Mix(5, sum), count)
end


local LOCAL_FIELDS = {
    session = true, sweepDue = true, reasonText = true, reasonLogged = true,
    rl = true, candidates = true,
}



function RunCopy.Fingerprint(item, name, cache)
    cache = cache or {}
    local sum, count = 0, 0
    for key, value in pairs(item) do
        if not LOCAL_FIELDS[key] then
            local hash = ValueHash(value, cache)
            if hash then
                sum = (sum + Mix(ValueHash(key, cache) or 0, hash)) % PRIME
                count = count + 1
            end
        end
    end
    local candidates = type(item.candidates) == "table" and item.candidates or {}
    local rows
    if name then
        rows = RowHash(candidates[name], cache)
    else
        local total, n = 0, 0
        for who, row in pairs(candidates) do
            local hash = RowHash(row, cache)
            if hash then
                total = (total + Mix(ValueHash(who, cache) or 0, hash)) % PRIME
                n = n + 1
            end
        end
        rows = n > 0 and Mix(Mix(5, total), n) or nil
    end
    return Mix(Mix(Mix(6, sum), count), rows or 0)
end


function RunCopy.CoinsFingerprint(coins, cache)
    cache = cache or {}
    local sum, count = 0, 0
    for _, coin in pairs(type(coins) == "table" and coins or {}) do
        local hash = ValueHash(coin, cache)
        if hash then sum, count = (sum + hash) % PRIME, count + 1 end
    end
    return Mix(Mix(7, sum), count)
end



function RunCopy.Load()
    heldCopy, heldAsk, heldRefused = nil, nil, false
    local saved = addon.db and addon.db.runCopy
    if type(saved) ~= "table" or saved.runId == nil then return end
    if not SnapshotValid(saved) then
        addon.db.runCopy = {}
        addon.Log:D("Session", "saved copy of the run discarded - expired or malformed")
        return
    end
    heldCopy = saved
    addon.Log:D("Session", "holding my saved copy of run", saved.runId, "-", #saved.items,
        "item(s), until the loot master confirms it")
end


function RunCopy.Drop(why)
    if not heldCopy then return end
    addon.Log:D("Session", "saved copy of run", tostring(heldCopy.runId), "put away -", why,
        "- the live run is", tostring(run.active and run.id or nil))
    heldCopy, heldAsk, heldRefused = nil, nil, false
    if addon.db then addon.db.runCopy = {} end
end



function RunCopy.Ask()
    local copy = heldCopy
    if not copy or heldRefused then return nil end
    if not heldAsk then
        local cache, list = {}, {}
        local name = copy.candidateOnly
        for index, item in ipairs(copy.items) do
            list[index] = RunCopy.Fingerprint(item, name, cache)
        end
        heldAsk = { i = copy.runId, w = name == nil and 1 or nil, f = list,
            k = RunCopy.CoinsFingerprint(copy.coins, cache) }
    end
    return heldAsk
end


function RunCopy.Request()
    local ask = not addon.PlayerIsMasterLooter() and RunCopy.Ask() or nil
    return { d = 1, h = ask }
end




function RunCopy.Delta(ask, requester, council, source)
    local r = source or run
    if type(ask) ~= "table" or not r.active or ask.i ~= r.id
        or type(ask.f) ~= "table" or #ask.f > #r.items then
        return nil
    end
    if (ask.w ~= nil) ~= (council and true or false) then return nil end
    local name = not council and requester or nil
    local cache, items = {}, {}
    for index, item in ipairs(r.items) do
        if tonumber(ask.f[index]) ~= RunCopy.Fingerprint(item, name, cache) then
            local entry = {}
            for key, value in pairs(item) do
                if key ~= "candidates" then
                    local kind = type(value)
                    if kind == "table" then
                        entry[key] = CopyMap(value)
                    elseif kind == "string" or kind == "number" or kind == "boolean" then
                        entry[key] = value
                    end
                end
            end
            if name then
                local row = item.candidates and item.candidates[name]
                entry.candidates = { [name] = row and CopyMap(row) or nil }
            else
                entry.candidates = CopyMap(item.candidates)
            end
            entry.s = index
            items[#items + 1] = entry
        end
    end
    local payload = {
        snapshotVersion = SNAPSHOT_VERSION,
        runId = r.id,
        items = items,
        dl = #r.items,
        candidateOnly = name,

        lootMaster = r.lootMaster,
        timer = r.duration,
        expiresAt = r.expiresAt,
        savedAt = GetServerTime(),
    }
    if tonumber(ask.k) ~= RunCopy.CoinsFingerprint(r.coins, cache) then
        payload.coins = CopyMap(r.coins)
    end
    return payload, #items
end


function RunCopy.Merge(delta)
    local copy = heldCopy
    if not copy or copy.runId ~= delta.runId then return nil, "no_copy" end
    local count = tonumber(delta.dl)
    if not count or count < #copy.items or type(delta.items) ~= "table" then
        return nil, "count"
    end
    if (delta.candidateOnly == nil) ~= (copy.candidateOnly == nil) then
        return nil, "shape"
    end
    local items = {}
    for index = 1, count do items[index] = copy.items[index] end
    for _, entry in ipairs(delta.items) do
        local index = type(entry) == "table" and tonumber(entry.s)
        if not index or index < 1 or index > count or index % 1 ~= 0 then
            return nil, "malformed"
        end
        entry.s = nil
        items[index] = entry
    end
    local merged = {
        snapshotVersion = SNAPSHOT_VERSION,
        runId = delta.runId,
        items = items,
        candidateOnly = delta.candidateOnly,
        lootMaster = delta.lootMaster,
        groupKey = delta.groupKey or copy.groupKey,
        timer = delta.timer,
        expiresAt = delta.expiresAt,
        savedAt = delta.savedAt,
        coins = delta.coins or copy.coins,
    }
    for index = 1, count do
        if type(items[index]) ~= "table" then
            return nil, "missing_item"
        end
    end
    if not SnapshotValid(merged) then return nil, "invalid" end
    return merged
end



local function Answered(row)
    return row ~= nil and (ANSWERS[row.status] or row.status == "AWARDED"
        or row.overridden or row.viaWhisper) and true or false
end



local function CopyClaims(copy, me)
    local answers, votes = {}, {}
    for index, saved in ipairs(copy.items) do
        local item = run.items[index]
        if item and item.id == saved.id and not item.awarded and not item.removed
            and (not item.gone or item.gone == "pending") and type(saved.candidates) == "table" then
            local mine = saved.candidates[me]
            if type(mine) == "table" and ANSWERS[mine.status]
                and not Answered(item.candidates[me]) then
                answers[#answers + 1] = {
                    s = index,
                    r = mine.status == "RESPONDED" and tonumber(mine.response) or nil,
                    n = type(mine.note) == "string" and mine.note or nil,
                }
            end
            if copy.candidateOnly == nil then
                for name, row in pairs(item.candidates) do
                    local was = saved.candidates[name]
                    local had = type(was) == "table" and type(was.voters) == "table"
                        and was.voters[me] == true
                    local has = row.voters ~= nil and row.voters[me] == true
                    if had ~= has then votes[#votes + 1] = { s = index, c = name, v = had } end
                end
            end
        end
    end
    table.sort(votes, function(a, b)
        if a.v ~= b.v then return not a.v end
        if a.s ~= b.s then return a.s < b.s end
        return a.c < b.c
    end)
    return answers, votes
end


function RunCopy.SendVotes()
    local pending = pendingVotes
    if not pending then return end
    if not run.active or run.id ~= pending.runId or GetTime() > pending.untilAt then
        pendingVotes = nil
        return
    end
    local me = addon.Player:GetFullName("player")
    if not me or not (addon.Council and addon.Council:Contains(me)) then return end
    pendingVotes = nil
    local _, votes = CopyClaims(pending.copy, me)
    local sent = 0
    for _, vote in ipairs(votes) do
        if Session:Vote(vote.s, vote.c, vote.v) then sent = sent + 1 end
    end
    if sent > 0 then
        addon.Log:I("Session", "cast", sent, "vote(s) again from my saved copy -",
            "the run came back without them")
    end
end



function RunCopy.Settle()
    local copy = heldCopy
    if not copy then return end
    local same = copy.runId == run.id
    RunCopy.Drop(same and "recovered" or "other_run")
    if not same then return end
    local me = addon.Player:GetFullName("player")
    if not me then return end
    local answers, votes = CopyClaims(copy, me)
    local sent = 0
    for _, answer in ipairs(answers) do
        if Session:Respond(answer.s, answer.r, answer.n) then sent = sent + 1 end
    end
    if sent > 0 then
        addon.Log:I("Session", "sent", sent, "answer(s) again from my saved copy -",
            "the run came back without them")
    end
    if #votes > 0 then
        pendingVotes = { copy = copy, runId = run.id, untilAt = GetTime() + RunCopy.VOTES_WAIT }
        RunCopy.SendVotes()
    end
end



function RunCopy.Measure(snapshot, requester, raider)
    local source = {
        active = true, id = snapshot.runId, items = snapshot.items,
        lootMaster = snapshot.lootMaster, groupKey = snapshot.groupKey,
        duration = snapshot.timer, expiresAt = snapshot.expiresAt, coins = snapshot.coins,
    }

    local function Size(command, payload)
        if not payload then return nil end
        local bytes, frames = addon.Comms:Measure(command, payload)
        return bytes and { bytes = bytes, frames = frames } or nil
    end
    local function Sizes(whole, name)
        local cache, list = {}, {}
        for index, item in ipairs(snapshot.items) do
            list[index] = RunCopy.Fingerprint(item, not whole and name or nil, cache)
        end
        local ask = { i = snapshot.runId, w = whole and 1 or nil, f = list,
            k = RunCopy.CoinsFingerprint(snapshot.coins, cache) }
        local changed = {}
        for key, value in pairs(ask) do changed[key] = value end
        changed.f = {}
        for index, hash in ipairs(list) do changed.f[index] = index == 1 and 0 or hash end
        return {
            ask = Size("run_request", { d = 1, h = ask }),
            same = Size("run_start", (RunCopy.Delta(ask, name, whole, source))),
            one = Size("run_start", (RunCopy.Delta(changed, name, whole, source))),
        }
    end
    local out = { council = Sizes(true, requester), raider = Sizes(false, raider) }
    for _, sizes in pairs(out) do
        if not (sizes.ask and sizes.same and sizes.one) then return nil end
    end
    return out
end



local function AskForRun(args, target)
    OpenHold()
    asked.at = GetTime()
    asked.copyRun = heldCopy and heldCopy.runId or nil
    asked.copyMaster = heldCopy and heldCopy.lootMaster or nil
    addon.Comms:Send("run_request", args, target, true)
end
Session.AskForRun = AskForRun





function Session:IsRunning()
    return run.active
end



function Session:GetRunLootMaster()
    return run.active and run.lootMaster or nil
end


function Session:GetItems()
    return run.items
end



function Session:GetItem(session)
    if run.active then return run.items[session] end
    return run.completed[session]
end



function Session:GetCoins()
    return run.coins
end



function Session:GetVoteCount(session, candidateName)
    local item = run.items[session]
    if not item then return 0 end
    local candidate = item.candidates[candidateName]
    if not candidate then return 0 end

    local n = 0
    for _ in pairs(candidate.voters) do n = n + 1 end
    return n
end

function Session:HasVoted(session, voterName)
    local item = run.items[session]
    if not item then return false end
    for _, candidate in pairs(item.candidates) do
        if candidate.voters[voterName] then return true end
    end
    return false
end





local function NewCandidateSet()
    local set = {}
    for fullName in pairs(addon.GetCandidates()) do
        set[fullName] = {
            status = "ANNOUNCED",
            response = nil,
            note = nil,
            voters = {},
        }
    end
    return set
end




local bossLookups = {}

local function FindItemById(id)
    for _, item in ipairs(run.items) do
        if item.id == id then return item end
    end
    for _, item in pairs(run.completed) do
        if item.id == id then return item end
    end
    return nil
end

local function ResolveMissingBoss(item)
    if type(item) ~= "table" or item.boss or item.simulated then return end
    if not item.id or type(item.link) ~= "string" then return end
    if bossLookups[item.id] then return end
    if not (addon.Encounter and addon.Encounter.JournalBossForLink) then return end

    local id, link = item.id, item.link
    bossLookups[id] = true
    addon.Encounter:JournalBossForLink(link, function(boss, detail, encounterID)
        bossLookups[id] = nil
        local current = FindItemById(id)
        if not current then
            addon.Log:D("Session", "journal boss for", link, "arrived after the item was gone")
            return
        end
        if current.boss then return end
        if not boss then
            addon.Log:D("Session", "no boss for", link, "- encounter log had none and",
                tostring(detail))
            return
        end


        current.boss = boss
        current.encounterID = encounterID
        addon.Log:I("Session", "boss for", link, "from the Adventure Guide -",
            boss, "(no kill in the encounter log)")
        if addon.Callbacks then
            addon.Callbacks:Fire("SessionChanged", current.session, "item")
        end
    end)
end
Session.ResolveMissingBoss = ResolveMissingBoss

local function ResolveMissingBosses()
    for _, item in ipairs(run.items) do ResolveMissingBoss(item) end
end





local function AppendItem(itemLink, owner, boss, encounterID, simulated, difficultyID)


    if not run.active and run.ended then
        run.ended = false
    end

    local index = #run.items + 1
    run.items[index] = {
        id = NextId(),
        session = index,
        link = itemLink,
        owner = owner,
        boss = boss,
        encounterID = tonumber(encounterID),
        simulated = simulated and true or nil,
        difficultyID = simulated and tonumber(difficultyID) or nil,
        awarded = nil,
        delivered = false,
        candidates = {},
    }


    if run.active then
        run.items[index].candidates = NewCandidateSet()
    end

    addon.Log:I("Session", "item added", index, itemLink)
    ResolveMissingBoss(run.items[index])
    if WatchBags then WatchBags() end
    return index
end



local function AnsweredAnywhere()
    local answered = {}
    for _, item in ipairs(run.items) do
        for name, candidate in pairs(item.candidates or {}) do
            local status = candidate.status
            if status == "AWARDED" then status = candidate.realStatus end
            if status == "RESPONDED" or status == "PASS" then answered[name] = true end
        end
    end
    return answered
end




local function SweepVerdict(indices)
    local answered, verdict, list, judged = AnsweredAnywhere(), {}, {}, {}
    for _, index in ipairs(indices) do
        local item = run.items[index]
        for name in pairs(item and item.candidates or {}) do
            if not judged[name] then
                judged[name] = true
                if not (answered[name] or (addon.Version and addon.Version:Knows(name))) then
                    verdict[name] = true
                    list[#list + 1] = name
                end
            end
        end
    end
    table.sort(list)
    return verdict, list
end




local sweepsWaiting = {}

local function ScheduleSweep(runId, indices, delay)
    local scheduled = {}
    for _, index in ipairs(indices) do scheduled[#scheduled + 1] = index end
    local wait = delay or (10 + 0.5 * #scheduled)
    local due = GetServerTime() + math.ceil(wait)
    for _, index in ipairs(scheduled) do
        if run.items[index] then run.items[index].sweepDue = due end
    end
    C_Timer.After(wait, function()
        if run.active and run.id == runId and addon.PlayerIsMasterLooter() then
            if Blocked() then
                sweepsWaiting[#sweepsWaiting + 1] = { runId = runId, indices = scheduled }
                addon.Log:D("Session", "sweep waits for the blackout to lift", tostring(runId))
                return
            end
            local verdict, list = SweepVerdict(scheduled)

            addon.Log:Hold()
            addon.Comms:Send("sweep", { s = scheduled, j = 1, na = #list > 0 and list or nil },
                nil, true)
            Session:ApplySweep(scheduled, verdict)
            addon.Log:Release()
        else
            addon.Log:D("Session", "sweep skipped, run moved on", tostring(runId))
        end
    end)
end


local function ResumeSweeps()
    if #sweepsWaiting == 0 then return end
    local list = sweepsWaiting
    sweepsWaiting = {}
    for _, entry in ipairs(list) do
        if run.active and run.id == entry.runId then ScheduleSweep(entry.runId, entry.indices) end
    end
end


local RECOVERED_SWEEP_GRACE = 10


local function ScheduleRecoveredSweep()
    if not run.active or not addon.PlayerIsMasterLooter() then return end

    local pending, wait = {}, RECOVERED_SWEEP_GRACE
    local now = GetServerTime()
    for index, item in ipairs(run.items) do
        local waiting = false
        if not item.awarded and not item.removed then
            for _, candidate in pairs(item.candidates or {}) do
                if candidate.status == "ANNOUNCED" then waiting = true break end
            end
        end
        if waiting then
            pending[#pending + 1] = index
            local due = tonumber(item.sweepDue)
            if due and due - now > wait then wait = due - now end
        end
    end
    if #pending == 0 then return end

    addon.Log:I("Session", "recovered run: sweeping", #pending, "item(s) in", wait .. "s")
    ScheduleSweep(run.id, pending, wait)
end


local function AnnounceAdded(indices)
    if not run.active or #indices == 0 then return end
    if not addon.PlayerIsMasterLooter() then return end

    local runId = run.id

    local items = {}
    for _, index in ipairs(indices) do
        local item = run.items[index]
        items[index] = {
            id = item.id, link = item.link,
            owner = item.owner, boss = item.boss, encounterID = item.encounterID,
            simulated = item.simulated, difficultyID = item.difficultyID,
        }
    end

    addon.Log:I("Session", "adding to running run", #indices, "item(s)")
    addon.Comms:Send("items_add", { items = items }, nil, true)
    if addon.Callbacks then addon.Callbacks:Fire("ItemsAdded", indices, runId) end
    ScheduleSweep(runId, indices)
end





local function RefusesLiveAppend()
    if run.active and not addon.PlayerIsMasterLooter() then
        addon.Log:W("Session", "not adding to the running run - only the loot master can")
        return true
    end
    return false
end



function Session:MayStage()
    if addon.PlayerIsMasterLooter() then return true end
    return addon.Council and addon.Council:Contains(addon.Player:GetFullName("player"))
        and true or false
end

local function RefusesStaging()
    if RefusesLiveAppend() then return true end
    if not Session:MayStage() then
        addon.Log:I("Session", "not staging - only the loot master and the council stage items")
        return true
    end
    return false
end



function Session:AddItem(itemLink, owner, boss, encounterID)
    if RefusesStaging() then return nil end
    local index = AppendItem(itemLink, owner, boss, encounterID)
    AnnounceAdded({ index })
    return index
end




function Session:AddItems(itemLinks, owner, boss, encounterIDs)
    local indices = {}
    if RefusesStaging() then return indices end
    local perItem = type(boss) == "table"
    for i, itemLink in ipairs(itemLinks) do

        local itemBoss
        if perItem then itemBoss = boss[i] else itemBoss = boss end
        local encounterID = type(encounterIDs) == "table" and encounterIDs[i] or nil
        indices[#indices + 1] = AppendItem(itemLink, owner, itemBoss, encounterID)
    end
    AnnounceAdded(indices)
    return indices
end



function Session:AddDrops(itemLinks, bosses, encounterIDs)
    local indices = {}
    if RefusesLiveAppend() then return indices end
    local me = addon.Player:GetFullName("player")
    for i, itemLink in ipairs(itemLinks) do
        local index = AppendItem(itemLink, me, bosses[i], encounterIDs[i])
        drops[run.items[index].id] = "pending"
        indices[i] = index
    end
    AnnounceAdded(indices)
    return indices
end



function Session:DropSettled(id, landed)
    if not id or drops[id] ~= "pending" then return false end
    drops[id] = landed and "landed" or "lost"
    if not landed and run.active then Session:CheckHeld() end
    return true
end

local function PruneDrops()
    if next(drops) == nil then return end
    local live = {}
    for _, item in ipairs(run.items) do
        if item.id then live[item.id] = true end
    end
    for id in pairs(drops) do
        if not live[id] then drops[id] = nil end
    end
end




function Session:StartTest(itemLinks, count, sources)
    if run.active then return false, T["a run is already active"] end
    if not addon.PlayerIsMasterLooter() then
        return false, T["only the Loot Master can start a test"]
    end
    if IsInGroup() and not IsInRaid() and not addon.GroupTestActive() then
        return false, T["only possible in a raid"]
    end
    if #run.items > 0 then
        return false, T["clear the staging queue first with /slc clear"]
    end
    if Blocked() then
        return false, addon.Restrictions:GetBlockReason() or T["unavailable"]
    end

    local owner = addon.Player:GetFullName("player")
    local links = itemLinks
    if type(links) ~= "table" or #links == 0 then

        if addon.IsForever then
            links, sources = addon.TestLoot:PickDungeon(count or 3)
        else
            links = addon.TestLoot:Pick(count or 3)
            sources = nil
        end
    end
    for i, link in ipairs(links) do
        local source = type(sources) == "table" and sources[i] or nil
        AppendItem(link, owner, source and source.boss or "Simulated Loot",
            source and source.encounterID, true, source and source.difficultyID)
    end

    if not Session:Start() then

        run.items = {}
        return false, T["the council is not ready"]
    end
    return true, #links
end



function Session:CountQueued(link, owner)
    local wanted = addon.Storage.ItemID(link)
    if not wanted then return 0 end

    local count = 0
    for _, item in ipairs(run.items) do
        if addon.Storage.ItemID(item.link) == wanted
            and (not owner or addon.Player:IsSame(item.owner, owner)) then
            count = count + 1
        end
    end
    return count
end




local function TradeableCounts(wanted)
    local counts = {}
    for id in pairs(wanted) do counts[id] = { n = 0, b = 0, links = {} } end
    local ItemID = addon.Storage.ItemID
    for bag = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local id = C_Container.GetContainerItemID(bag, slot)
            local count = id and counts[id]
            if count then
                local link = C_Container.GetContainerItemLink(bag, slot)
                if ItemID(link) == id then
                    local secondsLeft, bonding = addon.Storage:GetSlotTradeInfo(bag, slot)
                    if not (secondsLeft and secondsLeft > 0)
                        and bonding == Enum.TooltipDataItemBinding.Soulbound then
                        count.b = count.b + 1
                    else
                        count.n = count.n + 1
                        count.links[#count.links + 1] = link
                    end
                end
            end
        end
    end
    return counts
end



function Session:PruneUnheld()
    if run.active then return 0 end

    local ItemID, ItemsMatch = addon.Storage.ItemID, addon.Storage.ItemsMatch
    local byId, wanted, any = {}, {}, false
    for index, item in ipairs(run.items) do
        local arriving = drops[item.id] == "pending" or drops[item.id] == "landed"
        local id = item.link and not item.simulated and not arriving
            and addon.Player:IsSelf(item.owner) and ItemID(item.link)
        if id then
            local group = byId[id]
            if not group then
                group = {}
                byId[id], wanted[id], any = group, true, true
            end
            group[#group + 1] = index
        end
    end
    if not any then return 0 end

    local counts = TradeableCounts(wanted)
    local drop = {}
    for id, group in pairs(byId) do
        local count = counts[id]
        local excess = #group - count.n
        if excess > 0 then
            addon.Log:I("Session", "queued", #group, "held", count.n, "of item", id)
            local claimed, matched = {}, {}
            for _, index in ipairs(group) do
                local link = run.items[index].link
                for p, have in ipairs(count.links) do
                    if not claimed[p] and ItemsMatch(have, link) then
                        claimed[p], matched[index] = true, true
                        break
                    end
                end
            end
            for pass = 1, 2 do
                for k = #group, 1, -1 do
                    if excess <= 0 then break end
                    local index = group[k]
                    if not drop[index] and (pass == 2 or not matched[index]) then
                        drop[index] = true
                        excess = excess - 1
                    end
                end
            end
        end
    end

    local dropped, links = 0, nil
    for index = #run.items, 1, -1 do
        if drop[index] then
            local item = run.items[index]
            addon.Log:I("Session", "dropping unheld item from the queue", item.link)
            links = links or {}
            links[#links + 1] = item.link
            table.remove(run.items, index)
            dropped = dropped + 1
        end
    end

    if dropped > 0 then

        for index, item in ipairs(run.items) do item.session = index end
        if addon.Callbacks then addon.Callbacks:Fire("SessionChanged") end
    end
    return dropped, links, counts
end



function Session:ApplyQueueDrop(link, held, sender, droppedLinks)
    if run.active then
        addon.Log:D("Session", "ignoring queue_drop during an active run", tostring(link))
        return 0
    end
    if type(link) ~= "string" then return 0 end

    local ItemID, ItemsMatch = addon.Storage.ItemID, addon.Storage.ItemsMatch
    local wanted = ItemID(link)
    if not wanted then return 0 end

    local mine, owned = {}, 0
    for index, item in ipairs(run.items) do
        if ItemID(item.link) == wanted
            and addon.Player:IsSame(item.owner, sender) then
            owned = owned + 1
            mine[owned] = index
        end
    end

    local excess = owned - (tonumber(held) or 0)
    if excess <= 0 then return 0 end

    local prefer = {}
    if type(droppedLinks) == "table" then
        for n, gone in ipairs(droppedLinks) do
            if n > 32 then break end
            if type(gone) == "string" and #gone <= 512 and ItemID(gone) == wanted then
                prefer[#prefer + 1] = gone
            end
        end
    end

    local remove, count, used = {}, 0, {}
    for k = owned, 1, -1 do
        if count >= excess or #prefer == 0 then break end
        local index = mine[k]
        for p, gone in ipairs(prefer) do
            if not used[p] and ItemsMatch(gone, run.items[index].link) then
                used[p], remove[index], count = true, true, count + 1
                break
            end
        end
    end
    for k = owned, 1, -1 do
        if count >= excess then break end
        local index = mine[k]
        if not remove[index] then
            remove[index], count = true, count + 1
        end
    end

    local dropped = 0
    for index = #run.items, 1, -1 do
        if remove[index] then
            addon.Log:I("Session", "dropping item", run.items[index].link,
                "no longer held by", tostring(sender))
            table.remove(run.items, index)
            dropped = dropped + 1
        end
    end

    if dropped > 0 then

        for index, item in ipairs(run.items) do item.session = index end
        if addon.Callbacks then addon.Callbacks:Fire("SessionChanged") end
    end
    return dropped
end


function Session:RemoveQueued(index)
    if run.active then return false end
    if not run.items[index] then return false end
    table.remove(run.items, index)

    for i, item in ipairs(run.items) do item.session = i end
    if addon.Callbacks then addon.Callbacks:Fire("SessionChanged") end
    return true
end

function Session:Clear()
    local wasActive = run.active
    run.active = false
    run.ended = false
    run.items = {}
    wipe(drops)
    run.stash = nil
    assembling = nil
    run.recoveryFromReplies, run.recoverySources = nil, nil
    CloseAsk("cleared")
    Refused.copy, Refused.filled = nil, {}

    run.completed = {}
    run.coins = {}
    run.startedAt = nil
    ClearPersisted()
    run.deadline, run.duration = nil, nil
    if addon.Callbacks then

        if wasActive then addon.Callbacks:Fire("RunEnded") end
        addon.Callbacks:Fire("SessionChanged", nil, "run")
    end
end

function Session:HasEnded()
    return run.ended == true
end



function Session:GetRunId()
    return run.id
end


local ENDED_REMEMBERED = 8
local endedRuns = {}

local function RememberEnded(runId)
    if not runId then return end
    for index = #endedRuns, 1, -1 do
        if endedRuns[index] == runId then table.remove(endedRuns, index) end
    end
    endedRuns[#endedRuns + 1] = runId
    while #endedRuns > ENDED_REMEMBERED do table.remove(endedRuns, 1) end
end

function Session.RunHasEnded(runId)
    for _, ended in ipairs(endedRuns) do
        if ended == runId then return true end
    end
    return false
end


local function RunIsNewer(a, b)
    local ta = type(a) == "string" and tonumber(a:match("^(%d+)%-")) or nil
    local tb = type(b) == "string" and tonumber(b:match("^(%d+)%-")) or nil
    return ta ~= nil and tb ~= nil and ta > tb
end


function Session:GetTimeLeft()
    if not run.active or not run.deadline then return nil end
    return math.max(0, run.deadline - GetTime())
end


function Session:GetTimerDuration()
    return run.duration
end


function Session:AllAwarded()
    if #run.items == 0 then return false end
    local any = false
    for _, item in ipairs(run.items) do

        if not item.removed then
            if not item.awarded then return false end
            any = true
        end
    end
    return any
end


function Session:Settled()
    if not run.active then return false end
    local any = false
    for _, item in ipairs(run.items) do
        if not item.awarded and not item.removed then return false end
        any = true
    end
    return any
end






function Session:Start()
    if run.active then return false end
    if not addon.PlayerIsMasterLooter() then
        addon.Log:W("Session", "only the group leader can start a run")
        return false
    end
    if IsInGroup() and not IsInRaid() and not addon.GroupTestActive() then
        addon.Chat.Print(addon.Locale.Format(T["could not start the run: %s"],
            T["only possible in a raid"]))
        return false, "raid"
    end
    if Blocked() then
        local reason = addon.Restrictions:GetBlockReason() or T["unavailable"]
        addon.Log:W("Session", "cannot start a run:", reason)
        addon.Chat.Print(addon.Locale.Format(T["could not start the run: %s"], reason))
        return false, "blocked"
    end


    local queued = #run.items
    if addon.BagShare then addon.BagShare:Push() end
    Session:PruneUnheld()
    local dropped = queued - #run.items
    if dropped > 0 then


        addon.Log:I("Session", "dropped", dropped,
            "queued item(s) that can no longer be traded from your bags")


        addon.Chat.Print(addon.Locale.Format(addon.Locale.Plural{
            one = "dropped %d queued item you can no longer trade.",
            other = "dropped %d queued items you can no longer trade.",
        }, dropped, dropped))
    end

    if #run.items == 0 then
        addon.Log:I("Session", "nothing to start")
        if dropped > 0 then
            addon.Chat.Print(T["nothing left to start a run with."])
            return false, "emptied"
        end
        return false, "empty"
    end


    if addon.Council:GetCount() == 0 then
        addon.Log:W("Session", "no council resolved yet - wait a few seconds")
        return false
    end


    local runId = NextId()


    local length = addon.Config:SessionLength()

    local payload = { runId = runId, timer = length > 0 and length or nil, items = {} }
    for index, item in ipairs(run.items) do
        payload.items[index] = {
            id = item.id,
            link = item.link,
            owner = item.owner,
            boss = item.boss,
            encounterID = item.encounterID,
            simulated = item.simulated,

            difficultyID = item.difficultyID,
        }
    end

    addon.Log:I("Session", "starting run", #run.items, "items")
    addon.Comms:Send("run_start", payload, nil, true)



    Session:ApplyRunStart(payload, addon.Player:GetFullName("player"))


    local initialIndices = {}
    for index in ipairs(run.items) do initialIndices[#initialIndices + 1] = index end
    ScheduleSweep(runId, initialIndices)
    if AnnounceRunState then AnnounceRunState() end

    return true
end







local function LinkKeys(link, owner)
    if type(link) ~= "string" then return nil end
    local id = addon.Storage.ItemID(link)
    if not id then return nil end
    local text = link:match("|H(item:[^|]*)")
    local exact = text and (addon.Storage.CanonicalItemString(text) .. "|" .. tostring(owner)) or nil
    return id .. "|" .. tostring(owner), exact
end
Session.LinkKeys = LinkKeys

function Session.Leftover(staged, runItems)
    local taken, exactTaken = {}, {}
    for _, entry in ipairs(runItems or {}) do
        local key, exact = LinkKeys(type(entry) == "table" and entry.link or nil,
            type(entry) == "table" and entry.owner or nil)
        if key then
            taken[key] = (taken[key] or 0) + 1
            if exact then exactTaken[exact] = (exactTaken[exact] or 0) + 1 end
        end
    end
    local keys, matched = {}, {}
    for index, item in ipairs(staged or {}) do
        local key, exact = LinkKeys(item.link, item.owner)
        keys[index] = key or false
        if exact and (exactTaken[exact] or 0) > 0 then
            exactTaken[exact] = exactTaken[exact] - 1
            taken[key] = taken[key] - 1
            matched[index] = true
        end
    end
    local leftover = {}
    for index, item in ipairs(staged or {}) do
        if not matched[index] then
            local key = keys[index]
            if key and (taken[key] or 0) > 0 then
                taken[key] = taken[key] - 1
            elseif not item.simulated then
                leftover[#leftover + 1] = item
            end
        end
    end
    return leftover
end

function Session:ApplyRunStart(payload, sender, recovered)
    if type(payload) ~= "table" or type(payload.items) ~= "table" then return end


    if payload.runId and run.active and run.id == payload.runId then
        addon.Log:D("Session", "ignoring duplicate run_start", payload.runId)
        return
    end


    if payload.runId and Session.RunHasEnded(payload.runId) then
        addon.Log:I("Session", "ignoring run_start for a run that already ended",
            payload.runId)
        return
    end

    if run.active and run.id and run.id ~= payload.runId then RememberEnded(run.id) end
    run.id = payload.runId

    run.backupOwner = nil

    assembling = nil

    run.recoveryFromReplies, run.recoverySources = nil, nil


    Refused.filled = {}
    if not (recovered and payload.candidateOnly) then
        Refused.copy = nil
        CloseAsk(recovered and "recovered" or "run_started")
    end
    local senderRecord = addon.Player:Get(sender) or {}
    run.lootMaster = payload.lootMaster or senderRecord.fullName or sender
    run.groupKey = payload.groupKey or GroupKey()
    run.grouped = (IsInGroup() or (type(run.groupKey) == "string"
        and run.groupKey:find("\0", 1, true) ~= nil)) and true or false



    if not run.active then
        run.stash = Session.Leftover(run.items, payload.items)
        if #run.stash > 0 then
            addon.Log:I("Session", "keeping", #run.stash,
                "staged item(s) the run did not take")
        end
    end

    run.items = {}

    run.completed = {}
    run.deliveredSeen = {}



    run.coins = addon.BonusRoll and addon.BonusRoll:Seed(GetServerTime()) or {}
    if addon.BonusRoll and type(payload.coins) == "table" then
        for _, coin in ipairs(payload.coins) do
            if type(coin) == "table" then
                addon.BonusRoll.Apply(run.coins, coin.name, coin.link, coin.epoch,
                    coin.boss, coin.encounterID, coin.quantity)
            end
        end
    end
    for index, entry in ipairs(payload.items) do
        if payload.snapshotVersion == SNAPSHOT_VERSION then
            run.items[index] = CopyMap(entry)
            run.items[index].session = index


            local rows = {}
            for name, row in pairs(type(entry.candidates) == "table" and entry.candidates or {}) do
                if type(name) == "string" then rows[name] = CleanRow(row) end
            end
            run.items[index].candidates = rows
            if payload.candidateOnly or payload.parts then

                for name, candidate in pairs(NewCandidateSet()) do
                    if not run.items[index].candidates[name] then
                        run.items[index].candidates[name] = candidate
                    end
                end
            end
        else
            run.items[index] = {
                id = entry.id,
                session = index,
                link = entry.link,
                owner = entry.owner,
                boss = entry.boss,
                encounterID = tonumber(entry.encounterID),
                simulated = entry.simulated and true or nil,
                difficultyID = entry.simulated and tonumber(entry.difficultyID) or nil,
                awarded = nil,
                delivered = false,
                candidates = NewCandidateSet(),
            }
        end
    end

    if payload.snapshotVersion == SNAPSHOT_VERSION then DecodeRolls(payload.rn) end


    local drafts = addon.db and addon.db.noteDrafts
    if drafts and drafts.runId ~= run.id then
        addon.db.noteDrafts = nil
        drafts = nil
    end
    local me = addon.Player:GetFullName("player")
    local resend = {}
    if drafts and type(drafts.notes) == "table" and me then
        for session, note in pairs(drafts.notes) do
            local item = run.items[session]
            if item and type(note) == "string" then
                local candidate = item.candidates[me]
                local have = candidate and candidate.note or ""
                if note ~= have then resend[session] = note end
                if candidate then candidate.note = note ~= "" and note or nil end
            end
        end
    end
    ResolveMissingBosses()
    run.active = true


    run.ended = false
    run.startedAt = GetTime()



    local expiresAt = tonumber(payload.expiresAt)
    local remaining = expiresAt and math.max(0, expiresAt - GetServerTime())
        or tonumber(payload.timer)
    run.duration = tonumber(payload.timer) or remaining
    run.deadline = remaining and (GetTime() + remaining) or nil
    run.expiresAt = remaining and (GetServerTime() + remaining) or nil


    run.complete = payload.candidateOnly == nil and payload.parts == nil



    if type(payload.parts) == "table" and not recovered then
        OpenAssembly(payload, sender)
    end

    addon.Log:I("Session", recovered and "run recovered by" or "run started by",
        tostring(sender), #run.items, "items")
    if addon.Callbacks then
        addon.Callbacks:Fire("RunStarted")
        if recovered then addon.Callbacks:Fire("RunRecovered") end
    end
    for session, note in pairs(resend) do Session:SetNote(session, note, true) end

    if recovered then ScheduleRecoveredSweep() end

    ReplayHeld()

    if assembling and assembling.runId == run.id then
        local runId = run.id
        MergeStash()
        CheckAssembled()
        if assembling then ScheduleFill(runId) end
    end


    RunCopy.Settle()
end



function Session:ApplyRunDelta(payload, sender)
    if type(payload) ~= "table" then return end
    if run.active and run.id == payload.runId then
        addon.Log:D("Session", "ignoring duplicate run_start", tostring(payload.runId))
        return
    end
    local merged, why = RunCopy.Merge(payload)
    if not merged and run.active and not heldCopy then


        addon.Log:D("Session", "changes for run", tostring(payload.runId),
            "ignored - no saved copy of it is held any more")
        return
    end
    if not merged then
        addon.Log:W("Session", "could not rebuild the run from my saved copy -", why,
            "- asking for the whole run")
        heldRefused = true
        AskForRun({ d = 1 }, sender)
        return
    end
    addon.Log:I("Session", "run rebuilt from my saved copy:", #payload.items, "of", #merged.items,
        "item(s) changed", payload.coins and "and the coins" or "", "- from", tostring(sender))
    Session:ApplyRunStart(merged, sender)
end



local function NotLive(what, session)
    if run.active then return false end
    addon.Log:D("Session", what, "after its run ended, ignored", tostring(session))
    return true
end



local function ApplyAnswer(what, session, candidateName, response, note, sender, gear)
    if NotLive(what, session) then return end
    local index = ResponseIndex(response)
    if index == false or type(candidateName) ~= "string" then
        return Refuse(what, "malformed", sender)
    end
    local item = run.items[session]
    if not item then return Refuse(what, "unknown_session", sender) end

    local candidate = item.candidates[candidateName]
    if not candidate then

        candidate = { status = "ANNOUNCED", voters = {} }
        item.candidates[candidateName] = candidate
    end



    local status = index and "RESPONDED" or "PASS"
    if candidate.status == "AWARDED" then
        candidate.realResponse, candidate.realStatus = index, status
    else
        candidate.response, candidate.status = index, status
    end
    candidate.note = CleanNote(note)

    candidate.overridden = nil
    local whispered = what == "whisper"

    if whispered then candidate.viaWhisper = true end



    local gearSaid = not whispered or type(gear) == "table"
    if gearSaid and addon.Gear then addon.Gear:ApplyToCandidate(candidate, gear) end
    Touch(session, candidateName, true, true, gearSaid)

    if whispered then
        addon.Log:I("Session", "whispered response", session, candidateName,
            tostring(index), "relayed by", tostring(sender))
    else
        addon.Log:D("Session", "response", session, candidateName, tostring(index))
    end
    if addon.Callbacks then
        addon.Callbacks:Fire("SessionChanged", session, "response", candidateName)
    end
end

function Session:ApplyResponse(session, candidateName, response, note, sender, gear)
    return ApplyAnswer("response", session, candidateName, response, note, sender, gear)
end


function Session:ApplyNote(session, candidateName, note, sender)
    if not run.active or type(note) ~= "string" or type(candidateName) ~= "string" then
        return false
    end
    local item = run.items[session]
    if not item then return false end
    local candidate = item.candidates[candidateName]
    if not candidate then
        candidate = { status = "ANNOUNCED", voters = {} }
        item.candidates[candidateName] = candidate
    end
    candidate.note = CleanNote(note)
    Touch(session, candidateName, false, true, false)
    addon.Log:D("Session", "note", session, candidateName, "from", sender)
    if addon.Callbacks then
        addon.Callbacks:Fire("SessionChanged", session, "note", candidateName)
    end
    return true
end



function Session:ApplyWhisperResponse(session, candidateName, response, note, sender, gear)
    return ApplyAnswer("whisper", session, candidateName, response, note, sender, gear)
end



function Session:ApplyResponseSet(session, candidateName, response, sender)
    if NotLive("response_set", session) then return end
    response = ResponseIndex(response)
    if response == false then return Refuse("response_set", "malformed", sender) end
    local item = run.items[session]
    if not item then
        addon.Log:WLogOnly("Session", "response_set for unknown session", tostring(session))
        return
    end

    local candidate = item.candidates[candidateName]
    if not candidate then return end

    local status = response and "RESPONDED" or "PASS"


    local awarded = candidate.status == "AWARDED"

    if awarded then
        if candidate.realResponse == response then return end
        candidate.realResponse = response
        candidate.realStatus = status
    else
        if candidate.response == response and candidate.status == status then return end
        candidate.response = response
        candidate.status = status
    end


    candidate.overridden = true
    Touch(session, candidateName, true, false, false)

    addon.Log:I("Session", "response overridden by", tostring(sender), session,
        candidateName, tostring(response))


    if awarded and addon.PlayerIsMasterLooter() then
        addon.Chat.Print(T["response changed, but this item is already awarded - history keeps what was recorded. Undo the award first if the record matters."])
    end

    if addon.Callbacks then
        addon.Callbacks:Fire("SessionChanged", session, "response", candidateName)
    end
end



function Session:ApplyVote(session, candidateName, voterName, voted)
    if NotLive("vote", session) then return end
    local item = run.items[session]
    if not item then return end

    local candidate = item.candidates[candidateName]
    if not candidate then return end

    candidate.voters[voterName] = voted and true or nil
    TouchVote(session, candidateName, voterName)

    addon.Log:D("Session", "vote", session, candidateName, voterName, tostring(voted))
    if addon.Callbacks then
        addon.Callbacks:Fire("SessionChanged", session, "vote", candidateName)
    end
end




function Session:ReceiveVote(session, candidateName, voterName, voted)
    if voted and addon.Config:RulesSettled() then
        local rules = addon.Config:Vote()
        if not rules.selfVote
            and addon.Player:IsSame(candidateName, voterName) then
            addon.Log:I("Session", "refusing a self-vote - the group's rules forbid it",
                session, voterName)
            return
        end
        if not rules.multiVote then
            local item = run.items[session]
            if item and item.candidates[candidateName] then
                for otherName, candidate in pairs(item.candidates) do
                    if otherName ~= candidateName and candidate.voters[voterName] then
                        addon.Log:D("Session", "single vote - dropping",
                            voterName, "on", otherName)
                        Session:ApplyVote(session, otherName, voterName, false)
                    end
                end
            end
        end
    end
    Session:ApplyVote(session, candidateName, voterName, voted)
end



function Session:ApplySweep(indices, verdict)
    if NotLive("sweep") then return end


    local answered = not verdict and AnsweredAnywhere() or nil

    local function SweepItem(item)
        if not item then return end

        if not item.awarded and not item.removed then

            local swept = { NOTHING = {}, NO_ADDON = {} }
            for name, candidate in pairs(item.candidates) do
                if candidate.status == "ANNOUNCED" then

                    local hasAddon
                    if verdict then
                        hasAddon = not verdict[name]
                    else
                        hasAddon = answered[name]
                            or (addon.Version and addon.Version:Knows(name))
                    end
                    candidate.status = hasAddon and "NOTHING" or "NO_ADDON"
                    local names = swept[candidate.status]
                    names[#names + 1] = name
                end
            end
            if #swept.NOTHING + #swept.NO_ADDON > 0 then
                table.sort(swept.NOTHING)
                table.sort(swept.NO_ADDON)

                if #swept.NO_ADDON == 0 then
                    addon.Log:D("Session", "swept", item.session,
                        "NOTHING", table.concat(swept.NOTHING, ", "))
                elseif #swept.NOTHING == 0 then
                    addon.Log:D("Session", "swept", item.session,
                        "NO_ADDON", table.concat(swept.NO_ADDON, ", "))
                else
                    addon.Log:D("Session", "swept", item.session,
                        "NOTHING", table.concat(swept.NOTHING, ", "),
                        "NO_ADDON", table.concat(swept.NO_ADDON, ", "))
                end
            end
        end
    end
    if type(indices) == "table" then
        for _, index in ipairs(indices) do SweepItem(run.items[index]) end
    else

        for _, item in ipairs(run.items) do SweepItem(item) end
    end

    if addon.Callbacks then addon.Callbacks:Fire("SessionChanged", nil, "status") end
end







local function AcceptSeq(item, seq, what)
    if seq == nil then return true end
    local current = item.awardSeq or 0
    if seq <= current then
        addon.Log:D("Session", "stale", what, "discarded", seq, "have", current)
        return false
    end
    item.awardSeq = seq
    return true
end


local function NextSeq(item)
    return (item.awardSeq or 0) + 1
end

function Session:ApplyAward(session, winner, sender, reason, seq)
    if NotLive("award", session) then return end
    local item = run.items[session]
    if not item then return end

    if not AcceptSeq(item, seq, "award") then return end


    if item.awarded == winner then
        addon.Log:D("Session", "award already applied", session, tostring(winner))
        return
    end


    local previousName = item.awarded
    if previousName then
        local previous = item.candidates[previousName]
        if previous then
            previous.status = previous.realStatus or "ANNOUNCED"
            previous.response = previous.realResponse
            previous.realStatus, previous.realResponse = nil, nil
        end
        addon.Log:I("Session", "award moved off", previousName)



        item.awarded = nil
        item.delivered = false
        if addon.Callbacks then
            addon.Callbacks:Fire("ItemUnawarded", session, previousName, item, run.id, winner)
        end
    end

    item.delivered = false
    item.awarded = winner


    local reasonEntry = reason and addon.db.awardReasons
        and addon.db.awardReasons[reason] or nil
    item.reason = reason
    item.reasonText = reasonEntry and reasonEntry.text or nil
    item.reasonLogged = reasonEntry and reasonEntry.log and true or false

    local candidate = item.candidates[winner]
    if candidate then

        candidate.realResponse = candidate.realResponse or candidate.response
        candidate.realStatus = candidate.realStatus or candidate.status
        candidate.status = "AWARDED"
    end

    addon.Log:I("Session", "awarded", session, winner, "by", tostring(sender))
    if addon.Callbacks then

        addon.Callbacks:Fire("ItemAwarded", session, winner, item, previousName)

        addon.Callbacks:Fire("SessionChanged", session, "award")
    end
end



function Session:ApplyUnaward(session, sender, seq)


    local item = Session:GetItem(session)
    if not item then return end



    if not AcceptSeq(item, seq, "unaward") then return end

    local previous = item.awarded
    if not previous then
        addon.Log:D("Session", "unaward with nothing awarded", session)
        return
    end



    local candidate = item.candidates[previous]
    if candidate then
        candidate.status = candidate.realStatus or "ANNOUNCED"
        candidate.response = candidate.realResponse
        candidate.realStatus, candidate.realResponse = nil, nil
    end

    item.awarded = nil
    item.delivered = false

    addon.Log:I("Session", "award struck", session, previous, "by", tostring(sender))
    if addon.Callbacks then

        addon.Callbacks:Fire("ItemUnawarded", session, previous, item, run.id)
        addon.Callbacks:Fire("SessionChanged", session, "award")
    end
end

function Session:Unaward(session, expectedRunId)
    if not addon.PlayerIsMasterLooter() then return false end

    if expectedRunId and run.id ~= expectedRunId then
        addon.Log:WLogOnly("Session", "stale unaward refused", tostring(expectedRunId),
            "current", tostring(run.id))
        return false
    end



    local item = Session:GetItem(session)
    if not item or not item.awarded then return false end

    if addon.Restrictions:IsBlocked() then
        addon.Log:W("Session", "cannot strike:", addon.Restrictions:GetBlockReason())
        return false
    end

    local seq = NextSeq(item)
    addon.Comms:Send("unaward", { s = session, q = seq }, nil, true)
    Session:ApplyUnaward(session, addon.Player:GetFullName("player"), seq)
    return true
end




function Session:RetractAward(runId, session, winner)
    if not addon.PlayerIsMasterLooter() then return false end
    if not runId or not session or not winner then return false end

    local item = run.id == runId and Session:GetItem(session) or nil
    if item and item.awarded then


        if not addon.Player:IsSame(item.awarded, winner) then return false end
        return Session:Unaward(session, runId)
    end

    if addon.Restrictions:IsBlocked() then
        addon.Log:W("Session", "cannot retract:", addon.Restrictions:GetBlockReason())
        return false
    end
    addon.Comms:Send("award_retract", { i = runId, s = session, w = winner }, nil, true)
    Session:ApplyRetract(runId, session, winner, addon.Player:GetFullName("player"))
    return true
end



function Session:ApplyRetract(runId, session, winner, sender)
    if not runId or not session or not winner then return end

    local item = run.id == runId and Session:GetItem(session) or nil
    if item and item.awarded then
        if not addon.Player:IsSame(item.awarded, winner) then return end

        Session:ApplyUnaward(session, sender, nil)
        return
    end

    addon.Log:I("Session", "award retracted", tostring(runId), session, winner,
        "by", tostring(sender))
    if addon.Callbacks then
        addon.Callbacks:Fire("ItemUnawarded", session, winner, nil, runId)
    end
end









function Session:IsRemoved(item)
    return item and item.removed and true or false
end


function Session:IsAwardable(item)
    return item and not item.removed and not item.gone or false
end

function Session:ApplyRemove(session, on, sender, seq, runId)
    if runId and run.id ~= runId then
        addon.Log:D("Session", "item_remove for another run ignored", tostring(runId))
        return
    end
    if NotLive("item_remove", session) then return end
    local item = run.items[session]
    if not item then return end
    if not AcceptSeq(item, seq, on and "remove" or "restore") then return end

    on = on and true or nil
    if item.removed == on then return end
    item.removed = on
    addon.Log:I("Session", on and "item removed from the run" or "item restored to the run",
        session, tostring(item.link), "by", tostring(sender))
    if addon.Callbacks then addon.Callbacks:Fire("SessionChanged", session, "item") end
end



function Session:RemoveItem(session, on, expectedRunId)
    if not addon.PlayerIsMasterLooter() then return false end
    if expectedRunId and run.id ~= expectedRunId then
        addon.Log:WLogOnly("Session", "stale remove refused", tostring(expectedRunId))
        return false
    end
    local item = run.items[session]
    if not run.active or run.ended or not item then return false end
    if item.awarded or item.delivered then return false end
    if (item.removed and true or false) == (on and true or false) then return false end
    if addon.Restrictions:IsBlocked() then
        addon.Log:W("Session", "cannot remove:", addon.Restrictions:GetBlockReason())
        return false
    end

    local seq = NextSeq(item)
    addon.Comms:Send("item_remove",
        { s = session, i = run.id, on = on and true or false, q = seq }, nil, true)
    Session:ApplyRemove(session, on, addon.Player:GetFullName("player"), seq, run.id)
    return true
end



function Session:UnawardAndRemove(session, expectedRunId)
    if not Session:Unaward(session, expectedRunId) then return false end
    return Session:RemoveItem(session, true, expectedRunId)
end



local GONE_TEXT = addon.Locale.Texts{
    equipped = T["%s was equipped by %s, so it cannot be awarded. Right-click it in the council list to remove it from the run."],
    bound = T["%s is still in %s's bags, but its trade window has ended, so it cannot be awarded. Right-click it in the council list to remove it from the run."],
    left = T["%s is no longer in %s's bags, so it cannot be awarded. Right-click it in the council list to remove it from the run."],
    pending = T["%s has not reached %s's bags yet, so it can be awarded once it does."],
    lost = T["%s went to another player in the loot roll instead of %s, so it cannot be awarded. Right-click it in the council list to remove it from the run."],
}


local function OwedKey(owed)
    if type(owed) ~= "table" or not owed.w then return nil end
    return ("%s|%s|%s"):format(tostring(owed.i), tostring(owed.s), tostring(owed.w))
end


local function CleanOwed(owed)
    if type(owed) ~= "table" then return nil end
    local w, i, s = owed.w, owed.i, owed.s
    if type(w) ~= "string" or w == "" or #w > 64 then return nil end
    if i ~= nil and (type(i) ~= "string" or #i > 64) then return nil end
    if s ~= nil and (type(s) ~= "number" or s % 1 ~= 0 or s < 1 or s > 1000) then
        return nil
    end
    return { w = w, i = i, s = s }
end

function Session:ApplyGone(session, runId, reason, sender, owed)
    if not run.active or not runId or run.id ~= runId then return end
    local item = run.items[session]
    if not item then return end

    if not addon.Player:IsSame(sender, item.owner) then
        addon.Log:D("Session", "item_gone from someone other than the holder ignored",
            tostring(sender))
        return
    end

    if reason == "" or reason == false then reason = nil end
    if reason ~= nil and (type(reason) ~= "string" or not GONE_TEXT[reason]) then
        return Refuse("item_gone", "unknown_reason", sender)
    end
    owed = CleanOwed(owed)
    if item.gone == reason and OwedKey(item.owed) == OwedKey(owed) then return end
    local was = item.gone
    item.gone = reason
    item.owed = owed
    if owed then
        addon.Log:I("Session", "holder's copy is already owed", session,
            tostring(item.link), "to", tostring(owed.w), "held by", tostring(sender))
    else
        addon.Log:I("Session", reason and "holder no longer has" or "holder has again",
            session, tostring(item.link), tostring(reason), "held by", tostring(sender))
    end

    if reason and not was and not item.removed and addon.PlayerIsMasterLooter()
        and not addon.Player:IsSelf(sender) then
        addon.Chat.Error(addon.Locale.Format(GONE_TEXT[reason] or GONE_TEXT.left,
            item.link or "?", Ambiguate(sender or "?", "short")))
    end
    if addon.Callbacks then addon.Callbacks:Fire("SessionChanged", session, "item") end
end




function Session:CheckHeld()
    if not run.active or run.ended or not run.id then return 0 end

    local byId, order = {}, {}
    for pass = 1, 2 do
        for _, item in ipairs(run.items) do
            if (drops[item.id] ~= nil) == (pass == 2)
                and item.link and not item.simulated and not item.awarded
                and not item.delivered and not item.removed
                and addon.Player:IsSelf(item.owner) then
                local id = addon.Storage.ItemID(item.link)
                if id then
                    if not byId[id] then byId[id] = {} order[#order + 1] = id end
                    table.insert(byId[id], item)
                end
            end
        end
    end

    if #order == 0 then return 0 end

    local owedById = {}
    for _, entry in ipairs(addon.Storage:GetAll(addon.Storage.TO_TRADE)) do
        local id = not entry.untradeable and addon.Storage.ItemID(entry.link)
        if id and byId[id] then
            local args = entry.args or {}
            owedById[id] = owedById[id] or {}
            table.insert(owedById[id], { w = args.recipient, i = args.runId, s = args.session })
        end
    end

    local counts = TradeableCounts(byId)
    local changed = 0
    for _, id in ipairs(order) do
        local group = byId[id]
        local tradeable, bound = counts[id].n, counts[id].b

        local owedTo = owedById[id] or {}
        local free = math.max(0, tradeable - #owedTo)
        for index, item in ipairs(group) do
            local reason, owed
            local drop = drops[item.id]
            if index > tradeable then

                if drop == "pending" or drop == "lost" then
                    reason = drop
                elseif addon.Storage:IsEquipped(item.link) then
                    reason = "equipped"
                elseif bound > 0 then
                    reason = "bound"
                elseif drop == "landed" then
                    reason = "pending"
                else
                    reason = "left"
                end
            else
                if drop then drops[item.id] = nil end
                if index > free then
                    owed = CleanOwed(owedTo[index - free])
                end
            end
            if item.gone ~= reason or OwedKey(item.owed) ~= OwedKey(owed) then
                changed = changed + 1
                addon.Comms:Send("item_gone", { s = item.session, i = run.id,
                    g = reason or false, o = owed or false }, nil, true)
                Session:ApplyGone(item.session, run.id, reason,
                    addon.Player:GetFullName("player"), owed)
            end
        end
    end
    return changed
end



function Session:ApplyDelivered(session, winner, sender, link, runId)

    local item = (not runId or run.id == runId) and Session:GetItem(session) or nil

    if not item then
        if not link then


            addon.Log:WLogOnly("Session", "delivery for a session we do not have:",
                tostring(session), "winner", tostring(winner))
            return
        end


        local key = ("%s|%s|%s|%s"):format(tostring(runId), tostring(session),
            tostring(winner), link)
        if run.deliveredSeen[key] then return end
        run.deliveredSeen[key] = true

        addon.Log:I("Session", "delivered", link, "to", winner,
            "(no session record; from the ledger)")
        if addon.Callbacks then
            addon.Callbacks:Fire("ItemDelivered", session, winner, { link = link },
                runId)
        end
        return
    end


    if item.delivered then return end
    if not addon.Player:IsSame(winner, item.awarded) then
        addon.Log:WLogOnly("Session", "delivery of", session, "to", tostring(winner),
            "not taken - it is awarded to", tostring(item.awarded), "per", tostring(sender))
        if item.awarded and type(winner) == "string" and type(link) == "string" then
            Session:ApplyUndelivered(session, item.awarded, sender, link, runId or run.id,
                "wrong", winner)
        end
        return
    end

    item.delivered = true
    addon.Log:I("Session", "delivered", session, winner, "per", tostring(sender))
    if addon.Callbacks then


        addon.Callbacks:Fire("ItemDelivered", session, winner, item, runId or run.id)
        addon.Callbacks:Fire("SessionChanged", session, "award")
    end
end


local function HistoryHandover(session, winner, sender, runId)
    if not (winner and runId and addon.History and addon.History.GetForWinner) then return nil end
    local found

    for _, entry in ipairs(addon.History:GetLiveForWinner(winner)) do
        if entry.runId == runId and entry.session == session and entry.owner then
            if addon.Player:IsSame(sender, entry.owner) then return entry, true end
            found = entry
        end
    end
    return found, false
end




function Session:MayReportHandover(session, winner, sender, runId)
    if addon.IsMasterLooter and addon.IsMasterLooter(sender) then return true end

    local item = (not runId or run.id == runId) and Session:GetItem(session) or nil
    if item then
        if item.owner ~= nil and addon.Player:IsSame(sender, item.owner) then
            return true
        end
        return false, "not the holder"
    end

    local entry, held = HistoryHandover(session, winner, sender, runId)
    if held then return true end
    return false, entry and "not the holder" or "unverifiable"
end


local function RefuseHandover(what, why, sender, session)
    local level = why == "not the holder" and "W" or "D"
    addon.Log[level](addon.Log, "Session", what, "refused -", tostring(sender),
        why, "of session", tostring(session))
end



local undeliveredSeen, undeliveredCount = {}, 0
local UNDELIVERED_SEEN_MAX = 256

local function ForgetUndelivered()
    undeliveredSeen, undeliveredCount = {}, 0
end

local UNDELIVERED = { missing = true, equipped = true, bound = true, wrong = true, left = true }





function Session:ApplyUndelivered(session, winner, sender, link, runId, why, to)
    if addon.Player:IsSelf(sender) then return end
    if not UNDELIVERED[why] then return Refuse("undelivered", "unknown_reason", sender) end

    local key = ("%s|%s|%s|%s"):format(tostring(runId), tostring(session),
        tostring(winner), tostring(sender))
    if undeliveredSeen[key] then return end
    if undeliveredCount >= UNDELIVERED_SEEN_MAX then ForgetUndelivered() end
    undeliveredSeen[key] = true
    undeliveredCount = undeliveredCount + 1


    local item = (not runId or run.id == runId) and Session:GetItem(session) or nil
    local shown, owed
    if item then
        if addon.Player:IsSame(item.awarded, winner) then shown, owed = item.link, item.awarded end
    else
        local entry, held = HistoryHandover(session, winner, sender, runId)
        if held then shown, owed = entry.link, entry.winner end
    end

    local given = type(to) == "string" and addon.Player:Get(to).fullName or nil
    if not (given and (addon.GetCandidates() or {})[given]) then given = nil end
    addon.Log:WLogOnly("Session", "undeliverable -", why, tostring(shown), "owed to",
        tostring(owed), "held by", tostring(sender), given and ("handed to " .. given) or "")


    if addon.Callbacks then
        addon.Callbacks:Fire("ItemUndelivered", session, winner, sender, shown,
            runId, why, given)
    end
    if not addon.PlayerIsMasterLooter() or not shown then return end

    local Format = addon.Locale.Format
    link = shown
    local holder = Ambiguate(sender or "?", "short")
    local short = Ambiguate(owed, "short")
    if why == "missing" then
        addon.Chat.Error(Format(T["%s was awarded to %s, but it is not in %s's bags. Re-award or strike it."],
            link, short, holder))
    elseif why == "equipped" then
        addon.Chat.Error(Format(T["%s was equipped by %s, so it can no longer be traded to %s - it was NOT delivered. Re-award or strike it."],
            link, holder, short))
    elseif why == "bound" then
        addon.Chat.Error(Format(T["%s is still in %s's bags, but its trade window has ended, so it can no longer be traded to %s - it was NOT delivered. Re-award or strike it."],
            link, holder, short))
    elseif why == "wrong" and given then
        given = Ambiguate(given, "short")
        addon.Chat.Error(Format(T["%s was awarded to %s, but %s traded it to %s - it was NOT delivered. Re-award it to %s if they may keep it, or strike it."],
            link, short, holder, given, given))
    elseif why == "wrong" then
        addon.Chat.Error(Format(T["%s was awarded to %s, but %s traded it to someone outside the group - it was NOT delivered. Re-award or strike it."],
            link, short, holder))
    else
        addon.Chat.Error(Format(T["%s left %s's bags without a trade to %s - it was NOT delivered. Re-award or strike it."],
            link, holder, short))
    end
end







local function SendAnswer(command, args, guaranteed)
    local Comms = addon.Comms
    if Comms.SendBatched then
        return Comms:SendBatched(command, args, nil, guaranteed)
    end
    return Comms:Send(command, args, nil, guaranteed)
end

function Session:Respond(session, response, note)
    if not run.active then return false end

    if addon.Restrictions:IsBlocked() then
        addon.Log:W("Session", "cannot respond:", addon.Restrictions:GetBlockReason())
        return false
    end

    local me = addon.Player:GetFullName("player")
    if not me then return false end

    note = addon.Locale.Truncate(note, addon.Config:NoteMax())


    Session:SetNote(session, note or "", false)



    local item = run.items[session]
    local gear = item and addon.Gear
        and addon.Gear:BuildResponsePayload(item.link) or nil

    SendAnswer("response", {
        s = session, r = response, n = note, g = gear,
    })
    Session:ApplyResponse(session, me, response, note, me, gear)
    return true
end



function Session:SetNote(session, note, send)
    if not run.active or not run.items[session] or type(note) ~= "string" then
        return false
    end
    local me = addon.Player:GetFullName("player")
    if not me then return false end
    note = addon.Locale.Truncate(note, addon.Config:NoteMax())
    local candidate = run.items[session].candidates[me]
    if not candidate then
        candidate = { status = "ANNOUNCED", voters = {} }
        run.items[session].candidates[me] = candidate
    end
    candidate.note = note ~= "" and note or nil
    if addon.db then
        if type(addon.db.noteDrafts) ~= "table"
            or addon.db.noteDrafts.runId ~= run.id then
            addon.db.noteDrafts = { runId = run.id, notes = {} }
        end
        if type(addon.db.noteDrafts.notes) ~= "table" then
            addon.db.noteDrafts.notes = {}
        end
        addon.db.noteDrafts.notes[session] = note
    end
    if send then
        SendAnswer("note", { s = session, n = note }, true)
        if addon.Callbacks then addon.Callbacks:Fire("SessionChanged", session, "note", me) end
    end
    return true
end

function Session:Vote(session, candidateName, voted)
    if not run.active then return false end

    local me = addon.Player:GetFullName("player")
    if not me then return false end

    if not addon.Council:Contains(me) then
        addon.Log:W("Session", "not on the council")
        return false
    end

    if not addon.Config:Vote().selfVote and candidateName == me then
        addon.Log:W("Session", "self-voting is disabled")
        return false
    end

    if addon.Restrictions:IsBlocked() then
        addon.Log:W("Session", "cannot vote:", addon.Restrictions:GetBlockReason())
        return false
    end



    if voted and not addon.Config:Vote().multiVote then
        local item = run.items[session]
        if item then
            for otherName, candidate in pairs(item.candidates) do
                if otherName ~= candidateName and candidate.voters[me] then
                    SendAnswer("vote", { s = session, c = otherName, v = false })
                    Session:ApplyVote(session, otherName, me, false)
                    addon.Log:D("Session", "retracted vote", session, otherName)
                end
            end
        end
    end

    SendAnswer("vote", { s = session, c = candidateName, v = voted and true or false })
    Session:ApplyVote(session, candidateName, me, voted)
    return true
end


function Session:SetResponse(session, candidateName, response)
    if not addon.PlayerIsMasterLooter() then return false end
    if not run.active then return false end

    if addon.Restrictions:IsBlocked() then
        addon.Log:W("Session", "cannot set a response:",
            addon.Restrictions:GetBlockReason())
        return false
    end

    addon.Comms:Send("response_set",
        { s = session, c = candidateName, r = response }, nil, true)
    Session:ApplyResponseSet(session, candidateName, response,
        addon.Player:GetFullName("player"))
    return true
end

function Session:Award(session, winner, reason, expectedRunId)
    if not addon.PlayerIsMasterLooter() then return false end
    if expectedRunId and run.id ~= expectedRunId then
        addon.Log:WLogOnly("Session", "stale award refused", tostring(expectedRunId),
            "current", tostring(run.id))
        return false
    end
    if not run.active or run.ended or not run.items[session] or not winner then
        addon.Log:W("Session", "invalid award target", tostring(session),
            tostring(winner))
        return false
    end

    if not Session:IsAwardable(run.items[session]) then
        addon.Log:W("Session", "award refused, item not available", session,
            tostring(run.items[session].removed and "removed" or run.items[session].gone))
        return false
    end
    if addon.Restrictions:IsBlocked() then
        addon.Log:W("Session", "cannot award:", addon.Restrictions:GetBlockReason())
        return false
    end



    if reason ~= nil then
        local list = addon.db.awardReasons or {}
        if not list[reason] then
            addon.Log:W("Session", "unknown award reason", tostring(reason))
            reason = nil
        end
    end



    local owed = run.items[session].owed
    if owed and not run.items[session].awarded then
        if Session:RetractAward(owed.i, owed.s, owed.w) then
            addon.Log:I("Session", "owed copy moved off", tostring(owed.w),
                "for", session)
        end
        run.items[session].owed = nil
    end

    local seq = NextSeq(run.items[session])
    addon.Comms:Send("award",
        { s = session, w = winner, r = reason, q = seq }, nil, true)
    Session:ApplyAward(session, winner, addon.Player:GetFullName("player"),
        reason, seq)
    return true
end

function Session:End()
    if not run.active then return false end
    if not addon.PlayerIsMasterLooter() then return false end
    local endedId = run.id
    addon.Comms:Send("run_end", {}, nil, true)
    Session:ApplyRunEnd()
    if IsInGroup() and type(endedId) == "string" then
        addon.Comms:Send("run_state", { x = endedId }, nil, true)
    end
    return true
end

function Session:ApplyRunEnd()


    if not run.active then
        addon.Log:D("Session", "run_end with no active run, ignored")
        return
    end

    addon.Log:I("Session", "run ended")
    RememberEnded(run.id)
    run.active = false
    run.ended = true
    assembling = nil
    run.recoveryFromReplies, run.recoverySources = nil, nil
    CloseAsk("run_ended")
    Refused.copy, Refused.filled = nil, {}
    run.deadline, run.duration = nil, nil
    run.expiresAt = nil



    run.completed = {}
    for index, item in pairs(run.items) do
        run.completed[index] = item
    end

    run.items = run.stash or {}
    run.stash = nil
    for index, item in ipairs(run.items) do item.session = index end

    if addon.Callbacks then
        addon.Callbacks:Fire("RunEnded")


        addon.Callbacks:Fire("SessionChanged", nil, "run")
    end
end


function Session:ApplyItemsAdd(payload, sender)
    if type(payload) ~= "table" or type(payload.items) ~= "table" then return end
    if not run.active then
        addon.Log:WLogOnly("Session", "items_add for a run that is not running")
        return
    end



    local added = {}
    for index, entry in pairs(payload.items) do
        if run.items[index] then
            if run.items[index].id == entry.id then

                addon.Log:D("Session", "items_add already applied", index)
            else
                addon.Log:W("Session", "items_add would overwrite session", index)
            end
        else
            run.items[index] = {
                id = entry.id,
                session = index,
                link = entry.link,
                owner = entry.owner,
                boss = entry.boss,
                encounterID = tonumber(entry.encounterID),
                simulated = entry.simulated and true or nil,
                difficultyID = entry.simulated and tonumber(entry.difficultyID) or nil,
                awarded = nil,
                delivered = false,
                candidates = NewCandidateSet(),
            }
            added[#added + 1] = index
            addon.Log:I("Session", "item appended by", tostring(sender), index, entry.link)
        end
    end
    ResolveMissingBosses()

    if addon.Callbacks then
        if #added > 0 then addon.Callbacks:Fire("ItemsAdded", added, run.id) end

        addon.Callbacks:Fire("SessionChanged", nil, "item")
    end
end



local rebuilding


local REBUILD_SETTLE = 4



local function BlankRow(row)
    if row == nil then return true end
    local cache = {}
    for key, value in pairs(row) do
        if key ~= "note" and not (key == "status" and value == "ANNOUNCED")
            and ValueHash(value, cache) ~= nil then
            return false
        end
    end
    return true
end



local function FillFromRefused()
    local copy = Refused.copy
    if not copy or copy.runId ~= run.id or type(copy.items) ~= "table" then return 0 end
    local count, cache = 0, {}
    for index, saved in ipairs(copy.items) do
        local item = run.items[index]
        if item and type(saved) == "table" and saved.id == item.id
            and type(saved.candidates) == "table" then
            for name, row in pairs(saved.candidates) do
                local current = item.candidates[name]
                if type(name) == "string" and type(row) == "table"
                    and RowHash(row, cache) ~= nil and BlankRow(current) then

                    local fill = CleanRow(row)

                    if current and type(current.note) == "string" then
                        fill.note = current.note
                    end
                    if fill.status == "AWARDED" and item.awarded ~= name then
                        fill.status = fill.realStatus or "ANNOUNCED"
                        fill.response = fill.realResponse
                        fill.realStatus, fill.realResponse = nil, nil
                    elseif item.awarded == name and fill.status ~= "AWARDED" then
                        fill.realStatus, fill.realResponse = fill.status, fill.response
                        fill.status = "AWARDED"
                    end
                    item.candidates[name] = fill
                    local marks = Refused.filled[index] or {}
                    Refused.filled[index] = marks
                    marks[name] = true
                    count = count + 1
                end
            end
        end
    end
    return count
end



local function SettleRebuild(runId)
    if not rebuilding or rebuilding.runId ~= runId then return end
    if run.active and run.id == runId and not run.complete then
        local count = FillFromRefused()
        if count > 0 then
            addon.Log:I("Session", "rebuild settled - filled", count,
                "row(s) the holders' replies left blank from my refused saved copy")
            if addon.Callbacks then addon.Callbacks:Fire("SessionChanged", nil, "run") end
        end
    end
    Refused.copy = nil
    if AnswerHeldForRebuild then AnswerHeldForRebuild() end
    rebuilding = nil
end



local function MaySendWhole(holder, runId)
    if addon.IsMasterLooter and addon.IsMasterLooter(holder) then return true end
    return asked.copyMaster ~= nil and asked.copyRun == runId
        and addon.Player:IsSame(asked.copyMaster, holder)
end



function Session:ApplyRunReply(payload, sender)
    if not addon.PlayerIsMasterLooter() then return false end
    local holder = addon.Player:Get(sender).fullName
    if not holder or not (addon.GetCandidates() or {})[holder] then
        addon.Log:WLogOnly("Session", "run recovery reply from someone outside the group",
            tostring(sender))
        return false
    end
    if not Asked() then
        Refuse("run_reply", "unasked", sender)
        return false
    end
    if not SnapshotValid(payload) then
        addon.Log:WLogOnly("Session", "invalid run recovery reply from", tostring(sender))
        return false
    end

    local me = addon.Player:GetFullName("player")
    if not me or not addon.Player:IsSame(payload.lootMaster, me) then
        addon.Log:WLogOnly("Session", "run recovery reply names another loot master",
            tostring(payload.lootMaster), "from", tostring(sender))
        return false
    end

    if run.active and (not run.recoveryFromReplies or run.id ~= payload.runId) then
        return false
    end
    if payload.candidateOnly then
        if not addon.Player:IsSame(payload.candidateOnly, holder) then
            addon.Log:WLogOnly("Session", "run recovery reply names another holder",
                tostring(payload.candidateOnly), "from", tostring(sender))
            return false
        end
        for _, item in ipairs(payload.items) do
            for name in pairs(item.candidates) do
                if not addon.Player:IsSame(name, holder) then
                    addon.Log:WLogOnly("Session", "run recovery reply claims another candidate",
                        tostring(name), "from", tostring(sender))
                    return false
                end
            end
        end
    elseif not MaySendWhole(holder, payload.runId) then
        Refuse("run_reply", "whole_run_from_a_holder", sender)
        return false
    end

    if not run.active then
        addon.Log:I("Session", "recovering run from", tostring(sender))
        rebuilding = payload.candidateOnly
            and { runId = payload.runId, settleAt = GetTime() + REBUILD_SETTLE } or nil
        Session:ApplyRunStart(payload, sender, true)
        if not run.active or run.id ~= payload.runId then
            rebuilding = nil
            return false
        end
        run.recoveryFromReplies = true
        run.recoverySources = {}
        if rebuilding then
            local runId = payload.runId
            C_Timer.After(REBUILD_SETTLE, function() SettleRebuild(runId) end)
        else

            Refused.copy = nil
        end
    end

    if run.recoverySources[holder] then return false end
    run.recoverySources[holder] = true
    local changed = false
    if addon.BonusRoll and type(payload.coins) == "table" then
        for _, coin in ipairs(payload.coins) do
            if type(coin) == "table" then
                local _, added = addon.BonusRoll.Apply(run.coins, coin.name, coin.link,
                    coin.epoch, coin.boss, coin.encounterID, coin.quantity)
                if added then changed = true end
            end
        end
    end
    for index, entry in ipairs(payload.items) do
        local item = run.items[index]
        if item and item.id == entry.id and item.link == entry.link then


            local marks = Refused.filled[index]
            for name, candidate in pairs(entry.candidates) do
                local current = item.candidates[name]
                if not current or (marks and marks[name]) or current.status == "ANNOUNCED"
                    or current.status == "NOTHING" or current.status == "NO_ADDON" then
                    if marks then marks[name] = nil end

                    item.candidates[name] = CleanRow(candidate)
                    changed = true
                end
            end
        else
            addon.Log:WLogOnly("Session", "run recovery reply item mismatch", index,
                "from", tostring(sender))
        end
    end

    if not payload.candidateOnly and not run.complete then
        run.complete = true

        Refused.copy = nil
        CloseAsk("recovered")
        if AnnounceRunState then AnnounceRunState() end
        if AnswerHeldForRebuild then AnswerHeldForRebuild() end
    end
    if changed and addon.Callbacks then addon.Callbacks:Fire("SessionChanged", nil, "run") end
    return true
end





function Session:Init()


    for _, command in ipairs({
        "run_end", "items_add", "sweep", "award", "unaward",
        "response", "response_set", "note", "whisper", "vote",
    }) do
        addon.Comms:ScopeToRun(command)
    end


    local function RegisterRun(command, authority, handler)
        addon.Comms:Register(command, authority, function(args, sender)
            if Session:HoldForRecovery(command, args, sender, handler) then return end
            local stamped = not run.active and type(args) == "table" and args.i or nil
            if type(stamped) == "string" and stamped ~= run.id and Session.NoteUnknownRun
                and not Session.RunHasEnded(stamped) then
                Session:NoteUnknownRun(stamped, sender)
            end
            handler(args, sender)
        end)
    end


    addon.Comms:Register("run_start", "ml", function(args, sender)
        if type(args) == "table" and args.dl ~= nil then
            return Session:ApplyRunDelta(args, sender)
        end
        Session:ApplyRunStart(args, sender)
    end)

    RegisterRun("run_end", "ml", function(_, _)
        Session:ApplyRunEnd()
    end)

    RegisterRun("items_add", "ml", function(args, sender)
        Session:ApplyItemsAdd(args, sender)
    end)


    addon.Comms:Register("delivered", "any", function(args, sender)
        if not args or not args.s then return end
        local ok, why = Session:MayReportHandover(args.s, args.w, sender, args.i)
        if not ok then return RefuseHandover("delivered", why, sender, args.s) end
        Session:ApplyDelivered(args.s, args.w, sender, args.l, args.i)
    end)


    addon.Comms:Register("undelivered", "any", function(args, sender)
        if not args or not args.s then return end
        local ok, why = Session:MayReportHandover(args.s, args.w, sender, args.i)
        if not ok then return RefuseHandover("undelivered", why, sender, args.s) end
        Session:ApplyUndelivered(args.s, args.w, sender, args.l, args.i, args.r,
            type(args.t) == "string" and args.t or nil)
    end)


    addon.Comms:Register("queue_drop", "any", function(args, sender)
        if type(args) ~= "table" or not args.l then return end
        Session:ApplyQueueDrop(args.l, args.held, sender, type(args.d) == "table" and args.d or nil)
    end)


    RegisterRun("item_remove", "ml", function(args, sender)
        if args and args.s then
            Session:ApplyRemove(args.s, args.on, sender, args.q, args.i)
        end
    end)



    RegisterRun("item_gone", "any", function(args, sender)
        if args and args.s and args.i then
            Session:ApplyGone(args.s, args.i, args.g, sender, args.o)
        end
    end)

    addon.Comms:Register("award_retract", "ml", function(args, sender)
        if args and args.i and args.s and args.w then
            Session:ApplyRetract(args.i, args.s, args.w, sender)
        end
    end)



    RegisterRun("sweep", "ml", function(args, _)
        local verdict
        if type(args) == "table" and args.j then
            verdict = {}
            for _, name in ipairs(type(args.na) == "table" and args.na or {}) do
                if type(name) == "string" then verdict[name] = true end
            end
        end
        Session:ApplySweep(args and args.s, verdict)
    end)

    RegisterRun("award", "ml", function(args, sender)
        if args and args.s and args.w then
            Session:ApplyAward(args.s, args.w, sender, args.r, args.q)
        end
    end)

    RegisterRun("unaward", "ml", function(args, sender)
        if args and args.s then
            Session:ApplyUnaward(args.s, sender, args.q)
        end
    end)


    RegisterRun("response", "any", function(args, sender)
        if not args or not args.s then return end
        local record = addon.Player:Get(sender)
        if not record.fullName then return end
        Session:ApplyResponse(args.s, record.fullName, args.r, args.n, sender,
            args.g)
    end)

    RegisterRun("note", "any", function(args, sender)
        if not args or not args.s or type(args.n) ~= "string" then return end
        local record = addon.Player:Get(sender)
        if not record.fullName then return end
        Session:ApplyNote(args.s, record.fullName, args.n, sender)
    end)


    RegisterRun("response_set", "ml", function(args, sender)
        if not args or not args.s or not args.c then return end
        Session:ApplyResponseSet(args.s, args.c, args.r, sender)
    end)


    RegisterRun("whisper", "ml", function(args, sender)
        if not args or not args.s or not args.c then return end
        Session:ApplyWhisperResponse(args.s, args.c, args.r, args.n, sender,
            args.g)
    end)



    RegisterRun("vote", "council", function(args, sender)
        if not args or not args.s or type(args.c) ~= "string" then return end


        if addon.Player:IsSelf(sender) then return end
        local record = addon.Player:Get(sender)
        if not record.fullName then return end
        Session:ReceiveVote(args.s, args.c, record.fullName, args.v)
    end)







    local noRunFrom
    local function KnownNoRun()
        return not run.active and noRunFrom ~= nil
    end



    local completeSeen = {}


    local askedFor = {}
    local ASK_AGAIN = 10
    local unknownAskedAt



    local THIN_REPLY_SPREAD = 3



    local REANSWER_AFTER = 5
    local answered = {}


    local function Rebuilding()
        return rebuilding ~= nil and run.active and run.id == rebuilding.runId
            and not run.complete and GetTime() < rebuilding.settleAt
    end



    local heldForRebuild = {}
    local function HoldForRebuild(sender, args)
        heldForRebuild[sender] = type(args) == "table" and args or {}
        addon.Log:D("Session", "holding the run request of", sender,
            "until the rebuild settles")
    end



    local function AnswerRunRequest(sender, args)
        local requester = addon.Player:Get(sender).fullName or sender
        local current = addon.GetMasterLooter and addon.GetMasterLooter()
        local requesterIsRunMaster = current
            and addon.Player:IsSame(requester, current)
        if not addon.PlayerIsMasterLooter() and not requesterIsRunMaster then return end
        local council = requesterIsRunMaster or
            (addon.Council and addon.Council.Contains
                and addon.Council:Contains(requester))

        if council and addon.PlayerIsMasterLooter() and Rebuilding() then
            return HoldForRebuild(sender, args)
        end
        local last = answered[requester]
        if last and last.runId == run.id and GetTime() - last.at < REANSWER_AFTER then
            addon.Log:D("Session", "run state already sent to", sender)
            return
        end
        answered[requester] = { runId = run.id, at = GetTime() }
        addon.Log:D("Session", "run state requested by", sender)


        if addon.PlayerIsMasterLooter() then


            local delta, changed, frames
            if type(args) == "table" and type(args.h) == "table" then
                delta, changed = RunCopy.Delta(args.h, requester, council)
                if delta then
                    delta.lootMaster = current or run.lootMaster
                    if addon.Comms.Measure then
                        frames = select(2, addon.Comms:Measure("run_start", delta))
                    end
                else
                    addon.Log:D("Session", "saved copy from", requester,
                        "is of no use - run", tostring(args.h.i), "is not this one,",
                        "or not the shape they are owed")
                end
            end
            local function SendDelta()
                addon.Log:D("Session", "recovery from a saved copy for", requester, "-",
                    changed, "of", #run.items, "item(s) changed,",
                    delta.coins and "coins changed," or "coins unchanged,",
                    tostring(frames), "frame(s)")
                addon.Comms:Send("run_start", delta, requester, true)
            end
            if delta and (not council or not frames or frames <= RunCopy.BURST) then
                return SendDelta()
            end


            if council and not requesterIsRunMaster and type(args) == "table"
                and args.d and Split.Send(requester, current) then
                return
            end
            if delta then return SendDelta() end
            local payload
            if council then
                payload = Snapshot()
            else
                payload = Snapshot(requester)
            end
            if not payload then return end
            payload.lootMaster = current or run.lootMaster
            addon.Comms:Send("run_start", payload, requester, true)
            return
        end



        if OwnsBackup() then
            local payload = Snapshot()
            if not payload then return end
            payload.lootMaster = current or run.lootMaster
            addon.Comms:Send("run_reply", payload, requester, true)
            return
        end
        local runId = run.id
        C_Timer.After(math.random() * THIN_REPLY_SPREAD, function()
            if not run.active or run.id ~= runId then return end
            if completeSeen[runId] then
                addon.Log:D("Session", "thin recovery reply not sent -",
                    "the loot master holds the whole run")
                return
            end
            local payload = Snapshot(addon.Player:GetFullName("player"))
            if not payload then return end
            payload.lootMaster = (addon.GetMasterLooter and addon.GetMasterLooter())
                or run.lootMaster
            addon.Comms:Send("run_reply", payload, requester, true)
        end)
    end



    AnswerHeldForRebuild = function()
        if next(heldForRebuild) == nil then return end
        local pending = heldForRebuild
        heldForRebuild, rebuilding = {}, nil
        local count, sources = 0, 0
        for _ in pairs(pending) do count = count + 1 end
        for _ in pairs(run.recoverySources or {}) do sources = sources + 1 end
        addon.Log:D("Session", "rebuild settled with", sources, "holder reply(ies) -",
            "answering", count, "held run request(s)")
        for sender, args in pairs(pending) do AnswerRunRequest(sender, args) end
    end



    local EARLY_REQUEST_WINDOW = 30
    local earlyRequests = {}
    local masterStepsFor


    local NONE_GATHER = 0.3
    local noneWaiting
    local function AnswerNoRun(sender)
        if noneWaiting then
            noneWaiting[sender] = true
            return
        end
        noneWaiting = { [sender] = true }
        C_Timer.After(NONE_GATHER, function()
            local asked = noneWaiting
            noneWaiting = nil
            if not KnownNoRun() or not addon.PlayerIsMasterLooter() then return end
            local count, only = 0, nil
            for name in pairs(asked) do count, only = count + 1, name end
            addon.Log:D("Session", "no run - answering", count, "request(s)")
            addon.Comms:Send("run_state", {}, count == 1 and only or nil)
        end)
    end

    addon.Comms:Register("run_request", "any", function(args, sender)

        if addon.Player:IsSame(sender, addon.Player:GetFullName("player")) then return end
        if run.active and (masterStepsFor ~= run.id
            or (addon.IsMasterLooter and addon.IsMasterLooter(sender))) then
            return AnswerRunRequest(sender, args)
        end

        earlyRequests[sender] = { at = GetTime(), args = args }
        if not run.active and addon.PlayerIsMasterLooter() and KnownNoRun() then
            AnswerNoRun(sender)
        end
    end)


    AnnounceRunState = function()
        if not run.active or not IsInGroup() or not addon.PlayerIsMasterLooter() then
            return
        end
        addon.Comms:Send("run_state", { i = run.id, c = run.complete or nil })
    end

    local function MasterSteps()
        masterStepsFor = nil
        local pending, now = earlyRequests, GetTime()
        earlyRequests = {}
        for sender, ask in pairs(pending) do
            if now - ask.at <= EARLY_REQUEST_WINDOW then
                addon.Log:D("Session", "answering run request held until recovery",
                    sender)
                AnswerRunRequest(sender, ask.args)
            end
        end
        AnnounceRunState()
    end

    addon.Callbacks:Register("RunRecovered", function()
        if not IsInGroup() or addon.PlayerIsMasterLooter() then
            MasterSteps()
            return
        end
        masterStepsFor = run.id
        addon.Log:D("Session", "recovered run", tostring(run.id),
            "- finishing its recovery once this client is the loot master")
    end)

    local function BecameMaster()
        if not masterStepsFor then return end
        if not run.active or run.id ~= masterStepsFor then
            masterStepsFor = nil
            return
        end
        if not IsInGroup() or not addon.PlayerIsMasterLooter() then return end
        addon.Log:I("Session", "now the loot master of recovered run", tostring(run.id),
            "- finishing its recovery")
        ScheduleRecoveredSweep()
        MasterSteps()
    end
    addon.Callbacks:Register("LootMasterChanged", BecameMaster)
    addon.Callbacks:Register("SharedConfigChanged", BecameMaster)



    addon.Comms:Register("run_reply", "any", function(args, sender)
        if type(args) == "table" and args.p then
            Session:ApplyRunPart(args, sender)
        else
            Session:ApplyRunReply(args, sender)
        end
    end)






    addon.Comms:ScopeToRun("run_help")
    addon.Comms:ScopeToRun("run_fill")



    local helped = {}
    addon.Comms:Register("run_help", "ml", function(args, sender)
        local me = addon.Player:GetFullName("player")
        if not me or addon.Player:IsSame(sender, me) then return end
        if type(args) ~= "table" or type(args.w) ~= "string" then return end
        if not run.active or addon.Player:IsSame(args.w, me) then return end
        local requester, runId = args.w, run.id
        local last = helped[requester]
        if last and last.runId == runId and GetTime() - last.at < REANSWER_AFTER then return end
        helped[requester] = { runId = runId, at = GetTime() }
        local resync = addon.Player:IsSame(requester, sender)
        C_Timer.After(math.random() * Split.SPREAD, function()
            if not run.active or run.id ~= runId then return end
            if resync then
                for _, item in ipairs(run.items) do
                    if item.link and not item.simulated and not item.awarded
                        and not item.delivered and not item.removed
                        and addon.Player:IsSelf(item.owner) then
                        addon.Comms:Send("item_gone", { s = item.session, i = runId,
                            g = item.gone or false, o = item.owed or false }, requester, true)
                    end
                end
                if addon.Callbacks then addon.Callbacks:Fire("RunResyncRequested", runId) end
            end
            local part, rows, lists = Split.OwnPart(me)
            if not part then
                addon.Log:D("Session", "nothing of mine to add to", requester, "'s recovery")
                return
            end
            addon.Log:D("Session", "recovery part for", requester .. ":", rows, "row(s),",
                lists, "vote list(s)")
            addon.Comms:Send("run_reply", part, requester, true)
        end)
    end)



    addon.Comms:Register("run_fill", "any", function(args, sender)
        if not run.active or not addon.PlayerIsMasterLooter() then return end
        local requester = addon.Player:Get(sender).fullName or sender
        if not (addon.Council and addon.Council:Contains(requester)) then
            addon.Log:WLogOnly("Session", "refusing a recovery fill for someone not on the council",
                tostring(sender))
            return
        end

        if Split.skeletonOf[requester] ~= run.id then
            return Refuse("run_fill", "unasked", sender)
        end
        Split.skeletonOf[requester] = nil
        local names = type(args) == "table" and type(args.w) == "table" and args.w or {}
        local part = Split.Fill(names)
        addon.Log:D("Session", "filling", #part.vv, "missing part(s) for", requester)
        addon.Comms:Send("run_reply", part, requester, true)
    end)



    addon.Comms:Register("run_state", "ml", function(args, sender)
        if addon.Player:IsSame(sender, addon.Player:GetFullName("player")) then return end
        local runId = type(args) == "table" and args.i or nil
        local endedId = runId == nil and type(args) == "table" and type(args.x) == "string"
            and args.x or nil
        if endedId then
            if run.active and run.id == endedId then
                addon.Log:I("Session", "the loot master ended run", endedId, "- ending it here")
                Session:ApplyRunEnd()
                return
            end
            RememberEnded(endedId)
        end
        if runId == nil then
            if run.active then return end
            noRunFrom = addon.Player:Get(sender).fullName or sender
            addon.Log:D("Session", "no run, says", sender)
            CloseHold("no_run")

            RunCopy.Drop("no_run")
            return
        end
        if type(runId) ~= "string" then return end
        noRunFrom = nil
        if args.c then completeSeen[runId] = true end
        if run.active and run.id == runId then return end
        if Session.RunHasEnded(runId) then return end
        if run.active then
            if not RunIsNewer(runId, run.id) then return end
            addon.Log:I("Session", "the loot master holds newer run", runId, "- ending",
                tostring(run.id), "here")
            Session:ApplyRunEnd()
        end
        for id in pairs(askedFor) do
            if id ~= runId then askedFor[id] = nil end
        end
        local now = GetTime()
        if askedFor[runId] and now - askedFor[runId] < ASK_AGAIN then return end
        askedFor[runId] = now
        addon.Log:I("Session", "the loot master holds run", tostring(runId), "- asking for it")
        AskForRun(RunCopy.Request(), sender)
    end)



    local function PoliceOwnQueue()
        if run.active then return end

        local mine = {}
        for _, item in ipairs(run.items) do
            if item.link and not item.simulated and addon.Player:IsSelf(item.owner) then
                local id = addon.Storage.ItemID(item.link)
                if id then mine[id] = item.link end
            end
        end
        if not next(mine) then return end

        local dropped, links, counts = Session:PruneUnheld()


        if dropped > 0 and counts and not addon.PlayerIsMasterLooter() then
            local gone = {}
            for _, link in ipairs(links or {}) do
                local id = addon.Storage.ItemID(link)
                if id then
                    gone[id] = gone[id] or {}
                    table.insert(gone[id], link)
                end
            end
            for id, link in pairs(mine) do
                local list = gone[id]

                addon.Comms:Send("queue_drop", {
                    l = list and list[1] or link,
                    held = counts[id] and counts[id].n or 0,
                    d = list,
                }, nil, true)
            end
        end
    end
    addon.Callbacks:Register("StorageChanged", PoliceOwnQueue)



    local bagCheckQueued = false
    local bagFrame = CreateFrame("Frame")

    local watching = false
    WatchBags = function()
        local own = false
        for _, item in ipairs(run.items) do
            if item.link and not item.simulated and addon.Player:IsSelf(item.owner) then
                own = true
                break
            end
        end
        if own == watching then return end
        watching = own
        if own then
            bagFrame:RegisterEvent("BAG_UPDATE_DELAYED")
        else
            bagFrame:UnregisterEvent("BAG_UPDATE_DELAYED")
        end
    end
    addon.Callbacks:Register("RunStarted", WatchBags)
    addon.Callbacks:Register("SessionChanged", function(_, kind)
        if kind == nil or kind == "item" or kind == "run" then WatchBags() end
    end)


    local function CheckSoon(delay)
        if bagCheckQueued or #run.items == 0 then return end
        bagCheckQueued = true
        C_Timer.After(delay or 2, function()
            bagCheckQueued = false
            if run.active then Session:CheckHeld() else PoliceOwnQueue() end
        end)
    end
    bagFrame:SetScript("OnEvent", function() CheckSoon() end)


    addon.Callbacks:Register("ItemUnawarded", function() CheckSoon(1) end)
    addon.Callbacks:Register("RunStarted", function() CheckSoon() end)
    addon.Callbacks:Register("ItemsAdded", function() CheckSoon() end)


    addon.Callbacks:Register("StorageChanged", function() CheckSoon(1) end)



    local saveFrame = CreateFrame("Frame")
    saveFrame:RegisterEvent("PLAYER_LOGOUT")
    saveFrame:SetScript("OnEvent", function() Session:SaveRun() end)
    addon.Callbacks:Register("RunStarted", NoteAuthority)

    addon.Callbacks:Register("RunEnded", function()
        ClearPersisted()
        PruneDrops()

        RunCopy.Drop("run_ended")
        if addon.db then addon.db.runCopy = {} end
        noRunFrom = run.lootMaster or "?"
        ForgetUndelivered()
    end)

    addon.Callbacks:Register("CouncilChanged", function() RunCopy.SendVotes() end)




    local recoveryPending, recoveryGroupKey, recoveryAttempts = false, nil, 0
    local recoveryAuthority
    local recoveryWaiting = false
    addon.Callbacks:Register("RunStarted", function()
        noRunFrom = nil
        askedFor = {}
        recoveryAttempts = 0
    end)
    local function SavedSoloRun()
        local saved = addon.db and addon.db.activeRun
        local me = addon.Player:GetFullName("player")
        return type(saved) == "table" and me ~= nil
            and saved.groupKey == GroupKey()
            and addon.Player:IsSame(saved.lootMaster, me)
    end



    local function AskTarget(attempt)
        if addon.PlayerIsMasterLooter() then return nil end
        local master = addon.GetMasterLooter and addon.GetMasterLooter()
        if master and attempt < 3 then return master end
        return nil
    end



    function Session:NoteUnknownRun(runId, sender)
        if type(runId) ~= "string" or Session.RunHasEnded(runId) or askedFor[runId] then return end
        if run.active and (run.id == runId or not RunIsNewer(runId, run.id)) then return end
        if not IsInGroup() or addon.PlayerIsMasterLooter() or Blocked() then return end
        local now = GetTime()
        if unknownAskedAt and now - unknownAskedAt < ASK_AGAIN then return end
        unknownAskedAt = now
        askedFor[runId] = now
        addon.Log:I("Session", "heard run", runId, "from", tostring(sender),
            "- asking the loot master for it")
        AskForRun(RunCopy.Request(), AskTarget(1))
    end


    local CONCLUDE_AFTER = 3
    local function Conclude(key)
        C_Timer.After(CONCLUDE_AFTER, function()
            if run.active or recoveryPending or recoveryGroupKey ~= key then return end
            if not addon.PlayerIsMasterLooter() then return end
            local saved = addon.db and addon.db.activeRun
            local me = addon.Player:GetFullName("player")
            if type(saved) == "table" and saved.runId ~= nil
                and addon.Player:IsSame(saved.lootMaster, me) then
                return
            end
            noRunFrom = me or "?"

            CloseAsk("no_run")
            addon.Log:I("Session", "no run to recover - answering those who asked")
            local now = GetTime()
            for sender, ask in pairs(earlyRequests) do
                if now - ask.at <= EARLY_REQUEST_WINDOW then AnswerNoRun(sender) end
            end
        end)
    end

    local function ScheduleRecovery()
        if recoveryPending or run.active then return end
        if IsInGroup() and not KnownNoRun() then OpenHold() end
        recoveryPending = true
        C_Timer.After(2, function()
            recoveryPending = false
            if run.active then return end
            if not IsInGroup() then

                noRunFrom = nil
                recoveryGroupKey, recoveryAuthority, recoveryAttempts = nil, nil, 0
                CloseHold("left_group")
                if SavedSoloRun() then Session:RecoverPersisted() end
                return
            end



            local authority = tostring(addon.GetMasterLooter())
            local key = GroupKey() .. "|" .. authority
            local keyChanged = recoveryGroupKey ~= key
            if keyChanged then
                local inFlight = recoveryAttempts > 0 and recoveryAttempts < 3
                if recoveryAuthority ~= authority
                    or (not inFlight and addon.PlayerIsMasterLooter()) then
                    recoveryAttempts = 0
                end
                recoveryGroupKey, recoveryAuthority = key, authority
            end
            if recoveryAttempts >= 3 then
                if keyChanged then
                    addon.Log:D("Session", "run request not repeated -", authority, "has not answered")
                end
                return
            end
            if Session:RecoverPersisted() then return end


            if KnownNoRun() then return end

            if Blocked() then
                recoveryWaiting = true
                addon.Log:I("Session", "run request waits for the blackout to lift")
                return
            end
            recoveryAttempts = recoveryAttempts + 1
            if addon.PlayerIsMasterLooter() then
                addon.Log:I("Session", "requesting active run after local recovery failed",
                    recoveryAttempts, "/3")
            end


            AskForRun(RunCopy.Request(), AskTarget(recoveryAttempts))


            if recoveryAttempts < 3 then
                ScheduleRecovery()
            elseif addon.PlayerIsMasterLooter() then
                Conclude(key)
            end
        end)
    end



    local function OnGroupChange(diff)
        if run.active and type(diff) == "table" and diff.wasInGroup and diff.inGroup == false
            and not IsInGroup() and GroupRun() then
            addon.Log:I("Session", "left the group - closing run", tostring(run.id), "on this side")
            Session:ApplyRunEnd()
            ScheduleRecovery()
            return
        end
        if run.active then NoteAuthority() else ScheduleRecovery() end
    end
    local ZONE_ASK_GAP = 30
    local zoneAskedAt
    local recoveryFrame = CreateFrame("Frame")
    recoveryFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    recoveryFrame:SetScript("OnEvent", function(_, _, isInitialLogin, isReloadingUi)
        if run.active then return NoteAuthority() end
        if not isInitialLogin and not isReloadingUi and KnownNoRun() and IsInGroup()
            and not recoveryPending and not addon.PlayerIsMasterLooter() and not Blocked() then
            local now = GetTime()
            if not zoneAskedAt or now - zoneAskedAt >= ZONE_ASK_GAP then
                zoneAskedAt, unknownAskedAt = now, now
                addon.Log:D("Session", "asking the loot master for a run after a loading screen")
                AskForRun(RunCopy.Request(), AskTarget(1))
                return
            end
        end
        ScheduleRecovery()
    end)
    addon.Callbacks:Register("RosterChanged", OnGroupChange)
    addon.Callbacks:Register("CouncilChanged", function() OnGroupChange() end)
    if addon.Restrictions then addon.Restrictions:OnChange(function(isBlocked)
        if isBlocked then return end
        ResumeSweeps()
        if Split.resyncFor and run.active and run.id == Split.resyncFor then Split.Resync() end
        if not recoveryWaiting then return end
        recoveryWaiting = false
        ScheduleRecovery()
    end) end

    RunCopy.Load()
    ScheduleRecovery()

    addon.Log:I("Session", "ready")
end
