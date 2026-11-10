if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_Bar.lua
--
--  Chat Bar (opt-in, chatBarEnabled): a row of buttons that pick the chat
--  type of the main input box, plus Roll, Ready Check / Pull and Reload.
--
--  Taint: no EUI code writes the edit box's chat state (the rule in
--  EUI_Chat_EditBox.lua). A channel button is a SecureActionButtonTemplate
--  "attribute" action: Blizzard's secure handler writes the box's chatType
--  from the hardware click, so the next send reads a value no addon wrote.
--  A world channel also needs channelTarget, which a wrapped OnClick sets
--  from the restricted environment. That environment reaches the unprotected
--  box only out of combat, so world channel buttons do nothing in combat.
--
--  The buttons are protected, so the bar sits on UIParent at numeric offsets
--  (an anchor to a chat frame would pull that frame into their anchor family
--  and lock it in combat) and every layout write waits for combat to end.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
if not I or I.broken then return end

local EUI = _G.EllesmereUI
local ECHAT = ns.ECHAT
local PP = EUI.PP
local CFD, GetFont, GetOutlineFlag = I.CFD, I.GetFont, I.GetOutlineFlag
local issecretvalue = _G.issecretvalue

local _alpha = I._chatAlphaCurrent
I.chatAlphaCurrentSetters[#I.chatAlphaCurrentSetters + 1] = function(v) _alpha = v end

-- Created inert: events are registered only while the bar is enabled.
local events = CreateFrame("Frame")

local CHANNELS = {
    { key = "chatBarShowSay",         chatType = "SAY",           label = "S" },
    { key = "chatBarShowYell",        chatType = "YELL",          label = "Y" },
    { key = "chatBarShowEmote",       chatType = "EMOTE",         label = "E" },
    { key = "chatBarShowParty",       chatType = "PARTY",         label = "P" },
    { key = "chatBarShowInstance",    chatType = "INSTANCE_CHAT", label = "I" },
    { key = "chatBarShowRaid",        chatType = "RAID",          label = "R" },
    { key = "chatBarShowRaidWarning", chatType = "RAID_WARNING",  label = "RW" },
    { key = "chatBarShowGuild",       chatType = "GUILD",         label = "G" },
    { key = "chatBarShowOfficer",     chatType = "OFFICER",       label = "O" },
}

local bar, header, box
local stdButtons, worldButtons, utilButtons = {}, {}, {}
local shown = {}
local registered = false

local function DB() return ECHAT.DB() end

local function Flag(v)
    if issecretvalue and issecretvalue(v) then return false end
    return v and true or false
end

local function Available(chatType)
    if chatType == "PARTY" then return Flag(IsInGroup(LE_PARTY_CATEGORY_HOME)) end
    if chatType == "INSTANCE_CHAT" then return Flag(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) end
    if chatType == "RAID" then return Flag(IsInRaid(LE_PARTY_CATEGORY_HOME)) end
    if chatType == "RAID_WARNING" then
        if not Flag(IsInRaid()) then return false end
        return Flag(UnitIsGroupLeader("player")) or Flag(UnitIsGroupAssistant("player"))
            or Flag(IsEveryoneAssistant and IsEveryoneAssistant())
    end
    if chatType == "GUILD" then return Flag(IsInGuild()) end
    if chatType == "OFFICER" then
        if not Flag(IsInGuild()) then return false end
        return not (C_GuildInfo and C_GuildInfo.IsGuildOfficer) or Flag(C_GuildInfo.IsGuildOfficer())
    end
    return true
end

local function TypeColor(btn)
    local info = btn.chatType and ChatTypeInfo[btn.channelId and ("CHANNEL" .. btn.channelId) or btn.chatType]
    if not info then info = ChatTypeInfo.SYSTEM end
    if info then return info.r or 1, info.g or 1, info.b or 1 end
    return 1, 1, 1
end

local function IsActive(btn)
    if not (box and btn.chatType) then return false end
    local current = box:GetAttribute("chatType")
    if current ~= btn.chatType then return false end
    if btn.channelId then return box:GetAttribute("channelTarget") == btn.channelId end
    return true
end

local function PaintButton(btn)
    local cfg = DB()
    local style = cfg.chatBarStyle or "square"
    local r, g, b = TypeColor(btn)
    if style == "block" then
        btn.text:Hide()
        btn.bg:SetColorTexture(r, g, b, cfg.chatBarBgAlpha or 0.65)
    else
        btn.text:Show()
        btn.text:SetTextColor(r, g, b)
        if style == "text" then
            btn.bg:SetColorTexture(0, 0, 0, 0)
        else
            btn.bg:SetColorTexture(cfg.bgR or 0.03, cfg.bgG or 0.045, cfg.bgB or 0.05, cfg.chatBarBgAlpha or 0.65)
        end
    end
    if IsActive(btn) then
        local ar, ag, ab = EUI.GetAccentColor()
        PP.SetBorderColor(btn, ar, ag, ab, 1)
        PP.ShowBorder(btn)
    elseif style ~= "text" and cfg.chatBarShowBorder ~= false then
        PP.SetBorderColor(btn, 1, 1, 1, 0.18)
        PP.ShowBorder(btn)
    else
        PP.HideBorder(btn)
    end
end

-- Reads the box's attributes only; repaints the active-channel border.
local function RefreshActive()
    for i = 1, #shown do PaintButton(shown[i]) end
end

local function ShowTip(btn)
    EUI.ShowWidgetTooltip(btn, btn.tip)
end

local function NewButton(secure)
    local btn = CreateFrame("Button", nil, bar, secure and "SecureActionButtonTemplate" or nil)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetPoint("CENTER")
    PP.CreateBorder(btn, 1, 1, 1, 0.18, 1, "OVERLAY", 7)
    btn:SetScript("OnEnter", ShowTip)
    btn:SetScript("OnLeave", function() EUI.HideWidgetTooltip() end)
    btn:Hide()
    return btn
end

local function NewChannelButton(chatType)
    local btn = NewButton(true)
    btn.chatType = chatType
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "attribute")
    btn:SetAttribute("attribute-frame", box)
    btn:SetAttribute("attribute-name", "chatType")
    btn:SetAttribute("attribute-value", chatType)
    btn:SetScript("PostClick", RefreshActive)
    return btn
end

-- World channel: the restricted pre-body sets both attributes and cancels the
-- click (no secure action left to run). Out of combat only: there the
-- restricted environment may reach the unprotected box.
local WORLD_PRE_CLICK = [[
    if button ~= "LeftButton" or PlayerInCombat() then return false end
    local eb = owner:GetFrameRef("box")
    eb:SetAttribute("channelTarget", self:GetAttribute("chatbar-channel"))
    eb:SetAttribute("chatType", "CHANNEL")
    return false
]]

local function NewWorldButton()
    local btn = NewButton(true)
    btn.chatType = "CHANNEL"
    btn:RegisterForClicks("AnyUp", "AnyDown")
    SecureHandlerWrapScript(btn, "OnClick", header, WORLD_PRE_CLICK)
    btn:SetScript("PostClick", RefreshActive)
    return btn
end

local function StartPull()
    local secs = DB().chatBarPullDuration or 10
    local handler = SlashCmdList.BIGWIGSPULL or SlashCmdList.DEADLYBOSSMODSPULL
    if handler then handler(tostring(secs)) end
    -- Blizzard's countdown travels through chat, which refuses it in lockdown.
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    C_PartyInfo.DoCountdown(secs)
end

local function NewUtilButton(label, tip, onClick)
    local btn = NewButton(false)
    btn.label = label
    btn.tip = tip
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", onClick)
    return btn
end

local function Build()
    box = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox or _G.ChatFrame1EditBox
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(100)
    bar:SetSize(1, 1)
    bar:SetAlpha(_alpha or 1)
    bar:Hide()
    ns._chatBar = bar

    header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    header:SetFrameRef("box", box)

    for i = 1, #CHANNELS do
        local info = CHANNELS[i]
        local btn = NewChannelButton(info.chatType)
        btn.label = info.label
        btn.tip = _G[info.chatType] or info.chatType
        stdButtons[i] = btn
    end

    utilButtons.roll = NewUtilButton("D",EllesmereUI.L("Roll"), function(_, button)
        if button == "LeftButton" then RandomRoll(1, 100) end
    end)
    utilButtons.ready = NewUtilButton("RC",
        EllesmereUI.L("Ready Check") .. "\n" .. EllesmereUI.L("Right Click") .. ": " .. EllesmereUI.L("Pull Timer"),
        function(_, button)
            if button == "RightButton" then StartPull() else DoReadyCheck() end
        end)
    utilButtons.reload = NewUtilButton("RL", EllesmereUI.L("Reload UI"), function(_, button)
        if button == "LeftButton" then ReloadUI() end
    end)
end

local function DefaultPosition()
    local cf1 = _G.ChatFrame1
    local strip = ns._chatTabStrip
    local ref = (strip and strip:IsShown() and strip:GetTop()) and strip or (cf1 and CFD(cf1).bg)
    local left, top = ref and ref:GetLeft(), ref and ref:GetTop()
    if not (left and top) then return 32, 220 end
    return left, top + 2
end

local function ApplyPosition()
    if not bar then return end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("chatBarPosition", ApplyPosition)
        return
    end
    bar:ClearAllPoints()
    local pos = DB().chatBarPosition
    if pos and pos.point then
        local x, y = pos.x or 0, pos.y or 0
        local es = bar:GetEffectiveScale()
        bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, PP.SnapForES(x, es), PP.SnapForES(y, es))
    else
        local x, y = DefaultPosition()
        bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
end

local function Layout()
    if not bar then return end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("chatBarLayout", Layout)
        return
    end
    local cfg = DB()
    for i = 1, #shown do shown[i]:Hide() end
    wipe(shown)

    local hideUnavailable = cfg.chatBarHideUnavailable ~= false
    for i = 1, #CHANNELS do
        local info = CHANNELS[i]
        if cfg[info.key] ~= false and (not hideUnavailable or Available(info.chatType)) then
            shown[#shown + 1] = stdButtons[i]
        end
    end

    if cfg.chatBarShowWorldChannels ~= false then
        local list, n = { GetChannelList() }, 0
        for i = 1, #list, 3 do
            local id, name, disabled = list[i], list[i + 1], list[i + 2]
            if type(id) == "number" and type(name) == "string" and not disabled then
                n = n + 1
                local btn = worldButtons[n]
                if not btn then
                    btn = NewWorldButton()
                    worldButtons[n] = btn
                end
                btn.channelId = id
                btn.label = tostring(id)
                btn.tip = name
                btn:SetAttribute("chatbar-channel", id)
                shown[#shown + 1] = btn
            end
        end
    end

    if cfg.chatBarShowRoll ~= false then shown[#shown + 1] = utilButtons.roll end
    if cfg.chatBarShowReadyCheck ~= false then shown[#shown + 1] = utilButtons.ready end
    if cfg.chatBarShowReload ~= false then shown[#shown + 1] = utilButtons.reload end

    local w, h = cfg.chatBarButtonWidth or 22, cfg.chatBarButtonHeight or 20
    local gap = cfg.chatBarSpacing or 2
    local font, size, flags = GetFont(), cfg.chatBarFontSize or 11, GetOutlineFlag()
    for i = 1, #shown do
        local btn = shown[i]
        btn:ClearAllPoints()
        btn:SetSize(w, h)
        btn:SetPoint("LEFT", bar, "LEFT", (i - 1) * (w + gap), 0)
        btn.text:SetFont(font, size, flags)
        btn.text:SetText(btn.label)
        PaintButton(btn)
        btn:Show()
    end
    local count = #shown
    bar:SetSize(count > 0 and (count * w + (count - 1) * gap) or 1, h)
    ApplyPosition()
end

local function RegisterUnlock()
    if registered or not EUI.RegisterUnlockElements then return end
    registered = true
    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key   = "ECHAT_ChatBar",
            label = "Chat Bar",
            group = "Chat",
            order = 602,
            noResize = true,
            noAnchorTo = true,
            getFrame = function() return bar end,
            getSize  = function() return bar:GetWidth(), bar:GetHeight() end,
            isHidden = function() return not DB().chatBarEnabled end,
            savePos = function(_, point, relPoint, x, y)
                DB().chatBarPosition = { point = point, relPoint = relPoint or point, x = x, y = y }
                if not EUI._unlockActive then ApplyPosition() end
            end,
            loadPos  = function() return DB().chatBarPosition end,
            clearPos = function() DB().chatBarPosition = nil end,
            applyPos = ApplyPosition,
        }),
    })
end

local function Enable()
    if InCombatLockdown() then
        ns.CombatQueue.Defer("chatBarApply", ECHAT.ApplyChatBar)
        return
    end
    if not bar then Build() end
    local cfg = DB()
    events:UnregisterAllEvents()
    events:SetScript("OnEvent", Layout)
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    if cfg.chatBarShowWorldChannels ~= false then events:RegisterEvent("CHANNEL_UI_UPDATE") end
    if cfg.chatBarHideUnavailable ~= false then
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterEvent("PARTY_LEADER_CHANGED")
        events:RegisterEvent("PLAYER_GUILD_UPDATE")
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", RefreshActive, "EUI_ChatBar")
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxHide", RefreshActive, "EUI_ChatBar")
    end
    RegisterUnlock()
    Layout()
    bar:Show()
end

local function Disable()
    events:UnregisterAllEvents()
    if EventRegistry and EventRegistry.UnregisterCallback then
        EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxFocusLost", "EUI_ChatBar")
        EventRegistry:UnregisterCallback("ChatFrame.OnEditBoxHide", "EUI_ChatBar")
    end
    if not bar then return end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("chatBarApply", ECHAT.ApplyChatBar)
        return
    end
    bar:Hide()
end

-- Options and init entry point: builds the bar on first enable.
function ECHAT.ApplyChatBar()
    if DB().chatBarEnabled then Enable() else Disable() end
end
