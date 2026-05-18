-------------------------------------------------------------------------------
--  EllesmereUIMinimap.lua
--  Custom minimap skin and layout for EllesmereUI.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local EBS = EllesmereUI.Lite.NewAddon("EllesmereUIMinimap")

local PP = EllesmereUI.PP

local EG = EllesmereUI.ELLESMERE_GREEN

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-- TEMP_DISABLED kept for call-site compat with helper functions that still
-- reference it. Minimap module is never force-disabled here.
local TEMP_DISABLED = {}

local defaults = {
    profile = {
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
            hideGreatVault       = false,
            greatVaultExtraInfo  = true,
            hidePortals          = false,
            hideAddonCompartment = false,
            hideAddonButtons     = false,
            addonBtnSize         = 24,
            interactableBtnSize  = 21,
            ungroupedButtons     = {},
            freeMoveBtns         = false,
            btnBackgrounds       = true,
            customBtnSizeEnabled = false,
            customBtnSize        = 24,
            btnPositions         = {},
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
    },
}

-------------------------------------------------------------------------------
--  Utility
-------------------------------------------------------------------------------
local function GetBorderColor(cfg)
    if cfg.useClassColor then
        -- Flag name is legacy ("useClassColor") but both minimap and friends
        -- now use the live EllesmereUI accent color when it's set. The flag
        -- name is kept as-is for backwards compat with stored SV data.
        return EG.r, EG.g, EG.b, 1
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
            local mp = EBS.db and EBS.db.profile.minimap
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
    -- Only snapshot original state once; subsequent calls just re-hide
    if not flyoutSavedRegions[btn] then
        local saved = { junk = {} }
        for _, region in ipairs({ btn:GetRegions() }) do
            if IsJunkTexture(region) then
                saved.junk[#saved.junk + 1] = { region = region, alpha = region:GetAlpha(), shown = region:IsShown() }
            end
        end
        local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if hl and IsJunkTexture(hl) then
            saved.junk[#saved.junk + 1] = { region = hl, alpha = hl:GetAlpha(), shown = hl:IsShown() }
        end
        -- Snapshot icon anchors/texcoord so we can restore native layout
        local icon = btn.icon or btn.Icon
        if icon then
            local nPts = icon:GetNumPoints()
            local pts = {}
            for i = 1, nPts do
                pts[i] = { icon:GetPoint(i) }
            end
            saved.icon = icon
            saved.iconPoints = pts
            saved.iconTC = { icon:GetTexCoord() }
        end
        -- Snapshot native button size
        saved.btnW, saved.btnH = btn:GetWidth(), btn:GetHeight()
        flyoutSavedRegions[btn] = saved
    end
    -- Hide junk textures (runs every call)
    for _, info in ipairs(flyoutSavedRegions[btn].junk) do
        info.region:SetAlpha(0)
        info.region:Hide()
    end
end

local function RestoreButtonDecorations(btn)
    local saved = flyoutSavedRegions[btn]
    if not saved then return end
    for _, info in ipairs(saved.junk) do
        info.region:SetAlpha(info.alpha)
        if info.shown then info.region:Show() end
    end
    -- Restore icon anchors and texcoord
    if saved.icon and saved.iconPoints then
        saved.icon:ClearAllPoints()
        for _, pt in ipairs(saved.iconPoints) do
            saved.icon:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
        end
        if saved.iconTC and #saved.iconTC >= 8 then
            saved.icon:SetTexCoord(unpack(saved.iconTC))
        end
    end
    -- Restore native button size
    if saved.btnW and saved.btnH then
        btn:SetSize(saved.btnW, saved.btnH)
    end
    flyoutSavedRegions[btn] = nil
end

local function IsUngrouped(btn)
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp or not mp.ungroupedButtons then return false end
    local name = btn:GetName()
    return name and mp.ungroupedButtons[name]
end

local function GetMinimapButtonLabel(btn)
    local name = btn:GetName() or ""
    return name:gsub("^LibDBIcon10_", ""):gsub("^Lib_GPI_Minimap_", ""):gsub("MinimapButton$", ""):gsub("_MinimapButton$", "")
end

local function CollectFlyoutButtons()
    -- Return only buttons the addon wants visible and not ungrouped
    local collected = {}
    for _, btn in ipairs(cachedAddonButtons) do
        if _addonVisible[btn] ~= false and not IsUngrouped(btn) then
            collected[#collected + 1] = btn
        end
    end
    table.sort(collected, function(a, b)
        return GetMinimapButtonLabel(a):lower() < GetMinimapButtonLabel(b):lower()
    end)
    return collected
end

local function GetAddonBtnSize()
    local mp = EBS.db and EBS.db.profile.minimap
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
        -- Hide ungrouped overlays left over from a previous ungroup cycle
        if GetFFD(btn).ungroupBg then GetFFD(btn).ungroupBg:Hide() end
        if btn._ungroupRing then btn._ungroupRing:Hide() end
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
            pcall(icon.SetTexCoord, icon, 0.05, 0.95, 0.05, 0.95)
        end
        -- Add atlas ring border overlay
        if not GetFFD(btn).flyoutRing then
            local ring = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            ring:SetAtlas("AdventureMap-combatally-ring")
            ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
            ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
            GetFFD(btn).flyoutRing = ring
        end
        GetFFD(btn).flyoutRing:Show()
    end
end

local function RestoreFlyoutButtons()
    for btn, saved in pairs(flyoutSavedParents) do
        RestoreButtonDecorations(btn)
        if GetFFD(btn).flyoutRing then GetFFD(btn).flyoutRing:Hide() end
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

local _flyoutBuilt = false

local function EnsureFlyoutPanel()
    if not flyoutPanel then
        flyoutPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        flyoutPanel:SetFrameStrata("DIALOG")
        flyoutPanel:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
        })
        flyoutPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        flyoutPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        flyoutPanel:SetPoint("BOTTOMLEFT", flyoutToggle, "BOTTOMRIGHT", 2, 0)
        flyoutPanel:SetClampedToScreen(true)
        flyoutOwnedFrames[flyoutPanel] = true
    end
end

-- Build the flyout contents once. Buttons are reparented into the grid
-- and stay there permanently. Only rebuilds when the button list changes
-- (new addon loaded, button ungrouped, etc).
local function BuildFlyoutContents()
    EnsureFlyoutPanel()
    LayoutFlyoutButtons()
    _flyoutBuilt = true
end

-- Force a rebuild on next show (called when button list changes)
local function InvalidateFlyout()
    _flyoutBuilt = false
end

-- Profile-swap refresh: re-show buttons in the flyout and invalidate
-- so the next open rebuilds with new settings. Also re-asserts alpha
-- on buttons that may have been hidden by re-initialization.
_G._EMIN_RefreshFlyout = function()
    InvalidateFlyout()
    if flyoutPanel and flyoutPanel:IsShown() then
        BuildFlyoutContents()
    end
    -- Re-assert alpha on buttons in the flyout (profile swap may have
    -- re-hidden them via HideMinimapChild during re-init)
    for _, btn in ipairs(cachedAddonButtons) do
        if btn:GetParent() == flyoutPanel then
            btn:SetAlpha(1)
            btn:Show()
        end
    end
end

local function ShowFlyoutPanel()
    EnsureFlyoutPanel()
    -- Show the panel BEFORE layout so the Show hook on addon buttons
    -- sees flyoutPanel:IsShown() == true and skips the alpha-zero path.
    flyoutPanel:Show()
    if not _flyoutBuilt then
        BuildFlyoutContents()
    end
end

local function HideFlyoutPanel()
    if flyoutPanel then
        flyoutPanel:Hide()
        -- Do NOT restore buttons or wipe saved parents.
        -- Buttons stay parented to the flyout panel permanently.
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
    local mp = EBS.db and EBS.db.profile.minimap
    return mp and mp.interactableBtnSize or 22
end

local function CreateFlyoutToggle()
    if flyoutToggle then
        -- Re-apply the current accent to the existing textures so a later
        -- ApplyAll (e.g. at PLAYER_ENTERING_WORLD, after EllesmereUI's theme
        -- resolution has mutated ELLESMERE_GREEN) picks up the right color.
        local EG2 = EllesmereUI.ELLESMERE_GREEN
        if flyoutToggle._norm   then flyoutToggle._norm:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)   end
        if flyoutToggle._pushed then flyoutToggle._pushed:SetVertexColor(EG2.r, EG2.g, EG2.b, 1) end
        if flyoutToggle._hl     then flyoutToggle._hl:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)     end
        return flyoutToggle
    end

    local btn = CreateFrame("Button", nil, Minimap)
    local iconSize = GetInteractableBtnSize()
    btn:SetSize(iconSize, iconSize)
    btn:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT", 0, 0)
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 10)

    local norm = btn:CreateTexture(nil, "ARTWORK")
    norm:SetAllPoints()
    norm:SetAtlas("Map-Filter-Button")
    norm:SetDesaturated(true)
    norm:SetVertexColor(EG.r, EG.g, EG.b, 1)
    btn:SetNormalTexture(norm)
    btn._norm = norm

    local pushed = btn:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    pushed:SetAtlas("Map-Filter-Button-down")
    pushed:SetDesaturated(true)
    pushed:SetVertexColor(EG.r, EG.g, EG.b, 1)
    btn:SetPushedTexture(pushed)
    btn._pushed = pushed

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetAtlas("Map-Filter-Button")
    hl:SetDesaturated(true)
    hl:SetVertexColor(EG.r, EG.g, EG.b, 1)
    hl:SetAlpha(0.3)
    btn:SetHighlightTexture(hl)
    btn._hl = hl

    -- Keep the three textures in sync with the accent color.
    -- Vertex alpha stays at 1; the highlight's SetAlpha(0.3) still applies
    -- on top since the two multiply.
    EllesmereUI.RegAccent({ type = "vertex", obj = norm })
    EllesmereUI.RegAccent({ type = "vertex", obj = pushed })
    EllesmereUI.RegAccent({ type = "vertex", obj = hl })

    -- Black background to match indicator icons
    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    btn:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        ToggleFlyoutPanel()
    end)
    btn:SetScript("OnEnter", function(self)
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Addon Buttons", { anchor = "left" })
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

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
    local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("minimap") or STANDARD_TEXT_FONT
    local flag = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("minimap") or "OUTLINE"
    return path, flag
end

local function ApplyMinimapFont(fs, size)
    local path, flag = GetMinimapFont()
    fs:SetFont(path, size, flag)
    if EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow("minimap") then
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

-------------------------------------------------------------------------------
--  Free Move Button System
--  When freeMoveBtns is enabled, shift+click any minimap-area button to drag
--  it. Positions are stored as offsets in DB.profile.minimap.btnPositions
--  keyed by a stable identifier string.
-------------------------------------------------------------------------------
local function GetBtnPosKey(frame)
    -- Custom indicator buttons store their key directly
    if frame._indicatorKey then return frame._indicatorKey end
    local name = frame:GetName()
    if name then return name end
    if frame == flyoutToggle then return "_flyoutToggle" end
    return nil
end

local function GetBtnOffset(key)
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp or not mp.freeMoveBtns or not mp.btnPositions then return 0, 0 end
    local pos = mp.btnPositions[key]
    if not pos then return 0, 0 end
    return pos.x or 0, pos.y or 0
end

local function SaveBtnOffset(key, x, y)
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp then return end
    if not mp.btnPositions then mp.btnPositions = {} end
    mp.btnPositions[key] = { x = x, y = y }
end

local _freeMoveHooked = {}  -- [frame] = true, one-time hook guard

local function EnableFreeMove(frame)
    if not frame or _freeMoveHooked[frame] then return end
    _freeMoveHooked[frame] = true

    local key = GetBtnPosKey(frame)
    if not key then return end

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Guard third-party buttons (LibDBIcon, etc.) that have their own OnClick.
    -- Wrap their handler so the drag flag blocks click-through.
    if not frame._indicatorKey and frame ~= flyoutToggle then
        local origClick = frame:GetScript("OnClick")
        if origClick then
            frame:SetScript("OnClick", function(self, ...)
                if GetFFD(self).freeMoveJustDragged then return end
                origClick(self, ...)
            end)
        end
    end

    local isDragging = false
    local startX, startY, origOffX, origOffY

    local origPoint, origRel, origRelPoint, origX, origY

    local function FreeMoveOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then
            isDragging = false
            self:SetScript("OnUpdate", nil)
            -- Clear the drag flag on the next frame (set in OnMouseDown)
            C_Timer.After(0, function() GetFFD(self).freeMoveJustDragged = nil end)
            -- Save final offset and re-layout once on release
            local es = self:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / es, cy / es
            local dx, dy = cx - startX, cy - startY
            SaveBtnOffset(key, origOffX + dx, origOffY + dy)
            if ApplyMinimap then ApplyMinimap() end
            return
        end
        -- Move the button directly during drag (no full relayout)
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / es, cy / es
        local dx, dy = cx - startX, cy - startY
        if origPoint then
            self:ClearAllPoints()
            self:SetPoint(origPoint, origRel, origRelPoint, origX + origOffX + dx, origY + origOffY + dy)
        end
    end

    frame:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if not IsShiftKeyDown() then return end
        local mp = EBS.db and EBS.db.profile.minimap
        if not mp or not mp.freeMoveBtns then return end
        isDragging = true
        -- Block click actions immediately so OnClick can never fire during a drag,
        -- regardless of WoW's event ordering. Cleared on the frame after release.
        GetFFD(self).freeMoveJustDragged = true
        local es = self:GetEffectiveScale()
        startX, startY = GetCursorPosition()
        startX, startY = startX / es, startY / es
        origOffX, origOffY = GetBtnOffset(key)
        -- Snapshot the button's current anchor (before any offset)
        origPoint, origRel, origRelPoint, origX, origY = self:GetPoint(1)
        -- Subtract current offset to get the base anchor position
        origX = (origX or 0) - origOffX
        origY = (origY or 0) - origOffY
        self:SetScript("OnUpdate", FreeMoveOnUpdate)
    end)

    frame:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not isDragging then return end
        isDragging = false
        self:SetScript("OnUpdate", nil)
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / es, cy / es
        local dx, dy = cx - startX, cy - startY
        SaveBtnOffset(key, origOffX + dx, origOffY + dy)
        -- Clear the drag flag on the next frame (set in OnMouseDown)
        C_Timer.After(0, function() GetFFD(frame).freeMoveJustDragged = nil end)
        if ApplyMinimap then ApplyMinimap() end
    end)

end

-- Apply saved offset to a button (called during layout)
local function ApplyBtnOffset(frame)
    if not frame then return end
    local key = GetBtnPosKey(frame)
    if not key then return end
    local ox, oy = GetBtnOffset(key)
    if ox == 0 and oy == 0 then return end
    local p1, rel, p2, x, y = frame:GetPoint(1)
    if p1 then
        frame:SetPoint(p1, rel, p2, (x or 0) + ox, (y or 0) + oy)
    end
end

local function SaveZoomLevel()
    local p = EBS.db and EBS.db.profile.minimap
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
                -- Don't track addon Show() while flyout is open: the button
                -- is already visible in our grid, and tracking would let a
                -- subsequent Hide() mark it as unwanted.
                if not (flyoutPanel and flyoutPanel:IsShown()) then
                    _addonVisible[self] = true
                end
            end
            if InCombatLockdown() then return end
            -- Never zero alpha while the flyout is open -- addon buttons
            -- are visible in the grid and periodic Show() calls from
            -- LibDBIcon/addons would make them disappear mid-view.
            if flyoutPanel and flyoutPanel:IsShown() then return end
            -- Allow ungrouped buttons to stay visible
            if IsUngrouped(self) then return end
            local mp = EBS.db and EBS.db.profile.minimap
            if mp and mp.enabled and not flyoutOwnedFrames[self] then
                self:SetAlpha(0)
            end
        end)
        hooksecurefunc(btn, "Hide", function(self)
            if not _suppressVisTrack then
                -- Freeze visibility tracking while the flyout is open.
                -- LibDBIcon and addons periodically call Hide() during
                -- internal refreshes; letting that mark _addonVisible=false
                -- causes buttons to vanish from the open flyout grid.
                if flyoutPanel and flyoutPanel:IsShown() then
                    self:Show()
                    return
                end
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
                elseif child:IsObjectType("Button") and name
                    and not name:match("%d+$") then
                    local w = child:GetWidth() or 0
                    -- Width gate only for first discovery; once a button is
                    -- tracked in _addonVisible it is always re-collected so
                    -- our own SetSize (e.g. slider < 20) can't permanently
                    -- drop it from the list.
                    if w >= 20 or _addonVisible[child] ~= nil then
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
-- Buttons currently displayed inside the open flyout are also skipped --
-- HideMinimapChild uses _suppressVisTrack which bypasses the force-show
-- protection in the Hide hook, so calling it on flyout buttons while the
-- panel is visible would silently zero their alpha with no recovery.
local function HideAllMinimapButtons()
    GatherMinimapButtons()
    local flyoutOpen = flyoutPanel and flyoutPanel:IsShown()
    for _, btn in ipairs(cachedAddonButtons) do
        if not IsUngrouped(btn) then
            if flyoutOpen and btn:GetParent() == flyoutPanel then
                -- Button is visible in the flyout grid; leave it alone
            else
                HideMinimapChild(btn)
            end
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
--  Minimap Indicator Buttons (custom replacements for Blizzard's reparented frames)
--  Each is our own Button with a black bg, icon texture, and simple click handler.
--  No Blizzard frame reparenting = no taint, no layout fights.
-------------------------------------------------------------------------------
local indicatorBg = nil  -- combined bg strip for square mode (legacy, still used when free move is off)
local _customIndicators = {}  -- { tracking, calendar, mail, crafting }

-- Native atlas aspect ratios (width / height) and per-icon scale multipliers
local INDICATOR_ATLAS_RATIO = {
    ["UI-HUD-Minimap-Tracking-Up"]           = 15 / 14,
    ["UI-HUD-Minimap-Tracking-Mouseover"]    = 15 / 14,
    ["UI-HUD-Minimap-Tracking-Down"]         = 16 / 15,
    ["UI-HUD-Minimap-Mail-Up"]               = 19.5 / 15,
    ["UI-HUD-Minimap-Mail-Mouseover"]        = 19.5 / 15,
    ["UI-HUD-Minimap-CraftingOrder-Up-2x"]   = 17 / 16,
    ["UI-HUD-Minimap-CraftingOrder-Over-2x"] = 17 / 16,
    ["UI-HUD-Minimap-CraftingOrder-Down-2x"] = 17 / 16,
}
local INDICATOR_ATLAS_SCALE = {}
-- Calendar atlases: all 31 days share the same ratio/scale
for day = 1, 31 do
    local prefix = "UI-HUD-Calendar-" .. day
    INDICATOR_ATLAS_RATIO[prefix .. "-Up"]        = 21 / 19
    INDICATOR_ATLAS_RATIO[prefix .. "-Mouseover"] = 21 / 19
    INDICATOR_ATLAS_RATIO[prefix .. "-Down"]      = 21 / 19
    INDICATOR_ATLAS_SCALE[prefix .. "-Up"]        = 1.25
    INDICATOR_ATLAS_SCALE[prefix .. "-Mouseover"] = 1.25
    INDICATOR_ATLAS_SCALE[prefix .. "-Down"]      = 1.25
end
-- Per-icon pixel offset from center { x, y }
local INDICATOR_ATLAS_OFFSET = {
    _gameTime = { 2, -2 },
    _mail     = { 1, -1 },
}

local function CreateIndicatorBtn(name, parent, upAtlas, overAtlas, downAtlas, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    btn:SetFrameLevel(parent:GetFrameLevel() + 20)
    btn:EnableMouse(true)

    -- Black background
    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    -- Icon: sized to preserve atlas aspect ratio within the button
    local icon = btn:CreateTexture(nil, "ARTWORK")
    local inset = 3
    local ratio = upAtlas and INDICATOR_ATLAS_RATIO[upAtlas]
    if ratio then
        local btnSz = GetInteractableBtnSize()
        local avail = btnSz - inset * 2
        local scale = INDICATOR_ATLAS_SCALE[upAtlas] or 1
        local iconW, iconH
        if ratio >= 1 then
            iconW = avail * scale
            iconH = (avail / ratio) * scale
        else
            iconH = avail * scale
            iconW = (avail * ratio) * scale
        end
        icon:SetSize(iconW, iconH)
        local off = INDICATOR_ATLAS_OFFSET[name]
        icon:SetPoint("CENTER", btn, "CENTER", off and off[1] or 0, off and off[2] or 0)
    else
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
    end
    if upAtlas then icon:SetAtlas(upAtlas) end
    btn._icon = icon
    btn._upAtlas = upAtlas
    btn._overAtlas = overAtlas
    btn._downAtlas = downAtlas
    btn._indicatorKey = name

    -- Hover/push states
    btn:SetScript("OnEnter", function(self)
        if self._overAtlas and self._icon then self._icon:SetAtlas(self._overAtlas) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self._upAtlas and self._icon then self._icon:SetAtlas(self._upAtlas) end
    end)
    btn:SetScript("OnMouseDown", function(self)
        if self._downAtlas and self._icon then self._icon:SetAtlas(self._downAtlas) end
    end)
    btn:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local atlas = over and self._overAtlas or self._upAtlas
        if atlas and self._icon then self._icon:SetAtlas(atlas) end
    end)

    if onClick then
        btn:SetScript("OnClick", function(self)
            if GetFFD(self).freeMoveJustDragged then return end
            onClick(self)
        end)
    end

    return btn
end

-- Great Vault button. Lives at the top of the ungrouped-button stack above
-- the flyout toggle. Single "whole" atlas scaled to fit the button.
local _greatVaultBtn = nil
local GREAT_VAULT_WHOLE_ATLAS = "greatVault-whole-normal"

local function RegisterVaultEscClose()
    local wrf = _G.WeeklyRewardsFrame
    if not wrf or not EllesmereUI.RegisterEscapeClose then return end
    EllesmereUI.RegisterEscapeClose(wrf)
end

local function ColorizeVaultText(text, r, g, b)
    r = math.floor(math.max(0, math.min(1, r or 1)) * 255 + 0.5)
    g = math.floor(math.max(0, math.min(1, g or 1)) * 255 + 0.5)
    b = math.floor(math.max(0, math.min(1, b or 1)) * 255 + 0.5)
    return ("|cff%02x%02x%02x%s|r"):format(r, g, b, tostring(text or ""))
end

local function GetOrderedWeeklyActivities(activityType)
    if not C_WeeklyRewards or not C_WeeklyRewards.GetActivities then return nil end

    local activities = C_WeeklyRewards.GetActivities(activityType)
    if type(activities) ~= "table" or #activities == 0 then
        return nil
    end

    local ordered = {}
    for i = 1, #activities do
        ordered[i] = activities[i]
    end

    table.sort(ordered, function(a, b)
        local aIndex = a and a.index or 0
        local bIndex = b and b.index or 0
        if aIndex == bIndex then
            return (a and a.threshold or 0) < (b and b.threshold or 0)
        end
        return aIndex < bIndex
    end)

    return ordered
end

local function GetVaultTokenColor(state)
    if state == "done" then
        return 0.176, 0.796, 0.349
    elseif state == "partial" then
        return 0.812, 0.592, 0.212
    end

    return 0.58, 0.58, 0.58
end

local function FormatVaultToken(text, state)
    local r, g, b = GetVaultTokenColor(state)
    return ColorizeVaultText(text, r, g, b)
end

-- Build vault row data: { label, isRaid, tokens = { {text, state}, ... } }
local function BuildVaultRowData(label, activityType, isRaid)
    local activities = GetOrderedWeeklyActivities(activityType)
    local tokens = {}
    for i = 1, 3 do
        local info = activities and activities[i]
        if not info then
            tokens[i] = { text = "-", state = "empty" }
        else
            local progress = math.max(0, tonumber(info.progress) or 0)
            local threshold = math.max(0, tonumber(info.threshold) or 0)
            local level = math.max(0, tonumber(info.level) or 0)
            if threshold <= 0 then
                tokens[i] = { text = "-", state = "empty" }
            elseif progress >= threshold then
                if isRaid then
                    tokens[i] = { text = ("%d/%d"):format(progress, threshold), state = "done" }
                elseif level > 0 then
                    tokens[i] = { text = "+" .. level, state = "done" }
                else
                    tokens[i] = { text = ("%d/%d"):format(progress, threshold), state = "done" }
                end
            else
                tokens[i] = { text = ("%d/%d"):format(progress, threshold), state = progress > 0 and "partial" or "empty" }
            end
        end
    end
    return { label = label, tokens = tokens }
end

-- Custom multi-column vault tooltip (pixel-aligned columns via FontStrings)
local _vaultTT
local _vaultTTRows = {}  -- [row][col] = FontString
local VAULT_COL_GAP = 8
local VAULT_ROW_H = 14
local VAULT_PAD = 6

local function GetVaultTooltip()
    if _vaultTT then return _vaultTT end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.90)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    f:SetFrameStrata("TOOLTIP")
    f:Hide()

    -- Fade animations (matches ShowWidgetTooltip/HideWidgetTooltip)
    local fadeInAG = f:CreateAnimationGroup()
    local fadeIn = fadeInAG:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.25); fadeIn:SetSmoothing("OUT")
    fadeInAG:SetScript("OnFinished", function() f:SetAlpha(1) end)
    f._fadeInAG = fadeInAG; f._fadeIn = fadeIn

    local fadeOutAG = f:CreateAnimationGroup()
    local fadeOut = fadeOutAG:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.25); fadeOut:SetSmoothing("IN")
    fadeOutAG:SetScript("OnFinished", function() f:SetAlpha(0); f:Hide() end)
    f._fadeOutAG = fadeOutAG; f._fadeOut = fadeOut

    -- Title row (font set at show-time)
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")  -- placeholder, updated on show
    title:SetTextColor(0.80, 0.80, 0.80, 1)
    title:SetPoint("TOP", f, "TOP", 0, -VAULT_PAD)
    title:SetText("Great Vault")
    f._title = title

    -- 3 data rows x 4 columns (label + 3 tokens)
    for row = 1, 3 do
        _vaultTTRows[row] = {}
        for col = 0, 3 do
            local fs = f:CreateFontString(nil, "OVERLAY")
            fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "")  -- placeholder, updated on show
            fs:SetJustifyH("LEFT")
            _vaultTTRows[row][col] = fs
        end
    end

    _vaultTT = f
    return f
end

local function ShowVaultTooltip(anchor)
    local raidType = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Raid) or 3
    local dungeonType = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Activities) or 1
    local worldType = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.World) or 6

    local rows = {
        BuildVaultRowData("Raids", raidType, true),
        BuildVaultRowData("Mythic+", dungeonType, false),
        BuildVaultRowData("World", worldType, false),
    }

    local tt = GetVaultTooltip()

    -- Apply user's current font to all FontStrings
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
    local fontFlags = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
    tt._title:SetFont(fontPath, 11, fontFlags)
    for r = 1, 3 do
        _vaultTTRows[r][0]:SetFont(fontPath, 11, fontFlags)
        for c = 1, 3 do
            _vaultTTRows[r][c]:SetFont(fontPath, 10, fontFlags)
        end
    end

    -- Populate text and measure column widths
    local colWidths = { 0, 0, 0, 0 }
    for r = 1, 3 do
        local rd = rows[r]
        local labelFS = _vaultTTRows[r][0]
        labelFS:SetText(rd.label)
        labelFS:SetTextColor(0.812, 0.592, 0.212, 1)
        local w = labelFS:GetStringWidth() or 0
        if w > colWidths[1] then colWidths[1] = w end

        for c = 1, 3 do
            local tk = rd.tokens[c]
            local fs = _vaultTTRows[r][c]
            fs:SetText(tk.text)
            local tr, tg, tb = GetVaultTokenColor(tk.state)
            fs:SetTextColor(tr, tg, tb, 1)
            local tw = fs:GetStringWidth() or 0
            if tw > colWidths[c + 1] then colWidths[c + 1] = tw end
        end
    end

    -- Position columns at measured offsets
    local titleTop = VAULT_PAD + (tt._title:GetStringHeight() or 14) + 4
    local colX = { VAULT_PAD }
    for c = 2, 4 do
        colX[c] = colX[c - 1] + colWidths[c - 1] + VAULT_COL_GAP
    end
    local totalW = colX[4] + colWidths[4] + VAULT_PAD

    for r = 1, 3 do
        local y = -(titleTop + (r - 1) * VAULT_ROW_H)
        for c = 0, 3 do
            _vaultTTRows[r][c]:ClearAllPoints()
            _vaultTTRows[r][c]:SetPoint("TOPLEFT", tt, "TOPLEFT", colX[c + 1], y)
        end
    end

    local totalH = titleTop + 3 * VAULT_ROW_H + VAULT_PAD
    tt:SetSize(totalW, totalH)
    tt:ClearAllPoints()
    tt:SetPoint("RIGHT", anchor, "LEFT", -4, 0)

    -- Fade in
    tt._fadeOutAG:Stop()
    tt._fadeInAG:Stop()
    tt:SetAlpha(0)
    tt:Show()
    tt._fadeIn:SetFromAlpha(0)
    tt._fadeIn:SetToAlpha(1)
    tt._fadeInAG:Play()
end

local function HideVaultTooltip()
    if not _vaultTT or not _vaultTT:IsShown() then return end
    _vaultTT._fadeInAG:Stop()
    _vaultTT._fadeOutAG:Stop()
    _vaultTT._fadeOut:SetFromAlpha(_vaultTT:GetAlpha())
    _vaultTT._fadeOut:SetToAlpha(0)
    _vaultTT._fadeOutAG:Play()
end

local function ToggleGreatVault()
    local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    local Load     = (C_AddOns and C_AddOns.LoadAddOn)     or _G.LoadAddOn
    if Load and IsLoaded and not IsLoaded("Blizzard_WeeklyRewards") then
        Load("Blizzard_WeeklyRewards")
    end
    RegisterVaultEscClose()
    if WeeklyRewardsFrame then
        WeeklyRewardsFrame:SetShown(not WeeklyRewardsFrame:IsShown())
    end
end

local function SizeGreatVaultBtn(btn, showBg)
    local btnSz = GetInteractableBtnSize()
    btn:SetSize(btnSz, btnSz)
    if btn._bg then btn._bg:SetShown(showBg ~= false) end
    local inset = 3
    local avail = btnSz - inset * 2
    -- Whole is 105x108: height is the limiting dimension. Fit by height.
    local wholeH = avail
    local wholeW = wholeH * (105 / 108)
    btn._whole:SetSize(wholeW, wholeH)
    btn._whole:ClearAllPoints()
    btn._whole:SetPoint("CENTER", btn, "CENTER", 0, 0)
end

local function CreateGreatVaultBtn(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)
    btn:EnableMouse(true)

    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    local whole = btn:CreateTexture(nil, "ARTWORK")
    whole:SetAtlas(GREAT_VAULT_WHOLE_ATLAS)
    btn._whole = whole

    SizeGreatVaultBtn(btn)

    btn:SetScript("OnEnter", function(self)
        self._whole:SetVertexColor(1, 1, 1, 1)
        local minimapCfg = EBS and EBS.db and EBS.db.profile and EBS.db.profile.minimap
        if minimapCfg and minimapCfg.greatVaultExtraInfo == false then
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, "Great Vault", { anchor = "left" })
            end
        else
            ShowVaultTooltip(self)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self._whole:SetVertexColor(0.85, 0.85, 0.85, 1)
        HideVaultTooltip()
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._whole:SetVertexColor(0.7, 0.7, 0.7, 1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local v = over and 1 or 0.85
        self._whole:SetVertexColor(v, v, v, 1)
    end)
    btn:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        ToggleGreatVault()
    end)

    -- Resting tint matches OnLeave state
    whole:SetVertexColor(0.85, 0.85, 0.85, 1)

    btn._indicatorKey = "_greatVault"

    return btn
end

-------------------------------------------------------------------------------
-- M+ Portal button. Identical flyout as Chat sidebar but anchored to minimap.
-------------------------------------------------------------------------------
local PORTAL_SPELLS = {
    1254400, 1254572, 1254563, 1254559,
    159898,  1254555, 1254551, 393273,
}
local PORTAL_SHORT = {
    [1254400] = "WRS", [1254572] = "MT",  [1254563] = "NPX", [1254559] = "MC",
    [159898]  = "SR",  [1254555] = "PoS", [1254551] = "SoT", [393273]  = "AA",
}

local _portalBtn = nil
local _portalFlyout, _portalFlyoutBtns

local function RefreshMinimapPortalButtons()
    if not _portalFlyoutBtns then return end
    for _, btn in ipairs(_portalFlyoutBtns) do
        local spellID = btn.spellID
        local known = IsPlayerSpell(spellID)
        if btn._lastKnown ~= known then
            btn._lastKnown = known
            btn.icon:SetDesaturated(not known)
            btn.icon:SetAlpha(known and 1 or 0.4)
        end
        if known then
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                btn.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
            else
                btn.cooldown:Clear()
            end
        else
            btn.cooldown:Clear()
        end
    end
end

local function CreateMinimapPortalFlyout()
    if _portalFlyout then return _portalFlyout end

    local BTN_SIZE = 32
    local SPACING = 1
    local PADDING = 2
    local COLS = 4
    local ROWS = math.ceil(#PORTAL_SPELLS / COLS)

    local portalW = PADDING * 2 + BTN_SIZE * COLS + SPACING * (COLS - 1)
    local flyH = PADDING * 2 + BTN_SIZE * ROWS + SPACING * (ROWS - 1)
    local HS_COUNT = 3
    local HS_H = math.floor((flyH - PADDING * 2 - SPACING * (HS_COUNT - 1)) / HS_COUNT)
    local hsX = PADDING + COLS * BTN_SIZE + (COLS - 1) * SPACING + SPACING
    local flyW = hsX + HS_H + PADDING

    local flyout = CreateFrame("Frame", "EUIMinimapPortalFlyout", UIParent)
    flyout:SetSize(flyW, flyH)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetFrameLevel(100)
    flyout:Hide()

    local bg = flyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.95)

    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.CreateBorder then
        PP.CreateBorder(flyout, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
    end

    local guard = CreateFrame("Frame")
    guard:RegisterEvent("PLAYER_REGEN_DISABLED")
    guard:SetScript("OnEvent", function() flyout:Hide() end)

    _portalFlyoutBtns = {}
    for i, spellID in ipairs(PORTAL_SPELLS) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)

        local btn = CreateFrame("Button", "EUIMinimapPortal" .. i, flyout, "SecureActionButtonTemplate")
        btn:SetSize(BTN_SIZE, BTN_SIZE)
        btn:SetPoint("TOPLEFT", flyout, "TOPLEFT",
            PADDING + col * (BTN_SIZE + SPACING),
            -(PADDING + row * (BTN_SIZE + SPACING)))

        btn.spellID = spellID

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo then icon:SetTexture(spellInfo.iconID) end
        btn.icon = icon

        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(true)
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        btn.cooldown = cd

        local short = PORTAL_SHORT[spellID]
        if short then
            local fontPath = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("minimap")) or "Fonts\\FRIZQT__.TTF"
            local labelFrame = CreateFrame("Frame", nil, btn)
            labelFrame:SetAllPoints()
            labelFrame:SetFrameLevel(cd:GetFrameLevel() + 2)
            local label = labelFrame:CreateFontString(nil, "OVERLAY", nil)
            label:SetFont(fontPath, 8, "OUTLINE")
            label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
            label:SetTextColor(1, 1, 1, 0.9)
            label:SetText(short)
            label:SetShadowOffset(1, -1)
            label:SetShadowColor(0, 0, 0, 1)
        end

        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.20)

        local castHL = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        castHL:SetAllPoints()
        castHL:SetColorTexture(1, 1, 1, 0.4)
        castHL:Hide()
        btn._castHL = castHL

        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spellID)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        _portalFlyoutBtns[i] = btn
    end

    -- Hearthstone column: 3 icons stacked vertically as a 5th column
    local _hearthBtns = {}
    for i = 1, HS_COUNT do
        local btn = CreateFrame("Button", "EUIMinimapHearth" .. i, flyout, "SecureActionButtonTemplate")
        btn:SetSize(HS_H, HS_H)
        btn:SetPoint("TOPLEFT", flyout, "TOPLEFT",
            hsX,
            -(PADDING + (i - 1) * (HS_H + SPACING)))

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
        btn.icon = icon

        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(true)
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        btn.cooldown = cd

        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.20)

        btn:RegisterForClicks("AnyUp", "AnyDown")

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._hsType == "spell" then
                GameTooltip:SetSpellByID(self._hsID)
            elseif self._hsType == "item" then
                if self._hsID ~= 6948 and PlayerHasToy and PlayerHasToy(self._hsID) then
                    GameTooltip:SetToyByItemID(self._hsID)
                else
                    GameTooltip:SetItemByID(self._hsID)
                end
            elseif self._hsType == "housing" then
                GameTooltip:AddLine("Housing Dashboard")
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local castHL = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        castHL:SetAllPoints()
        castHL:SetColorTexture(1, 1, 1, 0.4)
        castHL:Hide()
        btn._castHL = castHL

        btn:HookScript("PostClick", function(self)
            if self._hsType == "housing" then
                if HousingFramesUtil and HousingFramesUtil.ToggleHousingDashboard then
                    HousingFramesUtil.ToggleHousingDashboard()
                end
                if _portalFlyout then _portalFlyout:Hide() end
            else
                self._castHL:Show()
            end
        end)

        _hearthBtns[i] = btn
    end


    local function RefreshHearthCooldowns()
        for _, btn in ipairs(_hearthBtns) do
            local aType, id = btn._hsType, btn._hsID
            if aType == "spell" and C_Spell and C_Spell.GetSpellCooldown then
                local cdInfo = C_Spell.GetSpellCooldown(id)
                if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                    btn.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
                else
                    btn.cooldown:Clear()
                end
            elseif aType == "item" and GetItemCooldown then
                local ok, start, dur = pcall(GetItemCooldown, id)
                if ok and start and dur and dur > 0 then
                    btn.cooldown:SetCooldown(start, dur)
                else
                    btn.cooldown:Clear()
                end
            else
                btn.cooldown:Clear()
            end
        end
    end

    local function ResolveHearthButtons()
        if InCombatLockdown() then return end
        local EUI = EllesmereUI
        local resolvers = {
            EUI.ResolveHearthSlot,
            EUI.ResolveDalaranSlot,
            EUI.ResolveHousingSlot,
        }
        for i, btn in ipairs(_hearthBtns) do
            local aType, id, iconTex = resolvers[i]()
            btn._hsType = aType
            btn._hsID = id
            btn.icon:SetTexture(iconTex)
            btn.icon:SetTexCoord(aType == "housing" and 0 or 6/64,
                                 aType == "housing" and 1 or 58/64,
                                 aType == "housing" and 0 or 6/64,
                                 aType == "housing" and 1 or 58/64)
            if aType == "housing" then
                btn:SetAttribute("type", nil)
                btn:SetAttribute("macrotext", nil)
            elseif aType == "spell" then
                btn:SetAttribute("type", "macro")
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                local name = info and info.name or ""
                btn:SetAttribute("macrotext", "/cast " .. name)
            else
                btn:SetAttribute("type", "macro")
                if id == 6948 then
                    btn:SetAttribute("macrotext", "/use item:" .. id)
                else
                    local toyName
                    if C_ToyBox and C_ToyBox.GetToyInfo then
                        local _, tn = C_ToyBox.GetToyInfo(id)
                        toyName = tn
                    end
                    btn:SetAttribute("macrotext", toyName and ("/use " .. toyName) or ("/use item:" .. id))
                end
            end
        end
        RefreshHearthCooldowns()
    end

    flyout:SetScript("OnShow", function(self)
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        RefreshMinimapPortalButtons()
        ResolveHearthButtons()
    end)
    flyout:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        for _, btn in ipairs(_portalFlyoutBtns) do
            if btn._castHL then btn._castHL:Hide() end
        end
        for _, btn in ipairs(_hearthBtns) do
            if btn._castHL then btn._castHL:Hide() end
        end
    end)
    flyout:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
        if event == "SPELL_UPDATE_COOLDOWN" then
            RefreshMinimapPortalButtons()
            RefreshHearthCooldowns()
        elseif unit == "player" then
            local casting = (event == "UNIT_SPELLCAST_START") and spellID or nil
            for _, btn in ipairs(_portalFlyoutBtns) do
                if btn._castHL then
                    btn._castHL:SetShown(casting and casting == btn.spellID)
                end
            end
            if not casting then
                for _, btn in ipairs(_hearthBtns) do
                    if btn._castHL then btn._castHL:Hide() end
                end
            end
        end
    end)

    EllesmereUI.RegisterEscapeClose(flyout)

    _portalFlyout = flyout
    return flyout
end

local function ToggleMinimapPortalFlyout(anchorBtn)
    if InCombatLockdown() then return end
    local flyout = CreateMinimapPortalFlyout()
    if flyout:IsShown() then
        flyout:Hide()
    else
        local bs = anchorBtn:GetEffectiveScale()
        local fs = flyout:GetEffectiveScale()
        local bTop  = anchorBtn:GetTop()  * bs
        local bLeft = anchorBtn:GetLeft() * bs
        flyout:ClearAllPoints()
        flyout:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fs, (bTop + 4) / fs)
        flyout:Show()
    end
end

local function SizePortalBtn(btn, showBg)
    local btnSz = GetInteractableBtnSize()
    btn:SetSize(btnSz, btnSz)
    if btn._bg then btn._bg:SetShown(showBg ~= false) end
    local inset = 4
    local avail = btnSz - inset * 2
    btn._icon:SetSize(avail, avail)
    btn._icon:ClearAllPoints()
    btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
end

local function CreatePortalBtn(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)
    btn:EnableMouse(true)

    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_PortalDalaran")
    icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
    btn._icon = icon

    SizePortalBtn(btn)

    btn:SetScript("OnEnter", function(self)
        self._icon:SetVertexColor(1, 1, 1, 1)
        if _portalFlyout and _portalFlyout:IsShown() then return end
        if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(self, "M+ Portals", { anchor = "left" }) end
    end)
    btn:SetScript("OnLeave", function(self)
        self._icon:SetVertexColor(0.85, 0.85, 0.85, 1)
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._icon:SetVertexColor(0.7, 0.7, 0.7, 1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local v = over and 1 or 0.85
        self._icon:SetVertexColor(v, v, v, 1)
    end)
    btn:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip(true) end
        ToggleMinimapPortalFlyout(self)
    end)

    icon:SetVertexColor(0.85, 0.85, 0.85, 1)

    btn._indicatorKey = "_portals"

    return btn
end

local function BuildCustomIndicators(minimap)
    if _customIndicators.tracking then return end

    -- Tracking
    _customIndicators.tracking = CreateIndicatorBtn("_tracking", minimap,
        "UI-HUD-Minimap-Tracking-Up", "UI-HUD-Minimap-Tracking-Mouseover", "UI-HUD-Minimap-Tracking-Down",
        function(self)
            local blizBtn = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
            if not blizBtn or not blizBtn.OpenMenu then return end

            -- Toggle: close if already open
            if blizBtn.menu and blizBtn.menu:IsShown() then
                blizBtn.menu:Hide()
                return
            end

            -- Position hidden Blizzard button at our custom button
            blizBtn:ClearAllPoints()
            blizBtn:SetPoint("CENTER", self, "CENTER", 0, 0)
            blizBtn:SetAlpha(0)
            blizBtn:EnableMouse(false)
            blizBtn:OpenMenu()

            -- Reposition menu so its top aligns with our button's top
            if blizBtn.menu then
                blizBtn.menu:ClearAllPoints()
                blizBtn.menu:SetPoint("TOPRIGHT", self, "TOPLEFT", -4, 0)
            end
        end)
    local trackBaseEnter = _customIndicators.tracking:GetScript("OnEnter")
    local trackBaseLeave = _customIndicators.tracking:GetScript("OnLeave")
    _customIndicators.tracking:SetScript("OnEnter", function(self)
        if trackBaseEnter then trackBaseEnter(self) end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Tracking", { anchor = "left" })
        end
    end)
    _customIndicators.tracking:SetScript("OnLeave", function(self)
        if trackBaseLeave then trackBaseLeave(self) end
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    -- Calendar (day-of-month atlas)
    local calDay = tonumber(date("%d")) or 1
    local calPrefix = "UI-HUD-Calendar-" .. calDay
    _customIndicators.calendar = CreateIndicatorBtn("_gameTime", minimap,
        calPrefix .. "-Up", calPrefix .. "-Mouseover", calPrefix .. "-Down",
        function()
            if ToggleCalendar then ToggleCalendar() end
        end)
    _customIndicators.calendar._calDay = calDay
    local calBaseEnter = _customIndicators.calendar:GetScript("OnEnter")
    local calBaseLeave = _customIndicators.calendar:GetScript("OnLeave")
    _customIndicators.calendar:SetScript("OnEnter", function(self)
        if calBaseEnter then calBaseEnter(self) end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Calendar", { anchor = "left" })
        end
    end)
    _customIndicators.calendar:SetScript("OnLeave", function(self)
        if calBaseLeave then calBaseLeave(self) end
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    -- Mail (informational, tooltip on hover, with hover atlas)
    _customIndicators.mail = CreateIndicatorBtn("_mail", minimap,
        "UI-HUD-Minimap-Mail-Up", "UI-HUD-Minimap-Mail-Mouseover", nil, nil)
    local mailBaseEnter = _customIndicators.mail:GetScript("OnEnter")
    local mailBaseLeave = _customIndicators.mail:GetScript("OnLeave")
    _customIndicators.mail:SetScript("OnEnter", function(self)
        if mailBaseEnter then mailBaseEnter(self) end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, HAVE_MAIL or "New Mail", { anchor = "left" })
        end
    end)
    _customIndicators.mail:SetScript("OnLeave", function(self)
        if mailBaseLeave then mailBaseLeave(self) end
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    -- Crafting Order (informational, tooltip on hover, with hover atlas)
    _customIndicators.crafting = CreateIndicatorBtn("_crafting", minimap,
        "UI-HUD-Minimap-CraftingOrder-Up-2x", "UI-HUD-Minimap-CraftingOrder-Over-2x", "UI-HUD-Minimap-CraftingOrder-Down-2x", nil)
    local craftBaseEnter = _customIndicators.crafting:GetScript("OnEnter")
    local craftBaseLeave = _customIndicators.crafting:GetScript("OnLeave")
    _customIndicators.crafting:SetScript("OnEnter", function(self)
        if craftBaseEnter then craftBaseEnter(self) end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            local label = "Crafting Orders"
            if C_CraftingOrders and C_CraftingOrders.GetPersonalOrdersInfo then
                local infos = C_CraftingOrders.GetPersonalOrdersInfo()
                if type(infos) == "table" then
                    local lines = {}
                    for _, info in ipairs(infos) do
                        local count = tonumber(info.numPersonalOrders) or 0
                        if count > 0 then
                            local name = tostring(info.professionName or info.profession or "Unknown")
                            lines[#lines + 1] = count .. " " .. name .. " Order" .. (count > 1 and "s" or "")
                        end
                    end
                    if #lines > 0 then
                        label = label .. "\n" .. table.concat(lines, "\n")
                    end
                end
            end
            EllesmereUI.ShowWidgetTooltip(self, label, { anchor = "left" })
        end
    end)
    _customIndicators.crafting:SetScript("OnLeave", function(self)
        if craftBaseLeave then craftBaseLeave(self) end
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    -- Great Vault button (built once, anchored later in LayoutIndicatorFrames)
    _greatVaultBtn = CreateGreatVaultBtn(minimap)

    -- M+ Portal button (built once, anchored later in LayoutIndicatorFrames)
    _portalBtn = CreatePortalBtn(minimap)
end

-- Hide the Blizzard originals so they never render or intercept clicks
local function HideBlizzardIndicators()
    local tracking = MinimapCluster and MinimapCluster.Tracking
    if tracking then tracking:SetAlpha(0); tracking:EnableMouse(false) end
    local gameTime = _G.GameTimeFrame
    if gameTime then gameTime:SetAlpha(0); gameTime:EnableMouse(false) end
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if indicator then
        if indicator.MailFrame then indicator.MailFrame:SetAlpha(0); indicator.MailFrame:EnableMouse(false) end
        if indicator.CraftingOrderFrame then indicator.CraftingOrderFrame:SetAlpha(0); indicator.CraftingOrderFrame:EnableMouse(false) end
    end
end

-- Sync visibility of custom mail/crafting indicators with Blizzard state
local function SyncIndicatorVisibility()
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if _customIndicators.mail then
        local hasMail = false
        if HasNewMail then
            local raw = HasNewMail()
            if not issecretvalue or not issecretvalue(raw) then
                hasMail = raw or false
            end
        end
        _customIndicators.mail:SetShown(hasMail)
    end
    if _customIndicators.crafting then
        local blizCraft = indicator and indicator.CraftingOrderFrame
        local hasCraft = blizCraft and blizCraft:IsShown()
        _customIndicators.crafting:SetShown(hasCraft or false)
    end
end

local function LayoutIndicatorFrames(minimap, p, circleMode)
    local flvl = minimap:GetFrameLevel() + 10

    -- Build our custom buttons once, hide Blizzard originals
    BuildCustomIndicators(minimap)
    HideBlizzardIndicators()
    SyncIndicatorVisibility()

    local ci = _customIndicators
    local sz = GetInteractableBtnSize()
    local showBg = p.btnBackgrounds ~= false
    -- Resize buttons and update icon aspect ratios
    local inset = 3
    local avail = sz - inset * 2
    local function ResizeIndicator(btn)
        if not btn then return end
        btn:SetSize(sz, sz)
        if btn._bg then btn._bg:SetShown(showBg) end
        local ratio = btn._upAtlas and INDICATOR_ATLAS_RATIO[btn._upAtlas]
        if ratio and btn._icon then
            local scale = INDICATOR_ATLAS_SCALE[btn._upAtlas] or 1
            local iconW, iconH
            if ratio >= 1 then iconW = avail * scale; iconH = (avail / ratio) * scale
            else iconH = avail * scale; iconW = (avail * ratio) * scale end
            btn._icon:ClearAllPoints()
            btn._icon:SetSize(iconW, iconH)
            local off = btn._indicatorKey and INDICATOR_ATLAS_OFFSET[btn._indicatorKey]
            btn._icon:SetPoint("CENTER", btn, "CENTER", off and off[1] or 0, off and off[2] or 0)
        end
    end
    ResizeIndicator(ci.tracking)
    -- Update calendar day if it changed (midnight rollover)
    if ci.calendar then
        local today = tonumber(date("%d")) or 1
        if ci.calendar._calDay ~= today then
            ci.calendar._calDay = today
            local prefix = "UI-HUD-Calendar-" .. today
            ci.calendar._upAtlas = prefix .. "-Up"
            ci.calendar._overAtlas = prefix .. "-Mouseover"
            ci.calendar._downAtlas = prefix .. "-Down"
            if ci.calendar._icon then ci.calendar._icon:SetAtlas(ci.calendar._upAtlas) end
        end
    end
    ResizeIndicator(ci.calendar)
    ResizeIndicator(ci.mail)
    ResizeIndicator(ci.crafting)
    if flyoutToggle then
        flyoutToggle:SetSize(sz, sz)
        if flyoutToggle._bg then flyoutToggle._bg:SetShown(showBg) end
        -- Reset to base anchor so free-move offsets don't accumulate across relayouts
        flyoutToggle:ClearAllPoints()
        flyoutToggle:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMLEFT", 0, 0)
    end

    -- Calendar visibility
    if ci.calendar then ci.calendar:SetShown(not p.hideGameTime) end

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
    if not minimap.Layout then minimap.Layout = function() end end

    if circleMode then
        -- Circle layout: horizontal row around the clock
        if ci.tracking then
            ci.tracking:ClearAllPoints()
            if clockBg and p.showClock then
                ci.tracking:SetPoint("RIGHT", clockBg, "LEFT", 0, 0)
            else
                ci.tracking:SetPoint("TOP", minimap, "TOP", -20, -3)
            end
            ci.tracking:Show()
        end

        if ci.calendar and not p.hideGameTime then
            ci.calendar:ClearAllPoints()
            if clockBg and p.showClock then
                ci.calendar:SetPoint("LEFT", clockBg, "RIGHT", 0, 0)
            else
                ci.calendar:SetPoint("TOP", minimap, "TOP", 20, -3)
            end
        end

        if ci.mail and ci.mail:IsShown() then
            ci.mail:ClearAllPoints()
            ci.mail:SetPoint("RIGHT", ci.tracking, "LEFT", 0, 0)
        end

        if ci.crafting and ci.crafting:IsShown() then
            ci.crafting:ClearAllPoints()
            local anchor = (ci.mail and ci.mail:IsShown()) and ci.mail or ci.tracking
            ci.crafting:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
        end

        if indicatorBg then indicatorBg:Hide() end

    else
        -- Square layout: vertical stack on the left side
        local y = 0

        if ci.tracking then
            ci.tracking:ClearAllPoints()
            ci.tracking:SetPoint("TOPRIGHT", minimap, "TOPLEFT", 0, y)
            ci.tracking:Show()
            y = y - sz
        end

        if ci.calendar and not p.hideGameTime then
            ci.calendar:ClearAllPoints()
            ci.calendar:SetPoint("TOPRIGHT", minimap, "TOPLEFT", 0, y)
            y = y - sz
        end

        if ci.mail and ci.mail:IsShown() then
            ci.mail:ClearAllPoints()
            ci.mail:SetPoint("TOPRIGHT", minimap, "TOPLEFT", 0, y)
            y = y - sz
        end

        if ci.crafting and ci.crafting:IsShown() then
            ci.crafting:ClearAllPoints()
            ci.crafting:SetPoint("TOPRIGHT", minimap, "TOPLEFT", 0, y)
            y = y - sz
        end

        if indicatorBg then indicatorBg:Hide() end
    end

    -- Position ungrouped buttons above the flyout toggle (or at its position if hidden)
    if flyoutToggle then
        local btnSize = GetInteractableBtnSize()
        local ungroupBtnSize = (p.customBtnSizeEnabled and p.customBtnSize) or btnSize
        local flyoutVisible = flyoutToggle:IsShown()
        local anchor = flyoutVisible and flyoutToggle or nil
        local mp = EBS.db and EBS.db.profile.minimap
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
        local freeMove = p.freeMoveBtns
        -- Calculate base Y for free-move independent anchoring
        local fmBaseY = 0
        if freeMove and flyoutVisible then
            fmBaseY = ungroupBtnSize  -- start above flyout toggle
        end
        for idx, entry in ipairs(ungrouped) do
            local btn = entry.btn
            -- Restore from flyout if needed
            if flyoutSavedParents[btn] then
                if GetFFD(btn).flyoutRing then GetFFD(btn).flyoutRing:Hide() end
                if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
                if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
                flyoutSavedParents[btn] = nil
            end
            btn:SetParent(minimap)
            btn:SetFrameLevel(minimap:GetFrameLevel() + 11)
            btn:ClearAllPoints()
            if showBg then
                -- Strip BEFORE resize so the snapshot captures the real
                -- native size, not our modified ungroupBtnSize.
                StripButtonDecorations(btn)
                btn:SetSize(ungroupBtnSize, ungroupBtnSize)
            end
            if freeMove then
                local yOff = fmBaseY + (idx - 1) * ungroupBtnSize
                btn:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMLEFT", 0, yOff)
            elseif anchor then
                btn:SetPoint("BOTTOM", anchor, "TOP", 0, 0)
            else
                btn:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMLEFT", 0, 0)
            end
            btn:SetMovable(false)
            btn:RegisterForDrag()
            btn:SetScript("OnDragStart", nil)
            btn:SetScript("OnDragStop", nil)
            if showBg then
                local icon = btn.icon or btn.Icon
                if not icon then
                    for _, region in ipairs({ btn:GetRegions() }) do
                        if region:IsObjectType("Texture") and region:IsShown()
                           and region:GetAlpha() > 0 and not IsJunkTexture(region)
                           and region ~= GetFFD(btn).ungroupBg then
                            icon = region
                            break
                        end
                    end
                end
                if icon then
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
                    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
                    pcall(icon.SetTexCoord, icon, 0.05, 0.95, 0.05, 0.95)
                end
                -- Black square background
                if not GetFFD(btn).ungroupBg then
                    local ubg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
                    ubg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
                    ubg:SetBackdropColor(0, 0, 0, 0.8)
                    ubg:SetAllPoints(btn)
                    GetFFD(btn).ungroupBg = ubg
                end
                -- Re-assert strata/level every layout; the flyout child-loop
                -- bumps all children to DIALOG which would render the bg
                -- above the icon after ungrouping.
                local ubg = GetFFD(btn).ungroupBg
                ubg:SetFrameStrata(btn:GetFrameStrata())
                ubg:SetFrameLevel(btn:GetFrameLevel() - 1)
                ubg:Show()
                if btn._ungroupRing then btn._ungroupRing:Hide() end
            else
                -- No backgrounds: restore native appearance, hide our overlays.
                -- Do NOT override button size — native ring textures have fixed
                -- anchors that only look correct at the button's original size.
                RestoreButtonDecorations(btn)
                if GetFFD(btn).ungroupBg then GetFFD(btn).ungroupBg:Hide() end
                if btn._ungroupRing then btn._ungroupRing:Hide() end
            end
            _suppressVisTrack = true
            btn:SetAlpha(1)
            btn:Show()
            _suppressVisTrack = false
            anchor = btn
        end

        -- Great Vault button: always sits at the top of the ungrouped stack.
        if _greatVaultBtn then
            if p.hideGreatVault then
                _greatVaultBtn:Hide()
            else
                SizeGreatVaultBtn(_greatVaultBtn, showBg)
                _greatVaultBtn:SetParent(minimap)
                _greatVaultBtn:SetFrameLevel(minimap:GetFrameLevel() + 11)
                _greatVaultBtn:ClearAllPoints()
                if freeMove then
                    local idx = #ungrouped + (flyoutVisible and 1 or 0)
                    local yOff = idx * ungroupBtnSize
                    _greatVaultBtn:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMLEFT", 0, yOff)
                elseif anchor then
                    _greatVaultBtn:SetPoint("BOTTOM", anchor, "TOP", 0, 0)
                else
                    _greatVaultBtn:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMLEFT", 0, 0)
                end
                _greatVaultBtn:Show()
                anchor = _greatVaultBtn
            end
        end

        -- M+ Portal button: sits above the Great Vault button.
        if _portalBtn then
            if p.hidePortals then
                _portalBtn:Hide()
            else
                SizePortalBtn(_portalBtn, showBg)
                _portalBtn:SetParent(minimap)
                _portalBtn:SetFrameLevel(minimap:GetFrameLevel() + 11)
                _portalBtn:ClearAllPoints()
                if freeMove then
                    local idx = #ungrouped + (flyoutVisible and 1 or 0)
                        + ((_greatVaultBtn and not p.hideGreatVault) and 1 or 0)
                    local yOff = idx * ungroupBtnSize
                    _portalBtn:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMLEFT", 0, yOff)
                elseif anchor then
                    _portalBtn:SetPoint("BOTTOM", anchor, "TOP", 0, 0)
                else
                    _portalBtn:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMLEFT", 0, 0)
                end
                _portalBtn:Show()
                anchor = _portalBtn
            end
        end
    end

    -- Free Move: hook shift+drag on all indicator buttons and apply saved offsets
    local freeMove = p.freeMoveBtns
    local fmTargets = {}
    if ci.tracking then fmTargets[#fmTargets + 1] = ci.tracking end
    if ci.calendar and not p.hideGameTime then fmTargets[#fmTargets + 1] = ci.calendar end
    if ci.mail then fmTargets[#fmTargets + 1] = ci.mail end
    if ci.crafting then fmTargets[#fmTargets + 1] = ci.crafting end
    if flyoutToggle then fmTargets[#fmTargets + 1] = flyoutToggle end
    if _greatVaultBtn and not p.hideGreatVault then fmTargets[#fmTargets + 1] = _greatVaultBtn end
    if _portalBtn and not p.hidePortals then fmTargets[#fmTargets + 1] = _portalBtn end
    -- Include ungrouped addon buttons
    for _, btn in ipairs(cachedAddonButtons) do
        if _addonVisible[btn] ~= false and IsUngrouped(btn) then
            fmTargets[#fmTargets + 1] = btn
        end
    end
    for _, frame in ipairs(fmTargets) do
        EnableFreeMove(frame)
        if freeMove then
            ApplyBtnOffset(frame)
        end
    end
end

local function RestoreIndicatorFrames()
    -- Hide our custom indicator buttons
    for _, btn in pairs(_customIndicators) do
        if btn and btn.Hide then btn:Hide() end
    end
    -- Restore Blizzard originals
    local tracking = MinimapCluster and MinimapCluster.Tracking
    if tracking then tracking:SetAlpha(1); tracking:EnableMouse(true) end
    local gameTime = _G.GameTimeFrame
    if gameTime then gameTime:SetAlpha(1); gameTime:EnableMouse(true) end
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if indicator then
        if indicator.MailFrame then indicator.MailFrame:SetAlpha(1); indicator.MailFrame:EnableMouse(true) end
        if indicator.CraftingOrderFrame then indicator.CraftingOrderFrame:SetAlpha(1); indicator.CraftingOrderFrame:EnableMouse(true) end
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
    p.enabled = true

    local minimap = Minimap
    if not minimap then return end

    if not p.enabled then
        -- If we never touched the minimap this session, do absolutely nothing.
        -- This ensures zero interference with other minimap addons.
        if not GetFFD(minimap).active then return end
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
    -- Guard reparent: Blizzard reparents the minimap during housing transitions
    -- and other events. Hook SetParent to force it back to UIParent.
    if not GetFFD(minimap).parentGuard then
        GetFFD(minimap).parentGuard = true
        hooksecurefunc(minimap, "SetParent", function()
            if minimap:GetParent() ~= UIParent then
                if not InCombatLockdown() then
                    minimap:SetParent(UIParent)
                end
            end
        end)
        -- Lock strata/level so Blizzard can't change them during transitions
        if minimap.SetFixedFrameStrata then minimap:SetFixedFrameStrata(true) end
        if minimap.SetFixedFrameLevel then minimap:SetFixedFrameLevel(true) end
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
        GetFFD(compartment).origParent = GetFFD(compartment).origParent or compartment:GetParent()
        compartment:SetParent(EBS._hiddenFrame)
    end

    local isCircle = (p.shape == "circle" or p.shape == "textured_circle")

    -- Hide background (no black bg behind minimap)
    if GetFFD(minimap).bg then GetFFD(minimap).bg:SetAlpha(0) end

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
        if not PP.GetBorders(minimap) then
            PP.CreateBorder(minimap, r, g, b, 1, bs, "OVERLAY", 7)
        else
            PP.SetBorderColor(minimap, r, g, b, 1)
        end
        PP.SetBorderSize(minimap, bs)
        if GetFFD(minimap).circBorder then GetFFD(minimap).circBorder:Hide() end
        if GetFFD(minimap).texCircBorder then GetFFD(minimap).texCircBorder:Hide() end
    elseif p.shape == "circle" then
        -- Circle: solid colored disc behind the minimap, slightly larger = border ring
        if PP.GetBorders(minimap) then PP.SetBorderSize(minimap, 0); PP.SetBorderColor(minimap, 0, 0, 0, 0) end
        if not GetFFD(minimap).circBorder then
            local disc = CreateFrame("Frame", nil, minimap)
            disc:SetFrameLevel(minimap:GetFrameLevel() - 1)
            local tex = disc:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(disc)
            tex:SetTexture("Interface\\Common\\CommonMaskCircle")
            disc._tex = tex
            GetFFD(minimap).circBorder = disc
        end
        local bs = p.borderSize or 1
        local circBorder = GetFFD(minimap).circBorder
        circBorder:ClearAllPoints()
        circBorder:SetPoint("TOPLEFT", minimap, "TOPLEFT", -bs, bs)
        circBorder:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", bs, -bs)
        circBorder._tex:SetVertexColor(r, g, b, 1)
        circBorder:Show()
        if GetFFD(minimap).texCircBorder then GetFFD(minimap).texCircBorder:Hide() end
    elseif p.shape == "textured_circle" then
        -- Textured Circle: void ring border, hide the solid circle border
        if PP.GetBorders(minimap) then PP.SetBorderSize(minimap, 0); PP.SetBorderColor(minimap, 0, 0, 0, 0) end
        if GetFFD(minimap).circBorder then GetFFD(minimap).circBorder:Hide() end
        if not GetFFD(minimap).texCircBorder then
            local ring = minimap:CreateTexture(nil, "OVERLAY", nil, 7)
            ring:SetAtlas("wowlabs_minimapvoid-ring-single")
            GetFFD(minimap).texCircBorder = ring
        end
        local inset = 2
        local texCircBorder = GetFFD(minimap).texCircBorder
        texCircBorder:ClearAllPoints()
        texCircBorder:SetPoint("TOPLEFT", minimap, "TOPLEFT", -inset, inset)
        texCircBorder:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", inset, -inset)
        texCircBorder:SetVertexColor(r, g, b, 1)
        texCircBorder:Show()
    end

    -- Live-update border when accent color changes (only when using accent)
    if p.useClassColor then
        if not GetFFD(minimap).accentBorderCB then
            GetFFD(minimap).accentBorderCB = function(ar, ag, ab)
                if PP.GetBorders(minimap) then
                    PP.SetBorderColor(minimap, ar, ag, ab, 1)
                end
                local cb = GetFFD(minimap).circBorder
                if cb and cb:IsShown() then
                    cb._tex:SetVertexColor(ar, ag, ab, 1)
                end
                local tcb = GetFFD(minimap).texCircBorder
                if tcb and tcb:IsShown() then
                    tcb:SetVertexColor(ar, ag, ab, 1)
                end
            end
        end
        EllesmereUI.RegAccent({ type = "callback", fn = GetFFD(minimap).accentBorderCB })
    end

    -- Size
    minimap:SetScale(1.0)
    local mapSize = p.mapSize or 140
    minimap:SetSize(mapSize, mapSize)
    -- Shape mask
    local maskID = isCircle and 186178 or 130937
    minimap:SetMaskTexture(maskID)
    -- Custom housing overlay: our own texture behind the minimap that shows
    -- the housing indoor map when Blizzard hides the real minimap content.
    -- Fully owned by us, no Blizzard frame manipulation.
    if not GetFFD(minimap).housingTex then
        local frame = CreateFrame("Frame", nil, minimap)
        frame:SetAllPoints(minimap)
        frame:SetFrameLevel(minimap:GetFrameLevel() + 1)
        local tex = frame:CreateTexture(nil, "ARTWORK")
        if isCircle then
            local inset = -mapSize * 0.10
            tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        else
            tex:SetAllPoints(frame)
        end
        if isCircle then
            local mask = frame:CreateMaskTexture()
            mask:SetAllPoints(frame)
            mask:SetTexture(maskID)
            tex:AddMaskTexture(mask)
            frame._mask = mask
        end
        frame._isCircle = isCircle
        frame._tex = tex
        frame:Hide()
        GetFFD(minimap).housingFrame = frame
        GetFFD(minimap).housingTex = tex
        -- Watch for MinimapBackdrop atlas changes to detect housing
        local backdrop = _G.MinimapBackdrop
        if backdrop then
            local function CheckHousing()
                local housingAtlas
                for ri = 1, backdrop:GetNumRegions() do
                    local rgn = select(ri, backdrop:GetRegions())
                    if rgn and rgn.GetAtlas then
                        local atlas = rgn:GetAtlas()
                        if atlas and atlas:find("housing") then
                            housingAtlas = atlas
                            break
                        end
                    end
                end
                if housingAtlas then
                    if frame._isCircle then
                        tex:SetAtlas(housingAtlas)
                    else
                        tex:SetTexture("Interface\\AddOns\\EllesmereUIMinimap\\Media\\housing-minimap.png")
                    end
                    frame:Show()
                else
                    frame:Hide()
                end
            end
            -- Check on zone transitions
            if not GetFFD(minimap).housingZoneHook then
                GetFFD(minimap).housingZoneHook = true
                local zf = CreateFrame("Frame")
                zf:RegisterEvent("PLAYER_ENTERING_WORLD")
                zf:RegisterEvent("ZONE_CHANGED_NEW_AREA")
                zf:RegisterEvent("ZONE_CHANGED_INDOORS")
                zf:SetScript("OnEvent", function()
                    C_Timer.After(0.5, CheckHousing)
                end)
            end
        end
    else
        -- Update existing housing frame on reapply
        local frame = GetFFD(minimap).housingFrame
        if frame then
            frame:SetFrameLevel(minimap:GetFrameLevel() + 1)
            if frame._mask then
                frame._mask:SetTexture(maskID)
            elseif not isCircle and frame._mask then
                -- Switched to square, remove mask
            end
        end
    end
    -- Clamp to screen so the border never extends off-screen
    minimap:SetClampedToScreen(true)
    local bInset = isCircle and (p.borderSize or 1) or 0
    minimap:SetClampRectInsets(-bInset, bInset, bInset, -bInset)
    -- Force the minimap engine to re-render at the new size.
    -- Nudge zoom to a different value then immediately restore (same frame).
    local curZoom = minimap:GetZoom()
    minimap:SetZoom(curZoom > 0 and 0 or 1)
    minimap:SetZoom(curZoom)

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
        if not GetFFD(zoomIn).hooked then
            hooksecurefunc(zoomIn, "SetPoint", function(self)
                if GetFFD(self).inHook then return end
                GetFFD(self).inHook = true
                self:ClearAllPoints()
                self:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 20)
                GetFFD(self).inHook = false
            end)
            GetFFD(zoomIn).hooked = true
        end
    end
    if zoomOut then
        zoomOut:SetParent(minimap)
        zoomOut:SetFrameLevel(minimap:GetFrameLevel() + 10)
        zoomOut:ClearAllPoints()
        zoomOut:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 2)
        zoomOut:EnableMouse(true)
        zoomOut:Show()
        if not GetFFD(zoomOut).hooked then
            hooksecurefunc(zoomOut, "SetPoint", function(self)
                if GetFFD(self).inHook then return end
                GetFFD(self).inHook = true
                self:ClearAllPoints()
                self:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 2)
                GetFFD(self).inHook = false
            end)
            GetFFD(zoomOut).hooked = true
        end
    end

    -- Save zoom level when zoom buttons are clicked
    if zoomIn and not GetFFD(zoomIn).zoomSaveHooked then
        zoomIn:HookScript("OnClick", function() SaveZoomLevel() end)
        GetFFD(zoomIn).zoomSaveHooked = true
    end
    if zoomOut and not GetFFD(zoomOut).zoomSaveHooked then
        zoomOut:HookScript("OnClick", function() SaveZoomLevel() end)
        GetFFD(zoomOut).zoomSaveHooked = true
    end

    -- Mark zoom buttons so GatherMinimapButtons skips them
    if zoomIn then flyoutOwnedFrames[zoomIn] = true end
    if zoomOut then flyoutOwnedFrames[zoomOut] = true end

    -- Flyout toggle button (bottom-left corner) -- create before hiding children
    CreateFlyoutToggle()

    -- Hide ALL minimap child frames from the map surface
    HideAllMinimapButtons()

    -- Show/hide flyout toggle based on whether any grouped buttons exist
    local groupedButtons = CollectFlyoutButtons()
    if #groupedButtons > 0 then
        flyoutToggle:Show()
    else
        flyoutToggle:Hide()
    end

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
                -- New buttons may have appeared; force flyout rebuild on
                -- next open so they get picked up by the grid.
                InvalidateFlyout()
                -- If the flyout is already open, rebuild immediately so
                -- newly-discovered buttons appear without closing/reopening.
                if flyoutPanel and flyoutPanel:IsShown() then
                    BuildFlyoutContents()
                end
            end)
        end)
    end
    addonButtonPoll:Show()

    -- Force the flyout to rebuild on next open so it picks up any
    -- changes to the button list (ungroup, new addon, profile swap, etc.)
    -- and re-shows buttons that HideAllMinimapButtons just hid.
    InvalidateFlyout()
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

    -- Hook Blizzard mail/crafting Show/Hide to sync our custom indicator visibility
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    local mailFrame = indicator and indicator.MailFrame
    local craftingFrame = indicator and indicator.CraftingOrderFrame
    if mailFrame and not GetFFD(mailFrame).visHooked then
        GetFFD(mailFrame).visHooked = true
        local function onMailChange()
            local mp = EBS.db and EBS.db.profile.minimap
            if not mp or not mp.enabled then return end
            SyncIndicatorVisibility()
            LayoutIndicatorFrames(minimap, mp, (mp.shape or "square") ~= "square")
        end
        hooksecurefunc(mailFrame, "Show", onMailChange)
        hooksecurefunc(mailFrame, "Hide", onMailChange)
    end
    if craftingFrame and not GetFFD(craftingFrame).visHooked then
        GetFFD(craftingFrame).visHooked = true
        local function onCraftChange()
            local mp = EBS.db and EBS.db.profile.minimap
            if not mp or not mp.enabled then return end
            SyncIndicatorVisibility()
            LayoutIndicatorFrames(minimap, mp, (mp.shape or "square") ~= "square")
        end
        hooksecurefunc(craftingFrame, "Show", onCraftChange)
        hooksecurefunc(craftingFrame, "Hide", onCraftChange)
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
    if not GetFFD(minimap).coordsHooked then
        minimap:HookScript("OnEnter", function(self)
            if not GetFFD(self).active then return end
            if coordFrame then coordFrame:Show() end
            coordTicker:Show()
            UpdateCoords()
        end)
        minimap:HookScript("OnLeave", function(self)
            if not GetFFD(self).active then return end
            if coordFrame and not self:IsMouseOver() then coordFrame:Hide() end
            coordTicker:Hide()
        end)
        GetFFD(minimap).coordsHooked = true
    end

    -- Mousewheel zoom
    if p.scrollZoom then
        minimap:EnableMouseWheel(true)
        if not GetFFD(minimap).zoomHooked then
            GetFFD(minimap).zoomHooked = true
            minimap:HookScript("OnMouseWheel", function(self, delta)
                local mp = EBS.db and EBS.db.profile.minimap
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
    if not GetFFD(minimap).active then
        local saved = p.savedZoom or 0
        if saved >= 0 and saved <= minimap:GetZoomLevels() then
            minimap:SetZoom(saved)
        end
    end

    -- Position: only set on first activation; after that, unlock mode owns positioning.
    if not GetFFD(minimap).active then
        minimap:ClearAllPoints()
        if p.position then
            local px, py = p.position.x, p.position.y
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and px and py then
                local es = minimap:GetEffectiveScale()
                local isCenterAnchor = (p.position.point == "CENTER")
                    and (p.position.relPoint == "CENTER" or p.position.relPoint == nil)
                if isCenterAnchor and PPa.SnapCenterForDim then
                    px = PPa.SnapCenterForDim(px, minimap:GetWidth() or 0, es)
                    py = PPa.SnapCenterForDim(py, minimap:GetHeight() or 0, es)
                elseif PPa.SnapForES then
                    px = PPa.SnapForES(px, es)
                    py = PPa.SnapForES(py, es)
                end
            end
            minimap:SetPoint(p.position.point, UIParent, p.position.relPoint, px, py)
        else
            minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -10)
        end
    end

    -- Mark module as active so persistent hooks know they can fire
    GetFFD(minimap).active = true
end


-------------------------------------------------------------------------------
--  Visibility (registered with the shared EllesmereUI visibility dispatcher)
-------------------------------------------------------------------------------
local function UpdateMinimapVisibility()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if not p or not p.enabled then return end
    local vis = EllesmereUI.EvalVisibility(p)
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

-------------------------------------------------------------------------------
--  Apply All
-------------------------------------------------------------------------------
ApplyAll = function()
    ApplyMinimap()
    if EllesmereUI.RequestVisibilityUpdate then
        C_Timer.After(0, EllesmereUI.RequestVisibilityUpdate)
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function EBS:OnInitialize()
    EBS.db = EllesmereUI.Lite.NewDB("EllesmereUIMinimapDB", defaults)

    -- Full rebuild: wipes cached button state so the next ApplyMinimap
    -- re-snapshots native button sizes/textures from scratch (as if /reload).
    -- Called when toggling btnBackgrounds or ungrouping a button.
    local function FullRebuildMinimap()
        wipe(flyoutSavedRegions)
        ApplyMinimap()
    end

    -- Global bridge for options <-> main communication
    _G._EMM_DB           = EBS.db
    _G._EMM_ApplyMinimap = ApplyMinimap
    _G._EMM_FullRebuildMinimap = FullRebuildMinimap

    -- Register visibility updater + mouseover target
    if EllesmereUI.RegisterVisibilityUpdater then
        EllesmereUI.RegisterVisibilityUpdater(UpdateMinimapVisibility)
    end
    if EllesmereUI.RegisterMouseoverTarget and Minimap then
        EllesmereUI.RegisterMouseoverTarget(Minimap, function()
            local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
            return p and p.enabled and p.visibility == "mouseover"
        end)
    end
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
    end)

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
        EllesmereUI:RegisterUnlockElements({
            MK({
                key   = "EBS_Minimap",
                label = "Minimap",
                group = "Minimap",
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
        })
    end
end

-------------------------------------------------------------------------------
--  FarmHud Compatibility
--  When FarmHud is active, keep the minimap centered in its frame and
--  hide EllesmereUI border/background elements so they don't overlap.
--  Credit: Discord user DnL (original concept), PR #293 by jonathanfernandezfm.
-------------------------------------------------------------------------------
do
    local _fhLock = false

    local fhFix = CreateFrame("Frame")
    fhFix:RegisterEvent("PLAYER_ENTERING_WORLD")
    fhFix:SetScript("OnEvent", function(self)
        if not FarmHud then return end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

        -- Keep the minimap centered in the FarmHud frame whenever
        -- FarmHud or another addon repositions / reparents it.
        hooksecurefunc(Minimap, "SetPoint", function(mm)
            if FarmHud:IsShown() and not _fhLock then
                _fhLock = true
                mm:ClearAllPoints()
                mm:SetPoint("CENTER", FarmHud, "CENTER", 0, 0)
                _fhLock = false
            end
        end)

        hooksecurefunc(Minimap, "SetParent", function(mm, parent)
            if FarmHud:IsShown() and parent ~= FarmHud and not _fhLock then
                _fhLock = true
                mm:SetParent(FarmHud)
                _fhLock = false
            end
        end)

        -- Hide / restore EllesmereUI minimap borders
        local function ToggleMinimapBorders(show)
            local alpha = show and 1 or 0

            -- Circle border
            if GetFFD(Minimap).circBorder then GetFFD(Minimap).circBorder:SetAlpha(alpha) end
            -- Textured circle border
            if GetFFD(Minimap).texCircBorder then GetFFD(Minimap).texCircBorder:SetAlpha(alpha) end

            -- Square pixel-perfect border
            if EllesmereUI.PP and EllesmereUI.PP.GetBorders(Minimap) then
                if show then
                    local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
                    if p then
                        local r, g, b, a = GetBorderColor(p)
                        EllesmereUI.PP.SetBorderColor(Minimap, r, g, b, a)
                    end
                else
                    EllesmereUI.PP.SetBorderColor(Minimap, 0, 0, 0, 0)
                end
            end
        end

        FarmHud:HookScript("OnShow", function() ToggleMinimapBorders(false) end)
        FarmHud:HookScript("OnHide", function() ToggleMinimapBorders(true) end)
    end)
end
