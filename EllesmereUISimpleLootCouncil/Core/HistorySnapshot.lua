if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Snapshot = {}
addon.Snapshot = Snapshot






local function CopyVoters(voters)
    local names = {}
    for name in pairs(voters or {}) do names[#names + 1] = name end
    table.sort(names)
    return names
end



local function BuildCandidate(candidate, resolveResponse, awardedWinner)
    local responseText, responseID, r, g, b, responseCode =
        resolveResponse(candidate, awardedWinner)

    return {

        response = responseText,
        responseCode = responseCode,
        responseID = responseID,
        r = r, g = g, b = b,
        status = awardedWinner and responseCode == "PASS" and "PASS"
            or candidate.realStatus or candidate.status,
        note = candidate.note,
        roll = candidate.roll,
        rollBy = candidate.rollBy,
        diff = candidate.diff,
        ilvl = candidate.ilvl,
        gear1 = candidate.gear1,
        gear2 = candidate.gear2,
        viaWhisper = candidate.viaWhisper or nil,
        votes = CopyVoters(candidate.voters),
    }
end



function Snapshot.Build(item, session, winner, resolveResponse)
    if type(item) ~= "table" or type(item.candidates) ~= "table" then return nil end

    local candidates, count = {}, 0
    for name, candidate in pairs(item.candidates) do
        candidates[name] = BuildCandidate(candidate, resolveResponse, name == winner)
        count = count + 1
    end

    return {
        link = item.link,
        boss = item.boss,
        encounterID = item.encounterID,
        owner = item.owner,
        reasonText = item.reasonText,
        winner = winner,
        session = session,
        count = count,
        candidates = candidates,
    }
end







function Snapshot.Compare(a, b, winner)
    if a.name == winner or b.name == winner then
        return a.name == winner
    end

    local ai = a.candidate.responseID or math.huge
    local bi = b.candidate.responseID or math.huge
    if ai ~= bi then return ai < bi end

    local av, bv = #(a.candidate.votes or {}), #(b.candidate.votes or {})
    if av ~= bv then return av > bv end

    return a.name < b.name
end



function Snapshot.Ordered(snapshot)
    if not snapshot or type(snapshot.candidates) ~= "table" then return {} end

    local list = {}
    for name, candidate in pairs(snapshot.candidates) do
        list[#list + 1] = { name = name, candidate = candidate }
    end
    table.sort(list, function(a, b) return Snapshot.Compare(a, b, snapshot.winner) end)
    return list
end







local function Key(runId, session)
    if not runId or not session then return nil end
    return tostring(runId) .. ":" .. tostring(session)
end
Snapshot.Key = Key



function Snapshot:Capture(session, winner, item)
    if not addon.db then return end

    local runId = addon.Session and addon.Session:GetRunId()
    local key = Key(runId, session)
    if not key then return end

    local built = Snapshot.Build(item, session, winner, function(candidate, awardedWinner)
        return addon.History.ResolveCandidateResponse(candidate,
            function(index) return addon.Config:Responses()[index] end, awardedWinner)
    end)
    if not built then return end

    built.runId = runId
    built.epoch = GetServerTime()

    addon.db.historySnapshots = addon.db.historySnapshots or {}
    addon.db.historySnapshots[key] = built
    addon.Log:D("Snapshot", "captured", item.link, "session", session,
        "run", runId, built.count, "candidate(s)")
end


function Snapshot:For(entry)
    if not entry or not entry.runId or not entry.session then return nil end
    local key = Key(entry.runId, entry.session)
    return key and addon.db and addon.db.historySnapshots
        and addon.db.historySnapshots[key]
end


function Snapshot:RemoveForSession(session, runId)
    local key = Key(runId, session)
    if key and addon.db and addon.db.historySnapshots then
        addon.db.historySnapshots[key] = nil
    end
end



function Snapshot:Prune()
    if not addon.db or not addon.db.historySnapshots then return 0 end

    local live = {}
    addon.History.EachEntry(function(entry)
        local key = Key(entry.runId, entry.session)
        if key then live[key] = true end
    end)

    local removed = 0
    for key in pairs(addon.db.historySnapshots) do
        if not live[key] then
            addon.db.historySnapshots[key] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then
        addon.Log:D("Snapshot", "pruned", removed, "orphaned snapshot(s)")
    end
    return removed
end






local function EstimateBytes(candidate)
    local n = 40
    if candidate.response then n = n + #candidate.response end
    if candidate.note then n = n + #candidate.note end
    if candidate.gear1 then n = n + #candidate.gear1 end
    if candidate.gear2 then n = n + #candidate.gear2 end
    for _, voter in ipairs(candidate.votes or {}) do n = n + #voter end
    return n
end

local function EstimateSnapshotBytes(snapshot)
    local n = 80
    for _, candidate in pairs(snapshot.candidates or {}) do
        n = n + EstimateBytes(candidate)
    end
    return n
end

local MAX_LINES = 8


local function CandidateLine(name, candidate)
    local S = addon.Style
    local text = name



    local response = candidate.response
        or (candidate.responseCode and addon.History.CodeText(candidate.responseCode))
    if response then
        if candidate.r then
            text = text .. "  " .. S.Colorize(
                { candidate.r, candidate.g, candidate.b }, response)
        else
            text = text .. "  " ..
                S.Colorize(S.Flatten(S.color.textMuted), response)
        end
    end

    if candidate.roll then
        local rollText = candidate.rollBy == "leader"
            and addon.Locale.Format(T["roll %d (assigned)"], candidate.roll)
            or addon.Locale.Format(T["roll %d"], candidate.roll)
        text = text .. "  " .. S.Colorize(S.Flatten(S.color.textFaint), rollText)
    end

    if candidate.diff then
        local diffText = addon.Locale.Format(T["%+d ilvl"], candidate.diff)
        local diffColor = candidate.diff > 0 and S.color.good
            or (candidate.diff < 0 and S.color.textMuted or S.color.textFaint)
        text = text .. "  " .. S.Colorize(S.Flatten(diffColor), diffText)
    end

    local votes = #(candidate.votes or {})
    if votes > 0 then
        text = text .. "  " .. S.Colorize(S.Flatten(S.color.textFaint),
            addon.Locale.Format(addon.Locale.Plural{ one = "%d vote", other = "%d votes" },
                votes, votes))
    end

    return text
end



function Snapshot:AddTooltipLines(tooltip, entry, full)
    local snapshot = self:For(entry)
    if not snapshot then return end

    local S = addon.Style
    local ordered = Snapshot.Ordered(snapshot)
    if #ordered == 0 then return end

    S.TooltipSection(tooltip, T["Council Snapshot"])

    local shown = full and #ordered or math.min(#ordered, MAX_LINES)
    for i = 1, shown do
        local row = ordered[i]
        tooltip:AddLine(CandidateLine(row.name, row.candidate))
    end

    if not full and #ordered > MAX_LINES then
        tooltip:AddLine(addon.Locale.Format(T["... and %d more (hold Shift)"], #ordered - MAX_LINES),
            S.Unpack(S.color.textFaint))
    end
end





function Snapshot:Init()
    addon.db.historySnapshots = addon.db.historySnapshots or {}



    addon.Callbacks:Register("ItemAwarded", function(session, winner, item)
        if item and item.simulated then return end
        Snapshot:Capture(session, winner, item)
    end)

    addon.Callbacks:Register("ItemUnawarded", function(session, previous, item, runId)
        if item and item.simulated then return end
        Snapshot:RemoveForSession(session, runId or addon.Session:GetRunId())
    end)


    Snapshot:Prune()

    local n, candidates, bytes = 0, 0, 0
    for _, snapshot in pairs(addon.db.historySnapshots) do
        n = n + 1
        candidates = candidates + (snapshot.count or 0)
        bytes = bytes + EstimateSnapshotBytes(snapshot)
    end
    addon.Log:I("Snapshot", "ready,", n, "council snapshot(s),", candidates,
        "candidate record(s), ~", math.floor(bytes / 1024 + 0.5) .. "KB")
end
