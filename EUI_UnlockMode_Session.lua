if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnlockMode_Session.lua
--  Unlock Mode session: top banner HUD, save / revert, spec overrides,
--  open / close with their animations, the one-time how-to-use tip.
--  Loaded after EUI_UnlockMode.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
EUI_NS.unlockParts = EUI_NS.unlockParts or {}
EUI_NS.unlockParts.Session = function(UM)
local ns, EAB, min, max = EUI_NS, UM.EAB, UM.min, UM.max
local sin, FONT_PATH, LOCK_INNER, LOCK_OUTER = UM.sin, UM.FONT_PATH, UM.LOCK_INNER, UM.LOCK_OUTER
local LOCK_TOP, MOVER_ALPHA, GEAR_ROTATION, ALL_BAR_ORDER = UM.LOCK_TOP, UM.MOVER_ALPHA, UM.GEAR_ROTATION, UM.ALL_BAR_ORDER
local registeredElements, registeredOrder, RebuildRegisteredOrder, movers = UM.registeredElements, UM.registeredOrder, UM.RebuildRegisteredOrder, UM.movers
local lockAnimFrame, pendingPositions, snapshotPositions, snapshotAnchors = UM.lockAnimFrame, UM.pendingPositions, UM.snapshotPositions, UM.snapshotAnchors
local snapshotSizes, snapshotWidthMatch, snapshotHeightMatch, snapshotGrowDirs = UM.snapshotSizes, UM.snapshotWidthMatch, UM.snapshotHeightMatch, UM.snapshotGrowDirs
local GridHudAlpha, GridLabelText, CycleGridMode, _blizzOwnedOverlays = UM.GridHudAlpha, UM.GridLabelText, UM.CycleGridMode, UM._blizzOwnedOverlays
local GetAnchorDB, MatchH, ValidateStoredLinks, FadeOverlayForSelectElement = UM.GetAnchorDB, UM.MatchH, UM.ValidateStoredLinks, UM.FadeOverlayForSelectElement
local CancelPickMode, ReapplyAllAnchors, ConvertToCenterPos, ClearBarPosition = UM.CancelPickMode, UM.ReapplyAllAnchors, UM.ConvertToCenterPos, UM.ClearBarPosition
local InstallAnchorGuard, GetAccent, CreateGrid, HideAllGuidesAndHighlight = UM.InstallAnchorGuard, UM.GetAccent, UM.CreateGrid, UM.HideAllGuidesAndHighlight
local SelectMover, DeselectMover, ApplyDarkOverlays, SetupArrowKeyFrame = UM.SelectMover, UM.DeselectMover, UM.ApplyDarkOverlays, UM.SetupArrowKeyFrame
local SortMoverFrameLevels, ShowBlizzOwnedOverlays, HideBlizzOwnedOverlays, CreateMover = UM.SortMoverFrameLevels, UM.ShowBlizzOwnedOverlays, UM.HideBlizzOwnedOverlays, UM.CreateMover

-------------------------------------------------------------------------------
--  Top Banner Bar: single pre-rendered banner image (1144x120), displayed
--  pixel-perfect at native resolution, flush with top of screen. Grid + magnet
--  toggle icons overlaid on top. Slides down during the SHACKLE animation phase.
-------------------------------------------------------------------------------
local GRID_ICON       = "Interface\\AddOns\\EllesmereUI\\media\\icons\\grid.png"
local MAGNET_ICON     = "Interface\\AddOns\\EllesmereUI\\media\\icons\\magnet.png"
local FLASHLIGHT_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\flashlight.png"
local HOVER_ICON      = "Interface\\AddOns\\EllesmereUI\\media\\icons\\hover.png"
local DARK_OVERLAY_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\dark-overlay.png"
local COORD_ICON      = "Interface\\AddOns\\EllesmereUI\\media\\icons\\coordinates.png"
local BANNER_TEX      = "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-banner-2.png"

local HUD_ON_ALPHA  = 0.60
local HUD_OFF_ALPHA = 0.30
local HUD_ICON_SZ   = 20

-- Banner native pixel dimensions
local BANNER_PX_W = 1144
local BANNER_PX_H = 120

UM.hudFrame = nil

-- Stable visible-height anchor for other addons that stack controls below the banner.
function EllesmereUI:GetUnlockModeTopBarAnchor()
    return UM.hudFrame and UM.hudFrame._hoverZone
end

local hoverBarEnabled = false   -- show-bar-on-hover toggle

local function CreateHUD(parent)
    if UM.hudFrame then return UM.hudFrame end

    local ar, ag, ab = GetAccent()

    -- Load saved settings
    if EllesmereUIDB then
        if EllesmereUIDB.unlockGridMode == nil then EllesmereUIDB.unlockGridMode = "dimmed" end
        if EllesmereUIDB.unlockSnapEnabled == nil then EllesmereUIDB.unlockSnapEnabled = true end
    end
    UM.gridMode = (EllesmereUIDB and EllesmereUIDB.unlockGridMode) or "dimmed"
    UM.snapEnabled = (EllesmereUIDB and EllesmereUIDB.unlockSnapEnabled ~= false) or true

    -- Pixel-perfect scale: 1 frame unit = 1 physical screen pixel
    local physW = (GetPhysicalScreenSize())
    local uiScale = GetScreenWidth() / physW
    -- At very low UI scales the top bar gets too small to read; enlarge it 15%.
    -- Bumping the base here propagates through every downstream scale use
    -- (initial scale, user banner scale, slide-in offsets read GetScale()).
    if UIParent:GetEffectiveScale() < 0.6 then uiScale = uiScale * 1.08 end

    UM.hudFrame = CreateFrame("Frame", nil, parent)
    UM.hudFrame:SetFrameStrata("TOOLTIP")
    UM.hudFrame:SetFrameLevel(900)
    UM.hudFrame:SetSize(BANNER_PX_W, BANNER_PX_H)
    UM.hudFrame:SetScale(uiScale)
    UM.hudFrame:EnableMouse(false)  -- background only, clicks pass through
    -- Start off-screen above
    UM.hudFrame:SetPoint("TOP", UIParent, "TOP", 0, (BANNER_PX_H + 10) * uiScale)

    -- Banner image at native resolution
    local bannerTex = UM.hudFrame:CreateTexture(nil, "ARTWORK")
    bannerTex:SetTexture(BANNER_TEX)
    bannerTex:SetSize(BANNER_PX_W, BANNER_PX_H)
    bannerTex:SetPoint("TOPLEFT", UM.hudFrame, "TOPLEFT", 0, 0)
    if bannerTex.SetSnapToPixelGrid then bannerTex:SetSnapToPixelGrid(false); bannerTex:SetTexelSnappingBias(0) end
    UM.hudFrame._bannerTex = bannerTex

    -- Icons at native 28x28 resolution (banner frame is already pixel-perfect scaled)
    -- Vertically centered within the 58px visible banner area, shifted up 1px
    local iconSz = 28
    local BANNER_VIS_H = 58
    local iconCenterY = -(BANNER_VIS_H / 2) + 1  -- -28px from top (centered + 1px up)

    -- Helper: shared hover/click behavior for icon+label wrapper buttons
    local function SetupToggleBtn(wrapper, iconTex, labelFS, getState, setState)
        wrapper:SetScript("OnClick", function() setState() end)
        wrapper:SetScript("OnEnter", function()
            iconTex:SetAlpha(0.9)
            labelFS:SetTextColor(1, 1, 1, 0.9)
        end)
        wrapper:SetScript("OnLeave", function()
            local a = getState() and HUD_ON_ALPHA or HUD_OFF_ALPHA
            iconTex:SetAlpha(a)
            labelFS:SetTextColor(1, 1, 1, a)
        end)
    end

    ---------------------------------------------------------------
    --  Grid toggle (left of center): label LEFT of icon
    ---------------------------------------------------------------
    local gridBtn = CreateFrame("Button", nil, UM.hudFrame)
    -- Size will be set after label is created to encompass icon + gap + label
    gridBtn:SetPoint("RIGHT", UM.hudFrame, "TOP", -80 + iconSz / 2, iconCenterY)

    local gridTex = gridBtn:CreateTexture(nil, "OVERLAY")
    gridTex:SetSize(iconSz, iconSz)
    gridTex:SetPoint("RIGHT", gridBtn, "RIGHT", 0, 0)
    gridTex:SetTexture(GRID_ICON)
    gridTex:SetAlpha(GridHudAlpha())
    gridBtn._tex = gridTex

    local gridLabel = gridBtn:CreateFontString(nil, "OVERLAY")
    gridLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    gridLabel:SetJustifyH("RIGHT")
    gridLabel:SetPoint("RIGHT", gridTex, "LEFT", -5, 0)
    gridLabel:SetTextColor(1, 1, 1, GridHudAlpha())
    gridLabel:SetText(EllesmereUI.L(GridLabelText()))
    gridBtn._label = gridLabel

    -- Size wrapper to fit label + gap + icon
    local gridLabelW = gridLabel:GetStringWidth() or 80
    gridBtn:SetSize(gridLabelW + 5 + iconSz, max(iconSz, 24))

    -- Custom 3-state toggle (not using SetupToggleBtn)
    gridBtn:SetScript("OnClick", function()
        CycleGridMode()
        if EllesmereUIDB then EllesmereUIDB.unlockGridMode = UM.gridMode end
        local a = GridHudAlpha()
        gridTex:SetAlpha(a)
        gridLabel:SetTextColor(1, 1, 1, a)
        gridLabel:SetText(EllesmereUI.L(GridLabelText()))
        if UM.gridFrame then
            if UM.gridMode ~= "disabled" then
                UM.gridFrame:Rebuild()
                UM.gridFrame:Show()
            else
                UM.gridFrame:Hide()
            end
        end
    end)
    gridBtn:SetScript("OnEnter", function()
        gridTex:SetAlpha(0.9)
        gridLabel:SetTextColor(1, 1, 1, 0.9)
    end)
    gridBtn:SetScript("OnLeave", function()
        local a = GridHudAlpha()
        gridTex:SetAlpha(a)
        gridLabel:SetTextColor(1, 1, 1, a)
    end)
    UM.hudFrame._gridBtn = gridBtn

    ---------------------------------------------------------------
    --  Dark Overlays toggle (left of grid): label LEFT of icon
    ---------------------------------------------------------------
    local darkOverlayBtn = CreateFrame("Button", nil, UM.hudFrame)
    darkOverlayBtn:SetPoint("RIGHT", gridBtn, "LEFT", -20, 0)

    local darkOverlayTex = darkOverlayBtn:CreateTexture(nil, "OVERLAY")
    darkOverlayTex:SetSize(iconSz, iconSz)
    darkOverlayTex:SetPoint("RIGHT", darkOverlayBtn, "RIGHT", 0, 0)
    darkOverlayTex:SetTexture(DARK_OVERLAY_ICON)
    darkOverlayTex:SetAlpha(UM.darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    darkOverlayBtn._tex = darkOverlayTex

    local darkOverlayLabel = darkOverlayBtn:CreateFontString(nil, "OVERLAY")
    darkOverlayLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    darkOverlayLabel:SetJustifyH("RIGHT")
    darkOverlayLabel:SetPoint("RIGHT", darkOverlayTex, "LEFT", -5, 0)
    darkOverlayLabel:SetTextColor(1, 1, 1, UM.darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    darkOverlayLabel:SetText(UM.darkOverlaysEnabled and EllesmereUI.L("Dark Overlays\nEnabled") or EllesmereUI.L("Dark Overlays\nDisabled"))
    darkOverlayBtn._label = darkOverlayLabel

    local darkOverlayLabelW = darkOverlayLabel:GetStringWidth() or 80
    darkOverlayBtn:SetSize(darkOverlayLabelW + 5 + iconSz, max(iconSz, 24))

    SetupToggleBtn(darkOverlayBtn, darkOverlayTex, darkOverlayLabel,
        function() return UM.darkOverlaysEnabled end,
        function()
            UM.darkOverlaysEnabled = not UM.darkOverlaysEnabled
            darkOverlayTex:SetAlpha(UM.darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            darkOverlayLabel:SetTextColor(1, 1, 1, UM.darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            darkOverlayLabel:SetText(UM.darkOverlaysEnabled and EllesmereUI.L("Dark Overlays\nEnabled") or EllesmereUI.L("Dark Overlays\nDisabled"))
            ApplyDarkOverlays()
        end)
    UM.hudFrame._darkOverlayBtn = darkOverlayBtn

    ---------------------------------------------------------------
    --  Flashlight toggle (left of grid): label LEFT of icon
    ---------------------------------------------------------------
    local flashBtn = CreateFrame("Button", nil, UM.hudFrame)
    flashBtn:SetPoint("RIGHT", darkOverlayBtn, "LEFT", -20, 0)

    local flashTex = flashBtn:CreateTexture(nil, "OVERLAY")
    flashTex:SetSize(iconSz, iconSz)
    flashTex:SetPoint("RIGHT", flashBtn, "RIGHT", 0, 0)
    flashTex:SetTexture(FLASHLIGHT_ICON)
    flashTex:SetAlpha(UM.flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    flashBtn._tex = flashTex

    local flashLabel = flashBtn:CreateFontString(nil, "OVERLAY")
    flashLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    flashLabel:SetJustifyH("RIGHT")
    flashLabel:SetPoint("RIGHT", flashTex, "LEFT", -5, 0)
    flashLabel:SetTextColor(1, 1, 1, UM.flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    flashLabel:SetText(UM.flashlightEnabled and EllesmereUI.L("Cursor Light\nEnabled") or EllesmereUI.L("Cursor Light\nDisabled"))
    flashBtn._label = flashLabel

    local flashLabelW = flashLabel:GetStringWidth() or 80
    flashBtn:SetSize(flashLabelW + 5 + iconSz, max(iconSz, 24))

    SetupToggleBtn(flashBtn, flashTex, flashLabel,
        function() return UM.flashlightEnabled end,
        function()
            UM.flashlightEnabled = not UM.flashlightEnabled
            flashTex:SetAlpha(UM.flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            flashLabel:SetTextColor(1, 1, 1, UM.flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            flashLabel:SetText(UM.flashlightEnabled and EllesmereUI.L("Cursor Light\nEnabled") or EllesmereUI.L("Cursor Light\nDisabled"))
        end)
    UM.hudFrame._flashBtn = flashBtn

    ---------------------------------------------------------------
    --  Magnet/Snap toggle (right of center): label RIGHT of icon
    ---------------------------------------------------------------
    local magnetBtn = CreateFrame("Button", nil, UM.hudFrame)
    magnetBtn:SetPoint("LEFT", UM.hudFrame, "TOP", 76 - iconSz / 2, iconCenterY)

    local magnetTex = magnetBtn:CreateTexture(nil, "OVERLAY")
    magnetTex:SetSize(iconSz, iconSz)
    magnetTex:SetPoint("LEFT", magnetBtn, "LEFT", 0, 0)
    magnetTex:SetTexture(MAGNET_ICON)
    magnetTex:SetAlpha(UM.snapEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    magnetBtn._tex = magnetTex

    local magnetLabel = magnetBtn:CreateFontString(nil, "OVERLAY")
    magnetLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    magnetLabel:SetJustifyH("LEFT")
    magnetLabel:SetPoint("LEFT", magnetTex, "RIGHT", 5, 0)
    magnetLabel:SetTextColor(1, 1, 1, UM.snapEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    magnetLabel:SetText(UM.snapEnabled and EllesmereUI.L("Snap Elements\nEnabled") or EllesmereUI.L("Snap Elements\nDisabled"))
    magnetBtn._label = magnetLabel

    local magnetLabelW = magnetLabel:GetStringWidth() or 100
    magnetBtn:SetSize(iconSz + 5 + magnetLabelW, max(iconSz, 24))

    SetupToggleBtn(magnetBtn, magnetTex, magnetLabel,
        function() return UM.snapEnabled end,
        function()
            UM.snapEnabled = not UM.snapEnabled
            if EllesmereUIDB then EllesmereUIDB.unlockSnapEnabled = UM.snapEnabled end
            magnetTex:SetAlpha(UM.snapEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            magnetLabel:SetTextColor(1, 1, 1, UM.snapEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            magnetLabel:SetText(UM.snapEnabled and EllesmereUI.L("Snap Elements\nEnabled") or EllesmereUI.L("Snap Elements\nDisabled"))
            -- Refresh all movers' snap dropdown visual state
            for _, m in pairs(movers) do
                if m._refreshSnapDD then m._refreshSnapDD() end
            end
        end)
    UM.hudFrame._magnetBtn = magnetBtn

    ---------------------------------------------------------------
    --  Coordinates toggle (right of snap): label RIGHT of icon
    ---------------------------------------------------------------
    local coordBtn = CreateFrame("Button", nil, UM.hudFrame)
    coordBtn:SetPoint("LEFT", magnetBtn, "RIGHT", 7, 0)

    local coordTex = coordBtn:CreateTexture(nil, "OVERLAY")
    coordTex:SetSize(iconSz, iconSz)
    coordTex:SetPoint("LEFT", coordBtn, "LEFT", 0, 0)
    coordTex:SetTexture(COORD_ICON)
    coordTex:SetAlpha(UM.coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    coordBtn._tex = coordTex

    local coordLabel = coordBtn:CreateFontString(nil, "OVERLAY")
    coordLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    coordLabel:SetJustifyH("LEFT")
    coordLabel:SetPoint("LEFT", coordTex, "RIGHT", 1, 0)
    coordLabel:SetTextColor(1, 1, 1, UM.coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    coordLabel:SetText(UM.coordsEnabled and EllesmereUI.L("Coordinates\nEnabled") or EllesmereUI.L("Coordinates\nDisabled"))
    coordBtn._label = coordLabel

    local coordLabelW = coordLabel:GetStringWidth() or 110
    coordBtn:SetSize(iconSz + 5 + coordLabelW, max(iconSz, 24))

    SetupToggleBtn(coordBtn, coordTex, coordLabel,
        function() return UM.coordsEnabled end,
        function()
            UM.coordsEnabled = not UM.coordsEnabled
            coordTex:SetAlpha(UM.coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            coordLabel:SetTextColor(1, 1, 1, UM.coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            coordLabel:SetText(UM.coordsEnabled and EllesmereUI.L("Coordinates\nEnabled") or EllesmereUI.L("Coordinates\nDisabled"))
            -- Show or hide coords for all movers based on new state
            for _, m in pairs(movers) do
                if m._coordFS then
                    if UM.coordsEnabled then
                        if m.UpdateCoordText then m:UpdateCoordText() end
                    else
                        -- Only keep visible on the currently selected mover
                        if not m._selected then
                            m._coordFS:Hide()
                        end
                    end
                end
            end
        end)
    UM.hudFrame._coordBtn = coordBtn

    ---------------------------------------------------------------
    --  Hover toggle (right of coords): label RIGHT of icon
    ---------------------------------------------------------------
    local hoverBtn = CreateFrame("Button", nil, UM.hudFrame)
    hoverBtn:SetPoint("LEFT", coordBtn, "RIGHT", 2, 0)

    local hoverTex = hoverBtn:CreateTexture(nil, "OVERLAY")
    hoverTex:SetSize(iconSz, iconSz)
    hoverTex:SetPoint("LEFT", hoverBtn, "LEFT", 0, 0)
    hoverTex:SetTexture(HOVER_ICON)
    hoverTex:SetAlpha(hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    hoverBtn._tex = hoverTex

    local hoverLabel = hoverBtn:CreateFontString(nil, "OVERLAY")
    hoverLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    hoverLabel:SetJustifyH("LEFT")
    hoverLabel:SetPoint("LEFT", hoverTex, "RIGHT", 5, 0)
    hoverLabel:SetTextColor(1, 1, 1, hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    hoverLabel:SetText(hoverBarEnabled and EllesmereUI.L("Hover Top Bar\nEnabled") or EllesmereUI.L("Hover Top Bar\nDisabled"))
    hoverBtn._label = hoverLabel

    local hoverLabelW = hoverLabel:GetStringWidth() or 110
    hoverBtn:SetSize(iconSz + 5 + hoverLabelW, max(iconSz, 24))

    SetupToggleBtn(hoverBtn, hoverTex, hoverLabel,
        function() return hoverBarEnabled end,
        function()
            hoverBarEnabled = not hoverBarEnabled
            hoverTex:SetAlpha(hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            hoverLabel:SetTextColor(1, 1, 1, hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            hoverLabel:SetText(hoverBarEnabled and EllesmereUI.L("Hover Top Bar\nEnabled") or EllesmereUI.L("Hover Top Bar\nDisabled"))
        end)
    UM.hudFrame._hoverBtn = hoverBtn

    ---------------------------------------------------------------
    --  Exit (left) and Save & Exit (right) buttons
    --  Vertically centered in the 58px visible banner area.
    --  Positioned ~50px from left/right edges of the banner, but pulled in
    --  further when localized toggle labels run wide enough to reach them
    --  (German especially runs longer than English and used to overlap them).
    ---------------------------------------------------------------
    local BTN_H = 26
    local BTN_FONT = 10
    local btnCenterY = iconCenterY  -- same vertical center as icons
    local CHAIN_GAP = 15  -- minimum clearance from the icon-toggle chain

    -- Outer edges of the left (grid/darkOverlay/flash) and right
    -- (magnet/coord/hover) toggle chains, center-relative -- re-derives the
    -- same offsets used to anchor them above, so keep these in sync with
    -- those SetPoint calls if the chain spacing ever changes.
    local flashLeftEdge = (-80 + iconSz / 2) - gridBtn:GetWidth() - 20 - darkOverlayBtn:GetWidth() - 20 - flashBtn:GetWidth()
    local hoverRightEdge = (76 - iconSz / 2) + magnetBtn:GetWidth() + 7 + coordBtn:GetWidth() + 2 + hoverBtn:GetWidth()

    -- Exit button (left side, 85px from left edge by default)
    local exitBtn = CreateFrame("Button", nil, UM.hudFrame)
    local EXIT_BTN_W = 60
    exitBtn:SetSize(EXIT_BTN_W, BTN_H)
    local exitLeftEdge = min(-BANNER_PX_W / 2 + 85, flashLeftEdge - CHAIN_GAP - EXIT_BTN_W)
    exitBtn:SetPoint("LEFT", UM.hudFrame, "TOPLEFT", exitLeftEdge + BANNER_PX_W / 2, btnCenterY)
    EllesmereUI.MakeStyledButton(exitBtn, "Exit", BTN_FONT,
        EllesmereUI.RB_COLOURS, function() ns.RequestClose(false) end)
    UM.hudFrame._exitBtn = exitBtn

    -- Save & Exit button (right side, 50px from right edge, green "Done" style)
    do
        local btn = CreateFrame("Button", nil, UM.hudFrame)
        local SAVE_BTN_W = 90
        btn:SetSize(SAVE_BTN_W, BTN_H)
        local saveRightEdge = max(BANNER_PX_W / 2 - 85, hoverRightEdge + CHAIN_GAP + SAVE_BTN_W)
        btn:SetPoint("RIGHT", UM.hudFrame, "TOPRIGHT", saveRightEdge - BANNER_PX_W / 2, btnCenterY)
        btn:SetFrameLevel(UM.hudFrame:GetFrameLevel() + 2)

        local eg = EllesmereUI.ELLESMERE_GREEN or { r = 12/255, g = 210/255, b = 157/255 }
        EllesmereUI.MakeBorder(btn, eg.r, eg.g, eg.b, 0.7)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.92)

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT_PATH, BTN_FONT, "OUTLINE, SLUG")
        lbl:SetPoint("CENTER")
        lbl:SetText(EllesmereUI.L("Save & Exit"))
        lbl:SetTextColor(eg.r, eg.g, eg.b, 0.7)

        local FADE_DUR = 0.1
        local progress, target = 0, 0
        local lerp = EllesmereUI.lerp
        local function Apply(t)
            local c = EllesmereUI.ELLESMERE_GREEN or eg
            lbl:SetTextColor(c.r, c.g, c.b, lerp(0.7, 1, t))
        end
        local function OnUpdate(self, elapsed)
            local dir = (target == 1) and 1 or -1
            progress = progress + dir * (elapsed / FADE_DUR)
            if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                progress = target; self:SetScript("OnUpdate", nil)
            end
            Apply(progress)
        end
        btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
        btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
        btn:SetScript("OnClick", function() ns.RequestClose(true) end)
        UM.hudFrame._saveBtn = btn
    end

    ---------------------------------------------------------------
    --  Banner Scale +/- Buttons: far left (-) and far right (+) of the banner.
    --  Scale range 100%-150% in 10% steps. Saved to EllesmereUIDB.unlockBannerScale.
    ---------------------------------------------------------------
    do
        local SCALE_MIN = 1.0
        local SCALE_MAX = 1.5
        local SCALE_STEP = 0.1
        local DISABLED_R, DISABLED_G, DISABLED_B = 0.35, 0.35, 0.35
        local NORMAL_R, NORMAL_G, NORMAL_B = 1, 1, 1
        local HOVER_R, HOVER_G, HOVER_B = 1, 1, 1
        local NORMAL_A = 0.50
        local HOVER_A  = 0.90
        local FONT_SZ  = 26

        -- Load saved banner scale
        local bannerUserScale = 1.0
        if EllesmereUIDB and EllesmereUIDB.unlockBannerScale then
            bannerUserScale = EllesmereUIDB.unlockBannerScale
            if bannerUserScale < SCALE_MIN then bannerUserScale = SCALE_MIN end
            if bannerUserScale > SCALE_MAX then bannerUserScale = SCALE_MAX end
        end

        -- Apply initial scale (uiScale * userScale)
        UM.hudFrame:SetScale(uiScale * bannerUserScale)

        local minusBtn, plusBtn  -- forward refs for cross-refresh

        local function RefreshScaleBtns()
            local atMin = bannerUserScale <= SCALE_MIN + 0.001
            local atMax = bannerUserScale >= SCALE_MAX - 0.001
            if atMin then
                minusBtn._shadow:SetTextColor(DISABLED_R, DISABLED_G, DISABLED_B, NORMAL_A * 0.6)
                minusBtn._label:SetTextColor(DISABLED_R, DISABLED_G, DISABLED_B, NORMAL_A)
                minusBtn:EnableMouse(true)  -- still catch hover for tooltip
                minusBtn._isDisabled = true
            else
                minusBtn._shadow:SetTextColor(0, 0, 0, NORMAL_A)
                minusBtn._label:SetTextColor(NORMAL_R, NORMAL_G, NORMAL_B, NORMAL_A)
                minusBtn._isDisabled = false
            end
            if atMax then
                plusBtn._shadow:SetTextColor(DISABLED_R, DISABLED_G, DISABLED_B, NORMAL_A * 0.6)
                plusBtn._label:SetTextColor(DISABLED_R, DISABLED_G, DISABLED_B, NORMAL_A)
                plusBtn:EnableMouse(true)
                plusBtn._isDisabled = true
            else
                plusBtn._shadow:SetTextColor(0, 0, 0, NORMAL_A)
                plusBtn._label:SetTextColor(NORMAL_R, NORMAL_G, NORMAL_B, NORMAL_A)
                plusBtn._isDisabled = false
            end
        end

        local function ApplyBannerScale(newScale)
            newScale = max(SCALE_MIN, min(SCALE_MAX, newScale))
            bannerUserScale = newScale
            if EllesmereUIDB then EllesmereUIDB.unlockBannerScale = newScale end
            UM.hudFrame:SetScale(uiScale * newScale)
            -- Keep flush with top of screen
            UM.hudFrame:ClearAllPoints()
            UM.hudFrame:SetPoint("TOP", UIParent, "TOP", 0, 0)
            -- Resize hover zone to match new scale
            if UM.hudFrame._hoverZone then
                UM.hudFrame._hoverZone:SetHeight(60 * uiScale * newScale)
            end
            RefreshScaleBtns()
        end

        -- Helper: create a text button with drop shadow
        local function MakeScaleBtn(text, anchorPoint, anchorTo, anchorRel, xOff, yOff)
            local btn = CreateFrame("Button", nil, UM.hudFrame)
            btn:SetSize(30, 30)
            btn:SetPoint(anchorPoint, anchorTo, anchorRel, xOff, yOff)
            btn:SetFrameLevel(UM.hudFrame:GetFrameLevel() + 3)

            -- Drop shadow (offset 1px down-right)
            local shadow = btn:CreateFontString(nil, "ARTWORK")
            shadow:SetFont(FONT_PATH, FONT_SZ, "")
            shadow:SetPoint("CENTER", btn, "CENTER", 1, -1)
            shadow:SetText(EllesmereUI.L(text))
            shadow:SetTextColor(0, 0, 0, NORMAL_A)
            btn._shadow = shadow

            -- Main text
            local label = btn:CreateFontString(nil, "OVERLAY")
            label:SetFont(FONT_PATH, FONT_SZ, "")
            label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            label:SetText(EllesmereUI.L(text))
            label:SetTextColor(NORMAL_R, NORMAL_G, NORMAL_B, NORMAL_A)
            btn._label = label

            btn._isDisabled = false

            btn:SetScript("OnEnter", function(self)
                if self._isDisabled then return end
                self._shadow:SetTextColor(0, 0, 0, HOVER_A)
                self._label:SetTextColor(HOVER_R, HOVER_G, HOVER_B, HOVER_A)
            end)
            btn:SetScript("OnLeave", function(self)
                if self._isDisabled then return end
                self._shadow:SetTextColor(0, 0, 0, NORMAL_A)
                self._label:SetTextColor(NORMAL_R, NORMAL_G, NORMAL_B, NORMAL_A)
            end)

            return btn
        end

        -- Minus button (10px left of the Exit button, outer side)
        minusBtn = MakeScaleBtn("\226\128\147", "RIGHT", exitBtn, "LEFT", -10, 0)
        minusBtn:SetScript("OnClick", function(self)
            if self._isDisabled then return end
            ApplyBannerScale(bannerUserScale - SCALE_STEP)
        end)

        -- Plus button (10px right of the Save & Exit button, outer side)
        plusBtn = MakeScaleBtn("+", "LEFT", UM.hudFrame._saveBtn, "RIGHT", 10, 0)
        plusBtn:SetScript("OnClick", function(self)
            if self._isDisabled then return end
            ApplyBannerScale(bannerUserScale + SCALE_STEP)
        end)

        UM.hudFrame._minusBtn = minusBtn
        UM.hudFrame._plusBtn = plusBtn
        UM.hudFrame._applyBannerScale = ApplyBannerScale

        RefreshScaleBtns()
    end

    ---------------------------------------------------------------
    --  Hover-bar logic: when hoverBarEnabled, the banner + all children fade out
    --  unless the cursor is in a 1144x60 zone at the top of the screen. Fade = 0.5s.
    --  Holding Shift fades the bar out in ANY mode so elements beneath it can
    --  be seen and clicked; releasing Shift brings it straight back.
    ---------------------------------------------------------------
    local HOVER_ZONE_H = 60
    local HOVER_FADE = 0.5
    local SHIFT_FADE = 0.15
    local hoverAlpha = 1  -- current fade alpha (1 = fully visible)

    -- Invisible hover detection zone (parented to UIParent, not hudFrame,
    -- so it's always accessible even when hudFrame alpha is 0)
    local hoverZone = CreateFrame("Frame", nil, parent)
    hoverZone:SetFrameStrata("FULLSCREEN_DIALOG")
    hoverZone:SetFrameLevel(parent:GetFrameLevel() + 56)
    hoverZone:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    hoverZone:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    hoverZone:SetHeight(HOVER_ZONE_H * (UM.hudFrame:GetScale() or uiScale))
    hoverZone:EnableMouse(false)  -- doesn't block clicks
    hoverZone:Hide()
    UM.hudFrame._hoverZone = hoverZone

    -- Every mouse-interactive banner child. Mouse is cut while Shift-hidden so
    -- the invisible buttons can't eat clicks meant for elements under the bar.
    local hudMouseKids = {
        UM.hudFrame._gridBtn, UM.hudFrame._darkOverlayBtn, UM.hudFrame._flashBtn,
        UM.hudFrame._magnetBtn, UM.hudFrame._coordBtn, UM.hudFrame._hoverBtn,
        UM.hudFrame._exitBtn, UM.hudFrame._saveBtn, UM.hudFrame._minusBtn, UM.hudFrame._plusBtn,
    }
    local shiftMouseCut = false

    UM.hudFrame:SetScript("OnUpdate", function(self, dt)
        -- Hold Shift: temporarily hide the top bar (works in both modes)
        local shiftHeld = IsShiftKeyDown()
        if shiftHeld ~= shiftMouseCut then
            shiftMouseCut = shiftHeld
            for i = 1, #hudMouseKids do
                local kid = hudMouseKids[i]
                if shiftHeld then
                    -- EnableMouse(false) does not fire OnLeave on a frame the
                    -- cursor is already over; reset hover visuals explicitly
                    -- so no button sticks in its highlighted state.
                    local leave = kid:GetScript("OnLeave")
                    if leave then leave(kid) end
                end
                kid:EnableMouse(not shiftHeld)
            end
        end
        if shiftHeld then
            -- Push-through, no change guard: unlock entry force-sets frame
            -- alpha to 1 while hoverAlpha can still be 0 from a close that
            -- happened with Shift held; a guarded write would strand the
            -- banner visible with its buttons mouse-dead.
            hoverAlpha = max(0, hoverAlpha - dt / SHIFT_FADE)
            self:SetAlpha(hoverAlpha)
            if not hoverBarEnabled then hoverZone:Hide() end
            return
        end

        if not hoverBarEnabled then
            -- Not in hover mode -- ensure full alpha
            if hoverAlpha < 1 then
                hoverAlpha = 1
                self:SetAlpha(1)
            end
            hoverZone:Hide()
            return
        end

        hoverZone:Show()

        -- Check if cursor is within the hover zone (top of screen)
        local scale = UIParent:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        cy = cy / scale
        local screenH = UIParent:GetHeight()
        local zoneBot = screenH - (HOVER_ZONE_H * (UM.hudFrame:GetScale() or uiScale))
        local inZone = (cy >= zoneBot)

        if inZone then
            hoverAlpha = min(1, hoverAlpha + dt / HOVER_FADE)
        else
            hoverAlpha = max(0, hoverAlpha - dt / HOVER_FADE)
        end
        self:SetAlpha(hoverAlpha)
    end)

    UM.hudFrame:Hide()
    return UM.hudFrame
end

-------------------------------------------------------------------------------
--  Save / Revert / Close helpers
-------------------------------------------------------------------------------

-- Snapshot current bar positions when entering unlock mode
local function SnapshotPositions()
    wipe(snapshotPositions)
    -- Action bars: capture from barPositions DB
    local db = UM.GetPositionDB()
    if db then
        for barKey, pos in pairs(db) do
            snapshotPositions[barKey] = { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
        end
    end
    -- Action bars: for any bar that has NO saved position, capture its live position
    for _, barKey in ipairs(ALL_BAR_ORDER) do
        if not snapshotPositions[barKey] then
            local bar = UM.GetBarFrame(barKey)
            if bar then
                local nPts = bar:GetNumPoints()
                if nPts and nPts > 0 then
                    local point, _, relPoint, x, y = bar:GetPoint(1)
                    if point then
                        snapshotPositions[barKey] = { point = point, relPoint = relPoint, x = x, y = y }
                    end
                end
            end
        end
    end
    -- Registered elements: snapshot via loadPosition or live frame position
    RebuildRegisteredOrder()
    for _, key in ipairs(registeredOrder) do
        if not snapshotPositions[key] then
            local elem = registeredElements[key]
            if elem then
                local pos = elem.loadPosition and elem.loadPosition(key)
                if pos then
                    snapshotPositions[key] = { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
                else
                    local fr = elem.getFrame and elem.getFrame(key)
                    if fr then
                        local nPts = fr:GetNumPoints()
                        if nPts and nPts > 0 then
                            local point, _, relPoint, x, y = fr:GetPoint(1)
                            if point then
                                -- relPoint may be a frame object here (not a string) if anchored to
                                -- a parent frame rather than UIParent; mark this snapshot so RevertPositions skips writing it to SavedVariables.
                                snapshotPositions[key] = { point = point, relPoint = relPoint, x = x, y = y, _fromLiveFrame = true }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Snapshot anchor data so we can revert on discard (includes the
    -- growth-edge pin fields; losing them on cancel would force a lazy
    -- recapture from whatever position the session left the bar at)
    wipe(snapshotAnchors)
    local anchorDB = GetAnchorDB()
    if anchorDB then
        for childKey, info in pairs(anchorDB) do
            snapshotAnchors[childKey] = {
                target = info.target, side = info.side,
                offsetX = info.offsetX, offsetY = info.offsetY,
                refX = info.refX, refY = info.refY,
                edgeOffX = info.edgeOffX, edgeOffY = info.edgeOffY,
                refFor = info.refFor,
                -- COPY, not a reference: _NudgeSelectedFallbackGhost mutates
                -- fb.offsetX/offsetY in place, so a shared table would drag the
                -- snapshot along with the edit and make the revert a no-op. The
                -- cross-axis edge is nudged in place too, so it copies as well.
                fallback = info.fallback and CopyTable(info.fallback) or nil,
                edge = info.edge and CopyTable(info.edge) or nil,
            }
        end
    end

    -- Snapshot element sizes so we can revert width/height changes on discard
    wipe(snapshotSizes)
    for _, key in ipairs(registeredOrder) do
        local elem = registeredElements[key]
        if elem and elem.getSize then
            local w, h = elem.getSize(key)
            if w and h then
                snapshotSizes[key] = { w = w, h = h }
            end
        end
    end

    -- Snapshot width/height match DBs so we can revert on discard
    wipe(snapshotWidthMatch)
    wipe(snapshotHeightMatch)
    local wmDB = MatchH.GetWidthMatchDB()
    if wmDB then
        for k, v in pairs(wmDB) do snapshotWidthMatch[k] = v end
    end
    local hmDB = MatchH.GetHeightMatchDB()
    if hmDB then
        for k, v in pairs(hmDB) do snapshotHeightMatch[k] = v end
    end
    -- ...and each match's Extra Width / Height, reverted with its link.
    local sx = MatchH.snapExtra
    wipe(sx.w)
    wipe(sx.h)
    local wxDB = EllesmereUIDB and EllesmereUIDB.unlockWidthMatchExtra
    if wxDB then
        for k, v in pairs(wxDB) do sx.w[k] = v end
    end
    local hxDB = EllesmereUIDB and EllesmereUIDB.unlockHeightMatchExtra
    if hxDB then
        for k, v in pairs(hxDB) do sx.h[k] = v end
    end

    -- Snapshot growth directions so we can revert on discard
    wipe(snapshotGrowDirs)
    local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
    local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
    if cdmBars and cdmBars.bars then
        for _, bar in ipairs(cdmBars.bars) do
            -- bar.key guard: ghost bars (keyless skeletons from stale
            -- override writes) have nothing to snapshot.
            if bar.key then
                snapshotGrowDirs["CDM_" .. bar.key] = bar.growDirection or false
            end
        end
    end
    local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
    local abBars = eab and eab.db and eab.db.profile and eab.db.profile.bars
    if abBars then
        local abGrowKeys = { MainBar=1, Bar2=1, Bar3=1, Bar4=1, Bar5=1, Bar6=1, Bar7=1, Bar8=1 }
        for bk, cfg in pairs(abBars) do
            if abGrowKeys[bk] then
                snapshotGrowDirs[bk] = cfg.growDirection or false
            end
        end
    end

    -- Raw pre-session position entries for CDM/AB bars: verbatim saved edges
    -- including the tgt* follow baselines. The snapshotPositions entries above are
    -- center-converted and LOSSY for edge-preserving grow bars (a restored
    -- CENTER-format saved edge can't pin, so the bar stays wherever it currently
    -- sits). Spec-override baseline capture prefers these raw copies. Namespace
    -- table: this body is inside the deferred-init closure, at the 200-local cap.
    local rawSnap = {}
    EllesmereUI._unlockSnapRawPos = rawSnap
    local cdmPos = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBarPositions
    if cdmPos and cdmBars and cdmBars.bars then
        for _, bar in ipairs(cdmBars.bars) do
            local e = cdmPos[bar.key]
            if e then rawSnap["CDM_" .. bar.key] = CopyTable(e) end
        end
    end
    local abPos = UM.GetPositionDB()
    if abPos and EllesmereUI._abBarKeys then
        for bk in pairs(EllesmereUI._abBarKeys) do
            local e = abPos[bk]
            if e then rawSnap[bk] = CopyTable(e) end
        end
    end
end

-------------------------------------------------------------------------------
--  Unlock spec-overrides: session visuals + Save & Exit routing. Gold border =
--  this element carries an unlock override for the active edit context (the
--  special group's entry, or the current spec's owning group in a normal
--  session). Red lock = element can't be edited in the special session (owned by a spec-sharing group, or a blocked subsystem).
-------------------------------------------------------------------------------
do
    local specOvBanner
    local function UpdateSpecOvBanner()
        local g = EllesmereUI._specialUnlockGroup
        if not g or not UM.unlockFrame then
            if specOvBanner then specOvBanner:Hide() end
            return
        end
        if not specOvBanner then
            specOvBanner = CreateFrame("Frame", nil, UM.unlockFrame)
            specOvBanner:SetFrameLevel(UM.unlockFrame:GetFrameLevel() + 60)
            specOvBanner:SetHeight(28)
            specOvBanner:SetPoint("TOP", UM.unlockFrame, "TOP", 0, -64)
            local bg = specOvBanner:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.16, 0.12, 0.04, 0.92)
            EllesmereUI.MakeBorder(specOvBanner, 199/255, 166/255, 90/255, 0.7)
            local fs = specOvBanner:CreateFontString(nil, "OVERLAY")
            fs:SetFont(FONT_PATH, 12, "OUTLINE, SLUG")
            fs:SetPoint("CENTER")
            fs:SetTextColor(1, 0.88, 0.55, 1)
            specOvBanner._text = fs
        end
        specOvBanner._text:SetText(string.format(
            EllesmereUI.L("Customizing Unlock Mode: %s (changes apply only to this group's specs)"),
            g.name or "?"))
        specOvBanner:SetWidth((specOvBanner._text:GetStringWidth() or 200) + 28)
        specOvBanner:Show()
    end

    -- Layer model: a custom unlock mode is a whole-layout fork, so there are no
    -- per-element gold marks or conflict locks anymore -- the gold frame variant
    -- and this banner carry the state; this refresh keeps the banner current and hides stale per-element markers on pooled movers.
    EllesmereUI._unlockRefreshSpecOvMarks = function()
        UpdateSpecOvBanner()
        for _, m in pairs(movers) do
            if m._specOvBrd then m._specOvBrd:Hide() end
            if m._specOvLock then m._specOvLock:Hide() end
        end
    end
end

-- Commit pending positions to SavedVariables
local function CommitPositions()
    -- Suppress per-save rebuilds (e.g. CDM's BuildAllCDMBars) so that
    -- all positions are written first, then a single rebuild runs at the end.
    EllesmereUI._propagatingSave = true
    for barKey, pos in pairs(pendingPositions) do
        if pos == "RESET" then
            ClearBarPosition(barKey)
        else
            local elem = registeredElements[barKey]
            local pt, rpt, px, py = pos.point, pos.relPoint, pos.x, pos.y
            -- Anchor-cascade marker: ApplyAnchorPosition repositioned this bar during
            -- the session (e.g. its anchor target was dragged) but the entry carries no
            -- coords. The open-time snapshot below is STALE for it: saving that would
            -- pair a pre-move growth edge with the post-move target baselines savePos
            -- captures, and the bar snaps to the stale edge on save. Resolve from the
            -- bar's LIVE bounds instead -- ConvertToCenterPos prefers them and returns
            -- the exact CENTER/CENTER convention SaveBarPosition expects. Bars a cascade
            -- reapplied without actually moving resolve to the same snapshot position.
            if elem and not pt and pos._anchored then
                local liveBar = UM.GetBarFrame(barKey)
                if liveBar and liveBar:GetLeft() and liveBar:GetRight()
                   and liveBar:GetTop() and liveBar:GetBottom() then
                    pt, rpt, px, py = ConvertToCenterPos(barKey, "TOPLEFT", "TOPLEFT", 0, 0)
                end
            end
            -- If position wasn't dragged, fill from snapshot
            if elem and not pt then
                local snap = snapshotPositions[barKey]
                if snap then
                    pt, rpt, px, py = snap.point, snap.relPoint or snap.point, snap.x, snap.y
                else
                    -- Fallback: read from loadPosition
                    local lp = elem.loadPosition and elem.loadPosition(barKey)
                    if lp then
                        pt, rpt, px, py = lp.point, lp.relPoint or lp.point, lp.x, lp.y
                    end
                end
            end
            UM.SaveBarPosition(barKey, pt, rpt, px, py)
            -- Install anchor guard for action bar positions
            if not elem then
                local bar = UM.GetBarFrame(barKey)
                if bar then InstallAnchorGuard(bar, barKey) end
            end
        end
    end
    EllesmereUI._propagatingSave = false

    -- Force edge-preservation across the save rebuild + reapply below. These run
    -- while isUnlocked is still true (DoClose clears it only AFTER CommitPositions
    -- returns), so without this flag ApplyAnchorPosition skips its absolute
    -- saved-edge branch and places anchored custom-growth CDM bars from the anchor
    -- offset + live width instead -- if the rebuild changed a bar's width, the
    -- growth edge lands off the freshly-saved edge and the bar visibly snaps back
    -- until /reload. Setting the flag makes both passes read cdmBarPositions
    -- exactly like the login/reload apply. Mirrors OpenUnlockMode's entry reapply; pcall-wrapped and reset in all cases so it can never leak.
    EllesmereUI._reapplyForceEdgePreserve = true

    -- Single rebuild now that all positions are committed.
    -- CDM savePos normally calls BuildAllCDMBars per save, but we
    -- suppressed that above to avoid partial-state rebuilds.
    for barKey in pairs(pendingPositions) do
        if type(barKey) == "string" and barKey:sub(1, 4) == "CDM_" then
            local elem = registeredElements[barKey]
            if elem and elem.applyPosition then
                pcall(elem.applyPosition, barKey)
            end
            break  -- one rebuild is enough, it rebuilds all bars
        end
    end

    -- Reapply anchor positions for all anchored bars so they move from the stale CENTER
    -- coords (saved by CommitPositions) to their correct anchor-relative position
    -- immediately. Without this, anchored bars sit at stale coords until a deferred
    -- ScheduleAnchorBatch corrects them, causing a visible jump on the next resize.
    if EllesmereUI.ReapplyAllUnlockAnchorsForced then
        pcall(EllesmereUI.ReapplyAllUnlockAnchorsForced)
    end

    EllesmereUI._reapplyForceEdgePreserve = false

    -- Persist unlock layout into the active profile so it survives reloads
    -- without requiring a manual profile switch.
    if EllesmereUIDB and EllesmereUI.GetProfilesDB then
        local pdb = EllesmereUI.GetProfilesDB()
        local activeName = pdb.activeProfile or "Default"
        local profileData = pdb.profiles and pdb.profiles[activeName]
        if profileData then
            local snap = {
                anchors       = CopyTable(EllesmereUIDB.unlockAnchors     or {}),
                widthMatch    = CopyTable(EllesmereUIDB.unlockWidthMatch  or {}),
                heightMatch   = CopyTable(EllesmereUIDB.unlockHeightMatch or {}),
                widthMatchExtra  = CopyTable(EllesmereUIDB.unlockWidthMatchExtra  or {}),
                heightMatchExtra = CopyTable(EllesmereUIDB.unlockHeightMatchExtra or {}),
                phantomBounds = CopyTable(EllesmereUIDB.phantomBounds     or {}),
            }
            -- While a spec-override unlock LAYER is live, the profile
            -- snapshot must carry the shared BASELINE links, not the live
            -- (group-valued) globals; the stored baseline layout provides
            -- them. When the baseline itself is live, live is the source.
            if EllesmereUI.SpecOverrides_UnlockBaselineLinks then
                local ba, bw, bh = EllesmereUI.SpecOverrides_UnlockBaselineLinks()
                if ba then
                    snap.anchors     = CopyTable(ba)
                    snap.widthMatch  = CopyTable(bw)
                    snap.heightMatch = CopyTable(bh)
                    -- The baseline's match extras ride with its links (4th and
                    -- 5th returns); a baseline without extras carries none.
                    local _, _, _, bwx, bhx = EllesmereUI.SpecOverrides_UnlockBaselineLinks()
                    snap.widthMatchExtra  = CopyTable(bwx or {})
                    snap.heightMatchExtra = CopyTable(bhx or {})
                end
            end
            profileData.unlockLayout = snap
        end
    end
    -- The active spec's tracked buff bar links and extras into their spec bucket,
    -- so a profile restore before the next bar build cannot swap older ones in.
    if EllesmereUI._TBBBankUnlockLinks then EllesmereUI._TBBBankUnlockLinks() end

    -- Bank CAPTURED settings the session edited (cog size inputs) into
    -- values.default -- a normal unlock session edits the shared baseline, exactly
    -- like the panel's Default Editing Mode. Without this the next value apply
    -- reverts the user's unlock-mode resize (the sticky harvest deliberately never adopts foreign live diffs).
    if EllesmereUI.SpecOverrides_UnlockValueSnapCommit then
        pcall(EllesmereUI.SpecOverrides_UnlockValueSnapCommit)
    end

    -- Bank the freshly-saved live layout into its owning spec-override layer (the
    -- active group layer, else the stored baseline). Wholesale harvest -- no
    -- per-aspect routing exists. true = user commit: banks even inside the post-import suppression window (and closes it).
    if EllesmereUI.SpecOverrides_HarvestUnlockLayout then
        local okH, errH = pcall(EllesmereUI.SpecOverrides_HarvestUnlockLayout, true)
        if not okH then
            print("|cffff6060[EllesmereUI]|r Unlock layer harvest failed: "
                .. tostring(errH))
        end
    end
end

-- Revert bars to their snapshot positions (discard all pending changes)
local function RevertPositions()
    if InCombatLockdown() then return end

    -- Cancel: unlock-session value edits are discarded too (the module store may
    -- keep the cog-edited size until the next value apply restores the recorded default -- correct for a discard).
    if EllesmereUI.SpecOverrides_UnlockValueSnapDiscard then
        EllesmereUI.SpecOverrides_UnlockValueSnapDiscard()
    end

    -- 1) Restore all DB state from snapshots (suppress rebuilds)
    EllesmereUI._propagatingSave = true

    local db = UM.GetPositionDB()
    if db then
        for barKey, _ in pairs(pendingPositions) do
            if not registeredElements[barKey] then
                -- Prefer the verbatim pre-session entry (saved edge PLUS the tgt*
                -- follow baselines): the coordinate-only snapshot would strip the baselines from grow bars on every cancel, costing a bless cycle before target-follow works again.
                local rawSnap = EllesmereUI._unlockSnapRawPos
                    and EllesmereUI._unlockSnapRawPos[barKey]
                local snap = snapshotPositions[barKey]
                if rawSnap then
                    db[barKey] = CopyTable(rawSnap)
                elseif snap then
                    db[barKey] = { point = snap.point, relPoint = snap.relPoint, x = snap.x, y = snap.y }
                else
                    db[barKey] = nil
                end
            end
        end
    end

    for barKey, _ in pairs(pendingPositions) do
        local elem = registeredElements[barKey]
        if elem and elem.savePosition then
            local snap = snapshotPositions[barKey]
            if snap and not snap._fromLiveFrame then
                elem.savePosition(barKey, snap.point, snap.relPoint or snap.point, snap.x, snap.y)
            end
        end
    end

    EllesmereUI._propagatingSave = false

    -- 2) Restore anchor data before repositioning
    local anchorDB = GetAnchorDB()
    if anchorDB then
        -- fallback rides the snapshot (copied both ways), so pre-session
        -- fallbacks survive the revert and session edits discard with it.
        wipe(anchorDB)
        for childKey, info in pairs(snapshotAnchors) do
            anchorDB[childKey] = {
                target = info.target, side = info.side,
                offsetX = info.offsetX, offsetY = info.offsetY,
                refX = info.refX, refY = info.refY,
                edgeOffX = info.edgeOffX, edgeOffY = info.edgeOffY,
                refFor = info.refFor,
                edge = info.edge and CopyTable(info.edge) or nil,
                -- Restored from the snapshot, so a fallback MOVED this session
                -- reverts like every other position. Fresh copy so the next
                -- session's nudges cannot reach back into the snapshot.
                fallback = info.fallback and CopyTable(info.fallback) or nil,
            }
        end
    end

    -- 3) Restore element sizes
    for key, snap in pairs(snapshotSizes) do
        local elem = registeredElements[key]
        if elem then
            if elem.setWidth and snap.w then
                pcall(elem.setWidth, key, snap.w)
            end
            if elem.setHeight and snap.h then
                pcall(elem.setHeight, key, snap.h)
            end
        end
    end

    -- 4) Restore width/height match DBs
    local wmDB = MatchH.GetWidthMatchDB()
    if wmDB then
        wipe(wmDB)
        for k, v in pairs(snapshotWidthMatch) do wmDB[k] = v end
    end
    local hmDB = MatchH.GetHeightMatchDB()
    if hmDB then
        wipe(hmDB)
        for k, v in pairs(snapshotHeightMatch) do hmDB[k] = v end
    end
    -- Each match's Extra Width / Height, in the same step as its link. A CDM bar
    -- reads both live (its setWidth only re-lays it out) and step 6 rebuilds only
    -- bars that moved, so a bar whose extra the restore changes is re-laid out here.
    if EllesmereUIDB then
        local sx = MatchH.snapExtra
        local relayout
        local function Note(live, snap)
            if live then
                for k, v in pairs(live) do
                    if snap[k] ~= v and k:sub(1, 4) == "CDM_" then
                        relayout = relayout or {}; relayout[k] = true
                    end
                end
            end
            for k, v in pairs(snap) do
                if not (live and live[k] == v) and k:sub(1, 4) == "CDM_" then
                    relayout = relayout or {}; relayout[k] = true
                end
            end
        end
        Note(EllesmereUIDB.unlockWidthMatchExtra, sx.w)
        Note(EllesmereUIDB.unlockHeightMatchExtra, sx.h)
        if EllesmereUIDB.unlockWidthMatchExtra then wipe(EllesmereUIDB.unlockWidthMatchExtra) end
        for k, v in pairs(sx.w) do MatchH.SetMatchExtra("w", k, v) end
        if EllesmereUIDB.unlockHeightMatchExtra then wipe(EllesmereUIDB.unlockHeightMatchExtra) end
        for k, v in pairs(sx.h) do MatchH.SetMatchExtra("h", k, v) end
        if relayout then
            for k in pairs(relayout) do
                local e = registeredElements[k]
                if e and e.setWidth then pcall(e.setWidth, k) end
            end
        end
    end

    -- 5) Restore growth directions
    for key, snapGrow in pairs(snapshotGrowDirs) do
        local val = snapGrow == false and nil or snapGrow
        if key:sub(1, 4) == "CDM_" then
            local rawKey = key:sub(5)
            local cdmA = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
            local cdmB = cdmA and cdmA.db and cdmA.db.profile and cdmA.db.profile.cdmBars
            if cdmB and cdmB.bars then
                for _, bar in ipairs(cdmB.bars) do
                    if bar.key == rawKey then bar.growDirection = val; break end
                end
            end
        else
            local eabA = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
            local abB = eabA and eabA.db and eabA.db.profile and eabA.db.profile.bars
            if abB and abB[key] then abB[key].growDirection = val end
        end
    end

    -- 6) Rebuild CDM bars so they read the restored DB and position correctly.
    -- Without this, CDM bars revert to wrong positions (CENTER vs edge mismatch).
    local didCDMRebuild = false
    for barKey in pairs(pendingPositions) do
        if not didCDMRebuild and type(barKey) == "string" and barKey:sub(1, 4) == "CDM_" then
            local elem = registeredElements[barKey]
            if elem and elem.applyPosition then
                pcall(elem.applyPosition, barKey)
            end
            didCDMRebuild = true
        end
    end

    -- 6) Reposition unanchored elements through normal path.
    -- Skip anchored elements -- step 7 handles them via ApplyAnchorPosition.
    for barKey, _ in pairs(pendingPositions) do
        local ai = anchorDB and anchorDB[barKey]
        if not (ai and ai.target) then
            local bar = UM.GetBarFrame(barKey)
            if bar then
                local snap = snapshotPositions[barKey]
                if snap and not snap._fromLiveFrame then
                    if not UM.ApplyCenterPosition(barKey, snap) then
                        pcall(function()
                            EllesmereUI.ClearFramePoints(bar)
                            EllesmereUI.SetFramePoint(bar, snap.point, UIParent, snap.relPoint, snap.x, snap.y)
                        end)
                    end
                elseif bar.UpdateGridLayout then
                    pcall(bar.UpdateGridLayout, bar)
                end
            end
        end
    end

    -- 7) Reapply anchor positions for anchored elements. Force edge preservation
    -- across the pass: this runs while isUnlocked is still true, and without the
    -- flag ApplyAnchorPosition skips its absolute saved-edge branch and places
    -- anchored custom-growth bars (StanceBar, CDM grow bars) from their center
    -- offsets + live width instead of the just-restored saved edge -- the bar
    -- visibly snaps off its reverted position. Mirrors the CommitPositions fix.
    if anchorDB then
        EllesmereUI._reapplyForceEdgePreserve = true
        for childKey, info in pairs(anchorDB) do
            if info.target and UM.GetBarFrame(childKey) and UM.GetBarFrame(info.target) then
                pcall(UM.ApplyAnchorPosition, childKey, info.target, info.side)
            end
        end
        EllesmereUI._reapplyForceEdgePreserve = false
    end
end

local pendingAfterClose        -- callback to run after DoClose completes
local cogHoveredMover = nil    -- the mover whose cog button is currently hovered

-- Internal close (actually hides everything and returns to options)
local function DoClose(closeAction)
    if not UM.isUnlocked then return end
    UM.isUnlocked = false
    EllesmereUI._unlockActive = false
    EllesmereUI._unlockModeActive = false
    EllesmereUI:_NotifyUnlockModeListeners(false, closeAction or "exit")
    if EllesmereUI._HideFallbackGhosts then EllesmereUI._HideFallbackGhosts() end
    if EllesmereUI._HideOverrideGhosts then EllesmereUI._HideOverrideGhosts() end
    -- Re-engage override anchors now that isUnlocked is false (the settle's
    -- position pass is the belt; this is deterministic and immediate).
    if EllesmereUI._ReapplyOverrideAnchors then EllesmereUI._ReapplyOverrideAnchors() end

    -- Notify action bars to restore Blizzard-owned frame anchors
    if _G._EAB_UnlockModeClose then pcall(_G._EAB_UnlockModeClose) end

    -- Recalculate action bar flyout directions after positions are finalized
    if _G._EAB_RecalcFlyouts then pcall(_G._EAB_RecalcFlyouts) end

    -- Notify beacon reminders to restore (if follow-mouse is active)
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Restore expandIfNoResource after unlock mode finishes
    if _G._ERB_RestoreExpand then pcall(_G._ERB_RestoreExpand) end
    -- Re-apply the anchor-target shifts after unlock mode finishes. Independent of
    -- expand restore (which early-returns when expand was never suppressed); runs
    -- after _unlockActive is cleared above so the providers return non-zero and
    -- PropagateAnchorChain is no longer a no-op. Each provider gates itself so
    -- None = no work.
    EllesmereUI.RestoreAnchorShifts()

    -- Restore unit frame buffs/debuffs
    local UF_FRAME_NAMES = {
        "EllesmereUIUnitFrames_Player", "EllesmereUIUnitFrames_Target",
        "EllesmereUIUnitFrames_Focus", "EllesmereUIUnitFrames_Pet",
        "EllesmereUIUnitFrames_TargetTarget", "EllesmereUIUnitFrames_FocusTarget",
    }
    for i = 1, 8 do UF_FRAME_NAMES[#UF_FRAME_NAMES + 1] = "EllesmereUIUnitFrames_Boss" .. i end
    for _, name in ipairs(UF_FRAME_NAMES) do
        local f = _G[name]
        if f then
            if f.Buffs and f.Buffs._unlockWasShown then
                f.Buffs:Show()
                f.Buffs._unlockWasShown = nil
            end
            if f.Debuffs and f.Debuffs._unlockWasShown then
                f.Debuffs:Show()
                f.Debuffs._unlockWasShown = nil
            end
        end
    end

    -- Restore objective tracker
    if UM.objTrackerWasVisible then
        local objTracker = _G.ObjectiveTrackerFrame
        if objTracker then
            objTracker:SetAlpha(1)
            local wasEnabled = objTracker._eabMouseWasEnabled
            if objTracker.EnableMouse then
                pcall(objTracker.EnableMouse, objTracker, wasEnabled and true or false)
            end
        end
        UM.objTrackerWasVisible = false
    end
    -- Restore EllesmereUI QT background
    local qtBg = _G.EllesmereUIQTBackground
    if qtBg then qtBg:SetAlpha(1) end
    -- Re-apply user visibility setting (handles "never" mode for both tracker + bg)
    if _G.EllesmereUIQuestTracker and _G.EllesmereUIQuestTracker.UpdateVisibility then
        _G.EllesmereUIQuestTracker.UpdateVisibility()
    end

    -- Re-check Dragon Riding's real visibility (it force-shows while unlocked
    -- so it can be edited off-mount; without this it stays stuck visible
    -- after exiting Unlock Mode if the player dismounted while unlocked).
    if _G._EDR_UpdateVisibility then pcall(_G._EDR_UpdateVisibility) end

    if not UM.unlockFrame then return end

    UM.unlockFrame:SetScript("OnUpdate", nil)
    if UM.logoFadeFrame then UM.logoFadeFrame:SetScript("OnUpdate", nil); UM.logoFadeFrame:Hide() end
    if UM.openAnimFrame then UM.openAnimFrame:Hide() end
    if lockAnimFrame then lockAnimFrame:Hide() end
    if UM.gridFrame then UM.gridFrame:SetScript("OnUpdate", nil); UM.gridFrame:Hide() end
    if UM.hudFrame then UM.hudFrame:Hide() end
    if UM.unlockTipFrame then UM.unlockTipFrame:SetScript("OnUpdate", nil); UM.unlockTipFrame:Hide() end
    if UM.unlockFrame._anchorLineDriver then UM.unlockFrame._anchorLineDriver:Hide() end
    if UM.unlockFrame._anchorLineFrame  then UM.unlockFrame._anchorLineFrame:Hide() end
    if UM.unlockFrame._clearAnchorLineAnim then UM.unlockFrame._clearAnchorLineAnim() end
    DeselectMover()
    -- Collapse any expanded mover so it doesn't stay stuck on re-enter
    UM.hoveredMover    = nil
    cogHoveredMover = nil
    EllesmereUI._unlockCursorSpeed = 0
    for _, m in pairs(movers) do
        m._snapTarget   = nil
        m._dragging     = false
        m._shiftAxis    = nil
        m._hoverPending = false
        -- Snap-collapse hover state so mover isn't stuck expanded on re-enter
        if m._forceCollapse then m._forceCollapse() end
        m:SetScript("OnUpdate", nil)
        m:Hide()
    end
    HideAllGuidesAndHighlight()
    HideBlizzOwnedOverlays()
    UM.unlockFrame:Hide()
    UM.unlockFrame:SetAlpha(1)

    -- Clean up arrow key nudge state
    UM.selectedMover = nil
    UM.selectElementPicker = nil
    if UM.arrowKeyFrame then UM.arrowKeyFrame:Hide() end

    -- Reset session state
    wipe(pendingPositions)
    wipe(snapshotPositions)
    wipe(snapshotAnchors)
    wipe(snapshotGrowDirs)
    UM.hasChanges = false

    -- End any special spec-override session and clear its mover marks (the
    -- banner is a child of unlockFrame, hidden with it above; the next
    -- session's mark refresh re-evaluates everything).
    EllesmereUI._specialUnlockGroup = nil
    for _, m in pairs(movers) do
        if m._specOvBrd then m._specOvBrd:Hide() end
        if m._specOvLock then m._specOvLock:Hide() end
    end

    -- Clean up pick mode / anchor dropdown state
    UM.pickMode = nil
    UM.pickModeMover = nil
    if UM.anchorDropdownFrame then UM.anchorDropdownFrame:Hide() end
    if UM.anchorDropdownCatcher then UM.anchorDropdownCatcher:Hide() end
    if UM.growDropdownFrame then UM.growDropdownFrame:Hide() end
    if UM.growDropdownCatcher then UM.growDropdownCatcher:Hide() end

    -- Restore action bar alpha from saved settings
    if EAB and EAB.RefreshMouseover and not InCombatLockdown() then
        EAB:RefreshMouseover()
    end

    -- Restore CDM bar visibility (unlock forced all bars visible)
    if _G._ECME_ApplyVisibility then _G._ECME_ApplyVisibility() end

    -- Restore panel scale and show options
    local panelRealScale
    do
        local physW = (GetPhysicalScreenSize())
        local baseScale = GetScreenWidth() / physW
        local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
        panelRealScale = baseScale * userScale
    end
    local panel = EllesmereUI and EllesmereUI._mainFrame
    if panel then panel:SetScale(panelRealScale); panel:SetAlpha(1) end
    -- If there's a pending after-close callback, skip the default panel restore
    -- (the callback will handle opening the panel to the right page)
    if not pendingAfterClose then
        if EllesmereUI then
            -- Restore the module + page active before unlock mode opened (captured
            -- by SelectPage("Unlock Mode") in EllesmereUI.lua). Do NOT show the panel
            -- yet -- SelectModule/SelectPage cause Hide->Show cycles on the page
            -- wrapper via HideAllChildren, and showing the panel first would add
            -- extra cycles that leave EditBox text blank. Set up the page while hidden, then show once at the end.
            local restoreModule = EllesmereUI._unlockReturnModule
            local restorePage   = EllesmereUI._unlockReturnPage
            EllesmereUI._unlockReturnPage = nil
            EllesmereUI._unlockReturnModule = nil
            if restoreModule then
                EllesmereUI:SelectModule(restoreModule)
                if restorePage and EllesmereUI.SelectPage then
                    local currentPage = EllesmereUI:GetActivePage()
                    if currentPage ~= restorePage then
                        EllesmereUI:SelectPage(restorePage)
                    end
                end
                -- NOW show the panel -- one clean Show, no prior cycling.
                EllesmereUI:Toggle()
            end
        end
    end

    -- Fire any pending after-close callback (e.g. from slash commands)
    if pendingAfterClose then
        EllesmereUI._unlockReturnPage = nil
        EllesmereUI._unlockReturnModule = nil
        local fn = pendingAfterClose
        pendingAfterClose = nil
        fn()
    end
end

-- Public close request: save=true commits, save=false may prompt
-- Optional afterFn runs after close completes (for slash command chaining)
function ns.RequestClose(save, afterFn)
    if afterFn then pendingAfterClose = afterFn end
    if save then
        CommitPositions()
        DoClose("save")
        return
    end
    -- No changes -> just exit
    if not UM.hasChanges then
        DoClose("exit")
        return
    end
    -- Has unsaved changes -> show confirm popup
    EllesmereUI:ShowConfirmPopup({
        title = "Unsaved Changes",
        message = "You have unsaved position changes.\nWhat would you like to do?",
        cancelText  = "Exit Without Saving",
        confirmText = "Save & Exit",
        onCancel = function()
            RevertPositions()
            DoClose("exit")
        end,
        onConfirm = function()
            CommitPositions()
            DoClose("save")
        end,
        -- Dismiss (ESC / click-off) does nothing -- user stays in unlock mode,
        -- and any pending close callback is cleared since the close was abandoned
        onDismiss = function()
            pendingAfterClose = nil
            -- Controller Back: stamp the dismiss so the same press's step skips
            if UM.unlockFrame and UM.unlockFrame._padEsc then UM.unlockFrame._padDismissAt = GetTime() end
        end,
    })
end

--- Force-closes unlock mode DISCARDING the session. Called by the profile system
--- on a spec transition: movers, snapshots, and pending edits all belong to the
--- OUTGOING spec's layout, so saving them against the incoming spec would corrupt both baseline and spec-override data.
function EllesmereUI.ForceCloseUnlockDiscard()
    if not UM.isUnlocked then return end
    print("|cffff6060[EllesmereUI]|r Spec changed: Unlock Mode closed, unsaved layout changes discarded.")
    pendingAfterClose = nil
    -- Unconditional: RevertPositions only runs below when positions changed,
    -- but the value-edit snapshot must never survive a discard-close.
    if EllesmereUI.SpecOverrides_UnlockValueSnapDiscard then
        EllesmereUI.SpecOverrides_UnlockValueSnapDiscard()
    end
    if UM.hasChanges then pcall(RevertPositions) end
    pcall(DoClose, "discard")
end

-------------------------------------------------------------------------------
--  Smooth easing function (ease-in-out cubic)
-------------------------------------------------------------------------------
local function EaseInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local f = 2 * t - 2
        return 0.5 * f * f * f + 1
    end
end

-------------------------------------------------------------------------------
--  Open / Close Unlock Mode
-------------------------------------------------------------------------------
local function CreateUnlockFrame()
    if UM.unlockFrame then return UM.unlockFrame end

    UM.unlockFrame = CreateFrame("Frame", "EllesmereUnlockMode", UIParent)
    UM.unlockFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    UM.unlockFrame:SetAllPoints(UIParent)
    UM.unlockFrame:EnableMouse(false)  -- let clicks pass through to game world
    UM.unlockFrame:EnableKeyboard(true)

    -- Dark overlay background -- on a dedicated sub-frame so movers render ABOVE it
    local overlayFrame = CreateFrame("Frame", nil, UM.unlockFrame)
    overlayFrame:SetFrameLevel(UM.unlockFrame:GetFrameLevel() + 1)
    overlayFrame:SetAllPoints(UIParent)
    local overlay = overlayFrame:CreateTexture(nil, "BACKGROUND")
    overlay:SetAllPoints()
    overlay:SetColorTexture(0.030, 0.023, 0.018, 0.20)
    UM.unlockFrame._overlay = overlay
    UM.unlockFrame._overlayMaxAlpha = 0.20

    -- Anchor connector lines: accent-colored lines drawn center-to-center
    -- between each anchored child and its parent, rendered behind all elements.
    local anchorLinePool = {}
    local anchorPulsePool = {}
    local anchorLineFrame = CreateFrame("Frame", nil, UIParent)
    anchorLineFrame:SetFrameStrata("BACKGROUND")
    anchorLineFrame:SetFrameLevel(1)
    anchorLineFrame:SetAllPoints(UIParent)
    anchorLineFrame:EnableMouse(false)

    local function GetAnchorLine(idx)
        if anchorLinePool[idx] then return anchorLinePool[idx] end
        local line = anchorLineFrame:CreateLine(nil, "ARTWORK", nil, 1)
        line:SetThickness(3)
        line:SetSnapToPixelGrid(false)
        line:SetTexelSnappingBias(0)
        line:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\textures\\soft-line")
        anchorLinePool[idx] = line
        return line
    end

    local function GetAnchorPulse(idx)
        if anchorPulsePool[idx] then return anchorPulsePool[idx] end
        local line = anchorLineFrame:CreateLine(nil, "ARTWORK", nil, 2)
        line:SetThickness(3)
        line:SetSnapToPixelGrid(false)
        line:SetTexelSnappingBias(0)
        line:SetTexture("Interface\\AnimaChannelingDevice\\AnimaChannelingDeviceLineVerticalMask")
        anchorPulsePool[idx] = line
        return line
    end

    -- Per-line animation state keyed by "childKey:targetKey"
    local anchorLineAnim = {}
    local ANCHOR_LINE_DUR = 0.5
    local PULSE_CYCLE = 2.5
    local PULSE_SWEEP = 0.56  -- fraction of cycle spent sweeping (rest is pause)

    local function UpdateAnchorLines()
        local db = GetAnchorDB()
        local idx = 0
        local now = GetTime()
        if db and UM.isUnlocked then
            for childKey, info in pairs(db) do
                local cm = movers[childKey]
                local tm = movers[info.target]
                if cm and tm and cm:IsShown() and tm:IsShown() then
                    -- Use _hoverConfirmed so lines wait for hover intent
                    local cmActive = cm._hoverConfirmed or cm._dragging
                    local tmActive = tm._hoverConfirmed or tm._dragging
                    local pairKey = childKey .. ":" .. info.target
                    if cmActive or tmActive then
                        -- Start or continue animation
                        if not anchorLineAnim[pairKey] then
                            anchorLineAnim[pairKey] = now
                        end
                        local elapsed = now - anchorLineAnim[pairKey]
                        local t = elapsed / ANCHOR_LINE_DUR
                        if t > 1 then t = 1 end
                        -- Ease-out for smooth deceleration
                        local ease = 1 - (1 - t) * (1 - t)

                        idx = idx + 1
                        local line = GetAnchorLine(idx)
                        -- Child center (line origin)
                        local x1 = ((cm:GetLeft() or 0) + (cm:GetRight()  or 0)) * 0.5
                        local y1 = ((cm:GetBottom() or 0) + (cm:GetTop()  or 0)) * 0.5
                        -- Parent center (line destination)
                        local x2 = ((tm:GetLeft() or 0) + (tm:GetRight()  or 0)) * 0.5
                        local y2 = ((tm:GetBottom() or 0) + (tm:GetTop()  or 0)) * 0.5
                        -- Partial endpoint based on animation progress
                        local ex = x1 + (x2 - x1) * ease
                        local ey = y1 + (y2 - y1) * ease
                        line:SetStartPoint("BOTTOMLEFT", UIParent, x1, y1)
                        line:SetEndPoint("BOTTOMLEFT", UIParent, ex, ey)
                        line:SetVertexColor(1, 0.7, 0.3, 0.75 * ease)
                        line:Show()

                        -- Pulse overlay: streak that sweeps child->parent, loops every 3s
                        local pulse = GetAnchorPulse(idx)
                        if ease >= 1 then
                            local pulseAge = now - anchorLineAnim[pairKey] - 0.3
                            local cycleT = (pulseAge % PULSE_CYCLE) / PULSE_CYCLE
                            local sweepEnd = PULSE_SWEEP
                            if cycleT <= sweepEnd then
                                local st = cycleT / sweepEnd
                                -- Smooth ease-in-out motion, overshooting to 3x line length
                                local smoothT = st * st * (3 - 2 * st)
                                local headT = smoothT * 2.0
                                local tailT = math.max(0, headT - 1.0)
                                -- Clamp endpoints to the actual line
                                local clampHead = math.min(1, headT)
                                local clampTail = math.min(1, tailT)
                                -- Fade in/out
                                local fadeA = 1
                                if smoothT < 0.1 then
                                    fadeA = smoothT / 0.1
                                elseif smoothT > 0.7 then
                                    fadeA = (1 - smoothT) / 0.3
                                end
                                if fadeA < 0 then fadeA = 0 end
                                if clampHead <= clampTail then
                                    pulse:Hide()
                                else
                                    local px1 = x1 + (x2 - x1) * clampTail
                                    local py1 = y1 + (y2 - y1) * clampTail
                                    local px2 = x1 + (x2 - x1) * clampHead
                                    local py2 = y1 + (y2 - y1) * clampHead
                                    pulse:SetStartPoint("BOTTOMLEFT", UIParent, px1, py1)
                                    pulse:SetEndPoint("BOTTOMLEFT", UIParent, px2, py2)
                                    pulse:SetVertexColor(1, 0.89, 0.625, 0.5 * fadeA)
                                    pulse:Show()
                                end
                            else
                                pulse:Hide()
                            end
                        else
                            pulse:Hide()
                        end
                    else
                        -- Not active, clear animation state
                        anchorLineAnim[pairKey] = nil
                    end
                end
            end
        end
        -- Hide unused lines and clean stale anim entries
        for i = idx + 1, #anchorLinePool do
            anchorLinePool[i]:Hide()
        end
        for i = idx + 1, #anchorPulsePool do
            anchorPulsePool[i]:Hide()
        end
    end

    -- Drive line updates every frame while unlock mode is open
    local anchorLineDriver = CreateFrame("Frame")
    anchorLineDriver:SetScript("OnUpdate", UpdateAnchorLines)
    anchorLineDriver:Hide()
    UM.unlockFrame._anchorLineDriver = anchorLineDriver
    UM.unlockFrame._anchorLineFrame  = anchorLineFrame
    UM.unlockFrame._clearAnchorLineAnim = function() wipe(anchorLineAnim) end

    -- Click-to-deselect is handled by toggle behavior on movers themselves
    -- (clicking the selected mover again deselects it), so no full-screen catcher is needed -- world interaction (targeting, camera) stays unblocked.

    -- One Escape step: the innermost open layer closes, else Unlock Mode does
    -- (which asks first when there are unsaved changes). padAll: a controller
    -- Back that closes every window at once (nil from the keyboard).
    local function EscapeStep(padAll)
        -- If anchor dropdown is open, close it instead of closing unlock mode
        if UM.anchorDropdownFrame and UM.anchorDropdownFrame:IsShown() then
            UM.anchorDropdownFrame:Hide()
            if UM.anchorDropdownCatcher then UM.anchorDropdownCatcher:Hide() end
            return
        end
        -- If in width/height/anchor pick mode, cancel it instead of closing
        if UM.pickModeMover and UM.pickMode then
            CancelPickMode()
            return
        end
        -- If in select-element pick mode, cancel it instead of closing
        if UM.selectElementPicker then
            local picker = UM.selectElementPicker
            picker._snapTarget = picker._preSelectTarget
            picker._preSelectTarget = nil
            if picker._updateSnapLabel then picker._updateSnapLabel() end
            UM.selectElementPicker = nil
            FadeOverlayForSelectElement(false)
            return
        end
        -- That Back exits to the world, as Blizzard's does: a panel reopened
        -- here loses the pointer as soon as the press ends. Unsaved changes
        -- keep the way back for the prompt's Save & Exit.
        if padAll and not UM.hasChanges then
            EllesmereUI._unlockReturnModule = nil
            EllesmereUI._unlockReturnPage = nil
        end
        ns.CloseUnlockMode()
    end

    -- ESC to close (skip if confirm popup is already showing)
    UM.unlockFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            -- If the confirm popup is visible, let it handle ESC instead
            local dimmer = _G["EUIConfirmDimmer"]
            if dimmer and dimmer:IsShown() then
                self:SetPropagateKeyboardInput(true)
                return
            end
            self:SetPropagateKeyboardInput(false)
            EscapeStep()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- Controller Back (the escape proxy runs it once Unlock Mode is registered
    -- there, see OpenUnlockMode): the same step as Escape. A shown confirm
    -- popup answers Back itself, and the Back that just dismissed the
    -- unsaved-changes prompt must not raise it again in the same pass.
    UM.unlockFrame._padBack = function()
        local dimmer = _G["EUIConfirmDimmer"]
        if dimmer and dimmer:IsShown() then return end
        if UM.unlockFrame._padDismissAt == GetTime() then return end
        -- The game also closes every window by itself (the UI hidden and shown
        -- again, a loading screen, death, loss of control): not a Back press,
        -- so Unlock Mode stays open through those, as it always has. Hiding
        -- the UI marks the frame, so the close when it returns is skipped too.
        if not UM.unlockFrame:IsVisible() then
            UM.unlockFrame._padUIHidden = true
            return
        end
        if UM.unlockFrame._padUIHidden then
            UM.unlockFrame._padUIHidden = nil
            return
        end
        if EllesmereUI._zoneTransitionActive or UnitIsDeadOrGhost("player")
           or (not HasFullControl() and not UnitOnTaxi("player")) then
            return
        end
        EscapeStep(EllesmereUI.PadNative() and CanAutoSetGamePadCursorControl(false))
    end

    UM.unlockFrame:Hide()
    return UM.unlockFrame
end

-------------------------------------------------------------------------------
--  Open lock animation frame (panel shrink -> gear rotate -> shackle unlock).
--  Uses a container frame + SetScale for guaranteed uniform aspect ratio; each
--  texture is set to its NATIVE pixel dimensions so proportions stay exact.
-------------------------------------------------------------------------------
-- Native pixel dimensions of each PNG (from Photoshop)
local INNER_W, INNER_H = 253, 253
local OUTER_W, OUTER_H = 368, 353
local TOP_W,   TOP_H   = 412, 412

-- Container size = largest piece so everything fits
local CONTAINER_SZ = 412
-- The "icon size" we want the logo to appear at on screen (in UI pixels)
local ICON_SZ = 100
-- Base scale to shrink native-res textures down to icon size
local BASE_SCALE = ICON_SZ / CONTAINER_SZ

local SHACKLE_LIFT = 62  -- how far the shackle lifts (in container-space pixels)
local OUTER_Y_OFFSET = -7  -- outer ring sits 7px lower than center

local function CreateOpenAnimFrame(parent)
    if UM.openAnimFrame then return UM.openAnimFrame end

    UM.openAnimFrame = CreateFrame("Frame", nil, parent)
    UM.openAnimFrame:SetFrameLevel(50)  -- above movers (~20), below confirm popup (100)
    UM.openAnimFrame:SetAllPoints(UIParent)

    -- Container frame: sized to hold the largest texture at native res.
    -- SetScale on this frame handles ALL sizing uniformly.
    local container = CreateFrame("Frame", nil, UM.openAnimFrame)
    container:SetSize(CONTAINER_SZ, CONTAINER_SZ)
    container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    container:SetScale(BASE_SCALE)
    UM.openAnimFrame._container = container

    -- Each texture at its NATIVE pixel dimensions, centered in container
    -- Disable pixel snapping for smooth sub-pixel animation
    local outer = container:CreateTexture(nil, "ARTWORK", nil, 1)
    outer:SetTexture(LOCK_OUTER)
    outer:SetSize(OUTER_W, OUTER_H)
    outer:SetPoint("CENTER", container, "CENTER", 0, OUTER_Y_OFFSET)
    if outer.SetSnapToPixelGrid then outer:SetSnapToPixelGrid(false); outer:SetTexelSnappingBias(0) end
    UM.openAnimFrame._outer = outer

    local inner = container:CreateTexture(nil, "ARTWORK", nil, 2)
    inner:SetTexture(LOCK_INNER)
    inner:SetSize(INNER_W, INNER_H)
    inner:SetPoint("CENTER", container, "CENTER", 0, 0)
    if inner.SetSnapToPixelGrid then inner:SetSnapToPixelGrid(false); inner:SetTexelSnappingBias(0) end
    UM.openAnimFrame._inner = inner

    local top = container:CreateTexture(nil, "ARTWORK", nil, 3)
    top:SetTexture(LOCK_TOP)
    top:SetSize(TOP_W, TOP_H)
    top:SetPoint("CENTER", container, "CENTER", 0, 0)
    if top.SetSnapToPixelGrid then top:SetSnapToPixelGrid(false); top:SetTexelSnappingBias(0) end
    UM.openAnimFrame._top = top

    -- Sweep shine: tightly clipped to logo center (lives inside container)
    local sweepClip = CreateFrame("Frame", nil, container)
    sweepClip:SetSize(CONTAINER_SZ * 0.75, CONTAINER_SZ * 0.75)
    sweepClip:SetPoint("CENTER", container, "CENTER", 0, 0)
    sweepClip:SetFrameLevel(container:GetFrameLevel() + 5)
    sweepClip:SetClipsChildren(true)
    UM.openAnimFrame._sweepClip = sweepClip

    local sweep = sweepClip:CreateTexture(nil, "OVERLAY", nil, 7)
    sweep:SetColorTexture(1, 1, 1, 0.30)
    sweep:SetSize(12, 120)
    sweep:SetRotation(math.rad(20))
    sweep:ClearAllPoints()
    sweep:SetPoint("CENTER", sweepClip, "LEFT", -20, 0)
    sweep:Hide()
    UM.openAnimFrame._sweep = sweep

    UM.openAnimFrame:Hide()
    return UM.openAnimFrame
end

-------------------------------------------------------------------------------
--  One-time "How to use" tip -- shows below the banner on first ever open.
--  Saved to EllesmereUIDB.unlockTipSeen so it never shows again.
-------------------------------------------------------------------------------

function ns.ShowUnlockTip()
    if EllesmereUIDB and EllesmereUIDB.unlockTipSeen then return end
    if UM.unlockTipFrame and UM.unlockTipFrame:IsShown() then return end

    if not UM.unlockTipFrame then
        local TIP_W, TIP_H = 450, 175
        local ar, ag, ab = GetAccent()

        local tip = CreateFrame("Frame", nil, UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetFrameLevel(900)
        tip:SetSize(TIP_W, TIP_H)
        tip:EnableMouse(true)

        -- Pixel-perfect scale (match banner)
        local physW = (GetPhysicalScreenSize())
        local ppScale = GetScreenWidth() / physW
        tip:SetScale(ppScale)

        -- Position 100px from the top of the screen
        tip:SetPoint("TOP", UIParent, "TOP", 0, -100 / ppScale)

        local bg = tip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.95)

        EllesmereUI.MakeBorder(tip, ar, ag, ab, 0.25)

        -- Smooth arrow pointing up: rotated squares for clean diagonal edges, using
        -- SetClipsChildren to show only the top half of the diamond. No mask needed.
        local ARROW_SZ = 16  -- diamond size
        -- Clip frame: sits above the popup top edge, clips to show only top half
        -- Shifted up 2px so the arrow appears 2px higher
        local arrowClip = CreateFrame("Frame", nil, tip)
        arrowClip:SetFrameStrata("TOOLTIP")
        arrowClip:SetFrameLevel(tip:GetFrameLevel() + 10)
        arrowClip:SetClipsChildren(true)
        -- Clip region: tall enough for the top half of the diamond
        local clipH = ARROW_SZ
        arrowClip:SetSize(ARROW_SZ * 2, clipH)
        arrowClip:SetPoint("BOTTOM", tip, "TOP", 0, -1)

        -- The actual diamond frame inside the clip, positioned so its center
        -- (widest point) is exactly at the clip's bottom edge
        local arrowFrame = CreateFrame("Frame", nil, arrowClip)
        arrowFrame:SetFrameLevel(arrowClip:GetFrameLevel() + 1)
        arrowFrame:SetSize(ARROW_SZ + 4, ARROW_SZ + 4)
        arrowFrame:SetPoint("CENTER", arrowClip, "BOTTOM", 0, 0)

        -- Border diamond (accent, slightly larger for 1px border effect)
        -- Alpha slightly lower than popup border (0.25) to compensate for
        -- anti-aliased rotated edges appearing brighter than crisp 1px lines
        local arrowBorder = arrowFrame:CreateTexture(nil, "ARTWORK", nil, 7)
        arrowBorder:SetSize(ARROW_SZ + 2, ARROW_SZ + 2)
        arrowBorder:SetPoint("CENTER")
        arrowBorder:SetColorTexture(ar, ag, ab, 0.18)
        arrowBorder:SetRotation(math.rad(45))
        if arrowBorder.SetSnapToPixelGrid then arrowBorder:SetSnapToPixelGrid(false); arrowBorder:SetTexelSnappingBias(0) end

        -- Fill diamond (same bg as popup: 0.077, 0.068, 0.058, 0.95)
        local arrowFill = arrowFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        arrowFill:SetSize(ARROW_SZ, ARROW_SZ)
        arrowFill:SetPoint("CENTER")
        arrowFill:SetColorTexture(0.077, 0.068, 0.058, 0.95)
        arrowFill:SetRotation(math.rad(45))
        if arrowFill.SetSnapToPixelGrid then arrowFill:SetSnapToPixelGrid(false); arrowFill:SetTexelSnappingBias(0) end

        local msg = tip:CreateFontString(nil, "OVERLAY")
        msg:SetFont(FONT_PATH, 12, "OUTLINE, SLUG")
        msg:SetTextColor(1, 1, 1, 0.85)
        msg:SetPoint("TOP", tip, "TOP", 0, -17)
        msg:SetWidth(TIP_W - 30)
        msg:SetJustifyH("CENTER")
        msg:SetSpacing(6)
        msg:SetText(EllesmereUI.L("This is where you can control the settings of Unlock Mode.\n\nElements can be repositioned by dragging or arrow keys (+shift)\nAnchor, Height Match, or Width match any element.\nSnapping is based on closest element, but you can snap only to\n a specific element via right click or the settings icon."))

        local okBtn = CreateFrame("Button", nil, tip)
        okBtn:SetSize(80, 24)
        okBtn:SetPoint("BOTTOM", tip, "BOTTOM", 0, 15)
        EllesmereUI.MakeStyledButton(okBtn, "Okay", 10,
            EllesmereUI.RB_COLOURS, function()
                tip:Hide()
                if EllesmereUIDB then EllesmereUIDB.unlockTipSeen = true end
            end)

        UM.unlockTipFrame = tip
    end

    UM.unlockTipFrame:SetAlpha(0)
    UM.unlockTipFrame:Show()

    -- Fade in over 0.3s
    local fadeIn = 0
    UM.unlockTipFrame:SetScript("OnUpdate", function(self, dt)
        fadeIn = fadeIn + dt
        if fadeIn >= 0.3 then
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
            return
        end
        self:SetAlpha(fadeIn / 0.3)
    end)
end

function ns.OpenUnlockMode()
    if UM.isUnlocked then return end
    if InCombatLockdown() then
        print("|cffff6060[EllesmereUI]|r Cannot enter Unlock Mode during combat.")
        return
    end
    -- Standardized options-panel roundtrip: entering unlock mode by ANY means
    -- (minimap, /euiunlock, ...) while the options panel is open reopens it on exit,
    -- exactly like the sidebar Unlock Mode tab. Options-side entries capture their
    -- own return target BEFORE calling here, so only fill when unset. The game menu
    -- button never coexists with an open panel, so the IsShown gate is a natural no-op there.
    if not EllesmereUI._unlockReturnModule then
        local panel = EllesmereUI._mainFrame
        if panel and panel:IsShown() then
            EllesmereUI._unlockReturnModule = EllesmereUI:GetActiveModule() or nil
            EllesmereUI._unlockReturnPage = EllesmereUI:GetActivePage() or nil
        end
    end
    -- Permanent gold variant: when the current spec's owning group has a custom
    -- unlock layout (the ACTIVE layer), every unlock session on this spec edits
    -- that layer -- so every session shows the special visuals (gold frame/banner,
    -- size inputs hidden). Derived here, not at the card button, so opening unlock any way gets the right identity.
    do
        local activeGid = EllesmereUI.SpecOverrides_UnlockActive
            and EllesmereUI.SpecOverrides_UnlockActive() or nil
        local g
        if type(activeGid) == "string" then
            -- Conditional layer live ("cond:<gid>"): same gold identity, the
            -- banner shows the conditional group's name.
            local cid = tonumber(activeGid:match("^cond:(%d+)$"))
            g = cid and EllesmereUI.Conditions_GroupById
                and EllesmereUI.Conditions_GroupById(cid) or nil
        elseif activeGid then
            g = EllesmereUI.SpecOverrides_GroupById
                and EllesmereUI.SpecOverrides_GroupById(activeGid) or nil
        end
        EllesmereUI._specialUnlockGroup = g
    end
    -- Close any panel-side editing session/view BEFORE taking the value snapshot: the
    -- options panel doesn't hide until much later in this flow, so with the Default
    -- view (or an editing-as session) still holding SWAPPED values live, the snapshot
    -- would capture the view's values while the panel's eventual OnHide restored the
    -- SPEC's values -- Save & Exit would then diff spec-vs-default and bank every
    -- difference into values.default (defaults silently flipping to a group's
    -- values). Exiting the sessions here banks them properly and restores canonical
    -- spec values, so the snapshot below is clean. No-op when the panel is closed.
    if EllesmereUI.SpecOverrides_CloseEditSessions then
        EllesmereUI.SpecOverrides_CloseEditSessions()
    end
    -- Value-edit banking baseline: captured settings edited from unlock mode (cog
    -- size inputs) are Default-baseline edits; Save & Exit diffs against this
    -- snapshot and banks into values.default (special sessions skipped inside --
    -- their size inputs are hidden). Must run AFTER the special-group derivation above.
    if EllesmereUI.SpecOverrides_UnlockValueSnapBegin then
        EllesmereUI.SpecOverrides_UnlockValueSnapBegin()
    end
    -- Disable expandIfNoResource before _unlockActive is set so the
    -- Rebuild inside runs in normal gameplay state and the power bar
    -- is at its true stored height before movers capture positions.
    if _G._ERB_SuppressExpand then pcall(_G._ERB_SuppressExpand) end

    UM.isUnlocked = true
    EllesmereUI._unlockActive = true
    EllesmereUI._unlockModeActive = true

    -- Notify action bars to flip Blizzard-owned frame anchors for drag
    if _G._EAB_UnlockModeOpen then pcall(_G._EAB_UnlockModeOpen) end
    -- Notify raid frames to fade out overlay previews
    if _G._ERF_UnlockModeOpen then pcall(_G._ERF_UnlockModeOpen) end

    -- Remove any stale anchor/match relationships before entering unlock mode.
    -- By this point all elements are registered, so anything not in the registry
    -- is genuinely gone (e.g. a custom CDM bar that was deleted).
    ValidateStoredLinks()

    -- Notify beacon reminders to hide (if follow-mouse is active)
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Hide unit frame buffs/debuffs so they don't clutter the movers
    local UF_FRAME_NAMES = {
        "EllesmereUIUnitFrames_Player", "EllesmereUIUnitFrames_Target",
        "EllesmereUIUnitFrames_Focus", "EllesmereUIUnitFrames_Pet",
        "EllesmereUIUnitFrames_TargetTarget", "EllesmereUIUnitFrames_FocusTarget",
    }
    for i = 1, 8 do UF_FRAME_NAMES[#UF_FRAME_NAMES + 1] = "EllesmereUIUnitFrames_Boss" .. i end
    for _, name in ipairs(UF_FRAME_NAMES) do
        local f = _G[name]
        if f then
            if f.Buffs and f.Buffs:IsShown() then
                f.Buffs._unlockWasShown = true
                f.Buffs:Hide()
            end
            if f.Debuffs and f.Debuffs:IsShown() then
                f.Debuffs._unlockWasShown = true
                f.Debuffs:Hide()
            end
        end
    end

    -- Hide objective tracker (alpha only -- no :Hide() to avoid taint).
    -- Hook SetAlpha to suppress Blizzard re-showing it during unlock
    -- (mounting, quest updates, etc. call SetAlpha(1) on their own).
    local objTracker = _G.ObjectiveTrackerFrame
    if objTracker and objTracker:IsShown() then
        UM.objTrackerWasVisible = true
        objTracker._eabMouseWasEnabled = objTracker:IsMouseEnabled()
        objTracker:SetAlpha(0)
        if objTracker.EnableMouse then pcall(objTracker.EnableMouse, objTracker, false) end
        if not objTracker._eabUnlockAlphaHooked then
            objTracker._eabUnlockAlphaHooked = true
            hooksecurefunc(objTracker, "SetAlpha", function(self, a)
                if UM.isUnlocked and a > 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    else
        UM.objTrackerWasVisible = false
    end
    -- Also hide EllesmereUI QT background (separate UIParent child)
    local qtBg = _G.EllesmereUIQTBackground
    if qtBg then
        qtBg:SetAlpha(0)
        if not qtBg._eabUnlockAlphaHooked then
            qtBg._eabUnlockAlphaHooked = true
            hooksecurefunc(qtBg, "SetAlpha", function(self, a)
                if UM.isUnlocked and a > 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    end

    -- Reset session state and snapshot current positions
    wipe(pendingPositions)
    UM.hasChanges = false
    UM.selectedMover = nil
    -- Clear per-session temporary overlay hides (Shift+Right Click). Every unlock
    -- session starts with all overlays visible again. Cleared before the fade-in
    -- Sync / ShowBlizzOwnedOverlays calls so last session's hides don't persist.
    -- Fallback/override anchor ghosts carry the same flag (their tables are
    -- do-block locals, hence the namespaced helpers).
    for _, m in pairs(movers) do m._tempHidden = nil end
    for _, ov in pairs(_blizzOwnedOverlays) do ov._tempHidden = nil end
    if EllesmereUI._ClearFallbackGhostTempHides then EllesmereUI._ClearFallbackGhostTempHides() end
    if EllesmereUI._ClearOverrideGhostTempHides then EllesmereUI._ClearOverrideGhostTempHides() end
    -- Strip provider-owned visual adjustments that live OUTSIDE the anchor
    -- system (CDM's Additional Bar Offset on un-anchored bars): each enter hook
    -- self-gates, so this is near-free when nothing is active.
    EllesmereUI.RunAnchorShiftEnters()
    -- Strip any temporary anchor-target shift (e.g. "Shift Elements if No
    -- Resource"/"...if No Bars") so movers snapshot TRUE saved positions.
    -- _unlockActive is already true above, so the shift providers return 0 and
    -- this re-apply snaps shifted children back to their real positions. Gated so
    -- non-shift profiles do no extra work on unlock entry.
    if EllesmereUI.AnchorShiftWantsApply()
       and EllesmereUI.ReapplyAllUnlockAnchors then
        -- Force edge-preservation for this reapply so custom-growth anchored bars
        -- snap to their fixed growth edge (their true saved position), not the
        -- center-offset position. Reset in all cases (pcall) so the flag can't leak.
        EllesmereUI._reapplyForceEdgePreserve = true
        pcall(EllesmereUI.ReapplyAllUnlockAnchors)
        EllesmereUI._reapplyForceEdgePreserve = false
    end
    SnapshotPositions()

    -- Setup and show arrow key frame for nudge support
    SetupArrowKeyFrame()
    UM.arrowKeyFrame:Show()

    -- Play unlock sound
    PlaySound(201528, "Master")

    -- Create frames
    CreateUnlockFrame()
    CreateGrid(UM.unlockFrame)
    CreateHUD(UM.unlockFrame)
    EllesmereUI:_NotifyUnlockModeListeners(true)
    CreateOpenAnimFrame(UM.unlockFrame)

    -- Special (spec-override) sessions swap the unlock art for the override
    -- variants; normal sessions restore the standard art. Re-set every open:
    -- the frames are created once and reused across sessions.
    do
        local ov = EllesmereUI._specialUnlockGroup and "-override" or ""
        if UM.hudFrame and UM.hudFrame._bannerTex then
            UM.hudFrame._bannerTex:SetTexture(
                "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-banner-2" .. ov .. ".png")
        end
        if UM.openAnimFrame then
            if UM.openAnimFrame._outer then
                UM.openAnimFrame._outer:SetTexture(
                    "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-outer-2" .. ov .. ".png")
            end
            if UM.openAnimFrame._inner then
                UM.openAnimFrame._inner:SetTexture(
                    "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-inner-2" .. ov .. ".png")
            end
            if UM.openAnimFrame._top then
                UM.openAnimFrame._top:SetTexture(
                    "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-top-2" .. ov .. ".png")
            end
        end
    end

    -- Capture the options panel frame for the shrink animation
    local panel = EllesmereUI and EllesmereUI._mainFrame
    local panelStartW, panelStartH
    if panel and panel:IsShown() then
        panelStartW = panel:GetWidth()
        panelStartH = panel:GetHeight()
    end
    panelStartW = panelStartW or 600
    panelStartH = panelStartH or 400
    -- Use the larger dimension for the scale factor
    local panelStartSz = max(panelStartW, panelStartH)
    -- startScale: how big the container needs to be so it appears panel-sized
    -- BASE_SCALE makes the container appear as ICON_SZ on screen,
    -- so to appear as panelStartSz we need: BASE_SCALE * (panelStartSz / ICON_SZ)
    local startScale = BASE_SCALE * (panelStartSz / ICON_SZ) * 0.6

    -- Controller Back steps out like Escape: registered with the escape proxy
    -- on the first open with a controller in use (padOnly: it counts only then),
    -- and never a controller-cursor root (a pointer-drag UI).
    if not UM.unlockFrame._padEsc and EllesmereUI.PadInUse() then
        UM.unlockFrame._padEsc = true
        EllesmereUI.RegisterEscapeClose(UM.unlockFrame, {
            padOnly = true, notOwned = true, onEscape = UM.unlockFrame._padBack,
        })
    end

    -- Show overlay, hide grid/toolbar/movers
    UM.unlockFrame:Show()
    UM.unlockFrame:SetAlpha(1)
    if UM.gridFrame then UM.gridFrame:Hide() end
    if UM.hudFrame then UM.hudFrame:Hide() end
    for _, m in pairs(movers) do m:Hide() end

    local container = UM.openAnimFrame._container
    local outerTex  = UM.openAnimFrame._outer
    local innerTex  = UM.openAnimFrame._inner
    local topTex    = UM.openAnimFrame._top

    if UM.openAnimFrame._sweep then UM.openAnimFrame._sweep:Hide() end

    -- Container starts at panel-sized scale, textures stay at native dims always
    local TOTAL_GEAR_ROT = GEAR_ROTATION * 4

    -- Reset textures anchored to container center -- ONCE
    -- (sizes are already set to native dims at creation, never change them)
    outerTex:ClearAllPoints()
    outerTex:SetPoint("CENTER", container, "CENTER", 0, OUTER_Y_OFFSET)
    outerTex:SetAlpha(0)
    outerTex:SetRotation(TOTAL_GEAR_ROT)

    innerTex:ClearAllPoints()
    innerTex:SetPoint("CENTER", container, "CENTER", 0, 0)
    innerTex:SetAlpha(0)
    innerTex:SetRotation(-TOTAL_GEAR_ROT)

    topTex:ClearAllPoints()
    topTex:SetPoint("CENTER", container, "CENTER", 0, 0)
    topTex:SetAlpha(0)
    topTex:SetRotation(0)

    -- Container starts at panel scale
    container:SetScale(startScale)

    UM.openAnimFrame:Show()
    UM.openAnimFrame:SetAlpha(1)

    -- Start overlay at 0 alpha, will fade in during animation
    if UM.unlockFrame._overlay then
        UM.unlockFrame._overlay:SetColorTexture(0.030, 0.023, 0.018, 0)
    end

    -- Phase timings
    local MORPH     = 0.50  -- panel shrinks + lock appears simultaneously
    local IDLE_SPIN = 1.00  -- gears keep spinning at icon size
    local OVERLAP   = 0.75  -- shackle starts this much BEFORE idle spin ends
    local SHACKLE   = 0.75  -- shackle lifts + sweep duration (slowed)

    -- Gear rotation: one continuous motion across MORPH + IDLE_SPIN
    local SPIN_DUR = MORPH + IDLE_SPIN  -- total time gears rotate
    -- Shackle/HUD start time (0.75s before scaling/spinning stops)
    local SHACKLE_START = MORPH + IDLE_SPIN - OVERLAP

    local panelHidden = false
    local panelRealScale = panel and panel:GetScale() or 1
    local elapsed = 0
    local fadeInSynced = false

    -- Grid glitch starts immediately and lasts 0.75s
    local GLITCH_DUR = 0.75
    local GRID_START = 0  -- grid begins immediately
    local gridStarted = false

    -- Reset cursor speed so the first hover isn't blocked by a stale value
    EllesmereUI._unlockCursorSpeed = 0

    UM.unlockFrame:SetScript("OnUpdate", function(self, dt)
        -- Sample cursor position and compute speed for hover intent detection
        do
            local scale = UIParent:GetEffectiveScale()
            local nx, ny = GetCursorPosition()
            nx = nx / scale; ny = ny / scale
            if dt > 0 then
                local dx = nx - EllesmereUI._unlockCursorX
                local dy = ny - EllesmereUI._unlockCursorY
                -- Store squared speed to avoid sqrt; TryExpand compares against squared threshold
                EllesmereUI._unlockCursorSpeed = (dx * dx + dy * dy) / (dt * dt)

                -- After arrow-key nudge collapsed a mover, re-expand it
                -- once the cursor moves and is still hovering the mover.
                if UM.selectedMover and UM.selectedMover._nudgeCollapsed then
                    local moved = (dx ~= 0 or dy ~= 0)
                    if moved then
                        UM.selectedMover._nudgeCollapsed = nil
                        if UM.selectedMover:IsMouseOver() then
                            if UM.selectedMover._showOverlayText then
                                UM.selectedMover._showOverlayText()
                                UM.hoveredMover = UM.selectedMover
                            end
                        end
                    end
                end
            end
            EllesmereUI._unlockCursorX = nx; EllesmereUI._unlockCursorY = ny
        end

        -- Selected movers are NOT auto re-expanded: expansion is purely
        -- hover-driven. A selected element (e.g. one being width/height matched or
        -- anchored) keeps its border/level highlight via OnLeave regardless; the
        -- nudge block above re-expands only while the cursor is over the mover.

        elapsed = elapsed + dt

        ---------------------------------------------------------------
        --  Background overlay fade: 0 -> full alpha over 0.75 seconds
        --  (synced with grid glitch duration)
        ---------------------------------------------------------------
        local OVERLAY_FADE_DUR = 0.75
        if UM.unlockFrame._overlay then
            local oa = min(1, elapsed / OVERLAY_FADE_DUR) * (UM.unlockFrame._overlayMaxAlpha or 0.20)
            UM.unlockFrame._overlay:SetColorTexture(0.030, 0.023, 0.018, oa)
        end

        ---------------------------------------------------------------
        --  Grid glitch overlay -- runs independently of lock phases
        --  Starts at GRID_START (beginning of idle spin, 1s earlier)
        ---------------------------------------------------------------
        if elapsed >= GRID_START then
            if not gridStarted then
                gridStarted = true
                if UM.gridFrame then
                    UM.gridFrame:Rebuild()
                    if UM.gridMode ~= "disabled" then UM.gridFrame:Show() end
                    UM.gridFrame:SetAlpha(0)
                end
                if UM.hudFrame then
                    UM.hudFrame:Show()
                    UM.hudFrame:SetAlpha(1)
                    -- Position off-screen (will slide down during shackle)
                    UM.hudFrame:ClearAllPoints()
                    local ppS = UM.hudFrame:GetScale() or 1
                    UM.hudFrame:SetPoint("TOP", UIParent, "TOP", 0, (BANNER_PX_H + 10) * ppS)
                end
                for _, barKey in ipairs(ALL_BAR_ORDER) do
                    -- Skip bars that have a registered element (avoids duplicates)
                    if not registeredElements[barKey] then
                        local m = CreateMover(barKey)
                        if m then m:Sync(); m:SetAlpha(0) end
                    end
                end
                -- Registered elements (unit frames, etc.)
                RebuildRegisteredOrder()
                for _, key in ipairs(registeredOrder) do
                    local m = CreateMover(key)
                    if m then m:Sync(); m:SetAlpha(0) end
                end
                -- Sort frame levels: smaller movers render on top
                SortMoverFrameLevels()
                -- Re-apply saved anchor positions and refresh anchored mover text
                ReapplyAllAnchors()
                wipe(pendingPositions)
                for bk, _ in pairs(movers) do
                    if movers[bk].RefreshAnchoredText then
                        movers[bk]:RefreshAnchoredText()
                    end
                end
                -- Spec-override gold borders / special-session locks + banner
                if EllesmereUI._unlockRefreshSpecOvMarks then EllesmereUI._unlockRefreshSpecOvMarks() end

                -- Info overlays on Blizzard-owned elements (chat, micro, bags, encounter)
                -- Start at alpha 0; the mover fade-in loop below handles them.
                ShowBlizzOwnedOverlays(UM.unlockFrame)
                for _, bov in pairs(_blizzOwnedOverlays) do
                    bov:SetAlpha(0)
                end

                -- Fallback ghost overlays for elements with a fallback link
                -- (spawn at 0 alpha; the mover fade-in loop below ramps them)
                if EllesmereUI._RefreshFallbackGhosts then
                    EllesmereUI._RefreshFallbackGhosts()
                    if EllesmereUI._SetFallbackGhostsAlpha then
                        EllesmereUI._SetFallbackGhostsAlpha(0)
                    end
                end

                -- Override anchors release to baseline for the session (movers
                -- edit the baseline; the gold ghosts edit the overrides), then
                -- their ghosts spawn on the same fade curve.
                if EllesmereUI._ReapplyOverrideAnchors then EllesmereUI._ReapplyOverrideAnchors() end
                if EllesmereUI._RefreshOverrideGhosts then
                    EllesmereUI._RefreshOverrideGhosts()
                    if EllesmereUI._SetOverrideGhostsAlpha then
                        EllesmereUI._SetOverrideGhostsAlpha(0)
                    end
                end

                -- Retry ticker: some addons (CDM) may not have their bar
                -- frames ready yet. Poll briefly to catch late arrivals.
                local retryAttempts = 0
                local retryTicker
                retryTicker = C_Timer.NewTicker(0.5, function()
                    retryAttempts = retryAttempts + 1
                    if not UM.isUnlocked then retryTicker:Cancel(); return end
                    -- Ask addons to re-register elements they may not have
                    -- registered yet (CDM bars that were still building, etc.)
                    if EllesmereUI._unlockRegistrationDirty or retryAttempts <= 3 then
                        if _G._ECME_RegisterUnlock then _G._ECME_RegisterUnlock() end
                        if _G._ECME_RegisterTBBUnlock then _G._ECME_RegisterTBBUnlock() end
                        -- Late-registering frames may satisfy a fallback
                        -- ghost that could not resolve at open.
                        if EllesmereUI._RefreshFallbackGhosts then
                            EllesmereUI._RefreshFallbackGhosts()
                        end
                        if EllesmereUI._RefreshOverrideGhosts then
                            EllesmereUI._RefreshOverrideGhosts()
                        end
                    end
                    RebuildRegisteredOrder()
                    local spawned = false
                    local missing = false
                    for _, rk in ipairs(registeredOrder) do
                        if not movers[rk] then
                            local rm = CreateMover(rk)
                            if rm then
                                rm:Sync()
                                rm:SetAlpha(UM.darkOverlaysEnabled and 1 or MOVER_ALPHA)
                                rm:Show()
                                spawned = true
                            else
                                missing = true
                            end
                        elseif not movers[rk]:IsShown() then
                            -- Mover exists but bar frame was not ready on
                            -- first Sync -- re-sync now that it may be available
                            local re = registeredElements[rk]
                            if not (re and re.isHidden and re.isHidden()) then
                                local rm = movers[rk]
                                rm:Sync()
                                if rm:IsShown() then
                                    rm:SetAlpha(UM.darkOverlaysEnabled and 1 or MOVER_ALPHA)
                                    spawned = true
                                else
                                    missing = true
                                end
                            end
                        end
                    end
                    if spawned then
                        SortMoverFrameLevels()
                        ReapplyAllAnchors()
                        if EllesmereUI._unlockRefreshSpecOvMarks then EllesmereUI._unlockRefreshSpecOvMarks() end
                    end
                    -- Stop once every mover is visible, or after timeout
                    if not missing or retryAttempts >= 20 then
                        retryTicker:Cancel()
                    end
                end)
            end

            local glitchT = elapsed - GRID_START
            local glitchProgress = min(1, glitchT / GLITCH_DUR)

            -- (Banner slides down during shackle phase, not here)

            -- Movers fade in over 0.75s, delayed by 0.5s
            local MOVER_DELAY = 0.50
            local moverFadeT = glitchT - MOVER_DELAY
            for _, m in pairs(movers) do
                if m:IsShown() then
                    if moverFadeT > 0 then
                        -- Re-sync once right as movers begin fading in so any
                        -- frames that were nil at initial sync are now ready.
                        if not fadeInSynced then
                            fadeInSynced = true
                            for _, rm in pairs(movers) do rm:Sync() end
                        end
                        m:SetAlpha((UM.darkOverlaysEnabled and 1 or MOVER_ALPHA) * min(1, moverFadeT / GLITCH_DUR))
                    else
                        m:SetAlpha(0)
                    end
                end
            end
            -- Blizzard-owned overlays fade in on the same curve
            for _, bov in pairs(_blizzOwnedOverlays) do
                if bov:IsShown() then
                    if moverFadeT > 0 then
                        bov:SetAlpha(min(1, moverFadeT / GLITCH_DUR))
                    else
                        bov:SetAlpha(0)
                    end
                end
            end
            -- Fallback ghosts fade in on the same curve (75% resting alpha)
            if EllesmereUI._SetFallbackGhostsAlpha then
                if moverFadeT > 0 then
                    EllesmereUI._SetFallbackGhostsAlpha(min(1, moverFadeT / GLITCH_DUR))
                else
                    EllesmereUI._SetFallbackGhostsAlpha(0)
                end
            end
            -- Override anchor ghosts ride the same curve
            if EllesmereUI._SetOverrideGhostsAlpha then
                if moverFadeT > 0 then
                    EllesmereUI._SetOverrideGhostsAlpha(min(1, moverFadeT / GLITCH_DUR))
                else
                    EllesmereUI._SetOverrideGhostsAlpha(0)
                end
            end

            -- Grid glitch effect
            if UM.gridFrame and UM.gridFrame:IsShown() then
                local baseA = glitchProgress
                local flicker = 0
                if glitchProgress < 0.9 then
                    local intensity = (1 - glitchProgress) * 0.7
                    local t1 = glitchT * 37.3
                    local t2 = glitchT * 13.7
                    local t3 = glitchT * 71.1
                    flicker = (sin(t1) * 0.4 + sin(t2) * 0.35 + sin(t3) * 0.25) * intensity
                    if sin(glitchT * 5.3) > 0.85 and glitchProgress < 0.6 then
                        flicker = flicker - 0.5
                    end
                end
                UM.gridFrame:SetAlpha(max(0, min(1, baseA + flicker)))
            end
        end

        -------------------------------------------------------------------
        --  Continuous gear rotation: one smooth ease-out across MORPH +
        --  IDLE_SPIN combined. Rotation goes from TOTAL_GEAR_ROT -> 0.
        -------------------------------------------------------------------
        local gearRot = 0
        -- Extended taper with quintic ease-out for imperceptible final frames
        local SPIN_TAPER = SPIN_DUR + 0.5
        if elapsed < SPIN_TAPER then
            local spinT = elapsed / SPIN_TAPER
            -- Quintic ease-out: (1-t)^5 -- extremely gradual deceleration
            local inv = 1 - spinT
            local eased = 1 - inv * inv * inv * inv * inv
            gearRot = TOTAL_GEAR_ROT * (1 - eased)
        end
        outerTex:SetRotation(gearRot)
        innerTex:SetRotation(-gearRot)

        -------------------------------------------------------------------
        --  Phase 1: Panel shrinks + fades while lock container scales down
        --           from startScale -> BASE_SCALE over MORPH seconds.
        --           After MORPH, container stays at BASE_SCALE (no hard snap).
        -------------------------------------------------------------------
        if elapsed < MORPH then
            local t = EaseInOutCubic(elapsed / MORPH)
            local sc = startScale + (BASE_SCALE - startScale) * t

            -- Panel scales down, slides to center, and fades out
            -- Panel scales down + fades out (relative to its real scale)
            if panel and not panelHidden then
                local s = panelRealScale * max(0.01, 1 - t)
                panel:SetScale(s)
                -- Alpha fades to 0 in 0.25s (twice as fast as the scale)
                local alphaT = min(1, elapsed / 0.25)
                panel:SetAlpha(1 - alphaT)
                if t > 0.95 then
                    panelHidden = true
                    panel:SetScale(panelRealScale)
                    panel:SetAlpha(1)
                    EllesmereUI:Hide()
                end
            end

            -- Scale the container uniformly
            container:SetScale(sc)

            -- Fade textures in: delayed 0.25s, then 0->1 over remaining 0.25s
            -- Top stays hidden until shackle phase
            local LOGO_FADE_DELAY = 0.15
            local logoAlpha = 0
            if elapsed > LOGO_FADE_DELAY then
                logoAlpha = min(1, (elapsed - LOGO_FADE_DELAY) / (MORPH - LOGO_FADE_DELAY))
            end
            outerTex:SetAlpha(logoAlpha)
            innerTex:SetAlpha(logoAlpha)
            topTex:SetAlpha(0)
            return
        end

        -- Ensure panel is hidden (one-time cleanup, no visual snap)
        if not panelHidden then
            panelHidden = true
            if panel then panel:SetScale(panelRealScale); panel:SetAlpha(1) end
            EllesmereUI:Hide()
        end

        -- Post-morph: container at final scale, inner/outer fully visible
        -- (these are already at their final values from the last morph frame,
        --  but we set them once cleanly without causing a visual snap)
        container:SetScale(BASE_SCALE)

        -------------------------------------------------------------------
        --  Shackle + HUD: starts at SHACKLE_START (0.25s before spin ends)
        --  Overlaps the final gear deceleration.
        -------------------------------------------------------------------
        local shackleT = elapsed - SHACKLE_START
        if shackleT >= 0 and shackleT < SHACKLE then
            local t = EaseInOutCubic(shackleT / SHACKLE)
            -- Top piece fades from 0->100% over 0.5s, delayed 0.2s from shackle start
            -- (movement still starts immediately, only alpha is delayed)
            local TOP_FADE_IN = 0.25
            local TOP_FADE_DELAY = 0.20
            local topAlphaT = shackleT - TOP_FADE_DELAY
            if topAlphaT > 0 then
                topTex:SetAlpha(min(1, topAlphaT / TOP_FADE_IN))
            else
                topTex:SetAlpha(0)
            end
            topTex:ClearAllPoints()
            topTex:SetPoint("CENTER", container, "CENTER", 0, SHACKLE_LIFT * t)

            -- Banner slides down from off-screen, synced with shackle
            if UM.hudFrame and UM.hudFrame:IsShown() then
                local ppS = UM.hudFrame:GetScale() or 1
                local offScreen = (BANNER_PX_H + 10) * ppS
                local bannerY = offScreen * (1 - t)
                UM.hudFrame:ClearAllPoints()
                UM.hudFrame:SetPoint("TOP", UIParent, "TOP", 0, bannerY)
            end

            -- Sweep runs during shackle phase
            local sweepTex = UM.openAnimFrame._sweep
            if sweepTex then
                if not sweepTex:IsShown() then sweepTex:Show() end
                local st = min(1, shackleT / SHACKLE)
                local clipW = UM.openAnimFrame._sweepClip:GetWidth()
                local xPos = -20 + (clipW + 40) * st
                sweepTex:ClearAllPoints()
                sweepTex:SetPoint("CENTER", UM.openAnimFrame._sweepClip, "LEFT", xPos, 0)
                local sweepAlpha
                if st < 0.15 then sweepAlpha = st / 0.15
                elseif st > 0.85 then sweepAlpha = (1 - st) / 0.15
                else sweepAlpha = 1 end
                sweepTex:SetAlpha(0.30 * sweepAlpha)
            end
        end

        -- After shackle completes, settle top piece and hide sweep
        if shackleT >= SHACKLE then
            topTex:SetAlpha(1)
            topTex:ClearAllPoints()
            topTex:SetPoint("CENTER", container, "CENTER", 0, SHACKLE_LIFT)
            if UM.openAnimFrame._sweep then UM.openAnimFrame._sweep:Hide() end
        end

        -- Still in idle spin phase (before shackle or during overlap), keep waiting
        if elapsed < SPIN_DUR and shackleT < SHACKLE then
            return
        end

        -- If shackle hasn't finished yet, keep going
        if shackleT < SHACKLE then
            return
        end

        -------------------------------------------------------------------
        --  Done -- logo stays at full alpha, grid fully visible,
        --  banner is at final position (flush with top of screen)
        -------------------------------------------------------------------
        UM.openAnimFrame:SetAlpha(1)
        outerTex:SetRotation(0)
        innerTex:SetRotation(0)
        if UM.gridFrame then UM.gridFrame:SetAlpha(1) end
        if UM.hudFrame then
            UM.hudFrame:ClearAllPoints()
            UM.hudFrame:SetPoint("TOP", UIParent, "TOP", 0, 0)
        end
        self:SetScript("OnUpdate", nil)

        -- Start anchor connector line updates now that movers are visible
        if UM.unlockFrame._anchorLineDriver then
            UM.unlockFrame._anchorLineDriver:Show()
        end
        if UM.unlockFrame._anchorLineFrame then
            UM.unlockFrame._anchorLineFrame:Show()
        end

        -- ReapplyAllAnchors during open sets hasChanges; reset ONLY if
        -- the user hasn't already interacted (e.g. dragged during animation).
        if not next(pendingPositions) then
            UM.hasChanges = false
        end

        -- Auto-select a mover if requested (e.g. from cog popup link)
        if EllesmereUI._unlockAutoSelectKey then
            local autoKey = EllesmereUI._unlockAutoSelectKey
            EllesmereUI._unlockAutoSelectKey = nil
            C_Timer.After(0.6, function()
                if movers[autoKey] then
                    SelectMover(movers[autoKey])
                end
            end)
        end

        -- Fade ONLY the lock logo to 0% over 2 seconds, after 1s hold.
        -- Banner stays visible permanently (it has functional toggles).
        local LOGO_HOLD = 1.0
        local LOGO_FADE_DUR = 2.0
        local fadeElapsed = 0
        if not UM.logoFadeFrame then
            UM.logoFadeFrame = CreateFrame("Frame", nil, UIParent)
        end
        UM.logoFadeFrame:Show()
        UM.logoFadeFrame:SetScript("OnUpdate", function(ff, fdt)
            fadeElapsed = fadeElapsed + fdt
            if fadeElapsed < LOGO_HOLD then return end
            local ft = fadeElapsed - LOGO_HOLD
            if ft >= LOGO_FADE_DUR then
                if UM.openAnimFrame then UM.openAnimFrame:SetAlpha(0) end
                ff:SetScript("OnUpdate", nil)
                ff:Hide()
                return
            end
            local t = ft / LOGO_FADE_DUR
            if UM.openAnimFrame then
                UM.openAnimFrame:SetAlpha(1 - t)
            end
        end)

        -- Show one-time toolbar tip (after animation settles)
        ns.ShowUnlockTip()
    end)
end
end
