-------------------------------------------------------------------------------
--  EllesmereUI_Widgets.lua
--  Shared Widget Helpers + Widget Factory
--  Split from EllesmereUI.lua -- see EllesmereUI.lua for constants & utilities
--  DEFERRED: body runs on first EllesmereUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()
local PP = EllesmereUI.PanelPP

-- Utility functions (used heavily)
local SolidTex         = EllesmereUI.SolidTex
local MakeFont         = EllesmereUI.MakeFont
local MakeBorder       = EllesmereUI.MakeBorder
local DisablePixelSnap = EllesmereUI.DisablePixelSnap
local RowBg            = EllesmereUI.RowBg
local lerp             = EllesmereUI.lerp
local MakeDropdownArrow = EllesmereUI.MakeDropdownArrow
local RegisterWidgetRefresh = EllesmereUI.RegisterWidgetRefresh
local RegAccent        = EllesmereUI.RegAccent

-- Visual constants (used in hot paths)
local EXPRESSWAY       = EllesmereUI.EXPRESSWAY
local ELLESMERE_GREEN  = EllesmereUI.ELLESMERE_GREEN
local CONTENT_PAD      = EllesmereUI.CONTENT_PAD
local DARK_BG          = EllesmereUI.DARK_BG
local BORDER_COLOR     = EllesmereUI.BORDER_COLOR
local TEXT_WHITE       = EllesmereUI.TEXT_WHITE
local TEXT_DIM         = EllesmereUI.TEXT_DIM
local TEXT_SECTION     = EllesmereUI.TEXT_SECTION
local MEDIA_PATH       = EllesmereUI.MEDIA_PATH
local CS               = EllesmereUI.CS

-- Numeric constants (used frequently in widget builders)
local TEXT_WHITE_R = EllesmereUI.TEXT_WHITE_R
local TEXT_WHITE_G = EllesmereUI.TEXT_WHITE_G
local TEXT_WHITE_B = EllesmereUI.TEXT_WHITE_B
local TEXT_DIM_R   = EllesmereUI.TEXT_DIM_R
local TEXT_DIM_G   = EllesmereUI.TEXT_DIM_G
local TEXT_DIM_B   = EllesmereUI.TEXT_DIM_B
local TEXT_DIM_A   = EllesmereUI.TEXT_DIM_A
local BORDER_R     = EllesmereUI.BORDER_R
local BORDER_G     = EllesmereUI.BORDER_G
local BORDER_B     = EllesmereUI.BORDER_B
local ROW_BG_ODD   = EllesmereUI.ROW_BG_ODD
local ROW_BG_EVEN  = EllesmereUI.ROW_BG_EVEN

-- Slider constants (packed into table to reduce upvalue count)
local SL = {
    TRACK_R = EllesmereUI.SL_TRACK_R, TRACK_G = EllesmereUI.SL_TRACK_G,
    TRACK_B = EllesmereUI.SL_TRACK_B, TRACK_A = EllesmereUI.SL_TRACK_A,
    FILL_A  = EllesmereUI.SL_FILL_A,
    INPUT_R = EllesmereUI.SL_INPUT_R, INPUT_G = EllesmereUI.SL_INPUT_G,
    INPUT_B = EllesmereUI.SL_INPUT_B, INPUT_A = EllesmereUI.SL_INPUT_A,
    INPUT_BRD_A = EllesmereUI.SL_INPUT_BRD_A,
    MW_INPUT_BOOST = EllesmereUI.MW_INPUT_ALPHA_BOOST,
    MW_TRACK_BOOST = EllesmereUI.MW_TRACK_ALPHA_BOOST,
}

-- Toggle constants (packed into table to reduce upvalue count)
local TG = {
    OFF_R = EllesmereUI.TG_OFF_R, OFF_G = EllesmereUI.TG_OFF_G,
    OFF_B = EllesmereUI.TG_OFF_B, OFF_A = EllesmereUI.TG_OFF_A,
    ON_A  = EllesmereUI.TG_ON_A,
    KNOB_OFF_R = EllesmereUI.TG_KNOB_OFF_R, KNOB_OFF_G = EllesmereUI.TG_KNOB_OFF_G,
    KNOB_OFF_B = EllesmereUI.TG_KNOB_OFF_B, KNOB_OFF_A = EllesmereUI.TG_KNOB_OFF_A,
    KNOB_ON_R  = EllesmereUI.TG_KNOB_ON_R,  KNOB_ON_G  = EllesmereUI.TG_KNOB_ON_G,
    KNOB_ON_B  = EllesmereUI.TG_KNOB_ON_B,  KNOB_ON_A  = EllesmereUI.TG_KNOB_ON_A,
}

-- Checkbox constants (packed into table to reduce upvalue count)
local CB = {
    BOX_R = EllesmereUI.CB_BOX_R, BOX_G = EllesmereUI.CB_BOX_G, BOX_B = EllesmereUI.CB_BOX_B,
    BRD_A = EllesmereUI.CB_BRD_A, ACT_BRD_A = EllesmereUI.CB_ACT_BRD_A,
}

-------------------------------------------------------------------------------
--  Physical-pixel sizing for toggle / checkbox widgets
--
--  The panel runs at baseScale * userScale.  At userScale ~= 1.0 the
--  coordinate system no longer maps 1:1 to physical pixels, so sub-pixel
--  drift causes uneven padding on inner elements (knob, checkmark).
--
--  Fix: convert hardcoded physical-pixel counts into panel coordinates
--  using PP.SnapForES(pixelCount * onePixel, es) where onePixel is the
--  size of 1 physical pixel in panel coords.  This guarantees every
--  dimension lands on an exact physical pixel boundary regardless of
--  scroll position, because relative offsets between parent and child
--  cancel out any sub-pixel scroll drift.
-------------------------------------------------------------------------------
local function GetPanelEffectiveScale()
    local mf = EllesmereUI._mainFrame
    if mf then return mf:GetEffectiveScale() end
    -- Fallback before mainFrame exists
    local physW = (GetPhysicalScreenSize())
    local baseScale = GetScreenWidth() / physW
    local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
    return baseScale * userScale
end

local function PixelsToPanel(px, es)
    -- Convert a physical pixel count to panel coordinate units,
    -- snapped so it maps to exactly that many physical pixels.
    local RealPP = EllesmereUI.PP
    local onePixel = RealPP.perfect / es
    return px * onePixel
end



-------------------------------------------------------------------------------

--  BuildToggleControl(parent, frameLevel, getValue, setValue, opts)

--

--  Creates a toggle switch (track + knob) with animated on/off transition.

--  Returns: toggle (Button), applyVisual (fn), snapToState (fn)

--

--  opts (optional table):

--    .sizeRatio  -- multiplier on track/knob sizes (default 1.0)

--    .noAnim     -- if true, snap instead of animate (used by cog popup)

--    .offColors  -- {trackR,trackG,trackB,trackA, knobR,knobG,knobB,knobA}

--    .onColors   -- {trackA, knobR,knobG,knobB,knobA}  (track RGB = accent)

-------------------------------------------------------------------------------

local function BuildToggleControl(parent, frameLevel, getValue, setValue, opts)
    opts = opts or {}
    local RealPP = EllesmereUI.PP

    local TOGGLE_W, TOGGLE_H = 40, 20
    local KNOB_SZ  = 16
    local KNOB_PAD = 2

    if opts.sizeRatio and opts.sizeRatio ~= 1 then
        local r = opts.sizeRatio
        TOGGLE_W = math.floor(TOGGLE_W * r + 0.5)
        TOGGLE_H = math.floor(TOGGLE_H * r + 0.5)
        KNOB_SZ  = TOGGLE_H - KNOB_PAD * 2
    end

    local offTR = opts.offColors and opts.offColors[1] or TG.OFF_R
    local offTG = opts.offColors and opts.offColors[2] or TG.OFF_G
    local offTB = opts.offColors and opts.offColors[3] or TG.OFF_B
    local offTA = opts.offColors and opts.offColors[4] or TG.OFF_A
    local offKR = opts.offColors and opts.offColors[5] or TG.KNOB_OFF_R
    local offKG = opts.offColors and opts.offColors[6] or TG.KNOB_OFF_G
    local offKB = opts.offColors and opts.offColors[7] or TG.KNOB_OFF_B
    local offKA = opts.offColors and opts.offColors[8] or TG.KNOB_OFF_A
    local onTA  = opts.onColors and opts.onColors[1] or TG.ON_A
    local onKR  = opts.onColors and opts.onColors[2] or TG.KNOB_ON_R
    local onKG  = opts.onColors and opts.onColors[3] or TG.KNOB_ON_G
    local onKB  = opts.onColors and opts.onColors[4] or TG.KNOB_ON_B
    local onKA  = opts.onColors and opts.onColors[5] or TG.KNOB_ON_A

    local toggle = CreateFrame("Button", nil, parent)
    RealPP.Size(toggle, TOGGLE_W, TOGGLE_H)
    toggle:SetFrameLevel(frameLevel)

    local tBg = SolidTex(toggle, "BACKGROUND", offTR, offTG, offTB, offTA)
    DisablePixelSnap(tBg)
    tBg:SetAllPoints()

    local knob = toggle:CreateTexture(nil, "ARTWORK")
    DisablePixelSnap(knob)
    knob:SetColorTexture(offKR, offKG, offKB, offKA)
    RealPP.Size(knob, KNOB_SZ, KNOB_SZ)
    RealPP.Point(knob, "LEFT", toggle, "LEFT", KNOB_PAD, 0)

    local POS_OFF = KNOB_PAD
    local POS_ON  = TOGGLE_W - KNOB_SZ - KNOB_PAD

    local animProgress = getValue() and 1 or 0
    local animTarget   = animProgress
    local ANIM_DUR = 0.075

    local function ApplyVisual(p)
        local xOff = math.floor(lerp(POS_OFF, POS_ON, p) + 0.5)
        knob:ClearAllPoints()
        RealPP.Point(knob, "LEFT", toggle, "LEFT", xOff, 0)
        tBg:SetColorTexture(
            lerp(offTR, ELLESMERE_GREEN.r, p),
            lerp(offTG, ELLESMERE_GREEN.g, p),
            lerp(offTB, ELLESMERE_GREEN.b, p),
            lerp(offTA, onTA, p))
        knob:SetColorTexture(
            lerp(offKR, onKR, p),
            lerp(offKG, onKG, p),
            lerp(offKB, onKB, p),
            lerp(offKA, onKA, p))
        DisablePixelSnap(knob)
    end
    ApplyVisual(animProgress)

    if opts.noAnim then
        toggle:SetScript("OnClick", function()
            local v = not getValue()
            setValue(v)
            animProgress = v and 1 or 0
            animTarget = animProgress
            ApplyVisual(animProgress)
        end)
    else
        local function AnimOnUpdate(self, elapsed)
            local dir = (animTarget == 1) and 1 or -1
            animProgress = animProgress + dir * (elapsed / ANIM_DUR)
            if (dir == 1 and animProgress >= 1) or (dir == -1 and animProgress <= 0) then
                animProgress = animTarget
                self:SetScript("OnUpdate", nil)
            end
            ApplyVisual(animProgress)
        end
        toggle:SetScript("OnClick", function()
            local v = not getValue()
            setValue(v)
            animTarget = v and 1 or 0
            toggle:SetScript("OnUpdate", AnimOnUpdate)
        end)
    end

    local function SnapToState()
        local v = getValue() and 1 or 0
        animProgress = v; animTarget = v
        ApplyVisual(v)
        toggle:SetScript("OnUpdate", nil)
    end

    return toggle, ApplyVisual, SnapToState
end



-------------------------------------------------------------------------------

--  BuildCheckboxControl(parent, frameLevel)

--

--  Creates a checkbox (box + border + checkmark texture).

--  Returns: box (Frame), check (Texture), boxBorder, applyVisual (fn)

--  applyVisual(isOn, isHovering) updates colors/visibility.

-------------------------------------------------------------------------------

local function BuildCheckboxControl(parent, frameLevel)
    local RealPP = EllesmereUI.PP
    local BOX_SZ  = 18
    local BOX_PAD = 2

    local box = CreateFrame("Frame", nil, parent)
    RealPP.Size(box, BOX_SZ, BOX_SZ)
    box:SetFrameLevel(frameLevel)

    local boxBg = SolidTex(box, "BACKGROUND", CB.BOX_R, CB.BOX_G, CB.BOX_B, 1)
    DisablePixelSnap(boxBg)
    boxBg:SetAllPoints()
    local boxBorder = MakeBorder(box, BORDER_R, BORDER_G, BORDER_B, CB.BRD_A, PP)

    local check = SolidTex(box, "ARTWORK", ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
    DisablePixelSnap(check)
    RealPP.SetInside(check, box, BOX_PAD, BOX_PAD)

    local function ApplyVisual(isOn, isHovering)
        check:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
        if isOn then
            check:Show()
            boxBg:SetColorTexture(CB.BOX_R, CB.BOX_G, CB.BOX_B, 1)
            boxBorder:SetColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, CB.ACT_BRD_A)
        else
            check:Hide()
            local a = isHovering and 1 or 0.8
            boxBg:SetColorTexture(CB.BOX_R, CB.BOX_G, CB.BOX_B, 1 * a)
            boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB.BRD_A * a)
        end
    end

    return box, check, boxBorder, ApplyVisual
end



-- Button constants
local BTN_BG_R  = EllesmereUI.BTN_BG_R
local BTN_BG_G  = EllesmereUI.BTN_BG_G
local BTN_BG_B  = EllesmereUI.BTN_BG_B
local BTN_BG_A  = EllesmereUI.BTN_BG_A
local BTN_BG_HA = EllesmereUI.BTN_BG_HA
local BTN_BRD_A  = EllesmereUI.BTN_BRD_A
local BTN_BRD_HA = EllesmereUI.BTN_BRD_HA
local BTN_TXT_A  = EllesmereUI.BTN_TXT_A
local BTN_TXT_HA = EllesmereUI.BTN_TXT_HA

-- Dropdown constants
local DD_BG_R  = EllesmereUI.DD_BG_R
local DD_BG_G  = EllesmereUI.DD_BG_G
local DD_BG_B  = EllesmereUI.DD_BG_B
local DD_BG_A  = EllesmereUI.DD_BG_A
local DD_BG_HA = EllesmereUI.DD_BG_HA
local DD_BRD_A  = EllesmereUI.DD_BRD_A
local DD_BRD_HA = EllesmereUI.DD_BRD_HA
local DD_TXT_A  = EllesmereUI.DD_TXT_A
local DD_TXT_HA = EllesmereUI.DD_TXT_HA
local DD_ITEM_HL_A  = EllesmereUI.DD_ITEM_HL_A
local DD_ITEM_SEL_A = EllesmereUI.DD_ITEM_SEL_A

-- Layout constants
local DUAL_ITEM_W  = EllesmereUI.DUAL_ITEM_W
local DUAL_GAP     = EllesmereUI.DUAL_GAP
local TRIPLE_ITEM_W = EllesmereUI.TRIPLE_ITEM_W
local TRIPLE_GAP    = EllesmereUI.TRIPLE_GAP

-------------------------------------------------------------------------------
--  Shared Widget Helpers  (reduce duplication across widget factories)
-------------------------------------------------------------------------------

-- Style a button frame with bg/border/label + hover scripts.
-- colours = { bg_r,bg_g,bg_b,bg_a, bg_hr,bg_hg,bg_hb,bg_ha,
--             brd_r,brd_g,brd_b,brd_a, brd_hr,brd_hg,brd_hb,brd_ha,
--             txt_r,txt_g,txt_b,txt_a, txt_hr,txt_hg,txt_hb,txt_ha }
local function MakeStyledButton(btn, text, fontSize, colours, onClick)
    local c = colours
    local bg  = SolidTex(btn, "BACKGROUND", c[1], c[2], c[3], c[4])
    bg:SetAllPoints()
    local brd = MakeBorder(btn, c[9], c[10], c[11], c[12], PP)
    local lbl = MakeFont(btn, fontSize, nil, c[17], c[18], c[19])
    lbl:SetAlpha(c[20])
    lbl:SetPoint("CENTER")
    lbl:SetText(text)
    btn:SetScript("OnEnter", function()
        lbl:SetTextColor(c[21], c[22], c[23], c[24])
        brd:SetColor(c[13], c[14], c[15], c[16])
        bg:SetColorTexture(c[5], c[6], c[7], c[8])
    end)
    btn:SetScript("OnLeave", function()
        lbl:SetTextColor(c[17], c[18], c[19], c[20])
        brd:SetColor(c[9], c[10], c[11], c[12])
        bg:SetColorTexture(c[1], c[2], c[3], c[4])
    end)
    btn:SetScript("OnClick", function() if onClick then onClick() end end)
    return bg, brd, lbl
end

-- Pre-built colour arrays for the two button styles
local WB_COLOURS = {  -- Button hover style
    BTN_BG_R, BTN_BG_G, BTN_BG_B, BTN_BG_A,  BTN_BG_R, BTN_BG_G, BTN_BG_B, BTN_BG_HA,
    1, 1, 1, BTN_BRD_A,  1, 1, 1, BTN_BRD_HA,
    1, 1, 1, BTN_TXT_A,  1, 1, 1, BTN_TXT_HA,
}
local RB_COLOURS = {
    BTN_BG_R, BTN_BG_G, BTN_BG_B, BTN_BG_A,  BTN_BG_R, BTN_BG_G, BTN_BG_B, BTN_BG_HA,
    1, 1, 1, BTN_BRD_A,  1, 1, 1, BTN_BRD_HA,
    1, 1, 1, BTN_TXT_A,  1, 1, 1, BTN_TXT_HA,
}

-- Extract display text from a dropdown value (supports both string and {text, note} table)
-- Forward declarations (defined after the Widget Factory section)
local ShowWidgetTooltip, HideWidgetTooltip

-- Search metadata: tag a row frame so the inline search can find it
local function TagOptionRow(frame, parent, labelText)
    frame._isOptionRow = true
    frame._labelText = labelText
    frame._sectionHeader = parent._currentSection
end

-- Global disabled-widget tooltip: "This option requires ___ to be enabled"
-- Pass the human-readable requirement name (e.g. "Show Class Power", "a non-None slot")
local function DisabledTooltip(requirement)
    if type(requirement) == "string" and requirement:find("^This option") then return requirement end
    return "This option requires " .. requirement .. " to be enabled"
end

-- Add a disabled-tooltip overlay on a control frame (slider region, toggle, swatch, etc.)
-- Shows the disabled tooltip centered on the control when hovered while disabled.
local function AddControlDisabledTooltip(controlAnchor, cfg)
    if not cfg.disabledTooltip or not cfg.disabled then return end
    local parent = controlAnchor:GetParent()
    local hit = CreateFrame("Frame", nil, parent)
    hit:SetAllPoints(controlAnchor)
    local baseLevel = controlAnchor.GetFrameLevel and controlAnchor:GetFrameLevel() or parent:GetFrameLevel()
    hit:SetFrameLevel(baseLevel + 10)
    hit:SetMouseClickEnabled(false)
    hit:SetMouseMotionEnabled(false)
    hit:SetScript("OnEnter", function()
        if cfg.disabled() then
            local tt = cfg.disabledTooltip
            if type(tt) == "function" then tt = tt() end
            ShowWidgetTooltip(controlAnchor, DisabledTooltip(tt))
        end
    end)
    hit:SetScript("OnLeave", function() HideWidgetTooltip() end)
    local function UpdateMouse()
        local off = cfg.disabled()
        hit:SetMouseClickEnabled(off and true or false)
        hit:SetMouseMotionEnabled(off and true or false)
    end
    RegisterWidgetRefresh(UpdateMouse)
    UpdateMouse()
end

local function DDText(v)
    if type(v) == "table" then return v.text end
    return v
end


-- Resolve the display label for a dropdown, handling subnav children.
-- If curKey matches a top-level key whose value has a subnav, returns 'ParentText: ChildText'.
-- If curKey matches a subnav child key, searches all values for the parent.
-- Otherwise falls back to DDText(values[curKey]) or tostring(curKey).
local function DDResolveLabel(values, order, curKey)
    -- Direct top-level match (non-subnav)
    local direct = values[curKey]
    if direct and type(direct) ~= 'table' then return direct end
    if direct and type(direct) == 'table' and not direct.subnav then return direct.text end
    -- curKey might be a subnav child  search all values for a parent with subnav
    for _, parentKey in ipairs(order) do
        local pv = values[parentKey]
        if type(pv) == 'table' and pv.subnav then
            local sv = pv.subnav.values
            if sv and sv[curKey] then
                return pv.text .. ' - ' .. sv[curKey]
            end
        end
    end
    return tostring(curKey)
end
local function DDFont(v)
    if type(v) == "table" then return v.font end
    return nil
end

-- Build a dropdown popup menu, item buttons, and return { menu, menuItems, refresh }.
-- ddBtn   = the dropdown button frame the menu hangs off
-- menuW   = pixel width of the menu
-- order   = ordered key array
-- values  = { key = displayName }  -- displayName may be string or { text=..., note=... }
-- getValue / setValue = accessors
-- ddLbl   = the dropdown label FontString to update on selection
-- style   = "wide" or "regular" (chooses WD_ vs RD_ menu colours)
local DD_MAX_HEIGHT = 200

local function BuildDropdownMenu(ddBtn, menuW, order, values, getValue, setValue, ddLbl, style, disabledValuesFn)
    local isWide = (style == "wide")
    -- Menu bg/border: same colours for both styles (DD_BTN with menu-specific alpha)
    local _menuOpts = values._menuOpts
    local _moIcon = _menuOpts and _menuOpts.icon
    local _moBackground = _menuOpts and _menuOpts.background
    local _moBgVertexColor = _menuOpts and _menuOpts.backgroundVertexColor
    local _moItemH = _menuOpts and _menuOpts.itemHeight or 26
    local _moOnItemHover = _menuOpts and _menuOpts.onItemHover
    local _moOnItemLeave = _menuOpts and _menuOpts.onItemLeave
    local mBgR, mBgG, mBgB, mBgA = DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_HA
    local mBrR, mBrG, mBrB, mBrA = 1, 1, 1, DD_BRD_A
    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(200)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetSize(menuW, 10)
    menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
    menu:Hide()
    SolidTex(menu, "BACKGROUND", mBgR, mBgG, mBgB, mBgA):SetAllPoints()
    MakeBorder(menu, mBrR, mBrG, mBrB, mBrA, PP)

    -- Inner container: items are always parented here.
    -- If scrolling is needed, this becomes the scroll child.
    local innerContainer = CreateFrame("Frame", nil, menu)
    innerContainer:SetWidth(menuW)
    innerContainer:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)

    local menuItems = {}
    local mH = 4
    for _, key in ipairs(order) do
        -- Divider support: "---" key inserts a thin separator line
        if key == "---" then
            local div = innerContainer:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", innerContainer, "TOPLEFT", 1, -mH - 4)
            div:SetPoint("TOPRIGHT", innerContainer, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        else
        local dn = values[key]
        if dn then
            -- SUBNAV PARENT: render with arrow, hover flyout
            if type(dn) == 'table' and dn.subnav then
                local sn = dn.subnav
                local parentText = dn.text or tostring(key)
                local item = CreateFrame('Button', nil, innerContainer)
                item:SetHeight(26)
                item:SetPoint('TOPLEFT', innerContainer, 'TOPLEFT', 1, -mH)
                item:SetPoint('TOPRIGHT', innerContainer, 'TOPRIGHT', -1, -mH)
                item:SetFrameLevel(menu:GetFrameLevel() + 2)
                local iLbl = MakeFont(item, 13, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                iLbl:SetAlpha(1)
                iLbl:SetPoint('LEFT', item, 'LEFT', isWide and 12 or 10, 0)
                iLbl:SetText(parentText)
                -- Arrow indicator (right side, texture)
                local arrowTex = item:CreateTexture(nil, 'ARTWORK')
                arrowTex:SetSize(10, 10)
                arrowTex:SetPoint('RIGHT', item, 'RIGHT', -8, 0)
                arrowTex:SetTexture(MEDIA_PATH .. 'icons/right-arrow.png')
                arrowTex:SetAlpha(0.7)
                local iHl = SolidTex(item, 'ARTWORK', 1, 1, 1, 1); iHl:SetAlpha(0)
                iHl:SetAllPoints()
                item._key = key
                item._label = iLbl
                item._highlight = iHl
                item._isSubnavParent = true
                item._subnavChildKeys = {}
                if sn.order then for _, ck in ipairs(sn.order) do item._subnavChildKeys[ck] = true end end
                menuItems[#menuItems + 1] = item

                -- Build flyout sub-menu
                local flyout = CreateFrame('Frame', nil, UIParent)
                flyout:SetFrameStrata('FULLSCREEN_DIALOG')
                flyout:SetFrameLevel(menu:GetFrameLevel() + 10)
                flyout:SetClampedToScreen(true)
                flyout:SetSize(menuW, 10)
                flyout:Hide()
                SolidTex(flyout, 'BACKGROUND', mBgR, mBgG, mBgB, mBgA):SetAllPoints()
                MakeBorder(flyout, mBrR, mBrG, mBrB, mBrA, PP)
                item._flyout = flyout
                if not menu._flyouts then menu._flyouts = {} end
                menu._flyouts[#menu._flyouts + 1] = flyout

                local fH = 4
                for _, childKey in ipairs(sn.order) do
                    local childText = sn.values[childKey]
                    if childText then
                        local ci = CreateFrame('Button', nil, flyout)
                        ci:SetHeight(sn.itemHeight or 26)
                        ci:SetPoint('TOPLEFT', flyout, 'TOPLEFT', 1, -fH)
                        ci:SetPoint('TOPRIGHT', flyout, 'TOPRIGHT', -1, -fH)
                        ci:SetFrameLevel(flyout:GetFrameLevel() + 2)
                        local cLbl = MakeFont(ci, 13, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                        cLbl:SetAlpha(1)
                        cLbl:SetPoint('LEFT', ci, 'LEFT', 10, 0)
                        cLbl:SetText(childText)
                        cLbl:SetJustifyH('LEFT')
                        -- Optional icon from subnav.icon callback
                        if sn.icon then
                            local iconPath, l, r, t, b = sn.icon(childKey)
                            if iconPath then
                                local ico = ci:CreateTexture(nil, 'ARTWORK')
                                local icoSz = (sn.itemHeight or 26) - 8; ico:SetSize(icoSz, icoSz)
                                ico:SetPoint('RIGHT', ci, 'RIGHT', -6, 0)
                                ico:SetTexture(iconPath)
                                if l then ico:SetTexCoord(l, r, t, b) end
                                cLbl:SetPoint('RIGHT', ico, 'LEFT', -4, 0)
                            end
                        end
                        local cHl = SolidTex(ci, 'ARTWORK', 1, 1, 1, 1); cHl:SetAlpha(0)
                        cHl:SetAllPoints()
                        ci._key = childKey
                        ci._label = cLbl
                        ci._highlight = cHl
                        ci:SetScript('OnEnter', function()
                            cLbl:SetTextColor(1, 1, 1, 1)
                            cHl:SetAlpha(DD_ITEM_HL_A)
                        end)
                        ci:SetScript('OnLeave', function()
                            cLbl:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                            local cur = getValue()
                            cHl:SetAlpha(ci._key == cur and DD_ITEM_SEL_A or 0)
                        end)
                        ci:SetScript('OnClick', function()
                            if sn.onSelect then sn.onSelect(childKey) end
                            ddLbl:SetText(parentText .. ': ' .. childText)
                            flyout:Hide()
                            menu:Hide()
                            C_Timer.After(0, function()
                                local rl = EllesmereUI._widgetRefreshList
                                if rl then for ri = 1, #rl do rl[ri]() end end
                            end)
                        end)
                        fH = fH + (sn.itemHeight or 26)
                    end
                end
                flyout:SetHeight(fH + 4)

                -- Show/hide flyout on parent hover
                local flyoutTimer
                item:SetScript('OnEnter', function()
                    iLbl:SetTextColor(1, 1, 1, 1)
                    arrowTex:SetAlpha(1)
                    iHl:SetAlpha(DD_ITEM_HL_A)
                    if flyoutTimer then flyoutTimer:Cancel(); flyoutTimer = nil end
                    flyout:ClearAllPoints()
                    flyout:SetPoint('TOPLEFT', item, 'TOPRIGHT', 2, 0)
                    flyout:Show()
                    -- Match scale
                    flyout:SetScale(menu:GetScale())
                end)
                item:SetScript('OnLeave', function()
                    iLbl:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                    arrowTex:SetAlpha(0.7)
                    local cur = getValue()
                    local isChild = item._subnavChildKeys[cur]
                    iHl:SetAlpha(isChild and DD_ITEM_SEL_A or 0)
                    -- Delay hide so user can move mouse to flyout
                    flyoutTimer = C_Timer.NewTimer(0.25, function()
                        if not flyout:IsMouseOver() and not item:IsMouseOver() then
                            flyout:Hide()
                        end
                        flyoutTimer = nil
                    end)
                end)
                -- Keep flyout alive while mouse is over it
                flyout:SetScript('OnEnter', function()
                    if flyoutTimer then flyoutTimer:Cancel(); flyoutTimer = nil end
                end)
                flyout:SetScript('OnLeave', function()
                    flyoutTimer = C_Timer.NewTimer(0.15, function()
                        if not flyout:IsMouseOver() and not item:IsMouseOver() then
                            flyout:Hide()
                        end
                        flyoutTimer = nil
                    end)
                end)
                -- Hide flyout when main menu hides
                menu:HookScript('OnHide', function() flyout:Hide() end)
                item:SetScript('OnClick', function() end)  -- no-op, subnav only
                mH = mH + 26
            else
            -- Support annotated labels: dn can be a string or { text=..., note=..., font=... }
            local mainText, noteText, itemFont
            if type(dn) == "table" then
                mainText = dn.text
                noteText = dn.note
                itemFont = dn.font
            else
                mainText = dn
            end
            local item = CreateFrame("Button", nil, innerContainer)
            item:SetHeight(_moItemH)
            item:SetPoint("TOPLEFT", innerContainer, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", innerContainer, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(menu:GetFrameLevel() + 2)
            -- Optional background texture from _menuOpts.background callback
            if _moBackground then
                local bgPath = _moBackground(key)
                if bgPath then
                    local bgTex = item:CreateTexture(nil, "BACKGROUND", nil, 1)
                    bgTex:SetAllPoints()
                    bgTex:SetTexture(bgPath)
                    bgTex:SetAlpha(0.45)
                    if _moBgVertexColor then
                        local vr, vg, vb = _moBgVertexColor()
                        if vr then bgTex:SetVertexColor(vr, vg, vb, 1) end
                    end
                end
            end
            local iLbl = MakeFont(item, 13, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
            if itemFont then iLbl:SetFont(itemFont, 13, "") end
            iLbl:SetAlpha(1)
            iLbl:SetPoint("LEFT", item, "LEFT", isWide and 12 or 10, 0)
            iLbl:SetJustifyH("LEFT")
            iLbl:SetText(mainText)
            -- Optional annotation (smaller font, 75% alpha, same color)
            -- Optional icon from _menuOpts.icon callback
            if _moIcon then
                local iconPath, il, ir, it, ib = _moIcon(key)
                if iconPath then
                    local ico = item:CreateTexture(nil, "ARTWORK")
                    local icoSz = _moItemH - 8; ico:SetSize(icoSz, icoSz)
                    ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
                    ico:SetTexture(iconPath)
                    if il then ico:SetTexCoord(il, ir, it, ib) end
                    iLbl:SetPoint("RIGHT", ico, "LEFT", -4, 0)
                end
            end
            local iNote
            if noteText then
                iNote = MakeFont(item, 11, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                iNote:SetAlpha(0.75)
                iNote:SetPoint("LEFT", iLbl, "RIGHT", 4, 0)
                iNote:SetText(noteText)
            end
            local iHl = SolidTex(item, "ARTWORK", 1, 1, 1, 1); iHl:SetAlpha(0)
            iHl:SetAllPoints()
            item._key, item._label, item._highlight, item._note = key, iLbl, iHl, iNote
            -- Store the full display name for the dropdown button label
            item._displayName = noteText and (mainText .. " " .. noteText) or mainText
            menuItems[#menuItems + 1] = item
            item:SetScript("OnEnter", function()
                if disabledValuesFn then
                    local dv = disabledValuesFn(key)
                    if dv then
                        -- If the function returns a string, show it as a tooltip via the addon system
                        if type(dv) == "string" then ShowWidgetTooltip(item, dv) end
                        return
                    end
                end
                iLbl:SetTextColor(1, 1, 1, 1)
                if iNote then iNote:SetTextColor(1, 1, 1, 1) end
                iHl:SetAlpha(DD_ITEM_HL_A)
                if _moOnItemHover then _moOnItemHover(key) end
            end)
            item:SetScript("OnLeave", function()
                if disabledValuesFn and disabledValuesFn(key) then HideWidgetTooltip(); return end
                iLbl:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                if iNote then iNote:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A) end
                iHl:SetAlpha((item._key == getValue()) and DD_ITEM_SEL_A or 0)
                if _moOnItemLeave then _moOnItemLeave(key) end
            end)
            item:SetScript("OnClick", function()
                if disabledValuesFn and disabledValuesFn(key) then return end
                setValue(key); ddLbl:SetText(mainText)
                menu:Hide()
                -- Deferred refresh: setValue may have mutually-excluded another
                -- dropdown (e.g. left/right text).  A zero-delay timer ensures
                -- the other dropdown's label updates after the menu fully closes.
                C_Timer.After(0, function()
                    local rl = EllesmereUI._widgetRefreshList
                    if rl then for ri = 1, #rl do rl[ri]() end end
                end)
            end)
            mH = mH + _moItemH
            end -- subnav if/else
        end -- if dn
        end -- divider else
    end -- for order

    local totalContentH = mH + 4
    innerContainer:SetHeight(totalContentH)

    ---------------------------------------------------------------------------
    --  Scrollable dropdown: if content exceeds DD_MAX_HEIGHT, wrap in a
    --  ScrollFrame with a thin custom scrollbar + smooth scrolling.
    ---------------------------------------------------------------------------
    if totalContentH > (_menuOpts and _menuOpts.maxHeight or DD_MAX_HEIGHT) then
        menu:SetHeight(_menuOpts and _menuOpts.maxHeight or DD_MAX_HEIGHT)

        local sf = CreateFrame("ScrollFrame", nil, menu)
        sf:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
        sf:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0)
        sf:SetFrameLevel(menu:GetFrameLevel() + 1)
        sf:EnableMouseWheel(true)
        sf:SetScrollChild(innerContainer)
        innerContainer:SetWidth(menuW)

        -- Thin scrollbar track (4px, right side, matching main panel style)
        local ddTrack = CreateFrame("Frame", nil, sf)
        ddTrack:SetWidth(4)
        ddTrack:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -4, -4)
        ddTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -4, 4)
        ddTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
        SolidTex(ddTrack, "BACKGROUND", 1, 1, 1, 0.02):SetAllPoints()

        local ddThumb = CreateFrame("Button", nil, ddTrack)
        ddThumb:SetWidth(4)
        ddThumb:SetFrameLevel(ddTrack:GetFrameLevel() + 1)
        ddThumb:EnableMouse(true)
        ddThumb:RegisterForDrag("LeftButton")
        ddThumb:SetScript("OnDragStart", function() end)
        ddThumb:SetScript("OnDragStop", function() end)
        SolidTex(ddThumb, "ARTWORK", 1, 1, 1, 0.27):SetAllPoints()

        -- Smooth scroll state (per-dropdown, isolated from main panel)
        local ddScrollTarget = 0
        local ddSmoothing = false
        local SCROLL_STEP = 40
        local SMOOTH_SPEED = 12

        local ddSmoothFrame = CreateFrame("Frame")
        ddSmoothFrame:Hide()

        local function UpdateDDThumb()
            local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
            if maxScroll <= 0 then ddTrack:Hide(); return end
            ddTrack:Show()
            local trackH = ddTrack:GetHeight()
            local visH = sf:GetHeight()
            local ratio = visH / (visH + maxScroll)
            local thumbH = math.max(20, trackH * ratio)
            ddThumb:SetHeight(thumbH)
            local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
            local maxTravel = trackH - thumbH
            ddThumb:ClearAllPoints()
            ddThumb:SetPoint("TOP", ddTrack, "TOP", 0, -(scrollRatio * maxTravel))
        end

        ddSmoothFrame:SetScript("OnUpdate", function(_, elapsed)
            local cur = sf:GetVerticalScroll()
            local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
            ddScrollTarget = math.max(0, math.min(maxScroll, ddScrollTarget))
            local diff = ddScrollTarget - cur
            if math.abs(diff) < 0.3 then
                sf:SetVerticalScroll(ddScrollTarget)
                UpdateDDThumb()
                ddSmoothing = false
                ddSmoothFrame:Hide()
                return
            end
            local newScroll = cur + diff * math.min(1, SMOOTH_SPEED * elapsed)
            newScroll = math.max(0, math.min(maxScroll, newScroll))
            sf:SetVerticalScroll(newScroll)
            UpdateDDThumb()
        end)

        local function DDSmoothScrollTo(target)
            local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
            ddScrollTarget = math.max(0, math.min(maxScroll, target))
            if not ddSmoothing then
                ddSmoothing = true
                ddSmoothFrame:Show()
            end
        end

        sf:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = tonumber(self:GetVerticalScrollRange()) or 0
            if maxScroll <= 0 then return end
            local base = ddSmoothing and ddScrollTarget or self:GetVerticalScroll()
            DDSmoothScrollTo(base - delta * SCROLL_STEP)
        end)
        sf:SetScript("OnScrollRangeChanged", UpdateDDThumb)

        -- Thumb drag
        local ddDragging = false
        local ddDragStartY, ddDragStartScroll

        ddThumb:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            ddDragging = true
            ddSmoothing = false
            ddSmoothFrame:Hide()
            local _, cursorY = GetCursorPosition()
            ddDragStartY = cursorY / self:GetEffectiveScale()
            ddDragStartScroll = sf:GetVerticalScroll()
            self:SetScript("OnUpdate", function(self2)
                if not IsMouseButtonDown("LeftButton") then
                    ddDragging = false
                    self2:SetScript("OnUpdate", nil)
                    return
                end
                local _, cy = GetCursorPosition()
                cy = cy / self2:GetEffectiveScale()
                local deltaY = ddDragStartY - cy
                local trackH = ddTrack:GetHeight()
                local maxTravel = trackH - self2:GetHeight()
                if maxTravel <= 0 then return end
                local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
                local newScroll = math.max(0, math.min(maxScroll,
                    ddDragStartScroll + (deltaY / maxTravel) * maxScroll))
                ddScrollTarget = newScroll
                sf:SetVerticalScroll(newScroll)
                UpdateDDThumb()
            end)
        end)
        ddThumb:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            ddDragging = false
            self:SetScript("OnUpdate", nil)
        end)

        -- Stop smooth animation when menu hides
        menu:HookScript("OnHide", function()
            ddSmoothing = false
            ddSmoothFrame:Hide()
            ddScrollTarget = 0
            sf:SetVerticalScroll(0)
        end)

        -- Initial thumb update when menu shows
        menu:HookScript("OnShow", function()
            ddScrollTarget = 0
            sf:SetVerticalScroll(0)
            UpdateDDThumb()
        end)
    else
        menu:SetHeight(totalContentH)
        innerContainer:SetAllPoints(menu)
    end

    local function Refresh()
        local cur = getValue()
        for _, item in ipairs(menuItems) do
            local off = disabledValuesFn and disabledValuesFn(item._key)
            -- Subnav parent: highlight if cur is one of its child keys
            if item._isSubnavParent then
                local isChild = item._subnavChildKeys and item._subnavChildKeys[cur]
                item._highlight:SetAlpha(isChild and DD_ITEM_SEL_A or 0)
                item._label:SetAlpha(1)
                item._label:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                -- Also refresh flyout child highlights
                if item._flyout then
                    local children = { item._flyout:GetChildren() }
                    for _, child in ipairs(children) do
                        if child._key and child._highlight then
                            child._highlight:SetAlpha(child._key == cur and DD_ITEM_SEL_A or 0)
                        end
                    end
                end
            else
                item._highlight:SetAlpha((item._key == cur and not off) and DD_ITEM_SEL_A or 0)
                item._label:SetAlpha(1)
                item._label:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, off and 0.18 or TEXT_DIM_A)
                if item._note then
                    item._note:SetAlpha(1)
                    item._note:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, off and 0.12 or (TEXT_DIM_A * 0.75))
                end
            end
        end
    end
    return menu, menuItems, Refresh
end

-- Wire OnEnter/OnLeave/OnClick/OnShow/OnHide for a dropdown button + menu.
-- s = { bg_r..a, bg_hr..ha, brd_r..a, brd_hr..ha, txt_r..a, txt_hr..ha } (24 values)
local function WireDropdownScripts(ddBtn, ddLbl, bg, brd, menu, refresh, s)
    local function ApplyNormal()
        ddLbl:SetTextColor(s[17], s[18], s[19], s[20])
        brd:SetColor(s[9], s[10], s[11], s[12])
        bg:SetColorTexture(s[1], s[2], s[3], s[4])
    end
    local function ApplyHover()
        ddLbl:SetTextColor(s[21], s[22], s[23], s[24])
        brd:SetColor(s[13], s[14], s[15], s[16])
        bg:SetColorTexture(s[5], s[6], s[7], s[8])
    end
    ddBtn:SetScript("OnEnter", function()
        ApplyHover()
        if ddBtn._ttText and not menu:IsShown() then
            ShowWidgetTooltip(ddBtn, ddBtn._ttText, ddBtn._ttOpts)
        end
    end)
    ddBtn:SetScript("OnLeave", function()
        if not menu:IsShown() then
            ApplyNormal()
            if ddBtn._ttText then HideWidgetTooltip() end
        end
    end)
    ddBtn:SetScript("OnClick", function()
        if ddBtn._ttText then HideWidgetTooltip() end
        if menu:IsShown() then menu:Hide() else menu:Show() end
    end)
    ddBtn:HookScript("OnHide", function() menu:Hide() end)
    menu:SetScript("OnShow", function(self)
        -- Match the panel's effective scale since menu lives on UIParent
        local btnScale = ddBtn:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        self:SetScale(btnScale / uiScale)
        ApplyHover()
        refresh()
        self:SetScript("OnUpdate", function(m)
            local flyoverFlyout = false; if m._flyouts then for _, fo in ipairs(m._flyouts) do if fo:IsShown() and fo:IsMouseOver() then flyoverFlyout = true; break end end end
            if not m:IsMouseOver() and not ddBtn:IsMouseOver() and not flyoverFlyout and IsMouseButtonDown("LeftButton") then m:Hide(); return end
            -- Close when the bottom edge of the dropdown button leaves the visible scroll area.
            -- Skip for buttons NOT inside the scroll child (e.g. content header dropdowns).
            local scrollFrame = EllesmereUI._scrollFrame
            if scrollFrame then
                -- Cache the ancestor check on the button (runs once per menu open)
                if ddBtn._inScrollChild == nil then
                    local scrollChild = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
                    local found = false
                    if scrollChild then
                        local p = ddBtn:GetParent()
                        while p do
                            if p == scrollChild then found = true; break end
                            p = p:GetParent()
                        end
                    end
                    ddBtn._inScrollChild = found
                end
                if ddBtn._inScrollChild then
                    local sfTop = scrollFrame:GetTop()
                    local sfBot = scrollFrame:GetBottom()
                    local btnBot = ddBtn:GetBottom()
                    if sfTop and sfBot and btnBot then
                        if btnBot < sfBot or btnBot > sfTop then m:Hide() end
                    end
                end
            end
        end)
    end)
    menu:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        if self._flyouts then for _, fo in ipairs(self._flyouts) do fo:Hide() end end
        if ddBtn:IsMouseOver() then
            ApplyHover()
            if ddBtn._ttText then
                ShowWidgetTooltip(ddBtn, ddBtn._ttText, ddBtn._ttOpts)
            end
        else
            ApplyNormal()
            if ddBtn._ttText then HideWidgetTooltip() end
        end
    end)
end

-- Pre-built colour arrays for the two dropdown styles
local WD_DD_COLOURS = {
    DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A,  DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_HA,
    1, 1, 1, DD_BRD_A,  1, 1, 1, DD_BRD_HA,
    1, 1, 1, DD_TXT_A,  1, 1, 1, DD_TXT_HA,
}
local RD_DD_COLOURS = {
    DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A,  DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_HA,
    1, 1, 1, DD_BRD_A,  1, 1, 1, DD_BRD_HA,
    1, 1, 1, DD_TXT_A,  1, 1, 1, DD_TXT_HA,
}

-- Build a complete slider core (track + fill + thumb + input + drag logic).
-- Returns: frame (the container), currentVal (for external reads), UpdateSliderVisual
local function BuildSliderCore(parent, trackW, trackH, thumbSz, inputW, inputH, inputFontSz, inputAlpha, minVal, maxVal, step, getValue, setValue, isMultiWidget, snapPoints)
    -- Multi-widget overrides: boost track alpha (brighter), boost input alpha
    local trkR, trkG, trkB, trkA = SL.TRACK_R, SL.TRACK_G, SL.TRACK_B, SL.TRACK_A
    if isMultiWidget then
        trkA = math.min(1, trkA + SL.MW_TRACK_BOOST)
        inputAlpha = math.min(1, inputAlpha + SL.MW_INPUT_BOOST)
    end

    local trackFrame = CreateFrame("Frame", nil, parent)
    PP.Size(trackFrame, trackW, 20)
    trackFrame:SetFrameLevel(parent:GetFrameLevel() + 1)

    local trackDark = SolidTex(trackFrame, "BACKGROUND", trkR, trkG, trkB, trkA)
    PP.Size(trackDark, trackW, trackH)
    PP.Point(trackDark, "CENTER", trackFrame, "CENTER", 0, 0)

    local trackFill = SolidTex(trackFrame, "BORDER", ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, SL.FILL_A)
    PP.Height(trackFill, trackH)
    PP.Point(trackFill, "LEFT", trackDark, "LEFT", 0, 0)

    local thumb = CreateFrame("Button", nil, trackFrame)
    PP.Size(thumb, thumbSz, thumbSz)
    thumb:SetFrameLevel(trackFrame:GetFrameLevel() + 2)
    thumb:EnableMouse(true)
    PP.Point(thumb, "CENTER", trackFill, "RIGHT", 0, 0)
    -- Opaque blocker behind thumb to hide the track fill line.
    -- Uses a child Frame with SetIgnoreParentAlpha so it stays solid
    -- even when the slider is grayed out at 0.3 alpha.
    local thumbBlockerFrame = CreateFrame("Frame", nil, thumb)
    thumbBlockerFrame:SetAllPoints()
    thumbBlockerFrame:SetFrameLevel(thumb:GetFrameLevel())
    thumbBlockerFrame:SetIgnoreParentAlpha(true)
    local thumbBlocker = thumbBlockerFrame:CreateTexture(nil, "BACKGROUND")
    thumbBlocker:SetAllPoints()
    thumbBlocker:SetColorTexture(DARK_BG.r, DARK_BG.g, DARK_BG.b, 1)
    local thumbTex = SolidTex(thumb, "ARTWORK", ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
    thumbTex:SetAllPoints()

    -- Value input box
    local valBox = CreateFrame("EditBox", nil, parent)
    PP.Size(valBox, inputW, inputH)
    valBox:SetFrameLevel(parent:GetFrameLevel() + 2)
    valBox:SetAutoFocus(false)
    valBox:SetNumeric(false)
    valBox:SetMaxLetters(6)
    valBox:SetJustifyH("CENTER")
    valBox:SetFont(EXPRESSWAY, inputFontSz, "")
    valBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
    SolidTex(valBox, "BACKGROUND", SL.INPUT_R, SL.INPUT_G, SL.INPUT_B, inputAlpha):SetAllPoints()
    MakeBorder(valBox, BORDER_R, BORDER_G, BORDER_B, SL.INPUT_BRD_A, PP)

    local function FormatVal(v)
        if step >= 1 then return tostring(math.floor(v + 0.5))
        elseif step < 0.1 then return string.format("%.2f", v)
        else return string.format("%.1f", v) end
    end

    local currentVal = getValue()
    local function UpdateSliderVisual(val)
        local ratio = math.max(0, math.min(1, (val - minVal) / (maxVal - minVal)))
        trackFill:SetWidth(math.max(1, math.floor(trackW * ratio + 0.5)))
        local snapped = math.max(minVal, math.min(maxVal, math.floor(val / step + 0.5) * step))
        if not valBox:HasFocus() then valBox:SetText(FormatVal(snapped)) end
    end
    UpdateSliderVisual(currentVal)

    local isDragging = false
    local rawDragVal = currentVal
    local lastSnapped = currentVal
    local lastCommitX = nil
    local stepped = ((maxVal - minVal) / step) < 20
    local dragScale, dragTrackLeft  -- frozen at drag start to avoid feedback loops

    local function HalfStepPx()
        local range = maxVal - minVal
        if range <= 0 or step <= 0 then return 4 end
        return math.max(2, (trackW / (range / step)) * 0.7)
    end

    local function CommitSnap()
        local snapped = math.max(minVal, math.min(maxVal, math.floor(rawDragVal / step + 0.5) * step))
        setValue(snapped); currentVal = snapped; rawDragVal = snapped; lastSnapped = snapped; UpdateSliderVisual(snapped)
    end

    local function SliderOnUpdate(self)
        -- Safety: if mouse button was released while a modifier key stole the event, stop drag
        if not IsMouseButtonDown("LeftButton") then
            isDragging = false
            self:SetScript("OnUpdate", nil)
            dragScale = nil; dragTrackLeft = nil; lastCommitX = nil
            EllesmereUI._sliderDragging = math.max(0, (EllesmereUI._sliderDragging or 1) - 1)
            if EllesmereUI._sliderDragging == 0 then EllesmereUI._sliderDragging = nil end
            CommitSnap()
            return
        end
        local es = dragScale or self:GetEffectiveScale()
        local x = select(1, GetCursorPosition()) / es
        local left = dragTrackLeft or trackDark:GetLeft()
        if not left then return end
        local cursorX = x - left
        local ratio = math.max(0, math.min(1, cursorX / trackW))
        rawDragVal = math.max(minVal, math.min(maxVal, minVal + ratio * (maxVal - minVal)))
        -- Snap to any declared snap points within their threshold
        if snapPoints then
            for _, sp in ipairs(snapPoints) do
                local pt, threshold = sp[1], sp[2] or (step * 5)
                if math.abs(rawDragVal - pt) <= threshold then
                    rawDragVal = pt
                    break
                end
            end
        end
        local snapped = math.max(minVal, math.min(maxVal, math.floor(rawDragVal / step + 0.5) * step))
        local halfPx = HalfStepPx()
        local shouldCommit = snapped ~= lastSnapped
            and (lastCommitX == nil or math.abs(cursorX - lastCommitX) >= halfPx)
        if shouldCommit then
            setValue(snapped); currentVal = snapped; lastSnapped = snapped; lastCommitX = cursorX
            UpdateSliderVisual(stepped and snapped or rawDragVal)
        else
            -- Use lastSnapped for visual to prevent flicker at step boundaries
            UpdateSliderVisual(stepped and lastSnapped or rawDragVal)
        end
    end

    local function BeginDrag()
        isDragging = true
        EllesmereUI._sliderDragging = (EllesmereUI._sliderDragging or 0) + 1
        dragScale = trackFrame:GetEffectiveScale()
        dragTrackLeft = trackDark:GetLeft()
        local x = select(1, GetCursorPosition()) / dragScale
        local left = dragTrackLeft
        if left then
            local cursorX = x - left
            local ratio = math.max(0, math.min(1, cursorX / trackW))
            rawDragVal = math.max(minVal, math.min(maxVal, minVal + ratio * (maxVal - minVal)))
            if snapPoints then
                for _, sp in ipairs(snapPoints) do
                    local pt, threshold = sp[1], sp[2] or (step * 5)
                    if math.abs(rawDragVal - pt) <= threshold then rawDragVal = pt; break end
                end
            end
            local snapped = math.max(minVal, math.min(maxVal, math.floor(rawDragVal / step + 0.5) * step))
            UpdateSliderVisual(stepped and snapped or rawDragVal)
            setValue(snapped); currentVal = snapped; lastSnapped = snapped; lastCommitX = cursorX
        end
        trackFrame:SetScript("OnUpdate", SliderOnUpdate)
    end

    local function EndDrag()
        isDragging = false; trackFrame:SetScript("OnUpdate", nil)
        dragScale = nil; dragTrackLeft = nil; lastCommitX = nil
        EllesmereUI._sliderDragging = math.max(0, (EllesmereUI._sliderDragging or 1) - 1)
        if EllesmereUI._sliderDragging == 0 then
            EllesmereUI._sliderDragging = nil
        end
        CommitSnap()  -- final setValue runs with _sliderDragging cleared Snap() rounds
        if not EllesmereUI._sliderDragging then
            -- Fire any deferred drift checks now that all sliders have finished dragging
            if EllesmereUI._deferredDriftChecks then
                local checks = EllesmereUI._deferredDriftChecks
                EllesmereUI._deferredDriftChecks = nil
                for fn in pairs(checks) do fn() end
            end
        end
    end

    local function CommitInput()
        local raw = tonumber(valBox:GetText())
        if raw then
            raw = math.max(minVal, math.min(maxVal, raw))
            local snapped = math.max(minVal, math.min(maxVal, math.floor(raw / step + 0.5) * step))
            setValue(snapped); currentVal = snapped; rawDragVal = snapped; UpdateSliderVisual(snapped)
        else
            valBox:SetText(FormatVal(currentVal))
        end
        valBox:ClearFocus()
    end

    valBox:SetScript("OnEnterPressed", function() CommitInput() end)
    valBox:SetScript("OnEscapePressed", function() valBox:SetText(FormatVal(currentVal)); valBox:ClearFocus() end)
    valBox:SetScript("OnEditFocusLost", function() CommitInput(); valBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A) end)
    valBox:SetScript("OnEditFocusGained", function() valBox:SetTextColor(1, 1, 1, 1); valBox:HighlightText() end)
    -- WoW's EditBox can fail to visually render text set via SetText when the
    -- frame has just become visible (parent Show cycle).  Force a re-render
    -- by nudging the cursor position after setting the text.
    valBox:SetScript("OnShow", function()
        if not valBox:HasFocus() then
            valBox:SetText(FormatVal(currentVal))
            valBox:SetCursorPosition(0)
        end
    end)

    trackFrame:EnableMouse(true)
    trackFrame:RegisterForDrag("LeftButton")
    trackFrame:SetScript("OnDragStart", function() end)   -- swallow drag so parent window doesn't move
    trackFrame:SetScript("OnDragStop",  function() end)
    trackFrame:SetScript("OnMouseDown", function(_, button) if thumb._sliderDisabled then return end; if button == "LeftButton" then BeginDrag() end end)
    trackFrame:SetScript("OnMouseUp",   function(_, button) if thumb._sliderDisabled then return end; if button == "LeftButton" then EndDrag() end end)
    thumb._sliderDisabled = false
    thumb:RegisterForDrag("LeftButton")
    thumb:SetScript("OnDragStart", function() end)
    thumb:SetScript("OnDragStop",  function() end)
    thumb:SetScript("OnMouseDown", function(self, button)
        if self._sliderDisabled then return end
        if button == "LeftButton" then
            isDragging = true
            EllesmereUI._sliderDragging = (EllesmereUI._sliderDragging or 0) + 1
            rawDragVal = currentVal
            trackFrame:SetScript("OnUpdate", SliderOnUpdate)
        end
    end)
    thumb:SetScript("OnMouseUp", function(self, button)
        if self._sliderDisabled then return end
        if button == "LeftButton" then EndDrag() end
    end)

    -- Refresh: re-read value from getter and update visual + accent colors
    local function RefreshSlider()
        local v = getValue()
        if v then
            currentVal = v; rawDragVal = v; UpdateSliderVisual(v)
        end
        -- Re-apply accent color (in case theme changed on another tab)
        trackFill:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, SL.FILL_A)
        thumbTex:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
    end
    RegisterWidgetRefresh(RefreshSlider)

    return trackFrame, valBox, RefreshSlider, thumb
end

-------------------------------------------------------------------------------
--  Shared Tooltip  (single frame, lazily created, reused by all widgets)
-------------------------------------------------------------------------------
local tooltipFrame

local function GetTooltipFrame()
    if tooltipFrame then return tooltipFrame end
    tooltipFrame = CreateFrame("Frame", nil, UIParent)
    tooltipFrame:SetFrameStrata("TOOLTIP")
    tooltipFrame:SetSize(250, 40)
    local bg = tooltipFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.067, 0.067, 0.067, 0.90)
    MakeBorder(tooltipFrame, 1, 1, 1, 0.15, PP)
    tooltipFrame.text = MakeFont(tooltipFrame, 10, nil, 1, 1, 1, 0.80)
    tooltipFrame.text:SetPoint("TOPLEFT", 8, -8)
    tooltipFrame.text:SetPoint("TOPRIGHT", -8, -8)
    tooltipFrame.text:SetWordWrap(true)
    tooltipFrame.text:SetSpacing(3)
    tooltipFrame:Hide()
    return tooltipFrame
end

-- opts (optional table): { color = {r,g,b}, width = number } to override text color or force width
ShowWidgetTooltip = function(label, text, opts)
    local tt = GetTooltipFrame()
    local MAX_W = 250
    local PAD = 8  -- horizontal padding each side (matches text anchor insets)
    if opts and opts.width then
        tt:SetWidth(opts.width)
    else
        -- Measure natural single-line text width, then clamp to MAX_W
        tt:SetWidth(MAX_W)
    end
    -- Apply text color override or default white
    if opts and opts.color then
        tt.text:SetTextColor(opts.color[1], opts.color[2], opts.color[3], 0.80)
    else
        tt.text:SetTextColor(1, 1, 1, 0.80)
    end
    tt.text:SetText(text)
    tt:ClearAllPoints()
    if opts and opts.anchor == "below" then
        tt:SetPoint("TOP", label, "BOTTOM", 0, -4)
    else
        tt:SetPoint("BOTTOM", label, "TOP", 0, 4)
    end
    -- Show at alpha 0 BEFORE measuring so WoW computes font geometry
    -- on a visible frame (GetStringHeight returns wrong values on hidden frames).
    tt:SetAlpha(0)
    tt:Show()
    -- Auto-size width: use natural text width + padding, capped at MAX_W
    if not (opts and opts.width) then
        local naturalW = tt.text:GetStringWidth() + PAD * 2
        tt:SetWidth(math.min(naturalW, MAX_W))
    end
    tt:SetHeight(10)
    local textH = tt.text:GetStringHeight()
    tt:SetHeight(textH + 16)
    -- Cancel any in-progress fade-out so its OnFinished doesn't hide us
    if tt._fadeOutAG then tt._fadeOutAG:Stop() end
    if tt._fadeAG then tt._fadeAG:Stop() end
    if not tt._fadeAG then
        tt._fadeAG = tt:CreateAnimationGroup()
        tt._fadeIn = tt._fadeAG:CreateAnimation("Alpha")
        tt._fadeIn:SetDuration(0.25)
        tt._fadeIn:SetSmoothing("OUT")
    end
    tt._fadeIn:SetFromAlpha(0)
    tt._fadeIn:SetToAlpha(1)
    tt._fadeAG:SetScript("OnFinished", function() tt:SetAlpha(1) end)
    tt._fadeAG:Play()
end

HideWidgetTooltip = function()
    local tt = GetTooltipFrame()
    if not tt:IsShown() then return end
    -- Fade out
    if tt._fadeOutAG then tt._fadeOutAG:Stop() end
    if not tt._fadeOutAG then
        tt._fadeOutAG = tt:CreateAnimationGroup()
        tt._fadeOut = tt._fadeOutAG:CreateAnimation("Alpha")
        tt._fadeOut:SetDuration(0.25)
        tt._fadeOut:SetSmoothing("IN")
    end
    if tt._fadeAG then tt._fadeAG:Stop() end
    tt._fadeOut:SetFromAlpha(tt:GetAlpha())
    tt._fadeOut:SetToAlpha(0)
    tt._fadeOutAG:SetScript("OnFinished", function() tt:SetAlpha(0); tt:Hide() end)
    tt._fadeOutAG:Play()
end

-------------------------------------------------------------------------------
--  WIDGET FACTORY
-------------------------------------------------------------------------------
local WidgetFactory = {}
EllesmereUI.Widgets = WidgetFactory
EllesmereUI._font  = EXPRESSWAY
EllesmereUI.CONTENT_PAD = CONTENT_PAD

-- Theme API -- exposed so General Options can read/write
EllesmereUI.DEFAULT_ACCENT = { r = EllesmereUI.DEFAULT_ACCENT_R, g = EllesmereUI.DEFAULT_ACCENT_G, b = EllesmereUI.DEFAULT_ACCENT_B }
EllesmereUI.THEME_PRESETS = EllesmereUI.THEME_PRESETS
EllesmereUI.THEME_ORDER   = EllesmereUI.THEME_ORDER

EllesmereUI.GetAccentColor = function()
    return ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b
end

--- Get the active theme name (default "EllesmereUI")
EllesmereUI.GetActiveTheme = function()
    return EllesmereUIDB and EllesmereUIDB.activeTheme or "EllesmereUI"
end

--- Backwards compat helpers (some options files may still reference these)
EllesmereUI.IsCustomThemeEnabled = function()
    local t = EllesmereUI.GetActiveTheme()
    return t ~= "EllesmereUI"
end
EllesmereUI.IsClassColoredTheme = function()
    return EllesmereUI.GetActiveTheme() == "Class Colored"
end

--- Internal: resolve the accent color for a given theme name
local function ResolveThemeColor(theme)
    theme = EllesmereUI._ResolveFactionTheme(theme)
    if theme == "Class Colored" then
        local clr = EllesmereUI.CLASS_COLOR_MAP[EllesmereUI._playerClass]
        if clr then return clr.r, clr.g, clr.b end
        return EllesmereUI.DEFAULT_ACCENT_R, EllesmereUI.DEFAULT_ACCENT_G, EllesmereUI.DEFAULT_ACCENT_B
    elseif theme == "Custom Color" then
        local sa = EllesmereUIDB and EllesmereUIDB.accentColor
        return sa and sa.r or EllesmereUI.DEFAULT_ACCENT_R, sa and sa.g or EllesmereUI.DEFAULT_ACCENT_G, sa and sa.b or EllesmereUI.DEFAULT_ACCENT_B
    else
        local preset = EllesmereUI.THEME_PRESETS[theme]
        if preset then return preset.r, preset.g, preset.b end
        return EllesmereUI.DEFAULT_ACCENT_R, EllesmereUI.DEFAULT_ACCENT_G, EllesmereUI.DEFAULT_ACCENT_B
    end
end
EllesmereUI.ResolveThemeColor = ResolveThemeColor

--- Internal: snap accent color to all registered one-time elements (no transition)
local function UpdateAccentElements(r, g, b)
    for _, entry in ipairs(EllesmereUI._accentElements) do
        if entry.type == "solid" and entry.obj then
            entry.obj:SetColorTexture(r, g, b, entry.a or 1)
        elseif entry.type == "gradient" and entry.obj then
            entry.obj:SetColorTexture(r, g, b, 1)
            entry.obj:SetGradient("HORIZONTAL",
                CreateColor(r, g, b, entry.startA or 0.15),
                CreateColor(r, g, b, 0))
        elseif entry.type == "vertex" and entry.obj then
            entry.obj:SetVertexColor(r, g, b, 1)
        elseif entry.type == "callback" and entry.fn then
            entry.fn(r, g, b)
        end
    end
end

--- Accent color transition state
local ACCENT_FADE_DURATION, ACCENT_REFRESH_INTERVAL = 0.5, 0.067  -- ~15fps for widget refreshes
local accentFadeFrom = { r = 0, g = 0, b = 0 }
local accentFadeTo   = { r = 0, g = 0, b = 0 }
local accentFadeProgress = 1  -- 1 = done
local accentRefreshAccum = 0
local accentGCFrame, accentGCDelay  -- reused for deferred GC after fade
local accentFadeTicker = CreateFrame("Frame")
accentFadeTicker:Hide()
accentFadeTicker:SetScript("OnUpdate", function(self, elapsed)
    accentFadeProgress = accentFadeProgress + elapsed / ACCENT_FADE_DURATION
    if accentFadeProgress >= 1 then
        accentFadeProgress = 1
        self:Hide()
        -- Final snap to exact target
        ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = accentFadeTo.r, accentFadeTo.g, accentFadeTo.b
        UpdateAccentElements(accentFadeTo.r, accentFadeTo.g, accentFadeTo.b)
        -- Fast-path refresh only: re-read accent colors via widget callbacks.
        -- A force rebuild (RefreshPage(true)) here caused a full page teardown +
        -- rebuild in a single frame, which was heavy enough to hitch WoW's
        -- renderer and produce a visible full-screen blink.  The fast path is
        -- sufficient because UpdateAccentElements already snapped all one-time
        -- elements, and widget callbacks pick up the final ELLESMERE_GREEN.
        for i = 1, #EllesmereUI._widgetRefreshList do EllesmereUI._widgetRefreshList[i]() end
        -- Deferred full GC: wait 2 frames so the collection doesn't land in
        -- the same frame as the transition completion (which would hitch the
        -- renderer and cause a visible blink).  By frame +2, the transition
        -- is fully settled and the GC cost is the only work in that tick.
        if not accentGCFrame then
            accentGCFrame = CreateFrame("Frame")
        end
        accentGCDelay = 2
        accentGCFrame:SetScript("OnUpdate", function(gcSelf)
            accentGCDelay = accentGCDelay - 1
            if accentGCDelay <= 0 then
                gcSelf:SetScript("OnUpdate", nil)
                collectgarbage("collect")
            end
        end)
        return
    end
    local t = accentFadeProgress
    -- Smooth ease-in-out
    t = t < 0.5 and (2 * t * t) or (1 - (-2 * t + 2) * (-2 * t + 2) / 2)
    local r = lerp(accentFadeFrom.r, accentFadeTo.r, t)
    local g = lerp(accentFadeFrom.g, accentFadeTo.g, t)
    local b = lerp(accentFadeFrom.b, accentFadeTo.b, t)
    ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = r, g, b
    -- RegAccent elements (sidebar, tabs, footer) update every frame -- cheap
    UpdateAccentElements(r, g, b)
    -- Widget refreshes (toggles, sliders, checkboxes) are heavier -- throttle
    accentRefreshAccum = accentRefreshAccum + elapsed
    if accentRefreshAccum >= ACCENT_REFRESH_INTERVAL then
        accentRefreshAccum = 0
        for i = 1, #EllesmereUI._widgetRefreshList do EllesmereUI._widgetRefreshList[i]() end
    end
end)

--- Internal: apply accent with animated transition (for theme switches)
local function ApplyAccentAnimated(r, g, b)
    -- Save starting color
    accentFadeFrom.r, accentFadeFrom.g, accentFadeFrom.b = ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b
    accentFadeTo.r, accentFadeTo.g, accentFadeTo.b = r, g, b
    accentFadeProgress = 0
    accentRefreshAccum = 0

    -- Invalidate cached popups so they rebuild with new accent
    EllesmereUI._InvalidateConfirmPopup()

    -- Start the transition -- OnUpdate will lerp ELLESMERE_GREEN and refresh widgets each tick
    accentFadeTicker:Show()
end

--- Internal: apply accent instantly (for color picker dragging, resets, etc.)
local function ApplyAccentLive(r, g, b)
    -- Stop any running transition
    accentFadeTicker:Hide()
    accentFadeProgress = 1

    -- 1. Update the canonical color table in-place
    ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = r, g, b

    -- 2. Update registered one-time elements
    UpdateAccentElements(r, g, b)

    -- 3. Invalidate cached popups so they rebuild with new accent
    EllesmereUI._InvalidateConfirmPopup()

    -- 4. Background tint (for Custom Color picker dragging -- no crossfade)
    if EllesmereUI._applyBgTint then
        EllesmereUI._applyBgTint(r, g, b)
    end

    -- 5. Rebuild current page -- widget factories read from ELLESMERE_GREEN
    EllesmereUI:RefreshPage(true)
end

--- SetActiveTheme: main theme setter. Persists and applies with animated transition.
EllesmereUI.SetActiveTheme = function(theme)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.activeTheme = theme
    ELLESMERE_GREEN._themeEnabled = true
    local r, g, b = ResolveThemeColor(theme)

    -- Crossfade background image
    if EllesmereUI._applyThemeBG then
        EllesmereUI._applyThemeBG(theme, r, g, b)
    end

    -- Animate accent color transition
    ApplyAccentAnimated(r, g, b)
end

--- SetAccentColor: for Custom Color mode -- persists user's color and applies live.
EllesmereUI.SetAccentColor = function(r, g, b)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.accentColor = { r = r, g = g, b = b }
    -- Only apply live if we're actually in Custom Color mode
    if EllesmereUI.GetActiveTheme() == "Custom Color" then
        ApplyAccentLive(r, g, b)
    end
end

--- GetPlayerClassColor: returns the class color for the current player
EllesmereUI.GetPlayerClassColor = function()
    local clr = EllesmereUI.CLASS_COLOR_MAP[EllesmereUI._playerClass]
    if clr then return clr.r, clr.g, clr.b end
    return EllesmereUI.DEFAULT_ACCENT_R, EllesmereUI.DEFAULT_ACCENT_G, EllesmereUI.DEFAULT_ACCENT_B
end

--- ResetAccentColor: clears saved custom accent, reverts to current theme's default.
EllesmereUI.ResetAccentColor = function()
    if EllesmereUIDB then EllesmereUIDB.accentColor = nil end
    local theme = EllesmereUI.GetActiveTheme()
    local r, g, b = ResolveThemeColor(theme)
    ApplyAccentLive(r, g, b)
end

--- ResetTheme: wipes all style/theme settings back to defaults.
--- Called by the global "Reset to Defaults" button before ReloadUI().
EllesmereUI.ResetTheme = function()
    if not EllesmereUIDB then return end
    EllesmereUIDB.accentColor   = nil
    EllesmereUIDB.activeTheme   = nil
    -- Clean up legacy keys
    EllesmereUIDB.customThemeEnabled = nil
    EllesmereUIDB.classColoredTheme  = nil
end

--- Backwards compat stubs
EllesmereUI.SetCustomThemeEnabled = function(enabled)
    if enabled then
        EllesmereUI.SetActiveTheme("Custom Color")
    else
        EllesmereUI.SetActiveTheme("EllesmereUI")
    end
end
EllesmereUI.SetClassColoredTheme = function(enabled)
    if enabled then
        EllesmereUI.SetActiveTheme("Class Colored")
    else
        EllesmereUI.SetActiveTheme("EllesmereUI")
    end
end
EllesmereUI.DD_STYLE = {
    BG_R = DD_BG_R, BG_G = DD_BG_G, BG_B = DD_BG_B, BG_A = DD_BG_A, BG_HA = DD_BG_HA,
    BRD_A = DD_BRD_A, BRD_HA = DD_BRD_HA,
    TXT_A = DD_TXT_A, TXT_HA = DD_TXT_HA,
    ITEM_HL_A = DD_ITEM_HL_A, ITEM_SEL_A = DD_ITEM_SEL_A,
}

-- Section header  (e.g. "APPEARANCE", "KEY BINDING TEXT")
function WidgetFactory:SectionHeader(parent, text, yOffset)
    local splitParent = parent._splitParent
    local fullW = (splitParent or parent):GetWidth() - CONTENT_PAD * 2
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, 40)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)

    local label = MakeFont(frame, 12, nil, TEXT_SECTION.r, TEXT_SECTION.g, TEXT_SECTION.b, TEXT_SECTION.a)
    PP.Point(label, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 8)
    label:SetText(text)

    -- Separator spans full width when in split mode
    local sepParent = splitParent or frame
    local sep = sepParent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.02)
    if splitParent then
        sep:SetHeight(1)
        PP.Point(sep, "LEFT", splitParent, "LEFT", CONTENT_PAD, 0)
        PP.Point(sep, "RIGHT", splitParent, "RIGHT", -CONTENT_PAD, 0)
        PP.Point(sep, "BOTTOM", frame, "BOTTOM", 0, 0)
    else
        PP.Size(sep, fullW, 1)
        PP.Point(sep, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    end

    -- Reset alternating row counter so each section starts fresh
    EllesmereUI._rowCounters[parent] = 0

    -- Search metadata: tag this frame as a section header and track it on the parent
    frame._isSectionHeader = true
    frame._sectionName = text
    parent._currentSection = frame

    return frame, 40
end

-- Helper: create a fully wired dropdown control (button + bg + border + label + arrow + menu)
-- Returns ddBtn, ddLbl so caller can position the button and register refresh
-- Menu is created lazily on first click to reduce initial memory allocation.
local function BuildDropdownControl(parent, ddW, fLevel, values, order, getValue, setValue, disabledValuesFn)
    local ddBtn = CreateFrame("Button", nil, parent)
    PP.Size(ddBtn, ddW, 30)
    ddBtn:SetFrameLevel(fLevel)
    local ddBg = SolidTex(ddBtn, "BACKGROUND", DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
    ddBg:SetAllPoints()
    local ddBrd = MakeBorder(ddBtn, 1, 1, 1, DD_BRD_A, PP)
    local ddLbl = MakeFont(ddBtn, 13, nil, 1, 1, 1)
    ddLbl:SetAlpha(DD_TXT_A)
    ddLbl:SetJustifyH("LEFT")
    ddLbl:SetWordWrap(false)
    ddLbl:SetMaxLines(1)
    ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
    local arrow = MakeDropdownArrow(ddBtn, 12, PP)
    ddLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
    if not order then order = {}; for key in pairs(values) do order[#order + 1] = key end end
    ddLbl:SetText(DDResolveLabel(values, order, getValue()))

    -- Lazy menu: defer BuildDropdownMenu until first click
    local menu, refresh
    local function EnsureMenu()
        if menu then return end
        menu, _, refresh = BuildDropdownMenu(ddBtn, ddW, order, values, getValue, setValue, ddLbl, "regular", disabledValuesFn)
        ddBtn._ddMenu = menu
        ddBtn._ddRefresh = refresh
        WireDropdownScripts(ddBtn, ddLbl, ddBg, ddBrd, menu, refresh, RD_DD_COLOURS)
    end

    -- Lightweight hover scripts (before menu is created).
    -- Once EnsureMenu() runs, WireDropdownScripts replaces these with
    -- tooltip-aware versions that read ddBtn._ttText / ddBtn._ttOpts.
    local s = RD_DD_COLOURS
    local function ApplyNormal()
        ddLbl:SetTextColor(s[17], s[18], s[19], s[20])
        ddBrd:SetColor(s[9], s[10], s[11], s[12])
        ddBg:SetColorTexture(s[1], s[2], s[3], s[4])
    end
    local function ApplyHover()
        ddLbl:SetTextColor(s[21], s[22], s[23], s[24])
        ddBrd:SetColor(s[13], s[14], s[15], s[16])
        ddBg:SetColorTexture(s[5], s[6], s[7], s[8])
    end
    ddBtn:SetScript("OnEnter", function()
        ApplyHover()
        if ddBtn._ttText then ShowWidgetTooltip(ddBtn, ddBtn._ttText, ddBtn._ttOpts) end
    end)
    ddBtn:SetScript("OnLeave", function()
        if not (menu and menu:IsShown()) then ApplyNormal() end
        if ddBtn._ttText then HideWidgetTooltip() end
    end)
    ddBtn:SetScript("OnClick", function()
        if ddBtn._ttText then HideWidgetTooltip() end
        EnsureMenu()
        if menu:IsShown() then menu:Hide() else menu:Show() end
    end)
    ddBtn:HookScript("OnHide", function() if menu then menu:Hide() end end)

    return ddBtn, ddLbl
end

-- Toggle switch  (pill-shaped, teal when ON, dark when OFF, animated)
function WidgetFactory:Toggle(parent, text, yOffset, getValue, setValue, tooltip)
    local ROW_H = 50
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)

    RowBg(frame, parent)
    TagOptionRow(frame, parent, text)    local label = MakeFont(frame, 14, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b)
    label:SetPoint("LEFT", frame, "LEFT", 20, 0)
    label:SetText(text)

    if tooltip then
        local hitFrame = CreateFrame("Frame", nil, frame)
        hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
        hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
        hitFrame:SetScript("OnEnter", function() ShowWidgetTooltip(label, tooltip) end)
        hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
        hitFrame:SetMouseClickEnabled(false)
    end

    -- Toggle button
    local toggle, _, tgSnap = BuildToggleControl(frame, frame:GetFrameLevel() + 1, getValue, setValue)
    toggle:SetPoint("RIGHT", frame, "RIGHT", -20, 0)

    RegisterWidgetRefresh(tgSnap)

    return frame, ROW_H
end

-- Slider with teal fill bar
function WidgetFactory:Slider(parent, text, yOffset, minVal, maxVal, step, getValue, setValue, tooltip)
    local ROW_H = 50
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    RowBg(frame, parent)
    TagOptionRow(frame, parent, text)
    local label = MakeFont(frame, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
    PP.Point(label, "LEFT", frame, "LEFT", 20, 0)
    label:SetText(text)
    if tooltip then
        local hitFrame = CreateFrame("Frame", nil, frame)
        hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
        hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
        hitFrame:SetScript("OnEnter", function() ShowWidgetTooltip(label, tooltip) end)
        hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
        hitFrame:SetMouseClickEnabled(false)
    end
    local trackFrame, valBox = BuildSliderCore(frame, 320, 4, 14, 40, 26, 13, SL.INPUT_A, minVal, maxVal, step, getValue, setValue)
    PP.Point(valBox, "RIGHT", frame, "RIGHT", -20, 0)
    PP.Point(trackFrame, "RIGHT", valBox, "LEFT", -16, 0)
    return frame, ROW_H
end

-- Dropdown  (optional 'order' is an array of keys for display order)
function WidgetFactory:Dropdown(parent, text, yOffset, values, getValue, setValue, order, tooltip)
    local ROW_H = 50
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    RowBg(frame, parent)
    TagOptionRow(frame, parent, text)
    local label = MakeFont(frame, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
    label:SetAlpha(1)
    PP.Point(label, "LEFT", frame, "LEFT", 20, 0)
    label:SetText(text)
    local ddBtn, ddLbl = BuildDropdownControl(frame, 200, frame:GetFrameLevel() + 1, values, order, getValue, setValue)
    if tooltip then
        local hitFrame = CreateFrame("Frame", nil, frame)
        hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
        hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
        hitFrame:SetScript("OnEnter", function()
            if not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown()) then
                ShowWidgetTooltip(label, tooltip)
            end
        end)
        hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
        hitFrame:SetMouseClickEnabled(false)
        ddBtn._ttText = tooltip
    end
    PP.Point(ddBtn, "RIGHT", frame, "RIGHT", -20, 0)
    RegisterWidgetRefresh(function()
        ddLbl:SetText(DDResolveLabel(values, order, getValue()))
    end)
    return frame, ROW_H
end

-- Checkbox (small square box with checkmark, label to the right)
function WidgetFactory:Checkbox(parent, text, yOffset, getValue, setValue, tooltip)
    local ROW_H = 36
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)

    RowBg(frame, parent)
    TagOptionRow(frame, parent, text)

    local btn = CreateFrame("Button", nil, frame)
    PP.Size(btn, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    btn:SetAllPoints(frame)

    local box, check, boxBorder, cbApply = BuildCheckboxControl(btn, frame:GetFrameLevel() + 1)
    PP.Point(box, "LEFT", btn, "LEFT", 20, 0)

    local label = MakeFont(btn, 14, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b)
    label:SetPoint("LEFT", box, "RIGHT", 10, 0)
    label:SetText(text)

    if tooltip then
        local hitFrame = CreateFrame("Frame", nil, btn)
        hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
        hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
        hitFrame:SetScript("OnEnter", function() ShowWidgetTooltip(label, tooltip) end)
        hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
        hitFrame:SetMouseClickEnabled(false)
    end

    local isHovering = false

    local function ApplyVisual()
        local on = getValue()
        cbApply(on, isHovering)
        if on then
            label:SetTextColor(TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b, 1)
        else
            local a = isHovering and 1 or 0.8
            label:SetTextColor(TEXT_WHITE.r * a, TEXT_WHITE.g * a, TEXT_WHITE.b * a, a)
        end
    end
    ApplyVisual()

    btn:SetScript("OnClick", function()
        local v = not getValue()
        setValue(v)
        ApplyVisual()
    end)

    btn:SetScript("OnEnter", function()
        isHovering = true
        ApplyVisual()
    end)
    btn:SetScript("OnLeave", function()
        isHovering = false
        ApplyVisual()
    end)

    RegisterWidgetRefresh(ApplyVisual)

    return frame, ROW_H
end

-------------------------------------------------------------------------------
--  HSV RGB Conversion Helpers
-------------------------------------------------------------------------------
local function HSVtoRGB(h, s, v)
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if     h < 60  then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else                r, g, b = c, 0, x
    end
    return r + m, g + m, b + m
end

local function RGBtoHSV(r, g, b)
    local mx = math.max(r, g, b)
    local mn = math.min(r, g, b)
    local d = mx - mn
    local h, s, v
    v = mx
    s = (mx == 0) and 0 or (d / mx)
    if d == 0 then
        h = 0
    elseif mx == r then
        h = 60 * (((g - b) / d) % 6)
    elseif mx == g then
        h = 60 * (((b - r) / d) + 2)
    else
        h = 60 * (((r - g) / d) + 4)
    end
    return h, s, v
end

-------------------------------------------------------------------------------
--  Custom Color Picker Popup (singleton, replaces Blizzard ColorPickerFrame)
-------------------------------------------------------------------------------
local function BuildColorPickerPopup()
    local PAD = 31
    local PAD_TOP = 21
    local SV_SIZE = 200
    local BAR_W = 20
    local BAR_GAP = 10
    local RIGHT_W = 70
    local RIGHT_GAP = 19
    local PAD_RIGHT = 26
    local POPUP_H = PAD_TOP + 28 + SV_SIZE + PAD
    local BASE_W = PAD + SV_SIZE + BAR_GAP + BAR_W + BAR_GAP + BAR_W + RIGHT_GAP + RIGHT_W + PAD_RIGHT
    local BASE_W_NO_ALPHA = PAD + SV_SIZE + BAR_GAP + BAR_W + RIGHT_GAP + RIGHT_W + PAD_RIGHT

    local currentH, currentS, currentV, currentA = 0, 1, 1, 1
    local prevR, prevG, prevB, prevA = 1, 1, 1, 1
    local swatchFunc, opacityFunc, cancelFunc
    local hasOpacity = false
    local updating = false

    local popup = CreateFrame("Frame", "EllesmereUIColorPicker", UIParent)
    popup:SetSize(BASE_W, POPUP_H)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(200)
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:Hide()

    -- Click-off detection: close picker when clicking outside it
    -- Uses a global OnMouseDown hook (non-blocking, preserves all hover/click on other frames)
    local clickOffFrame = CreateFrame("Frame")
    clickOffFrame:Hide()
    clickOffFrame:SetScript("OnEvent", function(_, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            if popup:IsShown() and not popup:IsMouseOver() then
                if cancelFunc then cancelFunc() end
                popup:Hide()
            end
        end
    end)
    popup:HookScript("OnShow", function()
        clickOffFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
        clickOffFrame:Show()
    end)
    popup:HookScript("OnHide", function()
        clickOffFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        clickOffFrame:Hide()
    end)

    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.08, 0.10, 1)

    -- Pixel-perfect border (matching popup style)
    MakeBorder(popup, BORDER_R, BORDER_G, BORDER_B, 0.15, PP)

    -- Title bar (draggable)
    local titleBar = CreateFrame("Frame", nil, popup)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT"); titleBar:SetPoint("TOPRIGHT")
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() popup:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)
    local titleLbl = MakeFont(titleBar, 12, nil, 1, 1, 1)
    titleLbl:SetAlpha(0.5); titleLbl:SetPoint("CENTER", 0, -10); titleLbl:SetText("Color Picker")

    -- Close button (top-right icon)
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(25, 25)
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -13, -12)
    closeBtn:SetFrameLevel(popup:GetFrameLevel() + 5)
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetAllPoints()
    closeIcon:SetTexture(MEDIA_PATH .. "icons/close-popup-4.png")
    closeIcon:SetAlpha(0.40)
    closeIcon:SetSnapToPixelGrid(false)
    closeIcon:SetTexelSnappingBias(0)
    closeBtn:SetScript("OnEnter", function() closeIcon:SetAlpha(0.50) end)
    closeBtn:SetScript("OnLeave", function() closeIcon:SetAlpha(0.40) end)
    closeBtn:SetScript("OnClick", function()
        if cancelFunc then cancelFunc() end
        popup:Hide()
    end)

    -- Getter methods (Blizzard API compat)
    local outR, outG, outB, outA = 1, 1, 1, 1
    function popup:GetColorRGB() return outR, outG, outB end
    function popup:GetColorAlpha() return outA end

    -- Forward declarations
    local UpdateSVPadHue, UpdateSVCrosshair, UpdateHueIndicator
    local UpdateAlphaBar, UpdateHexInput
    local newPreviewTex, prevPreviewTex

    local function FireCallbacks()
        if swatchFunc then swatchFunc() end
        if hasOpacity and opacityFunc then opacityFunc() end
    end

    local function UpdateAllControls()
        if updating then return end
        updating = true
        local r, g, b = HSVtoRGB(currentH, currentS, currentV)
        outR, outG, outB, outA = r, g, b, currentA
        if UpdateSVPadHue then UpdateSVPadHue(currentH) end
        if UpdateSVCrosshair then UpdateSVCrosshair(currentS, currentV) end
        if UpdateHueIndicator then UpdateHueIndicator(currentH) end
        if UpdateAlphaBar then UpdateAlphaBar(r, g, b, currentA) end
        if UpdateHexInput then UpdateHexInput(r, g, b) end
        if newPreviewTex then newPreviewTex:SetColorTexture(r, g, b, currentA) end
        updating = false
    end

    -- SV Pad
    local svPad = CreateFrame("Frame", nil, popup)
    svPad:SetSize(SV_SIZE, SV_SIZE)
    svPad:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -(PAD_TOP + 28))
    svPad:EnableMouse(true)

    local svHue = svPad:CreateTexture(nil, "BACKGROUND")
    svHue:SetAllPoints(); svHue:SetColorTexture(1, 0, 0, 1)

    local svWhite = svPad:CreateTexture(nil, "BORDER")
    svWhite:SetAllPoints(); svWhite:SetColorTexture(1, 1, 1, 1)
    svWhite:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))

    local svBlack = svPad:CreateTexture(nil, "ARTWORK")
    svBlack:SetAllPoints(); svBlack:SetColorTexture(0, 0, 0, 1)
    svBlack:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))

    MakeBorder(svPad, 1, 1, 1, 0.06, PP)

    local ARM = 6
    local chT = svPad:CreateTexture(nil, "OVERLAY", nil, 7); chT:SetSize(1, ARM); chT:SetColorTexture(1,1,1,0.9)
    local chB = svPad:CreateTexture(nil, "OVERLAY", nil, 7); chB:SetSize(1, ARM); chB:SetColorTexture(1,1,1,0.9)
    local chL = svPad:CreateTexture(nil, "OVERLAY", nil, 7); chL:SetSize(ARM, 1); chL:SetColorTexture(1,1,1,0.9)
    local chR = svPad:CreateTexture(nil, "OVERLAY", nil, 7); chR:SetSize(ARM, 1); chR:SetColorTexture(1,1,1,0.9)

    UpdateSVPadHue = function(h)
        local r, g, b = HSVtoRGB(h, 1, 1)
        svHue:SetColorTexture(r, g, b, 1)
    end
    UpdateSVCrosshair = function(s, v)
        local x = s * SV_SIZE
        local y = -(1 - v) * SV_SIZE
        chT:ClearAllPoints(); chT:SetPoint("BOTTOM", svPad, "TOPLEFT", x, y + 2)
        chB:ClearAllPoints(); chB:SetPoint("TOP", svPad, "TOPLEFT", x, y - 2)
        chL:ClearAllPoints(); chL:SetPoint("RIGHT", svPad, "TOPLEFT", x - 2, y)
        chR:ClearAllPoints(); chR:SetPoint("LEFT", svPad, "TOPLEFT", x + 2, y)
    end

    local svDragging = false
    local function SVFromCursor()
        local cx, cy = GetCursorPosition()
        local scale = svPad:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local left, bottom = svPad:GetLeft(), svPad:GetBottom()
        local s = math.max(0, math.min(1, (cx - left) / SV_SIZE))
        local v = math.max(0, math.min(1, (cy - bottom) / SV_SIZE))
        return s, v
    end
    svPad:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            svDragging = true
            currentS, currentV = SVFromCursor()
            UpdateAllControls(); FireCallbacks()
            self:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then svDragging = false; self:SetScript("OnUpdate", nil); return end
                currentS, currentV = SVFromCursor()
                UpdateAllControls(); FireCallbacks()
            end)
        end
    end)
    svPad:SetScript("OnMouseUp", function(self) svDragging = false; self:SetScript("OnUpdate", nil) end)

    -- Hue Bar
    local hueBar = CreateFrame("Frame", nil, popup)
    hueBar:SetSize(BAR_W, SV_SIZE)
    hueBar:SetPoint("TOPLEFT", svPad, "TOPRIGHT", BAR_GAP, 0)
    hueBar:EnableMouse(true)

    local HUE_COLORS = {
        {1,0,0}, {1,1,0}, {0,1,0}, {0,1,1}, {0,0,1}, {1,0,1}, {1,0,0},
    }
    local segH = SV_SIZE / 6
    for i = 1, 6 do
        local seg = hueBar:CreateTexture(nil, "BACKGROUND")
        seg:SetSize(BAR_W, segH); seg:SetPoint("TOPLEFT", hueBar, "TOPLEFT", 0, -(i-1)*segH)
        seg:SetColorTexture(1,1,1,1)
        local top, bot = HUE_COLORS[i], HUE_COLORS[i+1]
        seg:SetGradient("VERTICAL", CreateColor(bot[1],bot[2],bot[3],1), CreateColor(top[1],top[2],top[3],1))
    end
    MakeBorder(hueBar, 1, 1, 1, 0.06, PP)

    local hueInd = hueBar:CreateTexture(nil, "OVERLAY", nil, 7)
    hueInd:SetSize(BAR_W + 4, 2); hueInd:SetColorTexture(1,1,1,1)

    UpdateHueIndicator = function(h)
        hueInd:ClearAllPoints()
        hueInd:SetPoint("CENTER", hueBar, "TOPLEFT", BAR_W/2, -(h/360)*SV_SIZE)
    end

    local hueDragging = false
    local function HueFromCursor()
        local _, cy = GetCursorPosition()
        cy = cy / hueBar:GetEffectiveScale()
        return math.max(0, math.min(1, (hueBar:GetTop() - cy) / SV_SIZE)) * 360
    end
    hueBar:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            hueDragging = true; currentH = HueFromCursor(); UpdateAllControls(); FireCallbacks()
            self:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then hueDragging = false; self:SetScript("OnUpdate", nil); return end
                currentH = HueFromCursor(); UpdateAllControls(); FireCallbacks()
            end)
        end
    end)
    hueBar:SetScript("OnMouseUp", function(self) hueDragging = false; self:SetScript("OnUpdate", nil) end)

    -- Alpha Bar
    local alphaBar = CreateFrame("Frame", nil, popup)
    alphaBar:SetSize(BAR_W, SV_SIZE)
    alphaBar:SetPoint("TOPLEFT", hueBar, "TOPRIGHT", BAR_GAP, 0)
    alphaBar:EnableMouse(true)

    local CK = 10
    -- Coarse checkerboard: 2 columns 20 rows = 40 textures (vs 160 before)
    local ckCols = math.ceil(BAR_W / CK)
    local ckRows = math.ceil(SV_SIZE / CK)
    for row = 0, ckRows - 1 do
        for col = 0, ckCols - 1 do
            local c = ((row + col) % 2 == 0) and 0.3 or 0.15
            local ck = alphaBar:CreateTexture(nil, "BACKGROUND")
            ck:SetSize(CK, CK); ck:SetPoint("TOPLEFT", alphaBar, "TOPLEFT", col * CK, -row * CK)
            ck:SetColorTexture(c, c, c, 1)
        end
    end

    local alphaGrad = alphaBar:CreateTexture(nil, "ARTWORK")
    alphaGrad:SetAllPoints(); alphaGrad:SetColorTexture(1,0,0,1)

    local alphaInd = alphaBar:CreateTexture(nil, "OVERLAY", nil, 7)
    alphaInd:SetSize(BAR_W+4, 2); alphaInd:SetColorTexture(1,1,1,1)
    MakeBorder(alphaBar, 1, 1, 1, 0.06, PP)

    -- Reusable CreateColor objects to avoid per-frame allocation during drag
    local alphaColorBot = CreateColor(0, 0, 0, 0)
    local alphaColorTop = CreateColor(0, 0, 0, 1)

    UpdateAlphaBar = function(r, g, b, a)
        alphaColorBot.r, alphaColorBot.g, alphaColorBot.b, alphaColorBot.a = r, g, b, 0
        alphaColorTop.r, alphaColorTop.g, alphaColorTop.b, alphaColorTop.a = r, g, b, 1
        alphaGrad:SetGradient("VERTICAL", alphaColorBot, alphaColorTop)
        alphaInd:ClearAllPoints()
        alphaInd:SetPoint("CENTER", alphaBar, "TOPLEFT", BAR_W/2, -(1-a)*SV_SIZE)
    end

    local alphaDragging = false
    local function AlphaFromCursor()
        local _, cy = GetCursorPosition()
        cy = cy / alphaBar:GetEffectiveScale()
        return 1 - math.max(0, math.min(1, (alphaBar:GetTop() - cy) / SV_SIZE))
    end
    alphaBar:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            alphaDragging = true; currentA = AlphaFromCursor(); UpdateAllControls(); FireCallbacks()
            self:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then alphaDragging = false; self:SetScript("OnUpdate", nil); return end
                currentA = AlphaFromCursor(); UpdateAllControls(); FireCallbacks()
            end)
        end
    end)
    alphaBar:SetScript("OnMouseUp", function(self) alphaDragging = false; self:SetScript("OnUpdate", nil) end)

    ---------------------------------------------------------------------------
    --  Right column: New, Prev, Hex#, OK
    ---------------------------------------------------------------------------
    local rightCol = CreateFrame("Frame", nil, popup)
    rightCol:SetSize(RIGHT_W, SV_SIZE)
    rightCol:SetPoint("TOPLEFT", alphaBar, "TOPRIGHT", RIGHT_GAP, 0)

    -- New preview
    local nl = MakeFont(rightCol, 10, nil, 1,1,1); nl:SetAlpha(TEXT_DIM_A)
    nl:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0); nl:SetText("New")

    newPreviewTex = rightCol:CreateTexture(nil, "ARTWORK")
    newPreviewTex:SetSize(RIGHT_W, 26); newPreviewTex:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -14)
    newPreviewTex:SetColorTexture(1,1,1,1)

    -- Prev preview (directly below New)
    local prevPrev = rightCol:CreateTexture(nil, "ARTWORK")
    prevPrev:SetSize(RIGHT_W, 26); prevPrev:SetPoint("TOPLEFT", newPreviewTex, "BOTTOMLEFT", 0, -4)
    prevPrev:SetColorTexture(1,1,1,1)
    prevPreviewTex = prevPrev

    -- Clickable overlay on prev swatch: clicking restores the previous color
    local prevBtn = CreateFrame("Button", nil, rightCol)
    prevBtn:SetAllPoints(prevPrev)
    prevBtn:SetFrameLevel(rightCol:GetFrameLevel() + 5)
    prevBtn:SetScript("OnClick", function()
        currentH, currentS, currentV = RGBtoHSV(prevR, prevG, prevB)
        currentA = hasOpacity and prevA or 1
        UpdateAllControls(); FireCallbacks()
    end)

    local pl = MakeFont(rightCol, 10, nil, 1,1,1); pl:SetAlpha(TEXT_DIM_A)
    pl:SetPoint("TOPLEFT", prevPrev, "BOTTOMLEFT", 0, -6); pl:SetText("Prev")

    -- Hex input
    local hexLbl = MakeFont(rightCol, 10, nil, 1,1,1); hexLbl:SetAlpha(TEXT_DIM_A)
    hexLbl:SetPoint("TOPLEFT", pl, "BOTTOMLEFT", 0, -21); hexLbl:SetText("Hex#")

    local hexBox = CreateFrame("EditBox", nil, rightCol)
    hexBox:SetSize(RIGHT_W, 24); hexBox:SetPoint("TOPLEFT", hexLbl, "BOTTOMLEFT", 0, -4)
    hexBox:SetFont(EXPRESSWAY, 10, ""); hexBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
    hexBox:SetMaxLetters(6); hexBox:SetAutoFocus(false); hexBox:EnableMouse(true)
    hexBox:SetJustifyH("CENTER")
    local hbg = hexBox:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(); hbg:SetColorTexture(0.22, 0.24, 0.28, 0.5)
    MakeBorder(hexBox, 1, 1, 1, 0.04, PP)

    local lastValidHex = "FFFFFF"
    local lastHexR, lastHexG, lastHexB = -1, -1, -1
    UpdateHexInput = function(r, g, b)
        if hexBox:HasFocus() then return end
        local ri, gi, bi = math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5)
        if ri == lastHexR and gi == lastHexG and bi == lastHexB then return end
        lastHexR, lastHexG, lastHexB = ri, gi, bi
        local hex = string.format("%02X%02X%02X", ri, gi, bi)
        lastValidHex = hex; hexBox:SetText(hex)
    end
    local function CommitHex()
        local txt = hexBox:GetText():upper():gsub("[^%dA-F]", "")
        if #txt == 6 then
            local ri, gi, bi = tonumber(txt:sub(1,2),16)/255, tonumber(txt:sub(3,4),16)/255, tonumber(txt:sub(5,6),16)/255
            currentH, currentS, currentV = RGBtoHSV(ri, gi, bi)
            lastValidHex = txt; UpdateAllControls(); FireCallbacks()
        else hexBox:SetText(lastValidHex) end
    end
    local hexEscaping = false
    hexBox:SetScript("OnEnterPressed", function() CommitHex(); hexBox:ClearFocus(); popup:Hide() end)
    hexBox:SetScript("OnEscapePressed", function()
        hexEscaping = true
        hexBox:SetText(lastValidHex)
        hexBox:ClearFocus()
        hexEscaping = false
        if cancelFunc then cancelFunc() end
        popup:Hide()
    end)
    hexBox:SetScript("OnEditFocusLost", function()
        if not hexEscaping then CommitHex() end
    end)
    hexBox:SetScript("OnEditFocusGained", function() hexBox:HighlightText() end)
    hexBox:SetScript("OnTextChanged", function(self, userInput)
        if not self:HasFocus() then return end
        local txt = self:GetText():upper():gsub("[^%dA-F]", "")
        if #txt == 6 then
            local ri, gi, bi = tonumber(txt:sub(1,2),16)/255, tonumber(txt:sub(3,4),16)/255, tonumber(txt:sub(5,6),16)/255
            currentH, currentS, currentV = RGBtoHSV(ri, gi, bi)
            lastValidHex = txt; UpdateAllControls(); FireCallbacks()
        end
    end)

    -- OK Button (bottom of right column, styled like reset/reload buttons)
    local okBtn = CreateFrame("Button", nil, rightCol)
    okBtn:SetSize(RIGHT_W, 21)
    okBtn:SetPoint("BOTTOMLEFT", rightCol, "BOTTOMLEFT", 0, 0)
    okBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    MakeStyledButton(okBtn, "OK", 10, RB_COLOURS, function() popup:Hide() end)

    -- Cancel text above OK button
    local cancelBtn = CreateFrame("Button", nil, rightCol)
    cancelBtn:SetSize(RIGHT_W, 14)
    cancelBtn:SetPoint("BOTTOM", okBtn, "TOP", 0, 5)
    cancelBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY")
    cancelText:SetFont(EXPRESSWAY, 10, "")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("cancel")
    cancelText:SetTextColor(1, 1, 1, 0.4)
    cancelBtn:SetScript("OnEnter", function() cancelText:SetTextColor(1, 1, 1, 0.7) end)
    cancelBtn:SetScript("OnLeave", function() cancelText:SetTextColor(1, 1, 1, 0.4) end)
    cancelBtn:SetScript("OnClick", function()
        if cancelFunc then cancelFunc() end
        popup:Hide()
    end)

    -- Hide / Escape
    popup:SetScript("OnHide", function()
        EllesmereUI._colorPickerOpen = false
        svDragging = false; hueDragging = false; alphaDragging = false
        svPad:SetScript("OnUpdate", nil)
        hueBar:SetScript("OnUpdate", nil)
        alphaBar:SetScript("OnUpdate", nil)
        local checks = EllesmereUI._deferredDriftChecks
        EllesmereUI._deferredDriftChecks = nil
        if checks then for fn in pairs(checks) do fn() end end
    end)
    tinsert(UISpecialFrames, "EllesmereUIColorPicker")
    popup:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            popup:SetPropagateKeyboardInput(false)
            if cancelFunc then cancelFunc() end
            popup:Hide()
        else popup:SetPropagateKeyboardInput(true) end
    end)

    -- Open API
    function popup:Open(info, anchorFrame)
        if popup:IsShown() and cancelFunc then cancelFunc() end
        swatchFunc = info.swatchFunc
        opacityFunc = info.opacityFunc
        cancelFunc = info.cancelFunc
        hasOpacity = info.hasOpacity or false
        local r, g, b = info.r or 0, info.g or 0, info.b or 0
        local a = info.opacity or 1
        prevR, prevG, prevB, prevA = r, g, b, a
        currentH, currentS, currentV = RGBtoHSV(r, g, b)
        currentA = hasOpacity and a or 1
        prevPreviewTex:SetColorTexture(r, g, b, hasOpacity and a or 1)
        -- Reposition right column based on alpha bar visibility
        rightCol:ClearAllPoints()
        if hasOpacity then
            alphaBar:Show()
            popup:SetWidth(BASE_W)
            rightCol:SetPoint("TOPLEFT", alphaBar, "TOPRIGHT", RIGHT_GAP, 0)
        else
            alphaBar:Hide()
            popup:SetWidth(BASE_W_NO_ALPHA)
            rightCol:SetPoint("TOPLEFT", hueBar, "TOPRIGHT", RIGHT_GAP, 0)
        end
        popup:ClearAllPoints()
        -- Position horizontally centered on cursor, vertically smart
        local cx, cy = GetCursorPosition()
        local scale = popup:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local pw = popup:GetWidth()
        local ph = popup:GetHeight()
        local x = cx - pw * 0.5
        -- Default: top of popup 30px below cursor
        local y = cy - 30
        -- If that would push below the main options window bottom, flip above cursor
        local mainFrame = EllesmereUI._mainFrame
        if mainFrame and mainFrame:IsShown() then
            local mBot = mainFrame:GetBottom()
            if mBot and (y - ph) < mBot then
                -- Bottom of popup 30px above cursor
                y = cy + 30 + ph
            end
        end
        popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        EllesmereUI._colorPickerOpen = true
        popup:Show(); UpdateAllControls()
    end

    EllesmereUI._colorPickerPopup = popup
    return popup
end

function EllesmereUI:ShowColorPicker(info, anchorFrame)
    local popup = self._colorPickerPopup or BuildColorPickerPopup()
    popup:Open(info, anchorFrame)
end

-- Shared color swatch builder: rainbow/white crossfade border + fill + UpdateSwatch + OnClick
-- Returns swatch (Button), UpdateSwatch (function)
-- Caller is responsible for positioning (SetPoint) before calling this.
-- The rainbow border image + white border textures are deferred until the swatch
-- is first shown, keeping initial page build lightweight.
local function BuildColorSwatch(parentFrame, baseLevel, getValue, setValue, hasAlpha, overrideSize)
    local SWATCH_SZ = overrideSize or 24
    local swatch = CreateFrame("Button", nil, parentFrame)
    PP.Size(swatch, SWATCH_SZ, SWATCH_SZ)
    swatch:SetFrameLevel(baseLevel)

    -- Color fill (always created immediately -- 1 texture)
    local sFill = swatch:CreateTexture(nil, "ARTWORK")
    sFill:SetAllPoints()

    -- Border state (populated lazily)
    local borderBuilt = false
    local brdFrame, rainbowFrame, whiteFrame
    local rainbowFadeAG, whiteFadeAG
    local currentBorderIsWhite = false

    local function BuildBorder()
        if borderBuilt then return end
        borderBuilt = true
        local T = CS.BRD_THICK

        brdFrame = CreateFrame("Frame", nil, swatch)
        brdFrame:SetAllPoints()
        brdFrame:SetFrameLevel(swatch:GetFrameLevel() + 1)

        -- Rainbow border: uses PP for pixel-perfect at any panel scale
        rainbowFrame = CreateFrame("Frame", nil, brdFrame)
        rainbowFrame:SetAllPoints()
        rainbowFrame:SetFrameLevel(brdFrame:GetFrameLevel())
        local rbT = rainbowFrame:CreateTexture(nil, "BORDER")
        rbT:SetTexture(MEDIA_PATH .. "icons\\rainbow-border-top.png")
        rbT:SetPoint("BOTTOMLEFT", swatch, "TOPLEFT", -T, -T); rbT:SetPoint("BOTTOMRIGHT", swatch, "TOPRIGHT", T, -T); PP.Height(rbT, 2 * T)
        local rbB = rainbowFrame:CreateTexture(nil, "BORDER")
        rbB:SetTexture(MEDIA_PATH .. "icons\\rainbow-border-bottom.png")
        rbB:SetPoint("TOPLEFT", swatch, "BOTTOMLEFT", -T, T); rbB:SetPoint("TOPRIGHT", swatch, "BOTTOMRIGHT", T, T); PP.Height(rbB, 2 * T)
        local rbL = rainbowFrame:CreateTexture(nil, "BORDER")
        rbL:SetTexture(MEDIA_PATH .. "icons\\rainbow-border-left.png")
        rbL:SetPoint("TOPLEFT", rbT, "BOTTOMLEFT", 0, 0); rbL:SetPoint("BOTTOMLEFT", rbB, "TOPLEFT", 0, 0); PP.Width(rbL, 2 * T)
        local rbR = rainbowFrame:CreateTexture(nil, "BORDER")
        rbR:SetTexture(MEDIA_PATH .. "icons\\rainbow-border-right.png")
        rbR:SetPoint("TOPRIGHT", rbT, "BOTTOMRIGHT", 0, 0); rbR:SetPoint("BOTTOMRIGHT", rbB, "TOPRIGHT", 0, 0); PP.Width(rbR, 2 * T)

        -- Solid white border (shown for colorful/saturated colors)
        whiteFrame = CreateFrame("Frame", nil, brdFrame)
        whiteFrame:SetAllPoints()
        whiteFrame:SetFrameLevel(brdFrame:GetFrameLevel())
        local wt = whiteFrame:CreateTexture(nil, "BORDER")
        wt:SetColorTexture(CS.SOLID_R, CS.SOLID_G, CS.SOLID_B, CS.SOLID_A)
        wt:SetPoint("BOTTOMLEFT", swatch, "TOPLEFT", -T, 0); wt:SetPoint("BOTTOMRIGHT", swatch, "TOPRIGHT", T, 0); PP.Height(wt, T)
        local wb = whiteFrame:CreateTexture(nil, "BORDER")
        wb:SetColorTexture(CS.SOLID_R, CS.SOLID_G, CS.SOLID_B, CS.SOLID_A)
        wb:SetPoint("TOPLEFT", swatch, "BOTTOMLEFT", -T, 0); wb:SetPoint("TOPRIGHT", swatch, "BOTTOMRIGHT", T, 0); PP.Height(wb, T)
        local wl = whiteFrame:CreateTexture(nil, "BORDER")
        wl:SetColorTexture(CS.SOLID_R, CS.SOLID_G, CS.SOLID_B, CS.SOLID_A)
        wl:SetPoint("TOPLEFT", swatch, "TOPLEFT", -T, 0); wl:SetPoint("BOTTOMLEFT", swatch, "BOTTOMLEFT", -T, 0); PP.Width(wl, T)
        local wr = whiteFrame:CreateTexture(nil, "BORDER")
        wr:SetColorTexture(CS.SOLID_R, CS.SOLID_G, CS.SOLID_B, CS.SOLID_A)
        wr:SetPoint("TOPRIGHT", swatch, "TOPRIGHT", T, 0); wr:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", T, 0); PP.Width(wr, T)

        -- Crossfade setup
        whiteFrame:SetAlpha(0)
        rainbowFrame:SetAlpha(1)

        local function MakeFade(frm)
            local ag = frm:CreateAnimationGroup()
            local anim = ag:CreateAnimation("Alpha")
            anim:SetDuration(0.25); anim:SetSmoothing("IN_OUT")
            ag.anim = anim
            ag:SetScript("OnFinished", function() frm:SetAlpha(ag.targetAlpha) end)
            return ag
        end
        rainbowFadeAG = MakeFade(rainbowFrame)
        whiteFadeAG   = MakeFade(whiteFrame)

        -- Apply initial state without fade
        local r, g, b = getValue()
        r, g, b = r or 0, g or 0, b or 0
        local maxC = math.max(r, g, b)
        local minC = math.min(r, g, b)
        local chroma = maxC - minC
        local lightness = (maxC + minC) / 2
        local sat = 0
        if chroma > 0 and lightness > 0 and lightness < 1 then
            sat = chroma / (1 - math.abs(2 * lightness - 1))
        end
        currentBorderIsWhite = sat > CS.SAT_THRESH and chroma >= CS.CHROMA_MIN
        whiteFrame:SetAlpha(currentBorderIsWhite and 1 or 0)
        rainbowFrame:SetAlpha(currentBorderIsWhite and 0 or 1)
    end

    local function FadeTo(frm, ag, targetAlpha)
        if frm:GetAlpha() == targetAlpha then return end
        ag:Stop(); ag.targetAlpha = targetAlpha
        ag.anim:SetFromAlpha(frm:GetAlpha()); ag.anim:SetToAlpha(targetAlpha)
        ag:Play()
    end

    local function UpdateSwatch(skipFade)
        local r, g, b, a = getValue()
        r, g, b = r or 0, g or 0, b or 0
        sFill:SetColorTexture(r, g, b, a or 1)
        -- Border update only if border has been built
        if not borderBuilt then return end
        local maxC = math.max(r, g, b)
        local minC = math.min(r, g, b)
        local chroma = maxC - minC
        local lightness = (maxC + minC) / 2
        local sat = 0
        if chroma > 0 and lightness > 0 and lightness < 1 then
            sat = chroma / (1 - math.abs(2 * lightness - 1))
        end
        local wantWhite = sat > CS.SAT_THRESH and chroma >= CS.CHROMA_MIN
        if wantWhite ~= currentBorderIsWhite then
            currentBorderIsWhite = wantWhite
            if skipFade then
                whiteFrame:SetAlpha(wantWhite and 1 or 0)
                rainbowFrame:SetAlpha(wantWhite and 0 or 1)
                rainbowFadeAG:Stop(); whiteFadeAG:Stop()
            else
                FadeTo(whiteFrame, whiteFadeAG, wantWhite and 1 or 0)
                FadeTo(rainbowFrame, rainbowFadeAG, wantWhite and 0 or 1)
            end
        end
    end

    -- Set initial fill color immediately (no border needed yet)
    do
        local r, g, b, a = getValue()
        sFill:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    end

    -- Build border lazily on first show
    swatch:HookScript("OnShow", function()
        if not borderBuilt then BuildBorder() end
    end)
    -- If already visible, build now
    if swatch:IsVisible() then BuildBorder() end

    -- OnClick: open custom EllesmereUI color picker
    swatch:SetScript("OnClick", function()
        local r, g, b, a = getValue()
        r, g, b, a = r or 0, g or 0, b or 0, a or 1
        local snapR, snapG, snapB, snapA = r, g, b, a
        local function OnColorChanged()
            local popup = EllesmereUI._colorPickerPopup
            if not popup then return end
            local cr, cg, cb = popup:GetColorRGB()
            local ca = hasAlpha and popup:GetColorAlpha() or 1
            sFill:SetColorTexture(cr, cg, cb, ca)
            setValue(cr, cg, cb, ca)
            UpdateSwatch()
        end
        local info = {
            swatchFunc = function() OnColorChanged() end,
            hasOpacity = hasAlpha,
            opacityFunc = function() OnColorChanged() end,
            opacity = a,
            cancelFunc = function() setValue(snapR, snapG, snapB, snapA); UpdateSwatch() end,
            r = r, g = g, b = b,
        }
        EllesmereUI:ShowColorPicker(info, swatch)
    end)

    return swatch, UpdateSwatch
end

-- Color Picker  (swatch that opens Blizzard's ColorPickerFrame)
function WidgetFactory:ColorPicker(parent, text, yOffset, getValue, setValue, hasAlpha)
    local ROW_H = 50
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)

    RowBg(frame, parent)
    TagOptionRow(frame, parent, text)

    local label = MakeFont(frame, 14, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b)
    PP.Point(label, "LEFT", frame, "LEFT", 20, 0)
    label:SetText(text)

    local swatch, UpdateSwatch = BuildColorSwatch(frame, frame:GetFrameLevel() + 1, getValue, setValue, hasAlpha)
    PP.Point(swatch, "RIGHT", frame, "RIGHT", -20, 0)

    -- Expose a refresh method so external code can update the swatch after bar changes
    frame.RefreshSwatch = UpdateSwatch
    RegisterWidgetRefresh(function() UpdateSwatch() end)

    return frame, ROW_H
end

-- Button  (execute action, matches the reset/reload button style)
function WidgetFactory:Button(parent, text, yOffset, onClick)
    local ROW_H = 50
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    RowBg(frame, parent)
    TagOptionRow(frame, parent, text)
    local btn = CreateFrame("Button", nil, frame)
    PP.Size(btn, 200, 32)
    PP.Point(btn, "LEFT", frame, "LEFT", 20, 0)
    btn:SetFrameLevel(frame:GetFrameLevel() + 1)
    MakeStyledButton(btn, text, 13, RB_COLOURS, onClick)
    return frame, ROW_H
end

-- WideButton  (centered, no row background, customizable width -- for prominent actions)
function WidgetFactory:WideButton(parent, text, yOffset, onClick, btnWidth)
    btnWidth = btnWidth or 450
    local BTN_H = 42
    local ROW_H = BTN_H + 20
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    TagOptionRow(frame, parent, text)
    local btn = CreateFrame("Button", nil, frame)
    PP.Size(btn, btnWidth, BTN_H)
    PP.Point(btn, "CENTER", frame, "CENTER", 0, 0)
    btn:SetFrameLevel(frame:GetFrameLevel() + 1)
    MakeStyledButton(btn, text, 14, WB_COLOURS, onClick)
    return frame, ROW_H
end

-- DualRow  (two widgets side by side on a single full-width row with 1px center divider)
-- Each side: { type = "slider"|"dropdown"|"toggle"|"colorpicker", ... }
-- Slider:      { type="slider", text, min, max, step, getValue, setValue }
-- Dropdown:    { type="dropdown", text, values, getValue, setValue, order }
-- Toggle:      { type="toggle", text, getValue, setValue }
-- ColorPicker: { type="colorpicker", text, getValue, setValue, hasAlpha }
function WidgetFactory:DualRow(parent, yOffset, leftCfg, rightCfg)
    local ROW_H = 50
    local SIDE_PAD = 20  -- padding inside each half
    local frame = CreateFrame("Frame", nil, parent)
    local totalW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(frame, totalW, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    if not rightCfg then frame._skipRowDivider = true end
    RowBg(frame, parent)
    -- Search metadata: combine both labels
    local dualLabel = (leftCfg and leftCfg.text or "")
    if rightCfg and rightCfg.text then dualLabel = dualLabel .. " " .. rightCfg.text end
    TagOptionRow(frame, parent, dualLabel)

    -- Half regions (invisible, just for anchoring)
    local fullWidth = not rightCfg
    local halfW = math.floor(totalW / 2)
    local leftRegion = CreateFrame("Frame", nil, frame)
    leftRegion:SetSize(fullWidth and totalW or halfW, ROW_H)
    leftRegion:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    local rightRegion = CreateFrame("Frame", nil, frame)
    rightRegion:SetSize(halfW, ROW_H)
    rightRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    -- Helper: populate one half with a widget
    local function BuildHalf(region, cfg)
        if not cfg then return end
        local t = cfg.type
        -- Label (all types have one)
        local label = MakeFont(region, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        PP.Point(label, "LEFT", region, "LEFT", SIDE_PAD, 0)
        label:SetText(cfg.text or "")
        region._label = label

        -- Tooltip on the label text.  For dropdowns the hitFrame is created
        -- after the dropdown button so it can check whether the menu is open.
        if (cfg.tooltip or cfg.disabledTooltip) and t ~= "dropdown" then
            local ttOpts = cfg.tooltipOpts
            local hitFrame = CreateFrame("Frame", nil, region)
            hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
            hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
            hitFrame:SetFrameLevel(region:GetFrameLevel() + 10)
            hitFrame:SetScript("OnEnter", function()
                if cfg.disabled and cfg.disabled() and cfg.disabledTooltip then
                    local tt = cfg.disabledTooltip
                    if type(tt) == "function" then tt = tt() end
                    ShowWidgetTooltip(label, DisabledTooltip(tt))
                elseif cfg.tooltip then
                    ShowWidgetTooltip(label, cfg.tooltip, ttOpts)
                end
            end)
            hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
            -- Pass through clicks by default so controls remain interactive
            hitFrame:SetMouseClickEnabled(false)
            -- When disabled, intercept clicks to prevent interaction
            if cfg.disabled and cfg.disabledTooltip then
                local function UpdateHitMouse()
                    hitFrame:SetMouseClickEnabled(cfg.disabled() and true or false)
                end
                RegisterWidgetRefresh(UpdateHitMouse)
                UpdateHitMouse()
            end
        end

        -- Disabled state support: cfg.disabled is an optional function returning bool.
        -- When true, the label is dimmed and the control is non-interactive.
        local disabledOverlay  -- optional dark overlay to gray out the whole half
        local controlFrame     -- the clickable control (dropdown btn, toggle, etc.)
        local controlAnchor    -- the main control frame for inline element anchoring

        local function ApplyDisabledState()
            if not cfg.disabled then return end
            local off = cfg.disabled()
            label:SetAlpha(off and 0.3 or 1)
            if controlFrame then
                if off then
                    controlFrame:EnableMouse(false)
                    controlFrame:SetAlpha(0.3)
                else
                    controlFrame:EnableMouse(true)
                    controlFrame:SetAlpha(1)
                end
            end
        end

        if t == "slider" then
            local trackFrame, valBox, _, slThumb = BuildSliderCore(region, cfg.trackWidth or 160, 4, 14, 40, 26, 13, SL.INPUT_A,
                cfg.min, cfg.max, cfg.step, cfg.getValue, cfg.setValue, true, cfg.snapPoints)
            PP.Point(valBox, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            PP.Point(trackFrame, "RIGHT", valBox, "LEFT", -12, 0)
            controlFrame = nil  -- slider handles its own disabled state; don't let generic handler disable mouse
            AddControlDisabledTooltip(trackFrame, cfg)
            RegisterWidgetRefresh(function()
                if cfg.disabled then
                    local off = cfg.disabled()
                    label:SetAlpha(off and 0.3 or 1)
                    trackFrame:SetAlpha(off and 0.3 or 1)
                    valBox:EnableMouse(not off)
                    valBox:SetAlpha(off and 0.3 or 1)
                    if slThumb then slThumb._sliderDisabled = off end
                end
            end)
            -- Initial apply
            if cfg.disabled then
                local off = cfg.disabled()
                label:SetAlpha(off and 0.3 or 1)
                trackFrame:SetAlpha(off and 0.3 or 1)
                valBox:EnableMouse(not off)
                valBox:SetAlpha(off and 0.3 or 1)
                if slThumb then slThumb._sliderDisabled = off end
            end
            controlAnchor = trackFrame

        elseif t == "dropdown" then
            local DD_W = 170
            -- Bridge itemDisabled/itemDisabledTooltip into disabledValuesFn for BuildDropdownControl
            local ddDisabledFn = cfg.disabledValues
            if not ddDisabledFn and cfg.itemDisabled then
                ddDisabledFn = function(v)
                    if cfg.itemDisabled(v) then
                        if cfg.itemDisabledTooltip then
                            local tip = cfg.itemDisabledTooltip(v)
                            if tip then return DisabledTooltip(tip) end
                        end
                        return true
                    end
                    return false
                end
            end
            local ddBtn, ddLbl = BuildDropdownControl(region, DD_W, frame:GetFrameLevel() + 2, cfg.values, cfg.order, cfg.getValue, cfg.setValue, ddDisabledFn)
            PP.Point(ddBtn, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            controlFrame = ddBtn
            controlAnchor = ddBtn
            if cfg.labelOnlyDisabled then
                AddControlDisabledTooltip(label, cfg)
            else
                AddControlDisabledTooltip(ddBtn, cfg)
            end
            -- Store tooltip config on the button -- WireDropdownScripts and the
            -- pre-menu hover scripts read ddBtn._ttText / ddBtn._ttOpts to
            -- show/hide the tooltip at the right times.
            if cfg.tooltip or (cfg.disabledTooltip and cfg.disabled) then
                if cfg.tooltip then
                    ddBtn._ttText = cfg.tooltip
                    ddBtn._ttOpts = cfg.tooltipOpts
                end
                local ttOpts = cfg.tooltipOpts
                local hitFrame = CreateFrame("Frame", nil, region)
                hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
                hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
                hitFrame:SetFrameLevel(region:GetFrameLevel() + 10)
                hitFrame:SetScript("OnEnter", function()
                    if cfg.disabled and cfg.disabled() and cfg.disabledTooltip then
                        local tt = cfg.disabledTooltip
                        if type(tt) == "function" then tt = tt() end
                        ShowWidgetTooltip(label, DisabledTooltip(tt))
                    elseif cfg.tooltip and not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown()) then
                        ShowWidgetTooltip(label, cfg.tooltip, ttOpts)
                    end
                end)
                hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
                hitFrame:SetMouseClickEnabled(false)
                -- When disabled, intercept clicks to prevent interaction with label area
                if cfg.disabled and cfg.disabledTooltip then
                    local function UpdateHitMouse()
                        hitFrame:SetMouseClickEnabled(cfg.disabled() and true or false)
                    end
                    RegisterWidgetRefresh(UpdateHitMouse)
                    UpdateHitMouse()
                end
            end
            if cfg.labelOnlyDisabled and cfg.disabled then
                local function ApplyLabelOnly()
                    local off = cfg.disabled()
                    label:SetAlpha(1)
                end
                RegisterWidgetRefresh(function()
                    ddLbl:SetText(DDResolveLabel(cfg.values, cfg.order or {}, cfg.getValue()))
                    ApplyLabelOnly()
                end)
                ApplyLabelOnly()
            else
                RegisterWidgetRefresh(function()
                    ddLbl:SetText(DDResolveLabel(cfg.values, cfg.order or {}, cfg.getValue()))
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            end

        elseif t == "toggle" then
            local toggle, _, tgSnap = BuildToggleControl(region, frame:GetFrameLevel() + 2, cfg.getValue, cfg.setValue)
            toggle:SetPoint("RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            controlFrame = toggle
            controlAnchor = toggle
            AddControlDisabledTooltip(toggle, cfg)
            RegisterWidgetRefresh(function()
                tgSnap()
                ApplyDisabledState()
            end)
            ApplyDisabledState()

        elseif t == "colorpicker" then
            local swatch, _updateSwatch = BuildColorSwatch(region, frame:GetFrameLevel() + 2, cfg.getValue, cfg.setValue, cfg.hasAlpha)
            PP.Point(swatch, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            controlFrame = swatch
            controlAnchor = swatch
            AddControlDisabledTooltip(swatch, cfg)
            RegisterWidgetRefresh(function() _updateSwatch(); ApplyDisabledState() end)
            ApplyDisabledState()

        elseif t == "button" then
            -- Button inside a half-row: label is hidden, the button IS the content
            label:Hide()
            local btn = CreateFrame("Button", nil, region)
            PP.Size(btn, cfg.width or 180, 32)
            PP.Point(btn, "CENTER", region, "CENTER", 0, 0)
            btn:SetFrameLevel(frame:GetFrameLevel() + 2)
            MakeStyledButton(btn, cfg.text or "", 13, RB_COLOURS, cfg.onClick)
            controlFrame = btn
            controlAnchor = btn
            RegisterWidgetRefresh(function() ApplyDisabledState() end)
            ApplyDisabledState()

        elseif t == "multiSwatch" then
            -- Label + N color swatches laid out right-to-left from the right edge
            local SWATCH_SZ = 24
            local SWATCH_GAP = 8
            local swatches = cfg.swatches or {}
            local anchorX = -SIDE_PAD
            local leftmostSwatch
            for i = #swatches, 1, -1 do
                local sc = swatches[i]
                local swatch, updateSwatch = BuildColorSwatch(region, frame:GetFrameLevel() + 2, sc.getValue, sc.setValue, sc.hasAlpha)
                PP.Point(swatch, "RIGHT", region, "RIGHT", anchorX, 0)
                anchorX = anchorX - SWATCH_SZ - SWATCH_GAP
                leftmostSwatch = swatch
                -- Override click handler if provided (e.g. class color toggle)
                if sc.onClick then
                    swatch._eabOrigClick = swatch:GetScript("OnClick")
                    swatch:SetScript("OnClick", sc.onClick)
                end
                -- Per-swatch disabled overlay (same pattern as AuraBuffReminders)
                if sc.disabled then
                    local swatchBlock = CreateFrame("Frame", nil, swatch)
                    swatchBlock:SetAllPoints()
                    swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
                    swatchBlock:EnableMouse(true)
                    swatchBlock:SetScript("OnEnter", function()
                        local tip = sc.disabledTooltip
                        if type(tip) == "function" then tip = tip() end
                        if tip then ShowWidgetTooltip(swatch, DisabledTooltip(tip)) end
                    end)
                    swatchBlock:SetScript("OnLeave", function() HideWidgetTooltip() end)
                    local function UpdateSwatchDisabled()
                        local dis = type(sc.disabled) == "function" and sc.disabled() or sc.disabled
                        if dis then
                            swatch:SetAlpha(0.3)
                            swatchBlock:Show()
                        else
                            swatch:SetAlpha(1)
                            swatchBlock:Hide()
                        end
                    end
                    UpdateSwatchDisabled()
                    RegisterWidgetRefresh(UpdateSwatchDisabled)
                end
                -- Tooltip on hover (only when not disabled)
                if sc.tooltip then
                    swatch:HookScript("OnEnter", function()
                        ShowWidgetTooltip(swatch, sc.tooltip)
                    end)
                    swatch:HookScript("OnLeave", function()
                        HideWidgetTooltip()
                    end)
                end
                -- Per-swatch alpha refresh (e.g. dim inactive, bright active)
                if sc.refreshAlpha then
                    local _sw, _ra, _sd = swatch, sc.refreshAlpha, sc.disabled
                    local function UpdateAlpha()
                        -- Skip when disabled -- disabled handler controls alpha
                        if _sd then
                            local dis = type(_sd) == "function" and _sd() or _sd
                            if dis then return end
                        end
                        _sw:SetAlpha(_ra())
                    end
                    UpdateAlpha()
                    RegisterWidgetRefresh(UpdateAlpha)
                end
                RegisterWidgetRefresh(function() updateSwatch() end)
            end
            controlAnchor = leftmostSwatch
            -- Row-level disabled state
            RegisterWidgetRefresh(function() ApplyDisabledState() end)
            ApplyDisabledState()
        end
        region._control = controlAnchor or controlFrame
    end

    BuildHalf(leftRegion, leftCfg)
    BuildHalf(rightRegion, rightCfg)

    -- Slot-level search labels for per-slot highlighting
    leftRegion._slotLabel  = leftCfg and leftCfg.text or ""
    rightRegion._slotLabel = rightCfg and rightCfg.text or ""

    -- Store dropdown getValue/values for dynamic search matching
    if leftCfg and leftCfg.type == "dropdown" then
        leftRegion._ddGetValue = leftCfg.getValue
        leftRegion._ddValues  = leftCfg.values
    end
    if rightCfg and rightCfg.type == "dropdown" then
        rightRegion._ddGetValue = rightCfg.getValue
        rightRegion._ddValues  = rightCfg.values
    end

    -- 1px center divider (matches global BORDER style)
    if not fullWidth then
        local div = frame:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(BORDER_R, BORDER_G, BORDER_B, 0.05)
        div:SetWidth(1)
        div:SetPoint("TOP", frame, "TOP", 0, 0)
        div:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    end

    -- Expose half regions so callers can anchor child elements to them
    frame._leftRegion  = leftRegion
    frame._rightRegion = rightRegion

    return frame, ROW_H
end

-- TripleRow  (three widgets side by side on a single full-width row with 1px dividers at 1/3 and 2/3)
-- Each column: same cfg format as DualRow  { type = "slider"|"dropdown"|"toggle"|"colorpicker", ... }
function WidgetFactory:TripleRow(parent, yOffset, leftCfg, midCfg, rightCfg, splits)
    local ROW_H = (splits and splits.rowHeight) or 50
    local SIDE_PAD = 20
    local frame = CreateFrame("Frame", nil, parent)
    local totalW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(frame, totalW, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    frame._skipRowDivider = true
    RowBg(frame, parent)
    -- Search metadata: combine all labels
    local triLabel = (leftCfg and leftCfg.text or "") .. " " .. (midCfg and midCfg.text or "") .. " " .. (rightCfg and rightCfg.text or "")
    TagOptionRow(frame, parent, triLabel)

    -- Custom or default 44% / 28% / 28% split
    local leftW  = math.floor(totalW * ((splits and splits[1]) or 0.44))
    local midW   = math.floor(totalW * ((splits and splits[2]) or 0.28))
    local rightW = totalW - leftW - midW

    local leftRegion = CreateFrame("Frame", nil, frame)
    leftRegion:SetSize(leftW, ROW_H)
    leftRegion:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    local midRegion = CreateFrame("Frame", nil, frame)
    midRegion:SetSize(midW, ROW_H)
    midRegion:SetPoint("TOPLEFT", leftRegion, "TOPRIGHT", 0, 0)

    local rightRegion = CreateFrame("Frame", nil, frame)
    rightRegion:SetSize(rightW, ROW_H)
    rightRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local function BuildThird(region, cfg)
        if not cfg then return end
        local t = cfg.type
        local label = MakeFont(region, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        PP.Point(label, "LEFT", region, "LEFT", SIDE_PAD, 0)
        label:SetText(cfg.text or "")

        if (cfg.tooltip or cfg.disabledTooltip) and t ~= "dropdown" then
            local ttOpts = cfg.tooltipOpts
            local hitFrame = CreateFrame("Frame", nil, region)
            hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
            hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
            hitFrame:SetFrameLevel(region:GetFrameLevel() + 10)
            hitFrame:SetScript("OnEnter", function()
                if cfg.disabled and cfg.disabled() and cfg.disabledTooltip then
                    local tt = cfg.disabledTooltip
                    if type(tt) == "function" then tt = tt() end
                    ShowWidgetTooltip(label, DisabledTooltip(tt))
                elseif cfg.tooltip then
                    ShowWidgetTooltip(label, cfg.tooltip, ttOpts)
                end
            end)
            hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
            -- Pass through clicks by default so controls remain interactive
            hitFrame:SetMouseClickEnabled(false)
            -- When disabled, intercept clicks to prevent interaction
            if cfg.disabled and cfg.disabledTooltip then
                local function UpdateHitMouse()
                    hitFrame:SetMouseClickEnabled(cfg.disabled() and true or false)
                end
                RegisterWidgetRefresh(UpdateHitMouse)
                UpdateHitMouse()
            end
        end

        local controlFrame
        local function ApplyDisabledState()
            if not cfg.disabled then return end
            local off = cfg.disabled()
            label:SetAlpha(off and 0.3 or 1)
            if controlFrame then
                if off then
                    controlFrame:EnableMouse(false)
                    controlFrame:SetAlpha(0.3)
                else
                    controlFrame:EnableMouse(true)
                    controlFrame:SetAlpha(1)
                end
            end
        end

        if t == "slider" then
            local trackFrame, valBox, _, slThumb = BuildSliderCore(region, cfg.trackWidth or 130, 4, 14, 40, 26, 13, SL.INPUT_A,
                cfg.min, cfg.max, cfg.step, cfg.getValue, cfg.setValue, true, cfg.snapPoints)
            PP.Point(valBox, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            PP.Point(trackFrame, "RIGHT", valBox, "LEFT", -12, 0)
            RegisterWidgetRefresh(function()
                if cfg.disabled then
                    local off = cfg.disabled()
                    label:SetAlpha(off and 0.3 or 1)
                    trackFrame:SetAlpha(off and 0.3 or 1)
                    valBox:EnableMouse(not off)
                    valBox:SetAlpha(off and 0.3 or 1)
                    if slThumb then slThumb._sliderDisabled = off end
                end
            end)
            if cfg.disabled then
                local off = cfg.disabled()
                label:SetAlpha(off and 0.3 or 1)
                trackFrame:SetAlpha(off and 0.3 or 1)
                valBox:EnableMouse(not off)
                valBox:SetAlpha(off and 0.3 or 1)
                if slThumb then slThumb._sliderDisabled = off end
            end

        elseif t == "dropdown" then
            local DD_W = cfg.dropdownWidth or 170
            -- Bridge itemDisabled/itemDisabledTooltip into disabledValuesFn for BuildDropdownControl
            local ddDisabledFn = cfg.disabledValues
            if not ddDisabledFn and cfg.itemDisabled then
                ddDisabledFn = function(v)
                    if cfg.itemDisabled(v) then
                        if cfg.itemDisabledTooltip then
                            local tip = cfg.itemDisabledTooltip(v)
                            if tip then return DisabledTooltip(tip) end
                        end
                        return true
                    end
                    return false
                end
            end
            local ddBtn, ddLbl = BuildDropdownControl(region, DD_W, frame:GetFrameLevel() + 2, cfg.values, cfg.order, cfg.getValue, cfg.setValue, ddDisabledFn)
            PP.Point(ddBtn, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            controlFrame = ddBtn
            if cfg.labelOnlyDisabled then
                AddControlDisabledTooltip(label, cfg)
            else
                AddControlDisabledTooltip(ddBtn, cfg)
            end
            if cfg.tooltip or (cfg.disabledTooltip and cfg.disabled) then
                if cfg.tooltip then
                    ddBtn._ttText = cfg.tooltip
                    ddBtn._ttOpts = cfg.tooltipOpts
                end
                local ttOpts = cfg.tooltipOpts
                local hitFrame = CreateFrame("Frame", nil, region)
                hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
                hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
                hitFrame:SetFrameLevel(region:GetFrameLevel() + 10)
                hitFrame:SetScript("OnEnter", function()
                    if cfg.disabled and cfg.disabled() and cfg.disabledTooltip then
                        local tt = cfg.disabledTooltip
                        if type(tt) == "function" then tt = tt() end
                        ShowWidgetTooltip(label, DisabledTooltip(tt))
                    elseif cfg.tooltip and not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown()) then
                        ShowWidgetTooltip(label, cfg.tooltip, ttOpts)
                    end
                end)
                hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
                hitFrame:SetMouseClickEnabled(false)
                if cfg.disabled and cfg.disabledTooltip then
                    local function UpdateHitMouse()
                        hitFrame:SetMouseClickEnabled(cfg.disabled() and true or false)
                    end
                    RegisterWidgetRefresh(UpdateHitMouse)
                    UpdateHitMouse()
                end
            end
            if cfg.labelOnlyDisabled and cfg.disabled then
                local function ApplyLabelOnly()
                    local off = cfg.disabled()
                    label:SetAlpha(1)
                    -- Gray out the dropdown button label when the current value is disabled
                    if cfg.disabledValues then
                        local curVal = cfg.getValue()
                        ddLbl:SetAlpha(cfg.disabledValues(curVal) and 0.15 or DD_TXT_A)
                    end
                end
                RegisterWidgetRefresh(function()
                    ddLbl:SetText(DDResolveLabel(cfg.values, cfg.order or {}, cfg.getValue()))
                    ApplyLabelOnly()
                    if ddBtn._ddRefresh then ddBtn._ddRefresh() end
                end)
                ApplyLabelOnly()
            else
                RegisterWidgetRefresh(function()
                    ddLbl:SetText(DDResolveLabel(cfg.values, cfg.order or {}, cfg.getValue()))
                    ApplyDisabledState()
                    if ddBtn._ddRefresh then ddBtn._ddRefresh() end
                end)
                ApplyDisabledState()
            end

        elseif t == "toggle" then
            local toggle, _, tgSnap = BuildToggleControl(region, frame:GetFrameLevel() + 2, cfg.getValue, cfg.setValue)
            toggle:SetPoint("RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            controlFrame = toggle
            AddControlDisabledTooltip(toggle, cfg)
            RegisterWidgetRefresh(function()
                tgSnap()
                ApplyDisabledState()
            end)
            ApplyDisabledState()

        elseif t == "colorpicker" then
            local swatch, _updateSwatch = BuildColorSwatch(region, frame:GetFrameLevel() + 2, cfg.getValue, cfg.setValue, cfg.hasAlpha)
            PP.Point(swatch, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            controlFrame = swatch
            RegisterWidgetRefresh(function() _updateSwatch(); ApplyDisabledState() end)
            ApplyDisabledState()

        elseif t == "checkbox" then
            -- Hide the generic label; checkbox draws its own label+box
            label:Hide()
            local btn = CreateFrame("Button", nil, region)
            btn:SetSize(region:GetWidth(), ROW_H)
            btn:SetAllPoints(region)
            btn:SetFrameLevel(frame:GetFrameLevel() + 2)

            local box, check, boxBorder, cbApply = BuildCheckboxControl(btn, frame:GetFrameLevel() + 2)
            box:SetPoint("LEFT", btn, "LEFT", SIDE_PAD, 0)

            local cbLabel = MakeFont(btn, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
            cbLabel:SetPoint("LEFT", box, "RIGHT", 10, 0)
            cbLabel:SetText(cfg.text or "")

            local isHovering = false
            local function ApplyCBVisual()
                local on = cfg.getValue()
                cbApply(on, isHovering)
                if on then
                    cbLabel:SetTextColor(TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B, 1)
                else
                    local a = isHovering and 1 or 0.8
                    cbLabel:SetTextColor(TEXT_WHITE_R * a, TEXT_WHITE_G * a, TEXT_WHITE_B * a, a)
                end
            end
            ApplyCBVisual()

            btn:SetScript("OnClick", function()
                local v = not cfg.getValue()
                cfg.setValue(v)
                ApplyCBVisual()
            end)
            btn:SetScript("OnEnter", function() isHovering = true; ApplyCBVisual() end)
            btn:SetScript("OnLeave", function() isHovering = false; ApplyCBVisual() end)

            controlFrame = btn
            RegisterWidgetRefresh(function() ApplyCBVisual(); ApplyDisabledState() end)
            ApplyDisabledState()
        elseif t == "button" then
            label:Hide()
            local btn = CreateFrame("Button", nil, region)
            PP.Size(btn, cfg.width or 140, 32)
            PP.Point(btn, "CENTER", region, "CENTER", 0, 0)
            btn:SetFrameLevel(frame:GetFrameLevel() + 2)
            MakeStyledButton(btn, cfg.text or "", 13, RB_COLOURS, cfg.onClick)
            controlFrame = btn
            RegisterWidgetRefresh(function() ApplyDisabledState() end)
            ApplyDisabledState()
        end
    end

    BuildThird(leftRegion, leftCfg)
    BuildThird(midRegion, midCfg)
    BuildThird(rightRegion, rightCfg)

    -- Slot-level search labels for per-slot highlighting
    leftRegion._slotLabel  = leftCfg and leftCfg.text or ""
    midRegion._slotLabel   = midCfg and midCfg.text or ""
    rightRegion._slotLabel = rightCfg and rightCfg.text or ""

    -- Store dropdown getValue/values for dynamic search matching
    if leftCfg and leftCfg.type == "dropdown" then
        leftRegion._ddGetValue = leftCfg.getValue
        leftRegion._ddValues  = leftCfg.values
    end
    if midCfg and midCfg.type == "dropdown" then
        midRegion._ddGetValue = midCfg.getValue
        midRegion._ddValues  = midCfg.values
    end
    if rightCfg and rightCfg.type == "dropdown" then
        rightRegion._ddGetValue = rightCfg.getValue
        rightRegion._ddValues  = rightCfg.values
    end

    -- 1px dividers at column boundaries (same style as RowBg center divider)
    for _, rgn in ipairs({ leftRegion, midRegion }) do
        local div = frame:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.06)
        if div.SetSnapToPixelGrid then div:SetSnapToPixelGrid(false); div:SetTexelSnappingBias(0) end
        div:SetWidth(1)
        PP.Point(div, "TOP", rgn, "TOPRIGHT", 0, 0)
        PP.Point(div, "BOTTOM", rgn, "BOTTOMRIGHT", 0, 0)
    end

    frame._leftRegion  = leftRegion
    frame._midRegion   = midRegion
    frame._rightRegion = rightRegion

    return frame, ROW_H
end

-- MultiSwatchRow  (label on left, N full-size color swatches on right with tooltips)
-- cfg = {
--   text = "Row Label",
--   swatches = {
--     { tooltip = "Swatch 1", getValue = fn, setValue = fn, hasAlpha = bool },
--     { tooltip = "Swatch 2", getValue = fn, setValue = fn, hasAlpha = bool },
--     ...
--   },
-- }
function WidgetFactory:MultiSwatchRow(parent, yOffset, cfg)
    local ROW_H = 50
    local SIDE_PAD = 20
    local SWATCH_GAP = 8
    local frame = CreateFrame("Frame", nil, parent)
    local totalW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(frame, totalW, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    frame._skipRowDivider = true
    RowBg(frame, parent)
    TagOptionRow(frame, parent, cfg.text or "")

    -- Label
    local label = MakeFont(frame, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
    PP.Point(label, "LEFT", frame, "LEFT", SIDE_PAD, 0)
    label:SetText(cfg.text or "")

    -- Build swatches right-to-left from the right edge
    local swatches = cfg.swatches or {}
    local anchorX = -SIDE_PAD
    for i = #swatches, 1, -1 do
        local sc = swatches[i]
        local swatch, updateSwatch = BuildColorSwatch(frame, frame:GetFrameLevel() + 2, sc.getValue, sc.setValue, sc.hasAlpha)
        PP.Point(swatch, "RIGHT", frame, "RIGHT", anchorX, 0)
        anchorX = anchorX - 24 - SWATCH_GAP

        -- Per-swatch disabled overlay
        if sc.disabled then
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            if sc.disabledTooltip then
                swatchBlock:SetScript("OnEnter", function()
                    ShowWidgetTooltip(swatch, sc.disabledTooltip)
                end)
                swatchBlock:SetScript("OnLeave", function() HideWidgetTooltip() end)
            end
            -- Normal tooltip when enabled
            if sc.tooltip then
                swatch:HookScript("OnEnter", function()
                    ShowWidgetTooltip(swatch, sc.tooltip)
                end)
                swatch:HookScript("OnLeave", function() HideWidgetTooltip() end)
            end
            RegisterWidgetRefresh(function()
                updateSwatch()
                local off = sc.disabled()
                if off then swatch:SetAlpha(0.3); swatchBlock:Show()
                else swatch:SetAlpha(1); swatchBlock:Hide() end
            end)
            -- Initial state
            local off = sc.disabled()
            if off then swatch:SetAlpha(0.3); swatchBlock:Show()
            else swatch:SetAlpha(1); swatchBlock:Hide() end
        else
            -- Tooltip on hover
            if sc.tooltip then
                swatch:HookScript("OnEnter", function()
                    ShowWidgetTooltip(swatch, sc.tooltip)
                end)
                swatch:HookScript("OnLeave", function()
                    HideWidgetTooltip()
                end)
            end
            RegisterWidgetRefresh(function() updateSwatch() end)
        end
    end

    return frame, ROW_H
end

-- DropdownWithOffsets  (dropdown on left, X and Y mini-sliders side by side on right)
-- dropdownCfg: same as DualRow dropdown cfg (text, values, order, getValue, setValue, disabledValues, disabled)
-- xSliderCfg / ySliderCfg: { text, min, max, step, getValue, setValue, disabled }
function WidgetFactory:DropdownWithOffsets(parent, yOffset, dropdownCfg, xSliderCfg, ySliderCfg)
    local ROW_H = 50
    local SIDE_PAD = 20
    local frame = CreateFrame("Frame", nil, parent)
    local totalW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(frame, totalW, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    RowBg(frame, parent)
    TagOptionRow(frame, parent, (dropdownCfg and dropdownCfg.text or "") .. " " .. (xSliderCfg and xSliderCfg.text or "") .. " " .. (ySliderCfg and ySliderCfg.text or ""))

    local halfW = math.floor(totalW / 2)

    -- Left half: label + dropdown (same as DualRow dropdown half)
    local leftRegion = CreateFrame("Frame", nil, frame)
    leftRegion:SetSize(halfW, ROW_H)
    leftRegion:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    local ddLabel = MakeFont(leftRegion, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
    PP.Point(ddLabel, "LEFT", leftRegion, "LEFT", SIDE_PAD, 0)
    ddLabel:SetText(dropdownCfg.text or "")

    local DD_W = 170
    local ddBtn, ddLbl = BuildDropdownControl(leftRegion, DD_W, frame:GetFrameLevel() + 2,
        dropdownCfg.values, dropdownCfg.order, dropdownCfg.getValue, dropdownCfg.setValue, dropdownCfg.disabledValues)
    PP.Point(ddBtn, "RIGHT", leftRegion, "RIGHT", -SIDE_PAD, 0)

    local function ApplyDDDisabled()
        if not dropdownCfg.disabled then return end
        local off = dropdownCfg.disabled()
        ddLabel:SetAlpha(off and 0.3 or 1)
        ddBtn:EnableMouse(not off)
        ddBtn:SetAlpha(off and 0.3 or 1)
    end

    -- Right half: X and Y mini-sliders side by side on one line
    local rightRegion = CreateFrame("Frame", nil, frame)
    rightRegion:SetSize(halfW, ROW_H)
    rightRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local MINI_TRACK_W = 120
    local MINI_VALBOX_W = 30
    local SLIDER_H = 24

    local function BuildMiniSlider(slCfg, align)
        -- align: "LEFT" = label,track,valbox left-to-right; "RIGHT" = valbox,track,label right-to-left
        local isLeft = (align == "LEFT")

        -- Axis label ("X" or "Y")
        local axisLabel = MakeFont(rightRegion, 12, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        axisLabel:SetAlpha(0.6)
        axisLabel:SetText(slCfg.text or "")

        local trackFrame, valBox, _, slThumb = BuildSliderCore(rightRegion, MINI_TRACK_W, 4, 12, MINI_VALBOX_W, SLIDER_H, 11, SL.INPUT_A,
            slCfg.min, slCfg.max, slCfg.step, slCfg.getValue, slCfg.setValue, true, slCfg.snapPoints)

        if isLeft then
            PP.Point(axisLabel, "LEFT", rightRegion, "LEFT", 4, 0)
            PP.Point(trackFrame, "LEFT", axisLabel, "RIGHT", 6, 0)
            PP.Point(valBox, "LEFT", trackFrame, "RIGHT", 6, 0)
        else
            PP.Point(valBox, "RIGHT", rightRegion, "RIGHT", -4, 0)
            PP.Point(trackFrame, "RIGHT", valBox, "LEFT", -6, 0)
            PP.Point(axisLabel, "RIGHT", trackFrame, "LEFT", -6, 0)
        end

        RegisterWidgetRefresh(function()
            if slCfg.disabled then
                local off = slCfg.disabled()
                axisLabel:SetAlpha(off and 0.2 or 0.6)
                trackFrame:SetAlpha(off and 0.3 or 1)
                valBox:EnableMouse(not off)
                valBox:SetAlpha(off and 0.3 or 1)
                if slThumb then slThumb._sliderDisabled = off end
            end
        end)
        if slCfg.disabled then
            local off = slCfg.disabled()
            axisLabel:SetAlpha(off and 0.2 or 0.6)
            trackFrame:SetAlpha(off and 0.3 or 1)
            valBox:EnableMouse(not off)
            valBox:SetAlpha(off and 0.3 or 1)
            if slThumb then slThumb._sliderDisabled = off end
        end
    end

    -- X slider left-aligned, Y slider right-aligned
    BuildMiniSlider(xSliderCfg, "LEFT")
    BuildMiniSlider(ySliderCfg, "RIGHT")

    -- 1px center divider between dropdown and sliders
    local div = frame:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(BORDER_R, BORDER_G, BORDER_B, 0.05)
    div:SetWidth(1)
    div:SetPoint("TOP", frame, "TOP", 0, 0)
    div:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)

    -- Refresh dropdown on page refresh
    RegisterWidgetRefresh(function()
        ddLbl:SetText(DDResolveLabel(dropdownCfg.values, dropdownCfg.order or {}, dropdownCfg.getValue()))
        ApplyDDDisabled()
    end)
    ApplyDDDisabled()

    -- Expose regions for eye icon anchoring
    frame._leftRegion  = leftRegion
    frame._rightRegion = rightRegion
    -- Slot-level search labels for per-slot highlighting
    leftRegion._slotLabel  = dropdownCfg and dropdownCfg.text or ""
    rightRegion._slotLabel = (xSliderCfg and xSliderCfg.text or "") .. " " .. (ySliderCfg and ySliderCfg.text or "")

    return frame, ROW_H
end

-- WideDualButton  (two centered buttons side by side -- each 100px narrower and 5px shorter than WideButton)
function WidgetFactory:WideDualButton(parent, text1, text2, yOffset, onClick1, onClick2, btnWidth)
    btnWidth = btnWidth or DUAL_ITEM_W
    local BTN_H = 37
    local ROW_H = BTN_H + 20
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    TagOptionRow(frame, parent, (text1 or "") .. " " .. (text2 or ""))
    local halfGap = DUAL_GAP / 2
    for i, info in ipairs({{text1, -(btnWidth/2 + halfGap), onClick1}, {text2, (btnWidth/2 + halfGap), onClick2}}) do
        local btn = CreateFrame("Button", nil, frame)
        PP.Size(btn, btnWidth, BTN_H)
        PP.Point(btn, "CENTER", frame, "CENTER", info[2], 0)
        btn:SetFrameLevel(frame:GetFrameLevel() + 1)
        MakeStyledButton(btn, info[1], 14, WB_COLOURS, info[3])
    end
    return frame, ROW_H
end

-- WideDropdown  (centered, no row background, with title above -- for prominent selectors)
function WidgetFactory:WideDropdown(parent, title, yOffset, values, getValue, setValue, order, btnWidth, disabledValuesFn)
    btnWidth = btnWidth or 450
    local BTN_H, TITLE_H, GAP = 38, 20, 12
    local ROW_H = TITLE_H + GAP + BTN_H + 5
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    TagOptionRow(frame, parent, title)
    local titleLabel = MakeFont(frame, 13, nil, EllesmereUI.TEXT_SECTION_R, EllesmereUI.TEXT_SECTION_G, EllesmereUI.TEXT_SECTION_B, EllesmereUI.TEXT_SECTION_A)
    PP.Point(titleLabel, "TOP", frame, "TOP", 0, 0)
    titleLabel:SetText(title)
    local ddBtn = CreateFrame("Button", nil, frame)
    PP.Size(ddBtn, btnWidth, BTN_H)
    PP.Point(ddBtn, "TOP", titleLabel, "BOTTOM", 0, -GAP)
    ddBtn:SetFrameLevel(frame:GetFrameLevel() + 1)
    local bg = SolidTex(ddBtn, "BACKGROUND", DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
    bg:SetAllPoints()
    local brd = MakeBorder(ddBtn, 1, 1, 1, DD_BRD_A, PP)
    local ddLbl = MakeFont(ddBtn, 13, nil, 1, 1, 1)
    ddLbl:SetAlpha(DD_TXT_A)
    ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 14, 0)
    local arrow = MakeDropdownArrow(ddBtn, 14, PP)
    if not order then order = {}; for key in pairs(values) do order[#order + 1] = key end end
    local menu, menuItems, refresh = BuildDropdownMenu(ddBtn, btnWidth, order, values, getValue, setValue, ddLbl, "wide", disabledValuesFn)
    ddLbl:SetText(DDResolveLabel(values, order, getValue()))
    WireDropdownScripts(ddBtn, ddLbl, bg, brd, menu, refresh, WD_DD_COLOURS)
    RegisterWidgetRefresh(function()
        ddLbl:SetText(DDResolveLabel(values, order, getValue()))
        if disabledValuesFn then
            ddLbl:SetAlpha(disabledValuesFn(getValue()) and 0.15 or DD_TXT_A)
        end
    end)
    return frame, ROW_H
end

-- TripleDropdown  (3 normal-sized dropdowns side by side, each with a small title above, centered, 50px apart)
function WidgetFactory:TripleDropdown(parent, configs, yOffset)
    local DD_W, DD_H, TITLE_H, GAP_Y = TRIPLE_ITEM_W, 30, 16, 6
    local ROW_H = TITLE_H + GAP_Y + DD_H + 12
    local frame = CreateFrame("Frame", nil, parent)
    local frameW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(frame, frameW, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    TagOptionRow(frame, parent, (configs[1] and configs[1][1] or "") .. " " .. (configs[2] and configs[2][1] or "") .. " " .. (configs[3] and configs[3][1] or ""))
    local totalW = DD_W * 3 + TRIPLE_GAP * 2
    local startX = (frameW - totalW) / 2
    for idx, cfg in ipairs(configs) do
        local col = startX + (idx - 1) * (DD_W + TRIPLE_GAP)
        local titleLbl = MakeFont(frame, 11, nil, EllesmereUI.TEXT_SECTION_R, EllesmereUI.TEXT_SECTION_G, EllesmereUI.TEXT_SECTION_B, EllesmereUI.TEXT_SECTION_A)
        PP.Point(titleLbl, "TOP", frame, "TOPLEFT", col + DD_W / 2, 0)
        titleLbl:SetText(cfg.title)
        local ddBtn, ddLbl = BuildDropdownControl(frame, DD_W, frame:GetFrameLevel() + 1, cfg.values, cfg.order, cfg.getValue, cfg.setValue)
        PP.Point(ddBtn, "TOPLEFT", frame, "TOPLEFT", col, -(TITLE_H + GAP_Y))
        RegisterWidgetRefresh(function()
            ddLbl:SetText(DDResolveLabel(cfg.values, cfg.order or {}, cfg.getValue()))
        end)
    end
    return frame, ROW_H
end

-- TripleSlider  (three mini-sliders side by side -- mirrors TripleDropdown column positions)
-- configs = { { title (unused), minVal, maxVal, step, getValue, setValue }, ... } (exactly 3)
function WidgetFactory:TripleSlider(parent, configs, yOffset)
    local SL_W, SL_H = TRIPLE_ITEM_W, 26
    local ROW_H = SL_H + 12
    local frame = CreateFrame("Frame", nil, parent)
    local frameW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(frame, frameW, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    TagOptionRow(frame, parent, "")
    local totalW = SL_W * 3 + TRIPLE_GAP * 2
    local startX = (frameW - totalW) / 2
    for idx, cfg in ipairs(configs) do
        local col = startX + (idx - 1) * (SL_W + TRIPLE_GAP)
        local minVal = cfg.minVal or 16
        local maxVal = cfg.maxVal or 40
        local step   = cfg.step   or 1
        local INPUT_W = 36
        local TRACK_W = SL_W - INPUT_W - 16
        local slRow = CreateFrame("Frame", nil, frame)
        PP.Size(slRow, SL_W, SL_H)
        PP.Point(slRow, "TOPLEFT", frame, "TOPLEFT", col, -((ROW_H - SL_H) / 2))
        slRow:SetFrameLevel(frame:GetFrameLevel() + 1)
        local trackFrame, valBox = BuildSliderCore(slRow, TRACK_W, 4, 12, INPUT_W, 22, 12, SL.INPUT_A, minVal, maxVal, step, cfg.getValue, cfg.setValue, true)
        PP.Point(valBox, "RIGHT", slRow, "RIGHT", 0, 0)
        PP.Point(trackFrame, "LEFT", slRow, "LEFT", 4, 0)
    end
    return frame, ROW_H
end

-- Spacer
function WidgetFactory:Spacer(parent, yOffset, height)
    height = height or 16
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth(), height)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    frame._isSpacer = true
    return frame, height
end

-------------------------------------------------------------------------------
--  BuildCogPopup reusable cog settings popup with consistent layout
--
--  opts = {
--    title = "Popup Title",
--    rows  = {
--      { type="slider", label="Distance", min=-50, max=50, step=1, get=fn, set=fn },
--      { type="toggle", label="Show Health Percent", get=fn, set=fn },
--    },
--  }
--
--  Returns: popupFrame, showFn(anchorBtn)
-------------------------------------------------------------------------------
local function BuildCogPopup(opts)
    local SIDE_PAD         = 14
    local TOP_PAD          = 14
    local TITLE_H          = 11
    local TITLE_GAP        = 10
    local GAP              = 10
    local ROW_H            = 24
    local DROPDOWN_ROW_H   = 30
    local TOGGLE_ROW_H     = 28
    local INPUT_W          = 34
    local SLIDER_INPUT_GAP = 8
    local LABEL_SLIDER_GAP = 12
    local MIN_POPUP_W      = 180
    local POPUP_INPUT_A    = 0.55

    -- Toggle widget dimensions
    local TG_W = 32; local TG_H = 16; local KNOB_SZ = 12; local KNOB_PAD = 2

    local popupFrame, popupOwner
    local rowWidgets = {}  -- stores per-row refresh info

    local function CreatePopup()
        -- Measure slider labels to find maxLblW
        local tmpFS = UIParent:CreateFontString(nil, "OVERLAY")
        tmpFS:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
        local maxLblW = 0
        local maxDDLblW = 0
        for _, row in ipairs(opts.rows) do
            if row.type == "slider" then
                tmpFS:SetText(row.label)
                local w = tmpFS:GetStringWidth()
                if w > maxLblW then maxLblW = w end
            elseif row.type == "dropdown" then
                tmpFS:SetText(row.label)
                local w = tmpFS:GetStringWidth()
                if w > maxDDLblW then maxDDLblW = w end
            end
        end
        tmpFS:Hide()
        if maxLblW < 10 then maxLblW = 60 end

        local COG_DD_W = 130
        local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
        local SLIDER_W = math.max(80, 260 - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
        local POPUP_W = math.max(MIN_POPUP_W, SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD)
        -- Ensure popup is wide enough for dropdown rows (label + gap + dropdown + padding)
        local ddNeeded = SIDE_PAD + maxDDLblW + LABEL_SLIDER_GAP + COG_DD_W + SIDE_PAD
        if ddNeeded > POPUP_W then POPUP_W = ddNeeded end

        -- Calculate total height
        local totalH = TOP_PAD + TITLE_H + TITLE_GAP
        for i, row in ipairs(opts.rows) do
            if i > 1 then totalH = totalH + GAP end
            if row.type == "toggle" then
                totalH = totalH + TOGGLE_ROW_H
            elseif row.type == "dropdown" then
                totalH = totalH + DROPDOWN_ROW_H
            elseif row.type == "button" then
                totalH = totalH + ROW_H + 4
            else
                totalH = totalH + ROW_H
            end
        end
        totalH = totalH + TOP_PAD

        -- Footer (optional unlock mode link)
        local FOOTER_H = 0
        if opts.footer and opts.footer.unlockKey then
            FOOTER_H = 42  -- 2 lines of small text + padding
            totalH = totalH + FOOTER_H
        end

        -- Create popup frame
        local pf = CreateFrame("Frame", nil, UIParent)
        pf:SetSize(POPUP_W, totalH)
        pf:SetFrameStrata("DIALOG"); pf:SetFrameLevel(200)
        pf:EnableMouse(true); pf:Hide()

        -- Match panel scale so cog popup looks identical to scrollable-area widgets
        local ppScale = EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale() or 1
        pf:SetScale(ppScale)
        if EllesmereUI._popupFrames then
            EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = pf }
        end

        local bg = SolidTex(pf, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
        bg:SetAllPoints()
        MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15, PP)

        -- Title
        local titleFS = MakeFont(pf, TITLE_H, "", 1, 1, 1)
        titleFS:SetAlpha(0.7)
        titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
        titleFS:SetText(opts.title or "")

        -- Build rows
        local curY = -(TOP_PAD + TITLE_H + TITLE_GAP)
        for i, row in ipairs(opts.rows) do
            if i > 1 then curY = curY - GAP end

            if row.type == "slider" then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(row.label)
                lbl:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, curY - ROW_H / 2 - 1)

                local track, valBox, updateVisual = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                    row.min, row.max, row.step, row.get, row.set, true)
                track:SetPoint("LEFT", pf, "TOPLEFT", SLIDER_LEFT, curY - ROW_H / 2)
                valBox:ClearAllPoints()
                valBox:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, curY - ROW_H / 2)

                -- Disabled overlay for slider
                local sliderDis
                if row.disabled then
                    sliderDis = CreateFrame("Frame", nil, pf)
                    sliderDis:SetPoint("TOPLEFT", pf, "TOPLEFT", 0, curY)
                    sliderDis:SetPoint("TOPRIGHT", pf, "TOPRIGHT", 0, curY)
                    sliderDis:SetHeight(ROW_H)
                    sliderDis:SetFrameLevel(pf:GetFrameLevel() + 10)
                    sliderDis:EnableMouse(true)
                    local disTex = SolidTex(sliderDis, "OVERLAY", 0.06, 0.08, 0.10, 0.70)
                    disTex:SetAllPoints()
                    local disTip = row.disabledTooltip
                    sliderDis:SetScript("OnEnter", function(self)
                        local tip = type(disTip) == "function" and disTip() or disTip
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip(tip))
                        end
                    end)
                    sliderDis:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
                end

                rowWidgets[#rowWidgets + 1] = { type = "slider", updateVisual = updateVisual, get = row.get, disOverlay = sliderDis, disCheck = row.disabled }
                curY = curY - ROW_H

            elseif row.type == "toggle" then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(row.label)
                lbl:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, curY - TOGGLE_ROW_H / 2 - 1)

                -- Toggle button (cog popup, smaller)
                local cogToggle, _, cogSnap = BuildToggleControl(pf, pf:GetFrameLevel() + 2, row.get, function(v) row.set(v) end, { sizeRatio = 0.8, noAnim = true })
                cogToggle:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, curY - TOGGLE_ROW_H / 2)

                local function UpdateToggleVisual() cogSnap() end
                UpdateToggleVisual()
                cogToggle:SetScript("OnClick", function()
                    local cur = row.get()
                    row.set(not cur)
                    UpdateToggleVisual()
                    if pf._refresh then pf._refresh() end
                end)

                rowWidgets[#rowWidgets + 1] = { type = "toggle", updateVisual = UpdateToggleVisual }
                curY = curY - TOGGLE_ROW_H
            elseif row.type == 'dropdown' then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(row.label)
                lbl:SetPoint('LEFT', pf, 'TOPLEFT', SIDE_PAD, curY - DROPDOWN_ROW_H / 2 - 1)

                local ddBtn, ddLbl = BuildDropdownControl(pf, COG_DD_W, pf:GetFrameLevel() + 2, row.values, row.order, row.get, function(v)
                    row.set(v)
                    if pf._refresh then pf._refresh() end
                end)
                ddBtn:ClearAllPoints()
                ddBtn:SetPoint('RIGHT', pf, 'TOPRIGHT', -SIDE_PAD, curY - DROPDOWN_ROW_H / 2)
                -- Propagate popup scale to the lazily-created dropdown menu
                ddBtn:HookScript('OnClick', function(self)
                    if self._ddMenu and not self._ddMenu._cogScaled then
                        self._ddMenu:SetScale(ppScale)
                        self._ddMenu._cogScaled = true
                    end
                end)

                rowWidgets[#rowWidgets + 1] = { type = 'dropdown', btn = ddBtn, lbl = ddLbl, get = row.get, values = row.values, refresh = ddBtn._ddRefresh }
                curY = curY - DROPDOWN_ROW_H
            elseif row.type == 'colorpicker' then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(row.label)
                lbl:SetPoint('LEFT', pf, 'TOPLEFT', SIDE_PAD, curY - ROW_H / 2 - 1)

                local cpSwatch, cpUpdate = BuildColorSwatch(pf, pf:GetFrameLevel() + 2,
                    function() return row.get() end,
                    function(r, g, b, a)
                        row.set(r, g, b, a)
                        if pf._refresh then pf._refresh() end
                    end,
                    row.hasAlpha, 20)
                cpSwatch:ClearAllPoints()
                cpSwatch:SetPoint('RIGHT', pf, 'TOPRIGHT', -SIDE_PAD, curY - ROW_H / 2)

                -- Disabled: blocking overlays on label + swatch (matches inline swatch pattern)
                local cpSwBlock, cpLblBlock
                if row.disabled then
                    local disTip = row.disabledTooltip

                    -- Block on swatch
                    cpSwBlock = CreateFrame("Frame", nil, cpSwatch)
                    cpSwBlock:SetAllPoints()
                    cpSwBlock:SetFrameLevel(cpSwatch:GetFrameLevel() + 10)
                    cpSwBlock:EnableMouse(true)
                    cpSwBlock:SetScript("OnEnter", function()
                        local tip = type(disTip) == "function" and disTip() or disTip
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(cpSwatch, EllesmereUI.DisabledTooltip(tip))
                        end
                    end)
                    cpSwBlock:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)

                    -- Block on label
                    cpLblBlock = CreateFrame("Frame", nil, pf)
                    cpLblBlock:SetPoint("TOPLEFT", lbl, "TOPLEFT", -2, 2)
                    cpLblBlock:SetPoint("BOTTOMRIGHT", lbl, "BOTTOMRIGHT", 2, -2)
                    cpLblBlock:SetFrameLevel(pf:GetFrameLevel() + 10)
                    cpLblBlock:EnableMouse(true)
                    cpLblBlock:SetScript("OnEnter", function()
                        local tip = type(disTip) == "function" and disTip() or disTip
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(lbl, EllesmereUI.DisabledTooltip(tip))
                        end
                    end)
                    cpLblBlock:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
                end

                rowWidgets[#rowWidgets + 1] = { type = 'colorpicker', updateSwatch = cpUpdate, swatch = cpSwatch, swBlock = cpSwBlock, lblBlock = cpLblBlock, disCheck = row.disabled }

                -- Set initial disabled state
                if row.disabled then
                    local initDis = type(row.disabled) == "function" and row.disabled() or row.disabled
                    cpSwatch:SetAlpha(initDis and 0.3 or 1)
                    if cpSwBlock then if initDis then cpSwBlock:Show() else cpSwBlock:Hide() end end
                    if cpLblBlock then if initDis then cpLblBlock:Show() else cpLblBlock:Hide() end end
                end

                curY = curY - ROW_H
            elseif row.type == 'button' then
                local BTN_ROW_H = ROW_H + 4
                local btn = CreateFrame("Button", nil, pf)
                PP.Size(btn, POPUP_W - SIDE_PAD * 2, BTN_ROW_H)
                PP.Point(btn, "TOP", pf, "TOPLEFT", POPUP_W / 2, curY)
                btn:SetFrameLevel(pf:GetFrameLevel() + 2)
                local btnBg = SolidTex(btn, "BACKGROUND", 0.18, 0.18, 0.18, 0.85)
                btnBg:SetAllPoints()
                local btnLbl = MakeFont(btn, 11, nil, 1, 1, 1)
                btnLbl:SetAlpha(0.7)
                btnLbl:SetPoint("CENTER")
                btnLbl:SetText(row.label)
                btn:SetScript("OnEnter", function() btnBg:SetColorTexture(0.25, 0.25, 0.25, 0.85); btnLbl:SetAlpha(1) end)
                btn:SetScript("OnLeave", function() btnBg:SetColorTexture(0.18, 0.18, 0.18, 0.85); btnLbl:SetAlpha(0.7) end)
                btn:SetScript("OnClick", function()
                    if row.action then row.action() end
                    if pf._refresh then pf._refresh() end
                end)
                rowWidgets[#rowWidgets + 1] = { type = 'button' }
                curY = curY - BTN_ROW_H
            end
        end


        -- Footer: unlock mode link
        if opts.footer and opts.footer.unlockKey then
            local footerY = curY - 10
            local line1 = MakeFont(pf, 12, nil, 0x78/255, 0x7b/255, 0x81/255)
            line1:SetText("Reposition freely with")
            line1:SetPoint("TOP", pf, "TOPLEFT", POPUP_W / 2, footerY)

            local unlockBtn = CreateFrame("Button", nil, pf)
            unlockBtn:SetSize(80, 14)
            unlockBtn:SetPoint("TOP", line1, "BOTTOM", 0, -5)
            local _ugr, _ugg, _ugb = ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b
            local _uhr = _ugr + (1 - _ugr) * 0.25
            local _uhg = _ugg + (1 - _ugg) * 0.25
            local _uhb = _ugb + (1 - _ugb) * 0.25
            local unlockFS = MakeFont(unlockBtn, 13, nil, _ugr, _ugg, _ugb)
            unlockFS:SetAlpha(0.9)
            unlockFS:SetText("Unlock Mode")
            unlockFS:SetPoint("CENTER")
            unlockBtn:SetScript("OnClick", function()
                pf:Hide()
                if EllesmereUI._openUnlockMode then
                    EllesmereUI._unlockAutoSelectKey = opts.footer.unlockKey
                    local panel = EllesmereUI._mainFrame
                    if panel and panel:IsShown() then panel:Hide() end
                    C_Timer.After(0, EllesmereUI._openUnlockMode)
                end
            end)
            unlockBtn:SetScript("OnEnter", function(self)
                unlockFS:SetTextColor(_uhr, _uhg, _uhb)
                unlockFS:SetAlpha(1)
            end)
            unlockBtn:SetScript("OnLeave", function(self)
                unlockFS:SetTextColor(_ugr, _ugg, _ugb)
                unlockFS:SetAlpha(0.9)
            end)
        end
        -- Refresh method: re-read all get functions and update visuals
        pf._refresh = function()
            for _, rw in ipairs(rowWidgets) do
                if rw.type == "slider" then
                    if rw.disOverlay and rw.disCheck then
                        local dis = type(rw.disCheck) == "function" and rw.disCheck() or rw.disCheck
                        if dis then rw.disOverlay:Show() else rw.disOverlay:Hide() end
                    end
                    if rw.updateVisual and rw.get then rw.updateVisual(rw.get()) end
                elseif rw.type == "toggle" then
                    if rw.updateVisual then rw.updateVisual() end
                elseif rw.type == 'colorpicker' then
                    if rw.disCheck then
                        local dis = type(rw.disCheck) == "function" and rw.disCheck() or rw.disCheck
                        if rw.swatch then rw.swatch:SetAlpha(dis and 0.3 or 1) end
                        if rw.swBlock then if dis then rw.swBlock:Show() else rw.swBlock:Hide() end end
                        if rw.lblBlock then if dis then rw.lblBlock:Show() else rw.lblBlock:Hide() end end
                    end
                    if rw.updateSwatch then rw.updateSwatch() end
                elseif rw.type == 'dropdown' then
                    if rw.lbl and rw.get and rw.values then
                        rw.lbl:SetText(DDText(rw.values[rw.get()]) or tostring(rw.get()))
                        if rw.refresh then rw.refresh() end
                    end
                end
            end
        end

        -- Click-outside-to-close handler (also closes when scrolled out of view)
        local wasDown = false
        pf._clickOutside = function(self)
            local down = IsMouseButtonDown("LeftButton")
            if down and not wasDown then
                local ddOpen = false; for _, rw in ipairs(rowWidgets) do if rw.type == 'dropdown' and rw.btn and rw.btn._ddMenu and rw.btn._ddMenu:IsShown() and rw.btn._ddMenu:IsMouseOver() then ddOpen = true; break end end; if not self:IsMouseOver() and not (popupOwner and popupOwner:IsMouseOver()) and not ddOpen then
                    self:Hide()
                end
            end
            wasDown = down

            -- Close when the anchor button scrolls out of the visible scroll area
            if popupOwner then
                local scrollFrame = EllesmereUI._scrollFrame
                if scrollFrame then
                    if popupOwner._inScrollChild == nil then
                        local scrollChild = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
                        local found = false
                        if scrollChild then
                            local p = popupOwner:GetParent()
                            while p do
                                if p == scrollChild then found = true; break end
                                p = p:GetParent()
                            end
                        end
                        popupOwner._inScrollChild = found
                    end
                    if popupOwner._inScrollChild then
                        local sfTop = scrollFrame:GetTop()
                        local sfBot = scrollFrame:GetBottom()
                        local btnBot = popupOwner:GetBottom()
                        if sfTop and sfBot and btnBot then
                            if btnBot < sfBot or btnBot > sfTop then self:Hide() end
                        end
                    end
                end
            end
        end

        pf:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            if popupOwner then popupOwner:SetAlpha(0.4) end
            popupOwner = nil
        end)

        -- Close popup when main EllesmereUI frame hides
        if EllesmereUI._mainFrame then
            EllesmereUI._mainFrame:HookScript("OnHide", function()
                if pf:IsShown() then pf:Hide() end
            end)
        end

        popupFrame = pf
    end

    -- showFn: toggle popup anchored to a button
    -- Wrap in a callable table so callers can access showFn._popupFrame
    local showFn = setmetatable({}, { __call = function(self, anchorBtn)
        if not popupFrame then CreatePopup(); self._popupFrame = popupFrame end

        -- Toggle off if same anchor clicked while visible
        if popupOwner == anchorBtn and popupFrame:IsShown() then
            popupFrame:Hide(); return
        end
        popupOwner = anchorBtn

        -- Refresh all widget visuals from get functions
        popupFrame._refresh()

        -- Anchor below the cog icon and animate downward
        popupFrame:ClearAllPoints()
        popupFrame:SetPoint("TOP", anchorBtn, "BOTTOM", 0, -5)
        popupFrame:SetAlpha(0)
        popupFrame:Show()
        local elapsed = 0
        popupFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            local t = math.min(elapsed / 0.15, 1)
            self:SetAlpha(t)
            self:ClearAllPoints()
            self:SetPoint("TOP", anchorBtn, "BOTTOM", 0, -5 + (8 * (1 - t)))
            if t >= 1 then self:SetScript("OnUpdate", self._clickOutside) end
        end)
    end })

    return popupFrame, showFn
end

-------------------------------------------------------------------------------
--  Segmented Control  (pill-shaped tab bar for multi-edit headers)
--  cfg = {
--      parent       = Frame,          -- parent frame to attach to
--      width        = number,         -- total width (used as fallback)
--      autoWidth    = bool,           -- auto-size to fit label content
--      keys         = { "k1", ... },  -- ordered keys
--      labels       = { k1="Lbl" },   -- display labels per key
--      getChecked   = function(key) -> bool,
--      getEyeball   = function() -> key  (optional, the "primary" selected key)
--      onToggle     = function(key),  -- called when a segment is clicked
--      isDisabled   = function(key) -> bool  (optional, grays out segment)
--      disabledTip  = function(key) -> string (optional, tooltip for disabled)
--  }
--  Returns: frame, height, refreshFn
-------------------------------------------------------------------------------
local function BuildSegmentedControl(cfg)
    local ACCENT   = ELLESMERE_GREEN
    local SEG_H    = 28
    local FONT_SZ  = 13
    local SEG_PAD  = 22
    local PILL_BG  = { 0.125, 0.125, 0.137 }  -- #202023
    local PILL_BGA = 0.95
    local INACTIVE_R, INACTIVE_G, INACTIVE_B = 0.467, 0.471, 0.482  -- #77787b
    local INACTIVE_A = 0.5
    local ACTIVE_R,   ACTIVE_G,   ACTIVE_B   = ACCENT.r, ACCENT.g, ACCENT.b
    local BG_HOVER_BOOST = 0.04  -- 4% brightness on hover for background

    local numKeys = #cfg.keys

    local tmpFS = UIParent:CreateFontString(nil, "OVERLAY")
    tmpFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", FONT_SZ, "")
    local segWidths = {}
    local pillW = 0
    for _, key in ipairs(cfg.keys) do
        tmpFS:SetText(cfg.labels[key] or key)
        local w = math.ceil(tmpFS:GetStringWidth()) + SEG_PAD * 2
        segWidths[key] = w
        pillW = pillW + w
    end
    tmpFS:Hide()

    if not cfg.autoWidth then
        pillW = cfg.width
        local baseW = math.floor(pillW / numKeys)
        local remainder = pillW - baseW * numKeys
        for idx, key in ipairs(cfg.keys) do
            segWidths[key] = baseW + (idx <= remainder and 1 or 0)
        end
    end

    local capW = SEG_H
    segWidths[cfg.keys[1]] = math.floor(segWidths[cfg.keys[1]] - capW)
    segWidths[cfg.keys[numKeys]] = math.floor(segWidths[cfg.keys[numKeys]] - capW)
    pillW = 0
    for _, key in ipairs(cfg.keys) do pillW = pillW + segWidths[key] end
    -- Account for 1px overlap between adjacent segments
    local overlapTotal = (numKeys - 1) * 1
    local totalW = pillW + capW * 2 - overlapTotal

    local frame = CreateFrame("Frame", nil, cfg.parent)
    frame:SetSize(totalW, SEG_H)

    local pillBody = CreateFrame("Frame", nil, frame)
    pillBody:SetSize(pillW - overlapTotal, SEG_H)
    PP.Point(pillBody, "TOP", frame, "TOP", 0, 0)
    pillBody:SetFrameLevel(frame:GetFrameLevel() + 1)

    local bg = pillBody:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0)  -- transparent; per-segment segBg handles background

    -------------------------------------------------------------------
    -- Pill caps
    -------------------------------------------------------------------
    local CAP_FILL_L_TEX   = MEDIA_PATH .. "pill-fill-l.png"
    local CAP_FILL_R_TEX   = MEDIA_PATH .. "pill-fill-r.png"
    local CAP_BORDER_L_TEX = MEDIA_PATH .. "pill-border-l.png"
    local CAP_BORDER_R_TEX = MEDIA_PATH .. "pill-border-r.png"

    local capLeftFill = pillBody:CreateTexture(nil, "BACKGROUND", nil, 1)
    capLeftFill:SetSize(capW, SEG_H)
    capLeftFill:SetTexture(CAP_FILL_L_TEX)
    capLeftFill:SetVertexColor(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)

    local capLeftBdr = pillBody:CreateTexture(nil, "BACKGROUND", nil, 2)
    capLeftBdr:SetSize(capW, SEG_H)
    capLeftBdr:SetTexture(CAP_BORDER_L_TEX)

    local capRightFill = pillBody:CreateTexture(nil, "BACKGROUND", nil, 1)
    capRightFill:SetSize(capW, SEG_H)
    capRightFill:SetTexture(CAP_FILL_R_TEX)
    capRightFill:SetVertexColor(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)

    local capRightBdr = pillBody:CreateTexture(nil, "BACKGROUND", nil, 2)
    capRightBdr:SetSize(capW, SEG_H)
    capRightBdr:SetTexture(CAP_BORDER_R_TEX)

    -- Cap accent overlays (5% accent tint when checked, using same pill cap PNGs)
    local capLeftAccent = pillBody:CreateTexture(nil, "BACKGROUND", nil, 3)
    capLeftAccent:SetSize(capW, SEG_H)
    capLeftAccent:SetTexture(CAP_FILL_L_TEX)
    capLeftAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
    capLeftAccent:Hide()

    local capRightAccent = pillBody:CreateTexture(nil, "BACKGROUND", nil, 3)
    capRightAccent:SetSize(capW, SEG_H)
    capRightAccent:SetTexture(CAP_FILL_R_TEX)
    capRightAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
    capRightAccent:Hide()

    -- Cap click zones anchored to pillBody for now, re-anchored after segments
    local capLeftBtn = CreateFrame("Button", nil, frame)
    capLeftBtn:SetSize(capW, SEG_H)
    PP.Point(capLeftBtn, "RIGHT", pillBody, "LEFT", 0, 0)
    capLeftBtn:SetFrameLevel(pillBody:GetFrameLevel() + 4)
    capLeftBtn:SetScript("OnClick", function()
        local key = cfg.keys[1]
        if cfg.isDisabled and cfg.isDisabled(key) then return end
        if cfg.onToggle then cfg.onToggle(key) end
    end)
    capLeftBtn:SetScript("OnEnter", function()
        local key = cfg.keys[1]
        if cfg.isDisabled and cfg.isDisabled(key) then
            if cfg.disabledTip then
                local tip = cfg.disabledTip(key)
                if tip then ShowWidgetTooltip(capLeftBtn, tip) end
            end
            return
        end
        frame._hoverIdx = 1
        if frame._refreshAll then frame._refreshAll() end
    end)
    capLeftBtn:SetScript("OnLeave", function()
        HideWidgetTooltip()
        frame._hoverIdx = nil
        if frame._refreshAll then frame._refreshAll() end
    end)

    local capRightBtn = CreateFrame("Button", nil, frame)
    capRightBtn:SetSize(capW, SEG_H)
    PP.Point(capRightBtn, "LEFT", pillBody, "RIGHT", 0, 0)
    capRightBtn:SetFrameLevel(pillBody:GetFrameLevel() + 4)
    capRightBtn:SetScript("OnClick", function()
        local key = cfg.keys[numKeys]
        if cfg.isDisabled and cfg.isDisabled(key) then return end
        if cfg.onToggle then cfg.onToggle(key) end
    end)
    capRightBtn:SetScript("OnEnter", function()
        local key = cfg.keys[numKeys]
        if cfg.isDisabled and cfg.isDisabled(key) then
            if cfg.disabledTip then
                local tip = cfg.disabledTip(key)
                if tip then ShowWidgetTooltip(capRightBtn, tip) end
            end
            return
        end
        frame._hoverIdx = numKeys
        if frame._refreshAll then frame._refreshAll() end
    end)
    capRightBtn:SetScript("OnLeave", function()
        HideWidgetTooltip()
        frame._hoverIdx = nil
        if frame._refreshAll then frame._refreshAll() end
    end)

    -------------------------------------------------------------------
    -- Segments each has full 1px border; adjacent segments overlap by 1px
    -------------------------------------------------------------------
    local segments = {}
    local BASE_LEVEL = pillBody:GetFrameLevel() + 3
    local CHECKED_LEVEL = BASE_LEVEL + 1  -- checked segments draw on top

    for i, key in ipairs(cfg.keys) do
        local thisW = segWidths[key]

        local btn = CreateFrame("Button", nil, pillBody)
        PP.Size(btn, thisW, SEG_H)
        if i == 1 then
            PP.Point(btn, "TOPLEFT", pillBody, "TOPLEFT", 0, 0)
        else
            -- Anchor to previous segment's right edge, shifted 1px left for overlap
            PP.Point(btn, "TOPLEFT", segments[i-1].btn, "TOPRIGHT", -1, 0)
        end
        btn:SetFrameLevel(BASE_LEVEL)

        -- Per-segment hover background overlay
        local segBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        segBg:SetAllPoints()
        segBg:SetColorTexture(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)

        -- Accent tint overlay for checked/active segments (5% opacity)
        local accentBg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
        accentBg:SetAllPoints()
        accentBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
        accentBg:Hide()

        -- Full 1px border on all 4 sides matches MakeBorder's pixel-perfect
        -- technique: vertical edges inset by 1px to avoid overlapping corners.
        local segTop = btn:CreateTexture(nil, "ARTWORK", nil, 7)
        segTop:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
        segTop:SetHeight(1)
        PP.Point(segTop, "TOPLEFT", btn, "TOPLEFT", 0, 0)
        PP.Point(segTop, "TOPRIGHT", btn, "TOPRIGHT", 0, 0)

        local segBot = btn:CreateTexture(nil, "ARTWORK", nil, 7)
        segBot:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
        segBot:SetHeight(1)
        PP.Point(segBot, "BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        PP.Point(segBot, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)

        -- Vertical edges anchored to horizontal edges (inset 1px) to avoid bright corners
        local segLeft = btn:CreateTexture(nil, "ARTWORK", nil, 7)
        segLeft:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
        segLeft:SetWidth(1)
        PP.Point(segLeft, "TOPLEFT", segTop, "BOTTOMLEFT", 0, 0)
        PP.Point(segLeft, "BOTTOMLEFT", segBot, "TOPLEFT", 0, 0)

        local segRight = btn:CreateTexture(nil, "ARTWORK", nil, 7)
        segRight:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
        segRight:SetWidth(1)
        PP.Point(segRight, "TOPRIGHT", segTop, "BOTTOMRIGHT", 0, 0)
        PP.Point(segRight, "BOTTOMRIGHT", segBot, "TOPRIGHT", 0, 0)

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(EllesmereUI.EXPRESSWAY, FONT_SZ, "")
        local lblOfsX = 0
        if i == 1 then lblOfsX = -capW / 2 end
        if i == numKeys then lblOfsX = capW / 2 end
        lbl:SetPoint("CENTER", lblOfsX, 0)
        lbl:SetText(cfg.labels[key] or key)

        segments[i] = {
            key = key, btn = btn, lbl = lbl, w = thisW, segBg = segBg, accentBg = accentBg,
            segTop = segTop, segBot = segBot, segLeft = segLeft, segRight = segRight,
        }

        btn:SetScript("OnClick", function()
            if cfg.isDisabled and cfg.isDisabled(key) then return end
            if cfg.onToggle then cfg.onToggle(key) end
        end)

        btn:SetScript("OnEnter", function()
            if cfg.isDisabled and cfg.isDisabled(key) then
                if cfg.disabledTip then
                    local tip = cfg.disabledTip(key)
                    if tip then ShowWidgetTooltip(btn, tip) end
                end
                return
            end
            frame._hoverIdx = i
            if frame._refreshAll then frame._refreshAll() end
        end)

        btn:SetScript("OnLeave", function()
            HideWidgetTooltip()
            frame._hoverIdx = nil
            if frame._refreshAll then frame._refreshAll() end
        end)
    end

    -------------------------------------------------------------------
    -- Anchor caps to segment buttons
    -- Use raw SetPoint (not PixelUtil) for cap textures to avoid
    -- asymmetric pixel rounding that squishes one side.
    -------------------------------------------------------------------
    local firstBtn = segments[1].btn
    local lastBtn  = segments[#segments].btn

    capLeftFill:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
    capLeftBdr:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
    capLeftAccent:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
    capRightFill:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)
    capRightBdr:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)
    capRightAccent:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)
    capLeftBtn:ClearAllPoints()
    capLeftBtn:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
    capRightBtn:ClearAllPoints()
    capRightBtn:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)

    -------------------------------------------------------------------
    -- RefreshAll
    -------------------------------------------------------------------
    local function RefreshAll()
        local eyeKey = cfg.getEyeball and cfg.getEyeball()
        local hoverIdx = frame._hoverIdx

        for idx, seg in ipairs(segments) do
            local disabled = cfg.isDisabled and cfg.isDisabled(seg.key)
            local checked  = cfg.getChecked(seg.key)
            local isHover  = (hoverIdx == idx)

            -- Label color
            if disabled then
                seg.lbl:SetTextColor(1, 1, 1, 0.20)
            elseif checked then
                seg.lbl:SetTextColor(ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0)
            else
                seg.lbl:SetTextColor(1, 1, 1, 0.60)
            end

            -- Checked segments get higher frame level so their border
            -- draws on top of the adjacent unchecked segment's border.
            if checked and not disabled then
                seg.btn:SetFrameLevel(CHECKED_LEVEL)
            else
                seg.btn:SetFrameLevel(BASE_LEVEL)
            end

            -- Border color: checked = accent, unchecked = inactive gray, disabled = 25% opacity
            local br, bg2, bb, ba
            if disabled then
                br, bg2, bb, ba = INACTIVE_R, INACTIVE_G, INACTIVE_B, 0.10
            elseif checked then
                br, bg2, bb, ba = ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0
            else
                br, bg2, bb, ba = INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A
            end

            seg.segTop:SetColorTexture(br, bg2, bb, ba)
            seg.segBot:SetColorTexture(br, bg2, bb, ba)
            seg.segLeft:SetColorTexture(br, bg2, bb, ba)
            seg.segRight:SetColorTexture(br, bg2, bb, ba)

            -- All 4 borders visible, except: first segment hides left,
            -- last segment hides right (the pill caps handle those edges).
            seg.segTop:Show()
            seg.segBot:Show()
            local isFirst = (idx == 1)
            local isLast  = (idx == #segments)
            if isFirst then seg.segLeft:Hide() else seg.segLeft:Show() end
            if isLast  then seg.segRight:Hide() else seg.segRight:Show() end

            -- Background: disabled = 50% opacity, hover = lighten by 4%, normal = PILL_BGA
            if disabled then
                seg.segBg:SetColorTexture(PILL_BG[1], PILL_BG[2], PILL_BG[3], 0.50)
                seg.accentBg:Hide()
            elseif isHover then
                local hr, hg, hb = PILL_BG[1] + BG_HOVER_BOOST, PILL_BG[2] + BG_HOVER_BOOST, PILL_BG[3] + BG_HOVER_BOOST
                seg.segBg:SetColorTexture(hr, hg, hb, PILL_BGA)
                if checked then
                    seg.accentBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.05); seg.accentBg:Show()
                else
                    seg.accentBg:Hide()
                end
            else
                seg.segBg:SetColorTexture(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)
                if checked then
                    seg.accentBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.05); seg.accentBg:Show()
                else
                    seg.accentBg:Hide()
                end
            end
        end

        -- Cap borders & fills: match adjacent segment's state (checked/disabled/hover)
        local firstKey = cfg.keys[1]
        local lastKey  = cfg.keys[numKeys]
        local firstDisabled = cfg.isDisabled and cfg.isDisabled(firstKey)
        local lastDisabled  = cfg.isDisabled and cfg.isDisabled(lastKey)
        local firstChecked = cfg.getChecked(firstKey) and not firstDisabled
        local lastChecked  = cfg.getChecked(lastKey) and not lastDisabled
        local firstHover = (hoverIdx == 1) and not firstDisabled
        local lastHover  = (hoverIdx == numKeys) and not lastDisabled

        local lbr, lbg2, lbb, lba = INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A
        if firstDisabled then lba = 0.10
        elseif firstChecked then lbr, lbg2, lbb, lba = ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0 end
        capLeftBdr:SetVertexColor(lbr, lbg2, lbb, lba)

        local rbr, rbg2, rbb, rba = INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A
        if lastDisabled then rba = 0.10
        elseif lastChecked then rbr, rbg2, rbb, rba = ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0 end
        capRightBdr:SetVertexColor(rbr, rbg2, rbb, rba)

        -- Cap fills: disabled = 50% opacity, hover = lighten by 4%, normal = PILL_BGA
        local lfr, lfg, lfb, lfa = PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA
        if firstDisabled then lfa = 0.50
        elseif firstHover then lfr, lfg, lfb = lfr + BG_HOVER_BOOST, lfg + BG_HOVER_BOOST, lfb + BG_HOVER_BOOST end
        capLeftFill:SetVertexColor(lfr, lfg, lfb, lfa)

        local rfr, rfg, rfb, rfa = PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA
        if lastDisabled then rfa = 0.50
        elseif lastHover then rfr, rfg, rfb = rfr + BG_HOVER_BOOST, rfg + BG_HOVER_BOOST, rfb + BG_HOVER_BOOST end
        capRightFill:SetVertexColor(rfr, rfg, rfb, rfa)

        -- Cap accent overlays: show 5% accent tint when checked (matches segment accentBg)
        if firstChecked then
            capLeftAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
            capLeftAccent:Show()
        else
            capLeftAccent:Hide()
        end
        if lastChecked then
            capRightAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
            capRightAccent:Show()
        else
            capRightAccent:Hide()
        end
    end

    frame._refreshAll = RefreshAll
    RefreshAll()

    -- Pill sits at 90% opacity permanently
    frame:SetAlpha(0.9)    return frame, SEG_H, RefreshAll
end




-------------------------------------------------------------------------------
--  Exports  (widget helpers EllesmereUI table for EllesmereUI_Presets.lua)
-------------------------------------------------------------------------------
EllesmereUI.MakeStyledButton    = MakeStyledButton
EllesmereUI.WB_COLOURS          = WB_COLOURS
EllesmereUI.RB_COLOURS          = RB_COLOURS
EllesmereUI.DDText              = DDText
EllesmereUI.BuildDropdownMenu   = BuildDropdownMenu
EllesmereUI.WireDropdownScripts = WireDropdownScripts
EllesmereUI.WD_DD_COLOURS       = WD_DD_COLOURS
EllesmereUI.RD_DD_COLOURS       = RD_DD_COLOURS
--------------------------------------------------------------------------------
--  PlaySyncFlash -- accent-colored 4-edge border glow on a target frame
--  Pooled: one glow frame per target, reused across flashes.
--------------------------------------------------------------------------------
local _syncGlowPool = {}

local function PlaySyncFlash(targetFrame)
    if not targetFrame then return end
    local glow = _syncGlowPool[targetFrame]
    if not glow then
        glow = CreateFrame("Frame", nil, targetFrame)
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local function MkEdge()
            local t = glow:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(ar, ag, ab, 1)
            glow["_c_" .. (glow._edgeN or 0)] = t
            glow._edgeN = (glow._edgeN or 0) + 1
            return t
        end
        glow._top = MkEdge();  glow._top:SetHeight(2)
        glow._top:SetPoint("TOPLEFT");  glow._top:SetPoint("TOPRIGHT")
        glow._bot = MkEdge();  glow._bot:SetHeight(2)
        glow._bot:SetPoint("BOTTOMLEFT");  glow._bot:SetPoint("BOTTOMRIGHT")
        glow._lft = MkEdge();  glow._lft:SetWidth(2)
        glow._lft:SetPoint("TOPLEFT", glow._top, "BOTTOMLEFT")
        glow._lft:SetPoint("BOTTOMLEFT", glow._bot, "TOPLEFT")
        glow._rgt = MkEdge();  glow._rgt:SetWidth(2)
        glow._rgt:SetPoint("TOPRIGHT", glow._top, "BOTTOMRIGHT")
        glow._rgt:SetPoint("BOTTOMRIGHT", glow._bot, "TOPRIGHT")
        _syncGlowPool[targetFrame] = glow
    end
    -- Re-color edges in case accent changed
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    for i = 0, (glow._edgeN or 0) - 1 do
        local e = glow["_c_" .. i]
        if e then e:SetColorTexture(ar, ag, ab, 1) end
    end
    glow:SetAllPoints(targetFrame)
    glow:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
    glow:SetAlpha(1)
    glow:Show()
    local elapsed = 0
    glow:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.75 then
            self:Hide();  self:SetScript("OnUpdate", nil);  return
        end
        self:SetAlpha(1 - elapsed / 0.75)
    end)
end

EllesmereUI.PlaySyncFlash = PlaySyncFlash

--------------------------------------------------------------------------------
--  PlayWhiteFlash -- white 4-edge border flash on click, fades out over 0.35s
--  Reuses the same glow pool as PlaySyncFlash, just recolors edges white.
--------------------------------------------------------------------------------
local function PlayWhiteFlash(targetFrame)
    if not targetFrame then return end
    -- Ensure the glow frame exists (creates it if needed via PlaySyncFlash)
    if not _syncGlowPool[targetFrame] then PlaySyncFlash(targetFrame) end
    local glow = _syncGlowPool[targetFrame]
    if not glow then return end
    -- Stop any running animation (hover pulse or previous flash)
    glow:SetScript("OnUpdate", nil)
    -- Recolor edges white
    for i = 0, (glow._edgeN or 0) - 1 do
        local e = glow["_c_" .. i]
        if e then e:SetColorTexture(1, 1, 1, 1) end
    end
    glow:SetAllPoints(targetFrame)
    glow:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
    glow:SetAlpha(0.75)
    glow:Show()
    local elapsed = 0
    glow:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            self:Hide(); self:SetScript("OnUpdate", nil); return
        end
        self:SetAlpha(0.75 - 0.50 * (elapsed / 0.5))
    end)
end

EllesmereUI.PlayWhiteFlash = PlayWhiteFlash

--------------------------------------------------------------------------------
--  BuildMultiApplyDropdown -- checkbox popup for selective "Apply to Multiple"
--
--  Opens a DIALOG-strata popup with checkboxes for each element. The current
--  element is pre-checked and grayed out. All others are checked by default.
--  An "Apply" button at the top applies the setting to all checked elements.
--
--  opts = {
--      elementKeys   = { "MainBar", "Bar2", ... },
--      elementLabels = { MainBar = "Bar 1", Bar2 = "Bar 2", ... },
--      getCurrentKey = function() return selectedBarKey end,
--      onApply       = function(checkedKeys) ... end,
--  }
--  anchorFrame: frame to anchor the dropdown below
--  flashTargets: optional table or function for PlayWhiteFlash on apply
--
--  Returns: dropdownFrame
--------------------------------------------------------------------------------
local _activeMultiApplyDropdown = nil  -- only one open at a time
-- Persistent checkbox state per element-key-set (survives dropdown close/reopen)
local _multiApplyCheckedState = {}

local function BuildMultiApplyDropdown(anchorFrame, opts, flashTargets)
    -- Close any existing dropdown first
    if _activeMultiApplyDropdown then
        _activeMultiApplyDropdown:Hide()
        _activeMultiApplyDropdown = nil
    end

    local currentKey = opts.getCurrentKey()
    local keys = opts.elementKeys
    local labels = opts.elementLabels

    -- Build a stable cache key from the element keys list
    local cacheKey = table.concat(keys, "|")

    local ITEM_H = 28
    local APPLY_H = 29   -- 10% smaller than the 32px footer button height
    local PAD = 6
    local menuW = 180
    local menuH = PAD + APPLY_H + 2 + #keys * ITEM_H + PAD

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(200)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    PP.Size(menu, menuW, menuH)
    menu:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)

    local mBg = menu:CreateTexture(nil, "BACKGROUND")
    mBg:SetAllPoints()
    mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, 0.96)
    EllesmereUI.MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)

    local ppScale = EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale() or 1
    menu:SetScale(ppScale)

    -- Restore or initialize checked state for this key-set
    if not _multiApplyCheckedState[cacheKey] then
        _multiApplyCheckedState[cacheKey] = {}
        for _, key in ipairs(keys) do
            _multiApplyCheckedState[cacheKey][key] = true
        end
    end
    local checked = _multiApplyCheckedState[cacheKey]

    local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("options") or "Fonts\\FRIZQT__.TTF"

    -- "Apply" button at top -- styled like the footer Reset/Reload buttons (white, muted, fade hover)
    local applyRow = CreateFrame("Button", nil, menu)
    applyRow:SetHeight(APPLY_H)
    applyRow:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, -PAD)
    applyRow:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD, -PAD)
    applyRow:SetFrameLevel(menu:GetFrameLevel() + 2)

    local DB_BG = EllesmereUI.DARK_BG or { r = 0.05, g = 0.07, b = 0.09 }
    local applyBg = applyRow:CreateTexture(nil, "BACKGROUND")
    applyBg:SetAllPoints()
    applyBg:SetColorTexture(DB_BG.r, DB_BG.g, DB_BG.b, 0.92)
    local applyBrd = EllesmereUI.MakeBorder(applyRow, 1, 1, 1, 0.4, PP)

    local applyLbl = applyRow:CreateFontString(nil, "OVERLAY")
    applyLbl:SetFont(fontPath, 12, "")
    applyLbl:SetTextColor(1, 1, 1, 0.5)
    applyLbl:SetText("Apply")
    applyLbl:SetPoint("CENTER", applyRow, "CENTER", 0, 0)

    -- Fade hover (matches footer button 0.1s fade)
    do
        local FADE_DUR = 0.1
        local progress, target = 0, 0
        local function ApplyHover(t)
            applyLbl:SetTextColor(1, 1, 1, 0.5 + 0.2 * t)
            applyBrd:SetColor(1, 1, 1, 0.4 + 0.2 * t)
        end
        local function OnUpdate(self, elapsed)
            local dir = (target == 1) and 1 or -1
            progress = progress + dir * (elapsed / FADE_DUR)
            if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                progress = target; self:SetScript("OnUpdate", nil)
            end
            ApplyHover(progress)
        end
        applyRow:SetScript("OnEnter", function(self)
            if not applyRow:IsEnabled() then return end
            target = 1; self:SetScript("OnUpdate", OnUpdate)
        end)
        applyRow:SetScript("OnLeave", function(self)
            target = 0; self:SetScript("OnUpdate", OnUpdate)
        end)
    end

    -- Separator line below Apply button
    local sep = menu:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", applyRow, "BOTTOMLEFT", 0, -1)
    sep:SetPoint("TOPRIGHT", applyRow, "BOTTOMRIGHT", 0, -1)
    sep:SetColorTexture(1, 1, 1, 0.08)

    -- Count checked (excluding current) for disabled state
    local function CountChecked()
        local n = 0
        for _, key in ipairs(keys) do
            if key ~= currentKey and checked[key] then n = n + 1 end
        end
        return n
    end

    local function UpdateApplyState()
        local n = CountChecked()
        if n > 0 then
            applyLbl:SetTextColor(1, 1, 1, 0.5)
            applyBrd:SetColor(1, 1, 1, 0.4)
            applyBg:SetColorTexture(DB_BG.r, DB_BG.g, DB_BG.b, 0.92)
            applyRow:Enable()
        else
            applyLbl:SetTextColor(1, 1, 1, 0.2)
            applyBrd:SetColor(1, 1, 1, 0.15)
            applyBg:SetColorTexture(DB_BG.r, DB_BG.g, DB_BG.b, 0.92)
            applyRow:Disable()
        end
    end

    -- Checkbox rows
    local yOff = -(PAD + APPLY_H + 3)
    local checkRows = {}
    for _, key in ipairs(keys) do
        local isCurrent = (key == currentKey)
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(ITEM_H)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, yOff)
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, yOff)
        row:SetFrameLevel(menu:GetFrameLevel() + 2)

        local box = CreateFrame("Frame", nil, row)
        box:SetSize(16, 16)
        box:SetPoint("LEFT", row, "LEFT", 10, 0)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
        local boxBrd = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6, PP)

        local chk = box:CreateTexture(nil, "ARTWORK")
        PP.SetInside(chk, box, 2, 2)
        local gr = EllesmereUI.ELLESMERE_GREEN
        chk:SetColorTexture(gr.r, gr.g, gr.b, 1)

        local lbl = row:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(fontPath, 13, "")
        lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
        lbl:SetText(labels[key] or key)

        local hl = row:CreateTexture(nil, "ARTWORK")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0)

        local function UpdateCheck()
            if checked[key] then
                chk:Show()
                boxBrd:SetColor(gr.r, gr.g, gr.b, 0.8)
            else
                chk:Hide()
                boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
            end
        end

        if isCurrent then
            -- Current element: checked, grayed out, non-interactive
            lbl:SetTextColor(0.45, 0.45, 0.45, 0.7)
            chk:Show()
            boxBrd:SetColor(gr.r, gr.g, gr.b, 0.4)
            chk:SetAlpha(0.4)
            row:Disable()
        else
            lbl:SetTextColor(0.75, 0.75, 0.75, 1)
            UpdateCheck()
            row:SetScript("OnEnter", function()
                lbl:SetTextColor(1, 1, 1, 1)
                hl:SetColorTexture(1, 1, 1, 0.04)
            end)
            row:SetScript("OnLeave", function()
                lbl:SetTextColor(0.75, 0.75, 0.75, 1)
                hl:SetColorTexture(1, 1, 1, 0)
            end)
            row:SetScript("OnClick", function()
                checked[key] = not checked[key]
                UpdateCheck()
                UpdateApplyState()
            end)
        end

        checkRows[key] = row
        yOff = yOff - ITEM_H
    end

    UpdateApplyState()

    -- Apply button click
    applyRow:SetScript("OnClick", function()
        local result = {}
        for _, key in ipairs(keys) do
            if checked[key] and key ~= currentKey then
                result[#result + 1] = key
            end
        end
        if #result > 0 and opts.onApply then
            opts.onApply(result)
        end
        -- White flash on targets
        if flashTargets then
            local targets = flashTargets
            if type(targets) == "function" then targets = targets() end
            for _, f in ipairs(targets) do PlayWhiteFlash(f) end
        end
        menu:Hide()
    end)

    -- Click-outside-to-close
    local blocker = CreateFrame("Button", nil, UIParent)
    blocker:SetFrameStrata("FULLSCREEN")
    blocker:SetFrameLevel(199)
    blocker:SetAllPoints(UIParent)
    blocker:SetScript("OnClick", function()
        menu:Hide()
    end)
    blocker:Show()

    menu:HookScript("OnHide", function()
        blocker:Hide()
        blocker:SetParent(nil)
        _activeMultiApplyDropdown = nil
    end)

    _activeMultiApplyDropdown = menu
    menu:Show()
    return menu
end

--------------------------------------------------------------------------------
--  BuildSyncIcon -- label-shift + "Apply to All" subtext pattern
--
--  When the setting is desynced across bars, the row label shifts up and an
--  accent-colored "Apply to All" button appears below it. Clicking it syncs.
--  Hovering it pulses the flash targets' borders (same as before).
--
--  When opts.multiApply is provided, an additional " | Apply to Multiple"
--  link appears next to "Apply to All". Clicking it opens a checkbox dropdown
--  for selective application.
--
--  opts = {
--      region       = DualRow half-region (_leftRegion / _rightRegion),
--      tooltip      = "Apply X to all Bars",          -- shown on subtext hover
--      onClick      = function() ... end,
--      isSynced     = function() return bool end,      -- required
--      flashTargets = { f1, f2, ... } or function(),   -- optional
--      multiApply   = {                                 -- optional
--          elementKeys   = { "MainBar", "Bar2", ... },
--          elementLabels = { MainBar = "Bar 1", ... },
--          getCurrentKey = function() return key end,
--          onApply       = function(checkedKeys) ... end,
--      },
--  }
--  Returns: applyBtn (the "Apply to All" button, or nil if no isSynced)
--------------------------------------------------------------------------------
local LABEL_Y_NORMAL  =  0   -- label vertical offset when synced
local LABEL_Y_SHIFTED =  8   -- label vertical offset when desynced (shifted up)
local SUBTEXT_Y       = -8   -- "Apply to All" vertical offset below center
local ANIM_DUR        = 0.20 -- seconds for slide/fade transition

local function BuildSyncIcon(opts)
    local region = opts.region
    local label  = region and region._label
    if not region or not label then return nil end
    if not opts.isSynced then return nil end

    local ar, ag, ab = EllesmereUI.GetAccentColor()

    -- "Apply to All" clickable text button
    local applyBtn = CreateFrame("Button", nil, region)
    applyBtn:SetFrameLevel(region:GetFrameLevel() + 4)

    local applyText = applyBtn:CreateFontString(nil, "OVERLAY")
    applyText:SetFont(EXPRESSWAY, 11, "")
    applyText:SetTextColor(ar, ag, ab, 1)
    applyText:SetText("Apply to All")
    applyText:SetPoint("LEFT", applyBtn, "LEFT", 0, 0)

    -- "Apply to Multiple" link (only when multiApply opts are provided)
    local multiBtn, multiText, sepText
    if opts.multiApply then
        sepText = applyBtn:CreateFontString(nil, "OVERLAY")
        sepText:SetFont(EXPRESSWAY, 11, "")
        sepText:SetTextColor(0.45, 0.45, 0.45, 0.7)
        sepText:SetText(" | ")
        sepText:SetPoint("LEFT", applyText, "RIGHT", 0, 0)

        multiBtn = CreateFrame("Button", nil, region)
        multiBtn:SetFrameLevel(region:GetFrameLevel() + 4)
        multiText = multiBtn:CreateFontString(nil, "OVERLAY")
        multiText:SetFont(EXPRESSWAY, 11, "")
        multiText:SetTextColor(ar, ag, ab, 1)
        multiText:SetText("Apply to Multiple")
        multiText:SetPoint("CENTER", multiBtn, "CENTER", 0, 0)
        multiBtn:SetSize(100, 14)  -- initial estimate, corrected below
        -- Anchor multiBtn right after the separator
        multiBtn:SetPoint("LEFT", sepText, "RIGHT", 0, 0)
    end

    -- Size the button to the text + 2px padding each side (set after first render via OnUpdate)
    applyBtn:SetSize(80, 14)  -- initial estimate, corrected below
    local function ResizeBtn()
        local tw = applyText:GetStringWidth()
        local th = applyText:GetStringHeight()
        if tw and tw > 0 then
            applyBtn:SetSize(tw + 4, th + 4)
        end
        if multiBtn and multiText then
            local mw = multiText:GetStringWidth()
            local mh = multiText:GetStringHeight()
            if mw and mw > 0 then
                multiBtn:SetSize(mw + 4, mh + 4)
            end
        end
    end
    -- Anchor subtext below label's left edge
    local labelPoint = { label:GetPoint(1) }
    local labelXOff  = labelPoint[4] or 20
    PP.Point(applyBtn, "LEFT", region, "LEFT", labelXOff - 1, SUBTEXT_Y)

    -- ----------------------------------------------------------------
    --  State: track current animated position (0 = synced, 1 = desynced)
    -- ----------------------------------------------------------------
    local animState = opts.isSynced() and 0 or 1  -- start at correct state

    local function ApplyState(s)
        -- s: 0 = synced (label centered, subtext hidden), 1 = desynced (label up, subtext visible)
        local labelY = LABEL_Y_NORMAL + s * (LABEL_Y_SHIFTED - LABEL_Y_NORMAL)
        label:ClearAllPoints()
        PP.Point(label, "LEFT", region, "LEFT", labelXOff, labelY)
        applyBtn:SetAlpha(s)
        if s <= 0 then applyBtn:Hide() else applyBtn:Show() end
        if multiBtn then
            multiBtn:SetAlpha(s)
            if s <= 0 then multiBtn:Hide() else multiBtn:Show() end
        end
        if sepText then sepText:SetAlpha(s) end
    end

    -- Apply immediately on load (no animation)
    ApplyState(animState)
    ResizeBtn()

    -- ----------------------------------------------------------------
    --  Animate state transitions (uses a dedicated frame to avoid
    --  conflicting with the pulse OnUpdate on applyBtn)
    -- ----------------------------------------------------------------
    local animFrame = CreateFrame("Frame", nil, region)
    local animTarget = animState
    local function AnimateTo(target)
        if target == animTarget and not animFrame:GetScript("OnUpdate") and
           math.abs(animState - target) < 0.01 then return end
        animTarget = target
        animFrame:SetScript("OnUpdate", function(self, dt)
            local dir = animTarget > animState and 1 or -1
            animState = animState + dir * (dt / ANIM_DUR)
            if (dir == 1 and animState >= animTarget) or (dir == -1 and animState <= animTarget) then
                animState = animTarget
                self:SetScript("OnUpdate", nil)
            end
            ApplyState(animState)
        end)
    end

    -- ----------------------------------------------------------------
    --  Button scripts
    -- ----------------------------------------------------------------
    applyBtn:SetScript("OnClick", function()
        if opts.onClick then opts.onClick() end
        -- White border flash on all targets
        local targets = opts.flashTargets
        if targets then
            if type(targets) == "function" then targets = targets() end
            for _, f in ipairs(targets) do PlayWhiteFlash(f) end
        end
    end)

    -- ----------------------------------------------------------------
    --  "Apply to Multiple" button scripts
    -- ----------------------------------------------------------------
    if multiBtn then
        multiBtn:SetScript("OnClick", function()
            BuildMultiApplyDropdown(multiBtn, opts.multiApply, opts.flashTargets)
        end)
    end

    -- ----------------------------------------------------------------
    --  RefreshPage hook: animate when sync state changes.
    --  Deferred if a slider is being dragged or color picker is open,
    --  so the label doesn't jitter mid-interaction.
    -- ----------------------------------------------------------------
    EllesmereUI.RegisterWidgetRefresh(function()
        -- Re-color accent in case it changed
        local r, g, b = EllesmereUI.GetAccentColor()
        applyText:SetTextColor(r, g, b, 1)
        if multiText then multiText:SetTextColor(r, g, b, 1) end
        ResizeBtn()

        local synced = opts.isSynced()
        local target = synced and 0 or 1

        -- Slider dragging: allow showing (desynced → 1) immediately,
        -- but defer hiding (synced → 0) until the drag ends.
        if EllesmereUI._sliderDragging then
            if target == 1 then
                -- Value diverged mid-drag — show right away
                AnimateTo(1)
            else
                -- Values re-converged mid-drag — don't hide yet, defer to drag end
                if not EllesmereUI._deferredDriftChecks then
                    EllesmereUI._deferredDriftChecks = {}
                end
                EllesmereUI._deferredDriftChecks[function()
                    local r2, g2, b2 = EllesmereUI.GetAccentColor()
                    applyText:SetTextColor(r2, g2, b2, 1)
                    if multiText then multiText:SetTextColor(r2, g2, b2, 1) end
                    ResizeBtn()
                    AnimateTo(opts.isSynced() and 0 or 1)
                end] = true
            end
            return
        end

        -- Color picker open: defer all changes until it closes
        if EllesmereUI._colorPickerOpen then
            if not EllesmereUI._deferredDriftChecks then
                EllesmereUI._deferredDriftChecks = {}
            end
            EllesmereUI._deferredDriftChecks[function()
                local r2, g2, b2 = EllesmereUI.GetAccentColor()
                applyText:SetTextColor(r2, g2, b2, 1)
                if multiText then multiText:SetTextColor(r2, g2, b2, 1) end
                ResizeBtn()
                AnimateTo(opts.isSynced() and 0 or 1)
            end] = true
            return
        end

        AnimateTo(target)
    end)

    return applyBtn
end

EllesmereUI.BuildSliderCore     = BuildSliderCore
EllesmereUI.BuildDropdownControl = BuildDropdownControl
EllesmereUI.BuildColorSwatch    = BuildColorSwatch
EllesmereUI.BuildToggleControl   = BuildToggleControl
EllesmereUI.BuildCheckboxControl = BuildCheckboxControl
EllesmereUI.BuildCogPopup       = BuildCogPopup
EllesmereUI.BuildSyncIcon       = BuildSyncIcon
EllesmereUI.BuildMultiApplyDropdown = BuildMultiApplyDropdown
EllesmereUI.ShowWidgetTooltip   = ShowWidgetTooltip
EllesmereUI.HideWidgetTooltip   = HideWidgetTooltip
EllesmereUI.DisabledTooltip     = DisabledTooltip
EllesmereUI.BuildSegmentedControl = BuildSegmentedControl

-------------------------------------------------------------------------------
--  SharedMedia helpers: append LSM fonts/textures to dropdown tables
--  Called from each options file after building its local font/texture tables.
-------------------------------------------------------------------------------

-- Eagerly build the SM font name→path lookup so ResolveFontName works
-- immediately after deferred init (before any options page is opened).
do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local smFonts = LSM:HashTable("font")
        if smFonts then
            local lut = {}
            for name, path in pairs(smFonts) do lut[name] = path end
            EllesmereUI._smFontPaths = lut
        end
    end
end

end  -- end deferred init
