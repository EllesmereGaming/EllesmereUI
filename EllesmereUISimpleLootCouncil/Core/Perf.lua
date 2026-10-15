if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 





local ADDON_NAME = ...

SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Perf = {}
addon.Perf = Perf

local function Print(msg)
    print(addon.Log.CHAT_PREFIX.accent .. msg)
end






local SELF = ADDON_NAME or "SimpleLootCouncil"
local KEEP_RUNS = 20

local FRAME_BUDGET_MS = 1000 / 60


local COUNTERS = {
    { "over1", "CountTimeOver1Ms" },
    { "over5", "CountTimeOver5Ms" },
    { "over10", "CountTimeOver10Ms" },
    { "over50", "CountTimeOver50Ms" },
}

local recording

local function ProfilerOn()
    return C_AddOnProfiler and C_AddOnProfiler.IsEnabled
        and C_AddOnProfiler.IsEnabled() or false
end

local function Metric(name, key)
    return C_AddOnProfiler.GetAddOnMetric(name, Enum.AddOnProfilerMetric[key]) or 0
end

local function GroupSize()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    return math.max(1, n)
end

local function Counters(name)
    local out = {}
    for _, c in ipairs(COUNTERS) do out[c[1]] = Metric(name, c[2]) end
    return out
end



local function Sample()
    local r = recording
    if not r then return end
    local Kind = Enum.AddOnProfilerMetric
    for name, stats in pairs(r.addons) do
        local avg = Metric(name, "RecentAverageTime")
        local last = Metric(name, "LastTime")
        if avg > stats.avgMax then stats.avgMax = avg end
        if last > stats.lastMax then stats.lastMax = last end
    end
    local app = C_AddOnProfiler.GetApplicationMetric(Kind.RecentAverageTime) or 0
    local overall = C_AddOnProfiler.GetOverallMetric(Kind.RecentAverageTime) or 0
    if app > r.appAvgMax then r.appAvgMax = app end
    if overall > r.overallAvgMax then r.overallAvgMax = overall end
    local mine = Metric(SELF, "RecentAverageTime")
    local base = app - overall + mine
    if base > 0 and mine / base > r.shareMax then r.shareMax = mine / base end
    local group = GroupSize()
    if group > r.group then r.group = group end
    r.samples = r.samples + 1
end



local function CleanLabel(label)
    label = (label or ""):gsub("|", ""):gsub("%s+", "_"):sub(1, 32)
    return label ~= "" and label or "run"
end



function Perf:Start(label)
    if not ProfilerOn() then return false, "off" end
    if recording then return false, "recording" end

    recording = {
        label = CleanLabel(label),
        startedAt = GetTime(),
        group = GroupSize(),
        samples = 0,
        appAvgMax = 0, overallAvgMax = 0, shareMax = 0,
        addons = { [SELF] = { avgMax = 0, lastMax = 0, start = Counters(SELF) } },
    }
    Sample()
    recording.ticker = C_Timer.NewTicker(1, Sample)
    return true, recording.label
end

function Perf:IsRecording()
    return recording ~= nil, recording and recording.label
end



function Perf:Stop()
    local r = recording
    if not r then return nil end
    if r.ticker then r.ticker:Cancel() end
    Sample()
    recording = nil

    local record = {
        label = r.label,
        build = addon.VERSION,
        date = date and date("%Y-%m-%d %H:%M") or nil,
        seconds = GetTime() - r.startedAt,
        group = r.group,
        samples = r.samples,
        appAvgMax = r.appAvgMax,
        overallAvgMax = r.overallAvgMax,
        shareMax = r.shareMax,

        stress = r.stress,
        addons = {},
    }
    for name, stats in pairs(r.addons) do
        local now = Counters(name)
        local out = {
            avgMax = stats.avgMax,
            lastMax = stats.lastMax,

            peak = Metric(name, "PeakTime"),
        }
        for _, c in ipairs(COUNTERS) do
            out[c[1]] = now[c[1]] - stats.start[c[1]]
        end
        record.addons[name] = out
    end

    local db = addon.db
    if db then
        if type(db.perfRuns) ~= "table" then db.perfRuns = {} end
        db.perfRuns[#db.perfRuns + 1] = record
        while #db.perfRuns > KEEP_RUNS do table.remove(db.perfRuns, 1) end
    end
    return record
end

function Perf:Last()
    local runs = addon.db and addon.db.perfRuns
    return type(runs) == "table" and runs[#runs] or nil
end

local function AddonColumns(tag, stats)
    if not stats then return ("%s -"):format(tag) end
    return ("%s avg=%.3fms last=%.2fms >1/5/10/50=%d/%d/%d/%d"):format(tag,
        stats.avgMax, stats.lastMax, stats.over1, stats.over5, stats.over10,
        stats.over50)
end



function Perf.Summary(record)
    local line = ("%s  raid=%d  window=%.0fs  %s"):format(record.label,
        record.group or 1, record.seconds or 0,
        AddonColumns("SLC", record.addons[SELF]))

    local t = record.stress
    if t and t.events and t.events > 0 then
        line = line .. ("  timed=%.0fms %.2fms/event"):format(t.busy, t.busy / t.events)
        if t.paints then
            line = line .. (" paints=%d/%.0fms worst=%.1fms sum=%.0fms"):format(
                t.paints, t.paintMs, t.paintWorst, t.busy + t.paintMs)
        end
        line = line .. (" frame max=%.1fms over%.0fms=%d"):format(
            t.frameMax, FRAME_BUDGET_MS, t.overBudget)
    end
    return line
end



function Perf.Context(record)
    local mine = record.addons[SELF]
    return ("  v%s %s  app avg=%.2fms  all addons avg=%.3fms  SLC share max=%.1f%%  peak since game start: SLC %.1fms  samples=%d"):format(
        tostring(record.build), tostring(record.date or "?"),
        record.appAvgMax or 0, record.overallAvgMax or 0,
        (record.shareMax or 0) * 100, mine and mine.peak or 0,
        record.samples or 0)
end

local function PrintRecord(record)
    Print(Perf.Summary(record))
    Print(Perf.Context(record))
end

function Perf:PerfCommand(rest)
    local verb, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
    verb = (verb or ""):lower()

    if verb == "start" then
        local ok, why = Perf:Start(arg)
        if ok then
            Print(("perf recording %s - /slc perf stop to end it"):format(why))
        elseif why == "off" then
            Print("the client's addon profiler is off (C_AddOnProfiler.IsEnabled() is false) - nothing recorded")
        else
            Print(("already recording %s - /slc perf stop first"):format(
                tostring(select(2, Perf:IsRecording()))))
        end
    elseif verb == "stop" then
        local record = Perf:Stop()
        if record then
            PrintRecord(record)
        else
            Print("no perf recording is running - /slc perf start [label]")
        end
    elseif verb == "all" then
        local runs = addon.db and addon.db.perfRuns or {}
        if #runs == 0 then Print("no perf recordings yet") end
        for _, record in ipairs(runs) do Print(Perf.Summary(record)) end
    elseif verb == "" then
        local busy, label = Perf:IsRecording()
        if busy then
            Print(("recording %s for %.0fs - /slc perf stop to end it"):format(
                label, GetTime() - recording.startedAt))
        end
        local record = Perf:Last()
        if record then
            PrintRecord(record)
        elseif not busy then
            Print("no perf recordings yet - /slc perf start [label], then /slc perf stop")
        end
    else
        Print("usage: /slc perf [start [label]||stop||all]")
    end
end





local function Seconds(value)
    if not value then return "-" end
    if value < 1 then return ("%dms"):format(math.floor(value * 1000 + 0.5)) end
    return ("%.2fs"):format(value)
end


function Perf.CommsRows(report)
    local rows = {}
    for command, op in pairs(report.ops) do
        op.command = command
        rows[#rows + 1] = op
    end
    table.sort(rows, function(a, b)
        if a.sentBytes ~= b.sentBytes then return a.sentBytes > b.sentBytes end
        if a.receivedBytes ~= b.receivedBytes then
            return a.receivedBytes > b.receivedBytes
        end
        return a.command < b.command
    end)
    return rows
end



local LANE_ORDER = { "control", "bulk", "presence" }

function Perf.LaneLines(report)
    local lines = {}
    for _, name in ipairs(LANE_ORDER) do
        local lane = report.lanes and report.lanes[name]
        if lane then
            local latency = lane.latency or {}
            lines[#lines + 1] = ("  lane %-8s %-4s p95=%s p50=%s max=%s over %d frames  queue now=%d max=%d"):format(
                name, tostring(lane.prefix), Seconds(latency.p95), Seconds(latency.p50),
                Seconds(latency.max), latency.n or 0, lane.queueNow or 0, lane.queueMax or 0)
        end
    end
    lines[#lines + 1] = report.budget
        and ("  byte budget %d B"):format(report.budget)
        or "  byte budget -"
    return lines
end

function Perf:CommsCommand(rest)
    local Stats = addon.Comms and addon.Comms.Stats
    if not Stats then
        Print("comms counters are not available in this build")
        return
    end
    if (rest or ""):lower():match("^%s*reset%s*$") then
        Stats.Reset()
        Print("comms counters reset")
        return
    elseif (rest or ""):match("%S") then
        Print("usage: /slc comms [reset]")
        return
    end

    local report = Stats.Report()
    local rows = Perf.CommsRows(report)
    local window = math.max(GetTime() - (report.since or 0), 0.001)
    local sf, sb, rf, rb, ran = 0, 0, 0, 0, 0
    for _, row in ipairs(rows) do
        sf, sb = sf + row.sentFrames, sb + row.sentBytes
        rf, rb = rf + row.receivedFrames, rb + row.receivedBytes
        ran = ran + row.dispatched
    end
    local Result = Enum.SendAddonMessageResult
    local latency = report.latency

    Print(("comms over %.0fs: sent %d frames %d B (%.0f B/s)  received %d frames %d B  handled %d"):format(
        window, sf, sb, sb / window, rf, rb, ran))
    Print(("  queue now=%d max=%d  throttled addon=%d channel=%d  gave up=%d (%d frames)  failed=%d  blocked=%d"):format(
        report.queueNow, report.queueMax,
        report.throttle[Result.AddonMessageThrottle] or 0,
        report.throttle[Result.ChannelThrottle] or 0,
        report.dropped.gaveup or 0, report.droppedFrames.gaveup or 0,
        report.dropped.failed or 0, report.dropped.blocked or 0))
    Print(("  send delay over the last %d frames: p50=%s p95=%s max=%s"):format(
        latency.n, Seconds(latency.p50), Seconds(latency.p95), Seconds(latency.max)))
    for _, line in ipairs(Perf.LaneLines(report)) do Print(line) end
    for _, row in ipairs(rows) do
        Print(("  %-16s sent %4d f %7d B   recv %4d f %7d B   handled %4d"):format(
            row.command, row.sentFrames, row.sentBytes, row.receivedFrames,
            row.receivedBytes, row.dispatched))
    end
end







function Perf.StressName(index) return ("Stress%02d-Test"):format(index) end
function Perf.StressVoter(index) return ("StressVoter%d-Test"):format(index) end

function Perf.IsSynthetic(name)
    return type(name) == "string" and (name:match("^Stress%d%d%-Test$")
        or name:match("^StressVoter%d+%-Test$")) ~= nil
end

local NOTES = {
    "BiS for my raid spec",
    "Offspec only, 4-set piece",
    "Would replace a 10-level-lower crafted",
    "Tank set - low priority",
    "Trinket sim says +1.8%",
}




function Perf.PlanStress(opts)
    local rand = opts.random or math.random
    local raiders, items, seconds = opts.raiders, opts.items, opts.seconds
    local responses = math.max(1, opts.responses or 3)
    local council = opts.council or 5
    local autoNote = (addon.Autopass and addon.Autopass.AUTO_PREFIX or "auto: ")
        .. "armour"

    local events = {}
    local counts = { response = 0, autopass = 0, note = 0, vote = 0 }
    local function Add(event)
        event.seq = #events + 1
        events[#events + 1] = event
        counts[event.kind] = counts[event.kind] + 1
    end

    for s = 1, items do
        local answered = {}
        for r = 1, raiders do
            local name = Perf.StressName(r)
            local u = rand()
            local t = seconds * u * u

            local auto = (r * 3 + s * 5) % 7 == 0
            local note
            if not auto and (r + s) % 5 == 0 then


                note = NOTES[(r + s) % #NOTES + 1]
                Add({ t = t * 0.9, kind = "note", s = s, name = name, n = note })
            end
            Add({
                t = t, kind = "response", s = s, name = name,
                r = not auto and rand(1, responses) or nil,
                n = auto and autoNote or note,


                diff = (r * 7 + s) % 28 - 6, ilvl = 680 + (r + s) % 25,
                second = r % 4 == 0,
            })
            if auto then
                counts.autopass = counts.autopass + 1
            else
                answered[#answered + 1] = { name = name, t = t }
            end
        end


        for c = 1, council do
            if #answered > 0 then
                local voter = Perf.StressVoter(c)
                local pick = answered[rand(1, #answered)]
                local t = math.min(seconds,
                    math.max(pick.t + 1, seconds * (0.3 + 0.7 * rand())))
                Add({ t = t, kind = "vote", s = s, voter = voter,
                    candidate = pick.name, voted = true })
                if (c + s) % 2 == 0 and #answered > 1 then
                    local other = pick
                    while other == pick do other = answered[rand(1, #answered)] end
                    local later = math.min(seconds, t + 1 + 3 * rand())
                    Add({ t = later, kind = "vote", s = s, voter = voter,
                        candidate = pick.name, voted = false })
                    Add({ t = later, kind = "vote", s = s, voter = voter,
                        candidate = other.name, voted = true })
                end
            end
        end
    end

    table.sort(events, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.seq < b.seq
    end)
    counts.total = #events
    return events, counts
end

local stress


local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function() Perf:StressStep(GetTime()) end)


function Perf.StressTimingLine(t)
    if not t or not t.events or t.events == 0 then return nil end
    local paints = ""
    if t.paints then
        paints = ("; paints %d %.0fms, worst %.1fms; apply+paint %.0fms"):format(
            t.paints, t.paintMs, t.paintWorst, t.busy + t.paintMs)
    end
    return ("stress timed: SLC spent %.0fms in %d events (%.2fms each, worst %.1fms)%s; worst frame %.1fms, %d frames over %.1fms"):format(
        t.busy, t.events, t.busy / t.events, t.eventMax, paints, t.frameMax,
        t.overBudget, FRAME_BUDGET_MS)
end


local function CloseFrame(s)
    if s.frameAt == nil then return end
    local spent = s.frameSpent
    if spent > s.frameMax then s.frameMax = spent end
    if spent > FRAME_BUDGET_MS then s.overBudget = s.overBudget + 1 end
    s.frameAt, s.frameSpent = nil, 0
end

local function AddToFrame(s, now, ms)
    if s.frameAt ~= now then
        CloseFrame(s)
        s.frameAt, s.frameSpent = now, 0
    end
    s.frameSpent = s.frameSpent + ms
end


local function OnPaint(ms, now)
    if stress then AddToFrame(stress, now, ms) end
end



local function Scheduler()
    local C = addon.Callbacks
    return C and C.PaintStats and C.ResetPaintStats and C.SetPaintObserver and C or nil
end



local function StressGear(item, event)
    if not item or type(item.link) ~= "string" then return nil end
    return {
        g1 = item.link,
        g2 = event.second and item.link or nil,
        d = event.diff,
        il = event.ilvl,
        k1 = event.second and 1 or nil,
    }
end


local function ApplyEvent(event)
    local Session = addon.Session
    if event.kind == "response" then
        local item = Session:GetItems()[event.s]
        Session:ApplyResponse(event.s, event.name, event.r, event.n, event.name,
            StressGear(item, event))
    elseif event.kind == "note" then
        Session:ApplyNote(event.s, event.name, event.n, event.name)
    elseif event.kind == "vote" then
        Session:ApplyVote(event.s, event.candidate, event.voter, event.voted)
    end
end



local function StopDriver()
    driver:Hide()
    local s = stress
    stress = nil
    if not s then return end
    CloseFrame(s)
    local timing = {
        events = s.applied, busy = s.busy, eventMax = s.eventMax,
        frameMax = s.frameMax, overBudget = s.overBudget,
    }
    local C = Scheduler()
    if C then
        C.SetPaintObserver(nil)
        local paints = C.PaintStats()
        timing.paints, timing.paintMs = paints.paints, paints.ms
        timing.paintWorst = paints.worst
    end
    Perf.lastStress = timing
    if recording then recording.stress = timing end
    local line = Perf.StressTimingLine(timing)
    if line then Print(line) end
end


function Perf:StressStep(now)
    local s = stress
    if not s then return end
    local Session = addon.Session
    if not Session:IsRunning() or Session:GetRunId() ~= s.runId then
        Perf:StressStop("the run ended")
        return
    end
    local elapsed = now - s.startedAt
    local events = s.events
    local frameStart, ran = debugprofilestop(), 0
    while s.next <= #events and events[s.next].t <= elapsed do
        local eventStart = debugprofilestop()
        ApplyEvent(events[s.next])
        local spent = debugprofilestop() - eventStart
        s.busy = s.busy + spent
        if spent > s.eventMax then s.eventMax = spent end
        s.next = s.next + 1
        s.applied = s.applied + 1
        ran = ran + 1
    end
    if ran > 0 then AddToFrame(s, now, debugprofilestop() - frameStart) end
    if s.next > #events then

        s.doneAt = s.doneAt or now
        local C = Scheduler()
        if C and C.PaintPending and C:PaintPending() and now - s.doneAt < 1 then
            return
        end
        Print(("stress done: %d events in %.1fs - the synthetic candidates stay until /slc end"):format(
            s.applied, s.doneAt - s.startedAt))
        StopDriver()
    end
end

function Perf:StressStop(reason)
    local s = stress
    if not s then return false end
    Print(("stress stopped after %d of %d events (%s)"):format(
        s.applied, #s.events, reason or "stopped"))
    StopDriver()
    return true
end

function Perf:IsStressing()
    return stress ~= nil
end



function Perf.ScrubSynthetic(items)
    local removed = 0
    if type(items) ~= "table" then return removed end
    for _, item in pairs(items) do
        local candidates = type(item) == "table" and item.candidates
        if type(candidates) == "table" then
            for name, candidate in pairs(candidates) do
                if Perf.IsSynthetic(name) then
                    candidates[name] = nil
                    removed = removed + 1
                elseif type(candidate) == "table" and type(candidate.voters) == "table" then
                    for voter in pairs(candidate.voters) do
                        if Perf.IsSynthetic(voter) then
                            candidate.voters[voter] = nil
                            removed = removed + 1
                        end
                    end
                end
            end
        end
    end
    return removed
end



function Perf:StressStart(raiders, items, seconds)
    if stress then return false, "a stress is already running - /slc stress stop" end
    local Session = addon.Session
    local started = false

    if not Session:IsRunning() then
        local ok, why = Session:StartTest(nil, items)
        if not ok then
            return false, ("could not start a simulated run - %s"):format(tostring(why))
        end
        started = true
    end

    local runItems = Session:GetItems()
    for _, item in ipairs(runItems) do

        if not item.simulated then
            return false, "a real run is active - /slc stress only runs on a /slc test run"
        end
    end



    for _, item in ipairs(runItems) do
        for r = 1, raiders do
            local name = Perf.StressName(r)
            if not item.candidates[name] then
                item.candidates[name] = { status = "ANNOUNCED", voters = {} }
            end
        end
    end
    if addon.Callbacks then addon.Callbacks:Fire("SessionChanged") end

    local events, counts = Perf.PlanStress({
        raiders = raiders, items = #runItems, seconds = seconds,
        responses = addon.Config and #addon.Config:Responses() or 3,
    })
    stress = {
        events = events, counts = counts, next = 1, applied = 0,
        startedAt = GetTime(), runId = Session:GetRunId(),
        busy = 0, eventMax = 0, frameMax = 0, overBudget = 0,
        frameAt = nil, frameSpent = 0,
    }
    Perf.seededRun = stress.runId


    local C = Scheduler()
    if C then
        C.ResetPaintStats()
        C.SetPaintObserver(OnPaint)
    end
    driver:Show()
    return true, counts, #runItems, started
end

function Perf:StressCommand(rest)
    rest = (rest or ""):lower()
    if rest:match("^%s*stop%s*$") then
        if not Perf:StressStop("stopped by hand") then
            Print("no stress is running")
        end
        return
    end

    local a, b, c = rest:match("^%s*(%d*)%s*(%d*)%s*(%d*)%s*$")
    if not a then
        Print("usage: /slc stress [<raiders 1-40> [<items 1-32> [<seconds 1-600>]]] || stop")
        return
    end
    local raiders, items, seconds = tonumber(a) or 30, tonumber(b) or 12, tonumber(c) or 20
    local poolSize = addon.TestLoot and addon.TestLoot:Count() or 32
    if raiders < 1 or raiders > 40 or items < 1 or items > math.min(32, poolSize)
        or seconds < 1 or seconds > 600 then
        Print("usage: /slc stress [<raiders 1-40> [<items 1-32> [<seconds 1-600>]]] || stop")
        return
    end

    local ok, counts, itemCount, started = Perf:StressStart(raiders, items, seconds)
    if not ok then
        Print(counts)
        return
    end
    if started then
        Print(("started a simulated run with %d items for the stress (its run_start was sent as /slc test's is)"):format(
            itemCount))
    elseif itemCount ~= items then
        Print(("using the active run's %d items, not %d"):format(itemCount, items))
    end
    Print(("stress: %d raiders x %d items over %ds - %d responses (%d autopass), %d notes, %d votes; nothing is sent"):format(
        raiders, itemCount, seconds, counts.response, counts.autopass,
        counts.note, counts.vote))
end





function Perf:Init()


    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function()
        local saved = addon.db and addon.db.activeRun
        if Perf.seededRun and type(saved) == "table" then
            Perf.ScrubSynthetic(saved.items)
        end
    end)


    addon.Callbacks:Register("RunEnded", function()
        if stress then Perf:StressStop("the run ended") end
        if Perf.seededRun and addon.Session.run then
            Perf.ScrubSynthetic(addon.Session.run.completed)
            Perf.seededRun = nil
        end
    end)
end
