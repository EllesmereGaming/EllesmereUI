if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Opening whispers from the rest of the UI: the friends window's Whisper
--  button, the "Whisper" entries of the unit and friend menus, clicked player
--  names, /w and /r and the reply key. Each turns a chat edit box into a
--  whisper; the conversation then opens in the Message Center instead, its
--  input focused, and the edit box is closed as an ordinary /say box.
--
--  Taint: this is the one place we touch Blizzard's chat. The hooks are
--  post-hooks that only read; the box is changed a frame later, outside
--  Blizzard's call chain, and only where nothing restricted can follow it:
--  never in combat, the chat lockdown, an encounter, a Mythic+ run or
--  instanced PvP, and never on a forbidden box. Anywhere else the game's own
--  whisper box is left as it is. Also the slash commands.
-------------------------------------------------------------------------------
local _, addonNS = ...
local ns = addonNS.Whispers

local hooked = {}       -- edit boxes already hooked (never a field on Blizzard's frames)
local busy = false      -- re-entry guard while we reset a box

-- Out of every restricted context: the box may be changed
local function CanIntercept()
    local s = ns.settings
    if not (s and s.enabled) then return false end
    if InCombatLockdown() or ns.InChatLockdown() or IsEncounterInProgress() then return false end
    if C_ChallengeMode.IsChallengeModeActive() then return false end
    local _, instanceType = IsInInstance()
    return instanceType ~= "pvp" and instanceType ~= "arena"
end

local function Release(editBox)
    busy = true
    editBox:SetAttribute("chatType", "SAY")
    editBox:SetAttribute("tellTarget", nil)
    editBox:UpdateHeader()
    -- closed as the Escape key closes it
    local onEscape = editBox:GetScript("OnEscapePressed")
    if onEscape then onEscape(editBox) end
    busy = false
end

-- Does the work one frame after the edit box turned into a whisper: run from
-- the hook itself, it would execute inside Blizzard's own chain (a menu's
-- Whisper entry -> SendTell -> OpenChat -> ActivateChat -> UpdateHeader),
-- where an addon's changes taint that chain and an addon error is reported
-- as taint. Runs only if the box is still the same whisper by then.
local function Handle(editBox, chatType, target)
    if busy or not CanIntercept() or editBox:IsForbidden() or not editBox:IsShown() then return end
    local nowType, nowTarget = editBox:GetAttribute("chatType"), editBox:GetAttribute("tellTarget")
    if ns.IsSecret(nowType, nowTarget) or nowType ~= chatType or nowTarget ~= target then return end

    local convo
    if chatType == "BN_WHISPER" or target:find("^|K") then
        if not ns.settings.battleNet then return end
        local bnID = BNet_GetBNetIDAccount(target)
        convo = bnID and ns.GetBNConvo(bnID, true)
    else
        -- a character a Battle.net friend plays opens that friend's conversation
        convo = ns.ConvoForCharacter(target, nil, true)
    end
    if not convo then return end

    -- anything already typed after "/w name " comes along
    local text = editBox:GetText() or ""
    Release(editBox)
    ns.ShowWindow(convo, true)
    local input = ns.InputFor and ns.InputFor(convo)
    if input and text ~= "" and not text:find("^/") then input:SetText(text) end
end

-- In the hook: read only, and hand the rest to the next frame
local pending = {}
local function OnHeader(editBox)
    if busy or editBox:IsForbidden() or not CanIntercept() then return end
    if (ns.IsOwnInput and ns.IsOwnInput(editBox)) or pending[editBox] then return end
    local chatType, target = editBox:GetAttribute("chatType"), editBox:GetAttribute("tellTarget")
    if ns.IsSecret(chatType, target) then return end
    if (chatType ~= "WHISPER" and chatType ~= "BN_WHISPER") or type(target) ~= "string" or target == "" then return end
    pending[editBox] = true
    C_Timer.After(0, function()
        pending[editBox] = nil
        local ok, err = pcall(Handle, editBox, chatType, target)
        if not ok then geterrorhandler()(err) end
    end)
end

local function HookBox(editBox)
    if not editBox or hooked[editBox] or editBox:IsForbidden() then return end
    hooked[editBox] = true
    hooksecurefunc(editBox, "UpdateHeader", function(self)
        local ok, err = pcall(OnHeader, self)
        if not ok then geterrorhandler()(err) end
    end)
end

-- each chat edit box, as it is first activated
hooksecurefunc(ChatFrameUtil, "ActivateChat", HookBox)

-------------------------------------------------------------------------------
--  Settings shortcut and slash commands
-------------------------------------------------------------------------------
function ns.OpenSettings()
    if InCombatLockdown() then
        ns.Print("settings can't open in combat.")
        return
    end
    EllesmereUI:ShowModule("EllesmereUIMessaging")
end

SLASH_ELLESMEREUIMESSAGING1 = "/whispers"
SLASH_ELLESMEREUIMESSAGING2 = "/euiw"
SlashCmdList.ELLESMEREUIMESSAGING = function(msg)
    local raw = msg
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "history" then
        ns.ToggleHistory()
    elseif msg == "options" or msg == "settings" or msg == "config" then
        ns.OpenSettings()
    elseif msg == "test" or msg:match("^test%s") then
        -- /euiw test [name] [text] | /euiw test bn [text]
        -- (the original casing of the name and text, not the lowered msg)
        local args = (raw or ""):match("^%s*%S+%s*(.-)%s*$") or ""
        local first, rest = args:match("^(%S+)%s*(.*)$")
        if first and first:lower() == "bn" then
            ns.SimulateIncoming("bn", nil, rest)
        else
            ns.SimulateIncoming("char", first, rest)
        end
    elseif msg == "status" then
        -- what is in effect: the layout, the game's "New whispers" option,
        -- and which chat windows show whispers (tabs open only from those)
        ns.Print(("layout: %s | whisperMode: %s | bnWhisperMode: %s | kept: %s"):format(
            tostring(ns.settings.window.layout), tostring(C_CVar.GetCVar("whisperMode")),
            tostring(C_CVar.GetCVar("bnWhisperMode")), EllesmereUIDB.global.messagingWhisperMode and "yes" or "no"))
        ns.Print(("chat windows show whispers: %s, Battle.net whispers: %s"):format(
            tostring(ns.ChatShowsWhispers("char")), tostring(ns.ChatShowsWhispers("bn"))))
    elseif msg ~= "" and msg ~= "toggle" then
        -- /whispers <name> opens a conversation
        local name = msg:gsub("^%l", string.upper) -- (one value: gsub also returns a count)
        local convo = ns.ConvoForCharacter(name, nil, true)
        if convo then ns.ShowWindow(convo, true) end
    else
        ns.ToggleWindow()
    end
end
