-------------------------------------------------------------------------------
--  EllesmereUIBasics.lua
--  Chat, Minimap, and Friends List skinning for EllesmereUI.
--  Friends List: full frame reskin, accent tab underlines, class icons,
--  and custom friend groups with right-click assignment.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local EBS = EllesmereUI.Lite.NewAddon("EllesmereUIBasics")

local PP = EllesmereUI.PP

local defaults = {
    profile = {
        chat = {
            enabled       = true,
            bgAlpha       = 0.6,
            borderR       = 0.05, borderG = 0.05, borderB = 0.05, borderA = 1,
            useClassColor = false,
            fontSize      = 14,
            hideButtons   = false,
            hideTabFlash  = false,
            visibility    = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
        minimap = {
            enabled       = true,
            scale         = 1.0,
            borderR       = 0.05, borderG = 0.05, borderB = 0.05, borderA = 1,
            useClassColor = false,
            hideZoneText  = false,
            hideButtons   = true,
            visibility    = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
        friends = {
            enabled        = true,
            bgAlpha        = 0.8,
            showBorder     = true,
            borderR        = 0.05, borderG = 0.05, borderB = 0.05, borderA = 1,
            useClassColor  = false,
            useAccentTab   = true,
            showClassIcons = true,
            iconStyle      = "blizzard",
            groupsEnabled  = false,
            showUngrouped  = true,
            groups         = {},
            assignments    = {},
            visibility     = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
        cursor = {
            enabled = true,
            instanceOnly = false,
            useClassColor = true,
            hex = "0CD29D",
            texture = "ring_normal",
            scale = 1,
            gcd = {
                enabled = false,
                attached = true,
                radius = 21,
                ringTex = "light",
                scale = 100,
                hex = "FFFFFF",
                alpha = 80,
                useClassColor = false,
                instanceOnly = false,
            },
            castCircle = {
                enabled = false,
                attached = true,
                radius = 30,
                ringTex = "normal",
                scale = 100,
                hex = "3FA7FF",
                alpha = 80,
                sparkEnabled = true,
                sparkHex = nil,
                useClassColor = true,
                instanceOnly = false,
            },
            trail = false,
            visibility       = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
        questTracker = {
            enabled              = true,
            pos                  = nil,
            width                = 220,
            bgAlpha              = 0.6,
            bgR                  = 0,
            bgG                  = 0,
            bgB                  = 0,
            height               = 600,
            alignment            = "top",
            titleFontSize        = 11,
            titleColor           = { r=1.0,  g=0.91, b=0.47 },
            objFontSize          = 10,
            objColor             = { r=0.72, g=0.72, b=0.72 },
            secFontSize          = 12,
            showZoneQuests       = true,
            showWorldQuests      = true,
            zoneCollapsed        = false,
            worldCollapsed       = false,
            showQuestItems       = true,
            questItemSize        = 22,
            secColor             = { r=0.047, g=0.824, b=0.624 },
            delveCollapsed       = false,
            questsCollapsed      = false,
            questItemHotkey      = nil,
            autoAccept           = false,
            autoTurnIn           = false,
            autoTurnInShiftSkip  = true,
            showTopLine          = true,
            hideBlizzardTracker  = true,
            visibility           = "always",
            visOnlyInstances     = false,
            visHideHousing       = false,
            visHideMounted       = false,
            visHideNoTarget      = false,
            visHideNoEnemy       = false,
        },
    },
}

-------------------------------------------------------------------------------
--  Utility
-------------------------------------------------------------------------------
local function GetClassColor()
    local _, classFile = UnitClass("player")
    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if cc then return cc.r, cc.g, cc.b, 1 end
    return 0.05, 0.05, 0.05, 1
end

local function GetBorderColor(cfg)
    if cfg.useClassColor then
        return GetClassColor()
    end
    return cfg.borderR, cfg.borderG, cfg.borderB, cfg.borderA or 1
end

-------------------------------------------------------------------------------
--  Combat safety
-------------------------------------------------------------------------------
local pendingApply = false
local ApplyAll  -- forward declaration

local function QueueApplyAll()
    if pendingApply then return end
    pendingApply = true
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if pendingApply then
        pendingApply = false
        ApplyAll()
    end
end)

-------------------------------------------------------------------------------
--  Chat Skin
-------------------------------------------------------------------------------
local skinnedChatFrames = {}

local function SkinChatFrame(chatFrame, p)
    if not chatFrame then return end
    local name = chatFrame:GetName()
    if not name then return end

    -- Dark background
    if not chatFrame._ebsBg then
        chatFrame._ebsBg = chatFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
        chatFrame._ebsBg:SetColorTexture(0, 0, 0)
        chatFrame._ebsBg:SetPoint("TOPLEFT", -4, 4)
        chatFrame._ebsBg:SetPoint("BOTTOMRIGHT", 4, -4)
    end
    chatFrame._ebsBg:SetAlpha(p.bgAlpha)

    -- Border
    local r, g, b, a = GetBorderColor(p)
    if not chatFrame._ppBorders then
        PP.CreateBorder(chatFrame, r, g, b, a, 1, "OVERLAY", 7)
    else
        PP.SetBorderColor(chatFrame, r, g, b, a)
    end

    -- Edit box skin
    local editBox = _G[name .. "EditBox"]
    if editBox then
        if not editBox._ebsBg then
            editBox._ebsBg = editBox:CreateTexture(nil, "BACKGROUND", nil, -7)
            editBox._ebsBg:SetColorTexture(0, 0, 0)
            editBox._ebsBg:SetPoint("TOPLEFT", -2, 2)
            editBox._ebsBg:SetPoint("BOTTOMRIGHT", 2, -2)
        end
        editBox._ebsBg:SetAlpha(p.bgAlpha)

        if not editBox._ppBorders then
            PP.CreateBorder(editBox, r, g, b, a, 1, "OVERLAY", 7)
        else
            PP.SetBorderColor(editBox, r, g, b, a)
        end
    end

    -- Font size
    local fontString = chatFrame:GetFontObject()
    if fontString then
        local font, _, flags = fontString:GetFont()
        if font then
            chatFrame:SetFont(font, p.fontSize, flags)
        end
    end

    skinnedChatFrames[chatFrame] = true
end

local chatButtonsHidden = false
local chatButtonHooks = {}

local function HideChatButton(btn)
    if not btn then return end
    btn:Hide()
    btn:SetAlpha(0)
    if not chatButtonHooks[btn] then
        hooksecurefunc(btn, "Show", function(self)
            if _G._EBS_AceDB and _G._EBS_AceDB.profile.chat.hideButtons then
                self:Hide()
                self:SetAlpha(0)
            end
        end)
        chatButtonHooks[btn] = true
    end
end

local function ShowChatButton(btn)
    if not btn then return end
    btn:SetAlpha(1)
    btn:Show()
end

local tabFlashHooked = false

local function UnskinChatFrame(chatFrame)
    if not chatFrame then return end
    if chatFrame._ebsBg then chatFrame._ebsBg:SetAlpha(0) end
    if chatFrame._ppBorders then PP.SetBorderColor(chatFrame, 0, 0, 0, 0) end

    local name = chatFrame:GetName()
    if name then
        local editBox = _G[name .. "EditBox"]
        if editBox then
            if editBox._ebsBg then editBox._ebsBg:SetAlpha(0) end
            if editBox._ppBorders then PP.SetBorderColor(editBox, 0, 0, 0, 0) end
        end
    end
end

local function ApplyChat()
    if InCombatLockdown() then QueueApplyAll(); return end

    local p = EBS.db.profile.chat

    if not p.enabled then
        -- Revert all skinned chat frames
        for chatFrame in pairs(skinnedChatFrames) do
            UnskinChatFrame(chatFrame)
        end
        -- Restore buttons
        if chatButtonsHidden then
            local buttons = { ChatFrameMenuButton, ChatFrameChannelButton, QuickJoinToastButton }
            for _, btn in ipairs(buttons) do ShowChatButton(btn) end
            chatButtonsHidden = false
        end
        return
    end

    local numWindows = NUM_CHAT_WINDOWS or 10
    for i = 1, numWindows do
        local chatFrame = _G["ChatFrame" .. i]
        SkinChatFrame(chatFrame, p)
    end

    -- Hook dynamic windows
    if not EBS._chatHookDone then
        EBS._chatHookDone = true
        hooksecurefunc("FCF_OpenNewWindow", function()
            C_Timer.After(0.1, function()
                if not EBS.db then return end
                local cp = EBS.db.profile.chat
                if not cp.enabled then return end
                for j = 1, NUM_CHAT_WINDOWS or 10 do
                    local cf = _G["ChatFrame" .. j]
                    if cf and not skinnedChatFrames[cf] then
                        SkinChatFrame(cf, cp)
                    end
                end
            end)
        end)
    end

    -- Hide/show buttons
    local buttons = {
        ChatFrameMenuButton,
        ChatFrameChannelButton,
        QuickJoinToastButton,
    }
    if p.hideButtons then
        for _, btn in ipairs(buttons) do
            HideChatButton(btn)
        end
        chatButtonsHidden = true
    elseif chatButtonsHidden then
        for _, btn in ipairs(buttons) do
            ShowChatButton(btn)
        end
        chatButtonsHidden = false
    end

    -- Hide tab flash
    if p.hideTabFlash and not tabFlashHooked then
        tabFlashHooked = true
        if FCF_StartAlertFlash then
            hooksecurefunc("FCF_StartAlertFlash", function(chatF)
                if EBS.db and EBS.db.profile.chat.hideTabFlash then
                    FCF_StopAlertFlash(chatF)
                end
            end)
        end
    end

end

-------------------------------------------------------------------------------
--  Minimap Skin
-------------------------------------------------------------------------------
local minimapDecorations = {
    "MinimapBorder",
    "MinimapBorderTop",
}

local minimapButtons = {
    "MinimapZoomIn",
    "MinimapZoomOut",
    "MiniMapTrackingButton",
    "GameTimeFrame",
}

local minimapButtonHooks = {}

local function HideMinimapButton(name)
    local btn = _G[name]
    if not btn then return end
    btn:Hide()
    btn:SetAlpha(0)
    if not minimapButtonHooks[name] then
        hooksecurefunc(btn, "Show", function(self)
            if _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap.hideButtons then
                self:Hide()
                self:SetAlpha(0)
            end
        end)
        minimapButtonHooks[name] = true
    end
end

local function ShowMinimapButton(name)
    local btn = _G[name]
    if not btn then return end
    btn:SetAlpha(1)
    btn:Show()
end

local minimapButtonsHidden = false

local function ApplyMinimap()
    if InCombatLockdown() then QueueApplyAll(); return end

    local p = EBS.db.profile.minimap

    local minimap = Minimap
    if not minimap then return end

    if not p.enabled then
        -- Restore default decorations
        for _, name in ipairs(minimapDecorations) do
            local frame = _G[name]
            if frame then frame:Show() end
        end
        -- Restore circular mask
        minimap:SetMaskTexture("Textures\\MinimapMask")
        -- Hide our background & border
        if minimap._ebsBg then minimap._ebsBg:SetAlpha(0) end
        if minimap._ppBorders then PP.SetBorderColor(minimap, 0, 0, 0, 0) end
        -- Reset scale
        minimap:SetScale(1.0)
        -- Restore buttons
        if minimapButtonsHidden then
            for _, name in ipairs(minimapButtons) do ShowMinimapButton(name) end
            minimapButtonsHidden = false
        end
        -- Restore zone text
        local zoneBtn = MinimapZoneTextButton
        if zoneBtn then zoneBtn:Show() end
        return
    end

    -- Hide default decorations
    for _, name in ipairs(minimapDecorations) do
        local frame = _G[name]
        if frame then frame:Hide() end
    end

    -- Square mask
    minimap:SetMaskTexture("Interface\\ChatFrame\\ChatFrameBackground")

    -- Dark background
    if not minimap._ebsBg then
        minimap._ebsBg = minimap:CreateTexture(nil, "BACKGROUND", nil, -7)
        minimap._ebsBg:SetColorTexture(0, 0, 0)
        minimap._ebsBg:SetPoint("TOPLEFT", -2, 2)
        minimap._ebsBg:SetPoint("BOTTOMRIGHT", 2, -2)
    end

    -- Border
    local r, g, b, a = GetBorderColor(p)
    if not minimap._ppBorders then
        PP.CreateBorder(minimap, r, g, b, a, 1, "OVERLAY", 7)
    else
        PP.SetBorderColor(minimap, r, g, b, a)
    end

    -- Scale
    minimap:SetScale(p.scale)

    -- Hide/show buttons
    if p.hideButtons then
        for _, name in ipairs(minimapButtons) do
            HideMinimapButton(name)
        end
        minimapButtonsHidden = true
    elseif minimapButtonsHidden then
        for _, name in ipairs(minimapButtons) do
            ShowMinimapButton(name)
        end
        minimapButtonsHidden = false
    end

    -- Zone text
    local zoneBtn = MinimapZoneTextButton
    if zoneBtn then
        if p.hideZoneText then
            zoneBtn:Hide()
        else
            zoneBtn:Show()
        end
    end
end

-------------------------------------------------------------------------------
--  Friends List Skin
-------------------------------------------------------------------------------
local friendsSkinned = false
local friendButtonHooked = false

local CLASS_ICON_SPRITE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"
local CLASS_SPRITE_COORDS = {
    WARRIOR     = { 0,     0.125, 0,     0.125 },
    MAGE        = { 0.125, 0.25,  0,     0.125 },
    ROGUE       = { 0.25,  0.375, 0,     0.125 },
    DRUID       = { 0.375, 0.5,   0,     0.125 },
    EVOKER      = { 0.5,   0.625, 0,     0.125 },
    HUNTER      = { 0,     0.125, 0.125, 0.25  },
    SHAMAN      = { 0.125, 0.25,  0.125, 0.25  },
    PRIEST      = { 0.25,  0.375, 0.125, 0.25  },
    WARLOCK     = { 0.375, 0.5,   0.125, 0.25  },
    PALADIN     = { 0,     0.125, 0.25,  0.375 },
    DEATHKNIGHT = { 0.125, 0.25,  0.25,  0.375 },
    MONK        = { 0.25,  0.375, 0.25,  0.375 },
    DEMONHUNTER = { 0.375, 0.5,   0.25,  0.375 },
}

-- Reverse lookup: localized class name → class file token
local classFileByLocalName = {}
local function BuildClassNameLookup()
    if next(classFileByLocalName) then return end
    if LOCALIZED_CLASS_NAMES_MALE then
        for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE) do
            classFileByLocalName[name] = token
        end
    end
    if LOCALIZED_CLASS_NAMES_FEMALE then
        for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
            classFileByLocalName[name] = token
        end
    end
end

-- Single API call per button — returns (bnetAccountInfo, wowFriendInfo)
local function GetFriendInfo(button)
    if not button or not button.buttonType or not button.id then return nil, nil end
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        return C_BattleNet and C_BattleNet.GetFriendAccountInfo(button.id), nil
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        return nil, C_FriendList and C_FriendList.GetFriendInfoByIndex(button.id)
    end
    return nil, nil
end

local function GetFriendClassFile(bnetInfo, wowInfo)
    BuildClassNameLookup()
    if bnetInfo and bnetInfo.gameAccountInfo then
        local gi = bnetInfo.gameAccountInfo
        if gi.classID and gi.classID > 0 then
            local _, classFile = GetClassInfo(gi.classID)
            return classFile
        end
        if gi.className then
            return classFileByLocalName[gi.className]
        end
    elseif wowInfo and wowInfo.className then
        return classFileByLocalName[wowInfo.className]
    end
    return nil
end

local FRIEND_KEY_BNET_PREFIX = "bnet-"
local FRIEND_KEY_WOW_PREFIX  = "wow-"

local function GetFriendKey(button, bnetInfo, wowInfo)
    if bnetInfo then
        return FRIEND_KEY_BNET_PREFIX .. (bnetInfo.bnetAccountID or button.id)
    elseif wowInfo and wowInfo.name then
        return FRIEND_KEY_WOW_PREFIX .. wowInfo.name
    end
    return nil
end

local function IsFriendOnline(bnetInfo, wowInfo)
    if bnetInfo then
        return bnetInfo.gameAccountInfo and bnetInfo.gameAccountInfo.isOnline
    end
    if wowInfo then return wowInfo.connected end
    return false
end

local function GetFriendDisplayName(bnetInfo, wowInfo)
    if bnetInfo then return bnetInfo.accountName end
    if wowInfo then return wowInfo.name end
    return nil
end

-- Apply class icon to a friend button
local function UpdateClassIcon(button, bnetInfo, wowInfo)
    local p = EBS.db.profile.friends
    if not p.showClassIcons then
        if button._ebsClassIcon then button._ebsClassIcon:Hide() end
        return
    end

    local classFile = GetFriendClassFile(bnetInfo, wowInfo)
    if not classFile then
        if button._ebsClassIcon then button._ebsClassIcon:Hide() end
        return
    end

    if not button._ebsClassIcon then
        button._ebsClassIcon = button:CreateTexture(nil, "OVERLAY", nil, 2)
        button._ebsClassIcon:SetSize(16, 16)
    end
    local icon = button._ebsClassIcon
    local style = p.iconStyle or "blizzard"

    -- Skip texture/position updates if unchanged
    if button._ebsLastClassFile ~= classFile or button._ebsLastStyle ~= style then
        button._ebsLastClassFile = classFile
        button._ebsLastStyle = style
        if style == "blizzard" then
            icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
            if coords then
                icon:SetTexCoord(unpack(coords))
            end
        else
            local coords = CLASS_SPRITE_COORDS[classFile]
            if coords then
                icon:SetTexture(CLASS_ICON_SPRITE_BASE .. style .. ".tga")
                icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
        end
    end

    if not button._ebsIconAnchored then
        button._ebsIconAnchored = true
        icon:ClearAllPoints()
        local nameText = button.name or button.Name
        if nameText then
            icon:SetPoint("RIGHT", nameText, "LEFT", -4, 0)
        else
            icon:SetPoint("LEFT", button, "LEFT", 8, 0)
        end
    end

    local online = IsFriendOnline(bnetInfo, wowInfo)
    icon:SetDesaturated(not online)
    icon:SetAlpha(online and 1 or 0.5)
    icon:Show()
end

-- Apply group tag to a friend button
local function UpdateGroupTag(button, bnetInfo, wowInfo, accentR, accentG, accentB)
    local p = EBS.db.profile.friends
    if not p.groupsEnabled then
        if button._ebsGroupTag then button._ebsGroupTag:Hide() end
        return
    end

    local key = GetFriendKey(button, bnetInfo, wowInfo)
    local groupName = key and p.assignments[key]
    if not groupName then
        if button._ebsGroupTag then button._ebsGroupTag:Hide() end
        return
    end

    if not button._ebsGroupTag then
        button._ebsGroupTag = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button._ebsGroupTag:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    end
    local tag = button._ebsGroupTag
    tag:SetTextColor(accentR, accentG, accentB, 0.7)
    tag:SetText(groupName)
    tag:Show()
end

-- Update accent underline on active tab
local function UpdateTabUnderlines()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not p or not p.enabled then return end
    local selected = PanelTemplates_GetSelectedTab and
                     PanelTemplates_GetSelectedTab(FriendsFrame) or 1
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab and tab._ebsUnderline then
            tab._ebsUnderline:SetShown(i == selected)
        end
    end
end

-- Skin a single friend button (row bg + hover + fonts)
local function SkinFriendButton(button)
    if button._ebsSkinned then return end
    button._ebsSkinned = true

    local font = EllesmereUI.EXPRESSWAY or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

    -- Row background
    if not button._ebsRowBg then
        button._ebsRowBg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
        button._ebsRowBg:SetAllPoints()
    end

    -- Hover highlight
    if not button._ebsHover then
        button._ebsHover = button:CreateTexture(nil, "HIGHLIGHT")
        button._ebsHover:SetAllPoints()
        button._ebsHover:SetColorTexture(1, 1, 1, 0.08)
        button._ebsHover:SetBlendMode("ADD")
    end

    -- Apply EUI font to friend row text
    local nameText = button.name or button.Name
    if nameText and nameText.SetFont then nameText:SetFont(font, 12, "") end
    local infoText = button.info or button.Info
    if infoText and infoText.SetFont then infoText:SetFont(font, 10, "") end
    local statusText = button.status or button.Status
    if statusText and statusText.SetFont then statusText:SetFont(font, 10, "") end
    local gameText = button.gameText or button.GameText
    if gameText and gameText.SetFont then gameText:SetFont(font, 10, "") end
end

-- Apply alternating row colors to visible buttons
local function UpdateRowColors()
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if not scrollBox then return end
    local idx = 0
    for _, button in scrollBox:EnumerateFrames() do
        if button._ebsRowBg then
            button._ebsRowBg:SetColorTexture(1, 1, 1, 0)
        end
        idx = idx + 1
    end
end

-- Process all visible friend buttons (single API call per button)
local function ProcessFriendButtons()
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if not scrollBox then return end
    local ar, ag, ab = (EllesmereUI.GetAccentColor or function() return 0.047, 0.824, 0.624 end)()
    for _, button in scrollBox:EnumerateFrames() do
        SkinFriendButton(button)
        local bnetInfo, wowInfo = GetFriendInfo(button)
        UpdateClassIcon(button, bnetInfo, wowInfo)
        UpdateGroupTag(button, bnetInfo, wowInfo, ar, ag, ab)
    end
    UpdateRowColors()
end

-- Skin the scrollbar — hide Blizzard bar and overlay a thin EUI-style track
-- Skin a single ScrollBox+ScrollBar pair with EUI thin track
local function SkinOneScrollbar(scrollBox, scrollBar)
    if not scrollBox or not scrollBar then return end
    if scrollBox._ebsTrack then return end -- already skinned

    -- Hide Blizzard scrollbar visuals
    scrollBar:SetAlpha(0)

    -- Create thin EUI-style track overlay
    local track = CreateFrame("Frame", nil, scrollBox)
    track:SetWidth(4)
    track:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, -2)
    track:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 2)
    track:SetFrameLevel(scrollBox:GetFrameLevel() + 5)
    scrollBox._ebsTrack = track
    scrollBox._ebsScrollBar = scrollBar

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(1, 1, 1, 0.02)
    trackBg:SetAllPoints()

    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(4)
    thumb:SetHeight(60)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)
    scrollBox._ebsThumb = thumb

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetColorTexture(1, 1, 1, 0.27)
    thumbTex:SetAllPoints()

    local function UpdateThumb()
        local ok1, pct = pcall(function() return scrollBar:GetScrollPercentage() or 0 end)
        local ok2, extent = pcall(function() return scrollBar:GetVisibleExtentPercentage() or 1 end)
        if not ok1 then pct = 0 end
        if not ok2 then extent = 1 end
        if extent >= 1 then
            track:Hide()
            return
        end
        track:Show()
        local trackH = track:GetHeight()
        local thumbH = math.max(20, trackH * extent)
        thumb:SetHeight(thumbH)
        local travel = trackH - thumbH
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(travel * pct))
    end

    if scrollBar.RegisterCallback then
        scrollBar:RegisterCallback("OnScroll", UpdateThumb)
    end
    if scrollBar.SetScrollPercentage then
        hooksecurefunc(scrollBar, "SetScrollPercentage", function() C_Timer.After(0, UpdateThumb) end)
    end
    C_Timer.After(0.1, UpdateThumb)
end

-- Find and skin all scrollbars in the FriendsFrame hierarchy
local function SkinScrollbar()
    -- Known scroll frames across all tabs
    local targets = {
        FriendsListFrame,           -- Contacts tab
        WhoFrame or _G["WhoFrame"], -- Who tab
        _G["RaidFrame"],            -- Raid tab
        _G["QuickJoinFrame"],       -- Quick Join tab
        _G["RecruitAFriendFrame"],  -- Recruit a Friend
        _G["RecentAlliesFrame"],    -- Recent Allies
    }
    for _, f in ipairs(targets) do
        if f then
            -- Try direct .ScrollBox/.ScrollBar
            local sb = f.ScrollBox
            local bar = sb and (sb.ScrollBar or f.ScrollBar)
            if sb and bar then
                SkinOneScrollbar(sb, bar)
            end
            -- Also search one level of children for ScrollBox
            for _, child in ipairs({f:GetChildren()}) do
                if child.ScrollBox then
                    local csb = child.ScrollBox
                    local cbar = csb.ScrollBar or child.ScrollBar
                    if csb and cbar then SkinOneScrollbar(csb, cbar) end
                elseif child:GetObjectType() == "Frame" then
                    -- Check if the child itself is a ScrollBox-like frame
                    if child.ScrollBar and child.EnumerateFrames then
                        SkinOneScrollbar(child, child.ScrollBar)
                    end
                end
            end
        end
    end
end

-- Skin bottom-area buttons (AddFriend, etc.) — matches EUI footer button style
local function SkinBottomButton(btn, r, g, b, a)
    if not btn or btn._ebsBtnSkinned then return end
    btn._ebsBtnSkinned = true

    local font = EllesmereUI.EXPRESSWAY or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

    -- Strip ALL Blizzard art
    for _, child in ipairs({btn:GetRegions()}) do
        if child:IsObjectType("Texture") then
            child:SetAlpha(0)
        end
    end

    -- Dark background with margin (inset 3px each side for visual spacing)
    btn._ebsBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    btn._ebsBg:SetColorTexture(0.05, 0.07, 0.09, 0.92)
    btn._ebsBg:SetPoint("TOPLEFT", 3, -2)
    btn._ebsBg:SetPoint("BOTTOMRIGHT", -3, 2)

    PP.CreateBorder(btn, 1, 1, 1, 0.4, 1, "OVERLAY", 7)

    -- EUI font
    local text = btn:GetFontString()
    if text then
        text:SetFont(font, 13, "")
        text:SetTextColor(1, 1, 1, 0.5)
    end

    -- Hover fade (matching EUI footer buttons)
    btn:HookScript("OnEnter", function()
        if text then text:SetTextColor(1, 1, 1, 0.7) end
        if btn._ppBorders then PP.SetBorderColor(btn, 1, 1, 1, 0.6) end
        if btn._ebsBg then btn._ebsBg:SetColorTexture(0.05, 0.07, 0.09, 0.95) end
    end)
    btn:HookScript("OnLeave", function()
        if text then text:SetTextColor(1, 1, 1, 0.5) end
        if btn._ppBorders then PP.SetBorderColor(btn, 1, 1, 1, 0.4) end
        if btn._ebsBg then btn._ebsBg:SetColorTexture(0.05, 0.07, 0.09, 0.92) end
    end)
end

-- Right-click group menu (closures lifted to module level to avoid per-open allocation)
local _ctxMenuKey = nil
local _ctxMenuCurrentGroup = nil

local function OnGroupMenuClick(self, groupName)
    if not _ctxMenuKey then return end
    local fp = EBS.db.profile.friends
    fp.assignments[_ctxMenuKey] = groupName or nil
    CloseDropDownMenus()
    ProcessFriendButtons()
end

local function InitGroupMenu(self, level)
    if not level or level ~= 1 then return end
    local fp = EBS.db.profile.friends

    local info = UIDropDownMenu_CreateInfo()
    info.text = "Set Group"
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    for _, group in ipairs(fp.groups) do
        info = UIDropDownMenu_CreateInfo()
        info.text = group.name
        info.checked = (_ctxMenuCurrentGroup == group.name)
        info.func = OnGroupMenuClick
        info.arg1 = group.name
        UIDropDownMenu_AddButton(info, level)
    end

    info = UIDropDownMenu_CreateInfo()
    info.text = " "
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = "Remove from Group"
    info.notCheckable = true
    info.disabled = (_ctxMenuCurrentGroup == nil)
    info.func = OnGroupMenuClick
    info.arg1 = nil
    UIDropDownMenu_AddButton(info, level)
end

local function BuildGroupContextMenu(button)
    local p = EBS.db.profile.friends
    if not p.groupsEnabled then return end

    local bnetInfo, wowInfo = GetFriendInfo(button)
    _ctxMenuKey = GetFriendKey(button, bnetInfo, wowInfo)
    if not _ctxMenuKey then return end
    _ctxMenuCurrentGroup = p.assignments[_ctxMenuKey]

    local menuFrame = _G["EBS_FriendGroupMenu"]
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "EBS_FriendGroupMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(menuFrame, InitGroupMenu, "MENU")
    ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end

-- Hook new ScrollBox buttons for right-click group menu
local function HookNewButtonClicks(scrollBox)
    for _, button in scrollBox:EnumerateFrames() do
        if not button._ebsClickHooked and button.RegisterForClicks then
            button._ebsClickHooked = true
            button:HookScript("OnClick", function(btn, mouseButton)
                if mouseButton == "RightButton" then
                    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
                    if fp and fp.enabled and fp.groupsEnabled then
                        BuildGroupContextMenu(btn)
                    end
                end
            end)
        end
    end
end

-- One-time structural setup
local function SkinFriendsFrame()
    local frame = FriendsFrame
    if not frame or friendsSkinned then return end
    friendsSkinned = true

    local p = EBS.db.profile.friends

    -- ── Hide Blizzard decorations ──────────────────────────────────────
    if frame.NineSlice then frame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end
    if frame.TopTileStreaks then frame.TopTileStreaks:Hide() end

    -- Portrait / top-left icon — hide everything related
    if frame.portrait then frame.portrait:Hide() end
    if frame.PortraitContainer then
        frame.PortraitContainer:Hide()
        if frame.PortraitContainer.portrait then frame.PortraitContainer.portrait:Hide() end
    end
    if FriendsFramePortrait then FriendsFramePortrait:Hide() end
    if FriendsFrameIcon then FriendsFrameIcon:Hide() end
    if frame.PortraitFrame then frame.PortraitFrame:Hide() end
    if frame.portraitIcon then frame.portraitIcon:Hide() end

    -- ButtonFrameTemplate border textures
    for _, key in ipairs({"TopBorder", "TopRightCorner", "RightBorder",
                          "BottomRightCorner", "BottomBorder", "BottomLeftCorner",
                          "LeftBorder", "TopLeftCorner", "BtnCornerLeft",
                          "BtnCornerRight"}) do
        if frame[key] then frame[key]:Hide() end
    end

    -- Inset
    if frame.Inset then
        if frame.Inset.NineSlice then frame.Inset.NineSlice:Hide() end
        if frame.Inset.Bg then frame.Inset.Bg:Hide() end
    end

    -- ── Dark background (EUI panel color) ───────────────────────────
    frame._ebsBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame._ebsBg:SetColorTexture(0.05, 0.07, 0.09)
    frame._ebsBg:SetAllPoints()
    frame._ebsBg:SetAlpha(p.bgAlpha)

    -- ── Pixel border on frame (always created, alpha-controlled) ───────
    local r, g, b, a = GetBorderColor(p)
    local borderAlpha = (p.showBorder ~= false) and a or 0
    PP.CreateBorder(frame, r, g, b, borderAlpha, 1, "OVERLAY", 7)

    -- ── Bottom tab bar background (extends main frame bg) ───────────────
    if not frame._ebsTabBarBg then
        -- Find the first and last tab to size the bar
        local firstTab = _G["FriendsFrameTab1"]
        local lastTab = _G["FriendsFrameTab4"] or _G["FriendsFrameTab3"] or _G["FriendsFrameTab2"] or firstTab
        if firstTab then
            frame._ebsTabBarBg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
            frame._ebsTabBarBg:SetColorTexture(0.05, 0.07, 0.09)
            frame._ebsTabBarBg:SetAlpha(p.bgAlpha)
            -- Span the full width of the frame, from bottom of frame down to bottom of tabs
            frame._ebsTabBarBg:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 2)
            frame._ebsTabBarBg:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 2)
            frame._ebsTabBarBg:SetPoint("BOTTOM", firstTab, "BOTTOM", 0, 0)
        end
    end

    -- ── Skin tabs ──────────────────────────────────────────────────────
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            -- Move first tab flush with frame left edge
            if i == 1 then
                tab:ClearAllPoints()
                tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 2)
            end

            -- Lock tab geometry — prevent Blizzard from resizing/offsetting on select/deselect
            if tab.SetPushedTextOffset then
                tab:SetPushedTextOffset(0, 0)
                tab.SetPushedTextOffset = function() end
            end
            -- Lock height so PanelTemplates_TabResize can't change it
            local tabH = tab:GetHeight()
            tab.SetHeight = function(self, h) end
            -- Lock text position so it never shifts
            local text = tab:GetFontString()
            if text then
                text:ClearAllPoints()
                text:SetPoint("CENTER", tab, "CENTER", 0, 0)
            end

            -- Hide all Blizzard tab textures
            for _, child in ipairs({tab:GetRegions()}) do
                if child:IsObjectType("Texture") then
                    child:SetAlpha(0)
                end
            end



            -- Accent underline (always created, shown/hidden by UpdateTabUnderlines)
            do
                local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
                underline:SetHeight(2)
                underline:SetPoint("BOTTOMLEFT", 2, 0)
                underline:SetPoint("BOTTOMRIGHT", -2, 0)
                local ar, ag, ab
                if EllesmereUI.GetAccentColor then
                    ar, ag, ab = EllesmereUI.GetAccentColor()
                else
                    ar, ag, ab = 0.047, 0.824, 0.624
                end
                underline:SetColorTexture(ar, ag, ab, 1)
                tab._ebsUnderline = underline
                EllesmereUI.RegAccent({ type = "solid", obj = underline, a = 1 })
                underline:Hide()
            end
        end
    end
    -- Set initial underline visibility
    C_Timer.After(0, UpdateTabUnderlines)

    -- Build set of bottom tab frames to exclude from button skinning
    local bottomTabSet = {}
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then bottomTabSet[tab] = true end
    end

    -- Hook tab switching — update underlines + skin new buttons on the visible tab
    if PanelTemplates_SetTab then
        hooksecurefunc("PanelTemplates_SetTab", function(f)
            if f == FriendsFrame then
                -- Re-zero pushed text offset (Blizzard resets on tab switch)
                for i = 1, 4 do
                    local tab = _G["FriendsFrameTab" .. i]
                    if tab and tab.SetPushedTextOffset then
                        tab:SetPushedTextOffset(0, 0)
                    end
                end
                UpdateTabUnderlines()
                -- Skin scrollbars + action buttons on newly-visible tab
                if EBS.db and EBS.db.profile.friends.enabled then
                    SkinScrollbar()
                    C_Timer.After(0.1, function()
                        local p2 = EBS.db.profile.friends
                        local r2, g2, b2, a2 = GetBorderColor(p2)
                        local function SkinNewButtons(parent)
                            if not parent then return end
                            for _, child in ipairs({parent:GetChildren()}) do
                                if child:IsObjectType("Button") and not child._ebsBtnSkinned
                                   and not child._ebsSubSkinned and not bottomTabSet[child] then
                                    local ok, txt = pcall(function() return child:GetText() end)
                                    if ok and txt and #txt > 1 then
                                        local lower = txt:lower()
                                        local isAction = (lower:find("add") and lower:find("friend"))
                                            or lower:find("send") or lower:find("message")
                                            or lower:find("refresh") or lower:find("group")
                                            or lower:find("invite") or lower:find("raid")
                                            or lower:find("convert") or lower:find("info")
                                            or lower:find("request") or lower:find("join")
                                        local isSubTab = lower == "friends" or lower == "recent"
                                            or lower == "allies" or lower:find("recruit a friend")
                                            or lower == "contacts" or lower == "who" or lower == "quick join"
                                        if isAction and not isSubTab then
                                            SkinBottomButton(child, r2, g2, b2, a2)
                                        end
                                    end
                                end
                                SkinNewButtons(child)
                            end
                        end
                        SkinNewButtons(frame)
                    end)
                end
            end
        end)
    end
    -- Hook tab select/deselect to re-zero pushed text offset
    if PanelTemplates_SelectTab then
        hooksecurefunc("PanelTemplates_SelectTab", function(tab)
            if tab and tab.SetPushedTextOffset then tab:SetPushedTextOffset(0, 0) end
        end)
    end
    if PanelTemplates_DeselectTab then
        hooksecurefunc("PanelTemplates_DeselectTab", function(tab)
            if tab and tab.SetPushedTextOffset then tab:SetPushedTextOffset(0, 0) end
        end)
    end

    -- ── Skin scrollbar ─────────────────────────────────────────────────
    SkinScrollbar()

    -- ── Hook friend button updates ─────────────────────────────────────
    if FriendsFrame_UpdateFriendButton and not friendButtonHooked then
        friendButtonHooked = true
        hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button)
            if not EBS.db or not EBS.db.profile.friends.enabled then return end
            SkinFriendButton(button)
            local bnetInfo, wowInfo = GetFriendInfo(button)
            local ar, ag, ab = (EllesmereUI.GetAccentColor or function() return 0.047, 0.824, 0.624 end)()
            UpdateClassIcon(button, bnetInfo, wowInfo)
            UpdateGroupTag(button, bnetInfo, wowInfo, ar, ag, ab)
        end)
    end

    -- Single scroll hook: row colors + right-click hooking
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if scrollBox then
        hooksecurefunc(scrollBox, "Update", function(self)
            if not EBS.db or not EBS.db.profile.friends.enabled then return end
            UpdateRowColors()
            HookNewButtonClicks(self)
        end)
    end

    -- ── Skin Who tab content to match Contacts tab ─────────────────────
    local function SkinWhoFrame()
        local who = WhoFrame or _G["WhoFrame"]
        if not who or who._ebsSkinned then return end
        who._ebsSkinned = true

        local font = EllesmereUI.EXPRESSWAY or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

        -- Strip ALL Blizzard textures from a frame
        local function StripTextures(f)
            if not f then return end
            for _, region in ipairs({f:GetRegions()}) do
                if region:IsObjectType("Texture") then
                    region:SetAlpha(0)
                end
            end
        end

        -- Strip Who frame's own textures
        StripTextures(who)

        -- Hide NineSlice / Inset / border frames
        if who.NineSlice then who.NineSlice:Hide() end
        if who.Inset then
            if who.Inset.NineSlice then who.Inset.NineSlice:Hide() end
            if who.Inset.Bg then who.Inset.Bg:Hide() end
            StripTextures(who.Inset)
        end

        -- Strip ALL children frame textures recursively (depth 1)
        for _, child in ipairs({who:GetChildren()}) do
            if child:IsObjectType("Frame") and not child:IsObjectType("Button") then
                local cname = child:GetName() or ""
                if not cname:find("ScrollBox") and not cname:find("ScrollBar") then
                    StripTextures(child)
                    if child.NineSlice then child.NineSlice:Hide() end
                end
            end
        end

        -- Skin column headers
        for i = 1, 6 do
            local col = _G["WhoFrameColumn_" .. i] or _G["WhoFrameColumnHeader" .. i]
            if col then
                StripTextures(col)
                local text = col:GetFontString()
                if text then
                    text:SetFont(font, 11, "")
                    text:SetTextColor(1, 1, 1, 0.53)
                end
                -- Add subtle bottom border
                col._ebsDiv = col:CreateTexture(nil, "OVERLAY")
                local div = col._ebsDiv
                div:SetColorTexture(1, 1, 1, 0.06)
                div:SetHeight(1)
                div:SetPoint("BOTTOMLEFT", 0, 0)
                div:SetPoint("BOTTOMRIGHT", 0, 0)
            end
        end

        -- Skin the search edit box
        local editBox = WhoFrameEditBox or _G["WhoFrameEditBox"]
        if editBox then
            StripTextures(editBox)
            -- Dark bg for edit box
            if not editBox._ebsBg then
                editBox._ebsBg = editBox:CreateTexture(nil, "BACKGROUND", nil, -6)
                editBox._ebsBg:SetColorTexture(0.05, 0.07, 0.09, 0.8)
                editBox._ebsBg:SetPoint("TOPLEFT", -4, 2)
                editBox._ebsBg:SetPoint("BOTTOMRIGHT", 4, -2)
            end
            editBox:SetFont(font, 12, "")
            editBox:SetTextColor(1, 1, 1, 0.8)
        end

        -- Skin the total count text
        local totalCount = WhoFrameTotals or _G["WhoFrameTotals"]
        if totalCount and totalCount.SetFont then
            totalCount:SetFont(font, 11, "")
            totalCount:SetTextColor(1, 1, 1, 0.53)
        end

        -- Skin list rows — strip textures, apply EUI font
        local function SkinWhoButtons()
            for i = 1, 22 do
                local btn = _G["WhoFrameButton" .. i]
                if btn and not btn._ebsSkinned then
                    btn._ebsSkinned = true
                    StripTextures(btn)
                    -- Hover highlight
                    btn._ebsHover = btn:CreateTexture(nil, "HIGHLIGHT")
                    btn._ebsHover:SetAllPoints()
                    btn._ebsHover:SetColorTexture(1, 1, 1, 0.08)
                    btn._ebsHover:SetBlendMode("ADD")
                    -- Font for all text columns
                    for j = 1, 6 do
                        local colText = _G["WhoFrameButton" .. i .. "Name"]
                            or _G["WhoFrameButton" .. i .. "Column" .. j]
                        if colText and colText.SetFont then
                            colText:SetFont(font, 11, "")
                        end
                    end
                    -- Also try standard name/level/class/race/zone fields
                    for _, key in ipairs({"Name", "Level", "Class", "Race", "Zone"}) do
                        local txt = _G["WhoFrameButton" .. i .. key]
                        if txt and txt.SetFont then
                            txt:SetFont(font, 11, "")
                        end
                    end
                end
            end
        end
        SkinWhoButtons()

        -- Hook Who list updates to skin new rows
        if WhoList_Update then
            hooksecurefunc("WhoList_Update", function()
                if EBS.db and EBS.db.profile.friends.enabled then
                    SkinWhoButtons()
                end
            end)
        end

        -- Also search children recursively for any unskinned textures
        for _, child in ipairs({who:GetChildren()}) do
            if child:IsObjectType("Frame") and not child:IsObjectType("Button") then
                local cname = child:GetName() or ""
                -- Skip ScrollBox (handled by SkinScrollbar)
                if not cname:find("ScrollBox") and not cname:find("ScrollBar") then
                    StripTextures(child)
                end
            end
        end
    end
    -- Skin immediately if WhoFrame exists, also on tab switch
    SkinWhoFrame()
    frame:HookScript("OnShow", function()
        C_Timer.After(0.1, SkinWhoFrame)
    end)

    -- ── Skin bottom buttons ────────────────────────────────────────────
    -- Search all descendants for Add Friend / Send Message buttons
    -- Be specific: only match action buttons, NOT sub-tab labels or bottom tabs
    local function FindButtons(parent)
        if not parent then return end
        for _, child in ipairs({parent:GetChildren()}) do
            if child:IsObjectType("Button") and not bottomTabSet[child]
               and not child._ebsSubSkinned then
                local ok, txt = pcall(function() return child:GetText() end)
                if ok and txt and #txt > 1 then
                    local lower = txt:lower()
                    -- Match action buttons across all tabs (but not sub-tab labels)
                    local isActionBtn = (lower:find("add") and lower:find("friend"))
                        or lower:find("send") or lower:find("message")
                        or lower:find("refresh") or lower:find("group")
                        or lower:find("invite") or lower:find("raid")
                        or lower:find("convert") or lower:find("info")
                        or lower:find("request") or lower:find("join")
                    -- Exclude sub-tab labels
                    local isSubTab = lower == "friends" or lower == "recent" or lower == "allies"
                        or lower:find("recruit a friend")
                        or lower == "contacts" or lower == "who" or lower == "quick join"
                    if isActionBtn and not isSubTab then
                        SkinBottomButton(child, r, g, b, a)
                    end
                end
            end
            FindButtons(child)
        end
    end
    FindButtons(frame)
    if FriendsListFrame then FindButtons(FriendsListFrame) end

    -- ── Apply EUI font to all buttons and tabs ───────────────────────
    local font = EllesmereUI.EXPRESSWAY or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

    -- Main tab fonts (Friends/Who/Raid/Quick Join) — white text, dimmed for inactive
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            local text = tab:GetFontString()
            if text then
                text:SetFont(font, 11, "")
                text:SetTextColor(1, 1, 1, 1)
            end
            -- Override Blizzard's yellow highlight/normal colors
            if tab.Text then
                tab.Text:SetFont(font, 11, "")
                tab.Text:SetTextColor(1, 1, 1, 1)
            end
        end
    end

    -- Hook tab switching to keep white text (Blizzard resets to yellow)
    if PanelTemplates_SetTab and not frame._ebsTabColorHooked then
        frame._ebsTabColorHooked = true
        hooksecurefunc("PanelTemplates_SetTab", function(f)
            if f ~= FriendsFrame then return end
            local selected = PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(f) or 1
            for i = 1, 4 do
                local tab = _G["FriendsFrameTab" .. i]
                if tab then
                    local text = tab:GetFontString() or tab.Text
                    if text then
                        text:SetTextColor(1, 1, 1, i == selected and 1 or 0.5)
                    end
                end
            end
        end)
    end

    -- Title text
    if frame.TitleContainer then
        local title = frame.TitleContainer.TitleText or frame.TitleContainer:GetFontString()
        if title then
            title:SetFont(font, 13, "")
            title:SetTextColor(1, 1, 1, 1)
        end
    elseif FriendsFrameTitleText then
        FriendsFrameTitleText:SetFont(font, 13, "")
        FriendsFrameTitleText:SetTextColor(1, 1, 1, 1)
    end

    -- ── Subtle divider under title (EUI content header style) ──────
    if not frame._ebsTitleDiv then
        frame._ebsTitleDiv = frame:CreateTexture(nil, "OVERLAY", nil, 1)
        frame._ebsTitleDiv:SetColorTexture(1, 1, 1, 0.06)
        frame._ebsTitleDiv:SetHeight(1)
        frame._ebsTitleDiv:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -24)
        frame._ebsTitleDiv:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -24)
    end

    -- ── Skin sub-tabs (Friends/Recent/Allies/Recruit) — EUI tab bar style ──
    -- Matches EUI exactly: height 40, font 16pt Expressway, dim white 0.53a,
    -- full white active, accent underline only on active, 6px gap, no bg
    local EUI_TAB_H = 30
    local EUI_TAB_PAD = 10    -- horizontal text padding (20 total = textW + 20)
    local EUI_TAB_GAP = 4     -- gap between tabs
    local EUI_TAB_FONT = 12
    local skinnedSubTabs = {}

    local function SkinSubTab(subTab)
        if not subTab or subTab._ebsSubSkinned then return end
        subTab._ebsSubSkinned = true
        skinnedSubTabs[#skinnedSubTabs + 1] = subTab

        -- Strip ALL Blizzard textures on tab and its children
        for _, region in ipairs({subTab:GetRegions()}) do
            if region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end
        for _, child in ipairs({subTab:GetChildren()}) do
            for _, tex in ipairs({child:GetRegions()}) do
                if tex:IsObjectType("Texture") then
                    tex:SetAlpha(0)
                end
            end
        end

        -- Kill Blizzard's pushed text offset (causes text to jump down on active)
        if subTab.SetPushedTextOffset then
            subTab:SetPushedTextOffset(0, 0)
        end
        if subTab.SetDisabledFontObject and subTab.GetNormalFontObject then
            local nfo = subTab:GetNormalFontObject()
            if nfo then subTab:SetDisabledFontObject(nfo) end
        end

        -- EUI font — Expressway, dim white for inactive
        local text = subTab:GetFontString()
        if text then
            text:SetFont(font, EUI_TAB_FONT, "")
            text:SetTextColor(1, 1, 1, 0.53)
            text:SetDrawLayer("OVERLAY", 2)
        end

        local textW = text and text:GetStringWidth() or 40

        -- Accent underline — 2px, always present (transparent when inactive, visible when active)
        local underline = subTab:CreateTexture(nil, "OVERLAY", nil, 6)
        underline:SetHeight(2)
        underline:SetWidth(textW + 14)
        underline:SetPoint("BOTTOM", subTab, "BOTTOM", 0, 0)
        local ar, ag, ab = (EllesmereUI.GetAccentColor or function() return 0.047, 0.824, 0.624 end)()
        underline:SetColorTexture(ar, ag, ab, 1)
        EllesmereUI.RegAccent({ type = "solid", obj = underline, a = 1 })
        underline:SetAlpha(0)  -- start transparent, UpdateSubTabStates sets alpha
        subTab._ebsUnderline = underline

        -- Hover/leave handled by UpdateSubTabStates below
        subTab:HookScript("OnEnter", function()
            if text and not subTab._ebsActive then
                text:SetTextColor(1, 1, 1, 0.86)
            end
        end)
        subTab:HookScript("OnLeave", function()
            if text then
                text:SetTextColor(1, 1, 1, subTab._ebsActive and 1 or 0.53)
            end
        end)
    end

    -- Update all sub-tab underlines/colors based on Blizzard's own enabled state
    -- Blizzard disables (SetEnabled(false)) inactive tabs after click
    local function UpdateSubTabStates()
        for _, st in ipairs(skinnedSubTabs) do
            -- Blizzard marks active tab as disabled (not clickable) and inactive as enabled
            local isSelected = st.IsEnabled and not st:IsEnabled()
            -- Fallback: check button state
            if st.GetButtonState then
                local state = st:GetButtonState()
                if state == "PUSHED" or state == "DISABLED" then isSelected = true end
            end
            st._ebsActive = isSelected
            if st._ebsUnderline then st._ebsUnderline:SetAlpha(isSelected and 1 or 0) end
            local stText = st:GetFontString()
            if stText then stText:SetTextColor(1, 1, 1, isSelected and 1 or 0.53) end
        end
    end

    -- Don't reposition tabs — let Blizzard handle layout, we only restyle visuals
    local function RepositionSubTabs() end

    -- Scan a frame tree for unskinned tab-like buttons (depth-limited)
    local function ScanForSubTabs(parent, depth)
        if depth > 3 or not parent then return end
        for _, child in ipairs({parent:GetChildren()}) do
            if child:IsObjectType("Button") and not child._ebsSubSkinned
               and not child._ebsBtnSkinned then
                local name = child:GetName() or ""
                local ok, txt = pcall(function() return child:GetText() end)
                local isTab = name:lower():find("tab")
                if ok and txt and #txt > 0 and #txt < 30 then
                    local lower = txt:lower()
                    isTab = isTab or lower:find("friend") or lower:find("recent")
                            or lower:find("all") or lower:find("allies") or lower:find("recruit")
                end
                if isTab then SkinSubTab(child) end
            end
            -- Strip bg textures on header-like frames
            if child:IsObjectType("Frame") and not child:IsObjectType("Button") then
                local cname = child:GetName() or ""
                if cname:lower():find("tab") or cname:lower():find("header") then
                    for _, region in ipairs({child:GetRegions()}) do
                        if region:IsObjectType("Texture") then region:SetAlpha(0) end
                    end
                end
            end
            ScanForSubTabs(child, depth + 1)
        end
    end

    -- Scan _G for FriendsTabHeader* globals
    local function ScanGlobalsForTabs()
        for k, v in pairs(_G) do
            if type(k) == "string" and k:find("^FriendsTabHeader") and type(v) == "table"
               and type(v.GetObjectType) == "function" then
                if v:IsObjectType("Button") then
                    SkinSubTab(v)
                elseif v:IsObjectType("Frame") then
                    for _, region in ipairs({v:GetRegions()}) do
                        if region:IsObjectType("Texture") then region:SetAlpha(0) end
                    end
                    for _, child in ipairs({v:GetChildren()}) do
                        if child:IsObjectType("Button") then SkinSubTab(child) end
                    end
                end
            end
        end
    end

    -- Run scan and set initial underline state
    local function ScanAllSubTabs()
        local prevCount = #skinnedSubTabs
        ScanGlobalsForTabs()
        ScanForSubTabs(frame, 0)
        if FriendsListFrame then ScanForSubTabs(FriendsListFrame, 0) end
        -- Hook OnClick on any newly-skinned tabs to trigger state update
        for i = prevCount + 1, #skinnedSubTabs do
            skinnedSubTabs[i]:HookScript("OnClick", function()
                C_Timer.After(0.05, UpdateSubTabStates)
            end)
        end
        -- Update states after Blizzard has finished its own setup
        C_Timer.After(0.1, UpdateSubTabStates)
    end

    -- Run immediately + hook OnShow for lazily-created tabs
    ScanAllSubTabs()
    frame:HookScript("OnShow", function()
        C_Timer.After(0.05, ScanAllSubTabs)
    end)
    if FriendsListFrame then
        FriendsListFrame:HookScript("OnShow", function()
            C_Timer.After(0.05, ScanAllSubTabs)
        end)
    end

    -- ── Skin close button — EUI style (custom X with hover) ─────────
    local closeBtn = frame.CloseButton or _G["FriendsFrameCloseButton"]
    if closeBtn then
        -- Store refs to Blizzard textures so we can toggle them
        if not closeBtn._ebsBlizzTextures then
            closeBtn._ebsBlizzTextures = {}
            for _, child in ipairs({closeBtn:GetRegions()}) do
                if child:IsObjectType("Texture") then
                    closeBtn._ebsBlizzTextures[#closeBtn._ebsBlizzTextures + 1] = child
                    child:SetAlpha(0)
                end
            end
        end
        -- Custom X label
        if not closeBtn._ebsX then
            closeBtn._ebsX = closeBtn:CreateFontString(nil, "OVERLAY")
            closeBtn._ebsX:SetFont(font, 16, "")
            closeBtn._ebsX:SetText("x")
            closeBtn._ebsX:SetTextColor(1, 1, 1, 0.5)
            closeBtn._ebsX:SetPoint("CENTER", 0, 0)
        end
        closeBtn:HookScript("OnEnter", function()
            if closeBtn._ebsX then closeBtn._ebsX:SetTextColor(1, 1, 1, 0.9) end
        end)
        closeBtn:HookScript("OnLeave", function()
            if closeBtn._ebsX then closeBtn._ebsX:SetTextColor(1, 1, 1, 0.5) end
        end)
    end

    -- Initial tab underline update
    C_Timer.After(0, UpdateTabUnderlines)
end

-- Live updates: colors, opacity — safe to call repeatedly
local function ApplyFriends()
    if InCombatLockdown() then QueueApplyAll(); return end

    local p = EBS.db.profile.friends

    if not p.enabled then
        if FriendsFrame and friendsSkinned then
            -- Restore Blizzard chrome
            if FriendsFrame._ebsBg then FriendsFrame._ebsBg:SetAlpha(0) end
            if FriendsFrame._ppBorders then PP.SetBorderColor(FriendsFrame, 0, 0, 0, 0) end
            if FriendsFrame.NineSlice then FriendsFrame.NineSlice:Show() end
            if FriendsFrame.Bg then FriendsFrame.Bg:Show() end
            if FriendsFrame.TitleBg then FriendsFrame.TitleBg:Show() end
            if FriendsFrame.portrait then FriendsFrame.portrait:Show() end
            if FriendsFrame.PortraitContainer then
                FriendsFrame.PortraitContainer:Show()
                if FriendsFrame.PortraitContainer.portrait then FriendsFrame.PortraitContainer.portrait:Show() end
            end
            if FriendsFramePortrait then FriendsFramePortrait:Show() end
            if FriendsFrameIcon then FriendsFrameIcon:Show() end
            if FriendsFrame.PortraitFrame then FriendsFrame.PortraitFrame:Show() end
            if FriendsFrame.portraitIcon then FriendsFrame.portraitIcon:Show() end
            -- Hide EUI background + theme texture + tab bar bg + title divider + border
            if FriendsFrame._ebsBg then FriendsFrame._ebsBg:SetAlpha(0) end
            if FriendsFrame._ebsTabBarBg then FriendsFrame._ebsTabBarBg:SetAlpha(0) end
            if FriendsFrame._ebsTitleDiv then FriendsFrame._ebsTitleDiv:Hide() end
            if FriendsFrame._ppBorders then PP.SetBorderColor(FriendsFrame, 0, 0, 0, 0) end
            -- Restore Inset
            if FriendsFrame.Inset then
                if FriendsFrame.Inset.NineSlice then FriendsFrame.Inset.NineSlice:Show() end
                if FriendsFrame.Inset.Bg then FriendsFrame.Inset.Bg:Show() end
            end
            -- Restore bottom tabs
            for i = 1, 4 do
                local tab = _G["FriendsFrameTab" .. i]
                if tab then
                    if tab._ebsBg then tab._ebsBg:Hide() end
                    if tab._ebsUnderline then tab._ebsUnderline:Hide() end
                    -- Restore original tab textures
                    for _, child in ipairs({tab:GetRegions()}) do
                        if child:IsObjectType("Texture")
                           and child ~= tab._ebsBg
                           and child ~= tab._ebsUnderline then
                            child:SetAlpha(1)
                        end
                    end
                end
            end
            -- Restore sub-tabs (Friends/Recent/Allies/Recruit)
            local function RestoreSubTabs(parent, depth)
                if depth > 3 or not parent then return end
                for _, child in ipairs({parent:GetChildren()}) do
                    if child._ebsSubSkinned then
                        -- Restore Blizzard textures
                        for _, region in ipairs({child:GetRegions()}) do
                            if region:IsObjectType("Texture")
                               and region ~= child._ebsUnderline then
                                region:SetAlpha(1)
                            end
                        end
                        for _, sub in ipairs({child:GetChildren()}) do
                            for _, tex in ipairs({sub:GetRegions()}) do
                                if tex:IsObjectType("Texture") then tex:SetAlpha(1) end
                            end
                        end
                        if child._ebsUnderline then child._ebsUnderline:SetAlpha(0) end
                    end
                    -- Restore header frame textures
                    if child:IsObjectType("Frame") and not child:IsObjectType("Button") then
                        local cname = child:GetName() or ""
                        if cname:lower():find("tab") or cname:lower():find("header") then
                            for _, region in ipairs({child:GetRegions()}) do
                                if region:IsObjectType("Texture") then region:SetAlpha(1) end
                            end
                        end
                    end
                    RestoreSubTabs(child, depth + 1)
                end
            end
            RestoreSubTabs(FriendsFrame, 0)
            if FriendsListFrame then RestoreSubTabs(FriendsListFrame, 0) end
            -- Restore bottom buttons (Add Friend / Send Message)
            local function RestoreButtons(parent)
                if not parent then return end
                for _, child in ipairs({parent:GetChildren()}) do
                    if child._ebsBtnSkinned then
                        if child._ppBorders then PP.SetBorderColor(child, 0, 0, 0, 0) end
                        if child._ebsBg then child._ebsBg:Hide() end
                        -- Restore ALL Blizzard textures that were stripped
                        for _, region in ipairs({child:GetRegions()}) do
                            if region:IsObjectType("Texture") and region ~= child._ebsBg then
                                region:SetAlpha(1)
                            end
                        end
                    end
                    RestoreButtons(child)
                end
            end
            RestoreButtons(FriendsFrame)
            if FriendsListFrame then RestoreButtons(FriendsListFrame) end
            -- Restore close button
            local cb = FriendsFrame.CloseButton or _G["FriendsFrameCloseButton"]
            if cb then
                if cb._ebsBlizzTextures then
                    for _, tex in ipairs(cb._ebsBlizzTextures) do tex:SetAlpha(1) end
                end
                if cb._ebsX then cb._ebsX:Hide() end
            end
            -- Restore all scrollbars — show Blizzard, hide EUI tracks
            local scrollTargets = {
                FriendsListFrame, WhoFrame or _G["WhoFrame"],
                _G["RaidFrame"], _G["QuickJoinFrame"],
                _G["RecruitAFriendFrame"], _G["RecentAlliesFrame"],
            }
            for _, sf in ipairs(scrollTargets) do
                if sf then
                    local sbox = sf.ScrollBox
                    if sbox then
                        if sbox._ebsScrollBar then sbox._ebsScrollBar:SetAlpha(1) end
                        if sbox._ebsTrack then sbox._ebsTrack:Hide() end
                    end
                    -- Also check children
                    for _, ch in ipairs({sf:GetChildren()}) do
                        if ch.ScrollBox then
                            local csb = ch.ScrollBox
                            if csb._ebsScrollBar then csb._ebsScrollBar:SetAlpha(1) end
                            if csb._ebsTrack then csb._ebsTrack:Hide() end
                        end
                    end
                end
            end
            -- Restore friend row visuals
            if scrollBox then
                for _, button in scrollBox:EnumerateFrames() do
                    if button._ebsRowBg then button._ebsRowBg:SetAlpha(0) end
                    if button._ebsHover then button._ebsHover:Hide() end
                    if button._ebsClassIcon then button._ebsClassIcon:Hide() end
                    if button._ebsGroupTag then button._ebsGroupTag:Hide() end
                end
            end
            -- Restore Who frame
            local who = WhoFrame or _G["WhoFrame"]
            if who then
                -- Restore all WhoFrame textures
                for _, region in ipairs({who:GetRegions()}) do
                    if region:IsObjectType("Texture") then region:SetAlpha(1) end
                end
                if who.NineSlice then who.NineSlice:Show() end
                if who.Inset then
                    if who.Inset.NineSlice then who.Inset.NineSlice:Show() end
                    if who.Inset.Bg then who.Inset.Bg:Show() end
                    for _, region in ipairs({who.Inset:GetRegions()}) do
                        if region:IsObjectType("Texture") then region:SetAlpha(1) end
                    end
                end
                -- Restore child frame textures
                for _, child in ipairs({who:GetChildren()}) do
                    if child:IsObjectType("Frame") and not child:IsObjectType("Button") then
                        for _, region in ipairs({child:GetRegions()}) do
                            if region:IsObjectType("Texture") then region:SetAlpha(1) end
                        end
                        if child.NineSlice then child.NineSlice:Show() end
                    end
                end
                -- Hide Who column dividers and restore column header textures
                for i = 1, 6 do
                    local col = _G["WhoFrameColumn_" .. i] or _G["WhoFrameColumnHeader" .. i]
                    if col then
                        if col._ebsDiv then col._ebsDiv:Hide() end
                        for _, region in ipairs({col:GetRegions()}) do
                            if region:IsObjectType("Texture") and region ~= col._ebsDiv then
                                region:SetAlpha(1)
                            end
                        end
                    end
                end
                -- Hide edit box EUI bg, restore textures
                local editBox = WhoFrameEditBox or _G["WhoFrameEditBox"]
                if editBox then
                    if editBox._ebsBg then editBox._ebsBg:Hide() end
                    for _, region in ipairs({editBox:GetRegions()}) do
                        if region:IsObjectType("Texture") and region ~= editBox._ebsBg then
                            region:SetAlpha(1)
                        end
                    end
                end
                -- Restore Who row buttons
                for i = 1, 22 do
                    local btn = _G["WhoFrameButton" .. i]
                    if btn then
                        if btn._ebsHover then btn._ebsHover:Hide() end
                        for _, region in ipairs({btn:GetRegions()}) do
                            if region:IsObjectType("Texture") and region ~= btn._ebsHover then
                                region:SetAlpha(1)
                            end
                        end
                    end
                end
            end
        end
        return
    end

    -- FriendsFrame is load-on-demand
    if not FriendsFrame then return end
    SkinFriendsFrame()

    -- Re-hide Blizzard chrome
    if FriendsFrame.NineSlice then FriendsFrame.NineSlice:Hide() end
    if FriendsFrame.Bg then FriendsFrame.Bg:Hide() end
    if FriendsFrame.TitleBg then FriendsFrame.TitleBg:Hide() end
    -- Re-hide portrait/icon (may get re-shown by Blizzard code)
    if FriendsFrame.portrait then FriendsFrame.portrait:Hide() end
    if FriendsFrame.PortraitContainer then FriendsFrame.PortraitContainer:Hide() end
    if FriendsFramePortrait then FriendsFramePortrait:Hide() end
    if FriendsFrameIcon then FriendsFrameIcon:Hide() end
    if FriendsFrame.PortraitFrame then FriendsFrame.PortraitFrame:Hide() end
    if FriendsFrame.portraitIcon then FriendsFrame.portraitIcon:Hide() end
    -- Re-hide close button Blizzard textures, show EUI X
    local cb = FriendsFrame.CloseButton or _G["FriendsFrameCloseButton"]
    if cb then
        if cb._ebsBlizzTextures then
            for _, tex in ipairs(cb._ebsBlizzTextures) do tex:SetAlpha(0) end
        end
        if cb._ebsX then cb._ebsX:Show() end
    end

    -- Update colors
    local r, g, b, a = GetBorderColor(p)
    local borderAlpha = (p.showBorder ~= false) and a or 0
    PP.SetBorderColor(FriendsFrame, r, g, b, borderAlpha)
    if FriendsFrame._ebsBg then
        FriendsFrame._ebsBg:SetAlpha(p.bgAlpha)
    end
    if FriendsFrame._ebsTabBarBg then
        FriendsFrame._ebsTabBarBg:SetAlpha(p.bgAlpha)
    end
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            if tab._ebsBg then tab._ebsBg:Show() end
            -- Re-hide Blizzard tab textures (restored during disable)
            for _, child in ipairs({tab:GetRegions()}) do
                if child:IsObjectType("Texture")
                   and child ~= tab._ebsBg
                   and child ~= tab._ebsUnderline then
                    child:SetAlpha(0)
                end
            end
        end
    end

    -- Re-enable bottom buttons
    local function ReEnableButtons(parent)
        if not parent then return end
        for _, child in ipairs({parent:GetChildren()}) do
            if child._ebsBtnSkinned then
                if child._ebsBg then child._ebsBg:Show() end
                if child._ppBorders then PP.SetBorderColor(child, 1, 1, 1, 0.4) end
                -- Re-hide Blizzard textures
                for _, region in ipairs({child:GetRegions()}) do
                    if region:IsObjectType("Texture") and region ~= child._ebsBg then
                        region:SetAlpha(0)
                    end
                end
            end
            ReEnableButtons(child)
        end
    end
    ReEnableButtons(FriendsFrame)
    if FriendsListFrame then ReEnableButtons(FriendsListFrame) end

    -- Re-enable all scrollbars — hide Blizzard, show EUI tracks
    SkinScrollbar()

    -- Re-enable sub-tab styling
    local function ReEnableSubTabs(parent, depth)
        if depth > 3 or not parent then return end
        for _, child in ipairs({parent:GetChildren()}) do
            if child._ebsSubSkinned then
                -- Re-hide Blizzard textures
                for _, region in ipairs({child:GetRegions()}) do
                    if region:IsObjectType("Texture") and region ~= child._ebsUnderline then
                        region:SetAlpha(0)
                    end
                end
                for _, sub in ipairs({child:GetChildren()}) do
                    for _, tex in ipairs({sub:GetRegions()}) do
                        if tex:IsObjectType("Texture") then tex:SetAlpha(0) end
                    end
                end
            end
            -- Re-hide header frame textures
            if child:IsObjectType("Frame") and not child:IsObjectType("Button") then
                local cname = child:GetName() or ""
                if cname:lower():find("tab") or cname:lower():find("header") then
                    for _, region in ipairs({child:GetRegions()}) do
                        if region:IsObjectType("Texture") then region:SetAlpha(0) end
                    end
                end
            end
            ReEnableSubTabs(child, depth + 1)
        end
    end
    ReEnableSubTabs(FriendsFrame, 0)
    if FriendsListFrame then ReEnableSubTabs(FriendsListFrame, 0) end

    -- Re-enable Who frame styling
    local who = WhoFrame or _G["WhoFrame"]
    if who and who._ebsSkinned then
        -- Re-strip Who textures
        for _, region in ipairs({who:GetRegions()}) do
            if region:IsObjectType("Texture") then region:SetAlpha(0) end
        end
        if who.NineSlice then who.NineSlice:Hide() end
        if who.Inset then
            if who.Inset.NineSlice then who.Inset.NineSlice:Hide() end
            if who.Inset.Bg then who.Inset.Bg:Hide() end
            for _, region in ipairs({who.Inset:GetRegions()}) do
                if region:IsObjectType("Texture") then region:SetAlpha(0) end
            end
        end
        for _, child in ipairs({who:GetChildren()}) do
            if child:IsObjectType("Frame") and not child:IsObjectType("Button") then
                local cname = child:GetName() or ""
                if not cname:find("ScrollBox") and not cname:find("ScrollBar") then
                    for _, region in ipairs({child:GetRegions()}) do
                        if region:IsObjectType("Texture") then region:SetAlpha(0) end
                    end
                    if child.NineSlice then child.NineSlice:Hide() end
                end
            end
        end
        -- Re-show Who column dividers, re-strip column textures
        for i = 1, 6 do
            local col = _G["WhoFrameColumn_" .. i] or _G["WhoFrameColumnHeader" .. i]
            if col then
                if col._ebsDiv then col._ebsDiv:Show() end
                for _, region in ipairs({col:GetRegions()}) do
                    if region:IsObjectType("Texture") and region ~= col._ebsDiv then
                        region:SetAlpha(0)
                    end
                end
            end
        end
        -- Re-show edit box bg, re-strip textures
        local editBox = WhoFrameEditBox or _G["WhoFrameEditBox"]
        if editBox then
            if editBox._ebsBg then editBox._ebsBg:Show() end
            for _, region in ipairs({editBox:GetRegions()}) do
                if region:IsObjectType("Texture") and region ~= editBox._ebsBg then
                    region:SetAlpha(0)
                end
            end
        end
        -- Re-show Who row hovers, re-strip textures
        for i = 1, 22 do
            local btn = _G["WhoFrameButton" .. i]
            if btn then
                if btn._ebsHover then btn._ebsHover:Show() end
                for _, region in ipairs({btn:GetRegions()}) do
                    if region:IsObjectType("Texture") and region ~= btn._ebsHover then
                        region:SetAlpha(0)
                    end
                end
            end
        end
    end

    UpdateTabUnderlines()
    ProcessFriendButtons()
end

-------------------------------------------------------------------------------
--  Visibility
-------------------------------------------------------------------------------
local _ebsInCombat = false

-- Returns true = show, false = hide, "mouseover" = mouseover mode
local function EvalVisibility(cfg)
    if not cfg or not cfg.enabled then return false end
    if EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(cfg) then
        return false
    end
    local mode = cfg.visibility or "always"
    if mode == "mouseover" then return "mouseover" end
    if mode == "always" then return true end
    if mode == "never" then return false end
    if mode == "in_combat" then return _ebsInCombat end
    if mode == "out_of_combat" then return not _ebsInCombat end
    local inGroup = IsInGroup()
    local inRaid  = IsInRaid()
    if mode == "in_raid"  then return inRaid end
    if mode == "in_party" then return inGroup and not inRaid end
    if mode == "solo"     then return not inGroup end
    return true
end

-- Mouseover poll: single lightweight frame, only runs when needed
-- Cached state avoids redundant SetAlpha calls; only fires API on change
local mouseoverTargets = {}  -- { { frame=, visible= }, ... }
local mouseoverPoll = CreateFrame("Frame")
mouseoverPoll:Hide()
local moElapsed = 0
mouseoverPoll:SetScript("OnUpdate", function(_, dt)
    moElapsed = moElapsed + dt
    if moElapsed < 0.15 then return end
    moElapsed = 0
    for i = 1, #mouseoverTargets do
        local t = mouseoverTargets[i]
        local frame = t.frame
        if frame and frame:IsShown() then
            local over = frame:IsMouseOver()
            if over and not t.visible then
                t.visible = true
                frame:SetAlpha(1)
            elseif not over and t.visible then
                t.visible = false
                frame:SetAlpha(0)
            end
        end
    end
end)

local function RebuildMouseoverTargets()
    wipe(mouseoverTargets)
    if not EBS.db then return end
    local prof = EBS.db.profile
    -- Chat: use first skinned chat frame as hover anchor, apply alpha to all
    if prof.chat and prof.chat.enabled and prof.chat.visibility == "mouseover" then
        for chatFrame in pairs(skinnedChatFrames) do
            mouseoverTargets[#mouseoverTargets + 1] = { frame = chatFrame }
        end
    end
    -- Minimap
    if prof.minimap and prof.minimap.enabled and prof.minimap.visibility == "mouseover" then
        if Minimap then
            mouseoverTargets[#mouseoverTargets + 1] = { frame = Minimap }
        end
    end
    -- Friends
    if prof.friends and prof.friends.enabled and prof.friends.visibility == "mouseover" then
        if FriendsFrame then
            mouseoverTargets[#mouseoverTargets + 1] = { frame = FriendsFrame }
        end
    end
    if #mouseoverTargets > 0 then
        mouseoverPoll:Show()
    else
        mouseoverPoll:Hide()
    end
end

local function UpdateChatVisibility()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.chat
    if not p or not p.enabled then return end
    local vis = EvalVisibility(p)
    if vis == "mouseover" then
        -- Start hidden; poll will handle show on hover
        for chatFrame in pairs(skinnedChatFrames) do
            chatFrame:SetAlpha(0)
        end
    else
        for chatFrame in pairs(skinnedChatFrames) do
            chatFrame:SetAlpha(vis and 1 or 0)
        end
    end
end

local function UpdateMinimapVisibility()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if not p or not p.enabled then return end
    local vis = EvalVisibility(p)
    local minimap = Minimap
    if not minimap then return end
    if vis == "mouseover" then
        minimap:SetAlpha(0)
        minimap:Show()
    elseif vis then
        minimap:SetAlpha(1)
        minimap:Show()
    else
        minimap:Hide()
    end
end

local function UpdateFriendsVisibility()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not p or not p.enabled then return end
    if not FriendsFrame or not FriendsFrame:IsShown() then return end
    local vis = EvalVisibility(p)
    if vis == "mouseover" then
        FriendsFrame:SetAlpha(0)
    else
        FriendsFrame:SetAlpha(vis and 1 or 0)
    end
end

local function UpdateAllVisibility()
    UpdateChatVisibility()
    UpdateMinimapVisibility()
    UpdateFriendsVisibility()
    if _G._EBS_UpdateQTVisibility then _G._EBS_UpdateQTVisibility() end
    if _G._ECL_UpdateVisibility then _G._ECL_UpdateVisibility() end
    RebuildMouseoverTargets()
end

-- Expose globals for options/quest tracker/cursor
_G._EBS_InCombat = function() return _ebsInCombat end
_G._EBS_UpdateVisibility = UpdateAllVisibility
_G._EBS_EvalVisibility = EvalVisibility

local visFrame = CreateFrame("Frame")
visFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
visFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
visFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
visFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
visFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
visFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
visFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
visFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        _ebsInCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        _ebsInCombat = false
    end
    C_Timer.After(0, UpdateAllVisibility)
end)

-------------------------------------------------------------------------------
--  Apply All
-------------------------------------------------------------------------------
ApplyAll = function()
    ApplyChat()
    ApplyMinimap()
    ApplyFriends()
    C_Timer.After(0, UpdateAllVisibility)
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function EBS:OnInitialize()
    EBS.db = EllesmereUI.Lite.NewDB("EllesmereUIBasicsDB", defaults)

    -- Global bridge for options ↔ main communication
    _G._EBS_AceDB        = EBS.db
    _G._EBS_ApplyAll     = ApplyAll
    _G._EBS_ApplyChat    = ApplyChat
    _G._EBS_ApplyMinimap = ApplyMinimap
    _G._EBS_ApplyFriends = ApplyFriends
    _G._EBS_ProcessFriendButtons = ProcessFriendButtons
end

function EBS:OnEnable()
    ApplyAll()

    -- Hook FriendsFrame for load-on-demand
    if not FriendsFrame then
        local hookFrame = CreateFrame("Frame")
        hookFrame:RegisterEvent("ADDON_LOADED")
        hookFrame:SetScript("OnEvent", function(self, event, addon)
            if addon == "Blizzard_SocialUI" then
                C_Timer.After(0.1, function()
                    if FriendsFrame and EBS.db.profile.friends.enabled then
                        SkinFriendsFrame()
                    end
                end)
            end
        end)

        -- Also hook ShowUIPanel as a fallback
        if ShowUIPanel then
            hooksecurefunc("ShowUIPanel", function(frame)
                if frame == FriendsFrame and not friendsSkinned then
                    C_Timer.After(0, function()
                        if EBS.db.profile.friends.enabled then
                            SkinFriendsFrame()
                        end
                    end)
                end
            end)
        end
    else
        if EBS.db.profile.friends.enabled then
            SkinFriendsFrame()
        end
    end
end
