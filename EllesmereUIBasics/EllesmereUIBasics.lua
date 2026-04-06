-------------------------------------------------------------------------------
--  EllesmereUIBasics.lua
--  Chat, Minimap, and Friends List skinning for EllesmereUI.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local EBS = EllesmereUI.Lite.NewAddon("EllesmereUIBasics")

local PP = EllesmereUI.PP

local EG = EllesmereUI.ELLESMERE_GREEN

-------------------------------------------------------------------------------
--  DEBUG: /ebsfriend - inspect first visible friend button (remove after)
-------------------------------------------------------------------------------
SLASH_EBSRAID1 = "/ebsraid"
SlashCmdList["EBSRAID"] = function()
    local rf = _G.RaidFrame
    if not rf then print("|cffff0000[EBS] RaidFrame not found|r"); return end
    print(format("|cff00ccff[EBS]|r RaidFrame: shown=%s w=%.0f h=%.0f", tostring(rf:IsShown()), rf:GetWidth(), rf:GetHeight()))
    print(format("  strata=%s level=%d parent=%s", rf:GetFrameStrata(), rf:GetFrameLevel(), rf:GetParent() and rf:GetParent():GetName() or "?"))
    local p1, rel, p2, ox, oy = rf:GetPoint(1)
    print(format("  point1: %s, %s, %s, %.0f, %.0f", tostring(p1), tostring(rel and rel:GetName()), tostring(p2), ox or 0, oy or 0))
    print("|cffffcc00Children:|r")
    for i = 1, select("#", rf:GetChildren()) do
        local child = select(i, rf:GetChildren())
        local name = child:GetName() or ("anon_" .. i)
        local cw, ch = child:GetSize()
        print(format("  %s: type=%s shown=%s size=%.0fx%.0f", name, child:GetObjectType(), tostring(child:IsShown()), cw or 0, ch or 0))
        -- Check for ScrollBox
        if child.ScrollBox or child.scrollFrame then
            print("    ^ HAS ScrollBox/scrollFrame")
        end
        if child:GetObjectType() == "Button" then
            local fs = child:GetFontString()
            if fs then print("    ^ text: " .. (fs:GetText() or "")) end
        end
    end
end

SLASH_EBSTEX1 = "/ebstex"
SlashCmdList["EBSTEX"] = function()
    if not FriendsFrame or not FriendsFrame:IsShown() then
        print("|cffff0000[EBS] Open friends list first|r"); return
    end
    local sb = FriendsListFrame and FriendsListFrame.ScrollBox
    if not sb then return end
    for _, btn in sb:EnumerateFrames() do
        if btn.buttonType and btn.buttonType ~= FRIENDS_BUTTON_TYPE_DIVIDER then
            local nm = (btn.name or btn.Name)
            print(format("|cff00ccff[EBS]|r Textures on: %s", nm and nm:GetText() or "?"))
            for j = 1, select("#", btn:GetRegions()) do
                local rgn = select(j, btn:GetRegions())
                if rgn:IsObjectType("Texture") then
                    local dl, sl = rgn:GetDrawLayer()
                    local atlas = rgn:GetAtlas()
                    local tex = rgn:GetTexture()
                    local r, g, b, a = rgn:GetVertexColor()
                    local shown = rgn:IsShown()
                    local al = rgn:GetAlpha()
                    print(format("  [%s/%s] shown=%s a=%.2f vColor=(%.2f,%.2f,%.2f,%.2f) atlas=%s tex=%s",
                        tostring(dl), tostring(sl), tostring(shown), al,
                        r or 0, g or 0, b or 0, a or 0,
                        tostring(atlas), tostring(tex)))
                end
            end
            break
        end
    end
end

SLASH_EBSFRIEND1 = "/ebsfriend"
SlashCmdList["EBSFRIEND"] = function()
    if not FriendsFrame or not FriendsFrame:IsShown() then
        print("|cffff0000[EBS-DBG] Open friends list first|r"); return
    end
    local sb = FriendsListFrame and FriendsListFrame.ScrollBox
    if not sb then print("|cffff0000[EBS-DBG] No ScrollBox|r"); return end
    for _, btn in sb:EnumerateFrames() do
        if btn.buttonType and btn.buttonType ~= FRIENDS_BUTTON_TYPE_DIVIDER then
            local nm = (btn.name or btn.Name)
            local nameStr = nm and nm:GetText() or "?"
            print(format("|cff00ccff[EBS-DBG]|r === %s ===", nameStr))

            -- Tile bg
            local tile = btn._ebsTileBg
            if tile then
                local dl, sl = tile:GetDrawLayer()
                local l, b, w, h = tile:GetRect()
                print(format("  tile: shown=%s alpha=%.2f layer=%s/%s size=%.0fx%.0f",
                    tostring(tile:IsShown()), tile:GetAlpha(), tostring(dl), tostring(sl),
                    w or 0, h or 0))
            else
                print("  tile: MISSING")
            end

            -- Faction bg
            local fac = btn._ebsFactionBg
            if fac then
                local dl, sl = fac:GetDrawLayer()
                local l, b, w, h = fac:GetRect()
                print(format("  faction: shown=%s alpha=%.2f tex=%s layer=%s/%s size=%.0fx%.0f",
                    tostring(fac:IsShown()), fac:GetAlpha(), tostring(fac:GetTexture()),
                    tostring(dl), tostring(sl), w or 0, h or 0))
            else
                print("  faction: MISSING")
            end

            -- Button itself
            local bw, bh = btn:GetSize()
            print(format("  button: alpha=%.2f size=%.0fx%.0f visible=%s parentAlpha=%.2f",
                btn:GetAlpha(), bw or 0, bh or 0, tostring(btn:IsVisible()),
                btn:GetParent() and btn:GetParent():GetAlpha() or -1))

            -- All BACKGROUND layer textures (check for Blizzard covering ours)
            local bgList = {}
            for j = 1, select("#", btn:GetRegions()) do
                local rgn = select(j, btn:GetRegions())
                if rgn:IsObjectType("Texture") then
                    local dl, sl = rgn:GetDrawLayer()
                    if dl == "BACKGROUND" and rgn:IsShown() then
                        bgList[#bgList + 1] = format("sl=%s a=%.2f tex=%s",
                            tostring(sl), rgn:GetAlpha(), tostring(rgn:GetTexture()))
                    end
                end
            end
            print(format("  BG textures (%d): %s", #bgList, table.concat(bgList, " | ")))
            break  -- only first button
        end
    end
end



-- Global friend groups storage (not tied to profiles, excluded from import/export)
local function GetFriendGroupsGlobal()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.global then EllesmereUIDB.global = {} end
    local g = EllesmereUIDB.global
    if not g.friendGroups then g.friendGroups = {} end
    if not g.friendAssignments then g.friendAssignments = {} end
    if g.friendFavCollapsed == nil then g.friendFavCollapsed = false end
    if g.friendPendingCollapsed == nil then g.friendPendingCollapsed = false end
    if g.friendUngroupedCollapsed == nil then g.friendUngroupedCollapsed = false end
    if not g.friendNotes then g.friendNotes = {} end
    if not g.friendGroupColors then g.friendGroupColors = {} end
    -- Full group order: includes "_favorites", custom group names, and "_ungrouped"
    -- Built/validated on first access to handle legacy data
    if not g.friendGroupOrder then
        g.friendGroupOrder = {}
    end
    return g
end

-- Internal keys for Favorites and ungrouped in the order list
local ORDER_FAVORITES = "_favorites"
local ORDER_UNGROUPED = "_ungrouped"

-- Validate/rebuild the full group order so it contains all groups exactly once.
-- Preserves existing order, appends any missing entries.
local function GetValidGroupOrder()
    local fg = GetFriendGroupsGlobal()
    local order = fg.friendGroupOrder

    -- Build set of what should exist
    local needed = {}
    needed[ORDER_FAVORITES] = true
    needed[ORDER_UNGROUPED] = true
    for _, g in ipairs(fg.friendGroups) do
        needed[g.name] = true
    end

    -- Remove stale entries
    local clean = {}
    local seen = {}
    for _, key in ipairs(order) do
        if needed[key] and not seen[key] then
            clean[#clean + 1] = key
            seen[key] = true
        end
    end

    -- Append missing entries (Favorites first, then custom, then ungrouped)
    if not seen[ORDER_FAVORITES] then
        table.insert(clean, 1, ORDER_FAVORITES)
        seen[ORDER_FAVORITES] = true
    end
    for _, g in ipairs(fg.friendGroups) do
        if not seen[g.name] then
            -- Insert before ungrouped if it exists, otherwise append
            local ungroupedIdx
            for i, k in ipairs(clean) do
                if k == ORDER_UNGROUPED then ungroupedIdx = i; break end
            end
            if ungroupedIdx then
                table.insert(clean, ungroupedIdx, g.name)
            else
                clean[#clean + 1] = g.name
            end
            seen[g.name] = true
        end
    end
    if not seen[ORDER_UNGROUPED] then
        clean[#clean + 1] = ORDER_UNGROUPED
        seen[ORDER_UNGROUPED] = true
    end

    fg.friendGroupOrder = clean
    return clean
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
        chat = {
            enabled       = false,
            bgAlpha       = 0.6,
            borderR       = 0.05, borderG = 0.05, borderB = 0.05, borderA = 1,
            useClassColor = false,
            fontSize      = 14,
            hideButtons   = false,
            hideTabFlash  = false,
            position      = nil,
            visibility    = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
            fontFace           = nil,
            fontOutline        = "",
            fontShadow         = true,
            classColorNames    = true,
            clickableURLs      = true,
            shortenChannels    = "off",
            timestamps         = "none",
            messageFadeEnabled = true,
            messageFadeTime    = 120,
            messageSpacing     = 0,
            copyButton         = false,
            copyLines          = 200,
            showSearchButton   = true,
        },
        minimap = {
            enabled       = true,
            shape         = "square",
            borderSize    = 1,
            showCoords    = false,
            coordPrecision = 0,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            useClassColor = false,
            hideZoneText  = false,
            zoneInside    = false,
            scrollZoom    = true,
            savedZoom     = 0,
            hideZoomButtons      = true,
            hideTrackingButton   = true,
            hideGameTime         = false,
            hideMail             = false,
            hideRaidDifficulty   = false,
            hideCraftingOrder    = false,
            hideAddonCompartment = false,
            hideAddonButtons     = false,
            addonBtnSize         = 24,
            interactableBtnSize  = 21,
            ungroupedButtons     = {},
            showClock     = true,
            clockInside   = true,
            clockFormat   = "12h",
            clockScale    = 1.15,
            clockOffsetX  = 0,
            clockOffsetY  = 0,
            locationScale = 1.15,
            locationOffsetX = 0,
            locationOffsetY = 0,
            lock          = false,
            position      = nil,
            visibility    = "always",
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
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
            showOffline    = true,
            groupsEnabled  = true,
            showUngrouped  = true,
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
            width                = 325,
            bgAlpha              = 0.7,
            bgR                  = 0,
            bgG                  = 0,
            bgB                  = 0,
            height               = 500,
            alignment            = "top",
            titleFontSize        = 11,
            titleColor           = { r=1.0,  g=0.91, b=0.47 },
            objFontSize          = 11,
            objColor             = { r=0.72, g=0.72, b=0.72 },
            completedColor       = { r=0.25, g=1.0,  b=0.35 },
            completedFontSize    = 11,
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
            showPreyQuests       = true,
            preyCollapsed        = false,
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
        -- Friends uses accent color, minimap uses class color
        if cfg == (EBS.db and EBS.db.profile and EBS.db.profile.friends) then
            local ar, ag, ab = EG.r, EG.g, EG.b
            return ar, ag, ab, 1
        end
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
--  Chat Skin (placeholder -- rebuild from scratch)
-------------------------------------------------------------------------------
local skinnedChatFrames = {}  -- kept for visibility system compatibility

-- Chat module: stripped for rebuild. No-op stubs for existing call sites.
local function ApplyChat() end
_G._EBS_ApplyChat = ApplyChat
-------------------------------------------------------------------------------
--  Minimap Skin
-------------------------------------------------------------------------------
local minimapDecorations = {
    "MinimapBorder",
    "MinimapBorderTop",
    "MinimapBackdrop",
    "MinimapNorthTag",
    "MinimapCompassTexture",
    "TimeManagerClockButton",
}

local minimapButtonMap = {
    { key = "hideZoomButtons",      names = { "MinimapZoomIn", "MinimapZoomOut" } },
    { key = "hideTrackingButton",   names = { "MiniMapTrackingButton" } },
    { key = "hideGameTime",         names = { "GameTimeFrame" } },
    { key = "hideMail",             names = { "MiniMapMailFrame" } },
    { key = "hideRaidDifficulty",   names = { "MiniMapInstanceDifficulty", "GuildInstanceDifficulty" } },
    { key = "hideCraftingOrder",    names = { "MiniMapCraftingOrderFrame" } },
    { key = "hideAddonCompartment", names = { "AddonCompartmentFrame" } },
}

local minimapButtonHooks = {}

local function HideMinimapButton(name)
    local btn = _G[name]
    if not btn then return end
    btn:Hide()
    btn:SetAlpha(0)
    if not minimapButtonHooks[name] then
        hooksecurefunc(btn, "Show", function(self)
            if InCombatLockdown() then return end
            local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
            if not mp then return end
            for _, entry in ipairs(minimapButtonMap) do
                for _, btnName in ipairs(entry.names) do
                    if btnName == name and mp[entry.key] then
                        self:SetAlpha(0)
                        return
                    end
                end
            end
        end)
        minimapButtonHooks[name] = true
    end
end

local function ShowMinimapButton(name)
    local btn = _G[name]
    if not btn then return end
    btn:SetAlpha(1)
    btn:EnableMouse(true)
    btn:Show()
end

-- Forward declarations for flyout system
local addonButtonPoll = nil
local cachedAddonButtons = {}
local _addonVisible = {}       -- persistent: tracks whether each addon WANTS its button visible
local _suppressVisTrack = false -- flag to suppress tracking during our own Show/Hide calls
local flyoutOwnedFrames = {}

-------------------------------------------------------------------------------
--  Minimap Button Flyout
-------------------------------------------------------------------------------
local flyoutToggle = nil   -- the square trigger button
local flyoutPanel  = nil   -- the popup grid container
local flyoutSavedParents = {}  -- original parent/point data for restore
local flyoutSavedRegions = {}  -- original region states for restore

local FLYOUT_BTN_SIZE = 24
local FLYOUT_PADDING  = 4
local FLYOUT_COLS     = 4

-- Textures that are decorative borders/backgrounds on minimap buttons
local MINIMAP_BTN_JUNK = {
    [136467] = true,  -- UI-Minimap-Background
    [136430] = true,  -- MiniMap-TrackingBorder
    [136477] = true,  -- UI-Minimap-ZoomButton-Highlight (used on some buttons)
}
local MINIMAP_BTN_JUNK_PATH = {
    ["Interface\\Minimap\\MiniMap%-TrackingBorder"] = true,
    ["Interface\\Minimap\\UI%-Minimap%-Background"] = true,
    ["Interface\\Minimap\\UI%-Minimap%-ZoomButton%-Highlight"] = true,
}

local function IsJunkTexture(region)
    if not region or not region.IsObjectType or not region:IsObjectType("Texture") then
        return false
    end
    local texID = region.GetTextureFileID and region:GetTextureFileID()
    if texID and MINIMAP_BTN_JUNK[texID] then return true end
    local texPath = region:GetTexture()
    if texPath and type(texPath) == "string" then
        for pattern in pairs(MINIMAP_BTN_JUNK_PATH) do
            if texPath:match(pattern) then return true end
        end
    end
    return false
end

local function StripButtonDecorations(btn)
    local saved = {}
    for _, region in ipairs({ btn:GetRegions() }) do
        if IsJunkTexture(region) then
            saved[#saved + 1] = { region = region, alpha = region:GetAlpha(), shown = region:IsShown() }
            region:SetAlpha(0)
            region:Hide()
        end
    end
    -- Also hide highlight/pushed overlays that have junk textures
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl and IsJunkTexture(hl) then
        saved[#saved + 1] = { region = hl, alpha = hl:GetAlpha(), shown = hl:IsShown() }
        hl:SetAlpha(0)
        hl:Hide()
    end
    flyoutSavedRegions[btn] = saved
end

local function RestoreButtonDecorations(btn)
    local saved = flyoutSavedRegions[btn]
    if not saved then return end
    for _, info in ipairs(saved) do
        info.region:SetAlpha(info.alpha)
        if info.shown then info.region:Show() end
    end
    flyoutSavedRegions[btn] = nil
end

local function IsUngrouped(btn)
    local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
    if not mp or not mp.ungroupedButtons then return false end
    local name = btn:GetName()
    return name and mp.ungroupedButtons[name]
end

local function CollectFlyoutButtons()
    -- Return only buttons the addon wants visible and not ungrouped
    local collected = {}
    for _, btn in ipairs(cachedAddonButtons) do
        if _addonVisible[btn] ~= false and not IsUngrouped(btn) then
            collected[#collected + 1] = btn
        end
    end
    return collected
end

local function GetAddonBtnSize()
    local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
    return mp and mp.addonBtnSize or FLYOUT_BTN_SIZE
end

local function LayoutFlyoutButtons()
    if not flyoutPanel then return end
    local buttons = CollectFlyoutButtons()
    local count = #buttons
    if count == 0 then
        flyoutPanel:SetSize(1, 1)
        return
    end

    local btnSize = GetAddonBtnSize()
    local cols = math.min(count, FLYOUT_COLS)
    local rows = math.ceil(count / cols)
    local pw = FLYOUT_PADDING + cols * (btnSize + FLYOUT_PADDING)
    local ph = FLYOUT_PADDING + rows * (btnSize + FLYOUT_PADDING)
    flyoutPanel:SetSize(pw, ph)

    for i, btn in ipairs(buttons) do
        -- Save original parent/points for restore
        if not flyoutSavedParents[btn] then
            local p1, rel, p2, ox, oy = btn:GetPoint(1)
            flyoutSavedParents[btn] = {
                parent = btn:GetParent(),
                strata = btn:GetFrameStrata(),
                point = p1, relTo = rel, relPoint = p2, x = ox, y = oy,
            }
        end

        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local xOff = FLYOUT_PADDING + col * (btnSize + FLYOUT_PADDING)
        local yOff = -(FLYOUT_PADDING + row * (btnSize + FLYOUT_PADDING))

        btn:SetParent(flyoutPanel)
        -- Unlock fixed strata/level first (LibDBIcon locks these)
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
        btn:SetFrameStrata("DIALOG")
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(true) end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", flyoutPanel, "TOPLEFT", xOff, yOff)
        btn:SetSize(btnSize, btnSize)
        _suppressVisTrack = true
        btn:SetAlpha(1)
        btn:Show()
        _suppressVisTrack = false
        btn:SetFrameLevel(flyoutPanel:GetFrameLevel() + 5)
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(true) end
        -- Strip decorative border/background textures
        StripButtonDecorations(btn)
        -- Also force all child frames up to the same strata/level
        for _, child in ipairs({ btn:GetChildren() }) do
            child:SetFrameStrata("DIALOG")
            child:SetFrameLevel(flyoutPanel:GetFrameLevel() + 6)
        end
        -- Normalize icon region to fill the button cleanly
        local icon = btn.icon or btn.Icon
        if not icon then
            for _, region in ipairs({ btn:GetRegions() }) do
                if region:IsObjectType("Texture") and region:IsShown()
                   and region:GetAlpha() > 0 and not IsJunkTexture(region) then
                    icon = region
                    break
                end
            end
        end
        if icon then
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        end
        -- Add atlas ring border overlay
        if not btn._flyoutRing then
            local ring = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            ring:SetAtlas("AdventureMap-combatally-ring")
            ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
            ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
            btn._flyoutRing = ring
        end
        btn._flyoutRing:Show()
    end
end

local function RestoreFlyoutButtons()
    for btn, saved in pairs(flyoutSavedParents) do
        RestoreButtonDecorations(btn)
        if btn._flyoutRing then btn._flyoutRing:Hide() end
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
        btn:SetParent(saved.parent)
        btn:SetFrameStrata(saved.strata)
        btn:ClearAllPoints()
        if saved.point and saved.relTo then
            btn:SetPoint(saved.point, saved.relTo, saved.relPoint, saved.x, saved.y)
        end
        -- Re-hide on the minimap surface
        _suppressVisTrack = true
        btn:Hide()
        btn:SetAlpha(0)
        _suppressVisTrack = false
    end
    wipe(flyoutSavedParents)
end

local function ShowFlyoutPanel()
    if not flyoutPanel then
        flyoutPanel = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
        flyoutPanel:SetFrameStrata("DIALOG")
        flyoutPanel:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
        })
        flyoutPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        flyoutPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        flyoutPanel:SetPoint("BOTTOMLEFT", flyoutToggle, "TOPLEFT", 0, 2)
        flyoutPanel:SetClampedToScreen(true)
        flyoutOwnedFrames[flyoutPanel] = true
    end
    LayoutFlyoutButtons()
    flyoutPanel:Show()
end

local function HideFlyoutPanel()
    if flyoutPanel then
        flyoutPanel:Hide()
        RestoreFlyoutButtons()
    end
end

local function ToggleFlyoutPanel()
    if flyoutPanel and flyoutPanel:IsShown() then
        HideFlyoutPanel()
    else
        ShowFlyoutPanel()
    end
end

local function GetInteractableBtnSize()
    local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
    return mp and mp.interactableBtnSize or 22
end

local function CreateFlyoutToggle()
    if flyoutToggle then return flyoutToggle end

    local btn = CreateFrame("Button", nil, Minimap)
    local iconSize = GetInteractableBtnSize()
    btn:SetSize(iconSize, iconSize)
    btn:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT", 0, 0)
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 10)

    local norm = btn:CreateTexture(nil, "ARTWORK")
    norm:SetAllPoints()
    norm:SetAtlas("Map-Filter-Button")
    btn:SetNormalTexture(norm)

    local pushed = btn:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    pushed:SetAtlas("Map-Filter-Button-down")
    btn:SetPushedTexture(pushed)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetAtlas("Map-Filter-Button")
    hl:SetAlpha(0.3)
    btn:SetHighlightTexture(hl)

    -- Black background to match indicator icons
    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)

    btn:SetScript("OnClick", ToggleFlyoutPanel)

    -- Safety: ensure mouse stays enabled. Some Blizzard code or addon hooks
    -- on minimap children can disable mouse input. Re-assert on every Show.
    btn:HookScript("OnShow", function(self)
        if not self:IsMouseEnabled() then
            self:EnableMouse(true)
        end
    end)

    flyoutToggle = btn
    flyoutOwnedFrames[btn] = true
    return btn
end

local coordFrame, coordTicker
local clockFrame, clockTicker, clockBg
local locationFrame, locationBg

local function GetMinimapFont()
    local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    local flag = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or "OUTLINE"
    return path, flag
end

local function ApplyMinimapFont(fs, size)
    local path, flag = GetMinimapFont()
    fs:SetFont(path, size, flag)
    if EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow() then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.8)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- Cache clock CVars so we don't read them every second
local cachedUse24h, cachedUseLocal
local function RefreshClockCVars()
    cachedUse24h = GetCVar("timeMgrUseMilitaryTime") == "1"
    cachedUseLocal = GetCVar("timeMgrUseLocalTime") == "1"
end

local function UpdateClock()
    if not clockFrame then return end
    if cachedUse24h == nil then RefreshClockCVars() end
    if cachedUseLocal then
        local fmt = cachedUse24h and "%H:%M" or "%I:%M %p"
        clockFrame:SetText(date(fmt))
    else
        local h, m = GetGameTime()
        if cachedUse24h then
            clockFrame:SetText(format("%02d:%02d", h, m))
        else
            local ampm = h >= 12 and "PM" or "AM"
            h = h % 12
            if h == 0 then h = 12 end
            clockFrame:SetText(format("%d:%02d %s", h, m, ampm))
        end
    end
end

-- Cache coord format string so we don't rebuild it every 0.5s
local cachedCoordPrec, cachedCoordFmt
local function UpdateCoords()
    if not coordFrame then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then coordFrame:SetText(""); return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then coordFrame:SetText(""); return end
    local x, y = pos:GetXY()
    local p = EBS.db and EBS.db.profile.minimap
    local prec = p and p.coordPrecision or 1
    if prec ~= cachedCoordPrec then
        cachedCoordPrec = prec
        cachedCoordFmt = format("%%.%df, %%.%df", prec, prec)
    end
    coordFrame:SetText(format(cachedCoordFmt, x * 100, y * 100))
end

local lastLocationText
local function UpdateLocation()
    if not locationFrame then return end
    if InCombatLockdown() then return end
    local sub = GetSubZoneText()
    local text = (sub and sub ~= "") and sub or (GetZoneText() or "")
    if text == lastLocationText then return end
    lastLocationText = text
    locationFrame:SetText(text)
    if locationBg then
        local tw = locationFrame:GetStringWidth() or 0
        locationBg:SetSize(tw + 20, 18)
    end
end

local function SaveZoomLevel()
    local p = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
    if not p then return end
    p.savedZoom = Minimap:GetZoom()
end

-- Blizzard structural frames that should NOT go into the flyout
local flyoutBlacklist = {
    MinimapZoomIn    = true,
    MinimapZoomOut   = true,
    MinimapBackdrop  = true,
    GameTimeFrame    = true,
}

-- Persistently hide a minimap button via Show hook
local addonButtonHooks = {}

local function HideMinimapChild(btn)
    _suppressVisTrack = true
    btn:Hide()
    btn:SetAlpha(0)
    _suppressVisTrack = false
    if not addonButtonHooks[btn] then
        -- Track addon-intended visibility via Show/Hide hooks
        hooksecurefunc(btn, "Show", function(self)
            if not _suppressVisTrack then
                _addonVisible[self] = true
            end
            if InCombatLockdown() then return end
            -- Allow showing when parented to the flyout panel
            if self:GetParent() == flyoutPanel then return end
            -- Allow ungrouped buttons to stay visible
            if IsUngrouped(self) then return end
            local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
            if mp and mp.enabled and not flyoutOwnedFrames[self] then
                self:SetAlpha(0)
            end
        end)
        hooksecurefunc(btn, "Hide", function(self)
            if not _suppressVisTrack then
                _addonVisible[self] = false
            end
        end)
        addonButtonHooks[btn] = true
    end
end

local function ShowMinimapChild(btn)
    _suppressVisTrack = true
    btn:SetAlpha(1)
    btn:EnableMouse(true)
    btn:Show()
    _suppressVisTrack = false
end

-- Pin/POI frame patterns to exclude from the flyout (HandyNotes, TomTom, etc.)
local flyoutPinPatterns = {
    "^HandyNotes",
    "^TomTom",
    "^HereBeDragons",
    "^Questie",
    "^GatherMate",
    "^pin",
    "^Pin",
}

local function IsPinFrame(name)
    if not name then return false end
    for _, pat in ipairs(flyoutPinPatterns) do
        if name:match(pat) then return true end
    end
    return false
end

-- Gather all minimap buttons (Blizzard + addon) into cachedAddonButtons
local function GatherMinimapButtons()
    wipe(cachedAddonButtons)
    if not Minimap then return end
    -- Also scan flyout panel children (buttons we already reparented)
    local sources = { Minimap }
    if flyoutPanel then sources[2] = flyoutPanel end
    for _, source in ipairs(sources) do
        for _, child in ipairs({ source:GetChildren() }) do
            if not flyoutOwnedFrames[child] then
                local name = child:GetName()
                if flyoutBlacklist[name] then
                    -- skip
                elseif IsPinFrame(name) then
                    -- skip pin/POI frames
                elseif child:IsObjectType("Button") and name then
                    local w = child:GetWidth() or 0
                    if w >= 20 then
                        -- Record initial addon visibility (only first time)
                        if _addonVisible[child] == nil then
                            _addonVisible[child] = child:IsShown()
                        end
                        cachedAddonButtons[#cachedAddonButtons + 1] = child
                    end
                elseif not child:IsObjectType("Button") and name and name:match("^LibDBIcon10_") then
                    if _addonVisible[child] == nil then
                        _addonVisible[child] = child:IsShown()
                    end
                    cachedAddonButtons[#cachedAddonButtons + 1] = child
                end
            end
        end
    end
end

-- Expose for options UI
_G._EBS_CachedAddonButtons = cachedAddonButtons
_G._EBS_AddonVisible = _addonVisible

-- Hide all collected minimap buttons from the map surface
-- Ungrouped buttons are left alone (positioned by LayoutIndicatorFrames)
local function HideAllMinimapButtons()
    GatherMinimapButtons()
    for _, btn in ipairs(cachedAddonButtons) do
        if not IsUngrouped(btn) then
            HideMinimapChild(btn)
        end
    end
end

local function ShowAllMinimapButtons()
    for _, btn in ipairs(cachedAddonButtons) do
        ShowMinimapChild(btn)
    end
    wipe(cachedAddonButtons)
end

-------------------------------------------------------------------------------
--  Minimap Indicator Frames (top-left outer: Tracking, Calendar, Mail, Crafting)
-------------------------------------------------------------------------------
local indicatorBg = nil
local indicatorIconBgs = {}

local function GetIconBg(frame)
    if indicatorIconBgs[frame] then return indicatorIconBgs[frame] end
    local bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(frame)
    bg:SetFrameLevel(frame:GetFrameLevel() - 1)
    indicatorIconBgs[frame] = bg
    return bg
end

local function ShrinkTrackingIcon(tracking)
    local tBtn = tracking.Button
    if tBtn then
        tBtn:ClearAllPoints()
        tBtn:SetPoint("CENTER", tracking, "CENTER", 0, 0)
        local tw2 = (tracking:GetWidth() or 22) - 5
        local th2 = (tracking:GetHeight() or 22) - 5
        tBtn:SetSize(tw2, th2)
    end
end

local function ApplyInteractableSize(frame)
    if not frame then return end
    local sz = GetInteractableBtnSize()
    frame:SetSize(sz, sz)
end

local function LayoutIndicatorFrames(minimap, p, circleMode)
    local flvl = minimap:GetFrameLevel() + 10

    local tracking = MinimapCluster and MinimapCluster.Tracking
    local gameTime = _G.GameTimeFrame
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    local mailFrame = indicator and indicator.MailFrame
    local craftingFrame = indicator and indicator.CraftingOrderFrame

    -- Apply interactable button size
    ApplyInteractableSize(tracking)
    ApplyInteractableSize(gameTime)
    ApplyInteractableSize(mailFrame)
    ApplyInteractableSize(craftingFrame)
    if flyoutToggle then
        local sz = GetInteractableBtnSize()
        flyoutToggle:SetSize(sz, sz)
    end

    -- Reparent indicator children onto minimap (cluster is hidden).
    -- Guard with InCombatLockdown to avoid tainting during protected operations.
    if not InCombatLockdown() then
        if tracking then tracking:SetParent(minimap); tracking:SetFrameLevel(flvl + 1) end
        if gameTime then gameTime:SetParent(minimap); gameTime:SetFrameLevel(flvl + 1) end
        if mailFrame then mailFrame:SetParent(minimap); mailFrame:SetFrameLevel(flvl + 1) end
        if craftingFrame then craftingFrame:SetParent(minimap); craftingFrame:SetFrameLevel(flvl + 1) end
    end
    -- Difficulty flag (instance type/size indicator)
    local diffFrame = (MinimapCluster and MinimapCluster.InstanceDifficulty) or _G.MiniMapInstanceDifficulty
    if diffFrame then
        diffFrame:SetParent(minimap)
        diffFrame:SetFrameLevel(flvl + 2)
        diffFrame:ClearAllPoints()
        diffFrame:SetPoint("TOPRIGHT", minimap, "TOPRIGHT", 2, 1)
        if p.hideRaidDifficulty then
            diffFrame:SetAlpha(0)
        else
            diffFrame:SetAlpha(1)
        end
    end
    -- Blizzard indicator children call self:GetParent():Layout() on events;
    -- provide a no-op so reparented frames don't error
    if not minimap.Layout then minimap.Layout = function() end end

    if circleMode then
        -----------------------------------------------------------------------
        -- Circle layout: horizontal row around the clock
        -- [crafting][mail][tracking] [CLOCK] [calendar]
        -----------------------------------------------------------------------

        -- Tracking -- flush left of clock
        if tracking then
            tracking:ClearAllPoints()
            if clockBg and p.showClock then
                tracking:SetPoint("RIGHT", clockBg, "LEFT", 0, 0)
            else
                tracking:SetPoint("TOP", minimap, "TOP", -20, -3)
            end
            tracking:Show()
            ShrinkTrackingIcon(tracking)
        end

        -- Calendar -- flush right of clock
        if gameTime then
            if not p.hideGameTime then
                gameTime:ClearAllPoints()
                if clockBg and p.showClock then
                    gameTime:SetPoint("LEFT", clockBg, "RIGHT", 0, 0)
                else
                    gameTime:SetPoint("TOP", minimap, "TOP", 20, -3)
                end
                gameTime:SetAlpha(1)
                gameTime:Show()
                gameTime:SetFrameLevel(flvl + 1)
            else
                gameTime:Hide()
            end
        end

        -- Mail -- left of tracking, building left
        if mailFrame then
            mailFrame:ClearAllPoints()
            if tracking then
                mailFrame:SetPoint("RIGHT", tracking, "LEFT", 0, 0)
            elseif clockBg and p.showClock then
                mailFrame:SetPoint("RIGHT", clockBg, "LEFT", 0, 0)
            end
        end

        -- Crafting Order -- left of mail, building left
        if craftingFrame then
            craftingFrame:ClearAllPoints()
            if mailFrame then
                craftingFrame:SetPoint("RIGHT", mailFrame, "LEFT", 0, 0)
            elseif tracking then
                craftingFrame:SetPoint("RIGHT", tracking, "LEFT", 0, 0)
            end
        end

        -- Individual black backgrounds behind each icon
        if tracking then GetIconBg(tracking):Show() end
        if gameTime and not p.hideGameTime then GetIconBg(gameTime):Show() end
        if mailFrame then
            local bg = GetIconBg(mailFrame)
            if mailFrame:IsShown() then bg:Show() else bg:Hide() end
        end
        if craftingFrame then
            local bg = GetIconBg(craftingFrame)
            if craftingFrame:IsShown() then bg:Show() else bg:Hide() end
        end
        if indicatorBg then indicatorBg:Hide() end

    else
        -----------------------------------------------------------------------
        -- Square layout: vertical stack on the left side, building down
        -- [tracking] [calendar] [mail] [crafting]
        -----------------------------------------------------------------------
        local y = 0
        local w = 0
        local visCount = 0

        if tracking then
            tracking:ClearAllPoints()
            tracking:SetPoint("TOPRIGHT", minimap, "TOPLEFT", -1, y)
            tracking:Show()
            ShrinkTrackingIcon(tracking)
            local tw = tracking:GetWidth() or 22
            y = y - (tracking:GetHeight() or 22)
            if tw > w then w = tw end
            visCount = visCount + 1
        end

        if gameTime then
            if not p.hideGameTime then
                gameTime:ClearAllPoints()
                gameTime:SetPoint("TOPRIGHT", minimap, "TOPLEFT", 2, y)
                gameTime:SetAlpha(1)
                gameTime:Show()
                gameTime:SetFrameLevel(flvl + 1)
                local gw = gameTime:GetWidth() or 22
                y = y - (gameTime:GetHeight() or 22)
                if gw > w then w = gw end
                visCount = visCount + 1
            else
                gameTime:Hide()
            end
        end

        if mailFrame then
            mailFrame:ClearAllPoints()
            mailFrame:SetPoint("TOPRIGHT", minimap, "TOPLEFT", 0, y)
            if mailFrame:IsShown() then
                local mw = mailFrame:GetWidth() or 22
                y = y - (mailFrame:GetHeight() or 22)
                if mw > w then w = mw end
                visCount = visCount + 1
            end
        end

        if craftingFrame then
            craftingFrame:ClearAllPoints()
            craftingFrame:SetPoint("TOPRIGHT", minimap, "TOPLEFT", 0, y)
            if craftingFrame:IsShown() then
                local cw = craftingFrame:GetWidth() or 22
                y = y - (craftingFrame:GetHeight() or 22)
                if cw > w then w = cw end
                visCount = visCount + 1
            end
        end

        -- Hide individual icon backgrounds (square uses the combined one)
        for frame, bg in pairs(indicatorIconBgs) do bg:Hide() end

        -- Black background sized to visible icons only
        local totalH = -y
        if visCount > 0 and totalH > 0 then
            if not indicatorBg then
                indicatorBg = CreateFrame("Frame", nil, minimap, "BackdropTemplate")
                indicatorBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
                indicatorBg:SetBackdropColor(0, 0, 0, 0.8)
            end
            indicatorBg:SetParent(minimap)
            indicatorBg:ClearAllPoints()
            indicatorBg:SetPoint("TOPRIGHT", minimap, "TOPLEFT", 0, 0)
            indicatorBg:SetSize(w, totalH)
            indicatorBg:SetFrameLevel(flvl)
            indicatorBg:Show()
        elseif indicatorBg then
            indicatorBg:Hide()
        end
    end

    -- Position ungrouped buttons above the flyout toggle (in check order)
    if flyoutToggle then
        local btnSize = GetInteractableBtnSize()
        local anchor = flyoutToggle
        local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
        local ungrouped = {}
        for _, btn in ipairs(cachedAddonButtons) do
            if _addonVisible[btn] ~= false and IsUngrouped(btn) then
                local name = btn:GetName()
                local order = mp and mp.ungroupedButtons and mp.ungroupedButtons[name] or 999
                if type(order) == "boolean" then order = 999 end
                ungrouped[#ungrouped + 1] = { btn = btn, order = order }
            end
        end
        table.sort(ungrouped, function(a, b) return a.order < b.order end)
        for _, entry in ipairs(ungrouped) do
            local btn = entry.btn
            -- Restore from flyout if needed
            if flyoutSavedParents[btn] then
                if btn._flyoutRing then btn._flyoutRing:Hide() end
                if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
                if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
                flyoutSavedParents[btn] = nil
            end
            btn:SetParent(minimap)
            btn:SetFrameLevel(minimap:GetFrameLevel() + 11)
            btn:ClearAllPoints()
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("BOTTOM", anchor, "TOP", 0, 0)
            -- Lock position: disable dragging
            btn:SetMovable(false)
            btn:RegisterForDrag()
            btn:SetScript("OnDragStart", nil)
            btn:SetScript("OnDragStop", nil)
            -- Strip decorative textures and normalize icon
            StripButtonDecorations(btn)
            local icon = btn.icon or btn.Icon
            if not icon then
                for _, region in ipairs({ btn:GetRegions() }) do
                    if region:IsObjectType("Texture") and region:IsShown()
                       and region:GetAlpha() > 0 and not IsJunkTexture(region)
                       and region ~= btn._ungroupBg then
                        icon = region
                        break
                    end
                end
            end
            if icon then
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
                icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
                icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
            end
            -- Black square background
            if not btn._ungroupBg then
                local ubg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
                ubg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
                ubg:SetBackdropColor(0, 0, 0, 0.8)
                ubg:SetAllPoints(btn)
                ubg:SetFrameLevel(btn:GetFrameLevel() - 1)
                btn._ungroupBg = ubg
            end
            btn._ungroupBg:Show()
            _suppressVisTrack = true
            btn:SetAlpha(1)
            btn:Show()
            _suppressVisTrack = false
            anchor = btn
        end
    end
end

local function RestoreIndicatorFrames()
    local tracking = MinimapCluster and MinimapCluster.Tracking
    if tracking then
        tracking:SetParent(MinimapCluster)
        tracking:ClearAllPoints()
        tracking:Show()
    end

    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if indicator then
        indicator:Show()
        if indicator.MailFrame then
            indicator.MailFrame:SetParent(indicator)
            indicator.MailFrame:ClearAllPoints()
        end
        if indicator.CraftingOrderFrame then
            indicator.CraftingOrderFrame:SetParent(indicator)
            indicator.CraftingOrderFrame:ClearAllPoints()
        end
        -- Trigger Blizzard's layout so children get their default anchors back
        if indicator.Layout then indicator:Layout() end
    end

    local gameTime = _G.GameTimeFrame
    if gameTime then
        if indicator then
            gameTime:SetParent(indicator)
        elseif MinimapCluster then
            gameTime:SetParent(MinimapCluster)
        end
        gameTime:ClearAllPoints()
        gameTime:SetAlpha(1)
        gameTime:Show()
    end

    -- Remove the no-op Layout we added to the minimap
    if Minimap and Minimap.Layout then Minimap.Layout = nil end

    -- Trigger MinimapCluster layout to restore all default positions
    if MinimapCluster and MinimapCluster.Layout then
        MinimapCluster:Layout()
    end

    if indicatorBg then indicatorBg:Hide() end
end

-------------------------------------------------------------------------------
-- Snapshot Blizzard minimap size and position on first install.
-- Captures the native size and center position so our module starts matching
-- whatever the user had via Edit Mode. Only runs once per profile.
-------------------------------------------------------------------------------
local function CaptureBlizzardMinimap()
    local minimap = Minimap
    if not minimap then return end
    local p = EBS.db.profile.minimap
    if p._capturedOnce then return end

    local uiScale = UIParent:GetEffectiveScale()
    local mScale  = minimap:GetEffectiveScale()
    local ratio   = mScale / uiScale

    -- Capture size (use the larger dimension to keep it square)
    local w, h = minimap:GetWidth(), minimap:GetHeight()
    if w and w > 10 then
        local sz = math.floor(math.max(w, h) * ratio + 0.5)
        p.mapSize = sz
    end

    -- Capture center position as CENTER/CENTER offset from UIParent
    local cx, cy = minimap:GetCenter()
    if cx and cy then
        local uiW, uiH = UIParent:GetSize()
        cx = cx * ratio
        cy = cy * ratio
        p.position = {
            point = "CENTER", relPoint = "CENTER",
            x = cx - (uiW / 2), y = cy - (uiH / 2),
        }
    end

    p._capturedOnce = true
end

local function ApplyMinimap()
    if TEMP_DISABLED.minimap then return end
    if InCombatLockdown() then QueueApplyAll(); return end

    local p = EBS.db.profile.minimap

    local minimap = Minimap
    if not minimap then return end

    if not p.enabled then
        -- If we never touched the minimap this session, do absolutely nothing.
        -- This ensures zero interference with other minimap addons.
        if not minimap._ebsActive then return end
        -- Module was active but is now disabled; a reload is required to
        -- cleanly hand control back to Blizzard. The options toggle handles
        -- prompting the user for a reload.
        return
    end

    -- Ensure Blizzard_TimeManager is loaded so GameTimeFrame (calendar) exists
    if not _G.GameTimeFrame and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_TimeManager")
    end

    -- Snapshot Blizzard's native size/position before we modify anything
    CaptureBlizzardMinimap()

    -- Reparent minimap to UIParent so MinimapCluster layout cannot override our size.
    -- Deferred via C_Timer.After(0) to avoid tainting the secure frame environment
    -- when ApplyMinimap fires during a ShowUIPanel/World Map open sequence, which
    -- would cause ADDON_ACTION_BLOCKED when Blizzard's dungeon pin data provider
    -- later calls the protected SetPropagateMouseClicks() on map pins.
    local needsReparent = minimap:GetParent() ~= UIParent
    local needsClusterHide = MinimapCluster and MinimapCluster:IsShown()
    if needsReparent or needsClusterHide then
        C_Timer.After(0, function()
            if InCombatLockdown() then return end
            if needsReparent and minimap:GetParent() ~= UIParent then
                minimap:SetParent(UIParent)
            end
            if needsClusterHide and MinimapCluster then
                MinimapCluster:SetAlpha(0)
                MinimapCluster:EnableMouse(false)
            end
        end)
    end
    minimap:Show()

    -- Hide default decorations
    for _, name in ipairs(minimapDecorations) do
        local frame = _G[name]
        if frame then frame:Hide() end
    end

    -- Hide AddonCompartmentFrame by reparenting to a hidden frame
    local compartment = _G.AddonCompartmentFrame
    if compartment then
        if not EBS._hiddenFrame then
            EBS._hiddenFrame = CreateFrame("Frame")
            EBS._hiddenFrame:Hide()
        end
        compartment._ebsOrigParent = compartment._ebsOrigParent or compartment:GetParent()
        compartment:SetParent(EBS._hiddenFrame)
    end

    local isCircle = (p.shape == "circle" or p.shape == "textured_circle")

    -- Hide background (no black bg behind minimap)
    if minimap._ebsBg then minimap._ebsBg:SetAlpha(0) end

    -- Border
    local r, g, b = GetBorderColor(p)
    -- Hide the circular quest area ring on square minimaps
    if minimap.SetArchBlobRingScalar then
        minimap:SetArchBlobRingScalar(isCircle and 1 or 0)
    end
    if minimap.SetQuestBlobRingScalar then
        minimap:SetQuestBlobRingScalar(isCircle and 1 or 0)
    end

    if p.shape == "square" then
        -- Square: pixel-perfect border
        local bs = p.borderSize or 1
        if not minimap._ppBorders then
            PP.CreateBorder(minimap, r, g, b, 1, bs, "OVERLAY", 7)
        else
            PP.SetBorderColor(minimap, r, g, b, 1)
        end
        PP.SetBorderSize(minimap, bs)
        if minimap._circBorder then minimap._circBorder:Hide() end
        if minimap._texCircBorder then minimap._texCircBorder:Hide() end
    elseif p.shape == "circle" then
        -- Circle: solid colored disc behind the minimap, slightly larger = border ring
        if minimap._ppBorders then PP.SetBorderSize(minimap, 0); PP.SetBorderColor(minimap, 0, 0, 0, 0) end
        if not minimap._circBorder then
            local disc = CreateFrame("Frame", nil, minimap)
            disc:SetFrameLevel(minimap:GetFrameLevel() - 1)
            local tex = disc:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(disc)
            tex:SetTexture("Interface\\Common\\CommonMaskCircle")
            disc._tex = tex
            minimap._circBorder = disc
        end
        local bs = p.borderSize or 1
        minimap._circBorder:ClearAllPoints()
        minimap._circBorder:SetPoint("TOPLEFT", minimap, "TOPLEFT", -bs, bs)
        minimap._circBorder:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", bs, -bs)
        minimap._circBorder._tex:SetVertexColor(r, g, b, 1)
        minimap._circBorder:Show()
        if minimap._texCircBorder then minimap._texCircBorder:Hide() end
    elseif p.shape == "textured_circle" then
        -- Textured Circle: void ring border, hide the solid circle border
        if minimap._ppBorders then PP.SetBorderSize(minimap, 0); PP.SetBorderColor(minimap, 0, 0, 0, 0) end
        if minimap._circBorder then minimap._circBorder:Hide() end
        if not minimap._texCircBorder then
            local ring = minimap:CreateTexture(nil, "OVERLAY", nil, 7)
            ring:SetAtlas("wowlabs_minimapvoid-ring-single")
            minimap._texCircBorder = ring
        end
        local inset = 2
        minimap._texCircBorder:ClearAllPoints()
        minimap._texCircBorder:SetPoint("TOPLEFT", minimap, "TOPLEFT", -inset, inset)
        minimap._texCircBorder:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", inset, -inset)
        minimap._texCircBorder:SetVertexColor(r, g, b, 1)
        minimap._texCircBorder:Show()
    end

    -- Size
    minimap:SetScale(1.0)
    local mapSize = p.mapSize or 140
    minimap:SetSize(mapSize, mapSize)
    -- Shape mask
    minimap:SetMaskTexture(isCircle and 186178 or 130937)
    -- Clamp to screen so the border never extends off-screen
    minimap:SetClampedToScreen(true)
    local bInset = isCircle and (p.borderSize or 1) or 0
    minimap:SetClampRectInsets(-bInset, bInset, bInset, -bInset)
    -- Force the minimap engine to re-render at the new size. Nudge the zoom
    -- to a different value now, then restore it on the next rendered frame.
    -- Doing both in the same frame gets optimized away by the engine.
    local savedZoom = minimap:GetZoom()
    local nudgeZoom = savedZoom < minimap:GetZoomLevels() and savedZoom + 1 or savedZoom - 1
    minimap:SetZoom(nudgeZoom)
    if not minimap._zoomRestoreFrame then
        minimap._zoomRestoreFrame = CreateFrame("Frame")
    end
    minimap._zoomRestoreFrame._targetZoom = savedZoom
    minimap._zoomRestoreFrame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        minimap:SetZoom(self._targetZoom)
    end)

    -- Reposition zoom buttons to bottom-right corner of the minimap.
    -- Parent to minimap, raise frame level above the map surface, and
    -- hook SetPoint to prevent Blizzard from re-anchoring them.
    -- Midnight uses Minimap.ZoomIn/ZoomOut (not global MinimapZoomIn).
    local zoomIn = minimap.ZoomIn or _G.MinimapZoomIn
    local zoomOut = minimap.ZoomOut or _G.MinimapZoomOut
    if zoomIn then
        zoomIn:SetParent(minimap)
        zoomIn:SetFrameLevel(minimap:GetFrameLevel() + 10)
        zoomIn:ClearAllPoints()
        zoomIn:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 20)
        zoomIn:EnableMouse(true)
        zoomIn:Show()
        if not zoomIn._ebsHooked then
            hooksecurefunc(zoomIn, "SetPoint", function(self)
                if self._ebsInHook then return end
                self._ebsInHook = true
                self:ClearAllPoints()
                self:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 20)
                self._ebsInHook = false
            end)
            zoomIn._ebsHooked = true
        end
    end
    if zoomOut then
        zoomOut:SetParent(minimap)
        zoomOut:SetFrameLevel(minimap:GetFrameLevel() + 10)
        zoomOut:ClearAllPoints()
        zoomOut:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 2)
        zoomOut:EnableMouse(true)
        zoomOut:Show()
        if not zoomOut._ebsHooked then
            hooksecurefunc(zoomOut, "SetPoint", function(self)
                if self._ebsInHook then return end
                self._ebsInHook = true
                self:ClearAllPoints()
                self:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 2)
                self._ebsInHook = false
            end)
            zoomOut._ebsHooked = true
        end
    end

    -- Save zoom level when zoom buttons are clicked
    if zoomIn and not zoomIn._ebsZoomSaveHooked then
        zoomIn:HookScript("OnClick", function() SaveZoomLevel() end)
        zoomIn._ebsZoomSaveHooked = true
    end
    if zoomOut and not zoomOut._ebsZoomSaveHooked then
        zoomOut:HookScript("OnClick", function() SaveZoomLevel() end)
        zoomOut._ebsZoomSaveHooked = true
    end

    -- Mark zoom buttons so GatherMinimapButtons skips them
    if zoomIn then flyoutOwnedFrames[zoomIn] = true end
    if zoomOut then flyoutOwnedFrames[zoomOut] = true end

    -- Flyout toggle button (bottom-left corner) -- create before hiding children
    CreateFlyoutToggle()
    flyoutToggle:Show()

    -- Hide ALL minimap child frames from the map surface
    HideAllMinimapButtons()

    -- Poll for late-loading addons that attach buttons after ADDON_LOADED
    if not addonButtonPoll then
        addonButtonPoll = CreateFrame("Frame")
        addonButtonPoll:RegisterEvent("ADDON_LOADED")
        local pollPending = false
        addonButtonPoll:SetScript("OnEvent", function()
            if pollPending then return end
            pollPending = true
            C_Timer.After(0.1, function()
                pollPending = false
                HideAllMinimapButtons()
            end)
        end)
    end
    addonButtonPoll:Show()

    -- Close the flyout if it was open (layout may have changed)
    HideFlyoutPanel()

    -- Hide Blizzard zone text (we use our own location bar)
    local zoneBtn = MinimapZoneTextButton
    if zoneBtn then zoneBtn:Hide() end
    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:Hide()
    end
    if MinimapZoneText then MinimapZoneText:Hide() end

    -- Refresh cached clock CVars when settings are applied
    RefreshClockCVars()

    -- Clock -- top center (outside) or top inside the minimap
    if p.showClock then
        if not clockBg then
            clockBg = CreateFrame("Button", nil, minimap, "BackdropTemplate")
            clockBg:SetSize(80, 16)
            clockBg:SetPoint("TOP", minimap, "TOP", 0, 7)
            clockBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
            clockBg:SetFrameLevel(minimap:GetFrameLevel() + 5)
            clockBg:RegisterForClicks("AnyUp")
            clockBg:SetScript("OnClick", function()
                if ToggleTimeManager then ToggleTimeManager() end
            end)
        end
        if not clockFrame then
            clockFrame = clockBg:CreateFontString(nil, "OVERLAY")
            ApplyMinimapFont(clockFrame, 10)
            clockFrame:SetPoint("CENTER", clockBg, "CENTER", 0, 0)
            clockFrame:SetTextColor(1, 1, 1, 0.9)
        end
        -- Position and background based on inside/outside setting
        local clockInside = p.clockInside
        local cxOff = p.clockOffsetX or 0
        local cyOff = p.clockOffsetY or 0
        if clockInside then
            clockBg:SetBackdropColor(0, 0, 0, 0)
            clockBg:ClearAllPoints()
            clockBg:SetPoint("TOP", minimap, "TOP", cxOff, -4 + cyOff)
        else
            local ar, ag, ab = GetBorderColor(p)
            clockBg:SetBackdropColor(ar, ag, ab, 1)
            local clockYOff = isCircle and -3 or 7
            clockBg:ClearAllPoints()
            clockBg:SetPoint("TOP", minimap, "TOP", cxOff, clockYOff + cyOff)
        end
        local cs = p.clockScale or 1.15
        clockBg:SetScale(cs)
        _G._EBS_ClockBg = clockBg
        clockBg:Show()
        clockFrame:Show()
        if not clockTicker then
            clockTicker = CreateFrame("Frame")  -- kept for CVar event + Show/Hide API
            clockTicker._ticker = nil
            clockTicker.Show = function(self)
                if self._ticker then return end
                self._ticker = C_Timer.NewTicker(10, function()
                    UpdateClock()
                end)
            end
            clockTicker.Hide = function(self)
                if self._ticker then self._ticker:Cancel(); self._ticker = nil end
            end
            clockTicker:RegisterEvent("CVAR_UPDATE")
            clockTicker:SetScript("OnEvent", function(_, _, cvarName)
                if cvarName == "timeMgrUseMilitaryTime" or cvarName == "timeMgrUseLocalTime" then
                    RefreshClockCVars()
                    UpdateClock()
                end
            end)
        end
        clockTicker:Show()
        UpdateClock()
    else
        if clockBg then clockBg:Hide() end
        if clockFrame then clockFrame:Hide() end
        if clockTicker then clockTicker:Hide() end
    end

    -- Indicator frames (tracking, calendar, mail, crafting)
    LayoutIndicatorFrames(minimap, p, isCircle)

    -- Hook mail/crafting Show/Hide so backdrops update when status changes
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    local mailFrame = indicator and indicator.MailFrame
    local craftingFrame = indicator and indicator.CraftingOrderFrame
    if mailFrame and not mailFrame._ebsVisHooked then
        mailFrame._ebsVisHooked = true
        hooksecurefunc(mailFrame, "Show", function()
            local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
            if not mp or not mp.enabled then return end
            LayoutIndicatorFrames(minimap, mp, (mp.shape or "square") ~= "square")
        end)
        hooksecurefunc(mailFrame, "Hide", function()
            local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
            if not mp or not mp.enabled then return end
            LayoutIndicatorFrames(minimap, mp, (mp.shape or "square") ~= "square")
        end)
    end
    if craftingFrame and not craftingFrame._ebsVisHooked then
        craftingFrame._ebsVisHooked = true
        hooksecurefunc(craftingFrame, "Show", function()
            local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
            if not mp or not mp.enabled then return end
            LayoutIndicatorFrames(minimap, mp, (mp.shape or "square") ~= "square")
        end)
        hooksecurefunc(craftingFrame, "Hide", function()
            local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
            if not mp or not mp.enabled then return end
            LayoutIndicatorFrames(minimap, mp, (mp.shape or "square") ~= "square")
        end)
    end

    -- Location bar -- bottom center (outside) or bottom inside the minimap
    if not p.hideZoneText then
        if not locationBg then
            locationBg = CreateFrame("Frame", nil, minimap, "BackdropTemplate")
            locationBg:SetSize(120, 18)
            locationBg:SetPoint("BOTTOM", minimap, "BOTTOM", 0, -7)
            locationBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
            locationBg:SetFrameLevel(minimap:GetFrameLevel() + 5)
            locationBg:RegisterEvent("ZONE_CHANGED")
            locationBg:RegisterEvent("ZONE_CHANGED_INDOORS")
            locationBg:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            locationBg:RegisterEvent("PLAYER_REGEN_ENABLED")
            locationBg:SetScript("OnEvent", function() UpdateLocation() end)
        end
        if not locationFrame then
            locationFrame = locationBg:CreateFontString(nil, "OVERLAY")
            ApplyMinimapFont(locationFrame, 10)
            locationFrame:SetPoint("CENTER", locationBg, "CENTER", 0, 0)
            locationFrame:SetTextColor(1, 1, 1, 0.9)
        end
        -- Position and background based on inside/outside setting
        local zoneInside = p.zoneInside
        local lxOff = p.locationOffsetX or 0
        local lyOff = p.locationOffsetY or 0
        if zoneInside then
            locationBg:SetBackdropColor(0, 0, 0, 0)
            locationBg:ClearAllPoints()
            locationBg:SetPoint("BOTTOM", minimap, "BOTTOM", lxOff, 4 + lyOff)
        else
            local ar, ag, ab = GetBorderColor(p)
            locationBg:SetBackdropColor(ar, ag, ab, 1)
            local locYOff = isCircle and 3 or -7
            locationBg:ClearAllPoints()
            locationBg:SetPoint("BOTTOM", minimap, "BOTTOM", lxOff, locYOff + lyOff)
        end
        local ls = p.locationScale or 1.15
        locationBg:SetScale(ls)
        _G._EBS_LocationBg = locationBg
        locationBg:Show()
        locationFrame:Show()
        UpdateLocation()
    else
        if locationBg then locationBg:Hide() end
        if locationFrame then locationFrame:Hide() end
    end

    -- Coordinates -- top-right, always visible on hover
    if not coordFrame then
        coordFrame = minimap:CreateFontString(nil, "OVERLAY")
        ApplyMinimapFont(coordFrame, 11)
        coordFrame:SetPoint("TOPLEFT", minimap, "TOPLEFT", 4, -4)
        coordFrame:SetTextColor(1, 1, 1, 0.9)
    end
    coordFrame:Hide()  -- hidden by default, shown on hover
    if not coordTicker then
        coordTicker = CreateFrame("Frame")  -- kept for Show/Hide API
        coordTicker._ticker = nil
        coordTicker.Show = function(self)
            if self._ticker then return end
            self._ticker = C_Timer.NewTicker(0.5, function()
                UpdateCoords()
            end)
        end
        coordTicker.Hide = function(self)
            if self._ticker then self._ticker:Cancel(); self._ticker = nil end
        end
    end
    -- Coords ticker only runs while hovering the minimap
    if not minimap._ebsCoordsHooked then
        minimap:HookScript("OnEnter", function(self)
            if not self._ebsActive then return end
            if coordFrame then coordFrame:Show() end
            coordTicker:Show()
            UpdateCoords()
        end)
        minimap:HookScript("OnLeave", function(self)
            if not self._ebsActive then return end
            if coordFrame and not self:IsMouseOver() then coordFrame:Hide() end
            coordTicker:Hide()
        end)
        minimap._ebsCoordsHooked = true
    end

    -- Mousewheel zoom
    if p.scrollZoom then
        minimap:EnableMouseWheel(true)
        if not minimap._ebsZoomHooked then
            minimap._ebsZoomHooked = true
            minimap:HookScript("OnMouseWheel", function(self, delta)
                local mp = _G._EBS_AceDB and _G._EBS_AceDB.profile.minimap
                if not mp or not mp.scrollZoom then return end
                local zoom = self:GetZoom()
                if delta > 0 then
                    zoom = min(zoom + 1, 5)
                else
                    zoom = max(zoom - 1, 0)
                end
                self:SetZoom(zoom)
                SaveZoomLevel()
            end)
        end
    else
        minimap:EnableMouseWheel(false)
    end

    -- Restore saved zoom level on first activation
    if not minimap._ebsActive then
        local saved = p.savedZoom or 0
        if saved >= 0 and saved <= minimap:GetZoomLevels() then
            minimap:SetZoom(saved)
        end
    end

    -- Position: only set on first activation; after that, unlock mode owns positioning.
    if not minimap._ebsActive then
        minimap:ClearAllPoints()
        if p.position then
            local px, py = p.position.x, p.position.y
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and PPa.SnapForES and px and py then
                local es = minimap:GetEffectiveScale()
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
            minimap:SetPoint(p.position.point, UIParent, p.position.relPoint, px, py)
        else
            minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -10)
        end
    end

    -- Mark module as active so persistent hooks know they can fire
    minimap._ebsActive = true
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
local function SkinRaidRoleIcon(icon)
    if not icon or icon._ebsSkinned then return end
    icon._ebsSkinned = true
    if not icon._ebsBorder then
        local border = icon:GetParent():CreateTexture(nil, "OVERLAY", nil, 1)
        border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(0, 0, 0, 0.5)
        border:SetDrawLayer("OVERLAY", -1)
        icon._ebsBorder = border
    end
end

local function SkinRaidRoleCount(frame)
    if not frame or frame._ebsSkinned then return end
    frame._ebsSkinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region:IsObjectType("FontString") then
            region:SetFont(fontPath, 10, "")
            region:SetTextColor(1, 1, 1, 0.8)
        end
    end
end

local function SkinRaidTabButton(btn)
    if not btn or btn._ebsBtnSkinned then return end
    btn._ebsBtnSkinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    StripTextures(btn)
    btn._ebsBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    btn._ebsBg:SetColorTexture(0.025, 0.035, 0.045, 0.92)
    btn._ebsBg:SetAllPoints()
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
        if btn._ebsAccent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 1, 0.8
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if btn._ppBorders then PP.SetBorderColor(btn, r, g, b, a2) end
    end)
    btn:HookScript("OnLeave", function()
        local r, g, b, a1, a2 = 1, 1, 1, 0.5, 0.4
        if btn._ebsAccent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 0.7, 0.5
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if btn._ppBorders then PP.SetBorderColor(btn, r, g, b, a2) end
    end)
end

local RAID_TAB_BUTTONS = {
    "RaidFrameConvertToRaidButton",
    "RaidFrameRaidInfoButton",
    "QuickJoinFrame.JoinQueueButton",
}

local function SkinCheckbox(checkbox)
    if not checkbox or checkbox._ebsSkinned then return end
    checkbox._ebsSkinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    local ar, ag, ab = EG.r, EG.g, EG.b
    if checkbox.SetNormalTexture then checkbox:SetNormalTexture("") end
    if checkbox.SetPushedTexture then checkbox:SetPushedTexture("") end
    if checkbox.SetHighlightTexture then checkbox:SetHighlightTexture("") end
    if checkbox.SetDisabledTexture then checkbox:SetDisabledTexture("") end
    for i = 1, select("#", checkbox:GetRegions()) do
        local region = select(i, checkbox:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
    if not checkbox._ebsBox then
        checkbox._ebsBorder = checkbox:CreateTexture(nil, "ARTWORK", nil, 1)
        checkbox._ebsBorder:SetSize(18, 18)
        checkbox._ebsBorder:SetPoint("LEFT", checkbox, "LEFT", 2, 0)
        checkbox._ebsBorder:SetColorTexture(0.4, 0.4, 0.4, 1)
        checkbox._ebsBox = checkbox:CreateTexture(nil, "ARTWORK", nil, 2)
        checkbox._ebsBox:SetSize(14, 14)
        checkbox._ebsBox:SetPoint("CENTER", checkbox._ebsBorder, "CENTER", 0, 0)
        checkbox._ebsBox:SetColorTexture(0.06, 0.06, 0.06, 1)
        checkbox._ebsCheck = checkbox:CreateTexture(nil, "ARTWORK", nil, 3)
        checkbox._ebsCheck:SetSize(8, 8)
        checkbox._ebsCheck:SetPoint("CENTER", checkbox._ebsBox, "CENTER", 0, 0)
        checkbox._ebsCheck:SetColorTexture(ar, ag, ab, 1)
        checkbox._ebsCheck:Hide()
    end
    local function UpdateCheck()
        if checkbox._ebsCheck then checkbox._ebsCheck:SetShown(checkbox:GetChecked()) end
    end
    checkbox:HookScript("OnClick", UpdateCheck)
    checkbox:HookScript("OnShow", UpdateCheck)
    C_Timer.After(0, UpdateCheck)
    local text = checkbox.Text or checkbox.text or (checkbox.GetName and _G[checkbox:GetName().."Text"])
    if text and text.SetFont then
        text:SetFont(fontPath, 10, "")
        text:SetTextColor(1, 1, 1, 0.8)
    end
    checkbox:HookScript("OnEnter", function()
        if checkbox._ebsBorder then checkbox._ebsBorder:SetColorTexture(0.6, 0.6, 0.6, 1) end
    end)
    checkbox:HookScript("OnLeave", function()
        if checkbox._ebsBorder then checkbox._ebsBorder:SetColorTexture(0.4, 0.4, 0.4, 1) end
    end)
end

local function SkinRaidInfoFrame()
    -- Intentionally left unstyled (Blizzard default)
end

local function SkinRaidGroup(group)
    if not group or group._ebsSkinned then return end
    group._ebsSkinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    local ar, ag, ab = EG.r, EG.g, EG.b
    local groupName = group:GetName()
    for i = 1, select("#", group:GetRegions()) do
        local region = select(i, group:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
    if not group._ebsBg then
        group._ebsBg = group:CreateTexture(nil, "BACKGROUND", nil, -8)
        group._ebsBg:SetAllPoints()
        group._ebsBg:SetColorTexture(0.025, 0.025, 0.03, 0.98)
    end
    PP.CreateBorder(group, 0.25, 0.25, 0.25, 0.9, 1, "OVERLAY", 7)
    local labelFrame = _G[groupName .. "Label"]
    if labelFrame then
        for i = 1, select("#", labelFrame:GetRegions()) do
            local region = select(i, labelFrame:GetRegions())
            if region and region:IsObjectType("FontString") then
                region:SetFont(fontPath, 10, "")
                region:SetTextColor(ar, ag, ab, 1)
                region:SetShadowOffset(1, -1)
                region:SetShadowColor(0, 0, 0, 0.9)
            end
        end
        local fontString = labelFrame.GetFontString and labelFrame:GetFontString()
        if fontString and fontString.SetFont then
            fontString:SetFont(fontPath, 10, "")
            fontString:SetTextColor(ar, ag, ab, 1)
            fontString:SetShadowOffset(1, -1)
            fontString:SetShadowColor(0, 0, 0, 0.9)
        end
    end
end

local function SkinRaidSlot(slot)
    if not slot or slot._ebsSkinned then return end
    slot._ebsSkinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    for i = 1, select("#", slot:GetRegions()) do
        local region = select(i, slot:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
    if not slot._ebsBg then
        slot._ebsBg = slot:CreateTexture(nil, "BACKGROUND", nil, -5)
        slot._ebsBg:SetAllPoints()
        slot._ebsBg:SetColorTexture(0.045, 0.045, 0.05, 0.9)
    end
    if not slot._ebsBorderCreated then
        slot._ebsBorderCreated = true
        PP.CreateBorder(slot, 0.15, 0.15, 0.15, 0.7, 1, "BORDER", 1)
    end
    for i = 1, select("#", slot:GetRegions()) do
        local region = select(i, slot:GetRegions())
        if region and region:IsObjectType("FontString") then
            region:SetFont(fontPath, 9, "")
        end
    end
    slot:HookScript("OnEnter", function()
        if slot._ebsBg then slot._ebsBg:SetColorTexture(0.07, 0.07, 0.08, 0.95) end
    end)
    slot:HookScript("OnLeave", function()
        if slot._ebsBg then slot._ebsBg:SetColorTexture(0.045, 0.045, 0.05, 0.9) end
    end)
end

local function SkinRaidGroupButton(btn)
    if not btn or btn._ebsSkinned then return end
    btn._ebsSkinned = true
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
    for i = 1, select("#", btn:GetRegions()) do
        local region = select(i, btn:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
    if not btn._ebsBg then
        btn._ebsBg = btn:CreateTexture(nil, "BACKGROUND", nil, -5)
        btn._ebsBg:SetAllPoints()
        btn._ebsBg:SetColorTexture(0.06, 0.06, 0.07, 0.95)
    end
    local bdrFrame = CreateFrame("Frame", nil, btn)
    bdrFrame:SetAllPoints(btn)
    bdrFrame:SetFrameLevel(btn:GetFrameLevel() + 1)
    PP.CreateBorder(bdrFrame, 0.3, 0.3, 0.3, 0.9, 1, "BORDER", 1)
    for i = 1, select("#", btn:GetRegions()) do
        local region = select(i, btn:GetRegions())
        if region and region:IsObjectType("FontString") then
            region:SetFont(fontPath, 9, "")
            local p1, rel, p2, ox, oy = region:GetPoint(1)
            if p1 then region:SetPoint(p1, rel, p2, (ox or 0) - 10, oy or 0) end
        end
    end
    btn:HookScript("OnEnter", function()
        if btn._ebsBg then btn._ebsBg:SetColorTexture(0.1, 0.1, 0.12, 1) end
    end)
    btn:HookScript("OnLeave", function()
        if btn._ebsBg then btn._ebsBg:SetColorTexture(0.06, 0.06, 0.07, 0.95) end
    end)
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

    -- Reposition RaidFrame content
    if raidFrame then
        raidFrame:ClearAllPoints()
        raidFrame:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", 15, -76)
        raidFrame:SetPoint("BOTTOMRIGHT", FriendsFrame, "BOTTOMRIGHT", -15, 35)

        if not raidFrame._ebsBorderAdded then
            raidFrame._ebsBorderAdded = true
            local bdr = CreateFrame("Frame", nil, raidFrame)
            bdr:SetPoint("TOPLEFT", raidFrame, "TOPLEFT", 0, 0)
            bdr:SetPoint("BOTTOMRIGHT", raidFrame, "BOTTOMRIGHT", 0, 0)
            bdr:SetFrameLevel(raidFrame:GetFrameLevel() + 2)
            PP.CreateBorder(bdr, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
        end
    end

    -- Reposition buttons
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
            raidInfoBtn:SetPoint("TOPRIGHT", scrollBox, "TOPRIGHT", 0, 54)
        end
    end

    -- Move top bar icons
    local checkBtn = _G.RaidFrameAllAssistCheckButton
    if checkBtn and not checkBtn._ebsShifted then
        checkBtn._ebsShifted = true
        local p1, rel, p2, ox, oy = checkBtn:GetPoint(1)
        if p1 then checkBtn:SetPoint(p1, rel, p2, (ox or 0) - 62, (oy or 0) + 59) end
    end
    if raidFrame then
        local roleCount = raidFrame.RoleCount
        if roleCount and not roleCount._ebsShifted then
            roleCount._ebsShifted = true
            local p1, rel, p2, ox, oy = roleCount:GetPoint(1)
            if p1 then roleCount:SetPoint(p1, rel, p2, (ox or 0) - 62, (oy or 0) + 59) end
        end
    end

    -- Reposition raid groups: 2 columns
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
    local ar, ag, ab = EG.r, EG.g, EG.b
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
        if btn and btn._ebsBtnSkinned then
            -- Hook disable/enable for alpha (one-time)
            local text = btn:GetFontString()
            btn._ebsAccent = useAccent
            if useAccent then
                if text then text:SetTextColor(EG.r, EG.g, EG.b, 0.7) end
                if btn._ppBorders then PP.SetBorderColor(btn, EG.r, EG.g, EG.b, 0.5) end
            else
                if text then text:SetTextColor(1, 1, 1, 0.5) end
                if btn._ppBorders then PP.SetBorderColor(btn, 1, 1, 1, 0.4) end
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

-- Friend data cache: populated during RebuildFriendsDataProvider, read per-button.
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
    -- Cache miss fallback
    if button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        return C_BattleNet and C_BattleNet.GetFriendAccountInfo(button.id), nil
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        return nil, C_FriendList and C_FriendList.GetFriendInfoByIndex(button.id)
    end
    return nil, nil
end

-- Direct API call version for non-scroll callers (menus, tooltips)
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

local function GetFriendKey(button, bnetInfo, wowInfo)
    if bnetInfo then
        return "bnet-" .. (bnetInfo.bnetAccountID or button.id)
    elseif wowInfo and wowInfo.name then
        return "wow-" .. wowInfo.name
    end
    return nil
end

-- Group tag stored in Blizzard friend notes as ||EUI:GroupName||
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
    -- Strip the tag to get the clean user note
    local clean = note:sub(1, tagStart - 1)
    -- Trim trailing whitespace from user note
    clean = clean:match("^(.-)%s*$") or clean
    if group == "" then return nil, clean end
    return group, clean
end

local function WriteGroupToNote(note, group)
    -- Strip any existing EUI tag first
    local _, clean = ParseGroupFromNote(note)
    if not clean then clean = "" end
    if not group or group == "" then return clean end
    if clean ~= "" then
        return clean .. " " .. EUI_NOTE_TAG .. group .. EUI_NOTE_END
    end
    return EUI_NOTE_TAG .. group .. EUI_NOTE_END
end



-- Offline icon path (displayed when friend is not online)
local OFFLINE_ICON = "Interface\\AddOns\\EllesmereUIBasics\\Media\\offline.png"

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
    -- Skip dividers
    if button.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then return end
    if not button.buttonType then return end

    local p = EBS.db.profile.friends

    -- Hide Blizzard's game icon
    local gameIcon = button.gameIcon
    if gameIcon then gameIcon:SetAlpha(0) end

    if not p.showClassIcons then
        if button._ebsClassIcon then button._ebsClassIcon:Hide() end
        return
    end

    -- Create icon texture
    if not button._ebsClassIcon then
        button._ebsClassIcon = button:CreateTexture(nil, "ARTWORK", nil, 2)
    end
    local icon = button._ebsClassIcon
    local h = button:GetHeight() - 4
    if h <= 0 then icon:Hide(); return end

    -- Determine online state
    local state = "offline"  -- default
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

    -- Apply icon based on state
    icon:ClearAllPoints()

    if state == "retail" then
        -- Class icon with small inset
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
        -- Smaller icon using Blizzard's game icon texture
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

-- Apply class color to the character name portion of a friend button
local function UpdateNameColor(button, bnetInfo, wowInfo)
    local p = EBS.db.profile.friends
    local nameText = button.name or button.Name
    if not nameText then return end

    if not p.classColorNames then return end

    local classFile = GetFriendClassFile(bnetInfo, wowInfo)
    if not classFile then return end

    if wowInfo then
        -- WoW friend: entire name is the character
        local cc = RAID_CLASS_COLORS[classFile]
        if cc then nameText:SetTextColor(cc.r, cc.g, cc.b) end
    elseif bnetInfo then
        -- BNet friend: color only the (CharName) portion
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
local FACTION_TEX_ALLIANCE = "Interface\\AddOns\\EllesmereUIBasics\\Media\\alliance.png"
local FACTION_TEX_HORDE    = "Interface\\AddOns\\EllesmereUIBasics\\Media\\horde.png"
local FACTION_TEX_NEUTRAL  = "Interface\\AddOns\\EllesmereUIBasics\\Media\\neutral.png"

-- Apply faction background overlay to a friend button
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

    if not button._ebsFactionBg then
        button._ebsFactionBg = button:CreateTexture(nil, "BACKGROUND", nil, 3)
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

    local tex = button._ebsFactionBg
    tex:SetTexture(texPath)
    tex:SetTexCoord(0, 1, 0, 1)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    tex:SetAlpha(0.2)
    tex:Show()
end



-- Skin a single friend button
local function SkinFriendButton(button)
    if button._ebsSkinned then return end
    button._ebsSkinned = true

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

    local function ApplyFont(fs, size)
        if not fs or not fs.SetFont then return end
        fs:SetFont(fontPath, size, "")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.8)
    end

    -- Tile background
    local tileBg = button:CreateTexture(nil, "BACKGROUND", nil, 2)
    tileBg:SetAllPoints()
    tileBg:SetColorTexture(0, 0, 0, 0.10)
    button._ebsTileBg = tileBg

    -- Strip Blizzard's highlight texture (SetVertexColor to avoid taint risk)
    local blizzHighlight = button:GetHighlightTexture()
    if blizzHighlight then blizzHighlight:SetVertexColor(0, 0, 0, 0) end
    button.LockHighlight = function() end
    button.UnlockHighlight = function() end

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

-- Process all visible friend buttons (used only on initial OnShow as safety net)
local function ProcessFriendButtons()
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if not scrollBox then return end
    for _, button in scrollBox:EnumerateFrames() do
        if button._ebsPendingSkinned then
            -- Re-apply pending button colors (survive settings changes)
            if button._ebsName then button._ebsName:SetTextColor(0.51, 0.784, 1, 1) end
            if button._ebsSubText then button._ebsSubText:SetTextColor(0.5, 0.5, 0.5, 0.8) end
            if button._ebsTileBg then button._ebsTileBg:SetColorTexture(0.05, 0.15, 0.20, 0.30) end
        elseif button.buttonType and button.buttonType ~= FRIENDS_BUTTON_TYPE_DIVIDER then
            SkinFriendButton(button)
            local bnetInfo, wowInfo = GetCachedFriendInfo(button)
            UpdateClassIcon(button, bnetInfo, wowInfo)
            UpdateNameColor(button, bnetInfo, wowInfo)
            UpdateFactionOverlay(button, bnetInfo, wowInfo)
        end
    end
end

-- Skin a single ScrollBox+ScrollBar pair with thin EUI track
local function SkinOneScrollbar(scrollBox, scrollBar)
    if not scrollBox or not scrollBar then return end
    if scrollBox._ebsTrack then return end

    scrollBar:SetAlpha(0)
    scrollBar:Hide()
    scrollBox._ebsScrollBar = scrollBar

    -- Parent to UIParent (parenting to FriendsListFrame taints)
    local track = CreateFrame("Frame", nil, UIParent)
    track:Hide()
    track:SetFrameStrata("HIGH")
    track:SetWidth(4)
    track:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 2, 0)
    track:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 2, 0)
    track:SetFrameLevel(scrollBox:GetFrameLevel() + 10)
    scrollBox._ebsTrack = track

    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(1, 1, 1, 0)
    trackBg:SetAllPoints()

    -- Thumb
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

    -- Hit area (wider clickable region for the scrollbar)
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
        if ext >= 1 then
            track:SetAlpha(0)
            track:Hide()
            return
        end
        if not FriendsFrame or not FriendsFrame:IsShown() then
            track:Hide()
            return
        end
        track:Show()
        track:SetAlpha(SCROLLBAR_ALPHA)
        local pct = GetPct()
        local trackH = track:GetHeight()
        local thumbH = math.max(20, trackH * ext)
        thumb:SetHeight(thumbH)
        local maxTravel = trackH - thumbH
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(pct * maxTravel))
    end

    -- Direct scroll (no smoothing, no C_Timer allocations)
    scrollBox:SetScript("OnMouseWheel", function(_, delta)
        if GetExtent() >= 1 then return end
        local step = StepToPct()
        local newPct = math.max(0, math.min(1, GetPct() - delta * step))
        scrollBar:SetScrollPercentage(newPct)
        UpdateScrollThumb()
    end)

    -- Thumb drag
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

    thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isDragging = true
        local _, cursorY = GetCursorPosition()
        dragStartY = cursorY / self:GetEffectiveScale()
        dragStartPct = GetPct()
        self:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    thumb:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    -- Hit area click-to-jump
    hitArea:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
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
    hitArea:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    -- Keep thumb in sync with Blizzard scroll changes (no C_Timer, direct call)
    if scrollBar.RegisterCallback then
        scrollBar:RegisterCallback("OnScroll", UpdateScrollThumb)
    end
    -- Update thumb when content size changes (collapse/expand, filter toggle)
    if scrollBox.RegisterCallback then
        scrollBox:RegisterCallback("OnDataRangeChanged", UpdateScrollThumb)
    end
    C_Timer.After(0.1, UpdateScrollThumb)
end

-- Skin known scrollbars by direct reference
local function SkinScrollbars()
    -- FriendsListFrame uses our own custom ScrollBox (created later),
    -- so we only hide Blizzard's native scrollbar here without creating a track.
    if FriendsListFrame then
        local bar = FriendsListFrame.ScrollBar
            or (FriendsListFrame.ScrollBox and FriendsListFrame.ScrollBox.ScrollBar)
        if bar then bar:SetAlpha(0) end
    end
    -- RecentAlliesFrame has nested structure
    if _G.RecentAlliesFrame and _G.RecentAlliesFrame.List then
        local list = _G.RecentAlliesFrame.List
        if list.ScrollBox then
            local bar = list.ScrollBox.ScrollBar or list.ScrollBar
            if bar then SkinOneScrollbar(list.ScrollBox, bar) end
        end
    end
end

-- Skin a bottom-area button (Add Friend, Send Message, etc.)
local function SkinBottomButton(btn)
    if not btn or btn._ebsBtnSkinned then return end
    btn._ebsBtnSkinned = true

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

    StripTextures(btn)

    btn._ebsBg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
    btn._ebsBg:SetColorTexture(0.025, 0.035, 0.045, 0.92)
    btn._ebsBg:SetAllPoints()

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
        if btn._ebsAccent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 1, 0.8
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if btn._ppBorders then PP.SetBorderColor(btn, r, g, b, a2) end
    end)
    btn:HookScript("OnLeave", function()
        local r, g, b, a1, a2 = 1, 1, 1, 0.5, 0.4
        if btn._ebsAccent then
            r, g, b = EG.r, EG.g, EG.b
            a1, a2 = 0.7, 0.5
        end
        if text then text:SetTextColor(r, g, b, a1) end
        if btn._ppBorders then PP.SetBorderColor(btn, r, g, b, a2) end
    end)
end

-- Skin known buttons by name instead of string-matching
local KNOWN_BUTTONS = {
    "FriendsFrameAddFriendButton",
    "FriendsFrameSendMessageButton",
    "WhoFrameWhoButton",
    "WhoFrameAddFriendButton",
    "WhoFrameGroupInviteButton",
}

local function SkinKnownButtons()
    for _, name in ipairs(KNOWN_BUTTONS) do
        local btn = _G[name]
        if btn then SkinBottomButton(btn) end
    end
end

-- Apply accent coloring to bottom buttons + pending accept buttons (called from ApplyFriends)
local function UpdateBottomButtonAccent()
    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not fp then return end
    local useAccent = fp.accentColors ~= false

    -- Helper: apply accent state to a single button (reads EG live, no caching)
    local function ApplyAccentToBtn(btn, labelFS)
        if not btn then return end
        btn._ebsAccent = useAccent
        if useAccent then
            if labelFS then labelFS:SetTextColor(EG.r, EG.g, EG.b, 0.7) end
            if btn._ppBorders then PP.SetBorderColor(btn, EG.r, EG.g, EG.b, 0.5) end
        else
            if labelFS then labelFS:SetTextColor(1, 1, 1, 0.5) end
            if btn._ppBorders then PP.SetBorderColor(btn, 1, 1, 1, 0.4) end
        end
    end

    -- Bottom buttons (Send Message, Who buttons -- skip Add Friend)
    for _, name in ipairs(KNOWN_BUTTONS) do
        local btn = _G[name]
        if btn and btn._ebsBtnSkinned and btn:IsEnabled()
           and name ~= "FriendsFrameAddFriendButton" then
            ApplyAccentToBtn(btn, btn:GetFontString())
        end
    end

    -- Pending invite accept buttons
    local sb = FriendsListFrame and FriendsListFrame.ScrollBox
    if sb then
        for _, btn in sb:EnumerateFrames() do
            if btn._ebsAcceptBtn then
                ApplyAccentToBtn(btn._ebsAcceptBtn, btn._ebsAcceptLabel)
            end
        end
    end

end

-- StaticPopup for creating a new friend group

StaticPopupDialogs["EBS_DELETE_FRIEND_GROUP"] = {
    text = "Delete group \"%s\"?\nFriends in this group will be moved to the default list.",
    button1 = DELETE,
    button2 = CANCEL,
    OnAccept = function(self)
        local gName = self.data
        if not gName then return end
        local fg = GetFriendGroupsGlobal()
        for i = #fg.friendGroups, 1, -1 do
            if fg.friendGroups[i].name == gName then
                -- Remove group tag from all Blizzard friend notes
                local numBN = BNGetNumFriends and BNGetNumFriends() or 0
                for bi = 1, numBN do
                    local bInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo(bi)
                    if bInfo and bInfo.note then
                        local g = ParseGroupFromNote(bInfo.note)
                        if g == gName then
                            local _, cleanNote = ParseGroupFromNote(bInfo.note)
                            BNSetFriendNote(bInfo.bnetAccountID, cleanNote or "")
                        end
                    end
                end
                table.remove(fg.friendGroups, i)
                break
            end
        end
        if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["EBS_NEW_FRIEND_GROUP"] = {
    text = "Enter group name:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    editBoxWidth = 200,
    OnAccept = function(self)
        local name = (self.EditBox or self.editBox):GetText()
        if not name or name == "" then return end
        local fg = GetFriendGroupsGlobal()

        -- Rename mode
        if self.data and self.data.renameFrom then
            local oldName = self.data.renameFrom
            if name ~= oldName then
                for _, g in ipairs(fg.friendGroups) do
                    if g.name == oldName then
                        g.name = name
                        break
                    end
                end
                -- Rename group tag in all Blizzard friend notes
                local numBN = BNGetNumFriends and BNGetNumFriends() or 0
                for bi = 1, numBN do
                    local bInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo(bi)
                    if bInfo and bInfo.note then
                        local g = ParseGroupFromNote(bInfo.note)
                        if g == oldName then
                            local newNote = WriteGroupToNote(bInfo.note, name)
                            -- Re-parse to get clean user note, then rebuild with new group
                            local _, cleanNote = ParseGroupFromNote(bInfo.note)
                            BNSetFriendNote(bInfo.bnetAccountID, WriteGroupToNote(cleanNote, name))
                        end
                    end
                end
            end
        else
            -- New group mode: check for duplicate
            for _, g in ipairs(fg.friendGroups) do
                if g.name == name then return end
            end
            fg.friendGroups[#fg.friendGroups + 1] = { name = name, collapsed = false }
            -- Assign the friend who triggered the dialog
            if self.data and self.data.bnetID then
                local bInfo = C_BattleNet.GetAccountInfoByID(self.data.bnetID)
                local rawNote = bInfo and bInfo.note or ""
                BNSetFriendNote(self.data.bnetID, WriteGroupToNote(rawNote, name))
            elseif self.data and self.data.wowName then
                local numWoW = C_FriendList.GetNumFriends()
                for fi = 1, numWoW do
                    local wInfo = C_FriendList.GetFriendInfoByIndex(fi)
                    if wInfo and wInfo.name == self.data.wowName then
                        local rawNote = wInfo.notes or ""
                        C_FriendList.SetFriendNotes(self.data.wowName, WriteGroupToNote(rawNote, name))
                        break
                    end
                end
            end
        end
        if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
        -- Note: _EBS_ScrollToFriend is consumed inside RebuildFriendsDataProvider
    end,
    OnShow = function(self)
        local eb = self.EditBox or self.editBox
        eb:SetText("")
        eb:SetFocus()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}



-- Inject group assignment into Blizzard's friend right-click menu
local function EBS_ModifyFriendMenu(ownerRegion, rootDescription, contextData)
    if not contextData then return end
    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
    if not fp or not fp.enabled then return end
    -- Don't add group options for Recent Allies entries
    local raf = _G.RecentAlliesFrame
    if raf and raf:IsShown() then return end

    -- Identify the friend and read current group from Blizzard note
    local isFavorite = false
    local currentGroup, currentNote, bnetID, wowName
    if contextData.bnetIDAccount then
        bnetID = contextData.bnetIDAccount
        local info = C_BattleNet and C_BattleNet.GetAccountInfoByID(bnetID)
        if info then
            isFavorite = info.isFavorite
            currentGroup, currentNote = ParseGroupFromNote(info.note)
        end
    elseif contextData.name then
        wowName = contextData.name
        local numWoW = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
        for fi = 1, numWoW do
            local wInfo = C_FriendList.GetFriendInfoByIndex(fi)
            if wInfo and wInfo.name == wowName then
                currentGroup, currentNote = ParseGroupFromNote(wInfo.notes)
                break
            end
        end
    end
    if not bnetID and not wowName then return end

    -- Favorites are managed by Blizzard, don't show our group options
    if isFavorite then return end

    local fg = GetFriendGroupsGlobal()
    local hasGroups = #fg.friendGroups > 0

    local ar, ag, ab = EG.r, EG.g, EG.b
    local accentHex = format("|cff%02x%02x%02x", ar * 255, ag * 255, ab * 255)

    rootDescription:CreateDivider()
    rootDescription:CreateTitle(accentHex .. "EUI Friend Groups|r")

    -- Helper: write group tag into Blizzard friend note
    local function SetFriendGroup(groupName)
        if bnetID then
            local info = C_BattleNet.GetAccountInfoByID(bnetID)
            local rawNote = info and info.note or ""
            local newNote = WriteGroupToNote(rawNote, groupName)
            BNSetFriendNote(bnetID, newNote)
        elseif wowName then
            local numWoW = C_FriendList.GetNumFriends()
            for fi = 1, numWoW do
                local wInfo = C_FriendList.GetFriendInfoByIndex(fi)
                if wInfo and wInfo.name == wowName then
                    local rawNote = wInfo.notes or ""
                    local newNote = WriteGroupToNote(rawNote, groupName)
                    C_FriendList.SetFriendNotes(wowName, newNote)
                    break
                end
            end
        end
    end

    -- "Add to Group" / "Move to Group" submenu
    local addLabel = currentGroup and "Move to Group" or "Add to Group"
    local addToGroup = rootDescription:CreateButton(addLabel)
    addToGroup:CreateButton("|cff00ff00+|r Add New Group", function()
        local dialog = StaticPopup_Show("EBS_NEW_FRIEND_GROUP")
        if dialog then dialog.data = { bnetID = bnetID, wowName = wowName } end
    end)
    if hasGroups then
        addToGroup:CreateDivider()
        local groupOrder = GetValidGroupOrder()
        for _, gName in ipairs(groupOrder) do
            if gName ~= ORDER_FAVORITES and gName ~= ORDER_UNGROUPED and gName ~= currentGroup then
                addToGroup:CreateButton(gName, function()
                    SetFriendGroup(gName)
                    if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
                end)
            end
        end
    end

    -- "Remove from Group" (disabled if not in a group)
    local removeBtn = rootDescription:CreateButton("Remove from Group", function()
        SetFriendGroup(nil)
        if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
    end)
    if not currentGroup then removeBtn:SetEnabled(false) end

end

-- Register with all friend menu types
if Menu and Menu.ModifyMenu then
    Menu.ModifyMenu("MENU_UNIT_FRIEND", EBS_ModifyFriendMenu)
    Menu.ModifyMenu("MENU_UNIT_FRIEND_OFFLINE", EBS_ModifyFriendMenu)
    Menu.ModifyMenu("MENU_UNIT_BN_FRIEND", EBS_ModifyFriendMenu)
    Menu.ModifyMenu("MENU_UNIT_BN_FRIEND_OFFLINE", EBS_ModifyFriendMenu)
end

-- Hook Blizzard's BNet note edit popup to strip/restore EUI group tag.
-- When the user opens "Set Note", they see only their personal note.
-- When they save, the EUI group tag is re-appended automatically.
do
    local _euiNoteGroup = nil  -- stashed group during note edit
    local origBNSet = BNSetFriendNote
    -- Pre-intercept: inject group tag BEFORE the note reaches Blizzard,
    -- so the saved note always contains the tag and no rebuild sees it missing.
    BNSetFriendNote = function(id, note)
        if _euiNoteGroup then
            local group = _euiNoteGroup
            _euiNoteGroup = nil
            if not note or not note:find(EUI_NOTE_TAG, 1, true) then
                note = WriteGroupToNote(note or "", group)
            end
        end
        return origBNSet(id, note)
    end
    local notePopup = StaticPopupDialogs["SET_BNFRIENDNOTE"]
    if notePopup then
        local origOnShow = notePopup.OnShow
        notePopup.OnShow = function(self, ...)
            if origOnShow then origOnShow(self, ...) end
            -- Blizzard sets the note text after OnShow; defer our strip
            local popup = self
            C_Timer.After(0, function()
                local eb = popup.EditBox or popup.editBox
                if eb then
                    local raw = eb:GetText() or ""
                    local group, clean = ParseGroupFromNote(raw)
                    _euiNoteGroup = group
                    if clean ~= raw then
                        eb:SetText(clean or "")
                    end
                end
            end)
        end
    end
end

-- Frame background color (used everywhere)
local FRAME_BG_R, FRAME_BG_G, FRAME_BG_B = 0.03, 0.045, 0.05

-- One-time structural setup
local function SkinFriendsFrame()
    local frame = FriendsFrame
    if not frame or friendsSkinned then return end
    friendsSkinned = true

    local p = EBS.db.profile.friends
    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT

    -- Hide Blizzard decorations
    if frame.NineSlice then frame.NineSlice:Hide() end
    if frame.Bg then frame.Bg:Hide() end
    if frame.TitleBg then frame.TitleBg:Hide() end
    if frame.TopTileStreaks then
        frame.TopTileStreaks:Hide()
        hooksecurefunc(frame.TopTileStreaks, "Show", function(self) self:Hide() end)
    end
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

    -- Resize frame (deferred to avoid tainting panel management)
    if not frame._ebsSizeSet then
        frame._ebsSizeSet = true
        local origW = frame:GetWidth()
        local origH = frame:GetHeight()
        local origListH = FriendsListFrame:GetHeight()
        local EXTRA_H = 50
        local LIST_TOP = -92
        local LIST_BOTTOM = 35
        local LIST_LEFT = 15
        local LIST_RIGHT = -15
        local function ApplySize()
            frame:SetWidth(origW - 40)
            frame:SetHeight(origH + EXTRA_H)
            FriendsListFrame:SetHeight(origListH + EXTRA_H)
            -- Re-anchor Blizzard's ScrollBox to fill the resized frame
            FriendsListFrame.ScrollBox:ClearAllPoints()
            FriendsListFrame.ScrollBox:SetPoint("TOPLEFT", FriendsListFrame, "TOPLEFT", LIST_LEFT, LIST_TOP)
            FriendsListFrame.ScrollBox:SetPoint("BOTTOMRIGHT", FriendsListFrame, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
            -- Match other sub-tab content frames to the same list pane bounds
            local function FitToListPane(f)
                if not f then return end
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", frame, "TOPLEFT", LIST_LEFT, LIST_TOP)
                f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
                -- Strip background textures from the frame and its children
                StripTextures(f)
                if f.Bg then f.Bg:Hide() end
                if f.NineSlice then f.NineSlice:Hide() end
                -- Force inner List container to fill parent
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
            FitToListPane(_G.RecruitAFriendFrame)
        end

        -- Solid backdrop behind the ScrollBox for consistent dark background
        if not FriendsListFrame.ScrollBox._ebsBackdrop then
            local bd = FriendsListFrame.ScrollBox:CreateTexture(nil, "BACKGROUND", nil, -7)
            bd:SetAllPoints()
            bd:SetColorTexture(0.02, 0.02, 0.025, 1)
            FriendsListFrame.ScrollBox._ebsBackdrop = bd
        end

        -- Scale + position helpers
        local _ebsTempPos = nil  -- ctrl-drag temporary position, cleared on hide

        local function ApplyScaleAndPosition()
            local fp = EBS.db.profile.friends
            local scale = fp.scale or 1
            frame:SetScale(scale)
            -- Match scale on our UIParent-parented ScrollBox + ScrollBar
            if frame._ebsOurScrollBox then frame._ebsOurScrollBox:SetScale(scale) end
            if frame._ebsOurScrollBar then frame._ebsOurScrollBar:SetScale(scale) end
            -- Also scale scrollbar track + hit area (parented to UIParent)
            if frame._ebsOurScrollBox and frame._ebsOurScrollBox._ebsTrack then
                frame._ebsOurScrollBox._ebsTrack:SetScale(scale)
                if frame._ebsOurScrollBox._ebsTrack._hitArea then
                    frame._ebsOurScrollBox._ebsTrack._hitArea:SetScale(scale)
                end
            end
            -- Position: saved > default Blizzard
            local pos = _ebsTempPos or fp.position
            if pos then
                local px, py = pos.x, pos.y
                local PPa = EllesmereUI and EllesmereUI.PP
                if PPa and PPa.SnapForES and px and py then
                    local es = frame:GetEffectiveScale()
                    px = PPa.SnapForES(px, es)
                    py = PPa.SnapForES(py, es)
                end
                frame:ClearAllPoints()
                frame:SetPoint(pos.point, UIParent, pos.relPoint, px, py)
            end
        end
        frame._ebsApplyScaleAndPosition = ApplyScaleAndPosition

        local function SaveFramePosition()
            local fp = EBS.db.profile.friends
            local point, _, relPoint, x, y = frame:GetPoint(1)
            if point then
                fp.position = { point = point, relPoint = relPoint, x = x, y = y }
            end
        end

        -- Drag system: shift=permanent save, ctrl=temporary (resets on close)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        local _ebsDragging = false

        frame:HookScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            if not IsShiftKeyDown() and not IsControlKeyDown() then return end
            _ebsDragging = IsShiftKeyDown() and "save" or "temp"
            self:StartMoving()
        end)
        frame:HookScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or not _ebsDragging then return end
            self:StopMovingOrSizing()
            local point, _, relPoint, x, y = self:GetPoint(1)
            if _ebsDragging == "save" then
                SaveFramePosition()
            elseif _ebsDragging == "temp" then
                _ebsTempPos = { point = point, relPoint = relPoint, x = x, y = y }
            end
            _ebsDragging = false
        end)

        frame:HookScript("OnShow", function()
            _ebsTempPos = nil  -- clear temp position on each open
            if not InCombatLockdown() then
                ApplySize()
                ApplyScaleAndPosition()
            end
        end)
        frame:HookScript("OnHide", function()
            _ebsTempPos = nil
        end)
        ApplySize()
        ApplyScaleAndPosition()
    end

    -- Dark background
    frame._ebsBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame._ebsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
    frame._ebsBg:SetAllPoints()
    frame._ebsBg:SetAlpha(1)

    -- Pixel border
    do
        local r, g, b, a = GetBorderColor(p)
        local borderAlpha = (p.showBorder ~= false) and a or 0
        PP.CreateBorder(frame, r, g, b, borderAlpha, p.borderSize or 1, "OVERLAY", 7)
    end

    -- Reparent IgnoreListWindow to UIParent so it renders above the main frame
    if frame.IgnoreListWindow then
        frame.IgnoreListWindow:SetParent(UIParent)
        frame.IgnoreListWindow:SetFrameStrata("DIALOG")
    end

    -- Reparent RaidInfoFrame to UIParent so it renders above the main frame
    if _G.RaidInfoFrame then
        _G.RaidInfoFrame:SetParent(UIParent)
        _G.RaidInfoFrame:SetFrameStrata("DIALOG")
    end

    -- Reparent FriendsTooltip to UIParent so it renders independently of the main frame
    if FriendsTooltip then
        FriendsTooltip:SetParent(UIParent)
        FriendsTooltip:SetFrameStrata("TOOLTIP")
        local _ftAdjusting = false
        hooksecurefunc(FriendsTooltip, "SetPoint", function(self, point, rel, relP, x, y)
            if _ftAdjusting then return end
            _ftAdjusting = true
            self:ClearAllPoints()
            self:SetPoint(point, rel, relP, (x or 0) - 20, y or 0)
            _ftAdjusting = false
        end)
    end

    -- Tab bar background (extends below frame for bottom tabs)
    local firstTab = _G.FriendsFrameTab1
    if firstTab then
        frame._ebsTabBarBg = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        frame._ebsTabBarBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
        frame._ebsTabBarBg:SetAlpha(1)
        frame._ebsTabBarBg:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 2)
        frame._ebsTabBarBg:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 2)
        frame._ebsTabBarBg:SetPoint("BOTTOM", firstTab, "BOTTOM", 0, 0)
    end

    -- Restyle Blizzard's tabs in-place. No custom tab frames,
    -- no OnClick, no PanelTemplates_SetTab from addon code. Blizzard handles
    -- all tab switching securely. We just change the visuals.
    local customTabs = {}
    for i = 1, frame.numTabs or 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then
            -- Strip Blizzard's tab textures
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

            -- Dark background
            if not tab._ebsBg then
                tab._ebsBg = tab:CreateTexture(nil, "BACKGROUND")
                tab._ebsBg:SetAllPoints()
                tab._ebsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)
            end

            -- Active highlight
            if not tab._activeHL then
                local activeHL = tab:CreateTexture(nil, "ARTWORK", nil, -6)
                activeHL:SetAllPoints()
                activeHL:SetColorTexture(1, 1, 1, 0.05)
                activeHL:SetBlendMode("ADD")
                activeHL:Hide()
                tab._activeHL = activeHL
            end

            -- Hide Blizzard's label (shifts on select) and use our own
            local blizLabel = tab:GetFontString()
            local labelText = blizLabel and blizLabel:GetText() or ("Tab " .. i)
            if blizLabel then blizLabel:SetTextColor(0, 0, 0, 0) end
            tab:SetPushedTextOffset(0, 0)
            local label = tab:CreateFontString(nil, "OVERLAY")
            label:SetFont(fontPath, 9, "")
            label:SetPoint("CENTER", tab, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetText(labelText)
            tab._label = label

            -- Accent underline (1px pixel-perfect)
            if not tab._underline then
                local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
                PP.DisablePixelSnap(underline)
                underline:SetHeight(PP.mult or 1)
                underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
                underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
                local ar, ag, ab = EG.r, EG.g, EG.b
                underline:SetColorTexture(ar, ag, ab, 1)
                EllesmereUI.RegAccent({ type = "solid", obj = underline, a = 1 })
                underline:Hide()
                tab._underline = underline
            end

            customTabs[i] = tab
        end
    end
    -- Track active sub-tab index (1=Friends, 2=Recent Allies) to avoid
    -- reading bliz:IsEnabled() during OnShow which taints.
    local _activeSubTab = 1

    local function UpdateCustomTabs()
        local selected = PanelTemplates_GetSelectedTab(FriendsFrame) or 1
        local isContacts = (selected == 1)
        local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
        local useAccent = fp and fp.accentColors ~= false
        for i, ct in ipairs(customTabs) do
            local isActive = (i == selected)
            if ct._label then ct._label:SetTextColor(1, 1, 1, isActive and 1 or 0.5) end
            if ct._underline then
                ct._underline:SetShown(isActive)
                if isActive then
                    if useAccent then
                        local ar, ag, ab = EG.r, EG.g, EG.b
                        ct._underline:SetColorTexture(ar, ag, ab, 1)
                    else
                        ct._underline:SetColorTexture(1, 1, 1, 0.6)
                    end
                end
            end
            if ct._activeHL then ct._activeHL:SetShown(isActive) end
        end
        -- Show/hide bottom buttons based on whether Contacts tab is active
        local addBtn = _G.FriendsFrameAddFriendButton
        local msgBtn = _G.FriendsFrameSendMessageButton
        if addBtn then addBtn:SetShown(isContacts) end
        if msgBtn then msgBtn:SetShown(isContacts) end
        if frame._ebsOfflineBtn then frame._ebsOfflineBtn:SetShown(isContacts) end
        -- Show top links on all tabs except Raid
        local showTopUI = (selected ~= 3)
        -- Deselect all top sub-tabs when not on Contacts
        if not isContacts and frame._ebsSubTabs then
            for _, ct in ipairs(frame._ebsSubTabs) do
                ct._label:SetTextColor(1, 1, 1, 0.53)
                ct:SetShown(showTopUI)
            end
        elseif frame._ebsSubTabs then
            for _, ct in ipairs(frame._ebsSubTabs) do
                ct:Show()
            end
            -- Refresh sub-tab active states
            if frame._ebsUpdateSubTabs then frame._ebsUpdateSubTabs() end
        end
        -- Title, divider, search always visible; orb hidden on raid
        if frame._ebsStatusOrb then frame._ebsStatusOrb:SetShown(selected ~= 3) end
        if frame._ebsTitleBtn then frame._ebsTitleBtn:Show() end
        if frame._ebsTitleDiv then frame._ebsTitleDiv:Show() end
        -- Disable/enable search bar
        local searchBox = frame._ebsSearchBox
        if searchBox then
            searchBox:SetShown(selected ~= 3)
            searchBox:SetEnabled(isContacts)
            searchBox:SetAlpha(isContacts and 1 or 0.3)
            if not isContacts then
                searchBox:ClearFocus()
                searchBox:EnableMouse(false)
            else
                searchBox:EnableMouse(true)
            end
        end
        -- Sync scrollbar visibility based on selected tab (don't read IsVisible
        -- from Blizzard ScrollBoxes -- that taints during OnShow in combat)
        local function SetTrackVis(sb, vis)
            if sb and sb._ebsTrack then
                sb._ebsTrack:SetShown(vis)
                if sb._ebsTrack._hitArea then sb._ebsTrack._hitArea:SetShown(vis) end
            end
        end
        -- Show/hide our custom ScrollBox (only when FriendsFrame is open)
        if frame._ebsOurScrollBox then
            frame._ebsOurScrollBox:SetShown(frame:IsShown() and isContacts and _activeSubTab == 1)
        end
        local friendsSB = FriendsListFrame and FriendsListFrame.ScrollBox
        SetTrackVis(friendsSB, isContacts and _activeSubTab == 1)
        -- Also sync our ScrollBox's scrollbar track
        if frame._ebsOurScrollBox then
            SetTrackVis(frame._ebsOurScrollBox, isContacts and _activeSubTab == 1)
        end
        local raf = _G.RecentAlliesFrame
        if raf and raf.List then SetTrackVis(raf.List.ScrollBox, isContacts and _activeSubTab == 2) end
        local who = _G.WhoFrame
        if who then SetTrackVis(who.ScrollBox or (who.List and who.List.ScrollBox), selected == 2) end
    end

    frame._ebsUpdateCustomTabs = UpdateCustomTabs

    -- Update our tab visuals when Blizzard switches tabs (secure hook,
    -- only updates visuals, never calls PanelTemplates_SetTab).
    hooksecurefunc("PanelTemplates_SetTab", function(f)
        if f ~= FriendsFrame then return end
        UpdateCustomTabs()
        local selected = PanelTemplates_GetSelectedTab(FriendsFrame) or 1
        if selected == 3 then
            C_Timer.After(0, function() SkinRaidTab() end)
        end
    end)

    -- Update tab visuals on frame show
    frame:HookScript("OnShow", function()
        UpdateCustomTabs()
    end)

    -- Hide all scrollbar tracks when FriendsFrame closes
    frame:HookScript("OnHide", function()
        local function HideTrack(sb)
            if sb and sb._ebsTrack then
                sb._ebsTrack:Hide()
                if sb._ebsTrack._hitArea then sb._ebsTrack._hitArea:Hide() end
            end
        end
        HideTrack(FriendsListFrame and FriendsListFrame.ScrollBox)
        if frame._ebsOurScrollBox then
            frame._ebsOurScrollBox:Hide()
            HideTrack(frame._ebsOurScrollBox)
        end
        _activeSubTab = 1  -- reset to match Blizzard's default on reopen
        local raf = _G.RecentAlliesFrame
        if raf and raf.List then HideTrack(raf.List.ScrollBox) end
        local who = _G.WhoFrame
        if who then HideTrack(who.ScrollBox or (who.List and who.List.ScrollBox)) end
    end)

    -- Title text -- show BNet tag, accent colored
    -- Hide Blizzard's title
    if frame.TitleContainer then
        local blizTitle = frame.TitleContainer.TitleText or frame.TitleContainer:GetFontString()
        if blizTitle then blizTitle:SetAlpha(0) end
    elseif FriendsFrameTitleText then
        FriendsFrameTitleText:SetAlpha(0)
    end

    -- Our own title button (clickable, sized to text only so drag works around it)
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

    -- Size button to text bounds
    local textW = titleLabel:GetStringWidth() or 60
    titleBtn:SetSize(textW + 16, 20)
    titleBtn:SetPoint("TOP", frame, "TOP", 0, -5)

    titleBtn._label = titleLabel
    frame._ebsTitleBtn = titleBtn

    -- Hover: brighten to 100%
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
    frame._ebsTitleDiv = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame._ebsTitleDiv:SetColorTexture(1, 1, 1, 0.06)
    frame._ebsTitleDiv:SetHeight(1)
    frame._ebsTitleDiv:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    frame._ebsTitleDiv:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -30)

    -- BattleNet ID bar reskin
    -- Hide Blizzard's status dropdown and BNet bar
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
            bnetFrame.BroadcastFrame:SetAlpha(1)
            bnetFrame.BroadcastFrame:EnableMouse(true)
        end
        -- Collapse the bnet frame to reclaim vertical space
        bnetFrame:SetHeight(1)
    end

    -- Status orb + arrow will be placed on the sub-tabs row (created later in SkinSubTabs)
    -- Store references for SkinSubTabs to use
    local function GetPlayerStatusName()
        -- Guard against secret boolean return values to avoid taint
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
    frame._ebsGetPlayerStatus = GetPlayerStatusName

    -- Custom sub-tabs (Friends/Recent Allies/Recruit A Friend)
    local customSubTabs = {}
    frame._ebsSubTabs = customSubTabs
    local function SkinSubTabs()
        local tabHeader = _G.FriendsTabHeader
        if not tabHeader then return end
        local tabSystem = tabHeader.TabSystem
        if not tabSystem then return end

        -- Collect Blizzard sub-tab names and click references
        local blizSubTabs = {}
        for i = 1, select("#", tabSystem:GetChildren()) do
            local st = select(i, tabSystem:GetChildren())
            if st and st:IsObjectType("Button") then
                local text = st:GetFontString()
                local name = text and text:GetText() or ("Tab " .. i)
                blizSubTabs[#blizSubTabs + 1] = { blizTab = st, name = name }
            end
        end

        -- Hide Blizzard sub-tabs and header textures
        for _, info in ipairs(blizSubTabs) do
            info.blizTab:SetAlpha(0)
            info.blizTab:SetHeight(1)
            info.blizTab:EnableMouse(false)
        end
        StripTextures(tabHeader)
        if tabSystem then StripTextures(tabSystem) end

        -- Update function
        local function UpdateSubTabs()
            local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
            local useAccent = fp and fp.accentColors ~= false
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
        frame._ebsUpdateSubTabs = function()
            UpdateSubTabWidths()
            UpdateSubTabs()
        end

        -- Build custom sub-tabs
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


            -- Hover (only interactive when on Contacts bottom tab)
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
                    local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
                    if fp and fp.accentColors ~= false then
                        local ar, ag, ab = EG.r, EG.g, EG.b
                        ct._label:SetTextColor(ar, ag, ab, 1)
                    else
                        ct._label:SetTextColor(1, 1, 1, 1)
                    end
                else
                    ct._label:SetTextColor(1, 1, 1, 0.53)
                end
            end)

            -- Click: switch to Contacts if needed, then trigger the Blizzard sub-tab
            ct:SetScript("OnClick", function()
                local bliz = blizSubTabs[i] and blizSubTabs[i].blizTab
                -- Skip if already selected
                local isSelected = bliz and bliz.IsEnabled and not bliz:IsEnabled()
                if isSelected then return end
                local tabName = info.name or ""
                -- Recruit A Friend opens a popup, don't switch tabs
                if strfind(tabName, "Recruit") then
                    -- Open RAF popup, then restore our tab state so nothing visually changes
                    local savedSubTab = _activeSubTab
                    if RecruitAFriendFrame and RecruitAFriendFrame.RecruitmentButton then
                        RecruitAFriendFrame.RecruitmentButton:Click()
                    end
                    _activeSubTab = savedSubTab
                    UpdateSubTabs()
                    UpdateCustomTabs()
                    return
                else
                    -- Switch to Contacts bottom tab if needed
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

            -- Width set in UpdateSubTabWidths on each OnShow
            ct:SetWidth(60)  -- placeholder
            if i == 1 then
                ct:SetPoint("TOPLEFT", FriendsListFrame, "TOPLEFT", 15, -70)
            else
                ct:SetPoint("LEFT", customSubTabs[i - 1], "RIGHT", 20, 0)
            end

            customSubTabs[i] = ct
        end

        -- Extra sub-tab: "Ignored" (opens Blizzard ignore list)
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

            ct:SetWidth(60)  -- placeholder, updated in UpdateSubTabWidths
            ct:SetPoint("LEFT", customSubTabs[idx - 1], "RIGHT", 20, 0)
            customSubTabs[idx] = ct
        end

        -- Status orb on the right side of the sub-tabs row
        local lastSubTab = customSubTabs[#customSubTabs]
        if lastSubTab then
            local GetPlayerStatusName = frame._ebsGetPlayerStatus

            -- Status orb 
            local orbBtn = CreateFrame("Button", nil, frame)
            orbBtn:SetSize(26, 26)
            orbBtn:SetFrameLevel(frame:GetFrameLevel() + 5)
            orbBtn:SetPoint("RIGHT", FriendsListFrame, "TOPRIGHT", -10, -80)
            local orbTex = orbBtn:CreateTexture(nil, "ARTWORK", nil, 2)
            orbTex:SetAllPoints()
            orbTex:SetPoint("CENTER", orbBtn, "CENTER", 0, 0)
            local orbInfo = C_Texture.GetAtlasInfo("lootroll-animreveal-a")
            if orbInfo then
                orbTex:SetTexture(orbInfo.file)
                local aL = orbInfo.leftTexCoord or 0
                local aR = orbInfo.rightTexCoord or 1
                local aT = orbInfo.topTexCoord or 0
                local aB = orbInfo.bottomTexCoord or 1
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
                local status = GetPlayerStatusName()
                if status == (FRIENDS_LIST_ONLINE or "Online") then
                    -- Online -> Away
                    SendChatMessage("", "AFK")
                    if BNSetAFK then BNSetAFK(true) end
                elseif status == (AWAY or "Away") then
                    -- Away -> Busy
                    SendChatMessage("", "AFK")  -- clear AFK
                    SendChatMessage("", "DND")
                    if BNSetAFK then BNSetAFK(false) end
                    if BNSetDND then BNSetDND(true) end
                else
                    -- Busy -> Online
                    SendChatMessage("", "DND")
                    if BNSetDND then BNSetDND(false) end
                    if BNSetAFK then BNSetAFK(false) end
                end
            end)
            local function UpdateOrbTooltip()
                if orbBtn:IsMouseOver() then
                    EllesmereUI.ShowWidgetTooltip(orbBtn, "Status: " .. GetPlayerStatusName() .. "\nClick to change")
                end
            end
            orbBtn:SetScript("OnEnter", function(self)
                EllesmereUI.ShowWidgetTooltip(self, "Status: " .. GetPlayerStatusName() .. "\nClick to change")
            end)
            orbBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local statusEvt = CreateFrame("Frame")
            statusEvt:RegisterEvent("PLAYER_FLAGS_CHANGED")
            statusEvt:SetScript("OnEvent", function()
                UpdatePlayerOrb()
                UpdateOrbTooltip()
            end)

            frame._ebsStatusOrb = orbBtn
        end

        -- Initial state: default first tab to active, then verify
        if customSubTabs[1] then
            customSubTabs[1]._label:SetTextColor(1, 1, 1, 1)
        end
        C_Timer.After(0.1, UpdateSubTabs)
        C_Timer.After(0.5, UpdateSubTabs)
        -- Also update on frame show
        frame:HookScript("OnShow", function()
            C_Timer.After(0.1, UpdateSubTabs)
        end)
    end
    SkinSubTabs()

    -- Recent Allies: custom element factory and DataProvider for styled buttons
    do
        local raf = _G.RecentAlliesFrame
        if raf and raf.List and raf.List.ScrollBox then
            local rafSB = raf.List.ScrollBox

            -- Race ID -> faction lookup
            local RACE_FACTION = {}
            do
                local horde = {2,5,6,8,9,10,26,27,28,31,35,36,70,85}
                local alliance = {1,3,4,7,11,22,25,29,30,32,34,37,52,84}
                for _, id in ipairs(horde) do RACE_FACTION[id] = "Horde" end
                for _, id in ipairs(alliance) do RACE_FACTION[id] = "Alliance" end
            end
            local FACTION_TEX = "Interface\\AddOns\\EllesmereUIBasics\\Media\\"

            -- Orb atlas info: uses file-scope _orbFile, _orbL, _orbR, _orbT, _orbB

            local raFontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
            local _raSelectedGUID = nil

            -- Element initializer: fully style a plain Button as an RA entry
            local function InitRAButton(btn, elementData)
                btn:SetHeight(34)
                local cd = elementData.characterData
                local sd = elementData.stateData
                local fp = EBS.db.profile.friends
                local isOnline = sd and sd.isOnline

                -- One-time texture creation
                if not btn._ebsRASkinned then
                    btn._ebsRASkinned = true

                    -- Blizzard's selection system expects this method
                    function btn:SetSelected(selected)
                        if self._ebsSelected then
                            self._ebsSelected:SetShown(selected)
                        end
                    end

                    btn._ebsTileBg = btn:CreateTexture(nil, "BACKGROUND", nil, -4)
                    btn._ebsTileBg:SetAllPoints()

                    -- 10% lighten overlay
                    local lighten = btn:CreateTexture(nil, "BACKGROUND", nil, -3)
                    lighten:SetAllPoints()
                    lighten:SetColorTexture(1, 1, 1, 0.02)

                    btn._ebsFactionBg = btn:CreateTexture(nil, "ARTWORK", nil, -8)
                    btn._ebsFactionBg:SetAllPoints()
                    btn._ebsFactionBg:SetAlpha(0.2)

                    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
                    hover:SetAllPoints()
                    hover:SetColorTexture(1, 1, 1, 0.05)
                    hover:SetBlendMode("ADD")

                    -- Selection highlight
                    btn._ebsSelected = btn:CreateTexture(nil, "ARTWORK", nil, -7)
                    btn._ebsSelected:SetAllPoints()
                    btn._ebsSelected:SetColorTexture(1, 1, 1, 0.08)
                    btn._ebsSelected:Hide()

                    btn._ebsClassIcon = btn:CreateTexture(nil, "ARTWORK", nil, 2)

                    btn._ebsStatusOrb = btn:CreateTexture(nil, "OVERLAY", nil, 3)
                    btn._ebsStatusOrb:SetSize(18, 18)
                    if _orbFile then
                        btn._ebsStatusOrb:SetTexture(_orbFile)
                        btn._ebsStatusOrb:SetTexCoord(_orbL, _orbR, _orbT, _orbB)
                    end

                    btn._ebsName = btn:CreateFontString(nil, "OVERLAY")
                    btn._ebsName:SetFont(raFontPath, 12, "")
                    btn._ebsName:SetShadowOffset(1, -1)
                    btn._ebsName:SetShadowColor(0, 0, 0, 0.8)
                    btn._ebsName:SetPoint("TOPLEFT", btn, "TOPLEFT", 38, -4)
                    btn._ebsName:SetJustifyH("LEFT")

                    btn._ebsInfoLine = btn:CreateFontString(nil, "OVERLAY")
                    btn._ebsInfoLine:SetFont(raFontPath, 9, "")
                    btn._ebsInfoLine:SetShadowOffset(1, -1)
                    btn._ebsInfoLine:SetShadowColor(0, 0, 0, 0.8)
                    btn._ebsInfoLine:SetTextColor(0.5, 0.5, 0.5, 0.8)
                    btn._ebsInfoLine:SetPoint("TOPLEFT", btn._ebsName, "BOTTOMLEFT", 0, -3)
                    btn._ebsInfoLine:SetJustifyH("LEFT")

                    -- Invite to Group button (right side, matching friends list)
                    local invBtn = CreateFrame("Button", nil, btn)
                    invBtn:SetSize(24, 32)
                    invBtn:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
                    invBtn:SetFrameLevel(btn:GetFrameLevel() + 3)
                    invBtn:SetNormalAtlas("friendslist-invitebutton-default-normal")
                    invBtn:SetPushedAtlas("friendslist-invitebutton-default-pressed")
                    invBtn:SetHighlightAtlas("friendslist-invitebutton-highlight")
                    invBtn:SetScript("OnEnter", function(self)
                        EllesmereUI.ShowWidgetTooltip(self, PARTY_INVITE)
                    end)
                    invBtn:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    invBtn:SetScript("OnClick", function()
                        local ed = btn._ebsElementData
                        if ed and ed.characterData then
                            local fullName = ed.characterData.fullName
                            if fullName and ed.stateData and ed.stateData.isOnline then
                                C_PartyInfo.InviteUnit(fullName)
                            end
                        end
                    end)
                    btn._ebsInvBtn = invBtn

                    -- Click: left = select, right = context menu
                    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    btn:SetScript("OnClick", function(self, button)
                        local ed = self._ebsElementData
                        if not ed or not ed.characterData then return end
                        local c = ed.characterData
                        local guid = c.guid
                        if button == "LeftButton" then
                            _raSelectedGUID = guid
                            local st = rafSB.ScrollTarget
                            if st then
                                for j = 1, select("#", st:GetChildren()) do
                                    local b = select(j, st:GetChildren())
                                    if b._ebsSelected then
                                        local bGUID = b._ebsElementData and b._ebsElementData.characterData and b._ebsElementData.characterData.guid
                                        b._ebsSelected:SetShown(bGUID == _raSelectedGUID)
                                    end
                                end
                            end
                        elseif button == "RightButton" then
                            -- Blizzard context menu via unit GUID
                            if guid then
                                FriendsFrame_ShowDropdown(c.fullName or c.name, ed.stateData and ed.stateData.isOnline, nil, nil, nil, true)
                            end
                        end
                    end)

                    -- Blizzard tooltip on hover
                    btn:SetScript("OnEnter", function(self)
                        local ed = self._ebsElementData
                        if not ed or not ed.characterData then return end
                        local c = ed.characterData
                        local s = ed.stateData
                        local lines = {}
                        lines[#lines + 1] = c.name or ""
                        if c.realmName and c.realmName ~= "" then
                            lines[#lines + 1] = c.realmName
                        end
                        if s then
                            if s.isOnline then
                                local status = FRIENDS_LIST_ONLINE or "Online"
                                local _isv2 = issecretvalue
                                local sDND = s.isDND; local sAFK = s.isAFK
                                if (not _isv2 or not _isv2(sDND)) and sDND then status = BUSY or "Busy"
                                elseif (not _isv2 or not _isv2(sAFK)) and sAFK then status = AWAY or "Away" end
                                if s.currentLocation and s.currentLocation ~= "" then
                                    status = status .. " - " .. s.currentLocation
                                end
                                lines[#lines + 1] = status
                            else
                                lines[#lines + 1] = FRIENDS_LIST_OFFLINE or "Offline"
                            end
                        end
                        if ed.interactionData and ed.interactionData.interactions then
                            local inter = ed.interactionData.interactions
                            if #inter > 0 and inter[1].description then
                                lines[#lines + 1] = inter[1].description
                            end
                        end
                        EllesmereUI.ShowWidgetTooltip(self, table.concat(lines, "\n"))
                    end)
                    btn:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

                -- Store elementData reference for click/tooltip handlers
                btn._ebsElementData = elementData

                -- Selection highlight
                btn._ebsSelected:SetShown(cd.guid == _raSelectedGUID)

                -- Tile bg
                btn._ebsTileBg:SetColorTexture(0, 0, 0, 0.10)

                -- Class icon
                local icon = btn._ebsClassIcon
                local classFile
                if cd.classID and cd.classID > 0 then
                    local _, cf = GetClassInfo(cd.classID)
                    classFile = cf
                end
                if classFile and fp.showClassIcons ~= false then
                    local h = 30
                    local inset = math.floor(h * 0.025 + 0.5)
                    icon:ClearAllPoints()
                    icon:SetPoint("LEFT", btn, "LEFT", 4, 0)
                    icon:SetPoint("TOP", btn, "TOP", 0, -(2 + inset))
                    icon:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2 + inset)
                    local iconH = h - inset * 2
                    if iconH > 0 then icon:SetWidth(iconH) end
                    local style = fp.iconStyle or "modern"
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
                    if isOnline then
                        icon:SetDesaturated(false)
                        icon:SetAlpha(1)
                    else
                        icon:SetTexture(OFFLINE_ICON)
                        icon:SetTexCoord(0, 1, 0, 1)
                        icon:SetAlpha(0.5)
                    end
                    icon:Show()
                else
                    icon:Hide()
                end

                -- Faction overlay (respect factionBanners setting)
                local showFaction = fp and fp.factionBanners ~= false
                local faction = showFaction and isOnline and RACE_FACTION[cd.raceID] or nil
                local texPath
                if faction == "Alliance" then texPath = FACTION_TEX .. "alliance.png"
                elseif faction == "Horde" then texPath = FACTION_TEX .. "horde.png"
                else texPath = FACTION_TEX .. "neutral.png" end
                btn._ebsFactionBg:SetTexture(texPath)
                btn._ebsFactionBg:SetTexCoord(0, 1, 0, 1)

                -- Name: class-colored if online, white 75% if offline
                local nameText = cd.name or ""
                if isOnline and classFile and fp.classColorNames ~= false then
                    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                    if cc then
                        nameText = format("|cff%02x%02x%02x%s|r", cc.r * 255, cc.g * 255, cc.b * 255, nameText)
                    end
                elseif not isOnline then
                    nameText = "|cffbfbfbf" .. nameText .. "|r"
                end
                btn._ebsName:SetText(nameText)
                btn._ebsName:SetWidth(0)

                -- Status orb
                local orb = btn._ebsStatusOrb
                if isOnline then
                    local _isv3 = issecretvalue
                    local sdDND = sd.isDND; local sdAFK = sd.isAFK
                    if (not _isv3 or not _isv3(sdDND)) and sdDND then orb:SetVertexColor(1, 0.2, 0.2, 1)
                    elseif (not _isv3 or not _isv3(sdAFK)) and sdAFK then orb:SetVertexColor(1, 0.8, 0, 1)
                    else orb:SetVertexColor(0.2, 1, 0.2, 1) end
                else
                    orb:SetVertexColor(0.4, 0.4, 0.4, 0.6)
                end
                orb:ClearAllPoints()
                orb:SetPoint("LEFT", btn._ebsName, "RIGHT", -3, 1)
                orb:Show()

                -- Invite button: enabled for online, disabled for offline
                if btn._ebsInvBtn then
                    if isOnline then
                        btn._ebsInvBtn:SetNormalAtlas("friendslist-invitebutton-default-normal")
                        btn._ebsInvBtn:Enable()
                        btn._ebsInvBtn:SetAlpha(1)
                    else
                        btn._ebsInvBtn:SetNormalAtlas("friendslist-invitebutton-default-disabled")
                        btn._ebsInvBtn:Disable()
                        btn._ebsInvBtn:SetAlpha(0.4)
                    end
                end

                -- Info line: "Activity | Location"
                local activity = ""
                if elementData.interactionData and elementData.interactionData.interactions then
                    local interactions = elementData.interactionData.interactions
                    if #interactions > 0 then
                        activity = interactions[1].description or ""
                    end
                end
                local location = sd and sd.currentLocation or ""
                if activity ~= "" and location ~= "" then
                    btn._ebsInfoLine:SetText(activity .. "  |cff666666|  |r" .. location)
                elseif activity ~= "" then
                    btn._ebsInfoLine:SetText(activity)
                elseif location ~= "" then
                    btn._ebsInfoLine:SetText(location)
                else
                    btn._ebsInfoLine:SetText("")
                end
            end

            local RA_TYPE_DIVIDER = "ra_divider"
            local RA_TYPE_ALLY = "ra_ally"

            -- Divider initializer (same style as friends list "Friends" divider)
            local function InitRADivider(btn, elementData)
                btn:SetHeight(20)
                if not btn._ebsDivSetup then
                    btn._ebsDivSetup = true
                    btn:EnableMouse(false)

                    btn._ebsDivBg = btn:CreateTexture(nil, "BACKGROUND")
                    btn._ebsDivBg:SetAllPoints()
                    btn._ebsDivBg:SetColorTexture(0.059, 0.062, 0.065, 1)

                    btn._ebsDivLabel = btn:CreateFontString(nil, "OVERLAY")
                    btn._ebsDivLabel:SetFont(raFontPath, 9, "")
                    btn._ebsDivLabel:SetShadowOffset(1, -1)
                    btn._ebsDivLabel:SetShadowColor(0, 0, 0, 0.8)
                    btn._ebsDivLabel:SetTextColor(1, 1, 1, 0.4)
                    btn._ebsDivLabel:SetPoint("CENTER", btn, "CENTER", 0, 0)

                    btn._ebsDivLineL = btn:CreateTexture(nil, "OVERLAY")
                    btn._ebsDivLineL:SetColorTexture(1, 1, 1, 0.1)
                    btn._ebsDivLineL:SetHeight(1)
                    btn._ebsDivLineL:SetPoint("LEFT", btn, "LEFT", 8, 0)
                    btn._ebsDivLineL:SetPoint("RIGHT", btn._ebsDivLabel, "LEFT", -6, 0)

                    btn._ebsDivLineR = btn:CreateTexture(nil, "OVERLAY")
                    btn._ebsDivLineR:SetColorTexture(1, 1, 1, 0.1)
                    btn._ebsDivLineR:SetHeight(1)
                    btn._ebsDivLineR:SetPoint("LEFT", btn._ebsDivLabel, "RIGHT", 6, 0)
                    btn._ebsDivLineR:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
                end
                btn._ebsDivLabel:SetText(elementData.text or "")
            end

            -- Register our own view on the RA ScrollBox
            do
                local view = CreateScrollBoxListLinearView()
                view:SetPadding(0, 0, 0, 0, 2)
                view:SetElementExtentCalculator(function(dataIndex, elementData)
                    if elementData.entryType == RA_TYPE_DIVIDER then return 20 end
                    return 34
                end)
                view:SetElementFactory(function(factory, elementData)
                    if elementData.entryType == RA_TYPE_DIVIDER then
                        factory("Frame", function(btn, ed)
                            InitRADivider(btn, ed)
                        end)
                    else
                        factory("Button", function(btn, ed)
                            InitRAButton(btn, ed)
                        end)
                    end
                end)
                local scrollBar = rafSB.ScrollBar or raf.List.ScrollBar
                ScrollUtil.InitScrollBoxListWithScrollBar(rafSB, scrollBar, view)
            end

            -- Build DataProvider from C_RecentAllies API
            local _raSearchTerm = ""
            local function RebuildRADataProvider()
                if not C_RecentAllies or not C_RecentAllies.GetRecentAllies then return end
                local allies = C_RecentAllies.GetRecentAllies()
                if not allies then return end

                -- Build DataProvider preserving Blizzard's sort order
                -- Insert dividers at online/offline boundaries
                local newDP = CreateDataProvider()
                local insertedOnline = false
                local insertedOffline = false
                for _, ally in ipairs(allies) do
                    local cd = ally.characterData
                    if _raSearchTerm == "" or strfind((cd.name or ""):lower(), _raSearchTerm, 1, true) then
                        local isOnline = ally.stateData and ally.stateData.isOnline
                        if isOnline and not insertedOnline then
                            insertedOnline = true
                            newDP:Insert({ entryType = RA_TYPE_DIVIDER, text = "Recent Allies" })
                        elseif not isOnline and not insertedOffline then
                            insertedOffline = true
                            newDP:Insert({ entryType = RA_TYPE_DIVIDER, text = "Recent Allies (Offline)" })
                        end
                        newDP:Insert({
                            entryType = RA_TYPE_ALLY,
                            characterData = cd,
                            stateData = ally.stateData,
                            interactionData = ally.interactionData,
                        })
                    end
                end
                rafSB:SetDataProvider(newDP, true)
            end

            -- Loading indicator
            local raLoader = CreateFrame("Frame", nil, raf)
            raLoader:SetAllPoints(rafSB)
            raLoader:SetFrameLevel(rafSB:GetFrameLevel() + 20)
            raLoader:Hide()
            do
                local ar, ag, ab = EG.r, EG.g, EG.b
                local ring = raLoader:CreateTexture(nil, "ARTWORK")
                ring:SetSize(28, 28)
                ring:SetPoint("CENTER", raLoader, "CENTER", 0, 0)
                ring:SetAtlas("charactercreate-icon-customize-arrow-right")
                ring:SetVertexColor(ar, ag, ab, 0.6)
                local spinGroup = ring:CreateAnimationGroup()
                spinGroup:SetLooping("REPEAT")
                local spin = spinGroup:CreateAnimation("Rotation")
                spin:SetDegrees(-360)
                spin:SetDuration(1.2)
                raLoader._spinGroup = spinGroup
                local pulseGroup = raLoader:CreateAnimationGroup()
                pulseGroup:SetLooping("BOUNCE")
                local fadeOut = pulseGroup:CreateAnimation("Alpha")
                fadeOut:SetFromAlpha(1)
                fadeOut:SetToAlpha(0.4)
                fadeOut:SetDuration(0.8)
                fadeOut:SetSmoothing("IN_OUT")
                raLoader._pulseGroup = pulseGroup
            end

            local _raLoaded = false
            local function ShowRALoader()
                raLoader:Show()
                raLoader._spinGroup:Play()
                raLoader._pulseGroup:Play()
            end
            local function _hideRALoaderDeferred()
                raLoader._spinGroup:Stop()
                raLoader._pulseGroup:Stop()
                raLoader:Hide()
            end
            local function HideRALoader()
                C_Timer.After(0, _hideRALoaderDeferred)
            end

            -- Tab show: wait for data ready, then build
            raf:HookScript("OnShow", function()
                _raLoaded = false
                ShowRALoader()
                local function TryBuild()
                    if C_RecentAllies and C_RecentAllies.IsRecentAllyDataReady
                        and C_RecentAllies.IsRecentAllyDataReady() then
                        RebuildRADataProvider()
                        _raLoaded = true
                        HideRALoader()
                    else
                        C_Timer.After(0.25, TryBuild)
                    end
                end
                TryBuild()
            end)

            -- Listen for RA-specific data updates only
            local raEvents = CreateFrame("Frame")
            raEvents:RegisterEvent("RECENT_ALLIES_DATA_READY")
            raEvents:RegisterEvent("RECENT_ALLIES_CACHE_UPDATE")
            raEvents:RegisterEvent("RECENT_ALLY_DATA_UPDATED")
            raEvents:SetScript("OnEvent", function()
                if raf:IsShown() then
                    RebuildRADataProvider()
                    if not _raLoaded then
                        _raLoaded = true
                        HideRALoader()
                    end
                end
            end)

            -- Hook Send Message button to whisper selected RA entry
            local msgBtn = _G.FriendsFrameSendMessageButton
            if msgBtn then
                msgBtn:HookScript("OnClick", function()
                    if not raf:IsShown() then return end
                    if not _raSelectedGUID then return end
                    local allyData = C_RecentAllies.GetRecentAllyByGUID(_raSelectedGUID)
                    if allyData and allyData.characterData then
                        local fullName = allyData.characterData.fullName
                        if fullName then
                            ChatFrame_SendTell(fullName)
                        end
                    end
                end)
            end

            -- Clear selection on tab switch
            raf:HookScript("OnHide", function()
                _raSelectedGUID = nil
            end)

            -- Store for search
            frame._ebsRebuildRA = RebuildRADataProvider
            frame._ebsRAScrollBox = rafSB
            frame._ebsRASetSearch = function(term)
                _raSearchTerm = term
                if raf:IsShown() and _raLoaded then RebuildRADataProvider() end
            end
        end
    end

    -- Search bar (below sub-tabs, above ScrollBox)
    local _ebsSearchTerm = ""
    do
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
        sPh:SetText("Search...")

        -- Clear button (small x on the right)
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

        search:SetTextInsets(6, 18, 0, 0)  -- extra right inset for clear button

        search:SetScript("OnTextChanged", function(self)
            local t = strtrim(self:GetText())
            sPh:SetShown(t == "")
            clearBtn:SetShown(t ~= "")
            _ebsSearchTerm = t:lower()
            -- Filter friends list
            if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
            -- Filter Recent Allies via DataProvider rebuild
            if frame._ebsRASetSearch then frame._ebsRASetSearch(_ebsSearchTerm) end
        end)
        search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

        frame._ebsSearchBox = search
    end

    -- Skin scrollbars
    SkinScrollbars()

    -- Scroll-pause: skip ALL hook work while user is actively scrolling.
    -- ProcessFriendButtons runs once when scrolling stops to catch up.
    local _ebsScrolling = false
    local _ebsScrollTimer = nil
    local _ebsScrollLast = 0
    local SCROLL_PAUSE = 0.3    -- seconds after last scroll event to resume updates
    local SCROLL_THROTTLE = 0.1 -- minimum seconds between timer resets

    local function _ebsOnScrollStop()
        _ebsScrolling = false
        _ebsScrollTimer = nil
        -- Clear stamps and restyle so live data updates (AFK, offline) are picked up
        if FriendsFrame:IsShown() then
            local sb = FriendsListFrame and FriendsListFrame.ScrollBox
            if sb then
                for _, btn in sb:EnumerateFrames() do
                    btn._ebsStampType = nil
                end
            end
            ProcessFriendButtons()
        end
    end

    local function _ebsOnScrollActivity()
        _ebsScrolling = true
        local now = GetTime()
        if now - _ebsScrollLast < SCROLL_THROTTLE then return end
        _ebsScrollLast = now
        if _ebsScrollTimer then _ebsScrollTimer:Cancel() end
        _ebsScrollTimer = C_Timer.NewTimer(SCROLL_PAUSE, _ebsOnScrollStop)
    end

    -- Inject scroll detection into the friends ScrollBox and ScrollBar
    local friendsSB = FriendsListFrame and FriendsListFrame.ScrollBox
    if friendsSB then
        friendsSB:HookScript("OnMouseWheel", _ebsOnScrollActivity)
    end
    local friendsBar = FriendsListFrame and FriendsListFrame.ScrollBar
    if friendsBar and friendsBar.RegisterCallback then
        friendsBar:RegisterCallback("OnScroll", _ebsOnScrollActivity)
    end

    -- Hook friend button updates (secure hook on Blizzard function)
    if FriendsFrame_UpdateFriendButton then
        hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button)
            if not FriendsFrame:IsShown() then return end
            if not EBS.db or not EBS.db.profile.friends.enabled then return end
            if button.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then return end

            -- Structural skinning always runs (guarded by _ebsSkinned, only fires once per button)
            SkinFriendButton(button)

            -- On click, refresh all visible buttons in our ScrollBox so selection updates
            -- Selection highlight (update on every refresh for recycled buttons)
            if not button._ebsSelBar then
                local sel = button:CreateTexture(nil, "ARTWORK", nil, -7)
                sel:SetAllPoints()
                sel:SetAtlas("groupfinder-highlightbar-green")
                sel:SetDesaturated(true)
                sel:SetVertexColor(0.4, 0.7, 1.0)
                sel:SetAlpha(1)
                sel:Hide()
                local selFill = button:CreateTexture(nil, "ARTWORK", nil, -8)
                selFill:SetAllPoints()
                selFill:SetColorTexture(1, 1, 1, 0.02)
                selFill:SetBlendMode("ADD")
                selFill:Hide()
                button._ebsSelBar = sel
                button._ebsSelFill = selFill
            end
            local isSel = (FriendsFrame.selectedFriend == button.id)
            button._ebsSelBar:SetShown(isSel)
            if button._ebsSelFill then button._ebsSelFill:SetShown(isSel) end

            if not button._ebsClickHooked then
                button._ebsClickHooked = true
                button:HookScript("OnClick", function()
                    local sb = FriendsFrame._ebsOurScrollBox
                    if sb then
                        for _, btn in sb:EnumerateFrames() do
                            if btn._ebsSelBar then
                                local sel = (FriendsFrame.selectedFriend == btn.id)
                                btn._ebsSelBar:SetShown(sel)
                                if btn._ebsSelFill then btn._ebsSelFill:SetShown(sel) end
                            end
                        end
                    end
                end)
            end

            -- Hide Blizzard elements immediately so they don't flash during scroll
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

            -- Fill blank info text for BNet app users (runs every hook call, not stamped)
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

            -- Stamp: run data work once per button per friend assignment, skip repeats.
            -- Blizzard calls this hook many times for the same button+friend combo.
            -- We only need to style once -- subsequent calls for the same combo are no-ops.
            local curType = button.buttonType
            local curId = button.id or 0
            if button._ebsStampType == curType and button._ebsStampId == curId then return end
            button._ebsStampType = curType
            button._ebsStampId = curId

            local bnetInfo, wowInfo = GetCachedFriendInfo(button)

            -- Re-anchor info text below name so it lines up
            local nameText = button.name or button.Name
            local infoText = button.info or button.Info
            if infoText and nameText then
                infoText:ClearAllPoints()
                infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3)
            end

            -- Append friend note (from Blizzard note, stripped of EUI group tag)
            if infoText and button.buttonType and button.id then
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
                    local curText = infoText:GetText() or ""
                    if curText ~= "" then
                        infoText:SetText(curText .. "  |cff888888|  " .. userNote .. "|r")
                    else
                        infoText:SetText("|cff888888" .. userNote .. "|r")
                    end
                end
            end
            -- Determine online/away/busy state
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

            if not button._ebsStatusOrb then
                button._ebsStatusOrb = button:CreateTexture(nil, "OVERLAY", nil, 3)
                button._ebsStatusOrb:SetSize(18, 18)
                if _orbFile then
                    button._ebsStatusOrb:SetTexture(_orbFile)
                    button._ebsStatusOrb:SetTexCoord(_orbL, _orbR, _orbT, _orbB)
                else
                    button._ebsStatusOrb:SetAtlas("lootroll-animreveal-a")
                    button._ebsStatusOrb:SetTexCoord(0, 1/6, 0, 0.5)
                end
            end
            local orb = button._ebsStatusOrb
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

            -- Region icon: show if friend is in a different full region
            local fp2 = EBS.db and EBS.db.profile and EBS.db.profile.friends
            if fp2 and fp2.showRegionIcons == false then
                if button._ebsRegionBtn then button._ebsRegionBtn:Hide() end
            else
            local myFull = EllesmereUI.GetMyFullRegion and EllesmereUI.GetMyFullRegion()
            local friendMini
            if bnetInfo and bnetInfo.gameAccountInfo then
                friendMini = EllesmereUI.GetFriendMiniRegion and EllesmereUI.GetFriendMiniRegion(bnetInfo.gameAccountInfo)
            end
            local friendFull = friendMini and EllesmereUI.GetFullRegion and EllesmereUI.GetFullRegion(friendMini)

            if friendMini and friendFull and friendFull ~= myFull then
                if not button._ebsRegionBtn then
                    local rb = CreateFrame("Button", nil, button)
                    rb:SetFrameLevel(button:GetFrameLevel() + 5)
                    rb._tex = rb:CreateTexture(nil, "OVERLAY", nil, 7)
                    rb._tex:SetAllPoints()
                    rb._tex:SetAlpha(0.25)
                    rb:SetScript("OnEnter", function(self)
                        EllesmereUI.ShowWidgetTooltip(self, self._regionLabel or "")
                    end)
                    rb:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    local h = button:GetHeight()
                    local iconH = math.floor(h * 0.8)
                    rb:SetSize(iconH, iconH)
                    local tpBtn = button.travelPassButton
                    if tpBtn then
                        rb:SetPoint("RIGHT", tpBtn, "LEFT", -2, 0)
                    else
                        rb:SetPoint("RIGHT", button, "RIGHT", -30, 0)
                    end
                    button._ebsRegionBtn = rb
                end
                local rb = button._ebsRegionBtn
                if rb._lastMini ~= friendMini then
                    rb._lastMini = friendMini
                    local iconPath = EllesmereUI.GetRegionIcon and EllesmereUI.GetRegionIcon(friendMini)
                    rb._tex:SetTexture(iconPath)
                    rb._tex:SetTexCoord(0, 1, 0, 1)
                    rb._regionLabel = MINI_DISPLAY[friendMini] or friendMini
                end
                rb:Show()
            else
                if button._ebsRegionBtn then button._ebsRegionBtn:Hide() end
            end
            end -- showRegionIcons else
        end)
    end

    ---------------------------------------------------------------------------
    --  Friend Grouping: Element Factory + DataProvider Rebuild
    ---------------------------------------------------------------------------

    -- Priority from already-fetched info (avoids redundant API calls and throwaway tables)
    local function GetBNetPriority(info)
        if info and info.gameAccountInfo then
            local gi = info.gameAccountInfo
            if gi.isOnline then
                if gi.clientProgram == BNET_CLIENT_WOW then
                    return (gi.wowProjectID == 1 or gi.wowProjectID == nil) and 1 or 2
                end
                local cp = gi.clientProgram
                if not cp or cp == "" or cp == "BSAp" or cp == "App" then
                    return 4  -- BNet app / desktop client
                else
                    return 3  -- Other Blizzard game
                end
            end
        end
        return 5
    end

    -- Divider initializer: called by the element factory when rendering a divider
    local MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\"
    local DIV_ICON_SZ = 12
    local DIV_ICON_ALPHA = 0.35
    local DIV_ICON_HOVER = 0.7

    local EBS_FAVORITES_KEY = "Favorites"  -- internal key, never displayed

    local function InitDividerButton(btn, elementData)
        local groupName = elementData._groupKey  -- internal key for logic
        local displayName = elementData.text or ""
        local isFavorites = (groupName == EBS_FAVORITES_KEY)
        local isDefault = (groupName == nil or groupName == false)
        local isPending = (groupName == "_pending")

        -- Kill any highlight on the plain Button template
        if not btn._ebsHlKilled then
            btn._ebsHlKilled = true
            local hl = btn:GetHighlightTexture()
            if hl then hl:SetAlpha(0) end
            btn:EnableMouse(false)  -- divider itself doesn't receive mouse; child buttons do
        end

        if not btn._ebsDivSetup then
            btn._ebsDivSetup = true
            -- Background #141516
            btn._ebsDivBg = btn:CreateTexture(nil, "BACKGROUND")
            btn._ebsDivBg:SetAllPoints()
            btn._ebsDivBg:SetColorTexture(0.059, 0.062, 0.065, 1)

            -- Label (centered, color set per-init)
            btn._ebsDivLabel = btn:CreateFontString(nil, "OVERLAY")
            btn._ebsDivLabel:SetFont(fontPath, 9, "")
            btn._ebsDivLabel:SetShadowOffset(1, -1)
            btn._ebsDivLabel:SetShadowColor(0, 0, 0, 0.8)
            btn._ebsDivLabel:SetPoint("CENTER", btn, "CENTER", 0, 0)


            -- Up arrow (move group up in order)
            local upBtn = CreateFrame("Button", nil, btn)
            upBtn:SetSize(DIV_ICON_SZ, DIV_ICON_SZ)
            upBtn:SetFrameLevel(btn:GetFrameLevel() + 2)
            local upIcon = upBtn:CreateTexture(nil, "OVERLAY")
            upIcon:SetAllPoints()
            upIcon:SetTexture(MEDIA .. "icons\\eui-arrow-up3.png")
            upBtn:SetAlpha(DIV_ICON_ALPHA)
            upBtn:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
            upBtn:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            btn._ebsDivUp = upBtn

            -- Down arrow (move group down in order)
            local downBtn = CreateFrame("Button", nil, btn)
            downBtn:SetSize(DIV_ICON_SZ, DIV_ICON_SZ)
            downBtn:SetFrameLevel(btn:GetFrameLevel() + 2)
            local downIcon = downBtn:CreateTexture(nil, "OVERLAY")
            downIcon:SetAllPoints()
            downIcon:SetTexture(MEDIA .. "icons\\eui-arrow-down3.png")
            downBtn:SetAlpha(DIV_ICON_ALPHA)
            downBtn:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
            downBtn:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            btn._ebsDivDown = downBtn

            -- Lines on either side of text
            btn._ebsDivLineL = btn:CreateTexture(nil, "OVERLAY")
            btn._ebsDivLineL:SetColorTexture(1, 1, 1, 0.1)
            btn._ebsDivLineL:SetHeight(1)
            btn._ebsDivLineL:SetPoint("LEFT", btn, "LEFT", 8, 0)
            btn._ebsDivLineL:SetPoint("RIGHT", btn._ebsDivLabel, "LEFT", -6, 0)
            btn._ebsDivLine = btn:CreateTexture(nil, "OVERLAY")
            btn._ebsDivLine:SetColorTexture(1, 1, 1, 0.1)
            btn._ebsDivLine:SetHeight(1)
            -- Right line starts after label
            btn._ebsDivLine:SetPoint("LEFT", btn._ebsDivLabel, "RIGHT", 6, 0)

            -- Hover highlight for collapse (10% brighter)
            btn._ebsDivHover = btn:CreateTexture(nil, "ARTWORK", nil, -5)
            btn._ebsDivHover:SetAllPoints()
            btn._ebsDivHover:SetColorTexture(1, 1, 1, 0.06)
            btn._ebsDivHover:Hide()

            -- Enable mouse on divider for hover + click-to-collapse
            btn:EnableMouse(true)
            btn:SetScript("OnEnter", function() btn._ebsDivHover:Show() end)
            btn:SetScript("OnLeave", function() btn._ebsDivHover:Hide() end)

            -- X / delete button
            local xBtn = CreateFrame("Button", nil, btn)
            xBtn:SetSize(DIV_ICON_SZ, DIV_ICON_SZ)
            xBtn:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
            xBtn:SetFrameLevel(btn:GetFrameLevel() + 2)
            local xIcon = xBtn:CreateTexture(nil, "OVERLAY")
            xIcon:SetAllPoints()
            xIcon:SetTexture(MEDIA .. "icons\\eui-close.png")
            xBtn:SetAlpha(DIV_ICON_ALPHA)
            xBtn:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
            xBtn:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            btn._ebsDivX = xBtn

            -- Edit / rename button
            local editBtn = CreateFrame("Button", nil, btn)
            editBtn:SetSize(DIV_ICON_SZ, DIV_ICON_SZ)
            editBtn:SetPoint("RIGHT", xBtn, "LEFT", -4, 0)
            editBtn:SetFrameLevel(btn:GetFrameLevel() + 2)
            local editIcon = editBtn:CreateTexture(nil, "OVERLAY")
            editIcon:SetAllPoints()
            editIcon:SetTexture(MEDIA .. "icons\\eui-edit.png")
            editBtn:SetAlpha(DIV_ICON_ALPHA)
            editBtn:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
            editBtn:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            btn._ebsDivEdit = editBtn

            -- Right line endpoint set dynamically in visibility block below
        end

        -- Update text and color
        btn._ebsDivLabel:SetText(displayName)
        local colorKey = groupName or (isFavorites and ORDER_FAVORITES) or (isDefault and ORDER_UNGROUPED) or "_pending"
        local fg = GetFriendGroupsGlobal()
        local gc = fg.friendGroupColors[colorKey]
        if gc then
            btn._ebsDivLabel:SetTextColor(gc.r, gc.g, gc.b, 1)
        else
            local ar, ag, ab = EG.r, EG.g, EG.b
            btn._ebsDivLabel:SetTextColor(ar, ag, ab, 1)
        end

        -- Click label to open our custom color picker
        btn._ebsColorKey = colorKey
        if not btn._ebsDivLabelBtn then
            local labelBtn = CreateFrame("Button", nil, btn)
            labelBtn:SetHeight(20)
            labelBtn:SetFrameLevel(btn:GetFrameLevel() + 3)
            btn._ebsDivLabelBtn = labelBtn
        end
        btn._ebsDivLabelBtn:ClearAllPoints()
        btn._ebsDivLabelBtn:SetPoint("CENTER", btn._ebsDivLabel, "CENTER", 0, 0)
        btn._ebsDivLabelBtn:SetWidth((btn._ebsDivLabel:GetStringWidth() or 40) + 8)
        btn._ebsDivLabelBtn:SetScript("OnClick", function()
            local ck = btn._ebsColorKey
            if not ck then return end
            local fg3 = GetFriendGroupsGlobal()
            local gc2 = fg3.friendGroupColors[ck]
            local cr, cg, cb
            if gc2 then
                cr, cg, cb = gc2.r, gc2.g, gc2.b
            else
                cr, cg, cb = EG.r, EG.g, EG.b
            end
            local snapR, snapG, snapB = cr, cg, cb
            local info = {
                r = cr, g = cg, b = cb,
                hasOpacity = false,
                swatchFunc = function()
                    local popup = EllesmereUI._colorPickerPopup
                    if not popup then return end
                    local nr, ng, nb = popup:GetColorRGB()
                    fg3.friendGroupColors[ck] = { r = nr, g = ng, b = nb }
                    if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
                end,
                cancelFunc = function()
                    fg3.friendGroupColors[ck] = { r = snapR, g = snapG, b = snapB }
                    if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
                end,
            }
            EllesmereUI:ShowColorPicker(info, btn._ebsDivLabelBtn)
        end)


        -- Check collapsed state
        local fg = GetFriendGroupsGlobal()
        local collapsed = false
        if isPending then
            collapsed = fg.friendPendingCollapsed
        elseif isFavorites then
            collapsed = fg.friendFavCollapsed
        elseif isDefault then
            collapsed = fg.friendUngroupedCollapsed
        else
            for _, g in ipairs(fg.friendGroups) do
                if g.name == groupName then collapsed = g.collapsed; break end
            end
        end

        -- Layout: ↑ ------- Label ------- ↓       (Favorites/Friends)
        --         ↑ ↓ ----- Label ----- ✎ ✕    (Custom groups)
        --         ------- Label -------          (Pending)
        if isFavorites or isDefault or isPending then
            btn._ebsDivX:Hide()
            btn._ebsDivEdit:Hide()
            if isPending then
                btn._ebsDivUp:Hide()
                btn._ebsDivDown:Hide()
                btn._ebsDivLineL:ClearAllPoints()
                btn._ebsDivLineL:SetPoint("LEFT", btn, "LEFT", 8, 0)
                btn._ebsDivLineL:SetPoint("RIGHT", btn._ebsDivLabel, "LEFT", -6, 0)
                btn._ebsDivLine:ClearAllPoints()
                btn._ebsDivLine:SetColorTexture(1, 1, 1, 0.1)
                btn._ebsDivLine:SetHeight(1)
                btn._ebsDivLine:SetPoint("LEFT", btn._ebsDivLabel, "RIGHT", 6, 0)
                btn._ebsDivLine:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
            else
                -- Favorites and Friends: up on left, down on right for symmetry
                btn._ebsDivUp:Show()
                btn._ebsDivDown:Show()
                btn._ebsDivUp:ClearAllPoints()
                btn._ebsDivDown:ClearAllPoints()
                btn._ebsDivUp:SetPoint("LEFT", btn, "LEFT", 8, 0)
                btn._ebsDivDown:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
                btn._ebsDivLineL:ClearAllPoints()
                btn._ebsDivLineL:SetPoint("LEFT", btn._ebsDivUp, "RIGHT", 6, 0)
                btn._ebsDivLineL:SetPoint("RIGHT", btn._ebsDivLabel, "LEFT", -6, 0)
                btn._ebsDivLine:ClearAllPoints()
                btn._ebsDivLine:SetColorTexture(1, 1, 1, 0.1)
                btn._ebsDivLine:SetHeight(1)
                btn._ebsDivLine:SetPoint("LEFT", btn._ebsDivLabel, "RIGHT", 6, 0)
                btn._ebsDivLine:SetPoint("RIGHT", btn._ebsDivDown, "LEFT", -6, 0)
            end
        else
            -- Custom group: up edit -- Label -- close down (symmetric)
            btn._ebsDivX:Show()
            btn._ebsDivEdit:Show()
            btn._ebsDivUp:Show()
            btn._ebsDivDown:Show()
            btn._ebsDivUp:ClearAllPoints()
            btn._ebsDivDown:ClearAllPoints()
            btn._ebsDivEdit:ClearAllPoints()
            btn._ebsDivX:ClearAllPoints()
            -- Left side: up arrow, then edit
            btn._ebsDivUp:SetPoint("LEFT", btn, "LEFT", 8, 0)
            btn._ebsDivEdit:SetPoint("LEFT", btn._ebsDivUp, "RIGHT", 4, 0)
            -- Right side: down arrow, then X (inner)
            btn._ebsDivDown:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
            btn._ebsDivX:SetPoint("RIGHT", btn._ebsDivDown, "LEFT", -4, 0)
            -- Left line: after edit to label
            btn._ebsDivLineL:ClearAllPoints()
            btn._ebsDivLineL:SetPoint("LEFT", btn._ebsDivEdit, "RIGHT", 6, 0)
            btn._ebsDivLineL:SetPoint("RIGHT", btn._ebsDivLabel, "LEFT", -6, 0)
            -- Right line: after label to X
            btn._ebsDivLine:ClearAllPoints()
            btn._ebsDivLine:SetColorTexture(1, 1, 1, 0.1)
            btn._ebsDivLine:SetHeight(1)
            btn._ebsDivLine:SetPoint("LEFT", btn._ebsDivLabel, "RIGHT", 6, 0)
            btn._ebsDivLine:SetPoint("RIGHT", btn._ebsDivX, "LEFT", -6, 0)
        end

        -- Click on divider bar to toggle collapse
        btn:SetScript("OnClick", function()
            local fg2 = GetFriendGroupsGlobal()
            if isPending then
                fg2.friendPendingCollapsed = not fg2.friendPendingCollapsed
            elseif isFavorites then
                fg2.friendFavCollapsed = not fg2.friendFavCollapsed
            elseif isDefault then
                fg2.friendUngroupedCollapsed = not fg2.friendUngroupedCollapsed
            else
                for _, g in ipairs(fg2.friendGroups) do
                    if g.name == groupName then g.collapsed = not g.collapsed; break end
                end
            end
            if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
        end)

        if not isFavorites and not isDefault and not isPending then
            btn._ebsDivX:SetScript("OnClick", function()
                local dialog = StaticPopup_Show("EBS_DELETE_FRIEND_GROUP", displayName)
                if dialog then dialog.data = groupName end
            end)
            btn._ebsDivEdit:SetScript("OnClick", function()
                local dialog = StaticPopup_Show("EBS_NEW_FRIEND_GROUP")
                if dialog then
                    dialog.data = { renameFrom = groupName }
                    local eb = dialog.EditBox or dialog.editBox
                    if eb then eb:SetText(groupName) end
                end
            end)
        end

        -- Arrow reordering for all groups (Favorites, custom, Friends -- not pending)
        if not isPending then
            local orderKey = groupName
            if isFavorites then orderKey = ORDER_FAVORITES
            elseif isDefault then orderKey = ORDER_UNGROUPED end

            local isFirst = elementData._isFirstGroup
            local isLast = elementData._isLastGroup

            -- Disable/gray out arrows at boundaries (keep mouse enabled to block hover)
            if isFirst then
                btn._ebsDivUp:SetAlpha(0.06)
                btn._ebsDivUp:SetScript("OnEnter", nil)
                btn._ebsDivUp:SetScript("OnLeave", nil)
            else
                btn._ebsDivUp:SetAlpha(DIV_ICON_ALPHA)
                btn._ebsDivUp:EnableMouse(true)
                btn._ebsDivUp:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
                btn._ebsDivUp:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            end
            if isLast then
                btn._ebsDivDown:SetAlpha(0.06)
                btn._ebsDivDown:SetScript("OnEnter", nil)
                btn._ebsDivDown:SetScript("OnLeave", nil)
            else
                btn._ebsDivDown:SetAlpha(DIV_ICON_ALPHA)
                btn._ebsDivDown:EnableMouse(true)
                btn._ebsDivDown:SetScript("OnEnter", function(self) self:SetAlpha(DIV_ICON_HOVER) end)
                btn._ebsDivDown:SetScript("OnLeave", function(self) self:SetAlpha(DIV_ICON_ALPHA) end)
            end

            btn._ebsDivUp:SetScript("OnClick", function()
                if isFirst then return end
                local order = GetValidGroupOrder()
                for idx, k in ipairs(order) do
                    if k == orderKey and idx > 1 then
                        order[idx], order[idx - 1] = order[idx - 1], order[idx]
                        if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
                        break
                    end
                end
            end)
            btn._ebsDivDown:SetScript("OnClick", function()
                if isLast then return end
                local order = GetValidGroupOrder()
                for idx, k in ipairs(order) do
                    if k == orderKey and idx < #order then
                        order[idx], order[idx + 1] = order[idx + 1], order[idx]
                        if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
                        break
                    end
                end
            end)
        end
    end

    -- Custom pending invite button type
    local EBS_BUTTON_TYPE_PENDING = 999

    local function InitPendingButton(btn, elementData)
        -- Height: 36 content + top/bottom spacing
        local topGap = elementData._isFirst and 1 or 0
        local bottomGap = elementData._isLast and 1 or 2
        btn:SetHeight(36 + topGap + bottomGap)
        if not btn._ebsPendingSkinned then
            btn._ebsPendingSkinned = true

            -- Tile bg (slightly brighter with blue tint)
            btn._ebsTileBg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
            btn._ebsTileBg:SetColorTexture(0.05, 0.15, 0.20, 0.30)

            -- Neutral overlay
            btn._ebsFactionBg = btn:CreateTexture(nil, "BACKGROUND", nil, 3)
            btn._ebsFactionBg:SetTexture(FACTION_TEX_NEUTRAL)
            btn._ebsFactionBg:SetTexCoord(0, 1, 0, 1)
            btn._ebsFactionBg:SetAlpha(0.2)

            -- Hover highlight
            local hover = btn:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints()
            hover:SetColorTexture(1, 1, 1, 0.05)
            hover:SetBlendMode("ADD")

            -- Name (12pt, shadow)
            btn._ebsName = btn:CreateFontString(nil, "OVERLAY")
            btn._ebsName:SetFont(fontPath, 12, "")
            btn._ebsName:SetShadowOffset(1, -1)
            btn._ebsName:SetShadowColor(0, 0, 0, 0.8)
            btn._ebsName:SetPoint("LEFT", btn, "LEFT", 10, 4)
            btn._ebsName:SetTextColor(0.51, 0.784, 1, 1)

            -- Info line (9pt, shadow)
            btn._ebsSubText = btn:CreateFontString(nil, "OVERLAY")
            btn._ebsSubText:SetFont(fontPath, 9, "")
            btn._ebsSubText:SetShadowOffset(1, -1)
            btn._ebsSubText:SetShadowColor(0, 0, 0, 0.8)
            btn._ebsSubText:SetPoint("TOPLEFT", btn._ebsName, "BOTTOMLEFT", 0, -2)
            btn._ebsSubText:SetTextColor(0.5, 0.5, 0.5, 0.8)

            -- Decline button (x, right side)
            local declineBtn = CreateFrame("Button", nil, btn)
            declineBtn:SetSize(20, 20)
            declineBtn:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            declineBtn:SetFrameLevel(btn:GetFrameLevel() + 3)
            local decX = declineBtn:CreateFontString(nil, "OVERLAY")
            decX:SetFont(fontPath, 14, "")
            decX:SetText("x")
            decX:SetTextColor(1, 1, 1, 0.3)
            decX:SetPoint("CENTER", 0, 1)
            declineBtn:SetScript("OnEnter", function()
                decX:SetTextColor(1, 0.3, 0.3, 0.8)
                EllesmereUI.ShowWidgetTooltip(declineBtn, DECLINE or "Decline")
            end)
            declineBtn:SetScript("OnLeave", function()
                decX:SetTextColor(1, 1, 1, 0.3)
                EllesmereUI.HideWidgetTooltip()
            end)
            declineBtn:SetScript("OnClick", function()
                local invID = btn._ebsInviteID
                if invID and BNDeclineFriendInvite then BNDeclineFriendInvite(invID) end
            end)
            btn._ebsDeclineBtn = declineBtn

            -- Accept button (styled like Add Friend / Send Message buttons)
            local acceptBtn = CreateFrame("Button", nil, btn)
            local m = PP.mult or 1
            acceptBtn:SetSize(70, math.floor(18 / m + 0.5) * m)
            acceptBtn:SetPoint("RIGHT", declineBtn, "LEFT", -6, 0)
            acceptBtn:SetFrameLevel(btn:GetFrameLevel() + 3)

            local acceptBg = acceptBtn:CreateTexture(nil, "BACKGROUND", nil, -6)
            acceptBg:SetColorTexture(0.025, 0.035, 0.045, 0.92)
            acceptBg:SetAllPoints()

            PP.CreateBorder(acceptBtn, 1, 1, 1, 0.4, 1, "OVERLAY", 7)

            local acceptLabel = acceptBtn:CreateFontString(nil, "OVERLAY")
            acceptLabel:SetFont(fontPath, 9, "")
            acceptLabel:SetTextColor(1, 1, 1, 0.5)
            acceptLabel:SetPoint("CENTER", 0, 0)
            acceptLabel:SetText(ACCEPT or "Accept")
            btn._ebsAcceptLabel = acceptLabel

            -- Accent support: read from DB, same pattern as bottom buttons
            acceptBtn._ebsAccent = false
            acceptBtn:SetScript("OnEnter", function()
                local r, g, b, a1, a2 = 1, 1, 1, 0.7, 0.6
                if acceptBtn._ebsAccent then
                    r, g, b = EG.r, EG.g, EG.b
                    a1, a2 = 1, 0.8
                end
                acceptLabel:SetTextColor(r, g, b, a1)
                if acceptBtn._ppBorders then PP.SetBorderColor(acceptBtn, r, g, b, a2) end
            end)
            acceptBtn:SetScript("OnLeave", function()
                local r, g, b, a1, a2 = 1, 1, 1, 0.5, 0.4
                if acceptBtn._ebsAccent then
                    r, g, b = EG.r, EG.g, EG.b
                    a1, a2 = 0.7, 0.5
                end
                acceptLabel:SetTextColor(r, g, b, a1)
                if acceptBtn._ppBorders then PP.SetBorderColor(acceptBtn, r, g, b, a2) end
            end)
            acceptBtn:SetScript("OnClick", function()
                local invID = btn._ebsInviteID
                if invID and BNAcceptFriendInvite then BNAcceptFriendInvite(invID) end
            end)
            btn._ebsAcceptBtn = acceptBtn
        end

        -- Anchor tile/faction with per-element gaps (first gets top gap, last gets smaller bottom gap)
        local tGap = elementData._isFirst and -1 or 0
        local bGap = elementData._isLast and 1 or 2
        btn._ebsTileBg:ClearAllPoints()
        btn._ebsTileBg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, tGap)
        btn._ebsTileBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, bGap)
        btn._ebsFactionBg:ClearAllPoints()
        btn._ebsFactionBg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, tGap)
        btn._ebsFactionBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, bGap)

        -- Apply accent state from current settings
        local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
        local useAccent = fp and fp.accentColors ~= false
        local acceptBtn = btn._ebsAcceptBtn
        local acceptLabel = btn._ebsAcceptLabel
        if acceptBtn then
            acceptBtn._ebsAccent = useAccent
            if useAccent then
                if acceptLabel then acceptLabel:SetTextColor(EG.r, EG.g, EG.b, 0.7) end
                if acceptBtn._ppBorders then PP.SetBorderColor(acceptBtn, EG.r, EG.g, EG.b, 0.5) end
            else
                if acceptLabel then acceptLabel:SetTextColor(1, 1, 1, 0.5) end
                if acceptBtn._ppBorders then PP.SetBorderColor(acceptBtn, 1, 1, 1, 0.4) end
            end
        end

        -- Populate data (reapply colors every init in case rebuild recycled the frame)
        btn._ebsInviteID = elementData._inviteID
        btn._ebsName:SetText(elementData._accountName or "")
        btn._ebsName:SetTextColor(0.51, 0.784, 1, 1)
        btn._ebsSubText:SetText(PENDING_INVITE or "Pending")
        btn._ebsSubText:SetTextColor(0.5, 0.5, 0.5, 0.8)
        btn._ebsTileBg:SetColorTexture(0.05, 0.15, 0.20, 0.30)
    end

    -- Our own ScrollBox + ScrollBar (parented to UIParent) to avoid tainting
    -- Blizzard's FriendsListFrame.ScrollBox. ScrollUtil.Init + SetDataProvider
    -- on our frames don't propagate taint to RaidFrame:Show().
    local _ebsOurScrollBox, _ebsOurScrollBar
    do
        local ourSB = CreateFrame("Frame", nil, UIParent, "WowScrollBoxList")
        local ourBar = CreateFrame("EventFrame", nil, UIParent, "MinimalScrollBar")
        ourSB:SetFrameStrata("HIGH")
        ourSB:SetFrameLevel(20)
        ourSB:Hide()
        ourBar:SetFrameStrata("HIGH")
        ourBar:Hide()

        local ourBg = ourSB:CreateTexture(nil, "BACKGROUND")
        ourBg:SetAllPoints()
        ourBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B, 1)

        ourSB:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -92)
        ourSB:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)
        ourBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -92)
        ourBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 35)

        local view = CreateScrollBoxListLinearView()
        view:SetElementExtentCalculator(function(dataIndex, elementData)
            if elementData.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then
                return 20
            elseif elementData.buttonType == EBS_BUTTON_TYPE_PENDING then
                local top = elementData._isFirst and 1 or 0
                local bot = elementData._isLast and 1 or 2
                return 36 + top + bot
            end
            return 34
        end)
        view:SetElementFactory(function(factory, elementData)
            if elementData.buttonType == FRIENDS_BUTTON_TYPE_DIVIDER then
                factory("Button", function(btn, ed)
                    btn:SetHeight(20)
                    btn.buttonType = FRIENDS_BUTTON_TYPE_DIVIDER
                    InitDividerButton(btn, ed)
                end)
            elseif elementData.buttonType == EBS_BUTTON_TYPE_PENDING then
                factory("Frame", function(btn, ed)
                    InitPendingButton(btn, ed)
                end)
            elseif elementData.buttonType == FRIENDS_BUTTON_TYPE_INVITE_HEADER then
                factory("FriendsPendingInviteHeaderButtonTemplate", FriendsFrame_UpdateFriendInviteHeaderButton)
            elseif elementData.buttonType == FRIENDS_BUTTON_TYPE_INVITE then
                factory("FriendsFrameFriendInviteTemplate", FriendsFrame_UpdateFriendInviteButton)
            else
                factory("FriendsListButtonTemplate", FriendsFrame_UpdateFriendButton)
            end
        end)
        ScrollUtil.InitScrollBoxListWithScrollBar(ourSB, ourBar, view)
        SkinOneScrollbar(ourSB, ourBar)

        _ebsOurScrollBox = ourSB
        _ebsOurScrollBar = ourBar
        frame._ebsOurScrollBox = ourSB
        frame._ebsOurScrollBar = ourBar
    end

    -- Rebuild state
    local _ebsRebuilding = false
    local _ebsRebuildPending = false

    local function RebuildFriendsDataProvider()
        if _ebsRebuilding then
            _ebsRebuildPending = true
            return
        end
        if not FriendsFrame:IsShown() then return end
        if not EBS.db or not EBS.db.profile.friends.enabled then return end
        local fp = EBS.db.profile.friends
        local sb = _ebsOurScrollBox
        if not sb then return end

        local EBS_FAVORITES = "Favorites"

        -- Read ALL friends directly from the API and populate the scroll cache.
        -- Cache is read during per-button hook so scrolling never calls the API.
        local friends = {}
        local fg = GetFriendGroupsGlobal()
        wipe(_friendCache)
        local numBNet = BNGetNumFriends and BNGetNumFriends() or 0
        for i = 1, numBNet do
            local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo(i)
            if info then
                _friendCache[i] = info
                local isFavorite = info.isFavorite
                local noteGroup = ParseGroupFromNote(info.note)
                local group
                if isFavorite then
                    group = EBS_FAVORITES
                else
                    group = noteGroup
                end
                local btag = (info.battleTag or ""):lower()
                local sortName = btag:match("^(.-)#") or btag
                if sortName == "" then sortName = (info.accountName or ""):lower() end
                friends[#friends + 1] = {
                    buttonType = FRIENDS_BUTTON_TYPE_BNET,
                    id = i,
                    priority = GetBNetPriority(info),
                    name = sortName,
                    btag = btag,
                    group = group,
                }
            end
        end
        local numWoW = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
        for i = 1, numWoW do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name then
                _friendCache[i + _FC_WOW_OFFSET] = info
                local wowGroup = ParseGroupFromNote(info.notes)
                friends[#friends + 1] = {
                    buttonType = FRIENDS_BUTTON_TYPE_WOW,
                    id = i,
                    priority = info.connected and 1 or 5,
                    name = info.name:lower(),
                    group = wowGroup,
                }
            end
        end

        -- Filter offline friends if toggle is off
        if fp.showOffline == false then
            local onlineOnly = {}
            for _, f in ipairs(friends) do
                if f.priority < 5 then  -- priority 5 = offline
                    onlineOnly[#onlineOnly + 1] = f
                end
            end
            friends = onlineOnly
        end

        -- Apply search filter
        if _ebsSearchTerm ~= "" then
            local filtered = {}
            for _, f in ipairs(friends) do
                if strfind(f.name, _ebsSearchTerm, 1, true)
                    or (f.btag and strfind(f.btag, _ebsSearchTerm, 1, true)) then
                    filtered[#filtered + 1] = f
                end
            end
            friends = filtered
        end

        if #friends == 0 then
            local sb2 = FriendsListFrame and FriendsListFrame.ScrollBox
            if sb2 then sb2:SetDataProvider(CreateDataProvider(), true) end
            _ebsRebuilding = false
            return
        end

        -- Sort: priority ascending, then name ascending
        table.sort(friends, function(a, b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return a.name < b.name
        end)


        -- Build ordered group list from saved order
        local validOrder = GetValidGroupOrder()
        local groupOrder = {}
        for _, key in ipairs(validOrder) do
            if key == ORDER_FAVORITES then
                groupOrder[#groupOrder + 1] = EBS_FAVORITES
            elseif key == ORDER_UNGROUPED then
                groupOrder[#groupOrder + 1] = false
            else
                groupOrder[#groupOrder + 1] = key
            end
        end

        -- Bucket friends into groups
        local buckets = {}
        for _, f in ipairs(friends) do
            local key = f.group or false
            if not buckets[key] then buckets[key] = {} end
            buckets[key][#buckets[key] + 1] = f
        end

        -- Build new DataProvider (respect collapsed state)
        local newDP = CreateDataProvider()

        -- Pending friend invites (max 2, above all groups)
        local numInvites = BNGetNumFriendInvites and BNGetNumFriendInvites() or 0
        if numInvites > 0 then
            newDP:Insert({
                buttonType = FRIENDS_BUTTON_TYPE_DIVIDER,
                text = format(FRIEND_REQUESTS or "Friend Requests (%d)", numInvites),
                _groupKey = "_pending",
            })
            if not fg.friendPendingCollapsed then
                local maxShow = math.min(numInvites, 3)
                local inserted = 0
                for inv = 1, maxShow do
                    local inviteID, accountName = BNGetFriendInviteInfo(inv)
                    if inviteID then
                        inserted = inserted + 1
                        newDP:Insert({
                            buttonType = EBS_BUTTON_TYPE_PENDING,
                            _inviteID = inviteID,
                            _accountName = accountName or "",
                            _isFirst = (inserted == 1),
                            _isLast = (inv == maxShow),
                        })
                    end
                end
            end
        end

        -- Find which groups have members for first/last marking
        local activeGroups = {}
        for _, gName in ipairs(groupOrder) do
            if buckets[gName] and #buckets[gName] > 0 then
                activeGroups[#activeGroups + 1] = gName
            end
        end

        for gi, gName in ipairs(groupOrder) do
            local bucket = buckets[gName]
            if bucket and #bucket > 0 then
                local displayName = gName
                if gName == EBS_FAVORITES then
                    displayName = FAVORITES or "Favorites"
                elseif not gName then
                    displayName = FRIENDS or "Friends"
                end
                -- Determine if first/last active group
                local isFirstGroup = (activeGroups[1] == gName)
                local isLastGroup = (activeGroups[#activeGroups] == gName)
                newDP:Insert({
                    buttonType = FRIENDS_BUTTON_TYPE_DIVIDER,
                    text = displayName,
                    _groupKey = gName,
                    _isFirstGroup = isFirstGroup,
                    _isLastGroup = isLastGroup,
                })
                -- Check collapsed state
                local isCollapsed = false
                if gName == EBS_FAVORITES then
                    isCollapsed = fg.friendFavCollapsed
                elseif gName == false then
                    isCollapsed = fg.friendUngroupedCollapsed
                else
                    for _, g in ipairs(fg.friendGroups) do
                        if g.name == gName then isCollapsed = g.collapsed; break end
                    end
                end
                if not isCollapsed then
                    for _, f in ipairs(bucket) do
                        newDP:Insert({
                            buttonType = f.buttonType,
                            id = f.id,
                        })
                    end
                end
            end
        end

        -- Clear stamps so the hook re-applies styling with fresh data
        for _, btn in sb:EnumerateFrames() do
            btn._ebsStampType = nil
        end
        _ebsRebuilding = true
        sb:SetDataProvider(newDP, true)  -- safe: sb is our own ScrollBox, not Blizzard's
        _ebsRebuilding = false

        -- Scroll to a specific friend after rebuild (e.g. after adding to group)
        if _G._EBS_ScrollToFriend then
            local targetKey = _G._EBS_ScrollToFriend
            _G._EBS_ScrollToFriend = nil
            C_Timer.After(0, function()
                local dp = sb:GetDataProvider()
                if not dp then return end
                local idx = 0
                for _, ed in dp:Enumerate() do
                    idx = idx + 1
                    if ed.buttonType and ed.buttonType ~= FRIENDS_BUTTON_TYPE_DIVIDER and ed.id then
                        local fk
                        if ed.buttonType == FRIENDS_BUTTON_TYPE_BNET then
                            local cached = _friendCache[ed.id]
                            if cached then fk = "bnet-" .. (cached.bnetAccountID or ed.id) end
                        elseif ed.buttonType == FRIENDS_BUTTON_TYPE_WOW then
                            local cached = _friendCache[ed.id + _FC_WOW_OFFSET]
                            if cached then fk = "wow-" .. (cached.name or "") end
                        end
                        if fk == targetKey then
                            sb:ScrollToElementDataIndex(idx)
                            -- Brief flash highlight on the target button (no taint)
                            local targetType, targetId = ed.buttonType, ed.id
                            C_Timer.After(0.05, function()
                                for _, btn in sb:EnumerateFrames() do
                                    if btn.buttonType == targetType and btn.id == targetId then
                                        if not btn._ebsFlashHL then
                                            btn._ebsFlashHL = btn:CreateTexture(nil, "ARTWORK", nil, -5)
                                            btn._ebsFlashHL:SetAllPoints()
                                            btn._ebsFlashHL:SetColorTexture(1, 1, 1, 0.12)
                                        end
                                        btn._ebsFlashHL:Show()
                                        C_Timer.After(1.5, function()
                                            if btn._ebsFlashHL then btn._ebsFlashHL:Hide() end
                                        end)
                                        break
                                    end
                                end
                            end)
                            break
                        end
                    end
                end
            end)
        end

        if _ebsRebuildPending then
            _ebsRebuildPending = false
            C_Timer.After(0, RebuildFriendsDataProvider)
        end
    end

    -- Expose for menu callbacks
    _G._EBS_RebuildFriendsDP = RebuildFriendsDataProvider

    -- Hook FriendsList_Update to rebuild after Blizzard
    if FriendsList_Update then
        hooksecurefunc("FriendsList_Update", RebuildFriendsDataProvider)
    end

    -- Listen for friend list changes that require immediate rebuild
    local friendChangeEvents = CreateFrame("Frame")
    friendChangeEvents:RegisterEvent("BN_FRIEND_LIST_SIZE_CHANGED")
    friendChangeEvents:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
    friendChangeEvents:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
    friendChangeEvents:RegisterEvent("BN_FRIEND_INFO_CHANGED")
    friendChangeEvents:RegisterEvent("FRIENDLIST_UPDATE")
    friendChangeEvents:RegisterEvent("BN_FRIEND_INVITE_ADDED")
    friendChangeEvents:RegisterEvent("BN_FRIEND_INVITE_REMOVED")
    friendChangeEvents:SetScript("OnEvent", function()
        if FriendsFrame and FriendsFrame:IsShown() then
            RebuildFriendsDataProvider()
        end
    end)

    -- Auto-accept group invites from friends
    local _autoAcceptHideStatic = false
    local autoAcceptFrame = CreateFrame("Frame")
    autoAcceptFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    autoAcceptFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    autoAcceptFrame:SetScript("OnEvent", function(_, event, _, _, _, _, _, _, inviterGUID)
        if event == "PARTY_INVITE_REQUEST" then
            local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
            if not fp or not fp.autoAcceptFriendInvites then return end
            if not inviterGUID or inviterGUID == "" or IsInGroup() then return end
            local isFriend = false
            if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
                isFriend = C_BattleNet.GetGameAccountInfoByGUID(inviterGUID) ~= nil
            end
            if not isFriend and C_FriendList and C_FriendList.IsFriend then
                isFriend = C_FriendList.IsFriend(inviterGUID)
            end
            if isFriend then
                AcceptGroup()
                _autoAcceptHideStatic = true
            end
        elseif event == "GROUP_ROSTER_UPDATE" and _autoAcceptHideStatic then
            _autoAcceptHideStatic = false
            StaticPopup_Hide("PARTY_INVITE")
            if LFGInvitePopup then
                StaticPopupSpecial_Hide(LFGInvitePopup)
            end
        end
    end)

    -- Save/restore scroll position across open/close
    local _ebsSavedScrollPct = 0
    local function _ebsOnShowDeferred()
        ProcessFriendButtons()
        if _ebsSavedScrollPct > 0 then
            local bar = FriendsListFrame.ScrollBar
            if bar and bar.SetScrollPercentage then
                bar:SetScrollPercentage(_ebsSavedScrollPct)
            end
        end
    end
    frame:HookScript("OnHide", function()
        local bar = FriendsListFrame.ScrollBar
        if bar and bar.GetScrollPercentage then
            _ebsSavedScrollPct = bar:GetScrollPercentage() or 0
        end
    end)
    frame:HookScript("OnShow", function()
        RebuildFriendsDataProvider()
        C_Timer.After(0, _ebsOnShowDeferred)
    end)

    -- Status events (BN_FRIEND_INFO_CHANGED, etc.) are handled by the
    -- FriendsFrame_UpdateFriendButton hooksecurefunc above, which fires per-button
    -- when Blizzard processes these events. No separate event frame needed.

    ---------------------------------------------------------------------------
    --  Skin Who / Raid / Quick Join tabs (simple reskins, Blizzard handles logic)
    ---------------------------------------------------------------------------

    -- Helper: strip a frame and its inset
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

            -- Reanchor Who frame to our list pane area
            who:ClearAllPoints()
            who:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, 0)
            who:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -11, 0)

            -- Custom backdrop on the list inset area
            local whoInset = _G.WhoFrameListInset
            if whoInset then
                StripTextures(whoInset)
                if whoInset.Bg then whoInset.Bg:Hide() end
                if whoInset.NineSlice then
                    StripTextures(whoInset.NineSlice)
                    whoInset.NineSlice:Hide()
                end
                whoInset:SetClipsChildren(true)
                -- Match friends list ScrollBox left/right alignment
                whoInset:ClearAllPoints()
                whoInset:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -92)
                whoInset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)
                local whoBg = whoInset:CreateTexture(nil, "BACKGROUND", nil, -5)
                whoBg:SetAllPoints()
                whoBg:SetColorTexture(0, 0.08, 0.10, 0.35)
                PP.CreateBorder(whoInset, 1, 1, 1, 0.1, 1, "OVERLAY", 5)
            end

            -- 5px left padding + 10px up on all column headers via hooksecurefunc
            local col1 = _G["WhoFrameColumnHeader1"]
            for i = 1, 4 do
                local col = _G["WhoFrameColumnHeader" .. i]
                if col then
                    hooksecurefunc(col, "SetPoint", function(self)
                        if self._ebsAdjusting then return end
                        self._ebsAdjusting = true
                        local p1, rel, p2, x, y = self:GetPoint(1)
                        if p1 then
                            self:ClearAllPoints()
                            local xOff = (i == 1) and 5 or 0
                            self:SetPoint(p1, rel, p2, (x or 0) + xOff, (y or 0) + 10)
                        end
                        self._ebsAdjusting = false
                    end)
                end
            end

            -- Dark background behind the column header bar
            local whoInset2 = _G.WhoFrameListInset
            if col1 and whoInset2 then
                local headerBg = who:CreateTexture(nil, "BACKGROUND", nil, -6)
                headerBg:SetPoint("TOPLEFT", col1, "TOPLEFT", 0, 0)
                headerBg:SetPoint("RIGHT", whoInset2, "RIGHT", 0, 0)
                headerBg:SetHeight(col1:GetHeight())
                headerBg:SetColorTexture(0, 0, 0, 0.3)
            end

            -- Column headers with 1px dividers and hover highlight
            for i = 1, 4 do
                local col = _G["WhoFrameColumnHeader" .. i]
                if col then
                    StripTextures(col)
                    local text = col:GetFontString()
                    if text then
                        text:SetFont(fontPath, 10, "")
                        text:SetTextColor(1, 1, 1, 0.5)
                    end
                    -- Hover highlight (clipped within column bounds)
                    col:SetClipsChildren(true)
                    local hl = col:CreateTexture(nil, "HIGHLIGHT")
                    local nextCol = _G["WhoFrameColumnHeader" .. (i + 1)]
                    if nextCol then
                        hl:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
                        hl:SetPoint("BOTTOMRIGHT", nextCol, "BOTTOMLEFT", 0, 0)
                    else
                        -- Last column: anchor to the inset right edge
                        local whoInset3 = _G.WhoFrameListInset
                        if whoInset3 then
                            hl:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
                            hl:SetPoint("BOTTOM", col, "BOTTOM", 0, 0)
                            hl:SetPoint("RIGHT", whoInset3, "RIGHT", 0, 0)
                        else
                            hl:SetAllPoints()
                        end
                    end
                    hl:SetColorTexture(1, 1, 1, 0.1)
                    hl:SetBlendMode("ADD")
                    -- 1px divider on the left edge (skip first column)
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

            -- Replace Zone dropdown with plain "Zone" text on col2
            local zoneDropdown = _G.WhoFrameDropdown
            if zoneDropdown then
                zoneDropdown:SetAlpha(0)
                zoneDropdown:SetSize(1, 1)
                zoneDropdown:EnableMouse(false)
                zoneDropdown:ClearAllPoints()
                zoneDropdown:SetPoint("TOPLEFT", who, "TOPLEFT", 0, 0)
            end
            local col2 = _G["WhoFrameColumnHeader2"]
            if col2 then
                local zoneLabel = col2:CreateFontString(nil, "OVERLAY")
                zoneLabel:SetFont(fontPath, 10, "")
                zoneLabel:SetTextColor(1, 1, 1, 0.5)
                zoneLabel:SetPoint("LEFT", col2, "LEFT", 5, 0)
                zoneLabel:SetText("Zone")
                -- Wire click to sort by zone
                -- Wire col2 to sort by zone using col1's OnClick mixin method
                local col1ref = _G["WhoFrameColumnHeader1"]
                if col1ref and col1ref.OnClick then
                    col2.sortType = "zone"
                    col2:SetScript("OnClick", function(self)
                        col1ref.OnClick(self)
                    end)
                end
            end

            -- Search box (custom background)
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

            -- Total count
            local totalCount = _G.WhoFrameTotals
            if totalCount and totalCount.SetFont then
                totalCount:SetFont(fontPath, 10, "")
                totalCount:SetTextColor(1, 1, 1, 0.5)
            end

            -- Bottom buttons: equal thirds, flush with inset
            local whoInsetRef = _G.WhoFrameListInset
            local whoBtnNames = {"WhoFrameWhoButton", "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton"}
            if whoInsetRef then
                local function LayoutWhoBtns()
                    local totalW = whoInsetRef:GetWidth()
                    local btnW = math.floor(totalW / 3)
                    local btnY = -22 - 10 + 10  -- match friends: -BTN_H - BTN_GAP + 10
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

            -- Skin who list rows
            local function SkinWhoRows()
                for i = 1, 22 do
                    local btn = _G["WhoFrameButton" .. i]
                    if btn and not btn._ebsSkinned then
                        btn._ebsSkinned = true
                        StripTextures(btn)
                        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
                        hover:SetAllPoints()
                        hover:SetColorTexture(1, 1, 1, 0.04)
                        hover:SetBlendMode("ADD")
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
            if WhoList_Update then
                hooksecurefunc("WhoList_Update", SkinWhoRows)
            end

            -- Push the scroll list down 35px and add 5px left padding
            local sb = who.ScrollBox or (who.scrollFrame)
            if sb then
                local p1, rel, p2, x, y = sb:GetPoint(1)
                if p1 then
                    sb:SetPoint(p1, rel, p2, (x or 0) + 5, (y or 0) - 35)
                end
            end

            -- Reanchor Who background + top bar (10px gap above buttons)
            who:ClearAllPoints()
            who:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -10)
            who:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -11, 10)

            -- Reanchor column header 1 flush with list pane top (+10px shift)
            local col1 = _G["WhoFrameColumnHeader1"]
            if col1 then
                col1:ClearAllPoints()
                col1:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -102)
            end

            -- Skin scrollbar
            local bar = sb and (sb.ScrollBar or who.ScrollBar) or who.ScrollBar
            if sb and bar then SkinOneScrollbar(sb, bar) end
        end
    end

    -- Quick Join tab
    do
        local qjf = _G.QuickJoinFrame
        if qjf then
            -- Match scrollable area to friends list positioning
            local qjScroll = qjf.ScrollBox or (qjf.List and qjf.List.ScrollBox)
            if qjScroll then
                qjScroll:ClearAllPoints()
                qjScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -92)
                qjScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 35)

                -- 1px inset border (same as friends/who)
                if not qjScroll._ebsBorderAdded then
                    qjScroll._ebsBorderAdded = true
                    local bdr = CreateFrame("Frame", nil, qjf)
                    bdr:SetPoint("TOPLEFT", qjScroll, "TOPLEFT", 0, 0)
                    bdr:SetPoint("BOTTOMRIGHT", qjScroll, "BOTTOMRIGHT", 0, 0)
                    bdr:SetFrameLevel(qjScroll:GetFrameLevel() + 2)
                    PP.CreateBorder(bdr, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
                end

                -- Custom scrollbar
                local qjBar = qjScroll.ScrollBar or (qjf.List and qjf.List.ScrollBar) or qjf.ScrollBar
                if qjBar then
                    SkinOneScrollbar(qjScroll, qjBar)
                end
            end

            -- Position JoinQueueButton to match rightmost button (same as friends layout)
            local joinBtn = qjf.JoinQueueButton
            if joinBtn and qjScroll then
                SkinBottomButton(joinBtn)
                joinBtn:ClearAllPoints()
                local totalW = qjScroll:GetWidth()
                local btnW = math.floor(totalW / 3)
                joinBtn:SetSize(btnW, 22)
                joinBtn:SetPoint("BOTTOMRIGHT", qjScroll, "BOTTOMRIGHT", 0, -22)
            end
        end
    end


    -- Friends list area: 1px border around scrollable area
    local friendsList = FriendsListFrame
    if friendsList and friendsList.ScrollBox and not friendsList.ScrollBox._ebsBorderAdded then
        friendsList.ScrollBox._ebsBorderAdded = true
        local bdr = CreateFrame("Frame", nil, friendsList)
        bdr:SetPoint("TOPLEFT", friendsList.ScrollBox, "TOPLEFT", 0, 0)
        bdr:SetPoint("BOTTOMRIGHT", friendsList.ScrollBox, "BOTTOMRIGHT", 0, 0)
        bdr:SetFrameLevel(friendsList.ScrollBox:GetFrameLevel() + 2)
        PP.CreateBorder(bdr, 1, 1, 1, 0.1, 1, "OVERLAY", 7)
    end

    -- Shared inset: everything inside the frame uses this left/right padding
    local INSET = 3
    local BTN_H = 22
    local TAB_H = 26
    -- Skin and reposition Add Friend / Send Message buttons
    SkinKnownButtons()
    SkinRaidTab()
    local addBtn = _G.FriendsFrameAddFriendButton
    local msgBtn = _G.FriendsFrameSendMessageButton
    if addBtn and msgBtn then
        local BTN_GAP = 10
        local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
        local btnY = -BTN_H - BTN_GAP + 10

        local function LayoutFriendBtns()
            local totalW = frame:GetWidth() - 30
            local btnW = math.floor(totalW / 3)

            addBtn:SetParent(frame)
            addBtn:ClearAllPoints()
            addBtn:SetSize(btnW, BTN_H)
            addBtn:SetPoint("BOTTOMLEFT", scrollBox or frame, "BOTTOMLEFT", 0, btnY)

            if frame._ebsOfflineBtn then
                frame._ebsOfflineBtn:ClearAllPoints()
                frame._ebsOfflineBtn:SetSize(totalW - btnW * 2, BTN_H)
                frame._ebsOfflineBtn:SetPoint("BOTTOMLEFT", scrollBox or frame, "BOTTOMLEFT", btnW, btnY)
            end

            msgBtn:SetParent(frame)
            msgBtn:ClearAllPoints()
            msgBtn:SetSize(btnW, BTN_H)
            msgBtn:SetPoint("BOTTOMRIGHT", scrollBox or frame, "BOTTOMRIGHT", 0, btnY)
        end

        -- Show/Hide Offline toggle button
        if not frame._ebsOfflineBtn then
            local offBtn = CreateFrame("Button", nil, frame)
            SkinBottomButton(offBtn)
            offBtn:SetSize(85, BTN_H)
            offBtn:SetPoint("BOTTOM", scrollBox or frame, "BOTTOM", 0, btnY)

            local offLabel = offBtn:CreateFontString(nil, "OVERLAY")
            local offFontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
            offLabel:SetFont(offFontPath, 9, "")
            offLabel:SetPoint("CENTER", 0, 0)
            offBtn:SetFontString(offLabel)
            offBtn:SetPushedTextOffset(2, -2)
            offBtn._ebsLabel = offLabel

            local function UpdateOfflineLabel()
                local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
                local showOff = fp and fp.showOffline ~= false
                offLabel:SetText(showOff and (HIDE or "Hide") .. " Offline" or (SHOW or "Show") .. " Offline")
                offLabel:SetTextColor(1, 1, 1, 0.3)
            end
            UpdateOfflineLabel()

            offBtn:SetScript("OnClick", function()
                local fp = EBS.db and EBS.db.profile and EBS.db.profile.friends
                if not fp then return end
                fp.showOffline = not (fp.showOffline ~= false)
                UpdateOfflineLabel()
                if _G._EBS_RebuildFriendsDP then _G._EBS_RebuildFriendsDP() end
            end)

            -- Show Offline: 50% white, 75% on hover, no accent
            local offText = offBtn._ebsLabel
            if offText then offText:SetTextColor(1, 1, 1, 0.3) end
            if offBtn._ppBorders then PP.SetBorderColor(offBtn, 1, 1, 1, 0.3) end
            offBtn:HookScript("OnEnter", function()
                if offText then offText:SetTextColor(1, 1, 1, 0.5) end
                if offBtn._ppBorders then PP.SetBorderColor(offBtn, 1, 1, 1, 0.5) end
            end)
            offBtn:HookScript("OnLeave", function()
                if offText then offText:SetTextColor(1, 1, 1, 0.3) end
                if offBtn._ppBorders then PP.SetBorderColor(offBtn, 1, 1, 1, 0.3) end
            end)

            frame._ebsOfflineBtn = offBtn
            frame._ebsUpdateOfflineLabel = UpdateOfflineLabel
        end

        -- Add Friend: 50% white, 75% on hover, no accent
        local addText = addBtn:GetFontString()
        if addText then addText:SetTextColor(1, 1, 1, 0.3) end
        if addBtn._ppBorders then PP.SetBorderColor(addBtn, 1, 1, 1, 0.3) end
        addBtn:HookScript("OnEnter", function()
            if addText then addText:SetTextColor(1, 1, 1, 0.5) end
            if addBtn._ppBorders then PP.SetBorderColor(addBtn, 1, 1, 1, 0.5) end
        end)
        addBtn:HookScript("OnLeave", function()
            if addText then addText:SetTextColor(1, 1, 1, 0.3) end
            if addBtn._ppBorders then PP.SetBorderColor(addBtn, 1, 1, 1, 0.3) end
        end)

        LayoutFriendBtns()
        frame:HookScript("OnShow", LayoutFriendBtns)
    end

    -- Position custom tabs below the frame
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

            -- 1px pixel-perfect divider between tabs
            if i > 1 then
                if not ct._div then
                    ct._div = ct:CreateTexture(nil, "OVERLAY", nil, 7)
                    PP.DisablePixelSnap(ct._div)
                end
                ct._div:SetColorTexture(1, 1, 1, 0.08)
                ct._div:SetSize(onePx, snappedTabH)
                ct._div:ClearAllPoints()
                ct._div:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, 0)
            end
            lastCT = ct
        end

        -- Tab bar bg (parent to first custom tab so it extends below frame)
        if frame._ebsTabBarBg and lastCT then
            frame._ebsTabBarBg:SetParent(customTabs[1])
            frame._ebsTabBarBg:ClearAllPoints()
            frame._ebsTabBarBg:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
            frame._ebsTabBarBg:SetPoint("BOTTOMRIGHT", lastCT, "BOTTOMRIGHT", 0, 0)
            frame._ebsTabBarBg:SetDrawLayer("BACKGROUND", -8)
        end

        -- 1px top border
        if not frame._ebsTabTopBorder then
            frame._ebsTabTopBorder = customTabs[1]:CreateTexture(nil, "OVERLAY", nil, 7)
            PP.DisablePixelSnap(frame._ebsTabTopBorder)
            frame._ebsTabTopBorder:SetColorTexture(1, 1, 1, 0.08)
            frame._ebsTabTopBorder:SetHeight(onePx)
            frame._ebsTabTopBorder:ClearAllPoints()
            frame._ebsTabTopBorder:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
            frame._ebsTabTopBorder:SetPoint("TOPRIGHT", lastCT, "TOPRIGHT", 0, 0)
        end

        -- Initial state
        UpdateCustomTabs()
    end

    -- Skin close button
    local closeBtn = frame.CloseButton or _G.FriendsFrameCloseButton
    if closeBtn then
        StripTextures(closeBtn)
        closeBtn._ebsX = closeBtn:CreateFontString(nil, "OVERLAY")
        closeBtn._ebsX:SetFont(fontPath, 14, "")
        closeBtn._ebsX:SetText("x")
        closeBtn._ebsX:SetTextColor(1, 1, 1, 0.5)
        closeBtn._ebsX:SetPoint("CENTER", -2, -3)
        closeBtn:HookScript("OnEnter", function()
            closeBtn._ebsX:SetTextColor(1, 1, 1, 0.9)
        end)
        closeBtn:HookScript("OnLeave", function()
            closeBtn._ebsX:SetTextColor(1, 1, 1, 0.5)
        end)
    end

    -- Initial underline update
    C_Timer.After(0, UpdateCustomTabs)
end

-- Live updates: colors, border, opacity
local function ApplyFriends()
    if InCombatLockdown() then QueueApplyAll(); return end

    local p = EBS.db.profile.friends

    if not p.enabled then
        -- Module requires reload to fully disable (same as minimap)
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
    if FriendsFrame._ebsBg then
        FriendsFrame._ebsBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
        FriendsFrame._ebsBg:SetAlpha(1)
    end
    if FriendsFrame._ebsTabBarBg then
        FriendsFrame._ebsTabBarBg:SetColorTexture(FRAME_BG_R, FRAME_BG_G, FRAME_BG_B)
        FriendsFrame._ebsTabBarBg:SetAlpha(1)
    end
    -- Update tile backgrounds on visible buttons (friends + recent allies)
    local scrollBox = FriendsListFrame and FriendsListFrame.ScrollBox
    if scrollBox then
        for _, button in scrollBox:EnumerateFrames() do
            if button._ebsTileBg then
                button._ebsTileBg:SetColorTexture(0, 0, 0, 0.10)
            end
        end
    end
    local rafSB = _G.RecentAlliesFrame and _G.RecentAlliesFrame.List and _G.RecentAlliesFrame.List.ScrollBox
    if rafSB and rafSB.ScrollTarget then
        for i = 1, select("#", rafSB.ScrollTarget:GetChildren()) do
            local button = select(i, rafSB.ScrollTarget:GetChildren())
            if button._ebsTileBg then
                button._ebsTileBg:SetColorTexture(0, 0, 0, 0.10)
            end
        end
    end

    -- Apply accent colors to bottom buttons, raid tab buttons, tab underline, and sub-tab active text
    UpdateBottomButtonAccent()
    UpdateRaidTabButtonAccent()
    if FriendsFrame._ebsUpdateCustomTabs then FriendsFrame._ebsUpdateCustomTabs() end
    if FriendsFrame._ebsUpdateSubTabs then FriendsFrame._ebsUpdateSubTabs() end

    -- Apply scale and saved position
    if FriendsFrame._ebsApplyScaleAndPosition then
        FriendsFrame._ebsApplyScaleAndPosition()
    end
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

-- Pre-allocated tables for mouseoverTargets (avoids creating new tables every call)
local _moCache = {}
local function _moEntry(f)
    if not _moCache[f] then _moCache[f] = { frame = f } end
    return _moCache[f]
end

local function RebuildMouseoverTargets()
    wipe(mouseoverTargets)
    if not EBS.db then return end
    local prof = EBS.db.profile
    -- Chat: use first skinned chat frame as hover anchor, apply alpha to all
    if not TEMP_DISABLED.chat and prof.chat and prof.chat.enabled and prof.chat.visibility == "mouseover" then
        for chatFrame in pairs(skinnedChatFrames) do
            mouseoverTargets[#mouseoverTargets + 1] = _moEntry(chatFrame)
        end
    end
    -- Minimap
    if prof.minimap and prof.minimap.enabled and prof.minimap.visibility == "mouseover" then
        if Minimap then
            mouseoverTargets[#mouseoverTargets + 1] = _moEntry(Minimap)
        end
    end
    -- Friends
    if not TEMP_DISABLED.friends and prof.friends and prof.friends.enabled and prof.friends.visibility == "mouseover" then
        if FriendsFrame then
            mouseoverTargets[#mouseoverTargets + 1] = _moEntry(FriendsFrame)
        end
    end
    if #mouseoverTargets > 0 then
        mouseoverPoll:Show()
    else
        mouseoverPoll:Hide()
    end
end

local function UpdateChatVisibility()
    -- No-op: chat module stripped for rebuild
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
    if TEMP_DISABLED.friends then return end
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

-- Check if ANY module uses a non-"always" visibility mode that requires event updates
local function AnyVisibilityActive()
    if not EBS.db then return false end
    local prof = EBS.db.profile
    local function needs(cfg)
        if not cfg or not cfg.enabled then return false end
        local m = cfg.visibility or "always"
        return m ~= "always"
    end
    if not TEMP_DISABLED.chat and needs(prof.chat) then return true end
    if needs(prof.minimap) then return true end
    if not TEMP_DISABLED.friends and needs(prof.friends) then return true end
    if needs(prof.questTracker) then return true end
    if needs(prof.cursor) then return true end
    return false
end

-- These high-frequency events are only needed when a module uses conditional visibility
local visFrame = CreateFrame("Frame")
-- Always track combat state (cheap: only fires on enter/leave combat)
visFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
visFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local VIS_EVENTS = {
    "PLAYER_TARGET_CHANGED",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
    "GROUP_ROSTER_UPDATE",
    "UPDATE_SHAPESHIFT_FORM",
}
local visEventsRegistered = false

local function UpdateVisEventRegistration()
    local need = AnyVisibilityActive()
    if need and not visEventsRegistered then
        for _, ev in ipairs(VIS_EVENTS) do visFrame:RegisterEvent(ev) end
        visEventsRegistered = true
    elseif not need and visEventsRegistered then
        for _, ev in ipairs(VIS_EVENTS) do visFrame:UnregisterEvent(ev) end
        visEventsRegistered = false
    end
end
_G._EBS_UpdateVisEventRegistration = UpdateVisEventRegistration

local function UpdateAllVisibility()
    if not EBS.db then return end
    UpdateChatVisibility()
    UpdateMinimapVisibility()
    UpdateFriendsVisibility()
    if _G._EBS_UpdateQTVisibility then _G._EBS_UpdateQTVisibility() end
    if _G._ECL_UpdateVisibility then _G._ECL_UpdateVisibility() end
    RebuildMouseoverTargets()
    UpdateVisEventRegistration()
end

-- Expose globals for options/quest tracker/cursor
_G._EBS_InCombat = function() return _ebsInCombat end
_G._EBS_UpdateVisibility = UpdateAllVisibility
_G._EBS_EvalVisibility = EvalVisibility

-- Shared callback avoids creating a new closure on every event fire
local function DeferredUpdateAllVisibility()
    UpdateAllVisibility()
end

visFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        _ebsInCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        _ebsInCombat = false
    end
    C_Timer.After(0, DeferredUpdateAllVisibility)
end)

-------------------------------------------------------------------------------
--  Apply All
-------------------------------------------------------------------------------
ApplyAll = function()
    ApplyChat()
    ApplyMinimap()
    ApplyFriends()
    C_Timer.After(0, DeferredUpdateAllVisibility)
    UpdateVisEventRegistration()
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function EBS:OnInitialize()
    EBS.db = EllesmereUI.Lite.NewDB("EllesmereUIBasicsDB", defaults)

    -- Migrate old hideButtons to individual keys
    local mp = EBS.db.profile.minimap
    if mp.hideButtons ~= nil then
        if mp.hideButtons == true then
            mp.hideZoomButtons    = true
            mp.hideTrackingButton = true
            mp.hideGameTime       = true
        else
            mp.hideZoomButtons    = false
            mp.hideTrackingButton = false
            mp.hideGameTime       = false
        end
        mp.hideButtons = nil
    end

    -- Migrate old "round" shape to "circle"
    if mp.shape == "round" then
        mp.shape = "circle"
    end

    -- Scale removed in favor of direct sizing via snapshot; clean up stale key
    mp.scale = nil

    -- Global bridge for options <-> main communication
    _G._EBS_AceDB        = EBS.db
    _G._EBS_ApplyAll     = ApplyAll
    _G._EBS_ApplyChat    = ApplyChat
    _G._EBS_ApplyMinimap = ApplyMinimap
    _G._EBS_ApplyFriends = ApplyFriends
    _G._EBS_ProcessFriendButtons = ProcessFriendButtons
end

function EBS:OnEnable()
    ApplyAll()

    -- Re-apply after PLAYER_ENTERING_WORLD so accent colors from the theme
    -- system (which updates ELLESMERE_GREEN at PLAYER_LOGIN) are picked up.
    local loginRefresh = CreateFrame("Frame")
    loginRefresh:RegisterEvent("PLAYER_ENTERING_WORLD")
    loginRefresh:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(0, ApplyAll)
        -- One-time popup for users whose friend group assignments were wiped
        if EllesmereUIDB and EllesmereUIDB.global and EllesmereUIDB.global._friendGroupReassignPopup then
            EllesmereUIDB.global._friendGroupReassignPopup = nil
            C_Timer.After(2, function()
                if EllesmereUI and EllesmereUI.ShowConfirmPopup then
                    EllesmereUI:ShowConfirmPopup({
                        title = "Friend Groups Updated",
                        message = "EllesmereUI Update for \"Friend Group\" assignments: Friends must be re-assigned to your groups. Blizzard changes internal bnet ids which made tracking friends this way unstable, a new tracking system is now in place so this won't happen again!",
                        confirmText = "OK",
                    })
                end
            end)
        end
    end)

    -- Hook FriendsFrame for load-on-demand (only if friends module is enabled)
    if not TEMP_DISABLED.friends and EBS.db.profile.friends.enabled then
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
                    -- Hook FriendsFrame's own OnShow as fallback for future opens.
                    -- Do NOT hook the global ShowUIPanel --that taints every panel
                    -- open (World Map, etc.) causing ADDON_ACTION_BLOCKED.
                    if FriendsFrame then
                        FriendsFrame:HookScript("OnShow", function()
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

    -- If GameTimeFrame still doesn't exist, watch for Blizzard_TimeManager to load
    if not _G.GameTimeFrame then
        local tmWatcher = CreateFrame("Frame")
        tmWatcher:RegisterEvent("ADDON_LOADED")
        tmWatcher:SetScript("OnEvent", function(self, _, addon)
            if addon == "Blizzard_TimeManager" then
                self:UnregisterAllEvents()
                if EBS.db.profile.minimap.enabled then
                    C_Timer.After(0, ApplyMinimap)
                end
            end
        end)
    end

    -- Register minimap with unlock mode
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        local MK = EllesmereUI.MakeUnlockElement
        local function MDB() return EBS.db and EBS.db.profile.minimap end
        local function CDB() return EBS.db and EBS.db.profile.chat end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key   = "EBS_Minimap",
                label = "Minimap",
                group = "Basics",
                order = 500,
                noResize = true,
                noAnchorTo = true,
                getFrame = function() return Minimap end,
                getSize  = function()
                    return Minimap:GetWidth(), Minimap:GetHeight()
                end,
                isHidden = function()
                    local m = MDB()
                    return not m or not m.enabled
                end,
                savePos = function(_, point, relPoint, x, y)
                    local m = MDB(); if not m then return end
                    m.position = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        ApplyMinimap()
                    end
                end,
                loadPos = function()
                    local m = MDB()
                    if not m or not m.enabled then return nil end
                    return m.position
                end,
                clearPos = function()
                    local m = MDB(); if not m then return end
                    m.position = nil
                end,
                applyPos = function()
                    local m = MDB()
                    if not m or not m.enabled then return end
                    ApplyMinimap()
                end,
            }),
            MK({
                key   = "EBS_Chat",
                label = "Chat",
                group = "Basics",
                order = 510,
                getFrame = function() return ChatFrame1 end,
                getSize  = function()
                    return ChatFrame1:GetWidth(), ChatFrame1:GetHeight()
                end,
                isHidden = function()
                    local c = CDB()
                    return not c or not c.enabled
                end,
                savePos = function(_, point, relPoint, x, y)
                    local c = CDB(); if not c then return end
                    c.position = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        ApplyChat()
                    end
                end,
                loadPos = function()
                    local c = CDB()
                    return c and c.position
                end,
                clearPos = function()
                    local c = CDB(); if not c then return end
                    c.position = nil
                end,
                applyPos = function()
                    ApplyChat()
                end,
            }),
        })
    end
end
