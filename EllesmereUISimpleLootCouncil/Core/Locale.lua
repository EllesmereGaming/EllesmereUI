if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Locale = {}
addon.Locale = Locale

local clientLocale = "enUS"
if type(GetLocale) == "function" then
    local value = GetLocale()
    if type(value) == "string" then clientLocale = value end
end
Locale.clientLocale = clientLocale

local registered = {}
local pseudo = false


local handedOut = {}
local pluralsOut = setmetatable({}, { __mode = "k" })
Locale.rejected = {}
Locale.Text = setmetatable({}, {
    __index = function(_, key)
        if pseudo then return "\194\171" .. key .. "\194\187" end
        local text = registered[key] or key
        handedOut[text] = true
        return text
    end,
})



local textTables = {}
local wrappedTables = setmetatable({}, { __mode = "k" })
local PREFIXED = "^(|c%x%x%x%x%x%x%x%xSimpleLootCouncil:|r )(.+)$"

local function WrapText(value)
    if handedOut[value] then return "\194\171" .. value .. "\194\187" end
    local prefix, rest = value:match(PREFIXED)
    if prefix and handedOut[rest] then return prefix .. "\194\171" .. rest .. "\194\187" end
    return value
end

local function WrapTable(t)
    if wrappedTables[t] then return end
    wrappedTables[t] = true
    for key, value in pairs(t) do
        if type(value) == "string" then
            t[key] = WrapText(value)


        elseif type(value) == "table" and not wrappedTables[value] then
            if pluralsOut[value] then
                wrappedTables[value] = true
                for form, text in pairs(value) do
                    if type(text) == "string" then value[form] = "\194\171" .. text .. "\194\187" end
                end
            else
                WrapTable(value)
            end
        end
    end
end

function Locale.Texts(t)
    textTables[#textTables + 1] = t
    if pseudo then WrapTable(t) end
    return t
end



function Locale.Pseudo(on)
    pseudo = not not on
    local db = SimpleLootCouncil.db
    if type(db) == "table" then db.pseudoLocale = pseudo or nil end


    if pseudo then
        for _, t in ipairs(textTables) do WrapTable(t) end
    end
end

function Locale.IsPseudo()
    return pseudo
end



local function Slots(message)
    local slots, position = {}, 1
    while true do
        local start = message:find("%", position, true)
        if not start then return slots end
        if message:sub(start + 1, start + 1) == "%" then
            position = start + 2
        else
            local tail = message:sub(start + 1)
            local index = tail:match("^(%d+)%$")
            local cursor = start + 1
            if index then cursor = cursor + #index + 1 end
            local flags = message:sub(cursor):match("^[%-%+ #0]*") or ""
            cursor = cursor + #flags
            local width = message:sub(cursor):match("^%d*") or ""
            cursor = cursor + #width
            if message:sub(cursor, cursor) == "." then
                local precision = message:sub(cursor + 1):match("^%d+")
                if not precision then return nil, "invalid format slot" end
                cursor = cursor + #precision + 1
            end
            local conversion = message:sub(cursor, cursor)
            if not conversion:match("^[cdiouxXeEfgGqs]$") then
                return nil, "invalid format slot"
            end
            slots[#slots + 1] = {
                first = start, last = cursor, index = index and tonumber(index),
                conversion = conversion,
                plain = "%" .. message:sub(start + 1 + (index and #index + 1 or 0), cursor),
            }
            position = cursor + 1
        end
    end
end

local function Escapes(message)
    local tokens, position = {}, 1
    while true do
        local start = message:find("|", position, true)
        if not start then break end
        local tail = message:sub(start)
        local token = tail:match("^|c%x%x%x%x%x%x%x%x")
            or tail:match("^|[rn]")
            or tail:match("^|T.-|t")
            or tail:match("^|H.-|h")
            or tail:match("^||")
        if not token then return nil end
        tokens[#tokens + 1] = token
        position = start + #token
    end
    table.sort(tokens)
    return table.concat(tokens, "\n")
end

local function ValidForm(keySlots, keyEscapes, form, plural)
    if type(form) ~= "string" then return false, "translation is not a string" end
    local slots = Slots(form)
    if not slots then return false, "invalid format slot" end
    local escapes = Escapes(form)
    if not escapes or escapes ~= keyEscapes then return false, "escape mismatch" end
    local positional = false
    for _, slot in ipairs(slots) do
        if slot.index then positional = true end
    end
    if positional then
        for _, slot in ipairs(slots) do
            local original = slot.index and keySlots[slot.index]
            if not original or original.conversion ~= slot.conversion then
                return false, "slot mismatch"
            end
        end
    else
        if #slots > #keySlots or (not plural and #slots ~= #keySlots) then
            return false, "slot mismatch"
        end
        for index, slot in ipairs(slots) do
            if keySlots[index].conversion ~= slot.conversion then
                return false, "slot mismatch"
            end
        end
    end
    return true
end

local function Install(entries)
    if type(entries) ~= "table" then return end
    for key, value in pairs(entries) do
        local reason
        if type(key) ~= "string" then
            reason = "key is not a string"
        else
            local keySlots = Slots(key)
            local keyEscapes = Escapes(key)
            if not keySlots then reason = "invalid key format slot"
            elseif not keyEscapes then reason = "invalid key escape"
            elseif type(value) == "table" then
                if type(value.other) ~= "string" then
                    reason = "plural has no other form"
                else
                    for name, form in pairs(value) do
                        if name ~= "one" and name ~= "few" and name ~= "many"
                            and name ~= "other" then
                            reason = "unknown plural form"
                            break
                        end
                        local ok, why = ValidForm(keySlots, keyEscapes, form, true)
                        if not ok then reason = why; break end
                    end
                end
            else
                local ok, why = ValidForm(keySlots, keyEscapes, value, false)
                if not ok then reason = why end
            end
        end
        if reason then
            Locale.rejected[#Locale.rejected + 1] = {
                key = key, reason = reason .. " for " .. tostring(key),
            }
        else
            registered[key] = value
        end
    end
end

function Locale.Register(locale, entries)
    if locale == clientLocale then Install(entries) end
end


function Locale.RegisterShared(entries)
    Install(entries)
end

function Locale.Plural(forms)
    if type(forms) ~= "table" or type(forms.other) ~= "string" then return forms end
    local translated = registered[forms.other]
    local selected = type(translated) == "table" and translated or forms
    if not pseudo then
        pluralsOut[selected] = true
        return selected
    end
    local wrapped = {}
    for name, form in pairs(selected) do
        if type(form) == "string" then wrapped[name] = "\194\171" .. form .. "\194\187" end
    end
    return wrapped
end




local function PluralForm(count)
    count = tonumber(count)
    if not count or count ~= count or math.abs(count) == math.huge then return "other" end
    count = math.abs(count)

    if clientLocale == "ruRU" and count == math.floor(count) then
        local mod10, mod100 = count % 10, count % 100
        if mod10 == 1 and mod100 ~= 11 then return "one" end
        if mod10 >= 2 and mod10 <= 4
            and (mod100 < 12 or mod100 > 14) then
            return "few"
        end
        return "many"
    end

    if clientLocale == "frFR" or clientLocale == "ptBR" then
        if count < 2 then return "one" end
    end

    if clientLocale == "frFR" or clientLocale == "ptBR"
        or clientLocale == "itIT" or clientLocale == "esES" or clientLocale == "esMX" then
        if count ~= 0 and count % 1000000 == 0 then return "many" end
    end

    if clientLocale == "koKR" or clientLocale == "zhCN"
        or clientLocale == "zhTW" then
        return "other"
    end

    return count == 1 and "one" or "other"
end
Locale.PluralForm = PluralForm



local function FormatString(format, ...)
    if not format:find("%%%d+%$") then return format:format(...) end
    local slots = Slots(format)
    if not slots then return format:format(...) end
    local pieces, values, last = {}, {}, 1
    for index, slot in ipairs(slots) do
        pieces[#pieces + 1] = format:sub(last, slot.first - 1)
        pieces[#pieces + 1] = slot.plain
        local from = slot.index or index
        values[index] = from >= 1 and (select(from, ...)) or nil
        last = slot.last + 1
    end
    pieces[#pieces + 1] = format:sub(last)
    return string.format(table.concat(pieces), unpack(values, 1, #slots))
end





function Locale.Format(message, ...)
    if type(message) == "table" then
        local form = PluralForm(select(1, ...))
        message = message[form] or message.other or message.one
        if type(message) ~= "string" then return "" end
        return FormatString(message, select(2, ...))
    end
    if type(message) ~= "string" then return "" end
    return FormatString(message, ...)
end



function Locale.SectionTitle(title)
    title = tostring(title or "")
    if title:find("[:?!.]%s*$") or title:find("\239\188\154%s*$")
        or title:find("\239\188\159%s*$") or title:find("\239\188\129%s*$") or title:find("\227\128\130%s*$") then
        return title
    end
    local suffix = clientLocale == "frFR" and " :"
        or (clientLocale == "zhCN" or clientLocale == "zhTW") and "\239\188\154" or ":"
    return title .. suffix
end



local function Decode(text, position)
    local a, b, c, d = text:byte(position, position + 3)
    if a < 0x80 then return a, position + 1 end
    local function continuation(value)
        return value and value >= 0x80 and value <= 0xBF
    end
    if a >= 0xC2 and a <= 0xDF and continuation(b) then
        return (a - 0xC0) * 64 + b - 0x80, position + 2
    end
    if a >= 0xE0 and a <= 0xEF and continuation(b) and continuation(c)
        and (a ~= 0xE0 or b >= 0xA0) and (a ~= 0xED or b < 0xA0) then
        return (a - 0xE0) * 4096 + (b - 0x80) * 64 + c - 0x80, position + 3
    end
    if a >= 0xF0 and a <= 0xF4 and continuation(b) and continuation(c)
        and continuation(d) and (a ~= 0xF0 or b >= 0x90)
        and (a ~= 0xF4 or b < 0x90) then
        return (a - 0xF0) * 262144 + (b - 0x80) * 4096
            + (c - 0x80) * 64 + d - 0x80, position + 4
    end
end

local function Encode(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then
        return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
    end
    if code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 4096),
            0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
    end
    return string.char(0xF0 + math.floor(code / 262144),
        0x80 + math.floor(code / 4096) % 64,
        0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end



local lower, upper = {}, {}
local function Pair(capital, small)
    lower[capital], upper[small] = small, capital
end
for code = 0x41, 0x5A do Pair(code, code + 32) end
for code = 0xC0, 0xDE do
    if code ~= 0xD7 then Pair(code, code + 32) end
end
for code = 0x100, 0x12E, 2 do Pair(code, code + 1) end
for code = 0x132, 0x136, 2 do Pair(code, code + 1) end
for code = 0x139, 0x147, 2 do Pair(code, code + 1) end
for code = 0x14A, 0x176, 2 do Pair(code, code + 1) end
for code = 0x179, 0x17D, 2 do Pair(code, code + 1) end
Pair(0x178, 0xFF)
for code = 0x400, 0x40F do Pair(code, code + 80) end
for code = 0x410, 0x42F do Pair(code, code + 32) end
for code = 0x460, 0x480, 2 do Pair(code, code + 1) end
for code = 0x48A, 0x4BE, 2 do Pair(code, code + 1) end
for code = 0x4C1, 0x4CD, 2 do Pair(code, code + 1) end
for code = 0x4D0, 0x4FE, 2 do Pair(code, code + 1) end
Pair(0x4C0, 0x4CF)
lower[0x130] = "i\204\135"
lower[0x1E9E] = 0xDF
upper[0xDF], upper[0x131], upper[0x17F] = "SS", 0x49, 0x53
upper[0x149], upper[0xB5] = "\202\188N", 0x39C

local function Case(text, mapping, fold)
    if type(text) ~= "string" then return text end
    if not text:find("[\128-\255]") then
        return mapping == upper and text:upper() or text:lower()
    end
    local result, position = {}, 1
    while position <= #text do
        local code, nextPosition = Decode(text, position)
        if not code then return text end
        local replacement = mapping[code]
        if fold then
            if code == 0xDF or code == 0x1E9E then replacement = "ss"
            elseif code == 0x17F then replacement = 0x73
            elseif code == 0x149 then replacement = "\202\188n"
            elseif code == 0xB5 then replacement = 0x3BC end
        end
        result[#result + 1] = type(replacement) == "string" and replacement
            or Encode(replacement or code)
        position = nextPosition
    end
    return table.concat(result)
end

function Locale.Lower(text) return Case(text, lower) end
function Locale.Fold(text) return Case(text, lower, true) end
function Locale.Upper(text) return Case(text, upper) end




local function UTF8End(text, maxLetters)
    local byteCount, position, letters = #text, 1, 0
    while position <= byteCount and letters < maxLetters do
        local lead = text:byte(position)
        local width = lead < 0x80 and 1
            or (lead >= 0xC2 and lead <= 0xDF) and 2
            or (lead >= 0xE0 and lead <= 0xEF) and 3
            or (lead >= 0xF0 and lead <= 0xF4) and 4
            or 1

        if position + width - 1 > byteCount then
            width = 1
        else
            for offset = 1, width - 1 do
                local continuation = text:byte(position + offset)
                if continuation < 0x80 or continuation > 0xBF then
                    width = 1
                    break
                end
            end
        end
        position = position + width
        letters = letters + 1
    end
    return position
end




function Locale.Truncate(text, maxLetters)
    if type(text) ~= "string" or type(maxLetters) ~= "number" then return text end
    maxLetters = math.max(0, math.floor(maxLetters))

    if type(strlenutf8) == "function" and strlenutf8(text) <= maxLetters then
        return text
    end

    local finish = UTF8End(text, maxLetters)
    if finish > #text then return text end
    return text:sub(1, finish - 1)
end


local function Letters(text)
    return #(text:gsub("[\128-\191]", ""))
end

local function IsCJK(code)
    return code and ((code >= 0x3400 and code <= 0x9FFF)
        or (code >= 0xF900 and code <= 0xFAFF)
        or (code >= 0x20000 and code <= 0x323AF)
        or (code >= 0x3040 and code <= 0x30FF)
        or (code >= 0xAC00 and code <= 0xD7AF))
end


local function WrapParts(word)
    local parts, start, position, previousCJK = {}, 1, 1, false
    while position <= #word do
        local code, nextPosition = Decode(word, position)
        if not code then return { word } end
        local cjk = IsCJK(code)
        if position > start and (cjk or previousCJK) then
            parts[#parts + 1] = word:sub(start, position - 1)
            start = position
        end
        previousCJK, position = cjk, nextPosition
    end
    parts[#parts + 1] = word:sub(start)
    return parts
end



function Locale.Wrap(text, width)
    local lines = {}
    if type(text) ~= "string" then return lines end
    width = math.max(1, math.floor(tonumber(width) or 1))
    text = text:gsub("%s+$", "")

    for paragraph in (text .. "\n"):gmatch("([^\n]*)\n") do
        local line, lineLetters
        for word in paragraph:gmatch("%S+") do
            for index, part in ipairs(WrapParts(word)) do
                local separator = index == 1 and " " or ""
                local letters = Letters(part)
                if line and lineLetters + #separator + letters <= width then
                    line = line .. separator .. part
                    lineLetters = lineLetters + #separator + letters
                else
                    if line then lines[#lines + 1] = line end
                    line, lineLetters = part, letters
                end
            end
        end
        lines[#lines + 1] = line or ""
    end
    return lines
end
