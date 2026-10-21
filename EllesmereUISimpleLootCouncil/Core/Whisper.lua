if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Whisper = {}
addon.Whisper = Whisper

local IsSecret = addon.IsSecret







local RESERVED = {
    help     = "help",
    commands = "help",
    keys     = "help",
    ["?"]    = "help",
    pass     = "pass",
}



Whisper.RESERVED_ALIASES = {}



local BUILTIN_WORDS = {
    MAINSPEC = "mainspec",
    OFFSPEC  = "offspec",
    TRANSMOG = "transmog",
}



local function IsWidePunctuation(code)
    return code == 0xA0 or code == 0xA1 or code == 0xAB or code == 0xB7
        or code == 0xBB or code == 0xBF
        or (code >= 0x2000 and code <= 0x206F)
        or (code >= 0x3000 and code <= 0x3004)
        or (code >= 0x3008 and code <= 0x3020) or code == 0x3030
        or (code >= 0xFF01 and code <= 0xFF0F) or (code >= 0xFF1A and code <= 0xFF20)
        or (code >= 0xFF3B and code <= 0xFF40) or (code >= 0xFF5B and code <= 0xFF65)
end


local function CodePoint(char)
    local a, b, c, d = char:byte(1, 4)
    if #char == 1 then return a end
    if #char == 2 and b then return (a - 0xC0) * 64 + (b - 0x80) end
    if #char == 3 and c then return (a - 0xE0) * 4096 + (b - 0x80) * 64 + (c - 0x80) end
    if #char == 4 and d then
        return (a - 0xF0) * 262144 + (b - 0x80) * 4096 + (c - 0x80) * 64 + (d - 0x80)
    end
    return nil
end



local function Normalise(word)
    if type(word) ~= "string" then return "" end
    local out = {}
    for char in addon.Locale.Fold(word):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if #char == 1 then
            if char == "?" or not char:find("[%s%p]") then out[#out + 1] = char end
        else
            local code = CodePoint(char)
            if code == 0xFF1F then
                out[#out + 1] = "?"
            elseif code and not IsWidePunctuation(code) then
                out[#out + 1] = char
            end
        end
    end
    return table.concat(out)
end
Whisper.Normalise = Normalise



local function AliasesFor(response)
    local out, seen = {}, {}

    local function add(word)
        word = Normalise(word)
        if word ~= "" and not seen[word] then
            seen[word] = true
            out[#out + 1] = word
        end
    end



    for alias in tostring(response.whisper or ""):gmatch("[^,/%s]+") do
        add(alias)
    end

    local text = tostring(response.text or "")
    add(text)
    add(text:match("^%s*(%S+)"))

    add(BUILTIN_WORDS[response.id])

    return out
end
Whisper.AliasesFor = AliasesFor



function Whisper.BuildKeys(responses, reservedAliases)
    local map = {}
    for word, meaning in pairs(RESERVED) do map[word] = meaning end
    if reservedAliases == nil then
        reservedAliases = Whisper.RESERVED_ALIASES[GetLocale and GetLocale() or ""]
    end

    for word, meaning in pairs(reservedAliases or {}) do
        local key = Normalise(word)
        if key ~= "" and map[key] == nil
            and (meaning == "help" or meaning == "pass") then
            map[key] = meaning
        end
    end

    for index, response in ipairs(responses or {}) do
        for _, alias in ipairs(AliasesFor(response)) do

            if map[alias] == nil then map[alias] = index end
        end
    end

    return map
end






local STRIP = {
    "|H.-|h.-|h",
    "|c%x%x%x%x%x%x%x%x",
    "|cn[^:|]*:",
    "|r",
    "|T.-|t",
    "|A.-|a",
}





function Whisper.Parse(text, keys)
    if type(text) ~= "string" or type(keys) ~= "table" then return nil end



    local items = {}
    for itemString in text:gmatch("|H(item:[^|]*)|h") do
        items[#items + 1] = itemString
    end



    local bare = text
    for _, pattern in ipairs(STRIP) do
        bare = bare:gsub(pattern, " ")
    end

    bare = bare:gsub("\227\128\128", " "):gsub("\194\160", " ")

    bare = bare:gsub("\239\188\140", " ")
        :gsub("\227\128\130", " ")
        :gsub("\227\128\129", " ")
        :gsub("\239\188\154", " ")
        :gsub("\239\188\155", " ")
        :gsub("\239\188\129", " ")

    local words = {}
    for word in bare:gmatch("%S+") do words[#words + 1] = word end

    if #words == 0 and #items == 0 then return nil end



    local at, session, hashed = 1, nil, false
    local hash, leading = (words[1] or ""):match("^(#?)(%d+)$")
    if leading then
        session = tonumber(leading)
        hashed = hash == "#"
        at = 2
    end



    local link, gearFrom = nil, 1
    if not session and items[1] then
        link = items[1]
        gearFrom = 2
    end

    local keyword = words[at]
    local hit = nil
    if keyword then hit = keys[Normalise(keyword)] end

    if hit == "help" then
        return { kind = "help" }
    end

    if hit == nil then

        if not (link or session) then return nil end

        local quiet = keyword ~= nil and not hashed and #items == 0

        return { kind = "unknown", word = keyword and keyword:gsub("|", ""), link = link,
                 session = session, quiet = quiet }
    end

    local note = nil
    if #words > at then note = table.concat(words, " ", at + 1) end

    local gear = {}
    for i = gearFrom, #items do gear[#gear + 1] = items[i] end

    return {
        kind = "answer",
        session = session,
        link = link,


        response = (hit ~= "pass") and hit or nil,
        pass = hit == "pass",
        note = note,
        gear = gear,
    }
end







local outbox = {}
local ticker
local SPACING = 0.7
local lastSent = 0

local function Pump()
    local entry = table.remove(outbox, 1)
    if not entry then
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        return
    end

    C_ChatInfo.SendChatMessage(entry.text, "WHISPER", nil, addon.Player:WhisperTarget(entry.to))
    lastSent = GetTime()
end




local OUTBOX_MAX = 40

local function Say(to, lines, help)
    if not to then return end
    if type(lines) == "string" then lines = { lines } end

    if help then
        for _, queued in ipairs(outbox) do
            if queued.help and queued.to == to then
                addon.Log:D("Whisper", "guide already queued for", to)
                return
            end
        end
    end

    for _, line in ipairs(lines) do
        if line and line ~= "" then
            if #outbox >= OUTBOX_MAX then
                addon.Log:D("Whisper", "outbox full, dropping a reply to", to)
                break
            end
            outbox[#outbox + 1] = { to = to, text = line, help = help }
        end
    end

    if not ticker and (GetTime() - lastSent) >= SPACING then Pump() end
    if #outbox > 0 and not ticker then
        ticker = C_Timer.NewTicker(SPACING, Pump)
    end
end


local repliedAt = {}
local REPLY_COOLDOWN = 1.5

local function CanReply(who)
    local now = GetTime()
    if now - (repliedAt[who] or 0) < REPLY_COOLDOWN then
        addon.Log:D("Whisper", "reply suppressed by cooldown for", who)
        return false
    end
    repliedAt[who] = now
    return true
end







local LINE_MAX = 240



local function Wrap(prefix, parts, separator, out)
    local line, empty = prefix, true

    for _, part in ipairs(parts) do
        local candidate = empty and (line .. part) or (line .. separator .. part)
        if #candidate > LINE_MAX and not empty then
            out[#out + 1] = line
            line = part
        else
            line = candidate
        end
        empty = false
    end

    if not empty then out[#out + 1] = line end
end


local MAX_LISTED_ITEMS = 6



function Whisper:HelpLines()
    local responses = addon.Config:Responses()
    local keys = Whisper.BuildKeys(responses)

    local lines = {

        "SimpleLootCouncil: " .. T["whisper me your answer for an item."],
        T["Format: <item number or link> <keyword> <optional note>"],
    }


    local labels = {}
    for index, response in ipairs(responses) do
        local mine = {}
        for _, alias in ipairs(AliasesFor(response)) do
            if keys[alias] == index then mine[#mine + 1] = alias end
        end
        if #mine > 0 then
            labels[#labels + 1] = addon.Locale.Format(T["%s = %s"], response.text,
                table.concat(mine, T[" or "]))
        end
    end
    labels[#labels + 1] = T["or pass"]
    Wrap(addon.Locale.SectionTitle(T["Keywords"]) .. " ", labels, ", ", lines)

    local items = addon.Session:GetItems()
    if addon.Session:IsRunning() and #items > 0 then
        local shown = math.min(#items, MAX_LISTED_ITEMS)
        for index = 1, shown do
            local item = items[index]


            local text = item.removed and T["%d: %s (removed)"]
                or item.awarded and T["%d: %s (awarded)"] or T["%d: %s"]
            lines[#lines + 1] = addon.Locale.Format(text, index, item.link or "?")
        end
        if #items > shown then
            lines[#lines + 1] = addon.Locale.Format(T["...and %d more."], #items - shown)
        end
        local open = 0
        for _, item in ipairs(items) do
            if not item.removed then open = open + 1 end
        end
        if open == 1 then
            lines[#lines + 1] = T["Only one item, so the number is optional."]
        end
    else
        lines[#lines + 1] = T["No loot session is running at the moment."]
    end

    lines[#lines + 1] = T["Link your equipped items after the keyword and I will work out the upgrade for the council."]

    return lines
end








local function ResolveSession(parsed, items)

    local open = {}
    for index, item in ipairs(items) do
        if not item.removed then open[#open + 1] = index end
    end
    if #open == 0 then return nil, T["There is nothing up for loot right now."] end


    if parsed.session then
        if not items[parsed.session] then
            return nil, addon.Locale.Format(addon.Locale.Plural{
                one = "There is no item %d in this session - there is %d.",
                other = "There is no item %d in this session - there are %d.",
            }, #items, parsed.session, #items)
        end
        if items[parsed.session].removed then
            return nil, T["That item is not up for loot. Whisper 'help' for the list."]
        end
        return parsed.session
    end

    if parsed.link then
        local matches = {}
        for _, index in ipairs(open) do
            if addon.Storage.ItemsMatch(items[index].link, parsed.link) then
                matches[#matches + 1] = index
            end
        end


        if #matches == 0 then
            local wanted = addon.Storage.ItemID(parsed.link)
            if wanted then
                for _, index in ipairs(open) do
                    if addon.Storage.ItemID(items[index].link) == wanted then
                        matches[#matches + 1] = index
                    end
                end
            end
        end

        if #matches == 1 then return matches[1] end
        if #matches == 0 then
            return nil, T["That item is not up for loot. Whisper 'help' for the list."]
        end
        return nil, addon.Locale.Format(T["There are %d of those up - whisper the number instead. 'help' lists them."], #matches)
    end

    if #open == 1 then return open[1] end

    return nil, addon.Locale.Format(T["There are %d items up - start with the item number. 'help' lists them."], #open)
end
Whisper.ResolveSession = ResolveSession







local function GearFromLinks(itemLink, links)
    if not links or #links == 0 then return nil end

    local g1, g2 = links[1], links[2]
    local diff = addon.Gear and addon.Gear:Diff(itemLink, g1, g2) or nil

    return { g1 = g1, g2 = g2, d = diff }
end





local function ResponseLabel(parsed)
    if parsed.pass then return T["Pass"] end
    local response = addon.Config:Responses()[parsed.response]
    return response and response.text or "?"
end

local function Handle(text, sender)
    if not addon.db or not addon.db.whispers or not addon.db.whispers.enabled then
        return
    end



    if not IsInGroup() or not addon.PlayerIsMasterLooter() then return end


    if IsSecret(text, sender) then
        addon.Log:D("Whisper", "ignoring a whisper under chat lockdown")
        return
    end

    local who = addon.Player:Get(sender).fullName
    if not who then return end



    if addon.Player:IsSelf(who) then return end


    if not addon.GetCandidates()[who] then return end

    local parsed = Whisper.Parse(text, Whisper.BuildKeys(addon.Config:Responses()))
    if not parsed then return end

    if parsed.kind == "help" then
        if CanReply(who) then Say(who, Whisper:HelpLines(), true) end
        return
    end

    if parsed.quiet then
        addon.Log:D("Whisper", "bare number and unknown word from", who, "- read as chat")
        return
    end


    if not addon.Session:IsRunning() then
        if (parsed.link or parsed.session) and CanReply(who) then
            Say(who, T["No loot session is running. I have not recorded that."])
        end
        return
    end

    if parsed.kind == "unknown" then
        if CanReply(who) then


            Say(who, parsed.word
                and addon.Locale.Format(T["I did not recognise '%s'. Whisper 'help' for the keywords."],
                    tostring(parsed.word))
                or T["Add a keyword after the item. Whisper 'help' for the keywords."])
        end
        return
    end

    local session, refusal = ResolveSession(parsed, addon.Session:GetItems())
    if not session then
        if CanReply(who) then Say(who, refusal) end
        return
    end

    local item = addon.Session:GetItem(session)
    local note = parsed.note
    note = addon.Locale.Truncate(note, addon.Config:NoteMax())

    local gear = GearFromLinks(item and item.link, parsed.gear)

    addon.Log:I("Whisper", "answer from", who, "session", session,
        parsed.pass and "pass" or ("response " .. tostring(parsed.response)))


    addon.Comms:Send("whisper", {
        s = session, c = who, r = parsed.response, n = note, g = gear,
    }, nil, true)
    addon.Session:ApplyWhisperResponse(session, who, parsed.response, note,
        addon.Player:GetFullName("player"), gear)

    if CanReply(who) then
        local target = (item and item.link)
            or addon.Locale.Format(T["item %d"], session)
        Say(who, note
            and addon.Locale.Format(T["Recorded: %s on %s - %s"], ResponseLabel(parsed),
                target, note)
            or addon.Locale.Format(T["Recorded: %s on %s"], ResponseLabel(parsed), target))
    end
end


function Whisper:Describe(text)
    local keys = Whisper.BuildKeys(addon.Config:Responses())
    local parsed = Whisper.Parse(text, keys)

    if not parsed then
        return { T["ignored - not an attempt at a command, so no reply is sent."] }
    end

    if parsed.kind == "help" then
        local lines = { T["would whisper back the guide:"] }
        for _, line in ipairs(Whisper:HelpLines()) do
            lines[#lines + 1] = "    " .. line
        end
        return lines
    end

    if parsed.quiet then
        return { addon.Locale.Format(T["a bare number then '%s' reads as chat - silent. '#N' or a link would get a reply."],
            tostring(parsed.word)) }
    end

    if not addon.Session:IsRunning() then
        if parsed.link or parsed.session then
            return { T["no run is active - would reply that nothing was recorded."] }
        end
        return { T["no run is active, and no item was named - silent."] }
    end

    if parsed.kind == "unknown" then

        return { parsed.word
            and addon.Locale.Format(T["keyword '%s' not recognised - would reply pointing at 'help'."],
                tostring(parsed.word))
            or T["no keyword after the item - would reply asking for one."] }
    end

    local session, refusal = ResolveSession(parsed, addon.Session:GetItems())
    if not session then
        return { addon.Locale.Format(T["would refuse: %s"], tostring(refusal)) }
    end

    local item = addon.Session:GetItem(session)
    return {
        addon.Locale.Format(T["would record %s on session %d (%s)"],
            ResponseLabel(parsed), session, tostring(item and item.link or "?")),
        addon.Locale.Format(T["note: %s"], tostring(parsed.note or "-")),
        addon.Locale.Format(T["gear links read: %d"], #parsed.gear),
    }
end





function Whisper:Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_WHISPER")

    f:SetScript("OnEvent", function(_, _, text, sender)
        local ok, err = pcall(Handle, text, sender)
        if not ok then addon.Log:Bug("Whisper", tostring(err)) end
    end)

    addon.Log:I("Whisper", "ready",
        addon.db.whispers.enabled and "accepting whispers" or "disabled")
end
