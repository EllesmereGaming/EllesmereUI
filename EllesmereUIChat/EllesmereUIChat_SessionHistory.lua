-------------------------------------------------------------------------------
--  EllesmereUIChat_SessionHistory.lua
--
--  Persists recent player chat across /reload and relog. Saves on CHAT_MSG
--  in open world only (instances cannot provide storable text). Stores message
--  body plus serverTime/timestamp; restore prepends timestamp from that format.
-------------------------------------------------------------------------------
-- Chat session history disabled for now
do return end

local _, ns = ...
local ECHAT = ns.ECHAT
if not ECHAT then return end

local strsub = string.sub
local gsub = string.gsub
local format = string.format
local strupper = string.upper
local wipe = wipe
local GetTime = GetTime
local GetServerTime = GetServerTime
local pcall = pcall
local date = date

local SV_NAME = "EllesmereUIChatScrollDB"
local MAX_TEXT_LEN = 4096
local RESTORE_DELAY_SEC = 2.0
local RESTORE_RETRY_SEC = 2.0
local RESTORE_MAX_ATTEMPTS = 3
-- Capture starts RESTORE_DELAY + this many seconds after login/reload (avoids login spam).
local SESSION_EPOCH_DELAY_SEC = 3.0

local chatEventsInstalled = false
local restoreToken = 0
local restoredFrames = {}
local sessionEpochTime = nil
local captureSeq = 0

local eventFrame = CreateFrame("Frame")
local deferFrame = CreateFrame("Frame")
local UnarmDeferredRestore

-- Capture in open world only (CaptureAllowed); instance chat still not storable.
local CAPTURE_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
}

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function PersistEnabled()
    if not ECHAT.DB then return false end
    local db = ECHAT.DB()
    if not db then return false end
    return db.persistChatHistory == true
end

local function SessionHistorySafe()
    if not PersistEnabled() then return false end
    if EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance() then return false end
    if GetCVarBool and GetCVarBool("addonChatRestrictionsForced") then return false end
    return true
end

local function InOpenWorld()
    -- Housing plots register as "scenario" but chat is unrestricted there
    if C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then
        return true
    end
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return true end
    return instanceType == "none" or instanceType == ""
end

local function CaptureAllowed()
    if not PersistEnabled() then return false end
    if GetCVarBool and GetCVarBool("addonChatRestrictionsForced") then return false end
    if not InOpenWorld() then return false end
    return true
end

local function MaxLines()
    local maxN = 100
    if ECHAT.DB then
        local db = ECHAT.DB()
        if db and db.persistChatHistoryMaxLines then
            maxN = db.persistChatHistoryMaxLines
        end
    end
    if maxN < 10 then maxN = 10 end
    if maxN > 500 then maxN = 500 end
    return maxN
end

local function MarkSessionEpoch()
    sessionEpochTime = GetTime()
end

local function IsCombatLogChatFrame(cf)
    if not cf then return false end
    local combat = _G.COMBATLOG
    if combat and cf == combat then return true end
    local fn = _G.IsCombatLog
    if type(fn) == "function" then
        local ok, r = pcall(fn, cf)
        if ok and r then return true end
    end
    return false
end

local function ShouldTrackFrame(cf)
    if not cf or not cf.GetName then return false end
    if cf.isTemporary then return false end
    local name = cf:GetName()
    if not name or not name:match("^ChatFrame%d+$") then return false end
    return not IsCombatLogChatFrame(cf)
end

local function GetSV()
    local sv = _G[SV_NAME]
    if type(sv) ~= "table" then
        sv = { sessionLog = {} }
        _G[SV_NAME] = sv
    end
    if type(sv.sessionLog) ~= "table" then
        sv.sessionLog = {}
    end
    if sv.byFrame then
        sv.byFrame = nil
    end
    return sv
end

local function IsValidMessage(msg)
    if msg == nil then return false end
    if issecretvalue and issecretvalue(msg) then return false end
    local ok, valid = pcall(function()
        return type(msg) == "string" and msg ~= ""
    end)
    return ok and valid
end

local function MessageForStorage(msg)
    if not IsValidMessage(msg) then return nil end
    local ok, stored = pcall(function()
        if #msg > MAX_TEXT_LEN then
            return strsub(msg, 1, MAX_TEXT_LEN)
        end
        return msg
    end)
    if ok then return stored end
    return nil
end

-- Strip timestamp text baked into legacy saves (older builds prefixed on store).
-- Matches: "12:34 ...", "12:34:56 ...", "1:23 AM ...", "12:34:56 PM ..."
local function StripLegacyTimestampPrefix(msg)
    if type(msg) ~= "string" then return msg end
    local rest = msg:match("^%d%d?:%d%d:%d%d%s*[AP]M%s+(.+)$")
        or msg:match("^%d%d?:%d%d:%d%d%s+(.+)$")
        or msg:match("^%d%d?:%d%d%s*[AP]M%s+(.+)$")
        or msg:match("^%d%d?:%d%d%s+(.+)$")
    if rest and rest ~= "" then return rest end
    return msg
end

local function MessageBodyOnly(msg)
    return StripLegacyTimestampPrefix(msg)
end

local function TimestampFormatFromDB()
    if not ECHAT.DB then return nil end
    local db = ECHAT.DB()
    local fmt = db and db.timestampFormat
    if fmt == "none" or fmt == "__blizzard" then return nil end
    if type(fmt) == "string" and fmt ~= "" then return fmt end
    return nil
end

local function EffectiveTimestampFormat()
    local fmt = TimestampFormatFromDB()
    if fmt then return fmt end
    if ChatFrameUtil and ChatFrameUtil.GetTimestampFormat then
        local ok, f = pcall(ChatFrameUtil.GetTimestampFormat)
        if ok and f then return f end
    end
    if GetCVar then
        local cvar = GetCVar("showTimestamps")
        if cvar and cvar ~= "" and cvar ~= "none" then return cvar end
    end
    return nil
end

local function FormatTimestampPrefix(serverTime)
    local fmt = EffectiveTimestampFormat()
    if not fmt or not serverTime or not date then return "" end
    local ok, ts = pcall(date, fmt, serverTime)
    if ok and type(ts) == "string" and ts ~= "" then return ts end
    return ""
end

local function IsBNWhisperChatType(chatType)
    return chatType == "BN_WHISPER" or chatType == "BN_WHISPER_INFORM"
end

local function IsWhisperChatType(chatType)
    return chatType == "WHISPER" or chatType == "WHISPER_INFORM"
end

local PLAYER_LINKED_CHAT_TYPES = {
    SAY = true,
    YELL = true,
    PARTY = true,
    PARTY_LEADER = true,
    GUILD = true,
    OFFICER = true,
    RAID = true,
    RAID_LEADER = true,
    RAID_WARNING = true,
    WHISPER = true,
    WHISPER_INFORM = true,
    CHANNEL = true,
}

local function IsPlayerLinkedChatType(chatType)
    return chatType and PLAYER_LINKED_CHAT_TYPES[chatType] or false
end

local function EntryPlayerName(entry)
    if not entry then return nil end
    return MessageForStorage(entry.playerName) or MessageForStorage(entry.whisperPlayerName)
end

local function ChatTypeFromEvent(event)
    if type(event) ~= "string" or strsub(event, 1, 8) ~= "CHAT_MSG" then
        return nil
    end
    return strsub(event, 10)
end

-- messageTypeList uses group names (WHISPER, BN_WHISPER), not *_INFORM variants.
local function ChatTypeGroupFromEvent(event)
    local chatType = ChatTypeFromEvent(event)
    if not chatType then return nil end
    return gsub(chatType, "_INFORM", "")
end

-- Chat frames register message groups (EMOTE, WHISPER), not every CHAT_MSG_* suffix.
local function MessageGroupForEvent(event)
    local inverted = _G.ChatTypeGroupInverted
    if type(inverted) == "table" and inverted[event] then
        return inverted[event]
    end
    return ChatTypeGroupFromEvent(event)
end

local function NormalizeForDedup(msg)
    local text = MessageBodyOnly(msg)
    if not text then return nil end
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

-- Player/BN restore dedupe on chat type + name/id + payload.
local function NormalizeEntryForDedup(entry)
    if type(entry.bnSenderID) == "number" and entry.bnSenderID > 0 then
        local payload = MessageForStorage(entry.rawBody)
        local chatType = entry.event and ChatTypeFromEvent(entry.event)
        if payload and chatType then
            return "bn:" .. chatType .. ":" .. entry.bnSenderID .. ":" .. payload
        end
    end
    local playerName = EntryPlayerName(entry)
    if playerName then
        local payload = MessageForStorage(entry.rawBody)
        local chatType = entry.event and ChatTypeFromEvent(entry.event)
        if payload and chatType then
            return "p:" .. chatType .. ":" .. strupper(playerName) .. ":" .. payload
        end
    end
    return NormalizeForDedup(entry.message)
end

local function OldestFrameTimestamp(cf)
    local oldest
    local buf = cf and cf.historyBuffer
    if buf and type(buf.elements) == "table" then
        for i = 1, #buf.elements do
            local e = buf.elements[i]
            if e and type(e.timestamp) == "number" then
                if not oldest or e.timestamp < oldest then
                    oldest = e.timestamp
                end
            end
        end
    end
    if oldest then return oldest - 0.05 end
    return GetTime() - 1
end

local TrimLinesToMax

TrimLinesToMax = function(lines, maxN)
    local n = #lines
    if n <= maxN then return lines end
    local out = {}
    local start = n - maxN + 1
    for i = start, n do
        out[#out + 1] = lines[i]
    end
    return out
end

local function SortLinesChronological(lines)
    table.sort(lines, function(a, b)
        local ta = a.serverTime or a.timestamp or 0
        local tb = b.serverTime or b.timestamp or 0
        if ta ~= tb then return ta < tb end
        return (a.captureSeq or 0) < (b.captureSeq or 0)
    end)
    return lines
end

local function BuildSanitizedEntry(L, msg)
    return {
        message = msg,
        event = L.event,
        bnSenderID = (type(L.bnSenderID) == "number" and L.bnSenderID) or nil,
        rawBody = MessageForStorage(L.rawBody),
        bnPlayerToken = MessageForStorage(L.bnPlayerToken),
        guid = (type(L.guid) == "string" and L.guid) or nil,
        channelName = MessageForStorage(L.channelName),
        channelBaseName = MessageForStorage(L.channelBaseName),
        zoneChannelID = (type(L.zoneChannelID) == "number" and L.zoneChannelID) or nil,
        channelIndex = (type(L.channelIndex) == "number" and L.channelIndex) or nil,
        playerName = MessageForStorage(L.playerName) or MessageForStorage(L.whisperPlayerName),
        lineID = (type(L.lineID) == "number" and L.lineID) or nil,
        r = (type(L.r) == "number" and L.r) or 1,
        g = (type(L.g) == "number" and L.g) or 1,
        b = (type(L.b) == "number" and L.b) or 1,
        id = (type(L.id) == "number" and L.id) or 1,
        timestamp = (type(L.timestamp) == "number" and L.timestamp) or GetTime(),
        serverTime = (type(L.serverTime) == "number" and L.serverTime) or GetServerTime(),
        captureSeq = (type(L.captureSeq) == "number" and L.captureSeq) or nil,
    }
end

local function SanitizeLineList(lines)
    if type(lines) ~= "table" then return nil end
    local out = {}
    for _, L in ipairs(lines) do
        if type(L) == "table" then
            if L.event == "CHAT_MSG_EMOTE" or L.event == "CHAT_MSG_TEXT_EMOTE" then
                -- Emotes are not persisted.
            else
            local msg = MessageForStorage(L.message)
            if msg then msg = MessageBodyOnly(msg) end
            if msg then
                local evChatType = L.event and gsub(strsub(L.event, 10), "_INFORM", "")
                if evChatType and IsBNWhisperChatType(evChatType) then
                    local hasID = type(L.bnSenderID) == "number" and L.bnSenderID > 0
                    local hasLink = msg:find("|HBNplayer:", 1, true)
                    if not hasID and not hasLink then
                        -- Legacy BN rows baked in wrong plain-text names; drop on load.
                    else
                        out[#out + 1] = BuildSanitizedEntry(L, msg)
                    end
                else
                    out[#out + 1] = BuildSanitizedEntry(L, msg)
                end
            end
            end
        end
    end
    return TrimLinesToMax(out, MaxLines())
end

local function SanitizeSV()
    local sv = GetSV()
    local cleaned = SanitizeLineList(sv.sessionLog)
    if cleaned and #cleaned > 0 then
        sv.sessionLog = cleaned
    else
        sv.sessionLog = {}
    end
end

local function ChatColorsForType(chatType)
    if chatType and ChatTypeInfo[chatType] then
        local info = ChatTypeInfo[chatType]
        return info.r or 1, info.g or 1, info.b or 1, info.id or 1
    end
    return 1, 1, 1, 1
end

local function TextFromChatLineID(lineID)
    if not lineID or type(lineID) ~= "number" then return nil end
    if not C_ChatInfo or not C_ChatInfo.GetChatLineText then return nil end
    local ok, text = pcall(C_ChatInfo.GetChatLineText, lineID)
    if not ok or not text then return nil end
    if issecretvalue and issecretvalue(text) then return nil end
    return MessageForStorage(text)
end

local function SenderFromChatLineID(lineID)
    if not lineID or type(lineID) ~= "number" then return nil end
    if not C_ChatInfo or not C_ChatInfo.GetChatLineSenderName then return nil end
    local ok, name = pcall(C_ChatInfo.GetChatLineSenderName, lineID)
    if not ok or not name then return nil end
    if issecretvalue and issecretvalue(name) then return nil end
    return MessageForStorage(name)
end

local function ChatMessageBody(lineID, arg1)
    return TextFromChatLineID(lineID) or MessageForStorage(arg1)
end

local function ChatSenderName(lineID, arg2)
    local sender = SenderFromChatLineID(lineID)
    if not sender and type(arg2) == "string" and arg2 ~= "" then
        if not (issecretvalue and issecretvalue(arg2)) then
            sender = MessageForStorage(arg2)
        end
    end
    return sender
end

local function CountFormatPlaceholders(template)
    if type(template) ~= "string" then return 0 end
    local count = 0
    local i = 1
    while i <= #template do
        if template:sub(i, i) == "%" then
            local next = template:sub(i + 1, i + 1)
            if next == "%" then
                i = i + 2
            elseif next ~= "" then
                count = count + 1
                i = i + 2
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    return count
end

local function ApplyChatTemplate(template, link, body)
    if type(template) ~= "string" then return nil end
    local placeholders = CountFormatPlaceholders(template)
    if placeholders == 1 then
        return format(template .. body, link)
    end
    if placeholders == 2 then
        return format(template, link, body)
    end
    return nil
end

local function BNAccountInfo(bnSenderID)
    if type(bnSenderID) ~= "number" or bnSenderID <= 0 then return nil end
    if C_BattleNet and C_BattleNet.GetAccountInfoByID then
        local ok, info = pcall(C_BattleNet.GetAccountInfoByID, bnSenderID)
        if ok and type(info) == "table" then
            return info
        end
    end
    if BNGetFriendInfoByID then
        local ok, accountID, accountName, battleTag = pcall(BNGetFriendInfoByID, bnSenderID)
        if ok then
            return {
                bnetAccountID = accountID,
                accountName = accountName,
                battleTag = battleTag,
            }
        end
    end
    return nil
end

local function BNDisplayNameForAccount(bnSenderID)
    local info = BNAccountInfo(bnSenderID)
    if not info then return nil end
    local name = info.accountName or info.battleTag
    if type(name) == "string" and name ~= "" then
        return MessageForStorage(name)
    end
    return nil
end

local function BNLinkTokenForAccount(bnSenderID, storedToken)
    if type(storedToken) == "string" and storedToken ~= "" then
        if not (issecretvalue and issecretvalue(storedToken)) then
            return storedToken
        end
    end
    local display = BNDisplayNameForAccount(bnSenderID)
    if display then return display end
    return nil
end

-- Hyperlink token (arg2) can be a protected |K...|k string; display name is resolved separately.
local function BNPlayerHyperlink(playerToken, bnSenderID, guid, chatGroup, displayName)
    if not playerToken or type(bnSenderID) ~= "number" or bnSenderID <= 0 then
        return nil
    end
    if issecretvalue and issecretvalue(playerToken) then return nil end
    local label = displayName or playerToken
    if issecretvalue and issecretvalue(label) then return nil end
    guid = (type(guid) == "string" and guid) or ""
    chatGroup = chatGroup or "BN_WHISPER"
    return format(
        "|HBNplayer:%s:%d:%s:%s|h[%s]|h",
        playerToken, bnSenderID, guid, chatGroup, label
    )
end

local function FormatBNWhisperLine(chatType, body, playerToken, bnSenderID, guid, isMobile)
    if not body or not playerToken or type(bnSenderID) ~= "number" then return nil end
    local template = _G["CHAT_" .. chatType .. "_GET"]
    if type(template) ~= "string" then return nil end

    local chatGroup = chatType
    local displayName = BNDisplayNameForAccount(bnSenderID)
    if not displayName and type(playerToken) == "string" and playerToken ~= "" then
        if not (issecretvalue and issecretvalue(playerToken)) then
            displayName = MessageForStorage(playerToken)
        end
    end
    local link = BNPlayerHyperlink(playerToken, bnSenderID, guid, chatGroup, displayName)
    if not link then return nil end

    local pflag = ""
    if isMobile and ChatFrameUtil and ChatFrameUtil.GetMobileEmbeddedTexture then
        local ok, flag = pcall(ChatFrameUtil.GetMobileEmbeddedTexture, 0.2)
        if ok and flag then pflag = flag end
    end
    return format(template .. body, pflag .. link)
end

local function PlayerLinkTarget(playerName, chatType)
    if IsWhisperChatType(chatType) then
        if not playerName or playerName == "" then return "" end
        if strsub(playerName, 1, 2) == "|K" then return playerName end
        return strupper(playerName)
    end
    return ""
end

local function PlayerHyperlink(playerName, lineID, chatType, displayName)
    if not playerName or type(playerName) ~= "string" or playerName == "" then
        return nil
    end
    if issecretvalue and issecretvalue(playerName) then return nil end
    local label = displayName or playerName
    if issecretvalue and issecretvalue(label) then return nil end
    chatType = chatType or "SAY"
    if type(lineID) == "number" and lineID > 0 then
        local chatTarget = PlayerLinkTarget(playerName, chatType)
        return format(
            "|Hplayer:%s:%d:%s:%s|h[%s]|h",
            playerName, lineID, chatType, chatTarget, label
        )
    end
    return format("|Hplayer:%s|h[%s]|h", playerName, label)
end

local function PlainPlayerLine(chatType, body, playerName, extras)
    if not body or not playerName then return nil end
    if chatType == "WHISPER_INFORM" then return "To [" .. playerName .. "]: " .. body end
    if chatType == "WHISPER" then return "[" .. playerName .. "] whispers: " .. body end
    if chatType == "SAY" then return playerName .. " says: " .. body end
    if chatType == "YELL" then return playerName .. " yells: " .. body end
    if chatType == "CHANNEL" and extras and extras.channelName then
        return "[" .. extras.channelName .. "] [" .. playerName .. "]: " .. body
    end
    return "[" .. playerName .. "]: " .. body
end

local function FormatPlayerChatLine(chatType, body, playerName, lineID, extras)
    if not body or not playerName then return nil end
    local link = PlayerHyperlink(playerName, lineID, chatType, playerName)
    if not link then return PlainPlayerLine(chatType, body, playerName, extras) end

    if chatType == "CHANNEL" and extras and extras.channelName then
        local template = _G["CHAT_" .. chatType .. "_GET"]
        local formatted = ApplyChatTemplate(template, link, body)
        if formatted then
            return "[" .. extras.channelName .. "] " .. formatted
        end
        return "[" .. extras.channelName .. "] " .. link .. ": " .. body
    end

    local template = _G["CHAT_" .. chatType .. "_GET"]
    local formatted = ApplyChatTemplate(template, link, body)
    if formatted then return formatted end
    if chatType == "WHISPER_INFORM" then return "To " .. link .. ": " .. body end
    if chatType == "WHISPER" then return link .. " whispers: " .. body end
    if chatType == "SAY" then return link .. " says: " .. body end
    if chatType == "YELL" then return link .. " yells: " .. body end
    return link .. ": " .. body
end

local function StripPlayerLinkPrefix(storedLine)
    if type(storedLine) ~= "string" then return storedLine end
    local _, rest = storedLine:match("^(|Hplayer:.-%|h%[.-%]%]|h[%s]*)(.*)$")
    if rest and rest ~= "" then return rest end
    return storedLine
end

local function ExtractPlayerNameFromStored(storedLine, chatType)
    if type(storedLine) ~= "string" then return nil end
    local fromLink = storedLine:match("|Hplayer:([^:|]+)")
    if fromLink then return MessageForStorage(fromLink) end

    storedLine = StripPlayerLinkPrefix(storedLine)
    if chatType == "WHISPER_INFORM" then
        return MessageForStorage(storedLine:match("^To %[([^%]]+)%]:"))
            or MessageForStorage(storedLine:match("^To ([^:]+):"))
    end
    if chatType == "WHISPER" then
        return MessageForStorage(storedLine:match("^%[([^%]]+)%] whispers:"))
            or MessageForStorage(storedLine:match("^([^%s]+) whispers:"))
    end
    if chatType == "SAY" then
        return MessageForStorage(storedLine:match("^([^%s]+) says:"))
    end
    if chatType == "YELL" then
        return MessageForStorage(storedLine:match("^([^%s]+) yells:"))
    end
    if chatType == "CHANNEL" then
        return MessageForStorage(storedLine:match("^%[[^%]]+%] %[([^%]]+)%]:"))
            or MessageForStorage(storedLine:match("^%[[^%]]+%] ([^:]+):"))
    end
    return MessageForStorage(storedLine:match("^%[([^%]]+)%]:"))
end

local function ExtractPlayerRawBodyFromStored(storedLine, chatType, channelName)
    if type(storedLine) ~= "string" then return nil end
    storedLine = StripPlayerLinkPrefix(storedLine)

    if chatType == "WHISPER_INFORM" then
        local body = storedLine:match("^To .-%|h%[.-%]%]|h: (.+)$")
            or storedLine:match("^To %[.-%]: (.+)$")
            or storedLine:match("^To .-: (.+)$")
        if body then return MessageForStorage(body) end
    elseif chatType == "WHISPER" then
        local body = storedLine:match(" whispers: (.+)$")
            or storedLine:match("^%[.-%] whispers: (.+)$")
        if body then return MessageForStorage(body) end
    elseif chatType == "SAY" then
        local body = storedLine:match(" says: (.+)$")
        if body then return MessageForStorage(body) end
    elseif chatType == "YELL" then
        local body = storedLine:match(" yells: (.+)$")
        if body then return MessageForStorage(body) end
    elseif chatType == "CHANNEL" then
        local body = storedLine:match("^%[[^%]]+%] .-: (.+)$")
            or storedLine:match("^%[[^%]]+%] %[.-%]: (.+)$")
        if body then return MessageForStorage(body) end
    else
        local body = storedLine:match("^%[.-%]: (.+)$")
            or storedLine:match("^.-|h%[.-%]%]|h: (.+)$")
            or storedLine:match("^.-|h%[.-%]%]|h%s*(.+)$")
        if body then return MessageForStorage(body) end
    end
    return nil
end

local BRACKET_PLAYER_CHAT_TYPES = {
    "PARTY", "PARTY_LEADER", "GUILD", "OFFICER",
    "RAID", "RAID_LEADER", "RAID_WARNING",
}

local function ChatTypeFromStoredLine(stored)
    if type(stored) ~= "string" then return nil end
    if stored:match("^To ") then
        if stored:find("|HBNplayer:", 1, true) then return "BN_WHISPER_INFORM" end
        return "WHISPER_INFORM"
    end
    if stored:find(" whispers:", 1, true) then
        if stored:find("|HBNplayer:", 1, true) then return "BN_WHISPER" end
        return "WHISPER"
    end
    if stored:match(" says:") then return "SAY" end
    if stored:match(" yells:") then return "YELL" end
    if stored:match("^%[[^%]]+%] %[[^%]]+%]:") or stored:match("^%[[^%]]+%] |Hplayer:") then
        return "CHANNEL"
    end
    return nil
end

local function PlayerLinkedDedupKeysFromStored(stored)
    local chatType = ChatTypeFromStoredLine(stored)
    if chatType and IsBNWhisperChatType(chatType) then return nil end

    local channelName
    if chatType == "CHANNEL" then
        channelName = MessageForStorage(stored:match("^%[([^%]]+)%]"))
    end

    if chatType and IsPlayerLinkedChatType(chatType) then
        local name = ExtractPlayerNameFromStored(stored, chatType)
        local payload = ExtractPlayerRawBodyFromStored(stored, chatType, channelName)
        if name and payload then
            return { "p:" .. chatType .. ":" .. strupper(name) .. ":" .. payload }
        end
    end

    if stored:match("^%[.-%]: ") or stored:match("|Hplayer:") then
        local name, payload
        for i = 1, #BRACKET_PLAYER_CHAT_TYPES do
            local ct = BRACKET_PLAYER_CHAT_TYPES[i]
            name = name or ExtractPlayerNameFromStored(stored, ct)
            payload = payload or ExtractPlayerRawBodyFromStored(stored, ct, channelName)
        end
        if name and payload then
            local keys = {}
            for i = 1, #BRACKET_PLAYER_CHAT_TYPES do
                local ct = BRACKET_PLAYER_CHAT_TYPES[i]
                keys[#keys + 1] = "p:" .. ct .. ":" .. strupper(name) .. ":" .. payload
            end
            return keys
        end
    end
    return nil
end

local function RebuildPlayerMessageOnRestore(entry, storedLine)
    if not entry or not entry.event then return nil end
    local chatType = ChatTypeFromEvent(entry.event)
    if not IsPlayerLinkedChatType(chatType) then return nil end

    local playerName = EntryPlayerName(entry)
        or ExtractPlayerNameFromStored(storedLine, chatType)
    if not playerName then return nil end

    local extras
    if chatType == "CHANNEL" then
        local channelName = MessageForStorage(entry.channelName)
        if not channelName and type(storedLine) == "string" then
            channelName = MessageForStorage(storedLine:match("^%[([^%]]+)%]"))
        end
        if channelName then extras = { channelName = channelName } end
    end

    local rawBody = MessageForStorage(entry.rawBody)
        or ExtractPlayerRawBodyFromStored(storedLine, chatType, extras and extras.channelName)
    if not rawBody then return nil end

    local lineID = type(entry.lineID) == "number" and entry.lineID or nil
    return FormatPlayerChatLine(chatType, rawBody, playerName, lineID, extras)
end

-- Pull message payload out of a stored BN line (legacy plain text or linked).
local function ExtractBNRawBody(storedLine, chatType)
    if type(storedLine) ~= "string" then return nil end
    local link, rest = storedLine:match("^(|HBNplayer:.-%|h%[.-%]%]|h[%s]*)(.*)$")
    if link and rest and rest ~= "" then
        storedLine = rest
    end
    if chatType == "BN_WHISPER_INFORM" then
        local body = storedLine:match("^To .-%|h%[.-%]%]|h: (.+)$")
            or storedLine:match("^To %[.-%]: (.+)$")
            or storedLine:match("^To .-: (.+)$")
        if body then return MessageForStorage(body) end
    else
        local body = storedLine:match(" whispers: (.+)$")
            or storedLine:match(" whispers:%s*(.+)$")
            or storedLine:match("^%[.-%] whispers: (.+)$")
        if body then return MessageForStorage(body) end
    end
    return nil
end

local function RebuildBNMessageOnRestore(entry, storedLine)
    if not entry or not entry.event then return nil end
    local chatType = ChatTypeFromEvent(entry.event)
    if not IsBNWhisperChatType(chatType) then return nil end

    local bnSenderID = entry.bnSenderID
    if type(bnSenderID) ~= "number" or bnSenderID <= 0 then
        if type(storedLine) == "string" then
            bnSenderID = tonumber(storedLine:match("|HBNplayer:[^:]+:(%d+):"))
        end
    end
    if type(bnSenderID) ~= "number" or bnSenderID <= 0 then
        return nil
    end

    local rawBody = MessageForStorage(entry.rawBody) or ExtractBNRawBody(storedLine, chatType)
    if not rawBody then return nil end

    local playerToken = BNLinkTokenForAccount(bnSenderID, entry.bnPlayerToken)
    if not playerToken then return nil end

    local guid = (type(entry.guid) == "string" and entry.guid) or ""
    local rebuilt = FormatBNWhisperLine(chatType, rawBody, playerToken, bnSenderID, guid, false)
    if rebuilt then return rebuilt end

    local displayName = BNDisplayNameForAccount(bnSenderID)
    local link = BNPlayerHyperlink(playerToken, bnSenderID, guid, chatType, displayName)
    if not link then return nil end
    if chatType == "BN_WHISPER_INFORM" then
        return "To " .. link .. ": " .. rawBody
    end
    return link .. " whispers: " .. rawBody
end

-- After reload, BNet friend list may change; refresh stored BNplayer link ids/names.
local function RefreshBNLinksInMessage(msg)
    if type(msg) ~= "string" or not msg:find("|HBNplayer:", 1, true) then
        return msg
    end
    return gsub(
        msg,
        "|HBNplayer:([^:]+):(%d+):([^:]*):([^|]+)|h%[([^%]]*)%]|h",
        function(playerToken, idStr, guid, chatGroup, _oldDisplay)
            local bnSenderID = tonumber(idStr)
            if not bnSenderID then
                return format("|HBNplayer:%s:%s:%s:%s|h[%s]|h", playerToken, idStr, guid, chatGroup, _oldDisplay)
            end
            local displayName = BNDisplayNameForAccount(bnSenderID) or _oldDisplay
            local refreshed = BNPlayerHyperlink(playerToken, bnSenderID, guid, chatGroup, displayName)
            if refreshed then return refreshed end
            return format("|HBNplayer:%s:%d:%s:%s|h[%s]|h", playerToken, bnSenderID, guid, chatGroup, displayName)
        end
    )
end

-- PushBack does not apply showTimestamps to message text; prefix on restore only.
local function RestoreDisplayMessage(entry)
    local body = MessageForStorage(entry and entry.message)
    if not body then return nil end
    body = MessageBodyOnly(body)

    local chatType = entry.event and ChatTypeFromEvent(entry.event)
    if chatType and IsBNWhisperChatType(chatType) then
        local rebuilt = RebuildBNMessageOnRestore(entry, body)
        if rebuilt then
            body = rebuilt
        else
            return nil
        end
    elseif chatType and IsPlayerLinkedChatType(chatType) then
        local rebuilt = RebuildPlayerMessageOnRestore(entry, body)
        if rebuilt then
            body = rebuilt
        end
    elseif body:find("|HBNplayer:", 1, true) then
        body = RefreshBNLinksInMessage(body)
    end

    local prefix = FormatTimestampPrefix(entry.serverTime)
    if prefix ~= "" then return prefix .. body end
    return body
end

local function BuildLineFromChatEvent(event, ...)
    if type(event) ~= "string" or strsub(event, 1, 8) ~= "CHAT_MSG" then
        return nil
    end
    local arg1, arg2 = ...
    local lineID = select(11, ...)
    local guid = select(12, ...)
    local bnSenderID = select(13, ...)
    local isMobile = select(14, ...)
    local chatType = strsub(event, 10)
    local body = ChatMessageBody(lineID, arg1)
    if not body then return nil end

    local sender = ChatSenderName(lineID, arg2)

    if IsBNWhisperChatType(chatType) and type(arg2) == "string" and arg2 ~= "" then
        if type(bnSenderID) == "number" and bnSenderID > 0 then
            local bnLine = FormatBNWhisperLine(chatType, body, arg2, bnSenderID, guid, isMobile)
            if bnLine then return bnLine end
            local displayName = BNDisplayNameForAccount(bnSenderID)
            local link = BNPlayerHyperlink(arg2, bnSenderID, guid, chatType, displayName)
            if link then
                if chatType == "BN_WHISPER_INFORM" then
                    return "To " .. link .. ": " .. body
                end
                return link .. " whispers: " .. body
            end
        end
    end

    if IsPlayerLinkedChatType(chatType) then
        if sender then
            local extras
            if chatType == "CHANNEL" then
                local channelName = MessageForStorage(select(4, ...))
                if channelName then extras = { channelName = channelName } end
            end
            return FormatPlayerChatLine(chatType, body, sender, lineID, extras)
        end
        return body
    end

    return body
end

local function FrameShowsEvent(cf, event)
    if not cf or not event then return false end
    local group = MessageGroupForEvent(event)
    if not group then return false end
    local list = cf.messageTypeList
    if type(list) ~= "table" then return true end
    for i = 1, #list do
        if list[i] == group then
            return true
        end
    end
    return false
end

-- Resolve channel routing fields; legacy rows only have the channel prefix in message.
local function GetEntryChannelInfo(entry)
    local channelName = MessageForStorage(entry.channelName)
    local baseName = MessageForStorage(entry.channelBaseName)
    local zoneID = type(entry.zoneChannelID) == "number" and entry.zoneChannelID or 0

    if (not channelName or not baseName) and entry.message then
        local body = MessageBodyOnly(entry.message)
        local parsedName = body and body:match("^%[([^%]]+)%]")
        if parsedName then
            channelName = channelName or parsedName
            baseName = baseName or parsedName:match("^%d+%.%s*(.+)$") or parsedName
        end
    end

    return zoneID, baseName, channelName
end

-- Mirror Blizzard ChatFrame channelList / zoneChannelList matching on restore.
local function FrameHasRegisteredChannels(cf)
    local list = cf and cf.channelList
    if type(list) ~= "table" then return false end
    for _, value in pairs(list) do
        if type(value) == "string" and value ~= "" then
            return true
        end
    end
    return false
end

local function FrameShowsChannelEntry(cf, entry)
    if not cf or not entry then return false end
    if not FrameHasRegisteredChannels(cf) then return false end

    local zoneID, baseName, channelName = GetEntryChannelInfo(entry)
    if not baseName and zoneID <= 0 then return false end

    local channelLength = channelName and #channelName or 0
    if channelLength == 0 and baseName then
        channelLength = #baseName
    end
    if channelLength == 0 then return false end

    local baseUpper = baseName and strupper(baseName) or nil
    local zoneList = cf.zoneChannelList

    for index, value in pairs(cf.channelList) do
        if type(value) == "string" and value ~= "" and channelLength > #value then
            local zoneMatch = zoneID > 0 and type(zoneList) == "table" and zoneList[index] == zoneID
            local nameMatch = baseUpper and strupper(value) == baseUpper
            if zoneMatch or nameMatch then
                return true
            end
        end
    end
    return false
end

local function FrameShowsEntry(cf, entry)
    if not cf or not entry or not entry.event then return false end
    local chatType = ChatTypeGroupFromEvent(entry.event)
    if chatType == "CHANNEL" then
        return FrameShowsChannelEntry(cf, entry)
    end
    return FrameShowsEvent(cf, entry.event)
end

local function AppendLogEntry(entry)
    local sv = GetSV()
    local log = sv.sessionLog
    local norm = NormalizeEntryForDedup(entry)
    if norm then
        local checkN = math.min(#log, 10)
        for i = #log, #log - checkN + 1, -1 do
            if NormalizeEntryForDedup(log[i]) == norm then return end
        end
    end
    log[#log + 1] = entry
    sv.sessionLog = TrimLinesToMax(log, MaxLines())
end

-------------------------------------------------------------------------------
--  Capture (CHAT_MSG -> sessionLog, open world only)
-------------------------------------------------------------------------------
local function SaveChatEvent(event, ...)
    if not CaptureAllowed() or not sessionEpochTime then return end
    if GetTime() < sessionEpochTime - 0.5 then return end

    local chatType = strsub(event, 10)
    local arg1 = ...
    local arg2 = select(2, ...)
    local lineID = select(11, ...)
    local guid = select(12, ...)
    local bnSenderID = select(13, ...)
    local rawBody = ChatMessageBody(lineID, arg1)
    local line = BuildLineFromChatEvent(event, ...)
    if not line then return end

    local serverTime = GetServerTime()
    local message = MessageForStorage(line)
    if not message then return end
    local r, g, b, id = ChatColorsForType(chatType)
    captureSeq = captureSeq + 1

    local entry = {
        event = event,
        message = message,
        r = r, g = g, b = b, id = id,
        timestamp = GetTime(),
        serverTime = serverTime,
        captureSeq = captureSeq,
    }
    if IsBNWhisperChatType(chatType) and type(bnSenderID) == "number" and bnSenderID > 0 then
        entry.bnSenderID = bnSenderID
        entry.rawBody = rawBody
        entry.guid = (type(guid) == "string" and guid) or nil
        if type(arg2) == "string" and arg2 ~= "" then
            if not (issecretvalue and issecretvalue(arg2)) then
                entry.bnPlayerToken = MessageForStorage(arg2)
            end
        end
    elseif IsPlayerLinkedChatType(chatType) then
        entry.rawBody = rawBody
        entry.guid = (type(guid) == "string" and guid) or nil
        if type(lineID) == "number" then entry.lineID = lineID end
        entry.playerName = ChatSenderName(lineID, arg2)
        if chatType == "CHANNEL" then
            local channelName = MessageForStorage(select(4, ...))
            local zoneChannelID = select(7, ...)
            local channelIndex = select(8, ...)
            local channelBaseName = MessageForStorage(select(9, ...))
            if channelName then entry.channelName = channelName end
            if type(zoneChannelID) == "number" then entry.zoneChannelID = zoneChannelID end
            if type(channelIndex) == "number" then entry.channelIndex = channelIndex end
            if channelBaseName then entry.channelBaseName = channelBaseName end
        end
    end
    AppendLogEntry(entry)
end

local function ClearSavedSessionHistory()
    restoreToken = restoreToken + 1
    wipe(restoredFrames)
    captureSeq = 0
    sessionEpochTime = nil
    UnarmDeferredRestore()
    GetSV().sessionLog = {}
end

function ECHAT.SnapshotChatSessionHistory()
    if not PersistEnabled() then return end
    SanitizeSV()
end

-------------------------------------------------------------------------------
--  Restore (sessionLog -> historyBuffer)
-------------------------------------------------------------------------------
UnarmDeferredRestore = function()
    deferFrame:UnregisterAllEvents()
    deferFrame:SetScript("OnEvent", nil)
end

local function RefreshFrameDisplay(cf)
    if cf.ResetAllFadeTimes then pcall(cf.ResetAllFadeTimes, cf) end
    if cf.UpdateDisplay then pcall(cf.UpdateDisplay, cf) end
    if cf.ScrollToBottom then pcall(cf.ScrollToBottom, cf) end
end

-- Build a set of normalized message hashes already in the frame (O(n) once)
local function BuildFrameMessageSet(cf)
    local set = {}
    if not cf or not cf.GetNumMessages or not cf.GetMessageInfo then return set end
    local ok, n = pcall(cf.GetNumMessages, cf)
    if not ok or type(n) ~= "number" then return set end
    for i = 1, n do
        local mok, raw = pcall(cf.GetMessageInfo, cf, i)
        local stored = mok and MessageForStorage(raw) or nil
        if stored then
            local norm = NormalizeForDedup(stored)
            if norm then set[norm] = true end
            local playerKeys = PlayerLinkedDedupKeysFromStored(stored)
            if playerKeys then
                for j = 1, #playerKeys do
                    set[playerKeys[j]] = true
                end
            end
            local bnId = stored:match("|HBNplayer:[^:]+:(%d+):")
            if bnId then
                local chatType = stored:match("^To ") and "BN_WHISPER_INFORM" or "BN_WHISPER"
                local payload = ExtractBNRawBody(stored, chatType)
                if payload then
                    set["bn:" .. chatType .. ":" .. bnId .. ":" .. payload] = true
                end
            end
        end
    end
    return set
end

local function ShouldRestoreEntry(entry, frameFilter, existingSet)
    if not entry or not entry.event or not entry.message then return false end
    if not frameFilter(entry) then return false end
    local norm = NormalizeEntryForDedup(entry)
    if norm and existingSet[norm] then return false end
    return true
end

local function PushRestoreEntry(cf, buf, entry, baseTs, pushIndex, tsStep)
    local text = RestoreDisplayMessage(entry)
    if not text then return false end
    if buf and type(buf.PushBack) == "function" then
        return pcall(buf.PushBack, buf, {
            message = text,
            r = entry.r, g = entry.g, b = entry.b, id = entry.id,
            serverTime = entry.serverTime,
            timestamp = baseTs - (pushIndex * tsStep),
        })
    end
    if cf.BackFillMessage then
        return pcall(cf.BackFillMessage, cf, text, entry.r, entry.g, entry.b)
    end
    return false
end

local function RestoreFrame(cf, frameName, log)
    if not cf or not log or #log == 0 then return false end
    if not ShouldTrackFrame(cf) then return false end
    if restoredFrames[frameName] then return false end

    local lines = SanitizeLineList(log)
    if not lines or #lines == 0 then return false end
    lines = SortLinesChronological(lines)

    local buf = cf.historyBuffer
    if not ((buf and type(buf.PushBack) == "function") or cf.BackFillMessage) then
        return false
    end

    -- Build hash set of existing messages once (O(n)), then O(1) lookups
    local existingSet = BuildFrameMessageSet(cf)
    local function frameFilter(entry) return FrameShowsEntry(cf, entry) end

    local pushed = 0
    local baseTs = OldestFrameTimestamp(cf)
    local tsStep = 0.001
    local pushIndex = 0

    for i = #lines, 1, -1 do
        local entry = lines[i]
        if ShouldRestoreEntry(entry, frameFilter, existingSet) then
            pushIndex = pushIndex + 1
            if PushRestoreEntry(cf, buf, entry, baseTs, pushIndex, tsStep) then
                pushed = pushed + 1
            end
        end
    end

    if pushed == 0 then
        return false
    end

    restoredFrames[frameName] = true
    RefreshFrameDisplay(cf)
    return true
end

local function RunRestore(token)
    if token ~= restoreToken then return end
    if not SessionHistorySafe() then return false end

    local log = GetSV().sessionLog
    if not log or #log == 0 then return false end

    local any = false
    local chatFrames = _G.CHAT_FRAMES
    if type(chatFrames) == "table" then
        for i = 1, #chatFrames do
            local cf = _G[chatFrames[i]]
            if cf and RestoreFrame(cf, chatFrames[i], log) then
                any = true
            end
        end
    else
        for i = 1, 50 do
            local name = "ChatFrame" .. i
            local cf = _G[name]
            if cf and RestoreFrame(cf, name, log) then
                any = true
            end
        end
    end
    return any
end

local TryRestore  -- forward declaration (mutually recursive with ArmDeferredRestore)

local function ArmDeferredRestore(token)
    UnarmDeferredRestore()
    local function onDefer(_, deferEvent, ...)
        if token ~= restoreToken then
            UnarmDeferredRestore()
            return
        end
        if deferEvent == "PLAYER_ENTERING_WORLD" then
            local _, isReloadingUi = ...
            if isReloadingUi then return end
        end
        if not SessionHistorySafe() then return end
        UnarmDeferredRestore()
        TryRestore(token, 1)
    end
    deferFrame:SetScript("OnEvent", onDefer)
    deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    deferFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    if C_ChallengeMode then
        deferFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    end
end

TryRestore = function(token, attempt)
    if token ~= restoreToken then return end
    if not PersistEnabled() then return end
    if not SessionHistorySafe() then
        ArmDeferredRestore(token)
        return
    end

    attempt = attempt or 1
    local log = GetSV().sessionLog
    local hasLog = log and #log > 0
    local restored = RunRestore(token)

    if hasLog and not restored and attempt < RESTORE_MAX_ATTEMPTS then
        wipe(restoredFrames)
        C_Timer.After(RESTORE_RETRY_SEC, function()
            TryRestore(token, attempt + 1)
        end)
    end
end

function ECHAT.RestoreChatSessionHistory()
    UnarmDeferredRestore()
    restoreToken = restoreToken + 1
    wipe(restoredFrames)
    local token = restoreToken
    if not PersistEnabled() then return end
    C_Timer.After(RESTORE_DELAY_SEC, function()
        TryRestore(token, 1)
    end)
end

function ECHAT.OnSessionHistoryToggled(enabled)
    if enabled then
        ECHAT.InitChatSessionHistory()
        ECHAT.RestoreChatSessionHistory()
    else
        ClearSavedSessionHistory()
    end
end

local function ScheduleSessionEpochAfterLogin()
    C_Timer.After(RESTORE_DELAY_SEC + SESSION_EPOCH_DELAY_SEC, MarkSessionEpoch)
end

local function InstallChatCaptureEvents()
    if chatEventsInstalled then return end
    chatEventsInstalled = true
    for _, ev in ipairs(CAPTURE_EVENTS) do
        eventFrame:RegisterEvent(ev)
    end
end

local function UninstallChatCaptureEvents()
    if not chatEventsInstalled then return end
    chatEventsInstalled = false
    for _, ev in ipairs(CAPTURE_EVENTS) do
        eventFrame:UnregisterEvent(ev)
    end
end

function ECHAT.InitChatSessionHistory()
    if not PersistEnabled() then
        UninstallChatCaptureEvents()
        ClearSavedSessionHistory()
        return
    end
    SanitizeSV()
    InstallChatCaptureEvents()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGOUT" then
        if PersistEnabled() then
            ECHAT.SnapshotChatSessionHistory()
        else
            ClearSavedSessionHistory()
        end
        return
    end

    if event == "PLAYER_LEAVING_WORLD" then
        if PersistEnabled() then
            ECHAT.SnapshotChatSessionHistory()
        else
            ClearSavedSessionHistory()
        end
        return
    end

    if strsub(event, 1, 8) == "CHAT_MSG" then
        SaveChatEvent(event, ...)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if not isInitialLogin and not isReloadingUi then
            if SessionHistorySafe() then
                ECHAT.RestoreChatSessionHistory()
            end
            return
        end
        sessionEpochTime = nil
        captureSeq = 0
        ECHAT.InitChatSessionHistory()
        if PersistEnabled() then
            ECHAT.RestoreChatSessionHistory()
            ScheduleSessionEpochAfterLogin()
        end
    end
end)
