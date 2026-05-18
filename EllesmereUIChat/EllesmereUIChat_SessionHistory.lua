-------------------------------------------------------------------------------
--  EllesmereUIChat_SessionHistory.lua
--
--  Keeps recent chat lines per docked frame (SavedVariablesPerCharacter) so
--  /reload or relog can replay them. Excludes the combat log window using
--  Blizzard's COMBATLOG frame and IsCombatLog() when present (see
--  FloatingChatFrame.lua), not a hard-coded ChatFrame index. Taint-safe
--  post-hook on AddMessage only; no search / indexing.
--  Restore is deferred until PLAYER_REGEN_ENABLED if still InCombatLockdown
--  when the replay timer fires (team policy: avoid extra work during lockdown).
-------------------------------------------------------------------------------
local _, ns = ...
local ECHAT = ns.ECHAT
if not ECHAT then return end

-- Disabled for now; keeping code for future use.
do return end

-- Saved var name unchanged so existing character data keeps working.
local SV_NAME = "EllesmereUIChatScrollDB"
local MAX_TEXT_LEN = 4096
local RESTORE_DELAY_SEC = 0.5

local hooked = {}
local restoring = false
local captureReady = false

--- True if this chat frame is Blizzard's combat log display (any tab index).
local function IsCombatLogChatFrame(cf)
    if not cf then return false end
    local combat = _G.COMBATLOG
    if combat and cf == combat then
        return true
    end
    local fn = _G.IsCombatLog
    if type(fn) == "function" then
        local ok, r = pcall(fn, cf)
        if ok and r then
            return true
        end
    end
    return false
end

local function GetSV()
    local sv = _G[SV_NAME]
    if type(sv) ~= "table" then
        sv = { v = 1, byFrame = {} }
        _G[SV_NAME] = sv
    end
    if type(sv.byFrame) ~= "table" then
        sv.byFrame = {}
    end
    return sv
end

local function ShouldTrackFrame(cf)
    if not cf or not cf.GetName then return false end
    if cf.isTemporary then return false end
    local name = cf:GetName()
    if not name or not name:match("^ChatFrame%d+$") then return false end
    return not IsCombatLogChatFrame(cf)
end

local function PurgeCombatLogSavedLines()
    local sv = GetSV()
    local bf = sv.byFrame
    if not bf then return end
    for frameName, _ in pairs(bf) do
        local fr = _G[frameName]
        if fr and IsCombatLogChatFrame(fr) then
            bf[frameName] = nil
        end
    end
end

local function AppendCaptured(frameName, text, r, g, b, id)
    local sv = GetSV()
    sv.byFrame[frameName] = sv.byFrame[frameName] or {}
    local lines = sv.byFrame[frameName]
    lines[#lines + 1] = {
        t = text,
        r = r,
        g = g,
        b = b,
        id = id,
    }
    local maxN = ECHAT.DB().persistChatHistoryMaxLines or 100
    if maxN < 10 then maxN = 10 end
    if maxN > 500 then maxN = 500 end
    while #lines > maxN do
        table.remove(lines, 1)
    end
end

local function HookChatFrame(cf)
    if not cf or hooked[cf] or cf.isTemporary then return end
    local nm = cf.GetName and cf:GetName()
    if not nm or not nm:match("^ChatFrame%d+$") then return end
    if IsCombatLogChatFrame(cf) then return end
    hooked[cf] = true
    hooksecurefunc(cf, "AddMessage", function(self, text, r, g, b, id)
        if restoring or not captureReady then return end
        if not ECHAT.DB().persistChatHistory then return end
        if not ShouldTrackFrame(self) then return end
        if type(text) ~= "string" or text == "" then return end
        if #text > MAX_TEXT_LEN then
            text = strsub(text, 1, MAX_TEXT_LEN)
        end
        local rn = (type(r) == "number" and r) or 1
        local gn = (type(g) == "number" and g) or 1
        local bn = (type(b) == "number" and b) or 1
        local idn = (type(id) == "number" and id) or 1
        local frameName = self:GetName()
        if frameName then
            AppendCaptured(frameName, text, rn, gn, bn, idn)
        end
    end)
end

function ECHAT.InitChatSessionHistory()
    PurgeCombatLogSavedLines()
    for i = 1, 50 do
        local cf = _G["ChatFrame" .. i]
        if cf then
            HookChatFrame(cf)
        end
    end
end

local restoreToken = 0
local regenDeferFrame = CreateFrame("Frame")

local function RunRestoreReplay(token)
    if token ~= restoreToken then return end
    local sv = GetSV()
    if not sv.byFrame then
        captureReady = true
        return
    end
    restoring = true
    for i = 1, 50 do
        local frameName = "ChatFrame" .. i
        local cf = _G[frameName]
        local lines = sv.byFrame[frameName]
        if cf and cf.AddMessage and type(lines) == "table" and #lines > 0
            and ShouldTrackFrame(cf) then
            for _, L in ipairs(lines) do
                if L.t then
                    cf:AddMessage(L.t, L.r or 1, L.g or 1, L.b or 1, L.id or 1)
                end
            end
        end
    end
    restoring = false
    captureReady = true
end

function ECHAT.RestoreChatSessionHistory()
    regenDeferFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    regenDeferFrame:SetScript("OnEvent", nil)
    if not ECHAT.DB().persistChatHistory then
        captureReady = true
        return
    end
    captureReady = false
    restoreToken = restoreToken + 1
    local token = restoreToken
    C_Timer.After(RESTORE_DELAY_SEC, function()
        if token ~= restoreToken then return end
        if EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance() then
            regenDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            regenDeferFrame:SetScript("OnEvent", function(_, ev)
                if ev ~= "PLAYER_REGEN_ENABLED" then return end
                if token ~= restoreToken then
                    regenDeferFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    regenDeferFrame:SetScript("OnEvent", nil)
                    return
                end
                if EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance() then return end
                RunRestoreReplay(token)
                regenDeferFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
                regenDeferFrame:SetScript("OnEvent", nil)
            end)
            return
        end
        RunRestoreReplay(token)
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUi)
    if event ~= "PLAYER_ENTERING_WORLD" then return end
    if not isInitialLogin and not isReloadingUi then return end
    ECHAT.InitChatSessionHistory()
    ECHAT.RestoreChatSessionHistory()
end)
