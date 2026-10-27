if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Snapshot = {}
addon.Snapshot = Snapshot



local function Str(value) return type(value) == "string" and value or nil end
local function Num(value) return type(value) == "number" and value == value and value or nil end


local FORMAT = 2
Snapshot.FORMAT = FORMAT

local function Byte(x) return math.max(0, math.min(255, math.floor(x * 255 + 0.5))) end


local function Hex(r, g, b)
    r, g, b = Num(r), Num(g), Num(b)
    if not (r and g and b) then return nil end
    return string.format("%02x%02x%02x", Byte(r), Byte(g), Byte(b))
end
Snapshot.Hex = Hex

local function FromHex(hex)
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x$") then return nil end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255
end







local function BuildCandidate(candidate, resolveResponse, awardedWinner, responses)
    local responseText, responseID, r, g, b, responseCode =
        resolveResponse(candidate, awardedWinner)
    local status = awardedWinner and responseCode == "PASS" and "PASS"
        or candidate.realStatus or candidate.status

    local row = {
        responseCode = responseCode,
        responseID = responseID,
        status = status ~= "RESPONDED" and status or nil,
        roll = candidate.roll,
        rollBy = candidate.rollBy,
        diff = candidate.diff,
        viaWhisper = candidate.viaWhisper or nil,
    }
    if responseID then
        responses[responseID] = responses[responseID] or { text = responseText, color = Hex(r, g, b) }
    else

        row.response = responseText
        row.color = Hex(r, g, b)
    end
    return row
end




function Snapshot.Build(item, session, winner, resolveResponse)
    if type(item) ~= "table" or type(item.candidates) ~= "table" then return nil end

    local candidates, responses, count = {}, {}, 0
    for name, candidate in pairs(item.candidates) do
        candidates[name] = BuildCandidate(candidate, resolveResponse, name == winner, responses)
        count = count + 1
    end

    return {
        v = FORMAT,
        winner = winner,
        count = count,
        candidates = candidates,
        responses = responses,
    }
end


local ROW_ONLY = { "link", "boss", "encounterID", "owner", "reasonText", "session" }
function Snapshot.Compact(snapshot)
    if type(snapshot) ~= "table" or snapshot.v == FORMAT then return false end
    for _, field in ipairs(ROW_ONLY) do snapshot[field] = nil end

    local responses = type(snapshot.responses) == "table" and snapshot.responses or {}
    for _, candidate in pairs(type(snapshot.candidates) == "table" and snapshot.candidates or {}) do
        if type(candidate) == "table" then
            candidate.votes, candidate.voters = nil, nil
            if candidate.status == "RESPONDED" then candidate.status = nil end
            local color = Hex(candidate.r, candidate.g, candidate.b)
            candidate.r, candidate.g, candidate.b = nil, nil, nil

            local id, text = Num(candidate.responseID), Str(candidate.response)
            local shared = id and responses[id]
            if id and text and not shared then
                responses[id] = { text = text, color = color }
                candidate.response = nil
            elseif shared and shared.text == text and shared.color == color then
                candidate.response = nil
            else
                candidate.color = color
            end
        end
    end
    snapshot.responses = responses
    snapshot.v = FORMAT
    return true
end


function Snapshot.Answer(snapshot, candidate)
    local id = Num(candidate.responseID)
    local shared = id and type(snapshot.responses) == "table" and snapshot.responses[id]
    shared = type(shared) == "table" and shared or nil

    local code = Str(candidate.responseCode)
    local text = shared and Str(shared.text) or Str(candidate.response)
        or (code and addon.History.CodeText(code))
    local r, g, b = FromHex(shared and shared.color or candidate.color)
    if not r then r, g, b = Num(candidate.r), Num(candidate.g), Num(candidate.b) end
    return text, r, g, b
end







function Snapshot.Compare(a, b, winner)
    if a.name == winner or b.name == winner then
        return a.name == winner
    end

    local ai = Num(a.candidate.responseID) or math.huge
    local bi = Num(b.candidate.responseID) or math.huge
    if ai ~= bi then return ai < bi end

    return a.name < b.name
end



function Snapshot.Ordered(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.candidates) ~= "table" then return {} end

    local list = {}
    for name, candidate in pairs(snapshot.candidates) do
        if type(name) == "string" and type(candidate) == "table" then
            list[#list + 1] = { name = name, candidate = candidate }
        end
    end
    table.sort(list, function(a, b) return Snapshot.Compare(a, b, snapshot.winner) end)
    return list
end







local function Key(runId, session)
    if not runId or not session then return nil end
    return tostring(runId) .. ":" .. tostring(session)
end
Snapshot.Key = Key



local function PackedParts(value)
    if type(value) ~= "string" then return nil end
    local epoch, blob = value:match("^z(%d+):(.+)$")
    return tonumber(epoch), blob
end


local function PackSnapshot(snapshot)
    local epoch = type(snapshot) == "table" and Num(snapshot.epoch)
    if not epoch or epoch < 0 or epoch ~= math.floor(epoch) then return nil end
    local blob = addon.History and addon.History.PackValue and addon.History.PackValue(snapshot)
    return blob and ("z%d:%s"):format(epoch, blob) or nil
end
Snapshot.PackSnapshot = PackSnapshot


local cachedValue, cachedSnapshot


local function Stored(value)
    if type(value) == "table" then return value end
    if type(value) ~= "string" then return nil end
    if value ~= cachedValue then
        local _, blob = PackedParts(value)
        local snapshot = blob and addon.History.UnpackValue and addon.History.UnpackValue(blob)
        cachedValue, cachedSnapshot = value, type(snapshot) == "table" and snapshot or nil
    end
    return cachedSnapshot
end



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
    addon.db.historySnapshots[key] = PackSnapshot(built) or built
    addon.Log:D("Snapshot", "captured", item.link, "session", session,
        "run", runId, built.count, "candidate(s)")
end


function Snapshot:For(entry)
    if not entry or not entry.runId or not entry.session then return nil end
    local key = Key(entry.runId, entry.session)
    return key and addon.db and addon.db.historySnapshots
        and Stored(addon.db.historySnapshots[key]) or nil
end


function Snapshot:RemoveForSession(session, runId)
    local key = Key(runId, session)
    if key and addon.db and addon.db.historySnapshots then
        addon.db.historySnapshots[key] = nil
    end
end



local KEEP_DAYS = 60
Snapshot.KEEP_DAYS = KEEP_DAYS


local function AgeEpoch(snapshot, rowEpoch)
    local epoch = type(snapshot) == "table" and snapshot.epoch or PackedParts(snapshot)
    if type(epoch) == "number" then return epoch end
    if type(rowEpoch) == "number" and rowEpoch > 0 then return rowEpoch end
    return nil
end




function Snapshot:Prune(live, login)
    if not addon.db or not addon.db.historySnapshots then return 0 end

    if not live then
        live = {}

        addon.History.EachSnapKey(function(key, epoch)
            live[key] = math.max(live[key] or 0, epoch)
        end)
    end

    local cutoff = GetServerTime() - KEEP_DAYS * 24 * 60 * 60
    local orphans, aged, compacted = 0, 0, 0
    local unpacked = {}
    for key, snapshot in pairs(addon.db.historySnapshots) do
        if not live[key] then
            addon.db.historySnapshots[key] = nil
            orphans = orphans + 1
        else
            local epoch = AgeEpoch(snapshot, live[key])
            if epoch and epoch < cutoff then
                addon.db.historySnapshots[key] = nil
                aged = aged + 1
            elseif login and type(snapshot) == "table" then

                if Snapshot.Compact(snapshot) then compacted = compacted + 1 end
                unpacked[#unpacked + 1] = key
            end
        end
    end
    if orphans + aged > 0 then
        addon.Log:D("Snapshot", "pruned", orphans, "orphaned and", aged,
            "snapshot(s) older than", KEEP_DAYS, "days")
    end
    if compacted > 0 then
        addon.Log:I("Snapshot", "compacted", compacted, "older snapshot(s)")
    end
    if login then
        Snapshot:LogReady()
        if #unpacked > 0 then Snapshot:StartPacking(unpacked) end
    end
    return orphans + aged
end


local PACK_BUDGET = 20
Snapshot.PACK_BUDGET = PACK_BUDGET
local packQueue, packAt, packDone = nil, 1, 0


function Snapshot:PackStep(budget)
    local store = addon.db and addon.db.historySnapshots
    if not packQueue or type(store) ~= "table" then
        packQueue = nil
        return false
    end
    local stop = math.min(#packQueue, packAt + budget - 1)
    for i = packAt, stop do
        local key = packQueue[i]
        local packed = type(store[key]) == "table" and PackSnapshot(store[key])
        if packed then
            store[key] = packed
            packDone = packDone + 1
        end
    end
    packAt = stop + 1
    if packAt <= #packQueue then return true end
    addon.Log:I("Snapshot", "packed", packDone, "of", #packQueue, "council snapshot(s)")
    packQueue = nil
    return false
end


function Snapshot:StartPacking(keys)
    packQueue, packAt, packDone = keys, 1, 0
    if not CreateFrame then return end
    local driver = Snapshot.packDriver or CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(self)
        if not Snapshot:PackStep(PACK_BUDGET) then self:SetScript("OnUpdate", nil) end
    end)
    Snapshot.packDriver = driver
end






local function EstimateBytes(candidate)
    if type(candidate) ~= "table" then return 0 end
    local n = 40
    for _, field in ipairs({ "response", "note", "gear1", "gear2" }) do
        local text = Str(candidate[field])
        if text then n = n + #text end
    end
    return n
end

local function EstimateSnapshotBytes(snapshot)
    local n = 80
    local candidates = type(snapshot) == "table" and snapshot.candidates
    for _, candidate in pairs(type(candidates) == "table" and candidates or {}) do
        n = n + EstimateBytes(candidate)
    end
    return n
end

local MAX_LINES = 8


local function CandidateLine(snapshot, name, candidate)
    local S = addon.Style
    local text = name



    local response, r, g, b = Snapshot.Answer(snapshot, candidate)
    if response then
        if r and g and b then
            text = text .. "  " .. S.Colorize({ r, g, b }, response)
        else
            text = text .. "  " ..
                S.Colorize(S.Flatten(S.color.textMuted), response)
        end
    end

    local roll = Num(candidate.roll)
    if roll then
        roll = math.floor(roll)
        local rollText = candidate.rollBy == "leader"
            and addon.Locale.Format(T["roll %d (assigned)"], roll)
            or addon.Locale.Format(T["roll %d"], roll)
        text = text .. "  " .. S.Colorize(S.Flatten(S.color.textFaint), rollText)
    end

    local diff = Num(candidate.diff)
    if diff then
        diff = math.floor(diff)
        local diffText = addon.Locale.Format(T["%+d ilvl"], diff)
        local diffColor = diff > 0 and S.color.good
            or (diff < 0 and S.color.textMuted or S.color.textFaint)
        text = text .. "  " .. S.Colorize(S.Flatten(diffColor), diffText)
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
        tooltip:AddLine(CandidateLine(snapshot, row.name, row.candidate))
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
        if not addon.PlayerIsMasterLooter() then
            local me = addon.Player and addon.Player:GetFullName("player")
            if not (me and addon.Council and addon.Council:Contains(me)) then return end
        end
        Snapshot:Capture(session, winner, item)
    end)

    addon.Callbacks:Register("ItemUnawarded", function(session, previous, item, runId)
        if item and item.simulated then return end
        Snapshot:RemoveForSession(session, runId or addon.Session:GetRunId())
    end)


end


function Snapshot:LogReady()
    local n, packed, candidates, bytes = 0, 0, 0, 0
    for _, snapshot in pairs(addon.db.historySnapshots or {}) do
        n = n + 1
        if type(snapshot) == "string" then
            packed, bytes = packed + 1, bytes + #snapshot
        else
            candidates = candidates + (Num(type(snapshot) == "table" and snapshot.count) or 0)
            bytes = bytes + EstimateSnapshotBytes(snapshot)
        end
    end
    addon.Log:I("Snapshot", "ready,", n, "council snapshot(s),", packed, "packed,", candidates,
        "candidate record(s) unpacked, ~", math.floor(bytes / 1024 + 0.5) .. "KB")
end
