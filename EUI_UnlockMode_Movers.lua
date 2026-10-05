if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnlockMode_Movers.lua
--  CreateMover: the draggable mover built for each registered element.
--  Loaded after EUI_UnlockMode.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
EUI_NS.unlockParts = EUI_NS.unlockParts or {}
EUI_NS.unlockParts.Movers = function(UM)
local ns, EAB, floor, abs = EUI_NS, UM.EAB, UM.floor, UM.abs
local min, max, round, DeferMoverSync = UM.min, UM.max, UM.round, UM.DeferMoverSync
local FONT_PATH, MOVER_ALPHA, MOVER_HOVER, MOVER_DRAG = UM.FONT_PATH, UM.MOVER_ALPHA, UM.MOVER_HOVER, UM.MOVER_DRAG
local BAR_LOOKUP, ALL_BAR_ORDER, GetVisibilityOnly, registeredElements = UM.BAR_LOOKUP, UM.ALL_BAR_ORDER, UM.GetVisibilityOnly, UM.registeredElements
local registeredOrder, RebuildRegisteredOrder, movers, pendingPositions = UM.registeredOrder, UM.RebuildRegisteredOrder, UM.movers, UM.pendingPositions
local GetBarGrowDir, GetAnchorDB, GetAnchorInfo, SetAnchorInfo = UM.GetBarGrowDir, UM.GetAnchorDB, UM.GetAnchorInfo, UM.SetAnchorInfo
local ClearAnchorInfo, IsAnchored, MatchH, FadeOverlayForSelectElement = UM.ClearAnchorInfo, UM.IsAnchored, UM.MatchH, UM.FadeOverlayForSelectElement
local CancelPickMode, FlashRedBorder, RejectH, ReapplyAllAnchors = UM.CancelPickMode, UM.FlashRedBorder, UM.RejectH, UM.ReapplyAllAnchors
local LoadBarPosition, GetAccent, ClearSnapHighlight, ShowSnapHighlight = UM.LoadBarPosition, UM.GetAccent, UM.ClearSnapHighlight, UM.ShowSnapHighlight
local HideAllGuidesAndHighlight, ShowAlignmentGuides, SnapPosition, SelectMover = UM.HideAllGuidesAndHighlight, UM.ShowAlignmentGuides, UM.SnapPosition, UM.SelectMover
local DeselectMover, GetActionBarVisualSize, SortMoverFrameLevels = UM.DeselectMover, UM.GetActionBarVisualSize, UM.SortMoverFrameLevels

local _mouseHeld = false       -- true while left mouse button is held down anywhere

-- True while any part of a frame's rect reads secret: all of it when the frame
-- rides an engine aura container, its size alone when only one edge does (a
-- Blizzard Style unit frame's box around its aura stack). Nothing measures it then.
local function RectSecret(f)
    return issecretvalue and (issecretvalue(f:GetLeft()) or issecretvalue(f:GetTop())
        or issecretvalue(f:GetWidth()) or issecretvalue(f:GetHeight())) or false
end

local function CreateMover(barKey)
    local elem = registeredElements[barKey]
    local existing = movers[barKey]

    -- Skip elements that are intentionally hidden or currently anchored
    -- (keepMoverWhenAnchored elements keep a position-locked mover instead).
    if elem and ((elem.isHidden and elem.isHidden())
        or (elem.isAnchored and elem.isAnchored() and not elem.keepMoverWhenAnchored)) then
        if existing then existing:Hide() end
        return nil
    end

    if existing then return existing end

    local bar = UM.GetBarFrame(barKey)
    if not bar then return nil end

    local ar, ag, ab = GetAccent()
    local label = UM.GetBarLabel(barKey)
    local cogBtn  -- forward declaration; assigned later in CreateMover

    local mover = CreateFrame("Button", nil, UM.unlockFrame)
    -- Party Frames always render above Raid Frames in unlock mode
    local MOVER_LEVEL_BUMP = (barKey == "RF_PartyFrames") and 10 or 0
    local MOVER_BASE_LEVEL = UM.unlockFrame:GetFrameLevel() + 20 + MOVER_LEVEL_BUMP
    local MOVER_RAISED_LEVEL = MOVER_BASE_LEVEL + 5
    mover:SetFrameLevel(MOVER_BASE_LEVEL)
    mover._baseLevel = MOVER_BASE_LEVEL
    mover._raisedLevel = MOVER_RAISED_LEVEL
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:EnableMouse(true)
    mover:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then _mouseHeld = true end
    end)
    -- OnMouseUp is set later (after link buttons are created) to also handle link drag forwarding

    -- Background (matches cogwheel dark color at 75% opacity). Elements may
    -- override the base color via their moverBg definition field; the base is
    -- stored on the mover so snap-highlight and dark-overlay repaints keep it.
    local regElem = registeredElements[barKey]
    local bgTint = regElem and regElem.moverBg
    mover._bgR = bgTint and bgTint.r or 0.075
    mover._bgG = bgTint and bgTint.g or 0.113
    mover._bgB = bgTint and bgTint.b or 0.141
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if UM.darkOverlaysEnabled then
        bg:SetColorTexture(mover._bgR, mover._bgG, mover._bgB, 0.95)
    else
        bg:SetColorTexture(0, 0, 0, 0)
    end
    mover._bg = bg

    -- Pixel-perfect border (accent colored, uses shared MakeBorder)
    local brd = EllesmereUI.MakeBorder(mover, ar, ag, ab, 0.6)
    mover._brd = brd

    -- Label -- on a higher-level frame so it renders above the border
    local labelFrame = CreateFrame("Frame", nil, mover)
    labelFrame:SetAllPoints()
    labelFrame:SetClipsChildren(true)
    labelFrame:SetFrameLevel(mover:GetFrameLevel() + 3)
    local nameFS = labelFrame:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(nameFS, true)
    nameFS:SetFont(FONT_PATH, 10 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
    nameFS:SetText(EllesmereUI.L(label))
    nameFS:SetTextColor(1, 1, 1, 0.75)
    nameFS:SetWordWrap(false)
    nameFS:SetNonSpaceWrap(false)
    nameFS:SetPoint("CENTER", mover, "CENTER")
    mover._label = nameFS
    if not UM.darkOverlaysEnabled then nameFS:Hide() end

    -- Optional dimmed subtitle under the label (element definition field)
    if regElem and regElem.subtitle then
        local subFS = labelFrame:CreateFontString(nil, "OVERLAY")
        EllesmereUI.PrimeFontShadow(subFS, true)
        subFS:SetFont(FONT_PATH, 8 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
        subFS:SetText(EllesmereUI.L(regElem.subtitle))
        subFS:SetTextColor(1, 1, 1, 0.40)
        subFS:SetJustifyH("CENTER")
        subFS:SetWordWrap(true)
        subFS:SetNonSpaceWrap(false)
        subFS:SetPoint("TOP", nameFS, "BOTTOM", 0, -3)
        subFS:SetPoint("LEFT", labelFrame, "LEFT", 8, 0)
        subFS:SetPoint("RIGHT", labelFrame, "RIGHT", -8, 0)
        mover._subtitle = subFS
        if not UM.darkOverlaysEnabled then subFS:Hide() end
    end

    -- Coordinate readout (shows during drag and selection, top-left of mover)
    local coordFS = labelFrame:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(coordFS, true)
    coordFS:SetFont(FONT_PATH, 9 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
    coordFS:SetTextColor(1, 1, 1, 0.7)
    coordFS:SetPoint("TOPLEFT", mover, "TOPLEFT", 3, -2)
    coordFS:Hide()
    mover._coordFS = coordFS

    ---------------------------------------------------------------------------
    --  W Match | H Match | Anchor | Grow  (centered below the name)
    --  Also: "Anchored" text and pick-mode instruction text
    ---------------------------------------------------------------------------
    -- Action link text labels
    local WM_TEXT = "W Match"
    local HM_TEXT = "H Match"
    local AT_TEXT = "Anchor"
    local GD_TEXT = "Grow"

    -- Clickable buttons for each action (parented to labelFrame for correct level)
    local wmBtn = CreateFrame("Button", nil, labelFrame)
    wmBtn:SetFrameLevel(labelFrame:GetFrameLevel() + 2)
    wmBtn:RegisterForClicks("LeftButtonUp")
    wmBtn:EnableMouse(true)
    wmBtn:Hide()

    local hmBtn = CreateFrame("Button", nil, labelFrame)
    hmBtn:SetFrameLevel(labelFrame:GetFrameLevel() + 2)
    hmBtn:RegisterForClicks("LeftButtonUp")
    hmBtn:EnableMouse(true)
    hmBtn:Hide()

    local atBtn = CreateFrame("Button", nil, labelFrame)
    atBtn:SetFrameLevel(labelFrame:GetFrameLevel() + 2)
    atBtn:RegisterForClicks("LeftButtonUp")
    atBtn:EnableMouse(true)
    atBtn:Hide()

    local gdBtn = CreateFrame("Button", nil, labelFrame)
    gdBtn:SetFrameLevel(labelFrame:GetFrameLevel() + 2)
    gdBtn:RegisterForClicks("LeftButtonUp")
    gdBtn:EnableMouse(true)
    gdBtn:Hide()

    -- Store link buttons on mover so OnLeave can check if any are hovered
    mover._linkBtns = { wmBtn, hmBtn, atBtn, gdBtn }

    -- Font strings inside each button (accent colored, drop shadow)
    local wmFS = wmBtn:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(wmFS, true)
    wmFS:SetFont(FONT_PATH, 9, "")
    wmFS:SetTextColor(ar, ag, ab, 0.85)
    wmFS:SetText(EllesmereUI.L(WM_TEXT))
    wmFS:SetPoint("CENTER")

    local hmFS = hmBtn:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(hmFS, true)
    hmFS:SetFont(FONT_PATH, 9, "")
    hmFS:SetTextColor(ar, ag, ab, 0.85)
    hmFS:SetText(EllesmereUI.L(HM_TEXT))
    hmFS:SetPoint("CENTER")

    local atFS = atBtn:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(atFS, true)
    atFS:SetFont(FONT_PATH, 9, "")
    atFS:SetTextColor(ar, ag, ab, 0.85)
    atFS:SetText(EllesmereUI.L(AT_TEXT))
    atFS:SetPoint("CENTER")

    local gdFS = gdBtn:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(gdFS, true)
    gdFS:SetFont(FONT_PATH, 9, "")
    gdFS:SetTextColor(ar, ag, ab, 0.85)
    gdFS:SetText(EllesmereUI.L(GD_TEXT))
    gdFS:SetPoint("CENTER")

    -- 1px pixel-perfect divider lines between action links
    local PP = EllesmereUI and EllesmereUI.PP
    local divPx = PP and PP.mult or 1

    local div1 = labelFrame:CreateTexture(nil, "OVERLAY")
    div1:SetColorTexture(1, 1, 1, 0.25)
    div1:SetWidth(divPx)
    div1:SetHeight(10)
    if div1.SetSnapToPixelGrid then div1:SetSnapToPixelGrid(false); div1:SetTexelSnappingBias(0) end
    div1:Hide()

    local div2 = labelFrame:CreateTexture(nil, "OVERLAY")
    div2:SetColorTexture(1, 1, 1, 0.25)
    div2:SetWidth(divPx)
    div2:SetHeight(10)
    if div2.SetSnapToPixelGrid then div2:SetSnapToPixelGrid(false); div2:SetTexelSnappingBias(0) end
    div2:Hide()

    local div3 = labelFrame:CreateTexture(nil, "OVERLAY")
    div3:SetColorTexture(1, 1, 1, 0.25)
    div3:SetWidth(divPx)
    div3:SetHeight(10)
    if div3.SetSnapToPixelGrid then div3:SetSnapToPixelGrid(false); div3:SetTexelSnappingBias(0) end
    div3:Hide()

    -- Determine if this element supports resizing
    local canResize = not (elem and elem.noResize)
    -- Determine if this element can be anchored to other elements (an element
    -- that places itself, ownsPosition, takes no link either)
    local canAnchorTo = not (elem and (elem.noAnchorTo or elem.ownsPosition))

    -- Grow direction: action bars 1-8 and CDM bars (both horizontal and vertical)
    local _GROW_KEYS = {
        MainBar = true, Bar2 = true, Bar3 = true, Bar4 = true,
        Bar5 = true, Bar6 = true, Bar7 = true, Bar8 = true,
        StanceBar = true, PetBar = true,
        ERB_TotemBar = true,   -- totem bar: align active icons left/right/center
        EABR_Reminders = true, -- aura buff reminders: align icons left/right/center
    }
    local canGrow = _GROW_KEYS[barKey] or barKey:sub(1, 4) == "CDM_" or barKey:sub(1, 4) == "PAB_"

    -- Match-source capability: width/height MATCH buttons may appear even when
    -- drag/manual resize is disabled (noResize), if the element opts in via
    -- allowMatchSource (e.g. tracking bars sized via their own sliders can still size-MATCH another element).
    local canMatchSource = canResize or (elem and elem.allowMatchSource) or false

    -- Single source of truth for which action-row link buttons are active, in
    -- left-to-right order. The layout, the hover show/hide, and the hover-box
    -- width calc all read this so they never drift apart. `fb` = fallback width.
    local function ActiveLinks()
        local t = {}
        if canMatchSource then
            t[#t + 1] = { btn = wmBtn, fs = wmFS, fb = 50 }
            t[#t + 1] = { btn = hmBtn, fs = hmFS, fb = 55 }
        end
        if canAnchorTo and not ns.IsMoverPosLocked(barKey) then
            t[#t + 1] = { btn = atBtn, fs = atFS, fb = 45 }
        end
        if canGrow then
            t[#t + 1] = { btn = gdBtn, fs = gdFS, fb = 30 }
        end
        return t
    end

    -- Layout: position action link buttons + dividers centered below name.
    -- Unified dynamic layout: lay out exactly the buttons ActiveLinks() reports,
    -- with one divider between each adjacent pair. This renders the existing
    -- cases pixel-identically and naturally handles match-buttons-without-resize.
    local function LayoutActionRow()
        local gap = 8
        local items = ActiveLinks()
        if #items == 0 then return end
        local divs = { div1, div2, div3 }
        local totalW = 0
        for i, it in ipairs(items) do
            it.w = it.fs:GetStringWidth() or it.fb
            totalW = totalW + it.w
            if i < #items then totalW = totalW + gap + 1 + gap end
        end
        local x = -totalW / 2
        for i, it in ipairs(items) do
            it.btn:SetSize(it.w + 4, 14); it.btn:ClearAllPoints()
            it.btn:SetPoint("TOP", nameFS, "BOTTOM", x + it.w / 2, -4)
            x = x + it.w
            if i < #items and divs[i] then
                divs[i]:ClearAllPoints()
                divs[i]:SetPoint("TOP", nameFS, "BOTTOM", x + gap + 0.5, -6)
                x = x + gap + 1 + gap
            end
        end
    end
    -- For MatchH.CommitMatchExtra (file scope): the matched label changes width.
    mover._layoutActionRow = LayoutActionRow

    -- Anchored indicator: name label turns orange when anchored
    -- No separate font string needed
    local anchoredFS = nil
    mover._anchoredFS = nil

    -- Pick mode instruction text (shown when in pick mode, replaces all other text)
    local pickFS = labelFrame:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(pickFS, true)
    pickFS:SetFont(FONT_PATH, 10 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
    pickFS:SetTextColor(1, 1, 1, 0.85)
    pickFS:SetPoint("CENTER", mover, "CENTER")
    pickFS:SetJustifyH("CENTER")
    pickFS:SetWordWrap(true)
    pickFS:Hide()
    mover._pickFS = pickFS

    ---------------------------------------------------------------------------
    --  Hover animation state
    --  0 = idle (name centered, action row hidden)
    --  1 = hovered (name shifted up, action row visible + faded in)
    ---------------------------------------------------------------------------
    local LABEL_Y_NORMAL  = 0
    local LABEL_Y_SHIFTED = 7
    local ANIM_DUR        = 0.15
    local hoverState      = 0
    local hoverTarget     = 0
    local isAnchored      = false
    local baseW, baseH    = 0, 0   -- real element size (set by Sync)
    local moverCX, moverCY = 0, 0  -- stored center in UIParent-TOPLEFT coords (set by Sync)
    mover._setCenterXY = function(cx, cy) moverCX = cx; moverCY = cy end
    mover._getCenterXY = function() return moverCX, moverCY end

    -- Re-anchor the mover directly to the bar frame so both share the exact same
    -- screen position with zero coordinate math (pixel-perfect). The bar's CENTER
    -- anchor is already applied synchronously by RecenterBarAnchor before this
    -- fires, so just update mover size and re-attach to bar TOPLEFT. Deferred one frame so the bar's layout has flushed after a move/resize.
    function mover:ReanchorToBar()
        local bk = self._barKey
        local self2 = self
        C_Timer.After(0, function()
            if self2._dragging then return end
            local b = UM.GetBarFrame(bk)
            if not b then return end
            -- A bar riding an engine aura container reports a secret rect
            -- outside unlock mode (the follow provider is inert inside it, so
            -- the bar rests plain there): nothing to attach to yet.
            if RectSecret(b) then return end
            local s = b:GetEffectiveScale()
            local uiS = UIParent:GetEffectiveScale()
            local elemScale = s / uiS
            -- Update size from bar (+ any below-frame extra, e.g. boss castbar).
            local elem = registeredElements[bk]
            local extra = (elem and elem.getBottomExtra and (elem.getBottomExtra(bk) or 0) or 0) * elemScale
            -- Visual insets (optional, e.g. a Blizzard Style unit frame whose stock
            -- box carries transparent padding round its art): the mover outlines
            -- the rect inside them. Left, right, top, bottom in the bar's units.
            local il, ir, it, ib = 0, 0, 0, 0
            if elem and elem.getInsets then
                local l, r, t, bt = elem.getInsets(bk)
                if l then il, ir, it, ib = l * elemScale, (r or 0) * elemScale, (t or 0) * elemScale, (bt or 0) * elemScale end
            end
            local w = (b:GetWidth() or 50) * elemScale - il - ir
            local h = (b:GetHeight() or 50) * elemScale + extra - it - ib
            if w > 10 then baseW = w end
            if h > 10 then baseH = h end
            self2:SetSize(baseW, baseH)
            -- Recompute moverCX/moverCY from bar's current center. Shift the
            -- stored center DOWN by half the extra so the box stays top-pinned
            -- to the frame and grows downward over the extra region; insets
            -- shift it by half their difference.
            local bcx, bcy = b:GetCenter()
            if bcx and bcy then
                moverCX = bcx * elemScale + (il - ir) * 0.5
                moverCY = bcy * elemScale - UIParent:GetHeight() - extra * 0.5 + (ib - it) * 0.5
            end
            -- Anchor mover to bar TOPLEFT for pixel-perfect overlay
            EllesmereUI._unlockAttachMover(self2, b, bk, il, it)
        end)
    end

    -- Refresh link button text/color based on active matches
    local function RefreshLinkStates()
        local wm = MatchH.GetWidthMatchInfo(barKey)
        local hm = MatchH.GetHeightMatchInfo(barKey)
        local ai = GetAnchorInfo(barKey)
        -- For linkedDimensions elements, one active match blocks the other
        local wmBlocked = elem and elem.linkedDimensions and hm ~= nil
        local hmBlocked = elem and elem.linkedDimensions and wm ~= nil
        if wm then
            wmFS:SetText(EllesmereUI.L("W Matched"))
            wmFS:SetTextColor(1, 0.7, 0.3, 0.85)
            -- A match's Extra Width rides the label: "W Matched +5".
            local wx = EllesmereUI.GetMatchExtra("w", barKey)
            if wx then wmFS:SetText(EllesmereUI.L("W Matched") .. (wx > 0 and " +" or " ") .. wx) end
        elseif wmBlocked then
            wmFS:SetText(EllesmereUI.L("W Match"))
            wmFS:SetTextColor(ar, ag, ab, 0.35)
        else
            wmFS:SetText(EllesmereUI.L("W Match"))
            wmFS:SetTextColor(ar, ag, ab, 0.85)
        end
        if hm then
            hmFS:SetText(EllesmereUI.L("H Matched"))
            hmFS:SetTextColor(1, 0.7, 0.3, 0.85)
            local hx = EllesmereUI.GetMatchExtra("h", barKey)
            if hx then hmFS:SetText(EllesmereUI.L("H Matched") .. (hx > 0 and " +" or " ") .. hx) end
        elseif hmBlocked then
            hmFS:SetText(EllesmereUI.L("H Match"))
            hmFS:SetTextColor(ar, ag, ab, 0.35)
        else
            hmFS:SetText(EllesmereUI.L("H Match"))
            hmFS:SetTextColor(ar, ag, ab, 0.85)
        end
        if ai then
            atFS:SetText(EllesmereUI.L("Anchored"))
            atFS:SetTextColor(1, 0.7, 0.3, 0.85)
        else
            atFS:SetText(EllesmereUI.L("Anchor"))
            atFS:SetTextColor(ar, ag, ab, 0.85)
        end
        gdFS:SetText(EllesmereUI.L("Grow"))
        gdFS:SetTextColor(1, 0.7, 0.3, 0.85)
    end

    -- Update the name label color based on anchor state
    local function RefreshAnchoredIdle()
        -- A link on an element that places itself (ownsPosition) is inert.
        local ai = not (elem and elem.ownsPosition) and GetAnchorInfo(barKey) or nil
        isAnchored = ai ~= nil or ns.IsMoverPosLocked(barKey)
        nameFS:SetText(EllesmereUI.L(label))
        if isAnchored then
            nameFS:SetTextColor(1, 0.7, 0.3, 0.85)
        else
            nameFS:SetTextColor(1, 1, 1, 0.75)
        end
    end

    local animFrame = CreateFrame("Frame", nil, labelFrame)

    local function ApplyHoverState(s)
        -- Name shifts up on hover to make room for action links below
        local labelShift = LABEL_Y_NORMAL + s * (LABEL_Y_SHIFTED - LABEL_Y_NORMAL)
        labelShift = labelShift + 2 - s
        -- Update the existing anchor offset instead of ClearAllPoints to avoid
        -- layout thrash that causes the label to jitter during animation.
        nameFS:SetPoint("CENTER", mover, "CENTER", 0, labelShift)
        -- Smoothly interpolate text width from constrained to unconstrained
        -- to avoid a hard snap when the animation starts.
        if baseW > 0 then
            local constrainedW = baseW
            local targetW = mover._cachedNameStrW or constrainedW
            local curTextW = constrainedW + (targetW - constrainedW) * s
            nameFS:SetWidth(curTextW)
        end

        -- Action links: show on hover. Visibility is built from the same
        -- ActiveLinks() list as the layout, so match buttons appear for
        -- allowMatchSource elements and the dividers always match the buttons.
        local links = ActiveLinks()
        local activeBtn = {}
        for _, it in ipairs(links) do activeBtn[it.btn] = true end
        local function _linkVis(btn)
            if activeBtn[btn] then
                btn:SetAlpha(s)
                if s > 0.01 then btn:Show() else btn:Hide() end
            else
                btn:Hide()
            end
        end
        _linkVis(wmBtn); _linkVis(hmBtn); _linkVis(atBtn); _linkVis(gdBtn)
        local nDivs = #links > 0 and (#links - 1) or 0
        local divsV = { div1, div2, div3 }
        for i = 1, 3 do
            if i <= nDivs then
                divsV[i]:SetAlpha(s)
                if s > 0.01 then divsV[i]:Show() else divsV[i]:Hide() end
            else
                divsV[i]:Hide()
            end
        end

        -- Cog: same show/hide as links
        if cogBtn then
            cogBtn:SetAlpha(s)
            if s > 0.01 then cogBtn:Show() else cogBtn:Hide() end
        end

        -- Animate-expand the mover only on hover (idle = raw element size)
        if baseW > 0 and baseH > 0 then
            local PAD = 5
            -- Use cached hover dimensions (computed once in ShowOverlayText)
            -- to avoid calling GetStringWidth every frame during animation.
            local hoverW = mover._cachedHoverW or baseW
            local hoverH = mover._cachedHoverH or baseH
            local curW = baseW + (hoverW - baseW) * s
            local curH = baseH + (hoverH - baseH) * s
            -- Expand symmetrically from the mover's stored center (set by Sync).
            -- This avoids reading GetLeft/GetTop from the bar frame, which can
            -- shift after a resize and cause the mover to teleport.
            local hasCenterXY = (moverCX ~= 0 or moverCY ~= 0)
            if hasCenterXY then
                local tx = moverCX - curW * 0.5
                local ty = moverCY + curH * 0.5
                mover:ClearAllPoints()
                mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", tx, ty)
            else
                -- Fallback: Sync hasn't run yet, read from bar frame
                local bk2 = mover._barKey
                local b2 = UM.GetBarFrame(bk2)
                if b2 then
                    local s2 = b2:GetEffectiveScale()
                    local uiS2 = UIParent:GetEffectiveScale()
                    local bL2 = b2:GetLeft()
                    local bT2 = b2:GetTop()
                    if bL2 and bT2 then
                        local tx = bL2 * s2 / uiS2 - (curW - baseW) * 0.5
                        local ty = bT2 * s2 / uiS2 - UIParent:GetHeight() + (curH - baseH) * 0.5
                        mover:ClearAllPoints()
                        mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", tx, ty)
                    end
                end
            end
            mover:SetSize(curW, curH)
        end
    end

    local function AnimateHoverTo(target)
        if target == hoverTarget and not animFrame:GetScript("OnUpdate")
           and math.abs(hoverState - target) < 0.01 then return end
        hoverTarget = target
        animFrame:SetScript("OnUpdate", function(self, dt)
            local dir = hoverTarget > hoverState and 1 or -1
            hoverState = hoverState + dir * (dt / ANIM_DUR)
            if (dir == 1 and hoverState >= hoverTarget) or (dir == -1 and hoverState <= hoverTarget) then
                hoverState = hoverTarget
                self:SetScript("OnUpdate", nil)
                -- Snap back to bar anchor when fully collapsed
                if hoverState == 0 and mover.ReanchorToBar then
                    mover:ReanchorToBar()
                end
                -- Show coordinates when fully expanded
                if hoverState == 1 and mover._coordFS then
                    if mover.UpdateCoordText then mover:UpdateCoordText() end
                end
            end
            ApplyHoverState(hoverState)
        end)
    end

    -- Show/hide overlay text helpers
    local function ShowOverlayText()
        mover._hoverConfirmed = true
        if UM.darkOverlaysEnabled then
            nameFS:SetAlpha(1); nameFS:Show()
        end
        RefreshAnchoredIdle()
        -- Cache hover dimensions once so ApplyHoverState avoids per-frame GetStringWidth
        if baseW > 0 and baseH > 0 then
            local PAD = 5
            local nameW = nameFS:GetStringWidth() or 0
            local nameH = nameFS:GetStringHeight() or 10
            local rowW = 0
            do
                local links = ActiveLinks()
                local gap = 8
                for i, it in ipairs(links) do
                    rowW = rowW + (it.fs:GetStringWidth() or it.fb)
                    if i < #links then rowW = rowW + gap + 1 + gap end
                end
            end
            local contentW = math.max(nameW, rowW)
            local contentH = nameH + 4 + 14
            mover._cachedHoverW = math.max(baseW, contentW + PAD * 2 + 6)
            mover._cachedHoverH = math.max(baseH, contentH + PAD * 2 + 2)
        end
        -- Cache unconstrained name width for smooth text width interpolation
        local nsw = nameFS:GetStringWidth() or baseW
        mover._cachedNameStrW = math.max(nsw + 4, baseW)
        -- Skip RefreshLinkStates if a link button is currently hovered (would reset its white color)
        local linkHovered = false
        if mover._linkBtns then
            for _, b in ipairs(mover._linkBtns) do
                if b:IsMouseOver() then linkHovered = true; break end
            end
        end
        if not linkHovered then RefreshLinkStates() end
        LayoutActionRow()
        AnimateHoverTo(1)
        pickFS:Hide()
    end

    local function HideOverlayText()
        mover._hoverConfirmed = false
        -- Hide coordinates when collapsing (unless coords-always-on)
        if mover._coordFS and not UM.coordsEnabled then mover._coordFS:Hide() end
        AnimateHoverTo(0)
    end

    local function ShowPickText(text)
        wmBtn:Hide(); hmBtn:Hide(); atBtn:Hide(); gdBtn:Hide()
        div1:Hide(); div2:Hide(); div3:Hide()
        hoverState = 0; hoverTarget = 0
        animFrame:SetScript("OnUpdate", nil)
        nameFS:ClearAllPoints()
        nameFS:SetPoint("CENTER", mover, "CENTER", 0, LABEL_Y_NORMAL)
        nameFS:SetAlpha(0)
        pickFS:SetText(EllesmereUI.L(text))
        pickFS:Show()
    end

    local function HidePickText()
        pickFS:Hide()
        if UM.darkOverlaysEnabled then
            nameFS:SetAlpha(1)
        end
    end

    mover._showOverlayText = ShowOverlayText
    mover._hideOverlayText = HideOverlayText
    mover._showPickText = ShowPickText
    mover._hidePickText = HidePickText

    -- Snap-collapse: instantly reset hover state without animation.
    -- Used by DoClose to guarantee no mover is stuck expanded on re-enter.
    mover._forceCollapse = function()
        hoverState = 0
        hoverTarget = 0
        mover._hoverConfirmed = false
        if mover._coordFS and not UM.coordsEnabled then mover._coordFS:Hide() end
        animFrame:SetScript("OnUpdate", nil)
        ApplyHoverState(0)
        if mover.ReanchorToBar then mover:ReanchorToBar() end
    end

    -- Refresh the anchored text (called after anchor changes)
    function mover:RefreshAnchoredText()
        RefreshAnchoredIdle()
        RefreshLinkStates()
        -- If not hovered, apply idle state to show/hide anchored text
        if not self:IsMouseOver() then
            ApplyHoverState(hoverState)
        end
    end

    -- Hover effects for action buttons (brighten to white on hover, keep mover highlighted)
    local function BtnEnter(btn, fs, matchType)
        EllesmereUI.HideWidgetTooltip()
        -- Check if this button is blocked by linkedDimensions
        local isBlocked = false
        if elem and elem.linkedDimensions then
            if matchType == "width" and MatchH.GetHeightMatchInfo(barKey) ~= nil and MatchH.GetWidthMatchInfo(barKey) == nil then
                isBlocked = true
            elseif matchType == "height" and MatchH.GetWidthMatchInfo(barKey) ~= nil and MatchH.GetHeightMatchInfo(barKey) == nil then
                isBlocked = true
            end
        end
        if isBlocked then
            EllesmereUI.ShowWidgetTooltip(btn, "This element doesn't support both Height and Width matching")
            return
        end
        fs:SetTextColor(1, 1, 1, 1)
        mover:SetFrameLevel(mover._raisedLevel + 100)
        mover._brd:SetColor(1, 1, 1, 0.9)
        -- Show tooltip for active matches
        local tipText
        if matchType == "width" then
            local target = MatchH.GetWidthMatchInfo(barKey)
            if target then
                tipText = UM.GetBarLabel(target) or target
            end
        elseif matchType == "height" then
            local target = MatchH.GetHeightMatchInfo(barKey)
            if target then
                tipText = UM.GetBarLabel(target) or target
            end
        elseif matchType == "anchor" then
            local info = GetAnchorInfo(barKey)
            if info then
                tipText = UM.GetBarLabel(info.target) or info.target
            end
        elseif matchType == "grow" then
            local gd = GetBarGrowDir(barKey)
            if gd then
                tipText = "Grow " .. gd:sub(1,1) .. gd:sub(2):lower()
            end
        end
        if tipText then
            EllesmereUI.ShowWidgetTooltip(btn, tipText)
        end
    end
    local function BtnLeave(btn, fs, matchType)
        EllesmereUI.HideWidgetTooltip()
        -- Restore correct color based on active/blocked state
        local isActive = false
        local isBlocked = false
        if matchType == "width" then
            isActive = MatchH.GetWidthMatchInfo(barKey) ~= nil
            isBlocked = elem and elem.linkedDimensions and not isActive and MatchH.GetHeightMatchInfo(barKey) ~= nil
        elseif matchType == "height" then
            isActive = MatchH.GetHeightMatchInfo(barKey) ~= nil
            isBlocked = elem and elem.linkedDimensions and not isActive and MatchH.GetWidthMatchInfo(barKey) ~= nil
        elseif matchType == "anchor" then
            isActive = GetAnchorInfo(barKey) ~= nil
        elseif matchType == "grow" then
            isActive = true
        end
        if isActive then
            fs:SetTextColor(1, 0.7, 0.3, 0.85)
        elseif isBlocked then
            fs:SetTextColor(ar, ag, ab, 0.35)
        else
            fs:SetTextColor(ar, ag, ab, 0.85)
        end
        -- Restore frame level/border only -- mover OnLeave owns the collapse
        C_Timer.After(0.05, function()
            if not mover:IsMouseOver() then
                local overChild = mover._cogBtn and mover._cogBtn:IsMouseOver()
                if not overChild and mover._linkBtns then
                    for _, b in ipairs(mover._linkBtns) do
                        if b:IsMouseOver() then overChild = true; break end
                    end
                end
                if not overChild then
                    mover:SetFrameLevel(mover._baseLevel)
                    if mover._cogBtn then mover._cogBtn:SetFrameLevel(mover._baseLevel + 10) end
                    mover._brd:SetColor(ar, ag, ab, 0.6)
                end
            end
        end)
    end
    wmBtn:SetScript("OnEnter", function(self) BtnEnter(self, wmFS, "width") end)
    wmBtn:SetScript("OnLeave", function(self) BtnLeave(self, wmFS, "width") end)
    hmBtn:SetScript("OnEnter", function(self) BtnEnter(self, hmFS, "height") end)
    hmBtn:SetScript("OnLeave", function(self) BtnLeave(self, hmFS, "height") end)
    atBtn:SetScript("OnEnter", function(self) BtnEnter(self, atFS, "anchor") end)
    atBtn:SetScript("OnLeave", function(self) BtnLeave(self, atFS, "anchor") end)

    -- Forward drag from link buttons to the mover using OnMouseDown/Up instead of
    -- WoW's drag system: RegisterForDrag fires OnDragStop as soon as the button
    -- moves (happens when the hover row collapses on drag start), breaking the drag
    -- immediately; OnMouseDown/Up bypass that. To avoid collapsing the action row on a plain click, defer drag start until the cursor moves 3px.
    local linkDragPending = false
    local linkDragStartX, linkDragStartY = 0, 0

    local function LinkMouseDown(btn, button)
        if button ~= "LeftButton" then return end
        local sc = UIParent:GetEffectiveScale()
        linkDragStartX, linkDragStartY = GetCursorPosition()
        linkDragStartX = linkDragStartX / sc
        linkDragStartY = linkDragStartY / sc
        linkDragPending = true
        -- Poll for movement threshold before committing to drag
        mover:SetScript("OnUpdate", function(s)
            if not linkDragPending then return end
            local sc2 = UIParent:GetEffectiveScale()
            local mx, my = GetCursorPosition()
            mx = mx / sc2; my = my / sc2
            if abs(mx - linkDragStartX) > 1 or abs(my - linkDragStartY) > 1 then
                linkDragPending = false
                -- Now fire the real drag start
                local script = mover:GetScript("OnDragStart")
                if script then script(mover) end
            end
        end)
    end
    local function LinkMouseUp(btn, button)
        if button ~= "LeftButton" then return end
        linkDragPending = false
        if mover._dragging then
            local script = mover:GetScript("OnDragStop")
            if script then script(mover) end
        else
            -- No drag committed -- clear the pending OnUpdate
            mover:SetScript("OnUpdate", nil)
        end
    end
    wmBtn:SetScript("OnMouseDown", LinkMouseDown)
    wmBtn:SetScript("OnMouseUp",   LinkMouseUp)
    hmBtn:SetScript("OnMouseDown", LinkMouseDown)
    hmBtn:SetScript("OnMouseUp",   LinkMouseUp)
    atBtn:SetScript("OnMouseDown", LinkMouseDown)
    atBtn:SetScript("OnMouseUp",   LinkMouseUp)
    -- Also catch mouse release on the mover itself during a link-initiated drag.
    -- When the user drags far from the link button, the release happens over the
    -- mover (or nowhere), so the link button's OnMouseUp never fires.
    mover:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            _mouseHeld = false
            if linkDragPending or self._dragging then
                LinkMouseUp(self, button)
            end
        end
    end)

    -- Click handlers for Width Match / Height Match / Anchor To
    -- Toggle: if already matched, clear it; otherwise enter pick mode
    wmBtn:SetScript("OnClick", function()
        EllesmereUI.HideWidgetTooltip()
        -- Block if linkedDimensions and height match is already active
        if elem and elem.linkedDimensions and MatchH.GetHeightMatchInfo(barKey) ~= nil and MatchH.GetWidthMatchInfo(barKey) == nil then
            return
        end
        if MatchH.GetWidthMatchInfo(barKey) then
            MatchH.ClearWidthMatch(barKey)
            UM.hasChanges = true
            RefreshLinkStates()
            LayoutActionRow()
            return
        end
        -- Element-declared dynamic block on NEW matches (clearing above stays
        -- allowed): e.g. action bars in Blizzard Style, where EUI doesn't
        -- size the bars and a match would only write junk settings.
        if elem and elem.matchUnavailable then
            local why = elem.matchUnavailable(barKey)
            if why then
                EllesmereUI.ShowWidgetTooltip(wmBtn, why)
                return
            end
        end
        CancelPickMode()
        UM.pickMode = "widthMatch"
        UM.pickModeMover = mover
        ShowPickText("Click any element\nto match its width")
        FadeOverlayForSelectElement(true)
    end)

    hmBtn:SetScript("OnClick", function()
        EllesmereUI.HideWidgetTooltip()
        -- Block if linkedDimensions and width match is already active
        if elem and elem.linkedDimensions and MatchH.GetWidthMatchInfo(barKey) ~= nil and MatchH.GetHeightMatchInfo(barKey) == nil then
            return
        end
        if MatchH.GetHeightMatchInfo(barKey) then
            MatchH.ClearHeightMatch(barKey)
            UM.hasChanges = true
            RefreshLinkStates()
            LayoutActionRow()
            return
        end
        -- Element-declared dynamic block on NEW matches (see wmBtn above).
        if elem and elem.matchUnavailable then
            local why = elem.matchUnavailable(barKey)
            if why then
                EllesmereUI.ShowWidgetTooltip(hmBtn, why)
                return
            end
        end
        CancelPickMode()
        UM.pickMode = "heightMatch"
        UM.pickModeMover = mover
        ShowPickText("Click any element\nto match its height")
        FadeOverlayForSelectElement(true)
    end)

    atBtn:SetScript("OnClick", function()
        EllesmereUI.HideWidgetTooltip()
        if ns.IsMoverPosLocked(barKey) then return end
        if GetAnchorInfo(barKey) then
            ClearAnchorInfo(barKey)
            -- Capture current screen position so Save & Exit persists it.
            -- Without this, the old cdmBarPositions (from when anchored)
            -- would be used on /reload, snapping the bar to the wrong spot.
            local bar = UM.GetBarFrame(barKey)
            if bar then
                local pt, _, rpt, bx, by = bar:GetPoint(1)
                if pt then
                    pendingPositions[barKey] = {
                        point = pt, relPoint = rpt, x = bx, y = by,
                    }
                end
            end
            UM.hasChanges = true
            RefreshAnchoredIdle()
            RefreshLinkStates()
            LayoutActionRow()
            if movers[barKey] and movers[barKey].RefreshAnchoredText then
                movers[barKey]:RefreshAnchoredText()
            end
            return
        end
        CancelPickMode()
        UM.pickMode = "anchorTo"
        UM.pickModeMover = mover
        ShowPickText("Click any element\nto anchor to it")
        FadeOverlayForSelectElement(true)
    end)

    gdBtn:SetScript("OnClick", function()
        EllesmereUI.HideWidgetTooltip()
        -- Build and show the grow direction dropdown
        if not UM.growDropdownFrame then
            UM.growDropdownFrame = CreateFrame("Frame", nil, UM.unlockFrame)
            UM.growDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            UM.growDropdownFrame:SetFrameLevel(260)
            UM.growDropdownFrame:SetClampedToScreen(true)
            UM.growDropdownFrame:EnableMouse(true)
        end
        if not UM.growDropdownCatcher then
            UM.growDropdownCatcher = CreateFrame("Button", nil, UM.unlockFrame)
            UM.growDropdownCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            UM.growDropdownCatcher:SetFrameLevel(259)
            UM.growDropdownCatcher:SetAllPoints(UIParent)
            UM.growDropdownCatcher:RegisterForClicks("AnyUp")
            UM.growDropdownCatcher:SetScript("OnClick", function()
                UM.growDropdownFrame:Hide()
                UM.growDropdownCatcher:Hide()
            end)
        end
        -- Rebuild dropdown content
        for _, child in ipairs({UM.growDropdownFrame:GetChildren()}) do child:Hide(); child:SetParent(nil) end
        for _, tex in ipairs({UM.growDropdownFrame:GetRegions()}) do if tex.Hide then tex:Hide() end end

        local DD_ITEM_H = 24
        local DD_WIDTH = 160
        UM.growDropdownFrame:SetSize(DD_WIDTH, 10)
        UM.growDropdownFrame:ClearAllPoints()
        local scale = UIParent:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        curX = curX / scale
        curY = curY / scale - UIParent:GetHeight()
        UM.growDropdownFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", curX, curY)

        local ddBg = UM.growDropdownFrame:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
        EllesmereUI.MakeBorder(UM.growDropdownFrame, 1, 1, 1, 0.20)

        local ddY = -4
        local titleFS = UM.growDropdownFrame:CreateFontString(nil, "OVERLAY")
        EllesmereUI.PrimeFontShadow(titleFS, true)
        titleFS:SetFont(FONT_PATH, 10, "")
        titleFS:SetTextColor(1, 1, 1, 0.40)
        titleFS:SetJustifyH("LEFT")
        titleFS:SetPoint("TOPLEFT", UM.growDropdownFrame, "TOPLEFT", 10, ddY - 4)
        titleFS:SetText(EllesmereUI.L("Grow Direction"))
        ddY = ddY - 18
        local titleDiv = UM.growDropdownFrame:CreateTexture(nil, "ARTWORK")
        titleDiv:SetHeight(1)
        titleDiv:SetColorTexture(1, 1, 1, 0.10)
        titleDiv:SetPoint("TOPLEFT", UM.growDropdownFrame, "TOPLEFT", 1, ddY - 2)
        titleDiv:SetPoint("TOPRIGHT", UM.growDropdownFrame, "TOPRIGHT", -1, ddY - 2)
        ddY = ddY - 5

        -- Read orientation dynamically (not from closure) so the dropdown
        -- shows the correct options if orientation changed after mover creation.
        local isVert = false
        if barKey:sub(1, 4) == "CDM_" then
            local cdm3 = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
            local cb3 = cdm3 and cdm3.db and cdm3.db.profile and cdm3.db.profile.cdmBars
            if cb3 and cb3.bars then
                for _, b3 in ipairs(cb3.bars) do
                    if b3.key == barKey:sub(5) then isVert = b3.verticalOrientation == true; break end
                end
            end
        elseif barKey == "ERB_TotemBar" then
            if EllesmereUI.GetTotemGrowDir then
                local _, v3 = EllesmereUI.GetTotemGrowDir()
                isVert = v3
            end
        elseif barKey == "EABR_Reminders" then
            isVert = false   -- the reminder row is horizontal only
        elseif barKey:sub(1, 4) == "PAB_" then
            -- Player Aura Bars support vertical growth too -- read the bar's
            -- own current growDirection (same bridge the currentVal lookup below uses)
            -- to decide which pair of grow options this popup offers.
            local euf3 = EllesmereUI.Lite.GetAddon("EllesmereUIUnitFrames", true)
            local pabDir = (euf3 and euf3.GetGrowDirectionForBar and euf3:GetGrowDirectionForBar(barKey)) or "LEFT"
            isVert = (pabDir == "UP" or pabDir == "DOWN" or pabDir == "CENTER_VERTICAL")
        else
            local eab3 = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
            local s3 = eab3 and eab3.db and eab3.db.profile and eab3.db.profile.bars and eab3.db.profile.bars[barKey]
            if s3 then isVert = (s3.orientation == "vertical") end
        end
        local growDirs = {}
        if barKey:sub(1, 4) == "PAB_" then
            growDirs[#growDirs + 1] = { label = "Grow Centered Horizontal", val = "CENTER_HORIZONTAL" }
            growDirs[#growDirs + 1] = { label = "Grow Centered Vertical", val = "CENTER_VERTICAL" }
        else
            growDirs[#growDirs + 1] = { label = "Grow Centered", val = "CENTER" }
        end
        if isVert then
            growDirs[#growDirs + 1] = { label = "Grow Up",   val = "UP"   }
            growDirs[#growDirs + 1] = { label = "Grow Down", val = "DOWN" }
        else
            growDirs[#growDirs + 1] = { label = "Grow Left",  val = "LEFT"  }
            growDirs[#growDirs + 1] = { label = "Grow Right", val = "RIGHT" }
        end
        -- Read actual grow direction directly (GetBarGrowDir filters defaults)
        local currentVal = "CENTER"
        if barKey:sub(1, 4) == "CDM_" then
            local cdm4 = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
            local cb4 = cdm4 and cdm4.db and cdm4.db.profile and cdm4.db.profile.cdmBars
            if cb4 and cb4.bars then
                for _, b4 in ipairs(cb4.bars) do
                    if b4.key == barKey:sub(5) then currentVal = b4.growDirection or "CENTER"; break end
                end
            end
        elseif barKey == "ERB_TotemBar" then
            -- Clamped read: a direction left over from the other orientation is
            -- never stored back, so the menu must resolve it the same way the
            -- layout does or it would highlight an option that is not offered.
            currentVal = EllesmereUI.GetTotemGrowDir and EllesmereUI.GetTotemGrowDir()
                or (isVert and "DOWN" or "RIGHT")
        elseif barKey == "EABR_Reminders" then
            if EllesmereUI.GetAuraBuffGrowDir then currentVal = EllesmereUI.GetAuraBuffGrowDir() end
        elseif barKey:sub(1, 4) == "PAB_" then
            local euf4 = EllesmereUI.Lite.GetAddon("EllesmereUIUnitFrames", true)
            currentVal = (euf4 and euf4.GetGrowDirectionForBar and euf4:GetGrowDirectionForBar(barKey)) or "LEFT"
        else
            local eab4 = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
            local s4 = eab4 and eab4.db and eab4.db.profile and eab4.db.profile.bars
                       and eab4.db.profile.bars[barKey]
            if s4 then currentVal = (s4.growDirection or "up"):upper() end
        end

        for _, entry in ipairs(growDirs) do
            local isDisabled = false
            local isCurrent = (entry.val == currentVal)

            local item = CreateFrame("Button", nil, UM.growDropdownFrame)
            item:SetHeight(DD_ITEM_H)
            item:SetPoint("TOPLEFT", UM.growDropdownFrame, "TOPLEFT", 1, ddY)
            item:SetPoint("TOPRIGHT", UM.growDropdownFrame, "TOPRIGHT", -1, ddY)
            item:SetFrameLevel(UM.growDropdownFrame:GetFrameLevel() + 2)
            item:RegisterForClicks("AnyUp")
            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0)
            local lbl = item:CreateFontString(nil, "OVERLAY")
            EllesmereUI.PrimeFontShadow(lbl, true)
            lbl:SetFont(FONT_PATH, 11, "")
            lbl:SetJustifyH("LEFT")
            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
            lbl:SetText(EllesmereUI.L(entry.label))
            if isDisabled then
                lbl:SetTextColor(0.4, 0.4, 0.4, 0.5)
                local tipText = "Deselect a grow direction to return to centered"
                item:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(item, tipText)
                end)
                item:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                end)
            else
                local baseR, baseG, baseB, baseA = isCurrent and 1 or 0.75, isCurrent and 0.7 or 0.75, isCurrent and 0.3 or 0.75, isCurrent and 0.9 or 0.9
                lbl:SetTextColor(baseR, baseG, baseB, baseA)
                item:SetScript("OnEnter", function()
                    hl:SetColorTexture(1, 1, 1, 0.08)
                    lbl:SetTextColor(1, 1, 1, 1)
                end)
                item:SetScript("OnLeave", function()
                    hl:SetColorTexture(1, 1, 1, 0)
                    lbl:SetTextColor(baseR, baseG, baseB, baseA)
                end)
                local sideVal = entry.val
                item:SetScript("OnClick", function()
                    UM.growDropdownFrame:Hide()
                    UM.growDropdownCatcher:Hide()

                    -- If already on this direction, just close the popup
                    if sideVal == currentVal then return end

                    EllesmereUI._unlockSetGrowDirection(barKey, sideVal)
                    RefreshLinkStates()
                end)
            end
            ddY = ddY - DD_ITEM_H
        end

        UM.growDropdownFrame:SetHeight(-ddY + 4)
        UM.growDropdownFrame:Show()
        UM.growDropdownCatcher:Show()
    end)
    gdBtn:SetScript("OnEnter", function(self) BtnEnter(self, gdFS, "grow") end)
    gdBtn:SetScript("OnLeave", function(self) BtnLeave(self, gdFS, "grow") end)

    -- Helper: update coordinate readout from mover's current position
    function mover:UpdateCoordText()
        local fs = self._coordFS
        if not fs then return end
        local bk = self._barKey
        local PPi = EllesmereUI and EllesmereUI.PP
        local toPx = (PPi and PPi.ToPixels) or round
        -- STORED value first for unanchored CENTER/CENTER elements when not
        -- mid-drag: an odd-pixel-dimension frame's physical center legitimately
        -- sits on a half pixel (whole-pixel edges force it), so a live-derived
        -- readout can never echo the user's own typed value back (-368 reads as
        -- -367/-369 depending on rounding). The stored value is what the appliers
        -- round-trip, so it's the truth to display. Live geometry is only authoritative while dragging (store not yet updated).
        if not self._dragging then
            local ai = GetAnchorInfo(bk)
            if not (ai and ai.target) then
                local pos = pendingPositions[bk]
                if type(pos) ~= "table" or pos._anchored or not pos.point then
                    local elem = registeredElements[bk]
                    pos = elem and elem.loadPosition and elem.loadPosition(bk) or nil
                    if not pos then pos = LoadBarPosition(bk) end
                end
                if type(pos) == "table" and pos.point == "CENTER"
                   and (pos.relPoint or "CENTER") == "CENTER"
                   and pos.x and pos.y then
                    -- Parity-aware like the live branch below (odd dims store a half-pixel center).
                    local sb = UM.GetBarFrame(bk)
                    local c2pS = PPi and PPi.CenterToPixels
                    local px, py
                    if c2pS and sb then
                        px = c2pS(pos.x, sb:GetWidth(), sb:GetEffectiveScale())
                        py = c2pS(pos.y, sb:GetHeight(), sb:GetEffectiveScale())
                    else
                        px, py = toPx(pos.x), toPx(pos.y)
                    end
                    fs:SetText(format("%.0f, %.0f", px, py))
                    fs:Show()
                    return
                end
            end
        end
        -- Derive from the bar's LIVE geometry using the exact same formula and
        -- physical-pixel units as the cog X/Y boxes, so the overlay always agrees
        -- with the cog and updates immediately (no waiting for a commit).
        -- Parity-aware (CenterToPixels): odd-pixel dims center on a half pixel,
        -- which plain ToPixels reads back one high on this live path.
        local b = UM.GetBarFrame(bk)
        if b then
            local bL, bR = b:GetLeft(), b:GetRight()
            local bT, bB = b:GetTop(), b:GetBottom()
            if bL and bR and bT and bB then
                local ratio = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                local sw = UIParent:GetWidth()
                local sh = UIParent:GetHeight()
                local liveCX = ((bL + bR) * 0.5 * ratio) - sw * 0.5
                local liveCY = ((bT + bB) * 0.5 * ratio) - sh * 0.5
                local c2p = PPi and PPi.CenterToPixels
                fs:SetText(format("%.0f, %.0f",
                    c2p and c2p(liveCX, b:GetWidth(), b:GetEffectiveScale()) or toPx(liveCX),
                    c2p and c2p(liveCY, b:GetHeight(), b:GetEffectiveScale()) or toPx(liveCY)))
                fs:Show()
                return
            end
        end
        -- Fallback (frameless elements): saved CENTER position, same pixel units.
        local elem = registeredElements[bk]
        local pos = elem and elem.loadPosition and elem.loadPosition(bk)
        if not pos then
            pos = LoadBarPosition(bk)
        end
        if pos and pos.x and pos.y then
            fs:SetText(format("%.0f, %.0f", toPx(pos.x), toPx(pos.y)))
            fs:Show()
            return
        end
        -- Last resort: derive from mover bounds.
        local l, r, t, b2 = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
        if not l or not t then fs:Hide(); return end
        local screenW = UIParent:GetWidth()
        local screenH = UIParent:GetHeight()
        fs:SetText(format("%.0f, %.0f",
            toPx(((l + r) * 0.5) - screenW * 0.5),
            toPx(((t + b2) * 0.5) - screenH * 0.5)))
        fs:Show()
    end

    mover._barKey = barKey
    mover:SetAlpha(UM.darkOverlaysEnabled and 1 or MOVER_ALPHA)

    -- Initialize anchored text and link states, then apply idle state
    RefreshAnchoredIdle()
    RefreshLinkStates()
    ApplyHoverState(0)

    -- Sync size/position to the real bar (or registered element)
    function mover:Sync()
        -- Temporarily hidden for this unlock session (Shift+Right Click). Stay
        -- hidden until unlock mode is re-entered, which clears the flag. Every
        -- re-sync path (retry ticker, combat resume, open fade-in loops) must
        -- honor this and keep the overlay hidden.
        if self._tempHidden then self:Hide(); return end
        local bk = self._barKey
        local b = UM.GetBarFrame(bk)
        local elem = registeredElements[bk]

        -- Re-read the element's moverBg tint: movers persist for the session
        -- while elements re-register with STATE-DEPENDENT tints (CDM's
        -- Additional Bar Offset marker), so a stale CreateMover-time color
        -- would stick until /reload. Change-guarded repaint.
        do
            local bgTint = elem and elem.moverBg
            local nr = bgTint and bgTint.r or 0.075
            local ng = bgTint and bgTint.g or 0.113
            local nb = bgTint and bgTint.b or 0.141
            if self._bgR ~= nr or self._bgG ~= ng or self._bgB ~= nb then
                self._bgR, self._bgG, self._bgB = nr, ng, nb
                if self._bg and UM.darkOverlaysEnabled then
                    self._bg:SetColorTexture(nr, ng, nb, 0.95)
                end
            end
        end

        -- Stale/intentionally-hidden registrations (e.g. a deleted CDM tracking bar
        -- whose TBB_<idx> element is never unregistered, or a grouped non-anchor
        -- bar) must NOT be shown. Mirrors the CreateMover guard so blanket
        -- `for _, m in pairs(movers) do m:Sync() end` loops can't re-show a mover
        -- CreateMover intentionally hid. Action bars resolve elem == nil (no-op); isHidden is read live, so an un-hidden element still syncs.
        if elem and ((elem.isHidden and elem.isHidden())
                  or (elem.isAnchored and elem.isAnchored() and not elem.keepMoverWhenAnchored)) then
            self:Hide()
            return
        end

        -- For registered elements without a live frame, use getSize + loadPosition
        if not b and elem then
            local w, h = 100, 30
            local centerYOff = 0
            if elem.getSize then
                local gw, gh, gyOff = elem.getSize(bk)
                w, h = gw, gh
                centerYOff = gyOff or 0
            end
            if w < 10 then w = 100 end
            if h < 10 then h = 30 end
            baseW, baseH = w, h
            self:SetSize(w, h)
            if self._label then self._label:SetWidth(w * 0.95) end
            local pos = elem.loadPosition and elem.loadPosition(bk)
            if pos then
                self:ClearAllPoints()
                self:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, (pos.y or 0) + centerYOff)
            else
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "CENTER", 0, centerYOff)
            end
            self:Show()
            ApplyHoverState(hoverState)
            return
        end

        if not b then self:Hide(); return end
        -- Show mover even for hidden bars (mouseover/alwaysHidden) so user can reposition
        -- Only skip if the bar frame truly doesn't exist.
        -- A bar still on a follow anchor from before the session (a Blizzard
        -- Style cast bar under its frame's aura stack) reports a secret rect:
        -- re-apply its anchor now -- the follow provider is inert in unlock
        -- mode, so that places it absolutely -- and sync from the plain rect.
        -- If the rect has not resolved yet, sync again next frame.
        if RectSecret(b) then
            if EllesmereUI.ReapplyOwnAnchor then EllesmereUI.ReapplyOwnAnchor(bk) end
            if RectSecret(b) then
                self:Hide()
                local n = self._secretResync or 0
                if n < 2 then
                    self._secretResync = n + 1
                    C_Timer.After(0, function() self:Sync() end)
                end
                return
            end
        end
        self._secretResync = nil
        local s = b:GetEffectiveScale()
        local uiS = UIParent:GetEffectiveScale()
        local w, h
        local elemScale = s / uiS
        -- Visual insets (optional, e.g. a Blizzard Style unit frame whose stock
        -- box carries transparent padding round its art): the mover outlines
        -- the rect inside them. UIParent units.
        local il, ir, it, ib = 0, 0, 0, 0
        if elem and elem.getInsets then
            local l, r, t, bt = elem.getInsets(bk)
            if l then il, ir, it, ib = l * elemScale, (r or 0) * elemScale, (t or 0) * elemScale, (bt or 0) * elemScale end
        end
        -- Read size directly from the bar frame. Since the mover is anchored
        -- to the bar, we need the size in the mover's coordinate space.
        -- elemScale converts from bar space to UIParent (mover parent) space.
        w = (b:GetWidth() or 50) * elemScale - il - ir
        h = (b:GetHeight() or 50) * elemScale - it - ib
        -- For action bars, compute visual size from button grid (accounts for
        -- shape overrides, padding, and per-button scale)
        -- Only use this as a fallback when the frame has no size yet (first load).
        if w < 10 or h < 10 then
            local abW, abH = GetActionBarVisualSize(bk)
            if abW and abH then
                w, h = abW, abH
            end
        end
        local isTinyAnchor = (w < 10)
        local centerYOff = 0
        if isTinyAnchor then
            -- Frame exists but has no size yet -- use getSize fallback
            if elem and elem.getSize then
                local gw, gh, gyOff = elem.getSize(bk)
                w, h = gw, gh
                centerYOff = gyOff or 0
            end
        end
        -- Extend the overlay downward to wrap an element's below-frame extra
        -- (e.g. the boss castbar). Inflating h here flows into SetSize and the
        -- center math below, keeping the top pinned and growing the box down.
        if elem and elem.getBottomExtra then
            h = h + (elem.getBottomExtra(bk) or 0) * elemScale
        end
        baseW, baseH = w, h
        self:SetSize(w, h)
        if self._label then self._label:SetWidth(w * 0.95) end

        -- Position: convert bar's screen position to UIParent-relative
        -- Center the mover on the bar's visual center for pixel-perfect alignment.
        local bL = b:GetLeft()
        local bT = b:GetTop()
        if bL and bT then
            local PP = EllesmereUI and EllesmereUI.PP
            if isTinyAnchor and elem then
                -- Dynamic bar (1x1 when empty): anchor is CENTER-positioned.
                -- Compute TOPLEFT from GetCenter() to avoid layout-flush timing
                -- issues where GetLeft()/GetTop() still reflect the old 1x1 size.
                local cx, cy
                local bCX, bCY = b:GetCenter()
                if bCX and bCY then
                    cx = bCX * s / uiS + (il - ir) * 0.5 - w * 0.5
                    cy = bCY * s / uiS + (ib - it) * 0.5 - UIParent:GetHeight() + h * 0.5 + centerYOff
                elseif bL and bT then
                    cx = bL * s / uiS
                    cy = bT * s / uiS - UIParent:GetHeight()
                else
                    -- No screen position yet -- fall back to saved pos
                    local pos = elem.loadPosition and elem.loadPosition(bk)
                    if pos and pos.point == "CENTER" then
                        local uiW = UIParent:GetWidth()
                        local uiH = UIParent:GetHeight()
                        cx = uiW * 0.5 + (pos.x or 0) - w * 0.5
                        cy = -(uiH * 0.5) + (pos.y or 0) + h * 0.5
                    else
                        cx = 0; cy = -UIParent:GetHeight() * 0.5
                    end
                end
                if PP then cx = PP.Scale(cx); cy = PP.Scale(cy) end
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cx, cy)
                moverCX, moverCY = cx + w * 0.5, cy - h * 0.5
            else
                -- Anchor mover directly to the bar frame so both share the
                -- exact same screen position with zero coordinate math.
                EllesmereUI._unlockAttachMover(self, b, bk, il, it)
                -- Compute moverCX/moverCY for snap/drag logic
                local cx = bL * elemScale + il
                local cy = bT * elemScale - UIParent:GetHeight() - it
                moverCX, moverCY = cx + w * 0.5, cy - h * 0.5
            end
        else
            -- Bar has no position yet (not shown), place at center
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            moverCX, moverCY = 0, -UIParent:GetHeight() * 0.5
        end
        self:Show()
        -- Re-apply hover state so mover size reflects current animation state
        ApplyHoverState(hoverState)
    end

    -- Lightweight size-only sync: updates baseW/baseH and re-applies hover state
    -- without repositioning the mover. Used after width/height match changes.
    function mover:SyncSize()
        local bk = self._barKey
        local elem = registeredElements[bk]
        if elem and elem.getSize then
            local gw, gh = elem.getSize(bk)
            -- Use the raw value from getSize without rounding: the layout function
            -- (LayoutCDMBar, LayoutBar, etc.) already snapped dimensions to the
            -- physical pixel grid. Re-rounding to the nearest integer shifts values
            -- off the pixel grid when PP.mult != 1.0 (e.g. 214.4 -> 214 instead of staying 214.4, exactly 402 physical pixels at mult=0.533).
            if gw and gw > 0 then baseW = gw end
            if gh and gh > 0 then baseH = gh end
        else
            local b = UM.GetBarFrame(bk)
            if b then
                local s = b:GetEffectiveScale()
                local uiS = UIParent:GetEffectiveScale()
                baseW = (b:GetWidth() or baseW) * s / uiS
                baseH = (b:GetHeight() or baseH) * s / uiS
            end
        end
        -- moverCX/moverCY are already updated by RecenterBarAnchor (called before
        -- SyncSize). Do NOT recompute from GetLeft/GetTop here -- the mover may
        -- still be anchored to the bar's old TOPLEFT position at this point, which
        -- would produce a wrong center and cause a one-frame visual jump.
        ApplyHoverState(hoverState)
        -- Re-anchor to bar for pixel-perfect alignment after size change
        self:ReanchorToBar()
    end

    -- Drag handlers: manual cursor-based positioning for live snap + live bar movement
    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        -- Position-locked: the module's anchor option owns this bar's position
        if ns.IsMoverPosLocked(self._barKey) then SelectMover(self); return end
        -- Anchored bars can be dragged -- the offset from parent is updated on drop
        SelectMover(self)
        self:SetAlpha(UM.darkOverlaysEnabled and 1 or MOVER_DRAG)
        self._dragging = true
        self._hoverPending = false  -- cancel pending expand animation
        self._shiftAxis = nil  -- nil = not locked, "X" or "Y" once determined
        -- Cache centerYOff for tiny-anchor elements (used in OnUpdate and OnDragStop)
        local elem = registeredElements[self._barKey]
        if elem and elem.getSize then
            local _, _, gyOff = elem.getSize(self._barKey)
            self._dragCenterYOff = gyOff or 0
        else
            self._dragCenterYOff = 0
        end
        -- Visual insets (see Sync): the bar's box sits outside the mover by
        -- these, UIParent units. The bar is placed from the mover's rect plus
        -- them, and the mover re-attaches inside them.
        self._dragIL, self._dragIR, self._dragIT, self._dragIB = 0, 0, 0, 0
        if elem and elem.getInsets then
            local bIn = UM.GetBarFrame(self._barKey)
            local l, r, t, bt = elem.getInsets(self._barKey)
            if l and bIn then
                local es = bIn:GetEffectiveScale() / UIParent:GetEffectiveScale()
                self._dragIL, self._dragIR = l * es, (r or 0) * es
                self._dragIT, self._dragIB = (t or 0) * es, (bt or 0) * es
            end
        end
        -- Snap links away instantly during drag (no animation -- it fights with drag positioning)
        hoverState = 0
        hoverTarget = 0
        animFrame:SetScript("OnUpdate", nil)
        ApplyHoverState(0)

        -- Record offset from cursor to mover center at drag start
        -- Use stored moverCX/moverCY (base-size center) so expanding/collapsing
        -- hover state does not corrupt the offset when dragging from a link button
        local scale = UIParent:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        curX = curX / scale
        curY = curY / scale
        local cx = (moverCX ~= 0 or moverCY ~= 0) and moverCX or (self:GetLeft() + self:GetRight()) / 2
        local cy = (moverCX ~= 0 or moverCY ~= 0) and moverCY or (self:GetTop() + self:GetBottom()) / 2 - UIParent:GetHeight()
        cy = cy + UIParent:GetHeight()  -- convert back to screen-space Y for drag math
        self._dragOffX = cx - curX
        self._dragOffY = cy - curY
        self._dragStartCX = cx
        self._dragStartCY = cy

        -- Snap mover to cursor immediately so there's no one-frame lag
        local halfW0 = self:GetWidth() / 2
        local halfH0 = self:GetHeight() / 2
        self._dragHalfW = halfW0
        self._dragHalfH = halfH0
        local snap0X, snap0Y = SnapPosition(self._barKey, cx, cy, halfW0, halfH0)
        local bar0 = UM.GetBarFrame(self._barKey)
        if bar0 and not InCombatLockdown() then
            local uiS0 = UIParent:GetEffectiveScale()
            local bS0 = bar0:GetEffectiveScale()
            local ratio0 = uiS0 / bS0
            local barHW0 = (bar0:GetWidth() or 0) * 0.5
            local barHH0 = (bar0:GetHeight() or 0) * 0.5
            local barX0 = (snap0X + (self._dragIR - self._dragIL) * 0.5) * ratio0 - barHW0
            local barY0 = (snap0Y + (self._dragIT - self._dragIB) * 0.5 - UIParent:GetHeight() - (self._dragCenterYOff or 0)) * ratio0 + barHH0
            local PPd = EllesmereUI and EllesmereUI.PP
            if PPd and PPd.SnapForES then
                local lockX, lockY = EllesmereUI._snapAxisLocked()
                if not lockX then barX0 = PPd.SnapForES(barX0, bS0) end
                if not lockY then barY0 = PPd.SnapForES(barY0, bS0) end
            end
            pcall(function()
                EllesmereUI.ClearFramePoints(bar0)
                EllesmereUI.SetFramePoint(bar0, "TOPLEFT", UIParent, "TOPLEFT", barX0, barY0)
            end)
            -- Element follow-up to the one-point placement above (an element
            -- whose rect needs a second anchor -- main chat's size corner --
            -- restores it here), before the collapsed rect ever renders.
            if elem and elem.onLiveMove then
                pcall(elem.onLiveMove, self._barKey)
            end
            self:ClearAllPoints()
            if elem and elem.detachedMover then
                -- The bar refuses dependents (see AttachMoverToBar): same spot, absolute.
                self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", snap0X - halfW0, snap0Y + halfH0 - UIParent:GetHeight())
            else
                self:SetPoint("TOPLEFT", bar0, "TOPLEFT", self._dragIL, -self._dragIT)
            end
        else
            local f0X = snap0X - halfW0
            local f0Y = snap0Y + halfH0 - UIParent:GetHeight()
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", f0X, f0Y)
        end

        -- OnUpdate: move mover + real bar to cursor position with snap
        self:SetScript("OnUpdate", function(s)
            local sc = UIParent:GetEffectiveScale()
            local mx, my = GetCursorPosition()
            mx = mx / sc
            my = my / sc

            -- Raw center = cursor + offset
            local rawCX = mx + s._dragOffX
            local rawCY = my + s._dragOffY

            -- Shift-axis-lock: constrain to one axis based on initial drag direction
            if IsShiftKeyDown() then
                if not s._shiftAxis then
                    local adx = abs(rawCX - s._dragStartCX)
                    local ady = abs(rawCY - s._dragStartCY)
                    -- Determine axis once movement exceeds 3px threshold
                    if adx > 3 or ady > 3 then
                        s._shiftAxis = (adx >= ady) and "X" or "Y"
                    end
                end
                if s._shiftAxis == "X" then
                    rawCY = s._dragStartCY
                elseif s._shiftAxis == "Y" then
                    rawCX = s._dragStartCX
                end
            else
                s._shiftAxis = nil  -- release shift = unlock axis
            end

            local halfW = s._dragHalfW
            local halfH = s._dragHalfH

            -- Apply snap
            local snapCX, snapCY = SnapPosition(s._barKey, rawCX, rawCY, halfW, halfH)

            -- Clamp to screen edges
            local screenW = UIParent:GetWidth()
            local screenH = UIParent:GetHeight()
            snapCX = max(halfW, min(screenW - halfW, snapCX))
            snapCY = max(halfH, min(screenH - halfH, snapCY))

            -- Move the real bar live first, then anchor the mover to it so
            -- the overlay stays pixel-perfect regardless of scale differences.
            local bar = UM.GetBarFrame(s._barKey)
            if bar and not InCombatLockdown() then
                local uiS = UIParent:GetEffectiveScale()
                local bS = bar:GetEffectiveScale()
                local ratio = uiS / bS
                -- bar:GetWidth/Height are in the bar's local (unscaled) space.
                -- Convert snapCX/snapCY (UIParent screen coords) into the bar's
                -- local space first, then subtract the unscaled half-size to get TOPLEFT.
                local barHW = (bar:GetWidth() or 0) * 0.5
                local barHH = (bar:GetHeight() or 0) * 0.5
                local barX = (snapCX + (s._dragIR - s._dragIL) * 0.5) * ratio - barHW
                local barY = (snapCY + (s._dragIT - s._dragIB) * 0.5 - UIParent:GetHeight() - (s._dragCenterYOff or 0)) * ratio + barHH
                local PPd = EllesmereUI and EllesmereUI.PP
                if PPd and PPd.SnapForES then
                    -- When an edge snap is active, skip SnapForES on that axis.
                    -- The unsnapped barX/barY already matches the target's edge
                    -- exactly. Re-snapping would shift it to a different pixel.
                    local lockX, lockY = EllesmereUI._snapAxisLocked()
                    if not lockX then barX = PPd.SnapForES(barX, bS) end
                    if not lockY then barY = PPd.SnapForES(barY, bS) end
                end
                pcall(function()
                    EllesmereUI.ClearFramePoints(bar)
                    EllesmereUI.SetFramePoint(bar, "TOPLEFT", UIParent, "TOPLEFT", barX, barY)
                end)
                -- Anchor mover directly to bar TOPLEFT for pixel-perfect overlay
                s:ClearAllPoints()
                local dElem = registeredElements[s._barKey]
                if dElem and dElem.detachedMover then
                    -- The bar refuses dependents (see AttachMoverToBar): same spot, absolute.
                    s:SetPoint("TOPLEFT", UIParent, "TOPLEFT", snapCX - halfW, snapCY + halfH - UIParent:GetHeight())
                else
                    s:SetPoint("TOPLEFT", bar, "TOPLEFT", s._dragIL, -s._dragIT)
                end
            else
                -- No live bar -- position mover in UIParent space
                local finalX = snapCX - halfW
                local finalY = snapCY + halfH - UIParent:GetHeight()
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", UIParent, "TOPLEFT", finalX, finalY)
            end

            -- Element follow-up to the placement above, BEFORE the anchor chain
            -- reads this frame's rect: an element whose rect needs a second
            -- anchor (main chat's size corner) restores it here, so dependents
            -- anchor against the true rect on the same tick.
            local elem = registeredElements[s._barKey]
            if elem and elem.onLiveMove then
                pcall(elem.onLiveMove, s._barKey)
            end

            -- Show live coordinates during drag (only on elements >= 20px tall).
            -- Physical-pixel counts, matching the cog X/Y boxes and the overlay.
            if s._coordFS and s:GetHeight() >= 12 then
                local PPc = EllesmereUI and EllesmereUI.PP
                local toPx = (PPc and PPc.ToPixels) or round
                s._coordFS:SetText(format("%.0f, %.0f", toPx(snapCX - screenW * 0.5), toPx(snapCY - screenH * 0.5)))
                s._coordFS:Show()
            end

            -- Anchor chain: propagate recursively down the chain
            local anchorDB = GetAnchorDB()
            if anchorDB then
                UM.PropagateAnchorChain(s._barKey)
            end

            ShowAlignmentGuides(s._barKey)

            -- Safety net: if mouse button was released outside any button frame
            -- (e.g. during a link-initiated drag), stop the drag now.
            if not IsMouseButtonDown("LeftButton") then
                local stopScript = s:GetScript("OnDragStop")
                if stopScript then stopScript(s) end
            end
        end)
    end)

    mover:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self._dragging = false
        _mouseHeld = false
        self:SetAlpha(UM.darkOverlaysEnabled and 1 or MOVER_HOVER)
        -- Convert back to CENTER anchor so hover-expand stays symmetric
        local mL, mR = self:GetLeft(), self:GetRight()
        local mT, mB = self:GetTop(), self:GetBottom()
        if mL and mR and mT and mB then
            local cx = (mL + mR) * 0.5
            local cy = (mT + mB) * 0.5 - UIParent:GetHeight()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy)
            moverCX, moverCY = cx, cy
        end
        -- Update coords to final position (stays visible if selected or coords-always-on)
        if self._selected and self.UpdateCoordText then
            self:UpdateCoordText()
        elseif UM.coordsEnabled and self.UpdateCoordText then
            self:UpdateCoordText()
        else
            self._coordFS:Hide()
        end
        HideAllGuidesAndHighlight()
        -- Re-show links after drag if still hovered
        if self:IsMouseOver() then
            if self._showOverlayText then self._showOverlayText() end
        end
        -- Re-anchor toolbar in case mover moved near/away from screen top
        if self._anchorToolbar then self._anchorToolbar() end

        -- Check if the mover actually moved (avoids false dirty flag from
        -- click-and-hold without movement)
        local cxL, cxR = self:GetLeft(), self:GetRight()
        local cyT, cyB = self:GetTop(), self:GetBottom()
        if not cxL or not cxR or not cyT or not cyB then return end
        local cx = (cxL + cxR) / 2
        local cy = (cyT + cyB) / 2
        local startCX = self._dragStartCX or cx
        local startCY = self._dragStartCY or cy
        local moved = (abs(cx - startCX) > 0.5) or (abs(cy - startCY) > 0.5)
        if not moved then return end

        -- Store position in pending table (NOT saved until user clicks Save & Exit)

        local bar = UM.GetBarFrame(self._barKey)
        if not InCombatLockdown() then
            local uiS = UIParent:GetEffectiveScale()

            -- If this bar is anchored, the offset was already updated live during drag.
            -- No need to recompute here -- using mover screen coords would introduce
            -- sub-pixel drift vs the cursor-based offset set in OnUpdate.

            local dragCYOff = self._dragCenterYOff or 0
            if bar then
                -- Read the bar's actual TOPLEFT from its current SetPoint rather
                -- than recomputing from the mover center. The OnUpdate already
                -- positioned the bar with exact edge alignment (no SnapForES drift).
                local _, _, _, barX, barY = bar:GetPoint(1)
                if not barX or not barY then
                    local bS = bar:GetEffectiveScale()
                    local ratio = uiS / bS
                    local barHW = (bar:GetWidth() or 0) * 0.5
                    local barHH = (bar:GetHeight() or 0) * 0.5
                    barX = cx * ratio - barHW
                    barY = (cy - UIParent:GetHeight() - dragCYOff) * ratio + barHH
                    local PPd = EllesmereUI and EllesmereUI.PP
                    if PPd and PPd.SnapForES then
                        barX = PPd.SnapForES(barX, bS)
                        barY = PPd.SnapForES(barY, bS)
                    end
                end
                pendingPositions[self._barKey] = {
                    point = "TOPLEFT", relPoint = "TOPLEFT",
                    x = barX, y = barY,
                }
            else
                -- No live frame (e.g. unit frame not spawned) -- store in UIParent coords
                local halfW = (baseW > 0 and baseW or self:GetWidth()) / 2
                local halfH = (baseH > 0 and baseH or self:GetHeight()) / 2
                pendingPositions[self._barKey] = {
                    point = "TOPLEFT", relPoint = "TOPLEFT",
                    x = cx - halfW, y = cy + halfH - UIParent:GetHeight() - dragCYOff,
                }
            end
            UM.hasChanges = true
        end

        -- If anchored to a parent, update the stored offset so the parent's future
        -- moves don't snap this child back. Read actual child edges directly
        -- instead of computing from center+half to avoid float dust from (top+bottom)/2 - height/2 != bottom.
        local ai = GetAnchorInfo(self._barKey)
        if ai then
            local targetBar = UM.GetBarFrame(ai.target)
            if targetBar then
                local tS = targetBar:GetEffectiveScale()
                local uiScale = UIParent:GetEffectiveScale()
                local tL = targetBar:GetLeft()
                local tR = targetBar:GetRight()
                local tT = targetBar:GetTop()
                local tB = targetBar:GetBottom()
                if tL and tR and tT and tB then
                    tL = tL * tS / uiScale
                    tR = tR * tS / uiScale
                    tT = tT * tS / uiScale
                    tB = tB * tS / uiScale
                    local tCX = (tL + tR) / 2
                    local tCY = (tT + tB) / 2
                    -- Growth-edge extent and followed edges: the same edges the
                    -- apply measures from. A follow frame's live bottom is plain
                    -- here (unlock mode never runs under aura restriction).
                    if EllesmereUI._GetAnchorTargetExtent then
                        local ext = EllesmereUI._GetAnchorTargetExtent(ai.target, ai.side)
                        if ext then
                            if ai.side == "TOP" then tT = ext
                            elseif ai.side == "BOTTOM" then tB = ext
                            elseif ai.side == "LEFT" then tL = ext
                            elseif ai.side == "RIGHT" then tR = ext
                            end
                        end
                    end
                    if ai.side == "BOTTOM" and EllesmereUI._GetAnchorFollowFrame then
                        local fol = EllesmereUI._GetAnchorFollowFrame(self._barKey, ai.target, ai.side)
                        local fB = fol and fol:GetBottom()
                        if not (issecretvalue and issecretvalue(fB)) and fB then
                            tB = fB * fol:GetEffectiveScale() / uiScale
                        end
                    end
                    -- Read child edges from the actual bar frame for accuracy
                    local childBar = UM.GetBarFrame(self._barKey)
                    local cL, cR, cT, cB
                    local cRatio = 1   -- mover coords are already UIParent units
                    if childBar and childBar:GetLeft() then
                        local cS = childBar:GetEffectiveScale()
                        cRatio = cS / uiScale
                        cL = childBar:GetLeft() * cS / uiScale
                        cR = childBar:GetRight() * cS / uiScale
                        cT = childBar:GetTop() * cS / uiScale
                        cB = childBar:GetBottom() * cS / uiScale
                    else
                        local halfW = baseW > 0 and baseW / 2 or (self:GetWidth() / 2)
                        local halfH = baseH > 0 and baseH / 2 or (self:GetHeight() / 2)
                        cL = cx - halfW; cR = cx + halfW
                        cT = cy + halfH; cB = cy - halfH
                    end
                    -- The live rect carries the element's own extra offset (the raid
                    -- container's per-tier offset), which every anchored apply folds in
                    -- again: rebase to the base rect before storing the offsets, like
                    -- the cog's screen-edge link does. The getter is in frame units.
                    local exX, exY = EllesmereUI._ExtraAnchorOffset(self._barKey)
                    exX, exY = exX * cRatio, exY * cRatio
                    cL, cR = cL - exX, cR - exX
                    cT, cB = cT - exY, cB - exY
                    local cCX = (cL + cR) / 2
                    local cCY = (cT + cB) / 2
                    local sd = ai.side
                    if sd == "LEFT" then
                        ai.offsetX = cR - tL
                        ai.offsetY = cCY - tCY
                    elseif sd == "RIGHT" then
                        ai.offsetX = cL - tR
                        ai.offsetY = cCY - tCY
                    elseif sd == "TOP" then
                        ai.offsetX = cCX - tCX
                        ai.offsetY = cB - tT
                    elseif sd == "BOTTOM" then
                        ai.offsetX = cCX - tCX
                        ai.offsetY = cT - tB
                    else
                        ai.offsetX = cCX - tCX
                        ai.offsetY = cCY - tCY
                    end
                end
            end
            -- The cross-axis screen edge rides the same recapture, else the next
            -- apply pulls that axis back to where the edge offset still points.
            if ai.edge and ai.edge.key then
                local eo = EllesmereUI._CaptureScreenEdgeOffset(self._barKey, ai.edge.key, ai.edge.side)
                if eo then ai.edge.offset = eo end
            end
            -- Growth bars: recapture the growth-edge pin from the dropped
            -- position (the user may have carried the bar to the other
            -- corner, which can change the reference edge).
            if EllesmereUI._unlockCaptureGrowPin then
                EllesmereUI._unlockCaptureGrowPin(self._barKey, ai, ai.side)
            end
        end

        -- Anchor chain: propagate recursively down the chain
        UM.PropagateAnchorChain(self._barKey)

        local elem = registeredElements[self._barKey]
        if elem and elem.onLiveMove then
            pcall(elem.onLiveMove, self._barKey)
        end

        -- Keep the mover selected after drag so arrow keys can nudge it.
        -- Drop frame level back to normal so it doesn't block other movers.
        if self._selected then
            self:SetFrameLevel(self._baseLevel or self:GetFrameLevel())
        end

        -- Re-anchor mover to bar for pixel-perfect alignment
        self:ReanchorToBar()
    end)

    -- Hover effects
    mover:SetScript("OnEnter", function(self)
        if not self._dragging then
            if _mouseHeld and not self._dragging then return end
            -- Collapse any other expanded mover before expanding this one
            if UM.hoveredMover and UM.hoveredMover ~= self and not UM.hoveredMover._dragging then
                if UM.hoveredMover._hideOverlayText then UM.hoveredMover._hideOverlayText() end
                UM.hoveredMover = nil
            end
            -- Collapse selected mover's overlay if hovering a different one
            if UM.selectedMover and UM.selectedMover ~= self and not UM.selectedMover._dragging then
                if UM.selectedMover._hideOverlayText then UM.selectedMover._hideOverlayText() end
            end
            UM.hoveredMover = self
            -- Raise above all other movers
            self:SetFrameLevel(self._raisedLevel + 100)
            if self._cogBtn then self._cogBtn:SetFrameLevel(self:GetFrameLevel() + 10) end
            -- Select Element mode: white border highlight on hover targets
            if UM.selectElementPicker and UM.selectElementPicker ~= self then
                self._brd:SetColor(1, 1, 1, 0.9)
                if not UM.darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
                return
            end
            -- Pick mode (width/height match, anchor to): white border on hover targets
            if UM.pickModeMover and UM.pickModeMover ~= self and UM.pickMode then
                self._brd:SetColor(1, 1, 1, 0.9)
                if not UM.darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
                return
            end
            if not UM.darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
            self._brd:SetColor(1, 1, 1, 0.9)
            -- Don't show links if this mover is the pick mode source
            if UM.pickModeMover == self and UM.pickMode then
                -- Already showing pick text, don't override
            else
                -- Wait the intent delay, then expand if still hovered and cursor has settled.
                -- If cursor is still fast at fire time, allow one retry after a short pause.
                self._hoverPending = true
                local m = self
                C_Timer.After(EllesmereUI._unlockHoverIntentDelay, function()
                    if not m._hoverPending then return end
                    if not m:IsMouseOver() and not (m._cogBtn and m._cogBtn:IsMouseOver()) then
                        local overLink = false
                        if m._linkBtns then for _, b in ipairs(m._linkBtns) do if b:IsMouseOver() then overLink = true; break end end end
                        if not overLink then m._hoverPending = false; return end
                    end
                    local function DoExpand()
                        if not m._hoverPending then return end
                        m._hoverPending = false
                        local stillOver = m:IsMouseOver() or (m._cogBtn and m._cogBtn:IsMouseOver())
                        if not stillOver and m._linkBtns then
                            for _, b in ipairs(m._linkBtns) do if b:IsMouseOver() then stillOver = true; break end end
                        end
                        if stillOver and m._showOverlayText then
                            -- Collapse any other mover still animating open
                            if UM.hoveredMover and UM.hoveredMover ~= m and not UM.hoveredMover._dragging then
                                if UM.hoveredMover._hideOverlayText then UM.hoveredMover._hideOverlayText() end
                                UM.hoveredMover = nil
                            end
                            UM.hoveredMover = m
                            m._showOverlayText()
                        end
                    end
                    if EllesmereUI._unlockCursorSpeed > EllesmereUI._unlockHoverSpeedThresh then
                        C_Timer.After(0.08, DoExpand)
                    else
                        DoExpand()
                    end
                end)
            end
        end
    end)
    mover:SetScript("OnLeave", function(self)
        if not self._dragging then
            -- Delay so hovering child buttons (cog, link buttons) doesn't flicker
            C_Timer.After(0.12, function()
                if self._dragging then return end
                if self:IsMouseOver() then
                    self:SetFrameLevel(self._raisedLevel + 100)
                    self._brd:SetColor(1, 1, 1, 0.9)
                    if not UM.darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
                    return
                end
                if self._cogBtn and self._cogBtn:IsMouseOver() then
                    self:SetFrameLevel(self._raisedLevel + 100)
                    self._brd:SetColor(1, 1, 1, 0.9)
                    if not UM.darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
                    return
                end
                if self._linkBtns then
                    for _, btn in ipairs(self._linkBtns) do
                        if btn:IsMouseOver() then
                            self:SetFrameLevel(self._raisedLevel + 100)
                            self._brd:SetColor(1, 1, 1, 0.9)
                            if not UM.darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
                            return
                        end
                    end
                end
                -- Truly left the element -- cancel any pending expand and collapse
                self._hoverPending = false
                if self._hideOverlayText then self._hideOverlayText() end
                if UM.hoveredMover == self then UM.hoveredMover = nil end
                -- Keep highlight border and raised level if selected (arrow keys)
                if not self._selected then
                    self:SetFrameLevel(self._baseLevel)
                    if not UM.darkOverlaysEnabled then self:SetAlpha(MOVER_ALPHA) end
                    self._brd:SetColor(ar, ag, ab, 0.6)
                end
            end)
        end
    end)

    -- Left-click to select
    mover:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            -- Width Match / Height Match / Anchor To pick mode handling
            -- Clicking the source mover itself cancels the pick mode
            if UM.pickModeMover and UM.pickModeMover == self and UM.pickMode then
                CancelPickMode()
                return
            end
            if UM.pickModeMover and UM.pickModeMover ~= self and UM.pickMode then
                local sourceMover = UM.pickModeMover
                local sourceKey = sourceMover._barKey
                local targetKey = self._barKey

                if UM.pickMode == "widthMatch" then
                    local tEl = registeredElements[targetKey]
                    if tEl and tEl.noSizeMatchTarget then
                        CancelPickMode()
                        FlashRedBorder(self)
                        local tLabel = UM.GetBarLabel(targetKey) or targetKey
                        RejectH.ShowTooltip(EllesmereUI.Lf("Elements cannot size match to\n%1$s", EllesmereUI.L(tLabel)))
                        return
                    end
                    if RejectH.IsActionBar(sourceKey) and not RejectH.IsActionBar(targetKey) then
                        CancelPickMode()
                        FlashRedBorder(self)
                        RejectH.ShowTooltip("Action Bars can only width match\nto other Action Bars")
                        return
                    end
                    local wdb = MatchH.GetWidthMatchDB()
                    if wdb and MatchH.WouldCreateCycle(wdb, sourceKey, targetKey) then
                        CancelPickMode()
                        FlashRedBorder(self)
                        RejectH.ShowTooltip("This would create a circular width match")
                        return
                    end
                    MatchH.SetWidthMatch(sourceKey, targetKey)
                    MatchH.ApplyWidthMatch(sourceKey, targetKey)
                    UM.hasChanges = true
                    CancelPickMode()
                    local sm = movers[sourceKey]
                    if sm then
                        sm:SyncSize()
                        if sm.RefreshAnchoredText then sm:RefreshAnchoredText() end
                    end
                    local ai = GetAnchorInfo(sourceKey)
                    if ai then UM.ApplyAnchorPosition(sourceKey, ai.target, ai.side, true) end
                    EllesmereUI.PropagateWidthMatch(sourceKey)
                    UM.PropagateAnchorChain(sourceKey)
                    return

                elseif UM.pickMode == "heightMatch" then
                    local tEl = registeredElements[targetKey]
                    if tEl and tEl.noSizeMatchTarget then
                        CancelPickMode()
                        FlashRedBorder(self)
                        local tLabel = UM.GetBarLabel(targetKey) or targetKey
                        RejectH.ShowTooltip(EllesmereUI.Lf("Elements cannot size match to\n%1$s", EllesmereUI.L(tLabel)))
                        return
                    end
                    local hdb = MatchH.GetHeightMatchDB()
                    if hdb and MatchH.WouldCreateCycle(hdb, sourceKey, targetKey) then
                        CancelPickMode()
                        FlashRedBorder(self)
                        RejectH.ShowTooltip("This would create a circular height match")
                        return
                    end
                    MatchH.SetHeightMatch(sourceKey, targetKey)
                    MatchH.ApplyHeightMatch(sourceKey, targetKey)
                    UM.hasChanges = true
                    CancelPickMode()
                    local sm = movers[sourceKey]
                    if sm then
                        sm:SyncSize()
                        if sm.RefreshAnchoredText then sm:RefreshAnchoredText() end
                    end
                    local ai = GetAnchorInfo(sourceKey)
                    if ai then UM.ApplyAnchorPosition(sourceKey, ai.target, ai.side, true) end
                    EllesmereUI.PropagateHeightMatch(sourceKey)
                    UM.PropagateAnchorChain(sourceKey)
                    return

                elseif UM.pickMode == "anchorTo" or UM.pickMode == "fallbackAnchor"
                    or UM.pickMode == "overrideAnchor" then
                    -- Show anchor direction dropdown near the clicked target.
                    -- fallbackAnchor mode stores a fallback link on the
                    -- element's EXISTING anchor instead of re-anchoring it;
                    -- overrideAnchor mode stores a per-override-group link.
                    local fbPick = (UM.pickMode == "fallbackAnchor")
                    local ovPick = (UM.pickMode == "overrideAnchor")
                    local ovGid = ovPick and EllesmereUI._OverridePickGid
                        and EllesmereUI._OverridePickGid() or nil
                    local pm = UM.pickModeMover
                    local pmKey = pm._barKey

                    -- Reject elements marked as non-anchorable (e.g. buff bars
                    -- whose icon count changes dynamically with auras).
                    local targetEl = registeredElements[targetKey]
                    if targetEl and targetEl.noAnchorTarget then
                        CancelPickMode()
                        FlashRedBorder(self)
                        local targetLabel = UM.GetBarLabel(targetKey) or targetKey
                        RejectH.ShowTooltip(EllesmereUI.Lf("Elements cannot be anchored to\n%1$s", EllesmereUI.L(targetLabel)))
                        return
                    end

                    if fbPick then
                        local curInfo = GetAnchorInfo(pmKey)
                        if not curInfo or not curInfo.target then
                            CancelPickMode()
                            FlashRedBorder(self)
                            RejectH.ShowTooltip("Anchor this element first")
                            return
                        end
                        if targetKey == curInfo.target then
                            CancelPickMode()
                            FlashRedBorder(self)
                            RejectH.ShowTooltip("The fallback must differ from\nthe main anchor target")
                            return
                        end
                    end

                    if ovPick then
                        if not ovGid then
                            CancelPickMode()
                            return
                        end
                        if targetKey == pmKey then
                            CancelPickMode()
                            FlashRedBorder(self)
                            RejectH.ShowTooltip("An element cannot anchor to itself")
                            return
                        end
                        -- Walk primary + fallback + override edges from the
                        -- target: reaching this element means an engaged loop
                        -- could chase itself across cascades forever.
                        local circular = false
                        local seen = {}
                        local stack = { targetKey }
                        while #stack > 0 do
                            local k = table.remove(stack)
                            if k == pmKey then circular = true break end
                            if not seen[k] then
                                seen[k] = true
                                local info = GetAnchorInfo(k)
                                if info and info.target then stack[#stack + 1] = info.target end
                                if info and info.fallback and info.fallback.target then
                                    stack[#stack + 1] = info.fallback.target
                                end
                                local ovT = EllesmereUI._OverrideAnchorTargets
                                    and EllesmereUI._OverrideAnchorTargets(k)
                                if ovT then
                                    for i = 1, #ovT do stack[#stack + 1] = ovT[i] end
                                end
                            end
                        end
                        if circular then
                            CancelPickMode()
                            FlashRedBorder(self)
                            RejectH.ShowTooltip("This would create a circular anchor")
                            return
                        end
                    end

                    -- Circular / ancestor checks guard PRIMARY anchor links;
                    -- a fallback/override is a one-level positional read, so
                    -- they use their own checks above instead.
                    if not fbPick and not ovPick then
                        local circular = false
                        local visited = { [pmKey] = true }
                        local walk = targetKey
                        while walk do
                            if visited[walk] then circular = true; break end
                            visited[walk] = true
                            local info = GetAnchorInfo(walk)
                            walk = info and info.target or nil
                        end
                        if circular then
                            CancelPickMode()
                            FlashRedBorder(self)
                            RejectH.ShowTooltip("This would create a circular anchor")
                            return
                        end

                        -- Ancestor depth check: prevent anchoring to a grandparent
                        -- or higher. Only direct parent (depth 1) or unrelated
                        -- elements are valid targets.
                        local ancestorDepth = 0
                        local aWalk = pmKey
                        while aWalk do
                            local aInfo = GetAnchorInfo(aWalk)
                            if not aInfo or not aInfo.target then break end
                            ancestorDepth = ancestorDepth + 1
                            if aInfo.target == targetKey and ancestorDepth >= 2 then
                                CancelPickMode()
                                FlashRedBorder(self)
                                RejectH.ShowTooltip("This would create a circular anchor")
                                return
                            end
                            aWalk = aInfo.target
                        end
                    end

                    CancelPickMode()
                    -- Build and show the anchor direction dropdown
                    if not UM.anchorDropdownFrame then
                        UM.anchorDropdownFrame = CreateFrame("Frame", nil, UM.unlockFrame)
                        UM.anchorDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                        UM.anchorDropdownFrame:SetFrameLevel(260)
                        UM.anchorDropdownFrame:SetClampedToScreen(true)
                        UM.anchorDropdownFrame:EnableMouse(true)
                    end
                    -- Click catcher behind dropdown
                    if not UM.anchorDropdownCatcher then
                        UM.anchorDropdownCatcher = CreateFrame("Button", nil, UM.unlockFrame)
                        UM.anchorDropdownCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
                        UM.anchorDropdownCatcher:SetFrameLevel(259)
                        UM.anchorDropdownCatcher:SetAllPoints(UIParent)
                        UM.anchorDropdownCatcher:RegisterForClicks("AnyUp")
                        UM.anchorDropdownCatcher:SetScript("OnClick", function()
                            UM.anchorDropdownFrame:Hide()
                            UM.anchorDropdownCatcher:Hide()
                        end)
                    end
                    -- Rebuild dropdown content
                    for _, child in ipairs({UM.anchorDropdownFrame:GetChildren()}) do child:Hide(); child:SetParent(nil) end
                    for _, tex in ipairs({UM.anchorDropdownFrame:GetRegions()}) do if tex.Hide then tex:Hide() end end

                    local DD_ITEM_H = 24
                    local DD_WIDTH = 160
                    UM.anchorDropdownFrame:SetSize(DD_WIDTH, 10)
                    UM.anchorDropdownFrame:ClearAllPoints()
                    local scale = UIParent:GetEffectiveScale()
                    local curX, curY = GetCursorPosition()
                    curX = curX / scale
                    curY = curY / scale - UIParent:GetHeight()
                    UM.anchorDropdownFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", curX, curY)

                    local ddBg = UM.anchorDropdownFrame:CreateTexture(nil, "BACKGROUND")
                    ddBg:SetAllPoints()
                    ddBg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
                    EllesmereUI.MakeBorder(UM.anchorDropdownFrame, 1, 1, 1, 0.20)

                    local ddY = -4
                    -- Growth bars (CDM and action bars) get the corner rows below on a
                    -- primary anchor pick; the hint speaks to those rows when they exist.
                    local isGrowBar = not fbPick and not ovPick
                        and (pmKey:sub(1, 4) == "CDM_"
                             or (EllesmereUI._abBarKeys and EllesmereUI._abBarKeys[pmKey]) or false)
                    -- Title: the fallback picker keeps its short dimmed label;
                    -- the anchor picker shows a wrapped usage hint in the same
                    -- color as the option rows below.
                    local titleFS = UM.anchorDropdownFrame:CreateFontString(nil, "OVERLAY")
                    titleFS:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
                    titleFS:SetJustifyH("LEFT")
                    titleFS:SetPoint("TOPLEFT", UM.anchorDropdownFrame, "TOPLEFT", 10, ddY - 4)
                    if fbPick then
                        titleFS:SetTextColor(1, 1, 1, 0.40)
                        titleFS:SetText(EllesmereUI.L("Fallback Direction"))
                        ddY = ddY - 18
                    elseif ovPick then
                        titleFS:SetTextColor(1, 1, 1, 0.40)
                        titleFS:SetText(EllesmereUI.L("Override Anchor Direction"))
                        ddY = ddY - 18
                    else
                        titleFS:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        titleFS:SetWidth(DD_WIDTH - 20)
                        titleFS:SetWordWrap(true)
                        if isGrowBar then
                            titleFS:SetText(EllesmereUI.L("Corner options place the bar flush with that corner of the target and set its grow direction to keep it there as bars change size."))
                        else
                            titleFS:SetText(EllesmereUI.L("After anchoring, drag to an edge and choose a grow direction to maintain its corner spot as bars change size."))
                        end
                        ddY = ddY - (titleFS:GetStringHeight() + 8)
                    end
                    local titleDiv = UM.anchorDropdownFrame:CreateTexture(nil, "ARTWORK")
                    titleDiv:SetHeight(1)
                    titleDiv:SetColorTexture(1, 1, 1, 0.10)
                    titleDiv:SetPoint("TOPLEFT", UM.anchorDropdownFrame, "TOPLEFT", 1, ddY - 2)
                    titleDiv:SetPoint("TOPRIGHT", UM.anchorDropdownFrame, "TOPRIGHT", -1, ddY - 2)
                    ddY = ddY - 5

                    local sides = { "Left", "Right", "Top", "Bottom" }
                    for _, sideName in ipairs(sides) do
                        local sideVal = string.upper(sideName)
                        local item = CreateFrame("Button", nil, UM.anchorDropdownFrame)
                        item:SetHeight(DD_ITEM_H)
                        item:SetPoint("TOPLEFT", UM.anchorDropdownFrame, "TOPLEFT", 1, ddY)
                        item:SetPoint("TOPRIGHT", UM.anchorDropdownFrame, "TOPRIGHT", -1, ddY)
                        item:SetFrameLevel(UM.anchorDropdownFrame:GetFrameLevel() + 2)
                        item:RegisterForClicks("AnyUp")
                        local hl = item:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints()
                        hl:SetColorTexture(1, 1, 1, 0)
                        local lbl = item:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                        lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        lbl:SetJustifyH("LEFT")
                        lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                        lbl:SetText(EllesmereUI.Lf(fbPick and "Fallback to %1$s" or "Anchor to %1$s", EllesmereUI.L(sideName)))
                        item:SetScript("OnEnter", function()
                            hl:SetColorTexture(1, 1, 1, 0.08)
                            lbl:SetTextColor(1, 1, 1, 1)
                        end)
                        item:SetScript("OnLeave", function()
                            hl:SetColorTexture(1, 1, 1, 0)
                            lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        end)
                        item:SetScript("OnClick", function()
                            UM.anchorDropdownFrame:Hide()
                            UM.anchorDropdownCatcher:Hide()
                            if ovPick then
                                -- Store the override link; the element only
                                -- moves while that group's override is active.
                                if EllesmereUI._SetOverrideAnchor then
                                    EllesmereUI._SetOverrideAnchor(pmKey, ovGid, targetKey, sideVal)
                                end
                                UM.hasChanges = true
                                return
                            end
                            if fbPick then
                                -- Store the fallback link; the element only
                                -- moves when the main target is absent.
                                if EllesmereUI.SetAnchorFallback then
                                    EllesmereUI.SetAnchorFallback(pmKey, targetKey, sideVal)
                                end
                                UM.hasChanges = true
                                return
                            end
                            -- Default grow direction to match the anchor side
                            -- (orientation-aware: cross-axis sides map to CENTER)
                            local isVert = false
                            if pmKey:sub(1, 4) == "CDM_" then
                                local rawCdmKey = pmKey:sub(5)
                                local cdmAddon = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
                                local cdmBars = cdmAddon and cdmAddon.db and cdmAddon.db.profile and cdmAddon.db.profile.cdmBars
                                if cdmBars and cdmBars.bars then
                                    for _, bar in ipairs(cdmBars.bars) do
                                        if bar.key == rawCdmKey then
                                            isVert = bar.verticalOrientation == true
                                            local map = isVert
                                                and { TOP = "UP", BOTTOM = "DOWN", LEFT = "CENTER", RIGHT = "CENTER" }
                                                or  { LEFT = "LEFT", RIGHT = "RIGHT", TOP = "CENTER", BOTTOM = "CENTER" }
                                            bar.growDirection = map[sideVal] or "CENTER"
                                            break
                                        end
                                    end
                                end
                            else
                                local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
                                local abBars = eab and eab.db and eab.db.profile and eab.db.profile.bars
                                local abCfg = abBars and abBars[pmKey]
                                if abCfg then
                                    isVert = (abCfg.orientation == "vertical")
                                    local map = isVert
                                        and { TOP = "up", BOTTOM = "down", LEFT = "center", RIGHT = "center" }
                                        or  { LEFT = "left", RIGHT = "right", TOP = "center", BOTTOM = "center" }
                                    abCfg.growDirection = map[sideVal] or "center"
                                end
                            end
                            -- Set anchor relationship
                            SetAnchorInfo(pmKey, targetKey, sideVal)
                            -- Apply the anchor position
                            UM.ApplyAnchorPosition(pmKey, targetKey, sideVal)
                            -- Propagate to children after layout flushes so
                            -- they read the correct bounds from the newly-anchored parent
                            C_Timer.After(0, function() UM.PropagateAnchorChain(pmKey) end)
                            UM.hasChanges = true
                            -- Refresh the anchored mover's text
                            if movers[pmKey] and movers[pmKey].RefreshAnchoredText then
                                movers[pmKey]:RefreshAnchoredText()
                            end
                            -- Sync mover position to follow the element after anchor placement
                            DeferMoverSync(movers[pmKey], function(m) m:Sync() end, UM.GetBarFrame(pmKey))
                        end)
                        ddY = ddY - DD_ITEM_H
                    end

                    -- Corner rows (growth bars, primary anchor only): the bar sits flush
                    -- with that corner of the target and grows away from it. Nothing new
                    -- in the record -- it is the side pick above, the flush drag and the
                    -- cog's Grow row in one click. A corner reads by the bar's
                    -- orientation: a horizontal bar sits above or below the target
                    -- (Top/Bottom) with the named edges flush and grows away from them; a
                    -- vertical bar sits beside it (Left/Right) the same way. So the four
                    -- rows cover exactly the sides the picks above leave centered.
                    if isGrowBar then
                        local divC = UM.anchorDropdownFrame:CreateTexture(nil, "ARTWORK")
                        divC:SetHeight(1)
                        divC:SetColorTexture(1, 1, 1, 0.10)
                        divC:SetPoint("TOPLEFT", UM.anchorDropdownFrame, "TOPLEFT", 1, ddY - 4)
                        divC:SetPoint("TOPRIGHT", UM.anchorDropdownFrame, "TOPRIGHT", -1, ddY - 4)
                        ddY = ddY - 9
                        local corners = {
                            { label = EllesmereUI.L("Top Left"),     v = "TOP",    h = "LEFT"  },
                            { label = EllesmereUI.L("Top Right"),    v = "TOP",    h = "RIGHT" },
                            { label = EllesmereUI.L("Bottom Left"),  v = "BOTTOM", h = "LEFT"  },
                            { label = EllesmereUI.L("Bottom Right"), v = "BOTTOM", h = "RIGHT" },
                        }
                        for _, corner in ipairs(corners) do
                            local item = CreateFrame("Button", nil, UM.anchorDropdownFrame)
                            item:SetHeight(DD_ITEM_H)
                            item:SetPoint("TOPLEFT", UM.anchorDropdownFrame, "TOPLEFT", 1, ddY)
                            item:SetPoint("TOPRIGHT", UM.anchorDropdownFrame, "TOPRIGHT", -1, ddY)
                            item:SetFrameLevel(UM.anchorDropdownFrame:GetFrameLevel() + 2)
                            item:RegisterForClicks("AnyUp")
                            local hl = item:CreateTexture(nil, "ARTWORK")
                            hl:SetAllPoints()
                            hl:SetColorTexture(1, 1, 1, 0)
                            local lbl = item:CreateFontString(nil, "OVERLAY")
                            lbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                            lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                            lbl:SetJustifyH("LEFT")
                            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                            lbl:SetText(EllesmereUI.Lf("Anchor to %1$s", corner.label))
                            item:SetScript("OnEnter", function()
                                hl:SetColorTexture(1, 1, 1, 0.08)
                                lbl:SetTextColor(1, 1, 1, 1)
                            end)
                            item:SetScript("OnLeave", function()
                                hl:SetColorTexture(1, 1, 1, 0)
                                lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                            end)
                            item:SetScript("OnClick", function()
                                UM.anchorDropdownFrame:Hide()
                                UM.anchorDropdownCatcher:Hide()
                                -- Orientation, the same lookups as the side pick. The bar is
                                -- placed on centered growth first (the side pick's own default
                                -- for this side): a held growth edge would otherwise pin the
                                -- bar to where it stood before the anchor moved it.
                                local isVert = false
                                if pmKey:sub(1, 4) == "CDM_" then
                                    local rawCdmKey = pmKey:sub(5)
                                    local cdmAddon = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
                                    local cdmBars = cdmAddon and cdmAddon.db and cdmAddon.db.profile and cdmAddon.db.profile.cdmBars
                                    if cdmBars and cdmBars.bars then
                                        for _, bar in ipairs(cdmBars.bars) do
                                            if bar.key == rawCdmKey then
                                                isVert = bar.verticalOrientation == true
                                                bar.growDirection = "CENTER"
                                                break
                                            end
                                        end
                                    end
                                else
                                    local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
                                    local abBars = eab and eab.db and eab.db.profile and eab.db.profile.bars
                                    local abCfg = abBars and abBars[pmKey]
                                    if abCfg then
                                        isVert = (abCfg.orientation == "vertical")
                                        abCfg.growDirection = "center"
                                    end
                                end
                                -- The side the corner means, the edge held flush along it and
                                -- the direction that grows away from that edge.
                                local sideVal = isVert and corner.h or corner.v
                                local flush = isVert and corner.v or corner.h
                                local growVal
                                if isVert then
                                    growVal = (flush == "TOP") and "DOWN" or "UP"
                                else
                                    growVal = (flush == "RIGHT") and "LEFT" or "RIGHT"
                                end
                                -- Flush edges: the side pick centers the bar along the side, so
                                -- the shift is half the size difference (UIParent units,
                                -- pixel-snapped like the side pick's own offsets). Sizes, not
                                -- rects: the target's bounds are read before anything moves.
                                local offX, offY = 0, 0
                                local childF, targetF = UM.GetBarFrame(pmKey), UM.GetBarFrame(targetKey)
                                if childF and targetF then
                                    local uiS = UIParent:GetEffectiveScale()
                                    local cS, tS = childF:GetEffectiveScale() / uiS, targetF:GetEffectiveScale() / uiS
                                    local snap = (EllesmereUI.PP and EllesmereUI.PP.Snap) or function(v) return math.floor(v + 0.5) end
                                    if isVert then
                                        local half = ((targetF:GetHeight() or 0) * tS - (childF:GetHeight() or 0) * cS) / 2
                                        offY = snap((flush == "TOP") and half or -half)
                                    else
                                        local half = ((targetF:GetWidth() or 0) * tS - (childF:GetWidth() or 0) * cS) / 2
                                        offX = snap((flush == "RIGHT") and half or -half)
                                    end
                                end
                                -- Set anchor relationship, flush offsets included (the record a
                                -- side pick plus a drag to the edge leaves behind)
                                SetAnchorInfo(pmKey, targetKey, sideVal, offX, offY)
                                -- A screen edge the element holds on the flush axis would win
                                -- that axis on every apply and undo the alignment just asked
                                -- for: release it, the Relative-to-Screen clear path's way.
                                local aiC = GetAnchorInfo(pmKey)
                                if aiC and aiC.edge and aiC.edge.key and EllesmereUI._ScreenEdgeAxis
                                   and EllesmereUI._ScreenEdgeAxis(aiC.edge.key) == (isVert and "Y" or "X") then
                                    aiC.edge = nil
                                    EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
                                end
                                -- Apply the anchor position
                                UM.ApplyAnchorPosition(pmKey, targetKey, sideVal)
                                -- Grow away from the flush edge, after the placement: the
                                -- growth-edge hold captures from where the bar now sits.
                                EllesmereUI._unlockSetGrowDirection(pmKey, growVal)
                                -- Propagate to children after layout flushes so
                                -- they read the correct bounds from the newly-anchored parent
                                C_Timer.After(0, function() UM.PropagateAnchorChain(pmKey) end)
                                UM.hasChanges = true
                                -- Refresh the anchored mover's text
                                if movers[pmKey] and movers[pmKey].RefreshAnchoredText then
                                    movers[pmKey]:RefreshAnchoredText()
                                end
                                -- Sync mover position to follow the element after anchor placement
                                DeferMoverSync(movers[pmKey], function(m) m:Sync() end, UM.GetBarFrame(pmKey))
                            end)
                            ddY = ddY - DD_ITEM_H
                        end
                    end

                    -- "Remove Anchor" option if already anchored
                    if not fbPick and IsAnchored(pmKey) then
                        local divR = UM.anchorDropdownFrame:CreateTexture(nil, "ARTWORK")
                        divR:SetHeight(1)
                        divR:SetColorTexture(1, 1, 1, 0.10)
                        divR:SetPoint("TOPLEFT", UM.anchorDropdownFrame, "TOPLEFT", 1, ddY - 4)
                        divR:SetPoint("TOPRIGHT", UM.anchorDropdownFrame, "TOPRIGHT", -1, ddY - 4)
                        ddY = ddY - 9

                        local removeItem = CreateFrame("Button", nil, UM.anchorDropdownFrame)
                        removeItem:SetHeight(DD_ITEM_H)
                        removeItem:SetPoint("TOPLEFT", UM.anchorDropdownFrame, "TOPLEFT", 1, ddY)
                        removeItem:SetPoint("TOPRIGHT", UM.anchorDropdownFrame, "TOPRIGHT", -1, ddY)
                        removeItem:SetFrameLevel(UM.anchorDropdownFrame:GetFrameLevel() + 2)
                        removeItem:RegisterForClicks("AnyUp")
                        local rHl = removeItem:CreateTexture(nil, "ARTWORK")
                        rHl:SetAllPoints()
                        rHl:SetColorTexture(1, 1, 1, 0)
                        local rLbl = removeItem:CreateFontString(nil, "OVERLAY")
                        rLbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                        rLbl:SetTextColor(0.9, 0.3, 0.3, 0.9)
                        rLbl:SetJustifyH("LEFT")
                        rLbl:SetPoint("LEFT", removeItem, "LEFT", 10, 0)
                        rLbl:SetText(EllesmereUI.L("Remove Anchor"))
                        removeItem:SetScript("OnEnter", function()
                            rHl:SetColorTexture(1, 1, 1, 0.08)
                            rLbl:SetTextColor(1, 0.4, 0.4, 1)
                        end)
                        removeItem:SetScript("OnLeave", function()
                            rHl:SetColorTexture(1, 1, 1, 0)
                            rLbl:SetTextColor(0.9, 0.3, 0.3, 0.9)
                        end)
                        removeItem:SetScript("OnClick", function()
                            UM.anchorDropdownFrame:Hide()
                            UM.anchorDropdownCatcher:Hide()
                            ClearAnchorInfo(pmKey)
                            UM.hasChanges = true
                            if movers[pmKey] and movers[pmKey].RefreshAnchoredText then
                                movers[pmKey]:RefreshAnchoredText()
                            end
                        end)
                        ddY = ddY - DD_ITEM_H
                    end

                    UM.anchorDropdownFrame:SetHeight(-ddY + 4)
                    UM.anchorDropdownFrame:Show()
                    UM.anchorDropdownCatcher:Show()
                    return
                end
            end

            -- Select Element pick mode: clicking a different mover sets it as snap target
            if UM.selectElementPicker and UM.selectElementPicker ~= self then
                local picker = UM.selectElementPicker
                picker._snapTarget = self._barKey
                picker._preSelectTarget = nil
                UM.selectElementPicker = nil
                FadeOverlayForSelectElement(false)
                -- Restore this mover's normal colors
                self._brd:SetColor(ar, ag, ab, 0.6)
                if not UM.darkOverlaysEnabled then self:SetAlpha(MOVER_ALPHA) end
                -- Update the picker's dropdown label
                if picker._updateSnapLabel then picker._updateSnapLabel() end
                return
            end
            -- Toggle: clicking the already-selected mover deselects it
            if UM.selectedMover == self then
                DeselectMover()
            else
                SelectMover(self)
            end
        elseif button == "RightButton" then
            if UM.selectElementPicker then return end
            -- Shift+Right Click temporarily hides this element's overlay for the
            -- current unlock session. The _tempHidden flag is cleared when unlock
            -- mode is next entered, so the overlay reappears then. Purely a visual
            -- toggle on the overlay -- it never touches the underlying element.
            if IsShiftKeyDown() then
                self._tempHidden = true
                self._hoverPending = false
                if UM.selectedMover == self then DeselectMover() end
                if UM.hoveredMover == self then UM.hoveredMover = nil end
                if self._hideOverlayText then self._hideOverlayText() end
                -- Hide the cog too; its OnHide closes any open cog menu.
                if self._cogBtn then self._cogBtn:Hide() end
                self:Hide()
                return
            end
            SelectMover(self)
            if self._openCogMenu then self._openCogMenu() end
        end
    end)
    mover:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    ---------------------------------------------------------------------------
    --  Action toolbar: cog settings button only
    --  Cog is flush with mover's top-right corner.
    ---------------------------------------------------------------------------
    local ICON_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
    local ARROW_ICON  = ICON_PATH .. "eui-arrow.png"
    local ARROW_RIGHT_ICON = ICON_PATH .. "right-arrow.png"
    local COGS_ICON   = EllesmereUI.COGS_ICON or (ICON_PATH .. "cogs-3.png")
    local ACT_SZ = 22       -- cog button size
    local ACT_PAD = 3       -- gap between cog and dropdown
    local DD_W = 150        -- dropdown width

    -- Cog settings button (opens a dropdown with Reset / Center / Orientation)
    cogBtn = CreateFrame("Button", nil, UM.unlockFrame)
    cogBtn:SetFrameLevel(mover:GetFrameLevel() + 10)
    cogBtn:RegisterForClicks("AnyUp")
    cogBtn:EnableMouse(true)
    cogBtn:SetSize(ACT_SZ, ACT_SZ)
    do
        local bg = cogBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.103, 0.095, 0.088, 0.9)
        cogBtn._bg = bg
        local brd = EllesmereUI.MakeBorder(cogBtn, 1, 1, 1, 0.20)
        cogBtn._brd = brd
        local icon = cogBtn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("CENTER")
        icon:SetTexture(COGS_ICON)
        icon:SetAlpha(0.7)
        cogBtn._icon = icon
        cogBtn:SetScript("OnEnter", function(self)
            self._bg:SetColorTexture(0.103, 0.095, 0.088, 0.98)
            self._brd:SetColor(1, 1, 1, 0.30)
            self._icon:SetAlpha(1)
            mover:SetFrameLevel(mover._raisedLevel + 100)
            mover._brd:SetColor(1, 1, 1, 0.9)
            if not UM.darkOverlaysEnabled then mover:SetAlpha(MOVER_HOVER) end
        end)
        cogBtn:SetScript("OnLeave", function(self)
            self._bg:SetColorTexture(0.103, 0.095, 0.088, 0.9)
            self._brd:SetColor(1, 1, 1, 0.20)
            self._icon:SetAlpha(0.7)
        end)
    end
    cogBtn:Hide()

    -- Cog visibility is now tied to the hover animation.
    -- Show/hide helpers are simple wrappers.
    local function ShowCogForHover() end
    local function HideCogAfterDelay() end
    local function HideCogImmediate() end

    mover._showCogForHover = ShowCogForHover
    mover._hideCogAfterDelay = HideCogAfterDelay
    mover._hideCogImmediate = HideCogImmediate

    -- Re-set cogBtn hover scripts now that fade helpers are in scope
    cogBtn:SetScript("OnEnter", function(self)
        self._bg:SetColorTexture(0.103, 0.095, 0.088, 0.98)
        self._brd:SetColor(1, 1, 1, 0.30)
        self._icon:SetAlpha(1)
        -- Restore mover highlight immediately (mover:OnLeave resets it when mouse moves to cog)
        mover:SetFrameLevel(mover._raisedLevel + 100)
        mover._brd:SetColor(1, 1, 1, 0.9)
        if not UM.darkOverlaysEnabled then mover:SetAlpha(MOVER_HOVER) end
    end)
    cogBtn:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0.103, 0.095, 0.088, 0.9)
        self._brd:SetColor(1, 1, 1, 0.20)
        self._icon:SetAlpha(0.7)
    end)

    ---------------------------------------------------------------------------
    --  Snap-to dropdown (custom styled, per-mover memory)
    ---------------------------------------------------------------------------
    local snapDD = CreateFrame("Button", nil, UM.unlockFrame)
    snapDD:SetFrameLevel(mover:GetFrameLevel() + 10)
    snapDD:RegisterForClicks("AnyUp")
    snapDD:EnableMouse(true)
    snapDD:SetSize(DD_W, 30)
    local snapDDBg = snapDD:CreateTexture(nil, "BACKGROUND")
    snapDDBg:SetAllPoints()
    snapDDBg:SetColorTexture(0.103, 0.095, 0.088, 0.9)
    snapDD._bg = snapDDBg
    local snapDDBrd = EllesmereUI.MakeBorder(snapDD, 1, 1, 1, 0.20)
    snapDD._brd = snapDDBrd
    local snapDDLbl = snapDD:CreateFontString(nil, "OVERLAY")
    snapDDLbl:SetFont(FONT_PATH, 12, "OUTLINE, SLUG")
    snapDDLbl:SetTextColor(1, 1, 1, 0.50)
    snapDDLbl:SetJustifyH("LEFT")
    snapDDLbl:SetWordWrap(false)
    snapDDLbl:SetMaxLines(1)
    snapDDLbl:SetPoint("LEFT", snapDD, "LEFT", 8, 0)
    snapDDLbl:SetText(EllesmereUI.L("Snap to: Auto"))
    local snapDDArrow = EllesmereUI.MakeDropdownArrow(snapDD, 12)
    snapDDLbl:SetPoint("RIGHT", snapDDArrow, "LEFT", -5, 0)
    snapDD:SetScript("OnEnter", function(self)
        if not UM.snapEnabled then
            -- Grayed out: show tooltip explaining why
            EllesmereUI.ShowWidgetTooltip(self, "This feature requires Snap Elements to be enabled")
            return
        end
        self._bg:SetColorTexture(0.103, 0.095, 0.088, 0.98)
        self._brd:SetColor(1, 1, 1, 0.30)
        snapDDLbl:SetTextColor(1, 1, 1, 0.60)
    end)
    snapDD:SetScript("OnLeave", function(self)
        EllesmereUI.HideWidgetTooltip()
        if not UM.snapEnabled then return end
        self._bg:SetColorTexture(0.103, 0.095, 0.088, 0.9)
        self._brd:SetColor(1, 1, 1, 0.20)
        snapDDLbl:SetTextColor(1, 1, 1, 0.50)
    end)
    snapDD:Hide()

    -- Helper: apply grayed-out or normal visual state to the dropdown
    local function RefreshSnapDDState()
        if not UM.snapEnabled then
            snapDDBg:SetColorTexture(0.103, 0.095, 0.088, 0.50)
            snapDDBrd:SetColor(1, 1, 1, 0.07)
            snapDDLbl:SetTextColor(1, 1, 1, 0.20)
            snapDDArrow:SetAlpha(0.10)
        else
            snapDDBg:SetColorTexture(0.103, 0.095, 0.088, 0.9)
            snapDDBrd:SetColor(1, 1, 1, 0.20)
            snapDDLbl:SetTextColor(1, 1, 1, 0.50)
            snapDDArrow:SetAlpha(1)
        end
    end
    mover._refreshSnapDD = RefreshSnapDDState

    -- Snap dropdown menu frame (lazy-created, shared across this mover)
    local snapMenu
    local regSubMenus = {}

    local function CloseSnapMenu()
        if snapMenu then snapMenu:Hide() end
        for _, rs in pairs(regSubMenus) do
            if rs and rs.Hide then rs:Hide() end
        end
    end

    local function UpdateSnapLabel()
        local tgt = mover._snapTarget
        if tgt == "_disable_" then
            snapDDLbl:SetText(EllesmereUI.L("Snap to: None"))
        elseif tgt == "_select_" then
            snapDDLbl:SetText(EllesmereUI.L("Snap to: Select Element"))
        elseif tgt then
            local lbl = UM.GetBarLabel(tgt)
            snapDDLbl:SetText(EllesmereUI.Lf("Snap to: %1$s", lbl or tgt))
        else
            snapDDLbl:SetText(EllesmereUI.L("Snap to: All Elements"))
        end
        -- Update snap highlight to match new target
        if mover._selected then
            if tgt and tgt ~= "_disable_" and tgt ~= "_select_" and movers[tgt] then
                ShowSnapHighlight(tgt)
            else
                ClearSnapHighlight()
            end
        end
    end

    local function BuildSnapMenu()
        if snapMenu then
            -- Rebuild items
            for _, child in ipairs({snapMenu:GetChildren()}) do child:Hide(); child:SetParent(nil) end
            for _, tex in ipairs({snapMenu:GetRegions()}) do if tex.Hide then tex:Hide() end end
        end
        snapMenu = snapMenu or CreateFrame("Frame", nil, UM.unlockFrame)
        snapMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        snapMenu:SetFrameLevel(250)
        snapMenu:SetClampedToScreen(true)
        snapMenu:SetSize(DD_W, 10)
        snapMenu:SetPoint("TOPLEFT", mover, "TOPRIGHT", 4, 0)

        -- Background + border
        local menuBg = snapMenu:CreateTexture(nil, "BACKGROUND")
        menuBg:SetAllPoints()
        menuBg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
        EllesmereUI.MakeBorder(snapMenu, 1, 1, 1, 0.20)

        local ITEM_H = 24
        local yOff = -4
        local items = {}

        -- Title: "Snap Target"
        local titleLbl = snapMenu:CreateFontString(nil, "OVERLAY")
        titleLbl:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
        titleLbl:SetTextColor(1, 1, 1, 0.40)
        titleLbl:SetJustifyH("LEFT")
        titleLbl:SetPoint("TOPLEFT", snapMenu, "TOPLEFT", 10, yOff - 4)
        titleLbl:SetText(EllesmereUI.L("Snap Target"))
        yOff = yOff - 18

        -- Title divider
        local titleDiv = snapMenu:CreateTexture(nil, "ARTWORK")
        titleDiv:SetHeight(1)
        titleDiv:SetColorTexture(1, 1, 1, 0.10)
        titleDiv:SetPoint("TOPLEFT", snapMenu, "TOPLEFT", 1, yOff - 2)
        titleDiv:SetPoint("TOPRIGHT", snapMenu, "TOPRIGHT", -1, yOff - 2)
        yOff = yOff - 5

        local function MakeItem(parent, text, onClick, isSelected)
            local item = CreateFrame("Button", nil, parent)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, yOff)
            item:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, yOff)
            item:SetFrameLevel(parent:GetFrameLevel() + 2)
            item:RegisterForClicks("AnyUp")
            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0)
            local lbl = item:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
            lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            lbl:SetJustifyH("LEFT")
            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
            lbl:SetText(EllesmereUI.L(text))
            if isSelected then
                hl:SetColorTexture(1, 1, 1, 0.04)
                lbl:SetTextColor(1, 1, 1, 1)
            end
            item:SetScript("OnEnter", function()
                hl:SetColorTexture(1, 1, 1, 0.08)
                lbl:SetTextColor(1, 1, 1, 1)
            end)
            item:SetScript("OnLeave", function()
                if isSelected then
                    hl:SetColorTexture(1, 1, 1, 0.04)
                else
                    hl:SetColorTexture(1, 1, 1, 0)
                end
                lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            end)
            item:SetScript("OnClick", function()
                onClick()
                CloseSnapMenu()
                UpdateSnapLabel()
            end)
            items[#items + 1] = item
            yOff = yOff - ITEM_H
            return item
        end

        local curTarget = mover._snapTarget

        MakeItem(snapMenu, "All Elements", function()
            mover._snapTarget = nil
        end, not curTarget)

        -- None (per-mover snap disable)
        MakeItem(snapMenu, "None", function()
            mover._snapTarget = "_disable_"
        end, curTarget == "_disable_")

        -- Divider before element groups
        local div = snapMenu:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetColorTexture(1, 1, 1, 0.10)
        div:SetPoint("TOPLEFT", snapMenu, "TOPLEFT", 1, yOff - 4)
        div:SetPoint("TOPRIGHT", snapMenu, "TOPRIGHT", -1, yOff - 4)
        yOff = yOff - 9

        -- Registered element groups (Unit Frames, Action Bars, Resource Bars, etc.)
        RebuildRegisteredOrder()
        local regGroups = {}   -- { groupName = { {key,label}, ... } }
        local regGroupOrder = {} -- preserve first-seen order
        for _, rk in ipairs(registeredOrder) do
            if rk ~= barKey and movers[rk] and movers[rk]:IsShown() then
                local elem = registeredElements[rk]
                local gName = elem.group or "Other"
                if not regGroups[gName] then
                    regGroups[gName] = {}
                    regGroupOrder[#regGroupOrder + 1] = gName
                end
                regGroups[gName][#regGroups[gName] + 1] = { key = rk, label = elem.label or rk }
            end
        end
        -- Add visibility-only bars (MicroBar, BagBar) to "Other" group
        for _, bk in ipairs(ALL_BAR_ORDER) do
            if GetVisibilityOnly()[bk] and bk ~= barKey and movers[bk] and movers[bk]:IsShown() then
                if not regGroups["Other"] then
                    regGroups["Other"] = {}
                    regGroupOrder[#regGroupOrder + 1] = "Other"
                end
                regGroups["Other"][#regGroups["Other"] + 1] = { key = bk, label = UM.GetBarLabel(bk) }
            end
        end
        wipe(regSubMenus)
        for _, gName in ipairs(regGroupOrder) do
            local gElems = regGroups[gName]
            local rgItem = CreateFrame("Button", nil, snapMenu)
            rgItem:SetHeight(ITEM_H)
            rgItem:SetPoint("TOPLEFT", snapMenu, "TOPLEFT", 1, yOff)
            rgItem:SetPoint("TOPRIGHT", snapMenu, "TOPRIGHT", -1, yOff)
            rgItem:SetFrameLevel(snapMenu:GetFrameLevel() + 2)
            rgItem:RegisterForClicks("AnyUp")
            local rgHl = rgItem:CreateTexture(nil, "ARTWORK")
            rgHl:SetAllPoints()
            rgHl:SetColorTexture(1, 1, 1, 0)
            local rgLbl = rgItem:CreateFontString(nil, "OVERLAY")
            rgLbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
            rgLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            rgLbl:SetJustifyH("LEFT")
            rgLbl:SetPoint("LEFT", rgItem, "LEFT", 10, 0)
            rgLbl:SetText(EllesmereUI.L(gName))
            local rgArrow = rgItem:CreateTexture(nil, "ARTWORK")
            rgArrow:SetSize(10, 10)
            rgArrow:SetPoint("RIGHT", rgItem, "RIGHT", -8, 0)
            rgArrow:SetTexture(ARROW_RIGHT_ICON)
            rgArrow:SetAlpha(0.7)
            yOff = yOff - ITEM_H

            local regSub
            local function ShowRegSub()
                -- Close any other open leaf sub-menus first
                for otherName, rs in pairs(regSubMenus) do
                    if otherName ~= gName and rs and rs:IsShown() then rs:Hide() end
                end
                if regSub then
                    for _, child in ipairs({regSub:GetChildren()}) do child:Hide(); child:SetParent(nil) end
                    for _, tex in ipairs({regSub:GetRegions()}) do if tex.Hide then tex:Hide() end end
                end
                regSub = regSub or CreateFrame("Frame", nil, UM.unlockFrame)
                regSub:SetFrameStrata("FULLSCREEN_DIALOG")
                regSub:SetFrameLevel(260)
                regSub:SetClampedToScreen(true)
                regSub:SetSize(DD_W, 10)
                regSub:SetPoint("TOPLEFT", rgItem, "TOPRIGHT", 2, 0)
                local rsBg = regSub:CreateTexture(nil, "BACKGROUND")
                rsBg:SetAllPoints()
                rsBg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
                EllesmereUI.MakeBorder(regSub, 1, 1, 1, 0.20)
                local rsYOff = -4
                for _, eInfo in ipairs(gElems) do
                    local ek, eLbl = eInfo.key, eInfo.label
                    local isSel = (curTarget == ek)
                    local si = CreateFrame("Button", nil, regSub)
                    si:SetHeight(ITEM_H)
                    si:SetPoint("TOPLEFT", regSub, "TOPLEFT", 1, rsYOff)
                    si:SetPoint("TOPRIGHT", regSub, "TOPRIGHT", -1, rsYOff)
                    si:SetFrameLevel(regSub:GetFrameLevel() + 2)
                    si:RegisterForClicks("AnyUp")
                    local sHl = si:CreateTexture(nil, "ARTWORK")
                    sHl:SetAllPoints()
                    sHl:SetColorTexture(1, 1, 1, isSel and 0.04 or 0)
                    local sLbl = si:CreateFontString(nil, "OVERLAY")
                    sLbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                    sLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    sLbl:SetJustifyH("LEFT")
                    sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                    sLbl:SetText(EllesmereUI.L(eLbl))
                    if isSel then sLbl:SetTextColor(1, 1, 1, 1) end
                    si:SetScript("OnEnter", function()
                        sHl:SetColorTexture(1, 1, 1, 0.08)
                        sLbl:SetTextColor(1, 1, 1, 1)
                    end)
                    si:SetScript("OnLeave", function()
                        sHl:SetColorTexture(1, 1, 1, isSel and 0.04 or 0)
                        sLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    end)
                    si:SetScript("OnClick", function()
                        mover._snapTarget = ek
                        CloseSnapMenu()
                        UpdateSnapLabel()
                    end)
                    rsYOff = rsYOff - ITEM_H
                end
                regSub:SetHeight(-rsYOff + 4)
                -- Width: fit the widest label + left padding (10) + right spacing (10) + border (2)
                local rsMaxW = DD_W
                for _, eInfo in ipairs(gElems) do
                    local tw = (EllesmereUI.MeasureText and EllesmereUI.MeasureText(eInfo.label, FONT_PATH, 11)) or 0
                    local needed = 10 + tw + 10 + 2
                    if needed > rsMaxW then rsMaxW = needed end
                end
                regSub:SetWidth(rsMaxW)
                regSub:EnableMouse(true)
                regSub:SetScript("OnLeave", function(self)
                    C_Timer.After(0.05, function()
                        if self:IsShown() and not self:IsMouseOver() and not rgItem:IsMouseOver() then
                            self:Hide()
                        end
                    end)
                end)
                regSub:Show()
                regSubMenus[gName] = regSub
            end

            rgItem:SetScript("OnEnter", function()
                rgHl:SetColorTexture(1, 1, 1, 0.08)
                rgLbl:SetTextColor(1, 1, 1, 1)
                rgArrow:SetAlpha(0.9)
                ShowRegSub()
            end)
            rgItem:SetScript("OnLeave", function()
                rgHl:SetColorTexture(1, 1, 1, 0)
                rgLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                rgArrow:SetAlpha(0.5)
                C_Timer.After(0.05, function()
                    local rs = regSubMenus[gName]
                    if rs and rs:IsShown() and not rs:IsMouseOver() and not rgItem:IsMouseOver() then
                        rs:Hide()
                    end
                end)
            end)
        end

        snapMenu:SetHeight(-yOff + 4)
        snapMenu:Show()
    end

    -- Click-catcher: full-screen invisible frame that closes the menu when clicking elsewhere
    local snapClickCatcher
    local function ShowClickCatcher()
        if not snapClickCatcher then
            snapClickCatcher = CreateFrame("Button", nil, UM.unlockFrame)
            snapClickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            snapClickCatcher:SetFrameLevel(249)  -- just below snapMenu (250)
            snapClickCatcher:SetAllPoints(UIParent)
            snapClickCatcher:RegisterForClicks("AnyUp")
            snapClickCatcher:SetScript("OnClick", function()
                CloseSnapMenu()
            end)
        end
        snapClickCatcher:Show()
    end
    local function HideClickCatcher()
        if snapClickCatcher then snapClickCatcher:Hide() end
    end

    local origCloseSnapMenu = CloseSnapMenu
    CloseSnapMenu = function()
        origCloseSnapMenu()
        HideClickCatcher()
        mover._menuOpen = false
    end

    snapDD:SetScript("OnClick", function()
        -- Block opening when global snap is disabled
        if not UM.snapEnabled then return end
        if snapMenu and snapMenu:IsShown() then
            CloseSnapMenu()
        else
            mover._menuOpen = true
            BuildSnapMenu()
            ShowClickCatcher()
        end
    end)

    -- Also close menu when dropdown hides (e.g. mover deselected)
    snapDD:SetScript("OnHide", CloseSnapMenu)

    ---------------------------------------------------------------------------
    --  Layout: cog flush with mover top-right (flips below if near screen top)
    ---------------------------------------------------------------------------
    local TOOLBAR_FLIP_THRESHOLD = 50  -- px from screen top to flip toolbar below

    local function IsNearScreenTop()
        local mTop = mover:GetTop()
        if not mTop then return false end
        local uiS = UIParent:GetEffectiveScale()
        local mS = mover:GetEffectiveScale()
        local screenTop = UIParent:GetHeight()
        local moverTopUI = mTop * mS / uiS
        return (screenTop - moverTopUI) < TOOLBAR_FLIP_THRESHOLD
    end
    mover._isNearScreenTop = IsNearScreenTop

    local function AnchorToolbarToMover()
        cogBtn:ClearAllPoints()
        cogBtn:SetPoint("TOPRIGHT", mover, "TOPRIGHT", -1, -1)
    end
    mover._anchorToolbar = AnchorToolbarToMover
    AnchorToolbarToMover()

    -- Hide orientation button for visibility-only bars or bars without layout support
    local isVisOnly = (GetVisibilityOnly()[barKey]) or not (BAR_LOOKUP and BAR_LOOKUP[barKey])

    mover._cogBtn = cogBtn
    mover._actionBtns = { cogBtn }

    -- Open snap menu helper (called from right-click handler)
    mover._openSnapMenu = function()
        mover._menuOpen = true
        BuildSnapMenu()
        ShowClickCatcher()
    end
    mover._isVisOnly = isVisOnly
    mover._snapTarget = nil  -- per-mover snap target (nil = auto)
    mover._updateSnapLabel = UpdateSnapLabel
    RefreshSnapDDState()  -- apply initial grayed-out state if snap is disabled

    ---------------------------------------------------------------------------
    --  Cog settings menu (Reset / Center / Orientation)
    ---------------------------------------------------------------------------
    local cogMenu
    local cogClickCatcher

    local function CloseCogMenu()
        if cogMenu then cogMenu:Hide() end
        if mover._cogEdgeSub then mover._cogEdgeSub:Hide() end
        if cogClickCatcher then cogClickCatcher:Hide() end
        mover._menuOpen = false
        mover._syncCogPos = nil
        mover._syncCogSize = nil
    end

    local function BuildCogMenu()
        if cogMenu then
            for _, child in ipairs({cogMenu:GetChildren()}) do child:Hide(); child:SetParent(nil) end
            for _, tex in ipairs({cogMenu:GetRegions()}) do if tex.Hide then tex:Hide() end end
        end
        if mover._cogEdgeSub then mover._cogEdgeSub:Hide() end
        cogMenu = cogMenu or CreateFrame("Frame", nil, UM.unlockFrame)
        cogMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        cogMenu:SetFrameLevel(250)
        cogMenu:SetClampedToScreen(true)
        cogMenu:SetSize(DD_W + 60, 10)
        cogMenu:SetPoint("TOPLEFT", cogBtn, "BOTTOMLEFT", 0, -2)
        cogMenu:EnableMouse(true)

        local menuBg = cogMenu:CreateTexture(nil, "BACKGROUND")
        menuBg:SetAllPoints()
        menuBg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
        EllesmereUI.MakeBorder(cogMenu, 1, 1, 1, 0.20)

        local ITEM_H = 24
        local yOff = -4

        -- Arrow-key hint at the very top (centered). Shown for every element since
        -- arrow keys nudge the selected element 1px in any direction.
        do
            local hintFS = cogMenu:CreateFontString(nil, "OVERLAY")
            EllesmereUI.PrimeFontShadow(hintFS, true)
            hintFS:SetFont(FONT_PATH, 10, "")
            hintFS:SetTextColor(0.7, 0.7, 0.7, 0.85)
            hintFS:SetJustifyH("CENTER")
            hintFS:SetWordWrap(true)
            hintFS:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 8, yOff - 4)
            hintFS:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -8, yOff - 4)
            hintFS:SetText(EllesmereUI.L("Use arrow keys to move selected element 1px any direction")
                .. ". " .. EllesmereUI.L("Shift+Right Click to temporarily hide overlay"))
            local hintH = hintFS:GetStringHeight()
            if not hintH or hintH < 1 then hintH = 28 end
            yOff = yOff - (hintH + 10)

            -- Divider below the hint
            local hintDiv = cogMenu:CreateTexture(nil, "ARTWORK")
            local hintDivPx = PP and PP.mult or 1
            hintDiv:SetHeight(hintDivPx)
            if hintDiv.SetSnapToPixelGrid then hintDiv:SetSnapToPixelGrid(false); hintDiv:SetTexelSnappingBias(0) end
            hintDiv:SetColorTexture(1, 1, 1, 0.10)
            hintDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
            hintDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
            yOff = yOff - 9
        end

        -- "Element Options" -- navigate to this element's settings page (top of menu)
        local settingsMapping = EllesmereUI._ELEMENT_SETTINGS_MAP[barKey]
        -- Cooldown Manager bars use dynamic per-bar keys ("CDM_<key>" / "TBB_<idx>"),
        -- so they miss the exact lookup; resolve them to their shared tab entry by prefix.
        if not settingsMapping then
            if barKey:sub(1, 4) == "CDM_" then
                settingsMapping = EllesmereUI._ELEMENT_SETTINGS_MAP["CDM_"]
            elseif barKey:sub(1, 4) == "TBB_" or barKey:sub(1, 5) == "TBBG_" then
                settingsMapping = EllesmereUI._ELEMENT_SETTINGS_MAP["TBB_"]
            elseif barKey:sub(1, 7) == "EDM_Win" then
                settingsMapping = EllesmereUI._ELEMENT_SETTINGS_MAP["EDM_Win"]
            end
        end
        -- Queue Status is a Blizzard-owned element with no EUI settings page; its
        -- "Element Options" opens Blizzard Edit Mode instead of navigating to a tab
        -- (the same action as clicking a Blizzard Edit Mode overlay in unlock mode).
        local opensEditMode = (barKey == "QueueStatus")
        if settingsMapping or opensEditMode then
            local optItem = CreateFrame("Button", nil, cogMenu)
            optItem:SetHeight(ITEM_H)
            optItem:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
            optItem:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
            optItem:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
            optItem:RegisterForClicks("AnyUp")
            local optHl = optItem:CreateTexture(nil, "ARTWORK")
            optHl:SetAllPoints()
            optHl:SetColorTexture(1, 1, 1, 0)
            local optLbl = optItem:CreateFontString(nil, "OVERLAY")
            EllesmereUI.PrimeFontShadow(optLbl, true)
            optLbl:SetFont(FONT_PATH, 11, "")
            optLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            optLbl:SetJustifyH("LEFT")
            optLbl:SetPoint("LEFT", optItem, "LEFT", 10, 0)
            optLbl:SetText(EllesmereUI.L("Element Options"))
            optItem:SetScript("OnEnter", function()
                optHl:SetColorTexture(1, 1, 1, 0.08)
                optLbl:SetTextColor(1, 1, 1, 1)
            end)
            optItem:SetScript("OnLeave", function()
                optHl:SetColorTexture(1, 1, 1, 0)
                optLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            end)
            optItem:SetScript("OnClick", function()
                CloseCogMenu()
                if opensEditMode then
                    -- Open Blizzard Edit Mode, exactly as the Blizz-owned overlays do.
                    if InCombatLockdown() then return end
                    if EditModeManagerFrame then
                        ns.RequestClose(false, function()
                            ShowUIPanel(EditModeManagerFrame)
                        end)
                    end
                else
                    ns.RequestClose(true, function()
                        EllesmereUI:NavigateToElementSettings(
                            settingsMapping.module,
                            settingsMapping.page,
                            settingsMapping.sectionName,
                            settingsMapping.preSelectFn,
                            settingsMapping.highlightText
                        )
                    end)
                end
            end)
            yOff = yOff - ITEM_H

            -- Divider after Element Options
            local optDiv = cogMenu:CreateTexture(nil, "ARTWORK")
            local optDivPx = PP and PP.mult or 1
            optDiv:SetHeight(optDivPx)
            if optDiv.SetSnapToPixelGrid then optDiv:SetSnapToPixelGrid(false); optDiv:SetTexelSnappingBias(0) end
            optDiv:SetColorTexture(1, 1, 1, 0.10)
            optDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
            optDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
            yOff = yOff - 9
        end

        -- Width / Height input fields (only for resizable elements)
        -- CDM bars skip width/height here; size is driven by icon count/size in the options panel
        local isCDMBar = barKey:sub(1, 4) == "CDM_"
        if canResize and elem then
            local INPUT_W = 50
            local INPUT_H = 18
            local ROW_H = 22
            local curW, curH = 0, 0
            if elem.getSize then curW, curH = elem.getSize(barKey) end

            -- Create both boxes upfront so each OnEnterPressed can update the other
            local wBox, hBox

            local function MakeSizeRow(axis, initVal)
                local rowFrame = CreateFrame("Frame", nil, cogMenu)
                rowFrame:SetHeight(ROW_H)
                rowFrame:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
                rowFrame:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
                rowFrame:SetFrameLevel(cogMenu:GetFrameLevel() + 2)

                local lbl = rowFrame:CreateFontString(nil, "OVERLAY")
                EllesmereUI.PrimeFontShadow(lbl, true)
                lbl:SetFont(FONT_PATH, 11, "")
                lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                lbl:SetJustifyH("LEFT")
                lbl:SetPoint("LEFT", rowFrame, "LEFT", 10, 0)
                lbl:SetText((EllesmereUI.L(axis)) or axis)

                local box = CreateFrame("EditBox", nil, rowFrame)
                box:SetSize(INPUT_W, INPUT_H)
                box:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
                box:SetFrameLevel(cogMenu:GetFrameLevel() + 3)
                box:SetFont(FONT_PATH, 10, "")
                box:SetTextColor(1, 1, 1, 0.9)
                box:SetJustifyH("CENTER")
                local boxBg = box:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(0, 0, 0, 0.4)
                box:SetAutoFocus(false)
                box:SetNumeric(true)
                box:SetMaxLetters(5)
                -- Display the element's native size (UI coords), matching getSize/setWidth
                -- and the options sliders -- physical pixels (ToPixels) diverge from the actual setting at non-1.0 UI scales.
                box:SetNumber(floor((initVal or 0) + 0.5))

                -- Disable if this element is width/height matched
                local isWidth = (axis == "Width")
                local matchTarget = isWidth and EllesmereUI.GetWidthMatchTarget(barKey) or (not isWidth and EllesmereUI.GetHeightMatchTarget(barKey))
                if matchTarget then
                    box:Disable()
                    box:SetTextColor(0.4, 0.4, 0.4, 0.7)
                    local targetName = UM.GetBarLabel(matchTarget) or matchTarget
                    box:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(box, isWidth
                            and EllesmereUI.Lf("Width matched to %1$s. Unmatch to edit.", EllesmereUI.L(targetName))
                            or EllesmereUI.Lf("Height matched to %1$s. Unmatch to edit.", EllesmereUI.L(targetName)))
                    end)
                    box:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                end

                box:SetScript("OnEnterPressed", function(self)
                    -- Value is in the element's native UI coords (no physical-pixel conversion)
                    local val = math.max(1, math.floor(self:GetNumber() + 0.5))
                    local sb = UM.GetBarFrame(barKey)
                    local savedAlpha = sb and EllesmereUI._GetFFD(sb).restoreAlpha
                    if sb and not savedAlpha then EllesmereUI._UnlockSetBarAlpha(sb, 0) end
                    if axis == "Width" then
                        if elem.setWidth then elem.setWidth(barKey, val) end
                        for childKey, targetKey in pairs(MatchH.GetWidthMatchDB() or {}) do
                            if targetKey == barKey then MatchH.ApplyWidthMatch(childKey, barKey) end
                        end
                    else
                        if elem.setHeight then elem.setHeight(barKey, val) end
                        for childKey, targetKey in pairs(MatchH.GetHeightMatchDB() or {}) do
                            if targetKey == barKey then MatchH.ApplyHeightMatch(childKey, barKey) end
                        end
                    end
                    UM.hasChanges = true
                    self:ClearFocus()
                    EllesmereUI.RecenterBarAnchor(barKey)
                    if sb and not savedAlpha then
                        C_Timer.After(0, function() EllesmereUI._UnlockSetBarAlpha(sb, 1) end)
                    end
                    local bm = movers[barKey]
                    if bm then bm:SyncSize() end
                    for childKey, _ in pairs(movers) do
                        if movers[childKey] and movers[childKey].SyncSize then
                            local wm = MatchH.GetWidthMatchInfo(childKey)
                            local hm = MatchH.GetHeightMatchInfo(childKey)
                            if wm == barKey or hm == barKey then
                                movers[childKey]:SyncSize()
                            end
                        end
                    end
                    -- Refresh both input boxes to reflect actual post-resize dimensions
                    if elem.getSize then
                        local nw, nh = elem.getSize(barKey)
                        if wBox then wBox:SetNumber(floor((nw or 0) + 0.5)) end
                        if hBox then hBox:SetNumber(floor((nh or 0) + 0.5)) end
                    end
                    UM.PropagateAnchorChain(barKey)
                end)
                box:SetScript("OnEscapePressed", function(self)
                    self:ClearFocus()
                    if elem.getSize then
                        local w2, h2 = elem.getSize(barKey)
                        self:SetNumber(floor((axis == "Width" and (w2 or 0) or (h2 or 0)) + 0.5))
                    end
                end)
                yOff = yOff - ROW_H
                return box
            end

            -- Special override sessions never offer the direct size inputs: element
            -- size is not an override aspect (only the wm/hm size companions are),
            -- so a resize here would write the SHARED module setting mid-session
            -- while looking like a per-group edit. Users resize from the options panel instead.
            if not isCDMBar and not EllesmereUI._specialUnlockGroup then
                wBox = MakeSizeRow("Width",  curW)
                hBox = MakeSizeRow("Height", curH)
                -- Re-read both boxes after an Extra Width / Height commit.
                mover._syncCogSize = function()
                    if not elem.getSize then return end
                    local nw, nh = elem.getSize(barKey)
                    if wBox then wBox:SetNumber(floor((nw or 0) + 0.5)) end
                    if hBox then hBox:SetNumber(floor((nh or 0) + 0.5)) end
                end
            end

            -- X Position / Y Position rows (screen coords from center)
            do
                local sw = UIParent:GetWidth()
                local sh = UIParent:GetHeight()
                -- Current value of an axis as a physical-pixel COUNT, read from the
                -- bar's LIVE geometry. Displaying pixel counts (not raw UIParent
                -- units) makes +1 in the box equal exactly one physical pixel, i.e.
                -- one arrow-key nudge; PP.mult is only 1 at pixel-perfect UI scale.
                local function AxisToPx(ax)
                    local PPi = EllesmereUI and EllesmereUI.PP
                    if not PPi or not PPi.ToPixels then return nil end
                    -- STORED value first for unanchored CENTER/CENTER elements (same
                    -- reasoning as UpdateCoordText): the box must echo the user's own
                    -- typed value back; a live-derived center is off by half a pixel for odd-pixel-dimension frames.
                    local aiX = GetAnchorInfo(barKey)
                    if not (aiX and aiX.target) then
                        local pos = pendingPositions[barKey]
                        if type(pos) ~= "table" or pos._anchored or not pos.point then
                            local elemX = registeredElements[barKey]
                            pos = elemX and elemX.loadPosition and elemX.loadPosition(barKey) or nil
                            if not pos then pos = LoadBarPosition(barKey) end
                        end
                        if type(pos) == "table" and pos.point == "CENTER"
                           and (pos.relPoint or "CENTER") == "CENTER"
                           and pos.x and pos.y then
                            -- Parity-aware like the live conversion below (odd dims store a half-pixel center).
                            local sb = UM.GetBarFrame(barKey)
                            local c2pS = PPi.CenterToPixels
                            if ax == "X" then
                                if c2pS and sb then return c2pS(pos.x, sb:GetWidth(), sb:GetEffectiveScale()) end
                                return PPi.ToPixels(pos.x)
                            end
                            if c2pS and sb then return c2pS(pos.y, sb:GetHeight(), sb:GetEffectiveScale()) end
                            return PPi.ToPixels(pos.y)
                        end
                    end
                    local b = UM.GetBarFrame(barKey)
                    if not b then return nil end
                    local bL, bR = b:GetLeft(), b:GetRight()
                    local bT, bB = b:GetTop(), b:GetBottom()
                    if not (bL and bR and bT and bB) then return nil end
                    local ratio = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    -- Parity-aware live conversion: odd-pixel dims rest their
                    -- center on a half pixel; plain ToPixels reads that back
                    -- one high, so deltas computed from it move the frame to
                    -- the -0.5 side (1px off the stored-value convention).
                    local c2p = PPi.CenterToPixels
                    if ax == "X" then
                        local liveCX = ((bL + bR) * 0.5 * ratio) - sw * 0.5
                        if c2p then return c2p(liveCX, b:GetWidth(), b:GetEffectiveScale()) end
                        return PPi.ToPixels(liveCX)
                    end
                    local liveCY = ((bT + bB) * 0.5 * ratio) - sh * 0.5
                    if c2p then return c2p(liveCY, b:GetHeight(), b:GetEffectiveScale()) end
                    return PPi.ToPixels(liveCY)
                end

                local function MakePosRow(axis, initVal)
                    local rowFrame = CreateFrame("Frame", nil, cogMenu)
                    rowFrame:SetHeight(ROW_H)
                    rowFrame:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
                    rowFrame:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
                    rowFrame:SetFrameLevel(cogMenu:GetFrameLevel() + 2)

                    local lbl = rowFrame:CreateFontString(nil, "OVERLAY")
                    EllesmereUI.PrimeFontShadow(lbl, true)
                    lbl:SetFont(FONT_PATH, 11, "")
                    lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetPoint("LEFT", rowFrame, "LEFT", 10, 0)
                    lbl:SetText(axis == "X" and EllesmereUI.L("X Position") or EllesmereUI.L("Y Position"))

                    local box = CreateFrame("EditBox", nil, rowFrame)
                    box:SetSize(INPUT_W, INPUT_H)
                    box:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
                    box:SetFrameLevel(cogMenu:GetFrameLevel() + 3)
                    box:SetFont(FONT_PATH, 10, "")
                    box:SetTextColor(1, 1, 1, 0.9)
                    box:SetJustifyH("CENTER")
                    local boxBg = box:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints()
                    boxBg:SetColorTexture(0, 0, 0, 0.4)
                    box:SetAutoFocus(false)
                    box:SetNumeric(false)
                    box:SetMaxLetters(6)
                    box:SetText(tostring(initVal))

                    box:SetScript("OnEnterPressed", function(self)
                        local val = tonumber(self:GetText())
                        self:ClearFocus()
                        if not val then return end
                        local PPi = EllesmereUI and EllesmereUI.PP
                        if InCombatLockdown() or not PPi then return end
                        -- Current value from LIVE geometry (never the stale moverCX).
                        local curPx = AxisToPx(axis)
                        if not curPx then return end
                        local deltaPx = val - curPx
                        if deltaPx ~= 0 then
                            -- One physical pixel == PP.mult UIParent units. Apply an
                            -- exact integer-pixel delta through the SAME primitive the
                            -- arrow keys use, so anchored/unanchored handling, the
                            -- pending-save capture, and the mover-center re-sync all
                            -- match the proven path: no second snap, no lost move.
                            local stepUnits = PPi.FromPixels(deltaPx)
                            if axis == "X" then
                                EllesmereUI._unlockNudge(stepUnits, 0, mover, true)
                            else
                                EllesmereUI._unlockNudge(0, stepUnits, mover, true)
                            end
                        end
                        if mover.ReanchorToBar then mover:ReanchorToBar() end
                        -- Re-sync the text to where the bar ACTUALLY landed so it can
                        -- never snap back to the old number.
                        local landed = AxisToPx(axis)
                        if landed then self:SetText(tostring(landed)) end
                    end)
                    box:SetScript("OnEscapePressed", function(self)
                        self:ClearFocus()
                        -- Discard typed text; show the bar's actual current value.
                        local cur = AxisToPx(axis)
                        self:SetText(tostring(cur or initVal))
                    end)
                    yOff = yOff - ROW_H
                    return box
                end

                local xBox = MakePosRow("X", AxisToPx("X") or 0)
                local yBox = MakePosRow("Y", AxisToPx("Y") or 0)
                -- Let arrow-key nudges (while the cog is open) refresh these boxes
                -- so they stay in lockstep with the element and the floating overlay.
                mover._syncCogPos = function()
                    if xBox then local px = AxisToPx("X"); if px then xBox:SetText(tostring(px)) end end
                    if yBox then local py = AxisToPx("Y"); if py then yBox:SetText(tostring(py)) end end
                end
            end

            -- Divider after size/position inputs
            local sizeDiv = cogMenu:CreateTexture(nil, "ARTWORK")
            local sizeDivPx = PP and PP.mult or 1
            sizeDiv:SetHeight(sizeDivPx)
            if sizeDiv.SetSnapToPixelGrid then sizeDiv:SetSnapToPixelGrid(false); sizeDiv:SetTexelSnappingBias(0) end
            sizeDiv:SetColorTexture(1, 1, 1, 0.10)
            sizeDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
            sizeDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
            yOff = yOff - 9
        end

        -- Extra Width / Extra Height (matched elements only): whole physical pixels
        -- added to the size the match gives, typed like the Offset X/Y rows below
        -- (Enter applies, Escape reverts). Not gated on canResize: CDM bars and
        -- tracking bars are sized by their matches too. Hidden while the look
        -- fixes the size or the element refuses matches right now.
        do
            local wT = MatchH.GetWidthMatchInfo(barKey)
            local hT = MatchH.GetHeightMatchInfo(barKey)
            if (wT or hT) and not InCombatLockdown()
               and not (elem and elem.sizeFixedByLook)
               and not (elem and elem.matchUnavailable and elem.matchUnavailable(barKey)) then
                local XROW_H, XINPUT_W, XINPUT_H = 22, 50, 18
                local function ExtraText(axis)
                    return tostring(EllesmereUI.GetMatchExtra(axis, barKey) or 0)
                end
                local function MakeExtraRow(text, axis)
                    local rowFrame = CreateFrame("Frame", nil, cogMenu)
                    rowFrame:SetHeight(XROW_H)
                    rowFrame:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
                    rowFrame:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
                    rowFrame:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
                    local lbl = rowFrame:CreateFontString(nil, "OVERLAY")
                    EllesmereUI.PrimeFontShadow(lbl, true)
                    lbl:SetFont(FONT_PATH, 11, "")
                    lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetWordWrap(false)
                    lbl:SetPoint("LEFT", rowFrame, "LEFT", 10, 0)
                    lbl:SetText(text)
                    local box = CreateFrame("EditBox", nil, rowFrame)
                    box:SetSize(XINPUT_W, XINPUT_H)
                    box:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
                    box:SetFrameLevel(cogMenu:GetFrameLevel() + 3)
                    box:SetFont(FONT_PATH, 10, "")
                    box:SetTextColor(1, 1, 1, 0.9)
                    box:SetJustifyH("CENTER")
                    local boxBg = box:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints()
                    boxBg:SetColorTexture(0, 0, 0, 0.4)
                    box:SetAutoFocus(false)
                    box:SetNumeric(false)
                    box:SetMaxLetters(4)
                    box:SetText(ExtraText(axis))
                    -- Enter applies (clamped to -100..100 in the commit), Escape
                    -- reverts; the box then re-reads the store, so it only ever
                    -- shows a value that landed.
                    box:SetScript("OnEnterPressed", function(self)
                        self:ClearFocus()
                        local val = tonumber(self:GetText())
                        if val and not InCombatLockdown() then
                            MatchH.CommitMatchExtra(axis, barKey, val)
                            -- An anchored element may have moved with its new size.
                            if mover._syncCogPos then mover._syncCogPos() end
                            if mover._syncCogSize then mover._syncCogSize() end
                        end
                        self:SetText(ExtraText(axis))
                    end)
                    box:SetScript("OnEscapePressed", function(self)
                        self:SetText(ExtraText(axis))
                        self:ClearFocus()
                    end)
                    yOff = yOff - XROW_H
                end
                if wT then MakeExtraRow(EllesmereUI.L("Extra Width"), "w") end
                if hT then MakeExtraRow(EllesmereUI.L("Extra Height"), "h") end
                local xDiv = cogMenu:CreateTexture(nil, "ARTWORK")
                xDiv:SetHeight(PP and PP.mult or 1)
                if xDiv.SetSnapToPixelGrid then xDiv:SetSnapToPixelGrid(false); xDiv:SetTexelSnappingBias(0) end
                xDiv:SetColorTexture(1, 1, 1, 0.10)
                xDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
                xDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
                yOff = yOff - 9
            end
        end

        -- Anchor rows (anchored elements only): the target this element is linked
        -- to, and the offset a drag or a nudge left between the two, typed in
        -- place. Nothing here positions an element differently from a drag: a
        -- typed offset is a nudge by the difference. Rows share the size/position
        -- rows' shape above.
        do
            local aiM = GetAnchorInfo(barKey)
            if aiM and aiM.target and not InCombatLockdown() then
                local AROW_H, AINPUT_W, AINPUT_H = 22, 50, 18
                local tgtName = UM.GetBarLabel(aiM.target) or aiM.target
                local function MakeAnchorRow(text)
                    local rowFrame = CreateFrame("Frame", nil, cogMenu)
                    rowFrame:SetHeight(AROW_H)
                    rowFrame:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
                    rowFrame:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
                    rowFrame:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
                    local lbl = rowFrame:CreateFontString(nil, "OVERLAY")
                    EllesmereUI.PrimeFontShadow(lbl, true)
                    lbl:SetFont(FONT_PATH, 11, "")
                    lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetWordWrap(false)
                    lbl:SetPoint("LEFT", rowFrame, "LEFT", 10, 0)
                    lbl:SetText(text)
                    yOff = yOff - AROW_H
                    return rowFrame, lbl
                end
                do
                    local _, lbl = MakeAnchorRow(EllesmereUI.Lf("Anchored to: %1$s", tgtName))
                    lbl:SetTextColor(0.55, 0.55, 0.55, 0.9)
                end
                -- Offset X / Offset Y: typed values, Enter applies, Escape reverts.
                -- Physical pixels in the box, units in the record, like the X/Y
                -- Position boxes (AxisToPx): +1 here is one pixel, one nudge. A typed
                -- value drives the SAME pixel-exact nudge the arrow keys and the X/Y
                -- boxes use, by the difference from the record, so the anchored move,
                -- the pending-save capture and the mover re-sync all follow the proven
                -- path (a position-locked mover refuses it there too); the box then
                -- re-reads the record, so it can never show a number that did not land.
                local PPo = EllesmereUI and EllesmereUI.PP
                local function OffsetPx(key)
                    local a = GetAnchorInfo(barKey)
                    local v = a and a[key] or 0
                    if PPo and PPo.ToPixels then v = PPo.ToPixels(v) end
                    return math.floor(v + 0.5)
                end
                local function OffsetText(key)
                    return tostring(OffsetPx(key))
                end
                local function MakeOffsetRow(text, key)
                    local rowFrame = MakeAnchorRow(text)
                    local box = CreateFrame("EditBox", nil, rowFrame)
                    box:SetSize(AINPUT_W, AINPUT_H)
                    box:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
                    box:SetFrameLevel(cogMenu:GetFrameLevel() + 3)
                    box:SetFont(FONT_PATH, 10, "")
                    box:SetTextColor(1, 1, 1, 0.9)
                    box:SetJustifyH("CENTER")
                    local boxBg = box:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints()
                    boxBg:SetColorTexture(0, 0, 0, 0.4)
                    box:SetAutoFocus(false)
                    box:SetNumeric(false)
                    box:SetMaxLetters(6)
                    box:SetText(OffsetText(key))
                    local function Commit(self)
                        local val = tonumber(self:GetText())
                        if val and not InCombatLockdown() and PPo and PPo.FromPixels then
                            local deltaPx = math.floor(val + 0.5) - OffsetPx(key)
                            if deltaPx ~= 0 then
                                local stepUnits = PPo.FromPixels(deltaPx)
                                if key == "offsetX" then
                                    EllesmereUI._unlockNudge(stepUnits, 0, mover, true)
                                else
                                    EllesmereUI._unlockNudge(0, stepUnits, mover, true)
                                end
                                -- The bar just moved: the X/Y Position boxes follow right away.
                                if mover._syncCogPos then mover._syncCogPos() end
                            end
                        end
                        self:SetText(OffsetText(key))
                    end
                    -- Enter applies, Escape reverts; losing focus does neither, like
                    -- the X/Y Position boxes above.
                    box:SetScript("OnEnterPressed", function(self)
                        self:ClearFocus()
                        Commit(self)
                    end)
                    box:SetScript("OnEscapePressed", function(self)
                        self:SetText(OffsetText(key))
                        self:ClearFocus()
                    end)
                    return box
                end
                local oxBox = MakeOffsetRow(EllesmereUI.L("Offset X"), "offsetX")
                local oyBox = MakeOffsetRow(EllesmereUI.L("Offset Y"), "offsetY")
                -- Arrow-key nudges move the offsets underneath: keep these boxes in
                -- lockstep, the same way the X/Y boxes are.
                local prevSync = mover._syncCogPos
                mover._syncCogPos = function()
                    if prevSync then prevSync() end
                    if not oxBox:HasFocus() then oxBox:SetText(OffsetText("offsetX")) end
                    if not oyBox:HasFocus() then oyBox:SetText(OffsetText("offsetY")) end
                end
                local aDiv = cogMenu:CreateTexture(nil, "ARTWORK")
                local aDivPx = PP and PP.mult or 1
                aDiv:SetHeight(aDivPx)
                if aDiv.SetSnapToPixelGrid then aDiv:SetSnapToPixelGrid(false); aDiv:SetTexelSnappingBias(0) end
                aDiv:SetColorTexture(1, 1, 1, 0.10)
                aDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
                aDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
                yOff = yOff - 9
            end
        end
        -- Snap Target: enter pick mode or clear existing target
        local selElemItem = CreateFrame("Button", nil, cogMenu)
        selElemItem:SetHeight(ITEM_H)
        selElemItem:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
        selElemItem:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
        selElemItem:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
        selElemItem:RegisterForClicks("AnyUp")
        local selElemHl = selElemItem:CreateTexture(nil, "ARTWORK")
        selElemHl:SetAllPoints()
        selElemHl:SetColorTexture(1, 1, 1, 0)
        local selElemLbl = selElemItem:CreateFontString(nil, "OVERLAY")
        EllesmereUI.PrimeFontShadow(selElemLbl, true)
        selElemLbl:SetFont(FONT_PATH, 11, "")
        selElemLbl:SetJustifyH("LEFT")
        selElemLbl:SetPoint("LEFT", selElemItem, "LEFT", 10, 0)
        local curTgt = mover._snapTarget
        local hasTarget = curTgt and curTgt ~= "_disable_" and curTgt ~= "_select_"
        if hasTarget then
            local tgtName = UM.GetBarLabel(curTgt) or curTgt
            selElemLbl:SetText(EllesmereUI.Lf("Snap Target: %1$s", "|cFF0CD29D" .. tgtName .. "|r"))
            selElemLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
        else
            selElemLbl:SetText(EllesmereUI.L("Select Snap Target"))
            selElemLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
        end
        selElemItem:SetScript("OnEnter", function()
            selElemHl:SetColorTexture(1, 1, 1, 0.08)
            selElemLbl:SetTextColor(1, 1, 1, 1)
        end)
        selElemItem:SetScript("OnLeave", function()
            selElemHl:SetColorTexture(1, 1, 1, 0)
            selElemLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
        end)
        selElemItem:SetScript("OnClick", function()
            if hasTarget then
                mover._snapTarget = nil
                UpdateSnapLabel()
                CloseCogMenu()
            else
                mover._preSelectTarget = mover._snapTarget
                mover._snapTarget = "_select_"
                UM.selectElementPicker = mover
                FadeOverlayForSelectElement(true)
                UpdateSnapLabel()
                CloseCogMenu()
            end
        end)
        yOff = yOff - ITEM_H

        -- Helper: menu action item
        local function MakeActionItem(text, onClick, hoverFullText)
            local item = CreateFrame("Button", nil, cogMenu)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
            item:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
            item:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
            item:RegisterForClicks("AnyUp")
            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0)
            local lbl = item:CreateFontString(nil, "OVERLAY")
            EllesmereUI.PrimeFontShadow(lbl, true)
            lbl:SetFont(FONT_PATH, 11, "")
            lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            lbl:SetJustifyH("LEFT")
            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
            -- Cap the label at the row width, ending 5px before the row edge,
            -- so long dynamic labels truncate instead of spilling past the menu.
            lbl:SetPoint("RIGHT", item, "RIGHT", -5, 0)
            lbl:SetWordWrap(false)
            lbl:SetText(EllesmereUI.L(text))
            item:SetScript("OnEnter", function()
                hl:SetColorTexture(1, 1, 1, 0.08)
                lbl:SetTextColor(1, 1, 1, 1)
                -- Rows that opted in surface their full text while truncated.
                if hoverFullText and EllesmereUI.ShowWidgetTooltip
                   and lbl:GetStringWidth() > lbl:GetWidth() + 0.5 then
                    EllesmereUI.ShowWidgetTooltip(item, hoverFullText)
                end
            end)
            item:SetScript("OnLeave", function()
                hl:SetColorTexture(1, 1, 1, 0)
                lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                if hoverFullText and EllesmereUI.HideWidgetTooltip then
                    EllesmereUI.HideWidgetTooltip()
                end
            end)
            item:SetScript("OnClick", function()
                if hoverFullText and EllesmereUI.HideWidgetTooltip then
                    EllesmereUI.HideWidgetTooltip()
                end
                CloseCogMenu()
                onClick()
            end)
            yOff = yOff - ITEM_H
            return item, lbl
        end

        MakeActionItem("Center on Screen", function()
            if InCombatLockdown() then return end
            local bk = mover._barKey
            local PPc = EllesmereUI and EllesmereUI.PP
            local b = UM.GetBarFrame(bk)
            if not b or not PPc or not PPc.ToPixels or not PPc.FromPixels then return end
            -- Drive the move through the SAME stored-first delta path the cog X box
            -- uses when the user types 0: read current X from the pending/stored
            -- logical value for unanchored CENTER/CENTER elements (a live-derived
            -- center is off by half a pixel for odd-pixel-width frames), then
            -- NudgeMover accumulates prev + exact delta -- the stored X lands at
            -- exactly 0 and the readout echoes it (rewriting pendingPositions to a
            -- snapped TOPLEFT would bake the half pixel into the save).
            local curPx
            local aiC = GetAnchorInfo(bk)
            if not (aiC and aiC.target) then
                local pos = pendingPositions[bk]
                if type(pos) ~= "table" or pos._anchored or not pos.point then
                    local elemC = registeredElements[bk]
                    pos = elemC and elemC.loadPosition and elemC.loadPosition(bk) or nil
                    if not pos then pos = LoadBarPosition(bk) end
                end
                if type(pos) == "table" and pos.point == "CENTER"
                   and (pos.relPoint or "CENTER") == "CENTER"
                   and pos.x and pos.y then
                    -- Parity-aware like the cog X box and readout (odd dims store a half-pixel center).
                    local c2pC = PPc.CenterToPixels
                    curPx = (c2pC and c2pC(pos.x, b:GetWidth(), b:GetEffectiveScale())) or PPc.ToPixels(pos.x)
                end
            end
            if curPx == nil then
                -- Anchored/edge-stored/legacy formats: live-derived center, matching
                -- the coordinate readout. Parity-aware conversion (CenterToPixels):
                -- an odd-pixel-width frame's live center legitimately sits on a half
                -- pixel, and plain ToPixels' tie-up round overshoots it by one --
                -- the centering delta then lands the frame a full pixel left of an
                -- identical element centered from its stored value ("dragged first, then centered" 1px mismatch).
                local bL, bR = b:GetLeft(), b:GetRight()
                if not (bL and bR) then return end
                local ratio = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                local liveCX = ((bL + bR) * 0.5 * ratio) - UIParent:GetWidth() * 0.5
                if PPc.CenterToPixels then
                    curPx = PPc.CenterToPixels(liveCX, b:GetWidth(), b:GetEffectiveScale())
                else
                    curPx = PPc.ToPixels(liveCX)
                end
            end
            if curPx and curPx ~= 0 then
                EllesmereUI._unlockNudge(PPc.FromPixels(-curPx), 0, mover, true)
            end
            if mover.ReanchorToBar then mover:ReanchorToBar() end
            -- Collapse the mover if the mouse moved away during centering
            C_Timer.After(0.15, function()
                if not mover:IsMouseOver() and not (mover._cogBtn and mover._cogBtn:IsMouseOver()) then
                    if mover._hideOverlayText then mover._hideOverlayText() end
                    if UM.hoveredMover == mover then UM.hoveredMover = nil end
                    mover._hoverPending = false
                    if not mover._selected then
                        mover:SetFrameLevel(mover._baseLevel)
                    end
                end
            end)
        end)

        -- Screen-edge links: the element stays put and keeps its distance to that
        -- edge on any screen size. The grow direction is left alone.
        --
        -- Not gated on noAnchorTo, unlike the link button: that flag means "must not
        -- become a child of another element", which a screen edge never makes it.
        -- The minimap and kin carry it while EllesmereUI owns their position. Only a
        -- Blizzard-owned position must stay out, or the two fight over the frame.
        local NO_SCREEN_ANCHOR = { QueueStatus = true }   -- Blizzard Edit Mode owns it
        if not NO_SCREEN_ANCHOR[barKey] and not ns.IsMoverPosLocked(barKey)
           and not (registeredElements[barKey] and registeredElements[barKey].ownsPosition) then
            -- Primary link to a screen edge. The capture comes first: on an
            -- offset-less link ApplyAnchorPosition's side-snap branch stores the FLUSH
            -- offsets (0/0) before its no-move capture runs, and the next apply would
            -- snap the element onto the edge.
            local function LinkToScreenEdge(edgeKey, side)
                if InCombatLockdown() then return end
                local offX, offY = EllesmereUI._CaptureAnchorOffsets(barKey, edgeKey, side)
                if offX == nil then return end
                SetAnchorInfo(barKey, edgeKey, side, offX, offY)
                UM.ApplyAnchorPosition(barKey, edgeKey, side, nil, true)
                if mover.RefreshAnchoredText then mover:RefreshAnchoredText() end
            end

            -- Which slot a picked edge lands in: with nothing anchored it becomes the
            -- primary; a primary screen edge on the SAME axis is replaced; when a
            -- cross-axis edge already holds the other axis the pick takes the primary
            -- slot (a plain element link there would govern nothing any more, and
            -- SetAnchorInfo keeps the other edge); otherwise it becomes the cross-axis
            -- edge and the primary keeps its own axis.
            local function SetScreenAnchor(edgeKey, side)
                if InCombatLockdown() then return end
                local ai = GetAnchorInfo(barKey)
                local axis = EllesmereUI._ScreenEdgeAxis(edgeKey)
                local hasCrossEdge = ai and ai.edge and ai.edge.key
                    and EllesmereUI._ScreenEdgeAxis(ai.edge.key) ~= axis
                if not (ai and ai.target)
                   or EllesmereUI._ScreenEdgeAxis(ai.target) == axis
                   or hasCrossEdge then
                    LinkToScreenEdge(edgeKey, side)
                    return
                end
                local off = EllesmereUI._CaptureScreenEdgeOffset(barKey, edgeKey, side)
                if off == nil then return end
                -- A link that never got offsets (module default, imported layout) would
                -- take the side-snap branch below and bank FLUSH offsets for the axis
                -- the primary keeps. Fill them from the live rect first.
                if ai.offsetX == nil or ai.offsetY == nil then
                    local pX, pY = EllesmereUI._CaptureAnchorOffsets(barKey, ai.target, ai.side)
                    if pX == nil then return end
                    ai.offsetX, ai.offsetY = pX, pY
                end
                ai.edge = { key = edgeKey, side = side, offset = off }
                EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
                UM.ApplyAnchorPosition(barKey, ai.target, ai.side, nil, true)
                UM.hasChanges = true
                if mover.RefreshAnchoredText then mover:RefreshAnchoredText() end
            end
            -- The side says where the element sits relative to the strip, so it is
            -- the opposite of the edge it hugs. The last row carries no key: it
            -- clears the link, which is what centered means here -- the element
            -- follows the screen center again, like every unanchored element.
            local EDGE_ITEMS = {
                { key = "SCREEN_LEFT",   side = "RIGHT",  text = "Left" },
                { key = "SCREEN_RIGHT",  side = "LEFT",   text = "Right" },
                { key = "SCREEN_TOP",    side = "BOTTOM", text = "Top" },
                { key = "SCREEN_BOTTOM", side = "TOP",    text = "Bottom" },
                { text = "Center" },
            }

            -- Center: drop the SCREEN anchors only. A link to another element stays,
            -- that one belongs to the link button.
            local function ClearScreenAnchor()
                if InCombatLockdown() then return end
                local ai = GetAnchorInfo(barKey)
                if not ai then return end
                local primaryIsEdge = ai.target and EllesmereUI.IsScreenEdgeKey(ai.target)
                if not primaryIsEdge and not ai.edge then return end
                if primaryIsEdge then
                    -- Nothing holds the element afterwards: clear the record and
                    -- capture the live position so Save & Exit persists it, the same
                    -- way the link button unlink path does.
                    ClearAnchorInfo(barKey)
                    local bar = UM.GetBarFrame(barKey)
                    if bar then
                        local pt, _, rpt, bx, by = bar:GetPoint(1)
                        if pt then
                            pendingPositions[barKey] = { point = pt, relPoint = rpt, x = bx, y = by }
                        end
                    end
                else
                    -- The element link takes its axis back. Rebase its offsets from the
                    -- live rect first, or the element jumps to wherever that axis
                    -- pointed before the edge took over.
                    ai.edge = nil
                    EllesmereUI._anchorLinksStamp = (EllesmereUI._anchorLinksStamp or 0) + 1
                    local offX, offY = EllesmereUI._CaptureAnchorOffsets(barKey, ai.target, ai.side)
                    if offX ~= nil then ai.offsetX, ai.offsetY = offX, offY end
                    -- Growth bars: the pin outranks the offsets on its axis, so recapture
                    -- it from the current position too, the way the drag-stop path does.
                    if EllesmereUI._unlockCaptureGrowPin then
                        EllesmereUI._unlockCaptureGrowPin(barKey, ai, ai.side)
                    end
                    UM.ApplyAnchorPosition(barKey, ai.target, ai.side, nil, true)
                end
                UM.hasChanges = true
                if mover.RefreshAnchoredText then mover:RefreshAnchoredText() end
            end

            -- Divider: the screen anchor is a state, not another one-shot action.
            local seDiv = cogMenu:CreateTexture(nil, "ARTWORK")
            seDiv:SetHeight(PP and PP.mult or 1)
            if seDiv.SetSnapToPixelGrid then seDiv:SetSnapToPixelGrid(false); seDiv:SetTexelSnappingBias(0) end
            seDiv:SetColorTexture(1, 1, 1, 0.10)
            seDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
            seDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
            yOff = yOff - 9

            local seItem, seLbl = MakeActionItem("Relative to Screen", function() end)
            local seArrow = seItem:CreateTexture(nil, "ARTWORK")
            seArrow:SetSize(10, 10)
            seArrow:SetPoint("RIGHT", seItem, "RIGHT", -8, 0)
            seArrow:SetTexture(ARROW_RIGHT_ICON)
            seArrow:SetAlpha(0.7)
            -- Linked to an edge: the row wears the same orange as an anchored mover.
            local aiSE = GetAnchorInfo(barKey)
            local seLinked = aiSE and ((aiSE.target and EllesmereUI.IsScreenEdgeKey(aiSE.target))
                or (aiSE.edge and aiSE.edge.key ~= nil))
            if seLinked then seLbl:SetTextColor(1, 0.7, 0.3, 1) end

            local function ShowEdgeSub()
                local seSub = mover._cogEdgeSub
                if seSub then
                    for _, child in ipairs({seSub:GetChildren()}) do child:Hide(); child:SetParent(nil) end
                    for _, tex in ipairs({seSub:GetRegions()}) do if tex.Hide then tex:Hide() end end
                end
                -- Kept on the mover and parented to unlockFrame, NOT to cogMenu:
                -- BuildCogMenu reparents every cogMenu child to nil on each open, so a
                -- cogMenu-parented flyout would orphan a frame tree per menu open.
                seSub = seSub or CreateFrame("Frame", nil, UM.unlockFrame)
                mover._cogEdgeSub = seSub
                seSub:SetFrameStrata("FULLSCREEN_DIALOG")
                seSub:SetFrameLevel(cogMenu:GetFrameLevel() + 4)
                seSub:SetClampedToScreen(true)
                seSub:ClearAllPoints()
                seSub:SetPoint("TOPLEFT", seItem, "TOPRIGHT", 2, 0)
                local seBg = seSub:CreateTexture(nil, "BACKGROUND")
                seBg:SetAllPoints()
                seBg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
                EllesmereUI.MakeBorder(seSub, 1, 1, 1, 0.20)
                -- Two rows can be active at once: a primary edge plus the cross-axis
                -- one. Center is active exactly while neither exists.
                local curAi = GetAnchorInfo(barKey)
                local curT = curAi and curAi.target
                curT = (curT and EllesmereUI.IsScreenEdgeKey(curT)) and curT or nil
                local curEdge = curAi and curAi.edge and curAi.edge.key or nil
                local seY = -4
                for i = 1, #EDGE_ITEMS do
                    local e = EDGE_ITEMS[i]
                    -- Center is the active row exactly while nothing is linked.
                    local isCur = (e.key ~= nil and (e.key == curT or e.key == curEdge))
                        or (e.key == nil and curAi == nil)
                    local r, g, b, a = 0.75, 0.75, 0.75, 0.9
                    if isCur then r, g, b, a = 1, 0.7, 0.3, 1 end
                    local si = CreateFrame("Button", nil, seSub)
                    si:SetHeight(ITEM_H)
                    si:SetPoint("TOPLEFT", seSub, "TOPLEFT", 1, seY)
                    si:SetPoint("TOPRIGHT", seSub, "TOPRIGHT", -1, seY)
                    si:SetFrameLevel(seSub:GetFrameLevel() + 2)
                    si:RegisterForClicks("AnyUp")
                    local sHl = si:CreateTexture(nil, "ARTWORK")
                    sHl:SetAllPoints()
                    sHl:SetColorTexture(1, 1, 1, isCur and 0.04 or 0)
                    local sLbl = si:CreateFontString(nil, "OVERLAY")
                    sLbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                    sLbl:SetTextColor(r, g, b, a)
                    sLbl:SetJustifyH("LEFT")
                    sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                    sLbl:SetPoint("RIGHT", si, "RIGHT", -8, 0)
                    sLbl:SetWordWrap(false)
                    sLbl:SetText(EllesmereUI.L(e.text))
                    si:SetScript("OnEnter", function()
                        sHl:SetColorTexture(1, 1, 1, 0.08)
                        if isCur then sLbl:SetTextColor(1, 0.8, 0.5, 1)
                        else sLbl:SetTextColor(1, 1, 1, 1) end
                        -- Preview: show the line the element would hold on to.
                        if e.key then EllesmereUI._ShowScreenEdgeMarker(e.key) end
                    end)
                    si:SetScript("OnLeave", function()
                        sHl:SetColorTexture(1, 1, 1, isCur and 0.04 or 0)
                        sLbl:SetTextColor(r, g, b, a)
                        if e.key then EllesmereUI._HideScreenEdgeMarker(e.key) end
                    end)
                    si:SetScript("OnClick", function()
                        CloseCogMenu()
                        if e.key then
                            SetScreenAnchor(e.key, e.side)
                            -- Confirmation: the menu is gone, so the line is the only
                            -- feedback that the pick landed on that edge.
                            EllesmereUI._ShowScreenEdgeMarker(e.key, true)
                        else
                            ClearScreenAnchor()
                        end
                    end)
                    seY = seY - ITEM_H
                end
                -- Fixed width: EllesmereUI.MeasureText does not exist (the other two
                -- call sites in this file are dead code for the same reason), so a
                -- measuring loop would always keep its minimum. The labels truncate
                -- instead, so a long translation cannot spill past the background.
                seSub:SetSize(DD_W, -seY + 4)
                seSub:EnableMouse(true)
                seSub:SetScript("OnLeave", function(self)
                    C_Timer.After(0.05, function()
                        if self:IsShown() and not self:IsMouseOver() and not seItem:IsMouseOver() then
                            self:Hide()
                        end
                    end)
                end)
                seSub:Show()
            end

            seItem:SetScript("OnClick", ShowEdgeSub)
            seItem:HookScript("OnEnter", function()
                seArrow:SetAlpha(0.9)
                ShowEdgeSub()
            end)
            seItem:HookScript("OnLeave", function()
                seArrow:SetAlpha(0.7)
                if seLinked then seLbl:SetTextColor(1, 0.7, 0.3, 1) end
                C_Timer.After(0.05, function()
                    local sub = mover._cogEdgeSub
                    if sub and sub:IsShown() and not sub:IsMouseOver() and not seItem:IsMouseOver() then
                        sub:Hide()
                    end
                end)
            end)
        end

        -- Toggle Orientation (hidden for vis-only bars)
        if not isVisOnly then
            MakeActionItem("Toggle Orientation", function()
                if InCombatLockdown() then return end
                if not EAB then return end
                EAB:ToggleOrientationForBar(mover._barKey)
                UM.hasChanges = true
                DeferMoverSync(movers[mover._barKey], function(m) m:Sync() end, UM.GetBarFrame(mover._barKey))
            end)
        end

        -- Fallback Anchor: only for elements anchored to a target that can
        -- be absent (tracking bars / global groups per spec, pet frame with
        -- no pet). Captures the element's CURRENT position as the spot it
        -- falls back to whenever that target is missing.
        do
            local aiF = GetAnchorInfo(barKey)
            local fbEligible = aiF and aiF.target
                and EllesmereUI.EligibleFallbackTarget
                and EllesmereUI.EligibleFallbackTarget(aiF.target)
            if fbEligible then
                local fbDiv = cogMenu:CreateTexture(nil, "ARTWORK")
                local fbDivPx = PP and PP.mult or 1
                fbDiv:SetHeight(fbDivPx)
                if fbDiv.SetSnapToPixelGrid then fbDiv:SetSnapToPixelGrid(false); fbDiv:SetTexelSnappingBias(0) end
                fbDiv:SetColorTexture(1, 1, 1, 0.10)
                fbDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
                fbDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
                yOff = yOff - 9
                -- fallback records need a target (a legacy record without
                -- one, from the retired position-capture flow, reads as unset)
                local hasFb = aiF.fallback ~= nil and aiF.fallback.target ~= nil
                MakeActionItem(hasFb and "Fallback Anchor: Change" or "Fallback Anchor: Select", function()
                    if EllesmereUI._BeginFallbackAnchorPick then
                        EllesmereUI._BeginFallbackAnchorPick(mover)
                    end
                end)
                if hasFb then
                    MakeActionItem("Fallback Anchor: Clear", function()
                        if EllesmereUI.ClearAnchorFallback then
                            EllesmereUI.ClearAnchorFallback(barKey)
                        end
                    end)
                end
            end
        end

        -- Override Anchor (Resource Bars): a per-spec-override-group alternate
        -- anchor, edited via a draggable gold ghost. Only offered for groups
        -- WITHOUT a custom unlock layout (a fork owns every position already).
        -- ONE "Override Anchor" row hover-opens an upward-building subnav of
        -- groups to add (the snap menu's regSub pattern); each existing entry
        -- gets an "Edit Override" row whose subnav offers Edit/Delete -- the
        -- menu stays a single line until overrides actually exist.
        do
            local ovGroups = EllesmereUI._OverrideAnchorEligible
                and EllesmereUI._OverrideAnchorEligible(barKey)
                and EllesmereUI._OverrideAnchorGroups
                and EllesmereUI._OverrideAnchorGroups() or nil
            if ovGroups then
                local OV_ARROW = "Interface\\AddOns\\EllesmereUI\\media\\icons\\right-arrow.png"
                local ovOpenSub  -- only one override subnav open at a time

                local function OvSubRow(sub, rsY, text, onClick)
                    local si = CreateFrame("Button", nil, sub)
                    si:SetHeight(ITEM_H)
                    si:SetPoint("TOPLEFT", sub, "TOPLEFT", 1, rsY)
                    si:SetPoint("TOPRIGHT", sub, "TOPRIGHT", -1, rsY)
                    si:SetFrameLevel(sub:GetFrameLevel() + 2)
                    si:RegisterForClicks("AnyUp")
                    local sHl = si:CreateTexture(nil, "ARTWORK")
                    sHl:SetAllPoints()
                    sHl:SetColorTexture(1, 1, 1, 0)
                    local sLbl = si:CreateFontString(nil, "OVERLAY")
                    sLbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                    sLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    sLbl:SetJustifyH("LEFT")
                    sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                    sLbl:SetText(text)
                    si:SetScript("OnEnter", function()
                        sHl:SetColorTexture(1, 1, 1, 0.08)
                        sLbl:SetTextColor(1, 1, 1, 1)
                    end)
                    si:SetScript("OnLeave", function()
                        sHl:SetColorTexture(1, 1, 1, 0)
                        sLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    end)
                    si:SetScript("OnClick", function()
                        CloseCogMenu()
                        onClick()
                    end)
                    return rsY - ITEM_H
                end

                -- Parent row with a right arrow; entries rebuilt on every
                -- hover ({ text, fn } rows, { text, title = true } headers).
                local function OvSubnavItem(text, buildEntries)
                    local item = CreateFrame("Button", nil, cogMenu)
                    item:SetHeight(ITEM_H)
                    item:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
                    item:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
                    item:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
                    item:RegisterForClicks("AnyUp")
                    local hl = item:CreateTexture(nil, "ARTWORK")
                    hl:SetAllPoints()
                    hl:SetColorTexture(1, 1, 1, 0)
                    local lbl = item:CreateFontString(nil, "OVERLAY")
                    EllesmereUI.PrimeFontShadow(lbl, true)
                    lbl:SetFont(FONT_PATH, 11, "")
                    lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                    lbl:SetPoint("RIGHT", item, "RIGHT", -20, 0)
                    lbl:SetWordWrap(false)
                    lbl:SetText(EllesmereUI.L(text))
                    local arrow = item:CreateTexture(nil, "ARTWORK")
                    arrow:SetSize(10, 10)
                    arrow:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                    arrow:SetTexture(OV_ARROW)
                    arrow:SetAlpha(0.5)
                    local sub
                    local function ShowSub()
                        if ovOpenSub and ovOpenSub ~= sub and ovOpenSub:IsShown() then
                            ovOpenSub:Hide()
                        end
                        if sub then
                            for _, child in ipairs({sub:GetChildren()}) do child:Hide(); child:SetParent(nil) end
                            for _, tex in ipairs({sub:GetRegions()}) do if tex.Hide then tex:Hide() end end
                        end
                        -- Parented to the cog menu so closing/rebuilding the
                        -- menu tears the subnav down with it.
                        sub = sub or CreateFrame("Frame", nil, cogMenu)
                        sub:SetFrameStrata("FULLSCREEN_DIALOG")
                        sub:SetFrameLevel(cogMenu:GetFrameLevel() + 4)
                        sub:SetClampedToScreen(true)
                        -- Build UPWARD: the subnav's bottom is pinned level
                        -- with the row, so added rows extend toward the top.
                        sub:ClearAllPoints()
                        sub:SetPoint("BOTTOMLEFT", item, "BOTTOMRIGHT", 2, 0)
                        local sBg = sub:CreateTexture(nil, "BACKGROUND")
                        sBg:SetAllPoints()
                        sBg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
                        EllesmereUI.MakeBorder(sub, 1, 1, 1, 0.20)
                        local entries = buildEntries()
                        local rsY = -4
                        local maxW = 140
                        for _, e in ipairs(entries) do
                            if e.title then
                                local t = sub:CreateFontString(nil, "OVERLAY")
                                t:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
                                t:SetTextColor(1, 1, 1, 0.40)
                                t:SetJustifyH("LEFT")
                                t:SetPoint("TOPLEFT", sub, "TOPLEFT", 10, rsY - 4)
                                t:SetText(e.text)
                                rsY = rsY - 18
                                local div = sub:CreateTexture(nil, "ARTWORK")
                                div:SetHeight(1)
                                div:SetColorTexture(1, 1, 1, 0.10)
                                div:SetPoint("TOPLEFT", sub, "TOPLEFT", 1, rsY - 2)
                                div:SetPoint("TOPRIGHT", sub, "TOPRIGHT", -1, rsY - 2)
                                rsY = rsY - 5
                            else
                                rsY = OvSubRow(sub, rsY, e.text, e.fn)
                            end
                            local tw = (EllesmereUI.MeasureText
                                and EllesmereUI.MeasureText(e.text, FONT_PATH, e.title and 10 or 11)) or 0
                            local needed = 10 + tw + 10 + 2
                            if needed > maxW then maxW = needed end
                        end
                        sub:SetSize(maxW, -rsY + 4)
                        sub:EnableMouse(true)
                        sub:SetScript("OnLeave", function(self)
                            C_Timer.After(0.05, function()
                                if self:IsShown() and not self:IsMouseOver() and not item:IsMouseOver() then
                                    self:Hide()
                                end
                            end)
                        end)
                        sub:Show()
                        ovOpenSub = sub
                    end
                    item:SetScript("OnEnter", function()
                        hl:SetColorTexture(1, 1, 1, 0.08)
                        lbl:SetTextColor(1, 1, 1, 1)
                        arrow:SetAlpha(0.9)
                        ShowSub()
                    end)
                    item:SetScript("OnLeave", function()
                        hl:SetColorTexture(1, 1, 1, 0)
                        lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        arrow:SetAlpha(0.5)
                        C_Timer.After(0.05, function()
                            if sub and sub:IsShown() and not sub:IsMouseOver() and not item:IsMouseOver() then
                                sub:Hide()
                            end
                        end)
                    end)
                    yOff = yOff - ITEM_H
                    return item
                end

                local ovDiv = cogMenu:CreateTexture(nil, "ARTWORK")
                local ovDivPx = PP and PP.mult or 1
                ovDiv:SetHeight(ovDivPx)
                if ovDiv.SetSnapToPixelGrid then ovDiv:SetSnapToPixelGrid(false); ovDiv:SetTexelSnappingBias(0) end
                ovDiv:SetColorTexture(1, 1, 1, 0.10)
                ovDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
                ovDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
                yOff = yOff - 9

                local addable = {}
                for _, og in ipairs(ovGroups) do
                    if not (EllesmereUI._HasOverrideAnchor and EllesmereUI._HasOverrideAnchor(barKey, og.id)) then
                        addable[#addable + 1] = og
                    end
                end
                if #addable > 0 then
                    OvSubnavItem("Override Anchor", function()
                        local entries = {}
                        for _, og in ipairs(addable) do
                            local gid = og.id
                            entries[#entries + 1] = {
                                text = og.name or ("Group " .. tostring(gid)),
                                fn = function()
                                    if EllesmereUI._BeginOverrideAnchorPick then
                                        EllesmereUI._BeginOverrideAnchorPick(mover, gid)
                                    end
                                end,
                            }
                        end
                        return entries
                    end)
                end
                for _, og in ipairs(ovGroups) do
                    if EllesmereUI._HasOverrideAnchor and EllesmereUI._HasOverrideAnchor(barKey, og.id) then
                        local gid = og.id
                        local gname = og.name or ("Group " .. tostring(gid))
                        OvSubnavItem(EllesmereUI.Lf("Edit Override: %1$s", gname), function()
                            return {
                                { text = gname, title = true },
                                { text = EllesmereUI.L("Edit Anchor"), fn = function()
                                    if EllesmereUI._BeginOverrideAnchorPick then
                                        EllesmereUI._BeginOverrideAnchorPick(mover, gid)
                                    end
                                end },
                                { text = EllesmereUI.L("Delete Override Anchor"), fn = function()
                                    if EllesmereUI._ClearOverrideAnchor then
                                        EllesmereUI._ClearOverrideAnchor(barKey, gid)
                                    end
                                end },
                            }
                        end)
                    end
                end
            end
        end

        cogMenu:SetHeight(-yOff + 4)
        cogMenu:Show()
    end

    -- Click-catcher for cog menu
    local function ShowCogClickCatcher()
        if not cogClickCatcher then
            cogClickCatcher = CreateFrame("Button", nil, UM.unlockFrame)
            cogClickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            cogClickCatcher:SetFrameLevel(249)
            cogClickCatcher:SetAllPoints(UIParent)
            cogClickCatcher:RegisterForClicks("AnyUp")
            cogClickCatcher:SetScript("OnClick", function()
                CloseCogMenu()
            end)
        end
        cogClickCatcher:Show()
    end

    cogBtn:SetScript("OnClick", function()
        if cogMenu and cogMenu:IsShown() then
            CloseCogMenu()
        else
            SelectMover(mover)
            mover._menuOpen = true
            BuildCogMenu()
            ShowCogClickCatcher()
        end
    end)
    cogBtn:SetScript("OnHide", CloseCogMenu)

    -- Expose cog menu opener on the mover (used by right-click handler)
    mover._openCogMenu = function()
        if cogMenu and cogMenu:IsShown() then
            CloseCogMenu()
        else
            SelectMover(mover)
            mover._menuOpen = true
            BuildCogMenu()
            ShowCogClickCatcher()
        end
    end

    -- Re-read this mover's name from its registered element. `label` above is
    -- a plain local captured once at CreateMover time -- RefreshAnchoredIdle
    -- (fired on every hover and anchor-state change, see ShowOverlayText /
    -- RefreshAnchoredText) closes over that SAME local and keeps re-painting it
    -- verbatim, so a caller that only did nameFS:SetText(...) directly would see
    -- the very next hover silently revert the text. Reassigning the local here
    -- (a plain Lua upvalue write, legal from any function sharing this closure)
    -- is what makes the change stick.
    function mover:UpdateLabel()
        label = UM.GetBarLabel(barKey)
        RefreshAnchoredIdle()
    end

    -- Opt-in hover tooltip (element definition field `moverTooltip`, string or
    -- function): additive-only -- absent = the handlers no-op. Installed
    -- UNCONDITIONALLY and resolved LIVE from registeredElements, because movers
    -- persist for the whole session while elements re-register with
    -- state-dependent tooltips (CDM's Additional Bar Offset marker). Placed
    -- after every SetScript above so the HookScripts can never be replaced.
    -- Suppressed while dragging and in the pick/select modes (the base OnEnter
    -- early-returns there and a tooltip over the pickers would mislead).
    mover:HookScript("OnEnter", function()
        local el = registeredElements[barKey]
        local tip = el and el.moverTooltip
        if not tip then return end
        if _mouseHeld or UM.pickMode or UM.selectElementPicker then return end
        if type(tip) == "function" then tip = tip(barKey) end
        if tip and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(mover, tip)
        end
    end)
    mover:HookScript("OnLeave", function()
        EllesmereUI.HideWidgetTooltip()
    end)
    mover:HookScript("OnDragStart", function()
        EllesmereUI.HideWidgetTooltip()
    end)

    movers[barKey] = mover
    return mover
end

-- Override RegisterUnlockElements so that late-registering addons (e.g. CDM
-- registering after a 0.5s timer) get movers spawned immediately if unlock
-- mode is already open when they call in.
do
    local _origRegister = EllesmereUI.RegisterUnlockElements
    function EllesmereUI:RegisterUnlockElements(elements, folder)
        _origRegister(self, elements, folder)
        if not UM.isUnlocked then return end
        -- Unlock mode is open -- spawn movers for any newly registered keys,
        -- and hide existing movers whose element is now intentionally hidden.
        local spawned = false
        for _, elem in ipairs(elements) do
            local key = elem.key
            if movers[key] then
                -- Re-registration: hide mover if element is now hidden, and
                -- RE-SHOW one whose element came back (e.g. a PAB bar
                -- re-enabled mid-session -- the drop half always worked, the
                -- restore half never did). Session temp-hides
                -- (Shift+Right-Click) stay respected.
                if elem.isHidden and elem.isHidden() then
                    movers[key]:Hide()
                elseif not movers[key]:IsShown() and not movers[key]._tempHidden then
                    movers[key]:Sync()
                    movers[key]:SetAlpha(UM.darkOverlaysEnabled and 1 or MOVER_ALPHA)
                    movers[key]:Show()
                    spawned = true
                end
            else
                local m = CreateMover(key)
                if m then
                    m:Sync()
                    m:SetAlpha(UM.darkOverlaysEnabled and 1 or MOVER_ALPHA)
                    m:Show()
                    spawned = true
                end
            end
        end
        if spawned then
            SortMoverFrameLevels()
            ReapplyAllAnchors()
        end
    end
end

UM.CreateMover = CreateMover
end
