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

-- Resolve class file token from a friend button's data
local function GetFriendClassFile(button)
    if not button or not button.buttonType or not button.id then return nil end
    BuildClassNameLookup()

    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo(button.id)
        if info and info.gameAccountInfo then
            local gi = info.gameAccountInfo
            if gi.classID and gi.classID > 0 then
                local _, classFile = GetClassInfo(gi.classID)
                return classFile
            end
            if gi.className then
                return classFileByLocalName[gi.className]
            end
        end
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex(button.id)
        if info and info.className then
            return classFileByLocalName[info.className]
        end
    end
    return nil
end

-- Get unique key for a friend (used by group assignments)
local function GetFriendKey(button)
    if not button or not button.buttonType or not button.id then return nil end
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo(button.id)
        if info then return "bnet-" .. (info.bnetAccountID or button.id) end
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex(button.id)
        if info and info.name then return "wow-" .. info.name end
    end
    return nil
end

-- Is the friend currently online?
local function IsFriendOnline(button)
    if not button or not button.buttonType or not button.id then return false end
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo(button.id)
        return info and info.gameAccountInfo and info.gameAccountInfo.isOnline
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex(button.id)
        return info and info.connected
    end
    return false
end

-- Get the friend's display name (for group management UI)
local function GetFriendDisplayName(button)
    if not button or not button.buttonType or not button.id then return nil end
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo(button.id)
        if info then return info.accountName end
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex(button.id)
        if info then return info.name end
    end
    return nil
end

-- Apply class icon to a friend button
local function UpdateClassIcon(button)
    local p = EBS.db.profile.friends
    if not p.showClassIcons then
        if button._ebsClassIcon then button._ebsClassIcon:Hide() end
        return
    end

    local classFile = GetFriendClassFile(button)
    if not classFile then
        if button._ebsClassIcon then button._ebsClassIcon:Hide() end
        return
    end

    -- Create icon texture if needed
    if not button._ebsClassIcon then
        button._ebsClassIcon = button:CreateTexture(nil, "OVERLAY", nil, 2)
        button._ebsClassIcon:SetSize(16, 16)
    end
    local icon = button._ebsClassIcon
    local style = p.iconStyle or "blizzard"

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

    -- Position to the left of name text
    icon:ClearAllPoints()
    local nameText = button.name or button.Name
    if nameText then
        icon:SetPoint("RIGHT", nameText, "LEFT", -4, 0)
    else
        icon:SetPoint("LEFT", button, "LEFT", 8, 0)
    end

    -- Desaturate for offline
    local online = IsFriendOnline(button)
    icon:SetDesaturated(not online)
    icon:SetAlpha(online and 1 or 0.5)
    icon:Show()
end

-- Apply group tag to a friend button
local function UpdateGroupTag(button)
    local p = EBS.db.profile.friends
    if not p.groupsEnabled then
        if button._ebsGroupTag then button._ebsGroupTag:Hide() end
        return
    end

    local key = GetFriendKey(button)
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
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    tag:SetTextColor(ar, ag, ab, 0.7)
    tag:SetText(groupName)
    tag:Show()
end

-- Update accent underline on active tab
local function UpdateTabUnderlines()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not p or not p.enabled or not p.useAccentTab then return end
    local selected = PanelTemplates_GetSelectedTab and
                     PanelTemplates_GetSelectedTab(FriendsFrame) or 1
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab and tab._ebsUnderline then
            tab._ebsUnderline:SetShown(i == selected)
        end
    end
end

-- Skin a single friend button (row bg + hover)
local function SkinFriendButton(button)
    if button._ebsSkinned then return end
    button._ebsSkinned = true

    -- Row background
    if not button._ebsRowBg then
        button._ebsRowBg = button:CreateTexture(nil, "BACKGROUND", nil, -6)
        button._ebsRowBg:SetAllPoints()
    end

    -- Hover highlight
    if not button._ebsHover then
        button._ebsHover = button:CreateTexture(nil, "HIGHLIGHT")
        button._ebsHover:SetAllPoints()
        button._ebsHover:SetColorTexture(1, 1, 1, 0.05)
        button._ebsHover:SetBlendMode("ADD")
    end
end

-- Apply alternating row colors to visible buttons
local function UpdateRowColors()
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if not scrollBox then return end
    local idx = 0
    for _, button in scrollBox:EnumerateFrames() do
        if button._ebsRowBg then
            local alpha = (idx % 2 == 0) and 0.03 or 0.06
            button._ebsRowBg:SetColorTexture(1, 1, 1, alpha)
        end
        idx = idx + 1
    end
end

-- Process all visible friend buttons
local function ProcessFriendButtons()
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if not scrollBox then return end
    for _, button in scrollBox:EnumerateFrames() do
        SkinFriendButton(button)
        UpdateClassIcon(button)
        UpdateGroupTag(button)
    end
    UpdateRowColors()
end

-- Skin the scrollbar
local function SkinScrollbar()
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if not scrollBox then return end
    local scrollBar = scrollBox.ScrollBar or (FriendsListFrame and FriendsListFrame.ScrollBar)
    if not scrollBar then return end

    -- Hide Blizzard scrollbar chrome
    if scrollBar.Background then scrollBar.Background:Hide() end
    if scrollBar.Track then
        if scrollBar.Track.Begin then scrollBar.Track.Begin:Hide() end
        if scrollBar.Track.End then scrollBar.Track.End:Hide() end
        if scrollBar.Track.Middle then
            scrollBar.Track.Middle:SetColorTexture(0.08, 0.08, 0.08, 0.5)
        end
    end

    -- Skin thumb
    local thumb = scrollBar.Thumb or (scrollBar.Track and scrollBar.Track.Thumb)
    if thumb then
        if thumb.Begin then thumb.Begin:Hide() end
        if thumb.End then thumb.End:Hide() end
        if thumb.Middle then
            thumb.Middle:SetColorTexture(0.3, 0.3, 0.3, 0.6)
        end
    end
end

-- Skin bottom-area buttons (AddFriend, etc.)
local function SkinBottomButton(btn, r, g, b, a)
    if not btn or btn._ebsBtnSkinned then return end
    btn._ebsBtnSkinned = true

    -- Strip default art from BORDER/BACKGROUND layers
    for _, child in ipairs({btn:GetRegions()}) do
        if child:IsObjectType("Texture") then
            local layer = child:GetDrawLayer()
            if layer == "BORDER" or layer == "BACKGROUND" then
                child:SetAlpha(0)
            end
        end
    end

    -- Dark background
    if not btn._ebsBg then
        btn._ebsBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
        btn._ebsBg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
        btn._ebsBg:SetAllPoints()
    end
    PP.CreateBorder(btn, r, g, b, a, 1, "OVERLAY", 7)
end

-- Build the friends-list right-click group menu
local function BuildGroupContextMenu(button)
    local p = EBS.db.profile.friends
    if not p.groupsEnabled then return end

    local key = GetFriendKey(button)
    if not key then return end
    local currentGroup = p.assignments[key]

    local menuFrame = _G["EBS_FriendGroupMenu"]
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "EBS_FriendGroupMenu", UIParent, "UIDropDownMenuTemplate")
    end

    local function OnClick(self, groupName)
        local fp = EBS.db.profile.friends
        if groupName then
            fp.assignments[key] = groupName
        else
            fp.assignments[key] = nil
        end
        CloseDropDownMenus()
        ProcessFriendButtons()
    end

    local function Init(self, level)
        if not level then return end
        local info = UIDropDownMenu_CreateInfo()
        if level == 1 then
            info.text = "Set Group"
            info.isTitle = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)

            for _, group in ipairs(p.groups) do
                info = UIDropDownMenu_CreateInfo()
                info.text = group.name
                info.checked = (currentGroup == group.name)
                info.func = OnClick
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
            info.disabled = (currentGroup == nil)
            info.func = OnClick
            info.arg1 = nil
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(menuFrame, Init, "MENU")
    ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end

-- Hook friend button right-click for group menu
local function HookFriendButtonClicks()
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if not scrollBox then return end

    hooksecurefunc(scrollBox, "Update", function(self)
        for _, button in self:EnumerateFrames() do
            if not button._ebsClickHooked then
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
    end)
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

    -- Portrait
    if frame.portrait then frame.portrait:SetAlpha(0) end
    if frame.PortraitContainer then frame.PortraitContainer:SetAlpha(0) end
    if FriendsFramePortrait then FriendsFramePortrait:SetAlpha(0) end

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

    -- ── Dark background ────────────────────────────────────────────────
    frame._ebsBg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    frame._ebsBg:SetColorTexture(0, 0, 0)
    frame._ebsBg:SetAllPoints()
    frame._ebsBg:SetAlpha(p.bgAlpha)

    -- ── Pixel border on frame ──────────────────────────────────────────
    local r, g, b, a = GetBorderColor(p)
    PP.CreateBorder(frame, r, g, b, a, 1, "OVERLAY", 7)

    -- ── Skin tabs ──────────────────────────────────────────────────────
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            -- Hide all Blizzard tab textures
            for _, child in ipairs({tab:GetRegions()}) do
                if child:IsObjectType("Texture") then
                    child:SetAlpha(0)
                end
            end

            -- Dark tab background
            tab._ebsBg = tab:CreateTexture(nil, "BACKGROUND", nil, -6)
            tab._ebsBg:SetColorTexture(0, 0, 0, 0.8)
            tab._ebsBg:SetPoint("TOPLEFT", 2, -2)
            tab._ebsBg:SetPoint("BOTTOMRIGHT", -2, 2)

            -- Tab border
            PP.CreateBorder(tab, r, g, b, a, 1, "OVERLAY", 7)

            -- Accent underline (only active tab)
            if p.useAccentTab then
                local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
                underline:SetHeight(2)
                underline:SetPoint("BOTTOMLEFT", 2, 0)
                underline:SetPoint("BOTTOMRIGHT", -2, 0)
                local ar, ag, ab = EllesmereUI.GetAccentColor()
                underline:SetColorTexture(ar, ag, ab, 1)
                tab._ebsUnderline = underline
                EllesmereUI.RegAccent({ type = "solid", obj = underline, a = 1 })
                underline:Hide()
            end
        end
    end

    -- Hook tab switching
    if PanelTemplates_SetTab then
        hooksecurefunc("PanelTemplates_SetTab", function(f)
            if f == FriendsFrame then UpdateTabUnderlines() end
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
            UpdateClassIcon(button)
            UpdateGroupTag(button)
        end)
    end

    -- Hook scroll updates for row alternation
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if scrollBox then
        hooksecurefunc(scrollBox, "Update", function()
            if not EBS.db or not EBS.db.profile.friends.enabled then return end
            UpdateRowColors()
        end)
    end

    -- Hook right-click for group assignment menu
    HookFriendButtonClicks()

    -- ── Skin bottom buttons ────────────────────────────────────────────
    for _, btn in ipairs({ AddFriendButton, FriendsFrameSendMessageButton }) do
        SkinBottomButton(btn, r, g, b, a)
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
            if FriendsFrame.portrait then FriendsFrame.portrait:SetAlpha(1) end
            if FriendsFrame.PortraitContainer then FriendsFrame.PortraitContainer:SetAlpha(1) end
            for i = 1, 4 do
                local tab = _G["FriendsFrameTab" .. i]
                if tab then
                    if tab._ppBorders then PP.SetBorderColor(tab, 0, 0, 0, 0) end
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

    -- Update colors
    local r, g, b, a = GetBorderColor(p)
    PP.SetBorderColor(FriendsFrame, r, g, b, a)
    if FriendsFrame._ebsBg then
        FriendsFrame._ebsBg:SetAlpha(p.bgAlpha)
    end
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            if tab._ppBorders then PP.SetBorderColor(tab, r, g, b, a) end
            if tab._ebsBg then tab._ebsBg:Show() end
        end
    end

    -- Update bottom buttons
    for _, btn in ipairs({ AddFriendButton, FriendsFrameSendMessageButton }) do
        if btn and btn._ppBorders then PP.SetBorderColor(btn, r, g, b, a) end
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
    _G._EBS_GetFriendKey = GetFriendKey
    _G._EBS_GetFriendDisplayName = GetFriendDisplayName
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
        SkinFriendsFrame()
    end
end
