-------------------------------------------------------------------------------
--  EllesmereUIFriends.lua
--  Friends List skin for EllesmereUI. Direct skin of Blizzard's native
--  ScrollBox and buttons -- no custom DataProvider, no friend groups.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local EBS = EllesmereUI.Lite.NewAddon("EllesmereUIFriends")

local PP = EllesmereUI.PP

local EG = EllesmereUI.ELLESMERE_GREEN

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-- Modules temporarily disabled for public release (Coming Soon).
-- Force-overrides the per-module "enabled" flag so these do absolutely nothing
-- regardless of what users have in their SavedVariables.
local TEMP_DISABLED = {
    -- minimap = true,
    -- questTracker = true,
    -- cursor  = true,
}
_G._EBS_TEMP_DISABLED = TEMP_DISABLED

local defaults = {
    profile = {
        friends = {
            enabled        = true,
            scale          = 1,
            position       = nil,
            bgR            = 0.05, bgG = 0.05, bgB = 0.055, bgAlpha = 1,
            tileR          = 0,     tileG = 0,    tileB = 0,    tileAlpha = 0.35,
            showBorder     = true,
            borderSize     = 1,
            borderR        = 0, borderG = 0, borderB = 0, borderA = 1,
            useClassColor  = false,
            useAccentTab   = true,
            showClassIcons = true,
            iconStyle      = "modern",
            classColorNames = true,
            nameColorR      = 0.863, nameColorG = 0.820, nameColorB = 0.565,
            accentColors   = true,
            factionBanners = false,
            showRegionIcons = true,
            autoAcceptFriendInvites = false,
            autoAcceptGuildInvites = false,
            showOffline    = true,
            visibility     = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
    },
}

-------------------------------------------------------------------------------
--  Utility
-------------------------------------------------------------------------------
local function GetBorderColor(cfg)
    if cfg.useClassColor then
        return EG.r, EG.g, EG.b, 1
    end
    return cfg.borderR, cfg.borderG, cfg.borderB, cfg.borderA or 1
end

-- 12.1 replaces the friends window wholesale with the Social UI. The legacy
-- FriendsFrame still loads there but is never what the player sees, and
-- skinning it is not free: this module re-anchors Blizzard scroll boxes and
-- SetScripts their mouse wheel, which is a documented way to taint Battle.net
-- whisper handling (SetTellTarget on a secret target). Running a full skin over
-- a window nobody looks at is all cost and no benefit, so on a client serving
-- the Social UI the entire legacy skin stays off and EUI_Friends_Groups_121.lua
-- owns that window instead.
--
-- Resolved live rather than at load: the Social UI is behind a server-side
-- switch that can flip mid-session. On 12.0 IS_121 is false, so this is always
-- false and nothing about live behaviour changes.
local function LegacyFriendsRetired()
    if not (EllesmereUI and EllesmereUI.IS_121) then return false end
    if not (C_SocialUI and C_SocialUI.IsSystemEnabled) then return false end
    local ok, enabled = pcall(C_SocialUI.IsSystemEnabled)
    return ok and enabled == true
end

-------------------------------------------------------------------------------
--  Combat safety
-------------------------------------------------------------------------------
local pendingApply = false
local ApplyAll  -- forward declaration

local combatFrame = CreateFrame("Frame")
combatFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if pendingApply then
        pendingApply = false
        ApplyAll()
    end
end)

-- The regen listener is armed only while an apply is actually pending, so the
-- frame costs nothing across ordinary combat.
local function QueueApplyAll()
    if pendingApply then return end
    pendingApply = true
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Hide all textures on a frame (used by one-time skinning passes)
local function StripTextures(f)
    if not f then return end
    for i = 1, select("#", f:GetRegions()) do
        local region = select(i, f:GetRegions())
        if region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
end

-------------------------------------------------------------------------------
--  Raid Tab Skinning
-------------------------------------------------------------------------------
-- Taint-safe raid tab skinning: NEVER CreateTexture, CreateFrame, or
-- PP.CreateBorder on any frame in the RaidFrame tree. These permanently
-- taint the frame, breaking ClaimRaidFrame -> RaidFrame:SetParent().
-- Safe operations: SetTexture(""), font/color on FontStrings, HookScript,
-- BackdropTemplateMixin.

local function SkinRaidRoleIcon(icon)
    -- No-op: CreateTexture on protected parent taints
end

local function SkinRaidRoleCount(frame)
    if not frame or GetFFD(frame).skinned then return end
    GetFFD(frame).skinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region:IsObjectType("FontString") then
            region:SetFont(fontPath, 10, "")
            region:SetTextColor(1, 1, 1, 0.8)
        end
    end
end

local function SkinRaidTabButton(btn)
    if not btn or GetFFD(btn).btnSkinned then return end
    GetFFD(btn).btnSkinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    for i = 1, select("#", btn:GetRegions()) do
        local region = select(i, btn:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
            region:SetAlpha(0)
        end
    end
    if btn.SetNormalTexture then btn:SetNormalTexture("") end
    if btn.SetPushedTexture then btn:SetPushedTexture("") end
    if btn.SetHighlightTexture then btn:SetHighlightTexture("") end
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt then nt:SetTexture(""); nt:SetAlpha(0) end
    local pt = btn.GetPushedTexture and btn:GetPushedTexture()
    if pt then pt:SetTexture(""); pt:SetAlpha(0) end
    local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if ht then ht:SetTexture(""); ht:SetAlpha(0) end
    local dt = btn.GetDisabledTexture and btn:GetDisabledTexture()
    if dt then dt:SetTexture(""); dt:SetAlpha(0) end
    -- Left/Middle/Right chrome (UIPanelButtonTemplate)
    if btn.Left then btn.Left:SetAlpha(0) end
    if btn.Right then btn.Right:SetAlpha(0) end
    if btn.Middle then btn.Middle:SetAlpha(0) end
    if BackdropTemplateMixin then
        Mixin(btn, BackdropTemplateMixin)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.025, 0.035, 0.045, 0.92)
        btn:SetBackdropBorderColor(1, 1, 1, 0.4)
    end
    local text = btn:GetFontString()
    if text then
        text:SetFont(fontPath, 9, "")
        text:SetTextColor(1, 1, 1, 0.5)
        text:ClearAllPoints()
        text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    end
    btn:HookScript("OnEnter", function()
        local r, g, b, a1, a2 = 1, 1, 1, 0.7, 0.6
        if GetFFD(btn).accent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 1, 0.8
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(r, g, b, a2) end
    end)
    btn:HookScript("OnLeave", function()
        local r, g, b, a1, a2 = 1, 1, 1, 0.5, 0.4
        if GetFFD(btn).accent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 0.7, 0.5
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(r, g, b, a2) end
    end)
end

local RAID_TAB_BUTTONS = {
    "RaidFrameConvertToRaidButton",
    "RaidFrameRaidInfoButton",
    "QuickJoinFrame.JoinQueueButton",
}

local function SkinCheckbox(checkbox)
    if not checkbox or GetFFD(checkbox).skinned then return end
    GetFFD(checkbox).skinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    if checkbox.SetNormalTexture then checkbox:SetNormalTexture("") end
    if checkbox.SetPushedTexture then checkbox:SetPushedTexture("") end
    if checkbox.SetHighlightTexture then checkbox:SetHighlightTexture("") end
    if checkbox.SetDisabledTexture then checkbox:SetDisabledTexture("") end
    for i = 1, select("#", checkbox:GetRegions()) do
        local region = select(i, checkbox:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
        end
    end
    local text = checkbox.Text or checkbox.text or (checkbox.GetName and _G[checkbox:GetName().."Text"])
    if text and text.SetFont then
        text:SetFont(fontPath, 10, "")
        text:SetTextColor(1, 1, 1, 0.8)
    end
end

local function SkinRaidGroup(group)
    if not group or GetFFD(group).skinned then return end
    GetFFD(group).skinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    local ar, ag, ab = EG.r, EG.g, EG.b
    local groupName = group:GetName()
    for i = 1, select("#", group:GetRegions()) do
        local region = select(i, group:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
        end
    end
    if BackdropTemplateMixin then
        Mixin(group, BackdropTemplateMixin)
        group:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        group:SetBackdropColor(0.025, 0.025, 0.03, 0.98)
        group:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
    end
    local labelFrame = _G[groupName .. "Label"]
    if labelFrame then
        for i = 1, select("#", labelFrame:GetRegions()) do
            local region = select(i, labelFrame:GetRegions())
            if region and region:IsObjectType("FontString") then
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(region, true) end
                region:SetFont(fontPath, 10, "")
                region:SetTextColor(ar, ag, ab, 1)
            end
        end
        local fontString = labelFrame.GetFontString and labelFrame:GetFontString()
        if fontString and fontString.SetFont then
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fontString, true) end
            fontString:SetFont(fontPath, 10, "")
            fontString:SetTextColor(ar, ag, ab, 1)
        end
    end
end

local function SkinRaidSlot(slot)
    if not slot or GetFFD(slot).skinned then return end
    GetFFD(slot).skinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    for i = 1, select("#", slot:GetRegions()) do
        local region = select(i, slot:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
        end
    end
    if BackdropTemplateMixin then
        Mixin(slot, BackdropTemplateMixin)
        slot:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        slot:SetBackdropColor(0.045, 0.045, 0.05, 0.9)
        slot:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.7)
    end
    for i = 1, select("#", slot:GetRegions()) do
        local region = select(i, slot:GetRegions())
        if region and region:IsObjectType("FontString") then
            region:SetFont(fontPath, 9, "")
        end
    end
    slot:HookScript("OnEnter", function()
        if slot.SetBackdropColor then slot:SetBackdropColor(0.07, 0.07, 0.08, 0.95) end
    end)
    slot:HookScript("OnLeave", function()
        if slot.SetBackdropColor then slot:SetBackdropColor(0.045, 0.045, 0.05, 0.9) end
    end)
end

local function SkinRaidGroupButton(btn)
    if not btn or GetFFD(btn).skinned then return end
    GetFFD(btn).skinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
    for i = 1, select("#", btn:GetRegions()) do
        local region = select(i, btn:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetTexture("")
        end
    end
    if BackdropTemplateMixin then
        Mixin(btn, BackdropTemplateMixin)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
    end
    for i = 1, select("#", btn:GetRegions()) do
        local region = select(i, btn:GetRegions())
        if region and region:IsObjectType("FontString") then
            region:SetFont(fontPath, 9, "")
        end
    end
    btn:HookScript("OnEnter", function()
        if btn.SetBackdropColor then btn:SetBackdropColor(0.1, 0.1, 0.12, 1) end
    end)
    btn:HookScript("OnLeave", function()
        if btn.SetBackdropColor then btn:SetBackdropColor(0.06, 0.06, 0.07, 0.95) end
    end)
end

local function SkinRaidInfoFrame()
    -- Intentionally left unstyled (Blizzard default)
end

local function SkinRaidTab()

    for _, name in ipairs(RAID_TAB_BUTTONS) do
        local btn
        if name:find("%.") then
            local parts = {strsplit(".", name)}
            btn = _G[parts[1]]
            for i = 2, #parts do
                if btn then btn = btn[parts[i]] end
            end
        else
            btn = _G[name]
        end
        if btn then SkinRaidTabButton(btn) end
    end
    for i = 1, 40 do
        local playerBtn = _G["RaidGroupButton" .. i]
        if playerBtn then SkinRaidGroupButton(playerBtn) end
    end
    for i = 1, 8 do
        local groupFrame = _G["RaidGroup" .. i]
        if groupFrame then
            SkinRaidGroup(groupFrame)
            for j = 1, 5 do
                local slot = _G["RaidGroup" .. i .. "Slot" .. j]
                if slot then SkinRaidSlot(slot) end
            end
        end
    end
    local raidFrame = _G.RaidFrame
    if raidFrame then
        for i = 1, select("#", raidFrame:GetChildren()) do
            local child = select(i, raidFrame:GetChildren())
            if child then
                for j = 1, select("#", child:GetRegions()) do
                    local region = select(j, child:GetRegions())
                    if region and region:IsObjectType("Texture") then
                        local tex = region:GetTexture()
                        if tex and type(tex) == "string" then
                            local texLower = tex:lower()
                            if texLower:find("role") or texLower:find("tank") or
                               texLower:find("healer") or texLower:find("dps") or
                               texLower:find("damager") then
                                SkinRaidRoleIcon(region)
                            end
                        end
                    end
                end
            end
        end
    end
    SkinRaidInfoFrame()

    if raidFrame and not GetFFD(raidFrame).borderAdded then
        GetFFD(raidFrame).borderAdded = true
        if BackdropTemplateMixin then
            Mixin(raidFrame, BackdropTemplateMixin)
            raidFrame:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            raidFrame:SetBackdropBorderColor(1, 1, 1, 0.1)
        end
    end

    local inMplus2 = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
    local _, iType2 = IsInInstance()
    local inPvP2 = (iType2 == "pvp" or iType2 == "arena")
    if InCombatLockdown() or inMplus2 or inPvP2 then return end

    if raidFrame then
        raidFrame:ClearAllPoints()
        raidFrame:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", 15, -76)
        raidFrame:SetPoint("BOTTOMRIGHT", FriendsFrame, "BOTTOMRIGHT", -15, 35)
    end

    local convertBtn = _G.RaidFrameConvertToRaidButton
    local raidInfoBtn = _G.RaidFrameRaidInfoButton
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if scrollBox and (convertBtn or raidInfoBtn) then
        local btnW = math.floor(raidFrame:GetWidth() / 3)
        if convertBtn then
            convertBtn:ClearAllPoints()
            convertBtn:SetSize(btnW, 22)
            convertBtn:SetPoint("BOTTOMRIGHT", scrollBox, "BOTTOMRIGHT", 0, -22)
        end
        if raidInfoBtn then
            raidInfoBtn:ClearAllPoints()
            raidInfoBtn:SetSize(btnW, 20)
            raidInfoBtn:SetPoint("TOPRIGHT", scrollBox, "TOPRIGHT", 0, 48)
        end
    end

    local checkBtn = _G.RaidFrameAllAssistCheckButton
    if checkBtn and not GetFFD(checkBtn).shifted then
        GetFFD(checkBtn).shifted = true
        local p1, rel, p2, ox, oy = checkBtn:GetPoint(1)
        if p1 then checkBtn:SetPoint(p1, rel, p2, (ox or 0) - 62, (oy or 0) + 59) end
    end
    if raidFrame then
        local roleCount = raidFrame.RoleCount
        if roleCount and not GetFFD(roleCount).shifted then
            GetFFD(roleCount).shifted = true
            local p1, rel, p2, ox, oy = roleCount:GetPoint(1)
            if p1 then roleCount:SetPoint(p1, rel, p2, (ox or 0) - 62, (oy or 0) + 59) end
        end
    end

    if raidFrame then
        local groupW = math.floor((raidFrame:GetWidth() - 10) / 2)
        for i = 1, 8 do
            local gf = _G["RaidGroup" .. i]
            if gf then
                gf:ClearAllPoints()
                gf:SetWidth(groupW)
                for j = 1, 5 do
                    local slot = _G["RaidGroup" .. i .. "Slot" .. j]
                    if slot then slot:SetWidth(groupW - 6) end
                end
                if i == 1 then
                    gf:SetPoint("TOPLEFT", raidFrame, "TOPLEFT", 0, 0)
                elseif i == 2 then
                    gf:SetPoint("TOPRIGHT", raidFrame, "TOPRIGHT", 0, 0)
                elseif i % 2 == 1 then
                    local above = _G["RaidGroup" .. (i - 2)]
                    if above then gf:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -14) end
                else
                    local above = _G["RaidGroup" .. (i - 2)]
                    if above then gf:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -14) end
                end
            end
        end
        for i = 1, 40 do
            local btn = _G["RaidGroupButton" .. i]
            if btn then btn:SetWidth(groupW - 6) end
        end
    end
end

local function UpdateRaidTabButtonAccent()
    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not fp then return end
    local useAccent = fp.accentColors ~= false
    for _, name in ipairs(RAID_TAB_BUTTONS) do
        local btn
        if name:find("%.") then
            local parts = {strsplit(".", name)}
            btn = _G[parts[1]]
            for i = 2, #parts do
                if btn then btn = btn[parts[i]] end
            end
        else
            btn = _G[name]
        end
        if btn and GetFFD(btn).btnSkinned then
            local text = btn:GetFontString()
            GetFFD(btn).accent = useAccent
            if useAccent then
                if text then text:SetTextColor(EG.r, EG.g, EG.b, 0.7) end
                if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(EG.r, EG.g, EG.b, 0.5) end
            else
                if text then text:SetTextColor(1, 1, 1, 0.5) end
                if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(1, 1, 1, 0.4) end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Friends List Skin
-------------------------------------------------------------------------------
local friendsSkinned = false

local CLASS_ICON_SPRITE_BASE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"

-- Sprite texture paths keyed by style name
local CLASS_ICON_SPRITE_TEX = {}
for _, style in ipairs({"modern", "dark", "light", "clean"}) do
    CLASS_ICON_SPRITE_TEX[style] = CLASS_ICON_SPRITE_BASE .. style .. ".tga"
end
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

-- Localized class name -> class file token (built once on first use)
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

-- Friend data cache: populated on events, read per-button in the hook.
-- BNet friends keyed by [id], WoW friends keyed by [id + 10000].
local _friendCache = {}
local _FC_WOW_OFFSET = 10000

local function GetCachedFriendInfo(button)
    if not button or not button.buttonType or not button.id then return nil, nil end
    local key
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        key = button.id
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        key = button.id + _FC_WOW_OFFSET
    end
    if not key then return nil, nil end
    local cached = _friendCache[key]
    if cached then
        if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
            return cached, nil
        else
            return nil, cached
        end
    end
    -- Cache miss fallback (should not happen during normal scroll)
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo(button.id)
        if info then _friendCache[button.id] = info end
        return info, nil
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local info = C_FriendList and C_FriendList.GetFriendInfoByIndex(button.id)
        if info then _friendCache[button.id + _FC_WOW_OFFSET] = info end
        return nil, info
    end
    return nil, nil
end

-- Populate cache from APIs (called on events while frame is shown)
local function RefreshFriendCache()
    wipe(_friendCache)
    local numBNet = BNGetNumFriends and BNGetNumFriends() or 0
    for i = 1, numBNet do
        local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo(i)
        if info then _friendCache[i] = info end
    end
    local numWoW = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
    for i = 1, numWoW do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info then _friendCache[i + _FC_WOW_OFFSET] = info end
    end
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

-- Group tag stored in Blizzard friend notes as ||EUI:GroupName||
-- Kept for display only: strips legacy tags so notes render cleanly.
local EUI_NOTE_TAG = "||EUI:"
local EUI_NOTE_END = "||"

local function ParseGroupFromNote(note)
    if not note or note == "" then return nil, note end
    local tagStart = note:find(EUI_NOTE_TAG, 1, true)
    if not tagStart then return nil, note end
    local groupStart = tagStart + #EUI_NOTE_TAG
    local tagEnd = note:find(EUI_NOTE_END, groupStart, true)
    if not tagEnd then return nil, note end
    local group = note:sub(groupStart, tagEnd - 1)
    local clean = note:sub(1, tagStart - 1)
    clean = clean:match("^(.-)%s*$") or clean
    if group == "" then return nil, clean end
    return group, clean
end

-- Offline icon path (displayed when friend is not online)
local OFFLINE_ICON = "Interface\\AddOns\\EllesmereUIFriends\\Media\\offline.png"

-- Region display names for friend region tooltips
local MINI_DISPLAY = {
    namerica = "North America", samerica = "South America",
    australia = "Australia", europe = "Europe",
    russia = "Russia", korea = "Korea",
    taiwan = "Taiwan", china = "China",
}

-- Status orb atlas (online/away/dnd indicator on friend buttons)
local _orbFile, _orbL, _orbR, _orbT, _orbB
do
    local orbInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("lootroll-animreveal-a")
    if orbInfo and orbInfo.file then
        _orbFile = orbInfo.file
        local aL = orbInfo.leftTexCoord or 0
        local aR = orbInfo.rightTexCoord or 1
        local aT = orbInfo.topTexCoord or 0
        local aB = orbInfo.bottomTexCoord or 1
        local aW, aH = aR - aL, aB - aT
        _orbL, _orbR, _orbT, _orbB = aL, aL + aW/6, aT, aT + aH/2
    end
end

local function UpdateClassIcon(button, bnetInfo, wowInfo)
    if button.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then return end
    if not button.buttonType then return end

    local p = EBS.db.profile.friends

    local gameIcon = button.gameIcon
    if gameIcon then gameIcon:SetAlpha(0) end

    if not p.showClassIcons then
        if GetFFD(button).classIcon then GetFFD(button).classIcon:Hide() end
        return
    end

    if not GetFFD(button).classIcon then
        GetFFD(button).classIcon = button:CreateTexture(nil, "ARTWORK", nil, 2)
    end
    local icon = GetFFD(button).classIcon
    local h = button:GetHeight() - 4
    if h <= 0 then icon:Hide(); return end

    local state = "offline"
    if bnetInfo and bnetInfo.gameAccountInfo then
        local gi = bnetInfo.gameAccountInfo
        if gi.isOnline then
            if gi.clientProgram == BNET_CLIENT_WOW and (gi.wowProjectID == 1 or gi.wowProjectID == nil) then
                state = "retail"
            else
                state = "other_game"
            end
        end
    elseif wowInfo then
        state = wowInfo.connected and "retail" or "offline"
    end

    icon:ClearAllPoints()

    if state == "retail" then
        local inset = math.floor(h * 0.025 + 0.5)
        icon:SetPoint("LEFT", button, "LEFT", 4, 0)
        icon:SetPoint("TOP", button, "TOP", 0, -(2 + inset))
        icon:SetPoint("BOTTOM", button, "BOTTOM", 0, 2 + inset)
        local iconH = h - inset * 2
        if iconH > 0 then icon:SetWidth(iconH) end

        local classFile = GetFriendClassFile(bnetInfo, wowInfo)
        if not classFile then icon:Hide(); return end

        local style = p.iconStyle or "modern"
        if style == "blizzard" then
            icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
            if coords then icon:SetTexCoord(unpack(coords)) end
        else
            local coords = CLASS_SPRITE_COORDS[classFile]
            if coords then
                icon:SetTexture(CLASS_ICON_SPRITE_TEX[style] or (CLASS_ICON_SPRITE_BASE .. style .. ".tga"))
                icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
        end
        icon:SetDesaturated(false)
        icon:SetAlpha(1)

    elseif state == "other_game" then
        local smallH = math.floor(h * 0.75)
        icon:SetSize(smallH, smallH)
        icon:SetPoint("LEFT", button, "LEFT", 4 + math.floor((h - smallH) / 2), 0)
        if gameIcon then
            local tex = gameIcon:GetTexture()
            if tex then
                icon:SetTexture(tex)
                icon:SetTexCoord(0, 1, 0, 1)
            end
        end
        icon:SetDesaturated(false)
        icon:SetAlpha(1)

    else -- offline
        local smallH = math.floor(h * 0.75)
        icon:SetSize(smallH, smallH)
        icon:SetPoint("LEFT", button, "LEFT", 4 + math.floor((h - smallH) / 2), 0)
        icon:SetTexture(OFFLINE_ICON)
        icon:SetTexCoord(0, 1, 0, 1)
        icon:SetDesaturated(false)
        icon:SetAlpha(0.5)
    end

    icon:Show()
end

-- Class color hex codes (built on first use per class)
local _classColorCodes = {}
local function _getClassColorCode(classFile)
    local code = _classColorCodes[classFile]
    if code then return code end
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not cc then return nil end
    code = format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
    _classColorCodes[classFile] = code
    return code
end

local function UpdateNameColor(button, bnetInfo, wowInfo)
    local p = EBS.db.profile.friends
    local nameText = button.name or button.Name
    if not nameText then return end

    if not p.classColorNames then return end

    local classFile = GetFriendClassFile(bnetInfo, wowInfo)
    if not classFile then return end

    if wowInfo then
        local cc = RAID_CLASS_COLORS[classFile]
        if cc then nameText:SetTextColor(cc.r, cc.g, cc.b) end
    elseif bnetInfo then
        local text = nameText:GetText()
        if not text then return end
        local colorCode = _getClassColorCode(classFile)
        if not colorCode then return end
        local colored = text:gsub("%((.-)%)", "(" .. colorCode .. "%1|r)")
        if colored ~= text then
            nameText:SetText(colored)
        end
    end
end

-- Faction overlay texture paths
local FACTION_TEX_ALLIANCE = "Interface\\AddOns\\EllesmereUIFriends\\Media\\alliance.png"
local FACTION_TEX_HORDE    = "Interface\\AddOns\\EllesmereUIFriends\\Media\\horde.png"
local FACTION_TEX_NEUTRAL  = "Interface\\AddOns\\EllesmereUIFriends\\Media\\neutral.png"

local function UpdateFactionOverlay(button, bnetInfo, wowInfo)
    local factionName
    local isRetail = false
    if bnetInfo and bnetInfo.gameAccountInfo then
        local gi = bnetInfo.gameAccountInfo
        factionName = gi.factionName
        if gi.clientProgram == BNET_CLIENT_WOW and (gi.wowProjectID == 1 or gi.wowProjectID == nil) and gi.isOnline then
            isRetail = true
        end
    elseif wowInfo then
        factionName = UnitFactionGroup("player")
        isRetail = true
    end

    if not GetFFD(button).factionBg then
        GetFFD(button).factionBg = button:CreateTexture(nil, "BACKGROUND", nil, 3)
    end

    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
    local showFaction = fp and fp.factionBanners ~= false
    local texPath
    if showFaction and isRetail and factionName == "Alliance" then
        texPath = FACTION_TEX_ALLIANCE
    elseif showFaction and isRetail and factionName == "Horde" then
        texPath = FACTION_TEX_HORDE
    else
        texPath = FACTION_TEX_NEUTRAL
    end

    local tex = GetFFD(button).factionBg
    tex:SetTexture(texPath)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    tex:SetAlpha(0.2)
    tex:Show()
end

-- Skin a single friend button (one-time structural setup)
local function SkinFriendButton(button)
    if GetFFD(button).skinned then return end
    GetFFD(button).skinned = true

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT

    local function ApplyFont(fs, size)
        if not fs or not fs.SetFont then return end
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, true) end
        fs:SetFont(fontPath, size, "")
    end

    -- Tile background
    local tileBg = button:CreateTexture(nil, "BACKGROUND", nil, 2)
    tileBg:SetAllPoints()
    tileBg:SetColorTexture(0, 0, 0, 0.10)
    GetFFD(button).tileBg = tileBg

    -- Keep Blizzard's highlight texture for native selection/hover

    -- Hover highlight (OnEnter/OnLeave)
    local hover = button:CreateTexture(nil, "ARTWORK", nil, -7)
    hover:SetAllPoints()
    hover:SetAtlas("groupfinder-highlightbar-green")
    hover:SetDesaturated(true)
    hover:SetVertexColor(0.4, 0.7, 1.0)
    hover:SetAlpha(1)
    hover:Hide()
    local hoverFill = button:CreateTexture(nil, "ARTWORK", nil, -8)
    hoverFill:SetAllPoints()
    hoverFill:SetColorTexture(1, 1, 1, 0.02)
    hoverFill:SetBlendMode("ADD")
    hoverFill:Hide()
    button:HookScript("OnEnter", function() hover:Show(); hoverFill:Show() end)
    button:HookScript("OnLeave", function() hover:Hide(); hoverFill:Hide() end)

    -- Apply font to friend row text
    local nameText = button.name or button.Name
    ApplyFont(nameText, 12)
    local infoText = button.info or button.Info
    ApplyFont(infoText, 9)
    local statusText = button.status or button.Status
    ApplyFont(statusText, 9)
    local gameText = button.gameText or button.GameText
    ApplyFont(gameText, 9)

    -- Offset name text right for class icon
    if nameText then
        local p1, rel, p2, x, y = nameText:GetPoint(1)
        if p1 then
            nameText:SetPoint(p1, rel, p2, (x or 0) + 20, y or 0)
        end
    end
end

-- Post-update skinning for friend buttons. Called via hooksecurefunc on
-- FriendsFrame_UpdateFriendButton. Purely cosmetic -- never calls
-- C_BattleNet or C_FriendList APIs. Reads from pre-populated _friendCache.
local function PostUpdateFriendButton(button)
    if not FriendsFrame:IsShown() then return end
    if not EBS.db or not EBS.db.profile.friends.enabled then return end
    if button.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then return end
    if not button.buttonType then return end

    -- Structural skinning (one-time per button, guarded by FFD flag)
    SkinFriendButton(button)

    -- Selection highlight: use Blizzard's native selection (not stripped)

    -- Hide Blizzard elements
    local fav = button.Favorite
    if fav then fav:SetAlpha(0) end
    local statusIcon = button.statusIcon or button.StatusIcon
    if statusIcon then statusIcon:SetAlpha(0) end
    local statusTex = button.status
    if statusTex and statusTex.IsObjectType and statusTex:IsObjectType("Texture") then
        statusTex:SetAlpha(0)
    end
    local gameIcon = button.gameIcon
    if gameIcon then gameIcon:SetAlpha(0) end

    -- Fill blank info text for BNet app users
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET and button.id then
        local infoFS = button.info or button.Info
        if infoFS and (not infoFS:GetText() or infoFS:GetText() == "") then
            local cached = _friendCache[button.id]
            if cached and cached.gameAccountInfo then
                local gi = cached.gameAccountInfo
                local cp = gi.clientProgram
                if gi.isOnline and (cp == "App" or cp == "BSAp") then
                    local locale = GetLocale()
                    infoFS:SetText((locale == "enUS" or locale == "enGB") and "In App" or "Battle.Net")
                end
            end
        end
    end

    -- Stamp: skip redundant work for the same button+friend combo
    local curType = button.buttonType
    local curId = button.id or 0
    if GetFFD(button).stampType == curType and GetFFD(button).stampId == curId then return end
    GetFFD(button).stampType = curType
    GetFFD(button).stampId = curId
    GetFFD(button)._origInfo = nil  -- clear so note re-captures from Blizzard's fresh text

    local bnetInfo, wowInfo = GetCachedFriendInfo(button)

    -- Re-anchor info text below name
    local nameText = button.name or button.Name
    local infoText = button.info or button.Info
    if infoText and nameText then
        infoText:ClearAllPoints()
        infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3)
    end

    -- Append friend note (stripped of legacy EUI group tag).
    -- Save Blizzard's original text first to avoid double-appending on re-skin.
    if infoText and button.buttonType and button.id then
        -- Capture original text before we modify it (only on first stamp)
        local origInfo = GetFFD(button)._origInfo
        if not origInfo then
            origInfo = infoText:GetText() or ""
            -- Strip any previously-appended note suffix to avoid stacking
            -- (button recycling can leave our old text in infoText)
            origInfo = origInfo:match("^(.-)  |cff888888|") or origInfo
            GetFFD(button)._origInfo = origInfo
        end
        local userNote
        if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
            local cached = _friendCache[button.id]
            if cached and cached.note then
                local _, clean = ParseGroupFromNote(cached.note)
                if clean and clean ~= "" then userNote = clean end
            end
        elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
            local cached = _friendCache[button.id + _FC_WOW_OFFSET]
            if cached and cached.notes then
                local _, clean = ParseGroupFromNote(cached.notes)
                if clean and clean ~= "" then userNote = clean end
            end
        end
        if userNote then
            if origInfo ~= "" then
                infoText:SetText(origInfo .. "  |cff888888|  " .. userNote .. "|r")
            else
                infoText:SetText("|cff888888" .. userNote .. "|r")
            end
        end
    end

    -- Status orb (online/away/busy indicator)
    local isOnline, isAFK, isDND = false, false, false
    local _isv = issecretvalue
    if bnetInfo then
        isOnline = bnetInfo.gameAccountInfo and bnetInfo.gameAccountInfo.isOnline
        local rawAFK = bnetInfo.isAFK
        local rawDND = bnetInfo.isDND
        isAFK = (not _isv or not _isv(rawAFK)) and rawAFK or false
        isDND = (not _isv or not _isv(rawDND)) and rawDND or false
    elseif wowInfo then
        isOnline = wowInfo.connected
        local rawAFK = wowInfo.afk
        local rawDND = wowInfo.dnd
        isAFK = (not _isv or not _isv(rawAFK)) and rawAFK or false
        isDND = (not _isv or not _isv(rawDND)) and rawDND or false
    end

    if not GetFFD(button).statusOrb then
        GetFFD(button).statusOrb = button:CreateTexture(nil, "OVERLAY", nil, 3)
        GetFFD(button).statusOrb:SetSize(18, 18)
        if _orbFile then
            GetFFD(button).statusOrb:SetTexture(_orbFile)
            GetFFD(button).statusOrb:SetTexCoord(_orbL, _orbR, _orbT, _orbB)
        else
            GetFFD(button).statusOrb:SetAtlas("lootroll-animreveal-a")
            GetFFD(button).statusOrb:SetTexCoord(0, 1/6, 0, 0.5)
        end
    end
    local orb = GetFFD(button).statusOrb
    orb:ClearAllPoints()
    local nm = button.name or button.Name
    if nm then
        local textW = nm:GetStringWidth() or 0
        orb:SetPoint("TOPLEFT", nm, "TOPLEFT", textW - 1, 2)
    end
    if isOnline then
        if isDND then
            orb:SetVertexColor(1, 0.2, 0.2, 1)
        elseif isAFK then
            orb:SetVertexColor(1, 0.8, 0, 1)
        else
            orb:SetVertexColor(0.2, 1, 0.2, 1)
        end
        orb:Show()
    else
        orb:SetVertexColor(0.4, 0.4, 0.4, 0.6)
        orb:Show()
    end

    UpdateClassIcon(button, bnetInfo, wowInfo)
    UpdateNameColor(button, bnetInfo, wowInfo)
    UpdateFactionOverlay(button, bnetInfo, wowInfo)

    -- Region icon
    local fp2 = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if fp2 and fp2.showRegionIcons == false then
        if GetFFD(button).regionBtn then GetFFD(button).regionBtn:Hide() end
    else
        local myFull = EllesmereUI.GetMyFullRegion and EllesmereUI.GetMyFullRegion()
        local friendMini
        if bnetInfo and bnetInfo.gameAccountInfo then
            friendMini = EllesmereUI.GetFriendMiniRegion and EllesmereUI.GetFriendMiniRegion(bnetInfo.gameAccountInfo)
        end
        local friendFull = friendMini and EllesmereUI.GetFullRegion and EllesmereUI.GetFullRegion(friendMini)

        if friendMini and friendFull and friendFull ~= myFull then
            if not GetFFD(button).regionBtn then
                local rb = CreateFrame("Button", nil, button)
                rb:SetFrameLevel(button:GetFrameLevel() + 5)
                rb._tex = rb:CreateTexture(nil, "OVERLAY", nil, 7)
                rb._tex:SetAllPoints()
                rb._tex:SetAlpha(0.25)
                rb:SetScript("OnEnter", function(self)
                    if EllesmereUI.ShowWidgetTooltip then
                        EllesmereUI.ShowWidgetTooltip(self, self._regionLabel or "")
                    end
                end)
                rb:SetScript("OnLeave", function()
                    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                end)
                local hh = button:GetHeight()
                local iconH = math.floor(hh * 0.8)
                rb:SetSize(iconH, iconH)
                local tpBtn = button.travelPassButton
                if tpBtn then
                    rb:SetPoint("RIGHT", tpBtn, "LEFT", -2, 0)
                else
                    rb:SetPoint("RIGHT", button, "RIGHT", -30, 0)
                end
                GetFFD(button).regionBtn = rb
            end
            local rb = GetFFD(button).regionBtn
            if rb._lastMini ~= friendMini then
                rb._lastMini = friendMini
                local iconPath = EllesmereUI.GetRegionIcon and EllesmereUI.GetRegionIcon(friendMini)
                rb._tex:SetTexture(iconPath)
                rb._tex:SetTexCoord(0, 1, 0, 1)
                rb._regionLabel = MINI_DISPLAY[friendMini] or friendMini
            end
            rb:Show()
        else
            if GetFFD(button).regionBtn then GetFFD(button).regionBtn:Hide() end
        end
    end
end

-- Process all visible friend buttons (safety net for initial show)
local function ProcessFriendButtons()
    if LegacyFriendsRetired() then return end
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if not scrollBox then return end
    for _, button in scrollBox:EnumerateFrames() do
        if button.buttonType and button.buttonType ~= FRIENDS_BUTTON_TYPE_DIVIDER
           and button.buttonType ~= FRIENDS_BUTTON_TYPE_INVITE
           and button.buttonType ~= FRIENDS_BUTTON_TYPE_INVITE_HEADER then
            GetFFD(button).stampType = nil
            PostUpdateFriendButton(button)
        end
    end
end


-- Skin a single ScrollBox+ScrollBar pair with thin EUI track
local function SkinOneScrollbar(scrollBox, scrollBar)
    if not scrollBox or not scrollBar then return end
    if GetFFD(scrollBox).track then return end

    scrollBar:SetAlpha(0)
    GetFFD(scrollBox).scrollBar = scrollBar

    local track = CreateFrame("Frame", nil, UIParent)
    track:Hide()
    track:SetFrameStrata("HIGH")
    track:SetWidth(4)
    track:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, 0)
    track:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 0)
    track:SetFrameLevel(scrollBox:GetFrameLevel() + 10)
    GetFFD(scrollBox).track = track

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(1, 1, 1, 0)
    trackBg:SetAllPoints()

    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(4)
    thumb:SetHeight(60)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:SetFrameLevel(track:GetFrameLevel() + 1)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetColorTexture(1, 1, 1, 0.4)
    thumbTex:SetAllPoints()

    local hitArea = CreateFrame("Button", nil, UIParent)
    hitArea:SetFrameStrata("HIGH")
    hitArea:Hide()
    track._hitArea = hitArea
    hitArea:SetWidth(16)
    hitArea:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", -4, -2)
    hitArea:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", -4, 2)
    hitArea:SetFrameLevel(track:GetFrameLevel() + 2)
    hitArea:EnableMouse(true)
    hitArea:RegisterForDrag("LeftButton")

    local SCROLL_STEP = 40
    local SCROLLBAR_ALPHA = 0.35
    local isDragging = false
    local dragStartY, dragStartPct

    local function GetPct()
        return scrollBar.GetScrollPercentage and scrollBar:GetScrollPercentage() or 0
    end

    local function GetExtent()
        return scrollBar.GetVisibleExtentPercentage and scrollBar:GetVisibleExtentPercentage() or 1
    end

    local function StepToPct()
        local ext = GetExtent()
        if ext >= 1 then return 0 end
        local totalH = scrollBox:GetHeight() / ext
        if totalH <= 0 then return 0 end
        return SCROLL_STEP / totalH
    end

    local function StopScrollDrag()
        if not isDragging then return end
        isDragging = false
        thumb:SetScript("OnUpdate", nil)
    end

    local function UpdateScrollThumb()
        local ext = GetExtent()
        if ext >= 1 then track:SetAlpha(0); return end
        track:SetAlpha(SCROLLBAR_ALPHA)
        local pct = GetPct()
        local trackH = track:GetHeight()
        local thumbH = math.max(20, trackH * ext)
        thumb:SetHeight(thumbH)
        local maxTravel = trackH - thumbH
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(pct * maxTravel))
    end

    scrollBox:SetScript("OnMouseWheel", function(_, delta)
        if GetExtent() >= 1 then return end
        local step = StepToPct()
        local newPct = math.max(0, math.min(1, GetPct() - delta * step))
        scrollBar:SetScrollPercentage(newPct)
        UpdateScrollThumb()
    end)

    local function ScrollThumbOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then StopScrollDrag(); return end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local deltaY = dragStartY - cursorY
        local trackH = track:GetHeight()
        local maxTravel = trackH - self:GetHeight()
        if maxTravel <= 0 then return end
        local newPct = math.max(0, math.min(1, dragStartPct + deltaY / maxTravel))
        scrollBar:SetScrollPercentage(newPct)
        UpdateScrollThumb()
    end

    thumb:SetScript("OnMouseDown", function(self, mouseBtn)
        if mouseBtn ~= "LeftButton" then return end
        isDragging = true
        local _, cursorY = GetCursorPosition()
        dragStartY = cursorY / self:GetEffectiveScale()
        dragStartPct = GetPct()
        self:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    thumb:SetScript("OnMouseUp", function(_, mouseBtn)
        if mouseBtn ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    hitArea:SetScript("OnMouseDown", function(_, mouseBtn)
        if mouseBtn ~= "LeftButton" then return end
        if GetExtent() >= 1 then return end
        local _, cy = GetCursorPosition()
        cy = cy / track:GetEffectiveScale()
        local top = track:GetTop() or 0
        local trackH = track:GetHeight()
        local thumbH = thumb:GetHeight()
        if trackH <= thumbH then return end
        local frac = (top - cy - thumbH / 2) / (trackH - thumbH)
        frac = math.max(0, math.min(1, frac))
        scrollBar:SetScrollPercentage(frac)
        UpdateScrollThumb()
        isDragging = true
        dragStartY = cy
        dragStartPct = frac
        thumb:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    hitArea:SetScript("OnMouseUp", function(_, mouseBtn)
        if mouseBtn ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    if scrollBar.RegisterCallback then
        scrollBar:RegisterCallback("OnScroll", UpdateScrollThumb)
    end
    if scrollBox.RegisterCallback then
        scrollBox:RegisterCallback("OnDataRangeChanged", UpdateScrollThumb)
    end
    C_Timer.After(0.1, UpdateScrollThumb)
end

-- Polling scrollbar for the friends list. Does NOT register callbacks or
-- SetScript on Blizzard's ScrollBox/Bar. Instead uses OnUpdate to poll
-- scroll position (only while FriendsFrame is shown).

-- Skin a bottom-area button (Add Friend, Send Message, etc.)
local function SkinBottomButton(btn)
    if not btn or GetFFD(btn).btnSkinned then return end
    GetFFD(btn).btnSkinned = true

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT

    StripTextures(btn)

    GetFFD(btn).bg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    GetFFD(btn).bg:SetColorTexture(0.025, 0.035, 0.045, 0.92)
    GetFFD(btn).bg:SetAllPoints()

    PP.CreateBorder(btn, 1, 1, 1, 0.4, 1, "OVERLAY", 7)

    local text = btn:GetFontString()
    if text then
        text:SetFont(fontPath, 9, "")
        text:SetTextColor(1, 1, 1, 0.5)
        text:ClearAllPoints()
        text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    end

    btn:HookScript("OnEnter", function()
        local r, g, b, a1, a2 = 1, 1, 1, 0.7, 0.6
        if GetFFD(btn).accent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 1, 0.8
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if PP.GetBorders(btn) then PP.SetBorderColor(btn, r, g, b, a2) end
    end)
    btn:HookScript("OnLeave", function()
        local r, g, b, a1, a2 = 1, 1, 1, 0.5, 0.4
        if GetFFD(btn).accent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 0.7, 0.5
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if PP.GetBorders(btn) then PP.SetBorderColor(btn, r, g, b, a2) end
    end)
end

-- Skin known buttons by name
local KNOWN_BUTTONS = {
    "FriendsFrameAddFriendButton",
    "FriendsFrameSendMessageButton",
    "WhoFrameWhoButton",
    "WhoFrameAddFriendButton",
    "WhoFrameGroupInviteButton",
}

-- Apply accent coloring to bottom buttons
local function UpdateBottomButtonAccent()
    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not fp then return end
    local useAccent = fp.accentColors ~= false

    local function ApplyAccentToBtn(btn, labelFS)
        if not btn then return end
        GetFFD(btn).accent = useAccent
        if useAccent then
            if labelFS then labelFS:SetTextColor(EG.r, EG.g, EG.b, 0.7) end
            if PP.GetBorders(btn) then PP.SetBorderColor(btn, EG.r, EG.g, EG.b, 0.5) end
        else
            if labelFS then labelFS:SetTextColor(1, 1, 1, 0.5) end
            if PP.GetBorders(btn) then PP.SetBorderColor(btn, 1, 1, 1, 0.4) end
        end
    end

    for _, name in ipairs(KNOWN_BUTTONS) do
        local btn = _G[name]
        if btn and GetFFD(btn).btnSkinned and btn:IsEnabled()
           and name ~= "FriendsFrameAddFriendButton" then
            ApplyAccentToBtn(btn, btn:GetFontString())
        end
    end

    -- Send Message button: text + separate border overlay (skinned outside SkinBottomButton)
    local msgBtn = _G.FriendsFrameSendMessageButton
    if msgBtn then
        local text = msgBtn:GetFontString()
        if text then
            if useAccent then text:SetTextColor(EG.r, EG.g, EG.b, 0.7)
            else text:SetTextColor(1, 1, 1, 0.5) end
        end
    end
    local ffd = FriendsFrame and GetFFD(FriendsFrame)
    if ffd then
        if ffd.msgBdr then
            if useAccent then PP.SetBorderColor(ffd.msgBdr, EG.r, EG.g, EG.b, 0.5)
            else PP.SetBorderColor(ffd.msgBdr, 1, 1, 1, 0.4) end
        end
    end
end

-- Frame background color
local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

-------------------------------------------------------------------------------
--  SkinFriendsFrame (one-time structural setup)
-------------------------------------------------------------------------------
local function SkinFriendsFrame()
    if LegacyFriendsRetired() then return end
    local frame = FriendsFrame
    if not frame or friendsSkinned then return end
    friendsSkinned = true
    local p = EBS.db.profile.friends
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT

    -- Hide Blizzard decorations
    if frame.NineSlice then frame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end
    if frame.TopTileStreaks then frame.TopTileStreaks:SetAlpha(0) end
    if frame.PortraitContainer then frame.PortraitContainer:Hide() end
    if frame.portrait then frame.portrait:Hide() end
    if frame.PortraitFrame then frame.PortraitFrame:Hide() end
    if FriendsFramePortrait then FriendsFramePortrait:Hide() end
    if FriendsFrameIcon then FriendsFrameIcon:Hide() end

    for _, key in ipairs({"TopBorder", "TopRightCorner", "RightBorder",
                          "BottomRightCorner", "BottomBorder", "BottomLeftCorner",
                          "LeftBorder", "TopLeftCorner", "BtnCornerLeft",
                          "BtnCornerRight"}) do
        if frame[key] then frame[key]:Hide() end
    end

    if frame.Inset then
        if frame.Inset.NineSlice then frame.Inset.NineSlice:Hide() end
        if frame.Inset.Bg then frame.Inset.Bg:Hide() end
    end

    -- Resize frame
    if not GetFFD(frame).sizeSet then
        GetFFD(frame).sizeSet = true
        local origW = frame:GetWidth()
        local origH = frame:GetHeight()
        local origListH = FriendsListFrame:GetHeight()
        local EXTRA_H = 50
        local LIST_TOP = -92
        local LIST_BOTTOM = 35
        local LIST_LEFT = 15
        local LIST_RIGHT = -15
        local _sizeApplied = false
        local function ApplySize()
            if _sizeApplied then return end
            _sizeApplied = true
            frame:SetWidth(origW - 40)
            frame:SetHeight(origH + EXTRA_H)
            FriendsListFrame:SetHeight(origListH + EXTRA_H)
            -- Reposition Blizzard's ScrollBox to our list pane area
            FriendsListFrame.ScrollBox:ClearAllPoints()
            FriendsListFrame.ScrollBox:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT, LIST_TOP)
            FriendsListFrame.ScrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
            -- Match other sub-tab content frames
            local function FitToListPane(f)
                if not f then return end
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT, LIST_TOP)
                f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
                StripTextures(f)
                if f.Bg then f.Bg:Hide() end
                if f.NineSlice then f.NineSlice:Hide() end
                if f.List then
                    f.List:ClearAllPoints()
                    f.List:SetAllPoints(f)
                    StripTextures(f.List)
                    if f.List.ScrollBox then
                        f.List.ScrollBox:ClearAllPoints()
                        f.List.ScrollBox:SetAllPoints(f.List)
                    end
                end
            end
            FitToListPane(_G.RecentAlliesFrame)
            -- Skin Recent Allies scrollbar identically to Friends list
            local raFrame = _G.RecentAlliesFrame
            if raFrame and raFrame.List then
                local raBar = raFrame.List.ScrollBar or raFrame.ScrollBar
                if raBar then
                    StripTextures(raBar)
                    if raBar.Background then raBar.Background:Hide() end
                    if raBar.Back then raBar.Back:SetAlpha(0); raBar.Back:SetSize(1, 0.001) end
                    if raBar.Forward then raBar.Forward:SetAlpha(0); raBar.Forward:SetSize(1, 0.001) end
                    local raTrack = raBar.Track
                    if raTrack then
                        raTrack:DisableDrawLayer("ARTWORK")
                        raTrack:DisableDrawLayer("BACKGROUND")
                        raTrack:ClearAllPoints()
                        raTrack:SetPoint("TOPLEFT", raBar, "TOPLEFT", 0, 0)
                        raTrack:SetPoint("BOTTOMRIGHT", raBar, "BOTTOMRIGHT", 0, 0)
                    end
                    local raThumb = raBar.GetThumb and raBar:GetThumb()
                    if raThumb then
                        raThumb:DisableDrawLayer("ARTWORK")
                        raThumb:DisableDrawLayer("BACKGROUND")
                        local raTex = raThumb:CreateTexture(nil, "OVERLAY")
                        raTex:SetColorTexture(1, 1, 1, 0.4)
                        raTex:SetWidth(3)
                        raTex:SetPoint("TOP", raThumb, "TOP", 0, 0)
                        raTex:SetPoint("BOTTOM", raThumb, "BOTTOM", 0, 0)
                        raTex:SetPoint("RIGHT", raThumb, "RIGHT", 0, 0)
                    end
                    raBar:SetWidth(5)
                    local p1, rel, p2, ox, oy = raBar:GetPoint(1)
                    if p1 then
                        raBar:SetPoint(p1, rel, p2, (ox or 0) - 6, (oy or 0) + 4)
                    end
                    raBar:SetAlpha(0.6)
                    raBar:HookScript("OnEnter", function() raBar:SetAlpha(0.95) end)
                    raBar:HookScript("OnLeave", function() raBar:SetAlpha(0.6) end)
                    if raThumb then
                        raThumb:HookScript("OnEnter", function() raBar:SetAlpha(0.95) end)
                        raThumb:HookScript("OnLeave", function() raBar:SetAlpha(0.6) end)
                    end
                end
            end
            local raf = _G.RecruitAFriendFrame
            if raf then
                raf:ClearAllPoints()
                raf:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT, -20)
                raf:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM - 20)
                StripTextures(raf)
                if raf.Bg then raf.Bg:Hide() end
                if raf.NineSlice then raf.NineSlice:Hide() end
            end
        end

        hooksecurefunc(frame, "Show", function()
            local _mplus = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
            local _, _iT = IsInInstance()
            local _pvp = (_iT == "pvp" or _iT == "arena")
            if not InCombatLockdown() and not _mplus and not _pvp then
                ApplySize()
            end
        end)
        ApplySize()
    end

    -- Dark background
    GetFFD(frame).bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    GetFFD(frame).bg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
    GetFFD(frame).bg:SetAllPoints()
    GetFFD(frame).bg:SetAlpha(1)

    -- Pixel border
    do
        local r, g, b, a = GetBorderColor(p)
        local borderAlpha = (p.showBorder ~= false) and a or 0
        PP.CreateBorder(frame, r, g, b, borderAlpha, p.borderSize or 1, "OVERLAY", 7)
    end

    -- Reparent IgnoreListWindow
    if frame.IgnoreListWindow then
        frame.IgnoreListWindow:SetParent(UIParent)
        frame.IgnoreListWindow:SetFrameStrata("DIALOG")
    end

    if _G.RaidInfoFrame then
        _G.RaidInfoFrame:SetFrameStrata("DIALOG")
    end

    if FriendsTooltip then
        FriendsTooltip:SetParent(UIParent)
        FriendsTooltip:SetFrameStrata("TOOLTIP")
    end

    -- Tab bar background
    local firstTab = _G.FriendsFrameTab1
    if firstTab then
        GetFFD(frame).tabBarBg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        GetFFD(frame).tabBarBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
        GetFFD(frame).tabBarBg:SetAlpha(1)
        GetFFD(frame).tabBarBg:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 2)
        GetFFD(frame).tabBarBg:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 2)
        GetFFD(frame).tabBarBg:SetPoint("BOTTOM", firstTab, "BOTTOM", 0, 0)
    end

    -- Restyle Blizzard's tabs in-place
    local customTabs = {}
    for i = 1, frame.numTabs or 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            for j = 1, select("#", tab:GetRegions()) do
                local region = select(j, tab:GetRegions())
                if region and region:IsObjectType("Texture") then
                    region:SetTexture("")
                    if region.SetAtlas then region:SetAtlas("") end
                end
            end
            if tab.Left then tab.Left:SetTexture("") end
            if tab.Middle then tab.Middle:SetTexture("") end
            if tab.Right then tab.Right:SetTexture("") end
            if tab.LeftDisabled then tab.LeftDisabled:SetTexture("") end
            if tab.MiddleDisabled then tab.MiddleDisabled:SetTexture("") end
            if tab.RightDisabled then tab.RightDisabled:SetTexture("") end
            local hl = tab:GetHighlightTexture()
            if hl then hl:SetTexture("") end

            if not GetFFD(tab).bg then
                GetFFD(tab).bg = tab:CreateTexture(nil, "BACKGROUND")
                GetFFD(tab).bg:SetAllPoints()
                GetFFD(tab).bg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
            end

            local tfd = GetFFD(tab)
            if not tfd.activeHL then
                local activeHL = tab:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHL:SetAllPoints()
                activeHL:SetColorTexture(1, 1, 1, 0.05)
                activeHL:SetBlendMode("ADD")
                activeHL:Hide()
                tfd.activeHL = activeHL
            end

            local blizLabel = tab:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or ("Tab " .. i)
            if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
            tab:SetPushedTextOffset(0, 0)
            local label = tab:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 9, "")
            label:SetPoint("CENTER", tab, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetText(labelText)
            tfd.label = label

            if not tfd.underline then
                local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
                PP.DisablePixelSnap(underline)
                underline:SetHeight(PP.mult or 1)
                underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
                underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
                local ar, ag, ab = EG.r, EG.g, EG.b
                underline:SetColorTexture(ar, ag, ab, 1)
                EllesmereUI.RegAccent({ type = "solid", obj = underline, a = 1 })
                underline:Hide()
                tfd.underline = underline
            end

            customTabs[i] = tab
        end
    end

    local _activeSubTab = 1

    local function UpdateCustomTabs(overrideTab)
        local selected = overrideTab or PanelTemplates_GetSelectedTab(FriendsFrame) or 1
        local isContacts = (selected == 1)
        local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
        local useAccent = fp and fp.accentColors ~= false
        for i, ct in ipairs(customTabs) do
            local isActive = (i == selected)
            local ctd = GetFFD(ct)
            if ctd.label then ctd.label:SetTextColor(1, 1, 1, isActive and 1 or 0.5) end
            if ctd.underline then
                ctd.underline:SetShown(isActive)
                if isActive then
                    if useAccent then
                        local ar, ag, ab = EG.r, EG.g, EG.b
                        ctd.underline:SetColorTexture(ar, ag, ab, 1)
                    else
                        ctd.underline:SetColorTexture(1, 1, 1, 0.6)
                    end
                end
            end
            if ctd.activeHL then ctd.activeHL:SetShown(isActive) end
        end
        local showContactsUI = isContacts and _activeSubTab == 1
        local addBtn = _G.FriendsFrameAddFriendButton
        local msgBtn = _G.FriendsFrameSendMessageButton
        if addBtn then addBtn:SetAlpha(showContactsUI and 1 or 0); addBtn:EnableMouse(showContactsUI) end
        if msgBtn then msgBtn:SetAlpha(showContactsUI and 1 or 0); msgBtn:EnableMouse(showContactsUI) end
        if GetFFD(frame).addBdr then GetFFD(frame).addBdr:SetShown(showContactsUI) end
        if GetFFD(frame).msgBdr then GetFFD(frame).msgBdr:SetShown(showContactsUI) end
        local showListChrome = isContacts and _activeSubTab ~= 3
        if GetFFD(frame).listOverlay then GetFFD(frame).listOverlay:SetShown(showListChrome) end
        if GetFFD(frame).listBdr then GetFFD(frame).listBdr:SetShown(showListChrome) end
        if GetFFD(frame).searchBox then GetFFD(frame).searchBox:SetShown(isContacts) end
        if not isContacts and GetFFD(frame).searchDropdown then GetFFD(frame).searchDropdown:Hide() end
        local showTopUI = (selected ~= 3)
        if not isContacts and GetFFD(frame).subTabs then
            for _, ct in ipairs(GetFFD(frame).subTabs) do
                ct._label:SetTextColor(1, 1, 1, 0.53)
                ct:SetShown(showTopUI)
            end
        elseif GetFFD(frame).subTabs then
            for _, ct in ipairs(GetFFD(frame).subTabs) do
                ct:Show()
            end
            if GetFFD(frame).updateSubTabs then GetFFD(frame).updateSubTabs() end
        end
        if GetFFD(frame).statusOrb then GetFFD(frame).statusOrb:SetShown(isContacts) end
        if GetFFD(frame).broadcastBtn then GetFFD(frame).broadcastBtn:SetShown(isContacts) end
        if GetFFD(frame).titleBtn then GetFFD(frame).titleBtn:Show() end
        if GetFFD(frame).titleDiv then GetFFD(frame).titleDiv:Show() end
        -- Sync scrollbar visibility
        local function SetTrackVisSB(sb, vis)
            if sb and GetFFD(sb).track then
                GetFFD(sb).track:SetShown(vis)
                if GetFFD(sb).track._hitArea then GetFFD(sb).track._hitArea:SetShown(vis) end
            end
        end
        local shown = frame:IsShown()
        local raf = _G.RecentAlliesFrame
        if raf and raf.List then SetTrackVisSB(raf.List.ScrollBox, shown and isContacts and _activeSubTab == 2) end
        local who = _G.WhoFrame
        if who then SetTrackVisSB(who.ScrollBox or (who.List and who.List.ScrollBox), shown and selected == 2) end
    end

    GetFFD(frame).updateCustomTabs = UpdateCustomTabs

    -- Detect tab changes
    local tabFrames = {
        { _G.FriendsListFrame, 1 },
        { _G.WhoFrame,         2 },
        { _G.RaidFrame,        3 },
        { _G.QuickJoinFrame,   4 },
    }
    for _, entry in ipairs(tabFrames) do
        local sf, tabIdx = entry[1], entry[2]
        if sf then
            sf:HookScript("OnShow", function()
                UpdateCustomTabs(tabIdx)
                if tabIdx == 1 then
                    -- Skin buttons immediately on tab switch (user-initiated, safe)
                    RefreshFriendCache()
                    ProcessFriendButtons()
                end
                if tabIdx == 3 then C_Timer.After(0, SkinRaidTab); C_Timer.After(0.2, SkinRaidTab) end
            end)
        end
    end
    if not _G.RaidFrame then
        C_Timer.After(0.25, function()
            local rf = _G.RaidFrame
            if rf then
                rf:HookScript("OnShow", function()
                    UpdateCustomTabs(3)
                    C_Timer.After(0, SkinRaidTab); C_Timer.After(0.2, SkinRaidTab)
                end)
            end
        end)
    end
    hooksecurefunc(frame, "Show", function()
        UpdateCustomTabs()
    end)

    hooksecurefunc(frame, "Hide", function()
        local function HideTrackSB(sb)
            if sb and GetFFD(sb).track then
                GetFFD(sb).track:Hide()
                if GetFFD(sb).track._hitArea then GetFFD(sb).track._hitArea:Hide() end
            end
        end
        _activeSubTab = 1
        local raf = _G.RecentAlliesFrame
        if raf and raf.List then HideTrackSB(raf.List.ScrollBox) end
        local who = _G.WhoFrame
        if who then HideTrackSB(who.ScrollBox or (who.List and who.List.ScrollBox)) end
    end)

    -- Title text
    if frame.TitleContainer then
        local blizTitle = frame.TitleContainer.TitleText or frame.TitleContainer:GetFontString()
        if blizTitle then blizTitle:SetAlpha(0) end
    elseif FriendsFrameTitleText then
        FriendsFrameTitleText:SetAlpha(0)
    end

    local _, battleTag = BNGetInfo()
    local titleText = battleTag or (FRIENDS or "Friends")
    local titleBtn = CreateFrame("Button", nil, frame)
    titleBtn:SetFrameLevel(frame:GetFrameLevel() + 5)

    local titleLabel = titleBtn:CreateFontString(nil, "OVERLAY")
    titleLabel:SetFont(fontPath, 12, "")
    titleLabel:SetTextColor(1, 1, 1, 0.75)
    titleLabel:SetPoint("CENTER", titleBtn, "CENTER", 0, 0)
    titleLabel:SetJustifyH("CENTER")
    titleLabel:SetText(titleText)

    local textW = titleLabel:GetStringWidth() or 60
    titleBtn:SetSize(textW + 16, 20)
    titleBtn:SetPoint("TOP", frame, "TOP", 0, -5)

    titleBtn._label = titleLabel
    GetFFD(frame).titleBtn = titleBtn

    titleBtn:SetScript("OnEnter", function()
        titleLabel:SetTextColor(1, 1, 1, 1)
    end)
    titleBtn:SetScript("OnLeave", function()
        titleLabel:SetTextColor(1, 1, 1, 0.75)
    end)

    -- Copy popup for BattleTag
    local copyBackdrop, copyPopup
    local function HideCopyPopup()
        if copyPopup then copyPopup:Hide() end
        if copyBackdrop then copyBackdrop:Hide() end
    end

    local function ShowCopyPopup(text, anchorBtn)
        if not copyPopup then
            copyBackdrop = CreateFrame("Button", nil, UIParent)
            copyBackdrop:SetFrameStrata("DIALOG")
            copyBackdrop:SetFrameLevel(499)
            copyBackdrop:SetAllPoints(UIParent)
            local bdTex = copyBackdrop:CreateTexture(nil, "BACKGROUND")
            bdTex:SetAllPoints()
            bdTex:SetColorTexture(0, 0, 0, 0.10)
            local fadeIn = copyBackdrop:CreateAnimationGroup()
            fadeIn:SetToFinalAlpha(true)
            local a = fadeIn:CreateAnimation("Alpha")
            a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.2)
            copyBackdrop._fadeIn = fadeIn
            copyBackdrop:RegisterForClicks("AnyUp")
            copyBackdrop:SetScript("OnClick", HideCopyPopup)
            copyBackdrop:Hide()

            copyPopup = CreateFrame("Frame", nil, UIParent)
            copyPopup:SetFrameStrata("DIALOG")
            copyPopup:SetFrameLevel(500)
            copyPopup:SetSize(220, 52)
            local popFade = copyPopup:CreateAnimationGroup()
            popFade:SetToFinalAlpha(true)
            local pa = popFade:CreateAnimation("Alpha")
            pa:SetFromAlpha(0); pa:SetToAlpha(1); pa:SetDuration(0.2)
            copyPopup._fadeIn = popFade

            local bg = copyPopup:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
            PP.CreateBorder(copyPopup, 1, 1, 1, 0.15, 1, "OVERLAY", 7)

            local hint = copyPopup:CreateFontString(nil, "OVERLAY")
            hint:SetFont(fontPath, 8, "")
            hint:SetTextColor(1, 1, 1, 0.5)
            hint:SetPoint("TOP", copyPopup, "TOP", 0, -6)
            hint:SetText("Ctrl+C to copy, Escape to close")

            local eb = CreateFrame("EditBox", nil, copyPopup)
            eb:SetSize(160, 16)
            eb:SetPoint("TOP", hint, "BOTTOM", 0, -4)
            eb:SetFontObject(GameFontHighlight)
            eb:SetAutoFocus(false)
            eb:SetJustifyH("CENTER")
            local ebBg = eb:CreateTexture(nil, "BACKGROUND")
            ebBg:SetColorTexture(0.10, 0.12, 0.16, 1)
            ebBg:SetPoint("TOPLEFT", -6, 4); ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
            PP.CreateBorder(eb, 1, 1, 1, 0.02, 1, "OVERLAY", 7)
            eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); HideCopyPopup() end)
            eb:SetScript("OnKeyDown", function(self, key)
                if key == "C" and IsControlKeyDown() then
                    C_Timer.After(0.05, HideCopyPopup)
                end
            end)
            eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
            copyPopup:EnableMouse(true)
            copyPopup:SetScript("OnMouseDown", function() copyPopup._eb:SetFocus(); copyPopup._eb:HighlightText() end)
            copyPopup._eb = eb
        end
        copyPopup._eb:SetText(text)
        copyPopup:ClearAllPoints()
        copyPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 8)
        copyBackdrop:SetAlpha(0); copyBackdrop:Show(); copyBackdrop._fadeIn:Play()
        copyPopup:SetAlpha(0); copyPopup:Show(); copyPopup._fadeIn:Play()
        copyPopup._eb:SetFocus(); copyPopup._eb:HighlightText()
    end

    titleBtn:SetScript("OnClick", function(self)
        ShowCopyPopup(titleText, self)
    end)

    -- Divider under title
    GetFFD(frame).titleDiv = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    GetFFD(frame).titleDiv:SetColorTexture(1, 1, 1, 0.06)
    GetFFD(frame).titleDiv:SetHeight(1)
    GetFFD(frame).titleDiv:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    GetFFD(frame).titleDiv:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -30)

    -- BattleNet ID bar reskin
    local statusDD = _G.FriendsFrameStatusDropdown
    if statusDD then
        statusDD:SetAlpha(0)
        statusDD:EnableMouse(false)
        statusDD:SetSize(1, 1)
    end

    local bnetFrame = _G.FriendsFrameBattlenetFrame
    if bnetFrame then
        StripTextures(bnetFrame)
        for i = 1, select("#", bnetFrame:GetChildren()) do
            local child = select(i, bnetFrame:GetChildren())
            child:SetAlpha(0)
            child:EnableMouse(false)
        end
        for i = 1, select("#", bnetFrame:GetRegions()) do
            local region = select(i, bnetFrame:GetRegions())
            if region:IsObjectType("FontString") then
                region:SetAlpha(0)
            end
        end
        if bnetFrame.BroadcastFrame then
            local bf = bnetFrame.BroadcastFrame
            bf:SetParent(FriendsFrame)
            bf:SetAlpha(1)
            bf:EnableMouse(true)
            bf:ClearAllPoints()
            bf:SetPoint("TOPLEFT", FriendsFrame, "TOPRIGHT", 5, 0)
        end
        bnetFrame:SetHeight(1)
    end

    -- Player status helper
    local function GetPlayerStatusName()
        local dnd = UnitIsDND("player")
        if not issecretvalue or not issecretvalue(dnd) then
            if dnd then return BUSY or "Busy" end
        end
        local afk = UnitIsAFK("player")
        if not issecretvalue or not issecretvalue(afk) then
            if afk then return AWAY or "Away" end
        end
        return FRIENDS_LIST_ONLINE or "Online"
    end
    GetFFD(frame).getPlayerStatus = GetPlayerStatusName

    -- Custom sub-tabs (Friends/Recent Allies/Recruit A Friend)
    local customSubTabs = {}
    GetFFD(frame).subTabs = customSubTabs
    local function SkinSubTabs()
        local tabHeader = _G.FriendsTabHeader
        if not tabHeader then return end
        local tabSystem = tabHeader.TabSystem
        if not tabSystem then return end

        local blizSubTabs = {}
        for i = 1, select("#", tabSystem:GetChildren()) do
            local st = select(i, tabSystem:GetChildren())
            if st and st:IsObjectType("Button") then
                local text = st:GetFontString()
                local name = text and text:GetText() or ("Tab " .. i)
                blizSubTabs[#blizSubTabs + 1] = { blizTab = st, name = name }
            end
        end

        for _, info in ipairs(blizSubTabs) do
            info.blizTab:SetAlpha(0)
            info.blizTab:SetHeight(1)
            info.blizTab:EnableMouse(false)
        end
        StripTextures(tabHeader)
        if tabSystem then StripTextures(tabSystem) end

        local function UpdateSubTabs()
            local fp3 = EBS.db and EBS.db.profile and EBS.db.profile.friends
            local useAccent = fp3 and fp3.accentColors ~= false
            local ar, ag, ab = EG.r, EG.g, EG.b
            for i, ct in ipairs(customSubTabs) do
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if isSelected then
                    if useAccent then
                        ct._label:SetTextColor(ar, ag, ab, 1)
                    else
                        ct._label:SetTextColor(1, 1, 1, 1)
                    end
                else
                    ct._label:SetTextColor(1, 1, 1, 0.53)
                end
            end
        end
        local function UpdateSubTabWidths()
            for _, ct in ipairs(customSubTabs) do
                local w = ct._label:GetStringWidth() or 40
                ct:SetWidth(w)
            end
        end
        GetFFD(frame).updateSubTabs = function()
            UpdateSubTabWidths()
            UpdateSubTabs()
        end

        local ar, ag, ab = EG.r, EG.g, EG.b
        for i, info in ipairs(blizSubTabs) do
            local ct = CreateFrame("Button", nil, frame)
            ct:SetFrameLevel(frame:GetFrameLevel() + 5)
            ct:SetHeight(20)

            local label = ct:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 11, "")
            label:SetPoint("LEFT", ct, "LEFT", 0, 0)
            label:SetJustifyH("LEFT")
            label:SetText(info.name:match("^(%S+)") or info.name)
            ct._label = label

            ct:SetScript("OnEnter", function()
                local isContacts = (PanelTemplates_GetSelectedTab(FriendsFrame) or 1) == 1
                if not isContacts then return end
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if not isSelected then ct._label:SetTextColor(1, 1, 1, 0.86) end
            end)
            ct:SetScript("OnLeave", function()
                local isContacts = (PanelTemplates_GetSelectedTab(FriendsFrame) or 1) == 1
                if not isContacts then return end
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if isSelected then
                    local fp4 = EBS.db and EBS.db.profile and EBS.db.profile.friends
                    if fp4 and fp4.accentColors ~= false then
                        ct._label:SetTextColor(EG.r, EG.g, EG.b, 1)
                    else
                        ct._label:SetTextColor(1, 1, 1, 1)
                    end
                else
                    ct._label:SetTextColor(1, 1, 1, 0.53)
                end
            end)

            ct:SetScript("OnClick", function()
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if isSelected then return end
                local tabName = info.name or ""
                if strfind(tabName, "Recruit") then
                    -- Let Blizzard show the full RAF page natively.
                    -- Re-enable mouse momentarily so the click registers.
                    if bliz then
                        bliz:EnableMouse(true)
                        bliz:Click()
                        bliz:EnableMouse(false)
                    end
                    _activeSubTab = i
                    UpdateSubTabs()
                    UpdateCustomTabs()
                    return
                else
                    local bottomTab = PanelTemplates_GetSelectedTab(FriendsFrame) or 1
                    if bottomTab ~= 1 then
                        PanelTemplates_SetTab(FriendsFrame, 1)
                        FriendsFrame_Update()
                        UpdateCustomTabs()
                    end
                    if bliz then
                        bliz:EnableMouse(true)
                        bliz:Click()
                        bliz:EnableMouse(false)
                    end
                end
                _activeSubTab = i
                UpdateSubTabs()
                UpdateCustomTabs()
            end)

            ct:SetWidth(60)
            if i == 1 then
                ct:SetPoint("TOPLEFT", FriendsListFrame, "TOPLEFT", 15, -70)
            else
                ct:SetPoint("LEFT", customSubTabs[i - 1], "RIGHT", 20, 0)
            end

            customSubTabs[i] = ct
        end

        -- Extra sub-tab: "Ignored"
        do
            local idx = #customSubTabs + 1
            local ct = CreateFrame("Button", nil, frame)
            ct:SetFrameLevel(frame:GetFrameLevel() + 5)
            ct:SetHeight(20)

            local label = ct:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 11, "")
            label:SetPoint("LEFT", ct, "LEFT", 0, 0)
            label:SetJustifyH("LEFT")
            label:SetText(IGNORE or "Ignored")
            ct._label = label
            ct._label:SetTextColor(1, 1, 1, 0.53)

            ct:SetScript("OnEnter", function()
                ct._label:SetTextColor(1, 1, 1, 0.86)
            end)
            ct:SetScript("OnLeave", function()
                ct._label:SetTextColor(1, 1, 1, 0.53)
            end)
            ct:SetScript("OnClick", function()
                local ilw = FriendsFrame and FriendsFrame.IgnoreListWindow
                if ilw and ilw.ToggleFrame then
                    ilw:ToggleFrame()
                end
            end)

            ct:SetWidth(60)
            ct:SetPoint("LEFT", customSubTabs[idx - 1], "RIGHT", 20, 0)
            customSubTabs[idx] = ct
        end

        -- Status orb
        local lastSubTab = customSubTabs[#customSubTabs]
        if lastSubTab then
            local orbBtn = CreateFrame("Button", nil, frame)
            orbBtn:SetSize(26, 26)
            orbBtn:SetFrameLevel(frame:GetFrameLevel() + 5)
            orbBtn:SetPoint("RIGHT", FriendsListFrame, "TOPRIGHT", -10, -80)
            local orbTex = orbBtn:CreateTexture(nil, "ARTWORK", nil, 2)
            orbTex:SetAllPoints()
            local orbInfo2 = C_Texture.GetAtlasInfo("lootroll-animreveal-a")
            if orbInfo2 then
                orbTex:SetTexture(orbInfo2.file)
                local aL = orbInfo2.leftTexCoord or 0
                local aR = orbInfo2.rightTexCoord or 1
                local aT = orbInfo2.topTexCoord or 0
                local aB = orbInfo2.bottomTexCoord or 1
                local aW, aH = aR - aL, aB - aT
                orbTex:SetTexCoord(aL, aL + aW/6, aT, aT + aH/2)
            end

            local function UpdatePlayerOrb()
                local status = GetPlayerStatusName()
                if status == (BUSY or "Busy") then
                    orbTex:SetVertexColor(1, 0.2, 0.2, 1)
                elseif status == (AWAY or "Away") then
                    orbTex:SetVertexColor(1, 0.8, 0, 1)
                else
                    orbTex:SetVertexColor(0.2, 1, 0.2, 1)
                end
            end
            UpdatePlayerOrb()

            orbBtn:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                local status = GetPlayerStatusName()
                if status == (FRIENDS_LIST_ONLINE or "Online") then
                    SendChatMessage("", "AFK")
                    if BNSetAFK then BNSetAFK(true) end
                elseif status == (AWAY or "Away") then
                    SendChatMessage("", "AFK")
                    SendChatMessage("", "DND")
                    if BNSetAFK then BNSetAFK(false) end
                    if BNSetDND then BNSetDND(true) end
                else
                    SendChatMessage("", "DND")
                    if BNSetDND then BNSetDND(false) end
                    if BNSetAFK then BNSetAFK(false) end
                end
            end)
            orbBtn:SetScript("OnEnter", function(self)
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Status: " .. GetPlayerStatusName() .. "\nClick to change")
                end
            end)
            orbBtn:SetScript("OnLeave", function()
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)

            -- Status changes only repaint the orb, so the listener runs only
            -- while the panel is shown; the Show hook repaints once on open to
            -- catch flag changes made while it was closed.
            local statusEvt = CreateFrame("Frame")
            statusEvt:SetScript("OnEvent", function() UpdatePlayerOrb() end)
            if frame:IsShown() then
                statusEvt:RegisterEvent("PLAYER_FLAGS_CHANGED")
            end
            GetFFD(frame).statusEvt = statusEvt
            GetFFD(frame).updatePlayerOrb = UpdatePlayerOrb

            GetFFD(frame).statusOrb = orbBtn

            -- Broadcast message button
            local bcBtn = CreateFrame("Button", nil, frame)
            bcBtn:SetSize(20, 20)
            bcBtn:SetFrameLevel(orbBtn:GetFrameLevel())
            bcBtn:SetPoint("RIGHT", orbBtn, "LEFT", -2, 0)
            local bcIcon = bcBtn:CreateTexture(nil, "ARTWORK")
            bcIcon:SetAllPoints()
            bcIcon:SetAtlas("voicechat-icon-textchat-silenced")
            bcIcon:SetDesaturated(true)
            bcIcon:SetVertexColor(1, 1, 1)
            bcBtn:SetAlpha(0.6)
            bcBtn:SetScript("OnEnter", function(self)
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Set Status Message")
                end
            end)
            bcBtn:SetScript("OnLeave", function()
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            bcBtn:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                local bf = FriendsFrameBattlenetFrame and FriendsFrameBattlenetFrame.BroadcastFrame
                if not bf then return end
                if bf:IsShown() then bf:Hide() else bf:Show() end
            end)
            GetFFD(frame).broadcastBtn = bcBtn
        end

        if customSubTabs[1] then
            customSubTabs[1]._label:SetTextColor(1, 1, 1, 1)
        end
        C_Timer.After(0.1, UpdateSubTabs)
        C_Timer.After(0.5, UpdateSubTabs)
        hooksecurefunc(frame, "Show", function()
            C_Timer.After(0.1, UpdateSubTabs)
        end)
    end
    SkinSubTabs()

    -- Skin scrollbars. Do NOT register callbacks or setScript
    -- on Blizzard's Scrollbar. This was the taint source
    do
        local bar = FriendsListFrame and FriendsListFrame.ScrollBar
        if bar then
            StripTextures(bar)
            if bar.Background then bar.Background:Hide() end
            -- Collapse arrows to zero height so track fills full length
            if bar.Back then bar.Back:SetAlpha(0); bar.Back:SetSize(1, 0.001) end
            if bar.Forward then bar.Forward:SetAlpha(0); bar.Forward:SetSize(1, 0.001) end
            -- Skin track
            local track = bar.Track
            if track then
                track:DisableDrawLayer("ARTWORK")
                track:DisableDrawLayer("BACKGROUND")
                -- Expand track to fill space left by collapsed arrows
                track:ClearAllPoints()
                track:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
                track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            end
            -- Skin thumb: thin 3px bar
            local thumb = bar.GetThumb and bar:GetThumb()
            if thumb then
                thumb:DisableDrawLayer("ARTWORK")
                thumb:DisableDrawLayer("BACKGROUND")
                local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
                thumbTex:SetColorTexture(1, 1, 1, 0.4)
                thumbTex:SetWidth(3)
                thumbTex:SetPoint("TOP", thumb, "TOP", 0, 0)
                thumbTex:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
                thumbTex:SetPoint("RIGHT", thumb, "RIGHT", 0, 0)
            end
            -- Narrow the scrollbar, shift left 5px and up 2px
            bar:SetWidth(5)
            local p1, rel, p2, ox, oy = bar:GetPoint(1)
            if p1 then
                bar:SetPoint(p1, rel, p2, (ox or 0) - 6, (oy or 0) + 4)
            end
            -- Reduced alpha, full on hover
            bar:SetAlpha(0.6)
            bar:HookScript("OnEnter", function() bar:SetAlpha(0.95) end)
            bar:HookScript("OnLeave", function() bar:SetAlpha(0.6) end)
            if thumb then
                thumb:HookScript("OnEnter", function() bar:SetAlpha(0.95) end)
                thumb:HookScript("OnLeave", function() bar:SetAlpha(0.6) end)
            end
        end
    end


    ---------------------------------------------------------------------------
    --  Search bar with instant dropdown results
    ---------------------------------------------------------------------------
    do -- search bar
        local search = CreateFrame("EditBox", nil, frame)
        search:SetSize(FriendsListFrame:GetWidth() - 30, 20)
        search:SetPoint("TOPLEFT", FriendsListFrame, "TOPLEFT", 15, -40)
        search:SetPoint("TOPRIGHT", FriendsListFrame, "TOPRIGHT", -15, -40)
        search:SetFrameLevel(frame:GetFrameLevel() + 5)
        search:SetAutoFocus(false)
        search:SetMaxLetters(20)
        search:SetJustifyH("LEFT")
        search:SetFont(fontPath, 10, "")
        search:SetTextColor(1, 1, 1, 0.9)

        local sBg = search:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        sBg:SetColorTexture(0, 0, 0, 0.4)
        PP.CreateBorder(search, 1, 1, 1, 0.1, 1, "OVERLAY", 7)

        local sPh = search:CreateFontString(nil, "OVERLAY")
        sPh:SetFont(fontPath, 10, "")
        sPh:SetTextColor(0.5, 0.5, 0.5, 0.6)
        sPh:SetPoint("LEFT", search, "LEFT", 6, 0)
        sPh:SetText("Invite Friend...")

        -- Clear button
        local clearBtn = CreateFrame("Button", nil, search)
        clearBtn:SetSize(14, 14)
        clearBtn:SetPoint("RIGHT", search, "RIGHT", -4, 0)
        clearBtn:SetFrameLevel(search:GetFrameLevel() + 1)
        local clearX = clearBtn:CreateFontString(nil, "OVERLAY")
        clearX:SetFont(fontPath, 11, "")
        clearX:SetText("x")
        clearX:SetTextColor(1, 1, 1, 0.3)
        clearX:SetPoint("CENTER", 0, 0)
        clearBtn:SetScript("OnEnter", function() clearX:SetTextColor(1, 1, 1, 0.7) end)
        clearBtn:SetScript("OnLeave", function() clearX:SetTextColor(1, 1, 1, 0.3) end)
        clearBtn:SetScript("OnClick", function()
            search:SetText("")
            search:ClearFocus()
        end)
        clearBtn:Hide()
        search:SetTextInsets(6, 18, 0, 0)
        search:SetScript("OnEditFocusLost", function(self)
            C_Timer.After(0.15, function()
                if not search:HasFocus() then
                    search:SetText("")
                    clearBtn:Hide()
                end
            end)
        end)

        -- Dropdown results frame
        local dropdown = CreateFrame("Frame", nil, frame)
        dropdown:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -2)
        dropdown:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -2)
        dropdown:SetFrameLevel(frame:GetFrameLevel() + 10)
        dropdown:Hide()

        local ddBg = dropdown:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(0.04, 0.05, 0.06, 0.97)
        PP.CreateBorder(dropdown, 1, 1, 1, 0.15, 1, "OVERLAY", 7)

        -- Accent border flash highlight (matches EUI options panel search flash)
        local _searchHL
        local function GetSearchHL()
            if _searchHL then return _searchHL end
            local hl = CreateFrame("Frame", nil, UIParent)
            hl:SetFrameStrata("HIGH")
            hl:Hide()
            local c = EG
            local function MkEdge()
                local t = hl:CreateTexture(nil, "OVERLAY", nil, 7)
                t:SetColorTexture(c.r, c.g, c.b, 1)
                return t
            end
            hl._top = MkEdge()
            hl._bot = MkEdge()
            hl._lft = MkEdge()
            hl._rgt = MkEdge()
            local ppM = PP.mult or 1
            PP.DisablePixelSnap(hl._top)
            PP.DisablePixelSnap(hl._bot)
            PP.DisablePixelSnap(hl._lft)
            PP.DisablePixelSnap(hl._rgt)
            hl._top:SetHeight(ppM)
            hl._top:SetPoint("TOPLEFT"); hl._top:SetPoint("TOPRIGHT")
            hl._bot:SetHeight(ppM)
            hl._bot:SetPoint("BOTTOMLEFT"); hl._bot:SetPoint("BOTTOMRIGHT")
            hl._lft:SetWidth(ppM)
            hl._lft:SetPoint("TOPLEFT", hl._top, "BOTTOMLEFT")
            hl._lft:SetPoint("BOTTOMLEFT", hl._bot, "TOPLEFT")
            hl._rgt:SetWidth(ppM)
            hl._rgt:SetPoint("TOPRIGHT", hl._top, "BOTTOMRIGHT")
            hl._rgt:SetPoint("BOTTOMRIGHT", hl._bot, "TOPRIGHT")
            _searchHL = hl
            return hl
        end

        local function FlashHighlightOnButton(targetBtn)
            local hl = GetSearchHL()
            -- Position using absolute coords (don't anchor to Blizzard button)
            local left = targetBtn:GetLeft()
            local top = targetBtn:GetTop()
            local right = targetBtn:GetRight()
            local bottom = targetBtn:GetBottom()
            if not left or not top then return end
            local scale = targetBtn:GetEffectiveScale()
            local ovScale = hl:GetEffectiveScale()
            local ratio = scale / ovScale
            hl:ClearAllPoints()
            hl:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * ratio, top * ratio)
            hl:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right * ratio, bottom * ratio)
            hl:SetFrameLevel(20)
            hl:SetAlpha(0)
            hl:Show()
            -- Fade in 0.15s, hold 0.6s, fade out 0.3s
            local elapsed = 0
            local phase = "in"
            hl:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if phase == "in" then
                    if elapsed >= 0.15 then
                        self:SetAlpha(0.8)
                        phase = "hold"
                        elapsed = 0
                    else
                        self:SetAlpha(0.8 * (elapsed / 0.15))
                    end
                elseif phase == "hold" then
                    if elapsed >= 0.6 then
                        phase = "out"
                        elapsed = 0
                    end
                elseif phase == "out" then
                    if elapsed >= 0.3 then
                        self:SetAlpha(0)
                        self:Hide()
                        self:SetScript("OnUpdate", nil)
                    else
                        self:SetAlpha(0.8 * (1 - elapsed / 0.3))
                    end
                end
            end)
        end

        -- Result row pool
        local ROW_H = 24
        local MAX_RESULTS = 8
        local resultRows = {}

        local function GetResultRow(idx)
            if resultRows[idx] then return resultRows[idx] end
            local row = CreateFrame("Button", nil, dropdown)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 1, -1 - (idx - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1, -1 - (idx - 1) * ROW_H)

            local hover = row:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.06)

            local nameFS = row:CreateFontString(nil, "OVERLAY")
            nameFS:SetFont(fontPath, 11, "")
            nameFS:SetPoint("LEFT", row, "LEFT", 8, 0)
            nameFS:SetWidth((FriendsListFrame:GetWidth() - 30) * 0.75)
            nameFS:SetJustifyH("LEFT")
            nameFS:SetWordWrap(false)
            row._name = nameFS

            local infoFS = row:CreateFontString(nil, "OVERLAY")
            infoFS:SetFont(fontPath, 9, "")
            infoFS:SetTextColor(0.5, 0.5, 0.5, 0.8)
            infoFS:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            infoFS:SetJustifyH("RIGHT")
            row._info = infoFS

            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:SetScript("OnClick", function(_, mouseBtn)
                local targetType = row._matchType
                local targetId = row._matchId
                local cached = row._cached

                -- Invite to group
                if cached and targetType == FRIENDS_BUTTON_TYPE_BNET then
                    if cached.gameAccountInfo and cached.gameAccountInfo.isOnline then
                        local charName = cached.gameAccountInfo.characterName
                        local realmName = cached.gameAccountInfo.realmName
                        if charName then
                            local fullName = realmName and realmName ~= "" and (charName .. "-" .. realmName) or charName
                            C_PartyInfo.InviteUnit(fullName)
                        end
                    end
                elseif cached and targetType == FRIENDS_BUTTON_TYPE_WOW then
                    if cached.name and cached.connected then
                        C_PartyInfo.InviteUnit(cached.name)
                    end
                end
                search:SetText("")
                search:ClearFocus()
            end)

            resultRows[idx] = row
            return row
        end

        local function UpdateDropdown(term)
            if term == "" then dropdown:Hide(); return end

            -- Search through cache for matches
            local matches = {}
            for key, info in pairs(_friendCache) do
                if key <= _FC_WOW_OFFSET then
                    -- BNet friend
                    local btag = (info.battleTag or ""):lower()
                    local acctName = (info.accountName or ""):lower()
                    local charName = ""
                    if info.gameAccountInfo and info.gameAccountInfo.characterName then
                        charName = info.gameAccountInfo.characterName:lower()
                    end
                    local areaName = ""
                    if info.gameAccountInfo and info.gameAccountInfo.areaName then
                        areaName = info.gameAccountInfo.areaName:lower()
                    end
                    if strfind(btag, term, 1, true) or strfind(acctName, term, 1, true) or strfind(charName, term, 1, true) or strfind(areaName, term, 1, true) then
                        local displayName = info.accountName or info.battleTag or ""
                        local charDisplay = info.gameAccountInfo and info.gameAccountInfo.characterName or ""
                        local areaDisplay = info.gameAccountInfo and info.gameAccountInfo.areaName or ""
                        local isOnline = info.gameAccountInfo and info.gameAccountInfo.isOnline
                        local classFile = GetFriendClassFile(info, nil)
                        matches[#matches + 1] = {
                            buttonType = FRIENDS_BUTTON_TYPE_BNET,
                            id = key,
                            display = displayName,
                            char = charDisplay,
                            area = areaDisplay,
                            online = isOnline,
                            classFile = classFile,
                            sortName = btag,
                        }
                    end
                else
                    -- WoW friend
                    local wowId = key - _FC_WOW_OFFSET
                    local name = (info.name or ""):lower()
                    if strfind(name, term, 1, true) then
                        local classFile = GetFriendClassFile(nil, info)
                        matches[#matches + 1] = {
                            buttonType = FRIENDS_BUTTON_TYPE_WOW,
                            id = wowId,
                            display = info.name or "",
                            char = "",
                            online = info.connected,
                            classFile = classFile,
                            sortName = name,
                        }
                    end
                end
            end

            if #matches == 0 then dropdown:Hide(); return end

            -- Sort: online first, then alpha
            table.sort(matches, function(a, b)
                if a.online ~= b.online then return a.online end
                return a.sortName < b.sortName
            end)

            -- Find DataProvider index for each match
            local sb = FriendsListFrame and FriendsListFrame.ScrollBox
            local dp = sb and sb:GetDataProvider()

            local shown = math.min(#matches, MAX_RESULTS)
            for i = 1, shown do
                local m = matches[i]
                local row = GetResultRow(i)
                local nameText = m.display
                if m.online then
                    -- Class-color the character name portion, append zone
                    local areaSuffix = (m.area and m.area ~= "") and (" |cff888888- " .. m.area .. "|r") or ""
                    if m.classFile and m.char ~= "" then
                        local cc = _getClassColorCode(m.classFile)
                        if cc then
                            nameText = nameText .. " (" .. cc .. m.char .. "|r)" .. areaSuffix
                        else
                            nameText = nameText .. " (" .. m.char .. ")" .. areaSuffix
                        end
                    elseif m.char ~= "" then
                        nameText = nameText .. " |cff888888(" .. m.char .. ")|r" .. areaSuffix
                    end
                    local bnc = FRIENDS_BNET_NAME_COLOR or { r = 0.510, g = 0.773, b = 1.0 }
                    row._name:SetTextColor(bnc.r, bnc.g, bnc.b)
                else
                    if m.char ~= "" then
                        nameText = nameText .. " |cff555555(" .. m.char .. ")|r"
                    end
                    row._name:SetTextColor(0.5, 0.5, 0.5)
                end
                row._name:SetText(nameText)
                row._info:SetText(m.online and "|cff33ff33Online|r" or "|cff666666Offline|r")

                row._matchType = m.buttonType
                row._matchId = m.id
                -- Store cached data for whisper/invite
                if m.buttonType == FRIENDS_BUTTON_TYPE_BNET then
                    row._cached = _friendCache[m.id]
                else
                    row._cached = _friendCache[m.id + _FC_WOW_OFFSET]
                end
                -- Find index in DataProvider
                row._dpIndex = nil
                if dp then
                    local idx = 0
                    for _, ed in dp:Enumerate() do
                        idx = idx + 1
                        if ed.buttonType == m.buttonType and ed.id == m.id then
                            row._dpIndex = idx
                            break
                        end
                    end
                end
                row:Show()
            end

            -- Hide unused rows
            for i = shown + 1, #resultRows do
                resultRows[i]:Hide()
            end

            dropdown:SetHeight(shown * ROW_H + 2)
            dropdown:Show()
        end

        search:SetScript("OnTextChanged", function(self)
            local t = strtrim(self:GetText())
            sPh:SetShown(t == "")
            clearBtn:SetShown(t ~= "")
            UpdateDropdown(t:lower())
        end)
        search:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
        end)
        search:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)

        GetFFD(frame).searchBox = search
        GetFFD(frame).searchDropdown = dropdown
    end -- if false

    ---------------------------------------------------------------------------
    --  Button skinning: hook Blizzard's per-button update so we re-apply
    --  class colors immediately after Blizzard resets them.  Originally
    --  avoided (blamed for BNet whisper taint), but the real taint source
    --  was frame property writes -- fixed in the FFD refactor (session 58).
    --  This hook only reads button data and calls SetTextColor (safe).
    ---------------------------------------------------------------------------
    if FriendsFrame_UpdateFriendButton then
        hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button)
            if not button or not button.buttonType then return end
            if button.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then return end
            local fd = GetFFD(button)
            fd.stampType = nil
        end)
    end

    -- Scroll position poller: detects scroll changes (drag, keyboard, etc.)
    -- without touching Blizzard's ScrollBar/ScrollBox at all. Just reads
    -- GetScrollPercentage and debounces ProcessFriendButtons.
    do
        local scrollPoller = CreateFrame("Frame", nil, frame)
        scrollPoller:Hide()
        scrollPoller:SetScript("OnUpdate", function()
            local sb = FriendsListFrame and FriendsListFrame.ScrollBox
            if not sb then return end
            -- Only re-skin if a recycled button shows different data than its stamp
            local needsSkin = false
            for _, btn in sb:EnumerateFrames() do
                if btn.buttonType and btn.buttonType ~= FRIENDS_BUTTON_TYPE_DIVIDER then
                    local fd = GetFFD(btn)
                    if fd.stampType ~= btn.buttonType or fd.stampId ~= (btn.id or 0) then
                        needsSkin = true
                        break
                    end
                end
            end
            if needsSkin then
                ProcessFriendButtons()
            end
        end)
        hooksecurefunc(frame, "Show", function() scrollPoller:Show() end)
        hooksecurefunc(frame, "Hide", function() scrollPoller:Hide(); _pollLastPct = -1 end)
        if frame:IsShown() then scrollPoller:Show() end
    end

    -- Sync tab labels with Blizzard's tab text
    local function SyncFriendsTabLabels()
        for i = 1, (FriendsFrame and FriendsFrame.numTabs) or 4 do
            local tab = _G["FriendsFrameTab" .. i]
            if tab then
                local tfd = GetFFD(tab)
                if tfd.label then
                    local bliz = tab:GetFontString()
                    local txt = bliz and bliz:GetText()
                    if txt then tfd.label:SetText(txt) end
                end
            end
        end
    end

    -- Deferred skinning: sets a dirty flag, processed on next frame via OnUpdate.
    -- This ensures we NEVER run addon code inside Blizzard's secure dispatch.
    local _skinDirty = false
    local skinDriver = CreateFrame("Frame")
    skinDriver:Hide()
    skinDriver:SetScript("OnUpdate", function(self)
        self:Hide()
        _skinDirty = false
        if FriendsFrame:IsShown() then
            ProcessFriendButtons()
        end
    end)
    local function MarkSkinDirty()
        if not _skinDirty then
            _skinDirty = true
            skinDriver:Show()
        end
    end

    -- Friend events: refresh cache, mark dirty for deferred restyle
    local friendsEventFrame = CreateFrame("Frame")
    friendsEventFrame:SetScript("OnEvent", function(_, event)
        RefreshFriendCache()
        -- Clear stamps so buttons get restyled with fresh data
        local sb = FriendsListFrame and FriendsListFrame.ScrollBox
        if sb then
            for _, btn in sb:EnumerateFrames() do
                GetFFD(btn).stampType = nil
            end
        end
        SyncFriendsTabLabels()
        MarkSkinDirty()
    end)
    -- Re-skin after scrolling (HookScript is a post-hook, safe)
    if FriendsListFrame and FriendsListFrame.ScrollBox then
        FriendsListFrame.ScrollBox:HookScript("OnMouseWheel", function()
            MarkSkinDirty()
        end)
    end

    local function RegisterFriendsEvents()
        friendsEventFrame:RegisterEvent("FRIENDLIST_UPDATE")
        friendsEventFrame:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
        friendsEventFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")
        friendsEventFrame:RegisterEvent("BN_FRIEND_INVITE_ADDED")
        friendsEventFrame:RegisterEvent("BN_FRIEND_INVITE_REMOVED")
    end
    local function UnregisterFriendsEvents()
        friendsEventFrame:UnregisterAllEvents()
    end
    if FriendsFrame:IsShown() then RegisterFriendsEvents() end

    -- Auto-accept group invites from friends
    local _autoAcceptHideStatic = false
    -- GROUP_ROSTER_UPDATE is armed only between an auto-accept and its popup
    -- cleanup; the branch below never did anything outside that window.
    local autoAcceptFrame = CreateFrame("Frame")
    autoAcceptFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    autoAcceptFrame:SetScript("OnEvent", function(self, event, _, _, _, _, _, _, inviterGUID)
        if event == "PARTY_INVITE_REQUEST" then
            local fp5 = EBS.db and EBS.db.profile and EBS.db.profile.friends
            if not fp5 or not fp5.autoAcceptFriendInvites then return end
            if not inviterGUID or inviterGUID == "" or IsInGroup() then return end
            local isFriend = false
            if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
                isFriend = C_BattleNet.GetGameAccountInfoByGUID(inviterGUID) ~= nil
            end
            if not isFriend and C_FriendList and C_FriendList.IsFriend then
                isFriend = C_FriendList.IsFriend(inviterGUID)
            end
            if not isFriend and fp5.autoAcceptGuildInvites then
              isFriend = IsGuildMember(inviterGUID)
            end
            if isFriend then
                AcceptGroup()
                _autoAcceptHideStatic = true
                self:RegisterEvent("GROUP_ROSTER_UPDATE")
            end
        elseif event == "GROUP_ROSTER_UPDATE" and _autoAcceptHideStatic then
            _autoAcceptHideStatic = false
            self:UnregisterEvent("GROUP_ROSTER_UPDATE")
            StaticPopup_Hide("PARTY_INVITE")
            if LFGInvitePopup then
                StaticPopupSpecial_Hide(LFGInvitePopup)
            end
        end
    end)

    -- Show/Hide hooks
    hooksecurefunc(frame, "Hide", function()
        UnregisterFriendsEvents()
        local fd = GetFFD(frame)
        if fd.statusEvt then fd.statusEvt:UnregisterAllEvents() end
    end)
    hooksecurefunc(frame, "Show", function()
        RegisterFriendsEvents()
        RefreshFriendCache()
        MarkSkinDirty()
        local fd = GetFFD(frame)
        if fd.statusEvt then
            fd.statusEvt:RegisterEvent("PLAYER_FLAGS_CHANGED")
            if fd.updatePlayerOrb then fd.updatePlayerOrb() end
        end
    end)

    ---------------------------------------------------------------------------
    --  Skin Who / Raid / Quick Join tabs
    ---------------------------------------------------------------------------
    local function StripFrameChrome(f)
        if not f then return end
        StripTextures(f)
        if f.NineSlice then f.NineSlice:Hide() end
        if f.Bg then f.Bg:Hide() end
        if f.Inset then
            StripTextures(f.Inset)
            if f.Inset.NineSlice then f.Inset.NineSlice:Hide() end
            if f.Inset.Bg then f.Inset.Bg:Hide() end
        end
    end

    -- Who tab
    do
        local who = WhoFrame
        if who then
            StripFrameChrome(who)
            who:ClearAllPoints()
            who:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, 0)
            who:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -11, 0)

            local whoInset = _G.WhoFrameListInset
            if whoInset then
                StripTextures(whoInset)
                if whoInset.Bg then whoInset.Bg:Hide() end
                if whoInset.NineSlice then
                    StripTextures(whoInset.NineSlice)
                    whoInset.NineSlice:Hide()
                end
                whoInset:SetClipsChildren(true)
                whoInset:ClearAllPoints()
                whoInset:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -92)
                whoInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)
                local whoBg = whoInset:CreateTexture(nil, "BACKGROUND", nil, -5)
                whoBg:SetAllPoints()
                whoBg:SetColorTexture(0, 0.08, 0.10, 0.35)
                PP.CreateBorder(whoInset, 1, 1, 1, 0.1, 1, "OVERLAY", 5)
            end

            for i = 1, 4 do
                local col = _G["WhoFrameColumnHeader" .. i]
                if col then
                    hooksecurefunc(col, "SetPoint", function(self)
                        if GetFFD(self).adjusting then return end
                        GetFFD(self).adjusting = true
                        local p1, rel, p2, x, y = self:GetPoint(1)
                        if p1 then
                            self:ClearAllPoints()
                            local xOff = (i == 1) and 5 or 0
                            self:SetPoint(p1, rel, p2, (x or 0) + xOff, (y or 0) + 10)
                        end
                        GetFFD(self).adjusting = false
                    end)
                end
            end

            local col1 = _G["WhoFrameColumnHeader1"]
            local whoInset2 = _G.WhoFrameListInset
            if col1 and whoInset2 then
                local headerBg = who:CreateTexture(nil, "BACKGROUND", nil, -6)
                headerBg:SetPoint("TOPLEFT", col1, "TOPLEFT", 0, 0)
                headerBg:SetPoint("RIGHT", whoInset2, "RIGHT", 0, 0)
                headerBg:SetHeight(col1:GetHeight())
                headerBg:SetColorTexture(0, 0, 0, 0.3)
            end

            for i = 1, 4 do
                local col = _G["WhoFrameColumnHeader" .. i]
                if col then
                    StripTextures(col)
                    local text = col:GetFontString()
                    if text then
                        text:SetFont(fontPath, 10, "")
                        text:SetTextColor(1, 1, 1, 0.5)
                    end
                    col:SetClipsChildren(true)
                    local hlTex = col:CreateTexture(nil, "HIGHLIGHT")
                    local nextCol = _G["WhoFrameColumnHeader" .. (i + 1)]
                    if nextCol then
                        hlTex:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
                        hlTex:SetPoint("BOTTOMRIGHT", nextCol, "BOTTOMLEFT", 0, 0)
                    else
                        local whoInset3 = _G.WhoFrameListInset
                        if whoInset3 then
                            hlTex:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
                            hlTex:SetPoint("BOTTOM", col, "BOTTOM", 0, 0)
                            hlTex:SetPoint("RIGHT", whoInset3, "RIGHT", 0, 0)
                        else
                            hlTex:SetAllPoints()
                        end
                    end
                    hlTex:SetColorTexture(1, 1, 1, 0.1)
                    hlTex:SetBlendMode("ADD")
                    if i > 1 then
                        local div = col:CreateTexture(nil, "OVERLAY", nil, 7)
                        PP.DisablePixelSnap(div)
                        div:SetWidth(PP.mult or 1)
                        div:SetColorTexture(1, 1, 1, 0.1)
                        div:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -2)
                        div:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, 2)
                    end
                end
            end

            local zoneDropdown = _G.WhoFrameDropdown
            if zoneDropdown then
                zoneDropdown:SetAlpha(0)
                zoneDropdown:SetSize(1, 1)
                zoneDropdown:EnableMouse(false)
                zoneDropdown:ClearAllPoints()
                zoneDropdown:SetPoint("TOPLEFT", who, "TOPLEFT", 0, 0)
            end

            local editBox = _G.WhoFrameEditBox
            if editBox then
                StripTextures(editBox)
                editBox:SetScale(0.9)
                local p1, rel, p2, ox, oy = editBox:GetPoint(1)
                if p1 then
                    editBox:SetPoint(p1, rel, p2, (ox or 0) - 1, (oy or 0) + 3)
                end
                local ebBg = editBox:CreateTexture(nil, "BACKGROUND", nil, -6)
                ebBg:SetColorTexture(0, 0, 0, 0.4)
                ebBg:SetAllPoints()
                editBox:SetTextColor(1, 1, 1, 0.8)
                PP.CreateBorder(editBox, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
            end

            local totalCount = _G.WhoFrameTotals
            if totalCount and totalCount.SetFont then
                totalCount:SetFont(fontPath, 10, "")
                totalCount:SetTextColor(1, 1, 1, 0.5)
            end

            local whoInsetRef = _G.WhoFrameListInset
            local whoBtnNames = {"WhoFrameWhoButton", "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton"}
            if whoInsetRef then
                local function LayoutWhoBtns()
                    local totalW2 = whoInsetRef:GetWidth()
                    local btnW = math.floor(totalW2 / 3)
                    local btnY = -22 - 10 + 10
                    local btns = {}
                    for _, name in ipairs(whoBtnNames) do
                        btns[#btns + 1] = _G[name]
                    end
                    if btns[1] then
                        btns[1]:ClearAllPoints()
                        btns[1]:SetSize(btnW, 22)
                        btns[1]:SetPoint("BOTTOMLEFT", whoInsetRef, "BOTTOMLEFT", 0, btnY)
                    end
                    if btns[2] then
                        btns[2]:ClearAllPoints()
                        btns[2]:SetSize(btnW, 22)
                        btns[2]:SetPoint("BOTTOMLEFT", whoInsetRef, "BOTTOMLEFT", btnW, btnY)
                    end
                    if btns[3] then
                        btns[3]:ClearAllPoints()
                        btns[3]:SetSize(btnW, 22)
                        btns[3]:SetPoint("BOTTOMRIGHT", whoInsetRef, "BOTTOMRIGHT", 0, btnY)
                    end
                end
                for _, name in ipairs(whoBtnNames) do
                    local btn = _G[name]
                    if btn then
                        SkinBottomButton(btn)
                        hooksecurefunc(btn, "Disable", function(self) self:SetAlpha(0.4) end)
                        hooksecurefunc(btn, "Enable", function(self) self:SetAlpha(1) end)
                        if not btn:IsEnabled() then btn:SetAlpha(0.4) end
                    end
                end
                LayoutWhoBtns()
                who:HookScript("OnShow", LayoutWhoBtns)
            end

            local function SkinWhoRows()
                for i = 1, 22 do
                    local btn = _G["WhoFrameButton" .. i]
                    if btn and not GetFFD(btn).skinned then
                        GetFFD(btn).skinned = true
                        StripTextures(btn)
                        local hover2 = btn:CreateTexture(nil, "HIGHLIGHT")
                        hover2:SetAllPoints()
                        hover2:SetColorTexture(1, 1, 1, 0.04)
                        hover2:SetBlendMode("ADD")
                        for _, key in ipairs({"Name", "Level", "Class", "Variable"}) do
                            local txt = _G["WhoFrameButton" .. i .. key]
                            if txt and txt.SetFont then
                                txt:SetFont(fontPath, 11, "")
                            end
                        end
                    end
                end
            end
            SkinWhoRows()
            who:HookScript("OnShow", SkinWhoRows)

            local sb = who.ScrollBox or (who.scrollFrame)
            if sb then
                local p1, rel, p2, x, y = sb:GetPoint(1)
                if p1 then
                    sb:SetPoint(p1, rel, p2, (x or 0) + 5, (y or 0) - 35)
                end
            end

            who:ClearAllPoints()
            who:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -10)
            who:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -11, 10)

            if col1 then
                col1:ClearAllPoints()
                col1:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -102)
            end

            local bar = sb and (sb.ScrollBar or who.ScrollBar) or who.ScrollBar
            if sb and bar then SkinOneScrollbar(sb, bar) end
        end
    end

    -- Quick Join tab
    do
        local qjf = _G.QuickJoinFrame
        if qjf then
            local qjScroll = qjf.ScrollBox or (qjf.List and qjf.List.ScrollBox)
            if qjScroll then
                qjScroll:ClearAllPoints()
                qjScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -92)
                qjScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)

                if not GetFFD(qjScroll).borderAdded then
                    GetFFD(qjScroll).borderAdded = true
                    local bdr = CreateFrame("Frame", nil, qjf)
                    bdr:SetPoint("TOPLEFT", qjScroll, "TOPLEFT", 0, 0)
                    bdr:SetPoint("BOTTOMRIGHT", qjScroll, "BOTTOMRIGHT", 0, 0)
                    bdr:SetFrameLevel(qjScroll:GetFrameLevel() + 2)
                    PP.CreateBorder(bdr, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
                end

                local qjBar = qjScroll.ScrollBar or (qjf.List and qjf.List.ScrollBar) or qjf.ScrollBar
                if qjBar then
                    SkinOneScrollbar(qjScroll, qjBar)
                end
            end

            local joinBtn = qjf.JoinQueueButton
            if joinBtn and qjScroll then
                SkinBottomButton(joinBtn)
                joinBtn:ClearAllPoints()
                local totalW3 = qjScroll:GetWidth()
                local btnW = math.floor(totalW3 / 3)
                joinBtn:SetSize(btnW, 22)
                joinBtn:SetPoint("BOTTOMRIGHT", qjScroll, "BOTTOMRIGHT", 0, -22)
            end
        end
    end

    -- Friends list area: border + background via our own frame.
    -- NEVER reference FriendsListFrame.ScrollBox (even as anchor) -- any
    -- interaction with Blizzard's ScrollBox taints BNet whisper processing.
    if not GetFFD(frame).listOverlay then
        local overlay = CreateFrame("Frame", nil, frame)
        overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -92)
        overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)
        overlay:SetFrameLevel(frame:GetFrameLevel() + 1)
        local sbBg = overlay:CreateTexture(nil, "BACKGROUND", nil, -8)
        sbBg:SetAllPoints()
        sbBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
        GetFFD(frame).listOverlay = overlay

        local bdr = CreateFrame("Frame", nil, frame)
        bdr:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -92)
        bdr:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)
        bdr:SetFrameLevel(frame:GetFrameLevel() + 3)
        PP.CreateBorder(bdr, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
        GetFFD(frame).listBdr = bdr
    end

    -- Bottom buttons: strip + font + reposition (anchored to frame, not ScrollBox)
    SkinRaidTab()
    do
        local BTN_H = 22
        local btnFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("friends") or STANDARD_TEXT_FONT
        local addBtn = _G.FriendsFrameAddFriendButton
        local msgBtn = _G.FriendsFrameSendMessageButton
        local fp8 = EBS.db and EBS.db.profile and EBS.db.profile.friends
        local btnAccent = fp8 and fp8.accentColors ~= false
        for _, btn in ipairs({addBtn, msgBtn}) do
            if btn then
                StripTextures(btn)
                local text = btn:GetFontString()
                if text then
                    text:SetFont(btnFont, 9, "")
                    if btn == msgBtn and btnAccent then
                        text:SetTextColor(EG.r, EG.g, EG.b, 0.7)
                    else
                        text:SetTextColor(1, 1, 1, 0.5)
                    end
                end
            end
        end
        if addBtn and msgBtn then
            local BTN_GAP = 10
            local btnY = -BTN_H - BTN_GAP + 10

            -- Fake border overlays (our own frames, border only, no background)
            local addBdr = CreateFrame("Frame", nil, frame)
            addBdr:SetFrameLevel(frame:GetFrameLevel() + 3)
            PP.CreateBorder(addBdr, 1, 1, 1, 0.4, 1, "OVERLAY", 7)
            GetFFD(frame).addBdr = addBdr

            local msgBdr = CreateFrame("Frame", nil, frame)
            msgBdr:SetFrameLevel(frame:GetFrameLevel() + 3)
            local fp7 = EBS.db and EBS.db.profile and EBS.db.profile.friends
            local useAccent = fp7 and fp7.accentColors ~= false
            if useAccent then
                PP.CreateBorder(msgBdr, EG.r, EG.g, EG.b, 0.5, 1, "OVERLAY", 7)
            else
                PP.CreateBorder(msgBdr, 1, 1, 1, 0.4, 1, "OVERLAY", 7)
            end
            GetFFD(frame).msgBdr = msgBdr

            local function LayoutFriendBtns()
                local totalW4 = frame:GetWidth() - 30
                local btnW = math.floor(totalW4 / 3)
                addBtn:ClearAllPoints()
                addBtn:SetSize(btnW, BTN_H)
                addBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 35 + btnY)
                msgBtn:ClearAllPoints()
                msgBtn:SetSize(btnW, BTN_H)
                msgBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35 + btnY)
                -- Position border overlays to match
                addBdr:ClearAllPoints()
                addBdr:SetAllPoints(addBtn)
                msgBdr:ClearAllPoints()
                msgBdr:SetAllPoints(msgBtn)
            end
            LayoutFriendBtns()
            hooksecurefunc(frame, "Show", LayoutFriendBtns)
        end
    end

    -- Position custom tabs below the frame
    local TAB_H = 26
    local numCustomTabs = #customTabs
    if numCustomTabs > 0 then
        local m = PP.mult or 1
        local function pxSnap(x)
            if m == 1 then return x end
            return math.floor(x / m + 0.5) * m
        end
        local snappedTabH = pxSnap(TAB_H)
        local onePx = m
        local lastCT

        local TAB_WIDTHS = { 0.22, 0.22, 0.22, 0.34 }
        local frameW = frame:GetWidth() or 300
        for i, ct in ipairs(customTabs) do
            ct:ClearAllPoints()
            ct:SetHeight(snappedTabH)
            if i == 1 then
                ct:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
            else
                ct:SetPoint("TOPLEFT", customTabs[i - 1], "TOPRIGHT", 0, 0)
            end
            if i == numCustomTabs then
                ct:SetPoint("RIGHT", frame, "BOTTOMRIGHT", 0, 0)
            else
                ct:SetWidth(frameW * (TAB_WIDTHS[i] or 0.25))
            end

            if i > 1 then
                local ctd = GetFFD(ct)
                if not ctd.div then
                    ctd.div = ct:CreateTexture(nil, "OVERLAY", nil, 7)
                    PP.DisablePixelSnap(ctd.div)
                end
                ctd.div:SetColorTexture(1, 1, 1, 0.08)
                ctd.div:SetSize(onePx, snappedTabH)
                ctd.div:ClearAllPoints()
                ctd.div:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, 0)
            end
            lastCT = ct
        end

        if GetFFD(frame).tabBarBg and lastCT then
            GetFFD(frame).tabBarBg:SetParent(customTabs[1])
            GetFFD(frame).tabBarBg:ClearAllPoints()
            GetFFD(frame).tabBarBg:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
            GetFFD(frame).tabBarBg:SetPoint("BOTTOMRIGHT", lastCT, "BOTTOMRIGHT", 0, 0)
            GetFFD(frame).tabBarBg:SetDrawLayer("BACKGROUND", -8)
        end

        if not GetFFD(frame).tabTopBorder then
            GetFFD(frame).tabTopBorder = customTabs[1]:CreateTexture(nil, "OVERLAY", nil, 7)
            PP.DisablePixelSnap(GetFFD(frame).tabTopBorder)
            GetFFD(frame).tabTopBorder:SetColorTexture(1, 1, 1, 0.08)
            GetFFD(frame).tabTopBorder:SetHeight(onePx)
            GetFFD(frame).tabTopBorder:ClearAllPoints()
            GetFFD(frame).tabTopBorder:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
            GetFFD(frame).tabTopBorder:SetPoint("TOPRIGHT", lastCT, "TOPRIGHT", 0, 0)
        end

        UpdateCustomTabs()
    end

    -- Close button
    local closeBtn = frame.CloseButton or _G.FriendsFrameCloseButton
    if closeBtn then
        StripTextures(closeBtn)
        GetFFD(closeBtn).x = closeBtn:CreateFontString(nil, "OVERLAY")
        GetFFD(closeBtn).x:SetFont(fontPath, 14, "")
        GetFFD(closeBtn).x:SetText("x")
        GetFFD(closeBtn).x:SetTextColor(1, 1, 1, 0.5)
        GetFFD(closeBtn).x:SetPoint("CENTER", -2, -3)
        closeBtn:HookScript("OnEnter", function()
            GetFFD(closeBtn).x:SetTextColor(1, 1, 1, 0.9)
        end)
        closeBtn:HookScript("OnLeave", function()
            GetFFD(closeBtn).x:SetTextColor(1, 1, 1, 0.5)
        end)
    end

    C_Timer.After(0, UpdateCustomTabs)
end

-- Live updates: colors, border, opacity
local function ApplyFriends()
    if LegacyFriendsRetired() then return end
    local _mplus = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()
    local _, _iT = IsInInstance()
    local _pvp = (_iT == "pvp" or _iT == "arena")
    if InCombatLockdown() or _mplus or _pvp then QueueApplyAll(); return end

    local p = EBS.db.profile.friends
    p.enabled = true

    if not p.enabled then
        return
    end

    if not FriendsFrame then return end
    SkinFriendsFrame()

    -- Update border size and colors
    local r, g, b, a = GetBorderColor(p)
    local bs = p.borderSize or 1
    if bs > 0 then
        PP.UpdateBorder(FriendsFrame, bs, r, g, b, a)
    else
        PP.SetBorderColor(FriendsFrame, r, g, b, 0)
    end
    if GetFFD(FriendsFrame).bg then
        GetFFD(FriendsFrame).bg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
        GetFFD(FriendsFrame).bg:SetAlpha(1)
    end
    if GetFFD(FriendsFrame).tabBarBg then
        GetFFD(FriendsFrame).tabBarBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
        GetFFD(FriendsFrame).tabBarBg:SetAlpha(1)
    end

    -- Update tile backgrounds on visible buttons
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if scrollBox then
        for _, button in scrollBox:EnumerateFrames() do
            if GetFFD(button).tileBg then
                GetFFD(button).tileBg:SetColorTexture(0, 0, 0, 0.10)
            end
        end
    end

    -- Apply accent colors
    UpdateBottomButtonAccent()
    UpdateRaidTabButtonAccent()
    if GetFFD(FriendsFrame).updateCustomTabs then GetFFD(FriendsFrame).updateCustomTabs() end
    if GetFFD(FriendsFrame).updateSubTabs then GetFFD(FriendsFrame).updateSubTabs() end

    if GetFFD(FriendsFrame).applyScaleAndPosition then
        GetFFD(FriendsFrame).applyScaleAndPosition()
    end
end

-------------------------------------------------------------------------------
--  Visibility
-------------------------------------------------------------------------------
local function UpdateFriendsVisibility()
    if LegacyFriendsRetired() then return end
    local p = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not p or not p.enabled then return end
    if not FriendsFrame or not FriendsFrame:IsShown() then return end
    local vis = EllesmereUI.EvalVisibility(p)
    if vis == "mouseover" then
        FriendsFrame:SetAlpha(0)
    else
        FriendsFrame:SetAlpha(vis and 1 or 0)
    end
end

-------------------------------------------------------------------------------
--  Apply All
-------------------------------------------------------------------------------
ApplyAll = function()
    ApplyFriends()
    if EllesmereUI.RequestVisibilityUpdate then
        C_Timer.After(0, EllesmereUI.RequestVisibilityUpdate)
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function EBS:OnInitialize()
    EBS.db = EllesmereUI.Lite.NewDB("EllesmereUIFriendsDB", defaults)

    -- Global bridge for options <-> main communication
    _G._EFR_DB                   = EBS.db
    _G._EFR_ApplyFriends         = ApplyFriends
    _G._EFR_ProcessFriendButtons = ProcessFriendButtons

    -- Register the visibility updater + mouseover target only while the
    -- panel is shown. Both registries invoke our closures on this addon's
    -- time (the dispatcher fan-out on every visibility event, the shared
    -- mouseover scan every 0.15s), and with the panel closed both calls are
    -- provable no-ops: the updater early-outs on IsShown and the proxy has
    -- no rect. A closed friends list must cost nothing.
    local visProxy
    if EllesmereUI.RegisterMouseoverTarget then
        visProxy = CreateFrame("Frame")
        visProxy.IsShown     = function() return FriendsFrame and FriendsFrame:IsShown() end
        visProxy.IsMouseOver = function() return FriendsFrame and FriendsFrame:IsMouseOver() end
        visProxy.SetAlpha    = function(_, a2) if FriendsFrame then FriendsFrame:SetAlpha(a2) end end
    end
    local function VisWantsHover()
        local p2 = EBS.db and EBS.db.profile and EBS.db.profile.friends
        if not (p2 and p2.enabled) then return false end
        -- Hover-gated sets only reveal while their conditions pass
        return EllesmereUI.VisWantsMouseover(p2, "visibility")
    end
    local visRegistered = false
    local function RegisterVis()
        if visRegistered then return end
        visRegistered = true
        if EllesmereUI.RegisterVisibilityUpdater then
            EllesmereUI.RegisterVisibilityUpdater(UpdateFriendsVisibility)
        end
        if visProxy then
            EllesmereUI.RegisterMouseoverTarget(visProxy, VisWantsHover)
        end
    end
    local function UnregisterVis()
        if not visRegistered then return end
        visRegistered = false
        if EllesmereUI.UnregisterVisibilityUpdater then
            EllesmereUI.UnregisterVisibilityUpdater(UpdateFriendsVisibility)
        end
        if visProxy and EllesmereUI.UnregisterMouseoverTarget then
            EllesmereUI.UnregisterMouseoverTarget(visProxy)
        end
    end
    if FriendsFrame then
        hooksecurefunc(FriendsFrame, "Show", RegisterVis)
        hooksecurefunc(FriendsFrame, "Hide", UnregisterVis)
        if FriendsFrame:IsShown() then RegisterVis() end
    else
        -- Frame not created yet (12.1 load-on-demand Social UI): keep the
        -- always-registered behavior; both closures early-out safely there.
        RegisterVis()
    end
end

function EBS:OnEnable()
    ApplyAll()

    -- Live accent color update: re-apply friends skin when accent changes
    if EllesmereUI._accentElements then
        EllesmereUI._accentElements[#EllesmereUI._accentElements + 1] = {
            type = "callback",
            fn = function()
                if FriendsFrame and EBS.db.profile.friends.enabled then
                    ApplyFriends()
                end
            end,
        }
    end

    local loginRefresh = CreateFrame("Frame")
    loginRefresh:RegisterEvent("PLAYER_ENTERING_WORLD")
    loginRefresh:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(0, ApplyAll)
    end)

    -- Hook FriendsFrame for load-on-demand. Skipped entirely once the Social UI
    -- is the active friends window: there is nothing to hook that the player
    -- will ever see, and the hook only exists to drive the legacy skin.
    if EBS.db.profile.friends.enabled and not LegacyFriendsRetired() then
        if not FriendsFrame then
            local hookFrame = CreateFrame("Frame")
            hookFrame:RegisterEvent("ADDON_LOADED")
            hookFrame:SetScript("OnEvent", function(self, event, addon)
                if addon == "Blizzard_SocialUI" then
                    C_Timer.After(0.1, function()
                        if FriendsFrame and EBS.db.profile.friends.enabled then
                            ApplyFriends()
                        end
                    end)
                    if FriendsFrame then
                        hooksecurefunc(FriendsFrame, "Show", function()
                            if not friendsSkinned and EBS.db.profile.friends.enabled then
                                C_Timer.After(0, ApplyFriends)
                            end
                        end)
                    end
                end
            end)
        else
            if EBS.db.profile.friends.enabled then
                SkinFriendsFrame()
            end
        end
    end
end
