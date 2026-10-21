if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Comms = {}
addon.Comms = Comms

local byte, char, sub = string.byte, string.char, string.sub

local Stats = {}
Comms.Stats = Stats



local statOps = {}
local statQueueMax, statSince = 0, 0
local statLaneMax = {}
local statThrottle = {}
local statDropped = { gaveup = 0, failed = 0, blocked = 0 }
local statDroppedFrames = { gaveup = 0, failed = 0, blocked = 0 }

local statRefused = {}

local LATENCY_RING = 200
local function NewRing() return { count = 0, next = 1 } end
local latency, laneLatency = NewRing(), {}

local function StatOp(command)
    local op = statOps[command]
    if not op then
        op = { 0, 0, 0, 0, 0 }
        statOps[command] = op
    end
    return op
end

local function Push(ring, seconds)
    ring[ring.next] = seconds
    ring.next = ring.next % LATENCY_RING + 1
    if ring.count < LATENCY_RING then ring.count = ring.count + 1 end
end

function Stats.Sent(command, bytes)
    local op = StatOp(command or "?")
    op[1] = op[1] + 1
    op[2] = op[2] + bytes
end

function Stats.Received(command, frames, bytes)
    local op = StatOp(command or "?")
    op[3] = op[3] + frames
    op[4] = op[4] + bytes
end

function Stats.Dispatched(command)
    local op = StatOp(command)
    op[5] = op[5] + 1
end

function Stats.Queued(depth, lane, laneDepth)
    if depth > statQueueMax then statQueueMax = depth end
    if lane and laneDepth and laneDepth > (statLaneMax[lane] or 0) then
        statLaneMax[lane] = laneDepth
    end
end

function Stats.Throttled(result)
    statThrottle[result] = (statThrottle[result] or 0) + 1
end

function Stats.Dropped(kind, command, frames)
    statDropped[kind] = (statDropped[kind] or 0) + 1
    statDroppedFrames[kind] = (statDroppedFrames[kind] or 0) + (frames or 1)
end



function Stats.Refused(reason)
    statRefused[reason] = (statRefused[reason] or 0) + 1
end

function Stats.Latency(seconds, lane)
    Push(latency, seconds)
    if lane then
        local ring = laneLatency[lane]
        if not ring then
            ring = NewRing()
            laneLatency[lane] = ring
        end
        Push(ring, seconds)
    end
end


function Stats.Percentiles(samples, n)
    if not n or n < 1 then return nil end
    local sorted = {}
    for i = 1, n do sorted[i] = samples[i] end
    table.sort(sorted)
    return sorted[math.max(1, math.ceil(n * 0.5))],
        sorted[math.max(1, math.ceil(n * 0.95))], sorted[n]
end

function Stats.Reset()
    statOps, statThrottle, statLaneMax = {}, {}, {}
    statQueueMax = 0
    statDropped = { gaveup = 0, failed = 0, blocked = 0 }
    statDroppedFrames = { gaveup = 0, failed = 0, blocked = 0 }
    statRefused = {}
    latency, laneLatency = NewRing(), {}
    statSince = GetTime and GetTime() or 0
end

local function RingReport(ring)
    local n = ring and ring.count or 0
    local p50, p95, max = Stats.Percentiles(ring or {}, n)
    return { p50 = p50, p95 = p95, max = max, n = n }
end



local lanes, QueueDepth, BudgetNow



function Stats.Report()
    local ops = {}
    for command, op in pairs(statOps) do
        ops[command] = {
            sentFrames = op[1], sentBytes = op[2],
            receivedFrames = op[3], receivedBytes = op[4], dispatched = op[5],
        }
    end
    local throttle, dropped, droppedFrames, refused = {}, {}, {}, {}
    for k, v in pairs(statThrottle) do throttle[k] = v end
    for k, v in pairs(statDropped) do dropped[k] = v end
    for k, v in pairs(statDroppedFrames) do droppedFrames[k] = v end
    for k, v in pairs(statRefused) do refused[k] = v end
    local perLane = {}
    for _, lane in ipairs(lanes or {}) do
        perLane[lane.name] = {
            prefix = lane.prefix,
            queueNow = #lane.queue,
            queueMax = statLaneMax[lane.name] or 0,
            latency = RingReport(laneLatency[lane.name]),
        }
    end
    return {
        since = statSince,
        ops = ops,
        queueNow = QueueDepth and QueueDepth() or 0,
        queueMax = statQueueMax,
        throttle = throttle,
        dropped = dropped,
        droppedFrames = droppedFrames,
        refused = refused,
        latency = RingReport(latency),
        lanes = perLane,
        budget = BudgetNow and BudgetNow() or nil,
    }
end







local CONTROL, BULK, PRESENCE = 1, 2, 3


local LEGACY_PREFIX = "SLC"

local LEGACY_MAX_PAYLOAD = 240


local FIRST_CURRENT_MINOR = 41




lanes = {
    [CONTROL] = { name = "control", prefix = LEGACY_PREFIX .. "c", queue = {}, pausedUntil = 0,
        maxChunks = 64 },
    [BULK] = { name = "bulk", prefix = LEGACY_PREFIX .. "b", queue = {}, pausedUntil = 0,
        maxChunks = 254 },
    [PRESENCE] = { name = "presence", prefix = LEGACY_PREFIX .. "p", queue = {}, pausedUntil = 0,
        maxChunks = 64 },
}
local laneByPrefix = {}
for _, lane in ipairs(lanes) do laneByPrefix[lane.prefix] = lane end


local LANE_OF = {


    bags = BULK,


    bags_request = BULK,


    history = BULK,

    pull = BULK,

    config_offer = BULK,

    run_reply = BULK,


    version = PRESENCE,
    version_request = PRESENCE,
    spec = PRESENCE,

    hello = PRESENCE,
    hello_digest = PRESENCE,

    ping = PRESENCE,
}

local function LaneFor(command, target)
    if command == "run_start" and target then return lanes[BULK] end
    return lanes[LANE_OF[command] or CONTROL]
end

function QueueDepth()
    return #lanes[CONTROL].queue + #lanes[BULK].queue + #lanes[PRESENCE].queue
end







local FRAME_MAX = 255
local SINGLE_ROOM = FRAME_MAX - 1
local CHUNK_ROOM = FRAME_MAX - 4


local MAX_CHUNKS = 254


local MAX_MESSAGE_ID = 254

local KIND_SINGLE, KIND_CHUNK = byte("S"), byte("C")


local INCOMPLETE_TTL = 30

local handlers = {}
local pending = {}




local MAX_INFLATED = 1048576
local OUTSIDER_MAX_INFLATED = 32768

local MAX_COMMAND = 32

local MAX_PARTIALS, OUTSIDER_MAX_PARTIALS = 8, 1
local partialsOf = {}

local MAX_REMEMBERED = 256

local function NewSet() return { keys = {}, n = 0 } end


local function FirstTime(set, key)
    if set.keys[key] then return false end
    if set.n >= MAX_REMEMBERED then set.keys, set.n = {}, 0 end
    set.keys[key] = true
    set.n = set.n + 1
    return true
end


local nextMessageId = math.random(1, MAX_MESSAGE_ID)








local ESCAPE = { ["\0"] = "\1\1", ["\1"] = "\1\2" }
local UNESCAPE = { ["\1"] = "\0", ["\2"] = "\1" }

function Comms.Escape(raw)
    return (raw:gsub("[%z\1]", ESCAPE))
end



function Comms.Unescape(escaped)
    return (escaped:gsub("\1([\1\2])", UNESCAPE))
end
local Escape, Unescape = Comms.Escape, Comms.Unescape




function Comms.Split(escaped)
    local pieces, first, length = {}, 1, #escaped
    while first <= length do
        local last = first + CHUNK_ROOM - 1
        if last >= length then
            last = length
        else
            local run = 0
            while last - run >= first and byte(escaped, last - run) == 1 do
                run = run + 1
            end
            if run % 2 == 1 then last = last - 1 end
        end
        pieces[#pieces + 1] = sub(escaped, first, last)
        first = last + 1
    end
    return pieces
end
local Split = Comms.Split


local function Serialise(command, args)
    local payload = { c = command, a = args }
    if hasanysecretvalues and hasanysecretvalues(payload) then
        addon.Log:W("Comms", "refusing to send payload containing secrets", command)
        return nil
    end
    local ok, deflated = pcall(function()
        local cbor = C_EncodingUtil.SerializeCBOR(payload)
        return C_EncodingUtil.CompressString(cbor,
            Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
    end)
    if not ok or not deflated then
        addon.Log:Bug("Comms", ("encode failed for %s: %s"):format(command, tostring(deflated)))
        return nil
    end
    return deflated
end

local function Encode(command, args)
    local deflated = Serialise(command, args)
    return deflated and Escape(deflated) or nil
end


local function Inflate(raw, limit)
    local ok, value, size = pcall(function()
        local inflated = C_EncodingUtil.DecompressString(raw, Enum.CompressionMethod.Deflate)
        if type(inflated) ~= "string" then return nil end
        if #inflated > limit then return nil, #inflated end
        return C_EncodingUtil.DeserializeCBOR(inflated)
    end)
    if ok and type(value) == "table" then return value end
    return nil, ok and size or nil
end


local undecodableLogged = NewSet()

local function Decode(escaped, limit, sender)
    local value, size = Inflate(Unescape(escaped), limit)
    if not value and FirstTime(undecodableLogged, tostring(sender) .. "|" .. tostring(size ~= nil)) then
        if size then
            addon.Log:WLogOnly("Comms", "inflated message too large", size, "from", sender)
        else
            addon.Log:WLogOnly("Comms", "undecodable message discarded", "from", sender)
        end
    end
    return value, size
end


local function LegacyEncode(command, args)
    local deflated = Serialise(command, args)
    if not deflated then return nil end
    local ok, encoded = pcall(C_EncodingUtil.EncodeBase64, deflated,
        Enum.Base64Variant.StandardUrlSafe)
    return ok and encoded or nil
end

local function LegacyDecode(encoded)
    local ok, raw = pcall(C_EncodingUtil.DecodeBase64, encoded,
        Enum.Base64Variant.StandardUrlSafe)
    return ok and raw and Inflate(raw, MAX_INFLATED) or nil
end







local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end








local THROTTLE_PAUSE = 0.35


local MAX_ATTEMPTS = 30

local LOCKDOWN_PAUSE = 2
local MAX_LOCKDOWNS = 150




local GOVERNOR_BURST = 4000
local GOVERNOR_RATE = 800
local LOW_FPS = 20
local budget, budgetAt, refillRate = GOVERNOR_BURST, nil, GOVERNOR_RATE



function BudgetNow()
    local elapsed = budgetAt and GetTime() - budgetAt or 0
    return math.floor(math.min(GOVERNOR_BURST, budget + math.max(0, elapsed) * refillRate))
end



local function Refill(now)
    local elapsed = budgetAt and now - budgetAt or 0
    budgetAt = now
    if elapsed <= 0 or budget >= GOVERNOR_BURST then return end
    refillRate = GetFramerate() < LOW_FPS and GOVERNOR_RATE / 2 or GOVERNOR_RATE
    budget = math.min(GOVERNOR_BURST, budget + elapsed * refillRate)
end



local driver
local wakeAt = 0
local pumping = false

local nextShared = BULK


local batch
local FlushBatch



local function DropHead(lane)
    local queue = lane.queue
    local messageId = queue[1].messageId
    table.remove(queue, 1)
    if not messageId then return 1 end
    local dropped = 1
    local i = 1
    while queue[i] do
        if queue[i].messageId == messageId then
            table.remove(queue, i)
            dropped = dropped + 1
        else
            i = i + 1
        end
    end
    return dropped
end



local function NextLane(now)
    local control = lanes[CONTROL]
    if control.queue[1] and now >= control.pausedUntil then return control end
    local first = lanes[nextShared]
    if first.queue[1] and now >= first.pausedUntil then return first end
    local other = lanes[nextShared == BULK and PRESENCE or BULK]
    if other.queue[1] and now >= other.pausedUntil then return other end
    return nil
end



local function Drain(now)
    if batch and now >= batch.flushAt then FlushBatch() end
    Refill(now)

    local wake
    while true do
        local lane = NextLane(now)
        if not lane then break end
        local frame = lane.queue[1]
        local cost = #frame.prefix + #frame.body
        if budget < cost then
            wake = now + (cost - budget) / refillRate
            break
        end
        if lane ~= lanes[CONTROL] then
            nextShared = lane == lanes[BULK] and PRESENCE or BULK
        end


        local ok, result = pcall(C_ChatInfo.SendAddonMessage,
            frame.prefix, frame.body, frame.channel,
            frame.target and addon.Player:WhisperTarget(frame.target))

        if not ok then
            addon.Log:Bug("Comms", ("send raised for %s on %s: %s"):format(
                tostring(frame.command), tostring(frame.channel), tostring(result)))
            Stats.Dropped("failed", frame.command, DropHead(lane))
        elseif result == Enum.SendAddonMessageResult.Success then
            table.remove(lane.queue, 1)
            budget = budget - cost
            Stats.Sent(frame.command, #frame.body)
            Stats.Latency(now - frame.at, lane.name)
            if frame.lockdowns then
                addon.Log:I("Comms", "sent after a lockdown", frame.command, frame.lockdowns)
            end
        elseif result == Enum.SendAddonMessageResult.AddonMessageThrottle
            or result == Enum.SendAddonMessageResult.ChannelThrottle then
            Stats.Throttled(result)
            frame.attempts = (frame.attempts or 0) + 1
            if frame.attempts >= MAX_ATTEMPTS then
                addon.Log:E("Comms", "gave up after throttling", frame.command, frame.attempts)
                Stats.Dropped("gaveup", frame.command, DropHead(lane))
            else

                lane.pausedUntil = now + THROTTLE_PAUSE
            end
        elseif result == Enum.SendAddonMessageResult.AddOnMessageLockdown then

            frame.lockdowns = (frame.lockdowns or 0) + 1
            if frame.lockdowns == 1 then
                addon.Log:W("Comms", "held - addon messages locked down", frame.command,
                    frame.channel)
            end
            if frame.lockdowns >= MAX_LOCKDOWNS then
                addon.Log:E("Comms", "gave up after a lockdown", frame.command, frame.lockdowns)
                Stats.Dropped("gaveup", frame.command, DropHead(lane))
            else
                lane.pausedUntil = now + LOCKDOWN_PAUSE
            end
        else


            addon.Log:WLogOnly("Comms", "send failed", result, frame.command, frame.channel)
            Stats.Dropped("failed", frame.command, DropHead(lane))
        end
    end


    for _, lane in ipairs(lanes) do
        if lane.queue[1] and lane.pausedUntil > now
            and (not wake or lane.pausedUntil < wake) then
            wake = lane.pausedUntil
        end
    end
    if batch and (not wake or batch.flushAt < wake) then wake = batch.flushAt end
    return wake
end



local PARK_AFTER = 1
local parkGeneration = 0



local function Pump()
    if pumping then return end
    pumping = true
    local now = GetTime()
    local ok, wake = pcall(Drain, now)
    pumping = false
    if not ok then
        addon.Log:Bug("Comms", "pump raised: " .. tostring(wake))
        wake = now + THROTTLE_PAUSE
    end
    if not driver then return end
    parkGeneration = parkGeneration + 1
    if wake and wake - now >= PARK_AFTER then
        driver:Hide()
        local generation = parkGeneration
        C_Timer.After(wake - now, function()
            if generation == parkGeneration then Pump() end
        end)
    elseif wake then
        wakeAt = wake
        driver:Show()
    else
        driver:Hide()
    end
end



local function Enqueue(lane, body, channel, target, command, messageId, prefix)
    local queue = lane.queue
    queue[#queue + 1] = {
        body = body, channel = channel, target = target, prefix = prefix or lane.prefix,
        command = command, messageId = messageId, at = GetTime(),
    }
    Stats.Queued(QueueDepth(), lane.name, #queue)
end






function Comms:Measure(command, args)
    local escaped = Encode(command, args)
    if not escaped then return nil end
    if #escaped <= SINGLE_ROOM then return #escaped, 1 end
    return #escaped, #Split(escaped)
end

local function SendFramed(lane, command, escaped, channel, target)
    if #escaped <= SINGLE_ROOM then

        addon.Log:D("Comms", "queued", command, channel, lane.name, #escaped .. "b", "1 frame")
        Enqueue(lane, "S" .. escaped, channel, target, command)
        Pump()
        return true
    end


    local pieces = Split(escaped)
    local total = #pieces
    if total > MAX_CHUNKS or total > lane.maxChunks then
        addon.Log:E("Comms", "payload too large to chunk", command, #escaped, lane.name)
        return false
    end

    nextMessageId = nextMessageId % MAX_MESSAGE_ID + 1
    local id = nextMessageId



    addon.Log:D("Comms", "queued", command, channel, lane.name, #escaped .. "b", total .. " chunks")


    local head, totalByte = "C" .. char(id + 1), char(total + 1)
    for seq = 1, total do
        Enqueue(lane, head .. char(seq + 1) .. totalByte .. pieces[seq],
            channel, target, command, id)
    end
    Pump()
    return true
end









local runScoped = {}

function Comms:ScopeToRun(command)
    runScoped[command] = true
end

local function CurrentRunId()
    local session = addon.Session
    return session and session.GetRunId and session:GetRunId() or nil
end



function Comms.IsStale(stamped, current)
    return stamped ~= nil and current ~= nil and stamped ~= current
end



local function Stamp(command, args)
    if runScoped[command] and type(args) == "table" and args.i == nil then
        args.i = CurrentRunId()
    end
end







local droppedWhileBlocked = {}
local resumers = {}

function Comms:OnResume(command, rebuild)
    resumers[command] = rebuild
end


local function Resume()
    local dropped = droppedWhileBlocked
    droppedWhileBlocked = {}
    for command in pairs(dropped) do
        local rebuild = resumers[command]
        if rebuild then
            addon.Log:I("Comms", "re-sending after a blackout", command)
            local ok, err = pcall(rebuild)
            if not ok then addon.Log:Bug("Comms", tostring(err)) end
        else
            addon.Log:D("Comms", "stays dropped after a blackout", command)
        end
    end
end
Comms.Resume = function(_) Resume() end


local RESUME_DELAY = 1



function Comms:Send(command, args, target, guaranteed)
    Stamp(command, args)

    local channel, resolvedTarget = GroupChannel(), nil
    if target then
        channel, resolvedTarget = "WHISPER", target
    elseif not channel then

        channel, resolvedTarget = "WHISPER", addon.Player:GetFullName("player")
        if not resolvedTarget then
            addon.Log:D("Comms", "no channel available, dropping", command)
            return false
        end
    end



    if addon.Restrictions:IsBlocked() then
        if guaranteed then
            addon.Restrictions:Enqueue({
                command = command,
                args = args,
                target = target,
                guaranteed = true,
            })
        else
            addon.Log:D("Comms", "dropped while restricted", command)
            Stats.Dropped("blocked", command, 0)
            droppedWhileBlocked[command] = true
        end
        return false
    end

    local escaped = Encode(command, args)
    if not escaped then return false end

    return SendFramed(LaneFor(command, target), command, escaped, channel, resolvedTarget)
end






local BATCHABLE = { response = true, note = true, vote = true }
local BATCH = "batch"



local BATCH_WINDOW = 0.12




function Comms:SendBatched(command, args, target, guaranteed)
    if target or not BATCHABLE[command] then
        addon.Log:W("Comms", "not batchable, sent at once", command, target)
        return Comms:Send(command, args, target, guaranteed)
    end

    if addon.Restrictions:IsBlocked() then
        return Comms:Send(command, args, nil, guaranteed)
    end

    Stamp(command, args)
    if not batch then
        batch = { entries = {}, flushAt = GetTime() + BATCH_WINDOW }
    end
    batch.entries[#batch.entries + 1] = { c = command, a = args }
    if guaranteed then batch.guaranteed = true end
    Pump()
    return true
end



function FlushBatch()
    local held = batch
    batch = nil
    if not held then return end
    local entries = held.entries
    if #entries == 1 then
        Comms:Send(entries[1].c, entries[1].a, nil, held.guaranteed)
    else
        addon.Log:D("Comms", "batched", #entries, "entries")
        Comms:Send(BATCH, { l = entries }, nil, held.guaranteed)
    end
end







local CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }


local FROM_OUTSIDE = { config_offer = true }



local outsiderPrefix = {}
for command in pairs(FROM_OUTSIDE) do outsiderPrefix[LaneFor(command).prefix] = true end
local OUTSIDER_MAX_CHUNKS = 32
local OUTSIDER_WINDOW = 30
local outsiderHeard, outsiderCount = {}, 0


local function IsMember(sender)
    local roster = addon.Roster
    return roster and roster.IsMember and roster:IsMember(sender) or false
end



local refusalLogged = NewSet()
local function Refuse(reason, subject, sender, detail)
    Stats.Refused(reason)
    if not FirstTime(refusalLogged, reason .. "|" .. tostring(subject) .. "|" .. tostring(sender)) then
        return
    end
    if detail ~= nil then
        addon.Log:D("Comms", "refused", reason, subject, "from", sender, detail)
    else
        addon.Log:D("Comms", "refused", reason, subject, "from", sender)
    end
end



local function KnownCommand(command)
    if type(command) ~= "string" or #command > MAX_COMMAND then return nil end
    if command == BATCH or handlers[command] then return command end
    return nil
end


local function Shape(command)
    if type(command) == "string" then return #command end
    return type(command)
end







function Comms:LegacyAnnounce(version)
    if type(version) ~= "string" or version == "" then return false end
    local channel = GroupChannel()
    if not channel then return false end
    if addon.Restrictions:IsBlocked() then
        Stats.Dropped("blocked", "legacy", 0)
        droppedWhileBlocked.legacy = true
        return false
    end
    local encoded = LegacyEncode("version", { v = version })
    if not encoded or 1 + #encoded > LEGACY_MAX_PAYLOAD then
        addon.Log:E("Comms", "legacy version frame did not encode", version)
        return false
    end
    addon.Log:D("Comms", "queued legacy version", channel, version)
    Enqueue(lanes[PRESENCE], "S" .. encoded, channel, nil, "legacy", nil, LEGACY_PREFIX)
    Pump()
    return true
end



local legacyIgnored = NewSet()


local function IsCurrentFormat(version)
    local major, minor = version:match("^(%d*)%.?(%d*)")
    major, minor = tonumber(major) or 0, tonumber(minor) or 0
    return major > 0 or minor >= FIRST_CURRENT_MINOR
end



local function OnLegacy(body, sender)
    Stats.Received("legacy", 1, #body)
    if sender == addon.Player:GetFullName("player") then return end
    if byte(body, 1) == KIND_SINGLE then
        local message = LegacyDecode(sub(body, 2))
        local args = message and message.c == "version" and message.a
        if type(args) == "table" and type(args.v) == "string" and #args.v <= MAX_COMMAND then
            if IsCurrentFormat(args.v) then return end
            addon.Log:D("Comms", "legacy peer", sender, args.v)
            Stats.Dispatched("legacy")
            addon.Callbacks:Fire("LegacyPeer", sender, args.v)
            return
        end
    end
    if FirstTime(legacyIgnored, sender) then
        addon.Log:D("Comms", "ignoring 0.40-format traffic from", sender)
    end
end










function Comms:Register(command, authority, handler)
    handlers[command] = { authority = authority, handler = handler }
end

local function IsAuthorised(authority, sender)
    if authority == "any" then return true end
    if authority == "ml" then
        return addon.IsMasterLooter and addon.IsMasterLooter(sender) or false
    end
    if authority == "council" then
        return addon.Council and addon.Council:Contains(sender) or false
    end
    return false
end



local function ApplyOne(command, args, sender)
    local entry = handlers[command]
    if not entry then
        addon.Log:D("Comms", "no handler for", command)
        return
    end

    if not IsAuthorised(entry.authority, sender) then
        Stats.Refused("unauthorised")
        addon.Log:WLogOnly("Comms", "rejected unauthorised", command, "from", sender)
        return
    end


    addon.Log:D("Comms", "recv", command, "from", sender)


    if runScoped[command] then
        local stamped = type(args) == "table" and args.i or nil
        local current = CurrentRunId()
        if Comms.IsStale(stamped, current) then
            addon.Log:I("Comms", "stale", command, "for run", stamped,
                "- current run is", current)
            return
        end
    end

    Stats.Dispatched(command)
    local ok, err = pcall(entry.handler, args, sender)
    if not ok then
        addon.Log:Bug("Comms", ("handler %s failed: %s"):format(command, tostring(err)))
    end
end


local function Apply(command, args, sender)
    addon.Log:Hold()
    ApplyOne(command, args, sender)
    addon.Log:Release()
end



local function ApplyBatch(args, sender)
    local list = type(args) == "table" and args.l
    if type(list) ~= "table" then
        addon.Log:WLogOnly("Comms", "malformed batch from", sender)
        return
    end
    addon.Log:Hold()
    addon.Log:D("Comms", "recv batch from", sender, #list, "entries")
    Stats.Dispatched(BATCH)
    for _, inner in ipairs(list) do
        local raw = type(inner) == "table" and inner.c or nil
        local command = KnownCommand(raw)
        if BATCHABLE[command] then
            Apply(command, inner.a, sender)
        else
            Stats.Refused("unbatchable")
            if FirstTime(refusalLogged, "unbatchable|" .. tostring(sender)) then
                addon.Log:WLogOnly("Comms", "refused unbatchable", command or Shape(raw),
                    "in a batch from", sender)
            end
        end
    end
    addon.Log:Release()
end





local ArmSweep

local function Dispatch(escaped, sender, frames, bytes, member)
    if not member then
        local now = GetTime()
        local heard = outsiderHeard[sender]

        if now - (heard or -OUTSIDER_WINDOW) < OUTSIDER_WINDOW
            or not heard and outsiderCount >= MAX_REMEMBERED then
            Refuse("flood", "message", sender)
            return
        end
        if not heard then outsiderCount = outsiderCount + 1 end
        outsiderHeard[sender] = now
        ArmSweep()
    end
    local message = Decode(escaped, member and MAX_INFLATED or OUTSIDER_MAX_INFLATED, sender)
    local command = message and KnownCommand(message.c)
    Stats.Received(command, frames, bytes)
    if not message then return end
    if not command then
        Refuse("command", "unknown", sender, Shape(message.c))
        return
    end
    if not member and not FROM_OUTSIDE[command] then
        Refuse("outsider", command, sender)
        return
    end
    if command == BATCH then
        ApplyBatch(message.a, sender)
        return
    end
    Apply(command, message.a, sender)
end


local function DropPartial(key, buffer)
    pending[key] = nil
    local left = (partialsOf[buffer.sender] or 1) - 1
    partialsOf[buffer.sender] = left > 0 and left or nil
end

local function OnMessage(prefix, body, sender, channel)

    local member = IsMember(sender)
    if not member and (channel ~= "WHISPER" or not outsiderPrefix[prefix]) then
        Refuse("outsider", prefix, sender)
        return
    end

    local kind = byte(body, 1)

    if kind == KIND_SINGLE then
        Dispatch(sub(body, 2), sender, 1, #body, member)
        return
    end

    if kind ~= KIND_CHUNK then
        addon.Log:WLogOnly("Comms", "unknown frame type from", sender)
        Stats.Received(nil, 1, #body)
        return
    end

    if #body < 5 then
        addon.Log:WLogOnly("Comms", "malformed chunk from", sender)
        Stats.Received(nil, 1, #body)
        return
    end
    local id, seq, total = byte(body, 2, 4)
    id, seq, total = id - 1, seq - 1, total - 1



    if total < 1 or total > MAX_CHUNKS or seq < 1 or seq > total then
        addon.Log:WLogOnly("Comms", "invalid chunk", seq .. "/" .. total, "from", sender)
        Stats.Received(nil, 1, #body)
        return
    end


    if not member and total > OUTSIDER_MAX_CHUNKS then
        Refuse("outsider", "chunks", sender, total)
        return
    end
    if member and total > laneByPrefix[prefix].maxChunks then
        Refuse("chunks", prefix, sender, total)
        return
    end


    local key = sender .. "|" .. prefix .. "|" .. id
    local buffer = pending[key]
    local now = GetTime()




    if buffer and (now - buffer.at > INCOMPLETE_TTL
        or buffer.total ~= total or buffer.parts[seq]) then
        addon.Log:WLogOnly("Comms", "discarding superseded partial message", key,
            ("%d/%d chunks"):format(buffer.count, buffer.total))
        Stats.Received(nil, buffer.count, buffer.bytes)
        DropPartial(key, buffer)
        buffer = nil
    end

    if not buffer then
        local open = partialsOf[sender] or 0
        if open >= (member and MAX_PARTIALS or OUTSIDER_MAX_PARTIALS) then
            Refuse("partials", prefix, sender, open)
            return
        end
        buffer = { parts = {}, count = 0, total = total, bytes = 0, sender = sender }
        pending[key] = buffer
        partialsOf[sender] = open + 1
        ArmSweep()
    end


    buffer.parts[seq] = sub(body, 5)
    buffer.count = buffer.count + 1
    buffer.bytes = buffer.bytes + #body

    buffer.at = now

    if buffer.count == buffer.total then
        DropPartial(key, buffer)
        Dispatch(table.concat(buffer.parts), sender, buffer.count, buffer.bytes, member)
    end
end



local sweepTicker

local function Sweep()
    local now = GetTime()
    for key, buffer in pairs(pending) do
        if now - buffer.at > INCOMPLETE_TTL then
            addon.Log:WLogOnly("Comms", "discarding incomplete message", key,
                ("%d/%d chunks"):format(buffer.count, buffer.total))
            Stats.Received(nil, buffer.count, buffer.bytes)
            DropPartial(key, buffer)
        end
    end
    for sender, at in pairs(outsiderHeard) do
        if now - at >= OUTSIDER_WINDOW then
            outsiderHeard[sender] = nil
            outsiderCount = outsiderCount - 1
        end
    end
    if not next(pending) and outsiderCount == 0 and sweepTicker then
        sweepTicker:Cancel()
        sweepTicker = nil
    end
end

function ArmSweep()
    if not sweepTicker then sweepTicker = C_Timer.NewTicker(INCOMPLETE_TTL, Sweep) end
end


local function Receive(prefix, text, channel, sender)
    if not CHANNELS[channel] then
        Refuse("channel", channel, sender)
        return
    end
    if laneByPrefix[prefix] then
        OnMessage(prefix, text, sender, channel)
    elseif IsMember(sender) then
        OnLegacy(text, sender)
    else
        Refuse("outsider", prefix, sender)
    end
end





local function RegisterPrefix(prefix)
    local result = C_ChatInfo.RegisterAddonMessagePrefix(prefix)


    if result ~= Enum.RegisterAddonMessagePrefixResult.Success
        and result ~= Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix then
        addon.Log:E("Comms", "prefix registration failed", prefix, result)
    end
end

function Comms:Init()
    statSince = GetTime()
    for _, lane in ipairs(lanes) do RegisterPrefix(lane.prefix) end
    RegisterPrefix(LEGACY_PREFIX)

    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
        if event == "PLAYER_LOGOUT" then

            FlushBatch()
            return
        end
        if not laneByPrefix[prefix] and prefix ~= LEGACY_PREFIX then return end

        if addon.IsForever then sender = addon.Player:FromChat(sender) end
        local ok, err = pcall(Receive, prefix, text, channel, sender)
        if not ok then addon.Log:Bug("Comms", tostring(err)) end
    end)


    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", function()
        if GetTime() < wakeAt then return end
        Pump()
    end)

    Pump()


    addon.Restrictions:OnChange(function(isBlocked)
        if isBlocked then return end
        for _, lane in ipairs(lanes) do
            if lane.queue[1] and lane.queue[1].lockdowns then lane.pausedUntil = 0 end
        end
        Pump()
        C_Timer.After(RESUME_DELAY, Resume)
    end)

    addon.Log:I("Comms", "ready", "lanes", "SLCc SLCb SLCp", "legacy", LEGACY_PREFIX,
        "frame", FRAME_MAX)
end
