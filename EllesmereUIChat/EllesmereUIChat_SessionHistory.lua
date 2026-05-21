-------------------------------------------------------------------------------
--  EllesmereUIChat_SessionHistory.lua
--
--  Persists recent player chat across /reload and relog. Saves on CHAT_MSG
--  in open world only (instances cannot provide storable text). Stores message
--  body plus serverTime/timestamp; restore prepends timestamp from that format.
-------------------------------------------------------------------------------
local _, ns = ...
local ECHAT = ns.ECHAT
if not ECHAT then return end

local strsub = string.sub
local gsub = string.gsub
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
    "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
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
    if not ECHAT.DB then return true end
    local db = ECHAT.DB()
    if not db then return true end
    return db.persistChatHistory ~= false
end

local function SessionHistorySafe()
    if not PersistEnabled() then return false end
    if EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance() then return false end
    if GetCVarBool and GetCVarBool("addonChatRestrictionsForced") then return false end
    return true
end

local function InOpenWorld()
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
local function StripLegacyTimestampPrefix(msg)
    if type(msg) ~= "string" then return msg end
    local rest = msg:match("^%d%d?:%d%d(?::%d%d)?%s*([AP]M)?%s+(.*)$")
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

-- PushBack does not apply showTimestamps to message text; prefix on restore only.
local function RestoreDisplayMessage(entry)
    local body = MessageForStorage(entry and entry.message)
    if not body then return nil end
    body = MessageBodyOnly(body)
    local prefix = FormatTimestampPrefix(entry.serverTime)
    if prefix ~= "" then return prefix .. body end
    return body
end

local function IsEmoteChatType(chatType)
    return chatType == "EMOTE" or chatType == "TEXT_EMOTE"
end

local function IsEmoteChatEvent(event)
    if type(event) ~= "string" then return false end
    return IsEmoteChatType(strsub(event, 10))
end

local function IsPlayerChatLine(msg, chatType)
    if type(msg) ~= "string" then return false end
    if chatType and IsEmoteChatType(chatType) then return true end
    if msg:find("|Hplayer:", 1, true) or msg:find("|HBNplayer:", 1, true) then
        return true
    end
    if msg:find("|Hchannel:", 1, true) then return true end
    if msg:find(" says:", 1, true) or msg:find(" yells:", 1, true) then
        return true
    end
    if msg:find(" whispers:", 1, true) or msg:find("To [", 1, true) then
        return true
    end
    if msg:match("^%[%d+%.") or msg:match("^%[[^%]]+%]:") then
        return true
    end
    if msg:match("^%[[^%]]+%] %[[^%]]+%]:") then
        return true
    end
    return false
end

local function NormalizeForDedup(msg)
    local text = MessageBodyOnly(msg)
    if not text then return nil end
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
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

local function SanitizeLineList(lines)
    if type(lines) ~= "table" then return nil end
    local out = {}
    for _, L in ipairs(lines) do
        if type(L) == "table" then
            local msg = MessageForStorage(L.message)
            if msg then msg = MessageBodyOnly(msg) end
            local chatType = type(L.event) == "string" and strsub(L.event, 10) or nil
            if msg and (IsPlayerChatLine(msg, chatType) or IsEmoteChatEvent(L.event)) then
                out[#out + 1] = {
                    message = msg,
                    event = L.event,
                    r = (type(L.r) == "number" and L.r) or 1,
                    g = (type(L.g) == "number" and L.g) or 1,
                    b = (type(L.b) == "number" and L.b) or 1,
                    id = (type(L.id) == "number" and L.id) or 1,
                    timestamp = (type(L.timestamp) == "number" and L.timestamp) or GetTime(),
                    serverTime = (type(L.serverTime) == "number" and L.serverTime) or GetServerTime(),
                    captureSeq = (type(L.captureSeq) == "number" and L.captureSeq) or nil,
                }
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

local function BuildLineFromChatEvent(event, ...)
    if type(event) ~= "string" or strsub(event, 1, 8) ~= "CHAT_MSG" then
        return nil
    end
    local arg1, arg2 = ...
    local lineID = select(11, ...)
    local chatType = strsub(event, 10)
    local body = TextFromChatLineID(lineID) or MessageForStorage(arg1)
    if not body then return nil end

    local sender = SenderFromChatLineID(lineID)
    if not sender and type(arg2) == "string" and arg2 ~= "" then
        if not (issecretvalue and issecretvalue(arg2)) then
            sender = MessageForStorage(arg2)
        end
    end

    if chatType == "WHISPER_INFORM" or chatType == "BN_WHISPER_INFORM" then
        if sender then return "To [" .. sender .. "]: " .. body end
        return body
    end
    if chatType == "WHISPER" or chatType == "BN_WHISPER" then
        if sender then return "[" .. sender .. "] whispers: " .. body end
        return body
    end
    if chatType == "SAY" then
        if sender then return sender .. " says: " .. body end
        return body
    end
    if chatType == "YELL" then
        if sender then return sender .. " yells: " .. body end
        return body
    end
    if IsEmoteChatType(chatType) then
        if sender and body and not body:find(sender, 1, true) then
            return sender .. " " .. body
        end
        return body
    end
    if chatType == "CHANNEL" then
        local channelName = MessageForStorage(select(4, ...))
        if channelName and sender then
            return "[" .. channelName .. "] [" .. sender .. "]: " .. body
        end
    end
    if sender then return "[" .. sender .. "]: " .. body end
    return body
end

local function FrameShowsEvent(cf, event)
    if not cf or not event then return false end
    local chatType = gsub(strsub(event, 10), "_INFORM", "")
    local list = cf.messageTypeList
    if type(list) ~= "table" then return true end
    for i = 1, #list do
        if list[i] == chatType then
            return true
        end
    end
    return false
end

local function AppendLogEntry(entry)
    local sv = GetSV()
    local log = sv.sessionLog
    local last = log[#log]
    if last and NormalizeForDedup(last.message) == NormalizeForDedup(entry.message) then
        return
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
    local line = BuildLineFromChatEvent(event, ...)
    if not line or not IsPlayerChatLine(line, chatType) then return end

    local serverTime = GetServerTime()
    local message = MessageForStorage(line)
    if not message then return end
    local r, g, b, id = ChatColorsForType(chatType)
    captureSeq = captureSeq + 1

    AppendLogEntry({
        event = event,
        message = message,
        r = r, g = g, b = b, id = id,
        timestamp = GetTime(),
        serverTime = serverTime,
        captureSeq = captureSeq,
    })
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

local function FrameAlreadyHasMessage(cf, msg)
    if not cf or not msg then return false end
    local core = NormalizeForDedup(msg)
    if not core or core == "" then return false end
    if cf.GetNumMessages and cf.GetMessageInfo then
        local ok, n = pcall(cf.GetNumMessages, cf)
        if ok and type(n) == "number" then
            for i = 1, n do
                local mok, raw = pcall(cf.GetMessageInfo, cf, i)
                local stored = mok and MessageForStorage(raw) or nil
                if stored and NormalizeForDedup(stored) == core then
                    return true
                end
            end
        end
    end
    return false
end

local function ShouldRestoreEntry(cf, entry)
    return entry
        and entry.event
        and entry.message
        and FrameShowsEvent(cf, entry.event)
        and not FrameAlreadyHasMessage(cf, entry.message)
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

    local pushed = 0
    local baseTs = OldestFrameTimestamp(cf)
    local tsStep = 0.001
    local pushIndex = 0

    for i = #lines, 1, -1 do
        local entry = lines[i]
        if ShouldRestoreEntry(cf, entry) then
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

local function TryRestore(token, attempt)
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
