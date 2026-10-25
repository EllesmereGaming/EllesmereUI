if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local History = {}
addon.History = History




local byWinner = {}
local byItem = {}
local winnerKeyOf = setmetatable({}, { __mode = "k" })

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


local function Forget(kind, key)
    if addon.SharedSaved then addon.SharedSaved.Forget(addon.db, kind, key) end
end


local revive = { tried = false, unpacked = false }

function History.Revive(kind, key, unpack)
    local db = addon.db
    if type(db) ~= "table" or key == nil then return end
    local shared = addon.SharedSaved
    local packed = unpack and type(db.deletedPacked) == "table" and db.deletedPacked[kind]
    if packed and not revive.tried and shared and shared.Unpack then
        revive.tried = true
        shared.Unpack(db)
        revive.unpacked = true
    end
    local gone = type(db.deleted) == "table" and db.deleted[kind]
    if type(gone) == "table" and gone[key] ~= nil then gone[key] = nil end
end


function History.ReviveDone()
    revive.tried = false
    if not revive.unpacked then return end
    revive.unpacked = false
    local shared = addon.SharedSaved
    if shared and shared.Compact and type(addon.db) == "table" then shared.Compact(addon.db) end
end






local DAY = 24 * 60 * 60
local ARCHIVE_DAYS = 30
local COIN_KEEP_DAYS = 90
History.COIN_KEEP_DAYS = COIN_KEEP_DAYS

local SWEEP_MIN, SWEEP_EVERY, SWEEP_DELAY = 200, 7 * DAY, 20

local SEG_MAX = 1000

local RELEASE_DELAY = 30
local CLOSE_DELAY = 8

local KEEP_RECENT, KEEP_ITEM = 5, 5
local SUM_VERSION = 1
History.ARCHIVE_DAYS, History.SEG_MAX, History.SWEEP_MIN = ARCHIVE_DAYS, SEG_MAX, SWEEP_MIN


local STORES = { { store = "history", tag = "h" }, { store = "imported", tag = "i" } }
local STORE_OF = { h = "history", i = "imported" }


local loaded = {}
local loadedAll = false
local holds = {}
local lastUse = 0
local releaseQueued = false

local archivedByWinner
local unreadableLogged = {}

local summaryOk, summaryFor = false, nil
local sweepState, sweepScheduled, sweepDriver

local function Archive()
    local archive = addon.db and addon.db.historyArchive
    return type(archive) == "table" and archive or nil
end

local function Segs()
    local archive = Archive()
    local segs = archive and archive.segs
    return type(segs) == "table" and next(segs) ~= nil and segs or nil
end

local function Codec()
    local api = C_EncodingUtil
    if not (api and api.SerializeCBOR and api.DeserializeCBOR and api.CompressString
            and api.DecompressString and api.EncodeBase64 and api.DecodeBase64
            and Enum and Enum.CompressionMethod and Enum.Base64Variant) then
        return nil
    end
    return api
end


local function Pack(rows)
    local api = Codec()
    if not api then return nil end
    local ok, blob = pcall(function()
        local deflated = api.CompressString(api.SerializeCBOR(rows), Enum.CompressionMethod.Deflate,
            Enum.CompressionLevel and Enum.CompressionLevel.OptimizeForSize)
        return api.EncodeBase64(deflated, Enum.Base64Variant.StandardUrlSafe)
    end)
    if ok and type(blob) == "string" then return blob end
    return nil, tostring(blob)
end
History.PackValue = Pack


local function UnpackValue(blob)
    local api = Codec()
    if not api or type(blob) ~= "string" then return nil end
    local ok, value = pcall(function()
        local raw = api.DecodeBase64(blob, Enum.Base64Variant.StandardUrlSafe)
        local cbor = raw and api.DecompressString(raw, Enum.CompressionMethod.Deflate)
        return type(cbor) == "string" and api.DeserializeCBOR(cbor) or nil
    end)
    if not ok or type(value) ~= "table" then return nil end
    return value
end
History.UnpackValue = UnpackValue


local function Unpack(blob)
    local rows = UnpackValue(blob)
    if not rows then return nil end
    local out = { h = {}, i = {} }
    for tag in pairs(out) do
        if type(rows[tag]) == "table" then
            for key, row in pairs(rows[tag]) do
                if type(row) == "table" then out[tag][key] = row end
            end
        end
    end
    return out
end

local function MonthKey(epoch)
    return date("!%Y-%m", epoch)
end


local function SplitSegKey(key)
    local month, part = tostring(key):match("^(.-)%.(%d+)$")
    return month or tostring(key), tonumber(part) or 0
end

local function LastPart(segs, month)
    local high = 0
    for key in pairs(segs) do
        local m, p = SplitSegKey(key)
        if m == month and p > high then high = p end
    end
    return high
end


local function LiveHas(tag, key)
    local store = addon.db[STORE_OF[tag]]
    return type(store) == "table" and store[key] ~= nil
end


local function WriteSeg(segs, key, rows)
    local n, nh, ni, oldest, newest, oh, oc = 0, 0, 0, nil, nil, nil, nil
    for tag, list in pairs(rows) do
        for _, row in pairs(list) do
            local epoch = EpochOf(row)
            n = n + 1
            if tag == "h" then
                nh = nh + 1
                if not oh or epoch < oh then oh = epoch end
            else
                ni = ni + 1
            end
            if not oldest or epoch < oldest then oldest = epoch end
            if not newest or epoch > newest then newest = epoch end
            if row.coin == true and (not oc or epoch < oc) then oc = epoch end
        end
    end
    if n == 0 then
        segs[key], loaded[key] = nil, nil
        return true
    end
    local blob, err = Pack(rows)
    if not blob then
        addon.Log:W("History", "could not pack archive segment", key, err)
        return false
    end
    segs[key] = { n = n, nh = nh, ni = ni, oldest = oldest, newest = newest, oh = oh, oc = oc or false,
        blob = blob }
    if loaded[key] then loaded[key] = rows end
    return true
end

local function LoadSeg(key, seg)
    if loaded[key] then return loaded[key] end
    local rows = type(seg) == "table" and Unpack(seg.blob)
    if not rows then
        if not unreadableLogged[key] then
            unreadableLogged[key] = true
            addon.Log:W("History", "archive segment unreadable - kept as it is", tostring(key))
        end
        return nil
    end
    loaded[key] = rows
    return rows
end

local releaseGen = 0




local function QueueRelease(again)
    if (releaseQueued and not again) or not (C_Timer and C_Timer.After) then return end
    releaseQueued = true
    releaseGen = releaseGen + 1
    local gen = releaseGen
    local wait = RELEASE_DELAY - ((GetTime and GetTime() or 0) - lastUse)
    C_Timer.After(math.max(1, wait), function()
        if gen ~= releaseGen then return end
        releaseQueued = false
        if next(loaded) == nil then return end
        if next(holds) or GetTime() - lastUse < RELEASE_DELAY then
            QueueRelease()
            return
        end
        History:ReleaseArchive()
    end)
end


function History:EnsureArchive()
    local segs = Segs()
    if not segs then return false end
    lastUse = GetTime and GetTime() or 0
    if not loadedAll then
        for key, seg in pairs(segs) do LoadSeg(key, seg) end
        loadedAll, archivedByWinner = true, nil
    end
    QueueRelease()
    return true
end


function History:ReleaseArchive()
    if next(holds) then return false end
    local freed = next(loaded) ~= nil
    loaded, loadedAll, archivedByWinner = {}, false, nil
    if freed and addon.SettleGC then addon.SettleGC() end
    return true
end

function History:IsArchiveLoaded()
    return next(loaded) ~= nil
end


function History:HoldArchive(who)
    holds[who] = true
end

function History:DropArchive(who)
    holds[who] = nil

    lastUse = (GetTime and GetTime() or 0) - (RELEASE_DELAY - CLOSE_DELAY)
    QueueRelease(true)
end


local function EachArchived(fn, onlyTag)
    if not History:EnsureArchive() then return end
    for segKey, rows in pairs(loaded) do
        for tag, list in pairs(rows) do
            if not onlyTag or tag == onlyTag then
                for key, row in pairs(list) do
                    if not LiveHas(tag, key) then fn(row, tag, key, segKey) end
                end
            end
        end
    end
end


function History:ArchivedCount(tag)
    local n = 0
    for _, seg in pairs(Segs() or {}) do
        if type(seg) == "table" then
            n = n + (tonumber(tag == "i" and seg.ni or seg.nh) or 0)
        end
    end
    return n
end

local function ArchiveNewest()
    local newest
    for _, seg in pairs(Segs() or {}) do
        local epoch = type(seg) == "table" and tonumber(seg.newest)
        if epoch and (not newest or epoch > newest) then newest = epoch end
    end
    return newest
end
History.ArchiveNewest = ArchiveNewest


function History:IsArchived(store, key)
    local segs = Segs()
    if not segs or key == nil then return false end
    local tag = store == "imported" and "i" or "h"
    local epoch = tag == "h" and tonumber(tostring(key):match("^(%d+)%-"))
    if epoch then
        lastUse = GetTime and GetTime() or 0
        for segKey, seg in pairs(segs) do
            if type(seg) == "table" and (tonumber(seg.oldest) or 0) - DAY <= epoch
                and epoch <= (tonumber(seg.newest) or 0) + DAY then
                local rows = LoadSeg(segKey, seg)
                if rows and rows[tag][key] ~= nil then QueueRelease() return true end
            end
        end
        QueueRelease()
        return false
    end
    History:EnsureArchive()
    for _, rows in pairs(loaded) do
        if rows[tag][key] ~= nil then return true end
    end
    return false
end




local function ResponseKey(entry)
    if entry.responseCode then return "c" .. tostring(entry.responseCode) end
    if entry.coin == true and not entry.responseID then return "cCOIN" end
    if entry.responseText == nil then return "n" end
    return "t" .. tostring(entry.responseText)
end
History.ResponseKey = ResponseKey

function History.ResponseTextForKey(rk)
    local tag, value = rk:sub(1, 1), rk:sub(2)
    if tag == "c" then return History.CodeText(value) end
    if tag ~= "t" then return nil end
    local status = addon.Session and addon.Session.STATUS and addon.Session.STATUS[value]
    return (status and status.text) or value
end


local RECENT_FIELDS = { "id", "link", "winner", "epoch", "source", "r", "g", "b",
    "responseCode", "responseText", "responseID", "coin", "reason" }

local function Compact(row)
    local out = {}
    for _, field in ipairs(RECENT_FIELDS) do out[field] = row[field] end
    return out
end


local function KeepNewest(list, item, epoch, epochOf, max)
    local at = #list + 1
    for i = 1, #list do
        if epoch > epochOf(list[i]) then at = i break end
    end
    if at > max then return end
    table.insert(list, at, item)
    if #list > max then list[#list] = nil end
end


local function Sample(row)
    local winner = row.winner
    return (winner ~= nil and ("s" .. tostring(winner)) or "n") .. "\31" .. ResponseKey(row)
end

local function SampleEntry(sample)
    local winner, rk = sample:match("^([^\31]*)\31(.*)$")
    local entry = {}
    if winner and winner:sub(1, 1) == "s" then entry.winner = winner:sub(2) end
    local tag, value = (rk or "n"):sub(1, 1), (rk or "n"):sub(2)
    if tag == "c" then entry.responseCode = value elseif tag == "t" then entry.responseText = value end
    return entry
end


local function ItemSlot(link)
    local key = ItemKey(link)
    return key and (tonumber(key:match("^item:(%d+)$")) or key)
end


local PACK = 1024
local function Unpacked(value)
    local list = {}
    if type(value) == "number" then
        while value > 0 do
            list[#list + 1] = value % PACK
            value = math.floor(value / PACK)
        end
    elseif type(value) == "string" then
        for index in value:gmatch("%d+") do list[#list + 1] = tonumber(index) end
    end
    return list
end

local function Packed(list)
    local number, scale = 0, 1
    for _, index in ipairs(list) do
        if index >= PACK then return table.concat(list, ",") end
        number, scale = number + index * scale, scale * PACK
    end
    return number
end


local pairIndexOf = setmetatable({}, { __mode = "k" })
local function PairIndex(sum, sample)
    local index = pairIndexOf[sum]
    if not index then
        index = {}
        for i, known in ipairs(sum.pairs) do index[known] = i end
        pairIndexOf[sum] = index
    end
    local at = index[sample]
    if not at then
        at = #sum.pairs + 1
        sum.pairs[at], index[sample] = sample, at
    end
    return at
end

local function Tagged(value)
    return type(value):sub(1, 1) .. tostring(value)
end

local function NewSummary()
    return { w = {}, items = {}, itemAt = {}, pairs = {}, bosses = {}, snaps = {} }
end
local EMPTY_SUMMARY = NewSummary()

local function CompactEpoch(row) return EpochOf(row) end

local function AddRow(sum, row)
    local key = WinnerKey(row.winner)
    if key then
        local rec = sum.w[key]
        if not rec then
            rec = { n = 0, recent = {} }
            sum.w[key] = rec
        end
        rec.n = rec.n + 1
        if History.IsReasonAward(row) then
            rec.r = (rec.r or 0) + 1
        else
            local rk = ResponseKey(row)
            rec.c = rec.c or {}
            rec.c[rk] = (rec.c[rk] or 0) + 1
            if row.source then
                rec.s = rec.s or {}
                rec.s[row.source] = (rec.s[row.source] or 0) + 1
            end
        end
        KeepNewest(rec.recent, Compact(row), EpochOf(row), CompactEpoch, KEEP_RECENT)
        if type(row.class) == "string" then
            rec.cls = rec.cls or {}
            local seen = false
            for _, class in ipairs(rec.cls) do if class == row.class then seen = true end end
            if not seen then rec.cls[#rec.cls + 1] = row.class end
        end
        if row.coin then
            local id = addon.Storage and addon.Storage.ItemID(row.link)
            local tuple = table.concat({ Tagged(row.winner), Tagged(row.boss),
                Tagged(row.encounterID), Tagged(row.difficultyID), Tagged(id) }, "\31")
            rec.coins = rec.coins or {}
            local coin = rec.coins[tuple]
            if not coin then
                coin = { w = row.winner, b = row.boss, e = row.encounterID, d = row.difficultyID,
                    i = id, n = 0 }
                rec.coins[tuple] = coin
            end
            coin.n = coin.n + 1
        end
    end

    local item = ItemSlot(row.link)
    if item then
        sum.itemAt = type(sum.itemAt) == "table" and sum.itemAt or {}
        local list, at = Unpacked(sum.items[item]), Unpacked(sum.itemAt[item])
        local epoch = EpochOf(row)
        epoch = (epoch >= 0 and epoch < 1e12) and math.floor(epoch) or 0
        local pos = #list + 1
        for i = 1, #list do
            if epoch > (at[i] or 0) then pos = i break end
        end
        if pos <= KEEP_ITEM then
            for i = #at + 1, #list do at[i] = 0 end
            table.insert(list, pos, PairIndex(sum, Sample(row)))
            table.insert(at, pos, epoch)
            while #list > KEEP_ITEM do list[#list] = nil end
            while #at > #list do at[#at] = nil end
            sum.items[item] = Packed(list)
            sum.itemAt[item] = table.concat(at, ",")
        end
    end
    if type(row.boss) == "string" and row.boss ~= "" and not sum.bosses[row.boss] then
        sum.bosses[row.boss] = row.encounterID or false
    end
    if row.runId and row.session then
        local snap = tostring(row.runId) .. ":" .. tostring(row.session)
        sum.snaps[snap] = math.max(sum.snaps[snap] or 0, EpochOf(row))
    end
end


local function TrimSnaps(sum)
    local days = addon.Snapshot and addon.Snapshot.KEEP_DAYS or 60
    local cutoff = GetServerTime() - (days + 1) * DAY
    for key, epoch in pairs(sum.snaps) do
        if epoch < cutoff then sum.snaps[key] = nil end
    end
end

local function Token(segs)
    local keys = {}
    for key in pairs(segs) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for i, key in ipairs(keys) do
        local seg = segs[key]
        keys[i] = key .. ":" .. tostring(type(seg) == "table" and seg.n) .. ":"
            .. tostring(type(seg) == "table" and type(seg.blob) == "string" and #seg.blob)
    end
    return table.concat(keys, ",")
end


local function RebuildSummary()
    local archive, segs = Archive(), Segs()
    summaryOk, summaryFor = true, addon.db
    if not segs then
        if archive then archive.sum, archive.sumV, archive.token = nil, nil, nil end
        return
    end
    local sum = NewSummary()
    for segKey, seg in pairs(segs) do
        local rows = loaded[segKey] or Unpack(type(seg) == "table" and seg.blob)
        if rows then
            for tag, list in pairs(rows) do
                for key, row in pairs(list) do
                    if not LiveHas(tag, key) then AddRow(sum, row) end
                end
            end
        elseif not unreadableLogged[segKey] then
            unreadableLogged[segKey] = true
            addon.Log:W("History", "archive segment unreadable - kept as it is", tostring(segKey))
        end
    end
    TrimSnaps(sum)
    archive.sum, archive.sumV, archive.token = sum, SUM_VERSION, Token(segs)
    addon.Log:D("History", "archive summary rebuilt")
end

local function SummaryValid(archive, segs)
    local sum = archive.sum
    return archive.sumV == SUM_VERSION and type(sum) == "table" and type(sum.w) == "table"
        and type(sum.items) == "table"
        and type(sum.pairs) == "table" and type(sum.bosses) == "table"
        and type(sum.snaps) == "table" and archive.token == Token(segs)
end


local function Summary()
    local segs = Segs()
    if not segs then return EMPTY_SUMMARY end
    local archive = Archive()
    if not summaryOk or summaryFor ~= addon.db then
        if SummaryValid(archive, segs) then
            summaryOk, summaryFor = true, addon.db
        else
            RebuildSummary()
        end
    end
    return archive.sum or EMPTY_SUMMARY
end



local function CommitSegs(dirty, later)
    local segs = Archive() and Archive().segs
    if type(segs) ~= "table" then return end
    for segKey in pairs(dirty) do
        if loaded[segKey] then WriteSeg(segs, segKey, loaded[segKey]) end
    end
    archivedByWinner = nil
    if later or not Segs() then summaryOk = false else RebuildSummary() end
end


function History:ClearArchived(store)
    local tag = store == "imported" and "i" or "h"
    local segs = Archive() and Archive().segs
    if not Segs() then return 0 end
    History:EnsureArchive()
    local removed, dirty = 0, {}
    for segKey, rows in pairs(loaded) do
        for key in pairs(rows[tag]) do
            Forget(store, key)
            removed = removed + 1
        end
        if next(rows[tag]) then
            rows[tag] = {}
            dirty[segKey] = true
        end
    end
    CommitSegs(dirty)
    if not next(segs) then summaryOk = false end
    return removed
end


local function PruneArchived(cutoff)
    local segs = Segs()
    if not segs then return 0 end
    local removed, dirty = 0, {}
    for segKey, seg in pairs(segs) do
        if type(seg) == "table" and (tonumber(seg.nh) or 0) > 0
            and (tonumber(seg.oh) or 0) < cutoff then
            local rows = LoadSeg(segKey, seg)
            if rows then
                for key, row in pairs(rows.h) do
                    if EpochOf(row) < cutoff then
                        rows.h[key] = nil
                        removed = removed + 1
                        dirty[segKey] = true
                    end
                end
            end
        end
    end
    if removed > 0 then CommitSegs(dirty, true) end
    QueueRelease()
    return removed
end


local function PruneArchivedCoins(cutoff)
    local segs = Segs()
    if not segs then return 0 end
    local removed, dirty = 0, {}
    for segKey, seg in pairs(segs) do
        local oc = type(seg) == "table" and seg.oc
        if type(seg) == "table" and (tonumber(seg.oldest) or 0) < cutoff
            and (oc == nil or (oc and oc < cutoff)) then
            local rows = LoadSeg(segKey, seg)
            if rows then
                local kept
                for _, list in pairs(rows) do
                    for key, row in pairs(list) do
                        if row.coin == true then
                            local epoch = EpochOf(row)
                            if epoch < cutoff then
                                list[key] = nil
                                removed = removed + 1
                                dirty[segKey] = true
                            elseif not kept or epoch < kept then
                                kept = epoch
                            end
                        end
                    end
                end
                if not dirty[segKey] then seg.oc = kept or false end
            end
        end
    end
    if removed > 0 then CommitSegs(dirty, true) end
    QueueRelease()
    return removed
end

local function Index(entry)
    if type(entry) ~= "table" then return end
    local winnerKey = WinnerKey(entry.winner)
    winnerKeyOf[entry] = winnerKey
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


local function EachLive(fn)
    for _, entry in pairs(addon.db.history or {}) do fn(entry) end
    for _, entry in pairs(addon.db.imported or {}) do fn(entry) end
end
History.EachLive = EachLive



local function EachEntry(fn, store)
    if store ~= "imported" then
        for _, entry in pairs(addon.db.history or {}) do fn(entry) end
    end
    if store ~= "history" then
        for _, entry in pairs(addon.db.imported or {}) do fn(entry) end
    end
    EachArchived(function(row) fn(row) end,
        store == "history" and "h" or store == "imported" and "i" or nil)
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
    EachLive(Index)
    indexState = "ready"
    archivedByWinner = nil
end

local function Reindex()
    History:Reindex()
end


local function EnsureIndex()
    if indexState == "ready" then return end
    if indexState == "building" then IndexStep(math.huge) return end
    Reindex()
end


local function DropListed(index, key, gone)
    local list = index[key]
    if not list then return end
    local n = 0
    for i = 1, #list do
        local entry = list[i]
        if not gone[entry] then
            n = n + 1
            list[n] = entry
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    if n == 0 then index[key] = nil end
end


local function Unindex(gone)
    archivedByWinner = nil
    if indexState == "none" or next(gone) == nil then return end
    if indexState ~= "ready" then
        Reindex()
        return
    end
    local winners, items = {}, {}
    for entry in pairs(gone) do
        local winnerKey = winnerKeyOf[entry]
        if winnerKey then winners[winnerKey] = true end
        winnerKeyOf[entry] = nil
        local itemKey = ItemKey(entry.link)
        if itemKey then items[itemKey] = true end
    end
    for key in pairs(winners) do DropListed(byWinner, key, gone) end
    for key in pairs(items) do DropListed(byItem, key, gone) end
end


local function Reindexed(entry)
    if indexState ~= "ready" then
        Reindex()
        return
    end
    Unindex({ [entry] = true })
    Index(entry)
end











local function ResolveCandidateResponse(candidate, responseByIndex, awardedWinner)
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

local function EncounterRecord(boss, encounterID)
    local encounter = addon.Encounter
    if not (boss or encounterID) or not (encounter and encounter.GetLog and encounter.SameBoss) then
        return nil
    end
    local log, fallback = encounter:GetLog(), nil
    for i = #log, 1, -1 do
        local logged = log[i]
        if type(logged) == "table" and encounter.SameBoss(logged.name, logged.id, boss, encounterID) then
            if logged.success then return logged end
            fallback = fallback or logged
        end
    end
    return fallback
end


local function SourceOf(item)
    local here, hereType, hereDifficulty, hereDifficultyName = GetInstanceInfo()
    local record = EncounterRecord(item.boss, item.encounterID)
    if not record and not item.difficultyID then
        return here, hereType, hereDifficulty, hereDifficultyName
    end
    local inside = hereType == "raid" or hereType == "party"
    local difficultyID = item.difficultyID or (record and record.difficultyID)
        or (inside and hereDifficulty) or nil
    local instance, instanceType = record and record.instance, record and record.instanceType
    if not instance and inside then instance, instanceType = here, hereType end
    local difficultyName
    if inside and difficultyID == hereDifficulty then
        difficultyName = hereDifficultyName
    elseif type(difficultyID) == "number" and GetDifficultyInfo then
        local ok, name = pcall(GetDifficultyInfo, difficultyID)
        if ok and type(name) == "string" and name ~= "" then difficultyName = name end
    end
    return instance, instanceType, difficultyID, difficultyName
end


local function VoteCount(candidate)
    local voters = candidate and candidate.voters
    if type(voters) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(voters) do n = n + 1 end
    return n
end

local function BuildEntry(session, winner, item)
    counter = counter + 1

    local candidate = item.candidates and item.candidates[winner]

    local responseText, responseID, r, g, b, responseCode =
        ResolveCandidateResponse(candidate,
            function(index) return addon.Config:Responses()[index] end, true)

    local instanceName, instanceType, difficultyID, difficultyName = SourceOf(item)

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
        votes = VoteCount(candidate),
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
    editedAt = "number",
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
    local r, g, b = row.r, row.g, row.b
    if not (r and g and b and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1) then
        row.r, row.g, row.b = nil, nil, nil
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

    row.editedAt = GetServerTime()
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

    if addon.db.history[entry.id] or History:IsArchived("history", entry.id) then


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

    History.Revive("history", entry.id)
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

    if addon.BonusRoll and addon.BonusRoll.AlreadyRecorded(History:ForReplayCheck(name, epoch), name, link, boss,
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

    local struckNow, gone = {}, {}
    for id, entry in pairs(addon.db.history) do
        if entry.runId == runId and entry.session == session
            and (not winner or entry.winner == winner) then
            addon.db.history[id] = nil
            struck[id] = true
            Forget("history", id)
            struckNow[#struckNow + 1] = entry
            gone[entry] = true
            addon.Log:I("History", "struck", entry.link, "from", tostring(entry.winner))
        end
    end

    if #struckNow == 0 then
        if winner then RememberEarly("strike", session, winner, runId, seq) end
        return false
    end
    Unindex(gone)

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

                entry.editedAt = GetServerTime()
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


function History:GetLiveForWinner(winner)
    local key = WinnerKey(winner)
    if not key then return {} end
    EnsureIndex()
    return byWinner[key] or {}
end


function History:GetForWinner(winner)
    local key = WinnerKey(winner)
    if not key then return {} end
    EnsureIndex()
    local live = byWinner[key] or {}
    if not Summary().w[key] then return live end
    History:EnsureArchive()
    if not archivedByWinner then
        archivedByWinner = {}
        EachArchived(function(row)
            local rowKey = WinnerKey(row.winner)
            if rowKey then
                archivedByWinner[rowKey] = archivedByWinner[rowKey] or {}
                table.insert(archivedByWinner[rowKey], row)
            end
        end)
    end
    local archived = archivedByWinner[key]
    if not archived then return live end
    local out = {}
    for i, entry in ipairs(live) do out[i] = entry end
    for _, entry in ipairs(archived) do out[#out + 1] = entry end
    return out
end


function History:CountForWinner(winner)
    local key = WinnerKey(winner)
    if not key then return 0 end
    EnsureIndex()
    local rec = Summary().w[key]
    return #(byWinner[key] or {}) + (rec and rec.n or 0)
end


function History:CoinRowsFor(winner)
    local key = WinnerKey(winner)
    if not key then return {} end
    EnsureIndex()
    local live = byWinner[key] or {}
    local rec = Summary().w[key]
    if not (rec and rec.coins) then return live end
    local out = {}
    for i, entry in ipairs(live) do out[i] = entry end
    for _, coin in pairs(rec.coins) do
        local row = { coin = true, winner = coin.w, boss = coin.b, encounterID = coin.e,
            difficultyID = coin.d, link = coin.i and ("item:" .. coin.i) or nil }
        for _ = 1, coin.n do out[#out + 1] = row end
    end
    return out
end


function History:ForReplayCheck(winner, epoch)
    local window = addon.BonusRoll and addon.BonusRoll.REPLAY_WINDOW or DAY
    local newest = ArchiveNewest()
    if newest and (type(epoch) ~= "number" or epoch - window <= newest) then
        return History:GetForWinner(winner)
    end
    return History:GetLiveForWinner(winner)
end


function History:ClassesFor(winner)
    local key = WinnerKey(winner)
    if not key then return {} end
    EnsureIndex()
    local out = {}
    for _, entry in ipairs(byWinner[key] or {}) do
        if type(entry.class) == "string" then out[#out + 1] = entry.class end
    end
    local rec = Summary().w[key]
    for _, class in ipairs(rec and rec.cls or {}) do out[#out + 1] = class end
    return out
end


function History:ArchivedBosses()
    return Summary().bosses
end


function History.EachSnapKey(fn)
    EachLive(function(entry)
        if entry.runId and entry.session then
            fn(tostring(entry.runId) .. ":" .. tostring(entry.session), EpochOf(entry))
        end
    end)
    for key, epoch in pairs(Summary().snaps) do fn(key, epoch) end
end


local function NewestFirst(a, b) return EpochOf(a) > EpochOf(b) end

function History:GetWinnersOfItem(link)
    local key = ItemKey(link)
    if not key then return {} end
    EnsureIndex()
    local out = {}
    for i, entry in ipairs(byItem[key] or {}) do out[i] = entry end
    local sum = Summary()
    local slot = ItemSlot(link)
    local packed = slot and sum.items[slot]
    if packed then
        local at = Unpacked(sum.itemAt and sum.itemAt[slot])
        for i, index in ipairs(Unpacked(packed)) do
            local sample = sum.pairs[index]
            if sample then
                local entry = SampleEntry(sample)
                entry.epoch = at[i]
                out[#out + 1] = entry
            end
        end
    end
    table.sort(out, NewestFirst)
    return out
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
    local sum = Summary()

    for _, name in ipairs(names) do
        local nameKey = WinnerKey(name)
        local entries = nameKey and byWinner[nameKey]

        local rec = nameKey and sum.w[nameKey]
        if rec then
            any = true
            reasons = reasons + (rec.r or 0)
            for rk, n in pairs(rec.c or {}) do
                local key = History.ResponseTextForKey(rk) or T["Unknown"]
                counts[key] = (counts[key] or 0) + n
                total = total + n
                if nameKey ~= winnerKey then fromAlts = fromAlts + n end
            end
            for source, n in pairs(rec.s or {}) do
                imported = imported + n
                importedBySource[source] = (importedBySource[source] or 0) + n
            end
            for _, copy in ipairs(rec.recent) do recent[#recent + 1] = copy end
        end
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
    local n = History:ArchivedCount("h")
    for _ in pairs(addon.db.history or {}) do n = n + 1 end
    return n
end



function History:GetAll(unsorted)
    local all = {}
    EachEntry(function(entry) all[#all + 1] = entry end)
    if unsorted then return all end

    table.sort(all, function(a, b)
        local x, y = a.epoch, b.epoch
        if type(x) ~= "number" then x = 0 end
        if type(y) ~= "number" then y = 0 end
        return x > y
    end)
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

    local recorderKeys = {}
    EachEntry(function(entry)
        local guildKey = History.GuildKey(entry)
        local recorder = type(entry.recorder) == "string" and entry.recorder or false
        local recorderKey = recorderKeys[recorder]
        if not recorderKey then
            recorderKey = History.RecorderKey(entry)
            recorderKeys[recorder] = recorderKey
        end
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

        if (kind == "guild" and guildKey ~= selected)
            or (kind == "recorder" and recorderKey ~= selected) then
            hidden.total = hidden.total + 1
        end
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
    if not History:EnsureArchive() then return nil end
    for segKey, rows in pairs(loaded) do
        for tag, list in pairs(rows) do
            if list[id] and not LiveHas(tag, id) then return list, id, list[id], segKey, tag end
        end
    end
    for segKey, rows in pairs(loaded) do
        for tag, list in pairs(rows) do
            for key, entry in pairs(list) do
                if entry.id == id and not LiveHas(tag, key) then return list, key, entry, segKey, tag end
            end
        end
    end
end


local function MarkEdited(entry)
    entry.editedAt = GetServerTime()
    entry.editedBy = addon.Player and addon.Player:GetFullName("player") or nil
end

local function FinishEdit(action, entry, segKey, rekeyed)
    MarkEdited(entry)

    if segKey then
        CommitSegs({ [segKey] = true })
    elseif rekeyed then
        Reindexed(entry)
    end
    archivedByWinner = nil
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
    local _, _, entry, segKey = FindStoredEntry(id)
    if not entry then return false end
    if entry.winner == winner then return true end

    entry.winner = winner
    return FinishEdit("changed winner for", entry, segKey, true)
end

function History:SetResponse(id, responseID)
    local response = addon.Config:Responses()[responseID]
    if not response then return false end
    local _, _, entry, segKey = FindStoredEntry(id)
    if not entry then return false end

    entry.responseID = responseID
    entry.responseText = response.text


    entry.responseCode = nil
    entry.r, entry.g, entry.b = response.r, response.g, response.b

    entry.reason = nil
    return FinishEdit("changed response for", entry, segKey)
end

function History:SetReason(id, reasonIndex)
    local reason = addon.db.awardReasons and addon.db.awardReasons[reasonIndex]


    if not reason or not reason.log then return false end
    local _, _, entry, segKey = FindStoredEntry(id)
    if not entry then return false end

    entry.reason = reason.text
    return FinishEdit("changed award reason for", entry, segKey)
end



function History:DeleteEntries(ids)
    local removed, last, dirty, gone = 0, nil, {}, {}
    for _, id in ipairs(ids or {}) do
        local store, key, entry, segKey, tag = FindStoredEntry(id)
        if store then
            store[key] = nil
            local native = store == addon.db.history or tag == "h"

            if native then struck[key] = true end
            Forget(native and "history" or "imported", key)
            if segKey then dirty[segKey] = true else gone[entry] = true end
            removed = removed + 1
            last = entry
        end
    end
    if removed == 0 then return 0 end

    if next(dirty) then CommitSegs(dirty) end
    Unindex(gone)
    if addon.Snapshot then addon.Snapshot:Prune() end
    if removed == 1 then
        addon.Log:I("History", "deleted", tostring(last.id), "from", last.source or "slc")
    else
        addon.Log:I("History", "deleted", removed, "entries")
    end
    addon.Callbacks:Fire("HistoryChanged", "deleted", removed == 1 and last or nil)
    return removed
end

function History:DeleteEntry(id)
    return History:DeleteEntries({ id }) > 0
end






function History:PruneOlderThan(days, login)
    local cutoff = GetServerTime() - (days * 24 * 60 * 60)
    local removed = PruneArchived(cutoff)
    for id, entry in pairs(addon.db.history or {}) do
        if EpochOf(entry) < cutoff then
            addon.db.history[id] = nil
            removed = removed + 1
        end
    end

    if login then return removed end
    if removed > 0 then Reindex() end

    if addon.Snapshot then addon.Snapshot:Prune() end
    return removed
end



function History:PruneBySetting(login)
    local days = tonumber(addon.db.historyPruneDays) or 0
    if days <= 0 then return 0, 0 end
    local removed = History:PruneOlderThan(days, login)
    if removed > 0 then
        addon.Log:I("History", "pruned", removed, "entries older than", days, "days")
    end
    return removed, days
end



function History:PruneCoins(login)
    local cutoff = GetServerTime() - COIN_KEEP_DAYS * DAY
    local removed = PruneArchivedCoins(cutoff)
    for _, store in ipairs({ addon.db.history or {}, addon.db.imported or {} }) do
        for id, entry in pairs(store) do
            if entry.coin == true and EpochOf(entry) < cutoff then
                store[id] = nil
                removed = removed + 1
            end
        end
    end
    if removed > 0 then
        addon.Log:I("History", "removed", removed, "bonus roll entries older than", COIN_KEEP_DAYS, "days")
    end
    if login or removed == 0 then return removed end
    Reindex()
    if addon.Snapshot then addon.Snapshot:Prune() end
    return removed
end



function History:Clear()
    local removed = History:Count()
    for id in pairs(addon.db.history or {}) do Forget("history", id) end
    History:ClearArchived("history")
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






local function PlanSweep(now)
    local cutoff = now - ARCHIVE_DAYS * DAY
    local byMonth, count = {}, 0
    for _, s in ipairs(STORES) do
        for key, row in pairs(addon.db[s.store] or {}) do
            if type(row) == "table" and EpochOf(row) < cutoff then
                local month = MonthKey(EpochOf(row))
                byMonth[month] = byMonth[month] or {}
                table.insert(byMonth[month], { store = s.store, tag = s.tag, key = key, row = row })
                count = count + 1
            end
        end
    end
    local months = {}
    for month, list in pairs(byMonth) do
        table.sort(list, function(a, b)
            local x, y = EpochOf(a.row), EpochOf(b.row)
            if x ~= y then return x < y end
            return tostring(a.key) < tostring(b.key)
        end)
        months[#months + 1] = { month = month, list = list, at = 1 }
    end
    table.sort(months, function(a, b) return a.month < b.month end)
    return months, count
end



local function SweepStep(state)
    local job = state.months[state.at]
    if not job then return true end
    local archive = Archive()
    archive.segs = type(archive.segs) == "table" and archive.segs or {}
    local segs = archive.segs
    local sum = Summary()

    local high = LastPart(segs, job.month)
    local key, rows = nil, nil
    local last = high > 0 and segs[job.month .. "." .. high]
    if type(last) == "table" and (tonumber(last.n) or SEG_MAX) < SEG_MAX then
        rows = Unpack(last.blob)
        if rows then key = job.month .. "." .. high end
    end
    if not key then key, rows = job.month .. "." .. (high + 1), { h = {}, i = {} } end

    local room = SEG_MAX
    for _, list in pairs(rows) do for _ in pairs(list) do room = room - 1 end end
    local moved = {}
    while job.at <= #job.list and room > 0 do
        local item = job.list[job.at]
        job.at = job.at + 1
        local store = addon.db[item.store]
        if type(store) == "table" and store[item.key] == item.row then
            rows[item.tag][item.key] = item.row
            moved[#moved + 1] = item
            room = room - 1
        end
    end
    if #moved > 0 then
        if not WriteSeg(segs, key, rows) then return true, false end
        if sum == EMPTY_SUMMARY then
            sum = NewSummary()
            archive.sum, archive.sumV = sum, SUM_VERSION
            summaryOk, summaryFor = true, addon.db
        end
        local gone = {}
        for _, item in ipairs(moved) do
            addon.db[item.store][item.key] = nil
            AddRow(sum, item.row)
            gone[item.row] = true
        end
        archive.token = Token(segs)
        state.moved = state.moved + #moved
        state.segments = state.segments + 1
        Unindex(gone)
    end
    if job.at > #job.list then state.at = state.at + 1 end
    return state.at > #state.months, true
end


local function SweepDue(count, now)
    if count == 0 then return false end
    local archive = Archive()
    local swept = archive and tonumber(archive.sweptAt) or 0
    return count >= SWEEP_MIN or now - swept >= SWEEP_EVERY
end

local function FinishSweep(state, ok)
    sweepState = nil
    local archive = Archive()
    if ok and archive then
        archive.sweptAt = GetServerTime()
        TrimSnaps(Summary())
    end
    if state.moved > 0 then
        addon.Log:I("History", "archived", state.moved, "row(s) into", state.segments,
            "segment(s) in", ("%.1f"):format(state.ms), "ms")
    end
end


function History:SweepNow(force)
    if not Codec() or next(loaded) or sweepState then return 0 end
    local now = GetServerTime()
    local months, count = PlanSweep(now)
    if not force and not SweepDue(count, now) then return 0 end
    if type(addon.db.historyArchive) ~= "table" then addon.db.historyArchive = {} end
    local state = { months = months, at = 1, moved = 0, segments = 0, ms = 0 }
    local done, ok = false, true
    while not done and ok do done, ok = SweepStep(state) end
    FinishSweep(state, ok)
    return state.moved
end



local function SweepTick(self)
    local state = sweepState
    if not state then
        self:SetScript("OnUpdate", nil)
        return
    end
    if next(loaded) or (InCombatLockdown and InCombatLockdown()) then
        self:SetScript("OnUpdate", nil)
        FinishSweep(state, false)
        History:ScheduleSweep(RELEASE_DELAY)
        return
    end
    local started = debugprofilestop and debugprofilestop()
    local done, ok = SweepStep(state)
    if started then state.ms = state.ms + debugprofilestop() - started end
    if done or not ok then
        self:SetScript("OnUpdate", nil)
        FinishSweep(state, ok)
    end
end


function History:ScheduleSweep(delay)
    if sweepState or sweepScheduled or not Codec() or not (C_Timer and C_Timer.After) then return end
    sweepScheduled = true
    C_Timer.After(delay or SWEEP_DELAY, function()
        sweepScheduled = false
        if sweepState then return end
        if next(loaded) or (InCombatLockdown and InCombatLockdown()) then
            History:ScheduleSweep(RELEASE_DELAY)
            return
        end
        local now = GetServerTime()
        local months, count = PlanSweep(now)
        if not SweepDue(count, now) then return end
        if type(addon.db.historyArchive) ~= "table" then addon.db.historyArchive = {} end
        sweepState = { months = months, at = 1, moved = 0, segments = 0, ms = 0 }
        sweepDriver = sweepDriver or CreateFrame("Frame")
        sweepDriver:SetScript("OnUpdate", SweepTick)
    end)
end






local function EditedLater(a, b)
    local x = type(a) == "table" and type(a.editedAt) == "number" and a.editedAt or nil
    local y = type(b) == "table" and type(b.editedAt) == "number" and b.editedAt or nil
    if x and y then return x > y end
    return x ~= nil
end


local function MergeMonth(winner, wsegs, lsegs, month)
    local union = { h = {}, i = {} }
    local keys = {}
    for _, segs in ipairs({ wsegs, lsegs }) do
        for key, seg in pairs(segs) do
            if SplitSegKey(key) == month then
                local rows = Unpack(type(seg) == "table" and seg.blob)
                if not rows then return false end
                keys[key] = true
                for tag, list in pairs(rows) do
                    for id, row in pairs(list) do
                        if union[tag][id] == nil or EditedLater(row, union[tag][id]) then
                            union[tag][id] = row
                        end
                    end
                end
            end
        end
    end
    local deleted = type(winner.deleted) == "table" and winner.deleted or {}
    for tag, list in pairs(union) do
        local store = STORE_OF[tag]
        local gone = type(deleted[store]) == "table" and deleted[store] or {}
        local live = type(winner[store]) == "table" and winner[store] or nil
        for id, row in pairs(list) do
            if gone[id] then
                list[id] = nil
            elseif live and live[id] ~= nil then
                if EditedLater(row, live[id]) then live[id] = row end
                list[id] = nil
            end
        end
    end
    local ordered = {}
    for tag, list in pairs(union) do
        for id, row in pairs(list) do ordered[#ordered + 1] = { tag = tag, id = id, row = row } end
    end
    table.sort(ordered, function(a, b)
        local x, y = EpochOf(a.row), EpochOf(b.row)
        if x ~= y then return x < y end
        return tostring(a.id) < tostring(b.id)
    end)
    local parts, written = {}, {}
    for i, item in ipairs(ordered) do
        local part = math.floor((i - 1) / SEG_MAX) + 1
        parts[part] = parts[part] or { h = {}, i = {} }
        parts[part][item.tag][item.id] = item.row
    end
    for part, rows in ipairs(parts) do
        local probe = {}
        if not WriteSeg(probe, month .. "." .. part, rows) then return false end
        written[month .. "." .. part] = probe[month .. "." .. part]
    end
    for key in pairs(keys) do wsegs[key] = nil end
    for key, seg in pairs(written) do wsegs[key] = seg end
    return true
end




function History.MergeArchive(winner, loser, added)
    local wa = type(winner.historyArchive) == "table" and winner.historyArchive or nil
    local la = type(loser.historyArchive) == "table" and loser.historyArchive or nil
    local wsegs = wa and type(wa.segs) == "table" and wa.segs or {}
    local lsegs = la and type(la.segs) == "table" and la.segs or {}
    if next(wsegs) == nil and next(lsegs) == nil then return 0 end
    if not wa then
        wa = {}
        winner.historyArchive = wa
    end
    wa.segs = wsegs

    local months = {}
    for key, seg in pairs(lsegs) do
        local mine = wsegs[key]
        if type(mine) ~= "table" or type(seg) ~= "table" or mine.blob ~= seg.blob then
            months[SplitSegKey(key)] = true
        end
    end
    for _, item in ipairs(added or {}) do
        local row = winner[item.store] and winner[item.store][item.key]
        if type(row) == "table" then
            local month = MonthKey(EpochOf(row))
            if LastPart(wsegs, month) > 0 then months[month] = true end
        end
    end
    if next(months) == nil then return 0 end



    local deleted = type(winner.deleted) == "table" and winner.deleted or {}
    local anyDeleted = (type(deleted.history) == "table" and next(deleted.history) ~= nil)
        or (type(deleted.imported) == "table" and next(deleted.imported) ~= nil)
    local touched = {}
    for _, s in ipairs(STORES) do
        for _, row in pairs(type(winner[s.store]) == "table" and winner[s.store] or {}) do
            if type(row) == "table" then touched[MonthKey(EpochOf(row))] = true end
        end
    end
    for month in pairs(months) do
        if not anyDeleted and not touched[month] and LastPart(wsegs, month) == 0 then
            for key, seg in pairs(lsegs) do
                if SplitSegKey(key) == month then wsegs[key] = seg end
            end
            months[month] = nil
        end
    end

    local merged = 0
    for month in pairs(months) do
        if MergeMonth(winner, wsegs, lsegs, month) then
            merged = merged + 1
        else

            for key, seg in pairs(lsegs) do
                if SplitSegKey(key) == month and wsegs[key] == nil then wsegs[key] = seg end
            end
            if addon.Log then addon.Log:W("History", "archive month unreadable in a saved file", month) end
        end
    end
    wa.sum, wa.sumV, wa.token = nil, nil, nil
    if (la and tonumber(la.sweptAt) or 0) > (tonumber(wa.sweptAt) or 0) then wa.sweptAt = la.sweptAt end
    return merged
end






local LOGIN_BUDGET = 250
History.LOGIN_BUDGET = LOGIN_BUDGET



local function StartLoginPass()
    byWinner, byItem, liveKeys = {}, {}, {}
    pending, pendingAt = {}, 1
    EachLive(function(entry) pending[#pending + 1] = entry end)
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

        if live then
            for key, epoch in pairs(Summary().snaps) do live[key] = math.max(live[key] or 0, epoch) end
        end
        if addon.Snapshot then addon.Snapshot:Prune(live, true) end
        History:ScheduleSweep()
    end)
    return driver
end

function History:Init()
    addon.db.history = addon.db.history or {}
    addon.db.imported = addon.db.imported or {}
    summaryOk, loaded, loadedAll, archivedByWinner = false, {}, false, nil

    local removed, days = History:PruneBySetting(true)
    History:PruneCoins(true)
    History.loginDriver = StartLoginPass()
    if removed > 0 then

        addon.Chat.Print(addon.Locale.Format(addon.Locale.Plural{
            one = "removed %d award history entry older than %d days - \"Keep award history for\" in /slc, Data & history.",
            other = "removed %d award history entries older than %d days - \"Keep award history for\" in /slc, Data & history.",
        }, removed, removed, days))
    end



    addon.Callbacks:Register("EncounterEnded", function(logged)
        if type(logged) ~= "table" or logged.instance then return end
        local name, instanceType = GetInstanceInfo()
        if (instanceType == "raid" or instanceType == "party") and type(name) == "string" and name ~= "" then
            logged.instance, logged.instanceType = name, instanceType
        end
    end)

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
        addon.HistoryImport:Count(), "imported,", History:ArchivedCount("h")
            + History:ArchivedCount("i"), "of them archived")
end
