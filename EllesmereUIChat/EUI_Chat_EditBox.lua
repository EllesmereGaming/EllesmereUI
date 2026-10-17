if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_EditBox.lua
--
--  The skinned-frame registry, the message events, the chat-state callbacks
--  and SkinEditBox.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIChat.lua or an earlier EUI_Chat_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local ECHAT = ns.ECHAT

local CFD, GetEditBoxFont, GetEditBoxFontSize = I.CFD, I.GetEditBoxFont, I.GetEditBoxFontSize
local GetEditBoxHeight, GetOutlineFlag = I.GetEditBoxHeight, I.GetOutlineFlag

-------------------------------------------------------------------------------
--  Chat frame reskin
-------------------------------------------------------------------------------
local _skinned = {}

-- Chat events counted as real PLAYER activity (used ONLY to wake the idle
-- fade): a line of one of these that lands in a shown chat window resets the
-- timer (the engine's idle observer, init section 6). Player chat only: NPC
-- lines (MONSTER_SAY / MONSTER_YELL) never wake it.
local CHAT_MSG_EVENTS = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_CHANNEL = true,
    -- WHISPER/BN_WHISPER are not listed: the whisper-sound event frame (init
    -- section 7) wakes the fade for every incoming whisper, wherever it shows.
    -- Outgoing _INFORM lines need nothing -- the edit-box focus-gained
    -- callback and OnChar hook already reset the fade.
}

-------------------------------------------------------------------------------
--  Tabs are fully owned (EllesmereUIChat_Tabs.lua): our buttons over our own
--  strip, styled from the same settings, with Blizzard's strip hidden. The
--  ECHAT.ApplyTab* entry points the options page calls are defined there.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Chat-state callbacks: header font, input-top strips, sent-line capture,
--  recall-cursor reset, idle-fade and hover focus tracking.
--
--  Deliberately NOT widget HookScripts on a Blizzard edit box. THE RULE: no
--  EUI code may execute inside a Blizzard chat-state execution. An addon
--  closure invoked by a script dispatch inside a secure execution leaves that
--  execution tainted after it returns, and the chat-state functions write the
--  edit box's chatType ATTRIBUTE after the script dispatches they perform:
--    * ChatFrameUtil.ActivateChat does editBox:Show() (dispatches OnShow) and
--      editBox:SetFocus() (dispatches OnEditFocusGained), THEN calls
--      editBox:UpdateHeader(), which smart-switches a sticky RAID/PARTY to
--      INSTANCE_CHAT with SetChatType (ChatFrameEditBox.lua:655/661).
--    * ChatFrameEditBoxMixin:Deactivate does SetText("") (OnTextChanged) and
--      ClearFocus() (OnEditFocusLost), THEN ResetChatTypeToSticky/
--      ResetChatType.
--  SendText reads that attribute back on EVERY later message, so one tainted
--  write makes every send a tainted caller of C_ChatInfo.SendChatMessage.
--  Ordinarily invisible; inside a chat messaging lockdown (encounter,
--  challenge mode, PvP match) the call refuses a tainted caller and the
--  message is silently swallowed -- the "RBG chat eats my messages" report.
--
--  EventRegistry is the sanctioned substitute: CallbackRegistryMixin
--  :TriggerEvent runs every registrant through securecallfunction, so our
--  taint stops at our own closure. Blizzard fires ChatFrame.OnEditBoxShow /
--  .OnEditBoxHide / .OnEditBoxFocusGained / .OnEditBoxFocusLost /
--  .OnEditBoxPreSendText for exactly these points. A constant owner string
--  replaces rather than stacks, so repeated skin passes are safe.
-------------------------------------------------------------------------------
local _chatStateCallbacksDone = false

-- Blizzard fires these callbacks for EVERY chat edit box, including the temp
-- whisper windows (11+). Deriving EUI state from one of those poisons
-- HistoryKeeper through the secret BN_WHISPER tellTarget, which is what the
-- "idx <= 10" gate in SkinEditBox exists to prevent, so the same filter has
-- to be re-applied inside each callback body.
local function PermanentEditBox(eb)
    if not eb or type(eb.GetName) ~= "function" then return false end
    local n = eb:GetName()
    local i = n and tonumber(n:match("^ChatFrame(%d+)EditBox$"))
    return i ~= nil and i <= 10
end

-- Shared registration point for the focus-gained side: the permanent-frame
-- gate is applied once and the owner string keeps repeat passes idempotent.
-- On ECHAT rather than a file local: EUI_Chat_Init.lua registers through it too.
function ECHAT._RegisterEditBoxFocusGained(owner, fn)
    if not (EventRegistry and EventRegistry.RegisterCallback) then return end
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusGained", function(_, eb)
        if not PermanentEditBox(eb) then return end
        fn(eb)
    end, owner)
end

local function EnsureChatStateCallbacks()
    if _chatStateCallbacksDone then return end
    if not (EventRegistry and EventRegistry.RegisterCallback) then return end
    _chatStateCallbacksDone = true

    -- Input-on-top strip reclaim. Blizzard triggers these from the first line
    -- of its own OnShow/OnHide, so the timing matches the HookScripts these
    -- replace; RefreshInputTopStrips rescans every frame, so one registration
    -- covers all of them.
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxShow", function(_, eb)
        if not PermanentEditBox(eb) then return end
        ECHAT.RefreshInputTopStrips()
    end, "EUI_Chat_InputTopShow")
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxHide", function(_, eb)
        if not PermanentEditBox(eb) then return end
        ECHAT.RefreshInputTopStrips()
    end, "EUI_Chat_InputTopHide")

    -- Sent-line capture for the Up/Down recall history. Blizzard triggers
    -- this from SendText, sequenced AFTER ParseText has stripped any slash
    -- header and BEFORE GetText, so a message is recorded as it is sent
    -- ("/raid hello" records "hello"). A line ParseText consumed (it ran the
    -- slash command and ClearChat emptied the box) reaches here as "" and is
    -- taken from the copy the edit box's OnKeyDown hook made at Enter.
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(_, eb)
        if not PermanentEditBox(eb) then return end
        local d = CFD(eb)
        local h = d.history
        if not h then return end
        local line = d.pendingLine
        d.pendingLine = nil
        local text = eb:GetText()
        -- type() and issecretvalue() BEFORE any comparison. `text == ""` on a
        -- secret string THROWS ("attempt to compare ... a secret string
        -- value"), and this callback runs inside SendText one line before
        -- SendChatMessage, so the throw would swallow the message and read as
        -- the very bug this file is fixing. A BN-whisper reply produces one.
        if type(text) ~= "string" then return end
        if issecretvalue and issecretvalue(text) then return end
        if text == "" and line then
            -- Kept only when ParseText ran it as an ADDON's command: that slot
            -- in Blizzard's slash table is addon-written, so a typed one runs as
            -- addon code from the slash lookup on (a recalled one runs the steps
            -- before it that way too, among them the import of newly registered
            -- commands). Blizzard's own commands run secure when typed and stay
            -- with the engine's Alt+Up/Down history (WoW Forever blocks /reload
            -- from addon code). Chat types and channel numbers are checked first,
            -- in ParseText's order: a line it reads as a chat type (an addon's
            -- own /raid included) would switch the box's chat type as addon code.
            local lineCmd = line:match("^(/[^%s]+)")
            local slots, types = hash_SlashCmdList, hash_ChatTypeInfoList
            if lineCmd and not lineCmd:match("^/%d+$")
                and type(slots) == "table" and type(types) == "table" then
                lineCmd = lineCmd:upper()
                local chatType = types[lineCmd]
                if not (chatType and ChatTypeInfo[chatType])
                    and slots[lineCmd] ~= nil and not issecurevariable(slots, lineCmd) then
                    text = line
                end
            end
        end
        if text == "" then return end
        -- ExtractChannel returns without SetText or ClearChat when the channel
        -- is not joined (ChatFrameEditBox.lua:123-125), so "/c <name> msg"
        -- survives to here whole. Harmless: recalling it re-sends what the
        -- user typed.
        local cmd = text:match("^%s*(/%S+)")
        if cmd and IsSecureCmd and IsSecureCmd(cmd) then return end
        if h[#h] ~= text then
            h[#h + 1] = text
            if #h > 50 then table.remove(h, 1) end
        end
    end, "EUI_Chat_SendLineCapture")

    -- Recall cursor reset. Blizzard triggers this at the top of
    -- OnEditFocusLost, one line before it reaches DeactivateChat, so the
    -- timing is identical to the HookScript this replaces.
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", function(_, eb)
        if not PermanentEditBox(eb) then return end
        CFD(eb).histIdx = 0
    end, "EUI_Chat_RecallReset")
end

-------------------------------------------------------------------------------
--  SkinEditBox: ALL edit box modifications in one place. Chrome/position/font
--  apply to ALL frames (including temp 11+); HOOKS only on frames 1-10.
-------------------------------------------------------------------------------
local function SkinEditBox(cf)
    local name = cf:GetName()
    if not name then return end
    local eb = _G[name .. "EditBox"]
    local idx = tonumber(name:match("ChatFrame(%d+)"))
    if not eb or not idx or CFD(eb).skinned then return end
    CFD(eb).skinned = true

    -- Stock styles keep Blizzard's own input box: its art (and the chat-type
    -- focus border), anchors, height and text insets are left alone; only
    -- the font follows the chat's, like the chat text itself. WoW Forever
    -- hides that art like the EllesmereUI look and seats the box in its kit.
    if not ns.ChatStockArt() then
    for _, texName in ipairs({
        name .. "EditBoxLeft", name .. "EditBoxMid", name .. "EditBoxRight",
        name .. "EditBoxFocusLeft", name .. "EditBoxFocusMid", name .. "EditBoxFocusRight",
    }) do
        local tex = _G[texName]
        if tex then tex:SetAlpha(0) end
    end
    if eb.focusLeft then eb.focusLeft:SetAlpha(0) end
    if eb.focusMid then eb.focusMid:SetAlpha(0) end
    if eb.focusRight then eb.focusRight:SetAlpha(0) end

    -- Flush below the chat frame, for ALL frames including temp 11+.
    if ns.ChatForever() then
        ECHAT.FV_PlaceEditBox(cf, eb, GetEditBoxHeight())
    else
    eb:ClearAllPoints()
    eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -10, -8)
    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -8)
    eb:SetHeight(GetEditBoxHeight())
    end
    end -- not stock art

    -- Same outline as the chat frames and ECHAT.ApplyFonts (both read
    -- GetOutlineFlag), so the input box always matches the rest of chat --
    -- hardcoding "" here leaves it un-outlined with the drop shadow showing.
    local ebSize = GetEditBoxFontSize(cf:GetID())
    eb:SetFont(GetEditBoxFont(), ebSize, GetOutlineFlag())
    if not ns.ChatStockArt() then eb:SetTextInsets(8, 8, 0, 0) end

    -- Custom font for the header ("Say:", "Party:", ...) and suffix. Called at
    -- skin time and on focus-gained (covers chat-type switches). NEVER call
    -- from inside UpdateHeader -- SetFont in that secure chain taints the
    -- execution context and blocks SendChatMessage.
    local function ApplyEditBoxHeaderFont(editBox)
        local sz = GetEditBoxFontSize(editBox:GetParent():GetID())
        local ol = GetOutlineFlag()
        if editBox.header then
            editBox.header:SetFont(GetEditBoxFont(), sz, ol)
        end
        if editBox.headerSuffix then
            editBox.headerSuffix:SetFont(GetEditBoxFont(), sz, ol)
        end
    end
    ApplyEditBoxHeaderFont(eb)

    -- Edit box HOOKS (not the plain setters above) taint a temp whisper
    -- window's execution context: when its secure code later touches its
    -- secret tellTarget (e.g. a BN_WHISPER presence ID), it poisons the
    -- shared ChatHistory access tables and EVERY chat message errors in
    -- HistoryKeeper for the rest of the session. Only permanent docked frames
    -- (1-10) may be hooked; temp windows (11+) get visuals only.
    if idx <= 10 then
        -- Header re-font and the input-on-top strip reclaim are EventRegistry
        -- callbacks, not HookScripts. Both of those dispatch points sit inside
        -- ChatFrameUtil.ActivateChat (Show() then SetFocus(), both ahead of the
        -- UpdateHeader() that writes chatType), so a script hook on either one
        -- taints the attribute every send reads back. Full rationale in the
        -- chat-state callbacks block above.
        EnsureChatStateCallbacks()
        ECHAT._RegisterEditBoxFocusGained("EUI_Chat_HeaderFont", ApplyEditBoxHeaderFont)

        -- Plain Up/Down input recall. The Midnight edit box performs no native recall
        -- on plain arrows regardless of alt-arrow mode, so recall is Lua-side over an
        -- external history. Two rules keep it taint-safe (breaking them blocks /ping
        -- with ADDON_ACTION_FORBIDDEN): (1) SECURE commands (IsSecureCmd: /ping,
        -- /cast, ...) NEVER enter this history -- SetText plants addon-tainted text,
        -- fatal for a protected re-send; (2) Alt chords pass through untouched --
        -- Alt+Up/Down stays the engine's own untainted recall, our SetText must never
        -- overwrite it. Alt-arrow mode must be OFF or the widget never hands plain
        -- Up/Down to the OnKeyDown hook.
        eb:SetAltArrowKeyMode(false)
        if not CFD(eb).history then
            CFD(eb).history = {}
            CFD(eb).histIdx = 0
            -- Sent-line capture lives in EnsureChatStateCallbacks, NOT in a
            -- script hook on this frame. hooksecurefunc(eb, "AddHistoryLine")
            -- reads as a function hook but is a FIELD WRITE onto the Blizzard
            -- edit box; the OnTextChanged shadow that replaced it dropped the
            -- field write but not the problem, since Deactivate's SetText("")
            -- dispatches OnTextChanged and then writes chatType. OnChar and
            -- OnKeyDown stay safe: physical input only, so they can never land
            -- inside SendText or Deactivate.
            eb:HookScript("OnKeyDown", function(self, key)
                if key == "ENTER" or key == "NUMPADENTER" then
                    -- OnKeyDown runs before the box acts on the key (the
                    -- template's BACKSPACE autocomplete guard relies on that
                    -- order), so the whole typed line is still here; ParseText
                    -- may run it and empty the box before the send callback
                    -- reads it. Read-only copy, consumed by that callback.
                    local line = self:GetText()
                    if type(line) ~= "string" or (issecretvalue and issecretvalue(line)) then
                        line = nil
                    end
                    CFD(self).pendingLine = line
                    return
                end
                if key ~= "UP" and key ~= "DOWN" then return end
                if IsAltKeyDown() then return end
                -- Restriction guards. Recall is SetText, and addon-planted edit
                -- box text alone makes SendText a tainted caller: it reads the
                -- text back at GetText() one line before SendChatMessage
                -- (ChatFrameEditBox.lua:289). Field-proven by shift-clicked item
                -- links, which Blizzard's InsertLink plants from a tainted click
                -- -- that one message is refused, a retype sends fine. Alt+Up/Down
                -- still recalls in a lockdown (the engine writes the text), so say
                -- so once rather than leaving a silently dead key.
                local restricted = GetCVarBool("addonChatRestrictionsForced")
                    or C_ChatInfo.InChatMessagingLockdown()
                    or (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
                        and C_ChallengeMode.IsChallengeModeActive())
                if restricted then
                    if not ECHAT._recallLockdownNoticeShown then
                        ECHAT._recallLockdownNoticeShown = true
                        local cf = self.chatFrame or DEFAULT_CHAT_FRAME
                        cf:AddMessage(EllesmereUI.L("Chat recall is unavailable here. Use Alt+Up and Alt+Down."))
                    end
                    return
                end
                local d = CFD(self)
                local h = d.history
                if #h == 0 then return end
                if key == "UP" then
                    d.histIdx = d.histIdx + 1
                    if d.histIdx > #h then d.histIdx = #h end
                else
                    d.histIdx = d.histIdx - 1
                    if d.histIdx < 0 then d.histIdx = 0 end
                end
                if d.histIdx == 0 then
                    self:SetText("")
                else
                    local entry = h[#h - d.histIdx + 1]
                    if entry then self:SetText(entry) else self:SetText("") end
                end
            end)
        end
    end
end

I._skinned, I.CHAT_MSG_EVENTS, I.SkinEditBox = _skinned, CHAT_MSG_EVENTS, SkinEditBox
I.broken = false
