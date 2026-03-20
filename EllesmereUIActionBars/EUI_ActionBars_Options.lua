-------------------------------------------------------------------------------
--  EUI_ActionBar_Options.lua
--  Registers the real Action Bars module with EllesmereUI
--  Pure UI makeover all get/set calls go to EAB.db.profile, same as before
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EAB = ns.EAB

local function GetEABOptOutline() return EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or "" end
local function GetEABOptUseShadow() return EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow() or true end

-------------------------------------------------------------------------------
--  Section / page names  (edit here to rename everywhere)
-------------------------------------------------------------------------------
local PAGE_DISPLAY        = "Bar Display"
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
    local function SelectedKey()
        return EAB.db.profile.selectedBar or "MainBar"
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

    ---------------------------------------------------------------------------
    --  Ordered dropdown values for the bar selector
    ---------------------------------------------------------------------------
    local barLabels = {}
    local barOrder  = {}
    for _, key in ipairs(BAR_DROPDOWN_ORDER) do
        -- Skip individual MicroBar/BagBar and XPBar/RepBar — replaced by combined entries
        if key ~= "MicroBar" and key ~= "BagBar" and key ~= "XPBar" and key ~= "RepBar" then
            barLabels[key] = BAR_DROPDOWN_VALUES[key]
            barOrder[#barOrder + 1] = key
        end
        -- Insert combined entries after PetBar (last real bar before extras)
        if key == "PetBar" then
            barLabels["MicroBagBars"] = "Micro Menu / Bag Bars"
            barOrder[#barOrder + 1] = "MicroBagBars"
            barLabels["XPRepBars"] = "XP / Rep Bars"
            barOrder[#barOrder + 1] = "XPRepBars"
        end
    end

    -- Register combined keys as visibility-only so normal LAYOUT/ICON sections are suppressed
    ns.VISIBILITY_ONLY["MicroBagBars"] = true
    ns.VISIBILITY_ONLY["XPRepBars"]    = true

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
                -- Force a full rebuild of the preview and header on spec change
                activePreview = nil
                EllesmereUI:SetContentHeader(_barsHeaderBuilder)
                UpdatePreviewAndResize()
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
        if not barInfo or not barInfo.buttonPrefix or not barInfo.count then
            activePreview = nil
            return 0
        end

        local PAD      = EllesmereUI.CONTENT_PAD
        local maxBtns  = barInfo.count   -- always 12, used for pre-allocation

        -- Our custom bar frame (may be nil during first build before bars are created)
        local barFrame = _G["EABBar_" .. barKey]

        -- Read the real button size from the first actual button.
        -- Round to nearest integer to eliminate floating-point noise.
        local btn1 = _G[barInfo.buttonPrefix .. "1"]
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
            keybindFS:SetFont(DEFAULT_FONT, 12, "OUTLINE")
            keybindFS:SetShadowOffset(0, 0)
            keybindFS:SetTextColor(1, 1, 1)
            keybindFS:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -1, -3)
            keybindFS:SetPoint("TOPLEFT", bf, "TOPLEFT", 4, -3)
            keybindFS:SetJustifyH("RIGHT")
            keybindFS:SetWordWrap(false)
            keybindFS:SetText("")

            -- Count / charges text (bottom-right, mirrors real button Count position)
            local countFS = bf:CreateFontString(nil, "OVERLAY")
            countFS:SetFont(DEFAULT_FONT, 12, "OUTLINE")
            countFS:SetShadowOffset(0, 0)
            countFS:SetTextColor(1, 1, 1)
            countFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 4)
            countFS:SetText("")

            buttons[i] = {
                frame   = bf,
                icon    = icon,
                borders = { bT, bB, bL, bR },
                keybind = keybindFS,
                count   = countFS,
            }
        end

        -- Preview background texture (behind all buttons)
        local previewBG = pf:CreateTexture(nil, "BACKGROUND", nil, -1)
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

            -- Resize preview frame to fit all rows
            local frameH = Snap(gridH + 20)  -- 10px padding top + bottom
            self:SetHeight(frameH)

            -- Resize wrapper to min(content, max) and toggle scrollbar
            local parentH = frameH * self._previewScale
            local maxH = self._PREVIEW_MAX_H
            if parentH > maxH then
                -- Add bottom padding so the last icon row is fully visible
                -- when scrolled to the bottom
                local paddedH = Snap(gridH + 20 + scaledBtnH)
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
            self._gridW      = gridW
            self._gridH      = gridH

            local startY = -Snap(10)  -- top padding
            local growUp = (settings.growDirection or "up") == "up"
            for i = 1, maxBtns do
                local entry = buttons[i]
                local bf    = entry.frame
                local icon  = entry.icon

                if i >= leftmost and i <= previewCount then
                    -- Multi-row: compute row and column for this button
                    local idx = i - leftmost  -- 0-based index
                    local col, row
                    if isVertical then
                        col = math.floor(idx / stride)
                        row = idx % stride
                    else
                        col = idx % stride
                        row = math.floor(idx / stride)
                    end

                    local xOff, yOff
                    if isVertical then
                        -- Vertical: center each column vertically when last column is shorter
                        local colStart = col * stride + 1
                        local colEnd = math.min(colStart + stride - 1, previewCount)
                        local countInCol = colEnd - colStart + 1
                        local colH = countInCol * scaledBtnH + (countInCol - 1) * scaledPad
                        local colOffY = Snap((gridH - colH) / 2)
                        xOff = Snap(gridStartX + col * (scaledBtnW + scaledPad))
                        yOff = startY - colOffY - Snap(row * (scaledBtnH + scaledPad))
                    else
                        -- Horizontal: center each row horizontally when last row is shorter
                        local rowStart = row * stride + 1
                        local rowEnd = math.min(rowStart + stride - 1, previewCount)
                        local countInRow = rowEnd - rowStart + 1
                        local rowW = countInRow * scaledBtnW + (countInRow - 1) * scaledPad
                        local startX = Snap(gridStartX + (gridW - rowW) / 2)
                        xOff = Snap(startX + col * (scaledBtnW + scaledPad))
                        local displayRow = growUp and ((numRows - 1) - row) or row
                        yOff = startY - Snap(displayRow * (scaledBtnH + scaledPad))
                    end
                    bf:SetSize(scaledBtnW, scaledBtnH)
                    bf:ClearAllPoints()
                    bf:SetPoint("TOPLEFT", self, "TOPLEFT", xOff, yOff)
                    bf:Show()

                    -- Icon texture from real button
                    local realBtn = _G[info.buttonPrefix .. i]
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
                    if brdOn then
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
                    else
                        bT:Hide(); bB:Hide(); bL:Hide(); bR:Hide()
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
                    keybindFS:SetFont(fontPath, scaledKBSize, "OUTLINE")
                    keybindFS:SetShadowOffset(0, 0)
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
                    countFS:SetFont(fontPath, scaledCTSize, "OUTLINE")
                    countFS:SetShadowOffset(0, 0)
                    countFS:SetTextColor(ctColor.r, ctColor.g, ctColor.b)
                    -- Apply charges X/Y offsets
                    local ctOX = (settings.countOffsetX or 0) * totalScale
                    local ctOY = (settings.countOffsetY or 0) * totalScale
                    countFS:ClearAllPoints()
                    countFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1 + ctOX, 4 + ctOY)
                    end -- close alwaysShowButtons else
                else
                    -- Button beyond numButtonsShowable hide it
                    bf:Hide()
                end
            end

            -- Preview background
            if settings.bgEnabled then
                local bgC = settings.bgColor or { r = 0, g = 0, b = 0, a = 0.5 }
                previewBG:SetColorTexture(bgC.r, bgC.g, bgC.b, bgC.a)
                local extraX = Snap((settings.bgPadX or 0) * totalScale)
                local extraY = Snap((settings.bgPadY or 0) * totalScale)
                -- Anchor to the full grid bounds (not individual buttons) so multi-row
                -- backgrounds cover the entire grid even when the last row is shorter.
                local gx = self._gridStartX or 0
                local gw = self._gridW or 0
                local gh = self._gridH or 0
                local gy = -Snap(10)  -- top padding (matches startY)
                previewBG:ClearAllPoints()
                previewBG:SetPoint("TOPLEFT",     self, "TOPLEFT", gx - extraX,       gy + extraY)
                previewBG:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", gx + gw + extraX,  gy - gh - extraY)
                previewBG:Show()
            else
                previewBG:Hide()
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
    }




    ---------------------------------------------------------------------------
    --  Unified bar settings builder
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    --  Micro Menu / Bag Bars combined page
    ---------------------------------------------------------------------------
    local function BuildMicroBagPage(parent, y)
        local W = EllesmereUI.Widgets
        local _, h

        local function GetVisKey(s)
            return s.barVisibility or "always"
        end
        local function ApplyVisKey(s, v)
            s.barVisibility = v
            s.alwaysHidden      = (v == "never")
            local wasMO = s.mouseoverEnabled
            s.mouseoverEnabled  = (v == "mouseover")
            if v == "mouseover" then
                s._savedBarAlpha = s.mouseoverAlpha or 1
                s.mouseoverAlpha = 0
            elseif wasMO and s._savedBarAlpha then
                s.mouseoverAlpha = s._savedBarAlpha
                s._savedBarAlpha = nil
            end
            s.combatHideEnabled = false
            s.combatShowEnabled = (v == "in_combat")
        end

        local function MakeCogBtn(rgn, showFn, anchorTo)
            local anchor = anchorTo or (rgn and (rgn._lastInline or rgn._control)) or rgn
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) showFn(self) end)
            if rgn then rgn._lastInline = cogBtn end
            return cogBtn
        end

        local function BuildVisRow(barKey, sectionTitle)
            _, h = W:SectionHeader(parent, sectionTitle, y);  y = y - h
            local s = EAB.db.profile.bars[barKey]
            local visRow, visH = W:DualRow(parent, y,
                { type="dropdown", text="Visibility",
                  values=EllesmereUI.VIS_VALUES, order=EllesmereUI.VIS_ORDER,
                  getValue=function() return GetVisKey(EAB.db.profile.bars[barKey]) end,
                  setValue=function(v)
                      ApplyVisKey(EAB.db.profile.bars[barKey], v)
                      EAB:ApplyAlwaysHidden()
                      EAB:RefreshMouseover()
                      EAB:ApplyCombatVisibility()
                      EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Visibility Options",
                  values={ __placeholder = "..." }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end });  y = y - visH

            -- Replace the dummy right dropdown with checkbox dropdown
            do
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
            end
        end

        BuildVisRow("MicroBar", "MICRO MENU")
        _, h = W:Spacer(parent, y, 12);  y = y - h
        BuildVisRow("BagBar", "BAG BAR")

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  XP / Rep Bars combined page
    ---------------------------------------------------------------------------
    local function BuildXPRepPage(parent, y)
        local W = EllesmereUI.Widgets
        local _, h

        local BLIZZ_DIS_TIP = "This option does not work with Blizzard Bars. Please use Blizzard Edit Mode."
        local function _blizzDis() return EAB.db.profile.useBlizzardDataBars end

        local function GetVisKey(s)
            return s.barVisibility or "always"
        end
        local function ApplyVisKey(s, v)
            s.barVisibility = v
            s.alwaysHidden      = (v == "never")
            local wasMO = s.mouseoverEnabled
            s.mouseoverEnabled  = (v == "mouseover")
            if v == "mouseover" then
                s._savedBarAlpha = s.mouseoverAlpha or 1
                s.mouseoverAlpha = 0
            elseif wasMO and s._savedBarAlpha then
                s.mouseoverAlpha = s._savedBarAlpha
                s._savedBarAlpha = nil
            end
            s.combatHideEnabled = false
            s.combatShowEnabled = (v == "in_combat")
        end

        local function MakeCogBtn(rgn, showFn, anchorTo)
            local anchor = anchorTo or (rgn and (rgn._lastInline or rgn._control)) or rgn
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) showFn(self) end)
            if rgn then rgn._lastInline = cogBtn end
            return cogBtn
        end

        -- GENERAL section
        _, h = W:SectionHeader(parent, "GENERAL", y);  y = y - h

        local orientValues = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }
        local orientOrder  = { "HORIZONTAL", "VERTICAL" }

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Use Blizzard Bars",
              getValue=function() return EAB.db.profile.useBlizzardDataBars end,
              setValue=function(v)
                  EAB.db.profile.useBlizzardDataBars = v
                  if v then
                      for _, k in ipairs({"XPBar", "RepBar"}) do
                          local frame = ns.dataBarFrames and ns.dataBarFrames[k]
                          if frame then frame:Hide() end
                      end
                      if StatusTrackingBarManager then
                          StatusTrackingBarManager:Show()
                          StatusTrackingBarManager:RegisterAllEvents()
                      end
                  else
                      local anyMissing = false
                      for _, k in ipairs({"XPBar", "RepBar"}) do
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
              disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP,
              getValue=function()
                  return EAB.db.profile.bars["XPBar"] and EAB.db.profile.bars["XPBar"].orientation or "HORIZONTAL"
              end,
              setValue=function(v)
                  for _, k in ipairs({"XPBar", "RepBar"}) do
                      if EAB.db.profile.bars[k] then
                          EAB.db.profile.bars[k].orientation = v
                          if ns.ApplyDataBarLayout then ns.ApplyDataBarLayout(k) end
                      end
                  end
              end });  y = y - h

        _, h = W:Spacer(parent, y, 12);  y = y - h

        -- Per-bar section builder
        local function BuildDataBarSection(barKey, sectionTitle)
            _, h = W:SectionHeader(parent, sectionTitle, y);  y = y - h

            local visRow, visH = W:DualRow(parent, y,
                { type="dropdown", text="Visibility",
                  values=EllesmereUI.VIS_VALUES, order=EllesmereUI.VIS_ORDER,
                  disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP,
                  getValue=function() return GetVisKey(EAB.db.profile.bars[barKey]) end,
                  setValue=function(v)
                      ApplyVisKey(EAB.db.profile.bars[barKey], v)
                      EAB:ApplyAlwaysHidden()
                      EAB:RefreshMouseover()
                      EAB:ApplyCombatVisibility()
                      EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Visibility Options",
                  values={ __placeholder = "..." }, order={ "__placeholder" },
                  getValue=function() return "__placeholder" end,
                  setValue=function() end });  y = y - visH

            -- Replace the dummy right dropdown with checkbox dropdown
            do
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
            end

            _, h = W:DualRow(parent, y,
                { type="slider", text="Width", min=50, max=600, step=1,
                  disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP,
                  getValue=function() return EAB.db.profile.bars[barKey].width or 400 end,
                  setValue=function(v)
                      EAB.db.profile.bars[barKey].width = v
                      if ns.ApplyDataBarLayout then ns.ApplyDataBarLayout(barKey) end
                  end },
                { type="slider", text="Height", min=4, max=40, step=1,
                  disabled=_blizzDis, disabledTooltip=BLIZZ_DIS_TIP,
                  getValue=function() return EAB.db.profile.bars[barKey].height or 18 end,
                  setValue=function(v)
                      EAB.db.profile.bars[barKey].height = v
                      if ns.ApplyDataBarLayout then ns.ApplyDataBarLayout(barKey) end
                  end });  y = y - h
        end

        BuildDataBarSection("XPBar",  "EXPERIENCE BAR")
        _, h = W:Spacer(parent, y, 12);  y = y - h
        BuildDataBarSection("RepBar", "REPUTATION BAR")

        return math.abs(y)
    end

    local function BuildSharedBarSettings(parent, y)
        -- Route combined virtual keys to their dedicated page builders
        local sk = SelectedKey()
        if sk == "MicroBagBars" then
            BuildMicroBagPage(parent, y)
            return y
        elseif sk == "XPRepBars" then
            BuildXPRepPage(parent, y)
            return y
        end

        local W = EllesmereUI.Widgets
        local _, h

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

            local function GetVisKey(s)
                return s.barVisibility or "always"
            end

            local function ApplyVisKey(s, v)
                s.barVisibility = v
                -- Keep boolean flags in sync
                s.alwaysHidden     = (v == "never")
                local wasMO = s.mouseoverEnabled
                s.mouseoverEnabled = (v == "mouseover")
                if v == "mouseover" then
                    s._savedBarAlpha = s.mouseoverAlpha or 1
                    s.mouseoverAlpha = 0
                elseif wasMO and s._savedBarAlpha then
                    s.mouseoverAlpha = s._savedBarAlpha
                    s._savedBarAlpha = nil
                end
                s.combatHideEnabled = false
                s.combatShowEnabled = (v == "in_combat")
            end

            local visRow1
            visRow1, h = W:DualRow(parent, y,
                { type="dropdown", text="Visibility",
                  values=EllesmereUI.VIS_VALUES, order=EllesmereUI.VIS_ORDER,
                  disabled=_visBlizzDis, disabledTooltip=_visBlizzDis and _VIS_BLIZZ_TIP or nil,
                  getValue=function()
                      return GetVisKey(SB())
                  end,
                  setValue=function(v)
                      ApplyVisKey(SB(), v)
                      EAB:ApplyAlwaysHidden()
                      EAB:RefreshMouseover()
                      EAB:ApplyCombatVisibility()
                      EllesmereUI:RefreshPage()
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
                  local eff = bs.mouseoverEnabled and 1 or (bs.mouseoverAlpha or 1)
                  return floor(eff * 100 + 0.5)
              end,
              setValue=function(v)
                  SSet("mouseoverAlpha", v / 100, function(k) EAB:ApplyBarOpacity(k) end)
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

        -----------------------------------------------------------------------
        --  LAYOUT  (hidden when visibility-only)
        -----------------------------------------------------------------------
        if not visOnly then
            _, h = W:SectionHeader(parent, SECTION_LAYOUT, y);  y = y - h

            -- Row 1: Icon Size | Button Spacing
            local iconSizeRow
            iconSizeRow, h = W:DualRow(parent, y,
                { type="slider", text="Icon Size", min=16, max=80, step=1,
                  getValue=function()
                      local s = SB()
                      if s.buttonWidth and s.buttonWidth > 0 then return s.buttonWidth end
                      local info = BAR_LOOKUP[SelectedKey()]
                      local btn1 = info and _G[info.buttonPrefix .. "1"]
                      return btn1 and math.floor((btn1:GetWidth() or 36) + 0.5) or 36
                  end,
                  setValue=function(v)
                      SB().buttonWidth  = v
                      SB().buttonHeight = v
                      EAB:ApplyButtonSizeForBar(SelectedKey())
                      SUpdatePreviewAndResize()
                      EllesmereUI:RefreshPage()
                  end },
                { type="slider", text="Button Spacing", min=-10, max=20, step=1,
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
                        local btn1 = info and _G[info.buttonPrefix .. "1"]
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
                        local btn1 = info and _G[info.buttonPrefix .. "1"]
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
                            local btn1 = info and _G[info.buttonPrefix .. "1"]
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
                  isDisabled=function()
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
                local growDirValues = { up = "Up", down = "Down" }
                local growDirOrder  = { "up", "down" }
                local _, growCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Row Settings",
                    rows = {
                        { type="dropdown", label="Grow Direction", values=growDirValues, order=growDirOrder,
                          get=function() return SVal("growDirection", "up") end,
                          set=function(v)
                              SSet("growDirection", v, function(k) EAB:ApplyIconRowOverrides(k) end)
                              SUpdatePreviewAndResize()
                          end },
                    },
                })
                local growCogShow = growCogShowRaw
                MakeCogBtn(rightRgn, growCogShow)
            end

            -- Row 3: Vertical Orientation | Show Paging Arrows (MainBar only)
            do
                local rightWidget
                if SelectedKey() == "MainBar" then
                    rightWidget = { type="toggle", text="Show Paging Arrows",
                      getValue=function() return SGet("showPagingArrows") or false end,
                      setValue=function(v)
                          SSet("showPagingArrows", v, function(k)
                              if ns.LayoutPagingFrame then ns.LayoutPagingFrame() end
                          end)
                      end,
                      tooltip="Show page up/down arrows next to Action Bar 1 for cycling through action bar pages 1-6." }
                else
                    rightWidget = { type="label", text="" }
                end
                local orientRow
                orientRow, h = W:DualRow(parent, y,
                    { type="toggle", text="Vertical Orientation",
                      disabled=function()
                          return not EAB:BarSupportsOrientation(SelectedKey())
                      end,
                      disabledTooltip="This option is not supported for this bar type",
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
                    rightWidget);  y = y - h
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

                -- Inline cog: Paging Arrows settings (right region, MainBar only)
                if SelectedKey() == "MainBar" then
                    local rRgn = orientRow._rightRegion
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
                    local pagingCogBtn = CreateFrame("Button", nil, rRgn)
                    pagingCogBtn:SetSize(26, 26)
                    pagingCogBtn:SetPoint("RIGHT", rRgn._lastInline or rRgn._control, "LEFT", -9, 0)
                    rRgn._lastInline = pagingCogBtn
                    pagingCogBtn:SetFrameLevel(rRgn:GetFrameLevel() + 5)
                    pagingCogBtn:SetAlpha(pagingOff() and 0.15 or 0.4)
                    local pagingCogTex = pagingCogBtn:CreateTexture(nil, "OVERLAY")
                    pagingCogTex:SetAllPoints()
                    pagingCogTex:SetTexture(EllesmereUI.COGS_ICON)
                    pagingCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                    pagingCogBtn:SetScript("OnLeave", function(self)
                        self:SetAlpha(pagingOff() and 0.15 or 0.4)
                    end)
                    pagingCogBtn:SetScript("OnClick", function(self) pagingCogShow(self) end)

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
                        if off then
                            pagingCogBtn:SetAlpha(0.15)
                            pagingCogBlock:Show()
                        else
                            pagingCogBtn:SetAlpha(0.4)
                            pagingCogBlock:Hide()
                        end
                    end)
                    local pagingCogInitOff = pagingOff()
                    pagingCogBtn:SetAlpha(pagingCogInitOff and 0.15 or 0.4)
                    if pagingCogInitOff then pagingCogBlock:Show() else pagingCogBlock:Hide() end
                end
            end

            -------------------------------------------------------------------
            -------------------------------------------------------------------
            --  ICON APPEARANCE
            -------------------------------------------------------------------
            iconsSectionHeader, h = W:SectionHeader(parent, SECTION_ICON_APPEARANCE, y);  y = y - h

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

            local classColorBorderRow
            classColorBorderRow, h = W:DualRow(parent, y,
                { type="multiSwatch", text="Border Color",
                  swatches = {
                    { tooltip = "Custom Color",
                      hasAlpha = true,
                      getValue = function()
                          local c = SGet("borderColor")
                          if not c then return 0, 0, 0, 1 end
                          return c.r, c.g, c.b, c.a or 1
                      end,
                      setValue = function(r, g, b, a)
                          SSetColor("borderColor", r, g, b, a, function(k)
                              EAB:ApplyBordersForBar(k)
                              EAB:ApplyShapesForBar(k)
                          end)
                          SSetColor("shapeBorderColor", r, g, b, a, function(k)
                              EAB:ApplyShapesForBar(k)
                          end)
                          SUpdatePreview()
                      end,
                      onClick = function(self)
                          -- First click: switch from class to custom mode
                          if SGet("borderClassColor") then
                              SSet("borderClassColor", false, function(k)
                                  EAB:ApplyBordersForBar(k)
                                  EAB:ApplyShapesForBar(k)
                              end)
                              SUpdatePreview()
                              return
                          end
                          -- Second click: already in custom mode, open color picker
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha = function()
                          local v = SGet("borderClassColor")
                          if v == nil then v = SGet("shapeBorderClassColor") or false end
                          return v and 0.3 or 1
                      end },
                    { tooltip = "Class Colored",
                      getValue = function()
                          local _, ct = UnitClass("player")
                          if ct and RAID_CLASS_COLORS[ct] then
                              local cc = RAID_CLASS_COLORS[ct]
                              return cc.r, cc.g, cc.b, 1
                          end
                          return 1, 1, 1, 1
                      end,
                      setValue = function() end,
                      onClick = function()
                          SSet("borderClassColor", true, function(k)
                              EAB:ApplyBordersForBar(k)
                              EAB:ApplyShapesForBar(k)
                          end)
                          SUpdatePreview()
                      end,
                      refreshAlpha = function()
                          local v = SGet("borderClassColor")
                          if v == nil then v = SGet("shapeBorderClassColor") or false end
                          return v and 1 or 0.3
                      end },
                  } },
                { type="dropdown", text="Custom Button Shape",
                  values=SHAPE_VALUES, order=SHAPE_ORDER,
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
                      end)
                      EAB:RefreshProcGlows()
                      SUpdatePreview()
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
            borderRow = classColorBorderRow
            -- Sync icon: Border Color (left region of classColorBorderRow)
            do
                local rgn = classColorBorderRow._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Border Color to all Bars",
                    onClick = function()
                        local c = SB().borderColor
                        local cc = SB().borderClassColor
                        for _, key in ipairs(GROUP_BAR_ORDER) do
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
                        local c = SB().borderColor
                        local cc = SB().borderClassColor or false
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            local bc = EAB.db.profile.bars[key].borderColor
                            if (EAB.db.profile.bars[key].borderClassColor or false) ~= cc then return false end
                            if c and bc then
                                if c.r ~= bc.r or c.g ~= bc.g or c.b ~= bc.b then return false end
                            elseif c ~= bc then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local c = SB().borderColor
                            local cc = SB().borderClassColor
                            for _, key in ipairs(checkedKeys) do
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
            -- Sync icon: Custom Button Shape (right region of classColorBorderRow)
            do
                local rgn = classColorBorderRow._rightRegion
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

            -- Row 2: Icon Zoom (slider) | Border Size (dropdown)
            local zoomBorderRow
            zoomBorderRow, h = W:DualRow(parent, y,
                { type="slider", text="Icon Zoom", min=0, max=10, step=0.5,
                  getValue=function() return SVal("iconZoom", EAB.db.profile.iconZoom or 5.5) end,
                  setValue=function(v)
                      SSet("iconZoom", v, function(k)
                          EAB:ApplyBordersForBar(k)
                          EAB:ApplyShapesForBar(k)
                      end)
                      SUpdatePreview()
                  end },
                { type="dropdown", text="Border Size",
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

            -- Sync icons: Icon Zoom (left) and Border Size (right)
            do
                local rgn = zoomBorderRow._leftRegion
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
            do
                local rgn = zoomBorderRow._rightRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Border Size to all Bars",
                    onClick = function()
                        local v = SB().borderThickness or "thin"
                        local entry = ns.BORDER_THICKNESS[v]
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].borderThickness = v
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
                            EAB:ApplyBordersForBar(key)
                            EAB:ApplyShapesForBar(key)
                        end
                        EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local v = SB().borderThickness or "thin"
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].borderThickness or "thin") ~= v then return false end
                        end
                        return true
                    end,
                    flashTargets = function() return { rgn } end,
                    multiApply = {
                        elementKeys   = GROUP_BAR_ORDER,
                        elementLabels = SHORT_LABELS,
                        getCurrentKey = function() return SelectedKey() end,
                        onApply       = function(checkedKeys)
                            local v = SB().borderThickness or "thin"
                            local entry = ns.BORDER_THICKNESS[v]
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].borderThickness = v
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
                                EAB:ApplyBordersForBar(key)
                                EAB:ApplyShapesForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end

            -- Row 3: Bar Background (toggle + inline swatch + cog) | Click Through
            local bgAlwaysRow
            bgAlwaysRow, h = W:DualRow(parent, y,
                { type="toggle", text="Bar Background",
                  getValue=function()
                      return SGet("bgEnabled")
                  end,
                  setValue=function(v)
                      SSet("bgEnabled", v, function(k) EAB:ApplyBackgroundForBar(k) end)
                      SUpdatePreview()
                      EllesmereUI:RefreshPage()
                  end },
                { type="toggle", text="Click Through",
                  getValue=function()
                      return SGet("clickThrough")
                  end,
                  setValue=function(v)
                      SSet("clickThrough", v, function(k) EAB:ApplyClickThroughForBar(k) end)
                  end });  y = y - h
            -- Sync icon: Bar Background settings (left region)
            do
                local rgn = bgAlwaysRow._leftRegion
                EllesmereUI.BuildSyncIcon({
                    region  = rgn,
                    tooltip = "Apply Background Settings to all Bars",
                    onClick = function()
                        local s = SB()
                        local en = s.bgEnabled
                        local c = s.bgColor
                        local px = s.bgPadX or 0
                        local py = s.bgPadY or 0
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            EAB.db.profile.bars[key].bgEnabled = en
                            if c then EAB.db.profile.bars[key].bgColor = { r=c.r, g=c.g, b=c.b, a=c.a } end
                            EAB.db.profile.bars[key].bgPadX = px
                            EAB.db.profile.bars[key].bgPadY = py
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
                            local px = s.bgPadX or 0
                            local py = s.bgPadY or 0
                            for _, key in ipairs(checkedKeys) do
                                EAB.db.profile.bars[key].bgEnabled = en
                                if c then EAB.db.profile.bars[key].bgColor = { r=c.r, g=c.g, b=c.b, a=c.a } end
                                EAB.db.profile.bars[key].bgPadX = px
                                EAB.db.profile.bars[key].bgPadY = py
                                EAB:ApplyBackgroundForBar(key)
                            end
                            EllesmereUI:RefreshPage()
                        end,
                    },
                })
            end
            -- Sync icon: Click Through (right region)
            do
                local rgn = bgAlwaysRow._rightRegion
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

            -- Inline elements on Bar Background (left): color swatch + cog (Width/Height)
            do
                local leftRgn = bgAlwaysRow._leftRegion

                -- Color swatch
                local bgColorGet = function()
                    local c = SGet("bgColor")
                    if not c then return 0, 0, 0, 0.5 end
                    return c.r, c.g, c.b, c.a
                end
                local bgColorSet = function(r, g, b, a)
                    SSetColor("bgColor", r, g, b, a, function(k) EAB:ApplyBackgroundForBar(k) end)
                    SUpdatePreview()
                end
                local bgSwatch, bgUpdateSwatch = EllesmereUI.BuildColorSwatch(leftRgn, leftRgn:GetFrameLevel() + 5, bgColorGet, bgColorSet, true, 20)
                PP.Point(bgSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
                leftRgn._lastInline = bgSwatch
                EllesmereUI.RegisterWidgetRefresh(function()
                    local off = BgDisabled()
                    bgSwatch:SetAlpha(off and 0.15 or 1)
                    bgUpdateSwatch()
                end)
                bgSwatch:SetAlpha(BgDisabled() and 0.15 or 1)
                -- Wrap OnClick to block color picker when bg is disabled (keep mouse enabled for tooltip)
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
                bgSwatch:SetScript("OnLeave", function(self)
                    EllesmereUI.HideWidgetTooltip()
                end)

                -- Cog for Width/Height
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
                local bgCogShow = bgCogShowRaw
                local bgCogAnchor = leftRgn._lastInline or leftRgn._control
                local bgCogBtn = MakeCogBtn(leftRgn, bgCogShow, bgCogAnchor, EllesmereUI.RESIZE_ICON)
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
                    bgCogShow(self)
                end)
                EllesmereUI.RegisterWidgetRefresh(function()
                    bgCogBtn:SetAlpha(BgDisabled() and 0.15 or 0.4)
                end)
            end

            -- Row 4: Out of Range Coloring (toggle + inline swatch) | empty
            local rangeRow
            rangeRow, h = W:DualRow(parent, y,
                { type="toggle", text="Out of Range Coloring",
                  getValue=function()
                      return SGet("outOfRangeColoring") or false
                  end,
                  setValue=function(v)
                      SSet("outOfRangeColoring", v, function() EAB:ApplyRangeColoring() end)
                      EllesmereUI:RefreshPage()
                  end },
                { type="toggle", text="Disable Tooltips",
                  getValue=function()
                      return EAB.db and EAB.db.profile.disableTooltips or false
                  end,
                  setValue=function(v)
                      if EAB.db then EAB.db.profile.disableTooltips = v end
                  end });  y = y - h
            -- Sync icon: Out of Range Coloring (left region)
            do
                local rgn = rangeRow._leftRegion
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
                local leftRgn = rangeRow._leftRegion
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

                -- Block overlay when disabled
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

            _, h = W:Spacer(parent, y, 20);  y = y - h

            -------------------------------------------------------------------
            --  TEXT
            -------------------------------------------------------------------
            textSectionHeader, h = W:SectionHeader(parent, SECTION_TEXT, y);  y = y - h

            -- Row 1: Hide Keybind Text (left) | Keybind Text colorpicker (right)
            row, h = W:DualRow(parent, y,
                { type="toggle", text="Hide Keybind Text",
                  getValue=function()
                      return SGet("hideKeybind")
                  end,
                  setValue=function(v)
                      SSet("hideKeybind", v, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end },
                { type="colorpicker", text="Keybind Text",
                  getValue=function()
                      local c = SGet("keybindFontColor")
                      if not c then return 1, 1, 1, 1 end
                      return c.r, c.g, c.b, 1
                  end,
                  setValue=function(r, g, b)
                      SSetColor("keybindFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end,
                  hasAlpha=false });  y = y - h
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
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].keybindFontSize or 12) ~= sz then return false end
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

            -- Inline cog on Keybind Text (right) for Size + X/Y offsets
            do
                local rightRgn = keybindRow._rightRegion
                local _, kbSizeCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Keybind Text Settings",
                    rows = {
                        { type="slider", label="Size", min=6, max=24, step=1,
                          get=function() return SVal("keybindFontSize", 12) end,
                          set=function(v)
                              SSet("keybindFontSize", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="X Offset", min=-20, max=20, step=1,
                          get=function() return SVal("keybindOffsetX", 0) end,
                          set=function(v)
                              SSet("keybindOffsetX", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="Y Offset", min=-20, max=20, step=1,
                          get=function() return SVal("keybindOffsetY", 0) end,
                          set=function(v)
                              SSet("keybindOffsetY", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                    },
                })
                local kbSizeCogShow = kbSizeCogShowRaw
                MakeCogBtn(rightRgn, kbSizeCogShow, nil, EllesmereUI.RESIZE_ICON)
            end

            -- Row 2: Charges Text colorpicker (left) | Cooldown Text colorpicker (right)
            chargesRow, h = W:DualRow(parent, y,
                { type="colorpicker", text="Charges Text",
                  getValue=function()
                      local c = SGet("countFontColor")
                      if not c then return 1, 1, 1, 1 end
                      return c.r, c.g, c.b, 1
                  end,
                  setValue=function(r, g, b)
                      SSetColor("countFontColor", r, g, b, nil, function(k) EAB:ApplyFontsForBar(k) end)
                      SUpdatePreview()
                  end,
                  hasAlpha=false },
                { type="colorpicker", text="Cooldown Text",
                  getValue=function()
                      local c = SGet("cooldownTextColor")
                      if not c then return 1, 1, 1, 1 end
                      return c.r, c.g, c.b, 1
                  end,
                  setValue=function(r, g, b)
                      SSetColor("cooldownTextColor", r, g, b, nil, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                      SUpdatePreview()
                  end,
                  hasAlpha=false });  y = y - h
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
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].countFontSize or 12) ~= sz then return false end
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

            -- Inline cog on Charges Text (left) for Size + X/Y offsets
            do
                local leftRgn = chargesRow._leftRegion
                local _, ctSizeCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Charges Text Settings",
                    rows = {
                        { type="slider", label="Size", min=6, max=24, step=1,
                          get=function() return SVal("countFontSize", 12) end,
                          set=function(v)
                              SSet("countFontSize", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="X Offset", min=-20, max=20, step=1,
                          get=function() return SVal("countOffsetX", 0) end,
                          set=function(v)
                              SSet("countOffsetX", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="Y Offset", min=-20, max=20, step=1,
                          get=function() return SVal("countOffsetY", 0) end,
                          set=function(v)
                              SSet("countOffsetY", v, function(k) EAB:ApplyFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                    },
                })
                local ctSizeCogShow = ctSizeCogShowRaw
                MakeCogBtn(leftRgn, ctSizeCogShow, nil, EllesmereUI.RESIZE_ICON)
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
                        for _, key in ipairs(GROUP_BAR_ORDER) do
                            if (EAB.db.profile.bars[key].cooldownFontSize or 12) ~= sz then return false end
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

            -- Inline cog on Cooldown Text (right region of row 2) for Size + X/Y offsets
            do
                local rightRgn = chargesRow._rightRegion
                local _, cdSizeCogShowRaw = EllesmereUI.BuildCogPopup({
                    title = "Cooldown Text Settings",
                    rows = {
                        { type="slider", label="Size", min=6, max=24, step=1,
                          get=function() return SVal("cooldownFontSize", 12) end,
                          set=function(v)
                              SSet("cooldownFontSize", v, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="X Offset", min=-20, max=20, step=1,
                          get=function() return SVal("cooldownTextXOffset", 0) end,
                          set=function(v)
                              SSet("cooldownTextXOffset", v, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                        { type="slider", label="Y Offset", min=-20, max=20, step=1,
                          get=function() return SVal("cooldownTextYOffset", 0) end,
                          set=function(v)
                              SSet("cooldownTextYOffset", v, function(k) EAB:ApplyCooldownFontsForBar(k) end)
                              SUpdatePreview()
                          end },
                    },
                })
                local cdSizeCogShow = cdSizeCogShowRaw
                MakeCogBtn(rightRgn, cdSizeCogShow, nil, EllesmereUI.RESIZE_ICON)
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
                    EAB.db.profile.selectedBar = v
                    EllesmereUI:InvalidateContentHeaderCache()
                    EllesmereUI:SetContentHeader(_barsHeaderBuilder)
                    -- Always force full rebuild — combined keys (MicroBagBars,
                    -- XPRepBars) and StanceBar share the same visOnly/dataBar
                    -- flags, so the old conditional missed transitions between them.
                    EllesmereUI:RefreshPage(true)
                    -- MicroBar / BagBar have very little content; reset scroll
                    -- so the page isn't stuck at a stale offset from a taller bar.
                    if nowVisOnly then
                        EllesmereUI.SmoothScrollTo(0)
                    end
                    -- Show/hide edit overlay for the newly selected bar
                    ShowEditOverlay(v)
                end,
                function(key) if not IsBarEnabled(key) then return EllesmereUI.DisabledTooltip("this action bar") end end
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
                    _abPreviewHintFS:SetText("Click elements to scroll to and highlight their options")
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
              disabled=function() return p.pushedUseClassColor end,
              disabledTooltip="Class Colors",
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
              getValue=function() return p.pushedUseClassColor end,
              setValue=function(v)
                  SetUnifiedClassColor(v)
              end });  y = y - h

        -- Row 2: Pushed Type (left, cog + preview) | Highlight Type (right, cog + preview)
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Pushed Type",
              tooltip="The overlay that appears on the icon when you press and hold a spell button",
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
              getValue=function() return p.hideCastingAnimations or castAnimForced() end,
              setValue=function(v)
                  p.hideCastingAnimations = v
                  -- Live-apply: register/unregister casting events
                  if ActionBarActionEventsFrame then
                      if v then
                          ActionBarActionEventsFrame:UnregisterEvent("UNIT_SPELLCAST_START")
                          ActionBarActionEventsFrame:UnregisterEvent("UNIT_SPELLCAST_STOP")
                          ActionBarActionEventsFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                          ActionBarActionEventsFrame:UnregisterEvent("UNIT_SPELLCAST_FAILED")
                          ActionBarActionEventsFrame:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
                      else
                          ActionBarActionEventsFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
                          ActionBarActionEventsFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
                          ActionBarActionEventsFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
                          ActionBarActionEventsFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
                          ActionBarActionEventsFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
                      end
                  end
              end },
            { type="label", text="" });  y = y - h

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
              disabled=function() return hasCustomShape end,
              disabledTooltip="Custom shapes always use Shape Glow — change your bar shape to None or Cropped to pick a different glow",
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
              disabled=procGlowOff, disabledTooltip="This option requires a custom glow to be selected",
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
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Class Colors"))
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
        pages       = { PAGE_DISPLAY, PAGE_ANIMATIONS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName ~= PAGE_DISPLAY then
                HideEditOverlay()
            end
            if pageName == PAGE_DISPLAY then
                return BuildBarDisplayPage(pageName, parent, yOffset)
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
                EAB.db.sv._capturedOnce = nil
            end
            ReloadUI()
        end,
    })
end)
