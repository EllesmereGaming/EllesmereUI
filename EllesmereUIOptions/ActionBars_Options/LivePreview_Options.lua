if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\LivePreview_Options.lua
--  Action Bars options: the live preview in the Bar Display content header
--  (BuildLivePreview). Definitions only; the shared helpers come from
--  ns._ABO_OptEnv (filled by EUI_ActionBars_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not ns then return end  -- module disabled: no options page

--- Build (or rebuild for a different bar) the live preview frame. Shows only
--- Edit-Mode-enabled buttons (numButtonsShowable) at the first real button's
--- GetWidth/GetHeight so icon size matches Blizzard's.
--- @param parent  Frame   scrollChild content parent
--- @param yOff    number  current y offset in the page layout
--- @return number height consumed by the preview
local function BuildLivePreview(parent, yOff)
    local env = ns._ABO_OptEnv
    local BAR_LOOKUP, EAB, FirstBarButton, floor = env.BAR_LOOKUP, env.EAB, env.FirstBarButton, env.floor
    local optState, pcall, PP, RANGE_INDICATOR = env.optState, env.pcall, env.PP, env.RANGE_INDICATOR
    local SB, SelectedKey = env.SB, env.SelectedKey
    local barKey  = SelectedKey()
    local barInfo = BAR_LOOKUP[barKey]
    -- Skip visibility-only / data bars (no count). Guard on count, not buttonPrefix:
    -- custom bars (Bar9/Bar10) lack a prefix but render from EABButtons like any bar.
    if not barInfo or not barInfo.count then
        optState.activePreview = nil
        return 0
    end

    local PAD      = EllesmereUI.CONTENT_PAD
    local maxBtns  = barInfo.count   -- always 12, used for pre-allocation

    -- Our custom bar frame (may be nil during first build before bars are created)
    local barFrame = _G["EABBar_" .. barKey]

    -- Real button size from the first button, rounded to kill float noise.
    local btn1 = FirstBarButton(barKey)
    local realBtnW = math.floor((btn1 and btn1:GetWidth() or 0) + 0.5)
    local realBtnH = math.floor((btn1 and btn1:GetHeight() or 0) + 0.5)
    if realBtnW < 1 then realBtnW = 36 end
    if realBtnH < 1 then realBtnH = 36 end

    -- No Blizzard Edit Mode scale: our bar scale applies directly to the frame.
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

    local UpdatePVThumb = EllesmereUI.AttachSmoothScrollbar(sf, {
        step = 40, thumbMin = 20, trackParent = wrapper, topInset = 2, level = 5, panelWheel = true })

    -- Store refs for height management after Update()
    pf._wrapper = wrapper
    pf._scrollFrame = sf
    pf._previewScale = previewScale
    pf._PREVIEW_MAX_H = PREVIEW_MAX_H
    pf._updatePVThumb = UpdatePVThumb

    local function Snap(val)
        return EllesmereUI.PP.SnapForES(val, pf:GetEffectiveScale())
    end

    -- Snap to whole physical pixels at the preview's effective scale (same
    -- approach as the border system).
    local function SnapS(val)
        local es = pf:GetEffectiveScale()
        return EllesmereUI.PP.SnapForES(val, es)
    end

    -- Disable WoW's automatic pixel snapping on a texture
    local UnsnapTex = EllesmereUI.PP.DisablePixelSnap

    -- Pre-create all 12 per-button sub-frames/textures; show/hide by
    -- numButtonsShowable --------------------------------------------------
    local buttons = {}
    local DEFAULT_FONT = (EllesmereUI.GetFontPath("actionBars"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

    for i = 1, maxBtns do
        local bf = CreateFrame("Frame", nil, pf)
        bf:SetSize(baseBtnW, baseBtnH)
        bf:Hide()

        local icon = bf:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetColorTexture(0.077, 0.068, 0.058, 1)

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
        EllesmereUI.PrimeFontShadow(macroFS, false)
        macroFS:SetFont(DEFAULT_FONT, 12, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
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

    -- Stock styles: the stock button art on a preview button, laid out as
    -- the live buttons lay it (they keep Blizzard's own textures, scaled
    -- with the button). Blizzard Style: the rounded icon-frame mask centred
    -- on the icon and the icon-frame ring at its stock 46x45-on-45 ratio.
    -- Classic WoW UI: the vanilla slot ring at 66/36 of the button
    -- (CENTER 0,-1/36), the empty-slot art on an empty slot, no mask. No
    -- EUI border, shape or backdrop either way. Built once per button,
    -- re-sized per pass; the kit not in use steps aside.
    local blizzMaskInfo
    local function ApplyBlizzPreviewButton(entry, bf, icon, classic, filled)
        local bT, bB, bL, bR = entry.borders[1], entry.borders[2], entry.borders[3], entry.borders[4]
        bT:Hide(); bB:Hide(); bL:Hide(); bR:Hide()
        if entry._bdPreview then entry._bdPreview:Hide() end
        if entry.shapeBorderTex then entry.shapeBorderTex:Hide() end
        if entry.shapeMask and entry._prevMasked then
            pcall(icon.RemoveMaskTexture, icon, entry.shapeMask)
            entry.shapeMask:Hide()
            entry._prevMasked = false
        end
        icon:ClearAllPoints()
        icon:SetAllPoints(bf)
        local w, h = bf:GetSize()
        if classic then
            if entry.blizzMask then entry.blizzMask:Hide() end
            if entry.blizzRing then entry.blizzRing:Hide() end
            local cring = entry.classicRing
            if not cring then
                cring = bf:CreateTexture(nil, "ARTWORK", nil, 2)
                UnsnapTex(cring)
                entry.classicRing = cring
            end
            local art = ns.AB_CLASSIC
            cring:SetTexture(filled and art.slot or art.empty)
            cring:SetTexCoord(0, 1, 0, 1)
            cring:ClearAllPoints()
            cring:SetPoint("CENTER", bf, "CENTER", 0, -h / 36)
            cring:SetSize(66 * w / 36, 66 * h / 36)
            cring:Show()
            return
        end
        if entry.classicRing then entry.classicRing:Hide() end
        local mask = entry.blizzMask
        if not mask then
            mask = bf:CreateMaskTexture()
            mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
            icon:AddMaskTexture(mask)
            entry.blizzMask = mask
            -- Above the icon, below the OVERLAY texts (a NormalTexture on
            -- the live button sits under its font strings the same way).
            local ring = bf:CreateTexture(nil, "ARTWORK", nil, 2)
            ns.AB_StockAtlas(ring, "UI-HUD-ActionBar-IconFrame")
            UnsnapTex(ring)
            entry.blizzRing = ring
        end
        if blizzMaskInfo == nil then
            blizzMaskInfo = C_Texture.GetAtlasInfo("UI-HUD-ActionBar-IconFrame-Mask") or false
        end
        local sx, sy = w / 45, h / 45
        mask:ClearAllPoints()
        mask:SetPoint("CENTER", icon, "CENTER", 0, 0)
        if blizzMaskInfo then
            mask:SetSize(blizzMaskInfo.width * sx, blizzMaskInfo.height * sy)
        else
            mask:SetSize(w, h)
        end
        mask:Show()
        local ring = entry.blizzRing
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, 0)
        ring:SetSize(46 * sx, 45 * sy)
        ring:Show()
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
        local spacing   = settings.buttonPadding or 2
        local resolvedBrdSize, resolvedBrdPx = ns.ResolveBorderThickness(settings)
        local brdOn     = resolvedBrdSize > 0
        local brdSize   = resolvedBrdSize
        local brdPx     = resolvedBrdPx   -- the exact size the live buttons resolve (nil = legacy)
        local brdColor  = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 }
        local brdClassColor = settings.borderClassColor
        local zoom = ((settings.iconZoom or EAB.db.profile.iconZoom or 5.5)) / 100
        local square    = EAB.db.profile.squareIcons
        -- Stock styles: stock button art (see ApplyBlizzPreviewButton);
        -- shapes, zoom and EUI borders do not apply, as on the live bars.
        local abStyle   = EllesmereUI.BlizzStyle.Active("actionbars")
        local blizzAB   = abStyle ~= "eui"
        local classicAB = abStyle == "classic"
        local hideKB    = settings.hideKeybind

        -- Font path (global setting)
        local fontPath  = (EllesmereUI.GetFontPath("actionBars")) or DEFAULT_FONT

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
        if not blizzAB and btnShape ~= "none" and btnShape ~= "cropped" then
            local shapeExp = SnapS(ns.SHAPE_BTN_EXPAND * (self._blizzEditScale or 1))
            scaledBtnW = scaledBtnW + shapeExp
            scaledBtnH = scaledBtnH + shapeExp
        end
        -- Shrink button height for "cropped" mode (10% top + 10% bottom)
        if not blizzAB and btnShape == "cropped" then
            scaledBtnH = SnapS(scaledBtnH * 0.80)
        end

        local scaledPad  = SnapS(spacing * (self._blizzEditScale or 1))

        local isVertical = (settings.orientation or "horizontal") == "vertical"

        local totalScale = (self._blizzEditScale or 1)
        local scaledKBSize = math.max(6, floor(kbSize * totalScale + 0.5))
        local scaledCTSize = math.max(6, floor(ctSize * totalScale + 0.5))
        local scaledMCSize = math.max(6, floor(mcSize * totalScale + 0.5))

        -- Multi-row grid: vertical swaps cols/rows, uses actual column count (numRows may not fully fill).
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
        -- Paging Arrows (Action Bar 1), sized as the live ones
        -- (ns.AB_PagingArrowMetrics): beside a horizontal bar (grid and arrows
        -- centred as one), above or below a vertical one.
        local pgArrow, pgText, pgGap, pgOff, pgRight
        if info.key == "MainBar" and settings.showPagingArrows then
            pgArrow, pgText, pgGap, pgOff = ns.AB_PagingArrowMetrics(btnH)
            pgRight = settings.pagingArrowsRight and true or false
        end
        local pgSide = (pgArrow and not isVertical) and (pgArrow + pgOff) or 0
        local gridStartX = Snap(math.max(0, (self:GetWidth() - gridW - pgSide) / 2) + (pgRight and 0 or pgSide))

        -- Inset for background growth above/below the grid (ScrollFrame clips its child; without it the top border is lost).
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
        -- The bar's chrome (painted after the buttons): WoW Forever's
        -- frame and dividers and the bar's end caps (horizontal only),
        -- with room above and below the grid for them.
        local fvPrev = ns.AB_ForeverBg(info.key)
        local capsPrev, capsL, capsR
        if not isVertical then capsPrev, capsL, capsR = ns.AB_CapsLook(info.key) end
        if fvPrev or capsPrev then
            local reachT, reachB = ns.AB_ChromeReach(scaledBtnW, gridH, fvPrev, capsPrev, gridRows > 1, totalScale, info.key)
            bgTopInset = math.max(bgTopInset, Snap(reachT - 10))
            bgBottomInset = math.max(bgBottomInset, Snap(reachB - 10))
        end
        -- Room for the paging arrows past the grid's 10px margins.
        if pgArrow then
            if isVertical then
                local need = Snap(pgArrow + pgOff - 10)
                if pgRight then
                    bgBottomInset = math.max(bgBottomInset, need)
                else
                    bgTopInset = math.max(bgTopInset, need)
                end
            else
                local need = Snap((pgArrow * 2 + pgText + pgGap * 2 - gridH) / 2 - 10)
                bgTopInset = math.max(bgTopInset, need)
                bgBottomInset = math.max(bgBottomInset, need)
            end
        end

        local frameH = Snap(gridH + 20 + bgTopInset + bgBottomInset)
        self:SetHeight(frameH)

        -- Resize wrapper to min(content, max) and toggle scrollbar
        local parentH = frameH * self._previewScale
        local maxH = self._PREVIEW_MAX_H
        if parentH > maxH then
            -- Bottom padding so the last row is fully visible when scrolled down
            local paddedH = Snap(gridH + 20 + bgTopInset + bgBottomInset + scaledBtnH)
            self:SetHeight(paddedH)
            -- Snap the viewport to a whole number of rows so the cap never slices
            -- a row in half; topInset is the space above row 1 (matches gridStartY).
            local topInset = Snap(10) + bgTopInset
            local rowStep = scaledBtnH + scaledPad
            local visibleRows = math.max(1, math.floor((maxH / self._previewScale - topInset + scaledPad) / rowStep + 0.001))
            visibleRows = math.min(visibleRows, gridRows)
            local cappedLocalH = Snap(topInset + visibleRows * scaledBtnH + (visibleRows - 1) * scaledPad)
            self._wrapper:SetHeight(math.min(maxH, cappedLocalH * self._previewScale))
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
        -- growUp covers "up" OR "center": horizontal bars only store left/right/center, so a plain == "up" check never fires.
        local _gd = settings.growDirection or "up"
        local growUp = (_gd == "up" or _gd == "center")
        local colFlip, rowFlip, cornerFill = ns.GetOrderFlips(settings, isVertical, growUp)
        for i = 1, maxBtns do
            local entry = buttons[i]
            local bf    = entry.frame
            local icon  = entry.icon

            if i >= leftmost and i <= previewCount then
                local idx = i - leftmost  -- 0-based index
                local col, row
                if isVertical then
                    if cornerFill then
                        -- Corner modes fill across columns (gridCols) first, then wrap down.
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
                -- dispCol/dispRow = visual position after order flips; col stays the content
                -- column so vertical-centering math below still measures the right buttons.
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
                    if not blizzAB and (square or zoom > 0 or btnShape == "cropped") then
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

                if blizzAB then
                    ApplyBlizzPreviewButton(entry, bf, icon, classicAB, iconTex and true or false)
                else
                -- The styles' rings and mask step aside on the EUI look (the
                -- flag is a live read: a profile switch can flip it mid-page).
                if entry.blizzRing then entry.blizzRing:Hide() end
                if entry.blizzMask then entry.blizzMask:Hide() end
                if entry.classicRing then entry.classicRing:Hide() end
                local bT, bB, bL, bR = entry.borders[1], entry.borders[2], entry.borders[3], entry.borders[4]
                local brdTexKey = settings.borderTexture or "solid"
                local brdIsSolid = (brdTexKey == "solid")

                if brdOn and brdIsSolid then
                    -- Solid: 4 texture strips
                    local cr, cg, cb, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a
                    if useClassColor then
                        local _, ct2 = UnitClass("player")
                        if ct2 then local cc2 = RAID_CLASS_COLORS[ct2]; if cc2 then cr, cg, cb = cc2.r, cc2.g, cc2.b end end
                    end
                    -- The pixels the live strips draw (SnapBorderTextures): the exact size
                    -- when set, else the step, as whole pixels at this button's scale.
                    local onePx = EllesmereUI.PP.perfect / bf:GetEffectiveScale()
                    local sz = math.max(onePx, math.floor((brdPx or brdSize) + 0.5) * onePx)

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
                    -- The live edge (ApplyBorderStyle) in this frame's units: the exact
                    -- size as whole pixels at UIParent scale, else the step's edge. ratio
                    -- cancels any scale between the preview button and UIParent so the
                    -- edge is the game's size (1 today: the preview runs at UIParent scale).
                    local gamePP = EllesmereUI.PP
                    local EDGE_MAP = EllesmereUI.BORDER_EDGE_MAP
                    local uiES = UIParent:GetEffectiveScale()
                    local pvES = bf:GetEffectiveScale()
                    local ratio = (pvES > 0.01 and uiES > 0) and (uiES / pvES) or 1
                    local edgeSize
                    if brdPx then
                        edgeSize = math.max(1, math.floor(brdPx + 0.5)) * gamePP.mult * ratio
                    else
                        edgeSize = (EDGE_MAP[brdSize] or EDGE_MAP[1]) * ratio
                    end
                    local thKey = settings.borderThickness or "thin"
                    local dox, doy, dsx, dsy = EllesmereUI.GetBorderDefaults("actionbars", brdTexKey, thKey)
                    if brdPx then
                        -- The step's defaults follow the exact edge (the user's own offsets stay).
                        local f = (brdPx * gamePP.mult) / (EDGE_MAP[brdSize] or EDGE_MAP[1])
                        dox, doy, dsx, dsy = gamePP.Snap(dox * f), gamePP.Snap(doy * f), gamePP.Snap(dsx * f), gamePP.Snap(dsy * f)
                    end
                    local adjX = (settings.borderTextureOffset or dox) * ratio
                    local adjY = (settings.borderTextureOffsetY or doy) * ratio
                    local offX, offY
                    if EllesmereUI.BorderTextureUsesScaleOffset(brdTexKey) then
                        offX = (edgeSize / 2) + adjX
                        offY = (edgeSize / 2) + adjY
                    else
                        offX = adjX
                        offY = adjY
                    end
                    local sx = (settings.borderTextureShiftX or dsx) * ratio
                    local sy = (settings.borderTextureShiftY or dsy) * ratio
                    -- Whole pixels at the preview's own scale, as ApplyBorderStyle snaps the live anchors.
                    local snapES = (pvES > 0.01) and pvES or uiES
                    offX, offY = gamePP.SnapForES(offX, snapES), gamePP.SnapForES(offY, snapES)
                    sx, sy = gamePP.SnapForES(sx, snapES), gamePP.SnapForES(sy, snapES)
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
                    local SHAPE_INSETS = EllesmereUI.SHAPE_INSETS
                    local insetPx = SHAPE_INSETS[btnShape] or 17
                    local visRatio = (128 - 2 * insetPx) / 128
                    local expand = ((1 / visRatio) - 1) * 0.5
                    icon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand)
                    bT:Hide(); bB:Hide(); bL:Hide(); bR:Hide()
                    if not entry.shapeBorderTex then
                        entry.shapeBorderTex = bf:CreateTexture(nil, "OVERLAY", nil, 6)
                    end
                    -- No mask on border: render at button frame size
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
                    icon:ClearAllPoints()
                    icon:SetAllPoints(bf)
                    -- Texcoords: cropped trims top/bottom, none uses zoom only
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
                end -- close Blizzard Style / EUI look split
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
                local kbOX = (settings.keybindOffsetX or 0) * totalScale
                local kbOY = (settings.keybindOffsetY or 0) * totalScale
                if not (settings.keybindAnchor and EAB.PlaceButtonText(keybindFS, bf, settings.keybindAnchor, kbOX, kbOY)) then
                    keybindFS:ClearAllPoints()
                    keybindFS:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -1 + kbOX, -3 + kbOY)
                    keybindFS:SetPoint("TOPLEFT", bf, "TOPLEFT", 4 + kbOX, -3 + kbOY)
                    keybindFS:SetJustifyH("RIGHT")
                end

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
                local ctOX = (settings.countOffsetX or 0) * totalScale
                local ctOY = (settings.countOffsetY or 0) * totalScale
                if not (settings.countAnchor and EAB.PlaceButtonText(countFS, bf, settings.countAnchor, ctOX, ctOY)) then
                    countFS:ClearAllPoints()
                    countFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1 + ctOX, 4 + ctOY)
                    countFS:SetJustifyH("RIGHT")
                end

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
                    EllesmereUI.PrimeFontShadow(macroFS, false)
                    macroFS:SetFont(fontPath, scaledMCSize, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
                    macroFS:SetTextColor(mcColor.r, mcColor.g, mcColor.b)
                    local mcOX = (settings.macroOffsetX or 0) * totalScale
                    local mcOY = (settings.macroOffsetY or 0) * totalScale
                    if not (settings.macroAnchor and EAB.PlaceButtonText(macroFS, bf, settings.macroAnchor, mcOX, mcOY)) then
                        macroFS:ClearAllPoints()
                        macroFS:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", 1 + mcOX, 4 + mcOY)
                        macroFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1 + mcOX, 4 + mcOY)
                        macroFS:SetJustifyH("CENTER")
                    end
                end
                end -- close alwaysShowButtons else
            else
                bf:Hide()
            end
        end

        if fvPrev or capsPrev or self._abChrome then
            local abc = self._abChrome
            if not abc then abc = {}; self._abChrome = abc end
            local oneLine = (isVertical and gridCols or gridRows) == 1 and spacing <= 2
            ns.AB_PaintBarChrome(abc, self, gridStartX, self._gridStartY, gridW, gridH,
                scaledBtnW, fvPrev, capsPrev, gridRows > 1, isVertical,
                oneLine and (isVertical and gridRows or gridCols) or 0,
                (isVertical and scaledBtnH or scaledBtnW) + scaledPad, 0, 0, totalScale,
                info.key, capsL, capsR)
        end

        -- The paging arrows' stand-in (built on first use): the live arrow art
        -- and page number, over the bar's chrome.
        local pg = self._pagingPreview
        if pgArrow then
            if not pg then
                pg = CreateFrame("Frame", nil, self)
                pg.up = pg:CreateTexture(nil, "ARTWORK")
                pg.up:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Up")
                pg.down = pg:CreateTexture(nil, "ARTWORK")
                pg.down:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Up")
                pg.text = pg:CreateFontString(nil, "OVERLAY")
                pg.text:SetTextColor(1, 1, 1, 0.9)
                self._pagingPreview = pg
            end
            pg:SetFrameLevel(self:GetFrameLevel() + 20)
            pg.text:SetFont(STANDARD_TEXT_FONT, pgText, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
            pg.text:SetText(tostring(ns.EAB_VTABLE.GetActionBarPage() or 1))
            pg.up:SetSize(pgArrow, pgArrow)
            pg.down:SetSize(pgArrow, pgArrow)
            pg:ClearAllPoints()
            pg.up:ClearAllPoints()
            pg.down:ClearAllPoints()
            pg.text:ClearAllPoints()
            pg.text:SetPoint("CENTER", pg, "CENTER", 0, 0)
            if isVertical then
                pg:SetSize(pgArrow * 2 + pgText * 2 + pgGap * 2, pgArrow)
                local cx = Snap(gridStartX + gridW / 2)
                if pgRight then
                    pg:SetPoint("TOP", self, "TOPLEFT", cx, self._gridStartY - gridH - pgOff)
                else
                    pg:SetPoint("BOTTOM", self, "TOPLEFT", cx, self._gridStartY + pgOff)
                end
                pg.down:SetPoint("LEFT", pg, "LEFT", 0, 0)
                pg.up:SetPoint("RIGHT", pg, "RIGHT", 0, 0)
            else
                pg:SetSize(pgArrow, pgArrow * 2 + pgText + pgGap * 2)
                local cy = Snap(self._gridStartY - gridH / 2)
                if pgRight then
                    pg:SetPoint("LEFT", self, "TOPLEFT", gridStartX + gridW + pgOff, cy)
                else
                    pg:SetPoint("RIGHT", self, "TOPLEFT", gridStartX - pgOff, cy)
                end
                pg.up:SetPoint("TOP", pg, "TOP", 0, 0)
                pg.down:SetPoint("BOTTOM", pg, "BOTTOM", 0, 0)
            end
            pg:Show()
        elseif pg then
            pg:Hide()
        end

        if settings.bgEnabled then
            local bgC = settings.bgColor or { r = 0, g = 0, b = 0, a = 0.5 }
            local bgAlpha = settings.bgOpacity ~= nil and settings.bgOpacity / 100 or bgC.a
            previewBG:SetColorTexture(bgC.r, bgC.g, bgC.b, bgAlpha)
            local rawPadding = settings.bgPadding
            local extraX = Snap((rawPadding ~= nil and rawPadding or (settings.bgPadX or 0)) * totalScale)
            local extraY = Snap((rawPadding ~= nil and rawPadding or (settings.bgPadY or 0)) * totalScale)
            -- Anchor to full grid bounds (not buttons) so multi-row backgrounds still cover a shorter last row.
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
                local bgPx = EllesmereUI.BorderPx(settings.bgBorderThicknessPx, borderSize, settings.bgBorderTexture)
                EllesmereUI.ApplyBorderStyle(previewBGBorder, borderSize,
                    bc.r, bc.g, bc.b, bc.a or 1, settings.bgBorderTexture or "solid",
                    settings.bgBorderOffsetX, settings.bgBorderOffsetY,
                    settings.bgBorderShiftX, settings.bgBorderShiftY,
                    "actionbars", thicknessKey, nil, bgPx)
            end
        else
            previewBG:Hide()
            if EllesmereUI.ApplyBorderStyle then
                EllesmereUI.ApplyBorderStyle(previewBGBorder, 0, 0, 0, 0, settings.bgBorderTexture or "solid")
            else
                previewBGBorder:Hide()
            end
        end

        -- Mouseover fade shows the real bar at full alpha on hover, so preview uses full alpha too, not the fade-out alpha.
        local barAlpha = settings.mouseoverEnabled and 1 or (settings.mouseoverAlpha or 1)
        self:SetAlpha(barAlpha)

        -- Refresh text overlay sizes (font/text may have changed)
        if self._textOverlays then
            for _, ov in ipairs(self._textOverlays) do
                if ov._resizeToText then ov._resizeToText() end
            end
        end
    end

    pf:Update()

    -- Return the actual computed height (converted to parent-space)
    optState.activePreview = pf
    EllesmereUI._contentHeaderPreview = pf
    return pf._wrapper:GetHeight()
end

-- Used by EUI_ActionBars_Options.lua
ns.ABO_BuildLivePreview = BuildLivePreview
