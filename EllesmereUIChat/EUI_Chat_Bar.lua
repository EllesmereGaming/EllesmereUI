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
-- `name` is the tooltip. Labels and tooltips follow the EUI options language
-- (EllesmereUI.L), not the client's, like the rest of the addon.
local CHANNELS = {
    { key = "chatBarShowSay",         chatType = "SAY",           abbr = "Say (chat bar label)",          en = "S", name = "Say" },
    { key = "chatBarShowYell",        chatType = "YELL",          abbr = "Yell (chat bar label)",         en = "Y", name = "Yell" },
    { key = "chatBarShowInstance",    chatType = "INSTANCE_CHAT", abbr = "Instance (chat bar label)",     en = "I", name = "Instance" },
    { key = "chatBarShowParty",       chatType = "PARTY",         abbr = "Party (chat bar label)",        en = "P", name = "Party" },
    { key = "chatBarShowRaid",        chatType = "RAID",          abbr = "Raid (chat bar label)",         en = "R", name = "Raid" },
    { key = "chatBarShowRaidWarning", chatType = "RAID_WARNING",  abbr = "Raid Warning (chat bar label)", en = "RW", name = "Raid Warning" },
    { key = "chatBarShowGuild",       chatType = "GUILD",         abbr = "Guild (chat bar label)",        en = "G", name = "Guild" },
    { key = "chatBarShowOfficer",     chatType = "OFFICER",       abbr = "Officer (chat bar label)",      en = "O", name = "Officer" },
    { key = "chatBarShowEmote",       chatType = "EMOTE",         abbr = "Emote (chat bar label)",        en = "E", name = "Emote" },
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

-- Leader or assistant of the group (everyone is one in an everyone-assist raid).
local function CanLead()
    return Flag(UnitIsGroupLeader("player")) or Flag(UnitIsGroupAssistant("player"))
        or (Flag(IsInRaid()) and Flag(IsEveryoneAssistant and IsEveryoneAssistant()))
end

-- The timer follows the rules of the boss mod that shows it (BigWigs wins
-- when both are loaded, as its /pull and /break do), read from their code:
--   BigWigs /pull (Pull.lua): solo, the leader or an assist, the tank of a
--     group-finder group, anyone in a home party (not a raid).
--   BigWigs /break (Break.lua): solo, the leader or an assist.
--   DBM CreatePullTimer / CreateBreakTimer (UserTimers.lua): solo, the
--     leader or an assist, the tank of a group-finder group; never in a
--     battleground.
-- Without either the game's countdown is all there is: BigWigs' /pull rule
-- (it runs that very countdown), and the break as BigWigs'.
-- Encounters and the chat lockdown are refused by all of them; the timer's
-- usable() and the combat lock cover those.
local function BossMod()
    if _G.BigWigsAPI then return "bigwigs" end
    if _G.DBM then return "dbm" end
end

local function GroupFinderTank()
    return Flag(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) and UnitGroupRolesAssigned("player") == "TANK"
end

local function InBattleground()
    local _, instanceType = IsInInstance()
    return instanceType == "pvp"
end

local function CanCountdown()
    if not Flag(IsInGroup()) then return true end
    if BossMod() == "dbm" then
        return (CanLead() or GroupFinderTank()) and not InBattleground()
    end
    return CanLead() or GroupFinderTank()
        or (Flag(IsInGroup(LE_PARTY_CATEGORY_HOME)) and not Flag(IsInRaid()))
end

local function CanBreak()
    if not Flag(IsInGroup()) then return true end
    if BossMod() == "dbm" then
        return (CanLead() or GroupFinderTank()) and not InBattleground()
    end
    return CanLead()
end

local function Available(chatType)
    if chatType == "PARTY" then return Flag(IsInGroup(LE_PARTY_CATEGORY_HOME)) end
    if chatType == "INSTANCE_CHAT" then return Flag(IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) end
    if chatType == "RAID" then return Flag(IsInRaid(LE_PARTY_CATEGORY_HOME)) end
    if chatType == "RAID_WARNING" then
        return Flag(IsInRaid()) and CanLead()
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
-- The picked channel under Blizzard Style and Classic fills the inside of
-- the button's frame (FILL_INSET in from its edges) with the channel's
-- colour; WoW Forever colours its own plate instead.
-- Inset { sides, top, bottom }: Blizzard's plate is thicker at the bottom,
-- the vanilla bevel is thick all round.
local FILL_INSET = { blizzard = { 4, 4, 6 }, classic = { 5, 5, 5 } }

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

local ACTIVE_STEP = 0.21

-- The picked channel. The EllesmereUI look, chatBarActiveStyle:
--   "line" (default): the button darkens and is underlined in the channel's
--     colour;
--   "fill": the button fills with a dark shade of the channel's colour.
-- Blizzard Style, Classic and WoW Forever always fill (the inside of their
-- frame, or the Forever plate). A filled button's label turns white so it
-- stays readable.
local FILL_SHADE = 0.45

local function PaintButton(btn)
    local active = IsActive(btn)
    local cr, cg, cb = LabelColor(btn)
    local cfg = DB()
    local fill = active and (look ~= "eui" or cfg.chatBarActiveStyle == "fill")
    if fill then
        btn.text:SetTextColor(1, 1, 1)
    else
        btn.text:SetTextColor(cr, cg, cb)
    end
    local sr, sg, sb = cr * FILL_SHADE, cg * FILL_SHADE, cb * FILL_SHADE
    if look == "eui" then
        -- The chat background's opacity unless the bar has its own; darker
        -- while picked, by the step between an idle and the selected tab.
        -- The idle buttons stop that step short of opaque, so the picked one
        -- stays darker at any opacity.
        local a
        if cfg.chatBarBgCustom then
            a = cfg.chatBarBgAlpha or cfg.bgAlpha or 0.65
        else
            a = cfg.bgAlpha or 0.65
        end
        a = min(a, 1 - ACTIVE_STEP)
        if active then a = a + ACTIVE_STEP end
        if fill then
            btn.bg:SetColorTexture(sr, sg, sb, max(a, 0.9))
        else
            btn.bg:SetColorTexture(cfg.bgR or 0.03, cfg.bgG or 0.045, cfg.bgB or 0.05, a)
        end
        local line = active and not fill
        if line then btn.underline:SetColorTexture(cr, cg, cb, 1) end
        btn.underline:SetShown(line)
        return
    end
    if btn.fill then
        if fill then
            btn.fill:SetGradient("VERTICAL", CreateColor(sr, sg, sb, 0.95),
                CreateColor(sr * 0.75, sg * 0.75, sb * 0.75, 0.95))
        end
        btn.fill:SetShown(fill)
    end
    if look == "forever" then
        if fill then
            btn._fvPlate.fill:SetColorTexture(sr, sg, sb, 1)
        else
            local c = ECHAT.FV.plateFill
            btn._fvPlate.fill:SetColorTexture(c[1], c[2], c[3], c[4])
        end
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

-- One rule for every button: it is usable or it is not. An unusable one is
-- hidden with chatBarHideUnavailable, else shown dimmed; either way it takes
-- no click and no hover. Usable: a channel the player can write to
-- (Available), a tool whose own usable() holds (rights, lockdown).
-- In combat the same goes for world channels (their restricted body stands
-- down) and the tools; those dim there only with chatBarDimInCombat.
local function CombatLocked(btn)
    return btn.channelId ~= nil or btn.chatType == nil
end

local function Usable(btn)
    if btn.usable then return btn.usable() end
    if btn.chatType and not btn.channelId then return Available(btn.chatType) end
    return true
end

local function Inert(btn)
    return (InCombatLockdown() and CombatLocked(btn)) or not Usable(btn)
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
    if Inert(btn) or InChatLockdown() then return end
    if ActivateChat and box then ActivateChat(box) end
end

-- Hover is drawn by hand (not a HIGHLIGHT layer) so a button out of use in
-- combat can show none.
local function SetHover(btn, on)
    if btn.hover then btn.hover:SetShown(on) end
    if look == "forever" then ECHAT.FV_PlateLift(btn, on) end
end

-- Hovering the bar counts as hovering the chat: it lifts the idle fade
-- the same way (ECHAT.ChatHover, EUI_Chat_Init.lua), inert buttons included.
local function OnEnter(btn)
    if ECHAT.ChatHover then ECHAT.ChatHover(true) end
    if Inert(btn) then return end
    SetHover(btn, true)
    EUI.ShowWidgetTooltip(btn, btn.tipFn and btn.tipFn() or btn.tip)
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
    local inset = FILL_INSET[look]
    if inset then
        local x, top, bottom = inset[1], inset[2], inset[3]
        local fill = btn:CreateTexture(nil, "BORDER")
        fill:SetPoint("TOPLEFT", x, -top)
        fill:SetPoint("BOTTOMRIGHT", -x, bottom)
        fill:SetTexture("Interface\\Buttons\\WHITE8X8")
        fill:Hide()
        btn.fill = fill
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
    return EllesmereUI.Lf("%1$d sec", n)
end

local function Mins(n)
    return EllesmereUI.Lf("%1$d min", n)
end

-- The pull is the game's own countdown: BigWigs and DBM run exactly that for
-- /pull and draw their pull bar for any countdown (START_PLAYER_COUNTDOWN),
-- and a countdown of 0 cancels it for both. It travels through chat, which
-- refuses it in lockdown.
local function Countdown(secs)
    if InChatLockdown() then return end
    C_PartyInfo.DoCountdown(secs)
end

-- The game has no break timer: BigWigs and DBM send theirs as addon messages
-- each understands (BigWigs' /break also sends DBM's). Without either the
-- break falls back to the game's countdown, which boss mods in the group
-- show as a pull, so the group notice says it is a break.
-- BigWigs registers /break as SlashCmdList["break"] (trusted only with
-- BigWigs up); DBM's /dbm takes "break N" (0 cancels for both).
local function BreakHandler()
    local bigWigs = _G.BigWigsAPI and SlashCmdList["break"]
    if bigWigs then return bigWigs end
    local dbm = SlashCmdList.DEADLYBOSSMODS
    if dbm then
        return function(mins) dbm("break " .. mins) end
    end
end

local function StartBreak(mins)
    local handler = BreakHandler()
    if handler then
        handler(tostring(mins))
    else
        Countdown(mins * 60)
    end
end

-- Middle click: cancels the pull countdown (the button is usable only for
-- whoever may start one) and, under the same rule as starting it, the break.
local function StopTimers()
    Countdown(0)
    if not CanBreak() then return end
    local handler = BreakHandler()
    if handler then handler("0") end
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

-- Built on hover: the break line follows the player's rights (grey, with
-- the reason, without them) and whether a boss mod runs the break.
local function TimerTip()
    local cfg = DB()
    local tip = EllesmereUI.L("Pull Timer") .. " (" .. Secs(cfg.chatBarPullDuration or 10) .. ")"
    local breakLine = EllesmereUI.L("Right Click") .. ": " .. EllesmereUI.L("Break Timer")
        .. " (" .. Mins(cfg.chatBarBreakMinutes or 5) .. ")"
    if CanBreak() then
        tip = tip .. "\n" .. breakLine
        if not BreakHandler() then
            tip = tip .. "\n|cff999999" .. EllesmereUI.L("Without BigWigs or DBM: the game's countdown and a group notice.") .. "|r"
        end
    else
        -- Grey, with the reason: the right click does nothing for this player.
        tip = tip .. "\n|cff999999" .. breakLine .. "\n"
            .. EllesmereUI.L("Only the group's leader or an assist can start a break.") .. "|r"
    end
    tip = tip .. "\n" .. EllesmereUI.L("Middle Click") .. ": " .. EllesmereUI.L("Reset Timer")
    return tip
end

-- Roll, Raid Check, Timer and Reload: no click while inert (Inert).
local function NewUtilButton(label, tip, onClick, usable)
    local btn = NewButton(false)
    btn.label = label
    btn.tip = tip
    btn.usable = usable
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if Inert(self) then return end
        onClick(self, button)
    end)
    return btn
end

local DIM_ALPHA = 0.35

-- Unusable buttons are dim; in combat the combat-locked ones too, with
-- chatBarDimInCombat. inCombat comes from the combat events.
local function PaintState(inCombat)
    local dimCombat = inCombat and DB().chatBarDimInCombat ~= false
    for i = 1, #shown do
        local btn = shown[i]
        local dim = not Usable(btn) or (dimCombat and CombatLocked(btn))
        btn:SetAlpha(dim and DIM_ALPHA or 1)
    end
end

local function Build()
    LatchLook()
    box = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox or _G.ChatFrame1EditBox
    bar = CreateFrame("Frame", nil, UIParent)
    -- Above the chat tab strip (MEDIUM 100, EllesmereUIChat_Tabs.lua): the
    -- bar sits on its top edge, and at the same level the strip could draw
    -- over the buttons' bottom pixels.
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(110)
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
        btn.tip = EllesmereUI.L(info.name)
        stdButtons[i] = btn
    end

    utilButtons.roll = NewUtilButton(Short("Roll (chat bar label)", "R"), EllesmereUI.L("Roll"), function(_, button)
        if button == "LeftButton" then RandomRoll(1, 100) end
    end)
    utilButtons.ready = NewUtilButton(Short("Ready Check (chat bar label)", "RC"),
        EllesmereUI.L("Ready Check") .. "\n" .. EllesmereUI.L("Right Click") .. ": " .. EllesmereUI.L("Role Check"),
        function(_, button)
            if button == "RightButton" then InitiateRolePoll() else DoReadyCheck() end
        end,
        function() return Flag(IsInGroup()) and CanLead() end)
    utilButtons.pull = NewUtilButton(Short("Timer (chat bar label)", "T"), nil, function(_, button)
        local cfg = DB()
        if button == "MiddleButton" then
            StopTimers()
        elseif button == "RightButton" then
            if not CanBreak() then return end
            local mins = cfg.chatBarBreakMinutes or 5
            StartBreak(mins)
            if cfg.chatBarBreakAnnounce ~= false then AnnounceBreak(mins) end
        else
            Countdown(cfg.chatBarPullDuration or 10)
        end
    end,
    -- The countdown travels through chat, which a lockdown refuses.
    function() return CanCountdown() and not InChatLockdown() end)
    utilButtons.pull.tipFn = TimerTip
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
        local btn = stdButtons[i]
        local usable = Available(info.chatType)
        -- An unusable channel shown dim must not pick its type either.
        btn:SetAttribute("type1", usable and "attribute" or nil)
        if cfg[info.key] ~= false and (usable or not hideUnavailable) then
            shown[#shown + 1] = btn
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

    local tools = {
        { "chatBarShowRoll", utilButtons.roll },
        { "chatBarShowReadyCheck", utilButtons.ready },
        { "chatBarShowPullTimer", utilButtons.pull },
        { "chatBarShowReload", utilButtons.reload },
    }
    for i = 1, #tools do
        local key, btn = tools[i][1], tools[i][2]
        if cfg[key] ~= false and (not hideUnavailable or Usable(btn)) then
            shown[#shown + 1] = btn
        end
    end

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
    PaintState(false)
    local count = #shown
    bar:SetSize(count > 0 and (count * w + (count - 1) * gap) or 1, h)
    ApplyPosition()
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        PaintState(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        PaintState(false)
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
    -- What makes a button usable or not: group, rights, role, guild rank,
    -- and the chat messaging lockdown (encounter, Mythic+, rated PvP).
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("PARTY_LEADER_CHANGED")
    events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    events:RegisterEvent("PLAYER_GUILD_UPDATE")
    events:RegisterEvent("ENCOUNTER_START")
    events:RegisterEvent("ENCOUNTER_END")
    events:RegisterEvent("CHALLENGE_MODE_START")
    events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    events:RegisterEvent("CHALLENGE_MODE_RESET")
    events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
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
