if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIChat_SessionHistory.lua
--
--  Persists recent player chat across /reload and relog. Lines are captured
--  from the display engine's bridge tail: the FINAL formatted string
--  (player links, class colors, channel prefix included), after Blizzard's
--  secure pipeline produced it. Capture happens in the open world only and
--  never stores secret values; restore replays into OUR message frames, so
--  no Blizzard frame is ever touched. Saved format is compatible with the
--  previous sessionLog schema (message body without timestamp prefix;
--  the prefix is re-applied on restore from serverTime with the current
--  timestamp format).
-------------------------------------------------------------------------------
local _, ns = ...
local ECHAT = ns.ECHAT
if not ECHAT then return end

local strsub = string.sub
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

local observerInstalled = false
local restoreToken = 0
local restoredFrames = {}
local sessionEpochTime = nil
local captureSeq = 0

local eventFrame = CreateFrame("Frame")
local deferFrame = CreateFrame("Frame")
local UnarmDeferredRestore

-- Player-chat events worth persisting; system/loot/combat spam is not.
local CAPTURE_EVENTS = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
    CHAT_MSG_EMOTE = true, CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true,
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

-- Strip the timestamp Blizzard's formatter baked into the line (our
-- timestampFormat rides the showTimestamps CVar, so captured lines carry it).
-- Also cleans legacy saves that stored the prefix. The prefix is re-applied
-- on restore from serverTime with whatever format is current.
-- Matches: "12:34 ...", "12:34:56 ...", "1:23 AM ...", "12:34:56 PM ..."
local function StripTimestampPrefix(msg)
    if type(msg) ~= "string" then return msg end
    local rest = msg:match("^%d%d?:%d%d:%d%d%s*[AP]M%s+(.+)$")
        or msg:match("^%d%d?:%d%d:%d%d%s+(.+)$")
        or msg:match("^%d%d?:%d%d%s*[AP]M%s+(.+)$")
        or msg:match("^%d%d?:%d%d%s+(.+)$")
    if rest and rest ~= "" then return rest end
    return msg
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

local function RestoreDisplayMessage(entry)
    local body = MessageForStorage(entry and entry.message)
    if not body then return nil end
    body = StripTimestampPrefix(body)
    local prefix = FormatTimestampPrefix(entry.serverTime)
    if prefix ~= "" then return prefix .. body end
    return body
end

local function NormalizeForDedup(msg)
    local text = StripTimestampPrefix(msg)
    if not text then return nil end
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

local TrimLinesToMax = function(lines, maxN)
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
            if msg then msg = StripTimestampPrefix(msg) end
            if msg then
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
    local norm = NormalizeForDedup(entry.message)
    if norm then
        -- The bridge tail fires once per window that displays the line, so
        -- the same message can arrive more than once back to back.
        local checkN = math.min(#log, 10)
        for i = #log, #log - checkN + 1, -1 do
            if NormalizeForDedup(log[i].message) == norm then return end
        end
    end
    log[#log + 1] = entry
    sv.sessionLog = TrimLinesToMax(log, MaxLines())
end

-------------------------------------------------------------------------------
--  Capture: the engine's bridge tail hands us the final formatted line for
--  every message our windows display. Everything here runs in our own
--  execution (the tail is the last step after Blizzard's pipeline finished);
--  secret lines never pass IsValidMessage.
-------------------------------------------------------------------------------
local function OnBridgeLine(cf, msg, r, g, b, chatTypeID, event)
    if not event or not CAPTURE_EVENTS[event] then return end
    if not sessionEpochTime or GetTime() < sessionEpochTime then return end
    if not CaptureAllowed() then return end
    if not ShouldTrackFrame(cf) then return end

    local body = MessageForStorage(msg)
    if not body then return end
    body = StripTimestampPrefix(body)
    if body == "" then return end

    captureSeq = captureSeq + 1
    AppendLogEntry({
        event = event,
        message = body,
        r = (type(r) == "number" and r) or 1,
        g = (type(g) == "number" and g) or 1,
        b = (type(b) == "number" and b) or 1,
        id = (type(chatTypeID) == "number" and chatTypeID) or 1,
        timestamp = GetTime(),
        serverTime = GetServerTime(),
        captureSeq = captureSeq,
    })
end

local function InstallCapture()
    if observerInstalled then return end
    if not ECHAT.EngineSetTailObserver then return end
    observerInstalled = true
    ECHAT.EngineSetTailObserver(OnBridgeLine)
end

local function UninstallCapture()
    if not observerInstalled then return end
    observerInstalled = false
    if ECHAT.EngineSetTailObserver then
        ECHAT.EngineSetTailObserver(nil)
    end
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
--  Restore: replay saved lines into OUR message frames (oldest lines end up
--  above everything already displayed). No Blizzard frame is involved.
-------------------------------------------------------------------------------
UnarmDeferredRestore = function()
    deferFrame:UnregisterAllEvents()
    deferFrame:SetScript("OnEvent", nil)
end

-- Normalized hashes of what a window already shows, so relog restores do not
-- duplicate lines that survived in the engine (O(n) once per window).
local function BuildWindowMessageSet(cf)
    local set = {}
    if not ECHAT.EngineGetMessageLines then return set end
    local raw = {}
    ECHAT.EngineGetMessageLines(cf, raw)
    for i = 1, #raw do
        local stored = MessageForStorage(raw[i])
        if stored then
            local ok, norm = pcall(NormalizeForDedup, stored)
            if ok and norm then set[norm] = true end
        end
    end
    return set
end

local function RestoreWindow(cf, frameName, log)
    if not cf or not log or #log == 0 then return false end
    if not ShouldTrackFrame(cf) then return false end
    if restoredFrames[frameName] then return false end
    if not (ns._chatWins and ns._chatWins[cf]) then return false end

    local lines = SanitizeLineList(log)
    if not lines or #lines == 0 then return false end
    lines = SortLinesChronological(lines)

    local existingSet = BuildWindowMessageSet(cf)

    local pushed = 0
    -- Newest first: each BackFill lands above the previous push, so the final
    -- on-screen order is chronological, above whatever login produced.
    for i = #lines, 1, -1 do
        local entry = lines[i]
        if entry and entry.event and entry.message and FrameShowsEvent(cf, entry.event) then
            local norm = NormalizeForDedup(entry.message)
            if not (norm and existingSet[norm]) then
                local text = RestoreDisplayMessage(entry)
                if text and ECHAT.EngineBackfillLine(cf, text, entry.r, entry.g, entry.b, entry.id) then
                    pushed = pushed + 1
                end
            end
        end
    end

    if pushed == 0 then
        return false
    end

    restoredFrames[frameName] = true
    return true
end

local function RunRestore(token)
    if token ~= restoreToken then return end
    if not SessionHistorySafe() then return false end

    local log = GetSV().sessionLog
    if not log or #log == 0 then return false end

    local any = false
    for i = 1, 10 do
        local name = "ChatFrame" .. i
        local cf = _G[name]
        if cf and RestoreWindow(cf, name, log) then
            any = true
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
        UninstallCapture()
        ClearSavedSessionHistory()
    end
end

local function ScheduleSessionEpochAfterLogin()
    C_Timer.After(RESTORE_DELAY_SEC + SESSION_EPOCH_DELAY_SEC, MarkSessionEpoch)
end

function ECHAT.InitChatSessionHistory()
    if not PersistEnabled() then
        UninstallCapture()
        ClearSavedSessionHistory()
        return
    end
    SanitizeSV()
    InstallCapture()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
        if PersistEnabled() then
            ECHAT.SnapshotChatSessionHistory()
        else
            ClearSavedSessionHistory()
        end
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
