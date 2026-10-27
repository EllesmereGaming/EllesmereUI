if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end






SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Import = {}
addon.HistoryImport = Import



local SOURCE_CSV = "slc-csv"
Import.SOURCE_CSV = SOURCE_CSV








local function EpochFromEntry(d)
    local direct = tonumber(d.epoch)
    if direct and direct > 1000000000 then return direct end

    local fromId = tostring(d.id or ""):match("^(%d+)")
    if fromId then
        local epoch = tonumber(fromId)


        if epoch and epoch > 1000000000 then return epoch end
    end



    local a, b, c = tostring(d.date or ""):match("^(%d+)[/%-](%d+)[/%-](%d+)$")
    if not a then return nil end

    local year, month, day
    if #a == 4 then
        year, month, day = a, b, c
    else
        day, month, year = a, b, "20" .. c
    end

    local hour, min, sec = tostring(d.time or ""):match("^(%d+):(%d+):(%d+)$")
    return time({
        year = tonumber(year), month = tonumber(month), day = tonumber(day),
        hour = tonumber(hour) or 0, min = tonumber(min) or 0, sec = tonumber(sec) or 0,
    })
end


local function UnescapeLink(text)
    if type(text) ~= "string" or text == "" then return nil end
    return (text:gsub("||", "|"))
end



local function ImportedID(source, winner, sourceID)
    return ("%s:%s:%s"):format(source, tostring(winner), tostring(sourceID))
end

local function Blank(value)
    if value == nil then return true end
    local text = tostring(value):gsub("%s+", "")
    return text == "" or text == "nil"
end


local function NonZero(value)
    local n = tonumber(value)
    if not n or n == 0 then return nil end
    return n
end


local function Text(value)
    if Blank(value) then return nil end
    return tostring(value)
end



local function Recase(winner)
    if type(winner) ~= "string" then return winner end
    local name, realm = winner:match("^([^-]+)-(.+)$")
    if not name then return winner end
    local mine = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(mine) == "string" and mine ~= ""
        and addon.Locale.Fold(mine) == addon.Locale.Fold(realm) then
        return name .. "-" .. mine
    end
    return winner
end





function Import:Count()
    local n = tonumber(addon.History:ArchivedCount("i")) or 0
    for _ in pairs(addon.db.imported or {}) do n = n + 1 end
    return n
end

function Import:Clear()
    local removed = Import:Count()

    if addon.SharedSaved then
        for id in pairs(addon.db.imported or {}) do
            addon.SharedSaved.Forget(addon.db, "imported", id)
        end
    end
    addon.History:ClearArchived("imported")
    addon.db.imported = {}
    addon.History:Reindex()
    addon.Log:I("Import", "cleared", removed, "imported entries")
    addon.Callbacks:Fire("HistoryChanged", "cleared")
    return removed
end



local function Store(entry, cutoff, stats, commit)
    if not entry or not entry.id then
        stats.malformed = stats.malformed + 1
        return false
    end

    if cutoff and (entry.epoch or 0) < cutoff then
        stats.tooOld = stats.tooOld + 1
        return false
    end


    if (addon.db.imported or {})[entry.id] or addon.History:IsArchived("imported", entry.id) then
        stats.duplicate = stats.duplicate + 1
        return false
    end

    if commit ~= false then
        addon.db.imported = addon.db.imported or {}
        addon.History.Revive("imported", entry.id, true)
        addon.db.imported[entry.id] = entry
    end
    stats.imported = stats.imported + 1
    return true
end


local function Cutoff()
    local days = addon.db.importMaxDays
    if not days or days <= 0 then return nil end
    return GetServerTime() - (days * 24 * 60 * 60)
end

local function NewStats()
    return { imported = 0, duplicate = 0, tooOld = 0, malformed = 0, scanned = 0 }
end










local function Normalise(source, winner, d)
    if type(d) ~= "table" then return nil end

    local link = UnescapeLink(d.lootWon)
    if not link then return nil end
    if Blank(winner) or Blank(d.id) then return nil end

    local epoch = EpochFromEntry(d)

    local r, g, b
    if type(d.color) == "table" then
        r, g, b = d.color[1], d.color[2], d.color[3]
    end

    local response = Text(d.response)



    local reason = Text(d.awardReason)
    if not reason and d.isAwardReason then
        reason = response or T["Award reason"]
    end

    return {
        id = ImportedID(source, winner, d.id),
        source = source,
        link = link,


        name = Text(d.itemName),
        winner = winner,
        owner = Text(d.owner),


        responseText = response,
        responseCode = not response and "UNKNOWN" or nil,
        responseID = d.responseID,
        isAwardReason = d.isAwardReason and true or false,
        reason = reason,
        r = r, g = g, b = b,
        date = Text(d.date),
        time = Text(d.time),
        epoch = epoch,
        instance = Text(d.instance),
        difficultyID = NonZero(d.difficultyID),
        difficultyName = Text(d.difficultyName),
        mapID = NonZero(d.mapID),
        boss = Text(d.boss),
        note = Text(d.note),
        votes = tonumber(d.votes),
        class = Text(d.class),
        groupSize = NonZero(d.groupSize),
        delivered = nil,
        importedAt = GetServerTime(),
    }
end







local SOURCES, BY_KEY = {}, {}
Import.SOURCES = SOURCES


local function Register(source)
    SOURCES[#SOURCES + 1] = source
    BY_KEY[source.key] = source
end

function Import:Source(key)
    return BY_KEY[key]
end


function Import:Label(key)
    if key == "slc" or key == SOURCE_CSV or key == nil then
        return "SimpleLootCouncil"
    end
    local source = BY_KEY[key]
    return source and source.label or tostring(key)
end




Register({
    key = "rclc",
    label = "RCLootCouncil",
})

Register({
    key = "loothing",
    label = "Loothing",
    csvMarker = "Loothing",
})








local function ParseLine(line, delim)
    delim = delim or ","
    local fields, position, length = {}, 1, #line

    while position <= length do
        local field

        if line:sub(position, position) == '"' then
            local buffer, index = {}, position + 1
            while index <= length do
                local char = line:sub(index, index)
                if char == '"' then
                    if line:sub(index + 1, index + 1) == '"' then
                        buffer[#buffer + 1] = '"'
                        index = index + 2
                    else
                        index = index + 1
                        break
                    end
                else
                    buffer[#buffer + 1] = char
                    index = index + 1
                end
            end
            field = table.concat(buffer)
            position = index

            local next_ = line:find(delim, position, true)
            position = next_ and (next_ + 1) or (length + 1)
        else
            local next_ = line:find(delim, position, true)
            if next_ then
                field = line:sub(position, next_ - 1)
                position = next_ + 1
            else
                field = line:sub(position)
                position = length + 1
            end
        end

        fields[#fields + 1] = field
    end



    if length > 0 and line:sub(length, length) == delim then
        fields[#fields + 1] = ""
    end

    return fields
end





local REQUIRED = {
    foreign = { "player", "date", "time", "id", "item", "response" },
    slc     = { "winner", "date", "id", "response" },
}

local function MapHeader(line, delim, comments)
    local columns = {}
    for index, name in ipairs(ParseLine(line, delim)) do
        columns[name:gsub("^%s+", ""):gsub("%s+$", "")] = index
    end

    local family, format
    if columns.winner then
        family, format = "slc", "slc"
    elseif columns.player then
        family, format = "foreign", "rclc"
        for _, source in ipairs(SOURCES) do
            if source.csvMarker then
                for _, comment in ipairs(comments or {}) do
                    if comment:find(source.csvMarker, 1, true) then
                        format = source.key
                    end
                end
            end
        end
    else
        return nil, nil,
            T["the header names neither a \"winner\" nor a \"player\" column"]
    end

    for _, required in ipairs(REQUIRED[family]) do
        if not columns[required] then
            return nil, nil, addon.Locale.Format(T["the header has no %q column"], required)
        end
    end
    return columns, format
end


local function NormaliseSLC(get)
    local winner, rawID = get("winner"), get("id")
    if not winner or not rawID then return nil end


    local link = UnescapeLink(get("itemLink")) or get("item")
    if not link then return nil end


    local delivered
    local deliveredText = get("delivered")
    if deliveredText == "yes" then
        delivered = true
    elseif deliveredText == "no" then
        delivered = false
    end




    local storedID = rawID:find(":", 1, true) and rawID
        or ImportedID(SOURCE_CSV, winner, rawID)
    local epochID = rawID:match("([^:]*)$")
    local named = get("source")
    local source = named and BY_KEY[named] and named or SOURCE_CSV

    return {
        id = storedID,
        source = source,


        nativeID = rawID,
        link = link,

        name = get("item"),
        winner = winner,
        owner = get("owner"),


        responseText = get("response"),
        responseCode = not get("response") and "UNKNOWN" or nil,

        reason = Text(get("reason")),


        epoch = EpochFromEntry({ id = epochID, date = get("date"), time = get("time") }),
        date = get("date"),
        time = get("time"),
        instance = get("instance"),


        difficultyID = tonumber(get("difficulty")),
        difficultyName = (function()
            local text = get("difficulty")
            if text == nil or text == "" or tonumber(text) then return nil end
            return text
        end)(),
        boss = get("boss"),


        encounterID = tonumber(get("encounterID")),
        note = get("note"),
        votes = tonumber(get("votes")),
        delivered = delivered,

        coin = get("coin") == "yes" or nil,

        guild = Text(get("guild")),
        recorder = Text(get("recorder")),
        importedAt = GetServerTime(),
    }
end






local function NormaliseForeign(source, get)
    local winner, sourceID = get("player"), get("id")
    if not winner or not sourceID then return nil end


    local itemColumn = get("item")
    local intact = itemColumn and itemColumn:find("|H", 1, true) and itemColumn

    local itemString = get("itemString")
    if itemString and not itemString:find("item:", 1, true) then itemString = nil end



    local itemID = get("itemID")
    local fromID = itemID and itemID:match("^%d+$") and itemID ~= "0"
        and ("item:" .. itemID) or nil


    local flag = get("isAwardReason")
    local isAwardReason = flag == "true" or flag == "1"

    return Normalise(source, Recase(winner), {
        id = sourceID,
        lootWon = UnescapeLink(intact) or UnescapeLink(itemString) or fromID or itemColumn,

        itemName = itemColumn and (itemColumn:match("|h%[(.-)%]|h")
            or itemColumn:match("^%[(.+)%]$") or itemColumn),
        date = get("date"),
        time = get("time"),
        response = get("response"),
        responseID = tonumber(get("responseID")),
        isAwardReason = isAwardReason,
        votes = tonumber(get("votes")),
        class = get("class"),
        instance = get("instance"),
        boss = get("boss"),
        difficultyID = tonumber(get("difficultyID")),
        mapID = tonumber(get("mapID")),
        groupSize = tonumber(get("groupSize")),
        note = get("note"),
        owner = get("owner"),
    })
end







function Import:PrepareCSV(text)
    if type(text) ~= "string" or text == "" then
        return nil, T["nothing to import"]
    end


    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")


    text = text:gsub("^\239\187\191", "")


    local lines, comments, seenHeader = {}, {}, false
    for line in text:gmatch("([^\n]*)\n?") do
        if line ~= "" then
            if not seenHeader and line:match("^%s*#") then
                comments[#comments + 1] = line
            else
                seenHeader = true
                lines[#lines + 1] = line
            end
        end
    end

    local declared = lines[1] and lines[1]:match("^sep=(.)$")
    if declared then table.remove(lines, 1) end
    if #lines < 2 then return nil, T["no rows found below the header"] end



    local header = lines[1]

    if not declared and not header:find("[,;\t]") then
        return nil, T["no commas or semicolons in the header - a paste loses tabs, so export with commas or semicolons"]
    end
    local delim = declared
        or (header:find("\t", 1, true) and "\t")
        or (header:find(";", 1, true) and not header:find(",", 1, true) and ";")
        or ","

    local columns, format, err = MapHeader(lines[1], delim, comments)
    if not columns then
        return nil, addon.Locale.Format(
            T["%s - paste an export from a supported loot addon or from this addon"],
            err or T["unrecognised header"])
    end

    addon.db.imported = addon.db.imported or {}

    local stats = NewStats()
    stats.badRows = 0
    stats.format = format

    return {
        lines = lines,
        columns = columns,
        format = format,
        delim = delim,
        stats = stats,
        cutoff = Cutoff(),
        next = 2,

        headerFirst = ParseLine(lines[1], delim)[1],
    }
end


function Import:StepCSV(job, budget)
    local last = math.min(#job.lines, job.next + (budget or #job.lines) - 1)

    for index = job.next, last do
        local line = job.lines[index]



        if line:match("^%s*#") then

        else
            local fields = ParseLine(line, job.delim)

            local function get(name)
                local at = job.columns[name]
                local value = at and fields[at]
                if Blank(value) then return nil end
                return value
            end



            if fields[1] ~= job.headerFirst then
                job.stats.scanned = job.stats.scanned + 1


                local entry, counted
                if job.format == "slc" then
                    entry = NormaliseSLC(get)

                    if entry and entry.nativeID
                        and ((addon.db.history or {})[entry.nativeID]
                            or addon.History:IsArchived("history", entry.nativeID)) then
                        entry, counted = nil, true
                        job.stats.duplicate = job.stats.duplicate + 1
                    end
                else
                    entry = NormaliseForeign(job.format, get)
                end

                if entry then
                    Store(entry, job.cutoff, job.stats, true)
                elseif not counted then
                    job.stats.badRows = job.stats.badRows + 1
                end
            end
        end
    end

    job.next = last + 1
    return job.next > #job.lines
end

function Import:FinishCSV(job)
    addon.History.ReviveDone()
    if job.stats.imported > 0 then
        addon.History:Reindex()
        addon.History:ScheduleSweep()
    end
    addon.Log:I("Import", "CSV:", job.format, job.stats.imported, "imported,",
        job.stats.duplicate, "already held,", job.stats.tooOld,
        "outside the window,", job.stats.badRows, "unreadable")
    return job.stats
end


function Import:FromCSV(text)
    local job, err = Import:PrepareCSV(text)
    if not job then return nil, err end

    Import:StepCSV(job)
    return Import:FinishCSV(job)
end



local ROWS_PER_FRAME = 250

function Import:BeginCSV(text, onProgress, onDone)
    local job, err = Import:PrepareCSV(text)
    if not job then return nil, err end

    local cancelled, total = false, #job.lines - 1
    local ticker

    ticker = C_Timer.NewTicker(0, function()
        if cancelled then
            ticker:Cancel()
            return
        end

        local done = Import:StepCSV(job, ROWS_PER_FRAME)
        if onProgress then onProgress(math.min(job.next - 2, total), total) end

        if done then
            ticker:Cancel()
            if onDone then onDone(Import:FinishCSV(job)) end
        end
    end)

    return function()
        cancelled = true
        if ticker then ticker:Cancel() end
        addon.History.ReviveDone()
    end
end







function Import:Describe(stats)
    if not stats then return "" end
    local parts = { addon.Locale.Format(T["%d imported"], stats.imported) }
    if stats.duplicate > 0 then
        parts[#parts + 1] = addon.Locale.Format(T["%d already held"], stats.duplicate)
    end
    if stats.tooOld > 0 then
        parts[#parts + 1] = addon.Locale.Format(T["%d older than %d days"], stats.tooOld,
            addon.db.importMaxDays or 0)
    end
    if (stats.badRows or 0) > 0 then
        parts[#parts + 1] = addon.Locale.Format(T["%d unreadable"], stats.badRows)
    end
    if stats.malformed > 0 then
        parts[#parts + 1] = addon.Locale.Format(T["%d malformed"], stats.malformed)
    end
    return table.concat(parts, ", ")
end
