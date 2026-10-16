if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local History = {}
addon.History = History




local byWinner = {}
local byItem = {}

local indexState = "none"


local pending, pendingAt, liveKeys

local counter = 0



local function WinnerKey(winner)
    if type(winner) ~= "string" or winner == "" then return nil end
    if addon.Player and addon.Player.NameKey then
        local qualified = addon.Player.Qualify and addon.Player:Qualify(winner) or winner
        return addon.Player:NameKey(qualified) or winner
    end
    return winner
end


local function EpochOf(entry)
    local epoch = entry and entry.epoch
    return type(epoch) == "number" and epoch or 0
end
History.EpochOf = EpochOf







local function ItemKey(link)
    if type(link) ~= "string" then return nil end
    return link:match("|H(item:%d+)") or link:match("(item:%d+)") or link
end

local function Index(entry)
    if type(entry) ~= "table" then return end
    local winnerKey = WinnerKey(entry.winner)
    if winnerKey then
        byWinner[winnerKey] = byWinner[winnerKey] or {}
        table.insert(byWinner[winnerKey], entry)
    end
    local key = ItemKey(entry.link)
    if key then
        byItem[key] = byItem[key] or {}
        table.insert(byItem[key], entry)
    end
    if liveKeys and entry.runId and entry.session then
        local live = tostring(entry.runId) .. ":" .. tostring(entry.session)
        liveKeys[live] = math.max(liveKeys[live] or 0, EpochOf(entry))
    end
end




local function EachEntry(fn)
    for _, entry in pairs(addon.db.history or {}) do fn(entry) end
    for _, entry in pairs(addon.db.imported or {}) do fn(entry) end
end
History.EachEntry = EachEntry


local function IndexStep(budget)
    local last = math.min(#pending, pendingAt + budget - 1)
    for i = pendingAt, last do Index(pending[i]) end
    pendingAt = last + 1
    if pendingAt <= #pending then return false end
    pending, pendingAt, indexState = nil, nil, "ready"
    return true
end



function History:Reindex()
    byWinner, byItem = {}, {}
    pending, pendingAt = nil, nil
    if liveKeys then liveKeys = {} end
    EachEntry(Index)
    indexState = "ready"
end

local function Reindex()
    History:Reindex()
end


local function EnsureIndex()
    if indexState == "ready" then return end
    if indexState == "building" then IndexStep(math.huge) return end
    Reindex()
end











local function ResolveCandidateResponse(candidate, responseByIndex, awardedWinner)

    local boe = candidate and type(candidate.boe) == "table" and candidate.boe
    if boe and (candidate.realStatus or candidate.status) == "RESPONDED" then
        return boe.t, nil, boe.r, boe.g, boe.b, nil
    end
    local index = candidate and (candidate.realResponse or candidate.response)
    if index then
        local response = responseByIndex(index)
        if response then
            return response.text, index, response.r, response.g, response.b, nil
        end
    end
    local code = (candidate and (candidate.realStatus or candidate.status)) or "UNKNOWN"


    if awardedWinner and code == "ANNOUNCED" then code = "PASS" end
    return nil, nil, nil, nil, nil, code
end
History.ResolveCandidateResponse = ResolveCandidateResponse



local CODE_TEXT = addon.Locale.Texts{
    COIN      = T["Bonus roll"],
    UNKNOWN   = T["Unknown"],
    RESPONDED = T["Unknown"],
}



function History.CodeText(code)
    if code == nil then return nil end
    local status = addon.Session and addon.Session.STATUS
        and addon.Session.STATUS[code]
    return (status and status.text) or CODE_TEXT[code] or tostring(code)
end




function History.ResponseText(entry)
    if not entry then return nil end
    if entry.responseCode then return History.CodeText(entry.responseCode) end
    if entry.coin == true and not entry.responseID then
        return History.CodeText("COIN")
    end
    local text = entry.responseText
    local status = text and addon.Session and addon.Session.STATUS
        and addon.Session.STATUS[text]
    return (status and status.text) or text
end

local function BuildEntry(session, winner, item)
    counter = counter + 1

    local candidate = item.candidates and item.candidates[winner]

    local responseText, responseID, r, g, b, responseCode =
        ResolveCandidateResponse(candidate,
            function(index) return addon.Config:Responses()[index] end, true)

    local instanceName, instanceType, difficultyID, difficultyName = GetInstanceInfo()

    return {
        id = ("%d-%d"):format(GetServerTime(), counter),
        link = item.link,
        winner = winner,

        session = session,
        runId = addon.Session:GetRunId(),


        owner = item.owner,
        responseText = responseText,
        responseCode = responseCode,
        responseID = responseID,
        r = r, g = g, b = b,
        date = date("!%Y/%m/%d"),
        time = date("!%H:%M:%S"),
        epoch = GetServerTime(),
        instance = instanceName,
        instanceType = instanceType,
        difficultyID = difficultyID,
        difficultyName = difficultyName,

        boss = item.boss,
        encounterID = item.encounterID,
        note = candidate and candidate.note,
        votes = addon.Session:GetVoteCount(session, winner),
        groupSize = GetNumGroupMembers(),
        delivered = item.delivered and true or false,


        awardSeq = item.awardSeq,

        reason = item.reasonText,
    }
end



local struck = {}





local EARLY_MAX = 32
local EARLY_TTL = 300
local early = {}

local function RememberEarly(kind, session, winner, runId, seq)
    local now = GetTime()
    for i = #early, 1, -1 do
        if now - early[i].at > EARLY_TTL then table.remove(early, i) end
    end
    if #early >= EARLY_MAX then table.remove(early, 1) end
    early[#early + 1] = { kind = kind, session = session, winner = winner,
        runId = runId, seq = seq, at = now }
    addon.Log:D("History", "no row yet - remembering the", kind, "for", tostring(winner),
        "session", session)
end



local function ClaimEarly(entry)
    if #early == 0 or not entry.runId or not entry.session or not entry.winner then
        return false, false
    end
    local now = GetTime()
    local strike, delivered = false, false
    for i = #early, 1, -1 do
        local e = early[i]
        if now - e.at > EARLY_TTL then
            table.remove(early, i)
        elseif e.runId == entry.runId and e.session == entry.session
            and e.winner == entry.winner then
            if e.kind == "delivered" then
                delivered = true
                table.remove(early, i)
            elseif e.seq == nil or entry.awardSeq == nil or entry.awardSeq < e.seq then
                strike = true
                table.remove(early, i)
            end
        end
    end
    return strike, delivered
end



local ROW_FIELDS = {
    id = "string", link = "string", winner = "string", session = "number",
    runId = "string", owner = "string", responseText = "string",
    responseCode = "string", responseID = "number", r = "number", g = "number",
    b = "number", date = "string", time = "string", epoch = "number",
    instance = "string", instanceType = "string", difficultyID = "number",
    difficultyName = "string", boss = "string", encounterID = "number",
    note = "string", votes = "number", groupSize = "number", delivered = "boolean",
    awardSeq = "number", reason = "string", coin = "boolean", quantity = "number",
}
local MAX_TEXT, MAX_LONG = 255, 1024
local LONG_FIELDS = { link = true, note = true, reason = true, responseText = true }



function History.CleanRow(entry)
    if type(entry) ~= "table" then return nil, "not_a_table" end
    local id = entry.id
    if type(id) ~= "string" or #id > 64 or not id:match("^[%w%-:]+$") then
        return nil, "bad_id"
    end
    local link = entry.link
    if type(link) ~= "string" or not (link:match("|Hitem:%d+") or link:match("^item:%d+")) then
        return nil, "not_an_item"
    end
    if type(entry.winner) ~= "string" or entry.winner == "" then return nil, "no_winner" end
    local epoch = entry.epoch
    if type(epoch) ~= "number" or epoch ~= epoch or epoch < 0 or epoch == math.huge then
        return nil, "bad_epoch"
    end

    local row = {}
    for key, kind in pairs(ROW_FIELDS) do
        local value = entry[key]
        if type(value) == kind then
            if kind == "number" and value ~= value then value = nil end
            if kind == "string" and #value > (LONG_FIELDS[key] and MAX_LONG or MAX_TEXT) then
                value = nil
            end
            row[key] = value
        end
    end
    return row
end


local refusalLogged = {}
local function RefuseRow(reason, sender)
    local key = reason .. "|" .. tostring(sender)
    if refusalLogged[key] then return end
    refusalLogged[key] = true
    addon.Log:D("History", "refused a history row", reason, "from", tostring(sender))
end



local function Stamp(row)
    local player, raidTeam = addon.Player, addon.RaidTeam
    row.recorder = player and player.GetFullName and player:GetFullName("player") or nil
    row.guild = raidTeam and raidTeam.GetGuildName and raidTeam:GetGuildName() or nil
    if not row.guild and raidTeam and raidTeam.IsGuildPending and raidTeam:IsGuildPending() then
        addon.Log:D("History", "guild not readable yet - row left untagged", row.link)
    end
    return row
end


function History:Record(entry, sender)
    local clean, reason = History.CleanRow(entry)
    if not clean then
        RefuseRow(reason, sender)
        return
    end
    entry = clean
    addon.db.history = addon.db.history or {}

    if addon.db.history[entry.id] then


        return
    end
    if struck[entry.id] then
        addon.Log:I("History", "refusing a late copy of a struck row", entry.link,
            "to", tostring(entry.winner))
        return
    end

    local strike, delivered = ClaimEarly(entry)
    if strike then
        struck[entry.id] = true
        addon.Log:I("History", "refusing a row whose award was already undone", entry.link,
            "to", tostring(entry.winner))
        return
    end
    local row = Stamp(entry)
    if delivered and not row.delivered then
        row.delivered = true
        addon.Log:D("History", "row arrived after its delivery", entry.link,
            "to", tostring(entry.winner))
    end

    addon.db.history[entry.id] = row

    if indexState ~= "none" then Index(row) end
    addon.Log:D("History", "recorded", entry.link, "to", entry.winner)

    addon.Callbacks:Fire("HistoryChanged", "recorded", row)
end




function History:RecordCoin(name, link, epoch, boss, encounterID, quantity)
    if not addon.PlayerIsMasterLooter() then return end
    if type(name) ~= "string" or type(link) ~= "string" then return end
    epoch = math.floor(tonumber(epoch) or GetServerTime())
    encounterID = tonumber(encounterID)
    local difficultyID = addon.Encounter:DifficultyFor(boss, encounterID)

    if addon.BonusRoll and addon.BonusRoll.AlreadyRecorded(History:GetForWinner(name), name, link, boss,
            encounterID, difficultyID, epoch) then
        addon.Log:D("History", "coin already recorded", link, "for", name)
        return
    end
    counter = counter + 1

    local entry = {


        id = ("%d-%d"):format(epoch, counter),
        link = link,
        winner = name,
        coin = true,


        responseCode = "COIN",
        date = date("!%Y/%m/%d", epoch),
        time = date("!%H:%M:%S", epoch),
        epoch = epoch,
        instance = GetInstanceInfo(),

        difficultyID = difficultyID,
        boss = boss,
        encounterID = encounterID,

        delivered = true,
        quantity = quantity,
    }

    if addon.db.recordHistory then
        History:Record(entry)
    else
        addon.Log:I("History", "not recording coin", link,
            "- Record award history is off in your settings")
    end



    if addon.db.shareHistory then
        addon.Comms:Send("history", { e = entry }, nil, true)
    end
end




function History:RemoveForSession(session, winner, runId, seq)
    if not session or not runId then return false end
    addon.db.history = addon.db.history or {}

    local struckNow = {}
    for id, entry in pairs(addon.db.history) do
        if entry.runId == runId and entry.session == session
            and (not winner or entry.winner == winner) then
            addon.db.history[id] = nil
            struck[id] = true
            struckNow[#struckNow + 1] = entry
            addon.Log:I("History", "struck", entry.link, "from", tostring(entry.winner))
        end
    end

    if #struckNow == 0 then
        if winner then RememberEarly("strike", session, winner, runId, seq) end
        return false
    end
    Reindex()

    for _, entry in ipairs(struckNow) do
        addon.Callbacks:Fire("HistoryChanged", "struck", entry)
    end
    return true
end



function History:MarkDelivered(session, winner, runId)
    if not session or not runId then return 0 end
    local changed, matched = 0, 0
    for _, entry in pairs(addon.db.history or {}) do
        if entry.runId == runId and entry.session == session
            and (not winner or entry.winner == winner) then
            matched = matched + 1
            if not entry.delivered then
                entry.delivered = true
                changed = changed + 1
                addon.Log:D("History", "delivered", entry.link, "to",
                    tostring(entry.winner))
            end
        end
    end


    if matched == 0 and winner then RememberEarly("delivered", session, winner, runId) end

    if changed > 0 then addon.Callbacks:Fire("HistoryChanged", "delivered") end
    return changed
end







function History.IsReasonAward(entry)
    return entry ~= nil and entry.reason ~= nil and entry.reason ~= ""
end



function History.IsCoinLoot(entry)
    return entry ~= nil and entry.coin == true
end

function History:GetForWinner(winner)
    local key = WinnerKey(winner)
    if not key then return {} end
    EnsureIndex()
    return byWinner[key] or {}
end

function History:GetWinnersOfItem(link)
    local key = ItemKey(link)
    if not key then return {} end
    EnsureIndex()
    return byItem[key] or {}
end




function History:GetStats(winner)
    local winnerKey = WinnerKey(winner)
    if not winnerKey then return nil end
    EnsureIndex()

    local names = { winner }
    local hasAlts = addon.Player and addon.Player.Main and addon.Player.Alts
    local isAlt = hasAlts and WinnerKey(addon.Player:Main(winner)) ~= winnerKey
    if hasAlts and not isAlt then
        for _, alt in ipairs(addon.Player:Alts(winner)) do
            names[#names + 1] = alt
        end
    end

    local counts, total, imported, reasons, fromAlts = {}, 0, 0, 0, 0
    local importedBySource = {}
    local recent = {}
    local any = false

    for _, name in ipairs(names) do
        local nameKey = WinnerKey(name)
        local entries = byWinner[nameKey]
        if entries then
            any = true
            for _, entry in ipairs(entries) do
                if History.IsReasonAward(entry) then


                    reasons = reasons + 1
                else
                    local key = History.ResponseText(entry) or T["Unknown"]
                    counts[key] = (counts[key] or 0) + 1
                    total = total + 1
                    if entry.source then
                        imported = imported + 1
                        importedBySource[entry.source] =
                            (importedBySource[entry.source] or 0) + 1
                    end
                    if nameKey ~= winnerKey then fromAlts = fromAlts + 1 end
                end

                recent[#recent + 1] = entry
            end
        end
    end

    if not any then return nil end

    table.sort(recent, function(a, b) return EpochOf(a) > EpochOf(b) end)

    return {
        counts = counts, total = total, imported = imported,
        importedBySource = importedBySource,
        reasons = reasons, recent = recent, fromAlts = fromAlts,
    }
end



function History:Count()
    local n = 0
    for _ in pairs(addon.db.history or {}) do n = n + 1 end
    return n
end


function History:GetAll()
    local all = {}
    EachEntry(function(entry) all[#all + 1] = entry end)
    table.sort(all, function(a, b) return EpochOf(a) > EpochOf(b) end)
    return all
end






History.UNTAGGED = ""

function History.GuildKey(entry)
    local guild = entry and entry.guild
    if type(guild) ~= "string" or guild == "" then return "" end
    return guild
end


function History.RecorderKey(entry)
    local recorder = entry and entry.recorder
    if type(recorder) ~= "string" or recorder == "" then return "" end
    return (addon.Player and addon.Player:NameKey(recorder)) or recorder
end


local function Selection()
    local filter = addon.db and addon.db.historyFilter
    if type(filter) ~= "table" or (filter.kind ~= "guild" and filter.kind ~= "recorder")
        or type(filter.key) ~= "string" then
        return nil, nil
    end
    return filter.kind, filter.key
end

function History:OriginFilter()
    return Selection()
end

function History.PassesOrigin(entry)
    local kind, key = Selection()
    if kind == "guild" then return History.GuildKey(entry) == key end
    if kind == "recorder" then return History.RecorderKey(entry) == key end
    return true
end


function History:SetOriginFilter(kind, key)
    if kind ~= "guild" and kind ~= "recorder" then kind, key = nil, nil end
    if kind and type(key) ~= "string" then return end
    addon.db.historyFilter = { kind = kind, key = key }
    addon.Callbacks:Fire("HistoryFilterChanged", kind, key)
end



function History:OriginChoices()
    local guilds, recorders, byGuild, byRecorder = {}, {}, {}, {}
    local hidden = { total = 0 }
    local kind, selected = Selection()
    EachEntry(function(entry)
        local guildKey, recorderKey = History.GuildKey(entry), History.RecorderKey(entry)
        local g = byGuild[guildKey]
        if not g then
            g = { key = guildKey, label = entry.guild, count = 0 }
            byGuild[guildKey], guilds[#guilds + 1] = g, g
        end
        g.count = g.count + 1
        local r = byRecorder[recorderKey]
        if not r then
            r = { key = recorderKey, label = entry.recorder, count = 0 }
            byRecorder[recorderKey], recorders[#recorders + 1] = r, r
        end
        r.count = r.count + 1
        if not History.PassesOrigin(entry) then hidden.total = hidden.total + 1 end
    end)
    local Fold = addon.Locale.Fold
    local function order(a, b)
        if (a.key == "") ~= (b.key == "") then return b.key == "" end
        return Fold(a.label or "") < Fold(b.label or "")
    end
    table.sort(guilds, order)
    table.sort(recorders, order)
    for _, g in ipairs(guilds) do g.selected = kind == "guild" and g.key == selected end
    for _, r in ipairs(recorders) do r.selected = kind == "recorder" and r.key == selected end
    local chosen = kind and (kind == "guild" and byGuild or byRecorder)[selected]
    return { guilds = guilds, recorders = recorders, hidden = hidden,
        kind = kind, key = selected, label = chosen and chosen.label or selected }
end






local function FindStoredEntry(id)
    if not id then return nil end

    for _, store in ipairs({ addon.db.history or {}, addon.db.imported or {} }) do
        if store[id] then return store, id, store[id] end
        for key, entry in pairs(store) do
            if entry.id == id then return store, key, entry end
        end
    end
end

local function MarkEdited(entry)
    entry.editedAt = GetServerTime()
    entry.editedBy = addon.Player and addon.Player:GetFullName("player") or nil
end

local function FinishEdit(action, entry)
    MarkEdited(entry)
    Reindex()
    addon.Log:I("History", action, tostring(entry.id))
    addon.Callbacks:Fire("HistoryChanged", action, entry)
    return true
end


function History:GetKnownWinners()
    local seen, names = {}, {}
    EachEntry(function(entry)
        if entry.winner and entry.winner ~= "" then seen[entry.winner] = true end
    end)
    if addon.GetCandidates then
        for name in pairs(addon.GetCandidates()) do seen[name] = true end
    end
    for name in pairs(seen) do names[#names + 1] = name end
    local Fold = addon.Locale.Fold
    table.sort(names, function(a, b) return Fold(a) < Fold(b) end)
    return names
end

function History:SetWinner(id, winner)
    if type(winner) ~= "string" or winner == "" then return false end
    local _, _, entry = FindStoredEntry(id)
    if not entry then return false end
    if entry.winner == winner then return true end

    entry.winner = winner
    return FinishEdit("changed winner for", entry)
end

function History:SetResponse(id, responseID)
    local response = addon.Config:Responses()[responseID]
    if not response then return false end
    local _, _, entry = FindStoredEntry(id)
    if not entry then return false end

    entry.responseID = responseID
    entry.responseText = response.text


    entry.responseCode = nil
    entry.r, entry.g, entry.b = response.r, response.g, response.b

    entry.reason = nil
    return FinishEdit("changed response for", entry)
end

function History:SetReason(id, reasonIndex)
    local reason = addon.db.awardReasons and addon.db.awardReasons[reasonIndex]


    if not reason or not reason.log then return false end
    local _, _, entry = FindStoredEntry(id)
    if not entry then return false end

    entry.reason = reason.text
    return FinishEdit("changed award reason for", entry)
end

function History:DeleteEntry(id)
    local store, key, entry = FindStoredEntry(id)
    if not store then return false end

    store[key] = nil

    if store == addon.db.history then struck[key] = true end
    Reindex()
    if addon.Snapshot then addon.Snapshot:Prune() end
    addon.Log:I("History", "deleted", tostring(id), "from",
        entry.source or "slc")
    addon.Callbacks:Fire("HistoryChanged", "deleted", entry)
    return true
end






function History:PruneOlderThan(days)
    local cutoff = GetServerTime() - (days * 24 * 60 * 60)
    local removed = 0
    for id, entry in pairs(addon.db.history or {}) do
        if EpochOf(entry) < cutoff then
            addon.db.history[id] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then Reindex() end

    if addon.Snapshot then addon.Snapshot:Prune() end
    return removed
end



function History:PruneBySetting()
    local days = tonumber(addon.db.historyPruneDays) or 0
    if days <= 0 then return 0, 0 end
    local removed = History:PruneOlderThan(days)
    if removed > 0 then
        addon.Log:I("History", "pruned", removed, "entries older than", days, "days")
    end
    return removed, days
end



function History:Clear()
    local removed = History:Count()
    addon.db.history = {}
    Reindex()
    if addon.Snapshot then addon.Snapshot:Prune() end
    addon.Log:I("History", "cleared", removed, "recorded entries")

    addon.Callbacks:Fire("HistoryChanged", "cleared")
    return removed
end










local CSV_HEADER =
    "id,date,time,source,winner,owner,item,itemLink,response,votes,instance,difficulty,boss,delivered,note,reason,coin,encounterID,guild,recorder"

History.CSV_HEADER = CSV_HEADER



local function OriginatedHere(entry)
    return entry.source == nil or entry.source == addon.HistoryImport.SOURCE_CSV
end



History.DELIMITERS = { comma = ",", semicolon = ";" }

local SEMICOLON_LOCALES = {
    deDE = true, frFR = true, esES = true, esMX = true, itIT = true,
    ptBR = true, ruRU = true,
}



function History:Delimiter()
    local chosen = addon.db and History.DELIMITERS[addon.db.csvDelimiter or ""]
    if chosen then return chosen end
    local locale = GetLocale and GetLocale() or "enUS"
    return SEMICOLON_LOCALES[locale] and ";" or ","
end



function History:ToCSV(scope, delimiter)
    delimiter = delimiter or History:Delimiter()
    local rows = { (CSV_HEADER:gsub(",", delimiter)) }

    local ordered = {}
    if scope == "slc" then
        EachEntry(function(entry)
            if OriginatedHere(entry) then ordered[#ordered + 1] = entry end
        end)
    else
        ordered = History:GetAll()
    end
    table.sort(ordered, function(a, b) return EpochOf(a) < EpochOf(b) end)

    local function esc(value)
        if value == nil then return "" end
        local text = tostring(value)

        if text:find('[,"|\n]') or text:find(delimiter, 1, true) then
            return '"' .. text:gsub('"', '""') .. '"'
        end
        return text
    end


    local function escLink(link)
        if not link then return "" end
        return esc((tostring(link):gsub("|", "||")))
    end

    for _, entry in ipairs(ordered) do
        rows[#rows + 1] = table.concat({
            esc(entry.id), esc(entry.date), esc(entry.time),
            esc(entry.source or "slc"),
            esc(entry.winner), esc(entry.owner),

            esc(entry.name
                or (entry.link and (C_Item.GetItemInfo(entry.link) or entry.link))),
            escLink(entry.link),
            esc(History.ResponseText(entry)), esc(entry.votes), esc(entry.instance),
            esc(entry.difficultyName or entry.difficultyID), esc(entry.boss),

            esc(entry.delivered == nil and "" or (entry.delivered and "yes" or "no")),
            esc(entry.note and addon.Autopass
                and addon.Autopass.NoteText(entry.note) or entry.note),
            esc(entry.reason),

            esc(entry.coin and "yes" or ""),
            esc(entry.encounterID),
            esc(entry.guild), esc(entry.recorder),
        }, delimiter)
    end

    return table.concat(rows, "\n")
end


function History:CountForScope(scope)
    if scope ~= "slc" then
        return History:Count() + addon.HistoryImport:Count()
    end

    local n = 0
    EachEntry(function(entry)
        if OriginatedHere(entry) then n = n + 1 end
    end)
    return n
end






local LOGIN_BUDGET = 250
History.LOGIN_BUDGET = LOGIN_BUDGET



local function StartLoginPass()
    byWinner, byItem, liveKeys = {}, {}, {}
    pending, pendingAt = {}, 1
    EachEntry(function(entry) pending[#pending + 1] = entry end)
    indexState = "building"
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(self)
        if indexState == "building" then
            IndexStep(LOGIN_BUDGET)
            return
        end
        self:SetScript("OnUpdate", nil)
        local live = liveKeys
        liveKeys = nil
        if addon.Snapshot then addon.Snapshot:Prune(live, true) end
    end)
    return driver
end

function History:Init()
    addon.db.history = addon.db.history or {}
    addon.db.imported = addon.db.imported or {}

    local removed, days = History:PruneBySetting()
    History.loginDriver = StartLoginPass()
    if removed > 0 then

        print(addon.Log.CHAT_PREFIX.accent .. addon.Locale.Format(addon.Locale.Plural{
            one = "removed %d award history entry older than %d days - \"Keep award history for\" in /slc, Data & history.",
            other = "removed %d award history entries older than %d days - \"Keep award history for\" in /slc, Data & history.",
        }, removed, removed, days))
    end



    addon.Callbacks:Register("ItemAwarded", function(session, winner, item)
        if not addon.PlayerIsMasterLooter() then return end
        if item and item.simulated then return end


        if item and item.reason and not item.reasonLogged then
            addon.Log:I("History", "not recording", item.link,
                "- award reason", tostring(item.reasonText), "is not logged")
            return
        end

        local entry = BuildEntry(session, winner, item)



        if addon.db.recordHistory then
            History:Record(entry)
        else
            addon.Log:I("History", "not recording", item.link,
                "- Record award history is off in your settings")
        end



        if addon.db.shareHistory then
            addon.Comms:Send("history", { e = entry }, nil, true)
        end
    end)

    addon.Comms:Register("history", "ml", function(args, sender)
        if type(args) ~= "table" or type(args.e) ~= "table" then return end
        if addon.db.recordHistory then
            History:Record(args.e, sender)
        elseif not addon.PlayerIsMasterLooter() then


            addon.Log:D("History", "not recording", tostring(args.e.link),
                "- Record award history is off in your settings")
        end
    end)


    addon.Callbacks:Register("ItemUnawarded", function(session, previous, item, runId)
        if item and item.simulated then return end


        History:RemoveForSession(session, previous, runId or addon.Session:GetRunId(),
            item and item.awardSeq)
    end)



    addon.Callbacks:Register("ItemDelivered", function(session, winner, item, runId)
        if item and item.simulated then return end
        History:MarkDelivered(session, winner, runId)
    end)

    addon.Log:I("History", "ready", History:Count(), "entries,",
        addon.HistoryImport:Count(), "imported")
end
