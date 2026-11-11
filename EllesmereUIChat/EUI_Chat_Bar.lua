if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_Bar.lua
--
--  Chat Bar (opt-in, chatBarEnabled): a row of buttons that pick the chat
--  type of the main input box, plus Roll, Raid Check, Timer and Reload.
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

-- Button labels: `en` is the English abbreviation; a locale gives its own
-- under the `abbr` key (EllesmereUILocales, "<name> (chat bar label)").
local CHANNELS = {
    { key = "chatBarShowSay",         chatType = "SAY",           abbr = "Say (chat bar label)",          en = "S" },
    { key = "chatBarShowYell",        chatType = "YELL",          abbr = "Yell (chat bar label)",         en = "Y" },
    { key = "chatBarShowInstance",    chatType = "INSTANCE_CHAT", abbr = "Instance (chat bar label)",     en = "I" },
    { key = "chatBarShowParty",       chatType = "PARTY",         abbr = "Party (chat bar label)",        en = "P" },
    { key = "chatBarShowRaid",        chatType = "RAID",          abbr = "Raid (chat bar label)",         en = "R" },
    { key = "chatBarShowRaidWarning", chatType = "RAID_WARNING",  abbr = "Raid Warning (chat bar label)", en = "RW" },
    { key = "chatBarShowGuild",       chatType = "GUILD",         abbr = "Guild (chat bar label)",        en = "G" },
    { key = "chatBarShowOfficer",     chatType = "OFFICER",       abbr = "Officer (chat bar label)",      en = "O" },
    { key = "chatBarShowEmote",       chatType = "EMOTE",         abbr = "Emote (chat bar label)",        en = "E" },
}

local function Short(abbr, en)
    local s = EllesmereUI.L(abbr)
    if s == abbr then return en end
    return s
end

local bar, header, box
local stdButtons, worldButtons, utilButtons = {}, {}, {}
local shown = {}
local registered = false

local function DB() return ECHAT.DB() end

-- A chat messaging lockdown (encounter, Mythic+, rated PvP) refuses tainted
-- sends and addon chat traffic.
local function InChatLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() or false
end

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

-- The chat's look (Global Settings > Style), latched with it for the session:
-- "eui", "blizzard", "classic" or "forever". Read once, when the bar is built.
local look

-- Stock looks: the art of the chat sidebar's buttons under the same look
-- (EllesmereUIChat_SidebarStock.lua). The picked channel keeps the idle art
-- (the pressed one loses the frame under the fill) and is lit inside it.
local KITS = {
    blizzard = {
        up   = { atlas = "chatframe-button-up" },
        hl   = { atlas = "chatframe-button-highlight" },
    },
    classic = {
        up   = { file = "Interface\\Buttons\\UI-SquareButton-Up", desat = true },
        hl   = { file = "Interface\\Buttons\\UI-Common-MouseHilight" },
    },
}
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0
-- The picked channel under the stock looks, as the WoW Forever selected tab:
-- a warm light rising inside the button's frame (GLOW_INSET in from its
-- edges). Blizzard Style and Classic also lay that tab's dark warm body
-- (FILL_*) under it; WoW Forever warms its own plate instead.
-- Inset { sides, top, bottom }: Blizzard's plate is thicker at the bottom,
-- the vanilla bevel is thick all round.
local GLOW_INSET = { blizzard = { 4, 4, 6 }, classic = { 5, 5, 5 }, forever = { 3, 3, 3 } }
local GLOW_BOTTOM = CreateColor(1, 0.7, 0.35, 0.35)
local GLOW_TOP = CreateColor(1, 0.7, 0.35, 0)
local FILL_BOTTOM = CreateColor(0.17, 0.09, 0.035, 0.95)
local FILL_TOP = CreateColor(0.12, 0.063, 0.024, 0.95)

local function LatchLook()
    local style = ns.ChatStyle and ns.ChatStyle() or "eui"
    if style == "blizzard" and ns.ChatForever and ns.ChatForever() and ECHAT.FV_Plate then
        look = "forever"
    elseif style == "blizzard" and C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(KITS.blizzard.up.atlas) then
        look = "blizzard"
    elseif style == "classic" then
        look = "classic"
    else
        look = "eui"
    end
end

local function SetArt(tex, e)
    if e.atlas then
        tex:SetAtlas(e.atlas)
    else
        tex:SetTexture(e.file)
        tex:SetDesaturated(e.desat == true)
    end
end

-- Channel buttons wear their chat type's colour; the others the look's own
-- label colour (white, Blizzard's gold, the WoW Forever tan).
local function LabelColor(btn)
    if btn.chatType then
        local info = ChatTypeInfo[btn.channelId and ("CHANNEL" .. btn.channelId) or btn.chatType]
            or ChatTypeInfo.SYSTEM
        if info then return info.r or 1, info.g or 1, info.b or 1 end
        return 1, 1, 1
    end
    if look == "forever" then
        local tan = ECHAT.FV.tan
        return tan[1], tan[2], tan[3]
    end
    if look ~= "eui" then return GOLD_R, GOLD_G, GOLD_B end
    return 1, 1, 1
end

local function IsActive(btn)
    if not (box and btn.chatType) then return false end
    local current = box:GetAttribute("chatType")
    if current ~= btn.chatType then return false end
    if btn.channelId then return box:GetAttribute("channelTarget") == btn.channelId end
    return true
end

-- The picked channel: the EllesmereUI look underlines it in the accent colour
-- (as the chat tabs mark the selected one). The stock looks light it from
-- inside like the WoW Forever selected tab.
local function PaintButton(btn)
    local active = IsActive(btn)
    btn.text:SetTextColor(LabelColor(btn))
    if look == "eui" then
        local cfg = DB()
        -- The chat background's opacity unless the bar has its own; darker
        -- while picked, by the step between an idle and the selected tab.
        local a
        if cfg.chatBarBgCustom then
            a = cfg.chatBarBgAlpha or cfg.bgAlpha or 0.65
        else
            a = cfg.bgAlpha or 0.65
        end
        if active then a = min(1, a + 0.21) end
        btn.bg:SetColorTexture(cfg.bgR or 0.03, cfg.bgG or 0.045, cfg.bgB or 0.05, a)
        -- The underline follows the tabs' Active Underline setting.
        local underline = active and cfg.activeUnderline ~= false
        if underline then
            local ar, ag, ab = EUI.GetAccentColor()
            btn.underline:SetColorTexture(ar, ag, ab, 1)
        end
        btn.underline:SetShown(underline)
        return
    end
    btn.glow:SetShown(active)
    if btn.fill then btn.fill:SetShown(active) end
    if look == "forever" and btn._down ~= active then
        btn._down = active
        local c = active and ECHAT.FV.tabSel or ECHAT.FV.plateFill
        btn._fvPlate.fill:SetColorTexture(c[1], c[2], c[3], c[4])
    end
end

-- Reads the box's attributes only; repaints the picked-channel marker.
local function RefreshActive()
    for i = 1, #shown do PaintButton(shown[i]) end
end

-- Closing the box: Blizzard fires these callbacks first and resets the
-- box's chat type to the sticky one after them (Deactivate), so the marker
-- is repainted on the next frame, once the reset has landed.
local function RefreshSoon()
    C_Timer.After(0, RefreshActive)
end

-- After a channel click: with chatBarOpenOnClick (off by default), open the
-- input box on the type the secure action just picked. Opening it runs
-- Blizzard's ActivateChat from addon code, which leaves that execution
-- tainted; per THE RULE (EUI_Chat_EditBox.lua) its UpdateHeader may write
-- the box's chatType there, and a tainted chatType makes later sends tainted,
-- which a chat messaging lockdown (encounter, Mythic+, rated PvP) refuses.
-- So the option is opt-in with that warning, and it never runs inside a
-- lockdown. Off, the click only picks the type and Enter opens the box on
-- it. A world channel picks nothing in combat (its restricted body stands
-- down), so the box stays shut there too.
local ActivateChat = (ChatFrameUtil and ChatFrameUtil.ActivateChat) or _G.ChatEdit_ActivateChat
local function OpenChat(btn, button, down)
    RefreshActive()
    if button ~= "LeftButton" or DB().chatBarOpenOnClick ~= true then return end
    -- Both edges reach PostClick (AnyUp + AnyDown); act on the one the
    -- secure action used.
    if (down and true or false) ~= GetCVarBool("ActionButtonUseKeyDown") then return end
    if btn.channelId and InCombatLockdown() then return end
    if InChatLockdown() then return end
    if ActivateChat and box then ActivateChat(box) end
end

-- Hovering the bar counts as hovering the chat: it lifts the idle fade
-- the same way (ECHAT.ChatHover, EUI_Chat_Init.lua).
-- Out of use in combat: world channels (their restricted body stands down)
-- and the utility buttons (their clicks stand down). In combat they ignore
-- hover too, and dim with chatBarDimInCombat.
local function CombatLocked(btn)
    return btn.channelId ~= nil or btn.chatType == nil
end

-- Hover is drawn by hand (not a HIGHLIGHT layer) so a button out of use in
-- combat can show none.
local function SetHover(btn, on)
    if btn.hover then btn.hover:SetShown(on) end
    if look == "forever" then ECHAT.FV_PlateLift(btn, on) end
end

local function OnEnter(btn)
    if ECHAT.ChatHover then ECHAT.ChatHover(true) end
    if CombatLocked(btn) and InCombatLockdown() then return end
    SetHover(btn, true)
    EUI.ShowWidgetTooltip(btn, btn.tip)
end

local function OnLeave(btn)
    SetHover(btn, false)
    EUI.HideWidgetTooltip()
    if ECHAT.ChatHover then ECHAT.ChatHover(false) end
end

local function NewButton(secure)
    local btn = CreateFrame("Button", nil, bar, secure and "SecureActionButtonTemplate" or nil)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    if look == "forever" then
        -- The sidebar's bronze plate, its line warmed on hover (SetHover).
        btn.bg:Hide()
        ECHAT.FV_Plate(btn, true)
    else
        local hl = btn:CreateTexture(nil, "ARTWORK", nil, 7)
        hl:SetAllPoints()
        hl:Hide()
        btn.hover = hl
        local kit = KITS[look]
        if kit then
            SetArt(btn.bg, kit.up)
            SetArt(hl, kit.hl)
            hl:SetBlendMode("ADD")
        else
            hl:SetColorTexture(1, 1, 1, 0.08)
            local underline = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            underline:SetHeight(2 * (PP.mult or 1))
            underline:SetPoint("BOTTOMLEFT")
            underline:SetPoint("BOTTOMRIGHT")
            if PP.DisablePixelSnap then PP.DisablePixelSnap(underline) end
            underline:Hide()
            btn.underline = underline
        end
    end
    if look ~= "eui" then
        local x, top, bottom = unpack(GLOW_INSET[look])
        if look ~= "forever" then
            local fill = btn:CreateTexture(nil, "BORDER")
            fill:SetPoint("TOPLEFT", x, -top)
            fill:SetPoint("BOTTOMRIGHT", -x, bottom)
            fill:SetTexture("Interface\\Buttons\\WHITE8X8")
            fill:SetGradient("VERTICAL", FILL_BOTTOM, FILL_TOP)
            fill:Hide()
            btn.fill = fill
        end
        local glow = btn:CreateTexture(nil, "ARTWORK")
        glow:SetPoint("TOPLEFT", x, -top)
        glow:SetPoint("BOTTOMRIGHT", -x, bottom)
        glow:SetTexture("Interface\\Buttons\\WHITE8X8")
        glow:SetBlendMode("ADD")
        glow:SetGradient("VERTICAL", GLOW_BOTTOM, GLOW_TOP)
        glow:Hide()
        btn.glow = glow
    end
    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetPoint("CENTER")
    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)
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
    btn:SetScript("PostClick", OpenChat)
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
    btn:SetScript("PostClick", OpenChat)
    return btn
end

-- Timer button: left click starts a pull (chatBarPullDuration, seconds),
-- right click a break (chatBarBreakMinutes), announced to the group with
-- chatBarBreakAnnounce; middle click resets both.

local function Secs(n)
    return format(_G.SECOND_ONELETTER_ABBR or "%d s", n)
end

local function Mins(n)
    return format(_G.MINUTE_ONELETTER_ABBR or "%d m", n)
end

-- Blizzard's countdown travels through chat, which refuses it in lockdown.
local function Countdown(secs)
    if InChatLockdown() then return end
    C_PartyInfo.DoCountdown(secs)
end

local function StartPull(secs)
    local handler = SlashCmdList.BIGWIGSPULL or SlashCmdList.DEADLYBOSSMODSPULL
    if handler then handler(tostring(secs)) end
    Countdown(secs)
end

-- A break runs on the boss mod's break bar (minutes), else the game's
-- countdown.
local function StartBreak(mins)
    local bigWigs, dbm = SlashCmdList.BIGWIGSBREAK, SlashCmdList.DEADLYBOSSMODS
    if bigWigs then
        bigWigs(tostring(mins))
    elseif dbm then
        dbm("break " .. mins)
    else
        Countdown(mins * 60)
    end
end

-- Middle click: cancels both, the boss mod's bars and the game's countdown
-- (a 0 cancels each).
local function StopTimers()
    local pull = SlashCmdList.BIGWIGSPULL or SlashCmdList.DEADLYBOSSMODSPULL
    if pull then pull("0") end
    local bigWigs, dbm = SlashCmdList.BIGWIGSBREAK, SlashCmdList.DEADLYBOSSMODS
    if bigWigs then
        bigWigs("0")
    elseif dbm then
        dbm("break 0")
    end
    Countdown(0)
end

-- The group's chat for the break notice: the instance group first (its
-- RAID/PARTY chat does not reach a queued group), none while solo.
local function GroupChat()
    if Flag(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) then return "INSTANCE_CHAT" end
    if Flag(IsInRaid()) then return "RAID" end
    if Flag(IsInGroup()) then return "PARTY" end
end

-- An addon send is refused in a chat messaging lockdown; it touches no edit
-- box state, so it needs no other care.
local function AnnounceBreak(mins)
    local chatType = GroupChat()
    if not chatType then return end
    if InChatLockdown() then return end
    C_ChatInfo.SendChatMessage(EllesmereUI.Lf("Break for %1$d min.", mins), chatType)
end

local function TimerTip(cfg)
    return EllesmereUI.L("Pull Timer") .. " (" .. Secs(cfg.chatBarPullDuration or 10) .. ")\n"
        .. EllesmereUI.L("Right Click") .. ": " .. EllesmereUI.L("Break Timer")
        .. " (" .. Mins(cfg.chatBarBreakMinutes or 5) .. ")\n"
        .. EllesmereUI.L("Middle Click") .. ": " .. EllesmereUI.L("Reset Timer")
end

-- Roll, Raid Check, Timer and Reload stand down in combat.
local function NewUtilButton(label, tip, onClick)
    local btn = NewButton(false)
    btn.label = label
    btn.tip = tip
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if InCombatLockdown() then return end
        onClick(self, button)
    end)
    return btn
end

-- chatBarDimInCombat: the buttons out of use in combat dim there.
local COMBAT_ALPHA = 0.35

local function PaintCombat(inCombat)
    local a = inCombat and COMBAT_ALPHA or 1
    for i = 1, #shown do
        local btn = shown[i]
        if CombatLocked(btn) then btn:SetAlpha(a) end
    end
end

local function Build()
    LatchLook()
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
        btn.label = Short(info.abbr, info.en)
        btn.tip = _G[info.chatType] or info.chatType
        stdButtons[i] = btn
    end

    utilButtons.roll = NewUtilButton(Short("Roll (chat bar label)", "R"), EllesmereUI.L("Roll"), function(_, button)
        if button == "LeftButton" then RandomRoll(1, 100) end
    end)
    utilButtons.ready = NewUtilButton(Short("Ready Check (chat bar label)", "RC"),
        EllesmereUI.L("Ready Check") .. "\n" .. EllesmereUI.L("Right Click") .. ": " .. EllesmereUI.L("Role Check"),
        function(_, button)
            if button == "RightButton" then InitiateRolePoll() else DoReadyCheck() end
        end)
    -- Its tooltip names the set duration (Layout).
    utilButtons.pull = NewUtilButton(Short("Timer (chat bar label)", "T"), nil, function(_, button)
        local cfg = DB()
        if button == "MiddleButton" then
            StopTimers()
        elseif button == "RightButton" then
            local mins = cfg.chatBarBreakMinutes or 5
            StartBreak(mins)
            if cfg.chatBarBreakAnnounce ~= false then AnnounceBreak(mins) end
        else
            StartPull(cfg.chatBarPullDuration or 10)
        end
    end)
    utilButtons.pull:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    utilButtons.reload = NewUtilButton(Short("Reload UI (chat bar label)", "RL"), EllesmereUI.L("Reload UI"), function(_, button)
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
    if cfg.chatBarShowPullTimer ~= false then
        utilButtons.pull.tip = TimerTip(cfg)
        shown[#shown + 1] = utilButtons.pull
    end
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
    PaintCombat(false)
    local count = #shown
    bar:SetSize(count > 0 and (count * w + (count - 1) * gap) or 1, h)
    ApplyPosition()
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        PaintCombat(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        PaintCombat(false)
    else
        Layout()
    end
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
    events:SetScript("OnEvent", OnEvent)
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Combat state for the dimmed buttons (both edges: this tracks combat,
    -- it defers nothing).
    if cfg.chatBarDimInCombat ~= false then
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    if cfg.chatBarShowWorldChannels ~= false then events:RegisterEvent("CHANNEL_UI_UPDATE") end
    if cfg.chatBarHideUnavailable ~= false then
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterEvent("PARTY_LEADER_CHANGED")
        events:RegisterEvent("PLAYER_GUILD_UPDATE")
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", RefreshSoon, "EUI_ChatBar")
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxHide", RefreshSoon, "EUI_ChatBar")
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
