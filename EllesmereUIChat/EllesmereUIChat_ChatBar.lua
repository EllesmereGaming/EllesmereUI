local addonName, ns = ...
local EUI = _G.EllesmereUI
if not EUI then return end

ns.ECHAT = ns.ECHAT or {}
local ECHAT = ns.ECHAT

local ipairs, pairs, tonumber, type = ipairs, pairs, tonumber, type
local CreateFrame = CreateFrame
local GetChannelList = GetChannelList
local GetTime = GetTime
local UnitClass = UnitClass
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local ChatTypeInfo = ChatTypeInfo
local GameTooltip = GameTooltip
local ReloadUI = ReloadUI
local DoReadyCheck = DoReadyCheck
local RandomRoll = RandomRoll
local SlashCmdList = SlashCmdList
local C_AddOns = C_AddOns

-- Base definitions of standard buttons
local BUTTONS_CONFIG = {
    { id = "SAY",           tag = "chatBarShowSay",         text = "S",   abbrKey = "chatBarAbbrS",           chatType = "SAY",           tooltipL = "Say" },
    { id = "YELL",          tag = "chatBarShowYell",        text = "Y",   abbrKey = "chatBarAbbrY",           chatType = "YELL",          tooltipL = "Yell" },
    { id = "EMOTE",         tag = "chatBarShowEmote",       text = "E",   abbrKey = "chatBarAbbrEmote",      chatType = "EMOTE",         tooltipL = "Emote" },
    { id = "WHISPER",       tag = "chatBarShowWhisper",     text = "W",   abbrKey = "chatBarAbbrWhisper",    chatType = "WHISPER",       tooltipL = "Whisper" },
    { id = "PARTY",         tag = "chatBarShowParty",       text = "P",   abbrKey = "chatBarAbbrP",          chatType = "PARTY",         tooltipL = "Party",            hideTag = "chatBarHidePartyIfUnavailable" },
    { id = "RAID",          tag = "chatBarShowRaid",        text = "R",   abbrKey = "chatBarAbbrR",          chatType = "RAID",          tooltipL = "Raid",             hideTag = "chatBarHideRaidIfUnavailable" },
    { id = "RAID_WARNING",  tag = "chatBarShowRaidWarning", text = "RW",  abbrKey = "chatBarAbbrRaidWarning",  chatType = "RAID_WARNING",  tooltipL = "Raid Warning",     hideTag = "chatBarHideRaidWarningIfUnavailable" },
    { id = "INSTANCE_CHAT", tag = "chatBarShowInstance",    text = "I",   abbrKey = "chatBarAbbrInstance",   chatType = "INSTANCE_CHAT", tooltipL = "Instance",         hideTag = "chatBarHideInstanceIfUnavailable" },
    { id = "GUILD",         tag = "chatBarShowGuild",       text = "G",   abbrKey = "chatBarAbbrG",          chatType = "GUILD",         tooltipL = "Guild",            hideTag = "chatBarHideGuildIfUnavailable" },
    { id = "OFFICER",       tag = "chatBarShowOfficer",     text = "O",   abbrKey = "chatBarAbbrOfficer",    chatType = "OFFICER",       tooltipL = "Officer",          hideTag = "chatBarHideOfficerIfUnavailable" },
    { id = "BATTLEGROUND",  tag = "chatBarShowBattleground",text = "BG",  abbrKey = "chatBarAbbrBattleground",chatType = "BATTLEGROUND", tooltipL = "Battleground",     hideTag = "chatBarHideBattlegroundIfUnavailable" },
}

local function DB()
    if ECHAT.DB then return ECHAT.DB() end
    return {}
end

local function GetAbbrev(key, defaultVal)
    local localized = EUI.L(key)
    if localized and localized ~= key then
        return localized
    end
    return defaultVal
end

local function GetChatBarFont()
    local cfg = DB()
    local fontKey = cfg.chatBarFont or "__global"
    if fontKey == "__global" then
        return (EUI.GetFontPath and EUI.GetFontPath("chat")) or STANDARD_TEXT_FONT
    end
    return (EUI.ResolveFontName and EUI.ResolveFontName(fontKey)) or STANDARD_TEXT_FONT
end

local CHANNEL_COLOR_OVERRIDES = {
    SAY = {
        TEXT = { 1, 1, 1 },
        BG = { 0.376, 0.349, 0.341 },
        GRADIENT = { 0.333, 0.310, 0.302 },
    },
    YELL = {
        TEXT = { 1, 0.251, 0.251 },
        BG = { 0.376, 0.235, 0.227 },
        GRADIENT = { 0.333, 0.196, 0.188 },
    },
    EMOTE = {
        TEXT = { 1, 0.502, 0.251 },
        BG = { 0.376, 0.275, 0.227 },
        GRADIENT = { 0.333, 0.235, 0.188 },
    },
    WHISPER = {
        TEXT = { 1, 0.502, 1 },
        BG = { 0.376, 0.275, 0.341 },
        GRADIENT = { 0.333, 0.235, 0.302 },
    },
    PARTY = {
        TEXT = { 0.667, 0.667, 1 },
        BG = { 0.325, 0.298, 0.341 },
        GRADIENT = { 0.286, 0.259, 0.302 },
    },
    RAID = {
        TEXT = { 1, 0.498, 0 },
        BG = { 0.376, 0.275, 0.192 },
        GRADIENT = { 0.333, 0.231, 0.153 },
    },
    RAID_WARNING = {
        TEXT = { 1, 0.282, 0.031 },
        BG = { 0.376, 0.239, 0.196 },
        GRADIENT = { 0.333, 0.200, 0.157 },
    },
    INSTANCE_CHAT = {
        TEXT = { 1, 0.502, 0 },
        BG = { 0.376, 0.275, 0.192 },
        GRADIENT = { 0.333, 0.235, 0.153 },
    },
    GUILD = {
        TEXT = { 0.251, 1, 0.251 },
        BG = { 0.263, 0.349, 0.227 },
        GRADIENT = { 0.224, 0.310, 0.188 },
    },
    OFFICER = {
        TEXT = { 0.251, 0.753, 0.251 },
        BG = { 0.263, 0.310, 0.227 },
        GRADIENT = { 0.224, 0.271, 0.188 },
    },
    BATTLEGROUND = {
        TEXT = { 1, 0.498, 0 },
        BG = { 0.376, 0.275, 0.192 },
        GRADIENT = { 0.333, 0.231, 0.153 },
    },
    SYSTEM = {
        TEXT = { 1, 1, 0 },
        BG = { 0.376, 0.349, 0.192 },
        GRADIENT = { 0.333, 0.310, 0.153 },
    },
    TEXT = {
        TEXT = { 1, 1, 0 },
        BG = { 0.376, 0.349, 0.192 },
        GRADIENT = { 0.333, 0.310, 0.153 },
    },
}

local function GetColor(source, colorRole, chatType, channelNum)
    if source == "channel" then
        local t = chatType
        if chatType == "CHANNEL" and channelNum then
            t = "CHANNEL" .. channelNum
        end
        
        local role = colorRole
        if role == "BORDER" then
            role = "TEXT"
        end
        
        -- Custom Overrides
        if t:find("^CHANNEL") then
            if role == "TEXT" then
                return 1, 0.753, 0.753
            elseif role == "BG" then
                return 0.376, 0.310, 0.306
            elseif role == "GRADIENT" then
                return 0.333, 0.271, 0.263
            end
        end
        
        local over = CHANNEL_COLOR_OVERRIDES[t]
        if over and over[role] then
            return over[role][1], over[role][2], over[role][3]
        end
        
        local info = ChatTypeInfo[t]
        if info then return info.r, info.g, info.b end
        return 1, 1, 1
    elseif source == "class" then
        local _, class = UnitClass("player")
        local color = RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
        return 1, 1, 1
    elseif source == "custom" then
        local cfg = DB()
        if colorRole == "TEXT" then
            return cfg.chatBarCustomTextR or 1, cfg.chatBarCustomTextG or 1, cfg.chatBarCustomTextB or 1
        elseif colorRole == "BG" then
            return cfg.chatBarCustomBgR or 0.12, cfg.chatBarCustomBgG or 0.14, cfg.chatBarCustomBgB or 0.18
        elseif colorRole == "BORDER" then
            return cfg.chatBarCustomBorderR or 0.5, cfg.chatBarCustomBorderG or 0.5, cfg.chatBarCustomBorderB or 0.5
        elseif colorRole == "GRADIENT" then
            return cfg.chatBarGradientCustomR or 1, cfg.chatBarGradientCustomG or 1, cfg.chatBarGradientCustomB or 1
        end
    elseif source == "accent" then
        if EUI.GetAccentColor then return EUI.GetAccentColor() end
        local eg = EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
        return eg.r, eg.g, eg.b
    end
    -- Static/default fallback
    if colorRole == "TEXT" then return 1, 1, 1
    elseif colorRole == "BG" then
        local cfg = DB()
        return cfg.bgR or 0.03, cfg.bgG or 0.045, cfg.bgB or 0.05
    elseif colorRole == "BORDER" then return 0.3, 0.3, 0.3
    end
    return 1, 1, 1
end

local function ShowBorder(btn, r, g, b, a, size)
    if EUI.PP then
        if EUI.PP.GetBorders(btn) then
            if EUI.PP.UpdateBorder then
                EUI.PP.UpdateBorder(btn, size or 1, r, g, b, a or 1)
            elseif EUI.PP.SetBorderColor then
                EUI.PP.SetBorderColor(btn, r, g, b, a or 1)
                EUI.PP.SetBorderSize(btn, size or 1)
            end
            if EUI.PP.ShowBorder then
                EUI.PP.ShowBorder(btn)
            end
        else
            if EUI.PP.CreateBorder then
                EUI.PP.CreateBorder(btn, r, g, b, a or 1, size or 1, "OVERLAY", 7)
            end
        end
    end
end

local function HideBorder(btn)
    if EUI.PP and EUI.PP.HideBorder then
        EUI.PP.HideBorder(btn)
    end
end

local function ApplyButtonStyle(btn)
    local cfg = DB()
    local style = cfg.chatBarStyle or "square"
    
    local txt = btn.textFS
    local bg = btn.bgTex
    local chatType = btn.chatType
    local channelNum = btn.channelNum
    
    local textR, textG, textB
    local bgR, bgG, bgB, bgA
    local borderR, borderG, borderB, borderA
    
    local showBorder = cfg.chatBarShowBorder ~= false
    if cfg.chatBarBorderColorSource == "none" or style == "text" then
        showBorder = false
    end
    
    -- 1. Determine colors
    textR, textG, textB = GetColor(cfg.chatBarTextColorSource or "channel", "TEXT", chatType, channelNum)
    bgR, bgG, bgB = GetColor(cfg.chatBarBgColorSource or "static", "BG", chatType, channelNum)
    bgA = cfg.chatBarBgAlpha or 0.65
    
    borderR, borderG, borderB = GetColor(cfg.chatBarBorderColorSource or "none", "BORDER", chatType, channelNum)
    borderA = (cfg.chatBarBorderColorSource == "none") and 0 or 1.0
    if cfg.chatBarBorderColorSource == "channel" then
        borderA = 0.45
    end
    
    local borderWidth = cfg.chatBarBorderWidth or 1
    
    -- 2. Apply style representation
    if style == "text" then
        txt:Show()
        txt:SetTextColor(textR, textG, textB)
        bg:SetColorTexture(0, 0, 0, 0)
        HideBorder(btn)
    elseif style == "square" then
        txt:Show()
        txt:SetTextColor(textR, textG, textB)
        bg:SetColorTexture(bgR, bgG, bgB, bgA)
        if showBorder then
            ShowBorder(btn, borderR, borderG, borderB, borderA, borderWidth)
        else
            HideBorder(btn)
        end
    elseif style == "block" then
        txt:Hide()
        local br, bg_color, bb = GetColor(cfg.chatBarBgColorSource == "static" and "channel" or cfg.chatBarBgColorSource, "BG", chatType, channelNum)
        bg:SetColorTexture(br, bg_color, bb, bgA)
        if showBorder then
            ShowBorder(btn, borderR, borderG, borderB, borderA, borderWidth)
        else
            HideBorder(btn)
        end
    end
    
    -- 3. Apply Gradient overlay
    if btn.gradTex then
        local gradEnabled = cfg.chatBarGradientEnabled
        if gradEnabled and style ~= "text" then
            local gradDir = cfg.chatBarGradientDir or "LEFT"
            local gradAlpha = cfg.chatBarGradientAlpha or 0.5
            local gradR, gradG, gradB = GetColor(cfg.chatBarGradientColorSource or "custom", "GRADIENT", chatType, channelNum)
            
            if gradDir == "LEFT" then
                btn.gradTex:SetTexture("Interface\\Buttons\\WHITE8X8")
                btn.gradTex:SetGradient("HORIZONTAL", CreateColor(gradR, gradG, gradB, gradAlpha), CreateColor(gradR, gradG, gradB, 0))
            elseif gradDir == "RIGHT" then
                btn.gradTex:SetTexture("Interface\\Buttons\\WHITE8X8")
                btn.gradTex:SetGradient("HORIZONTAL", CreateColor(gradR, gradG, gradB, 0), CreateColor(gradR, gradG, gradB, gradAlpha))
            elseif gradDir == "UP" then
                btn.gradTex:SetTexture("Interface\\Buttons\\WHITE8X8")
                btn.gradTex:SetGradient("VERTICAL", CreateColor(gradR, gradG, gradB, 0), CreateColor(gradR, gradG, gradB, gradAlpha))
            elseif gradDir == "DOWN" then
                btn.gradTex:SetTexture("Interface\\Buttons\\WHITE8X8")
                btn.gradTex:SetGradient("VERTICAL", CreateColor(gradR, gradG, gradB, gradAlpha), CreateColor(gradR, gradG, gradB, 0))
            elseif gradDir == "RADIAL" then
                btn.gradTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\unlock-flash.png")
                btn.gradTex:SetGradient("HORIZONTAL", CreateColor(gradR, gradG, gradB, gradAlpha), CreateColor(gradR, gradG, gradB, gradAlpha))
            else
                btn.gradTex:SetTexture("Interface\\Buttons\\WHITE8X8")
                btn.gradTex:SetGradient("HORIZONTAL", CreateColor(gradR, gradG, gradB, gradAlpha), CreateColor(gradR, gradG, gradB, 0))
            end
            btn.gradTex:Show()
        else
            btn.gradTex:Hide()
        end
    end
end

local function SwitchToChannel(chatType, target)
    local eb = _G.ChatFrame1EditBox
    if not eb then return end
    
    if not eb:IsShown() then
        eb:Show()
    end
    eb:SetFocus()
    
    if chatType == "WHISPER" then
        eb:SetAttribute("chatType", "WHISPER")
        if target and target ~= "" then
            eb:SetAttribute("tellTarget", target)
        else
            eb:SetText("/w ")
        end
    elseif chatType == "CHANNEL" then
        eb:SetAttribute("chatType", "CHANNEL")
        if target then
            eb:SetAttribute("channelTarget", tonumber(target))
        end
    else
        eb:SetAttribute("chatType", chatType)
    end
    
    ChatEdit_UpdateHeader(eb)
end

local function TriggerPullTimer()
    local duration = DB().chatBarPullDuration or 10
    if C_AddOns.IsAddOnLoaded("DBM-Core") then
        SlashCmdList["DEADLYBOSSMODS"]("pull " .. duration)
    elseif C_AddOns.IsAddOnLoaded("BigWigs") then
        SlashCmdList["BIGWIGSPULL"](tostring(duration))
    else
        SlashCmdList["COUNTDOWN"](tostring(duration))
    end
end

local function ShowButtonTooltip(btn)
    if not GameTooltip then return end
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    
    local title = btn.tooltipL and EUI.L(btn.tooltipL) or ""
    local sub = btn.tooltipR and EUI.L(btn.tooltipR) or ""
    
    if title ~= "" and sub ~= "" then
        -- Multi-line for double actions
        GameTooltip:SetText(title .. " |cff0cd29f(" .. EUI.L("Left Click") .. ")|r")
        GameTooltip:AddLine(sub .. " |cff0cd29f(" .. EUI.L("Right Click") .. ")|r", 1, 1, 1)
    else
        -- Single action name
        GameTooltip:SetText(title ~= "" and title or (btn.tooltipL or ""))
    end
    GameTooltip:Show()
end

local function GetJoinedChannels()
    local channels = {}
    local list = { GetChannelList() }
    local i = 1
    while i <= #list do
        local id = list[i]
        local name = list[i+1]
        if type(id) == "number" and type(name) == "string" and name ~= "" then
            table.insert(channels, { id = id, name = name })
        end
        i = i + 3
    end
    return channels
end

local function IsChannelAvailable(id)
    if id == "GUILD" then
        return not not IsInGuild()
    elseif id == "OFFICER" then
        if not IsInGuild() then return false end
        local _, _, rankIndex = GetGuildInfo("player")
        if rankIndex then
            if C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags then
                local rankOrder = rankIndex + 1
                local perm = C_GuildInfo.GuildControlGetRankFlags(rankOrder)
                return not not (perm and perm[4])
            end
        end
        return true
    elseif id == "PARTY" then
        return not not IsInGroup()
    elseif id == "RAID" then
        return not not IsInRaid()
    elseif id == "RAID_WARNING" then
        return not not (IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or (_G.IsEveryoneAssistant and _G.IsEveryoneAssistant())))
    elseif id == "INSTANCE_CHAT" then
        return not not IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    elseif id == "BATTLEGROUND" then
        local inInstanceGroup = IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        local _, instanceType = GetInstanceInfo()
        local isPvP = (instanceType == "pvp" or instanceType == "arena")
        return not not (inInstanceGroup and isPvP)
    end
    return true
end

-- Re-layout ChatBar buttons
function ECHAT.UpdateButtonLayout()
    local frame = ECHAT.ChatBarFrame
    if not frame then return end
    
    local cfg = DB()
    if not cfg.chatBarEnabled then
        frame:Hide()
        return
    end
    
    if cfg.chatBarHideInCombat and InCombatLockdown() then
        frame:Hide()
        return
    end
    
    frame:Show()
    
    -- Hide all buttons in our pool first
    for _, btn in ipairs(frame.buttons) do
        btn:Hide()
    end
    
    local activeBtns = {}
    
    -- 1. Add standard channel buttons
    for _, info in ipairs(BUTTONS_CONFIG) do
        if cfg[info.tag] ~= false then
            local show = true
            if info.hideTag and cfg[info.hideTag] ~= false then
                show = IsChannelAvailable(info.id)
            end
            if show then
                local btn = frame.stdButtons[info.id]
                if btn then
                    table.insert(activeBtns, btn)
                end
            end
        end
    end
    
    -- 2. Add global channel buttons dynamically
    if cfg.chatBarShowGlobalChannels ~= false then
        local joined = GetJoinedChannels()
        for idx, chanInfo in ipairs(joined) do
            local btn = frame.globalButtons[idx]
            if not btn then
                btn = CreateFrame("Button", nil, frame)
                btn:SetFrameLevel(frame:GetFrameLevel() + 2)
                
                local bg = btn:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                btn.bgTex = bg
                
                local grad = btn:CreateTexture(nil, "BORDER")
                grad:SetAllPoints()
                btn.gradTex = grad
                
                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.06)
                
                local txt = btn:CreateFontString(nil, "OVERLAY")
                txt:SetFont(GetChatBarFont(), 11, "")
                txt:SetPoint("CENTER")
                btn.textFS = txt
                
                btn:SetScript("OnEnter", function(self)
                    ShowButtonTooltip(self)
                end)
                btn:SetScript("OnLeave", function()
                    if GameTooltip then GameTooltip:Hide() end
                end)
                btn:SetScript("OnClick", function(self, button)
                    if button == "LeftButton" then
                        SwitchToChannel(self.chatType, self.channelNum)
                    end
                end)
                btn:RegisterForClicks("LeftButtonUp")
                frame.globalButtons[idx] = btn
            end
            
            btn.chatType = "CHANNEL"
            btn.channelNum = chanInfo.id
            btn.textFS:SetText(chanInfo.id)
            btn.tooltipL = chanInfo.name
            btn.tooltipR = nil
            
            table.insert(activeBtns, btn)
        end
    end
    
    -- 3. Add Roll utility button
    if cfg.chatBarShowRoll ~= false then
        local btn = frame.utilButtons.ROLL
        if btn then table.insert(activeBtns, btn) end
    end
    
    -- 4. Add Ready Check / Pull utility button
    if cfg.chatBarShowReadyCheck ~= false then
        local btn = frame.utilButtons.RC
        if btn then table.insert(activeBtns, btn) end
    end
    
    -- 5. Add Reload UI utility button
    if cfg.chatBarShowReloadUI ~= false then
        local btn = frame.utilButtons.RL
        if btn then table.insert(activeBtns, btn) end
    end
    
    -- Positioning loop
    local scale = cfg.chatBarScale or 1.0
    local spacing = (cfg.chatBarSpacing or 4) * scale
    local btnW = (cfg.chatBarButtonWidth or 24) * scale
    local btnH = (cfg.chatBarButtonHeight or 20) * scale
    local font = GetChatBarFont()
    local fontSize = (cfg.chatBarFontSize or 11) * scale
    
    local totalWidth = 0
    local prev = nil
    for idx, btn in ipairs(activeBtns) do
        btn:ClearAllPoints()
        btn:SetSize(btnW, btnH)
        
        btn.textFS:SetFont(font, fontSize, "")
        
        ApplyButtonStyle(btn)
        
        if idx == 1 then
            btn:SetPoint("LEFT", frame, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        end
        btn:Show()
        prev = btn
        totalWidth = totalWidth + btnW + (idx > 1 and spacing or 0)
    end
    
    frame:SetHeight(btnH)
    frame:SetWidth(totalWidth > 0 and totalWidth or 1)
end

-- Position frame above chat tabs by default, or use saved position
function ECHAT.ApplyChatBarPosition()
    local frame = ECHAT.ChatBarFrame
    if not frame then return end
    
    if EllesmereUI and EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("ECHAT_ChatBar") then
        if frame:GetLeft() then
            return
        end
    end
    
    local cfg = DB()
    frame:ClearAllPoints()
    
    local pos = cfg.chatBarPosition
    if pos and pos.point then
        local px, py = pos.x or 0, pos.y or 0
        local PPa = EUI and EUI.PP
        if PPa and PPa.SnapForES then
            local es = frame:GetEffectiveScale()
            px = PPa.SnapForES(px, es)
            py = PPa.SnapForES(py, es)
        end
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px, py)
    else
        -- Default position strictly above the chat tabs (GeneralDockManager)
        local gdm = _G.GeneralDockManager
        if gdm then
            frame:SetPoint("BOTTOMLEFT", gdm, "TOPLEFT", 0, 2)
        else
            local cf1 = _G.ChatFrame1
            if cf1 then
                frame:SetPoint("BOTTOMLEFT", cf1, "TOPLEFT", 0, 28)
            else
                frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 220)
            end
        end
    end
end

-- Set up all buttons inside ChatBar
local function CreateChatBar()
    if ECHAT.ChatBarFrame then return end
    
    local frame = CreateFrame("Frame", "EUI_ChatBarFrame", UIParent)
    frame:SetSize(320, 20)
    frame:SetFrameStrata("LOW")
    if _G.GeneralDockManager then
        frame:SetFrameLevel(_G.GeneralDockManager:GetFrameLevel() + 1)
    else
        frame:SetFrameLevel(10)
    end
    ECHAT.ChatBarFrame = frame
    
    frame.buttons = {}
    frame.stdButtons = {}
    frame.globalButtons = {}
    frame.utilButtons = {}
    
    -- 1. Create standard buttons
    for _, info in ipairs(BUTTONS_CONFIG) do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetFrameLevel(frame:GetFrameLevel() + 2)
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        btn.bgTex = bg
        
        local grad = btn:CreateTexture(nil, "BORDER")
        grad:SetAllPoints()
        btn.gradTex = grad
        
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        
        local txt = btn:CreateFontString(nil, "OVERLAY")
        txt:SetFont(GetChatBarFont(), 11, "")
        txt:SetPoint("CENTER")
        txt:SetText(GetAbbrev(info.abbrKey, info.text))
        btn.textFS = txt
        
        btn.chatType = info.chatType
        btn.chatTypeR = info.chatTypeR
        btn.tooltipL = info.tooltipL
        btn.tooltipR = info.tooltipR
        
        btn:SetScript("OnEnter", function(self)
            ShowButtonTooltip(self)
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        btn:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                SwitchToChannel(self.chatType)
            elseif button == "RightButton" and self.chatTypeR then
                SwitchToChannel(self.chatTypeR)
            end
        end)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        frame.stdButtons[info.id] = btn
        table.insert(frame.buttons, btn)
    end
    
    -- 2. Create Roll utility button
    do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetFrameLevel(frame:GetFrameLevel() + 2)
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        btn.bgTex = bg
        
        local grad = btn:CreateTexture(nil, "BORDER")
        grad:SetAllPoints()
        btn.gradTex = grad
        
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        
        local txt = btn:CreateFontString(nil, "OVERLAY")
        txt:SetFont(GetChatBarFont(), 11, "")
        txt:SetPoint("CENTER")
        txt:SetText(GetAbbrev("chatBarAbbrRoll", "R"))
        btn.textFS = txt
        
        btn.chatType = "TEXT"
        btn.tooltipL = "Roll"
        
        btn:SetScript("OnEnter", function(self)
            ShowButtonTooltip(self)
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        btn:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                RandomRoll(1, 100)
            end
        end)
        btn:RegisterForClicks("LeftButtonUp")
        
        frame.utilButtons.ROLL = btn
        table.insert(frame.buttons, btn)
    end
    
    -- 3. Create Ready Check / Pull utility button
    do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetFrameLevel(frame:GetFrameLevel() + 2)
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        btn.bgTex = bg
        
        local grad = btn:CreateTexture(nil, "BORDER")
        grad:SetAllPoints()
        btn.gradTex = grad
        
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        
        local txt = btn:CreateFontString(nil, "OVERLAY")
        txt:SetFont(GetChatBarFont(), 11, "")
        txt:SetPoint("CENTER")
        txt:SetText(GetAbbrev("chatBarAbbrRC", "RC"))
        btn.textFS = txt
        
        btn.chatType = "TEXT"
        btn.tooltipL = "Ready Check"
        btn.tooltipR = "Pull Timer"
        
        btn:SetScript("OnEnter", function(self)
            ShowButtonTooltip(self)
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        btn:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                DoReadyCheck()
            elseif button == "RightButton" then
                TriggerPullTimer()
            end
        end)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        frame.utilButtons.RC = btn
        table.insert(frame.buttons, btn)
    end
    
    -- 4. Create Reload UI utility button
    do
        local btn = CreateFrame("Button", nil, frame)
        btn:SetFrameLevel(frame:GetFrameLevel() + 2)
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        btn.bgTex = bg
        
        local grad = btn:CreateTexture(nil, "BORDER")
        grad:SetAllPoints()
        btn.gradTex = grad
        
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        
        local txt = btn:CreateFontString(nil, "OVERLAY")
        txt:SetFont(GetChatBarFont(), 11, "")
        txt:SetPoint("CENTER")
        txt:SetText(GetAbbrev("chatBarAbbrRL", "RL"))
        btn.textFS = txt
        
        btn.chatType = "TEXT"
        btn.tooltipL = "Reload UI"
        
        btn:SetScript("OnEnter", function(self)
            ShowButtonTooltip(self)
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        btn:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                ReloadUI()
            end
        end)
        btn:RegisterForClicks("LeftButtonUp")
        
        frame.utilButtons.RL = btn
        table.insert(frame.buttons, btn)
    end
    
    ECHAT.ApplyChatBarPosition()
    ECHAT.UpdateButtonLayout()
    
    -- Register in Unlock Mode
    if EUI.RegisterUnlockElements then
        local MK = EUI.MakeUnlockElement
        EUI:RegisterUnlockElements({
            MK({
                key   = "ECHAT_ChatBar",
                label = EUI.L("Chat Bar"),
                group = "Chat",
                order = 602,
                noResize = true,
                getFrame = function() return ECHAT.ChatBarFrame end,
                getSize  = function()
                    if ECHAT.ChatBarFrame then
                        return ECHAT.ChatBarFrame:GetWidth(), ECHAT.ChatBarFrame:GetHeight()
                    end
                    return 320, 24
                end,
                isHidden = function()
                    local cfg = DB()
                    return not cfg.chatBarEnabled
                end,
                savePos = function(_, point, relPoint, x, y)
                    local cfg = DB()
                    if not cfg then return end
                    cfg.chatBarPosition = { point = point, relPoint = relPoint or point, x = x, y = y }
                    if not EUI._unlockActive then
                        ECHAT.ApplyChatBarPosition()
                    end
                end,
                loadPos = function()
                    local cfg = DB()
                    if not cfg then return nil end
                    return cfg.chatBarPosition
                end,
                clearPos = function()
                    local cfg = DB()
                    if not cfg then return end
                    cfg.chatBarPosition = nil
                end,
                applyPos = function()
                    ECHAT.ApplyChatBarPosition()
                end,
            }),
        })
    end
end

-- Event Handling
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHANNEL_UI_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        CreateChatBar()
    elseif event == "PLAYER_REGEN_DISABLED" then
        local cfg = DB()
        if cfg.chatBarEnabled and cfg.chatBarHideInCombat then
            if ECHAT.ChatBarFrame then ECHAT.ChatBarFrame:Hide() end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local cfg = DB()
        if cfg.chatBarEnabled then
            if ECHAT.ChatBarFrame then ECHAT.ChatBarFrame:Show() end
            ECHAT.UpdateButtonLayout()
        end
    else
        -- CHANNEL_UI_UPDATE / PLAYER_ENTERING_WORLD
        if ECHAT.ChatBarFrame then
            ECHAT.UpdateButtonLayout()
        end
    end
end)
