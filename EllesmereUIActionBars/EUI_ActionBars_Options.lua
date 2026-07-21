-------------------------------------------------------------------------------
--  EUI_ActionBar_Options.lua
--  Registers the real Action Bars module with EllesmereUI
--  Pure UI makeover all get/set calls go to EAB.db.profile, same as before
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EAB = ns.EAB
local VisibilityCompat = EAB and EAB.VisibilityCompat

local function GetEABOptOutline() return EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or "" end
local function GetEABOptUseShadow() return EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow() or true end

-------------------------------------------------------------------------------
--  Section / page names  (edit here to rename everywhere)
-------------------------------------------------------------------------------
local PAGE_DISPLAY        = "Bar Display"
local PAGE_MENUBAGSXP     = "Menu, Bags & XP Bars"
local PAGE_ANIMATIONS     = "Bar Animations"
local SECTION_ICON_APPEARANCE = "ICONS"
local SECTION_LAYOUT      = "LAYOUT"
local SECTION_TEXT        = "TEXT"
local SECTION_VISIBILITY  = "VISIBILITY"

-- Wait for EllesmereUI to exist (it's created by another addon in the suite)
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP
    if not EAB or not EAB.db then return end

    ---------------------------------------------------------------------------
    --  Local references from the addon namespace
    ---------------------------------------------------------------------------
    local BAR_DROPDOWN_VALUES = ns.BAR_DROPDOWN_VALUES
    local BAR_DROPDOWN_ORDER  = ns.BAR_DROPDOWN_ORDER
    local VISIBILITY_ONLY     = ns.VISIBILITY_ONLY
    local BAR_LOOKUP          = ns.BAR_LOOKUP
    local DATA_BAR            = ns.DATA_BAR or {}

    -- Filtered bar list for multi-edit: action bars only (no MicroBar/BagBar)
    local GROUP_BAR_ORDER = {}
    for _, key in ipairs(BAR_DROPDOWN_ORDER) do
        if not VISIBILITY_ONLY[key] then
            GROUP_BAR_ORDER[#GROUP_BAR_ORDER + 1] = key
        end
    end

    -- Check if a bar is enabled (we control all bars now, always enabled)
    local function IsBarEnabled(barKey)
        if not EAB or not EAB.db then return true end
        local s = EAB.db.profile.bars[barKey]
        if s and s.enabled ~= nil then return s.enabled end
        return true
    end

    local InCombatLockdown = InCombatLockdown
    local pcall = pcall
    local floor = math.floor
    local RANGE_INDICATOR = RANGE_INDICATOR or "\226\128\162"

    ---------------------------------------------------------------------------
    --  Helpers
    ---------------------------------------------------------------------------
    local _selectedBarKey = "MainBar"
    local function SelectedKey()
        return _selectedBarKey
    end

    local function SB()
        return EAB.db.profile.bars[SelectedKey()] or {}
    end

    local function IsVisOnly()
        return VISIBILITY_ONLY[SelectedKey()]
    end

    local function IsDataBar()
        return DATA_BAR[SelectedKey()]
    end

    -- First actual button of a bar, used to read its default size. Prefers our
    -- own EABButton; falls back to the native Blizzard button. Returns nil for
    -- custom bars (Bar9/Bar10), which have no native button -- callers default
    -- the size. (Avoids concatenating a nil buttonPrefix.)
    local function FirstBarButton(key)
        local eb = ns.barButtons and ns.barButtons[key]
        if eb and eb[1] then return eb[1] end
        local bi = BAR_LOOKUP[key]
        if bi and bi.buttonPrefix then return _G[bi.buttonPrefix .. "1"] end
        return nil
    end

    ---------------------------------------------------------------------------
    --  Ordered dropdown values for the bar selector
    ---------------------------------------------------------------------------
    local barLabels = {}
    local barOrder  = {}
    for _, key in ipairs(BAR_DROPDOWN_ORDER) do
        -- Skip MicroBar/BagBar and XPBar/RepBar/FavorBar — these live on the
        -- dedicated "Menu, Bags & XP Bars" tab, not the Bar Display bar selector.
        if key ~= "MicroBar" and key ~= "BagBar" and key ~= "XPBar" and key ~= "RepBar" and key ~= "FavorBar" then
            barLabels[key] = BAR_DROPDOWN_VALUES[key]
            barOrder[#barOrder + 1] = key
        end
    end

    -- Allow Unlock Mode's "Element Options" to pre-select a specific bar before
    -- the Bar Display page builds (mirrors the unit-frame path): a direct setter
    -- for when this module has already built, plus a pending value consumed at
    -- page-build time. Both ignore keys that are not Bar Display dropdown bars
    -- (Micro/Bag/XP/Rep live on their own tab) so the selector never goes blank.
    EllesmereUI._setActionBarKey = function(key)
        if barLabels[key] then _selectedBarKey = key end
    end
    EllesmereUI._consumePendingActionBarSelect = function()
        local pending = EllesmereUI._pendingActionBarSelect
        EllesmereUI._pendingActionBarSelect = nil
        if pending and barLabels[pending] then _selectedBarKey = pending end
    end

    ---------------------------------------------------------------------------
    --  Edit Overlay System
    --  Shows a non-draggable unlock-mode-style overlay on the actual bar
    --  position when editing certain bars in Single Bar Edit.
    --  XP/Rep bars: always show overlay when selected.
    --  BagBar/MicroBar: show overlay only when hidden or mouseover-fade.
    ---------------------------------------------------------------------------
    local EXTRA_BARS = ns.EXTRA_BARS or {}
    local editOverlayFrame = nil  -- reusable overlay frame

    local function GetEditOverlayTarget(barKey)
        -- Data bars: show overlay only if not using Blizzard data bars
        if DATA_BAR[barKey] then
            if EAB.db.profile.useBlizzardDataBars then return nil end
            local df = ns.dataBarFrames and ns.dataBarFrames[barKey]
            return df
        end
        -- BagBar / MicroBar: show only when hidden or mouseover
        if barKey == "BagBar" or barKey == "MicroBar" then
            local s = EAB.db.profile.bars[barKey]
            if s and (s.alwaysHidden or s.mouseoverEnabled) then
                for _, info in ipairs(EXTRA_BARS) do
                    if info.key == barKey and info.frameName then
                        return _G[info.frameName]
                    end
                end
            end
        end
        return nil
    end

    local function ShowEditOverlay(barKey)
        local target = GetEditOverlayTarget(barKey)
        if not target then
            if editOverlayFrame then editOverlayFrame:Hide() end
            return
        end

        if not editOverlayFrame then
            editOverlayFrame = CreateFrame("Frame", "EllesmereEAB_EditOverlay", UIParent)
            editOverlayFrame:SetFrameStrata("HIGH")
            editOverlayFrame:SetFrameLevel(100)
            editOverlayFrame:EnableMouse(false)  -- non-interactive, no dragging

            local bg = editOverlayFrame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.075, 0.113, 0.141, 0.85)
            editOverlayFrame._bg = bg

            -- Pixel-perfect border
            if EllesmereUI and EllesmereUI.MakeBorder then
                local eg = EllesmereUI.ELLESMERE_GREEN
                local ar, ag, ab = 1, 1, 1
                if eg then ar, ag, ab = eg.r, eg.g, eg.b end
                editOverlayFrame._border = EllesmereUI.MakeBorder(editOverlayFrame, ar, ag, ab, 0.6, EllesmereUI.PanelPP)
            end

            -- Label
            local label = editOverlayFrame:CreateFontString(nil, "OVERLAY")
            local fontPath = EllesmereUI and EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
            label:SetFont(fontPath, 10, GetEABOptOutline())
            label:SetTextColor(1, 1, 1, 0.75)
            label:SetPoint("CENTER")
            label:SetWordWrap(false)
            editOverlayFrame._label = label
        end

        -- Sync size and position to the target frame
        local s = target:GetEffectiveScale()
        local uiS = UIParent:GetEffectiveScale()
        local w = (target:GetWidth() or 50) * s / uiS
        local h = (target:GetHeight() or 50) * s / uiS
        editOverlayFrame:SetSize(w, h)

        local left, top = target:GetLeft(), target:GetTop()
        if left and top then
            local uiH = UIParent:GetHeight()
            local cx = left * s / uiS + w * 0.5
            local cy = top * s / uiS - h * 0.5
            editOverlayFrame:ClearAllPoints()
            editOverlayFrame:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy - uiH)
        end

        -- Set label text
        local labelText = BAR_DROPDOWN_VALUES[barKey] or barKey
        editOverlayFrame._label:SetText(labelText)
        editOverlayFrame:Show()
    end

    local function HideEditOverlay()
        if editOverlayFrame then editOverlayFrame:Hide() end
    end

    -- Hide overlay when the panel is closed
    EllesmereUI:RegisterOnHide(HideEditOverlay)

    -- Sync Edit Mode icon counts when the settings panel closes
    -- (user may have changed numIcons for a bar)
    EllesmereUI:RegisterOnHide(function() EAB:SyncEditModeIcons() end)

    ---------------------------------------------------------------------------
    --  Live Preview System
    --
    --  Instead of rebuilding static frames on every setting change, the
    --  preview creates its child frames once and exposes an :Update() method
    --  that re-reads all current DB values and applies them to the existing
    --  textures.  Widget callbacks call UpdatePreview() which is extremely
    --  cheap no frame creation, no GC pressure, just SetPoint / SetSize /
    --  SetColorTexture / SetTexCoord calls on already-existing objects.
    ---------------------------------------------------------------------------
    local activePreview    -- reference to the current preview frame (if any)
    local headerFixedH = 0 -- fixed height in content header (dropdown + label + padding), excluding preview
    local _barsHeaderBuilder  -- stored header builder for cache restore
    local _abPreviewHintFS                 -- hint FontString for Single Bar Edit
    local barsHeaderBaseH = 0              -- bars header height WITHOUT hint

    local function IsPreviewHintDismissed()
        return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
    end

    -- Lightweight refresh just re-reads settings and updates visuals
    local function UpdatePreview()
        -- Recover activePreview from content header if it was lost (e.g. page cache restore)
        if not activePreview and EllesmereUI._contentHeaderPreview then
            activePreview = EllesmereUI._contentHeaderPreview
        end
        if activePreview and activePreview.Update then
            activePreview:Update()
        end
    end

    -- Full refresh also recalculates content header height (for bar scale changes)
    local function UpdatePreviewAndResize()
        if not activePreview and EllesmereUI._contentHeaderPreview then
            activePreview = EllesmereUI._contentHeaderPreview
        end
        if activePreview and activePreview.Update then
            activePreview:Update()
            if headerFixedH > 0 then
                local hintH = (not IsPreviewHintDismissed()) and 29 or 0
                local wrapH = activePreview._wrapper and activePreview._wrapper:GetHeight() or (activePreview:GetHeight() * activePreview:GetScale())
                local newTotal = headerFixedH + wrapH + hintH
                EllesmereUI:UpdateContentHeaderHeight(newTotal)
            end
        end
    end

    -- Refresh the preview every time the panel is reopened
    EllesmereUI:RegisterOnShow(UpdatePreview)

    -- Rebuild the preview when spec changes (new talent group)
    -- Register a local event frame to detect spec changes and rebuild the preview
    do
        local specChangeFrame = CreateFrame("Frame")
        specChangeFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        specChangeFrame:SetScript("OnEvent", function(self, event)
            if event == "ACTIVE_TALENT_GROUP_CHANGED" and _barsHeaderBuilder then
                activePreview = nil
                if EllesmereUI:IsShown() and EllesmereUI:GetActiveModule() == "EllesmereUIActionBars" then
                    EllesmereUI:SetContentHeader(_barsHeaderBuilder)
                    UpdatePreviewAndResize()
                end
            end
        end)
    end




    --- Build (or rebuild for a different bar) the live preview frame.
    --- Reads numButtonsShowable from Blizzard's bar frame to only show the
    --- buttons the user has enabled in Edit Mode, and reads GetWidth/GetHeight
    --- from the first real button to match Blizzard's configured icon size.
    --- @param parent  Frame   scrollChild content parent
    --- @param yOff    number  current y offset in the page layout
    --- @return number height consumed by the preview
    local function BuildLivePreview(parent, yOff)
        local barKey  = SelectedKey()
        local barInfo = BAR_LOOKUP[barKey]
        -- Skip visibility-only / data bars (no button count). Custom bars
        -- (Bar9/Bar10) have a count but no native buttonPrefix, so key the guard
        -- off count -- they render from our own EABButtons like any action bar.
        if not barInfo or not barInfo.count then
            activePreview = nil
            return 0
        end

        local PAD      = EllesmereUI.CONTENT_PAD
        local maxBtns  = barInfo.count   -- always 12, used for pre-allocation

        -- Our custom bar frame (may be nil during first build before bars are created)
        local barFrame = _G["EABBar_" .. barKey]

        -- Read the real button size from the first actual button.
        -- Round to nearest integer to eliminate floating-point noise.
        local btn1 = FirstBarButton(barKey)
        local realBtnW = math.floor((btn1 and btn1:GetWidth() or 0) + 0.5)
        local realBtnH = math.floor((btn1 and btn1:GetHeight() or 0) + 0.5)
        if realBtnW < 1 then realBtnW = 36 end
        if realBtnH < 1 then realBtnH = 36 end

        -- With custom bars, there's no Blizzard Edit Mode scale factor.
        -- Our bar scale is applied directly to the bar frame.
        local blizzEditScale = 1

        local baseBtnW = realBtnW
        local baseBtnH = realBtnH

        -- Initial height estimate (will be recalculated in Update)
        local initH = baseBtnH + 20

        local pf = CreateFrame("Frame", nil, parent)
        -- Scale the preview so it matches real action bar size on screen.
        local previewScale = UIParent:GetEffectiveScale() / parent:GetEffectiveScale()
        pf:SetScale(previewScale)
        local localParentW = (parent:GetWidth() - PAD * 2) / previewScale
        PP.Size(pf, localParentW, initH)

        -- Max visible height for the preview area (in parent-space pixels)
        local PREVIEW_MAX_H = 200

        -- Wrapper frame at parent scale; holds the scroll frame and scrollbar
        local wrapper = CreateFrame("Frame", nil, parent)
        wrapper:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, yOff)
        wrapper:SetSize(parent:GetWidth() - PAD * 2, PREVIEW_MAX_H)
        wrapper:SetClipsChildren(true)

        local sf = CreateFrame("ScrollFrame", nil, wrapper)
        sf:SetAllPoints()
        sf:SetScrollChild(pf)
        sf:EnableMouseWheel(true)

        -- Thin scrollbar track (4px, right side)
        local pvTrack = CreateFrame("Frame", nil, wrapper)
        pvTrack:SetWidth(4)
        pvTrack:SetPoint("TOPRIGHT", wrapper, "TOPRIGHT", -2, -2)
        pvTrack:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", -2, 2)
        pvTrack:SetFrameLevel(wrapper:GetFrameLevel() + 5)
        do
            local bg = pvTrack:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.02)
        end
        pvTrack:Hide()

        local pvThumb = CreateFrame("Button", nil, pvTrack)
        pvThumb:SetWidth(4)
        pvThumb:SetFrameLevel(pvTrack:GetFrameLevel() + 1)
        pvThumb:EnableMouse(true)
        pvThumb:RegisterForDrag("LeftButton")
        pvThumb:SetScript("OnDragStart", function() end)
        pvThumb:SetScript("OnDragStop", function() end)
        do
            local t = pvThumb:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetColorTexture(1, 1, 1, 0.27)
        end

        -- Smooth scroll state
        local pvScrollTarget = 0
        local pvSmoothing = false
        local PV_SCROLL_STEP = 40
        local PV_SMOOTH_SPEED = 12
        local pvSmoothFrame = CreateFrame("Frame")
        pvSmoothFrame:Hide()

        local function UpdatePVThumb()
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            if maxScroll <= 0 then pvTrack:Hide(); return end
            pvTrack:Show()
            local trackH = pvTrack:GetHeight()
            local visH = sf:GetHeight()
            local ratio = visH / (visH + maxScroll)
            local thumbH = math.max(20, trackH * ratio)
            pvThumb:SetHeight(thumbH)
            local curScroll = 0
            do
                local ok, val = pcall(sf.GetVerticalScroll, sf)
                if ok and val then
                    local ok2, n = pcall(tonumber, val)
                    if ok2 and n then curScroll = n end
                end
            end
            local scrollRatio = curScroll / maxScroll
            local maxTravel = trackH - thumbH
            pvThumb:ClearAllPoints()
            pvThumb:SetPoint("TOP", pvTrack, "TOP", 0, -(scrollRatio * maxTravel))
        end

        pvSmoothFrame:SetScript("OnUpdate", function(_, elapsed)
            local cur = sf:GetVerticalScroll()
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            pvScrollTarget = math.max(0, math.min(maxScroll, pvScrollTarget))
            local diff = pvScrollTarget - cur
            if math.abs(diff) < 0.3 then
                sf:SetVerticalScroll(pvScrollTarget)
                UpdatePVThumb()
                pvSmoothing = false
                pvSmoothFrame:Hide()
                return
            end
            local newScroll = cur + diff * math.min(1, PV_SMOOTH_SPEED * elapsed)
            newScroll = math.max(0, math.min(maxScroll, newScroll))
            sf:SetVerticalScroll(newScroll)
            UpdatePVThumb()
        end)

        local function PVSmoothScrollTo(target)
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            pvScrollTarget = math.max(0, math.min(maxScroll, target))
            if not pvSmoothing then
                pvSmoothing = true
                pvSmoothFrame:Show()
            end
        end

        sf:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = EllesmereUI.SafeScrollRange(self)
            if maxScroll <= 0 then return end
            local base = pvSmoothing and pvScrollTarget or self:GetVerticalScroll()
            PVSmoothScrollTo(base - delta * PV_SCROLL_STEP)
        end)
        sf:SetScript("OnScrollRangeChanged", UpdatePVThumb)

        -- Thumb drag
        pvThumb:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            pvSmoothing = false
            pvSmoothFrame:Hide()
            local _, cursorY = GetCursorPosition()
            local dragStartY = cursorY / self:GetEffectiveScale()
            local dragStartScroll = sf:GetVerticalScroll()
            self:SetScript("OnUpdate", function(self2)
                if not IsMouseButtonDown("LeftButton") then
                    self2:SetScript("OnUpdate", nil)
                    return
                end
                local _, cy = GetCursorPosition()
                cy = cy / self2:GetEffectiveScale()
                local deltaY = dragStartY - cy
                local trackH = pvTrack:GetHeight()
                local maxTravel = trackH - self2:GetHeight()
                if maxTravel <= 0 then return end
                local maxScroll = EllesmereUI.SafeScrollRange(sf)
                local newScroll = math.max(0, math.min(maxScroll,
                    dragStartScroll + (deltaY / maxTravel) * maxScroll))
                pvScrollTarget = newScroll
                sf:SetVerticalScroll(newScroll)
                UpdatePVThumb()
            end)
        end)
        pvThumb:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            self:SetScript("OnUpdate", nil)
        end)

        -- Store refs for height management after Update()
        pf._wrapper = wrapper
        pf._scrollFrame = sf
        pf._previewScale = previewScale
        pf._PREVIEW_MAX_H = PREVIEW_MAX_H
        pf._updatePVThumb = UpdatePVThumb

        -- Pixel-snap helper for the preview's effective scale
        local function Snap(val)
            return EllesmereUI.PP.SnapForES(val, pf:GetEffectiveScale())
        end

        -- Scale-aware snap: snaps val to whole physical pixels at the preview's
        -- effective scale. Uses the same approach as the border system.
        local function SnapS(val)
            local es = pf:GetEffectiveScale()
            return EllesmereUI.PP.SnapForES(val, es)
        end

        -- Disable WoW's automatic pixel snapping on a texture
        local function UnsnapTex(tex)
            if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0) end
        end

        -- Pre-create per-button sub-frames and textures -----------------------
        -- We allocate for all 12, then show/hide based on numButtonsShowable
        local buttons = {}
        local DEFAULT_FONT = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("actionBars"))
            or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

        for i = 1, maxBtns do
            local bf = CreateFrame("Frame", nil, pf)
            bf:SetSize(baseBtnW, baseBtnH)
            bf:Hide()

            local icon = bf:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetColorTexture(0.06, 0.08, 0.10, 1)

            local bT = bf:CreateTexture(nil, "OVERLAY")
            local bB = bf:CreateTexture(nil, "OVERLAY")
            local bL = bf:CreateTexture(nil, "OVERLAY")
            local bR = bf:CreateTexture(nil, "OVERLAY")
            UnsnapTex(bT); UnsnapTex(bB); UnsnapTex(bL); UnsnapTex(bR)
            bT:Hide(); bB:Hide(); bL:Hide(); bR:Hide()

            -- Keybind text (top-right, mirrors real button HotKey position)
            local keybindFS = bf:CreateFontString(nil, "OVERLAY")
            EllesmereUI.ApplyIconTextFont(keybindFS, DEFAULT_FONT, 12, "actionBars")
            keybindFS:SetTextColor(1, 1, 1)
            keybindFS:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -1, -3)
            keybindFS:SetPoint("TOPLEFT", bf, "TOPLEFT", 4, -3)
            keybindFS:SetJustifyH("RIGHT")
            keybindFS:SetWordWrap(false)
            keybindFS:SetText("")

            -- Count / charges text (bottom-right, mirrors real button Count position)
            local countFS = bf:CreateFontString(nil, "OVERLAY")
            EllesmereUI.ApplyIconTextFont(countFS, DEFAULT_FONT, 12, "actionBars")
            countFS:SetTextColor(1, 1, 1)
            countFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 4)
            countFS:SetText("")

            -- Macro name text (bottom-center, mirrors real button Name position)
            local macroFS = bf:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(macroFS, false) end
            macroFS:SetFont(DEFAULT_FONT, 12, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
            macroFS:SetTextColor(1, 1, 1)
            macroFS:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", 1, 4)
            macroFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 4)
            macroFS:SetJustifyH("CENTER")
            macroFS:SetWordWrap(false)
            macroFS:SetText("")

            buttons[i] = {
                frame   = bf,
                icon    = icon,
                borders = { bT, bB, bL, bR },
                keybind = keybindFS,
                count   = countFS,
                macro   = macroFS,
            }
        end

        -- Preview background texture (behind all buttons)
        local previewBG = pf:CreateTexture(nil, "BACKGROUND", nil, -1)
        local previewBGBorder = CreateFrame("Frame", nil, pf, "BackdropTemplate")
        previewBGBorder:EnableMouse(false)
        previewBG:Hide()

        -- Store barFrame ref and base size for Update
        pf._barFrame  = barFrame
        pf._baseBtnW  = baseBtnW
        pf._baseBtnH  = baseBtnH
        pf._barInfo   = barInfo
        pf._blizzEditScale = blizzEditScale
        pf._buttons   = buttons
        pf._previewBG = previewBG

        -- The Update method reads current DB + Blizzard state, applies it --
        pf.Update = function(self)
            local settings = SB()
            if not settings then return end

            local info  = self._barInfo
            local bar   = self._barFrame
            local btnW  = self._baseBtnW
            local btnH  = self._baseBtnH

            -- Override with user-set button size from DB
            if settings.buttonWidth and settings.buttonWidth > 0 then
                btnW = settings.buttonWidth
            end
            if settings.buttonHeight and settings.buttonHeight > 0 then
                btnH = settings.buttonHeight
            end

            -- How many buttons are visible (from our DB settings)
            local numVisible = settings.overrideNumIcons or settings.numIcons or info.count
            if numVisible < 1 then numVisible = info.count end

            -- Stance bar: ignore icon count setting, use actual shapeshift form count
            if info.isStance then
                numVisible = GetNumShapeshiftForms() or info.count
                if numVisible < 1 then numVisible = info.count end
            end


            -- Multi-row layout: show all rows matching the real bar
            local numRows = settings.numRows or 1
            local ovRows = settings.overrideNumRows
            if ovRows and ovRows > 0 then numRows = ovRows end
            local stride = math.ceil(numVisible / numRows)
            numRows = math.ceil(numVisible / stride)
            local previewCount = numVisible
            -- Preview always shows all slots regardless of alwaysShowButtons setting
            local showEmpty = true

            local leftmost = 1
            -- Read settings
            local spacing   = settings.buttonPadding or 2
            -- Resolve border thickness from dropdown
            local resolvedBrdSize = ns.ResolveBorderThickness(settings)
            local brdOn     = resolvedBrdSize > 0
            local brdSize   = resolvedBrdSize
            local brdColor  = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 }
            local brdClassColor = settings.borderClassColor
            local zoom = ((settings.iconZoom or EAB.db.profile.iconZoom or 5.5)) / 100
            local square    = EAB.db.profile.squareIcons
            local hideKB    = settings.hideKeybind

            -- Font path (global setting)
            local fontPath  = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("actionBars")) or DEFAULT_FONT

            -- Font settings
            local kbSize    = settings.keybindFontSize or 12
            local kbColor   = settings.keybindFontColor or { r = 1, g = 1, b = 1 }
            local ctSize    = settings.countFontSize or 12
            local ctColor   = settings.countFontColor or { r = 1, g = 1, b = 1 }
            local hideMacro = settings.hideMacroText
            local mcSize    = settings.macroFontSize or 12
            local mcColor   = settings.macroFontColor or { r = 1, g = 1, b = 1 }

            -- Shape settings: derive from unified border system
            local btnShape = settings.buttonShape or "none"
            local shapeBrdOn = resolvedBrdSize > 0
            local shapeBrdColor = settings.shapeBorderColor or settings.borderColor or { r = 0, g = 0, b = 0, a = 1 }
            local shapeBrdSize = resolvedBrdSize
            local shapeBrdOpacity = (settings.shapeBorderOpacity or 100) / 100
            local shapeBrdR, shapeBrdG, shapeBrdB, shapeBrdA = shapeBrdColor.r, shapeBrdColor.g, shapeBrdColor.b, (shapeBrdColor.a or 1) * shapeBrdOpacity
            -- Unified class color
            local useClassColor = brdClassColor
            if useClassColor == nil then useClassColor = settings.shapeBorderClassColor end
            if useClassColor then
                local _, ct = UnitClass("player")
                if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then shapeBrdR, shapeBrdG, shapeBrdB = cc.r, cc.g, cc.b end end
            end

            local scaledBtnW = SnapS(btnW * (self._blizzEditScale or 1))
            local scaledBtnH = SnapS(btnH * (self._blizzEditScale or 1))
            -- Expand button size for custom shapes (mirrors SHAPE_BTN_EXPAND in main file)
            if btnShape ~= "none" and btnShape ~= "cropped" then
                local shapeExp = SnapS(ns.SHAPE_BTN_EXPAND * (self._blizzEditScale or 1))
                scaledBtnW = scaledBtnW + shapeExp
                scaledBtnH = scaledBtnH + shapeExp
            end
            -- Shrink button height for "cropped" mode (10% top + 10% bottom)
            if btnShape == "cropped" then
                scaledBtnH = SnapS(scaledBtnH * 0.80)
            end

            local scaledPad  = SnapS(spacing * (self._blizzEditScale or 1))

            -- Orientation
            local isVertical = (settings.orientation or "horizontal") == "vertical"

            -- Scale font sizes proportionally
            local totalScale = (self._blizzEditScale or 1)
            local scaledKBSize = math.max(6, floor(kbSize * totalScale + 0.5))
            local scaledCTSize = math.max(6, floor(ctSize * totalScale + 0.5))
            local scaledMCSize = math.max(6, floor(mcSize * totalScale + 0.5))

            -- Multi-row grid layout (vertical swaps cols/rows)
            -- For vertical: calculate actual columns used (not all numRows may be filled)
            local gridCols, gridRows
            if isVertical then
                gridCols = math.ceil(numVisible / stride)
                gridRows = stride
            else
                gridCols = stride
                gridRows = numRows
            end
            local gridW = gridCols * scaledBtnW + (gridCols - 1) * scaledPad
            local gridH = gridRows * scaledBtnH + (gridRows - 1) * scaledPad
            local gridStartX = Snap(math.max(0, (self:GetWidth() - gridW) / 2))

            -- Reserve room for a background that grows above/below the icon
            -- grid. The ScrollFrame clips outside its scroll child, so without
            -- this inset an upward-growing background loses its top border.
            local bgTopInset, bgBottomInset = 0, 0
            if settings.bgEnabled then
                local rawBgPadding = settings.bgPadding
                local bgSpacing = Snap((rawBgPadding ~= nil and rawBgPadding or (settings.bgPadY or 0)) * totalScale)
                local bgMultiplierY = math.max(1, math.min(4, math.floor((settings.bgMultiplierY or 1) + 0.5)))
                local bgIconPadding = Snap((settings.buttonPadding or 0) * totalScale)
                local bgGrowY = (bgMultiplierY - 1) * (gridH + bgIconPadding)
                if (settings.bgExpandDirectionY or "up") == "down" then
                    bgBottomInset = bgSpacing + bgGrowY
                else
                    bgTopInset = bgSpacing + bgGrowY
                end
            end

            -- Resize preview frame to fit all rows and background overflow.
            local frameH = Snap(gridH + 20 + bgTopInset + bgBottomInset)
            self:SetHeight(frameH)

            -- Resize wrapper to min(content, max) and toggle scrollbar
            local parentH = frameH * self._previewScale
            local maxH = self._PREVIEW_MAX_H
            if parentH > maxH then
                -- Add bottom padding so the last icon row is fully visible
                -- when scrolled to the bottom
                local paddedH = Snap(gridH + 20 + bgTopInset + bgBottomInset + scaledBtnH)
                self:SetHeight(paddedH)
                self._wrapper:SetHeight(maxH)
            else
                self._wrapper:SetHeight(parentH)
                -- Reset scroll when content fits without scrolling
                if self._scrollFrame then self._scrollFrame:SetVerticalScroll(0) end
            end
            if self._updatePVThumb then self._updatePVThumb() end

            -- Store grid bounds for background anchoring
            self._gridStartX = gridStartX
            self._gridStartY = -Snap(10) - bgTopInset
            self._gridW      = gridW
            self._gridH      = gridH

            local startY = self._gridStartY
            -- Match live layout: rows grow upward for "up" OR "center" (live
            -- lumps center with up for the icon grid; horizontal bars only ever
            -- store left/right/center, so a plain == "up" check never fired).
            local _gd = settings.growDirection or "up"
            local growUp = (_gd == "up" or _gd == "center")
            local colFlip, rowFlip, cornerFill = ns.GetOrderFlips(settings, isVertical, growUp)
            for i = 1, maxBtns do
                local entry = buttons[i]
                local bf    = entry.frame
                local icon  = entry.icon

                if i >= leftmost and i <= previewCount then
                    -- Multi-row: compute row and column for this button
                    local idx = i - leftmost  -- 0-based index
                    local col, row
                    if isVertical then
                        if cornerFill then
                            -- Corner modes fill across the columns first
                            -- (gridCols = column count), then wrap down.
                            col = idx % gridCols
                            row = math.floor(idx / gridCols)
                        else
                            col = math.floor(idx / stride)
                            row = idx % stride
                        end
                    else
                        col = idx % stride
                        row = math.floor(idx / stride)
                    end
                    -- dispCol/dispRow: visual position after icon order flips.
                    -- col keeps identifying the content column so the vertical
                    -- centering math below still measures the right buttons.
                    local dispCol, dispRow = col, row
                    if isVertical then
                        if colFlip then dispCol = gridCols - 1 - dispCol end
                        if rowFlip then dispRow = stride - 1 - dispRow end
                    else
                        if colFlip then dispCol = stride - 1 - dispCol end
                        if rowFlip then dispRow = numRows - 1 - dispRow end
                    end

                    local xOff, yOff
                    if isVertical then
                        -- Vertical: center each column vertically when last column is shorter
                        local countInCol
                        if cornerFill then
                            -- Row-major fill: column c holds every gridCols-th button.
                            countInCol = math.floor((previewCount - 1 - col) / gridCols) + 1
                        else
                            local colStart = col * stride + 1
                            local colEnd = math.min(colStart + stride - 1, previewCount)
                            countInCol = colEnd - colStart + 1
                        end
                        local colH = countInCol * scaledBtnH + (countInCol - 1) * scaledPad
                        local colOffY = Snap((gridH - colH) / 2)
                        xOff = Snap(gridStartX + dispCol * (scaledBtnW + scaledPad))
                        yOff = startY - colOffY - Snap(dispRow * (scaledBtnH + scaledPad))
                    else
                        -- Horizontal: left-align rows to match actual bar layout
                        xOff = Snap(gridStartX + dispCol * (scaledBtnW + scaledPad))
                        local displayRow = growUp and ((numRows - 1) - dispRow) or dispRow
                        yOff = startY - Snap(displayRow * (scaledBtnH + scaledPad))
                    end
                    bf:SetSize(scaledBtnW, scaledBtnH)
                    bf:ClearAllPoints()
                    bf:SetPoint("TOPLEFT", self, "TOPLEFT", xOff, yOff)
                    bf:Show()

                    -- Icon texture from our EABButton (not the hidden Blizzard button)
                    local eabBtns = ns.barButtons and ns.barButtons[info.key]
                    local realBtn = (eabBtns and eabBtns[i]) or (info.buttonPrefix and _G[info.buttonPrefix .. i])
                    local hasAction = realBtn and ns.ButtonHasAction(realBtn, info.buttonPrefix)
                    local iconTex = hasAction and realBtn.icon and realBtn.icon:GetTexture()

                    -- Always Show Buttons: when off, hide empty slots entirely
                    if not hasAction and not showEmpty then
                        bf:Hide()
                    else
                    if not iconTex then
                        icon:SetColorTexture(0, 0, 0, 0.5)
                        UnsnapTex(icon)
                        icon:SetTexCoord(0, 1, 0, 1)
                    else
                        icon:SetTexture(iconTex)
                        -- TexCoord (zoom / square / crop)
                        if square or zoom > 0 or btnShape == "cropped" then
                            local z = zoom
                            if btnShape == "cropped" then
                                -- Preserve aspect ratio: trim top/bottom by 10%
                                icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
                            else
                                icon:SetTexCoord(z, 1 - z, z, 1 - z)
                            end
                        else
                            icon:SetTexCoord(0, 1, 0, 1)
                        end
                    end

                    -- Borders
                    local bT, bB, bL, bR = entry.borders[1], entry.borders[2], entry.borders[3], entry.borders[4]
                    local brdTexKey = settings.borderTexture or "solid"
                    local brdIsSolid = (brdTexKey == "solid")

                    if brdOn and brdIsSolid then
                        -- Solid: 4 texture strips (original preview behavior)
                        local cr, cg, cb, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a
                        if useClassColor then
                            local _, ct2 = UnitClass("player")
                            if ct2 then local cc2 = RAID_CLASS_COLORS[ct2]; if cc2 then cr, cg, cb = cc2.r, cc2.g, cc2.b end end
                        end
                        local sz = SnapS(brdSize)

                        bT:SetColorTexture(cr, cg, cb, ca)
                        UnsnapTex(bT)
                        bT:SetHeight(sz)
                        bT:ClearAllPoints()
                        PP.Point(bT, "TOPLEFT", bf, "TOPLEFT", 0, 0)
                        PP.Point(bT, "TOPRIGHT", bf, "TOPRIGHT", 0, 0)
                        bT:Show()

                        bB:SetColorTexture(cr, cg, cb, ca)
                        UnsnapTex(bB)
                        bB:SetHeight(sz)
                        bB:ClearAllPoints()
                        PP.Point(bB, "BOTTOMLEFT", bf, "BOTTOMLEFT", 0, 0)
                        PP.Point(bB, "BOTTOMRIGHT", bf, "BOTTOMRIGHT", 0, 0)
                        bB:Show()

                        bL:SetColorTexture(cr, cg, cb, ca)
                        UnsnapTex(bL)
                        bL:SetWidth(sz)
                        bL:ClearAllPoints()
                        PP.Point(bL, "TOPLEFT", bT, "BOTTOMLEFT", 0, 0)
                        PP.Point(bL, "BOTTOMLEFT", bB, "TOPLEFT", 0, 0)
                        bL:Show()

                        bR:SetColorTexture(cr, cg, cb, ca)
                        UnsnapTex(bR)
                        bR:SetWidth(sz)
                        bR:ClearAllPoints()
                        PP.Point(bR, "TOPRIGHT", bT, "BOTTOMRIGHT", 0, 0)
                        PP.Point(bR, "BOTTOMRIGHT", bB, "TOPRIGHT", 0, 0)
                        bR:Show()

                        if entry._bdPreview then entry._bdPreview:Hide() end
                    elseif brdOn and not brdIsSolid then
                        -- Textured: BackdropTemplate on preview button
                        bT:Hide(); bB:Hide(); bL:Hide(); bR:Hide()
                        if not entry._bdPreview then
                            entry._bdPreview = CreateFrame("Frame", nil, bf, "BackdropTemplate")
                            entry._bdPreview:EnableMouse(false)
                        end
                        local bdPv = entry._bdPreview
                        local EDGE_MAP = { 12, 16, 24, 32 }
                        local edgeSize = EDGE_MAP[brdSize] or 12
                        local thKey = settings.borderThickness or "thin"
                        local dox, doy, dsx, dsy = EllesmereUI.GetBorderDefaults("actionbars", brdTexKey, thKey)
                        local adjX = settings.borderTextureOffset or dox
                        local adjY = settings.borderTextureOffsetY or doy
                        local offX, offY
                        if EllesmereUI.BorderTextureUsesScaleOffset(brdTexKey) then
                            offX = (edgeSize / 2) + adjX
                            offY = (edgeSize / 2) + adjY
                        else
                            offX = adjX
                            offY = adjY
                        end
                        local sx = settings.borderTextureShiftX or dsx
                        local sy = settings.borderTextureShiftY or dsy
                        bdPv:ClearAllPoints()
                        bdPv:SetPoint("TOPLEFT", bf, "TOPLEFT", -offX + sx, offY + sy)
                        bdPv:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", offX + sx, -offY + sy)
                        if settings.borderBehind then
                            bdPv:SetFrameLevel(math.max(0, bf:GetFrameLevel() - 1))
                        else
                            bdPv:SetFrameLevel(bf:GetFrameLevel() + 2)
                        end
                        local texPath = EllesmereUI.ResolveBorderTexture(brdTexKey)
                        if texPath then
                            bdPv:SetBackdrop({
                                edgeFile = texPath,
                                edgeSize = edgeSize,
                                insets = { left = 0, right = 0, top = 0, bottom = 0 },
                            })
                            local cr, cg, cb, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
                            if useClassColor then
                                local _, ct2 = UnitClass("player")
                                if ct2 then local cc2 = RAID_CLASS_COLORS[ct2]; if cc2 then cr, cg, cb = cc2.r, cc2.g, cc2.b end end
                            end
                            bdPv:SetBackdropBorderColor(cr, cg, cb, ca)
                            bdPv:Show()
                        end
                    else
                        bT:Hide(); bB:Hide(); bL:Hide(); bR:Hide()
                        if entry._bdPreview then entry._bdPreview:Hide() end
                    end


                    -- Button Shape mask + border
                    local SHAPE_MASKS = ns.SHAPE_MASKS
                    local SHAPE_BORDERS = ns.SHAPE_BORDERS
                    if btnShape ~= "none" and btnShape ~= "cropped" and SHAPE_MASKS and SHAPE_MASKS[btnShape] then
                        if not entry.shapeMask then
                            entry.shapeMask = bf:CreateMaskTexture()
                            entry.shapeMask:SetAllPoints(bf)
                        end
                        entry.shapeMask:SetTexture(SHAPE_MASKS[btnShape], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                        entry.shapeMask:Show()
                        if entry._prevMasked then pcall(icon.RemoveMaskTexture, icon, entry.shapeMask) end
                        icon:AddMaskTexture(entry.shapeMask)
                        entry._prevMasked = true
                        -- Expand icon beyond bf for SHAPE_ICON_EXPAND (icon only, NOT mask)
                        local SHAPE_ICON_EXPAND_OFFSETS = { circle=2, csquare=4, diamond=2, hexagon=4, portrait=2, shield=2, square=4 }
                        local shapeOffset = SHAPE_ICON_EXPAND_OFFSETS[btnShape] or 0
                        local shapeDefault = (ns.SHAPE_ZOOM_DEFAULTS and ns.SHAPE_ZOOM_DEFAULTS[btnShape] or 6.0) / 100
                        local iconExp = ns.SHAPE_ICON_EXPAND + shapeOffset + (zoom - shapeDefault) * 200
                        if iconExp < 0 then iconExp = 0 end
                        local halfIE = iconExp / 2
                        icon:ClearAllPoints()
                        PP.Point(icon, "TOPLEFT", bf, "TOPLEFT", -halfIE, halfIE)
                        PP.Point(icon, "BOTTOMRIGHT", bf, "BOTTOMRIGHT", halfIE, -halfIE)
                        -- Mask: inset 1px when border is on (matches unit frames)
                        entry.shapeMask:ClearAllPoints()
                        if shapeBrdSize >= 1 then
                            PP.Point(entry.shapeMask, "TOPLEFT", bf, "TOPLEFT", 1, -1)
                            PP.Point(entry.shapeMask, "BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 1)
                        else
                            entry.shapeMask:SetAllPoints(bf)
                        end
                        -- Expand texcoords to fill mask opening
                        local SHAPE_INSETS = { circle=17, csquare=17, diamond=14, hexagon=17, portrait=17, shield=13, square=17 }
                        local insetPx = SHAPE_INSETS[btnShape] or 17
                        local visRatio = (128 - 2 * insetPx) / 128
                        local expand = ((1 / visRatio) - 1) * 0.5
                        icon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand)
                        -- Hide square borders, show shape border
                        bT:Hide(); bB:Hide(); bL:Hide(); bR:Hide()
                        if not entry.shapeBorderTex then
                            entry.shapeBorderTex = bf:CreateTexture(nil, "OVERLAY", nil, 6)
                        end
                        -- No mask on border — just render at button frame size
                        pcall(entry.shapeBorderTex.RemoveMaskTexture, entry.shapeBorderTex, entry.shapeMask)
                        entry.shapeBorderTex:ClearAllPoints()
                        entry.shapeBorderTex:SetAllPoints(bf)
                        if shapeBrdOn and SHAPE_BORDERS[btnShape] then
                            entry.shapeBorderTex:SetTexture(SHAPE_BORDERS[btnShape])
                            entry.shapeBorderTex:SetVertexColor(shapeBrdR, shapeBrdG, shapeBrdB, shapeBrdA)
                            entry.shapeBorderTex:Show()
                        else
                            entry.shapeBorderTex:Hide()
                        end
                    else
                        -- None/Cropped: remove mask if previously applied
                        if entry.shapeMask and entry._prevMasked then
                            pcall(icon.RemoveMaskTexture, icon, entry.shapeMask)
                            entry.shapeMask:Hide()
                            entry._prevMasked = false
                        end
                        if entry.shapeBorderTex then entry.shapeBorderTex:Hide() end
                        -- Restore icon to fill bf
                        icon:ClearAllPoints()
                        icon:SetAllPoints(bf)
                        -- Set texcoords: cropped trims 15% top/bottom, none uses zoom only
                        if icon.SetTexCoord then
                            local z = zoom
                            if btnShape == "cropped" then
                                icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
                            else
                                if z > 0 or square then
                                    icon:SetTexCoord(z, 1 - z, z, 1 - z)
                                else
                                    icon:SetTexCoord(0, 1, 0, 1)
                                end
                            end
                        end
                    end
                    -- Keybind text
                    local keybindFS = entry.keybind
                    if hideKB then
                        keybindFS:SetText("")
                    else
                        local hkText = ""
                        if realBtn and realBtn.HotKey then
                            hkText = realBtn.HotKey:GetText() or ""
                            if hkText == RANGE_INDICATOR or hkText == "\226\128\162" then
                                hkText = ""
                            end
                        end
                        keybindFS:SetText(hkText)
                    end
                    EllesmereUI.ApplyIconTextFont(keybindFS, fontPath, scaledKBSize, "actionBars")
                    keybindFS:SetTextColor(kbColor.r, kbColor.g, kbColor.b)
                    -- Apply keybind X/Y offsets
                    local kbOX = (settings.keybindOffsetX or 0) * totalScale
                    local kbOY = (settings.keybindOffsetY or 0) * totalScale
                    keybindFS:ClearAllPoints()
                    keybindFS:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -1 + kbOX, -3 + kbOY)
                    keybindFS:SetPoint("TOPLEFT", bf, "TOPLEFT", 4 + kbOX, -3 + kbOY)
                    keybindFS:SetJustifyH("RIGHT")

                    -- Count / charges text
                    local countFS = entry.count
                    do
                        local ctText = ""
                        if realBtn and realBtn.Count then
                            ctText = realBtn.Count:GetText() or ""
                        end
                        countFS:SetText(ctText)
                    end
                    EllesmereUI.ApplyIconTextFont(countFS, fontPath, scaledCTSize, "actionBars")
                    countFS:SetTextColor(ctColor.r, ctColor.g, ctColor.b)
                    -- Apply charges X/Y offsets
                    local ctOX = (settings.countOffsetX or 0) * totalScale
                    local ctOY = (settings.countOffsetY or 0) * totalScale
                    countFS:ClearAllPoints()
                    countFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1 + ctOX, 4 + ctOY)

                    -- Macro name text
                    local macroFS = entry.macro
                    if macroFS then
                        if hideMacro then
                            macroFS:SetText("")
                        else
                            local mcText = ""
                            if realBtn and realBtn.Name then
                                mcText = realBtn.Name:GetText() or ""
                            end
                            macroFS:SetText(mcText)
                        end
                        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(macroFS, false) end
                        macroFS:SetFont(fontPath, scaledMCSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
                        macroFS:SetTextColor(mcColor.r, mcColor.g, mcColor.b)
                        local mcOX = (settings.macroOffsetX or 0) * totalScale
                        local mcOY = (settings.macroOffsetY or 0) * totalScale
                        macroFS:ClearAllPoints()
                        macroFS:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", 1 + mcOX, 4 + mcOY)
                        macroFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1 + mcOX, 4 + mcOY)
                        macroFS:SetJustifyH("CENTER")
                    end
                    end -- close alwaysShowButtons else
                else
                    -- Button beyond numButtonsShowable hide it
                    bf:Hide()
                end
            end

            -- Preview background
            if settings.bgEnabled then
                local bgC = settings.bgColor or { r = 0, g = 0, b = 0, a = 0.5 }
                local bgAlpha = settings.bgOpacity ~= nil and settings.bgOpacity / 100 or bgC.a
                previewBG:SetColorTexture(bgC.r, bgC.g, bgC.b, bgAlpha)
                local rawPadding = settings.bgPadding
                local extraX = Snap((rawPadding ~= nil and rawPadding or (settings.bgPadX or 0)) * totalScale)
                local extraY = Snap((rawPadding ~= nil and rawPadding or (settings.bgPadY or 0)) * totalScale)
                -- Anchor to the full grid bounds (not individual buttons) so multi-row
                -- backgrounds cover the entire grid even when the last row is shorter.
                local gx = self._gridStartX or 0
                local gw = self._gridW or 0
                local gh = self._gridH or 0
                local gy = self._gridStartY or -Snap(10)
                previewBG:ClearAllPoints()
                local left, right = gx - extraX, gx + gw + extraX
                local top, bottom = gy + extraY, gy - gh - extraY
                local multiplierX = math.max(1, math.min(4, math.floor((settings.bgMultiplierX or 1) + 0.5)))
                local multiplierY = math.max(1, math.min(4, math.floor((settings.bgMultiplierY or 1) + 0.5)))
                local directionX = settings.bgExpandDirectionX or "right"
                local directionY = settings.bgExpandDirectionY or "up"
                local iconPadding = Snap((settings.buttonPadding or 0) * totalScale)
                local growX = (multiplierX - 1) * (gw + iconPadding)
                local growY = (multiplierY - 1) * (gh + iconPadding)
                if directionX == "left" then left = left - growX else right = right + growX end
                if directionY == "down" then bottom = bottom - growY else top = top + growY end
                previewBG:SetPoint("TOPLEFT", self, "TOPLEFT", left, top)
                previewBG:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", right, bottom)
                previewBG:Show()
                previewBGBorder:SetFrameLevel(settings.bgBorderBehind
                    and math.max(0, self:GetFrameLevel() - 1) or self:GetFrameLevel())
                previewBGBorder:ClearAllPoints()
                previewBGBorder:SetAllPoints(previewBG)
                if EllesmereUI.ApplyBorderStyle then
                    local bc = settings.bgBorderColor or { r = 0, g = 0, b = 0, a = 1 }
                    local thicknessKey = settings.bgBorderThickness or "none"
                    local thickness = ns.BORDER_THICKNESS and ns.BORDER_THICKNESS[thicknessKey]
                    local borderSize = thickness and thickness.regular or 0
                    EllesmereUI.ApplyBorderStyle(previewBGBorder, borderSize,
                        bc.r, bc.g, bc.b, bc.a or 1, settings.bgBorderTexture or "solid",
                        settings.bgBorderOffsetX, settings.bgBorderOffsetY,
                        settings.bgBorderShiftX, settings.bgBorderShiftY,
                        "actionbars", thicknessKey)
                end
            else
                previewBG:Hide()
                if EllesmereUI.ApplyBorderStyle then
                    EllesmereUI.ApplyBorderStyle(previewBGBorder, 0, 0, 0, 0, settings.bgBorderTexture or "solid")
                else
                    previewBGBorder:Hide()
                end
            end

            -- Apply bar opacity to the preview
            -- When mouseover fade is active, the bar is fully visible on hover,
            -- so preview should show full opacity rather than the fade-out alpha.
            local barAlpha = settings.mouseoverEnabled and 1 or (settings.mouseoverAlpha or 1)
            self:SetAlpha(barAlpha)

            -- Refresh text overlay sizes (font/text may have changed)
            if self._textOverlays then
                for _, ov in ipairs(self._textOverlays) do
                    if ov._resizeToText then ov._resizeToText() end
                end
            end
        end

        -- Apply initial state immediately
        pf:Update()

        -- Return the actual computed height (converted to parent-space)
        activePreview = pf
        EllesmereUI._contentHeaderPreview = pf
        return pf._wrapper:GetHeight()
    end

    ---------------------------------------------------------------------------
    --  Short labels for sync icon multi-apply
    ---------------------------------------------------------------------------
    local SHORT_LABELS = {
        MainBar  = "Bar 1",
        Bar2     = "Bar 2",
        Bar3     = "Bar 3",
        Bar4     = "Bar 4",
        Bar5     = "Bar 5",
        Bar6     = "Bar 6",
        Bar7     = "Bar 7",
        Bar8     = "Bar 8",
        StanceBar = "Stance",
        PetBar   = "Pet",
        MicroBar = "Micro",
        BagBar   = "Bags",
        XPBar    = "XP",
        RepBar   = "Rep",
        FavorBar = "Favor",
    }

    -- Spec Overrides capture: report which bar is selected so captured
    -- entries are labeled with their element ("Action Bars > Bar 1 > ...").
    if EllesmereUI.RegisterCaptureContext then
        EllesmereUI.RegisterCaptureContext("EllesmereUIActionBars", function()
            local key = SelectedKey()
            return SHORT_LABELS[key] or key
        end)
    end

    -- Keep the legacy boolean flags and the newer visibility-mode dropdown in
    -- sync. The runtime still reads both shapes in different code paths.
    local function GetVisibilityKey(s)
        if not VisibilityCompat then
            return s.barVisibility or "always"
        end
        return VisibilityCompat.Normalize(s)
    end

    local function ApplyVisibilityKey(s, v)
        if VisibilityCompat then
            VisibilityCompat.ApplyMode(s, v)
            return
        end

        s.barVisibility = v
        s.alwaysHidden = (v == "never")

        local wasMouseover = s.mouseoverEnabled
        s.mouseoverEnabled = (v == "mouseover")
        if v == "mouseover" then
            if not wasMouseover then
                s._savedBarAlpha = s.mouseoverAlpha or 1
            end
            s.mouseoverAlpha = 0
        elseif wasMouseover and s._savedBarAlpha then
            s.mouseoverAlpha = s._savedBarAlpha
            s._savedBarAlpha = nil
        end

        s.combatHideEnabled = (v == "out_of_combat")
        s.combatShowEnabled = (v == "in_combat")
    end

    local function CopyVisibilitySettings(dst, src, dstKey)
        if VisibilityCompat then
            -- Pet Bar structurally ignores group modes: strip them from a
            -- copied multi-selection so its stored set stays honest.
            VisibilityCompat.Copy(dst, src, dstKey == "PetBar")
            return
        end

        local v = src.barVisibility or "always"
        dst.barVisibility = v
        dst.alwaysHidden = src.alwaysHidden
        dst.mouseoverEnabled = src.mouseoverEnabled
        dst.mouseoverAlpha = src.mouseoverAlpha
        dst._savedBarAlpha = src._savedBarAlpha
        dst.combatHideEnabled = src.combatHideEnabled
        dst.combatShowEnabled = src.combatShowEnabled
        dst.dragShow = src.dragShow
    end




    ---------------------------------------------------------------------------
    --  Unified bar settings builder
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    --  Menu, Bags & XP Bars page  (dedicated tab)
    ---------------------------------------------------------------------------
    local function BuildMenuBagsXPPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        -- Global settings page, no bar selector header
        EllesmereUI:ClearContentHeader()
        parent._showRowDivider = true

        local BLIZZ_DIS_TIP = "This option does not work with Blizzard Bars. Please use Blizzard Edit Mode."
        local function _blizzDis() return EAB.db.profile.useBlizzardDataBars end

        -- Shared visibility row: left vis dropdown + right "Visibility Options" checkbox dropdown
        -- trackNeverFlip: data-bar sections hide their dependent rows while the
        -- bar's visibility is Never, so a Never <-> not-Never flip must force a
        -- full page rebuild. The baseline is captured at build time; a flip
        -- rebuilds the page, which recreates this closure with a fresh baseline.
        local function BarIsNever(barKey)
            local s = EAB.db.profile.bars[barKey]
            if not s then return false end
            GetVisibilityKey(s) -- normalize legacy booleans into barVisibility
            return s.barVisibility == "never" or s.alwaysHidden == true
        end
        local function BuildVisRow(barKey, leftLabel, disabledFn, disTip, trackNeverFlip)
            local wasNever = trackNeverFlip and BarIsNever(barKey)
            local visRow, visH = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
                { getStore = function()
                      local s = EAB.db.profile.bars[barKey]
                      -- Normalize first: extra-bar defaults may carry only
                      -- the legacy booleans with no barVisibility key yet.
                      if s then GetVisibilityKey(s) end
                      return s
                  end,
                  legacyKey = "barVisibility",
                  label = leftLabel,
                  caps = { partyIncludesRaid = true, luaDragonriding = true },
                  applyScalarFn = function(s, mode) ApplyVisibilityKey(s, mode) end,
                  disabledFn = disabledFn, disabledTooltip = disTip, rawTooltip = disTip and true or nil,
                  onChanged = function()
                      EAB:RefreshRuntimeVisibility()
                      EAB:RefreshMouseover()
                      EAB:ApplyCombatVisibility()
                      if trackNeverFlip and BarIsNever(barKey) ~= wasNever then
                          EllesmereUI:RefreshPage(true)
                      end
                  end },
                { type="dropdown", text="Visibility Options",
                  values={ __placeholder = "..." }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end });  y = y - visH

            -- Replace the dummy right dropdown with checkbox dropdown
            local rightRgn = visRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local PP = EllesmereUI.PanelPP
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                EllesmereUI.VIS_OPT_ITEMS,
                function(k) return EAB.db.profile.bars[barKey][k] or false end,
                function(k, v)
                    EAB.db.profile.bars[barKey][k] = v
                    EAB:UpdateHousingVisibility()
                    EAB:ApplyCombatVisibility()
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

            return visRow
        end

        -------------------------------------------------------------------
        --  MICRO MENU & BAGS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "MICRO MENU & BAGS", y);  y = y - h
        BuildVisRow("MicroBar", "Micro Menu Visibility")
        BuildVisRow("BagBar",   "Bag Bar Visibility")

        _, h = W:Spacer(parent, y, 12);  y = y - h

        -------------------------------------------------------------------
        --  XP / REP BAR STYLE
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "XP/REP BAR STYLE", y);  y = y - h

        local orientValues = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }
        local orientOrder  = { "HORIZONTAL", "VERTICAL" }

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Use Blizzard's XP/Rep Bars",
              getValue=function() return EAB.db.profile.useBlizzardDataBars end,
              setValue=function(v)
                  EAB.db.profile.useBlizzardDataBars = v
                  if v then
                      for _, k in ipairs({"XPBar", "RepBar", "FavorBar"}) do
                          local frame = ns.dataBarFrames and ns.dataBarFrames[k]
                          if frame then
                              frame:Hide()
                              -- Runs the hidden path (Favor bar disarms its
                              -- events immediately).
                              if frame._updateFunc then frame._updateFunc() end
                          end
                      end
                      if StatusTrackingBarManager then
                          StatusTrackingBarManager:Show()
                          StatusTrackingBarManager:RegisterAllEvents()
                      end
                  else
                      local anyMissing = false
                      for _, k in ipairs({"XPBar", "RepBar", "FavorBar"}) do
                          local frame = ns.dataBarFrames and ns.dataBarFrames[k]
                          if frame then
                              local s = EAB.db.profile.bars[k]
                              if not s or not s.alwaysHidden then
                                  frame:Show()
                                  if frame._updateFunc then frame._updateFunc() end
                              end
                          else
                              anyMissing = true
                          end
                      end
                      if anyMissing then
                          print("|cff00ccffEllesmere:|r Reload required to create custom bars. Type /reload")
                      end
                      if StatusTrackingBarManager then
                          StatusTrackingBarManager:UnregisterAllEvents()
                          StatusTrackingBarManager:Hide()
                      end
                  end
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Orientation",
              values=orientValues, order=orientOrder,
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
              getValue=function()
                  return EAB.db.profile.bars["XPBar"] and EAB.db.profile.bars["XPBar"].orientation or "HORIZONTAL"
              end,
              setValue=function(v)
                  for _, k in ipairs({"XPBar", "RepBar", "FavorBar"}) do
                      if EAB.db.profile.bars[k] then
                          EAB.db.profile.bars[k].orientation = v
                          if ns.ApplyDataBarLayout then ns.ApplyDataBarLayout(k) end
                      end
                  end
              end });  y = y - h

        _, h = W:Spacer(parent, y, 12);  y = y - h

        -------------------------------------------------------------------
        --  EXPERIENCE BAR / REPUTATION BAR / HOUSE FAVOR BAR
        -------------------------------------------------------------------
        -- Shared bar-texture dropdown tables (built-ins + SharedMedia, with
        -- menu preview backgrounds -- same treatment as the nameplate Bar
        -- Texture dropdown).
        local dbTexValues, dbTexOrder = {}, {}
        do
            local names = ns.dataBarTextureNames or {}
            local lookup = ns.dataBarTextures or {}
            for _, key in ipairs(ns.dataBarTextureOrder or {}) do
                if key ~= "---" then dbTexValues[key] = names[key] or key end
                dbTexOrder[#dbTexOrder + 1] = key
            end
            dbTexValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    if not key or key == "---" or key == "none" then return nil end
                    if EllesmereUI.ResolveTexturePath then
                        return EllesmereUI.ResolveTexturePath(lookup, key, nil)
                    end
                    return lookup[key]
                end,
            }
        end
        -- Representative colors for the "Reactive (Default)" swatch.
        local REACTIVE_PREVIEW = {
            XPBar    = { 0.60, 0.40, 0.85 },
            RepBar   = { 0.30, 0.70, 0.25 },
            FavorBar = { 0.85, 0.64, 0.22 },
        }
        local function RefreshDataBar(bk)
            local f = ns.dataBarFrames and ns.dataBarFrames[bk]
            if f and f._updateFunc then f._updateFunc() end
        end

        local function BuildDataBarSection(barKey, sectionTitle, visLabel)
            local visRow, sizeRow
            local function S() return EAB.db.profile.bars[barKey] end

            _, h = W:SectionHeader(parent, sectionTitle, y);  y = y - h
            visRow = BuildVisRow(barKey, visLabel, _blizzDis, BLIZZ_DIS_TIP, true)

            -- The rows below are HIDDEN entirely while the bar's visibility
            -- is Never (BuildVisRow's trackNeverFlip rebuilds on the flip).
            if BarIsNever(barKey) then return visRow end

            local wDis, wTip, wRaw = EllesmereUI.MatchGuard(barKey, "Width", _blizzDis, BLIZZ_DIS_TIP)
            local hDis, hTip, hRaw = EllesmereUI.MatchGuard(barKey, "Height", _blizzDis, BLIZZ_DIS_TIP)
            sizeRow, h = W:DualRow(parent, y,
                { type="slider", text="Width", min=50, max=600, step=1,
                  disabled=wDis, disabledTooltip=wTip, rawTooltip=wRaw,
                  getValue=function() return S().width or 400 end,
                  setValue=function(v)
                      S().width = v
                      if ns.ApplyDataBarLayout then ns.ApplyDataBarLayout(barKey) end
                  end },
                { type="slider", text="Height", min=4, max=40, step=1,
                  disabled=hDis, disabledTooltip=hTip, rawTooltip=hRaw,
                  getValue=function() return S().height or 18 end,
                  setValue=function(v)
                      S().height = v
                      if ns.ApplyDataBarLayout then ns.ApplyDataBarLayout(barKey) end
                  end });  y = y - h

            -- Color mode (custom | accent | reactive) + bar texture.
            local rp = REACTIVE_PREVIEW[barKey] or { 1, 1, 1 }
            _, h = W:DualRow(parent, y,
                { type="multiSwatch", text="Color",
                  swatches = {
                      { tooltip = "Custom Color",
                        getValue = function()
                            local c = S().customColor
                            if c then return c.r or 1, c.g or 1, c.b or 1 end
                            return 1, 1, 1
                        end,
                        setValue = function(r, g, b)
                            S().customColor = { r = r, g = g, b = b }
                            S().colorMode = "custom"
                            RefreshDataBar(barKey)
                        end,
                        onClick = function(self)
                            if S().colorMode ~= "custom" then
                                S().colorMode = "custom"
                                RefreshDataBar(barKey)
                                EllesmereUI:RefreshPage()
                                return
                            end
                            if self._eabOrigClick then self._eabOrigClick(self) end
                        end,
                        refreshAlpha = function()
                            return S().colorMode == "custom" and 1 or 0.3
                        end },
                      { tooltip = "Accent Color",
                        getValue = function()
                            local EG = EllesmereUI.ELLESMERE_GREEN
                            if EG then return EG.r or 0.047, EG.g or 0.824, EG.b or 0.616 end
                            return 0.047, 0.824, 0.616
                        end,
                        setValue = function() end,
                        onClick = function()
                            S().colorMode = "accent"
                            RefreshDataBar(barKey)
                            EllesmereUI:RefreshPage()
                        end,
                        refreshAlpha = function()
                            return S().colorMode == "accent" and 1 or 0.3
                        end },
                      { tooltip = "Reactive (Default)",
                        getValue = function() return rp[1], rp[2], rp[3] end,
                        setValue = function() end,
                        onClick = function()
                            S().colorMode = nil
                            RefreshDataBar(barKey)
                            EllesmereUI:RefreshPage()
                        end,
                        refreshAlpha = function()
                            local m = S().colorMode
                            return (m ~= "custom" and m ~= "accent") and 1 or 0.3
                        end },
                  } },
                { type="dropdown", text="Bar Texture", values=dbTexValues, order=dbTexOrder,
                  disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP, rawTooltip=true,
                  getValue=function() return S().barTexture or "none" end,
                  setValue=function(v)
                      S().barTexture = v
                      if ns.ApplyDataBarLayout then ns.ApplyDataBarLayout(barKey) end
                  end });  y = y - h

            -- Click Through | (empty)
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Click Through",
                  tooltip="Mouse clicks pass through the bar. Disable to allow the mouseover tooltip.",
                  getValue=function() return S().clickThrough end,
                  setValue=function(v)
                      S().clickThrough = v
                      EAB:ApplyClickThroughForBar(barKey)
                  end },
                { type="label", text="" });  y = y - h

            return visRow, sizeRow
        end

        local xpBarRow = BuildDataBarSection("XPBar",  "EXPERIENCE BAR", "XP Bar Visibility")
        do
            local rgn = xpBarRow._leftRegion
            local _, xpCogShow = EllesmereUI.BuildCogPopup({
                title = "XP Bar Visibility",
                rows = {
                    { type="toggle", label="Show Raw Values",
                        get=function() return EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["XPBar"] and EAB.db.profile.bars["XPBar"].showRawValues end,
                        set=function(v)
                            EAB.db.profile.bars["XPBar"].showRawValues = v
                        end },
                    { type="toggle", label="Show Level",
                        get=function() return EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["XPBar"] and EAB.db.profile.bars["XPBar"].showLevel end,
                        set=function(v)
                            EAB.db.profile.bars["XPBar"].showLevel = v
                        end },
                },
            })
            local xpCtrl = rgn._control
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", xpCtrl or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) xpCogShow(self) end)
        end

        _, h = W:Spacer(parent, y, 12);  y = y - h
        BuildDataBarSection("RepBar", "REPUTATION BAR", "Rep Bar Visibility")
        _, h = W:Spacer(parent, y, 12);  y = y - h
        BuildDataBarSection("FavorBar", "HOUSE FAVOR BAR", "Favor Bar Visibility")

        return math.abs(y)
    end

    local function BuildSharedBarSettings(parent, y)
        local W = EllesmereUI.Widgets
        local _, h

        -- Scoped HERE, not shared with BuildMenuBagsXPPage's identically-named
        -- local: the Icon Size rows below referenced that other function's
        -- local, which resolved as a nil GLOBAL in this scope -- so the
        -- disabled-slider tooltip silently never showed (reported 8.5.1).
        local BLIZZ_DIS_TIP = "This option does not work with Blizzard Bars. Please use Blizzard Edit Mode."

        ---------------------------------------------------------------
        --  Unified Get / Set / DB abstraction
        ---------------------------------------------------------------
        local function SGet(key)
            return SB()[key]
        end
        local function SSet(key, val, applyFn)
            SB()[key] = val
            if applyFn then applyFn(SelectedKey()) end
            EllesmereUI:RefreshPage()
        end
        local function SDB()
            return SB()
        end
        local function SVal(key, default)
            local v = SB()[key]
            return v ~= nil and v or default
        end
        -- Apply to single bar
        local function SApplyAll(applyFn)
            applyFn(SelectedKey())
        end
        -- Set a color table
        local function SSetColor(key, r, g, b, a, applyFn)
            SB()[key] = { r=r, g=g, b=b, a=a }
            if applyFn then applyFn(SelectedKey()) end
            EllesmereUI:RefreshPage()
        end
        local function SUpdatePreview()
            UpdatePreview()
        end
        local function SUpdatePreviewAndResize()
            UpdatePreviewAndResize()
        end
        -- Helper: build a standard cog button
        local function MakeCogBtn(rgn, showFn, anchorTo, iconPath)
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", anchorTo or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(iconPath or EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) showFn(self) end)
            return cogBtn
        end

        parent._showRowDivider = true

        local visOnly = IsVisOnly()
        local row

        -- Row / section references for click-navigation
        local iconsSectionHeader, textSectionHeader
        local borderRow
        local keybindRow, chargesRow

        local function BgDisabled()
            return not SB().bgEnabled
        end

        -----------------------------------------------------------------------
        --  Bar 10 / Moonkin Form caution
        -----------------------------------------------------------------------
        -- Action page 10 (the slots Bar 10 displays) is the Druid Moonkin Form
        -- bonus bar, so a Druid editing Bar 10 also edits their Moonkin Form
        -- bar and vice versa. Surface that at the top of the page so it is not
        -- a surprise. Shown for all classes; the text self-qualifies to Druids.
        if SelectedKey() == "Bar10" then
            local PP = EllesmereUI.PanelPP
            local PAD = EllesmereUI.CONTENT_PAD
            local warnW = parent:GetWidth() - PAD * 2
            y = y - 5  -- 5px spacing above the caution
            local warnHost = CreateFrame("Frame", nil, parent)
            PP.Point(warnHost, "TOPLEFT", parent, "TOPLEFT", PAD, y)
            local warnFS = EllesmereUI.MakeFont(warnHost, 14, nil, 1, 0.82, 0)
            warnFS:SetWidth(warnW)
            warnFS:SetWordWrap(true)
            warnFS:SetJustifyH("CENTER")
            warnFS:SetPoint("TOPLEFT", warnHost, "TOPLEFT", 0, 0)
            warnFS:SetText(EllesmereUI.L("This Action Bar is also used as the Moonkin Form bar.\nChanging spells on a Druid for this bar will also change them on your Moonkin Form bar."))
            local warnH = math.ceil(warnFS:GetStringHeight()) + 4
            PP.Size(warnHost, warnW, warnH)
            y = y - (warnH + 12)
        end

        -----------------------------------------------------------------------
        --  VISIBILITY
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_VISIBILITY, y);  y = y - h

        -- Row 1: Bar Visibility (dropdown) | Visibility Options
        do
            local _visBlizzDis
            local _VIS_BLIZZ_TIP = "This option does not work with Blizzard Bars. Please use Blizzard Edit Mode."
            if IsDataBar() then
                _visBlizzDis = function() return EAB.db.profile.useBlizzardDataBars end
            end

            -- Pet Bar structurally cannot express group modes: lock them
            -- with an explanation instead of offering silent no-ops.
            local visCaps = { partyIncludesRaid = true }
            if SelectedKey() == "PetBar" then
                visCaps.noGroupModes = true
                visCaps.lockedTooltips = {
                    in_raid  = "The Pet Bar cannot use group-based visibility.",
                    in_party = "The Pet Bar cannot use group-based visibility.",
                    solo     = "The Pet Bar cannot use group-based visibility.",
                }
            end
            -- Data bars evaluate in Lua (non-secure), so their dragonriding
            -- items depend on the gliding edge event; the secure bars'
            -- drivers re-evaluate natively and never lock.
            if IsDataBar() then visCaps.luaDragonriding = true end

            local visRow1
            visRow1, h = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
                { getStore = function()
                      local s = SB()
                      GetVisibilityKey(s)
                      return s
                  end,
                  legacyKey = "barVisibility",
                  caps = visCaps,
                  applyScalarFn = function(s, mode) ApplyVisibilityKey(s, mode) end,
                  disabledFn = _visBlizzDis, disabledTooltip = _visBlizzDis and _VIS_BLIZZ_TIP or nil,
                  rawTooltip = true,
                  onChanged = function()
                      if EAB.ClearVisToggleOverride then EAB:ClearVisToggleOverride(SelectedKey()) end
                      if EAB.RebuildVisToggleBindings then EAB:RebuildVisToggleBindings() end
                      EAB:RefreshRuntimeVisibility()
                      EAB:RefreshMouseover()
                      EAB:ApplyCombatVisibility()
                  end },
                { type="dropdown", text="Visibility Options",
                  values={ __placeholder = "..." }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end });  y = y - h

            -- Replace the dummy right dropdown with checkbox dropdown
            do
                local rightRgn = visRow1._rightRegion
                if rightRgn._control then rightRgn._control:Hide() end
                local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                    EllesmereUI.VIS_OPT_ITEMS,
                    function(k) return SB()[k] or false end,
                    function(k, v)
                        SB()[k] = v
                        EAB:UpdateHousingVisibility()
                        EAB:ApplyCombatVisibility()
                        EllesmereUI:RefreshPage()
                    end)
                PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
                rightRgn._control = cbDD
                rightRgn._lastInline = nil
                EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
            end
            -- Sync icon: Visibility (left region)
            do
                local rgn = visRow1._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Visibility to all Bars",
                    onClick = function()
                        local src = SB()
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local dst = EAB.db.profile.bars[key]
                            CopyVisibilitySettings(dst, src, key)
                        end
                        EAB:RefreshRuntimeVisibility()
                        EAB:RefreshMouseover()
                        EAB:ApplyCombatVisibility()
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local src = SB()
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local dst = EAB.db.profile.bars[key]
                            if not EllesmereUI.VisSelectionEquals(src, "barVisibility", dst, "barVisibility") then return false end
                            if (src.dragShow or false) ~= (dst.dragShow or false) then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local src = SB()
                            for _, key in ipairs(checkedKeys) do
                                local dst = EAB.db.profile.bars[key]
                                CopyVisibilitySettings(dst, src, key)
                            end
                            EAB:RefreshRuntimeVisibility()
                            EAB:RefreshMouseover()
                            EAB:ApplyCombatVisibility()
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            -- Inline cog: Visibility settings (left region)
            do
                local rgn = visRow1._leftRegion
                local function MORow()
                    return { type="toggle", label="Show All on Mouseover",
                      tooltip="When hovering any action bar set to Mouseover, all Mouseover bars will appear.",
                      get=function() return EAB.db.profile.mouseoverShowAll or false end,
                      set=function(v)
                          EAB.db.profile.mouseoverShowAll = v
                      end }
                end
                -- Per-bar Show During Drag: only offered while THIS bar's
                -- visibility is Never (every other mode already surfaces
                -- during a drag). Two prebuilt popups; the cog opens the one
                -- matching the selected bar's current mode, so the row
                -- appears/disappears live with no page rebuild on visibility
                -- or bar-selection changes.
                local function DragRow()
                    return { type="toggle", label="Show During Drag",
                      tooltip="While dragging a spell or item, this bar appears so you can drop onto it.",
                      get=function() return SB().dragShow == true end,
                      set=function(v) SB().dragShow = v end }
                end
                local _, visCogShow = EllesmereUI.BuildCogPopup({
                    title = "Visibility",
                    rows = { MORow() },
                })
                local _, visCogShowNever = EllesmereUI.BuildCogPopup({
                    title = "Visibility",
                    rows = { MORow(), DragRow() },
                })
                local visCtrl = rgn._control
                local visCogBtn = MakeCogBtn(rgn, function(anchor)
                    local s = SB()
                    if s.barVisibility == "never" or s.alwaysHidden then
                        visCogShowNever(anchor)
                    else
                        visCogShow(anchor)
                    end
                end, visCtrl, EllesmereUI.COGS_ICON)
            end
        end

        -- Row 2: Always Show Buttons | Bar Opacity
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Always Show Buttons",
              getValue=function()
                  local v = SGet("alwaysShowButtons")
                  if v == nil then return true end
                  return v
              end,
              setValue=function(v)
                  SSet("alwaysShowButtons", v, function(k)
                      EAB:ApplyAlwaysShowButtons(k)
                      EAB:ApplyPaddingForBar(k)
                      EAB:ApplyBackgroundForBar(k)
                  end)
                  SUpdatePreview()
              end,
              tooltip="Show button backgrounds even if a spell is not assigned to that slot." },
            { type="slider", text="Bar Opacity", min=0, max=100, step=5,
              getValue=function()
                  local bs = SB()
                  if bs.mouseoverEnabled then
                      return floor((bs._savedBarAlpha or 1) * 100 + 0.5)
                  end
                  return floor((bs.mouseoverAlpha or 1) * 100 + 0.5)
              end,
              setValue=function(v)
                  local bs = SB()
                  if bs.mouseoverEnabled then
                      bs._savedBarAlpha = v / 100
                  else
                      SSet("mouseoverAlpha", v / 100, function(k) EAB:ApplyBarOpacity(k) end)
                  end
                  SUpdatePreview()
              end });  y = y - h
        -- Sync icon: Bar Opacity (right)
        do
            local rgn = row._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Bar Opacity to all Bars",
                onClick = function()
                    local v = SB().mouseoverAlpha or 1
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        EAB.db.profile.bars[key].mouseoverAlpha = v
                        EAB:ApplyBarOpacity(key)
                    end
                    EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local cur = SB()
                    local v = cur.mouseoverEnabled and 1 or (cur.mouseoverAlpha or 1)
                    for _, key in ipairs(GROUP_BAR_ORDER) do
                        local bs = EAB.db.profile.bars[key]
                        local bv = bs.mouseoverEnabled and 1 or (bs.mouseoverAlpha or 1)
                        if bv ~= v then return false end
                    end
                    return true
                end,
                flashTargets = function() return { rgn } end,
                multiApply = {
                    elementKeys   = GROUP_BAR_ORDER,
                    elementLabels = SHORT_LABELS,
                    getCurrentKey = function() return SelectedKey() end,
                    onApply       = function(checkedKeys)
                        local v = SB().mouseoverAlpha or 1
                        for _, key in ipairs(checkedKeys) do
                            EAB.db.profile.bars[key].mouseoverAlpha = v
                            EAB:ApplyBarOpacity(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                },
            })
        end

        -- Row 3: Toggle Action Bar keybind | Click Through  (hidden for vis-only bars)
        if not visOnly then
            local ctRow
            ctRow, h = W:DualRow(parent, y,
                { type="label", text="Toggle Action Bar Visibility" },
                { type="toggle", text="Click Through",
                  getValue=function()
                      return SGet("clickThrough")
                  end,
                  setValue=function(v)
                      SSet("clickThrough", v, function(k) EAB:ApplyClickThroughForBar(k) end)
                  end });  y = y - h
            -- Keybind button for "Toggle Action Bar" (left region). Pressing the
            -- bound key flips this bar between shown and hidden at runtime without
            -- writing the saved visibility. Enabled only when Visibility is Always
            -- or Never; the toggle itself only works out of combat.
            do
                local rgn = ctRow._leftRegion
                local kbBtn = CreateFrame("Button", nil, rgn)
                PP.Size(kbBtn, 126, 29)
                PP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -20, 0)
                kbBtn:SetFrameLevel(rgn:GetFrameLevel() + 4)
                kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND", EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                kbBg:SetAllPoints()
                kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PanelPP)
                local kbLbl = EllesmereUI.MakeFont(kbBtn, 12, nil, 1, 1, 1)
                kbLbl:SetAlpha(EllesmereUI.DD_TXT_A)
                kbLbl:SetPoint("CENTER")

                local listening = false

                local function FormatKey(key)
                    if not key then return EllesmereUI.L("Not Bound") end
                    local parts = {}
                    for mod in key:gmatch("(%u+)%-") do
                        parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
                    end
                    parts[#parts + 1] = key:match("[^%-]+$") or key
                    return table.concat(parts, " + ")
                end

                local function IsDisabled()
                    local v = SB().barVisibility or "always"
                    return v ~= "always" and v ~= "never"
                end

                local function RefreshLabel()
                    if listening then return end
                    kbLbl:SetText(FormatKey(SB().toggleVisKey))
                end

                local function RefreshState()
                    local off = IsDisabled()
                    kbBtn:SetAlpha(off and 0.3 or 1)
                    kbBtn:EnableMouse(not off)
                    if rgn._label then rgn._label:SetAlpha(off and 0.3 or 1) end
                    if off and listening then
                        listening = false
                        kbBtn:EnableKeyboard(false)
                    end
                    RefreshLabel()
                end

                kbBtn:SetScript("OnClick", function(self, button)
                    if IsDisabled() then return end
                    if button == "RightButton" then
                        if listening then listening = false; self:EnableKeyboard(false) end
                        SB().toggleVisKey = nil
                        EAB:RebuildVisToggleBindings()
                        RefreshLabel()
                        if EllesmereUI._NotifySettingWrite then EllesmereUI._NotifySettingWrite(rgn) end
                        return
                    end
                    if listening then return end
                    listening = true
                    kbLbl:SetText(EllesmereUI.L("Press a key..."))
                    self:EnableKeyboard(true)
                end)

                kbBtn:SetScript("OnKeyDown", function(self, key)
                    if not listening then self:SetPropagateKeyboardInput(true); return end
                    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
                       or key == "LALT" or key == "RALT" then
                        self:SetPropagateKeyboardInput(true); return
                    end
                    self:SetPropagateKeyboardInput(false)
                    if key == "ESCAPE" then
                        listening = false; self:EnableKeyboard(false); RefreshLabel(); return
                    end
                    local mods = ""
                    if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                    if IsControlKeyDown() then mods = mods .. "CTRL-" end
                    if IsAltKeyDown() then mods = mods .. "ALT-" end
                    SB().toggleVisKey = mods .. key
                    EAB:RebuildVisToggleBindings()
                    listening = false
                    self:EnableKeyboard(false)
                    RefreshLabel()
                    if EllesmereUI._NotifySettingWrite then EllesmereUI._NotifySettingWrite(rgn) end
                end)

                kbBtn:SetScript("OnEnter", function(self)
                    if IsDisabled() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Visibility set to Always or Never"))
                        return
                    end
                    kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                    if kbBtn._border and kbBtn._border.SetColor then kbBtn._border:SetColor(1, 1, 1, 0.3) end
                    EllesmereUI.ShowWidgetTooltip(self, "Toggling action bar visibility is only available out of combat\n\nLeft-click to set a keybind.\nRight-click to unbind.")
                end)
                kbBtn:SetScript("OnLeave", function()
                    if listening then return end
                    kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                    if kbBtn._border and kbBtn._border.SetColor then kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A) end
                    EllesmereUI.HideWidgetTooltip()
                end)
                kbBtn:SetScript("OnHide", function()
                    -- Closing the EUI window mid-capture must cancel the capture
                    -- AND hide the tooltip. OnLeave skips the hide while listening
                    -- (and may not fire at all if the mouse never left), so the
                    -- tooltip would otherwise linger after the window is gone.
                    if listening then listening = false; kbBtn:EnableKeyboard(false); RefreshLabel() end
                    EllesmereUI.HideWidgetTooltip()
                end)

                RefreshState()
                EllesmereUI.RegisterWidgetRefresh(RefreshState)

                -- Spec Overrides capture: bespoke widget, so its SLOT opts in
                -- with a synthetic accessor (the left half is a plain label
                -- cfg, which carries no get/set of its own).
                EllesmereUI.AddCaptureAccessor(rgn, {
                    type = "keybind", text = "Toggle Action Bar Visibility",
                    getValue = function() return SB().toggleVisKey end,
                    setValue = function(v)
                        SB().toggleVisKey = v
                        EAB:RebuildVisToggleBindings()
                        RefreshLabel()
                    end,
                })
            end
            -- Sync icon: Click Through (right)
            do
                local rgn = ctRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Click Through to all Bars",
                    onClick = function()
                        local v = SB().clickThrough or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].clickThrough = v
                            EAB:ApplyClickThroughForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().clickThrough or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].clickThrough or false) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().clickThrough or false
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].clickThrough = v
                                EAB:ApplyClickThroughForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
        end

        -----------------------------------------------------------------------
        --  LAYOUT  (hidden when visibility-only)
        -----------------------------------------------------------------------
        if not visOnly then
            _, h = W:SectionHeader(parent, SECTION_LAYOUT, y);  y = y - h

            -- Row 1: Icon Size | Button Spacing
            local iconSizeRow
            iconSizeRow, h = W:DualRow(parent, y,
                { type="slider", text="Icon Size", min=16, max=120, step=1,
                  disabled=function()
                      local k = SelectedKey()
                      if EllesmereUI.GetWidthMatchTarget and EllesmereUI.GetWidthMatchTarget(k) then return true end
                      if EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget(k) then return true end
                      return EAB.db.profile.useBlizzardStyle or false
                  end,
                  disabledTooltip=function()
                      -- Blizzard Style wins the message: sizing is Blizzard
                      -- Edit Mode's regardless of any (stale) match link, so
                      -- "unmatch to edit" would send the user on a dead end.
                      if EAB.db.profile.useBlizzardStyle then return BLIZZ_DIS_TIP end
                      local k = SelectedKey()
                      local wt = EllesmereUI.GetWidthMatchTarget and EllesmereUI.GetWidthMatchTarget(k)
                      local ht = EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget(k)
                      local target = wt or ht
                      if target then
                          local name = (EllesmereUI.GetBarLabel and EllesmereUI.GetBarLabel(target)) or target
                          return EllesmereUI.Lf("Size matched to %1$s. Unmatch in Unlock Mode to edit.", name)
                      end
                      return BLIZZ_DIS_TIP
                  end,
                  rawTooltip=true,
                  getValue=function()
                      local s = SB()
                      if s.buttonWidth and s.buttonWidth > 0 then return s.buttonWidth end
                      local info = BAR_LOOKUP[SelectedKey()]
                      local btn1 = FirstBarButton(SelectedKey())
                      return btn1 and math.floor((btn1:GetWidth() or 36) + 0.5) or 36
                  end,
                  setValue=function(v)
                      SB().buttonWidth  = v
                      SB().buttonHeight = v
                      SB()._matchExtraPixels = nil
                      SB()._matchExtraPixelsH = nil
                      EAB:ApplyButtonSizeForBar(SelectedKey())
                      SUpdatePreviewAndResize()
                      EllesmereUI:RefreshPage()
                  end },
                { type="slider", pixel=true, text="Button Spacing", min=-10, max=20, step=1,
                  getValue=function() return SVal("buttonPadding", 2) end,
                  setValue=function(v)
                      SSet("buttonPadding", v, function(k) EAB:ApplyPaddingForBar(k) end)
                      SUpdatePreview()
                  end });  y = y - h
            -- Sync icon: Icon Size (left)
            do
                local rgn = iconSizeRow._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Icon Size to all Bars",
                    onClick = function()
                        local s = SB()
                        local info = BAR_LOOKUP[SelectedKey()]
                        local btn1 = FirstBarButton(SelectedKey())
                        local v = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth
                            or (btn1 and math.floor((btn1:GetWidth() or 36) + 0.5)) or 36
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].buttonWidth  = v
                            EAB.db.profile.bars[key].buttonHeight = v
                            EAB:ApplyButtonSizeForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local s = SB()
                        local info = BAR_LOOKUP[SelectedKey()]
                        local btn1 = FirstBarButton(SelectedKey())
                        local v = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth
                            or (btn1 and math.floor((btn1:GetWidth() or 36) + 0.5)) or 36
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local ks = EAB.db.profile.bars[key]
                            local kv = (ks.buttonWidth and ks.buttonWidth > 0) and ks.buttonWidth or v
                            if kv ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local s = SB()
                            local info = BAR_LOOKUP[SelectedKey()]
                            local btn1 = FirstBarButton(SelectedKey())
                            local v = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth
                                or (btn1 and math.floor((btn1:GetWidth() or 36) + 0.5)) or 36
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].buttonWidth  = v
                                EAB.db.profile.bars[key].buttonHeight = v
                                EAB:ApplyButtonSizeForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            -- Sync icon: Button Spacing (right)
            do
                local rgn = iconSizeRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Button Spacing to all Bars",
                    onClick = function()
                        local v = SB().buttonPadding or 2
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].buttonPadding = v
                            EAB:ApplyPaddingForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().buttonPadding or 2
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].buttonPadding or 2) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().buttonPadding or 2
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].buttonPadding = v
                                EAB:ApplyPaddingForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Row 2: Number of Icons | Number of Rows
            row, h = W:DualRow(parent, y,
                { type="slider", text="Number of Icons", min=1, max=12, step=1,
                  disabled=function()
                      local info = BAR_LOOKUP[SelectedKey()]
                      return info and info.isStance
                  end,
                  getValue=function()
                      local v = SGet("overrideNumIcons")
                      if v and v > 0 then return v end
                      local s = SB()
                      if s and s.numIcons and s.numIcons > 0 then
                          return s.numIcons
                      end
                      return 12
                  end,
                  setValue=function(v)
                      SSet("overrideNumIcons", v, function(k) EAB:ApplyIconRowOverrides(k) end)
                      SUpdatePreviewAndResize()
                  end },
                { type="slider", text="Number of Rows", min=1, max=12, step=1,
                  getValue=function()
                      local v = SGet("overrideNumRows")
                      if v and v > 0 then return v end
                      local s = SB()
                      if s and s.numRows and s.numRows > 0 then
                          return s.numRows
                      end
                      return 1
                  end,
                  setValue=function(v)
                      SSet("overrideNumRows", v, function(k) EAB:ApplyIconRowOverrides(k) end)
                      SUpdatePreviewAndResize()
                  end });  y = y - h
            -- Sync icons: Number of Icons (left) and Number of Rows (right)
            do
                local rgn = row._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Number of Icons to all Bars",
                    onClick = function()
                        local v = SB().overrideNumIcons or 12
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].overrideNumIcons = v
                            EAB:ApplyIconRowOverrides(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().overrideNumIcons or 12
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].overrideNumIcons or 12) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().overrideNumIcons or 12
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].overrideNumIcons = v
                                EAB:ApplyIconRowOverrides(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            do
                local rgn = row._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Number of Rows to all Bars",
                    onClick = function()
                        local v = SB().overrideNumRows or 1
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].overrideNumRows = v
                            EAB:ApplyIconRowOverrides(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().overrideNumRows or 1
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].overrideNumRows or 1) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().overrideNumRows or 1
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].overrideNumRows = v
                                EAB:ApplyIconRowOverrides(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            -- Inline cog on Number of Rows (right) for Grow Direction
            do
                local rightRgn = row._rightRegion
                local isVert = SVal("orientation", "horizontal") == "vertical"
                local growDirValues, growDirOrder
                if isVert then
                    growDirValues = { up = "Up", down = "Down", center = "Centered" }
                    growDirOrder  = { "up", "down", "center" }
                else
                    growDirValues = { left = "Left", right = "Right", center = "Centered" }
                    growDirOrder  = { "left", "right", "center" }
                end
                local _, growCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Row Settings",
                    rows = {
                        { type="dropdown", label="Grow Direction",
                          values=growDirValues, order=growDirOrder,
                          get=function()
                              local val = SVal("growDirection", "up")
                              if not growDirValues[val] then return "center" end
                              return val
                          end,
                          set=function(v)
                              SSet("growDirection", v, function(k) EAB:ApplyIconRowOverrides(k) end)
                              SUpdatePreviewAndResize()
                          end },
                    },
                })
                local growCogShow = growCogShowRaw
                MakeCogBtn(rightRgn, growCogShow)
            end

            -- Row 3: Vertical Orientation
            do
                local orientRow
                orientRow, h = W:DualRow(parent, y,
                    { type="toggle", text="Vertical Orientation",
                      disabled=function()
                          return not EAB:BarSupportsOrientation(SelectedKey())
                      end,
                      disabledTooltip="This option is not supported for this bar type",
                      rawTooltip=true,
                      labelOnlyTooltip=true,
                      getValue=function()
                          return not EAB:GetOrientationForBar(SelectedKey())
                      end,
                      setValue=function(v)
                          EAB:SetOrientationForBar(SelectedKey(), not v)
                          SUpdatePreviewAndResize()
                          EllesmereUI:RefreshPage()
                      end,
                      tooltip="Toggle between horizontal and vertical bar layout." },
                    { type="label", text="" });  y = y - h
                -- Sync icon: Orientation (left)
                do
                    local rgn = orientRow._leftRegion
                    EllesmereUI.BuildSyncIcon({
                        region  = rgn,
                        tooltip = "Apply Orientation to all Bars",
                        onClick = function()
                            local isHoriz = EAB:GetOrientationForBar(SelectedKey())
                            for _, key in ipairs(GROUP_BAR_ORDER) do
                                if EAB:BarSupportsOrientation(key) then
                                    EAB:SetOrientationForBar(key, isHoriz)
                                end
                            end
                            EllesmereUI:RefreshPage()
                        end,
                        isSynced = function()
                            local isHoriz = EAB:GetOrientationForBar(SelectedKey())
                            for _, key in ipairs(GROUP_BAR_ORDER) do
                                if EAB:BarSupportsOrientation(key) and EAB:GetOrientationForBar(key) ~= isHoriz then return false end
                            end
                            return true
                        end,
                        flashTargets = function() return { rgn } end,
                        multiApply = {
                            elementKeys   = GROUP_BAR_ORDER,
                            elementLabels = SHORT_LABELS,
                            getCurrentKey = function() return SelectedKey() end,
                            onApply       = function(checkedKeys)
                                local isHoriz = EAB:GetOrientationForBar(SelectedKey())
                                for _, key in ipairs(checkedKeys) do
                                    if EAB:BarSupportsOrientation(key) then
                                        EAB:SetOrientationForBar(key, isHoriz)
                                    end
                                end
                                EllesmereUI:RefreshPage()
                            end,
                        },
                    })
                end

                -- Legacy background controls used to live in Layout. Keep the
                -- implementation block disabled so only the dedicated section
                -- below owns these settings.
                if false then
                -- Sync icon: Bar Background (right region)
                do
                    local rgn = orientRow._rightRegion
                    EllesmereUI.BuildSyncIcon({
                        region  = rgn,
                        tooltip = "Apply Background Settings to all Bars",
                        onClick = function()
                            local s = SB()
                            local en = s.bgEnabled
                            local c = s.bgColor
                            local bc = s.bgBorderColor
                            local px = s.bgPadX or 0
                            local py = s.bgPadY or 0
                            for _, key in ipairs(GROUP_BAR_ORDER) do
                                local bs = EAB.db.profile.bars[key]
                                bs.bgEnabled = en
                                if c then bs.bgColor = { r=c.r, g=c.g, b=c.b, a=c.a } end
                                bs.bgPadX = px
                                bs.bgPadY = py
                                bs.bgBorderThickness = s.bgBorderThickness
                                bs.bgBorderTexture = s.bgBorderTexture
                                bs.bgBorderSize = s.bgBorderSize
                                if bc then bs.bgBorderColor = { r=bc.r, g=bc.g, b=bc.b, a=bc.a } end
                                EAB:ApplyBackgroundForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                        isSynced = function()
                            local s = SB()
                            local en = s.bgEnabled or false
                            local px = s.bgPadX or 0
                            local py = s.bgPadY or 0
                            for _, key in ipairs(GROUP_BAR_ORDER) do
                                local bs = EAB.db.profile.bars[key]
                                if (bs.bgEnabled or false) ~= en then return false end
                                if (bs.bgPadX or 0) ~= px then return false end
                                if (bs.bgPadY or 0) ~= py then return false end
                                if (bs.bgBorderThickness or "none") ~= (s.bgBorderThickness or "none") then return false end
                                if (bs.bgBorderTexture or "solid") ~= (s.bgBorderTexture or "solid") then return false end
                                if (bs.bgBorderSize or 1) ~= (s.bgBorderSize or 1) then return false end
                            end
                            return true
                        end,
                        flashTargets = function() return { rgn } end,
                        multiApply = {
                            elementKeys   = GROUP_BAR_ORDER,
                            elementLabels = SHORT_LABELS,
                            getCurrentKey = function() return SelectedKey() end,
                            onApply       = function(checkedKeys)
                                local s = SB()
                                local en = s.bgEnabled
                                local c = s.bgColor
                                local bc = s.bgBorderColor
                                local px = s.bgPadX or 0
                                local py = s.bgPadY or 0
                                for _, key in ipairs(checkedKeys) do
                                    local bs = EAB.db.profile.bars[key]
                                    bs.bgEnabled = en
                                    if c then bs.bgColor = { r=c.r, g=c.g, b=c.b, a=c.a } end
                                    bs.bgPadX = px
                                    bs.bgPadY = py
                                    bs.bgBorderThickness = s.bgBorderThickness
                                    bs.bgBorderTexture = s.bgBorderTexture
                                    bs.bgBorderBehind = s.bgBorderBehind
                                    bs.bgBorderSize = s.bgBorderSize
                                    if bc then bs.bgBorderColor = { r=bc.r, g=bc.g, b=bc.b, a=bc.a } end
                                    EAB:ApplyBackgroundForBar(key)
                                end
                                EllesmereUI:RefreshPage()
                            end,
                        },
                    })
                end
                -- Inline swatch + cog on Bar Background (right region)
                do
                    local bgRgn = orientRow._rightRegion
                    local bgColorGet = function()
                        local c = SGet("bgColor")
                        if not c then return 0, 0, 0, 0.5 end
                        return c.r, c.g, c.b, c.a
                    end
                    local bgColorSet = function(r, g, b, a)
                        SSetColor("bgColor", r, g, b, a, function(k) EAB:ApplyBackgroundForBar(k) end)
                        SUpdatePreview()
                    end
                    local bgSwatch, bgUpdateSwatch = EllesmereUI.BuildColorSwatch(bgRgn, bgRgn:GetFrameLevel() + 5, bgColorGet, bgColorSet, true, 20)
                    PP.Point(bgSwatch, "RIGHT", bgRgn._control, "LEFT", -12, 0)
                    bgRgn._lastInline = bgSwatch
                    EllesmereUI.RegisterWidgetRefresh(function()
                        local off = BgDisabled()
                        bgSwatch:SetAlpha(off and 0.15 or 1)
                        bgUpdateSwatch()
                    end)
                    bgSwatch:SetAlpha(BgDisabled() and 0.15 or 1)
                    local bgSwatchOrigClick = bgSwatch:GetScript("OnClick")
                    bgSwatch:SetScript("OnClick", function(self, ...)
                        if BgDisabled() then return end
                        if bgSwatchOrigClick then bgSwatchOrigClick(self, ...) end
                    end)
                    bgSwatch:SetScript("OnEnter", function(self)
                        if BgDisabled() then
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Bar Background"))
                        end
                    end)
                    bgSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                    local _, bgCogShowRaw = EllesmereUI.BuildCogPopup({
                        title = "Bar Background Settings",
                        rows = {
                            { type="slider", label="Width", min=0, max=40, step=1,
                              get=function() return SVal("bgPadX", 0) end,
                              set=function(v)
                                  SSet("bgPadX", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                                  SUpdatePreview()
                              end },
                            { type="slider", label="Height", min=0, max=40, step=1,
                              get=function() return SVal("bgPadY", 0) end,
                              set=function(v)
                                  SSet("bgPadY", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                                  SUpdatePreview()
                              end },
                        },
                    })
                    local bgCogAnchor = bgRgn._lastInline or bgRgn._control
                    local bgCogBtn = MakeCogBtn(bgRgn, bgCogShowRaw, bgCogAnchor, EllesmereUI.RESIZE_ICON)
                    bgCogBtn:ClearAllPoints()
                    bgCogBtn:SetPoint("RIGHT", bgCogAnchor, "LEFT", -9, 0)
                    bgCogBtn:SetAlpha(BgDisabled() and 0.15 or 0.4)
                    bgCogBtn:SetScript("OnEnter", function(self)
                        if BgDisabled() then
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Bar Background"))
                        else
                            self:SetAlpha(0.7)
                        end
                    end)
                    bgCogBtn:SetScript("OnLeave", function(self)
                        EllesmereUI.HideWidgetTooltip()
                        self:SetAlpha(BgDisabled() and 0.15 or 0.4)
                    end)
                    bgCogBtn:SetScript("OnClick", function(self)
                        if BgDisabled() then return end
                        bgCogShowRaw(self)
                    end)
                    EllesmereUI.RegisterWidgetRefresh(function()
                        bgCogBtn:SetAlpha(BgDisabled() and 0.15 or 0.4)
                    end)
                end
                end
            end

            -- Built later, directly below ICON EFFECTS. Keeping the builder
            -- near the other layout helpers avoids duplicating its callbacks.
            local function BuildBarBackgroundSection()
            -------------------------------------------------------------------
            --  BAR BACKGROUND
            -------------------------------------------------------------------
            _, h = W:SectionHeader(parent, "BAR BACKGROUND", y);  y = y - h

            local bgOptionsRow
            bgOptionsRow, h = W:DualRow(parent, y,
                { type="toggle", text="Enable",
                  getValue=function() return SVal("bgEnabled", false) end,
                  setValue=function(v)
                      SSet("bgEnabled", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", text="Spacing", min=0, max=20, step=1,
                  disabled=BgDisabled,
                  disabledTooltip="Bar Background",
                  getValue=function()
                      local v = SGet("bgPadding")
                      if v ~= nil then return v end
                      return math.max(SVal("bgPadX", 0), SVal("bgPadY", 0))
                  end,
                  setValue=function(v)
                      SB().bgPadX, SB().bgPadY = nil, nil
                      SSet("bgPadding", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                      SUpdatePreview()
                  end });  y = y - h

            do
                local region = bgOptionsRow._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region=region,
                    tooltip="Apply Bar Background Enable to all Bars",
                    onClick=function()
                        local enabled = SVal("bgEnabled", false)
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].bgEnabled = enabled
                            EAB:ApplyBackgroundForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced=function()
                        local enabled = SVal("bgEnabled", false)
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].bgEnabled or false) ~= enabled then return false end
                        end
                        return true
                    end,
                    flashTargets=function() return { region } end,
                    multiApply={
                        elementKeys=GROUP_BAR_ORDER,
                        elementLabels=SHORT_LABELS,
                        getCurrentKey=function() return SelectedKey() end,
                        onApply=function(checkedKeys)
                            local enabled = SVal("bgEnabled", false)
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].bgEnabled = enabled
                                EAB:ApplyBackgroundForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            do
                local region = bgOptionsRow._rightRegion
                local function CurrentSpacing(settings)
                    if settings.bgPadding ~= nil then return settings.bgPadding end
                    return math.max(settings.bgPadX or 0, settings.bgPadY or 0)
                end
                local function ApplySpacingTo(key)
                    local target = EAB.db.profile.bars[key]
                    target.bgPadding = CurrentSpacing(SB())
                    target.bgPadX = nil
                    target.bgPadY = nil
                    EAB:ApplyBackgroundForBar(key)
                end
                EllesmereUI.BuildSyncIcon({
                    region=region,
                    tooltip="Apply Bar Background Spacing to all Bars",
                    onClick=function()
                        for _, key in ipairs(GROUP_BAR_ORDER) do ApplySpacingTo(key) end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced=function()
                        local spacing = CurrentSpacing(SB())
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if CurrentSpacing(EAB.db.profile.bars[key]) ~= spacing then return false end
                        end
                        return true
                    end,
                    flashTargets=function() return { region } end,
                    multiApply={
                        elementKeys=GROUP_BAR_ORDER,
                        elementLabels=SHORT_LABELS,
                        getCurrentKey=function() return SelectedKey() end,
                        onApply=function(checkedKeys)
                            for _, key in ipairs(checkedKeys) do ApplySpacingTo(key) end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            local function BackgroundOpacity(settings)
                if settings.bgOpacity ~= nil then return settings.bgOpacity end
                local color = settings.bgColor
                return ((color and color.a) or 0.5) * 100
            end

            local bgColorRow
            bgColorRow, h = W:DualRow(parent, y,
                { type="colorpicker", text="Background Color", hasAlpha=false,
                  disabled=BgDisabled,
                  disabledTooltip="Bar Background",
                  getValue=function()
                      local c = SGet("bgColor") or { r=0, g=0, b=0, a=0.5 }
                      return c.r, c.g, c.b, 1
                  end,
                  setValue=function(r, g, b)
                      local old = SGet("bgColor") or { a=0.5 }
                      SSetColor("bgColor", r, g, b, old.a or 0.5,
                          function(k) EAB:ApplyBackgroundForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", text="Background Opacity", min=0, max=100, step=1,
                  disabled=BgDisabled,
                  disabledTooltip="Bar Background",
                  getValue=function() return BackgroundOpacity(SB()) end,
                  setValue=function(v)
                      SSet("bgOpacity", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                      SUpdatePreview()
                  end });  y = y - h

            do
                local region = bgColorRow._leftRegion
                local function ApplyColorTo(key)
                    local source = SGet("bgColor") or { r=0, g=0, b=0, a=0.5 }
                    local target = EAB.db.profile.bars[key]
                    local old = target.bgColor
                    target.bgColor = { r=source.r, g=source.g, b=source.b,
                        a=(old and old.a) or source.a or 0.5 }
                    EAB:ApplyBackgroundForBar(key)
                end
                EllesmereUI.BuildSyncIcon({
                    region=region,
                    tooltip="Apply Background Color to all Bars",
                    onClick=function()
                        for _, key in ipairs(GROUP_BAR_ORDER) do ApplyColorTo(key) end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced=function()
                        local color = SGet("bgColor") or { r=0, g=0, b=0 }
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local target = EAB.db.profile.bars[key].bgColor or { r=0, g=0, b=0 }
                            if target.r ~= color.r or target.g ~= color.g or target.b ~= color.b then
                                return false
                            end
                        end
                        return true
                    end,
                    flashTargets=function() return { region } end,
                    multiApply={
                        elementKeys=GROUP_BAR_ORDER,
                        elementLabels=SHORT_LABELS,
                        getCurrentKey=function() return SelectedKey() end,
                        onApply=function(checkedKeys)
                            for _, key in ipairs(checkedKeys) do ApplyColorTo(key) end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            do
                local region = bgColorRow._rightRegion
                local function ApplyOpacityTo(key)
                    local target = EAB.db.profile.bars[key]
                    target.bgOpacity = BackgroundOpacity(SB())
                    EAB:ApplyBackgroundForBar(key)
                end
                EllesmereUI.BuildSyncIcon({
                    region=region,
                    tooltip="Apply Background Opacity to all Bars",
                    onClick=function()
                        for _, key in ipairs(GROUP_BAR_ORDER) do ApplyOpacityTo(key) end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced=function()
                        local opacity = BackgroundOpacity(SB())
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if BackgroundOpacity(EAB.db.profile.bars[key]) ~= opacity then return false end
                        end
                        return true
                    end,
                    flashTargets=function() return { region } end,
                    multiApply={
                        elementKeys=GROUP_BAR_ORDER,
                        elementLabels=SHORT_LABELS,
                        getCurrentKey=function() return SelectedKey() end,
                        onApply=function(checkedKeys)
                            for _, key in ipairs(checkedKeys) do ApplyOpacityTo(key) end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            do
                local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
                local bgBorderRow
                bgBorderRow, h = W:DualRow(parent, y,
                    { type="dropdown", text="Border Style",
                      disabled=BgDisabled,
                      disabledTooltip="Bar Background Border",
                      values=texValues, order=texOrder,
                      getValue=function() return SVal("bgBorderTexture", "solid") end,
                      setValue=function(v)
                          local color, behind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                          SSet("bgBorderTexture", v, function(k)
                              local settings = EAB.db.profile.bars[k]
                              settings.bgBorderOffsetX = nil
                              settings.bgBorderOffsetY = nil
                              settings.bgBorderShiftX = nil
                              settings.bgBorderShiftY = nil
                              settings.bgBorderBehind = behind
                              settings.bgBorderColor = { r=color.r, g=color.g, b=color.b, a=1 }
                              EAB:ApplyBackgroundForBar(k)
                          end)
                          SUpdatePreview()
                          EllesmereUI:RefreshPage()
                      end },
                    { type="dropdown", text="Border Size",
                      disabled=BgDisabled,
                      disabledTooltip="Bar Background Border",
                      values=ns.BORDER_THICKNESS_LABELS, order=ns.BORDER_THICKNESS_ORDER,
                      getValue=function() return SVal("bgBorderThickness", "none") end,
                      setValue=function(v)
                          SSet("bgBorderThickness", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                          SUpdatePreview()
                      end });  y = y - h

                do
                    local region = bgBorderRow._rightRegion
                    local borderSwatch, refreshBorder = EllesmereUI.BuildColorSwatch(region, region:GetFrameLevel() + 5,
                        function()
                            local c = SGet("bgBorderColor") or { r=0, g=0, b=0, a=1 }
                            return c.r, c.g, c.b, c.a
                        end,
                        function(r, g, b, a)
                            SSetColor("bgBorderColor", r, g, b, a, function(k) EAB:ApplyBackgroundForBar(k) end)
                            SUpdatePreview()
                    end, true, 20)
                    PP.Point(borderSwatch, "RIGHT", region._control, "LEFT", -12, 0)
                    region._lastInline = borderSwatch
                    EllesmereUI.RegisterWidgetRefresh(function()
                        local disabled = BgDisabled() or SVal("bgBorderThickness", "none") == "none"
                        borderSwatch:SetAlpha(disabled and 0.15 or 1)
                        refreshBorder()
                    end)
                end

                do
                    local region = bgBorderRow._rightRegion
                    local function ApplySizeTo(key)
                        local source = SB()
                        local target = EAB.db.profile.bars[key]
                        target.bgBorderThickness = source.bgBorderThickness
                        local color = source.bgBorderColor
                        if color then
                            target.bgBorderColor = { r=color.r, g=color.g, b=color.b, a=color.a }
                        end
                        EAB:ApplyBackgroundForBar(key)
                    end
                    EllesmereUI.BuildSyncIcon({
                        region=region,
                        tooltip="Apply Background Border Size and Color to all Bars",
                        onClick=function()
                            for _, key in ipairs(GROUP_BAR_ORDER) do ApplySizeTo(key) end
                            EllesmereUI:RefreshPage()
                        end,
                        isSynced=function()
                            local thickness = SVal("bgBorderThickness", "none")
                            local color = SGet("bgBorderColor") or { r=0, g=0, b=0, a=1 }
                            for _, key in ipairs(GROUP_BAR_ORDER) do
                                local target = EAB.db.profile.bars[key]
                                if (target.bgBorderThickness or "none") ~= thickness then return false end
                                local targetColor = target.bgBorderColor or { r=0, g=0, b=0, a=1 }
                                if targetColor.r ~= color.r or targetColor.g ~= color.g
                                    or targetColor.b ~= color.b or targetColor.a ~= color.a then return false end
                            end
                            return true
                        end,
                        flashTargets=function() return { region } end,
                        multiApply={
                            elementKeys=GROUP_BAR_ORDER,
                            elementLabels=SHORT_LABELS,
                            getCurrentKey=function() return SelectedKey() end,
                            onApply=function(checkedKeys)
                                for _, key in ipairs(checkedKeys) do ApplySizeTo(key) end
                                EllesmereUI:RefreshPage()
                            end,
                        },
                    })
                end

                do
                    local region = bgBorderRow._leftRegion
                    local _, showOffsetPopup = EllesmereUI.BuildCogPopup({
                        title="Border Offset",
                        captureRegion=region,
                        rows={
                            { type="slider", label="Offset X", min=-10, max=10, step=1,
                              get=function()
                                  local value = SGet("bgBorderOffsetX")
                                  if value ~= nil then return value end
                                  local texture = SVal("bgBorderTexture", "solid")
                                  local thickness = SVal("bgBorderThickness", "thin")
                                  local defaultX = EllesmereUI.GetBorderDefaults("actionbars", texture, thickness)
                                  return defaultX
                              end,
                              set=function(v)
                                  SSet("bgBorderOffsetX", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                                  SUpdatePreview()
                              end },
                            { type="slider", label="Offset Y", min=-10, max=10, step=1,
                              get=function()
                                  local value = SGet("bgBorderOffsetY")
                                  if value ~= nil then return value end
                                  local texture = SVal("bgBorderTexture", "solid")
                                  local thickness = SVal("bgBorderThickness", "thin")
                                  local _, defaultY = EllesmereUI.GetBorderDefaults("actionbars", texture, thickness)
                                  return defaultY
                              end,
                              set=function(v)
                                  SSet("bgBorderOffsetY", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                                  SUpdatePreview()
                              end },
                            { type="slider", label="Shift X", min=-10, max=10, step=1,
                              get=function()
                                  local value = SGet("bgBorderShiftX")
                                  if value ~= nil then return value end
                                  local texture = SVal("bgBorderTexture", "solid")
                                  local thickness = SVal("bgBorderThickness", "thin")
                                  local _, _, defaultX = EllesmereUI.GetBorderDefaults("actionbars", texture, thickness)
                                  return defaultX
                              end,
                              set=function(v)
                                  SSet("bgBorderShiftX", v == 0 and nil or v, function(k) EAB:ApplyBackgroundForBar(k) end)
                                  SUpdatePreview()
                              end },
                            { type="slider", label="Shift Y", min=-10, max=10, step=1,
                              get=function()
                                  local value = SGet("bgBorderShiftY")
                                  if value ~= nil then return value end
                                  local texture = SVal("bgBorderTexture", "solid")
                                  local thickness = SVal("bgBorderThickness", "thin")
                                  local _, _, _, defaultY = EllesmereUI.GetBorderDefaults("actionbars", texture, thickness)
                                  return defaultY
                              end,
                              set=function(v)
                                  SSet("bgBorderShiftY", v == 0 and nil or v, function(k) EAB:ApplyBackgroundForBar(k) end)
                                  SUpdatePreview()
                              end },
                            { type="toggle", label="Show Behind",
                              get=function() return SVal("bgBorderBehind", false) end,
                              set=function(v)
                                  SSet("bgBorderBehind", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                                  SUpdatePreview()
                              end },
                        },
                    })
                    local offsetButton = MakeCogBtn(region, showOffsetPopup, nil, EllesmereUI.DIRECTIONS_ICON)
                    local function UpdateOffsetButton()
                        local hidden = BgDisabled()
                        offsetButton:SetShown(not hidden)
                    end
                    EllesmereUI.RegisterWidgetRefresh(UpdateOffsetButton)
                    UpdateOffsetButton()
                end

                do
                    local region = bgBorderRow._leftRegion
                    local function ApplyStyleTo(key)
                        local source = SB()
                        local target = EAB.db.profile.bars[key]
                        target.bgBorderTexture = source.bgBorderTexture
                        target.bgBorderOffsetX = source.bgBorderOffsetX
                        target.bgBorderOffsetY = source.bgBorderOffsetY
                        target.bgBorderShiftX = source.bgBorderShiftX
                        target.bgBorderShiftY = source.bgBorderShiftY
                        target.bgBorderBehind = source.bgBorderBehind
                        EAB:ApplyBackgroundForBar(key)
                    end
                    EllesmereUI.BuildSyncIcon({
                        region=region,
                        tooltip="Apply Background Border Style to all Bars",
                        onClick=function()
                            for _, key in ipairs(GROUP_BAR_ORDER) do ApplyStyleTo(key) end
                            EllesmereUI:RefreshPage()
                        end,
                        isSynced=function()
                            local source = SB()
                            for _, key in ipairs(GROUP_BAR_ORDER) do
                                local target = EAB.db.profile.bars[key]
                                if (target.bgBorderTexture or "solid") ~= (source.bgBorderTexture or "solid") then return false end
                                if target.bgBorderOffsetX ~= source.bgBorderOffsetX then return false end
                                if target.bgBorderOffsetY ~= source.bgBorderOffsetY then return false end
                                if target.bgBorderShiftX ~= source.bgBorderShiftX then return false end
                                if target.bgBorderShiftY ~= source.bgBorderShiftY then return false end
                                if (target.bgBorderBehind or false) ~= (source.bgBorderBehind or false) then return false end
                            end
                            return true
                        end,
                        flashTargets=function() return { region } end,
                        multiApply={
                            elementKeys=GROUP_BAR_ORDER,
                            elementLabels=SHORT_LABELS,
                            getCurrentKey=function() return SelectedKey() end,
                            onApply=function(checkedKeys)
                                for _, key in ipairs(checkedKeys) do ApplyStyleTo(key) end
                                EllesmereUI:RefreshPage()
                            end,
                        },
                    })
                end
            end

            local bgMultiplierRow
            bgMultiplierRow, h = W:DualRow(parent, y,
                { type="slider", text="Multiplier X", min=1, max=4, step=1,
                  disabled=BgDisabled,
                  disabledTooltip="Bar Background",
                  getValue=function() return SVal("bgMultiplierX", 1) end,
                  setValue=function(v)
                      SSet("bgMultiplierX", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                      SUpdatePreviewAndResize()
                  end },
                { type="slider", text="Multiplier Y", min=1, max=4, step=1,
                  disabled=BgDisabled,
                  disabledTooltip="Bar Background",
                  getValue=function() return SVal("bgMultiplierY", 1) end,
                  setValue=function(v)
                      SSet("bgMultiplierY", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                      SUpdatePreviewAndResize()
                  end });  y = y - h

            do
                local region = bgMultiplierRow._leftRegion
                local _, showDirectionX = EllesmereUI.BuildCogPopup({
                    title="Multiplier X Settings",
                    captureRegion=region,
                    rows={{ type="dropdown", label="Growth Direction",
                        values={ left="Left", right="Right" }, order={ "left", "right" },
                        get=function() return SVal("bgExpandDirectionX", "right") end,
                        set=function(v)
                            SSet("bgExpandDirectionX", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                            SUpdatePreviewAndResize()
                        end }},
                })
                MakeCogBtn(region, showDirectionX, nil, EllesmereUI.DIRECTIONS_ICON)
            end

            do
                local region = bgMultiplierRow._rightRegion
                local _, showDirectionY = EllesmereUI.BuildCogPopup({
                    title="Multiplier Y Settings",
                    captureRegion=region,
                    rows={{ type="dropdown", label="Growth Direction",
                        values={ up="Up", down="Down" }, order={ "up", "down" },
                        get=function() return SVal("bgExpandDirectionY", "up") end,
                        set=function(v)
                            SSet("bgExpandDirectionY", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                            SUpdatePreviewAndResize()
                        end }},
                })
                MakeCogBtn(region, showDirectionY, nil, EllesmereUI.DIRECTIONS_ICON)
            end
            end

            -------------------------------------------------------------------
            --  ICON APPEARANCE
            -------------------------------------------------------------------
            iconsSectionHeader, h = W:SectionHeader(parent, SECTION_ICON_APPEARANCE, y);  y = y - h

            local function BlizzStyleOn()
                return EAB.db.profile.useBlizzardStyle or false
            end

            -- Helper: is current shape "none" (no custom shape)?
            local function ShapeIsNone()
                local v = SGet("buttonShape")
                return v == "none" or v == "cropped" or v == nil
            end
            -- Helper: is current shape a custom shape (not "none")?
            local function ShapeIsCustom()
                return not ShapeIsNone()
            end

            -- Row 1: Class Colored Icon Border (toggle + inline swatch) | Custom Button Shape (dropdown)
            local SHAPE_VALUES = {
                none     = "None",
                cropped  = "Cropped",
                square   = "Square",
                circle   = "Circle",
                csquare  = "Curved Square",
                diamond  = "Diamond",
                hexagon  = "Hexagon",
                portrait = "Portrait",
                shield   = "Shield",
            }
            local SHAPE_ORDER = { "none", "cropped", "---", "square", "circle", "csquare", "diamond", "hexagon", "portrait", "shield" }

            -- Border Style dropdown (+ inline offset cog)
            local abBsRow
            do
                local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
                abBsRow, h = W:DualRow(parent, y,
                    { type="dropdown", text="Border Style",
                      disabled=function() return BlizzStyleOn() or ShapeIsCustom() end,
                      disabledTooltip=function() if ShapeIsCustom() then return "This option requires a non-custom button shape" end return "This option requires Blizzard Style Action Bars to be disabled" end,
                      rawTooltip=true,
                      values=texValues, order=texOrder,
                      getValue=function() return SGet("borderTexture") or "solid" end,
                      setValue=function(v)
                          local defTh = EllesmereUI.GetBorderDefaultSize("actionbars", v)
                          SSet("borderTexture", v, function(k)
                              EAB.db.profile.bars[k].borderTextureOffset = nil
                              EAB.db.profile.bars[k].borderTextureOffsetY = nil
                              EAB.db.profile.bars[k].borderTextureShiftX = nil
                              EAB.db.profile.bars[k].borderTextureShiftY = nil
                              local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                              EAB.db.profile.bars[k].borderColor = { r = _bcol.r, g = _bcol.g, b = _bcol.b, a = 1 }
                              EAB.db.profile.bars[k].borderClassColor = false
                              EAB.db.profile.bars[k].borderBehind = _bbehind
                              if defTh then
                                  EAB.db.profile.bars[k].borderThickness = defTh
                                  local entry = ns.BORDER_THICKNESS[defTh]
                                  if entry then
                                      local shape = EAB.db.profile.bars[k].buttonShape or "none"
                                      if shape ~= "none" and shape ~= "cropped" then
                                          EAB.db.profile.bars[k].shapeBorderSize = entry.shape
                                          EAB.db.profile.bars[k].shapeBorderEnabled = entry.shape > 0
                                      else
                                          EAB.db.profile.bars[k].borderSize = entry.regular
                                          EAB.db.profile.bars[k].borderEnabled = entry.regular > 0
                                      end
                                  end
                              end
                              EAB:ApplyBordersForBar(k)
                              EAB:ApplyShapesForBar(k)
                          end)
                          SUpdatePreview()
                          EllesmereUI:RefreshPage()
                      end },
                    { type="dropdown", text="Border Size",
                      disabled=BlizzStyleOn, disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
                      values=ns.BORDER_THICKNESS_LABELS, order=ns.BORDER_THICKNESS_ORDER,
                      itemDisabled=function(val)
                          if ShapeIsCustom() and (val == "thin" or val == "normal" or val == "heavy") then return true end
                          return false
                      end,
                      itemDisabledTooltip=function(val)
                          if ShapeIsCustom() and (val == "thin" or val == "normal" or val == "heavy") then
                              return "This option requires a non-custom shape to be selected"
                          end
                      end,
                      getValue=function()
                          local v = SGet("borderThickness")
                          return v or "thin"
                      end,
                      setValue=function(v)
                          SSet("borderThickness", v, function(k)
                              local entry = ns.BORDER_THICKNESS[v]
                              if entry then
                                  local shape = EAB.db.profile.bars[k].buttonShape or "none"
                                  if shape ~= "none" and shape ~= "cropped" then
                                      EAB.db.profile.bars[k].shapeBorderSize = entry.shape
                                      EAB.db.profile.bars[k].shapeBorderEnabled = entry.shape > 0
                                  else
                                      EAB.db.profile.bars[k].borderSize = entry.regular
                                      EAB.db.profile.bars[k].borderEnabled = entry.regular > 0
                                  end
                              end
                              EAB:ApplyBordersForBar(k)
                              EAB:ApplyShapesForBar(k)
                          end)
                          SUpdatePreview()
                      end });  y = y - h
                do
                    local rgn = abBsRow._leftRegion
                    local _, cogShow = EllesmereUI.BuildCogPopup({
                        title = "Border Offset",
                        captureRegion = rgn,
                        rows = {
                            { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                              get = function()
                                  local v = SGet("borderTextureOffset")
                                  if v then return v end
                                  local tex = SGet("borderTexture") or "solid"
                                  local th = SGet("borderThickness") or "thin"
                                  local dox = EllesmereUI.GetBorderDefaults("actionbars", tex, th)
                                  return dox
                              end,
                              set = function(v)
                                  SSet("borderTextureOffset", v, function(k)
                                      EAB:ApplyBordersForBar(k)
                                  end)
                                  SUpdatePreview()
                              end },
                            { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                              get = function()
                                  local v = SGet("borderTextureOffsetY")
                                  if v then return v end
                                  local tex = SGet("borderTexture") or "solid"
                                  local th = SGet("borderThickness") or "thin"
                                  local _, doy = EllesmereUI.GetBorderDefaults("actionbars", tex, th)
                                  return doy
                              end,
                              set = function(v)
                                  SSet("borderTextureOffsetY", v, function(k)
                                      EAB:ApplyBordersForBar(k)
                                  end)
                                  SUpdatePreview()
                              end },
                            { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                              get = function()
                                  local v = SGet("borderTextureShiftX")
                                  if v then return v end
                                  local tex = SGet("borderTexture") or "solid"
                                  local th = SGet("borderThickness") or "thin"
                                  local _, _, dsx = EllesmereUI.GetBorderDefaults("actionbars", tex, th)
                                  return dsx
                              end,
                              set = function(v)
                                  SSet("borderTextureShiftX", v == 0 and nil or v, function(k)
                                      EAB:ApplyBordersForBar(k)
                                  end)
                                  SUpdatePreview()
                              end },
                            { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                              get = function()
                                  local v = SGet("borderTextureShiftY")
                                  if v then return v end
                                  local tex = SGet("borderTexture") or "solid"
                                  local th = SGet("borderThickness") or "thin"
                                  local _, _, _, dsy = EllesmereUI.GetBorderDefaults("actionbars", tex, th)
                                  return dsy
                              end,
                              set = function(v)
                                  SSet("borderTextureShiftY", v == 0 and nil or v, function(k)
                                      EAB:ApplyBordersForBar(k)
                                  end)
                                  SUpdatePreview()
                              end },
                            { type = "toggle", label = "Show Behind",
                              get = function() return SGet("borderBehind") or false end,
                              set = function(v)
                                  SSet("borderBehind", v == false and nil or v, function(k)
                                      EAB:ApplyBordersForBar(k)
                                  end)
                                  SUpdatePreview(); EllesmereUI:RefreshPage()
                              end },
                        },
                    })
                    local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                    local function UpdateCogVis()
                        local tex = SGet("borderTexture") or "solid"
                        if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                    end
                    EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                    UpdateCogVis()
                end
                -- Sync icon: Border Style (left region)
                local bsLeftRgn = abBsRow._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = bsLeftRgn,
                    tooltip = "Apply Border Style to all Bars",
                    onClick = function()
                        local bt = SB().borderTexture or "solid"
                        local ox = SB().borderTextureOffset
                        local oy = SB().borderTextureOffsetY
                        local sx = SB().borderTextureShiftX
                        local sy = SB().borderTextureShiftY
                        local bh = SB().borderBehind
                        local bc = SB().borderColor
                        local bcc = SB().borderClassColor
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].borderTexture = bt
                            EAB.db.profile.bars[key].borderTextureOffset = ox
                            EAB.db.profile.bars[key].borderTextureOffsetY = oy
                            EAB.db.profile.bars[key].borderTextureShiftX = sx
                            EAB.db.profile.bars[key].borderTextureShiftY = sy
                            EAB.db.profile.bars[key].borderBehind = bh
                            if bc then EAB.db.profile.bars[key].borderColor = { r=bc.r, g=bc.g, b=bc.b, a=bc.a } end
                            EAB.db.profile.bars[key].borderClassColor = bcc
                            EAB:ApplyBordersForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local bt = SB().borderTexture or "solid"
                        local ox = SB().borderTextureOffset
                        local oy = SB().borderTextureOffsetY
                        local sx = SB().borderTextureShiftX
                        local sy = SB().borderTextureShiftY
                        local bh = SB().borderBehind or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].borderTexture or "solid") ~= bt then return false end
                            if EAB.db.profile.bars[key].borderTextureOffset ~= ox then return false end
                            if EAB.db.profile.bars[key].borderTextureOffsetY ~= oy then return false end
                            if EAB.db.profile.bars[key].borderTextureShiftX ~= sx then return false end
                            if EAB.db.profile.bars[key].borderTextureShiftY ~= sy then return false end
                            if (EAB.db.profile.bars[key].borderBehind or false) ~= bh then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { bsLeftRgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local bt = SB().borderTexture or "solid"
                            local ox = SB().borderTextureOffset
                            local oy = SB().borderTextureOffsetY
                            local sx = SB().borderTextureShiftX
                            local sy = SB().borderTextureShiftY
                            local bh = SB().borderBehind
                            local bc = SB().borderColor
                            local bcc = SB().borderClassColor
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].borderTexture = bt
                                EAB.db.profile.bars[key].borderTextureOffset = ox
                                EAB.db.profile.bars[key].borderTextureOffsetY = oy
                                EAB.db.profile.bars[key].borderTextureShiftX = sx
                                EAB.db.profile.bars[key].borderTextureShiftY = sy
                                EAB.db.profile.bars[key].borderBehind = bh
                                if bc then EAB.db.profile.bars[key].borderColor = { r=bc.r, g=bc.g, b=bc.b, a=bc.a } end
                                EAB.db.profile.bars[key].borderClassColor = bcc
                                EAB:ApplyBordersForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Inline border color swatches on Border Size (right region of abBsRow)
            do
                local rightRgn = abBsRow._rightRegion
                local ctrl = rightRgn._control

                -- Class color swatch (rightmost)
                local classBorderSwatch, updateClassBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rightRgn, abBsRow:GetFrameLevel() + 3,
                    function()
                        local _, ct = UnitClass("player")
                        local cc = ct and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ct]
                        if cc then return cc.r, cc.g, cc.b end
                        return 1, 1, 1
                    end,
                    function() end,
                    false, 20)
                PP.Point(classBorderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                classBorderSwatch:SetScript("OnClick", function()
                    SSet("borderClassColor", true, function(k)
                        EAB:ApplyBordersForBar(k)
                        EAB:ApplyShapesForBar(k)
                    end)
                    SUpdatePreview()
                    EllesmereUI:RefreshPage()
                end)
                classBorderSwatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(classBorderSwatch, "Class Colored")
                end)
                classBorderSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                -- Custom color swatch (left of class swatch)
                local customSwatch, updateCustomSwatch = EllesmereUI.BuildColorSwatch(
                    rightRgn, abBsRow:GetFrameLevel() + 3,
                    function()
                        local c = SGet("borderColor")
                        if not c then return 0, 0, 0 end
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        SSetColor("borderColor", r, g, b, nil, function(k)
                            EAB:ApplyBordersForBar(k)
                            EAB:ApplyShapesForBar(k)
                        end)
                        SSetColor("shapeBorderColor", r, g, b, nil, function(k)
                            EAB:ApplyShapesForBar(k)
                        end)
                        SUpdatePreview()
                    end,
                    false, 20)
                PP.Point(customSwatch, "RIGHT", classBorderSwatch, "LEFT", -8, 0)
                customSwatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
                end)
                customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                -- Click the dimmed custom swatch to switch back from class color (no block overlay)
                local origClick = customSwatch:GetScript("OnClick")
                customSwatch:SetScript("OnClick", function(self, ...)
                    if SGet("borderClassColor") then
                        SSet("borderClassColor", false, function(k)
                            EAB:ApplyBordersForBar(k)
                            EAB:ApplyShapesForBar(k)
                        end)
                        SUpdatePreview()
                        EllesmereUI:RefreshPage()
                        return
                    end
                    -- No border selected: allow swapping boxes but do not open the color picker
                    if (SGet("borderThickness") or "thin") == "none" then return end
                    if origClick then origClick(self, ...) end
                end)

                local function UpdateBorderSwatchState()
                    local isClassColored = SGet("borderClassColor")
                    local isNone = (SGet("borderThickness") or "thin") == "none"
                    customSwatch:SetAlpha((isClassColored or isNone) and 0.3 or 1)
                    classBorderSwatch:SetAlpha((isClassColored and not isNone) and 1 or 0.3)
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateCustomSwatch(); updateClassBorderSwatch(); UpdateBorderSwatchState() end)
                UpdateBorderSwatchState()
            end

            -- Sync icon: Border Size (right region of abBsRow)
            do
                local rgn = abBsRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Border Size and Color to all Bars",
                    onClick = function()
                        local th = SB().borderThickness
                        local c = SB().borderColor
                        local cc = SB().borderClassColor
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].borderThickness = th
                            local entry = ns.BORDER_THICKNESS[th]
                            if entry then
                                local shape = EAB.db.profile.bars[key].buttonShape or "none"
                                if shape ~= "none" and shape ~= "cropped" then
                                    EAB.db.profile.bars[key].shapeBorderSize = entry.shape
                                    EAB.db.profile.bars[key].shapeBorderEnabled = entry.shape > 0
                                else
                                    EAB.db.profile.bars[key].borderSize = entry.regular
                                    EAB.db.profile.bars[key].borderEnabled = entry.regular > 0
                                end
                            end
                            if c then
                                EAB.db.profile.bars[key].borderColor = { r=c.r, g=c.g, b=c.b, a=c.a }
                                EAB.db.profile.bars[key].shapeBorderColor = { r=c.r, g=c.g, b=c.b, a=c.a }
                            end
                            EAB.db.profile.bars[key].borderClassColor = cc
                            EAB:ApplyBordersForBar(key)
                            EAB:ApplyShapesForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local th = SB().borderThickness or "thin"
                        local cc = SB().borderClassColor or false
                        local c = SB().borderColor
                        local cr, cg, cb, ca = c and c.r or 0, c and c.g or 0, c and c.b or 0, c and c.a or 1
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].borderThickness or "thin") ~= th then return false end
                            if (EAB.db.profile.bars[key].borderClassColor or false) ~= cc then return false end
                            local bc = EAB.db.profile.bars[key].borderColor
                            if (bc and bc.r or 0) ~= cr or (bc and bc.g or 0) ~= cg or (bc and bc.b or 0) ~= cb or (bc and bc.a or 1) ~= ca then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local th = SB().borderThickness
                            local c = SB().borderColor
                            local cc = SB().borderClassColor
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].borderThickness = th
                                local entry = ns.BORDER_THICKNESS[th]
                                if entry then
                                    local shape = EAB.db.profile.bars[key].buttonShape or "none"
                                    if shape ~= "none" and shape ~= "cropped" then
                                        EAB.db.profile.bars[key].shapeBorderSize = entry.shape
                                        EAB.db.profile.bars[key].shapeBorderEnabled = entry.shape > 0
                                    else
                                        EAB.db.profile.bars[key].borderSize = entry.regular
                                        EAB.db.profile.bars[key].borderEnabled = entry.regular > 0
                                    end
                                end
                                if c then
                                    EAB.db.profile.bars[key].borderColor = { r=c.r, g=c.g, b=c.b, a=c.a }
                                    EAB.db.profile.bars[key].shapeBorderColor = { r=c.r, g=c.g, b=c.b, a=c.a }
                                end
                                EAB.db.profile.bars[key].borderClassColor = cc
                                EAB:ApplyBordersForBar(key)
                                EAB:ApplyShapesForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            local classColorBorderRow
            classColorBorderRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Custom Button Shape",
                  disabled=BlizzStyleOn, disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
                  values=SHAPE_VALUES, order=SHAPE_ORDER,
                  itemDisabled=function(val)
                      if val ~= "none" and val ~= "cropped" and (SGet("borderTexture") or "solid") ~= "solid" then return true end
                      return false
                  end,
                  itemDisabledTooltip=function(val)
                      if val ~= "none" and val ~= "cropped" and (SGet("borderTexture") or "solid") ~= "solid" then
                          return "This option requires the Border Style to be set to Solid"
                      end
                  end,
                  getValue=function()
                      local v = SGet("buttonShape")
                      return v or "none"
                  end,
                  setValue=function(v)
                      -- Set icon zoom BEFORE applying shapes so the new zoom
                      -- value is read by ApplyShapesForBar → ApplyShapeToButton
                      SSet("iconZoom", ns.SHAPE_ZOOM_DEFAULTS[v] or 5.5)
                      SSet("buttonShape", v, function(k)
                          -- Reset border thickness to the default for the new shape mode
                          if v ~= "none" and v ~= "cropped" then
                              EAB.db.profile.bars[k].borderThickness = ns.BORDER_THICKNESS_DEFAULT_SHAPE
                              local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_SHAPE]
                              EAB.db.profile.bars[k].shapeBorderSize = entry.shape
                              EAB.db.profile.bars[k].shapeBorderEnabled = true
                          else
                              EAB.db.profile.bars[k].borderThickness = ns.BORDER_THICKNESS_DEFAULT_REGULAR
                              local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_REGULAR]
                              EAB.db.profile.bars[k].borderSize = entry.regular
                              EAB.db.profile.bars[k].borderEnabled = true
                          end
                          -- Default keybind/count text for cropped vs normal
                          if v == "cropped" then
                              EAB.db.profile.bars[k].keybindFontSize = 11
                              EAB.db.profile.bars[k].keybindOffsetX = 0
                              EAB.db.profile.bars[k].keybindOffsetY = 1
                              EAB.db.profile.bars[k].countFontSize = 11
                              EAB.db.profile.bars[k].countOffsetX = 0
                              EAB.db.profile.bars[k].countOffsetY = -1
                          else
                              EAB.db.profile.bars[k].keybindFontSize = 12
                              EAB.db.profile.bars[k].keybindOffsetX = 0
                              EAB.db.profile.bars[k].keybindOffsetY = 0
                              EAB.db.profile.bars[k].countFontSize = 12
                              EAB.db.profile.bars[k].countOffsetX = 0
                              EAB.db.profile.bars[k].countOffsetY = 0
                          end
                          EAB:ApplyShapesForBar(k)
                          EAB:ApplyPaddingForBar(k)
                          EAB:ApplyBordersForBar(k)
                          EAB:ApplyFontsForBar(k)
                          EAB:ApplyIconBackgroundForBar(k)
                      end)
                      EAB:RefreshProcGlows()
                      SUpdatePreview()
                      EllesmereUI:RefreshPage()
                  end },
                { type="slider", text="Icon Zoom", min=0, max=10, step=0.5,
                  disabled=BlizzStyleOn, disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
                  getValue=function() return SVal("iconZoom", EAB.db.profile.iconZoom or 5.5) end,
                  setValue=function(v)
                      SSet("iconZoom", v, function(k)
                          EAB:ApplyBordersForBar(k)
                          EAB:ApplyShapesForBar(k)
                      end)
                      SUpdatePreview()
                  end });  y = y - h
            borderRow = classColorBorderRow
            -- Sync icon: Custom Button Shape (left region of classColorBorderRow)
            do
                local rgn = classColorBorderRow._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Custom Button Shape to all Bars",
                    onClick = function()
                        local v = SGet("buttonShape") or "none"
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local bs = EAB.db.profile.bars[key]
                            bs.iconZoom = ns.SHAPE_ZOOM_DEFAULTS[v] or 5.5
                            bs.buttonShape = v
                            if v ~= "none" and v ~= "cropped" then
                                bs.borderThickness = ns.BORDER_THICKNESS_DEFAULT_SHAPE
                                local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_SHAPE]
                                bs.shapeBorderSize = entry.shape
                                bs.shapeBorderEnabled = true
                            else
                                bs.borderThickness = ns.BORDER_THICKNESS_DEFAULT_REGULAR
                                local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_REGULAR]
                                bs.borderSize = entry.regular
                                bs.borderEnabled = true
                            end
                            if v == "cropped" then
                                bs.keybindFontSize = 11; bs.keybindOffsetX = 0; bs.keybindOffsetY = 1
                                bs.countFontSize = 11; bs.countOffsetX = 0; bs.countOffsetY = -1
                            else
                                bs.keybindFontSize = 12; bs.keybindOffsetX = 0; bs.keybindOffsetY = 0
                                bs.countFontSize = 12; bs.countOffsetX = 0; bs.countOffsetY = 0
                            end
                            EAB:ApplyShapesForBar(key)
                            EAB:ApplyPaddingForBar(key)
                            EAB:ApplyBordersForBar(key)
                            EAB:ApplyFontsForBar(key)
                        end
                        EAB:RefreshProcGlows()
                        SUpdatePreview()
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SGet("buttonShape") or "none"
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].buttonShape or "none") ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SGet("buttonShape") or "none"
                            for _, key in ipairs(checkedKeys) do
                                local bs = EAB.db.profile.bars[key]
                                bs.iconZoom = ns.SHAPE_ZOOM_DEFAULTS[v] or 5.5
                                bs.buttonShape = v
                                if v ~= "none" and v ~= "cropped" then
                                    bs.borderThickness = ns.BORDER_THICKNESS_DEFAULT_SHAPE
                                    local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_SHAPE]
                                    bs.shapeBorderSize = entry.shape
                                    bs.shapeBorderEnabled = true
                                else
                                    bs.borderThickness = ns.BORDER_THICKNESS_DEFAULT_REGULAR
                                    local entry = ns.BORDER_THICKNESS[ns.BORDER_THICKNESS_DEFAULT_REGULAR]
                                    bs.borderSize = entry.regular
                                    bs.borderEnabled = true
                                end
                                if v == "cropped" then
                                    bs.keybindFontSize = 11; bs.keybindOffsetX = 0; bs.keybindOffsetY = 1
                                    bs.countFontSize = 11; bs.countOffsetX = 0; bs.countOffsetY = -1
                                else
                                    bs.keybindFontSize = 12; bs.keybindOffsetX = 0; bs.keybindOffsetY = 0
                                    bs.countFontSize = 12; bs.countOffsetX = 0; bs.countOffsetY = 0
                                end
                                EAB:ApplyShapesForBar(key)
                                EAB:ApplyPaddingForBar(key)
                                EAB:ApplyBordersForBar(key)
                                EAB:ApplyFontsForBar(key)
                            end
                            EAB:RefreshProcGlows()
                            SUpdatePreview()
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Sync icon: Icon Zoom (right region of classColorBorderRow)
            do
                local rgn = classColorBorderRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Icon Zoom to all Bars",
                    onClick = function()
                        local v = SB().iconZoom or EAB.db.profile.iconZoom or 5.5
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].iconZoom = v
                            EAB:ApplyBordersForBar(key)
                            EAB:ApplyShapesForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().iconZoom or EAB.db.profile.iconZoom or 5.5
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].iconZoom or EAB.db.profile.iconZoom or 5.5) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().iconZoom or EAB.db.profile.iconZoom or 5.5
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].iconZoom = v
                                EAB:ApplyBordersForBar(key)
                                EAB:ApplyShapesForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Row 3: Show Blizzard Icon Background (+ cog) | Show Cooldown Numbers
            -- "Show Cooldown Numbers" is a LIVE toggle of Blizzard's
            -- countdownForCooldowns CVar -- it is never stored in our DB. getValue
            -- reads the CVar; setValue writes it. We only touch the CVar when the
            -- user actively flips the toggle (same approach as the global-settings
            -- CVar controls, e.g. Lag Tolerance).
            local zoomIbgRow
            zoomIbgRow, h = W:DualRow(parent, y,
                { type="toggle", text="Show Blizzard Icon Background",
                  tooltip="Shows Blizzard's default icon slot background texture behind empty action bar slots.",
                  getValue=function() return EAB.db.profile.showBlizzIconBg or false end,
                  setValue=function(v)
                      EAB.db.profile.showBlizzIconBg = v
                      for _, info in ipairs(ns.BAR_CONFIG or {}) do
                          EAB:ApplyIconBackgroundForBar(info.key)
                      end
                      EllesmereUI:RefreshPage()
                  end },
                { type="toggle", text="Show Cooldown Numbers",
                  tooltip="Toggles Blizzard's Show Numbers for Cooldowns setting, which will show number text on any spells that are on cooldown on your action bars.",
                  getValue=function() return GetCVarBool("countdownForCooldowns") end,
                  setValue=function(v)
                      if InCombatLockdown() then return end
                      SetCVar("countdownForCooldowns", v and "1" or "0")
                      -- Refresh so the inline cog dims/undims with the CVar state.
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
            -- Inline cog: Icon Background Opacity (left region)
            do
                local rgn = zoomIbgRow._leftRegion
                local _, ibgCogShow = EllesmereUI.BuildCogPopup({
                    title = "Icon Background",
                    rows = {
                        { type="slider", label="Opacity", min=0, max=100, step=1,
                          tooltip="Controls the opacity of the Blizzard icon slot background texture.",
                          get=function() return math.floor((EAB.db.profile.blizzIconBgAlpha or 1) * 100 + 0.5) end,
                          set=function(v)
                              EAB.db.profile.blizzIconBgAlpha = v / 100
                              for _, info in ipairs(ns.BAR_CONFIG or {}) do
                                  EAB:ApplyIconBackgroundForBar(info.key)
                              end
                          end },
                    },
                })
                local ibgCtrl = rgn._control
                local ibgCogBtn = MakeCogBtn(rgn, ibgCogShow, ibgCtrl, EllesmereUI.COGS_ICON)
                local function IbgOff() return not (EAB.db.profile.showBlizzIconBg or false) end
                ibgCogBtn:SetAlpha(IbgOff() and 0.15 or 0.4)
                ibgCogBtn:SetScript("OnEnter", function(self)
                    if IbgOff() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show Blizzard Icon Background"))
                    else
                        self:SetAlpha(0.7)
                    end
                end)
                ibgCogBtn:SetScript("OnLeave", function(self)
                    EllesmereUI.HideWidgetTooltip()
                    self:SetAlpha(IbgOff() and 0.15 or 0.4)
                end)
                ibgCogBtn:SetScript("OnClick", function(self)
                    if IbgOff() then return end
                    ibgCogShow(self)
                end)
                EllesmereUI.RegisterWidgetRefresh(function()
                    ibgCogBtn:SetAlpha(IbgOff() and 0.15 or 0.4)
                end)
            end
            -- Inline cog: Show Cooldown Numbers (right region). Holds the optional
            -- charge-spell recharge-number toggle (our feature, saved to the DB).
            -- Dimmed when the parent CVar is off (no cooldown numbers show at all).
            do
                local rgn = zoomIbgRow._rightRegion
                local _, cdnCogShow = EllesmereUI.BuildCogPopup({
                    title = "Cooldown Numbers",
                    rows = {
                        { type="toggle", label="Charge Recharge Numbers",
                          tooltip="Show the recharge countdown on charge spells while a charge is still banked. When off, the recharge timer only appears at 0 charges (Blizzard default).",
                          get=function() return EAB.db.profile.showChargeRechargeNumbers ~= false end,
                          set=function(v)
                              EAB.db.profile.showChargeRechargeNumbers = v
                              EAB:RefreshChargeRechargeNumbers()
                          end },
                    },
                })
                local cdnCtrl = rgn._control
                local cdnCogBtn = MakeCogBtn(rgn, cdnCogShow, cdnCtrl, EllesmereUI.COGS_ICON)
                local function CdnOff() return not GetCVarBool("countdownForCooldowns") end
                cdnCogBtn:SetAlpha(CdnOff() and 0.15 or 0.4)
                cdnCogBtn:SetScript("OnEnter", function(self)
                    if CdnOff() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show Cooldown Numbers"))
                    else
                        self:SetAlpha(0.7)
                    end
                end)
                cdnCogBtn:SetScript("OnLeave", function(self)
                    EllesmereUI.HideWidgetTooltip()
                    self:SetAlpha(CdnOff() and 0.15 or 0.4)
                end)
                cdnCogBtn:SetScript("OnClick", function(self)
                    if CdnOff() then return end
                    cdnCogShow(self)
                end)
                EllesmereUI.RegisterWidgetRefresh(function()
                    cdnCogBtn:SetAlpha(CdnOff() and 0.15 or 0.4)
                end)
            end
            -------------------------------------------------------------------
            --  ICON EFFECTS
            -------------------------------------------------------------------
            _, h = W:SectionHeader(parent, "ICON EFFECTS", y);  y = y - h

            -- Row 1: Desaturate on Cooldown | Disable Tooltips
            local dtRow
            dtRow, h = W:DualRow(parent, y,
                { type="toggle", text="Desaturate on Cooldown",
                  tooltip="Desaturates (grays out) action button icons while the ability is on cooldown. GCD-only cooldowns are excluded.",
                  getValue=function() return EAB.db.profile.desaturateOnCooldown or false end,
                  setValue=function(v) EAB.db.profile.desaturateOnCooldown = v end },
                { type="toggle", text="Disable Tooltips",
                  getValue=function()
                      return SGet("disableTooltips") or false
                  end,
                  setValue=function(v)
                      SSet("disableTooltips", v)
                  end });  y = y - h
            -- Sync icon: Disable Tooltips (right)
            do
                local rgn = dtRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Disable Tooltips to all Bars",
                    onClick = function()
                        local v = SB().disableTooltips or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].disableTooltips = v
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().disableTooltips or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].disableTooltips or false) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().disableTooltips or false
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].disableTooltips = v
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Row 3: Out of Range Coloring (+ inline swatch) | Show Item Rank
            local rangeRankRow
            rangeRankRow, h = W:DualRow(parent, y,
                { type="toggle", text="Out of Range Coloring",
                  getValue=function()
                      return SGet("outOfRangeColoring") or false
                  end,
                  setValue=function(v)
                      SSet("outOfRangeColoring", v, function() EAB:ApplyRangeColoring() end)
                      EllesmereUI:RefreshPage()
                  end },
                { type="toggle", text="Show Item Rank",
                  tooltip="Shows the consumable rank (quality) diamond icon on action buttons.",
                  getValue=function() return SGet("showRankIcon") or false end,
                  setValue=function(v)
                      SSet("showRankIcon", v)
                      if _G._EAB_Apply then _G._EAB_Apply() end
                  end });  y = y - h
            -- Sync icon: Out of Range Coloring (left)
            do
                local rgn = rangeRankRow._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Range Coloring to all Bars",
                    onClick = function()
                        local v = SB().outOfRangeColoring or false
                        local c = SB().outOfRangeColor
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].outOfRangeColoring = v
                            if c then EAB.db.profile.bars[key].outOfRangeColor = { r=c.r, g=c.g, b=c.b } end
                        end
                        EAB:ApplyRangeColoring(); EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().outOfRangeColoring or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].outOfRangeColoring or false) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().outOfRangeColoring or false
                            local c = SB().outOfRangeColor
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].outOfRangeColoring = v
                                if c then EAB.db.profile.bars[key].outOfRangeColor = { r=c.r, g=c.g, b=c.b } end
                            end
                            EAB:ApplyRangeColoring(); EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            -- Inline color swatch for range color
            do
                local leftRgn = rangeRankRow._leftRegion
                local rangeColorGet = function()
                    local c = SGet("outOfRangeColor")
                    if not c then return 0.7, 0.2, 0.2 end
                    return c.r, c.g, c.b
                end
                local rangeColorSet = function(r, g, b)
                    SSetColor("outOfRangeColor", r, g, b, nil, function() EAB:ApplyRangeColoring() end)
                end
                local rangeSwatch, rangeUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, rangeColorGet, rangeColorSet, false, 20)
                PP.Point(rangeSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
                leftRgn._lastInline = rangeSwatch

                local function RangeDisabled()
                    return not SGet("outOfRangeColoring")
                end

                EllesmereUI.RegisterWidgetRefresh(function()
                    local off = RangeDisabled()
                    rangeSwatch:SetAlpha(off and 0.3 or 1)
                    rangeUpdateSwatch()
                end)
                rangeSwatch:SetAlpha(RangeDisabled() and 0.3 or 1)

                local rangeBlock = CreateFrame("Frame", nil, rangeSwatch)
                rangeBlock:SetAllPoints()
                rangeBlock:SetFrameLevel(rangeSwatch:GetFrameLevel() + 10)
                rangeBlock:EnableMouse(true)
                rangeBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(rangeSwatch, EllesmereUI.DisabledTooltip("Out of Range Coloring"))
                end)
                rangeBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                EllesmereUI.RegisterWidgetRefresh(function()
                    rangeBlock:SetShown(RangeDisabled())
                end)
                rangeBlock:SetShown(RangeDisabled())
            end
            -- Sync icon: Show Item Rank (right)
            do
                local rgn = rangeRankRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Show Item Rank to all Bars",
                    onClick = function()
                        local v = SB().showRankIcon or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].showRankIcon = v
                        end
                        if _G._EAB_Apply then _G._EAB_Apply() end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().showRankIcon or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].showRankIcon or false) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().showRankIcon or false
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].showRankIcon = v
                            end
                            if _G._EAB_Apply then _G._EAB_Apply() end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Row: Alpha when on CD | CD Swipe Opacity (+ inline colour swatch)
            local cdEffectsRow
            cdEffectsRow, h = W:DualRow(parent, y,
                { type="slider", text="Alpha when on CD", min=0, max=100, step=5,
                  tooltip="Dims action button icons to this opacity while on cooldown (100 = off), using the same detection as Desaturate on Cooldown.",
                  getValue=function() return EAB.db.profile.alphaWhenOnCD or 100 end,
                  setValue=function(v)
                      EAB.db.profile.alphaWhenOnCD = v
                      if EAB.ApplyCDAlphaAll then EAB:ApplyCDAlphaAll() end
                  end },
                { type="slider", text="CD Swipe Opacity", min=0, max=100, step=5,
                  tooltip="Opacity of the cooldown swipe (the dark radial sweep); use the swatch to set its colour.",
                  getValue=function() return EAB.db.profile.cdSwipeAlpha or 80 end,
                  setValue=function(v)
                      EAB.db.profile.cdSwipeAlpha = v
                      if EAB.ApplyCooldownSwipeColor then EAB:ApplyCooldownSwipeColor() end
                  end });  y = y - h
            -- Inline colour swatch for CD Swipe Opacity (right region). Alpha lives on
            -- the slider, so the swatch is colour-only (hasAlpha = false).
            do
                local rgn = cdEffectsRow._rightRegion
                local ctrl = rgn._control
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, cdEffectsRow:GetFrameLevel() + 5,
                    function()
                        local c = EAB.db.profile.cdSwipeColor or {}
                        return c.r or 0, c.g or 0, c.b or 0
                    end,
                    function(r, g, b)
                        EAB.db.profile.cdSwipeColor = { r = r, g = g, b = b }
                        if EAB.ApplyCooldownSwipeColor then EAB:ApplyCooldownSwipeColor() end
                    end,
                    false, 20)
                PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
                rgn._lastInline = swatch
                -- Auto-disable the swatch at 0 opacity (an invisible swipe has no
                -- visible colour), matching the canonical inline-swatch pattern.
                local function SwipeDisabled()
                    return (EAB.db.profile.cdSwipeAlpha or 80) == 0
                end
                local block = CreateFrame("Frame", nil, swatch)
                block:SetAllPoints(); block:SetFrameLevel(swatch:GetFrameLevel() + 10); block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Set CD Swipe Opacity above 0"))
                end)
                block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                EllesmereUI.RegisterWidgetRefresh(function()
                    updateSwatch()
                    local off = SwipeDisabled()
                    swatch:SetAlpha(off and 0.3 or 1)
                    block:SetShown(off)
                end)
                local off0 = SwipeDisabled()
                swatch:SetAlpha(off0 and 0.3 or 1)
                block:SetShown(off0)
            end

            BuildBarBackgroundSection()

            -------------------------------------------------------------------
            --  PAGING (MainBar + Bars 2-8 only, not Stance/Pet/Micro/Bag)
            -------------------------------------------------------------------
            do
                local selKey = SelectedKey()
                local _bkp = ns.EAB_VTABLE and ns.EAB_VTABLE.BAR_KEY_TO_PAGE
                local showPaging = selKey and _bkp and _bkp[selKey]
                if showPaging then
                    _, h = W:SectionHeader(parent, "PAGING", y);  y = y - h

                    local _, playerClass = UnitClass("player")
                    local EAB_VT = ns.EAB_VTABLE or {}
                    local PG_STATES = EAB_VT.PAGING_STATES or {}
                    local BKP = EAB_VT.BAR_KEY_TO_PAGE or {}

                    -- Build dropdown values: None, Bar 1-8
                    local pagingValues = { none = "Default" }
                    local pagingOrder = { "none" }
                    local barList = {
                        { key = "MainBar", label = "Action Bar 1 (Main)" },
                        { key = "Bar2",    label = "Action Bar 2" },
                        { key = "Bar3",    label = "Action Bar 3" },
                        { key = "Bar4",    label = "Action Bar 4" },
                        { key = "Bar5",    label = "Action Bar 5" },
                        { key = "Bar6",    label = "Action Bar 6" },
                        { key = "Bar7",    label = "Action Bar 7" },
                        { key = "Bar8",    label = "Action Bar 8" },
                        { key = "Bar9",    label = "Action Bar 9" },
                        { key = "Bar10",   label = "Action Bar 10" },
                    }
                    for _, bl in ipairs(barList) do
                        -- Skip self (can't page a bar to itself)
                        if bl.key ~= selKey then
                            local pg = BKP[bl.key]
                            if pg then
                                pagingValues[tostring(pg)] = bl.label
                                pagingOrder[#pagingOrder + 1] = tostring(pg)
                            end
                        end
                    end

                    local function GetPagingVal(stateId)
                        local paging = SGet("paging")
                        if not paging then return "none" end
                        local v = paging[stateId]
                        if not v then return "none" end
                        return tostring(v)
                    end
                    local function SetPagingVal(stateId, val)
                        local bars = EAB.db.profile.bars[selKey]
                        if not bars.paging then bars.paging = {} end
                        if val == "none" then
                            bars.paging[stateId] = false
                        else
                            bars.paging[stateId] = tonumber(val)
                        end
                        -- Clean up: if all values are false (all disabled), reset
                        local anySet = false
                        for _, v in pairs(bars.paging) do
                            if v then anySet = true; break end
                        end
                        if not anySet then bars.paging = {} end
                        if ns.RebuildBarPaging then ns.RebuildBarPaging(selKey) end
                    end

                    -- Row 1: Show Paging Arrows (+ inline cog) | Shift Modifier
                    local pagingArrowsWidget
                    if selKey == "MainBar" then
                        pagingArrowsWidget = { type="toggle", text="Show Paging Arrows",
                          getValue=function() return SGet("showPagingArrows") or false end,
                          setValue=function(v)
                              SSet("showPagingArrows", v, function()
                                  if ns.LayoutPagingFrame then ns.LayoutPagingFrame() end
                              end)
                              EllesmereUI:RefreshPage()
                          end,
                          tooltip="Show page up/down arrows next to Action Bar 1 for cycling through action bar pages 1-6." }
                    else
                        pagingArrowsWidget = { type="label", text="" }
                    end
                    local pagingRow
                    pagingRow, h = W:DualRow(parent, y,
                        pagingArrowsWidget,
                        { type="dropdown", text="Shift Modifier",
                          values=pagingValues, order=pagingOrder,
                          getValue=function() return GetPagingVal("shift") end,
                          setValue=function(v) SetPagingVal("shift", v) end });  y = y - h

                    -- Inline cog on Show Paging Arrows (left region, MainBar only)
                    if selKey == "MainBar" then
                        local lRgn = pagingRow._leftRegion
                        local pagingOff = function() return not (SGet("showPagingArrows") or false) end
                        local _, pagingCogShow = EllesmereUI.BuildCogPopup({
                            title = "Paging Arrow Settings",
                            rows = {
                                { type="toggle", label="Show Arrows on Right",
                                  get=function() return SGet("pagingArrowsRight") or false end,
                                  set=function(v)
                                      SSet("pagingArrowsRight", v, function()
                                          if ns.LayoutPagingFrame then ns.LayoutPagingFrame() end
                                      end)
                                  end },
                            },
                        })
                        local pagingCogBtn = MakeCogBtn(lRgn, pagingCogShow)
                        local pagingCogBlock = CreateFrame("Frame", nil, pagingCogBtn)
                        pagingCogBlock:SetAllPoints()
                        pagingCogBlock:SetFrameLevel(pagingCogBtn:GetFrameLevel() + 10)
                        pagingCogBlock:EnableMouse(true)
                        pagingCogBlock:SetScript("OnEnter", function()
                            EllesmereUI.ShowWidgetTooltip(pagingCogBtn, EllesmereUI.DisabledTooltip("Show Paging Arrows"))
                        end)
                        pagingCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                        EllesmereUI.RegisterWidgetRefresh(function()
                            local off = pagingOff()
                            pagingCogBtn:SetAlpha(off and 0.15 or 0.4)
                            if off then pagingCogBlock:Show() else pagingCogBlock:Hide() end
                        end)
                        local initOff = pagingOff()
                        pagingCogBtn:SetAlpha(initOff and 0.15 or 0.4)
                        if initOff then pagingCogBlock:Show() else pagingCogBlock:Hide() end
                    end

                    -- Row 2: Ctrl Modifier | Alt Modifier
                    _, h = W:DualRow(parent, y,
                        { type="dropdown", text="Ctrl Modifier",
                          values=pagingValues, order=pagingOrder,
                          getValue=function() return GetPagingVal("ctrl") end,
                          setValue=function(v) SetPagingVal("ctrl", v) end },
                        { type="dropdown", text="Alt Modifier",
                          values=pagingValues, order=pagingOrder,
                          getValue=function() return GetPagingVal("alt") end,
                          setValue=function(v) SetPagingVal("alt", v) end });  y = y - h

                    -- Row 3: Friendly Target | Hostile Target
                    _, h = W:DualRow(parent, y,
                        { type="dropdown", text="Friendly Target",
                          values=pagingValues, order=pagingOrder,
                          getValue=function() return GetPagingVal("help") end,
                          setValue=function(v) SetPagingVal("help", v) end },
                        { type="dropdown", text="Hostile Target",
                          values=pagingValues, order=pagingOrder,
                          getValue=function() return GetPagingVal("harm") end,
                          setValue=function(v) SetPagingVal("harm", v) end });  y = y - h

                    -- Class form dropdowns (paired into DualRows)
                    local classStatesLocal = PG_STATES.class and PG_STATES.class[playerClass]
                    if classStatesLocal then
                        for i = 1, #classStatesLocal, 2 do
                            local left = classStatesLocal[i]
                            local right = classStatesLocal[i + 1]
                            local rightWidget
                            if right then
                                rightWidget = { type="dropdown", text=right.label,
                                  values=pagingValues, order=pagingOrder,
                                  getValue=function() return GetPagingVal(right.id) end,
                                  setValue=function(v) SetPagingVal(right.id, v) end }
                            else
                                rightWidget = { type="label", text="" }
                            end
                            _, h = W:DualRow(parent, y,
                                { type="dropdown", text=left.label,
                                  values=pagingValues, order=pagingOrder,
                                  getValue=function() return GetPagingVal(left.id) end,
                                  setValue=function(v) SetPagingVal(left.id, v) end },
                                rightWidget);  y = y - h
                        end
                    end
                end
            end

            _, h = W:Spacer(parent, y, 20);  y = y - h

            -------------------------------------------------------------------
            --  TEXT
            -------------------------------------------------------------------
            textSectionHeader, h = W:SectionHeader(parent, SECTION_TEXT, y);  y = y - h

            -- Row 1: Hide Keybind Text (left) | Keybind Text Size slider + inline swatch (right)
            row, h = W:DualRow(parent, y,
                { type="toggle", text="Hide Keybind Text",
                  getValue=function()
                      return SGet("hideKeybind")
                  end,
                  setValue=function(v)
                      SSet("hideKeybind", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", text="Keybind Text Size", min=6, max=30, step=1, trackWidth=120,
                  getValue=function() return SVal("keybindFontSize", 12) end,
                  setValue=function(v)
                      SSet("keybindFontSize", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end });  y = y - h
            keybindRow = row
            -- Sync icon: Hide Keybind Text (left region)
            do
                local rgn = row._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Keybind Visibility to all Bars",
                    onClick = function()
                        local v = SB().hideKeybind
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].hideKeybind = v
                            EAB:ApplyFontsForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().hideKeybind or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].hideKeybind or false) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().hideKeybind
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].hideKeybind = v
                                EAB:ApplyFontsForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            -- Sync icon: Keybind Text Color (right region)
            do
                local rgn = keybindRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Keybind Text Settings to all Bars",
                    onClick = function()
                        local s = SB()
                        local c = s.keybindFontColor
                        local sz = s.keybindFontSize or 12
                        local ox = s.keybindOffsetX or 0
                        local oy = s.keybindOffsetY or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if c then EAB.db.profile.bars[key].keybindFontColor = { r=c.r, g=c.g, b=c.b } end
                            EAB.db.profile.bars[key].keybindFontSize = sz
                            EAB.db.profile.bars[key].keybindOffsetX = ox
                            EAB.db.profile.bars[key].keybindOffsetY = oy
                            EAB:ApplyFontsForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local s = SB()
                        local sz = s.keybindFontSize or 12
                        local c = s.keybindFontColor
                        local ox = s.keybindOffsetX or 0
                        local oy = s.keybindOffsetY or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local b = EAB.db.profile.bars[key]
                            if (b.keybindFontSize or 12) ~= sz then return false end
                            if (b.keybindOffsetX or 0) ~= ox then return false end
                            if (b.keybindOffsetY or 0) ~= oy then return false end
                            if c then
                                local bc = b.keybindFontColor
                                if not bc or bc.r ~= c.r or bc.g ~= c.g or bc.b ~= c.b then return false end
                            end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local s = SB()
                            local c = s.keybindFontColor
                            local sz = s.keybindFontSize or 12
                            local ox = s.keybindOffsetX or 0
                            local oy = s.keybindOffsetY or 0
                            for _, key in ipairs(checkedKeys) do
                                if c then EAB.db.profile.bars[key].keybindFontColor = { r=c.r, g=c.g, b=c.b } end
                                EAB.db.profile.bars[key].keybindFontSize = sz
                                EAB.db.profile.bars[key].keybindOffsetX = ox
                                EAB.db.profile.bars[key].keybindOffsetY = oy
                                EAB:ApplyFontsForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Inline color swatch + directions cog for Keybind Text (right region)
            do
                local rgn = keybindRow._rightRegion
                local ctrl = rgn._control
                local kbSwatch, kbUpdateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, keybindRow:GetFrameLevel() + 3,
                    function()
                        local c = SGet("keybindFontColor")
                        if not c then return 1, 1, 1 end
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        SSetColor("keybindFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                        SUpdatePreview()
                    end,
                    false, 20)
                PP.Point(kbSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
                rgn._lastInline = kbSwatch
                EllesmereUI.RegisterWidgetRefresh(function() kbUpdateSwatch() end)

                local _, kbCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Keybind Text Offsets",
                    rows = {
                        { type="slider", label="X Offset", min=-150, max=150, step=1,
                          get=function() return SVal("keybindOffsetX", 0) end,
                          set=function(v)
                              SSet("keybindOffsetX", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="Y Offset", min=-150, max=150, step=1,
                          get=function() return SVal("keybindOffsetY", 0) end,
                          set=function(v)
                              SSet("keybindOffsetY", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                    },
                })
                MakeCogBtn(rgn, kbCogShowRaw, kbSwatch, EllesmereUI.DIRECTIONS_ICON)
            end

            -- Row 2: Hide Macro Text (left) | Macro Text Size slider + inline swatch (right)
            local macroRow
            macroRow, h = W:DualRow(parent, y,
                { type="toggle", text="Hide Macro Text",
                  getValue=function()
                      return SGet("hideMacroText")
                  end,
                  setValue=function(v)
                      SSet("hideMacroText", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", text="Macro Text Size", min=6, max=30, step=1, trackWidth=120,
                  getValue=function() return SVal("macroFontSize", 12) end,
                  setValue=function(v)
                      SSet("macroFontSize", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end });  y = y - h
            -- Sync icon: Hide Macro Text (left region)
            do
                local rgn = macroRow._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Macro Text Visibility to all Bars",
                    onClick = function()
                        local v = SB().hideMacroText
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].hideMacroText = v
                            EAB:ApplyFontsForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().hideMacroText or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].hideMacroText or false) ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().hideMacroText
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].hideMacroText = v
                                EAB:ApplyFontsForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            -- Sync icon: Macro Text Settings (right region)
            do
                local rgn = macroRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Macro Text Settings to all Bars",
                    onClick = function()
                        local s = SB()
                        local c = s.macroFontColor
                        local sz = s.macroFontSize or 12
                        local ox = s.macroOffsetX or 0
                        local oy = s.macroOffsetY or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if c then EAB.db.profile.bars[key].macroFontColor = { r=c.r, g=c.g, b=c.b } end
                            EAB.db.profile.bars[key].macroFontSize = sz
                            EAB.db.profile.bars[key].macroOffsetX = ox
                            EAB.db.profile.bars[key].macroOffsetY = oy
                            EAB:ApplyFontsForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local s = SB()
                        local sz = s.macroFontSize or 12
                        local c = s.macroFontColor
                        local ox = s.macroOffsetX or 0
                        local oy = s.macroOffsetY or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local b = EAB.db.profile.bars[key]
                            if (b.macroFontSize or 12) ~= sz then return false end
                            if (b.macroOffsetX or 0) ~= ox then return false end
                            if (b.macroOffsetY or 0) ~= oy then return false end
                            if c then
                                local bc = b.macroFontColor
                                if not bc or bc.r ~= c.r or bc.g ~= c.g or bc.b ~= c.b then return false end
                            end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local s = SB()
                            local c = s.macroFontColor
                            local sz = s.macroFontSize or 12
                            local ox = s.macroOffsetX or 0
                            local oy = s.macroOffsetY or 0
                            for _, key in ipairs(checkedKeys) do
                                if c then EAB.db.profile.bars[key].macroFontColor = { r=c.r, g=c.g, b=c.b } end
                                EAB.db.profile.bars[key].macroFontSize = sz
                                EAB.db.profile.bars[key].macroOffsetX = ox
                                EAB.db.profile.bars[key].macroOffsetY = oy
                                EAB:ApplyFontsForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Inline color swatch + directions cog for Macro Text (right region)
            do
                local rgn = macroRow._rightRegion
                local ctrl = rgn._control
                local mcSwatch, mcUpdateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, macroRow:GetFrameLevel() + 3,
                    function()
                        local c = SGet("macroFontColor")
                        if not c then return 1, 1, 1 end
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        SSetColor("macroFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                        SUpdatePreview()
                    end,
                    false, 20)
                PP.Point(mcSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
                rgn._lastInline = mcSwatch
                EllesmereUI.RegisterWidgetRefresh(function() mcUpdateSwatch() end)

                local _, mcCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Macro Text Offsets",
                    rows = {
                        { type="slider", label="X Offset", min=-150, max=150, step=1,
                          get=function() return SVal("macroOffsetX", 0) end,
                          set=function(v)
                              SSet("macroOffsetX", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="Y Offset", min=-150, max=150, step=1,
                          get=function() return SVal("macroOffsetY", 0) end,
                          set=function(v)
                              SSet("macroOffsetY", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                    },
                })
                MakeCogBtn(rgn, mcCogShowRaw, mcSwatch, EllesmereUI.DIRECTIONS_ICON)
            end

            -- Row 3: Charges Text Size slider + inline swatch (left) | Cooldown Text Size slider + inline swatch (right)
            chargesRow, h = W:DualRow(parent, y,
                { type="slider", text="Charges Text Size", min=6, max=30, step=1, trackWidth=120,
                  getValue=function() return SVal("countFontSize", 12) end,
                  setValue=function(v)
                      SSet("countFontSize", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="slider", text="Cooldown Text Size", min=6, max=30, step=1, trackWidth=120,
                  getValue=function() return SVal("cooldownFontSize", 12) end,
                  setValue=function(v)
                      SSet("cooldownFontSize", v, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                      SUpdatePreview()
                  end });  y = y - h
            -- Sync icon: Charges Text (left region)
            do
                local rgn = chargesRow._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Charges Text Settings to all Bars",
                    onClick = function()
                        local s = SB()
                        local c = s.countFontColor
                        local sz = s.countFontSize or 12
                        local ox = s.countOffsetX or 0
                        local oy = s.countOffsetY or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if c then EAB.db.profile.bars[key].countFontColor = { r=c.r, g=c.g, b=c.b } end
                            EAB.db.profile.bars[key].countFontSize = sz
                            EAB.db.profile.bars[key].countOffsetX = ox
                            EAB.db.profile.bars[key].countOffsetY = oy
                            EAB:ApplyFontsForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local s = SB()
                        local sz = s.countFontSize or 12
                        local c = s.countFontColor
                        local ox = s.countOffsetX or 0
                        local oy = s.countOffsetY or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local b = EAB.db.profile.bars[key]
                            if (b.countFontSize or 12) ~= sz then return false end
                            if (b.countOffsetX or 0) ~= ox then return false end
                            if (b.countOffsetY or 0) ~= oy then return false end
                            if c then
                                local bc = b.countFontColor
                                if not bc or bc.r ~= c.r or bc.g ~= c.g or bc.b ~= c.b then return false end
                            end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local s = SB()
                            local c = s.countFontColor
                            local sz = s.countFontSize or 12
                            local ox = s.countOffsetX or 0
                            local oy = s.countOffsetY or 0
                            for _, key in ipairs(checkedKeys) do
                                if c then EAB.db.profile.bars[key].countFontColor = { r=c.r, g=c.g, b=c.b } end
                                EAB.db.profile.bars[key].countFontSize = sz
                                EAB.db.profile.bars[key].countOffsetX = ox
                                EAB.db.profile.bars[key].countOffsetY = oy
                                EAB:ApplyFontsForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Inline color swatch + directions cog for Charges Text (left region)
            do
                local rgn = chargesRow._leftRegion
                local ctrl = rgn._control
                local ctSwatch, ctUpdateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, chargesRow:GetFrameLevel() + 3,
                    function()
                        local c = SGet("countFontColor")
                        if not c then return 1, 1, 1 end
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        SSetColor("countFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                        SUpdatePreview()
                    end,
                    false, 20)
                PP.Point(ctSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
                rgn._lastInline = ctSwatch
                EllesmereUI.RegisterWidgetRefresh(function() ctUpdateSwatch() end)

                local _, ctCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Charges Text Offsets",
                    rows = {
                        { type="slider", label="X Offset", min=-150, max=150, step=1,
                          get=function() return SVal("countOffsetX", 0) end,
                          set=function(v)
                              SSet("countOffsetX", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="Y Offset", min=-150, max=150, step=1,
                          get=function() return SVal("countOffsetY", 0) end,
                          set=function(v)
                              SSet("countOffsetY", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                    },
                })
                MakeCogBtn(rgn, ctCogShowRaw, ctSwatch, EllesmereUI.DIRECTIONS_ICON)
            end

            -- Sync icon: Cooldown Text (right region of row 2)
            do
                local rgn = chargesRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Cooldown Text Settings to all Bars",
                    onClick = function()
                        local s = SB()
                        local c = s.cooldownTextColor
                        local sz = s.cooldownFontSize or 12
                        local ox = s.cooldownTextXOffset or 0
                        local oy = s.cooldownTextYOffset or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if c then EAB.db.profile.bars[key].cooldownTextColor = { r=c.r, g=c.g, b=c.b } end
                            EAB.db.profile.bars[key].cooldownFontSize = sz
                            EAB.db.profile.bars[key].cooldownTextXOffset = ox
                            EAB.db.profile.bars[key].cooldownTextYOffset = oy
                            EAB:ApplyCooldownFontsForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local s = SB()
                        local sz = s.cooldownFontSize or 12
                        local c = s.cooldownTextColor
                        local ox = s.cooldownTextXOffset or 0
                        local oy = s.cooldownTextYOffset or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local b = EAB.db.profile.bars[key]
                            if (b.cooldownFontSize or 12) ~= sz then return false end
                            if (b.cooldownTextXOffset or 0) ~= ox then return false end
                            if (b.cooldownTextYOffset or 0) ~= oy then return false end
                            if c then
                                local bc = b.cooldownTextColor
                                if not bc or bc.r ~= c.r or bc.g ~= c.g or bc.b ~= c.b then return false end
                            end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local s = SB()
                            local c = s.cooldownTextColor
                            local sz = s.cooldownFontSize or 12
                            local ox = s.cooldownTextXOffset or 0
                            local oy = s.cooldownTextYOffset or 0
                            for _, key in ipairs(checkedKeys) do
                                if c then EAB.db.profile.bars[key].cooldownTextColor = { r=c.r, g=c.g, b=c.b } end
                                EAB.db.profile.bars[key].cooldownFontSize = sz
                                EAB.db.profile.bars[key].cooldownTextXOffset = ox
                                EAB.db.profile.bars[key].cooldownTextYOffset = oy
                                EAB:ApplyCooldownFontsForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Inline color swatch + directions cog for Cooldown Text (right region)
            do
                local rgn = chargesRow._rightRegion
                local ctrl = rgn._control
                local cdSwatch, cdUpdateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, chargesRow:GetFrameLevel() + 3,
                    function()
                        local c = SGet("cooldownTextColor")
                        if not c then return 1, 1, 1 end
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        SSetColor("cooldownTextColor", r, g, b, nil, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                        SUpdatePreview()
                    end,
                    false, 20)
                PP.Point(cdSwatch, "RIGHT", ctrl, "LEFT", -12, 0)
                rgn._lastInline = cdSwatch
                EllesmereUI.RegisterWidgetRefresh(function() cdUpdateSwatch() end)

                local _, cdCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Cooldown Text Offsets",
                    rows = {
                        { type="slider", label="X Offset", min=-150, max=150, step=1,
                          get=function() return SVal("cooldownTextXOffset", 0) end,
                          set=function(v)
                              SSet("cooldownTextXOffset", v, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="Y Offset", min=-150, max=150, step=1,
                          get=function() return SVal("cooldownTextYOffset", 0) end,
                          set=function(v)
                              SSet("cooldownTextYOffset", v, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                    },
                })
                MakeCogBtn(rgn, cdCogShowRaw, cdSwatch, EllesmereUI.DIRECTIONS_ICON)
            end

            _, h = W:Spacer(parent, y, 20);  y = y - h

            -------------------------------------------------------------------
            --  CLICK NAVIGATION
            -------------------------------------------------------------------
            local glowFrame
            local function PlaySettingGlow(targetFrame)
                if not targetFrame then return end
                if not glowFrame then
                    glowFrame = CreateFrame("Frame")
                    local c = EllesmereUI.ELLESMERE_GREEN
                    local function MkEdge()
                        local t = glowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                        t:SetColorTexture(c.r, c.g, c.b, 1)
                        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
                        return t
                    end
                    glowFrame._top = MkEdge()
                    glowFrame._bot = MkEdge()
                    glowFrame._lft = MkEdge()
                    glowFrame._rgt = MkEdge()
                    local glowPx = PP.Scale(2)
                    glowFrame._top:SetHeight(glowPx)
                    glowFrame._top:SetPoint("TOPLEFT"); glowFrame._top:SetPoint("TOPRIGHT")
                    glowFrame._bot:SetHeight(glowPx)
                    glowFrame._bot:SetPoint("BOTTOMLEFT"); glowFrame._bot:SetPoint("BOTTOMRIGHT")
                    glowFrame._lft:SetWidth(glowPx)
                    glowFrame._lft:SetPoint("TOPLEFT", glowFrame._top, "BOTTOMLEFT")
                    glowFrame._lft:SetPoint("BOTTOMLEFT", glowFrame._bot, "TOPLEFT")
                    glowFrame._rgt:SetWidth(glowPx)
                    glowFrame._rgt:SetPoint("TOPRIGHT", glowFrame._top, "BOTTOMRIGHT")
                    glowFrame._rgt:SetPoint("BOTTOMRIGHT", glowFrame._bot, "TOPRIGHT")
                end
                glowFrame:SetParent(targetFrame)
                glowFrame:SetAllPoints(targetFrame)
                glowFrame:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
                glowFrame:SetAlpha(1)
                glowFrame:Show()
                local elapsed = 0
                glowFrame:SetScript("OnUpdate", function(self, dt)
                    elapsed = elapsed + dt
                    if elapsed >= 0.75 then
                        self:Hide(); self:SetScript("OnUpdate", nil); return
                    end
                    self:SetAlpha(1 - elapsed / 0.75)
                end)
            end

            local clickMappings = {
                icon       = { section = iconsSectionHeader, target = classColorBorderRow },
                keybind    = { section = textSectionHeader,  target = keybindRow, slotSide = "right" },
                charges    = { section = textSectionHeader,  target = chargesRow, slotSide = "left" },
            }

            local function NavigateToSetting(key)
                local m = clickMappings[key]
                if not m or not m.section or not m.target then return end

                -- Dismiss hint
                local hintFS = _abPreviewHintFS
                local headerBaseH = barsHeaderBaseH
                if not IsPreviewHintDismissed() and hintFS and hintFS:IsShown() then
                    EllesmereUIDB = EllesmereUIDB or {}
                    EllesmereUIDB.previewHintDismissed = true
                    local hint = hintFS
                    local _, anchorTo, _, _, startY = hint:GetPoint(1)
                    startY = startY or 17
                    anchorTo = anchorTo or hint:GetParent()
                    local hintSize = 29
                    local startHeaderH = headerBaseH + hintSize
                    local targetHeaderH = headerBaseH
                    local steps = 0
                    local ticker
                    ticker = C_Timer.NewTicker(0.016, function()
                        steps = steps + 1
                        local progress = steps * 0.016 / 0.3
                        if progress >= 1 then
                            hint:Hide(); ticker:Cancel()
                            if targetHeaderH > 0 then EllesmereUI:SetContentHeaderHeightSilent(targetHeaderH) end
                            return
                        end
                        hint:SetAlpha(0.45 * (1 - progress))
                        hint:ClearAllPoints()
                        hint:SetPoint("BOTTOM", anchorTo, "BOTTOM", 0, startY + progress * 12)
                        local hh = startHeaderH - hintSize * progress
                        if hh > 0 then EllesmereUI:SetContentHeaderHeightSilent(hh) end
                    end)
                end

                local sf = EllesmereUI._scrollFrame
                if not sf then return end
                local _, _, _, _, headerY = m.section:GetPoint(1)
                if not headerY then return end
                local scrollPos = math.max(0, math.abs(headerY) - 40)
                EllesmereUI.SmoothScrollTo(scrollPos)
                local glowTarget = m.target
                if m.slotSide and m.target then
                    local region = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
                    if region then glowTarget = region end
                end
                C_Timer.After(0.15, function() PlaySettingGlow(glowTarget) end)
            end

            -- Hit overlay factory
            local function CreateHitOverlay(element, mappingKey, isText, frameLevelOverride, opts)
                local anchor = isText and element:GetParent() or element
                if not anchor.CreateTexture then anchor = anchor:GetParent() end
                local btn = CreateFrame("Button", nil, anchor)
                if isText then
                    local function ResizeToText()
                        local ok, tw, th = pcall(function()
                            local w = element:GetStringWidth() or 0
                            local hh = element:GetStringHeight() or 0
                            if w < 1 then w = 1 end
                            if hh < 1 then hh = 1 end
                            return w, hh
                        end)
                        if not ok then tw = 40; th = 12 end
                        btn:SetSize(tw + 2, th + 2)
                    end
                    ResizeToText()
                    local justify = element:GetJustifyH()
                    if justify == "RIGHT" then btn:SetPoint("RIGHT", element, "RIGHT", 0, 0)
                    elseif justify == "CENTER" then btn:SetPoint("CENTER", element, "CENTER", -1, 0)
                    else btn:SetPoint("LEFT", element, "LEFT", -2, 0) end
                    btn:SetScript("OnShow", function() ResizeToText() end)
                    btn._resizeToText = ResizeToText
                else
                    btn:SetAllPoints(opts and opts.hlAnchor or element)
                end
                btn:SetFrameLevel(frameLevelOverride or (anchor:GetFrameLevel() + 20))
                btn:RegisterForClicks("LeftButtonDown")
                local c = EllesmereUI.ELLESMERE_GREEN
                local hlTarget = (opts and opts.hlBehindText) and element or (opts and opts.hlAnchor) or btn
                local brd = EllesmereUI.PP.CreateBorder(hlTarget, c.r, c.g, c.b, 1, 2, "OVERLAY", 7)
                brd:Hide()
                btn:SetScript("OnEnter", function() brd:Show() end)
                btn:SetScript("OnLeave", function() brd:Hide() end)
                btn:SetScript("OnMouseDown", function() NavigateToSetting(mappingKey) end)
                return btn
            end

            -- Create hit overlays on preview elements
            local textOverlays = {}
            if activePreview then
                local pv = activePreview
                local pvButtons = pv._buttons
                local iconLevel = (pvButtons[1] and pvButtons[1].frame and pvButtons[1].frame:GetFrameLevel() or 5) + 10
                local textOnIconLevel = iconLevel + 10
                local iconHlOpts = { hlBehindText = true }
                for i = 1, pv._barInfo.count do
                    local entry = pvButtons[i]
                    if entry and entry.frame then
                        CreateHitOverlay(entry.frame, "icon", false, iconLevel, iconHlOpts)
                        if entry.keybind then
                            textOverlays[#textOverlays + 1] = CreateHitOverlay(entry.keybind, "keybind", true, textOnIconLevel)
                        end
                        if entry.count then
                            textOverlays[#textOverlays + 1] = CreateHitOverlay(entry.count, "charges", true, textOnIconLevel)
                        end
                    end
                end
                pv._textOverlays = textOverlays
            end
        end  -- if not visOnly

        return y
    end

    local function BuildBarDisplayPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        activePreview = nil

        -- Consume any pending bar selection from Element Options navigation.
        if EllesmereUI._consumePendingActionBarSelect then EllesmereUI._consumePendingActionBarSelect() end

        -- Tag every option registered while building this page with the
        -- currently-selected bar, so a global-search jump to a bar-specific
        -- setting can restore this exact bar selection first via
        -- EllesmereUI._setActionBarKey -- see EUI_CooldownManager_Options.lua's
        -- matching EllesmereUI._buildingSelector comment for the full reasoning.
        EllesmereUI._buildingSelector = { setter = EllesmereUI._setActionBarKey, key = SelectedKey() }

        -- Show edit overlay for the currently selected bar
        ShowEditOverlay(SelectedKey())

        -------------------------------------------------------------------
        --  CONTENT HEADER  (dropdown + preview)
        -------------------------------------------------------------------
        _barsHeaderBuilder = function(hdr, hdrW)
            local PAD = EllesmereUI.CONTENT_PAD
            local PV_PAD = 10  -- internal padding inside BuildLivePreview
            local fy = -20

            -- Centered dropdown (same pattern as Multi Bar Edit)
            local DD_H = 34
            local availW = hdrW - PAD * 2
            local ddW = 350
            local ddBtn, ddLbl = EllesmereUI.BuildDropdownControl(
                hdr, ddW, hdr:GetFrameLevel() + 5,
                barLabels, barOrder,
                function() return SelectedKey() end,
                function(v)
                    _selectedBarKey = v
                    EllesmereUI:InvalidateContentHeaderCache()
                    EllesmereUI:SetContentHeader(_barsHeaderBuilder)
                    -- Always force full rebuild — visibility-only bars and
                    -- StanceBar share the same visOnly/dataBar flags, so the
                    -- old conditional missed transitions between them.
                    EllesmereUI:RefreshPage(true)
                    -- Show/hide edit overlay for the newly selected bar
                    ShowEditOverlay(v)
                end,
                function(key)
                    -- Bar9/Bar10 default to Hidden visibility, but must stay
                    -- selectable in this dropdown so the user can pick and
                    -- configure them -- never show the disabled effect on them.
                    if key == "Bar9" or key == "Bar10" then return nil end
                    if not IsBarEnabled(key) then return EllesmereUI.DisabledTooltip("this action bar") end
                end
            )
            PP.Point(ddBtn, "TOP", hdr, "TOP", 0, fy)
            ddBtn:SetHeight(DD_H)
            fy = fy - DD_H - PV_PAD

            local previewH = BuildLivePreview(hdr, fy)
            fy = fy - previewH - PV_PAD

            headerFixedH = 20 + DD_H + PV_PAD + PV_PAD

            if _abPreviewHintFS and not _abPreviewHintFS:GetParent() then
                _abPreviewHintFS = nil
            end
            local hintH = 0
            if not IsPreviewHintDismissed() then
                if not _abPreviewHintFS then
                    local hintHost = CreateFrame("Frame", nil, hdr)
                    hintHost:SetAllPoints(hdr)
                    _abPreviewHintFS = EllesmereUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                    _abPreviewHintFS:SetAlpha(0.45)
                    _abPreviewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
                end
                _abPreviewHintFS:GetParent():SetParent(hdr)
                _abPreviewHintFS:GetParent():Show()
                _abPreviewHintFS:ClearAllPoints()
                _abPreviewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 17)
                _abPreviewHintFS:SetAlpha(0.45)
                _abPreviewHintFS:Show()
                hintH = 29
            elseif _abPreviewHintFS then
                _abPreviewHintFS:Hide()
            end

            barsHeaderBaseH = math.abs(fy)
            return barsHeaderBaseH + hintH
        end
        EllesmereUI:SetContentHeader(_barsHeaderBuilder)

        -------------------------------------------------------------------
        --  Top action buttons: Quick Keybind + Blizzard/EUI Style toggle
        -------------------------------------------------------------------
        do
            local BTN_W = 312
            local BTN_H = 38
            local GAP = 40
            local ROW_H = BTN_H + 20
            local rowFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(rowFrame, totalW, ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)

            -- Quick Keybind Mode button (left)
            local qkbBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(qkbBtn, BTN_W, BTN_H)
            PP.Point(qkbBtn, "RIGHT", rowFrame, "CENTER", -(GAP / 2), 0)
            qkbBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 1)
            EllesmereUI.MakeStyledButton(qkbBtn, "Quick Keybind Mode (/kb)", 14,
                EllesmereUI.WB_COLOURS, function()
                    if InCombatLockdown() then return end
                    if not C_AddOns.IsAddOnLoaded("Blizzard_QuickKeybind") then
                        C_AddOns.LoadAddOn("Blizzard_QuickKeybind")
                    end
                    if QuickKeybindFrame then
                        EllesmereUI:Toggle()
                        QuickKeybindFrame:Show()
                    end
                end)

            -- Blizzard / EUI Style toggle button (right)
            local isBlizz = EAB.db and EAB.db.profile and EAB.db.profile.useBlizzardStyle
            local styleBtn = CreateFrame("Button", nil, rowFrame)
            PP.Size(styleBtn, BTN_W, BTN_H)
            PP.Point(styleBtn, "LEFT", rowFrame, "CENTER", GAP / 2, 0)
            styleBtn:SetFrameLevel(rowFrame:GetFrameLevel() + 1)
            local _, _, styleLbl = EllesmereUI.MakeStyledButton(styleBtn,
                isBlizz and "EUI Style Action Bars" or "Blizzard Style Action Bars", 14,
                EllesmereUI.WB_COLOURS, function()
                    local old = EAB.db.profile.useBlizzardStyle or false
                    local new = not old
                    EllesmereUI:ShowConfirmPopup({
                        title       = "Reload Required",
                        message     = "Changing icon style requires a UI reload to apply.",
                        confirmText = "Reload Now",
                        cancelText  = "Cancel",
                        onConfirm   = function()
                            EAB.db.profile.useBlizzardStyle = new
                            ReloadUI()
                        end,
                    })
                end)

            y = y - ROW_H
        end

        -------------------------------------------------------------------
        --  Build shared settings (single mode)
        -------------------------------------------------------------------
        y = BuildSharedBarSettings(parent, y)

        return math.abs(y)
    end


    local SECTION_BAR_INTERACTIONS = "BAR INTERACTIONS"
    local SECTION_PROC_GLOW     = "CUSTOM PROC GLOW"

    local interactionTypeValues = { [1] = "Light", [2] = "Medium", [3] = "Strong", [4] = "Solid Color", [5] = "Border", [6] = "None" }
    local interactionTypeOrder  = { 1, 2, 3, 4, 5, 6 }
    local pushedTypeValues, pushedTypeOrder = interactionTypeValues, interactionTypeOrder
    local highlightTypeValues, highlightTypeOrder = interactionTypeValues, interactionTypeOrder
    local procGlowValues = { [0] = "None" }
    local procGlowOrder = { 0 }
    do
        for i, entry in ipairs(ns.LOOP_GLOW_TYPES) do
            if not entry.shapeGlow then          -- Shape Glow is internal-only
                procGlowValues[i] = entry.name
                procGlowOrder[#procGlowOrder + 1] = i
            end
        end
    end

    -----------------------------------------------------------------------
    --  Preview icon helper for animation dropdown rows
    --  Creates a small square icon with a 1px border, parented to a
    --  DualRow's left region and centered vertically between the label
    --  and the dropdown.
    -----------------------------------------------------------------------
    local PREVIEW_ICON_SIZE = 30

    local function CreatePreviewIcon(parentRegion)
        local f = CreateFrame("Frame", nil, parentRegion)
        f:EnableMouse(false)
        PP.Size(f, PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
        -- Center vertically, positioned roughly between label and dropdown
        PP.Point(f, "RIGHT", parentRegion, "RIGHT", -200, 0)

        -- Icon texture (dark placeholder)
        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetColorTexture(0.15, 0.15, 0.15, 1)
        f._icon = icon

        -- 1px black border via unified PP system
        PP.CreateBorder(f, 0, 0, 0, 1, 1, "OVERLAY", 7)

        return f
    end

    -- Unified interaction preview (pushed / highlight)
    local INTERACTION_DEFAULTS = {
        pushed    = { typeDefault = 3, texFallback = 2, solidColor = { r = 1, g = 0.792, b = 0.427, a = 1 } },
        highlight = { typeDefault = 2, texFallback = 1, solidColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 } },
    }
    local function UpdateInteractionPreview(f, prefix)
        if not f then return end
        local p = EAB.db.profile
        local defs = INTERACTION_DEFAULTS[prefix]
        local iType = p[prefix .. "TextureType"] or defs.typeDefault
        if not f._overlay then
            local ov = f:CreateTexture(nil, "OVERLAY", nil, 1)
            ov:SetAllPoints()
            f._overlay = ov
        end
        if not f._borderOv then
            f._borderOv = {}
            for i = 1, 4 do
                local t = f:CreateTexture(nil, "OVERLAY", nil, 2)
                t:SetColorTexture(1, 1, 1, 1)
                f._borderOv[i] = t
            end
        end
        local ov = f._overlay
        local bo = f._borderOv
        if iType == 6 then
            ov:Hide()
            for i = 1, 4 do bo[i]:Hide() end
        elseif iType == 4 then
            ov:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            ov:SetTexCoord(0, 1, 0, 1)
            ov:SetDesaturated(false)
            local cr, cg, cb, ca
            if p[prefix .. "UseClassColor"] then
                local _, class = UnitClass("player")
                local cc = RAID_CLASS_COLORS[class]
                cr, cg, cb = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
                ca = 1
            else
                local c = p[prefix .. "CustomColor"] or defs.solidColor
                cr, cg, cb, ca = c.r, c.g, c.b, c.a
            end
            ov:SetVertexColor(cr, cg, cb, 0.3)
            ov:Show()
            for i = 1, 4 do bo[i]:Hide() end
        elseif iType == 5 then
            ov:Hide()
            local bsz = p[prefix .. "BorderSize"] or 4
            local cr, cg, cb, ca
            if p[prefix .. "UseClassColor"] then
                local _, class = UnitClass("player")
                local cc = RAID_CLASS_COLORS[class]
                cr, cg, cb = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
                ca = 1
            else
                local c = p[prefix .. "CustomColor"] or { r = 1, g = 0.792, b = 0.427, a = 1 }
                cr, cg, cb, ca = c.r, c.g, c.b, c.a
            end
            for i = 1, 4 do bo[i]:SetVertexColor(cr, cg, cb, ca) end
            bo[1]:ClearAllPoints(); bo[1]:SetPoint("TOPLEFT", f); bo[1]:SetPoint("TOPRIGHT", f); PP.Height(bo[1], bsz); bo[1]:Show()
            bo[2]:ClearAllPoints(); bo[2]:SetPoint("BOTTOMLEFT", f); bo[2]:SetPoint("BOTTOMRIGHT", f); PP.Height(bo[2], bsz); bo[2]:Show()
            bo[3]:ClearAllPoints(); bo[3]:SetPoint("TOPLEFT", bo[1], "BOTTOMLEFT"); bo[3]:SetPoint("BOTTOMLEFT", bo[2], "TOPLEFT"); PP.Width(bo[3], bsz); bo[3]:Show()
            bo[4]:ClearAllPoints(); bo[4]:SetPoint("TOPRIGHT", bo[1], "BOTTOMRIGHT"); bo[4]:SetPoint("BOTTOMRIGHT", bo[2], "TOPRIGHT"); PP.Width(bo[4], bsz); bo[4]:Show()
        else
            local texIdx = iType
            if texIdx < 1 or texIdx > 3 then texIdx = defs.texFallback end
            ov:SetTexture(ns.HIGHLIGHT_TEXTURES[texIdx])
            ov:SetTexCoord(0, 1, 0, 1)
            if p[prefix .. "UseClassColor"] then
                local _, class = UnitClass("player")
                local cc = RAID_CLASS_COLORS[class]
                ov:SetDesaturated(true)
                ov:SetVertexColor(cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1, 1)
            else
                local c = p[prefix .. "CustomColor"] or { r = 1, g = 0.792, b = 0.427, a = 1 }
                ov:SetDesaturated(true)
                ov:SetVertexColor(c.r, c.g, c.b, c.a)
            end
            ov:Show()
            for i = 1, 4 do bo[i]:Hide() end
        end
    end
    local function UpdatePushedPreview(f)    UpdateInteractionPreview(f, "pushed")    end
    local function UpdateHighlightPreview(f) UpdateInteractionPreview(f, "highlight") end

    -- Proc glow preview: supports FlipBook + procedural glow engines
    local function GetNthActionButtonIcon(n)
        -- Find the Nth action button with an assigned spell across bars 1-8
        n = n or 1
        local BAR_CONFIG = {
            { prefix = "ActionButton", count = 12 },
            { prefix = "MultiBarBottomLeftButton", count = 12 },
            { prefix = "MultiBarBottomRightButton", count = 12 },
            { prefix = "MultiBarRightButton", count = 12 },
            { prefix = "MultiBarLeftButton", count = 12 },
            { prefix = "MultiBar5Button", count = 12 },
            { prefix = "MultiBar6Button", count = 12 },
            { prefix = "MultiBar7Button", count = 12 },
        }
        local found = 0
        for _, bar in ipairs(BAR_CONFIG) do
            for i = 1, bar.count do
                local btn = _G[bar.prefix .. i]
                if btn and btn.icon then
                    local tex = btn.icon:GetTexture()
                    if tex and tex ~= 0 and tex ~= "" and tex ~= 136235 then
                        found = found + 1
                        if found >= n then return tex end
                    end
                end
            end
        end
        return 136197  -- fallback: generic spell icon
    end

    local function UpdateProcGlowPreview(f)
        if not f then return end
        local p = EAB.db.profile

        -- Create or reuse FlipBook overlay for loop glow
        if not f._loopTex then
            local loopTex = f:CreateTexture(nil, "OVERLAY", nil, 7)
            loopTex:SetPoint("CENTER")
            local loopGroup = loopTex:CreateAnimationGroup()
            loopGroup:SetLooping("REPEAT")
            local loopAnim = loopGroup:CreateAnimation("FlipBook")
            f._loopTex = loopTex
            f._loopGroup = loopGroup
            f._loopAnim = loopAnim
        end

        -- Stop all current animations
        f._loopGroup:Stop()
        f._loopTex:Hide()
        ns.Glows.StopProceduralAnts(f)
        ns.Glows.StopButtonGlow(f)
        ns.Glows.StopAutoCastShine(f)
        ns.Glows.StopShapeGlow(f)

        -- If disabled (None selected), keep the icon visible but grayed out
        if p.procGlowEnabled == false or (p.procGlowType == 0) then
            f:Show()
            f:SetAlpha(0.15)
            return
        end
        f:Show()
        f:SetAlpha(1)

        -- Loop glow
        local loopIdx = p.procGlowType or 1
        local LOOP = ns.LOOP_GLOW_TYPES
        if loopIdx < 1 or loopIdx > #LOOP then loopIdx = 1 end
        local loopEntry = LOOP[loopIdx]

        local iconSize = PREVIEW_ICON_SIZE
        local cr, cg, cb
        if p.procGlowUseClassColor then
            local _, class = UnitClass("player")
            local cc = RAID_CLASS_COLORS[class]
            if cc then
                cr, cg, cb = cc.r, cc.g, cc.b
            else
                cr, cg, cb = 1, 1, 1
            end
        else
            local c = p.procGlowColor or { r = 1, g = 0.776, b = 0.376 }
            cr, cg, cb = c.r, c.g, c.b
        end

        if loopEntry.procedural then
            -- Pixel Glow preview
            local N = 8
            local th = 2
            local period = 4
            local lineLen = math.floor((iconSize + iconSize) * (2 / N - 0.1))
            lineLen = math.min(lineLen, iconSize)
            if lineLen < 1 then lineLen = 1 end
            ns.Glows.StartProceduralAnts(f, N, th, period, lineLen, cr, cg, cb)
        elseif loopEntry.buttonGlow then
            ns.Glows.StartButtonGlow(f, iconSize, cr, cg, cb)
        elseif loopEntry.autocast then
            ns.Glows.StartAutoCastShine(f, iconSize, cr, cg, cb, 1.0)
        elseif loopEntry.shapeGlow then
            -- Shape Glow preview -- use first bar's shape mask
            local maskPath
            for k, bs in pairs(EAB.db.profile.bars) do
                if bs then
                    local shape = bs.buttonShape or "none"
                    if ns.SHAPE_MASKS[shape] then maskPath = ns.SHAPE_MASKS[shape]; break end
                end
            end
            ns.Glows.StartShapeGlow(f, iconSize, cr, cg, cb, 1.20, { maskPath = maskPath })
        else
            -- FlipBook preview
            local previewSz = iconSize * (loopEntry.texPadding or 1)
            f._loopTex:SetSize(previewSz, previewSz)
            if loopEntry.atlas then
                f._loopTex:SetAtlas(loopEntry.atlas)
            elseif loopEntry.texture then
                f._loopTex:SetTexture(loopEntry.texture)
            end
            f._loopAnim:SetFlipBookRows(loopEntry.rows or 6)
            f._loopAnim:SetFlipBookColumns(loopEntry.columns or 5)
            f._loopAnim:SetFlipBookFrames(loopEntry.frames or 30)
            f._loopAnim:SetDuration(loopEntry.duration or 1.0)
            f._loopAnim:SetFlipBookFrameWidth(loopEntry.frameW or 0.0)
            f._loopAnim:SetFlipBookFrameHeight(loopEntry.frameH or 0.0)

            -- Only desaturate+tint for custom texture styles (Classic WoW Glow).
            -- Atlas-based styles keep their original white highlights.
            f._loopTex:SetDesaturated(true)
            f._loopTex:SetVertexColor(cr, cg, cb)

            f._loopTex:Show()
            f._loopGroup:Play()
        end
    end

    -- Persistent preview icon frames (survive page cache restores)
    local _pushedPreview, _highlightPreview, _procGlowPreview

    local function BuildAnimationsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h, row
        local p = EAB.db.profile

        -- No content header for animations page (global settings, no bar selector)
        EllesmereUI:ClearContentHeader()

        -- Enable per-row center divider for the dual-column layout
        parent._showRowDivider = true

        -------------------------------------------------------------------
        --  BAR INTERACTIONS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_BAR_INTERACTIONS, y);  y = y - h

        local INTERACTIONS_TIP = "Bar Interactions are the light effects that happen when you hover/press a spell, your cooldown swipe line, aura active border glow, etc"

        -- Helper: apply unified color to ALL interaction systems
        local function ApplyAllInteractionColors()
            EAB:ApplyPushedTextures()
            EAB:ApplyHighlightTextures()
            EAB:ApplyCooldownEdge()
            EAB:ApplyMiscTextures()
            EAB:RefreshProcGlows()
            UpdatePushedPreview(_pushedPreview)
            UpdateHighlightPreview(_highlightPreview)
            UpdateProcGlowPreview(_procGlowPreview)
        end

        -- Helper: set unified color across all DB keys
        local function SetUnifiedColor(r, g, b, a)
            p.pushedCustomColor = { r = r, g = g, b = b, a = a }
            p.highlightCustomColor = { r = r, g = g, b = b, a = a }
            p.cooldownEdgeColor = { r = r, g = g, b = b, a = a }
            p.procGlowColor = { r = r, g = g, b = b }
            ApplyAllInteractionColors()
        end

        -- Helper: set unified class color across all DB keys
        local function SetUnifiedClassColor(v)
            p.pushedUseClassColor = v
            p.highlightUseClassColor = v
            p.cooldownEdgeUseClassColor = v
            p.procGlowUseClassColor = v
            ApplyAllInteractionColors()
            EllesmereUI:RefreshPage()
        end

        -- Row 1: Unified Color | Class Colored
        _, h = W:DualRow(parent, y,
            { type="colorpicker", text="Bar Interactions Color",
              tooltip=INTERACTIONS_TIP,
              disabled=function() return EAB.db.profile.useBlizzardStyle or p.pushedUseClassColor end,
              disabledTooltip=function()
                  if EAB.db.profile.useBlizzardStyle then return "This option requires Blizzard Style Action Bars to be disabled" end
                  return "This option requires Class Colors to be disabled"
              end,
              rawTooltip=true,
              getValue=function()
                  local c = p.pushedCustomColor
                  if not c then return 0.973, 0.839, 0.604, 1 end
                  return c.r, c.g, c.b, c.a
              end,
              setValue=function(r, g, b, a)
                  SetUnifiedColor(r, g, b, a)
              end,
              hasAlpha=true },
            { type="toggle", text="Class Colored Bar Interactions",
              tooltip=INTERACTIONS_TIP,
              disabled=function() return EAB.db.profile.useBlizzardStyle end,
              disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
              getValue=function() return p.pushedUseClassColor end,
              setValue=function(v)
                  SetUnifiedClassColor(v)
              end });  y = y - h

        -- Row 2: Pushed Type (left, cog + preview) | Highlight Type (right, cog + preview)
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Pushed Type",
              tooltip="The overlay that appears on the icon when you press and hold a spell button",
              disabled=function() return EAB.db.profile.useBlizzardStyle end,
              disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
              values=pushedTypeValues, order=pushedTypeOrder,
              getValue=function() return p.pushedTextureType or 2 end,
              setValue=function(v)
                  p.pushedTextureType = v
                  EAB:ApplyPushedTextures()
                  UpdatePushedPreview(_pushedPreview)
                  EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Highlight Type",
              tooltip="The overlay that appears on the icon when you hover your mouse over a spell button",
              disabled=function() return EAB.db.profile.useBlizzardStyle end,
              disabledTooltip="Blizzard Style Action Bars", requireState="disabled",
              values=highlightTypeValues, order=highlightTypeOrder,
              getValue=function() return p.highlightTextureType or 2 end,
              setValue=function(v)
                  p.highlightTextureType = v
                  EAB:ApplyHighlightTextures()
                  UpdateHighlightPreview(_highlightPreview)
                  EllesmereUI:RefreshPage()
              end })
        do
            -- Pushed Type inline elements (left)
            local leftRgn = row._leftRegion
            _pushedPreview = CreatePreviewIcon(leftRgn)
            if _pushedPreview._icon then
                _pushedPreview._icon:SetTexture(GetNthActionButtonIcon(1))
                _pushedPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            UpdatePushedPreview(_pushedPreview)
            EllesmereUI.RegisterWidgetRefresh(function() UpdatePushedPreview(_pushedPreview) end)

            local _, pushedCogShow = EllesmereUI.BuildCogPopup({
                title = "Pushed Border Settings",
                rows = {
                    { type="slider", label="Border Size", min=1, max=10, step=1,
                      get=function() return p.pushedBorderSize or 4 end,
                      set=function(v)
                          p.pushedBorderSize = v
                          EAB:ApplyPushedTextures()
                          UpdatePushedPreview(_pushedPreview)
                      end },
                },
            })
            local pushedCogBtn = CreateFrame("Button", nil, leftRgn)
            pushedCogBtn:SetSize(26, 26)
            pushedCogBtn:SetPoint("RIGHT", _pushedPreview, "LEFT", -8, 0)
            pushedCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            local pushedCogOff = function() return (p.pushedTextureType or 2) ~= 5 end
            pushedCogBtn:SetAlpha(pushedCogOff() and 0.15 or 0.4)
            local pushedCogTex = pushedCogBtn:CreateTexture(nil, "OVERLAY")
            pushedCogTex:SetAllPoints()
            pushedCogTex:SetTexture(EllesmereUI.COGS_ICON)
            pushedCogBtn:SetScript("OnEnter", function(self)
                if pushedCogOff() then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Border Pushed Type"))
                else
                    self:SetAlpha(0.7)
                end
            end)
            pushedCogBtn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                self:SetAlpha(pushedCogOff() and 0.15 or 0.4)
            end)
            pushedCogBtn:SetScript("OnClick", function(self)
                if pushedCogOff() then return end
                pushedCogShow(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                pushedCogBtn:SetAlpha(pushedCogOff() and 0.15 or 0.4)
            end)

            -- Highlight Type inline elements (right)
            local rightRgn = row._rightRegion
            _highlightPreview = CreatePreviewIcon(rightRgn)
            if _highlightPreview._icon then
                _highlightPreview._icon:SetTexture(GetNthActionButtonIcon(2))
                _highlightPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            UpdateHighlightPreview(_highlightPreview)
            EllesmereUI.RegisterWidgetRefresh(function() UpdateHighlightPreview(_highlightPreview) end)

            local _, highlightCogShow = EllesmereUI.BuildCogPopup({
                title = "Highlight Border Settings",
                rows = {
                    { type="slider", label="Border Size", min=1, max=10, step=1,
                      get=function() return p.highlightBorderSize or 4 end,
                      set=function(v)
                          p.highlightBorderSize = v
                          EAB:ApplyHighlightTextures()
                          UpdateHighlightPreview(_highlightPreview)
                      end },
                },
            })
            local highlightCogBtn = CreateFrame("Button", nil, rightRgn)
            highlightCogBtn:SetSize(26, 26)
            highlightCogBtn:SetPoint("RIGHT", _highlightPreview, "LEFT", -8, 0)
            highlightCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            local highlightCogOff = function() return (p.highlightTextureType or 2) ~= 5 end
            highlightCogBtn:SetAlpha(highlightCogOff() and 0.15 or 0.4)
            local highlightCogTex = highlightCogBtn:CreateTexture(nil, "OVERLAY")
            highlightCogTex:SetAllPoints()
            highlightCogTex:SetTexture(EllesmereUI.COGS_ICON)
            highlightCogBtn:SetScript("OnEnter", function(self)
                if highlightCogOff() then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Border Highlight Type"))
                else
                    self:SetAlpha(0.7)
                end
            end)
            highlightCogBtn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                self:SetAlpha(highlightCogOff() and 0.15 or 0.4)
            end)
            highlightCogBtn:SetScript("OnClick", function(self)
                if highlightCogOff() then return end
                highlightCogShow(self)
            end)
            EllesmereUI.RegisterWidgetRefresh(function()
                highlightCogBtn:SetAlpha(highlightCogOff() and 0.15 or 0.4)
            end)
        end
        y = y - h

        -- Row 3: Hide Casting Animations
        local function castAnimForced()
            local bars = EAB.db.profile.bars
            if not bars then return false end
            for _, s in pairs(bars) do
                if s.buttonShape and s.buttonShape ~= "none" then return true end
            end
            return false
        end
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Casting Animations",
              tooltip="This is the full overlay that swipes from right to left on the icon during its cast duration",
              disabled=castAnimForced,
              disabledTooltip="This option requires a non-custom shaped action bar",
              rawTooltip=true,
              getValue=function() return p.hideCastingAnimations or castAnimForced() end,
              setValue=function(v)
                  p.hideCastingAnimations = v
                  -- ActionBarActionEventsFrame is killed at file-load time.
                  -- Casting animation visibility is handled by ApplySettings.
              end },
            { type="toggle", text="Show Highlight on Spell Cast",
              tooltip="The highlight overlay that appears on a spell button while it is the active/current action. Disable to hide it.",
              rawTooltip=true,
              getValue=function() return p.showCastHighlight ~= false end,
              setValue=function(v)
                  p.showCastHighlight = v
                  EAB:ApplyCheckedTextures()
              end });  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  PROC GLOW EFFECT
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_PROC_GLOW, y);  y = y - h

        local function procGlowOff() return (p.procGlowType == 0) or (p.procGlowEnabled == false) end

        -- Check if any bar uses a custom shape (not "none")
        local function AnyBarHasCustomShape()
            local bars = EAB.db.profile.bars
            if not bars then return false end
            for _, s in pairs(bars) do
                if s.buttonShape and s.buttonShape ~= "none" and s.buttonShape ~= "cropped" then return true end
            end
            return false
        end

        local hasCustomShape = AnyBarHasCustomShape()

        -- Row 1: Custom Proc Glow (dropdown with "None" option) | Use Class Color
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Custom Proc Glow",
              values=procGlowValues, order=procGlowOrder,
              disabled=function() return EAB.db.profile.useBlizzardStyle or hasCustomShape end,
              disabledTooltip=function()
                  if EAB.db.profile.useBlizzardStyle then return "This option requires Blizzard Style Action Bars to be disabled" end
                  return "Custom shapes always use Shape Glow -- change your bar shape to None or Cropped to pick a different glow"
              end,
              rawTooltip=true,
              getValue=function() if p.procGlowEnabled == false then return 0 end; return p.procGlowType or 1 end,
              setValue=function(v)
                  local wasOff = (p.procGlowType == 0) or (p.procGlowEnabled == false)
                  local turningOn = wasOff and v ~= 0
                  if turningOn then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Custom Proc Glow Settings",
                          message     = "Custom proc glow may cause a slight loss in performance efficiency. Do you want to enable it?",
                          confirmText = "Enable",
                          cancelText  = "Cancel",
                          onConfirm   = function()
                              p.procGlowType = v
                              p.procGlowEnabled = true
                              EAB:RefreshProcGlows()
                              UpdateProcGlowPreview(_procGlowPreview)
                              EllesmereUI:RefreshPage()
                          end,
                          onCancel    = function()
                              if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
                          end,
                      })
                      return
                  end
                  p.procGlowType = v
                  p.procGlowEnabled = (v ~= 0)
                  EAB:RefreshProcGlows()
                  UpdateProcGlowPreview(_procGlowPreview)
                  C_Timer.After(0, function() EllesmereUI:RefreshPage() end)
              end },
            { type="toggle", text="Use Class Color",
              disabled=procGlowOff, disabledTooltip="This option requires a custom glow to be selected", rawTooltip=true,
              getValue=function() return p.procGlowUseClassColor end,
              setValue=function(v)
                  p.procGlowUseClassColor = v
                  EAB:RefreshProcGlows()
                  UpdateProcGlowPreview(_procGlowPreview)
                  EllesmereUI:RefreshPage()
              end })
        do
            local leftRgn = row._leftRegion
            _procGlowPreview = CreatePreviewIcon(leftRgn)
            if _procGlowPreview._icon then
                local iconTex = GetNthActionButtonIcon(3)
                _procGlowPreview._icon:SetTexture(iconTex)
                _procGlowPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            UpdateProcGlowPreview(_procGlowPreview)
            EllesmereUI.RegisterWidgetRefresh(function() UpdateProcGlowPreview(_procGlowPreview) end)

            -- Inline color swatch for Glow Color, anchored to the LEFT of the preview icon
            local glowSwatchGet = function()
                local c = p.procGlowColor or { r = 1, g = 0.776, b = 0.376 }
                return c.r, c.g, c.b
            end
            local glowSwatchSet = function(r, g, b)
                p.procGlowColor = { r = r, g = g, b = b }
                EAB:RefreshProcGlows()
                UpdateProcGlowPreview(_procGlowPreview)
            end
            local glowSwatch, glowUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, glowSwatchGet, glowSwatchSet, nil, 20)
            PP.Point(glowSwatch, "RIGHT", _procGlowPreview, "LEFT", -12, 0)

            local GLOW_DISABLED_TIP = "This option requires a custom glow to be selected"

            -- Add disabled tooltip to swatch
            glowSwatch:HookScript("OnEnter", function(self)
                if procGlowOff() then
                    EllesmereUI.ShowWidgetTooltip(self, GLOW_DISABLED_TIP)
                elseif p.procGlowUseClassColor then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Class Colors", "disabled"))
                end
            end)
            glowSwatch:HookScript("OnLeave", function()
                EllesmereUI.HideWidgetTooltip()
            end)

            -- Gray out swatch when proc glow is off or class color is on
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = procGlowOff() or p.procGlowUseClassColor
                glowSwatch:SetAlpha(off and 0.15 or 1)
                glowSwatch:SetMouseClickEnabled(not off)
                glowUpdateSwatch()
            end)
            local initOff = procGlowOff() or p.procGlowUseClassColor
            glowSwatch:SetAlpha(initOff and 0.15 or 1)
            glowSwatch:SetMouseClickEnabled(not initOff)
        end
        y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Unlock Mode page  (opens EllesmereUI Unlock Mode overlay)
    ---------------------------------------------------------------------------
    local function BuildUnlockPage(pageName, parent, yOffset)
        -- Defer to next frame so the page switch completes first
        C_Timer.After(0, function()
            if ns.OpenUnlockMode then
                ns.OpenUnlockMode()
            end
        end)
        return 0
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIActionBars", {
        title       = "Action Bars",
        description = "Configure visuals and behavior for your action bars.",
        pages       = { PAGE_DISPLAY, PAGE_MENUBAGSXP, PAGE_ANIMATIONS },
        buildPage   = function(pageName, parent, yOffset)
            -- BuildBarDisplayPage calls ShowEditOverlay() unconditionally at
            -- build time, which creates/shows a real overlay frame
            -- (EllesmereEAB_EditOverlay, parented to UIParent) over the
            -- player's live action bars -- not just on user interaction.
            -- Building this page during a hidden search pre-build would flash
            -- that overlay onto the live screen, so skip PAGE_DISPLAY here;
            -- it's indexed normally the first time the player visits it.
            if EllesmereUI._prebuilding then
                if pageName == PAGE_MENUBAGSXP then
                    return BuildMenuBagsXPPage(pageName, parent, yOffset)
                elseif pageName == PAGE_ANIMATIONS then
                    return BuildAnimationsPage(pageName, parent, yOffset)
                end
                return
            end
            if pageName ~= PAGE_DISPLAY then
                HideEditOverlay()
            end
            if pageName == PAGE_DISPLAY then
                return BuildBarDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_MENUBAGSXP then
                return BuildMenuBagsXPPage(pageName, parent, yOffset)
            elseif pageName == PAGE_ANIMATIONS then
                return BuildAnimationsPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _barsHeaderBuilder
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_DISPLAY then
                UpdatePreview()
                ShowEditOverlay(SelectedKey())
                local dismissed = IsPreviewHintDismissed()
                if _abPreviewHintFS then
                    if dismissed then
                        _abPreviewHintFS:Hide()
                    else
                        _abPreviewHintFS:SetAlpha(0.45)
                        _abPreviewHintFS:Show()
                        if _abPreviewHintFS:GetParent() then _abPreviewHintFS:GetParent():Show() end
                    end
                end
                if barsHeaderBaseH > 0 then
                    EllesmereUI:SetContentHeaderHeightSilent(barsHeaderBaseH + (dismissed and 0 or 29))
                end
            else
                HideEditOverlay()
            end
        end,
        onReset     = function()
            EAB.db:ResetProfile()
            -- Clear the per-install capture flag so the snapshot re-runs
            -- after reload and picks up Blizzard's current bar layout.
            if EAB.db and EAB.db.sv then
                EAB.db.sv._capturedOnce_EAB = nil
            end
            ReloadUI()
        end,
    })
end)
