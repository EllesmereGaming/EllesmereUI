if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets.lua -- Shared Widget Helpers + Widget Factory
--  Constants & utilities live in EllesmereUI.lua.
--  DEFERRED: body runs on first EllesmereUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()
local PP = EllesmereUI.PanelPP
local isRussian = GetLocale() == "ruRU"

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
--  Physical-pixel sizing for toggle / checkbox widgets: at userScale ~= 1.0,
--  panel coords don't map 1:1 to physical pixels, causing sub-pixel drift on
--  inner elements (knob, checkmark). Fix: express pixel counts as
--  PP.SnapForES(px * onePixel, es) so every dimension lands on an exact pixel.
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
    -- Physical pixel count -> panel coord units, snapped to exactly that many pixels.
    local RealPP = EllesmereUI.PP
    local onePixel = RealPP.perfect / es
    return px * onePixel
end



-------------------------------------------------------------------------------

--  BuildToggleControl(parent, frameLevel, getValue, setValue, opts)
--  Toggle switch (track + knob) with animated on/off transition.
--  Returns: toggle (Button), applyVisual (fn), snapToState (fn)
--  opts: .sizeRatio  multiplier on track/knob sizes (default 1.0)
--        .noAnim     snap instead of animate (used by cog popup)
--        .offColors  {trackR,trackG,trackB,trackA, knobR,knobG,knobB,knobA}
--        .onColors   {trackA, knobR,knobG,knobB,knobA}  (track RGB = accent)
-------------------------------------------------------------------------------
local function BuildToggleControl(parent, frameLevel, getValue, setValue, opts)
    -- Spec Overrides auto-capture: report every write + host frame for slot attribution during an active Editing-as session.
    do
        local _s = setValue
        setValue = function(...)
            _s(...)
            if EllesmereUI._NotifySettingWrite then EllesmereUI._NotifySettingWrite(parent) end
        end
    end
    do local _r = setValue; setValue = function(...) _r(...); EllesmereUI._settingsChanged = true end end
    opts = opts or {}
    local RealPP = EllesmereUI.PP

    local TOGGLE_W, TOGGLE_H = 40, 20
    local KNOB_PAD = 2

    if opts.sizeRatio and opts.sizeRatio ~= 1 then
        local r = opts.sizeRatio
        TOGGLE_W = math.floor(TOGGLE_W * r + 0.5)
        TOGGLE_H = math.floor(TOGGLE_H * r + 0.5)
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

    -- PanelPP for knob offsets: SetPoint coords are relative to the toggle (panel coordinate space).
    local PanelPP = EllesmereUI.PanelPP or RealPP
    local snappedPad = PanelPP.Scale(KNOB_PAD)

    local knob = toggle:CreateTexture(nil, "ARTWORK")
    DisablePixelSnap(knob)
    knob:SetColorTexture(offKR, offKG, offKB, offKA)

    -- Two-point vertical anchoring: knob top/bottom sit exactly snappedPad from the track edges (no independent size calc); width is set explicitly from snapped track height minus the two pads so the knob stays square.
    local snappedTrackH = PanelPP.Scale(TOGGLE_H)
    local snappedTrackW = PanelPP.Scale(TOGGLE_W)
    local knobSz = snappedTrackH - snappedPad * 2

    -- OFF = left edge, ON = right edge. Raw offsets, no PP.Scale. POS_ON is computed at SetKnobPos time from the toggle's actual rendered width so it matches the real right edge despite any RealPP/PanelPP scale mismatch.
    local POS_OFF = snappedPad
    local POS_ON  = 0  -- computed dynamically in SetKnobPos

    -- Raw SetPoint (bypass PP snapping); TOPLEFT + BOTTOMLEFT with explicit width gives an equal vertical gap.
    local function SetKnobPos(xOff)
        knob:ClearAllPoints()
        knob:SetPoint("TOPLEFT", toggle, "TOPLEFT", xOff, -snappedPad)
        knob:SetPoint("BOTTOMLEFT", toggle, "BOTTOMLEFT", xOff, snappedPad)
        knob:SetWidth(knobSz)
    end

    local function GetPosOn()
        local w = toggle:GetWidth()
        if w and w > 0 then
            return w - snappedPad - knobSz
        end
        return snappedTrackW - snappedPad - knobSz
    end

    local animProgress = getValue() and 1 or 0
    local animTarget   = animProgress
    local ANIM_DUR = 0.075

    local function ApplyVisual(p)
        local posOn = GetPosOn()
        local xOff = lerp(POS_OFF, posOn, p)
        -- Round mid-animation only; at endpoints use pre-snapped values so effective-scale rounding can't shift the knob.
        if p > 0 and p < 1 then
            local es = toggle:GetEffectiveScale()
            if es and es > 0 then
                xOff = math.floor(xOff * es + 0.5) / es
            end
        end
        SetKnobPos(xOff)
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

--  BuildCheckboxControl(parent, frameLevel) -- box + border + checkmark texture
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

-- MakeStyledButton + WB_COLOURS/RB_COLOURS live in EllesmereUI_UICore.lua (runtime login popups use them too).
local MakeStyledButton = EllesmereUI.MakeStyledButton
local WB_COLOURS = EllesmereUI.WB_COLOURS
local RB_COLOURS = EllesmereUI.RB_COLOURS

-- Widget tooltip system lives in EllesmereUI_UICore.lua.
local ShowWidgetTooltip, HideWidgetTooltip = EllesmereUI.ShowWidgetTooltip, EllesmereUI.HideWidgetTooltip

-- Global search index registration for ONE setting. Single-setting rows go via TagOptionRow; multi-slot rows (DualRow, TripleRow, offset rows, wide button rows) call this once per slot so every result is exactly one setting, never a concatenated row label. No-op until the optional EllesmereUI_GlobalSearch.lua defines it.
local function IndexSlotForSearch(parent, labelText, tooltipText)
    if not EllesmereUI._RegisterSearchEntry then return end
    if not labelText or labelText == "" then return end
    local sectionName = parent._currentSection and parent._currentSection._sectionName
    local loc = EllesmereUI.L(labelText)
    -- Some pages show different content per internal selector (CDM bar / action bar / unit); see _buildingSelector.
    local sel = EllesmereUI._buildingSelector
    EllesmereUI._RegisterSearchEntry(labelText, loc ~= labelText and loc or nil,
        type(tooltipText) == "string" and tooltipText or nil,
        EllesmereUI._buildingModule, EllesmereUI._buildingPage, sectionName,
        sel and sel.setter, sel and sel.key)
end

-- Search metadata: tag a row frame so inline search can find it. Combined multi-slot label stays on the FRAME (page search matches whole rows, then narrows to slots); multiSlot=true skips global indexing here because the caller indexes each slot via IndexSlotForSearch.
local function TagOptionRow(frame, parent, labelText, tooltipText, multiSlot)
    frame._isOptionRow = true
    frame._labelText = labelText
    -- Bilingual search: store the localized label only when it differs from the English key (nil on enUS).
    local _loc = EllesmereUI.L(labelText)
    if _loc ~= labelText then frame._labelTextLoc = _loc end
    frame._sectionHeader = parent._currentSection
    if not multiSlot then
        IndexSlotForSearch(parent, labelText, tooltipText)
    end
end

-- Disabled-widget tooltip wrapper lives in EllesmereUI_UICore.lua.
local DisabledTooltip = EllesmereUI.DisabledTooltip

-- Final disabled-tooltip string for a widget cfg (or cog-popup row / inline sub-config); nil = nothing to show. Honors:
--   cfg.disabledTooltip -- string OR fn returning requirement text/sentence
--   cfg.rawTooltip      -- bool OR fn; true => verbatim, skip the wrapper
--   cfg.requireState    -- "enabled" (default) or "disabled"; wrapper verb
local function ResolveDisabledTip(cfg)
    local tt = cfg.disabledTooltip
    if type(tt) == "function" then tt = tt() end
    if tt == nil then return nil end
    local raw = cfg.rawTooltip
    if type(raw) == "function" then raw = raw() end
    -- rawTooltip skips the wrapper sentence, not the translation.
    if raw then return EllesmereUI.L(tt) end
    return DisabledTooltip(tt, cfg.requireState)
end

-- Disabled-tooltip overlay on a control frame (slider region, toggle, swatch): shows tooltip centered when hovered while disabled.
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
            local tt = ResolveDisabledTip(cfg)
            if tt then ShowWidgetTooltip(controlAnchor, tt) end
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


-- Display label for a dropdown, handling subnav children: top-level key with a subnav -> 'ParentText: ChildText'; a subnav child key -> search all values for its parent; else DDText(values[curKey]) or tostring(curKey).
local function DDResolveLabel(values, order, curKey)
    -- Localize the visible label only; raw-key fallback is data. Data dropdowns (profile/spell lists) opt out via _noLoc.
    local noLoc = values and values._noLoc
    local function TR(s)
        if noLoc or type(s) ~= 'string' then return s end
        return EllesmereUI.L(s)
    end
    -- Direct top-level match (non-subnav)
    local direct = values[curKey]
    if direct and type(direct) ~= 'table' then return TR(direct) end
    if direct and type(direct) == 'table' and not direct.subnav then return TR(direct.text) end
    -- curKey might be a subnav child  search all values for a parent with subnav
    for _, parentKey in ipairs(order) do
        local pv = values[parentKey]
        if type(pv) == 'table' and pv.subnav then
            local sv = pv.subnav.values
            if sv and sv[curKey] then
                return TR(pv.text) .. ' - ' .. TR(sv[curKey])
            end
        end
    end
    -- SharedMedia keys ("sm:<name>") whose provider isn't loaded are absent from `values`; show the clean media name, never the raw "sm:" key.
    if type(curKey) == 'string' then
        local smName = curKey:match('^sm:(.+)')
        if smName then return smName end
    end
    return tostring(curKey)
end
local function DDFont(v)
    if type(v) == "table" then return v.font end
    return nil
end

local function IsDividerKey(key)
    return type(key) == "string" and key:match("^%-%-%-") ~= nil
end

-- Build a dropdown popup menu + item buttons; returns { menu, menuItems, refresh }. ddBtn = button the menu hangs off; menuW = menu pixel width; order = key array; values = { key = displayName } (displayName: string or { text=..., note=... }); ddLbl = label FontString updated on selection; style = "wide"/"regular" (WD_ vs RD_ colours).
local DD_MAX_HEIGHT = 200

local function BuildDropdownMenu(ddBtn, menuW, order, values, getValue, setValue, ddLbl, style, disabledValuesFn)
    do
        local _r = setValue
        setValue = function(...)
            _r(...)
            EllesmereUI._settingsChanged = true
            -- Spec Overrides auto-capture (see BuildToggleControl): dropdown button sits inside the host slot's region.
            if EllesmereUI._NotifySettingWrite then EllesmereUI._NotifySettingWrite(ddBtn) end
        end
    end
    local isWide = (style == "wide")
    -- Localize visible item captions only; data dropdowns opt out via _noLoc.
    local _noLoc = values and values._noLoc
    local function TR(s)
        if _noLoc or type(s) ~= 'string' then return s end
        return EllesmereUI.L(s)
    end
    -- Menu bg/border: same colours for both styles (DD_BTN with menu-specific alpha)
    local _menuOpts = values._menuOpts
    local _moIcon = _menuOpts and _menuOpts.icon
    local _moIconAtlas = _menuOpts and _menuOpts.iconAtlas
    local _moIconPressedAtlas = _menuOpts and _menuOpts.iconPressedAtlas
    local _moIconOnClick = _menuOpts and _menuOpts.iconOnClick
    local _moIconTooltip = _menuOpts and _menuOpts.iconTooltip
    local _moBackground = _menuOpts and _menuOpts.background
    local _moBgVertexColor = _menuOpts and _menuOpts.backgroundVertexColor
    local _moItemH = _menuOpts and _menuOpts.itemHeight or 26
    local _moMaxTextPct = _menuOpts and _menuOpts.maxTextWidthPct
    local _moOnItemHover = _menuOpts and _menuOpts.onItemHover
    local _moOnItemLeave = _menuOpts and _menuOpts.onItemLeave
    -- Optional in-menu search box (_menuOpts.searchable): filter field hides non-matching items and repositions the rest. Flat lists only (no subnav, no dividers).
    local _moSearchable = _menuOpts and _menuOpts.searchable
    local SEARCH_H = 26
    local searchPad = _moSearchable and (SEARCH_H + 8) or 0
    local searchEdit, searchPlaceholder
    local searchResetScroll  -- assigned inside the scrolling branch; nil otherwise
    local mBgR, mBgG, mBgB, mBgA = DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_HA
    local mBrR, mBrG, mBrB, mBrA = 1, 1, 1, DD_BRD_A
    -- Parent to a caller-supplied frame (a scaled popup) when given so the menu INHERITS its scale and layers within it -- no manual scale matching, nested dropdowns don't render giant/behind. Else UIParent, so page dropdowns escape the scroll-frame clip.
    local menu = CreateFrame("Frame", nil, (_menuOpts and _menuOpts.parent) or UIParent)
    -- Spec Overrides auto-capture: edits through this menu attribute to the slot whose dropdown opened it.
    menu._euiOptionsPopup = true
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(200)
    menu:SetClampedToScreen(true)
    menu:SetClipsChildren(true)
    menu:EnableMouse(true)
    menu:SetSize(menuW, 10)
    -- Anchor: default opens downward; _menuOpts.anchor opens left/right so it can't sit behind controls below it.
    if _menuOpts and _menuOpts.anchor == "LEFT" then
        menu:SetPoint("TOPRIGHT", ddBtn, "TOPLEFT", -4, 0)
    elseif _menuOpts and _menuOpts.anchor == "RIGHT" then
        menu:SetPoint("TOPLEFT", ddBtn, "TOPRIGHT", 4, 0)
    else
        menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
    end
    menu:Hide()
    SolidTex(menu, "BACKGROUND", mBgR, mBgG, mBgB, mBgA):SetAllPoints()
    MakeBorder(menu, mBrR, mBrG, mBrB, mBrA, PP)

    if _moSearchable then
        -- Options panel is Expressway-locked by design; EllesmereUI.EXPRESSWAY is locale-aware (CJK/Cyrillic get the system glyph font). The user's global font intentionally never restyles the settings UI.
        local fontPath = EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
        searchEdit = CreateFrame("EditBox", nil, menu)
        searchEdit:SetSize(menuW - 16, SEARCH_H)
        searchEdit:SetPoint("TOP", menu, "TOP", 0, -4)
        searchEdit:SetFrameLevel(menu:GetFrameLevel() + 4)
        searchEdit:SetFont(fontPath, 11, "")
        searchEdit:SetTextColor(1, 1, 1, 0.9)
        searchEdit:SetJustifyH("LEFT")
        searchEdit:SetAutoFocus(false)
        searchEdit:SetMaxLetters(30)
        searchEdit:SetTextInsets(4, 4, 0, 0)
        local sBg = searchEdit:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        sBg:SetColorTexture(0, 0, 0, 0.4)
        searchPlaceholder = searchEdit:CreateFontString(nil, "OVERLAY")
        searchPlaceholder:SetFont(fontPath, 11, "")
        searchPlaceholder:SetTextColor(0.5, 0.5, 0.5, 0.6)
        searchPlaceholder:SetPoint("LEFT", searchEdit, "LEFT", 4, 0)
        searchPlaceholder:SetText(EllesmereUI.L("Search..."))
        searchEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end

    -- Items are always parented here; becomes the scroll child if scrolling is needed.
    local innerContainer = CreateFrame("Frame", nil, menu)
    innerContainer:SetWidth(menuW)
    innerContainer:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)

    local menuItems = {}
    local mH = 4
    for _, key in ipairs(order) do
        -- Keys beginning with "---" insert a thin separator line
        if IsDividerKey(key) then
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
                iLbl:SetText(TR(parentText))
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
                        cLbl:SetText(TR(childText))
                        cLbl:SetJustifyH('LEFT')
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
                            ddLbl:SetText(TR(parentText) .. ': ' .. TR(childText))
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

                local flyoutTimer
                item:SetScript('OnEnter', function()
                    iLbl:SetTextColor(1, 1, 1, 1)
                    arrowTex:SetAlpha(1)
                    iHl:SetAlpha(DD_ITEM_HL_A)
                    if flyoutTimer then flyoutTimer:Cancel(); flyoutTimer = nil end
                    flyout:ClearAllPoints()
                    flyout:SetPoint('TOPLEFT', item, 'TOPRIGHT', 2, 0)
                    flyout:Show()
                    flyout:SetScale(menu:GetScale())
                end)
                item:SetScript('OnLeave', function()
                    iLbl:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                    arrowTex:SetAlpha(0.7)
                    local cur = getValue()
                    local isChild = item._subnavChildKeys[cur]
                    iHl:SetAlpha(isChild and DD_ITEM_SEL_A or 0)
                    -- Delay hide so the mouse can travel to the flyout
                    flyoutTimer = C_Timer.NewTimer(0.25, function()
                        if not flyout:IsMouseOver() and not item:IsMouseOver() then
                            flyout:Hide()
                        end
                        flyoutTimer = nil
                    end)
                end)
                -- Keep the flyout alive while the mouse is over it
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
                menu:HookScript('OnHide', function() flyout:Hide() end)
                item:SetScript('OnClick', function() end)  -- no-op, subnav only
                mH = mH + 26
            else
            -- Annotated labels: dn = string or { text=..., note=..., font=..., action=fn }.
            -- An action row runs its callback and closes the menu WITHOUT selecting a
            -- value (the "Edit ..." entry pinned above a "---" divider); accent-colored.
            local mainText, noteText, itemFont, dnAction
            if type(dn) == "table" then
                mainText = dn.text
                noteText = dn.note
                itemFont = dn.font
                dnAction = dn.action
            else
                mainText = dn
            end
            local item = CreateFrame("Button", nil, innerContainer)
            item:SetHeight(_moItemH)
            item:SetPoint("TOPLEFT", innerContainer, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", innerContainer, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(menu:GetFrameLevel() + 2)
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
            if _moMaxTextPct then
                iLbl:SetWordWrap(false)
                iLbl:SetWidth(menuW * _moMaxTextPct)
            end
            iLbl:SetText(TR(mainText))
            if dnAction then
                local EG = EllesmereUI.ELLESMERE_GREEN
                iLbl:SetTextColor(EG.r, EG.g, EG.b, 0.8)
                item._isAction = true  -- Refresh keeps the accent across menu opens
            end
            -- Optional icon, three sources: _menuOpts.icon(key) -> texture path (+ texcoord); .iconAtlas(key) -> atlas name; .iconPressedAtlas(key) -> pressed-state atlas. With .iconOnClick the icon becomes a clickable Button on its own frame level so clicks don't reach the item's OnClick.
            local _haveAtlas = _moIconAtlas and _moIconAtlas(key) or nil
            local _iconPath, _il, _ir, _it, _ib
            if _moIcon and not _haveAtlas then
                _iconPath, _il, _ir, _it, _ib = _moIcon(key)
            end
            if _haveAtlas or _iconPath then
                local icoSz = _moItemH - 8
                if _moIconOnClick then
                    local iconBtn = CreateFrame("Button", nil, item)
                    iconBtn:SetSize(icoSz, icoSz)
                    iconBtn:SetPoint("RIGHT", item, "RIGHT", -6, 0)
                    iconBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                    if _haveAtlas then
                        iconBtn:SetNormalAtlas(_haveAtlas)
                        local pressedAtlas = _moIconPressedAtlas and _moIconPressedAtlas(key)
                        if pressedAtlas then
                            iconBtn:SetPushedAtlas(pressedAtlas)
                        end
                        iconBtn:SetHighlightAtlas(_haveAtlas)
                        -- Atlas icons carry an intrinsic colour; SetVertexColor only scales it, so desaturate first, then tint to #929292.
                        local _nr, _ng, _nb = 0.573, 0.573, 0.573
                        local nrmTex = iconBtn:GetNormalTexture()
                        if nrmTex then
                            if nrmTex.SetDesaturated then nrmTex:SetDesaturated(true) end
                            nrmTex:SetVertexColor(_nr, _ng, _nb, 1)
                        end
                        local psdTex = iconBtn:GetPushedTexture()
                        if psdTex then
                            if psdTex.SetDesaturated then psdTex:SetDesaturated(true) end
                            psdTex:SetVertexColor(_nr, _ng, _nb, 1)
                        end
                        local hlTex = iconBtn:GetHighlightTexture()
                        if hlTex then
                            if hlTex.SetDesaturated then hlTex:SetDesaturated(true) end
                            hlTex:SetVertexColor(_nr, _ng, _nb, 1)
                            hlTex:SetAlpha(0.4)
                        end
                    else
                        local ico = iconBtn:CreateTexture(nil, "ARTWORK")
                        ico:SetAllPoints()
                        ico:SetTexture(_iconPath)
                        if _il then ico:SetTexCoord(_il, _ir, _it, _ib) end
                        ico:SetVertexColor(0.8, 0.8, 0.8, 1)
                        iconBtn._ico = ico
                    end
                    iconBtn:SetScript("OnEnter", function()
                        if iconBtn._ico then iconBtn._ico:SetVertexColor(1, 1, 1, 1) end
                        if _moIconTooltip then
                            ShowWidgetTooltip(iconBtn, _moIconTooltip(key))
                        end
                    end)
                    iconBtn:SetScript("OnLeave", function()
                        if iconBtn._ico then iconBtn._ico:SetVertexColor(0.8, 0.8, 0.8, 1) end
                        if _moIconTooltip then HideWidgetTooltip() end
                    end)
                    iconBtn:SetScript("OnClick", function()
                        _moIconOnClick(key)
                    end)
                    iLbl:SetPoint("RIGHT", iconBtn, "LEFT", -4, 0)
                else
                    local ico = item:CreateTexture(nil, "ARTWORK")
                    -- _menuOpts.iconWidth(key) allows non-square icons; default square.
                    ico:SetSize((_menuOpts and _menuOpts.iconWidth and _menuOpts.iconWidth(key)) or icoSz, icoSz)
                    ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
                    if _haveAtlas then
                        ico:SetAtlas(_haveAtlas)
                    else
                        ico:SetTexture(_iconPath)
                        if _il then ico:SetTexCoord(_il, _ir, _it, _ib) end
                    end
                    iLbl:SetPoint("RIGHT", ico, "LEFT", -4, 0)
                end
            end
            local iNote  -- annotation: smaller font, 75% alpha, same colour
            if noteText then
                iNote = MakeFont(item, 11, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                iNote:SetAlpha(0.75)
                iNote:SetPoint("LEFT", iLbl, "RIGHT", 4, 0)
                iNote:SetText(TR(noteText))
            end
            local iHl = SolidTex(item, "ARTWORK", 1, 1, 1, 1); iHl:SetAlpha(0)
            iHl:SetAllPoints()
            item._key, item._label, item._highlight, item._note = key, iLbl, iHl, iNote
            -- Full display name for the dropdown button label
            item._displayName = noteText and (mainText .. " " .. noteText) or mainText
            menuItems[#menuItems + 1] = item
            item:SetScript("OnEnter", function()
                if disabledValuesFn then
                    local dv = disabledValuesFn(key)
                    if dv then
                        -- A string return doubles as the tooltip text
                        if type(dv) == "string" then ShowWidgetTooltip(item, dv) end
                        return
                    end
                end
                iLbl:SetTextColor(1, 1, 1, 1)
                if iNote then iNote:SetTextColor(1, 1, 1, 1) end
                iHl:SetAlpha(DD_ITEM_HL_A)
                -- Second arg (item frame) is additive: (key)-only handlers ignore it; others use it to anchor tooltips.
                if _moOnItemHover then _moOnItemHover(key, item) end
            end)
            item:SetScript("OnLeave", function()
                if disabledValuesFn and disabledValuesFn(key) then HideWidgetTooltip(); return end
                if dnAction then
                    local EG = EllesmereUI.ELLESMERE_GREEN
                    iLbl:SetTextColor(EG.r, EG.g, EG.b, 0.8)
                else
                    iLbl:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                end
                if iNote then iNote:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A) end
                iHl:SetAlpha((item._key == getValue()) and DD_ITEM_SEL_A or 0)
                if _moOnItemLeave then _moOnItemLeave(key, item) end
            end)
            item:SetScript("OnClick", function()
                if disabledValuesFn and disabledValuesFn(key) then return end
                if dnAction then
                    menu:Hide()
                    dnAction()
                    return
                end
                setValue(key); ddLbl:SetText(TR(mainText))
                menu:Hide()
                -- Deferred refresh: setValue may have mutually-excluded another dropdown (e.g. left/right text); the zero-delay timer updates its label after the menu fully closes.
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

    local totalContentH = mH + 3
    innerContainer:SetHeight(totalContentH)

    ---------------------------------------------------------------------------
    --  Scrollable dropdown: content over DD_MAX_HEIGHT is wrapped in a ScrollFrame with a thin custom scrollbar + smooth scrolling.
    ---------------------------------------------------------------------------
    if totalContentH > (_menuOpts and _menuOpts.maxHeight or DD_MAX_HEIGHT) then
        menu:SetHeight((_menuOpts and _menuOpts.maxHeight or DD_MAX_HEIGHT) + searchPad)

        local sf = CreateFrame("ScrollFrame", nil, menu)
        sf:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -searchPad)
        sf:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0)
        sf:SetFrameLevel(menu:GetFrameLevel() + 1)
        sf:EnableMouseWheel(true)
        sf:SetScrollChild(innerContainer)
        innerContainer:SetWidth(menuW)

        -- Thin scrollbar track (4px, right side; matches main panel style)
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
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
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

        -- Lets the search filter snap back to the top after the list changes.
        searchResetScroll = function()
            ddScrollTarget = 0
            sf:SetVerticalScroll(0)
            UpdateDDThumb()
        end

        ddSmoothFrame:SetScript("OnUpdate", function(_, elapsed)
            local cur = sf:GetVerticalScroll()
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
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
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
            ddScrollTarget = math.max(0, math.min(maxScroll, target))
            if not ddSmoothing then
                ddSmoothing = true
                ddSmoothFrame:Show()
            end
        end

        sf:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = EllesmereUI.SafeScrollRange(self)
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
            menu._ddThumbDragging = true  -- suppress click-away dismiss while dragging the scrollbar
            ddSmoothing = false
            ddSmoothFrame:Hide()
            local _, cursorY = GetCursorPosition()
            ddDragStartY = cursorY / self:GetEffectiveScale()
            ddDragStartScroll = sf:GetVerticalScroll()
            self:SetScript("OnUpdate", function(self2)
                if not IsMouseButtonDown("LeftButton") then
                    ddDragging = false
                    menu._ddThumbDragging = false
                    self2:SetScript("OnUpdate", nil)
                    return
                end
                local _, cy = GetCursorPosition()
                cy = cy / self2:GetEffectiveScale()
                local deltaY = ddDragStartY - cy
                local trackH = ddTrack:GetHeight()
                local maxTravel = trackH - self2:GetHeight()
                if maxTravel <= 0 then return end
                local maxScroll = EllesmereUI.SafeScrollRange(sf)
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
            menu._ddThumbDragging = false
            self:SetScript("OnUpdate", nil)
        end)

        menu:HookScript("OnHide", function()
            ddSmoothing = false
            ddSmoothFrame:Hide()
            ddScrollTarget = 0
            sf:SetVerticalScroll(0)
        end)

        menu:HookScript("OnShow", function()
            ddScrollTarget = 0
            sf:SetVerticalScroll(0)
            UpdateDDThumb()
        end)
    else
        menu:SetHeight(totalContentH + searchPad)
        if searchPad > 0 then
            innerContainer:ClearAllPoints()
            innerContainer:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -searchPad)
            innerContainer:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 0)
        else
            innerContainer:SetAllPoints(menu)
        end
    end

    -- Optional search filter, wired once items/container/scroll helpers exist. Matches visible label text (any locale).
    if searchEdit then
        local function ApplySearchFilter(raw)
            local q = strlower(strtrim(raw or ""))
            if searchPlaceholder then searchPlaceholder:SetShown(q == "") end
            local visIdx = 0
            for _, item in ipairs(menuItems) do
                local name = (item._label and item._label:GetText()) or item._displayName or ""
                if q == "" or strfind(strlower(tostring(name)), q, 1, true) then
                    item:Show()
                    item:ClearAllPoints()
                    item:SetPoint("TOPLEFT", innerContainer, "TOPLEFT", 1, -(4 + visIdx * _moItemH))
                    item:SetPoint("TOPRIGHT", innerContainer, "TOPRIGHT", -1, -(4 + visIdx * _moItemH))
                    visIdx = visIdx + 1
                else
                    item:Hide()
                end
            end
            innerContainer:SetHeight(math.max(1, 4 + visIdx * _moItemH + 3))
            if searchResetScroll then searchResetScroll() end
        end
        searchEdit:SetScript("OnTextChanged", function(self) ApplySearchFilter(self:GetText()) end)
        -- Focus the dropdown search on open
        local function FocusSearch()
            searchEdit:SetText("")
            ApplySearchFilter("")
            searchEdit:SetFocus()
        end
        menu._focusSearch = FocusSearch
        menu:HookScript("OnShow", FocusSearch)
        menu:HookScript("OnHide", function()
            searchEdit:SetText("")
            searchEdit:ClearFocus()
        end)
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
                if item._isAction then
                    local EG = EllesmereUI.ELLESMERE_GREEN
                    item._label:SetTextColor(EG.r, EG.g, EG.b, 0.8)
                else
                    item._label:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, off and 0.18 or TEXT_DIM_A)
                end
                if item._note then
                    item._note:SetAlpha(1)
                    item._note:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, off and 0.12 or (TEXT_DIM_A * 0.75))
                end
            end
        end
    end
    return menu, menuItems, Refresh
end

-- Wire OnEnter/OnLeave/OnClick/OnShow/OnHide for a dropdown button + menu. s = { bg_r..a, bg_hr..ha, brd_r..a, brd_hr..ha, txt_r..a, txt_hr..ha } (24 values)
local function WireDropdownScripts(ddBtn, ddLbl, bg, brd, menu, refresh, s, keepClickHandler)
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
    -- keepClickHandler: caller owns OnClick/OnHide (BuildDropdownControl's lazy-menu path). Overwriting OnClick
    -- here would (a) pin this menu instance forever so _invalidateMenu could never rebuild -- clicks would Show()
    -- the orphaned menu, rendering behind everything since SetParent(nil) resets strata -- and (b) wipe any
    -- HookScripts callers attached to OnClick, since SetScript discards existing hooks.
    if not keepClickHandler then
        ddBtn:SetScript("OnClick", function()
            if ddBtn._ttText then HideWidgetTooltip() end
            if menu:IsShown() then menu:Hide() else menu:Show() end
        end)
        ddBtn:HookScript("OnHide", function() menu:Hide() end)
    end
    menu:SetScript("OnShow", function(self)
        -- Detect custom parenting via GetParent(); _menuOpts is out of scope here.
        if menu:GetParent() ~= UIParent then
            -- Scaled popup parent: scale is inherited, leave at 1 (nothing to match, nothing to go stale).
            self:SetScale(1)
        else
            -- On UIParent: match the panel's effective scale by walking GetScale() up to UIParent (always current); the button's GetEffectiveScale ratio can be stale right after the popup is (re)built.
            local s, f = 1, ddBtn
            while f and f ~= UIParent do s = s * (f:GetScale() or 1); f = f:GetParent() end
            self:SetScale(s)
        end
        -- Track the open menu globally so popups don't treat clicks on it (which can extend outside the popup/panel) as a dismissing outside click.
        EllesmereUI._openDropdownMenu = self
        ApplyHover()
        refresh()
        -- This SetScript replaces BuildDropdownMenu's OnShow hook, so drive its search auto-focus directly.
        if menu._focusSearch then menu._focusSearch() end
        self:SetScript("OnUpdate", function(m)
            local flyoverFlyout = false; if m._flyouts then for _, fo in ipairs(m._flyouts) do if fo:IsShown() and fo:IsMouseOver() then flyoverFlyout = true; break end end end
            if not m:IsMouseOver() and not ddBtn:IsMouseOver() and not flyoverFlyout and not m._ddThumbDragging and IsMouseButtonDown("LeftButton") then m:Hide(); return end
            -- Close when the button's bottom edge leaves the visible scroll area (skipped for buttons outside the scroll child, e.g. content header dropdowns).
            local scrollFrame = EllesmereUI._scrollFrame
            if scrollFrame then
                -- Ancestor check cached on the button (runs once per menu open)
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
        if EllesmereUI._openDropdownMenu == self then EllesmereUI._openDropdownMenu = nil end
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

-- Slider core (track + fill + thumb + input + drag logic). Returns: trackFrame, valBox, RefreshSlider, thumb
local function BuildSliderCore(parent, trackW, trackH, thumbSz, inputW, inputH, inputFontSz, inputAlpha, minVal, maxVal, step, getValue, setValue, isMultiWidget, snapPoints)
    -- Spec Overrides auto-capture: see BuildToggleControl.
    do
        local _s = setValue
        setValue = function(...)
            _s(...)
            if EllesmereUI._NotifySettingWrite then EllesmereUI._NotifySettingWrite(parent) end
        end
    end
    do local _r = setValue; setValue = function(...) _r(...); EllesmereUI._settingsChanged = true end end
    -- Multi-widget overrides: brighter track alpha, boosted input alpha
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
    -- Opaque blocker behind the thumb hides the track fill line; SetIgnoreParentAlpha keeps it solid when the slider grays out at 0.3.
    local thumbBlockerFrame = CreateFrame("Frame", nil, thumb)
    thumbBlockerFrame:SetAllPoints()
    thumbBlockerFrame:SetFrameLevel(thumb:GetFrameLevel())
    thumbBlockerFrame:SetIgnoreParentAlpha(true)
    local thumbBlocker = thumbBlockerFrame:CreateTexture(nil, "BACKGROUND")
    thumbBlocker:SetAllPoints()
    thumbBlocker:SetColorTexture(DARK_BG.r, DARK_BG.g, DARK_BG.b, 1)
    local thumbTex = SolidTex(thumb, "ARTWORK", ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
    thumbTex:SetAllPoints()

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

    -- Snap ANCHORED AT MIN, not at zero: the values a slider may land on are
    -- min, min + step, min + 2*step... A zero-anchored snap only agrees when
    -- min is itself a multiple of the step, and a slider whose min is not --
    -- an odd-count one like min 1, step 2 -- landed on the evens with its own
    -- minimum unreachable. Identical for every slider whose min IS a multiple
    -- of its step, which is all the rest of them.
    local function SnapStep(v)
        local snapped = minVal + math.floor((v - minVal) / step + 0.5) * step
        return math.max(minVal, math.min(maxVal, snapped))
    end

    local currentVal = getValue()
    local function UpdateSliderVisual(val)
        local ratio = math.max(0, math.min(1, (val - minVal) / (maxVal - minVal)))
        trackFill:SetWidth(math.max(1, math.floor(trackW * ratio + 0.5)))
        local snapped = SnapStep(val)
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
        local snapped = SnapStep(rawDragVal)
        setValue(snapped); currentVal = snapped; rawDragVal = snapped; lastSnapped = snapped; UpdateSliderVisual(snapped)
    end

    local function SliderOnUpdate(self)
        -- Safety: stop the drag if the button released while a modifier key stole the event
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
        -- Snap to declared snap points within their threshold
        if snapPoints then
            for _, sp in ipairs(snapPoints) do
                local pt, threshold = sp[1], sp[2] or (step * 5)
                if math.abs(rawDragVal - pt) <= threshold then
                    rawDragVal = pt
                    break
                end
            end
        end
        local snapped = SnapStep(rawDragVal)
        local halfPx = HalfStepPx()
        local shouldCommit = snapped ~= lastSnapped
            and (lastCommitX == nil or math.abs(cursorX - lastCommitX) >= halfPx)
        if shouldCommit then
            setValue(snapped); currentVal = snapped; lastSnapped = snapped; lastCommitX = cursorX
            UpdateSliderVisual(stepped and snapped or rawDragVal)
        else
            -- lastSnapped for the visual prevents flicker at step boundaries
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
            local snapped = SnapStep(rawDragVal)
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
            -- Deferred drift checks fire once every slider has finished dragging
            if EllesmereUI._deferredDriftChecks then
                local checks = EllesmereUI._deferredDriftChecks
                EllesmereUI._deferredDriftChecks = nil
                for fn in pairs(checks) do fn() end
            end
            -- Re-evaluate widget state (sync icons, disabled overlays) once drag fully ends. Fast path: no page rebuild.
            if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
        end
    end

    -- Re-entrancy guard: ClearFocus() below fires OnEditFocusLost, which re-enters CommitInput and would double the refresh sweep.
    local committingInput = false

    local function CommitInput()
        if committingInput then return end
        committingInput = true
        local raw = tonumber(valBox:GetText())
        local changed = false
        if raw then
            raw = math.max(minVal, math.min(maxVal, raw))
            local snapped = SnapStep(raw)
            changed = snapped ~= currentVal
            setValue(snapped); currentVal = snapped; rawDragVal = snapped; UpdateSliderVisual(snapped)
        else
            valBox:SetText(FormatVal(currentVal))
        end
        valBox:ClearFocus()
        committingInput = false
        -- Typing must re-evaluate widget state exactly as EndDrag does, or the refresh sweep misses the change ("Apply to: All" sync indicator, disabled overlays). Only when the value changed (untouched box stays free); deferred while any slider is mid-drag to match EndDrag's once-per-drag refresh.
        if changed and not EllesmereUI._sliderDragging and EllesmereUI.RefreshPage then
            EllesmereUI:RefreshPage()
        end
    end

    valBox:SetScript("OnEnterPressed", function() CommitInput() end)
    valBox:SetScript("OnEscapePressed", function() valBox:SetText(FormatVal(currentVal)); valBox:ClearFocus() end)
    valBox:SetScript("OnEditFocusLost", function() CommitInput(); valBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A) end)
    valBox:SetScript("OnEditFocusGained", function() valBox:SetTextColor(1, 1, 1, 1); valBox:HighlightText() end)
    -- EditBox can fail to render SetText text right after becoming visible; nudging cursor position forces a re-render.
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

    -- Re-read the getter, update the visual, and re-apply the accent colour (theme may have changed on another tab).
    local function RefreshSlider()
        local v = getValue()
        if v then
            currentVal = v; rawDragVal = v; UpdateSliderVisual(v)
        end
        trackFill:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, SL.FILL_A)
        thumbTex:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
    end
    RegisterWidgetRefresh(RefreshSlider)

    return trackFrame, valBox, RefreshSlider, thumb
end

-------------------------------------------------------------------------------
--  Pixel-unit sliders (cfg.pixel = true): saved value stays in WoW coordinate units (profile format unchanged);
--  slider displays/edits whole physical screen pixels, so "1" is one on-screen pixel at any resolution/UI scale.
--  min/max convert at build time so the physical range is unchanged (identity at pixel-perfect scale, PP.mult ==
--  1). Supports both getValue/setValue (row configs) and get/set (cog popup rows) accessor conventions. Returns
--  cfg untouched when the flag is off, so callers can pass every cfg through unconditionally.
-------------------------------------------------------------------------------
local function PixelizeSliderCfg(cfg)
    -- Convert against the GAME screen grid (EllesmereUI.PP), not this file's panel-scale PanelPP: saved values live in UIParent coordinate units.
    local gamePP = EllesmereUI.PP
    if not (cfg and cfg.pixel and gamePP) then return cfg end
    local px = {}
    for k, v in pairs(cfg) do px[k] = v end
    px.min, px.max = gamePP.ToPixels(cfg.min or 0), gamePP.ToPixels(cfg.max or 0)
    -- A declared step of 1 means "finest available", not "one coordinate unit", so it must stay 1 px: converting it like min/max rounds 1 coord to 2 px whenever mult <= 2/3 (e.g. 4K at 0.71 uiScale), making odd pixel values unreachable. Only coarse steps (> 1 coordinate unit) convert, keeping their physical coarseness.
    local st = cfg.step or 1
    px.step = st > 1 and math.max(1, math.floor(st / (gamePP.mult or 1) + 0.5)) or 1
    local get, set = cfg.getValue or cfg.get, cfg.setValue or cfg.set
    local pxGet = get and function()
        local v = get()
        return v and gamePP.ToPixels(v)
    end
    local pxSet = set and function(v) return set(gamePP.FromPixels(v)) end
    if cfg.getValue then px.getValue = pxGet end
    if cfg.get then px.get = pxGet end
    if cfg.setValue then px.setValue = pxSet end
    if cfg.set then px.set = pxSet end
    return px
end

-------------------------------------------------------------------------------
--  WIDGET FACTORY
-------------------------------------------------------------------------------
local WidgetFactory = {}
EllesmereUI.Widgets = WidgetFactory
EllesmereUI._font  = EXPRESSWAY
EllesmereUI.CONTENT_PAD = CONTENT_PAD

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
    label:SetText(EllesmereUI.L(text))
    frame._label = label

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

    -- Restart the alternating row counter so each section begins fresh
    EllesmereUI._rowCounters[parent] = 0

    -- Search metadata: mark as section header and track it on the parent
    frame._isSectionHeader = true
    frame._sectionName = text
    -- Bilingual search: localized name, set only when it differs (nil on enUS).
    local _snLoc = EllesmereUI.L(text)
    if _snLoc ~= text then frame._sectionNameLoc = _snLoc end
    parent._currentSection = frame

    -- Global search index hook (see TagOptionRow); no-op without the optional EllesmereUI_GlobalSearch.lua. Trailing true marks this a SECTION so results render as "Section: Title Case" instead of an option row.
    if EllesmereUI._RegisterSearchEntry then
        local sel = EllesmereUI._buildingSelector
        EllesmereUI._RegisterSearchEntry(text, frame._sectionNameLoc, nil, EllesmereUI._buildingModule, EllesmereUI._buildingPage, text, sel and sel.setter, sel and sel.key, true)
    end

    return frame, 40
end

-- Fully wired dropdown control (button + bg + border + label + arrow + menu). Returns ddBtn, ddLbl so the caller can position it and register a refresh. Menu is built lazily on first click to cut initial allocation.
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

    local menu, refresh
    local function EnsureMenu()
        if menu then return end
        menu, _, refresh = BuildDropdownMenu(ddBtn, ddW, order, values, getValue, setValue, ddLbl, "regular", disabledValuesFn)
        ddBtn._ddMenu = menu
        ddBtn._ddRefresh = refresh
        -- keepClickHandler=true: the lazy OnClick below must survive, so after _invalidateMenu() the next click re-runs EnsureMenu instead of showing the orphaned old menu.
        WireDropdownScripts(ddBtn, ddLbl, ddBg, ddBrd, menu, refresh, RD_DD_COLOURS, true)
    end
    -- Public: invalidate the cached menu so the next click rebuilds from the current `order`/`values`. For dropdowns whose options change at runtime (e.g. one listing the spells currently on a CDM bar).
    ddBtn._invalidateMenu = function()
        if menu then
            menu:Hide()
            if menu.SetParent then pcall(menu.SetParent, menu, nil) end
            menu = nil
            refresh = nil
            ddBtn._ddMenu = nil
            ddBtn._ddRefresh = nil
        end
        -- Refresh the label too, in case the selection's label changed
        ddLbl:SetText(DDResolveLabel(values, order, getValue()))
    end

    -- Public: refresh only the displayed label from getValue, without rebuilding/invalidating the menu. Safe while the menu is wired/open, unlike _invalidateMenu (nils the cached menu, breaks the wired click). Use when an external change can alter what getValue returns (e.g. crosshair size showing "Custom" after a cog edit).
    ddBtn._refreshLabel = function()
        ddLbl:SetText(DDResolveLabel(values, order, getValue()))
    end

    -- Lightweight hover scripts until EnsureMenu() runs; WireDropdownScripts then replaces them with tooltip-aware versions.
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

-- Bound a row label between its left inset and the control so overflow ellipsizes instead of running into the control (or off the row, for checkboxes). When truncated, the full label surfaces on hover: folded into the description tooltip when there is one, alone otherwise. Returns the hover text (nil if none) and whether it truncated.
local function ClampRowLabel(label, rightFrame, rightPoint, gap, text, tooltip)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetMaxLines(1)
    label:SetPoint("RIGHT", rightFrame, rightPoint, -(gap or 12), 0)

    local truncated = false
    local nw, bw = label:GetStringWidth(), label:GetWidth()
    if not (issecretvalue and (issecretvalue(nw) or issecretvalue(bw))) then
        truncated = (nw or 0) > (bw or 0) + 0.5
    end

    if truncated and tooltip then
        -- Both parts pre-localized; the composite is not a catalog key, so ShowWidgetTooltip's L() leaves it untouched.
        return EllesmereUI.L(text) .. "\n" .. EllesmereUI.L(tooltip), true
    elseif truncated then
        return text, true
    end
    return tooltip, false
end

-- Label hover region (motion only, clicks pass through); created only when there is something to show.
local function AttachLabelHover(parent, label, hoverText)
    if not hoverText then return end
    local hit = CreateFrame("Frame", nil, parent)
    hit:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
    hit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
    hit:SetScript("OnEnter", function() ShowWidgetTooltip(label, hoverText) end)
    hit:SetScript("OnLeave", function() HideWidgetTooltip() end)
    hit:SetMouseClickEnabled(false)
    return hit
end

-- Deferred label clamp for row-half regions (DualRow / TripleRow). Half-region labels get their RIGHT edge
-- bounded against the leftmost inline item (region._lastInline) or the control itself; runs one frame deferred
-- because cogs/swatches/eyeballs attach AFTER the row builder returns. Overflowing labels then ellipsize instead
-- of running under the controls; full text surfaces on hover: folded into the label tooltip when the row has one
-- (hitFrames read region._labelTruncated via LabelTooltipText), else a plain reveal hover here.
local _labelClampQueue, _labelClampQueued = {}, false
local function _FlushLabelClamps()
    _labelClampQueued = false
    for i = 1, #_labelClampQueue do
        local region = _labelClampQueue[i]
        _labelClampQueue[i] = nil
        -- Hole-tolerant: an aborted earlier flush (a hard error mid-queue)
        -- can leave gaps; a nil entry must never take the whole pass down.
        local label = region and region._label
        local bound = region and (region._lastInline or region._control)
        if label and bound and label:IsShown() then
            local truncated = false
            local ll, bl, sw = label:GetLeft(), bound:GetLeft(), label:GetStringWidth()
            if ll and bl and sw and not (issecretvalue and (issecretvalue(ll) or issecretvalue(bl) or issecretvalue(sw))) then
                truncated = sw > (bl - 12 - ll) + 0.5
            end
            -- Bound ONLY when overflowing: a right anchor stretches the rect and displaces label-edge-anchored subtitles on short labels.
            if truncated then
                label:SetPoint("RIGHT", bound, "LEFT", -12, 0)
            end
            region._labelTruncated = truncated
            if truncated and not region._labelHasHit and not region._labelRevealHit then
                region._labelRevealHit = AttachLabelHover(region, label, label:GetText())
            end
        end
    end
end
local function QueueLabelClamp(region)
    if not region._label then return end
    _labelClampQueue[#_labelClampQueue + 1] = region
    if not _labelClampQueued then
        _labelClampQueued = true
        C_Timer.After(0, _FlushLabelClamps)
    end
end

-- Label hover tooltip: prepend full label text when truncated (composite isn't a catalog key, so L() leaves it alone).
local function LabelTooltipText(region, label, tip)
    if region._labelTruncated then
        return (label:GetText() or "") .. "\n" .. EllesmereUI.L(tip)
    end
    return tip
end

-- Toggle switch  (pill-shaped, teal when ON, dark when OFF, animated)
function WidgetFactory:Toggle(parent, text, yOffset, getValue, setValue, tooltip)
    local ROW_H = 50
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)

    RowBg(frame, parent)
    TagOptionRow(frame, parent, text, tooltip)    local label = MakeFont(frame, 14, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b)
    label:SetPoint("LEFT", frame, "LEFT", 20, 0)
    label:SetText(EllesmereUI.L(text))

    local toggle, _, tgSnap = BuildToggleControl(frame, frame:GetFrameLevel() + 1, getValue, setValue)
    toggle:SetPoint("RIGHT", frame, "RIGHT", -20, 0)

    AttachLabelHover(frame, label, (ClampRowLabel(label, toggle, "LEFT", 12, text, tooltip)))

    RegisterWidgetRefresh(tgSnap)

    -- Spec Overrides capture: see DualRow BuildHalf.
    frame._captureCfg = { type = "toggle", text = text, getValue = getValue, setValue = setValue }

    return frame, ROW_H
end

-- Slider with teal fill bar
function WidgetFactory:Slider(parent, text, yOffset, minVal, maxVal, step, getValue, setValue, tooltip, pixel)
    local ROW_H = 50
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    RowBg(frame, parent)
    TagOptionRow(frame, parent, text, tooltip)
    local label = MakeFont(frame, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
    PP.Point(label, "LEFT", frame, "LEFT", 20, 0)
    label:SetText(EllesmereUI.L(text))
    local scfg = PixelizeSliderCfg({ pixel = pixel, min = minVal, max = maxVal, step = step, getValue = getValue, setValue = setValue })
    local trackFrame, valBox = BuildSliderCore(frame, 320, 4, 14, 40, 26, 13, SL.INPUT_A, scfg.min, scfg.max, scfg.step, scfg.getValue, scfg.setValue)
    PP.Point(valBox, "RIGHT", frame, "RIGHT", -20, 0)
    PP.Point(trackFrame, "RIGHT", valBox, "LEFT", -16, 0)
    AttachLabelHover(frame, label, (ClampRowLabel(label, trackFrame, "LEFT", 12, text, tooltip)))
    -- Spec Overrides capture: see DualRow BuildHalf.
    frame._captureCfg = { type = "slider", text = text, min = minVal, max = maxVal, step = step, getValue = getValue, setValue = setValue }
    return frame, ROW_H
end

-- Dropdown  (optional 'order' is an array of keys for display order)
function WidgetFactory:Dropdown(parent, text, yOffset, values, getValue, setValue, order, tooltip)
    local ROW_H = 50
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    RowBg(frame, parent)
    TagOptionRow(frame, parent, text, tooltip)
    local label = MakeFont(frame, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
    label:SetAlpha(1)
    PP.Point(label, "LEFT", frame, "LEFT", 20, 0)
    label:SetText(EllesmereUI.L(text))
    local ddBtn, ddLbl = BuildDropdownControl(frame, 200, frame:GetFrameLevel() + 1, values, order, getValue, setValue)
    PP.Point(ddBtn, "RIGHT", frame, "RIGHT", -20, 0)
    local hoverText = ClampRowLabel(label, ddBtn, "LEFT", 12, text, tooltip)
    if hoverText then
        local hitFrame = CreateFrame("Frame", nil, frame)
        hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
        hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
        hitFrame:SetScript("OnEnter", function()
            if not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown()) then
                ShowWidgetTooltip(label, hoverText)
            end
        end)
        hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
        hitFrame:SetMouseClickEnabled(false)
        ddBtn._ttText = hoverText
    end
    RegisterWidgetRefresh(function()
        ddLbl:SetText(DDResolveLabel(values, order, getValue()))
    end)
    return frame, ROW_H
end

-- Checkbox (small square box with checkmark, label to the right)
function WidgetFactory:Checkbox(parent, text, yOffset, getValue, setValue, tooltip)
    do local _r = setValue; setValue = function(...) _r(...); EllesmereUI._settingsChanged = true end end
    local ROW_H = 36
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)

    RowBg(frame, parent)
    TagOptionRow(frame, parent, text, tooltip)

    local btn = CreateFrame("Button", nil, frame)
    PP.Size(btn, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    btn:SetAllPoints(frame)

    local box, check, boxBorder, cbApply = BuildCheckboxControl(btn, frame:GetFrameLevel() + 1)
    PP.Point(box, "LEFT", btn, "LEFT", 20, 0)

    local label = MakeFont(btn, 14, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b)
    label:SetPoint("LEFT", box, "RIGHT", 10, 0)
    label:SetText(EllesmereUI.L(text))

    AttachLabelHover(btn, label, (ClampRowLabel(label, btn, "RIGHT", 20, text, tooltip)))

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
--  Color Picker recent-colors & favorites (file-scope, shared per session)
-------------------------------------------------------------------------------
local PICKER_MAX_SWATCHES = 10

local function GetPickerDB()
    if not EllesmereUIDB then return {} end
    if not EllesmereUIDB.colorPicker then EllesmereUIDB.colorPicker = {} end
    return EllesmereUIDB.colorPicker
end
local function GetRecentColorsDB()
    local db = GetPickerDB(); if not db.recentColors then db.recentColors = {} end; return db.recentColors
end
local function GetFavoritesDB()
    local db = GetPickerDB(); if not db.favorites then db.favorites = {} end; return db.favorites
end
local function ColorKey(r, g, b)
    return string.format("%d-%d-%d", math.floor(r*255+.5), math.floor(g*255+.5), math.floor(b*255+.5))
end
local function RecordRecentColor(r, g, b)
    local db = GetRecentColorsDB(); local key = ColorKey(r, g, b)
    for i = #db, 1, -1 do
        if ColorKey(db[i][1], db[i][2], db[i][3]) == key then table.remove(db, i) end
    end
    table.insert(db, 1, { r, g, b })
    while #db > PICKER_MAX_SWATCHES do table.remove(db) end
end
local function IsFavorite(r, g, b)
    local key = ColorKey(r, g, b)
    for _, c in ipairs(GetFavoritesDB()) do
        if ColorKey(c[1], c[2], c[3]) == key then return true end
    end
    return false
end
local function ToggleFavorite(r, g, b)
    local db = GetFavoritesDB(); local key = ColorKey(r, g, b)
    for i = #db, 1, -1 do
        if ColorKey(db[i][1], db[i][2], db[i][3]) == key then table.remove(db, i); return false end
    end
    table.insert(db, 1, { r, g, b })
    while #db > PICKER_MAX_SWATCHES do table.remove(db) end
    return true
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
    local POPUP_H = PAD_TOP + 28 + SV_SIZE + 80 + PAD
    local BASE_W = PAD + SV_SIZE + BAR_GAP + BAR_W + BAR_GAP + BAR_W + RIGHT_GAP + RIGHT_W + PAD_RIGHT
    local BASE_W_NO_ALPHA = PAD + SV_SIZE + BAR_GAP + BAR_W + RIGHT_GAP + RIGHT_W + PAD_RIGHT
    -- Extra RIGHT COLUMN height when the picker has an alpha slider, so OK/Cancel clear the Opacity input inserted below Hex#. Popup height and the left-side favorites/recent rows are NOT affected.
    local OPACITY_BLOCK_H = 50

    local currentH, currentS, currentV, currentA = 0, 1, 1, 1
    local prevR, prevG, prevB, prevA = 1, 1, 1, 1
    local swatchFunc, opacityFunc, cancelFunc
    local hasOpacity = false
    local updating = false

    local popup = CreateFrame("Frame", "EllesmereUIColorPicker", UIParent)
    popup:SetSize(BASE_W, POPUP_H)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(400)
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:Hide()

    -- Click-off close via GLOBAL_MOUSE_DOWN (non-blocking: preserves hover/click on every other frame)
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
        -- Defer registration one frame so the mouse-down that opened the popup doesn't immediately trigger click-outside-to-close.
        C_Timer.After(0, function()
            if popup:IsShown() then
                clickOffFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
                clickOffFrame:Show()
            end
        end)
    end)
    popup:HookScript("OnHide", function()
        clickOffFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        clickOffFrame:Hide()
    end)

    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.08, 0.10, 1)

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
    titleLbl:SetAlpha(0.5); titleLbl:SetPoint("CENTER", 0, -10); titleLbl:SetText(EllesmereUI.L("Color Picker"))

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

    -- Getters kept Blizzard-API-compatible
    local outR, outG, outB, outA = 1, 1, 1, 1
    function popup:GetColorRGB() return outR, outG, outB end
    function popup:GetColorAlpha() return outA end

    -- Forward declarations
    local UpdateSVPadHue, UpdateSVCrosshair, UpdateHueIndicator
    local UpdateAlphaBar, UpdateHexInput, UpdateOpacityInput
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
        if UpdateOpacityInput then UpdateOpacityInput(currentA) end
        if newPreviewTex then newPreviewTex:SetColorTexture(r, g, b, currentA) end
        updating = false
    end

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

    local alphaBar = CreateFrame("Frame", nil, popup)
    alphaBar:SetSize(BAR_W, SV_SIZE)
    alphaBar:SetPoint("TOPLEFT", hueBar, "TOPRIGHT", BAR_GAP, 0)
    alphaBar:EnableMouse(true)

    local CK = 10  -- coarse checkerboard cell: 2 cols x 20 rows = 40 textures
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

    -- Reused CreateColor objects: no per-frame allocation during drag
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

    local nl = MakeFont(rightCol, 10, nil, 1,1,1); nl:SetAlpha(TEXT_DIM_A)
    nl:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0); nl:SetText(EllesmereUI.L("New"))

    newPreviewTex = rightCol:CreateTexture(nil, "ARTWORK")
    newPreviewTex:SetSize(RIGHT_W, 26); newPreviewTex:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -14)
    newPreviewTex:SetColorTexture(1,1,1,1)

    -- Prev preview sits directly below New
    local prevPrev = rightCol:CreateTexture(nil, "ARTWORK")
    prevPrev:SetSize(RIGHT_W, 26); prevPrev:SetPoint("TOPLEFT", newPreviewTex, "BOTTOMLEFT", 0, -4)
    prevPrev:SetColorTexture(1,1,1,1)
    prevPreviewTex = prevPrev

    -- Clicking the prev swatch restores the previous color
    local prevBtn = CreateFrame("Button", nil, rightCol)
    prevBtn:SetAllPoints(prevPrev)
    prevBtn:SetFrameLevel(rightCol:GetFrameLevel() + 5)
    prevBtn:SetScript("OnClick", function()
        currentH, currentS, currentV = RGBtoHSV(prevR, prevG, prevB)
        currentA = hasOpacity and prevA or 1
        UpdateAllControls(); FireCallbacks()
    end)

    local pl = MakeFont(rightCol, 10, nil, 1,1,1); pl:SetAlpha(TEXT_DIM_A)
    pl:SetPoint("TOPLEFT", prevPrev, "BOTTOMLEFT", 0, -6); pl:SetText(EllesmereUI.L("Prev"))

    local hexLbl = MakeFont(rightCol, 10, nil, 1,1,1); hexLbl:SetAlpha(TEXT_DIM_A)
    hexLbl:SetPoint("TOPLEFT", pl, "BOTTOMLEFT", 0, -21); hexLbl:SetText(EllesmereUI.L("Hex#"))

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
    hexBox:SetScript("OnEnterPressed", function() CommitHex(); hexBox:ClearFocus() end)
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

    -- Opacity input: shown only with an alpha slider, below Hex# and styled identically. Integer percentage, 0-100.
    local opacityLbl = MakeFont(rightCol, 10, nil, 1,1,1); opacityLbl:SetAlpha(TEXT_DIM_A)
    opacityLbl:SetPoint("TOPLEFT", hexBox, "BOTTOMLEFT", 0, -10); opacityLbl:SetText(EllesmereUI.L("Opacity"))

    local opacityBox = CreateFrame("EditBox", nil, rightCol)
    opacityBox:SetSize(RIGHT_W, 24); opacityBox:SetPoint("TOPLEFT", opacityLbl, "BOTTOMLEFT", 0, -4)
    opacityBox:SetFont(EXPRESSWAY, 10, ""); opacityBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
    opacityBox:SetMaxLetters(3); opacityBox:SetAutoFocus(false); opacityBox:EnableMouse(true)
    opacityBox:SetNumeric(true); opacityBox:SetJustifyH("CENTER")
    local obg = opacityBox:CreateTexture(nil, "BACKGROUND")
    obg:SetAllPoints(); obg:SetColorTexture(0.22, 0.24, 0.28, 0.5)
    MakeBorder(opacityBox, 1, 1, 1, 0.04, PP)

    local lastOpacityPct = -1
    UpdateOpacityInput = function(a)
        if opacityBox:HasFocus() then return end
        local pct = math.floor((a or 1) * 100 + 0.5)
        if pct == lastOpacityPct then return end
        lastOpacityPct = pct
        opacityBox:SetText(tostring(pct))
    end
    -- Parse the box and apply as alpha. commit=true snaps back to the live value when unparseable (Enter/focus loss).
    local function ApplyOpacityText(commit)
        local n = tonumber(opacityBox:GetText())
        if n then
            n = math.max(0, math.min(100, math.floor(n + 0.5)))
            currentA = n / 100
            lastOpacityPct = n
            UpdateAllControls(); FireCallbacks()
            return true
        elseif commit then
            opacityBox:SetText(tostring(math.floor(currentA * 100 + 0.5)))
        end
        return false
    end
    local opacityEscaping = false
    opacityBox:SetScript("OnEnterPressed", function() ApplyOpacityText(true); opacityBox:ClearFocus() end)
    opacityBox:SetScript("OnEscapePressed", function()
        opacityEscaping = true
        opacityBox:SetText(tostring(math.floor(currentA * 100 + 0.5)))
        opacityBox:ClearFocus()
        opacityEscaping = false
        if cancelFunc then cancelFunc() end
        popup:Hide()
    end)
    opacityBox:SetScript("OnEditFocusLost", function() if not opacityEscaping then ApplyOpacityText(true) end end)
    opacityBox:SetScript("OnEditFocusGained", function() opacityBox:HighlightText() end)
    opacityBox:SetScript("OnTextChanged", function(self, userInput)
        if not self:HasFocus() then return end
        ApplyOpacityText(false)
    end)
    opacityLbl:Hide(); opacityBox:Hide()

    -- OK button, bottom of the right column (reset/reload button style)
    local okBtn = CreateFrame("Button", nil, rightCol)
    okBtn:SetSize(RIGHT_W, 21)
    okBtn:SetPoint("BOTTOMLEFT", rightCol, "BOTTOMLEFT", 0, 0)
    okBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    local _confirmed = false
    MakeStyledButton(okBtn, "OK", 10, RB_COLOURS, function()
        RecordRecentColor(HSVtoRGB(currentH, currentS, currentV))
        -- Fire on OK even when nothing changed, to confirm the selection
        FireCallbacks()
        _confirmed = true; popup:Hide()
    end)

    -- Cancel text above OK button
    local cancelBtn = CreateFrame("Button", nil, rightCol)
    cancelBtn:SetSize(RIGHT_W, 14)
    cancelBtn:SetPoint("BOTTOM", okBtn, "TOP", 0, 5)
    cancelBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY")
    cancelText:SetFont(EXPRESSWAY, 10, "")
    cancelText:SetPoint("CENTER")
    cancelText:SetText(EllesmereUI.L("cancel"))
    cancelText:SetTextColor(1, 1, 1, 0.4)
    cancelBtn:SetScript("OnEnter", function() cancelText:SetTextColor(1, 1, 1, 0.7) end)
    cancelBtn:SetScript("OnLeave", function() cancelText:SetTextColor(1, 1, 1, 0.4) end)
    cancelBtn:SetScript("OnClick", function()
        _confirmed = false
        popup:Hide()
    end)

    ---------------------------------------------------------------------------
    --  Favorites & Recent Colors (below HSV picker)
    ---------------------------------------------------------------------------
    local RefreshSwatchRows
    local SWATCH_SZ      = 19
    local SWATCH_SPACING = 4

    local function MakeSwatchBtn(parent, isFavorites)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(SWATCH_SZ, SWATCH_SZ)
        btn:SetFrameLevel(parent:GetFrameLevel() + 2)
        local tex = btn:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints(); btn._tex = tex
        btn:SetScript("OnEnter", function(self)
            local c = self._color; if not c then return end
            local hex = string.format("%02X%02X%02X",
                math.floor(c[1]*255+.5), math.floor(c[2]*255+.5), math.floor(c[3]*255+.5))
            local hint = isFavorites and EllesmereUI.L("Right-click: remove favorite")
                                      or  EllesmereUI.L("Right-click: favorite")
            -- Anchor on the hovered swatch so the tooltip sits directly above it (default placement is BOTTOM -> anchor TOP).
            ShowWidgetTooltip(self, "|cff"..hex.."#|r"..hex.."\n"..hint)
        end)
        btn:SetScript("OnLeave", function() HideWidgetTooltip() end)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(self, mouseButton)
            local c = self._color; if not c then return end
            if mouseButton == "RightButton" then
                if isFavorites or not IsFavorite(c[1], c[2], c[3]) then
                    ToggleFavorite(c[1], c[2], c[3])
                end
                RefreshSwatchRows()
            else
                currentH, currentS, currentV = RGBtoHSV(c[1], c[2], c[3])
                UpdateAllControls(); FireCallbacks()
            end
        end)
        btn:Hide()
        return btn
    end

    local favLbl = MakeFont(popup, 10, nil, 1,1,1); favLbl:SetAlpha(TEXT_DIM_A)
    favLbl:SetPoint("TOPLEFT", svPad, "BOTTOMLEFT", 0, -10)
    favLbl:SetText(EllesmereUI.L("Favorites"))

    local favRow = CreateFrame("Frame", nil, popup)
    favRow:SetSize(BASE_W - PAD - PAD_RIGHT, SWATCH_SZ)
    favRow:SetPoint("TOPLEFT", favLbl, "BOTTOMLEFT", 0, -3)
    favRow._label = favLbl; favRow._isFavorites = true

    local rcLbl = MakeFont(popup, 10, nil, 1,1,1); rcLbl:SetAlpha(TEXT_DIM_A)
    rcLbl:SetPoint("TOPLEFT", favRow, "BOTTOMLEFT", 0, -8)
    rcLbl:SetText(EllesmereUI.L("Recent Colors"))

    local rcRow = CreateFrame("Frame", nil, popup)
    rcRow:SetSize(BASE_W - PAD - PAD_RIGHT, SWATCH_SZ)
    rcRow:SetPoint("TOPLEFT", rcLbl, "BOTTOMLEFT", 0, -3)
    rcRow._label = rcLbl; rcRow._isFavorites = false

    local favSwatches, rcSwatches = {}, {}

    local function PopulateSwatchRow(swatchPool, row, data)
        local count = math.min(#data, PICKER_MAX_SWATCHES)
        for i = 1, math.max(count, #swatchPool) do
            local btn = swatchPool[i]
            if not btn then btn = MakeSwatchBtn(row, row._isFavorites); swatchPool[i] = btn end
            if i <= count then
                btn._color = data[i]
                btn._tex:SetColorTexture(data[i][1], data[i][2], data[i][3], 1)
                btn:Show(); btn:ClearAllPoints()
                if i == 1 then btn:SetPoint("LEFT", row, "LEFT", 0, 0)
                else btn:SetPoint("LEFT", swatchPool[i-1], "RIGHT", SWATCH_SPACING, 0) end
            else
                btn:Hide()
            end
        end
    end

    RefreshSwatchRows = function()
        PopulateSwatchRow(favSwatches, favRow, GetFavoritesDB())
        PopulateSwatchRow(rcSwatches,  rcRow,  GetRecentColorsDB())
    end

    popup:SetScript("OnHide", function()
        EllesmereUI._colorPickerOpen = false
        if not _confirmed and cancelFunc then cancelFunc() end
        _confirmed = false
        svDragging = false; hueDragging = false; alphaDragging = false
        svPad:SetScript("OnUpdate", nil)
        hueBar:SetScript("OnUpdate", nil)
        alphaBar:SetScript("OnUpdate", nil)
        local checks = EllesmereUI._deferredDriftChecks
        EllesmereUI._deferredDriftChecks = nil
        if checks then for fn in pairs(checks) do fn() end end
        -- Re-evaluate widget state (sync icons, disabled overlays) now the picked color is committed. Fast path: no rebuild.
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end)
    EllesmereUI.RegisterEscapeClose(popup)

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
        -- Reposition the right column by alpha-bar visibility. With an alpha slider ONLY the right column grows taller, so OK/Cancel clear the Opacity input below Hex#. Favorites/recent rows sit on the LEFT, clear of that column, so they and the popup height stay put.
        rightCol:ClearAllPoints()
        if hasOpacity then
            alphaBar:Show()
            popup:SetWidth(BASE_W)
            rightCol:SetPoint("TOPLEFT", alphaBar, "TOPRIGHT", RIGHT_GAP, 0)
            rightCol:SetHeight(SV_SIZE + OPACITY_BLOCK_H)
            opacityLbl:Show(); opacityBox:Show()
        else
            alphaBar:Hide()
            popup:SetWidth(BASE_W_NO_ALPHA)
            rightCol:SetPoint("TOPLEFT", hueBar, "TOPRIGHT", RIGHT_GAP, 0)
            rightCol:SetHeight(SV_SIZE)
            opacityLbl:Hide(); opacityBox:Hide()
        end
        popup:ClearAllPoints()
        -- Horizontally centered on the cursor; vertical placement flips if needed
        local cx, cy = GetCursorPosition()
        local scale = popup:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local pw = popup:GetWidth()
        local ph = popup:GetHeight()
        local x = cx - pw * 0.5
        local y = cy - 30  -- popup top 30px below the cursor
        -- Flip above the cursor if that would drop below the options window
        local mainFrame = EllesmereUI._mainFrame
        if mainFrame and mainFrame:IsShown() then
            local mBot = mainFrame:GetBottom()
            if mBot and (y - ph) < mBot then
                y = cy + 30 + ph  -- popup bottom 30px above the cursor
            end
        end
        popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        EllesmereUI._colorPickerOpen = true
        RefreshSwatchRows()
        popup:Show(); UpdateAllControls()
    end

    -- Spec Overrides auto-capture: color picker edits attribute to the slot whose swatch opened it.
    popup._euiOptionsPopup = true
    EllesmereUI._colorPickerPopup = popup
    return popup
end

function EllesmereUI:ShowColorPicker(info, anchorFrame)
    local popup = self._colorPickerPopup or BuildColorPickerPopup()
    popup:Open(info, anchorFrame)
end

-- Shared color swatch: border + fill + UpdateSwatch + OnClick. Returns swatch (Button), UpdateSwatch (function), caller positions it. Border textures are deferred until first show to keep page builds light.
local function BuildColorSwatch(parentFrame, baseLevel, getValue, setValue, hasAlpha, overrideSize)
    -- Spec Overrides auto-capture (see BuildToggleControl): fires for direct swatch writes and every color-picker change routed through it.
    do
        local _s = setValue
        setValue = function(...)
            _s(...)
            if EllesmereUI._NotifySettingWrite then EllesmereUI._NotifySettingWrite(parentFrame) end
        end
    end
    do local _r = setValue; setValue = function(...) _r(...); EllesmereUI._settingsChanged = true end end
    local SWATCH_SZ = overrideSize or 24
    local swatch = CreateFrame("Button", nil, parentFrame)
    PP.Size(swatch, SWATCH_SZ, SWATCH_SZ)
    swatch:SetFrameLevel(baseLevel)

    -- Color fill: 1 texture, always created immediately
    local sFill = swatch:CreateTexture(nil, "ARTWORK")
    sFill:SetAllPoints()

    local borderBuilt = false

    local function BuildBorder()
        if borderBuilt then return end
        borderBuilt = true
        local T = CS.BRD_THICK

        local wt = swatch:CreateTexture(nil, "BORDER")
        wt:SetColorTexture(1, 1, 1, 1)
        wt:SetPoint("BOTTOMLEFT", swatch, "TOPLEFT", -T, 0); wt:SetPoint("BOTTOMRIGHT", swatch, "TOPRIGHT", T, 0); PP.Height(wt, T)
        local wb = swatch:CreateTexture(nil, "BORDER")
        wb:SetColorTexture(1, 1, 1, 1)
        wb:SetPoint("TOPLEFT", swatch, "BOTTOMLEFT", -T, 0); wb:SetPoint("TOPRIGHT", swatch, "BOTTOMRIGHT", T, 0); PP.Height(wb, T)
        local wl = swatch:CreateTexture(nil, "BORDER")
        wl:SetColorTexture(1, 1, 1, 1)
        wl:SetPoint("TOPLEFT", swatch, "TOPLEFT", -T, 0); wl:SetPoint("BOTTOMLEFT", swatch, "BOTTOMLEFT", -T, 0); PP.Width(wl, T)
        local wr = swatch:CreateTexture(nil, "BORDER")
        wr:SetColorTexture(1, 1, 1, 1)
        wr:SetPoint("TOPRIGHT", swatch, "TOPRIGHT", T, 0); wr:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", T, 0); PP.Width(wr, T)
    end

    local function UpdateSwatch()
        local r, g, b, a = getValue()
        sFill:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    end

    -- Initial fill color (no border needed yet)
    do
        local r, g, b, a = getValue()
        sFill:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    end

    -- Border builds lazily on first show, or now if already visible
    swatch:HookScript("OnShow", function()
        if not borderBuilt then BuildBorder() end
    end)
    if swatch:IsVisible() then BuildBorder() end

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

    -- Spec Overrides capture: an inline swatch belongs to its hosting slot (options files pass the DualRow half-region as parent), so it joins that slot's capture group. AddCaptureAccessor dedupes by getValue identity, so factory-built swatches whose accessors are stashed separately never double.
    if EllesmereUI.AddCaptureAccessor and not parentFrame._noCapture then
        EllesmereUI.AddCaptureAccessor(parentFrame, {
            type = "colorpicker", hasAlpha = hasAlpha,
            getValue = getValue, setValue = setValue,
        })
    end

    return swatch, UpdateSwatch
end

-- default/custom/class color swatch trio; callers track a mode string. opts:
--   getMode()           -> "default" | "custom" | "class"
--   setMode(mode)       -> store the new mode
--   getCustomRGB()      -> r, g, b of the custom color
--   setCustomRGB(r,g,b) -> store the picked color
--   onChange()          -> optional, called after any swatch click
--   disabled()          -> optional, true to disable all swatches
--   disabledAlpha       -> optional alpha while disabled (default 0.3)
--   hasAlpha, overrideSize -> forwarded to BuildColorSwatch
-- Returns customSwatch, defaultSwatch, classSwatch, Update.
local DEFAULT_UNTINTED_R, DEFAULT_UNTINTED_G, DEFAULT_UNTINTED_B = 1.0, 0.788, 0.137
local function BuildTrioColorSwatch(parentFrame, baseLevel, opts)
    local customSwatch, updateCustom = BuildColorSwatch(parentFrame, baseLevel,
        function()
            local r, g, b = opts.getCustomRGB()
            return r, g, b, 1
        end,
        function(r, g, b)
            opts.setCustomRGB(r, g, b)
            opts.setMode("custom")
            if opts.onChange then opts.onChange() end
        end,
        opts.hasAlpha, opts.overrideSize)
    customSwatch:HookScript("OnEnter", function()
        ShowWidgetTooltip(customSwatch, "Custom Color")
    end)
    customSwatch:HookScript("OnLeave", function() HideWidgetTooltip() end)
    -- Suite-wide multiSwatch convention: clicking an INACTIVE custom swatch only selects custom mode; the picker opens on a second click while custom is already active.
    customSwatch._eabOrigClick = customSwatch:GetScript("OnClick")
    customSwatch:SetScript("OnClick", function(self)
        if opts.getMode() ~= "custom" then
            opts.setMode("custom")
            if opts.onChange then opts.onChange() end
            return
        end
        if self._eabOrigClick then self._eabOrigClick(self) end
    end)

    local defaultSwatch = BuildColorSwatch(parentFrame, baseLevel,
        function() return DEFAULT_UNTINTED_R, DEFAULT_UNTINTED_G, DEFAULT_UNTINTED_B, 1 end,
        function() end,
        opts.hasAlpha, opts.overrideSize)
    defaultSwatch:SetScript("OnClick", function()
        opts.setMode("default")
        if opts.onChange then opts.onChange() end
    end)
    defaultSwatch:SetScript("OnEnter", function()
        ShowWidgetTooltip(defaultSwatch, "Default")
    end)
    defaultSwatch:SetScript("OnLeave", function() HideWidgetTooltip() end)

    local classSwatch
    if opts.hasClassColor then
        classSwatch = BuildColorSwatch(parentFrame, baseLevel,
            function()
                local cc = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                return cc.r, cc.g, cc.b, 1
            end,
            function() end,
            opts.hasAlpha, opts.overrideSize)
        classSwatch:SetScript("OnClick", function()
            opts.setMode("class")
            if opts.onChange then opts.onChange() end
        end)
        classSwatch:SetScript("OnEnter", function()
            ShowWidgetTooltip(classSwatch, "Class Colored")
        end)
        classSwatch:SetScript("OnLeave", function() HideWidgetTooltip() end)
    end

    local function Update()
        local disabled = opts.disabled and opts.disabled()
        local mode = opts.getMode()
        if disabled then
            local a = opts.disabledAlpha or 0.3
            customSwatch:SetAlpha(a)
            defaultSwatch:SetAlpha(a)
            if classSwatch then classSwatch:SetAlpha(a) end
        else
            customSwatch:SetAlpha(mode == "custom" and 1 or 0.3)
            defaultSwatch:SetAlpha(mode == "default" and 1 or 0.3)
            if classSwatch then classSwatch:SetAlpha(mode == "class" and 1 or 0.3) end
        end
        updateCustom()
    end
    Update()
    RegisterWidgetRefresh(Update)

    return customSwatch, defaultSwatch, classSwatch, Update
end

-- Color Picker row (swatch that opens the EllesmereUI picker popup)
function WidgetFactory:ColorPicker(parent, text, yOffset, getValue, setValue, hasAlpha)
    local ROW_H = 50
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)

    RowBg(frame, parent)
    TagOptionRow(frame, parent, text)

    local label = MakeFont(frame, 14, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b)
    PP.Point(label, "LEFT", frame, "LEFT", 20, 0)
    label:SetText(EllesmereUI.L(text))

    local swatch, UpdateSwatch = BuildColorSwatch(frame, frame:GetFrameLevel() + 1, getValue, setValue, hasAlpha)
    PP.Point(swatch, "RIGHT", frame, "RIGHT", -20, 0)

    -- Public refresh so external code can update the swatch after bar changes
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

-- Spec Overrides capture: append an extra accessor to a region/row's capture config so inline extras (swatches, cog fields, inline toggles) built outside the factory capture TOGETHER with the slot's main setting as one override. acc = { type, text, getValue, setValue, step/values/order/hasAlpha }.
function EllesmereUI.AddCaptureAccessor(region, acc)
    if not (region and acc and acc.getValue and acc.setValue) then return end
    local cc = region._captureCfg
    -- Dedupe by getValue identity: factory paths stash some controls themselves (colorpicker halves, multiSwatch rows) and BuildColorSwatch self-registers, so the same accessor must never join twice.
    if cc then
        if cc.getValue == acc.getValue then return end
        if cc.accessors then
            for _, a in ipairs(cc.accessors) do
                if a.getValue == acc.getValue then return end
            end
        end
    end
    if not cc then
        region._captureCfg = { type = "multi", text = acc.text, accessors = { acc } }
    elseif cc.accessors then
        cc.accessors[#cc.accessors + 1] = acc
    else
        -- Promote a single-accessor widget cfg to a grouped slot cfg.
        region._captureCfg = { type = "multi", text = cc.text, accessors = { cc, acc } }
    end
end

-- DualRow: two widgets side by side on one full-width row, 1px center divider.
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
    -- Search metadata: combined label on the frame (inline page search), one global-index entry per slot.
    local dualLabel = (leftCfg and leftCfg.text or "")
    if rightCfg and rightCfg.text then dualLabel = dualLabel .. " " .. rightCfg.text end
    TagOptionRow(frame, parent, dualLabel, nil, true)
    IndexSlotForSearch(parent, leftCfg and leftCfg.text, leftCfg and leftCfg.tooltip)
    IndexSlotForSearch(parent, rightCfg and rightCfg.text, rightCfg and rightCfg.tooltip)

    -- Half regions: invisible, anchoring only
    local fullWidth = not rightCfg
    local halfW = math.floor(totalW / 2)
    local leftRegion = CreateFrame("Frame", nil, frame)
    leftRegion:SetSize(fullWidth and totalW or halfW, ROW_H)
    leftRegion:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    local rightRegion = CreateFrame("Frame", nil, frame)
    rightRegion:SetSize(halfW, ROW_H)
    rightRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local function BuildHalf(region, cfg)
        if not cfg then return end
        local t = cfg.type
        -- Spec Overrides capture: expose the widget config so the capture overlay can identify settings. A slot is ONE setting: multiSwatch slots capture all their swatches together, inline extras join via AddCaptureAccessor. cfg.noCapture opts a widget out (used by the Spec Overrides page's own mirrored editors).
        if cfg.noCapture then
            region._captureCfg = nil
            region._noCapture = true
        elseif cfg.getValue and cfg.setValue then
            region._captureCfg = cfg
        elseif t == "multiSwatch" and cfg.swatches then
            local accs = {}
            for i = 1, #cfg.swatches do
                local sc = cfg.swatches[i]
                if sc.getValue and sc.setValue then
                    accs[#accs + 1] = { type = "colorpicker", text = sc.tooltip or cfg.text,
                        hasAlpha = sc.hasAlpha, getValue = sc.getValue, setValue = sc.setValue }
                end
            end
            if #accs > 0 then
                region._captureCfg = { type = "multi", text = cfg.text, accessors = accs }
            end
        end
        -- Empty half-space placeholder for dual/third rows.
        if t == "spacer" then
            region._control = nil
            return
        end
        -- Label (every type has one). Single-line so the right-edge clamp (QueueLabelClamp) ellipsizes instead of wrapping.
        local label = MakeFont(region, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        PP.Point(label, "LEFT", region, "LEFT", SIDE_PAD, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetMaxLines(1)
        label:SetText(EllesmereUI.L(cfg.text or ""))
        region._label = label
        region._labelHasHit = (cfg.tooltip or cfg.disabledTooltip) and true or false

        -- Label tooltip. For dropdowns the hitFrame is created after the dropdown button so it can check whether the menu is open.
        if (cfg.tooltip or cfg.disabledTooltip) and t ~= "dropdown" then
            local ttOpts = cfg.tooltipOpts
            local hitFrame = CreateFrame("Frame", nil, region)
            hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
            hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
            hitFrame:SetFrameLevel(region:GetFrameLevel() + 10)
            hitFrame:SetScript("OnEnter", function()
                if cfg.disabled and cfg.disabled() and cfg.disabledTooltip then
                    local tt = ResolveDisabledTip(cfg)
                    if tt then ShowWidgetTooltip(label, tt) end
                elseif cfg.tooltip then
                    ShowWidgetTooltip(label, LabelTooltipText(region, label, cfg.tooltip), ttOpts)
                elseif region._labelTruncated then
                    -- Truncated label whose hit exists only for the disabled tooltip: reveal the full text while enabled.
                    ShowWidgetTooltip(label, label:GetText())
                end
            end)
            hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
            -- Clicks pass through by default so controls stay interactive; intercepted while disabled to block interaction.
            hitFrame:SetMouseClickEnabled(false)
            if cfg.disabled and cfg.disabledTooltip then
                local function UpdateHitMouse()
                    hitFrame:SetMouseClickEnabled(cfg.disabled() and true or false)
                end
                RegisterWidgetRefresh(UpdateHitMouse)
                UpdateHitMouse()
            end
        end

        -- cfg.disabled: optional fn returning bool; when true the label dims and the control goes non-interactive.
        local disabledOverlay  -- optional dark overlay to gray out the whole half
        local controlFrame     -- the clickable control (dropdown btn, toggle, etc.)
        local controlAnchor    -- main control frame for inline element anchoring

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
            local defaultTrackW = isRussian and 120 or 160
            local scfg = PixelizeSliderCfg(cfg)
            local trackFrame, valBox, _, slThumb = BuildSliderCore(region, cfg.trackWidth or defaultTrackW, 4, 14, 40, 26, 13, SL.INPUT_A,
                scfg.min, scfg.max, scfg.step, scfg.getValue, scfg.setValue, true, cfg.snapPoints)
            PP.Point(valBox, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            PP.Point(trackFrame, "RIGHT", valBox, "LEFT", -12, 0)
            controlFrame = nil  -- slider owns its disabled state; keep the generic handler off its mouse
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
            -- Bridge itemDisabled/itemDisabledTooltip into disabledValuesFn
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
            -- Tooltip config on the button: WireDropdownScripts and the pre-menu hover scripts read ddBtn._ttText/_ttOpts.
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
                        local tt = ResolveDisabledTip(cfg)
                        if tt then ShowWidgetTooltip(label, tt) end
                    elseif cfg.tooltip and not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown()) then
                        ShowWidgetTooltip(label, LabelTooltipText(region, label, cfg.tooltip), ttOpts)
                    elseif region._labelTruncated and not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown()) then
                        ShowWidgetTooltip(label, label:GetText())
                    end
                end)
                hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
                hitFrame:SetMouseClickEnabled(false)
                -- Intercept clicks over the label area while disabled
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
            -- Half-row button: label hidden, the button IS the content
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

        elseif t == "labeledButton" then
            -- Standard left label, button anchored right
            local btn = CreateFrame("Button", nil, region)
            PP.Size(btn, cfg.width or 180, 32)
            PP.Point(btn, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            btn:SetFrameLevel(frame:GetFrameLevel() + 2)
            MakeStyledButton(btn, cfg.buttonText or cfg.text or "", 13, RB_COLOURS, cfg.onClick)
            controlFrame = btn
            controlAnchor = btn
            RegisterWidgetRefresh(function() ApplyDisabledState() end)
            ApplyDisabledState()

        elseif t == "multiSwatch" then
            -- Label + N swatches laid out right-to-left from the right edge
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
                -- Optional click override (e.g. class color toggle)
                if sc.onClick then
                    swatch._eabOrigClick = swatch:GetScript("OnClick")
                    swatch:SetScript("OnClick", sc.onClick)
                end
                -- Effective disabled = row-level cfg.disabled OR per-swatch sc.disabled
                local function SwatchEffectiveDisabled()
                    if cfg.disabled and cfg.disabled() then return true end
                    if sc.disabled ~= nil then
                        if type(sc.disabled) == "function" then return sc.disabled() end
                        return sc.disabled
                    end
                    return false
                end
                -- Overlay greys out and blocks the swatch while disabled
                if cfg.disabled or sc.disabled then
                    local swatchBlock = CreateFrame("Frame", nil, swatch)
                    swatchBlock:SetAllPoints()
                    swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
                    swatchBlock:EnableMouse(true)
                    swatchBlock:SetScript("OnEnter", function()
                        local src = (sc.disabledTooltip ~= nil) and sc or cfg
                        local tip = ResolveDisabledTip(src)
                        if tip then ShowWidgetTooltip(swatch, tip) end
                    end)
                    swatchBlock:SetScript("OnLeave", function() HideWidgetTooltip() end)
                    local function UpdateSwatchDisabled()
                        if SwatchEffectiveDisabled() then
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
                if sc.tooltip then
                    swatch:HookScript("OnEnter", function()
                        ShowWidgetTooltip(swatch, sc.tooltip)
                    end)
                    swatch:HookScript("OnLeave", function()
                        HideWidgetTooltip()
                    end)
                end
                -- Per-swatch alpha refresh (dim inactive, bright active)
                if sc.refreshAlpha then
                    local _sw, _ra = swatch, sc.refreshAlpha
                    local function UpdateAlpha()
                        -- The disabled handler owns alpha while disabled
                        if SwatchEffectiveDisabled() then return end
                        _sw:SetAlpha(_ra())
                    end
                    UpdateAlpha()
                    RegisterWidgetRefresh(UpdateAlpha)
                end
                RegisterWidgetRefresh(function() updateSwatch() end)
            end
            controlAnchor = leftmostSwatch
            RegisterWidgetRefresh(function() ApplyDisabledState() end)
            ApplyDisabledState()

        elseif t == "input" then
            -- Free-text entry box, right-anchored. getValue returns the display
            -- string; setValue receives raw text and parses/validates it. Commits
            -- on Enter and focus loss; Escape reverts.
            -- cfg.inputStyle == "popup" restyles it like the ShowInputPopup field
            -- (near-black fill, subtle border, left-justified) and supports
            -- cfg.placeholder ghost text while empty.
            local isPopupStyle = cfg.inputStyle == "popup"
            local boxW = cfg.inputWidth or 64
            local box = CreateFrame("EditBox", nil, region)
            box:SetSize(boxW, isPopupStyle and 28 or 22)
            PP.Point(box, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            box:SetAutoFocus(false)
            box:SetTextColor(1, 1, 1, 0.9)
            local boxBg = box:CreateTexture(nil, "BACKGROUND")
            boxBg:SetAllPoints()
            if isPopupStyle then
                box:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
                box:SetJustifyH("LEFT")
                box:SetTextInsets(10, 10, 0, 0)
                boxBg:SetColorTexture(0, 0, 0, 0.5)
                MakeBorder(box, 1, 1, 1, 0.2)
                if cfg.placeholder then
                    local ph = box:CreateFontString(nil, "ARTWORK")
                    ph:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
                    ph:SetTextColor(0.7, 0.7, 0.7, 0.45)
                    ph:SetPoint("LEFT", box, "LEFT", 10, 0)
                    ph:SetText(EllesmereUI.L(cfg.placeholder))
                    box:SetScript("OnTextChanged", function(self)
                        ph:SetShown((self:GetText() or "") == "")
                    end)
                end
            else
                box:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
                box:SetJustifyH("CENTER")
                box:SetTextInsets(4, 4, 0, 0)
                boxBg:SetColorTexture(0.12, 0.12, 0.12, 0.85)
            end
            local function RefreshInput()
                if box:HasFocus() then return end
                box:SetText((cfg.getValue and cfg.getValue()) or "")
            end
            local committing = false
            local function CommitInput()
                if committing then return end
                committing = true
                box:ClearFocus()
                if cfg.setValue then cfg.setValue(box:GetText()) end
                RefreshInput()
                committing = false
            end
            box:SetScript("OnEnterPressed", CommitInput)
            box:SetScript("OnEditFocusLost", CommitInput)
            box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); RefreshInput() end)
            RefreshInput()
            controlFrame = box
            controlAnchor = box
            AddControlDisabledTooltip(box, cfg)
            RegisterWidgetRefresh(function() RefreshInput(); ApplyDisabledState() end)
            ApplyDisabledState()
        end
        region._control = controlAnchor or controlFrame
        -- Truncation is deferred (QueueLabelClamp) and the right bound applies ONLY on actual overflow: a bound stretches the label's rect, so anything anchored to its RIGHT edge (e.g. "(Applies to ...)" subtitles) would slide to the far side of the slot on short labels.
        QueueLabelClamp(region)
    end

    BuildHalf(leftRegion, leftCfg)
    BuildHalf(rightRegion, rightCfg)

    -- Slot-level search labels drive per-slot highlighting
    leftRegion._slotLabel  = leftCfg and leftCfg.text or ""
    rightRegion._slotLabel = rightCfg and rightCfg.text or ""

    -- Dropdown getValue/values stashed for dynamic search matching
    if leftCfg and leftCfg.type == "dropdown" then
        leftRegion._ddGetValue = leftCfg.getValue
        leftRegion._ddValues  = leftCfg.values
    end
    if rightCfg and rightCfg.type == "dropdown" then
        rightRegion._ddGetValue = rightCfg.getValue
        rightRegion._ddValues  = rightCfg.values
    end

    -- 1px center divider (global BORDER style)
    if not fullWidth then
        local div = frame:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(BORDER_R, BORDER_G, BORDER_B, 0.05)
        div:SetWidth(1)
        div:SetPoint("TOP", frame, "TOP", 0, 0)
        div:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    end

    -- Widget cfg on the regions lets sync icons check disabled state
    leftRegion._widgetCfg = leftCfg
    rightRegion._widgetCfg = rightCfg

    -- Half regions exposed so callers can anchor child elements
    frame._leftRegion  = leftRegion
    frame._rightRegion = rightRegion

    return frame, ROW_H
end

-- TripleRow: three widgets on one full-width row, 1px dividers at the splits. Each column uses the DualRow cfg format.
function WidgetFactory:TripleRow(parent, yOffset, leftCfg, midCfg, rightCfg, splits)
    local ROW_H = (splits and splits.rowHeight) or 50
    local SIDE_PAD = 20
    local frame = CreateFrame("Frame", nil, parent)
    local totalW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(frame, totalW, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    frame._skipRowDivider = true
    RowBg(frame, parent)
    -- Search metadata: combined label on the frame, one global-index entry per slot
    local triLabel = (leftCfg and leftCfg.text or "") .. " " .. (midCfg and midCfg.text or "") .. " " .. (rightCfg and rightCfg.text or "")
    TagOptionRow(frame, parent, triLabel, nil, true)
    IndexSlotForSearch(parent, leftCfg and leftCfg.text, leftCfg and leftCfg.tooltip)
    IndexSlotForSearch(parent, midCfg and midCfg.text, midCfg and midCfg.tooltip)
    IndexSlotForSearch(parent, rightCfg and rightCfg.text, rightCfg and rightCfg.tooltip)

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
        -- Spec Overrides capture: see DualRow BuildHalf.
        if cfg.noCapture then
            region._noCapture = true
        elseif cfg.getValue and cfg.setValue then
            region._captureCfg = cfg
        end
        local label = MakeFont(region, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        PP.Point(label, "LEFT", region, "LEFT", SIDE_PAD, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetMaxLines(1)
        label:SetText(EllesmereUI.L(cfg.text or ""))
        region._label = label
        region._labelHasHit = (cfg.tooltip or cfg.disabledTooltip) and true or false

        if (cfg.tooltip or cfg.disabledTooltip) and t ~= "dropdown" then
            local ttOpts = cfg.tooltipOpts
            local hitFrame = CreateFrame("Frame", nil, region)
            hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
            hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
            hitFrame:SetFrameLevel(region:GetFrameLevel() + 10)
            hitFrame:SetScript("OnEnter", function()
                if cfg.disabled and cfg.disabled() and cfg.disabledTooltip then
                    local tt = ResolveDisabledTip(cfg)
                    if tt then ShowWidgetTooltip(label, tt) end
                elseif cfg.tooltip then
                    ShowWidgetTooltip(label, LabelTooltipText(region, label, cfg.tooltip), ttOpts)
                elseif region._labelTruncated then
                    -- Truncated label whose hit exists only for the disabled tooltip: reveal the full text while enabled.
                    ShowWidgetTooltip(label, label:GetText())
                end
            end)
            hitFrame:SetScript("OnLeave", function() HideWidgetTooltip() end)
            -- Clicks pass through by default so controls stay interactive; intercepted while disabled to block interaction.
            hitFrame:SetMouseClickEnabled(false)
            if cfg.disabled and cfg.disabledTooltip then
                local function UpdateHitMouse()
                    hitFrame:SetMouseClickEnabled(cfg.disabled() and true or false)
                end
                RegisterWidgetRefresh(UpdateHitMouse)
                UpdateHitMouse()
            end
        end

        local controlFrame, controlAnchor
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
            local defaultTrackW = isRussian and 100 or 130
            local scfg = PixelizeSliderCfg(cfg)
            local trackFrame, valBox, _, slThumb = BuildSliderCore(region, cfg.trackWidth or defaultTrackW, 4, 14, 40, 26, 13, SL.INPUT_A,
                scfg.min, scfg.max, scfg.step, scfg.getValue, scfg.setValue, true, cfg.snapPoints)
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
            controlAnchor = trackFrame

        elseif t == "dropdown" then
            local DD_W = cfg.dropdownWidth or 170
            -- Bridge itemDisabled/itemDisabledTooltip into disabledValuesFn
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
                        local tt = ResolveDisabledTip(cfg)
                        if tt then ShowWidgetTooltip(label, tt) end
                    elseif cfg.tooltip and not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown()) then
                        ShowWidgetTooltip(label, LabelTooltipText(region, label, cfg.tooltip), ttOpts)
                    elseif region._labelTruncated and not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown()) then
                        ShowWidgetTooltip(label, label:GetText())
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
                    -- Gray the button label when the current value is disabled
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
            -- Generic label hidden: the checkbox draws its own label + box
            label:Hide()
            local btn = CreateFrame("Button", nil, region)
            btn:SetSize(region:GetWidth(), ROW_H)
            btn:SetAllPoints(region)
            btn:SetFrameLevel(frame:GetFrameLevel() + 2)

            local box, check, boxBorder, cbApply = BuildCheckboxControl(btn, frame:GetFrameLevel() + 2)
            box:SetPoint("LEFT", btn, "LEFT", SIDE_PAD, 0)

            local cbLabel = MakeFont(btn, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
            cbLabel:SetPoint("LEFT", box, "RIGHT", 10, 0)
            cbLabel:SetText(EllesmereUI.L(cfg.text or ""))

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
                EllesmereUI._settingsChanged = true
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

        elseif t == "labeledButton" then
            local btn = CreateFrame("Button", nil, region)
            PP.Size(btn, cfg.width or 140, 32)
            PP.Point(btn, "RIGHT", region, "RIGHT", -SIDE_PAD, 0)
            btn:SetFrameLevel(frame:GetFrameLevel() + 2)
            MakeStyledButton(btn, cfg.buttonText or cfg.text or "", 13, RB_COLOURS, cfg.onClick)
            controlFrame = btn
            RegisterWidgetRefresh(function() ApplyDisabledState() end)
            ApplyDisabledState()
        end
        region._control = controlAnchor or controlFrame
        -- Truncation is deferred (QueueLabelClamp) and the right bound applies ONLY on actual overflow: a bound stretches the label's rect, so anything anchored to its RIGHT edge (e.g. "(Applies to ...)" subtitles) would slide to the far side of the slot on short labels.
        QueueLabelClamp(region)
    end

    BuildThird(leftRegion, leftCfg)
    BuildThird(midRegion, midCfg)
    BuildThird(rightRegion, rightCfg)

    -- Slot-level search labels drive per-slot highlighting
    leftRegion._slotLabel  = leftCfg and leftCfg.text or ""
    midRegion._slotLabel   = midCfg and midCfg.text or ""
    rightRegion._slotLabel = rightCfg and rightCfg.text or ""

    -- Dropdown getValue/values stashed for dynamic search matching
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

    -- 1px column-boundary dividers (RowBg center-divider style)
    for _, rgn in ipairs({ leftRegion, midRegion }) do
        local div = frame:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.06)
        if div.SetSnapToPixelGrid then div:SetSnapToPixelGrid(false); div:SetTexelSnappingBias(0) end
        div:SetWidth(1)
        PP.Point(div, "TOP", rgn, "TOPRIGHT", 0, 0)
        PP.Point(div, "BOTTOM", rgn, "BOTTOMRIGHT", 0, 0)
    end

    leftRegion._widgetCfg = leftCfg
    if midRegion then midRegion._widgetCfg = midCfg end
    rightRegion._widgetCfg = rightCfg

    frame._leftRegion  = leftRegion
    frame._midRegion   = midRegion
    frame._rightRegion = rightRegion

    return frame, ROW_H
end

-- MultiSwatchRow: label left, N full-size color swatches right with tooltips.
-- cfg = { text = "Row Label", swatches = {
--   { tooltip = "Swatch 1", getValue = fn, setValue = fn, hasAlpha = bool }, ... } }
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

    local label = MakeFont(frame, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
    PP.Point(label, "LEFT", frame, "LEFT", SIDE_PAD, 0)
    label:SetText(EllesmereUI.L(cfg.text or ""))

    -- Swatches build right-to-left from the right edge
    local swatches = cfg.swatches or {}
    if cfg.noCapture then frame._noCapture = true end
    local anchorX = -SIDE_PAD
    for i = #swatches, 1, -1 do
        local sc = swatches[i]
        local swatch, updateSwatch = BuildColorSwatch(frame, frame:GetFrameLevel() + 2, sc.getValue, sc.setValue, sc.hasAlpha)
        PP.Point(swatch, "RIGHT", frame, "RIGHT", anchorX, 0)
        anchorX = anchorX - 24 - SWATCH_GAP

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
            if sc.tooltip then  -- normal tooltip while enabled
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
            local off = sc.disabled()
            if off then swatch:SetAlpha(0.3); swatchBlock:Show()
            else swatch:SetAlpha(1); swatchBlock:Hide() end
        else
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

    -- Spec Overrides capture: the whole row is ONE setting, all swatches capture together (see DualRow BuildHalf).
    do
        local accs = {}
        for i = 1, #swatches do
            local sc = swatches[i]
            if sc.getValue and sc.setValue then
                accs[#accs + 1] = { type = "colorpicker", text = sc.tooltip or cfg.text,
                    hasAlpha = sc.hasAlpha, getValue = sc.getValue, setValue = sc.setValue }
            end
        end
        if #accs > 0 and not cfg.noCapture then
            frame._captureCfg = { type = "multi", text = cfg.text, accessors = accs }
        end
    end

    return frame, ROW_H
end

-- DropdownWithOffsets: dropdown left, X and Y mini-sliders side by side right.
-- dropdownCfg: DualRow dropdown cfg (text, values, order, getValue, setValue,
--              disabledValues, disabled).
-- xSliderCfg / ySliderCfg: { text, min, max, step, getValue, setValue, disabled }
function WidgetFactory:DropdownWithOffsets(parent, yOffset, dropdownCfg, xSliderCfg, ySliderCfg)
    local ROW_H = 50
    local SIDE_PAD = 20
    local frame = CreateFrame("Frame", nil, parent)
    local totalW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(frame, totalW, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    RowBg(frame, parent)
    TagOptionRow(frame, parent, (dropdownCfg and dropdownCfg.text or "") .. " " .. (xSliderCfg and xSliderCfg.text or "") .. " " .. (ySliderCfg and ySliderCfg.text or ""), nil, true)
    IndexSlotForSearch(parent, dropdownCfg and dropdownCfg.text, dropdownCfg and dropdownCfg.tooltip)
    IndexSlotForSearch(parent, xSliderCfg and xSliderCfg.text, xSliderCfg and xSliderCfg.tooltip)
    IndexSlotForSearch(parent, ySliderCfg and ySliderCfg.text, ySliderCfg and ySliderCfg.tooltip)

    local halfW = math.floor(totalW / 2)

    -- Left half: label + dropdown (as in a DualRow dropdown half)
    local leftRegion = CreateFrame("Frame", nil, frame)
    leftRegion:SetSize(halfW, ROW_H)
    leftRegion:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    local ddLabel = MakeFont(leftRegion, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
    PP.Point(ddLabel, "LEFT", leftRegion, "LEFT", SIDE_PAD, 0)
    ddLabel:SetText(EllesmereUI.L(dropdownCfg.text or ""))

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

    -- Right half: X and Y mini-sliders on one line
    local rightRegion = CreateFrame("Frame", nil, frame)
    rightRegion:SetSize(halfW, ROW_H)
    rightRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local MINI_TRACK_W = 120
    local MINI_VALBOX_W = 30
    local SLIDER_H = 24

    -- align: "LEFT" = label,track,valbox left-to-right; "RIGHT" = the reverse
    local function BuildMiniSlider(slCfg, align)
        local isLeft = (align == "LEFT")

        -- Axis label ("X" or "Y")
        local axisLabel = MakeFont(rightRegion, 12, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        axisLabel:SetAlpha(0.6)
        axisLabel:SetText(EllesmereUI.L(slCfg.text or ""))

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

    BuildMiniSlider(xSliderCfg, "LEFT")
    BuildMiniSlider(ySliderCfg, "RIGHT")

    -- 1px center divider between dropdown and sliders
    local div = frame:CreateTexture(nil, "ARTWORK")
    div:SetColorTexture(BORDER_R, BORDER_G, BORDER_B, 0.05)
    div:SetWidth(1)
    div:SetPoint("TOP", frame, "TOP", 0, 0)
    div:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)

    RegisterWidgetRefresh(function()
        ddLbl:SetText(DDResolveLabel(dropdownCfg.values, dropdownCfg.order or {}, dropdownCfg.getValue()))
        ApplyDDDisabled()
    end)
    ApplyDDDisabled()

    -- Regions exposed for eye icon anchoring
    frame._leftRegion  = leftRegion
    frame._rightRegion = rightRegion
    -- Slot-level search labels drive per-slot highlighting
    leftRegion._slotLabel  = dropdownCfg and dropdownCfg.text or ""
    rightRegion._slotLabel = (xSliderCfg and xSliderCfg.text or "") .. " " .. (ySliderCfg and ySliderCfg.text or "")

    return frame, ROW_H
end

-- WideDualButton: two centered buttons side by side (each 100px narrower and 5px shorter than WideButton)
function WidgetFactory:WideDualButton(parent, text1, text2, yOffset, onClick1, onClick2, btnWidth)
    btnWidth = btnWidth or DUAL_ITEM_W
    local BTN_H = 37
    local ROW_H = BTN_H + 20
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    TagOptionRow(frame, parent, (text1 or "") .. " " .. (text2 or ""), nil, true)
    IndexSlotForSearch(parent, text1)
    IndexSlotForSearch(parent, text2)
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

-- WideTripleButton: three centered buttons side by side, for action rows. disabledOpts (optional): keyed by button index 1..3, e.g. { [3] = { disabled = true, tooltip = "why it's off" } }. A disabled button is dimmed, ignores hover highlight + clicks, and shows its tooltip on hover. Evaluated at build time (callers rebuild on RefreshPage).
function WidgetFactory:WideTripleButton(parent, text1, text2, text3, yOffset, onClick1, onClick2, onClick3, btnWidth, disabledOpts)
    btnWidth = btnWidth or 205
    local BTN_H = 37
    local ROW_H = BTN_H + 20
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    TagOptionRow(frame, parent, (text1 or "") .. " " .. (text2 or "") .. " " .. (text3 or ""), nil, true)
    IndexSlotForSearch(parent, text1)
    IndexSlotForSearch(parent, text2)
    IndexSlotForSearch(parent, text3)
    local gap = DUAL_GAP
    local offsets = { -(btnWidth + gap), 0, (btnWidth + gap) }
    for i, info in ipairs({ {text1, onClick1}, {text2, onClick2}, {text3, onClick3} }) do
        local btn = CreateFrame("Button", nil, frame)
        PP.Size(btn, btnWidth, BTN_H)
        PP.Point(btn, "CENTER", frame, "CENTER", offsets[i], 0)
        btn:SetFrameLevel(frame:GetFrameLevel() + 1)
        MakeStyledButton(btn, info[1], 12, WB_COLOURS, info[2])
        local dopt = disabledOpts and disabledOpts[i]
        if dopt and dopt.disabled then
            btn:SetAlpha(0.4)
            btn:SetScript("OnEnter", function()
                if dopt.tooltip then ShowWidgetTooltip(btn, dopt.tooltip) end
            end)
            btn:SetScript("OnLeave", function() HideWidgetTooltip() end)
            btn:SetScript("OnClick", nil)
        end
    end
    return frame, ROW_H
end

-- WideDropdown: centered, no row background, title above; prominent selectors
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
    titleLabel:SetText(EllesmereUI.L(title))
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

-- TripleDropdown: 3 normal-sized dropdowns side by side, centered, each with a small title above
function WidgetFactory:TripleDropdown(parent, configs, yOffset)
    local DD_W, DD_H, TITLE_H, GAP_Y = TRIPLE_ITEM_W, 30, 16, 6
    local ROW_H = TITLE_H + GAP_Y + DD_H + 12
    local frame = CreateFrame("Frame", nil, parent)
    local frameW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(frame, frameW, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    TagOptionRow(frame, parent, (configs[1] and configs[1][1] or "") .. " " .. (configs[2] and configs[2][1] or "") .. " " .. (configs[3] and configs[3][1] or ""), nil, true)
    IndexSlotForSearch(parent, configs[1] and configs[1][1])
    IndexSlotForSearch(parent, configs[2] and configs[2][1])
    IndexSlotForSearch(parent, configs[3] and configs[3][1])
    local totalW = DD_W * 3 + TRIPLE_GAP * 2
    local startX = (frameW - totalW) / 2
    for idx, cfg in ipairs(configs) do
        local col = startX + (idx - 1) * (DD_W + TRIPLE_GAP)
        local titleLbl = MakeFont(frame, 11, nil, EllesmereUI.TEXT_SECTION_R, EllesmereUI.TEXT_SECTION_G, EllesmereUI.TEXT_SECTION_B, EllesmereUI.TEXT_SECTION_A)
        PP.Point(titleLbl, "TOP", frame, "TOPLEFT", col + DD_W / 2, 0)
        titleLbl:SetText(EllesmereUI.L(cfg.title))
        local ddBtn, ddLbl = BuildDropdownControl(frame, DD_W, frame:GetFrameLevel() + 1, cfg.values, cfg.order, cfg.getValue, cfg.setValue)
        PP.Point(ddBtn, "TOPLEFT", frame, "TOPLEFT", col, -(TITLE_H + GAP_Y))
        RegisterWidgetRefresh(function()
            ddLbl:SetText(DDResolveLabel(cfg.values, cfg.order or {}, cfg.getValue()))
        end)
    end
    return frame, ROW_H
end

-- TripleSlider: three mini-sliders side by side, mirroring TripleDropdown columns. configs = exactly 3 x { title (unused), minVal, maxVal, step, getValue, setValue }
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
--  BuildCogPopup -- reusable cog settings popup with consistent layout
--  opts = { title = "Popup Title", rows = {
--      { type="slider", label="Distance", min=-50, max=50, step=1, get=fn, set=fn },
--      { type="toggle", label="Show Health Percent", get=fn, set=fn }, } }
--  Returns: popupFrame, showFn(anchorBtn)
-------------------------------------------------------------------------------
local function BuildCogPopup(opts)
    -- Spec Overrides capture: a cog's settings belong to its hosting slot -- ONE setting, captured whole. When the call site passes captureRegion (the DualRow half-region the cog sits in), every row with get/set joins that slot's capture group.
    -- row.noCapture opts a single row out (same flag DualRow honors): a popup can mix capturing rows with rows that must not capture (settings stored per palette rather than under a flat key).
    if opts.captureRegion and EllesmereUI.AddCaptureAccessor and opts.rows then
        for _, row in ipairs(opts.rows) do
            if row.get and row.set and not row.noCapture
               and row.type ~= "button" and row.type ~= "reorder"
               and row.type ~= "reordercheck" then
                EllesmereUI.AddCaptureAccessor(opts.captureRegion, {
                    type = row.type, text = row.label, getValue = row.get, setValue = row.set,
                    min = row.min, max = row.max, step = row.step,
                    values = row.values, order = row.order,
                    -- Grouping kept so the Spec Overrides page mirrors the slot 1:1 with a real inline cog.
                    fromCog = true, cogTitle = opts.title,
                })
            end
        end
    end

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

    local TG_W = 32; local TG_H = 16; local KNOB_SZ = 12; local KNOB_PAD = 2

    local popupFrame, popupOwner
    local rowWidgets = {}  -- per-row refresh info

    -- Spec Overrides auto-capture: cog row writes attribute to the cog's anchor button, which sits inside the host slot's region.
    if opts.rows then
        for _, row in ipairs(opts.rows) do
            if row.set then
                local _s = row.set
                row.set = function(...)
                    _s(...)
                    if EllesmereUI._NotifySettingWrite then
                        EllesmereUI._NotifySettingWrite(popupOwner or opts.captureRegion)
                    end
                end
            end
        end
    end

    local function CreatePopup()
        -- Measure slider labels to find maxLblW
        local tmpFS = UIParent:CreateFontString(nil, "OVERLAY")
        tmpFS:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
        local maxLblW = 0
        local maxDDLblW = 0
        for _, row in ipairs(opts.rows) do
            if row.type == "slider" or row.type == "input" then
                tmpFS:SetText(EllesmereUI.L(row.label))
                local w = tmpFS:GetStringWidth()
                if w > maxLblW then maxLblW = w end
            elseif row.type == "dropdown" or row.type == "segmented" or row.type == "reordercheck" then
                tmpFS:SetText(EllesmereUI.L(row.label))
                local w = tmpFS:GetStringWidth()
                if w > maxDDLblW then maxDDLblW = w end
            end
        end
        tmpFS:Hide()
        if maxLblW < 10 then maxLblW = 60 end

        local COG_DD_W = 130
        local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
        local TARGET_W = opts.minWidth or 260
        local SLIDER_W = math.max(80, TARGET_W - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
        local POPUP_W = math.max(opts.minWidth or MIN_POPUP_W, SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD)
        -- Widen for dropdown rows (label + gap + dropdown + padding)
        local ddNeeded = SIDE_PAD + maxDDLblW + LABEL_SLIDER_GAP + COG_DD_W + SIDE_PAD
        if ddNeeded > POPUP_W then POPUP_W = ddNeeded end
        if opts.minWidth and opts.minWidth > POPUP_W then POPUP_W = opts.minWidth end
        -- Stretch the track to fill a widened popup so no gap opens between the slider and its value box. Gated on minWidth so un-widened cog popups keep their original slider width.
        if opts.minWidth then
            SLIDER_W = math.max(SLIDER_W, POPUP_W - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
        end

        local totalH = TOP_PAD + TITLE_H + TITLE_GAP
        for i, row in ipairs(opts.rows) do
            if i > 1 then totalH = totalH + GAP end
            if row.type == "toggle" or row.type == "segmented" then
                totalH = totalH + TOGGLE_ROW_H
            elseif row.type == "dropdown" or row.type == "reorder" or row.type == "reordercheck" then
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

        local pf = CreateFrame("Frame", nil, UIParent)
        pf:SetSize(POPUP_W, totalH)
        pf:SetFrameStrata(opts.frameStrata or "DIALOG"); pf:SetFrameLevel(opts.frameLevel or 200)
        pf:EnableMouse(true); pf:Hide()
        -- Spec Overrides auto-capture: edits inside this popup attribute to the slot whose cog opened it.
        pf._euiOptionsPopup = true

        -- Match panel scale so the popup matches scrollable-area widgets
        local ppScale = EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale() or 1
        pf:SetScale(ppScale)
        if EllesmereUI._popupFrames then
            EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = pf }
        end

        local bg = SolidTex(pf, "BACKGROUND", 0.06, 0.08, 0.10, opts.bgAlpha or 0.95)
        bg:SetAllPoints()
        MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15, PP)

        local titleFS = MakeFont(pf, TITLE_H, "", 1, 1, 1)
        titleFS:SetAlpha(0.7)
        titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
        titleFS:SetText(EllesmereUI.L(opts.title or ""))

        local curY = -(TOP_PAD + TITLE_H + TITLE_GAP)
        for i, row in ipairs(opts.rows) do
            if i > 1 then curY = curY - GAP end

            if row.type == "slider" then
                local srow = PixelizeSliderCfg(row)
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
                lbl:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, curY - ROW_H / 2 - 1)

                if row.tooltip then
                    local hitFrame = CreateFrame("Frame", nil, pf)
                    hitFrame:SetPoint("TOPLEFT", lbl, "TOPLEFT", -2, 2)
                    hitFrame:SetPoint("BOTTOMRIGHT", lbl, "BOTTOMRIGHT", 2, -2)
                    hitFrame:SetFrameLevel(pf:GetFrameLevel() + 3)
                    hitFrame:EnableMouse(true)
                    hitFrame:SetScript("OnEnter", function()
                        if EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(lbl, row.tooltip)
                        end
                    end)
                    hitFrame:SetScript("OnLeave", function()
                        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                    end)
                end

                local track, valBox, updateVisual = BuildSliderCore(pf, SLIDER_W, 4, 12, INPUT_W, ROW_H, 11, POPUP_INPUT_A,
                    srow.min, srow.max, srow.step, srow.get, srow.set, true)
                track:SetPoint("LEFT", pf, "TOPLEFT", SLIDER_LEFT, curY - ROW_H / 2)
                valBox:ClearAllPoints()
                valBox:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, curY - ROW_H / 2)

                local sliderDis
                if row.disabled then
                    sliderDis = CreateFrame("Frame", nil, pf)
                    sliderDis:SetPoint("TOPLEFT", pf, "TOPLEFT", 1, curY)
                    sliderDis:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -1, curY)
                    sliderDis:SetHeight(ROW_H)
                    sliderDis:SetFrameLevel(pf:GetFrameLevel() + 10)
                    sliderDis:EnableMouse(true)
                    local disTex = SolidTex(sliderDis, "OVERLAY", 0.06, 0.08, 0.10, 0.70)
                    disTex:SetAllPoints()
                    sliderDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    sliderDis:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
                end

                rowWidgets[#rowWidgets + 1] = { type = "slider", updateVisual = updateVisual, get = srow.get, disOverlay = sliderDis, disCheck = row.disabled }
                curY = curY - ROW_H

            elseif row.type == "toggle" then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
                lbl:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, curY - TOGGLE_ROW_H / 2 - 1)

                if row.tooltip then
                    local hitFrame = CreateFrame("Frame", nil, pf)
                    hitFrame:SetPoint("TOPLEFT", lbl, "TOPLEFT", -2, 2)
                    hitFrame:SetPoint("BOTTOMRIGHT", lbl, "BOTTOMRIGHT", 2, -2)
                    hitFrame:SetFrameLevel(pf:GetFrameLevel() + 3)
                    hitFrame:EnableMouse(true)
                    hitFrame:SetScript("OnEnter", function()
                        if EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(lbl, row.tooltip)
                        end
                    end)
                    hitFrame:SetScript("OnLeave", function()
                        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                    end)
                end

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

                local toggleDis
                if row.disabled then
                    toggleDis = CreateFrame("Frame", nil, pf)
                    toggleDis:SetPoint("TOPLEFT", pf, "TOPLEFT", 1, curY)
                    toggleDis:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -1, curY)
                    toggleDis:SetHeight(TOGGLE_ROW_H)
                    toggleDis:SetFrameLevel(pf:GetFrameLevel() + 10)
                    toggleDis:EnableMouse(true)
                    local disTex = SolidTex(toggleDis, "OVERLAY", 0.06, 0.08, 0.10, 0.70)
                    disTex:SetAllPoints()
                    toggleDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    toggleDis:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
                end

                rowWidgets[#rowWidgets + 1] = { type = "toggle", updateVisual = UpdateToggleVisual, disOverlay = toggleDis, disCheck = row.disabled }
                curY = curY - TOGGLE_ROW_H
            elseif row.type == 'dropdown' then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
                lbl:SetPoint('LEFT', pf, 'TOPLEFT', SIDE_PAD, curY - DROPDOWN_ROW_H / 2 - 1)

                -- Cog-popup dropdowns render 10% smaller than the panel dropdowns.
                local DD_SCALE = 0.9
                local ddBtn, ddLbl = BuildDropdownControl(pf, COG_DD_W, pf:GetFrameLevel() + 2, row.values, row.order, row.get, function(v)
                    row.set(v)
                    if pf._refresh then pf._refresh() end
                end, row.itemDisabled)
                ddBtn:SetScale(DD_SCALE)
                ddBtn:ClearAllPoints()
                -- Offsets divided by DD_SCALE so the scaled control still lands flush-right and vertically centered: SetScale multiplies a frame's own anchor offsets by its scale.
                ddBtn:SetPoint('RIGHT', pf, 'TOPRIGHT', -SIDE_PAD / DD_SCALE, (curY - DROPDOWN_ROW_H / 2) / DD_SCALE)
                if row.tooltip then ddBtn._ttText = row.tooltip; ddBtn._ttOpts = row.tooltipOpts end
                -- Propagate popup scale and the 10% reduction to the lazily-built menu so the open list matches the shrunk control.
                ddBtn:HookScript('OnClick', function(self)
                    if self._ddMenu then
                        if not self._ddMenu._cogScaled then
                            self._ddMenu:SetScale(ppScale * DD_SCALE)
                            self._ddMenu._cogScaled = true
                        end
                        -- Keep the menu above the cog popup: BuildDropdownMenu creates it at FULLSCREEN_DIALOG 200, which sits BEHIND a popup that is itself FULLSCREEN_DIALOG.
                        self._ddMenu:SetFrameStrata(pf:GetFrameStrata())
                        self._ddMenu:SetFrameLevel(pf:GetFrameLevel() + 30)
                    end
                end)

                -- Disabled overlay, mirroring slider/input handling
                local ddDis
                if row.disabled then
                    ddDis = CreateFrame("Frame", nil, pf)
                    ddDis:SetPoint("TOPLEFT", pf, "TOPLEFT", 1, curY)
                    ddDis:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -1, curY)
                    ddDis:SetHeight(DROPDOWN_ROW_H)
                    ddDis:SetFrameLevel(pf:GetFrameLevel() + 10)
                    ddDis:EnableMouse(true)
                    local disTex = SolidTex(ddDis, "OVERLAY", 0.06, 0.08, 0.10, 0.70)
                    disTex:SetAllPoints()
                    ddDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    ddDis:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
                end

                rowWidgets[#rowWidgets + 1] = { type = 'dropdown', btn = ddBtn, lbl = ddLbl, get = row.get, values = row.values, refresh = ddBtn._ddRefresh, disOverlay = ddDis, disCheck = row.disabled }
                curY = curY - DROPDOWN_ROW_H
            elseif row.type == 'reordercheck' then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
                lbl:SetPoint('LEFT', pf, 'TOPLEFT', SIDE_PAD, curY - DROPDOWN_ROW_H / 2 - 1)

                local items = type(row.items) == "function" and row.items() or row.items or {}
                local ddBtn, refresh = EllesmereUI.BuildReorderCBDropdown(
                    pf, COG_DD_W, pf:GetFrameLevel() + 2, items,
                    row.get,
                    function(k, v)
                        row.set(k, v)
                        if pf._refresh then pf._refresh() end
                    end,
                    {
                        hint = row.hint,
                        hint2 = row.hint2,
                        setOrder = function(keys)
                            if row.setOrder then row.setOrder(keys) end
                        end,
                    })
                local DD_SCALE = 0.9
                ddBtn:SetScale(DD_SCALE)
                ddBtn:ClearAllPoints()
                ddBtn:SetPoint('RIGHT', pf, 'TOPRIGHT', -SIDE_PAD / DD_SCALE, (curY - DROPDOWN_ROW_H / 2) / DD_SCALE)
                ddBtn:HookScript('OnClick', function(self)
                    if self._ddMenu then
                        self._ddMenu:SetFrameStrata(pf:GetFrameStrata())
                        self._ddMenu:SetFrameLevel(pf:GetFrameLevel() + 30)
                    end
                end)

                rowWidgets[#rowWidgets + 1] = { type = 'reordercheck', btn = ddBtn, refresh = refresh }
                curY = curY - DROPDOWN_ROW_H
            elseif row.type == 'segmented' then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
                lbl:SetPoint('LEFT', pf, 'TOPLEFT', SIDE_PAD, curY - TOGGLE_ROW_H / 2 - 1)

                local seg, _seg2, segRefresh = EllesmereUI.BuildSegmentedControl({
                    parent     = pf,
                    keys       = row.keys,
                    labels     = row.labels,
                    autoWidth  = true,
                    square     = true,
                    height     = 22,
                    getChecked = function(key) return row.get() == key end,
                    onToggle   = function(key)
                        row.set(key)
                        if pf._refresh then pf._refresh() end
                    end,
                })
                seg:ClearAllPoints()
                seg:SetPoint('RIGHT', pf, 'TOPRIGHT', -SIDE_PAD, curY - TOGGLE_ROW_H / 2)

                local segDis
                if row.disabled then
                    segDis = CreateFrame("Frame", nil, pf)
                    segDis:SetPoint("TOPLEFT", pf, "TOPLEFT", 1, curY)
                    segDis:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -1, curY)
                    segDis:SetHeight(TOGGLE_ROW_H)
                    segDis:SetFrameLevel(pf:GetFrameLevel() + 10)
                    segDis:EnableMouse(true)
                    local disTex = SolidTex(segDis, "OVERLAY", 0.06, 0.08, 0.10, 0.70)
                    disTex:SetAllPoints()
                    segDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    segDis:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
                end

                rowWidgets[#rowWidgets + 1] = { type = 'segmented', seg = seg, refresh = segRefresh, disOverlay = segDis, disCheck = row.disabled }
                curY = curY - TOGGLE_ROW_H
            elseif row.type == 'colorpicker' then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
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

                -- Disabled: blocking overlays on label + swatch (inline swatch pattern)
                local cpSwBlock, cpLblBlock
                if row.disabled then

                    cpSwBlock = CreateFrame("Frame", nil, cpSwatch)
                    cpSwBlock:SetAllPoints()
                    cpSwBlock:SetFrameLevel(cpSwatch:GetFrameLevel() + 10)
                    cpSwBlock:EnableMouse(true)
                    cpSwBlock:SetScript("OnEnter", function()
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(cpSwatch, tip)
                        end
                    end)
                    cpSwBlock:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)

                    cpLblBlock = CreateFrame("Frame", nil, pf)
                    cpLblBlock:SetPoint("TOPLEFT", lbl, "TOPLEFT", -2, 2)
                    cpLblBlock:SetPoint("BOTTOMRIGHT", lbl, "BOTTOMRIGHT", 2, -2)
                    cpLblBlock:SetFrameLevel(pf:GetFrameLevel() + 10)
                    cpLblBlock:EnableMouse(true)
                    cpLblBlock:SetScript("OnEnter", function()
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(lbl, tip)
                        end
                    end)
                    cpLblBlock:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
                end

                rowWidgets[#rowWidgets + 1] = { type = 'colorpicker', updateSwatch = cpUpdate, swatch = cpSwatch, swBlock = cpSwBlock, lblBlock = cpLblBlock, disCheck = row.disabled }

                if row.disabled then
                    local initDis = type(row.disabled) == "function" and row.disabled() or row.disabled
                    cpSwatch:SetAlpha(initDis and 0.3 or 1)
                    if cpSwBlock then if initDis then cpSwBlock:Show() else cpSwBlock:Hide() end end
                    if cpLblBlock then if initDis then cpLblBlock:Show() else cpLblBlock:Hide() end end
                end

                curY = curY - ROW_H
            elseif row.type == 'multiswatch' then
                -- Cog-row form of the main-page multiSwatch slot: label + N swatches right-to-left from the right edge; click one or the other, the inactive one dims. Same swatch spec: getValue/setValue/hasAlpha/tooltip/onClick (original picker click stashed on _eabOrigClick)/refreshAlpha.
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
                lbl:SetPoint('LEFT', pf, 'TOPLEFT', SIDE_PAD, curY - ROW_H / 2 - 1)

                local MSW_GAP = 8
                local mswX = -SIDE_PAD
                local mswUpdates, mswAlphas = {}, {}
                local mswSwatches = row.swatches or {}
                for i = #mswSwatches, 1, -1 do
                    local sc = mswSwatches[i]
                    local swatch, updateSwatch = BuildColorSwatch(pf, pf:GetFrameLevel() + 2,
                        sc.getValue,
                        function(r, g, b, a)
                            if sc.setValue then sc.setValue(r, g, b, a) end
                            if EllesmereUI._NotifySettingWrite then
                                EllesmereUI._NotifySettingWrite(popupOwner or opts.captureRegion)
                            end
                            if pf._refresh then pf._refresh() end
                        end,
                        sc.hasAlpha, 20)
                    swatch:ClearAllPoints()
                    swatch:SetPoint('RIGHT', pf, 'TOPRIGHT', mswX, curY - ROW_H / 2)
                    mswX = mswX - 20 - MSW_GAP
                    if sc.onClick then
                        swatch._eabOrigClick = swatch:GetScript('OnClick')
                        swatch:SetScript('OnClick', function(self, ...)
                            sc.onClick(self, ...)
                            if EllesmereUI._NotifySettingWrite then
                                EllesmereUI._NotifySettingWrite(popupOwner or opts.captureRegion)
                            end
                            if pf._refresh then pf._refresh() end
                        end)
                    end
                    if sc.tooltip then
                        swatch:HookScript('OnEnter', function()
                            if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(swatch, sc.tooltip) end
                        end)
                        swatch:HookScript('OnLeave', function()
                            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                        end)
                    end
                    mswUpdates[#mswUpdates + 1] = updateSwatch
                    if sc.refreshAlpha then
                        mswAlphas[#mswAlphas + 1] = { sw = swatch, fn = sc.refreshAlpha }
                        swatch:SetAlpha(sc.refreshAlpha())
                    end
                end

                -- Row-level disabled overlay, as on the slider/input rows
                local mswDis
                if row.disabled then
                    mswDis = CreateFrame("Frame", nil, pf)
                    mswDis:SetPoint("TOPLEFT", pf, "TOPLEFT", 1, curY)
                    mswDis:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -1, curY)
                    mswDis:SetHeight(ROW_H)
                    mswDis:SetFrameLevel(pf:GetFrameLevel() + 10)
                    mswDis:EnableMouse(true)
                    local disTex = SolidTex(mswDis, "OVERLAY", 0.06, 0.08, 0.10, 0.70)
                    disTex:SetAllPoints()
                    mswDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    mswDis:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
                    local initDis = type(row.disabled) == "function" and row.disabled() or row.disabled
                    if initDis then mswDis:Show() else mswDis:Hide() end
                end

                rowWidgets[#rowWidgets + 1] = { type = 'multiswatch', updates = mswUpdates, alphaFns = mswAlphas, disOverlay = mswDis, disCheck = row.disabled }
                curY = curY - ROW_H
            elseif row.type == 'input' then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
                lbl:SetPoint("LEFT", pf, "TOPLEFT", SIDE_PAD, curY - ROW_H / 2 - 1)

                local inputW = row.inputWidth or 80
                local SAVE_W = 34
                local SAVE_GAP = 4

                -- commitOnBlur: no Save button, commit on Enter and focus loss (matches the threshold EditBoxes). Otherwise an explicit Save button sits right of the input.
                local commitOnBlur = row.commitOnBlur
                local EG = ELLESMERE_GREEN
                local saveBtn, saveBg, saveLbl
                if not commitOnBlur then
                    saveBtn = CreateFrame("Button", nil, pf)
                    saveBtn:SetSize(SAVE_W, ROW_H - 4)
                    saveBtn:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, curY - ROW_H / 2)
                    saveBtn:SetFrameLevel(pf:GetFrameLevel() + 3)
                    saveBg = SolidTex(saveBtn, "BACKGROUND", EG.r, EG.g, EG.b, 0.85)
                    saveBg:SetAllPoints()
                    saveLbl = MakeFont(saveBtn, 10, nil, 1, 1, 1)
                    saveLbl:SetAlpha(0.9)
                    saveLbl:SetText(EllesmereUI.L("Save"))
                    saveLbl:SetPoint("CENTER")
                    saveBtn:SetScript("OnEnter", function()
                        saveBg:SetColorTexture(EG.r + (1 - EG.r) * 0.25, EG.g + (1 - EG.g) * 0.25, EG.b + (1 - EG.b) * 0.25, 0.95)
                        saveLbl:SetAlpha(1)
                    end)
                    saveBtn:SetScript("OnLeave", function() saveBg:SetColorTexture(EG.r, EG.g, EG.b, 0.85); saveLbl:SetAlpha(0.9) end)
                end

                local box = CreateFrame("EditBox", nil, pf)
                box:SetSize(inputW, ROW_H - 4)
                if commitOnBlur then
                    box:SetPoint("RIGHT", pf, "TOPRIGHT", -SIDE_PAD, curY - ROW_H / 2)
                else
                    box:SetPoint("RIGHT", saveBtn, "LEFT", -SAVE_GAP, 0)
                end
                box:SetAutoFocus(false)
                box:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
                box:SetTextColor(1, 1, 1, POPUP_INPUT_A)
                box:SetJustifyH("CENTER")
                local boxBg = SolidTex(box, "BACKGROUND", 0.12, 0.12, 0.12, 0.8)
                boxBg:SetAllPoints()
                box:SetText(row.get and row.get() or "")

                local _committing = false  -- guard ClearFocus -> OnEditFocusLost reentry
                local function ApplyInput()
                    if _committing then return end
                    _committing = true
                    box:ClearFocus()
                    if row.set then row.set(box:GetText()) end
                    if pf._refresh then pf._refresh() end
                    -- Brief white flash on the save button as confirmation
                    if saveBg then
                        saveBg:SetColorTexture(1, 1, 1, 0.9)
                        saveLbl:SetText(EllesmereUI.L("Saved"))
                        C_Timer.After(0.4, function()
                            saveBg:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
                            saveLbl:SetText(EllesmereUI.L("Save"))
                        end)
                    end
                    _committing = false
                end

                box:SetScript("OnEnterPressed", function(self) ApplyInput() end)
                box:SetScript("OnEscapePressed", function(self)
                    -- Cancel: guard + restore BEFORE ClearFocus -- in commitOnBlur mode ClearFocus fires OnEditFocusLost, which would otherwise SAVE the discarded text.
                    _committing = true
                    self:SetText(row.get and row.get() or "")
                    self:ClearFocus()
                    _committing = false
                end)
                if commitOnBlur then
                    box:SetScript("OnEditFocusLost", function() ApplyInput() end)
                else
                    saveBtn:SetScript("OnClick", function() ApplyInput() end)
                end

                local inputDis
                if row.disabled then
                    inputDis = CreateFrame("Frame", nil, pf)
                    inputDis:SetPoint("TOPLEFT", pf, "TOPLEFT", 1, curY)
                    inputDis:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -1, curY)
                    inputDis:SetHeight(ROW_H)
                    inputDis:SetFrameLevel(pf:GetFrameLevel() + 10)
                    inputDis:EnableMouse(true)
                    local disTex = SolidTex(inputDis, "OVERLAY", 0.06, 0.08, 0.10, 0.70)
                    disTex:SetAllPoints()
                    inputDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    inputDis:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
                end

                rowWidgets[#rowWidgets + 1] = { type = 'input', box = box, get = row.get, disOverlay = inputDis, disCheck = row.disabled, saveBg = saveBg }
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
                btnLbl:SetText(EllesmereUI.L(row.label))
                btn:SetScript("OnEnter", function() btnBg:SetColorTexture(0.25, 0.25, 0.25, 0.85); btnLbl:SetAlpha(1) end)
                btn:SetScript("OnLeave", function() btnBg:SetColorTexture(0.18, 0.18, 0.18, 0.85); btnLbl:SetAlpha(0.7) end)
                btn:SetScript("OnClick", function()
                    if row.action then row.action() end
                    if pf._refresh then pf._refresh() end
                end)
                rowWidgets[#rowWidgets + 1] = { type = 'button' }
                curY = curY - BTN_ROW_H

            elseif row.type == 'reorder' then
                -- Full-width dropdown button opening a drag-to-reorder menu (hint label + draggable rows), matching the raid/party "Sort By" reorder section.
                local RR_W = POPUP_W - SIDE_PAD * 2
                local ddBtn = CreateFrame("Button", nil, pf)
                ddBtn:SetSize(RR_W, DROPDOWN_ROW_H - 2)
                ddBtn:SetPoint("TOP", pf, "TOPLEFT", POPUP_W / 2, curY - 1)
                ddBtn:SetFrameLevel(pf:GetFrameLevel() + 2)
                local rBg = SolidTex(ddBtn, "BACKGROUND", EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                rBg:SetAllPoints()
                local rBrd = MakeBorder(ddBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
                local rLbl = MakeFont(ddBtn, 12, nil, 1, 1, 1)
                rLbl:SetAlpha(EllesmereUI.DD_TXT_A)
                rLbl:SetJustifyH("LEFT"); rLbl:SetWordWrap(false); rLbl:SetMaxLines(1)
                rLbl:SetPoint("LEFT", ddBtn, "LEFT", 8, 0)
                rLbl:SetText(EllesmereUI.L(row.label))
                local rArrow = MakeDropdownArrow(ddBtn, 12, PP)
                rLbl:SetPoint("RIGHT", rArrow, "LEFT", -5, 0)
                ddBtn:SetScript("OnEnter", function()
                    rBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                    rBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_HA)
                    rLbl:SetAlpha(EllesmereUI.DD_TXT_HA)
                end)
                ddBtn:SetScript("OnLeave", function()
                    rBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                    rBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                    rLbl:SetAlpha(EllesmereUI.DD_TXT_A)
                end)

                -- Menu is FULLSCREEN_DIALOG so it floats above the popup
                local MH = 26
                local FONT = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                local menu = CreateFrame("Frame", nil, UIParent)
                menu:SetFrameStrata("FULLSCREEN_DIALOG")
                menu:SetFrameLevel(220)
                menu:SetClampedToScreen(true)
                menu:SetWidth(RR_W)
                menu:Hide()
                local mBg2 = SolidTex(menu, "BACKGROUND", EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, 0.98)
                mBg2:SetAllPoints()
                MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
                menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
                ddBtn._ddMenu = menu  -- popup click-outside ignores menu interaction

                -- Declared before OnShow so its OnUpdate can suppress the click-away dismiss while a row is being dragged.
                local dragRow, dsY, isDragging = nil, nil, false

                menu:SetScript("OnShow", function(self)
                    self:SetScale(ddBtn:GetEffectiveScale() / UIParent:GetEffectiveScale())
                    self:SetScript("OnUpdate", function(m)
                        if isDragging then return end  -- never dismiss mid-drag
                        if not ddBtn:IsMouseOver() and not m:IsMouseOver() then
                            if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then m:Hide() end
                        end
                    end)
                end)
                menu:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

                local mY = -2
                local ht = menu:CreateFontString(nil, "OVERLAY")
                ht:SetFont(FONT, 10, "")
                ht:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, mY - 4)
                ht:SetTextColor(1, 1, 1, 0.25)
                ht:SetText(EllesmereUI.L(row.hint or "Drag to Reorder"))
                mY = mY - 18

                local items = (row.items and row.items()) or {}
                -- Height cap: rows live on a scroll child. Menus longer than
                -- row.maxVisible rows clamp to that many and mousewheel-scroll;
                -- the drag math below is scroll-child-relative, so reordering
                -- keeps working while scrolled. No maxVisible = full height,
                -- scrolling never engages (exact legacy behavior).
                local visN = #items
                if row.maxVisible and row.maxVisible > 0 and visN > row.maxVisible then
                    visN = row.maxVisible
                end
                local listH = #items * MH
                local visH = visN * MH
                local scroller = CreateFrame("ScrollFrame", nil, menu)
                scroller:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, mY)
                scroller:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, mY)
                scroller:SetHeight(math.max(visH, 1))
                scroller:SetFrameLevel(menu:GetFrameLevel() + 1)
                local sChild = CreateFrame("Frame", nil, scroller)
                sChild:SetSize(RR_W, math.max(listH, 1))
                scroller:SetScrollChild(sChild)
                local maxScroll = math.max(0, listH - visH)
                menu:EnableMouseWheel(true)
                menu:SetScript("OnMouseWheel", function(_, delta)
                    if maxScroll <= 0 then return end
                    local nv = (scroller:GetVerticalScroll() or 0) - delta * MH * 2
                    if nv < 0 then nv = 0 elseif nv > maxScroll then nv = maxScroll end
                    scroller:SetVerticalScroll(nv)
                end)

                local cbBaseY = 0
                mY = 0
                local rowFrames = {}
                local insLine = sChild:CreateTexture(nil, "OVERLAY", nil, 7)
                insLine:SetHeight(2)
                local EG2 = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
                insLine:SetColorTexture(EG2.r, EG2.g, EG2.b, 0.9)
                insLine:Hide()

                local function PersistOrder()
                    local keys = {}
                    for _, rf in ipairs(rowFrames) do keys[#keys + 1] = rf._key end
                    if row.set then row.set(keys) end
                end

                for ci, it in ipairs(items) do
                    local rf = CreateFrame("Button", nil, sChild)
                    rf:SetHeight(MH)
                    rf._baseY = mY
                    rf._cbIndex = ci
                    rf._key = it.key
                    rf:SetPoint("TOPLEFT", sChild, "TOPLEFT", 1, mY)
                    rf:SetPoint("TOPRIGHT", sChild, "TOPRIGHT", -1, mY)
                    rf:SetFrameLevel(menu:GetFrameLevel() + 2)

                    local rl = rf:CreateFontString(nil, "OVERLAY")
                    rl:SetFont(FONT, 13, "")
                    rl:SetPoint("LEFT", rf, "LEFT", 20, 0)
                    rl:SetJustifyH("LEFT")
                    rl:SetText(it.label)
                    rl:SetTextColor(0.75, 0.75, 0.75, 1)
                    rf._lbl = rl

                    local grip = rf:CreateFontString(nil, "OVERLAY")
                    grip:SetFont(FONT, 10, "")
                    grip:SetPoint("LEFT", rf, "LEFT", 8, 0)
                    grip:SetText("=")
                    grip:SetTextColor(1, 1, 1, 0.2)

                    local rHL = rf:CreateTexture(nil, "ARTWORK")
                    rHL:SetAllPoints(); rHL:SetColorTexture(1, 1, 1, 0)

                    rf:SetScript("OnEnter", function()
                        if isDragging then return end
                        rl:SetTextColor(1, 1, 1, 1); rHL:SetColorTexture(1, 1, 1, 0.04)
                    end)
                    rf:SetScript("OnLeave", function()
                        if isDragging then return end
                        rl:SetTextColor(0.75, 0.75, 0.75, 1); rHL:SetColorTexture(1, 1, 1, 0)
                    end)

                    rf:SetScript("OnMouseDown", function(self, b)
                        if b ~= "LeftButton" then return end
                        local _, cy = GetCursorPosition()
                        dsY = cy; dragRow = self
                    end)

                    rf:SetScript("OnUpdate", function(self)
                        if dragRow ~= self or not dsY then return end
                        local _, cy = GetCursorPosition()
                        if not isDragging then
                            if math.abs(cy - dsY) < 3 then return end
                            isDragging = true
                            self:SetFrameLevel(menu:GetFrameLevel() + 10); self:SetAlpha(0.8)
                            for _, r2 in ipairs(rowFrames) do
                                if r2._lbl then r2._lbl:SetTextColor(0.75, 0.75, 0.75, 1) end
                            end
                        end
                        local sc = menu:GetEffectiveScale()
                        local cY = cy / sc
                        local mT = sChild:GetTop() or 0
                        local iI = #rowFrames
                        for ri, r2 in ipairs(rowFrames) do
                            if r2 ~= self and r2._baseY then
                                local rm = mT + r2._baseY - MH / 2
                                if cY > rm then iI = ri; break end
                                iI = ri + 1
                            end
                        end
                        iI = math.max(1, math.min(iI, #rowFrames + 1))
                        local lnY = (iI <= 1) and (cbBaseY + 1) or (cbBaseY - (iI - 1) * MH + 1)
                        insLine:ClearAllPoints()
                        insLine:SetPoint("TOPLEFT", sChild, "TOPLEFT", 8, lnY)
                        insLine:SetPoint("TOPRIGHT", sChild, "TOPRIGHT", -8, lnY)
                        insLine:Show()
                        self:ClearAllPoints()
                        self:SetPoint("TOPLEFT", sChild, "TOPLEFT", 1, cY - mT)
                        self:SetPoint("TOPRIGHT", sChild, "TOPRIGHT", -1, cY - mT)
                    end)

                    rf:SetScript("OnMouseUp", function(self, b)
                        if b ~= "LeftButton" or dragRow ~= self then return end
                        dsY = nil; dragRow = nil
                        if not isDragging then return end
                        isDragging = false; insLine:Hide()
                        self:SetFrameLevel(menu:GetFrameLevel() + 2); self:SetAlpha(1)
                        local _, cy = GetCursorPosition()
                        local sc = menu:GetEffectiveScale(); cy = cy / sc
                        local mT = sChild:GetTop() or 0
                        local from = self._cbIndex
                        local iI = #rowFrames
                        for ri, r2 in ipairs(rowFrames) do
                            if r2 ~= self and r2._baseY then
                                local rm = mT + r2._baseY - MH / 2
                                if cy > rm then iI = ri; break end
                                iI = ri + 1
                            end
                        end
                        iI = math.max(1, math.min(iI, #rowFrames + 1))
                        if from < iI then iI = iI - 1 end
                        local to = math.max(1, math.min(iI, #rowFrames))
                        if from ~= to then
                            local mv = table.remove(rowFrames, from)
                            table.insert(rowFrames, to, mv)
                            PersistOrder()
                        end
                        for ri = 1, #rowFrames do
                            local r2 = rowFrames[ri]
                            r2._cbIndex = ri
                            local ry = cbBaseY - (ri - 1) * MH
                            r2._baseY = ry
                            r2:ClearAllPoints()
                            r2:SetPoint("TOPLEFT", sChild, "TOPLEFT", 1, ry)
                            r2:SetPoint("TOPRIGHT", sChild, "TOPRIGHT", -1, ry)
                        end
                    end)

                    rowFrames[#rowFrames + 1] = rf
                    mY = mY - MH
                end
                menu:SetHeight(20 + visH + 4)

                ddBtn:SetScript("OnClick", function()
                    if menu:IsShown() then menu:Hide() else menu:Show() end
                end)

                -- Disabled overlay: dim + block + hide menu
                local reorderDis
                if row.disabled then
                    reorderDis = CreateFrame("Frame", nil, pf)
                    reorderDis:SetPoint("TOPLEFT", pf, "TOPLEFT", 1, curY)
                    reorderDis:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -1, curY)
                    reorderDis:SetHeight(DROPDOWN_ROW_H)
                    reorderDis:SetFrameLevel(pf:GetFrameLevel() + 12)
                    reorderDis:EnableMouse(true)
                    local disTex = SolidTex(reorderDis, "OVERLAY", 0.06, 0.08, 0.10, 0.70)
                    disTex:SetAllPoints()
                    reorderDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(self, tip) end
                    end)
                    reorderDis:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
                    local initDis = type(row.disabled) == "function" and row.disabled() or row.disabled
                    if initDis then reorderDis:Show() else reorderDis:Hide() end
                end

                rowWidgets[#rowWidgets + 1] = { type = 'reorder', btn = ddBtn, menu = menu, disOverlay = reorderDis, disCheck = row.disabled }
                curY = curY - DROPDOWN_ROW_H
            end
        end


        if opts.footer and opts.footer.unlockKey then
            local footerY = curY - 10
            local line1 = MakeFont(pf, 12, nil, 0x78/255, 0x7b/255, 0x81/255)
            line1:SetText(EllesmereUI.L("Reposition freely with"))
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
            unlockFS:SetText(EllesmereUI.L("Unlock Mode"))
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
        -- Re-read every get function and update visuals
        pf._refresh = function()
            for _, rw in ipairs(rowWidgets) do
                if rw.type == "slider" then
                    if rw.disOverlay and rw.disCheck then
                        local dis
                        if type(rw.disCheck) == "function" then dis = rw.disCheck() else dis = rw.disCheck end
                        if dis then rw.disOverlay:Show() else rw.disOverlay:Hide() end
                    end
                    if rw.updateVisual and rw.get then rw.updateVisual(rw.get()) end
                elseif rw.type == "toggle" then
                    if rw.disOverlay and rw.disCheck then
                        local dis
                        if type(rw.disCheck) == "function" then dis = rw.disCheck() else dis = rw.disCheck end
                        if dis then rw.disOverlay:Show() else rw.disOverlay:Hide() end
                    end
                    if rw.updateVisual then rw.updateVisual() end
                elseif rw.type == 'colorpicker' then
                    if rw.disCheck then
                        local dis
                        if type(rw.disCheck) == "function" then dis = rw.disCheck() else dis = rw.disCheck end
                        if rw.swatch then rw.swatch:SetAlpha(dis and 0.3 or 1) end
                        if rw.swBlock then if dis then rw.swBlock:Show() else rw.swBlock:Hide() end end
                        if rw.lblBlock then if dis then rw.lblBlock:Show() else rw.lblBlock:Hide() end end
                    end
                    if rw.updateSwatch then rw.updateSwatch() end
                elseif rw.type == 'dropdown' then
                    if rw.disOverlay and rw.disCheck then
                        local dis
                        if type(rw.disCheck) == "function" then dis = rw.disCheck() else dis = rw.disCheck end
                        if dis then rw.disOverlay:Show() else rw.disOverlay:Hide() end
                    end
                    if rw.lbl and rw.get and rw.values then
                        rw.lbl:SetText(EllesmereUI.L(DDText(rw.values[rw.get()]) or tostring(rw.get())))
                        if rw.refresh then rw.refresh() end
                    end
                elseif rw.type == 'input' then
                    if rw.disOverlay and rw.disCheck then
                        local dis
                        if type(rw.disCheck) == "function" then dis = rw.disCheck() else dis = rw.disCheck end
                        if dis then rw.disOverlay:Show() else rw.disOverlay:Hide() end
                    end
                    if rw.box and rw.get and not rw.box:HasFocus() then
                        rw.box:SetText(rw.get())
                    end
                    -- Re-apply save button colour for the current theme
                    if rw.saveBg then
                        rw.saveBg:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 0.85)
                    end
                elseif rw.type == 'segmented' then
                    if rw.disOverlay and rw.disCheck then
                        local dis
                        if type(rw.disCheck) == "function" then dis = rw.disCheck() else dis = rw.disCheck end
                        if dis then rw.disOverlay:Show() else rw.disOverlay:Hide() end
                    end
                    if rw.refresh then rw.refresh() end
                elseif rw.type == 'multiswatch' then
                    if rw.disOverlay and rw.disCheck then
                        local dis
                        if type(rw.disCheck) == "function" then dis = rw.disCheck() else dis = rw.disCheck end
                        if dis then rw.disOverlay:Show() else rw.disOverlay:Hide() end
                    end
                    if rw.updates then
                        for i = 1, #rw.updates do rw.updates[i]() end
                    end
                    if rw.alphaFns then
                        for i = 1, #rw.alphaFns do
                            local a = rw.alphaFns[i]
                            a.sw:SetAlpha(a.fn())
                        end
                    end
                elseif rw.type == 'reorder' then
                    if rw.disOverlay and rw.disCheck then
                        local dis
                        if type(rw.disCheck) == "function" then dis = rw.disCheck() else dis = rw.disCheck end
                        if dis then
                            rw.disOverlay:Show()
                            if rw.menu then rw.menu:Hide() end
                        else
                            rw.disOverlay:Hide()
                        end
                    end
                elseif rw.type == 'reordercheck' then
                    if rw.refresh then rw.refresh() end
                end
            end
        end

        -- True while a dropdown menu opened from inside this popup is shown and moused over. Exposed so external close-logic (e.g. a parent menu driving this popup as a flyout with its own _clickOutside disabled) stays open when a clicked dropdown list extends below the popup's own rect.
        pf._anyDropdownHovered = function()
            for _, rw in ipairs(rowWidgets) do
                if (rw.type == 'dropdown' or rw.type == 'reorder' or rw.type == 'reordercheck') and rw.btn and rw.btn._ddMenu
                   and rw.btn._ddMenu:IsShown() and rw.btn._ddMenu:IsMouseOver() then
                    return true
                end
            end
            return false
        end

        -- Click-outside-to-close; also closes when scrolled out of view
        local wasDown = false
        pf._clickOutside = function(self)
            local down = IsMouseButtonDown("LeftButton")
            if down and not wasDown then
                if not self:IsMouseOver() and not (popupOwner and popupOwner:IsMouseOver()) and not pf._anyDropdownHovered() then
                    self:Hide()
                end
            end
            wasDown = down

            -- Close when the anchor button scrolls out of the visible area
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
            -- Dim the anchor back to cog idle alpha; skipped via noOwnerDim when the anchor isn't a cog (e.g. a preview icon) and must not fade.
            if popupOwner and not opts.noOwnerDim then popupOwner:SetAlpha(0.4) end
            popupOwner = nil
        end)

        -- Close when the main EllesmereUI frame hides
        if EllesmereUI._mainFrame then
            EllesmereUI._mainFrame:HookScript("OnHide", function()
                if pf:IsShown() then pf:Hide() end
            end)
        end

        popupFrame = pf
    end

    -- showFn: toggle popup anchored to a button. Wrapped in a callable table so callers can access showFn._popupFrame.
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
    local SEG_H    = cfg.height or 28
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
        tmpFS:SetText(EllesmereUI.L(cfg.labels[key] or key))
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

    -- Square mode option
    local SQUARE = cfg.square and true or false
    local capW = SQUARE and 0 or SEG_H
    if not SQUARE then
        segWidths[cfg.keys[1]] = math.floor(segWidths[cfg.keys[1]] - capW)
        segWidths[cfg.keys[numKeys]] = math.floor(segWidths[cfg.keys[numKeys]] - capW)
    end
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

        -- Full 1px border on all 4 sides matches MakeBorder's pixel-perfect technique: vertical edges inset by 1px to avoid overlapping corners.
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
        lbl:SetText(EllesmereUI.L(cfg.labels[key] or key))

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
    -- Anchor caps to segment buttons. Raw SetPoint (not PixelUtil) for cap textures to avoid asymmetric pixel rounding that squishes one side.
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

    if SQUARE then
        -- No rounded caps: hide the textures and their click zones outright.
        capLeftFill:Hide();  capLeftBdr:Hide();  capLeftAccent:Hide()
        capRightFill:Hide(); capRightBdr:Hide(); capRightAccent:Hide()
        capLeftBtn:Hide();   capRightBtn:Hide()
    end

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

            -- Checked segments get higher frame level so their border draws on top of the adjacent unchecked segment's border.
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

            -- All 4 borders visible, except (pill mode only): first segment hides its left, last hides its right -- the rounded caps draw those edges. In square mode those outer edges are the box border, kept.
            seg.segTop:Show()
            seg.segBot:Show()
            local isFirst = (idx == 1)
            local isLast  = (idx == #segments)
            if isFirst and not SQUARE then seg.segLeft:Hide() else seg.segLeft:Show() end
            if isLast  and not SQUARE then seg.segRight:Hide() else seg.segRight:Show() end

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

        -- Square mode has no caps; the segment borders above are the whole box.
        if SQUARE then return end

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
--  BuildMultiApplyDropdown -- checkbox popup for selective "Apply to Multiple".
--  Opens a DIALOG-strata popup with checkboxes for each element. The current
--  element is pre-checked and grayed out (non-interactive); all others are
--  checked by default. An "Apply" button at the top applies the setting to all checked elements.
--  opts = {
--      elementKeys   = { "MainBar", "Bar2", ... },
--      elementLabels = { MainBar = "Bar 1", Bar2 = "Bar 2", ... },
--      getCurrentKey = function() return selectedBarKey end,
--      onApply       = function(checkedKeys) ... end,
--  }
--  anchorFrame: frame to anchor the dropdown below
--  flashTargets: optional table or function for PlayWhiteFlash on apply
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

    -- Reset the checked state to all-true on every open. Intentionally NOT carried over between opens: a prior per-operation deselection must never silently persist to another source unit or another sync icon (e.g. a stale exclusion could make a Bar Background sync from Target/Focus silently skip the Player frame).
    _multiApplyCheckedState[cacheKey] = {}
    for _, key in ipairs(keys) do
        _multiApplyCheckedState[cacheKey][key] = true
    end
    local checked = _multiApplyCheckedState[cacheKey]

    -- Options panel is Expressway-locked by design (locale-aware: CJK/Cyrillic get the system glyph font). The user's global font intentionally does not restyle the settings UI.
    local fontPath = EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"

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
    applyLbl:SetText(EllesmereUI.L("Apply"))
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
        lbl:SetText(EllesmereUI.L(labels[key] or key))

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
--  BuildSyncIcon -- label-shift + "Apply to All" subtext pattern.
--  When the setting is desynced across bars, the row label shifts up and an
--  accent-colored "Apply to All" button appears below it; clicking it syncs,
--  hovering it pulses the flash targets' borders. When opts.multiApply is
--  provided, an additional " | Apply to Multiple" link appears next to "Apply
--  to All" that opens a checkbox dropdown for selective application.
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
local SUBTEXT_Y       = -10  -- "Apply to All" vertical offset below center
local ANIM_DUR        = 0.20 -- seconds for slide/fade transition

local function BuildSyncIcon(opts)
    local region = opts.region
    local label  = region and region._label
    if not region or not label then return nil end
    if not opts.isSynced then return nil end

    local ar, ag, ab = EllesmereUI.GetAccentColor()

    -- "Apply to:" prefix label + "All" clickable link
    local applyBtn = CreateFrame("Button", nil, region)
    applyBtn:SetFrameLevel(region:GetFrameLevel() + 4)

    local prefixText = applyBtn:CreateFontString(nil, "OVERLAY")
    prefixText:SetFont(EXPRESSWAY, 11, "")
    prefixText:SetTextColor(1, 1, 1, 0.65)
    prefixText:SetText(EllesmereUI.L("Apply to:"))
    prefixText:SetPoint("LEFT", applyBtn, "LEFT", 0, 0)

    local allBtn = CreateFrame("Button", nil, region)
    allBtn:SetFrameLevel(region:GetFrameLevel() + 4)
    local allText = allBtn:CreateFontString(nil, "OVERLAY")
    allText:SetFont(EXPRESSWAY, 11, "")
    allText:SetTextColor(ar, ag, ab, 0.65)
    allText:SetText(EllesmereUI.L("All"))
    allText:SetPoint("CENTER", allBtn, "CENTER", 0, 0)
    allBtn:SetSize(20, 14)
    allBtn:SetPoint("LEFT", prefixText, "RIGHT", 4, 0)

    allBtn:SetScript("OnEnter", function()
        local r, g, b = EllesmereUI.GetAccentColor()
        allText:SetTextColor(r, g, b, 1)
        if opts.tooltip then ShowWidgetTooltip(allBtn, opts.tooltip, opts.tooltipOpts) end
    end)
    allBtn:SetScript("OnLeave", function()
        local r, g, b = EllesmereUI.GetAccentColor()
        allText:SetTextColor(r, g, b, 0.65)
        if opts.tooltip then HideWidgetTooltip() end
    end)

    -- " | Multiple" link (only when multiApply opts are provided)
    local multiBtn, multiText, sepText
    if opts.multiApply then
        sepText = region:CreateFontString(nil, "OVERLAY")
        sepText:SetFont(EXPRESSWAY, 11, "")
        sepText:SetTextColor(0.45, 0.45, 0.45, 0.7)
        sepText:SetText("|")
        sepText:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)

        multiBtn = CreateFrame("Button", nil, region)
        multiBtn:SetFrameLevel(region:GetFrameLevel() + 4)
        multiText = multiBtn:CreateFontString(nil, "OVERLAY")
        multiText:SetFont(EXPRESSWAY, 11, "")
        multiText:SetTextColor(ar, ag, ab, 0.65)
        multiText:SetText(EllesmereUI.L("Multiple"))
        multiText:SetPoint("CENTER", multiBtn, "CENTER", 0, 0)
        multiBtn:SetSize(50, 14)
        multiBtn:SetPoint("LEFT", sepText, "RIGHT", 4, 0)

        multiBtn:SetScript("OnEnter", function()
            local r, g, b = EllesmereUI.GetAccentColor()
            multiText:SetTextColor(r, g, b, 1)
        end)
        multiBtn:SetScript("OnLeave", function()
            local r, g, b = EllesmereUI.GetAccentColor()
            multiText:SetTextColor(r, g, b, 0.65)
        end)
    end

    -- Size buttons to their text
    applyBtn:SetSize(80, 14)  -- initial estimate, corrected below
    local function ResizeBtn()
        local pw = prefixText:GetStringWidth()
        local ph = prefixText:GetStringHeight()
        if pw and pw > 0 then
            applyBtn:SetSize(pw + 4, ph + 4)
        end
        local aw = allText:GetStringWidth()
        local ah = allText:GetStringHeight()
        if aw and aw > 0 then
            allBtn:SetSize(aw + 4, ah + 4)
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
        -- Force hidden when the parent widget is disabled
        local parentCfg = region._widgetCfg
        if parentCfg and parentCfg.disabled and parentCfg.disabled() then s = 0 end
        -- s: 0 = synced (label centered, subtext hidden), 1 = desynced (label up, subtext visible)
        local labelY = LABEL_Y_NORMAL + s * (LABEL_Y_SHIFTED - LABEL_Y_NORMAL)
        label:ClearAllPoints()
        PP.Point(label, "LEFT", region, "LEFT", labelXOff, labelY)
        applyBtn:SetAlpha(s)
        allBtn:SetAlpha(s)
        if s <= 0 then applyBtn:Hide(); allBtn:Hide() else applyBtn:Show(); allBtn:Show() end
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
    --  Animate state transitions (uses a dedicated frame to avoid conflicting with the pulse OnUpdate on applyBtn)
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
    allBtn:SetScript("OnClick", function()
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
    --  RefreshPage hook: animate when sync state changes. Deferred if a slider is being dragged or color picker
    --  is open, so the label doesn't jitter mid-interaction.
    -- ----------------------------------------------------------------
    EllesmereUI.RegisterWidgetRefresh(function()
        -- Re-color accent in case it changed
        local r, g, b = EllesmereUI.GetAccentColor()
        prefixText:SetTextColor(1, 1, 1, 0.65)
        allText:SetTextColor(r, g, b, 0.65)
        if multiText then multiText:SetTextColor(r, g, b, 0.65) end
        ResizeBtn()


        local synced = opts.isSynced()
        local target = synced and 0 or 1

        -- Slider dragging: allow showing (desynced -> 1) immediately, but defer hiding (synced -> 0) until the drag ends.
        if EllesmereUI._sliderDragging then
            if target == 1 then
                -- Value diverged mid-drag: show right away
                AnimateTo(1)
            else
                -- Values re-converged mid-drag: don't hide yet, defer to drag end
                if not EllesmereUI._deferredDriftChecks then
                    EllesmereUI._deferredDriftChecks = {}
                end
                EllesmereUI._deferredDriftChecks[function()
                    local r2, g2, b2 = EllesmereUI.GetAccentColor()
                    prefixText:SetTextColor(1, 1, 1, 0.65)
                    allText:SetTextColor(r2, g2, b2, 0.65)
                    if multiText then multiText:SetTextColor(r2, g2, b2, 0.65) end
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
                prefixText:SetTextColor(1, 1, 1, 0.65)
                allText:SetTextColor(r2, g2, b2, 0.65)
                if multiText then multiText:SetTextColor(r2, g2, b2, 0.65) end
                ResizeBtn()
                AnimateTo(opts.isSynced() and 0 or 1)
            end] = true
            return
        end

        AnimateTo(target)
    end)

    return applyBtn
end

-- Inline toggle: a small toggle placed inline inside a DualRow half-region,
-- chaining left of the control (slider/dropdown) like the sync icon / cog. Used
-- to gate the row's control (e.g. enable/disable the duration text). The toggle
-- itself is never disabled. opts: region, getValue, setValue, onToggle, sizeRatio.
local function BuildInlineToggle(opts)
    local region = opts.region
    if not region then return nil end
    local toggle, _, tgSnap = BuildToggleControl(region, region:GetFrameLevel() + 5,
        opts.getValue,
        function(v)
            if opts.setValue then opts.setValue(v) end
            if opts.onToggle then opts.onToggle(v) end
        end,
        { sizeRatio = opts.sizeRatio or 0.8 })
    toggle:ClearAllPoints()
    toggle:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
    region._lastInline = toggle
    RegisterWidgetRefresh(tgSnap)
    return toggle
end

-------------------------------------------------------------------------------
--  Less-Common Settings Expander
--  Centralized collapse link for rarely-customized option rows. Page builders wrap those rows in:
--      local expanded
--      expanded, y = EllesmereUI.BuildLessCommonExpander(parent, y,
--          "rfIndicators", "Show Less Common Indicator Options")
--      if expanded then
--          ... build the less-common rows ...
--      end
--      y = EllesmereUI.FinishLessCommonExpander(parent, y,
--          "rfIndicators", "Show Less Common Indicator Options")
--  Expansion is session-only per sectionKey (never saved). The global "Auto Expand Less Common Settings" toggle
--  (EllesmereUIDB.autoExpandLessCommon, Global Settings -> General -> Display) renders everything expanded and
--  suppresses the links entirely. Clicking the link forces RefreshPage(true) to re-run the page builder -- the
--  no-arg fast path only re-reads values and would never reveal the collapsed rows.
-------------------------------------------------------------------------------
local LESS_COMMON_ARROW_DOWN = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
local LESS_COMMON_ARROW_UP   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"

-- Shared link renderer for both expander states. The link always sits at the BOTTOM of its section: collapsed it
-- renders where the hidden rows would start (via BuildLessCommonExpander), expanded it renders below the
-- revealed rows (via FinishLessCommonExpander). Expanded state flips it into the collapse form: up arrows and a
-- "Hide ..." label -- the Hide key is derived from the ENGLISH label before localization so both variants are proper L() lookup keys.
local function BuildLessCommonLink(parent, y, sectionKey, label, expanded)
    local ARROW_SZ, ARROW_GAP = 12, 6
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(22)
    btn:SetPoint("TOP", parent, "TOP", 0, y - 12)
    btn:SetFrameLevel(parent:GetFrameLevel() + 5)
    btn:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")

    local arrowTex = expanded and LESS_COMMON_ARROW_UP or LESS_COMMON_ARROW_DOWN
    local text = expanded and (label:gsub("^Show", "Hide", 1)) or label

    local fs = EllesmereUI.MakeFont(btn, 13, nil, 1, 1, 1)
    fs:SetPoint("LEFT", btn, "LEFT", ARROW_SZ + ARROW_GAP, 0)
    fs:SetText(EllesmereUI.L(text))
    fs:SetAlpha(0.7)

    local leftArrow = btn:CreateTexture(nil, "OVERLAY")
    leftArrow:SetSize(ARROW_SZ, ARROW_SZ)
    leftArrow:SetTexture(arrowTex)
    leftArrow:SetPoint("RIGHT", fs, "LEFT", -ARROW_GAP, 0)
    leftArrow:SetAlpha(0.7)

    local rightArrow = btn:CreateTexture(nil, "OVERLAY")
    rightArrow:SetSize(ARROW_SZ, ARROW_SZ)
    rightArrow:SetTexture(arrowTex)
    rightArrow:SetPoint("LEFT", fs, "RIGHT", ARROW_GAP, 0)
    rightArrow:SetAlpha(0.7)

    btn:SetWidth(math.max((fs:GetStringWidth() or 0) + 2 * (ARROW_SZ + ARROW_GAP) + 8, 120))

    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
    btn:SetScript("OnEnter", function(self)
        fs:SetTextColor(EG.r, EG.g, EG.b); fs:SetAlpha(1)
        leftArrow:SetVertexColor(EG.r, EG.g, EG.b); leftArrow:SetAlpha(1)
        rightArrow:SetVertexColor(EG.r, EG.g, EG.b); rightArrow:SetAlpha(1)
        ShowWidgetTooltip(self, "Shift+Middle Click to always show all settings")
    end)
    btn:SetScript("OnLeave", function()
        fs:SetTextColor(1, 1, 1); fs:SetAlpha(0.7)
        leftArrow:SetVertexColor(1, 1, 1); leftArrow:SetAlpha(0.7)
        rightArrow:SetVertexColor(1, 1, 1); rightArrow:SetAlpha(0.7)
        HideWidgetTooltip()
    end)
    btn:SetScript("OnClick", function(_, button)
        if button == "MiddleButton" then
            -- Shift+Middle Click = enable the global Auto Expand Less Common Settings toggle (Global Settings -> General -> Display). Cached pages were built collapsed, so drop them all before rebuilding.
            if not IsShiftKeyDown() then return end
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.autoExpandLessCommon = true
            HideWidgetTooltip()
            EllesmereUI:InvalidatePageCache()
            EllesmereUI:RefreshPage(true)
            return
        end
        local sess = EllesmereUI._lessCommonExpanded
        if not sess then sess = {}; EllesmereUI._lessCommonExpanded = sess end
        sess[sectionKey] = (not expanded) and true or nil
        EllesmereUI:RefreshPage(true)
    end)

    return y - 40
end

local function BuildLessCommonExpander(parent, y, sectionKey, label)
    -- Hidden search pre-build: always build the wrapped rows so they register in the global search index; no link (the page is never shown).
    if EllesmereUI._prebuilding then return true, y end
    if EllesmereUIDB and EllesmereUIDB.autoExpandLessCommon then return true, y end
    -- Active search (either box): sections render force-expanded with NO link line at all; clearing the search collapses them back. Transient flag -- the session Show/Hide state below is untouched and restores afterwards (see SetLessCommonSearchActive).
    if EllesmereUI._lessCommonSearchActive then return true, y end
    local sess = EllesmereUI._lessCommonExpanded
    if not sess then sess = {}; EllesmereUI._lessCommonExpanded = sess end
    -- Expanded: render nothing here -- the caller builds the rows, then FinishLessCommonExpander places the "Hide ..." link below them.
    if sess[sectionKey] then return true, y end
    return false, BuildLessCommonLink(parent, y, sectionKey, label, false)
end

-- Call after the wrapped rows (safe to call unconditionally: no-ops while the section is collapsed, during the search pre-build, during an active search, or when the global auto-expand toggle is on).
local function FinishLessCommonExpander(parent, y, sectionKey, label)
    if EllesmereUI._prebuilding then return y end
    if EllesmereUIDB and EllesmereUIDB.autoExpandLessCommon then return y end
    if EllesmereUI._lessCommonSearchActive then return y end
    local sess = EllesmereUI._lessCommonExpanded
    if not (sess and sess[sectionKey]) then return y end
    return BuildLessCommonLink(parent, y, sectionKey, label, true)
end

-- Search-driven expansion (both the sidebar global box and the top-bar module box call this with query ~= ""). While active, every less-common section renders expanded with no link; on clear, sections fall back to their session Show/Hide state. Idempotent -- only transitions rebuild, dropping every cache and rebuilding the active page in place.
local function SetLessCommonSearchActive(active)
    active = active and true or false
    if (EllesmereUI._lessCommonSearchActive or false) == active then return end
    EllesmereUI._lessCommonSearchActive = active
    -- With the global auto-expand toggle on, links never render and sections are always expanded: track the flag but skip the rebuild churn.
    if EllesmereUIDB and EllesmereUIDB.autoExpandLessCommon then return end
    EllesmereUI:InvalidatePageCache()
    EllesmereUI:RefreshPage(true)
end

-------------------------------------------------------------------------------
--  BuildInlineSwatches(region, swatches, opts)
--  Inline form of the multiSwatch half: builds the same swatch list (tooltip, hasAlpha, getValue/setValue,
--  onClick override, per-swatch disabled+disabledTooltip, refreshAlpha) to the LEFT of the region's control, so a
--  slider (or any control half) can host its color swatches on the same row. Chains region._lastInline, so a cog
--  button built afterwards lands left of the swatches. opts.disabled/opts.disabledTooltip mirror the row-level disabled state of the multiSwatch form.
-------------------------------------------------------------------------------
local function BuildInlineSwatches(region, swatches, opts)
    opts = opts or {}
    local level = region:GetFrameLevel() + 3
    local anchorTo = region._lastInline or region._control
    for i = #swatches, 1, -1 do
        local sc = swatches[i]
        local swatch, updateSwatch = BuildColorSwatch(region, level, sc.getValue, sc.setValue, sc.hasAlpha)
        PP.Point(swatch, "RIGHT", anchorTo, "LEFT", -8, 0)
        anchorTo = swatch
        region._lastInline = swatch
        if sc.onClick then
            swatch._eabOrigClick = swatch:GetScript("OnClick")
            swatch:SetScript("OnClick", sc.onClick)
        end
        local function SwatchEffectiveDisabled()
            if opts.disabled and opts.disabled() then return true end
            if sc.disabled ~= nil then
                if type(sc.disabled) == "function" then return sc.disabled() end
                return sc.disabled
            end
            return false
        end
        if opts.disabled or sc.disabled then
            local swatchBlock = CreateFrame("Frame", nil, swatch)
            swatchBlock:SetAllPoints()
            swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
            swatchBlock:EnableMouse(true)
            swatchBlock:SetScript("OnEnter", function()
                local src = (sc.disabledTooltip ~= nil) and sc or opts
                local tip = ResolveDisabledTip(src)
                if tip then ShowWidgetTooltip(swatch, tip) end
            end)
            swatchBlock:SetScript("OnLeave", function() HideWidgetTooltip() end)
            local function UpdateSwatchDisabled()
                if SwatchEffectiveDisabled() then
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
        if sc.tooltip then
            swatch:HookScript("OnEnter", function() ShowWidgetTooltip(swatch, sc.tooltip) end)
            swatch:HookScript("OnLeave", function() HideWidgetTooltip() end)
        end
        if sc.refreshAlpha then
            local _sw, _ra = swatch, sc.refreshAlpha
            local function UpdateAlpha()
                if SwatchEffectiveDisabled() then return end
                _sw:SetAlpha(_ra())
            end
            UpdateAlpha()
            RegisterWidgetRefresh(UpdateAlpha)
        end
        RegisterWidgetRefresh(function() updateSwatch() end)
    end
end
EllesmereUI.BuildInlineSwatches = BuildInlineSwatches

-------------------------------------------------------------------------------
--  Hidden-While-Disabled Section Gate
--  For sections whose master toggle HIDES the dependent rows instead of graying them: the page builder simply
--  skips building those rows while the toggle is off, and the toggle's setValue is wrapped with this so flipping it re-runs the page builder to reveal/hide them:
--      { type="toggle", text="Enable Top Name Bar",
--        getValue=...,
--        setValue=EllesmereUI.SectionToggleSetValue(function(v)
--            SSet("tnbEnabled", v); ApplyAll()
--        end) }
-------------------------------------------------------------------------------
local function SectionToggleSetValue(fn)
    return function(v)
        fn(v)
        EllesmereUI:RefreshPage(true)
    end
end

-------------------------------------------------------------------------------
--  Dependent-Row Visibility
--  Row-level version of the section gate: one setting's value hides entire dependent rows instead of graying
--  them. The builder skips the dependent rows behind a plain predicate check, and the TRIGGER setting's setValue
--  is wrapped with this so the page rebuilds only when the predicate actually flips -- ordinary value changes keep whatever refresh the inner setValue already does, with no rebuild flash:
--      -- trigger dropdown:
--      setValue = EllesmereUI.DependentSetValue(
--          function() return SVal("healAbsorbTextMode", "none") ~= "none" end,
--          function(v) SSet("healAbsorbTextMode", v); EllesmereUI:RefreshPage() end),
--
--      -- dependent row below (skip building while hidden):
--      if SVal("healAbsorbTextMode", "none") ~= "none" then
--          ... build the dependent row(s) ...
--      end
-------------------------------------------------------------------------------
local function DependentSetValue(pred, fn)
    return function(v)
        local before = pred() and true or false
        fn(v)
        if (pred() and true or false) ~= before then
            EllesmereUI:RefreshPage(true)
        end
    end
end

EllesmereUI.BuildSliderCore     = BuildSliderCore
EllesmereUI.BuildDropdownControl = BuildDropdownControl
EllesmereUI.BuildColorSwatch    = BuildColorSwatch
EllesmereUI.BuildTrioColorSwatch = BuildTrioColorSwatch
EllesmereUI.BuildToggleControl   = BuildToggleControl
EllesmereUI.BuildInlineToggle    = BuildInlineToggle
EllesmereUI.BuildCheckboxControl = BuildCheckboxControl
EllesmereUI.BuildCogPopup       = BuildCogPopup
EllesmereUI.BuildSyncIcon       = BuildSyncIcon
EllesmereUI.BuildMultiApplyDropdown = BuildMultiApplyDropdown
EllesmereUI.BuildSegmentedControl = BuildSegmentedControl
EllesmereUI.BuildLessCommonExpander   = BuildLessCommonExpander
EllesmereUI.FinishLessCommonExpander  = FinishLessCommonExpander
EllesmereUI.SetLessCommonSearchActive = SetLessCommonSearchActive
EllesmereUI.SectionToggleSetValue     = SectionToggleSetValue
EllesmereUI.DependentSetValue         = DependentSetValue

-------------------------------------------------------------------------------
--  ShowPickMenu -- generic pick-one context menu (right-click "Add To" on
--  manager tiles). Dark popup at the CURSOR with icon+label rows; disabled
--  rows dim and ignore clicks; scrolls past maxHeight; closes on any outside
--  click (fullscreen catcher) or on picking a row. ONE shared frame + row
--  pool, reconfigured per open (menus are rare; frames are never GC'd).
--  opts = { title, fontPath, items = { { key, label, icon, disabled } },
--           onPick(key), width (default 230), maxHeight (default 320) }
-------------------------------------------------------------------------------
function EllesmereUI.ShowPickMenu(anchor, opts)
    opts = opts or {}
    local fontPath = opts.fontPath or "Fonts\\FRIZQT__.TTF"
    local width = opts.width or 230
    local maxH = opts.maxHeight or 320
    local items = opts.items or {}
    local ROW_H = 24

    local menu = EllesmereUI._pickMenu
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent)
        EllesmereUI._pickMenu = menu
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(220)
        menu:EnableMouse(true)
        menu:SetClampedToScreen(true)
        local bg = menu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.067, 0.067, 0.067, 0.98)
        if EllesmereUI.MakeBorder then EllesmereUI.MakeBorder(menu, 1, 1, 1, 0.2) end

        local catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(210)
        catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        catcher:SetScript("OnClick", function() menu:Hide() end)
        catcher:Hide()
        menu._catcher = catcher
        menu:SetScript("OnHide", function(self) self._catcher:Hide() end)
        menu:SetScript("OnShow", function(self) self._catcher:Show() end)

        local title = menu:CreateFontString(nil, "OVERLAY")
        title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -7)
        title:SetTextColor(0.6, 0.6, 0.6)
        menu._title = title

        local scroll = CreateFrame("ScrollFrame", nil, menu)
        scroll:SetClipsChildren(true)
        menu._scroll = scroll
        local child = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(child)
        menu._child = child
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local maxS = math.max(0, menu._child:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(maxS,
                self:GetVerticalScroll() - delta * ROW_H * 2)))
        end)
        menu._rows = {}
    end

    local titleH = 6
    if opts.title then
        menu._title:SetFont(fontPath, 11, "")
        menu._title:SetText(opts.title)
        menu._title:Show()
        titleH = 24
    else
        menu._title:Hide()
    end

    local listH = #items * ROW_H
    local scrollH = math.min(listH, maxH)
    menu:SetSize(width, titleH + scrollH + 8)
    menu._scroll:ClearAllPoints()
    menu._scroll:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -titleH)
    menu._scroll:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, 6)
    menu._child:SetSize(width, math.max(listH, 1))
    menu._scroll:SetVerticalScroll(0)

    local rows = menu._rows
    for i = 1, #items do
        local it = items[i]
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu._child)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", menu._child, "TOPLEFT", 0, -(i - 1) * ROW_H)
            row:SetPoint("RIGHT", menu._child, "RIGHT", 0, 0)
            local hov = row:CreateTexture(nil, "BACKGROUND")
            hov:SetAllPoints()
            hov:SetColorTexture(1, 1, 1, 0)
            row._hov = hov
            local ic = row:CreateTexture(nil, "ARTWORK")
            ic:SetSize(16, 16)
            ic:SetPoint("LEFT", row, "LEFT", 8, 0)
            ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row._icon = ic
            local lbl = row:CreateFontString(nil, "OVERLAY")
            lbl:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
            row._lbl = lbl
            row:SetScript("OnEnter", function(self)
                if not self._disabled then self._hov:SetColorTexture(1, 1, 1, 0.07) end
            end)
            row:SetScript("OnLeave", function(self)
                self._hov:SetColorTexture(1, 1, 1, 0)
            end)
            row:SetScript("OnClick", function(self)
                if self._disabled then return end
                menu:Hide()
                if menu._onPick then menu._onPick(self._key) end
            end)
            rows[i] = row
        end
        row._key = it.key
        row._disabled = it.disabled and true or false
        row._hov:SetColorTexture(1, 1, 1, 0)
        row._lbl:SetFont(fontPath, 12, "")
        row._lbl:SetText(it.label or tostring(it.key))
        row._lbl:ClearAllPoints()
        row._lbl:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        if it.icon then
            row._icon:SetTexture(it.icon)
            row._icon:Show()
            row._lbl:SetPoint("LEFT", row, "LEFT", 30, 0)
        else
            row._icon:Hide()
            row._lbl:SetPoint("LEFT", row, "LEFT", 10, 0)
        end
        if it.disabled then
            row:SetAlpha(0.35)
            row._lbl:SetTextColor(0.7, 0.7, 0.7)
        else
            row:SetAlpha(1)
            row._lbl:SetTextColor(0.9, 0.9, 0.9)
        end
        row:Show()
    end
    for i = #items + 1, #rows do rows[i]:Hide() end
    menu._onPick = opts.onPick

    -- Context-menu convention: open at the cursor (clamped on screen).
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 2, cy / scale + 2)
    menu:Show()
end

-------------------------------------------------------------------------------
--  BuildCursorAnchorRow
--  Shared "Anchor to Cursor" row used by CDM, Resource Bars, and any future section that supports cursor anchoring.
--  opts:
--    W           = widget factory (the W: table from options page)
--    parent      = parent frame
--    getData     = function() -> settings table with anchorTo, anchorPosition, anchorOffsetX, anchorOffsetY
--    onApply     = function() -> rebuild/refresh after value change
--    makeCogBtn  = function(rgn, showFn, anchorTo, iconPath) -> local cog builder
--    disabledFn  = (optional) function() -> true when the whole row is disabled
--    disabledTip = (optional) tooltip string for disabled state
--  Returns: row, height (same as W:DualRow)
-------------------------------------------------------------------------------
local function BuildCursorAnchorRow(opts)
    local W          = opts.W
    local parent     = opts.parent
    local getData    = opts.getData
    local onApply    = opts.onApply
    local makeCogBtn = opts.makeCogBtn

    local row, h = W:DualRow(parent, opts.y,
        { type = "toggle", text = "Anchor to Cursor",
          disabled = opts.disabledFn,
          disabledTooltip = opts.disabledTip,
          getValue = function() return getData().anchorTo == "mouse" end,
          setValue = function(v)
              local old = getData().anchorTo
              local new = v and "mouse" or "none"
              getData().anchorTo = new
              -- Cursor anchor requires a reload to take effect cleanly (Blizzard viewer Layout fights icon positions on live switch).
              local changed = (old == "mouse") ~= (new == "mouse")
              if changed then
                  EllesmereUI:ShowConfirmPopup({
                      title = "Reload Required",
                      message = "Changing cursor anchor requires a UI reload to take effect.",
                      confirmText = "Reload Now",
                      cancelText = "Later",
                      onConfirm = function() ReloadUI() end,
                  })
              else
                  onApply()
              end
              EllesmereUI:RefreshPage(true)
          end },
        { type = "dropdown", text = "Cursor Position",
          values = { left = "Left", right = "Right", top = "Top", bottom = "Bottom" },
          order = { "left", "right", "top", "bottom" },
          disabled = function()
              if opts.disabledFn and opts.disabledFn() then return true end
              return getData().anchorTo ~= "mouse"
          end,
          disabledTooltip = "Anchor to Cursor",
          getValue = function() return getData().anchorPosition or "right" end,
          setValue = function(v)
              getData().anchorPosition = v
              onApply()
          end })

    -- "(Applies on Window Close)" subtitle
    do
        local suffix = row._leftRegion:CreateFontString(nil, "OVERLAY")
        suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
        suffix:SetTextColor(1, 1, 1, 0.35)
        suffix:SetText(EllesmereUI.L("(Applies on Window Close)"))
        local anchorLabel
        for i = 1, row._leftRegion:GetNumRegions() do
            local reg = select(i, row._leftRegion:GetRegions())
            if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Anchor to Cursor" then
                anchorLabel = reg; break
            end
        end
        if anchorLabel then
            suffix:SetPoint("LEFT", anchorLabel, "RIGHT", 5, 0)
        else
            suffix:SetPoint("LEFT", row._leftRegion, "LEFT", 120, 0)
        end
    end

    -- Inline cog: X + Y offsets
    do
        local rightRgn = row._rightRegion
        local _, cogShow = BuildCogPopup({
            title = "Cursor Offset",
            rows = {
                { type = "slider", label = "X Offset", min = -125, max = 125, step = 1,
                  get = function() return getData().anchorOffsetX or 0 end,
                  set = function(v) getData().anchorOffsetX = v; onApply() end },
                { type = "slider", label = "Y Offset", min = -125, max = 125, step = 1,
                  get = function() return getData().anchorOffsetY or 0 end,
                  set = function(v) getData().anchorOffsetY = v; onApply() end },
            },
        })
        makeCogBtn(rightRgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
    end

    return row, h
end
EllesmereUI.BuildCursorAnchorRow = BuildCursorAnchorRow

-------------------------------------------------------------------------------
--  SharedMedia helpers: append LSM fonts/textures to dropdown tables
--  Called from each options file after building its local font/texture tables.
-------------------------------------------------------------------------------

-- Eagerly build the SM font name->path lookup so ResolveFontName works immediately after deferred init (before any options page is opened).
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

-------------------------------------------------------------------------------
--  Shared Visibility Options Checkbox Dropdown
--  Reusable across CDM, Action Bars, Resource Bars, Unit Frames.
--  items = EllesmereUI.VIS_OPT_ITEMS (or a subset)
--  getFn(key) -> bool, setFn(key, bool)
--  onMenuClosed (optional) fires once each time the open menu hides --
--  callers that defer page rebuilds while the menu is open flush there.
--  Returns: ddBtn, refreshFn
-------------------------------------------------------------------------------
-- Tracked Auras popup: the shared INCLUDED/EXCLUDED spell-list editor (announcement-popup chrome; two tri-state
-- columns with per-column Add buttons; adding an ID to one list removes it from the other). Storage-agnostic --
-- callers pass list accessors and an onChanged applier. Used by the nameplate slot filters and the target/focus/boss unit frame debuff filters.
-- opts = {
--     eyebrow / title    (header strings)
--     subtitle           (optional: one dim line under the title; the header
--                         band and the lists shift down to make room)
--     fontPath           (optional; defaults to the options font)
--     includeGet/excludeGet  -> tri-state map { [spellID] = true|false }
--     includePrompt/excludePrompt  (Add Spell ID popup messages)
--     onChanged          (engine reapply, called after every edit)
--     showAll = { label, get, set }        (optional header toggle)
--     copyFrom = { label, choices = { {key=,label=}, ... }, apply(key) }
--                                          (optional header copy row)
--     includeMine = { anyGet } | { mineGet }  (optional: INCLUDED rows carry a MINE tag.
--                                          anyGet(): entries default to your own casts,
--                                          the map holds any-caster OPT-OUTS (boss);
--                                          mineGet(): entries default to any caster,
--                                          the map holds MINE OPT-INS (target/focus))
-- }
-- showAll and copyFrom are mutually exclusive header bands; with neither the list section shifts up and gains the height.
local _trackedAurasDimmer
function EllesmereUI.ShowTrackedAurasPopup(opts)
    local PP = EllesmereUI.PP or EllesmereUI.PanelPP
    local fontPath = opts.fontPath or EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1
    local EG = EllesmereUI.ELLESMERE_GREEN

    if _trackedAurasDimmer then _trackedAurasDimmer:Hide(); _trackedAurasDimmer = nil end

    local dimmer = CreateFrame("Button", "EUITrackedAurasDimmer", UIParent)
    dimmer:SetAllPoints(UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetScale(ppScale)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    local dim = dimmer:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(); dim:SetColorTexture(0, 0, 0, 0.35)
    dimmer:SetScript("OnClick", function()
        dimmer:Hide(); _trackedAurasDimmer = nil
    end)
    _trackedAurasDimmer = dimmer

    local panel = CreateFrame("Frame", "EUITrackedAurasPopup", dimmer)
    panel:SetSize(520, 470)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    panel:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    local pbg = panel:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints(); pbg:SetColorTexture(0.06, 0.08, 0.10, 1)
    -- One-physical-pixel border (announcement-popup chrome): four edge textures, snap disabled, scale-derived thickness.
    do
        local onePhys = 1 / (panel:GetEffectiveScale() or 1)
        local function Edge()
            local t = panel:CreateTexture(nil, "BORDER")
            t:SetColorTexture(1, 1, 1, 0.15)
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0)
            end
            return t
        end
        local eT = Edge(); eT:SetPoint("TOPLEFT", 0, 0); eT:SetPoint("TOPRIGHT", 0, 0); eT:SetHeight(onePhys)
        local eB = Edge(); eB:SetPoint("BOTTOMLEFT", 0, 0); eB:SetPoint("BOTTOMRIGHT", 0, 0); eB:SetHeight(onePhys)
        local eL = Edge(); eL:SetPoint("TOPLEFT", eT, "BOTTOMLEFT"); eL:SetPoint("BOTTOMLEFT", eB, "TOPLEFT"); eL:SetWidth(onePhys)
        local eR = Edge(); eR:SetPoint("TOPRIGHT", eT, "BOTTOMRIGHT"); eR:SetPoint("BOTTOMRIGHT", eB, "TOPRIGHT"); eR:SetWidth(onePhys)
    end
    -- Header: accent eyebrow + large title (announcement style).
    local eyebrow = panel:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(fontPath, 11, "")
    eyebrow:SetPoint("TOP", panel, "TOP", 0, -16)
    eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    eyebrow:SetText(EllesmereUI.L(opts.eyebrow or "TRACKED AURAS"))
    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 20, "")
    title:SetPoint("TOP", panel, "TOP", 0, -32)
    title:SetTextColor(1, 1, 1, 0.95)
    title:SetText(EllesmereUI.L(opts.title or "Tracked Auras"))
    -- Optional one-line description under the title; everything below the
    -- header (band + lists) shifts down by hdrY and the panel grows to match.
    local hdrY = 0
    if opts.subtitle then
        local sub = panel:CreateFontString(nil, "OVERLAY")
        sub:SetFont(fontPath, 12, "")
        sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
        sub:SetWidth(470)
        sub:SetJustifyH("CENTER")
        sub:SetTextColor(1, 1, 1, 0.6)
        sub:SetText(EllesmereUI.L(opts.subtitle))
        hdrY = 18
        panel:SetHeight(470 + hdrY)
    end

    local function ClosePopup()
        dimmer:Hide()
        _trackedAurasDimmer = nil
    end

    -- Escape closes (consume Escape only; other keys propagate so chat/UI shortcuts keep working behind the dimmer).
    panel:EnableKeyboard(true)
    panel:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then ClosePopup() end
    end)

    -- X close (standard popup chrome: borderless eui-close, top right)
    local closeBtn = CreateFrame("Button", nil, panel)
    closeBtn:SetSize(19, 19)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -10)
    local closeTex = closeBtn:CreateTexture(nil, "OVERLAY")
    closeTex:SetAllPoints()
    closeTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
    closeBtn:SetAlpha(0.5)
    closeBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
    closeBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    closeBtn:SetScript("OnClick", ClosePopup)

    local RefreshBoth

    -- Header band: the Show All toggle OR the copy-from row (mutually exclusive by contract; with neither the list section shifts up).
    if opts.showAll then
        local sa = opts.showAll
        local tog = CreateFrame("Button", nil, panel)
        tog:SetSize(170, 20)
        tog:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -68 - hdrY)
        local box = CreateFrame("Frame", nil, tog)
        box:SetSize(16, 16); box:SetPoint("LEFT", tog, "LEFT", 0, 0)
        local bbg = box:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints(); bbg:SetColorTexture(0.12, 0.12, 0.14, 1)
        local bbrd = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6, PP)
        local chk = box:CreateTexture(nil, "ARTWORK")
        PP.SetInside(chk, box, 2, 2)
        chk:SetColorTexture(EG.r, EG.g, EG.b, 1)
        local tl = tog:CreateFontString(nil, "OVERLAY")
        tl:SetFont(fontPath, 13, "")
        tl:SetPoint("LEFT", box, "RIGHT", 8, 0)
        tl:SetTextColor(0.85, 0.85, 0.85)
        tl:SetText(EllesmereUI.L(sa.label or "Show All"))
        local function UpdAll()
            local on = sa.get() == true
            chk:SetShown(on)
            if bbrd and bbrd.SetColor then
                if on then
                    bbrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                else
                    bbrd:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
        end
        tog:SetScript("OnClick", function()
            sa.set(not (sa.get() == true))
            UpdAll()
        end)
        UpdAll()
    elseif opts.copyFrom then
        local cf = opts.copyFrom
        local lbl = panel:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(fontPath, 12, "")
        lbl:SetPoint("LEFT", panel, "TOPLEFT", 24, -80 - hdrY)
        lbl:SetTextColor(0.85, 0.85, 0.85)
        lbl:SetText(EllesmereUI.L(cf.label or "Copy From:"))

        -- Apply (rightmost), source dropdown to its left.
        local applyBtn = CreateFrame("Button", nil, panel)
        applyBtn:SetSize(64, 24)
        applyBtn:SetPoint("RIGHT", panel, "TOPRIGHT", -24, -80 - hdrY)
        local apBg = applyBtn:CreateTexture(nil, "BACKGROUND")
        apBg:SetAllPoints(); apBg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
        local apBrd = EllesmereUI.MakeBorder and EllesmereUI.MakeBorder(applyBtn, EG.r, EG.g, EG.b, 0.35, PP)
        local apLbl = applyBtn:CreateFontString(nil, "OVERLAY")
        apLbl:SetFont(fontPath, 12, "")
        apLbl:SetPoint("CENTER")
        apLbl:SetTextColor(EG.r, EG.g, EG.b, 0.7)
        apLbl:SetText(EllesmereUI.L("Apply"))
        applyBtn:SetScript("OnEnter", function()
            apLbl:SetTextColor(EG.r, EG.g, EG.b, 1)
            if apBrd and apBrd.SetColor then apBrd:SetColor(EG.r, EG.g, EG.b, 0.8) end
        end)
        applyBtn:SetScript("OnLeave", function()
            apLbl:SetTextColor(EG.r, EG.g, EG.b, 0.7)
            if apBrd and apBrd.SetColor then apBrd:SetColor(EG.r, EG.g, EG.b, 0.35) end
        end)

        local ddBtn = CreateFrame("Button", nil, panel)
        ddBtn:SetSize(110, 24)
        ddBtn:SetPoint("RIGHT", applyBtn, "LEFT", -8, 0)
        local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints(); ddBg:SetColorTexture(0.12, 0.12, 0.14, 1)
        EllesmereUI.MakeBorder(ddBtn, 0.4, 0.4, 0.4, 0.6, PP)
        local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
        ddLbl:SetFont(fontPath, 12, "")
        ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 8, 0)
        ddLbl:SetPoint("RIGHT", ddBtn, "RIGHT", -18, 0)
        ddLbl:SetJustifyH("LEFT")
        ddLbl:SetWordWrap(false)
        ddLbl:SetTextColor(1, 1, 1, 0.8)
        ddLbl:SetText(EllesmereUI.L("Select..."))
        if EllesmereUI.MakeDropdownArrow then EllesmereUI.MakeDropdownArrow(ddBtn, 10, PP) end

        local chosen
        local menu = CreateFrame("Frame", nil, panel)
        menu:SetFrameLevel(panel:GetFrameLevel() + 20)
        menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
        menu:SetSize(110, #cf.choices * 22 + 8)
        local mBg = menu:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints(); mBg:SetColorTexture(0.06, 0.08, 0.10, 0.98)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, 0.15, PP)
        menu:Hide()
        for i = 1, #cf.choices do
            local choice = cf.choices[i]
            local mrow = CreateFrame("Button", nil, menu)
            mrow:SetHeight(22)
            mrow:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -4 - (i - 1) * 22)
            mrow:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -4 - (i - 1) * 22)
            local hl = mrow:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0)
            local rl = mrow:CreateFontString(nil, "OVERLAY")
            rl:SetFont(fontPath, 12, "")
            rl:SetPoint("LEFT", mrow, "LEFT", 8, 0)
            rl:SetTextColor(0.85, 0.85, 0.85)
            rl:SetText(EllesmereUI.L(choice.label))
            mrow:SetScript("OnEnter", function() hl:SetColorTexture(1, 1, 1, 0.06) end)
            mrow:SetScript("OnLeave", function() hl:SetColorTexture(1, 1, 1, 0) end)
            mrow:SetScript("OnClick", function()
                chosen = choice.key
                ddLbl:SetText(EllesmereUI.L(choice.label))
                ddLbl:SetTextColor(1, 1, 1, 1)
                menu:Hide()
            end)
        end
        ddBtn:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)

        applyBtn:SetScript("OnClick", function()
            if not chosen then return end
            cf.apply(chosen)
            if RefreshBoth then RefreshBoth() end
        end)
    end

    local hasBand = (opts.showAll or opts.copyFrom) and true or false

    -- The two tri-state spell lists. INCLUDED renders through the caller's include machinery; EXCLUDED rides the caller's exclude machinery. Without a header band the whole section shifts up and the lists gain the reclaimed height.
    local secY = (hasBand and -104 or -68) - hdrY
    local div = panel:CreateTexture(nil, "ARTWORK")
    div:SetHeight(1)
    div:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, secY)
    div:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, secY)
    div:SetColorTexture(1, 1, 1, 0.08)

    -- Vertical divider down the column gutter (panel center), spanning the list section. One PHYSICAL pixel via the panel border's recipe above (snap disabled, scale-derived width): an unsnapped quad exactly 1 physical px wide always rasterizes exactly one pixel column at any UI scale.
    local vdiv = panel:CreateTexture(nil, "ARTWORK")
    vdiv:SetWidth(1 / (panel:GetEffectiveScale() or 1))
    if vdiv.SetSnapToPixelGrid then
        vdiv:SetSnapToPixelGrid(false); vdiv:SetTexelSnappingBias(0)
    end
    vdiv:SetPoint("TOP", panel, "TOP", 0, secY - 8)
    vdiv:SetPoint("BOTTOM", panel, "BOTTOM", 0, 62)
    vdiv:SetColorTexture(1, 1, 1, 0.08)

    local COL_W = 228
    -- withMine: the caller's includeMine descriptor (INCLUDED column only). Two
    -- polarities: anyGet() = entries default to Only My Casts and the map holds
    -- any-caster OPT-OUTS; mineGet() = entries default to any caster and the map
    -- holds MINE OPT-INS. Either way the tag reads "MINE" and lights when the
    -- entry is restricted to your casts.
    local function MakeSpellColumn(x, titleText, promptText, listFn, otherFn, withMine)
        local function ScopeMap()
            if not withMine then return nil end
            if withMine.mineGet then return withMine.mineGet() end
            return withMine.anyGet and withMine.anyGet()
        end
        local function MineOn(id)
            local map = ScopeMap()
            if withMine and withMine.mineGet then
                return map ~= nil and map[id] == true
            end
            return not (map and map[id])
        end
        -- Both polarities toggle by flipping the entry's presence in the map.
        local function ToggleMine(id)
            local map = ScopeMap()
            if not map then return end
            if map[id] then map[id] = nil else map[id] = true end
        end
        -- Section label (options-page section style: small gray caps).
        local colTitle = panel:CreateFontString(nil, "OVERLAY")
        colTitle:SetFont(fontPath, 11, "")
        colTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", x, secY - 16)
        colTitle:SetTextColor(1, 1, 1, 0.45)
        colTitle:SetText(EllesmereUI.L(titleText))

        -- Add Spell ID: the announcement popup's bordered accent button, secondary weight (dim border, brightens on hover).
        local addBtn = CreateFrame("Button", nil, panel)
        addBtn:SetSize(96, 24)
        addBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", x + COL_W - 520, secY - 8)
        local abg = addBtn:CreateTexture(nil, "BACKGROUND")
        abg:SetAllPoints(); abg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
        local abrd = EllesmereUI.MakeBorder and EllesmereUI.MakeBorder(addBtn, EG.r, EG.g, EG.b, 0.35, PP)
        local al = addBtn:CreateFontString(nil, "OVERLAY")
        al:SetFont(fontPath, 12, "")
        al:SetPoint("CENTER")
        al:SetTextColor(EG.r, EG.g, EG.b, 0.7)
        al:SetText(EllesmereUI.L("Add Spell ID"))
        addBtn:SetScript("OnEnter", function()
            al:SetTextColor(EG.r, EG.g, EG.b, 1)
            if abrd and abrd.SetColor then abrd:SetColor(EG.r, EG.g, EG.b, 0.8) end
        end)
        addBtn:SetScript("OnLeave", function()
            al:SetTextColor(EG.r, EG.g, EG.b, 0.7)
            if abrd and abrd.SetColor then abrd:SetColor(EG.r, EG.g, EG.b, 0.35) end
        end)

        local scroll = CreateFrame("ScrollFrame", nil, panel)
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", x, secY - 44)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", x + COL_W - 520, 62)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetWidth(COL_W)
        scroll:SetScrollChild(child)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local maxS = math.max(0, child:GetHeight() - self:GetHeight())
            local cur = self:GetVerticalScroll() - delta * 30
            if cur < 0 then cur = 0 elseif cur > maxS then cur = maxS end
            self:SetVerticalScroll(cur)
        end)

        -- Rows: checkbox (enable/disable the entry without deleting it) + spell icon + name with the spell ID in gray parentheses + delete X. Disabled entries stay stored (false) and dim the whole row; only true entries reach the engine.
        local rows = {}
        local function RefreshList()
            for i = 1, #rows do rows[i]:Hide() end
            local list = listFn() or {}
            local sorted = {}
            for id, v in pairs(list) do
                local nm = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                sorted[#sorted + 1] = { id = id, on = v == true, name = nm or tostring(id) }
            end
            table.sort(sorted, function(a, b) return a.name < b.name end)
            for i = 1, #sorted do
                local row = rows[i]
                if not row then
                    row = CreateFrame("Button", nil, child)
                    row:SetSize(COL_W, 28)
                    row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * 29)
                    row.hl = row:CreateTexture(nil, "BACKGROUND")
                    row.hl:SetAllPoints()
                    row.hl:SetColorTexture(1, 1, 1, 0)
                    -- Checkbox (checkbox-dropdown visuals)
                    row.box = CreateFrame("Frame", nil, row)
                    row.box:SetSize(16, 16)
                    row.box:SetPoint("LEFT", row, "LEFT", 2, 0)
                    local bxbg = row.box:CreateTexture(nil, "BACKGROUND")
                    bxbg:SetAllPoints(); bxbg:SetColorTexture(0.12, 0.12, 0.14, 1)
                    row.boxBrd = EllesmereUI.MakeBorder(row.box, 0.4, 0.4, 0.4, 0.6, PP)
                    row.chk = row.box:CreateTexture(nil, "ARTWORK")
                    PP.SetInside(row.chk, row.box, 2, 2)
                    row.chk:SetColorTexture(EG.r, EG.g, EG.b, 1)
                    row.icon = row:CreateTexture(nil, "ARTWORK")
                    row.icon:SetSize(20, 20)
                    row.icon:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
                    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    row.name = row:CreateFontString(nil, "OVERLAY")
                    row.name:SetFont(fontPath, 13, "")
                    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                    row.name:SetPoint("RIGHT", row, "RIGHT", withMine and -52 or -24, 0)
                    row.name:SetJustifyH("LEFT")
                    row.name:SetWordWrap(false)
                    row.x = CreateFrame("Button", nil, row)
                    row.x:SetSize(14, 14)
                    row.x:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                    row.x:SetFrameLevel(row:GetFrameLevel() + 2)
                    if withMine then
                        -- Only My Casts tag: accent when restricted to your
                        -- casts, gray when the entry shows from any caster.
                        row.mine = CreateFrame("Button", nil, row)
                        row.mine:SetSize(30, 16)
                        row.mine:SetPoint("RIGHT", row.x, "LEFT", -2, 0)
                        row.mine:SetFrameLevel(row:GetFrameLevel() + 2)
                        row.mine.txt = row.mine:CreateFontString(nil, "OVERLAY")
                        row.mine.txt:SetFont(fontPath, 11, "")
                        row.mine.txt:SetPoint("CENTER")
                        row.mine.txt:SetText(EllesmereUI.L("MINE"))
                        row.mine:SetScript("OnClick", function()
                            ToggleMine(row._id)
                            if opts.onChanged then opts.onChanged() end
                            RefreshList()
                        end)
                        row.mine:SetScript("OnEnter", function(self)
                            local tip
                            if MineOn(row._id) then
                                tip = EllesmereUI.L("Showing this aura from your casts only; click for any caster.")
                            else
                                tip = EllesmereUI.L("Showing this aura from any caster; click for your casts only.")
                            end
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end)
                        row.mine:SetScript("OnLeave", function()
                            EllesmereUI.HideWidgetTooltip()
                        end)
                    end
                    row.x.tex = row.x:CreateTexture(nil, "OVERLAY")
                    row.x.tex:SetAllPoints()
                    row.x.tex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
                    row.x:SetAlpha(0.5)
                    row.x:SetScript("OnEnter", function(self)
                        self:SetAlpha(0.9)
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Remove"))
                    end)
                    row.x:SetScript("OnLeave", function(self)
                        self:SetAlpha(0.5)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    row:SetScript("OnEnter", function(self) self.hl:SetColorTexture(1, 1, 1, 0.04) end)
                    row:SetScript("OnLeave", function(self) self.hl:SetColorTexture(1, 1, 1, 0) end)
                    rows[i] = row
                end
                local entry = sorted[i]
                row._id = entry.id
                local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.id)
                row.icon:SetTexture(tex or 134400)
                row.name:SetText(entry.name .. " |cff808080(" .. entry.id .. ")|r")
                -- Checked = entry active; unchecked entries dim.
                row.chk:SetShown(entry.on)
                if row.boxBrd and row.boxBrd.SetColor then
                    if entry.on then
                        row.boxBrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                    else
                        row.boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                    end
                end
                row.icon:SetDesaturated(not entry.on)
                row.icon:SetAlpha(entry.on and 1 or 0.45)
                row.name:SetAlpha(entry.on and 0.9 or 0.45)
                if row.mine then
                    if MineOn(row._id) then
                        -- Restricted to your own casts: accent tag.
                        row.mine.txt:SetTextColor(EG.r, EG.g, EG.b, entry.on and 1 or 0.45)
                    else
                        -- Any caster: dim gray tag.
                        row.mine.txt:SetTextColor(0.6, 0.6, 0.6, entry.on and 0.4 or 0.25)
                    end
                end
                row:SetScript("OnClick", function()
                    local l2 = listFn()
                    if l2 then
                        l2[row._id] = not (l2[row._id] == true)
                        if opts.onChanged then opts.onChanged() end
                        RefreshList()
                    end
                end)
                row.x:SetScript("OnClick", function()
                    local l2 = listFn()
                    if l2 then l2[row._id] = nil end
                    if withMine then
                        local map = ScopeMap()
                        if map then map[row._id] = nil end
                    end
                    if opts.onChanged then opts.onChanged() end
                    RefreshList()
                end)
                row:Show()
            end
            child:SetHeight(math.max(1, #sorted * 29))
        end
        addBtn:SetScript("OnClick", function()
            EllesmereUI:ShowInputPopup({
                title = EllesmereUI.L("Add Spell ID"),
                message = promptText,
                confirmText = EllesmereUI.L("Add"),
                cancelText = EllesmereUI.L("Cancel"),
                onConfirm = function(text)
                    local id = tonumber(text or "")
                    local list = id and listFn()
                    if list then
                        -- One list per spell: adding here removes it from the opposite list.
                        local other = otherFn()
                        if other then other[id] = nil end
                        list[id] = true
                        if opts.onChanged then opts.onChanged() end
                        if RefreshBoth then RefreshBoth() end
                    end
                end,
            })
        end)
        return RefreshList
    end

    local refreshInc = MakeSpellColumn(24, "INCLUDED DEBUFFS",
        EllesmereUI.L(opts.includePrompt or "Enter the spell ID to always show."),
        opts.includeGet,
        opts.excludeGet,
        opts.includeMine)
    local refreshEx = MakeSpellColumn(268, "EXCLUDED DEBUFFS",
        EllesmereUI.L(opts.excludePrompt or "Enter the spell ID to exclude."),
        opts.excludeGet,
        opts.includeGet)
    RefreshBoth = function()
        refreshInc(); refreshEx()
    end

    -- Done (announcement popup's primary action: green border and label, brighten on hover). Everything applies live, so Done = close.
    local doneBtn = CreateFrame("Button", nil, panel)
    doneBtn:SetSize(150, 32)
    doneBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 14)
    local dbg2 = doneBtn:CreateTexture(nil, "BACKGROUND")
    dbg2:SetAllPoints(); dbg2:SetColorTexture(0.06, 0.08, 0.10, 0.92)
    local dbrd = EllesmereUI.MakeBorder and EllesmereUI.MakeBorder(doneBtn, EG.r, EG.g, EG.b, 0.9, PP)
    local dl2 = doneBtn:CreateFontString(nil, "OVERLAY")
    dl2:SetFont(fontPath, 14, "")
    dl2:SetPoint("CENTER")
    dl2:SetText(EllesmereUI.L("Done"))
    dl2:SetTextColor(EG.r, EG.g, EG.b, 0.9)
    doneBtn:SetScript("OnEnter", function()
        dl2:SetTextColor(EG.r, EG.g, EG.b, 1)
        if dbrd and dbrd.SetColor then dbrd:SetColor(EG.r, EG.g, EG.b, 1) end
    end)
    doneBtn:SetScript("OnLeave", function()
        dl2:SetTextColor(EG.r, EG.g, EG.b, 0.9)
        if dbrd and dbrd.SetColor then dbrd:SetColor(EG.r, EG.g, EG.b, 0.9) end
    end)
    doneBtn:SetScript("OnClick", ClosePopup)

    RefreshBoth()
end

-------------------------------------------------------------------------------
-- Spell-ID blacklist editor: small standalone modal (dimmer, click-outside close) listing the current blacklist
-- with per-row remove plus an Add box. Storage-agnostic -- callers pass get/add/remove accessors and an onChanged
-- applier. Reused by the player-frame, Player Aura Bars and Buff Manager buff filter dropdowns ("Edit Blacklist" pinned actions).
function EllesmereUI.ShowSpellBlacklistPopup(opts)
    if EllesmereUI._blacklistPopup then
        EllesmereUI._blacklistPopup:Hide()
        EllesmereUI._blacklistPopup = nil
    end
    opts = opts or {}
    local fontPath = EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
    local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
    local PW, PH = 320, 400

    local dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:SetScript("OnMouseDown", function()
        dimmer:Hide()
        EllesmereUI._blacklistPopup = nil
    end)
    EllesmereUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25):SetAllPoints(dimmer)
    EllesmereUI._blacklistPopup = dimmer

    local popup = CreateFrame("Frame", nil, dimmer)
    popup:SetSize(PW, PH)
    popup:SetPoint("CENTER")
    popup:EnableMouse(true)
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 2)
    if EllesmereUI.GetPopupScale then popup:SetScale(EllesmereUI.GetPopupScale()) end
    EllesmereUI.SolidTex(popup, "BACKGROUND", 13 / 255, 17 / 255, 25 / 255, 0.98):SetAllPoints(popup)
    EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.22)

    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 14, "")
    title:SetPoint("TOP", popup, "TOP", 0, -12)
    title:SetTextColor(1, 1, 1, 0.95)
    title:SetText(EllesmereUI.L(opts.title or "Blacklist"))

    local hint = popup:CreateFontString(nil, "OVERLAY")
    hint:SetFont(fontPath, 11, "")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
    hint:SetWidth(PW - 32)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(1, 1, 1, 0.45)
    hint:SetText(EllesmereUI.L("Blacklisted spells never display."))

    local addBox = CreateFrame("EditBox", nil, popup)
    addBox:SetSize(PW - 24 - 70 - 8, 26)
    addBox:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -58)
    addBox:SetFont(fontPath, 12, "")
    addBox:SetTextColor(1, 1, 1, 0.9)
    addBox:SetAutoFocus(false)
    addBox:SetNumeric(true)
    addBox:SetMaxLetters(9)
    addBox:SetTextInsets(6, 6, 0, 0)
    addBox:SetJustifyH("LEFT")
    EllesmereUI.SolidTex(addBox, "BACKGROUND", 0, 0, 0, 0.4):SetAllPoints(addBox)
    EllesmereUI.MakeBorder(addBox, 1, 1, 1, 0.15)
    local ph = addBox:CreateFontString(nil, "OVERLAY")
    ph:SetFont(fontPath, 11, "")
    ph:SetPoint("LEFT", addBox, "LEFT", 6, 0)
    ph:SetTextColor(0.5, 0.5, 0.5, 0.6)
    ph:SetText(EllesmereUI.L("Spell ID..."))
    addBox:SetScript("OnTextChanged", function(self)
        ph:SetShown(self:GetText() == "")
    end)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addBtn = CreateFrame("Button", nil, popup)
    addBtn:SetSize(70, 26)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
    local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
    addBg:SetAllPoints()
    addBg:SetColorTexture(eg.r, eg.g, eg.b, 0.8)
    local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
    addLbl:SetFont(fontPath, 11, "")
    addLbl:SetPoint("CENTER")
    addLbl:SetTextColor(1, 1, 1)
    addLbl:SetText(EllesmereUI.L("Add"))
    addBtn:SetScript("OnEnter", function() addBg:SetColorTexture(eg.r, eg.g, eg.b, 1) end)
    addBtn:SetScript("OnLeave", function() addBg:SetColorTexture(eg.r, eg.g, eg.b, 0.8) end)

    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -94)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -12, 12)
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(PW - 24)
    child:SetHeight(1)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxS = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(maxS, math.max(0, self:GetVerticalScroll() - delta * 30)))
    end)

    local emptyLbl = child:CreateFontString(nil, "OVERLAY")
    emptyLbl:SetFont(fontPath, 11, "")
    emptyLbl:SetPoint("TOP", child, "TOP", 0, -10)
    emptyLbl:SetTextColor(1, 1, 1, 0.35)
    emptyLbl:SetText(EllesmereUI.L("No blacklisted spells."))

    local rows = {}
    local RebuildList
    RebuildList = function()
        for i = 1, #rows do rows[i]:Hide() end
        local map = (opts.get and opts.get()) or {}
        local ids = {}
        for id in pairs(map) do ids[#ids + 1] = id end
        table.sort(ids)
        local y = 0
        for i = 1, #ids do
            local id = ids[i]
            local row = rows[i]
            if not row then
                row = CreateFrame("Frame", nil, child)
                row:SetSize(PW - 24, 26)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(18, 18)
                row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                row.rm = CreateFrame("Button", nil, row)
                row.rm:SetSize(18, 18)
                row.rm:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                row.rmX = row.rm:CreateFontString(nil, "OVERLAY")
                row.rmX:SetFont(fontPath, 12, "")
                row.rmX:SetPoint("CENTER")
                row.rmX:SetText("X")
                row.rmX:SetTextColor(1, 0.3, 0.3, 0.7)
                row.rm:SetScript("OnEnter", function() row.rmX:SetTextColor(1, 0.3, 0.3, 1) end)
                row.rm:SetScript("OnLeave", function() row.rmX:SetTextColor(1, 0.3, 0.3, 0.7) end)
                row.idText = row:CreateFontString(nil, "OVERLAY")
                row.idText:SetFont(fontPath, 10, "")
                row.idText:SetTextColor(1, 1, 1, 0.35)
                row.idText:SetPoint("RIGHT", row.rm, "LEFT", -6, 0)
                row.name = row:CreateFontString(nil, "OVERLAY")
                row.name:SetFont(fontPath, 12, "")
                row.name:SetTextColor(1, 1, 1, 0.85)
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetPoint("RIGHT", row.idText, "LEFT", -6, 0)
                row.name:SetJustifyH("LEFT")
                row.name:SetWordWrap(false)
                rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
            row.icon:SetTexture((info and info.iconID) or 134400)
            row.name:SetText((info and info.name) or ("Spell " .. tostring(id)))
            row.idText:SetText(tostring(id))
            row.rm:SetScript("OnClick", function()
                if opts.remove then opts.remove(id) end
                if opts.onChanged then opts.onChanged() end
                RebuildList()
            end)
            row:Show()
            y = y - 26
        end
        child:SetHeight(math.max(1, -y))
        emptyLbl:SetShown(#ids == 0)
    end

    local function AddFromBox()
        local id = tonumber(addBox:GetText() or "")
        addBox:SetText("")
        addBox:ClearFocus()
        if not (id and id > 0) then return end
        local map = opts.get and opts.get()
        if map and map[id] then return end
        if opts.add then opts.add(id) end
        if opts.onChanged then opts.onChanged() end
        RebuildList()
    end
    addBtn:SetScript("OnClick", AddFromBox)
    addBox:SetScript("OnEnterPressed", AddFromBox)

    RebuildList()
end

-- Empty-selection warning for a filter dropdown whose selection is allowed
-- to reach "shows nothing" (PAB buff/debuff Filters, RF Debuff Manager base
-- Filters): while hasContentFn() is false, the dropdown carries a red border
-- and a persistent bubble above it (warnText), and the returned closure --
-- meant as the dropdown's onMenuClosed -- pulses the control red twice when
-- the menu closes on an empty selection. hasContentFn must be the surface's
-- REAL render predicate (broad mode / Show lane / extra spells / enchants /
-- fx-forced or claimed categories): anything that still renders must count,
-- so a surface that displays something never warns. Update registers as a
-- widget refresh, so every lane click that triggers a non-force RefreshPage
-- re-evaluates live.
function EllesmereUI.AttachEmptyFilterWarn(rgn, cbDD, warnText, hasContentFn)
    local PP = EllesmereUI.PanelPP

    local bubble = CreateFrame("Frame", nil, rgn)
    bubble:SetFrameLevel(cbDD:GetFrameLevel() + 10)
    local fs = EllesmereUI.MakeFont(bubble, 12, nil, 1, 0.4, 0.4)
    fs:SetPoint("CENTER")
    fs:SetText(warnText)
    PP.Size(bubble, math.ceil(fs:GetStringWidth()) + 16, math.ceil(fs:GetStringHeight()) + 10)
    bubble:SetPoint("BOTTOM", cbDD, "TOP", 0, 5)
    local bg = bubble:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.03, 0.03, 0.95)
    PP.CreateBorder(bubble, 0.85, 0.2, 0.2, 1, 1)
    bubble:Hide()

    local warnBorder = CreateFrame("Frame", nil, cbDD)
    warnBorder:SetAllPoints(cbDD)
    PP.CreateBorder(warnBorder, 0.85, 0.2, 0.2, 1, 1)
    warnBorder:Hide()

    local flash = cbDD:CreateTexture(nil, "OVERLAY", nil, 7)
    flash:SetAllPoints()
    flash:SetColorTexture(0.9, 0.15, 0.15, 0.45)
    flash:SetAlpha(0)
    local ag = flash:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.10); a1:SetOrder(1)
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.45); a2:SetOrder(2)
    -- Two pulses read as a deliberate alert; one reads as a rendering glitch.
    ag:SetLooping("REPEAT")
    local loops = 0
    ag:SetScript("OnPlay", function() loops = 0 end)
    ag:SetScript("OnLoop", function(self)
        loops = loops + 1
        if loops >= 2 then self:Stop() end
    end)

    local function Update()
        local empty = not hasContentFn()
        bubble:SetShown(empty)
        warnBorder:SetShown(empty)
        if not empty and ag:IsPlaying() then ag:Stop() end
    end
    Update()
    EllesmereUI.RegisterWidgetRefresh(Update)
    return function()
        Update()
        if not hasContentFn() then ag:Restart() end
    end
end

function EllesmereUI.BuildVisOptsCBDropdown(parentFrame, ddW, fLevel, items, getFn, setFn, onChanged, maxVisibleItems, searchable, closeButton, onMenuClosed, opts)
    local PP = EllesmereUI.PP or EllesmereUI.PanelPP
    opts = opts or {}
    -- Opt-in dynamic items: pass a FUNCTION returning the items array and it re-evaluates on every menu OPEN (the menu rebuilds), so lists that depend on other settings never go stale. A table stays static.
    local itemsFn
    if type(items) == "function" then
        itemsFn = items
        items = itemsFn() or {}
    end
    local ddBtn = CreateFrame("Button", nil, parentFrame)
    PP.Size(ddBtn, ddW, 30)
    ddBtn:SetFrameLevel(fLevel)
    local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints()
    ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
    local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
    local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
    -- Options panel is Expressway-locked by design (locale-aware: CJK/Cyrillic get the system glyph font). The user's global font intentionally does not restyle the settings UI.
    local fontPath = EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
    ddLbl:SetFont(fontPath, 13, "")
    ddLbl:SetTextColor(1, 1, 1, EllesmereUI.DD_TXT_A)
    ddLbl:SetJustifyH("LEFT")
    ddLbl:SetWordWrap(false)
    ddLbl:SetMaxLines(1)
    ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
    local arrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, PP)
    ddLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

    local menu
    local function SummaryLabel()
        local names = {}
        local total = 0
        local hiddenCount = 0
        for _, item in ipairs(items) do
            -- isModifier rows (the Visibility match toggle) are not conditions: excluded
            -- from the summary and from the "All" shortcut.
            if not item.isHeader and not item.isTopAction and not item.isModifier then
                total = total + 1
                if getFn(item.key) then names[#names + 1] = EllesmereUI.L(item.label) end
                -- Dual-lane rows: the hide lane reads through getFn(key, true).
                if item.dual and getFn(item.key, true) then hiddenCount = hiddenCount + 1 end
            end
        end
        local base
        -- opts.emptyLabel: the unified Visibility row reads "Always" with no show lane
        -- checked (an unconstrained element still shows), never "None".
        -- opts.separatorFn lets a modifier row rename the join, so the summary reads
        -- the way the conditions actually combine.
        local sep = opts.separatorFn and opts.separatorFn() or ", "
        if #names == 0 then base = opts.emptyLabel and EllesmereUI.L(opts.emptyLabel) or EllesmereUI.L("None")
        elseif #names == total then base = EllesmereUI.L("All")
        else base = table.concat(names, sep) end
        if hiddenCount > 0 then base = base .. " (-" .. hiddenCount .. ")" end
        return base
    end
    local function UpdateLabel()
        ddLbl:SetText(SummaryLabel())
    end
    UpdateLabel()

    local function EnsureMenu()
        if menu then return end
        local ITEM_H = 28
        local HDR_H = 22
        -- Opt-in top-action rows (item.isTopAction with label + onClick): accent clickable entries pinned ABOVE the search box with a divider under the group -- the "Custom Spell ID at the top" pattern from the CDM spell pickers. Excluded from the scroll list, the checkable count, and the summary label.
        local topActions = {}
        -- Top-action locked tints refresh in the same sweeps as _allRows. They can't JOIN _allRows: the search relayout repositions every frame in that list, and top actions live above the search box.
        local _taTints = {}
        for _, item in ipairs(items) do
            if item.isTopAction then topActions[#topActions + 1] = item end
        end
        local TOP_H = (#topActions > 0) and (#topActions * ITEM_H + 7) or 0
        local checkableCount = 0
        local contentH = 8
        for _, item in ipairs(items) do
            if item.isTopAction then -- rendered above the search box
            elseif item.isHeader then contentH = contentH + HDR_H
            else contentH = contentH + ITEM_H; checkableCount = checkableCount + 1 end
        end
        local SEARCH_H = searchable and 26 or 0
        local CLOSE_BTN_H = closeButton and (6 + 26 + 6) or 0
        contentH = contentH + CLOSE_BTN_H
        local needsScroll = maxVisibleItems and checkableCount > maxVisibleItems
        -- +2 accounts for scroll frame 1px top + 1px bottom insets so non-scrolling menus don't scroll
        local menuH = (needsScroll and (4 + maxVisibleItems * ITEM_H + 4 + CLOSE_BTN_H) or (contentH + 4)) + SEARCH_H + TOP_H
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(200)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetSize(ddW, menuH)
        menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
        menu:Hide()
        local mBg = menu:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints()
        mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA or 0.92)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
        local ppScale = EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale() or 1
        menu:SetScale(ppScale)

        -- Top-action rows above the search box, divider under the group.
        if #topActions > 0 then
            local ay = -4
            for i = 1, #topActions do
                local item = topActions[i]
                local row = CreateFrame("Button", nil, menu)
                row:SetHeight(ITEM_H)
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, ay)
                row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, ay)
                row:SetFrameLevel(menu:GetFrameLevel() + 2)
                local lbl = row:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(fontPath, 13, "")
                lbl:SetTextColor(EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b, 0.8)
                lbl:SetPoint("LEFT", row, "LEFT", 10, 0)
                lbl:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                lbl:SetJustifyH("LEFT")
                lbl:SetWordWrap(false)
                lbl:SetMaxLines(1)
                lbl:SetText(EllesmereUI.L(item.label))
                local hl = row:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0)
                -- Opt-in locked state (item.lockedFn + item.lockedTooltip): evaluated LIVE on hover/click (checkbox toggles can flip it while the menu is open), plus once at build for the initial tint.
                local function TALocked()
                    return item.lockedFn and item.lockedFn() or false
                end
                local function TATint()
                    if TALocked() then
                        lbl:SetTextColor(1, 1, 1, 0.3)
                    else
                        lbl:SetTextColor(EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b, 0.8)
                    end
                end
                TATint()
                _taTints[#_taTints + 1] = TATint
                row:SetScript("OnEnter", function()
                    TATint()
                    if TALocked() then
                        local tip = item.lockedTooltip
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(row, type(tip) == "function" and tip() or tip)
                        end
                        return
                    end
                    hl:SetColorTexture(1, 1, 1, 0.06)
                end)
                row:SetScript("OnLeave", function()
                    hl:SetColorTexture(1, 1, 1, 0)
                    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                    TATint()
                end)
                row:SetScript("OnClick", function()
                    if TALocked() then return end
                    menu:Hide()
                    if item.onClick then item.onClick() end
                end)
                ay = ay - ITEM_H
            end
            local divider = menu:CreateTexture(nil, "ARTWORK")
            divider:SetHeight(1)
            divider:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, ay - 3)
            divider:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -10, ay - 3)
            divider:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        end

        -- Search box (optional)
        local searchEdit, searchPlaceholder
        if searchable then
            searchEdit = CreateFrame("EditBox", nil, menu)
            searchEdit:SetSize(ddW - 16, SEARCH_H)
            searchEdit:SetPoint("TOP", menu, "TOP", 0, -4 - TOP_H)
            searchEdit:SetFrameLevel(menu:GetFrameLevel() + 3)
            searchEdit:SetFont(fontPath, 11, "")
            searchEdit:SetTextColor(1, 1, 1, 0.9)
            searchEdit:SetJustifyH("LEFT")
            searchEdit:SetAutoFocus(false)
            searchEdit:SetMaxLetters(30)
            searchEdit:SetTextInsets(4, 4, 0, 0)
            local sBg = searchEdit:CreateTexture(nil, "BACKGROUND")
            sBg:SetAllPoints()
            sBg:SetColorTexture(0, 0, 0, 0.4)
            searchPlaceholder = searchEdit:CreateFontString(nil, "OVERLAY")
            searchPlaceholder:SetFont(fontPath, 11, "")
            searchPlaceholder:SetTextColor(0.5, 0.5, 0.5, 0.6)
            searchPlaceholder:SetPoint("LEFT", searchEdit, "LEFT", 4, 0)
            searchPlaceholder:SetText(EllesmereUI.L("Search..."))
            searchEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        end

        -- Scroll frame for items
        local sf = CreateFrame("ScrollFrame", nil, menu)
        local sfTop = -((SEARCH_H > 0 and (SEARCH_H + 8) or 1) + TOP_H)
        sf:SetPoint("TOPLEFT", 1, sfTop)
        sf:SetPoint("BOTTOMRIGHT", -1, 1)
        sf:EnableMouseWheel(true)
        local child = CreateFrame("Frame", nil, sf)
        child:SetWidth(ddW - 2)
        child:SetHeight(contentH)
        sf:SetScrollChild(child)
        -- Thin scrollbar track (4px, right side, matching standard dropdown)
        local cbTrack = CreateFrame("Frame", nil, sf)
        cbTrack:SetWidth(4)
        cbTrack:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -4, -4)
        cbTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -4, 4)
        cbTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
        local cbTrackBg = cbTrack:CreateTexture(nil, "BACKGROUND")
        cbTrackBg:SetAllPoints()
        cbTrackBg:SetColorTexture(1, 1, 1, 0.02)

        local cbThumb = CreateFrame("Button", nil, cbTrack)
        cbThumb:SetWidth(4)
        cbThumb:SetFrameLevel(cbTrack:GetFrameLevel() + 1)
        cbThumb:EnableMouse(true)
        cbThumb:RegisterForDrag("LeftButton")
        local cbThumbBg = cbThumb:CreateTexture(nil, "ARTWORK")
        cbThumbBg:SetAllPoints()
        cbThumbBg:SetColorTexture(1, 1, 1, 0.27)

        local function SafeMaxScroll()
            return math.max(0, child:GetHeight() - sf:GetHeight())
        end

        local function UpdateCBThumb()
            local maxScroll = SafeMaxScroll()
            if maxScroll <= 0 then cbTrack:Hide(); return end
            cbTrack:Show()
            local trackH = cbTrack:GetHeight()
            local visH = sf:GetHeight()
            local ratio = visH / (visH + maxScroll)
            local thumbH = math.max(20, trackH * ratio)
            cbThumb:SetHeight(thumbH)
            local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
            local maxTravel = trackH - thumbH
            cbThumb:ClearAllPoints()
            cbThumb:SetPoint("TOP", cbTrack, "TOP", 0, -(scrollRatio * maxTravel))
        end

        -- Thumb drag
        cbThumb:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
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
                local trackH = cbTrack:GetHeight()
                local maxTravel = trackH - self2:GetHeight()
                if maxTravel <= 0 then return end
                local maxScroll = SafeMaxScroll()
                local newScroll = math.max(0, math.min(maxScroll,
                    dragStartScroll + (deltaY / maxTravel) * maxScroll))
                sf:SetVerticalScroll(newScroll)
                UpdateCBThumb()
            end)
        end)
        cbThumb:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return end
            self:SetScript("OnUpdate", nil)
        end)

        sf:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = SafeMaxScroll()
            if maxScroll <= 0 then return end
            local cur = self:GetVerticalScroll()
            self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * ITEM_H)))
            UpdateCBThumb()
        end)
        local itemParent = child

        local yOff = -4
        local _allRows = {}  -- { frame, isHeader, label(string), height }
        for _, item in ipairs(items) do
            -- Top-action items render above the search box, never here.
            if item.isTopAction then -- luacheck: ignore (intentional empty)
            -- Header/divider items: non-interactive label
            elseif item.isHeader then
                local hdrH = 22
                local hdr = CreateFrame("Frame", nil, itemParent)
                hdr:SetHeight(hdrH)
                hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 1, yOff)
                hdr:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, yOff)
                hdr:SetFrameLevel(menu:GetFrameLevel() + 2)
                local hdrLbl = hdr:CreateFontString(nil, "OVERLAY")
                hdrLbl:SetFont(fontPath, 10, "")
                hdrLbl:SetTextColor(0.5, 0.5, 0.5, 1)
                hdrLbl:SetPoint("LEFT", hdr, "LEFT", 10, 0)
                hdrLbl:SetJustifyH("LEFT")
                hdrLbl:SetText(EllesmereUI.L(item.label))
                local hdrLine = hdr:CreateTexture(nil, "ARTWORK")
                hdrLine:SetHeight(1)
                hdrLine:SetPoint("LEFT", hdrLbl, "RIGHT", 6, 0)
                hdrLine:SetColorTexture(0.3, 0.3, 0.3, 0.5)
                -- Opt-in right caption (item.rightLabel): labels the hide-lane column on dual menus.
                if item.rightLabel then
                    local hdrR = hdr:CreateFontString(nil, "OVERLAY")
                    hdrR:SetFont(fontPath, 10, "")
                    hdrR:SetTextColor(0.5, 0.5, 0.5, 1)
                    hdrR:SetPoint("RIGHT", hdr, "RIGHT", -10, 0)
                    hdrR:SetJustifyH("RIGHT")
                    hdrR:SetText(EllesmereUI.L(item.rightLabel))
                    hdrLine:SetPoint("RIGHT", hdrR, "LEFT", -6, 0)
                else
                    hdrLine:SetPoint("RIGHT", hdr, "RIGHT", -10, 0)
                end
                if item.tooltip then
                    hdr:EnableMouse(true)
                    hdr:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(hdr, item.tooltip)
                    end)
                    hdr:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end
                _allRows[#_allRows + 1] = { frame = hdr, isHeader = true, label = item.label, height = hdrH }
                yOff = yOff - hdrH
            elseif item.isAction then
                -- Action item: clickable text, no checkbox (for "All Specs", "All Healers", etc.)
                local row = CreateFrame("Button", nil, itemParent)
                row:SetHeight(ITEM_H)
                row:SetPoint("TOPLEFT", child, "TOPLEFT", 1, yOff)
                row:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, yOff)
                row:SetFrameLevel(menu:GetFrameLevel() + 2)
                local lbl = row:CreateFontString(nil, "OVERLAY")
                lbl:SetFont(fontPath, 13, "")
                lbl:SetTextColor(EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b, 0.8)
                lbl:SetPoint("LEFT", row, "LEFT", 10, 0)
                lbl:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                lbl:SetJustifyH("LEFT")
                lbl:SetWordWrap(false)
                lbl:SetMaxLines(1)
                lbl:SetText(EllesmereUI.L(item.labelFn and item.labelFn() or item.label))
                local function UpdateActionLabel()
                    if item.labelFn then lbl:SetText(EllesmereUI.L(item.labelFn())) end
                end
                row._updateActionLabel = UpdateActionLabel
                local hl = row:CreateTexture(nil, "ARTWORK")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0)
                local EG_r, EG_g, EG_b = EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b
                local function UpdateActionLocked()
                    local isLocked = item.lockedFn and item.lockedFn()
                    if isLocked then
                        lbl:SetTextColor(0.4, 0.4, 0.4, 0.4)
                        row:EnableMouse(false)
                    else
                        lbl:SetTextColor(EG_r, EG_g, EG_b, 0.8)
                        row:EnableMouse(true)
                    end
                end
                row._updateLocked = UpdateActionLocked
                UpdateActionLocked()
                row:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 1, 1); hl:SetColorTexture(1, 1, 1, 0.04) end)
                row:SetScript("OnLeave", function() UpdateActionLocked(); hl:SetColorTexture(1, 1, 1, 0) end)
                row:SetScript("OnClick", function()
                    if item.lockedFn and item.lockedFn() then return end
                    setFn(item.key, true)
                    -- Refresh all checkbox visuals + dynamic action labels
                    for _, r in ipairs(_allRows) do
                        if r.frame._updateCheck then r.frame._updateCheck() end
                        if r.frame._updateActionLabel then r.frame._updateActionLabel() end
                        if r.frame._updateLocked then r.frame._updateLocked() end
                    end
                    for i = 1, #_taTints do _taTints[i]() end
                    UpdateLabel()
                end)
                _allRows[#_allRows + 1] = { frame = row, isHeader = false, isAction = true, label = item.label, height = ITEM_H }
                yOff = yOff - ITEM_H
            else

            local row = CreateFrame("Button", nil, itemParent)
            row:SetHeight(ITEM_H)
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 1, yOff)
            row:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, yOff)
            row:SetFrameLevel(menu:GetFrameLevel() + 2)
            -- Opt-in plain rows (item.noCheck): the identical row minus the checkbox -- the regular-dropdown look for select-style pickers. Click still routes setFn(key, not getFn(key)), so a picker whose getFn is constant-false always selects with true.
            local box, boxBrd, chk
            if not item.noCheck then
                box = CreateFrame("Frame", nil, row)
                box:SetSize(16, 16)
                box:SetPoint("LEFT", row, "LEFT", 10, 0)
                local boxBg = box:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                boxBrd = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6, PP)
                chk = box:CreateTexture(nil, "ARTWORK")
                PP.SetInside(chk, box, 2, 2)
                chk:SetColorTexture(EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b, 1)
                chk:SetSnapToPixelGrid(false)
            end
            -- Optional icon (spell icon etc.) between checkbox and label
            local lblAnchor = box
            if item.icon then
                local icoSz = item.iconSize or (ITEM_H - 6)
                local ico = row:CreateTexture(nil, "ARTWORK")
                ico:SetSize(icoSz, icoSz)
                if box then
                    ico:SetPoint("LEFT", box, "RIGHT", 6, 0)
                else
                    ico:SetPoint("LEFT", row, "LEFT", 10, 0)
                end
                ico:SetTexture(item.icon)
                ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                lblAnchor = ico
            end
            -- Modifier rows rest in the accent only while active; read live, since a
            -- sibling's click flips the checked state (UpdateCheck runs on every row).
            local function RestColor()
                if item.isModifier and getFn(item.key) then
                    return EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b
                end
                return 0.75, 0.75, 0.75
            end
            local lbl = row:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(fontPath, 13, "")
            lbl:SetTextColor(RestColor())
            if lblAnchor then
                lbl:SetPoint("LEFT", lblAnchor, "RIGHT", item.icon and 6 or 8, 0)
            else
                lbl:SetPoint("LEFT", row, "LEFT", 10, 0)
            end
            lbl:SetPoint("RIGHT", row, "RIGHT", (item.dual and not item.noCheck) and -32 or -10, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
            lbl:SetMaxLines(1)
            lbl:SetText(EllesmereUI.L(item.label))
            local hl = row:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0)
            -- Opt-in dual-lane rows (item.dual): a second right-aligned box is the HIDE lane.
            -- Lane state reads getFn(key, true) and writes setFn(key, v, true); the show lane
            -- keeps the plain getFn(key)/setFn(key, v) contract, so single-lane callers are
            -- untouched. item.showLockedFn dims the show lane; while it is locked, row clicks
            -- fall through to the hide lane (broad "All" modes already show everything).
            local negBox, negBrd, negChk
            if item.dual and not item.noCheck then
                negBox = CreateFrame("Button", nil, row)
                negBox:SetSize(16, 16)
                negBox:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                negBox:SetFrameLevel(row:GetFrameLevel() + 1)
                local negBg = negBox:CreateTexture(nil, "BACKGROUND")
                negBg:SetAllPoints()
                negBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                negBrd = EllesmereUI.MakeBorder(negBox, 0.4, 0.4, 0.4, 0.6, PP)
                negChk = negBox:CreateTexture(nil, "ARTWORK")
                PP.SetInside(negChk, negBox, 2, 2)
                negChk:SetColorTexture(0.85, 0.3, 0.3, 1)
                negChk:SetSnapToPixelGrid(false)
            end
            local function ShowLaneLocked()
                return item.showLockedFn and item.showLockedFn() or false
            end
            local function UpdateCheck()
                if chk then
                    if getFn(item.key) then
                        chk:Show()
                        boxBrd:SetColor(EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b, 0.8)
                    else
                        chk:Hide()
                        boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                    end
                    if box and item.dual then
                        local laneLocked = ShowLaneLocked()
                        box:SetAlpha(laneLocked and 0.3 or 1)
                        -- Mouse only while locked AND the item explains the
                        -- dim (item.showLockedTooltip): the disabled box then
                        -- swallows its own hover for the tooltip, and clicks,
                        -- like any disabled control. Unlocked, the box goes
                        -- mouse-inert again so the ROW keeps every click.
                        box:EnableMouse((laneLocked and item.showLockedTooltip) and true or false)
                    end
                end
                if negChk then
                    if getFn(item.key, true) then
                        negChk:Show()
                        negBrd:SetColor(0.85, 0.3, 0.3, 0.8)
                    else
                        negChk:Hide()
                        negBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                    end
                end
                -- Radio partners refresh each other, so this also runs on the hovered row;
                -- repainting that one would drop its hover white until the mouse re-enters.
                if item.isModifier and not row._isLocked and not row:IsMouseOver() then
                    lbl:SetTextColor(RestColor())
                end
            end
            UpdateCheck()
            row._updateCheck = UpdateCheck
            row:SetScript("OnEnter", function()
                if row._isLocked then
                    -- Locked rows keep the gray look (no highlight); if the item explains its lock, show that instead of the normal tooltip.
                    local lt = item.lockedTooltip
                    if type(lt) == "function" then lt = lt() end
                    if lt then
                        EllesmereUI.ShowWidgetTooltip(row, lt)
                    end
                    return
                end
                lbl:SetTextColor(1, 1, 1, 1)
                hl:SetColorTexture(1, 1, 1, 0.04)
                local tip = item.tooltip
                if type(tip) == "function" then tip = tip() end
                if tip then
                    EllesmereUI.ShowWidgetTooltip(row, tip)
                end
            end)
            row:SetScript("OnLeave", function()
                if row._isLocked then
                    if item.lockedTooltip then
                        EllesmereUI.HideWidgetTooltip()
                    end
                    return
                end
                lbl:SetTextColor(RestColor())
                hl:SetColorTexture(1, 1, 1, 0)
                if item.tooltip then
                    EllesmereUI.HideWidgetTooltip()
                end
            end)
            local function UpdateLocked()
                local isLocked = item.locked or (item.lockedFn and item.lockedFn())
                -- Mouse stays enabled so locked rows can explain themselves on hover; clicks are guarded independently in OnClick.
                row._isLocked = isLocked and true or false
                if isLocked then
                    lbl:SetTextColor(0.4, 0.4, 0.4, 0.5)
                else
                    lbl:SetTextColor(RestColor())
                end
            end
            row._updateLocked = UpdateLocked
            UpdateLocked()
            local function AfterToggle()
                UpdateLabel()
                -- Refresh checkbox visuals + dynamic action labels, so items whose checked state depends on others (e.g. "Always" in crosshair) update live. Locked visuals refresh too, so rows whose lockedFn depends on the current selection never show a stale gray/active state.
                for _, r in ipairs(_allRows) do
                    if r.frame._updateCheck then r.frame._updateCheck() end
                    if r.frame._updateActionLabel then r.frame._updateActionLabel() end
                    if r.frame._updateLocked then r.frame._updateLocked() end
                end
                for i = 1, #_taTints do _taTints[i]() end
                if onChanged then
                    -- Anchor menu to absolute screen position BEFORE callback so a page rebuild (which destroys
                    -- ddBtn) can't shift us. GetCenter and SetPoint offsets are both in the menu's own coordinate
                    -- space, so the values pass through unscaled -- scaling them by effective-scale ratios made
                    -- the menu creep toward the bottom-left on every click when the options panel scale differs from UIParent's.
                    local cx, cy = menu:GetCenter()
                    menu:ClearAllPoints()
                    menu:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
                    onChanged()
                end
            end
            row:SetScript("OnClick", function()
                if item.locked or (item.lockedFn and item.lockedFn()) then return end
                if negBox and ShowLaneLocked() then
                    setFn(item.key, not getFn(item.key, true), true)
                else
                    setFn(item.key, not getFn(item.key))
                end
                AfterToggle()
            end)
            if negBox then
                negBox:SetScript("OnClick", function()
                    if item.locked or (item.lockedFn and item.lockedFn()) then return end
                    setFn(item.key, not getFn(item.key, true), true)
                    AfterToggle()
                end)
                negBox:SetScript("OnEnter", function()
                    if row._isLocked then return end
                    lbl:SetTextColor(1, 1, 1, 1)
                    hl:SetColorTexture(1, 1, 1, 0.04)
                    local hlt = opts.hideLaneTooltip
                    if type(hlt) == "function" then hlt = hlt() end
                    EllesmereUI.ShowWidgetTooltip(negBox,
                        hlt and EllesmereUI.L(hlt)
                        or EllesmereUI.L("Hide these instead of showing them"))
                end)
                negBox:SetScript("OnLeave", function()
                    if not row._isLocked then lbl:SetTextColor(RestColor()) end
                    hl:SetColorTexture(1, 1, 1, 0)
                    EllesmereUI.HideWidgetTooltip()
                end)
                -- The SHOW box mirrors the hide box's self-explanation, but
                -- only while a broad mode locks the lane: UpdateCheck enables
                -- its mouse exactly then, so these scripts never fire for an
                -- active lane and row clicks stay untouched.
                if box then
                    box:SetScript("OnEnter", function()
                        lbl:SetTextColor(1, 1, 1, 1)
                        hl:SetColorTexture(1, 1, 1, 0.04)
                        local tt = item.showLockedTooltip
                        if type(tt) == "function" then tt = tt() end
                        if tt then EllesmereUI.ShowWidgetTooltip(box, tt) end
                    end)
                    box:SetScript("OnLeave", function()
                        if not row._isLocked then lbl:SetTextColor(RestColor()) end
                        hl:SetColorTexture(1, 1, 1, 0)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end
            end
            _allRows[#_allRows + 1] = { frame = row, isHeader = false, label = item.label, height = ITEM_H }
            yOff = yOff - ITEM_H

            end -- isHeader else
        end

        -- Close button at bottom of dropdown (optional)
        if closeButton then
            local CLOSE_H = 26
            local closePad = 6
            yOff = yOff - closePad
            local closeBtn = CreateFrame("Button", nil, itemParent)
            closeBtn:SetHeight(CLOSE_H)
            local closeBtnW = math.floor((ddW - 2) * 0.75)
            closeBtn:SetWidth(closeBtnW)
            closeBtn:SetPoint("TOP", child, "TOPLEFT", (ddW - 2) / 2, yOff)
            closeBtn:SetFrameLevel(menu:GetFrameLevel() + 3)
            local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
            closeBg:SetAllPoints()
            local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            closeBg:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
            local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY")
            closeLbl:SetFont(fontPath, 12, "")
            closeLbl:SetPoint("CENTER")
            closeLbl:SetText(EllesmereUI.L(type(closeButton) == "string" and closeButton or "Okay"))
            closeLbl:SetTextColor(1, 1, 1, 1)
            closeBtn:SetScript("OnClick", function() menu:Hide() end)
            closeBtn:SetScript("OnEnter", function() closeBg:SetColorTexture(EG.r, EG.g, EG.b, 1) end)
            closeBtn:SetScript("OnLeave", function() closeBg:SetColorTexture(EG.r, EG.g, EG.b, 0.85) end)
            yOff = yOff - CLOSE_H - closePad
        end

        child:SetHeight(math.max(1, math.abs(yOff)))

        -- Wire search filtering
        if searchEdit then
            searchEdit:SetScript("OnTextChanged", function(self)
                local t = strlower(strtrim(self:GetText()))
                searchPlaceholder:SetShown(t == "")
                local visY = -4
                local lastHdr = nil
                local lastHdrY = 0
                local hdrHasVisible = false
                for _, r in ipairs(_allRows) do
                    if r.isHeader then
                        -- Defer header: show only if a child is visible
                        if lastHdr and not hdrHasVisible then lastHdr:Hide() end
                        lastHdr = r.frame
                        lastHdrY = visY
                        hdrHasVisible = false
                        if t == "" then
                            lastHdr:Show()
                            lastHdr:ClearAllPoints()
                            lastHdr:SetPoint("TOPLEFT", child, "TOPLEFT", 1, visY)
                            lastHdr:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, visY)
                            visY = visY - r.height
                            hdrHasVisible = true
                        end
                    else
                        if t == "" or strfind(strlower(r.label), t, 1, true) then
                            -- Show header if this is the first visible child
                            if lastHdr and not hdrHasVisible then
                                lastHdr:Show()
                                lastHdr:ClearAllPoints()
                                lastHdr:SetPoint("TOPLEFT", child, "TOPLEFT", 1, lastHdrY)
                                lastHdr:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, lastHdrY)
                                visY = lastHdrY - HDR_H
                                hdrHasVisible = true
                            end
                            r.frame:Show()
                            r.frame:ClearAllPoints()
                            r.frame:SetPoint("TOPLEFT", child, "TOPLEFT", 1, visY)
                            r.frame:SetPoint("TOPRIGHT", child, "TOPRIGHT", -1, visY)
                            visY = visY - r.height
                        else
                            r.frame:Hide()
                        end
                    end
                end
                -- Hide trailing header with no visible children
                if lastHdr and not hdrHasVisible then lastHdr:Hide() end
                child:SetHeight(math.max(1, math.abs(visY)))
                sf:SetVerticalScroll(0)
                UpdateCBThumb()
            end)
            menu:HookScript("OnShow", function()
                searchEdit:SetText("")
                searchEdit:SetFocus()
                UpdateCBThumb()
            end)
        end

        menu:HookScript("OnShow", UpdateCBThumb)

        -- Refresh all checkbox + locked visuals on show
        menu:HookScript("OnShow", function()
            for _, rowInfo in ipairs(_allRows) do
                if rowInfo.frame._updateCheck then rowInfo.frame._updateCheck() end
                if rowInfo.frame._updateLocked then rowInfo.frame._updateLocked() end
            end
            for i = 1, #_taTints do _taTints[i]() end
        end)

        ddBtn._ddMenu = menu
    end

    local function ApplyNormal()
        ddLbl:SetTextColor(1, 1, 1, EllesmereUI.DD_TXT_A)
        ddBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
        ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
    end
    local function ApplyHover()
        ddLbl:SetTextColor(1, 1, 1, EllesmereUI.DD_TXT_HA)
        ddBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_HA)
        ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
    end
    ddBtn:SetScript("OnEnter", function()
        ApplyHover()
    end)
    ddBtn:SetScript("OnLeave", function()
        if not (menu and menu:IsShown()) then
            ApplyNormal()
        end
    end)

    local function ShowMenu()
        -- Dynamic items: re-evaluate and rebuild the menu on every open (only when about to show -- a toggle-close never rebuilds).
        if itemsFn and not (menu and menu:IsShown()) then
            items = itemsFn() or {}
            if menu then
                menu:Hide()
                menu:SetParent(nil)
                menu = nil
                ddBtn._ddMenu = nil
            end
            UpdateLabel()
        end
        EnsureMenu()
        if menu:IsShown() then
            menu:Hide()
            return
        end
        -- Match the panel's effective scale since menu lives on UIParent
        local btnScale = ddBtn:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        menu:SetScale(btnScale / uiScale)
        ApplyHover()
        menu:Show()
        -- Track the open menu globally so popup outside-click watchers don't treat clicks on rows that extend below the popup as a dismissing outside click.
        EllesmereUI._openDropdownMenu = menu
        menu:SetScript("OnUpdate", function(self)
            -- Close when left-clicking outside the menu and button
            if not self:IsMouseOver() and not ddBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                self:Hide()
                return
            end
            -- Close when the dropdown button scrolls out of the visible area
            local scrollFrame = EllesmereUI._scrollFrame
            if scrollFrame then
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
                        if btnBot < sfBot or btnBot > sfTop then self:Hide() end
                    end
                end
            end
        end)
        menu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            if EllesmereUI._openDropdownMenu == self then EllesmereUI._openDropdownMenu = nil end
            if ddBtn:IsMouseOver() then
                ApplyHover()
            else
                ApplyNormal()
            end
            if onMenuClosed then onMenuClosed() end
        end)
    end

    ddBtn:SetScript("OnClick", function() ShowMenu() end)
    ddBtn:HookScript("OnHide", function() if menu then menu:Hide() end end)

    local function RefreshAll()
        UpdateLabel()
        if menu then
            for _, child in pairs({menu:GetChildren()}) do
                if child._updateCheck then child._updateCheck() end
            end
        end
    end
    return ddBtn, RefreshAll
end

-------------------------------------------------------------------------------
--  Shared Visibility Mode Checklist Row
--  The single-select Visibility dropdown as a multi-select checklist backed by the shared engine in
--  EllesmereUI_Visibility.lua. One checked item is stored and evaluated exactly like the legacy single mode;
--  multiple checked conditions store a set in `visibilityModes`.
--  opts = {
--      getStore      = fn -> settings table (required)
--      legacyKey     = "visibility" | "barVisibility" (required)
--      caps          = { partyIncludesRaid, noMouseover, noGroupModes,
--                        luaDragonriding, lockedTooltips = { key = text } }
--      applyScalarFn = optional fn(store, mode) for the module's scalar write side effects (Action Bars
--                      ApplyMode, Unit Frames side-effect chain, ...)
--      onChanged     = fn called after every selection write (module's refresh chain; row calls RefreshPage itself)
--      label / width / tooltip / disabledFn / disabledTooltip / rawTooltip
--                    = row-level passthroughs matching the old dropdown row
--  }
--  rightCfg: DualRow right-slot config (defaults to an empty label).
--  Returns row, height -- same contract as W:DualRow.
-------------------------------------------------------------------------------

EllesmereUI.VIS_MODE_ITEMS = {
    { key = "never",     label = "Never" },
    { key = "always",    label = "Always" },
    { isHeader = true, label = "Combine Conditions",
      tooltip = "Conditions of the same kind are OR'd together; different kinds must all match. Mouseover combines as a hover gate." },
    { key = "mouseover", label = "Mouseover",
      tooltip = "Combines with conditions: shows on hover only while they pass." },
    { key = "in_combat",     label = "In Combat" },
    { key = "out_of_combat", label = "Out of Combat" },
    { key = "show_dragonriding",     label = "When Dragonriding",
      tooltip = "Only while airborne on a skyriding mount." },
    { key = "show_not_dragonriding", label = "When Not Dragonriding",
      tooltip = "Whenever not airborne on a skyriding mount." },
    { key = "in_raid",  label = "In Raid Group" },
    { key = "in_party", label = "In Party" },
    { key = "solo",     label = "Solo" },
}

function EllesmereUI.BuildVisibilityModeRow(W, parent, y, opts, rightCfg)
    local PP = EllesmereUI.PP
    local caps = opts.caps or {}
    local legacyKey = opts.legacyKey or "visibility"

    local row, h = W:DualRow(parent, y,
        { type = "dropdown", text = opts.label or "Visibility",
          values = { __placeholder = "..." }, order = { "__placeholder" },
          tooltip = opts.tooltip,
          disabled = opts.disabledFn,
          disabledTooltip = opts.disabledTooltip,
          rawTooltip = opts.rawTooltip,
          getValue = function() return "__placeholder" end,
          setValue = function() end },
        rightCfg or { type = "label", text = "" })

    -- Per-module item list from the master list
    local items = {}
    local listed = {}
    for _, def in ipairs(EllesmereUI.VIS_MODE_ITEMS) do
        if def.isHeader then
            items[#items + 1] = def
        elseif not (def.key == "mouseover" and caps.noMouseover) then
            local item = { key = def.key, label = def.label, tooltip = def.tooltip }
            if caps.noGroupModes and (def.key == "in_raid" or def.key == "in_party" or def.key == "solo") then
                item.locked = true
                item.lockedTooltip = (caps.lockedTooltips and caps.lockedTooltips[def.key])
                    or "This element cannot use group-based visibility."
            end
            if caps.luaDragonriding and (def.key == "show_dragonriding" or def.key == "show_not_dragonriding") then
                item.lockedFn = function() return not EllesmereUI._hasGlidingEvent end
                item.lockedTooltip = "Requires a client with gliding events."
            end
            items[#items + 1] = item
            listed[def.key] = true
        end
    end

    -- Legacy-orphan rule: a stored scalar not covered by this module's list (an old alias like "combat", or a value the list omits) renders as a checked item only while it is the current value; picking anything else removes it on the page rebuild.
    do
        local store = opts.getStore()
        if store then
            local sel, isMulti = EllesmereUI.GetVisibilitySelection(store, legacyKey)
            if not isMulti then
                local cur = next(sel)
                if cur and not listed[cur] then
                    local lbl = cur
                    for _, def in ipairs(EllesmereUI.VIS_MODE_ITEMS) do
                        if def.key == cur then lbl = def.label; break end
                    end
                    items[#items + 1] = { key = cur, label = lbl }
                end
            end
        end
    end

    local function GetChecked(k)
        local store = opts.getStore()
        if not store then return k == "always" end
        local sel = EllesmereUI.GetVisibilitySelection(store, legacyKey)
        return sel[k] == true
    end

    -- The module refresh chain runs on every click so changes apply live, but the page REBUILD is deferred to
    -- menu close: rebuilding under the open menu destroys the button it is anchored to, and the point of a
    -- checklist is checking several conditions in one visit. Terminal picks (Never/Always, legacy orphans) close
    -- the menu themselves, flushing the rebuild immediately. Everything runs from setFn: the widget's optional
    -- onChanged callback is deliberately NOT used, because passing it activates the widget's absolute-screen
    -- re-anchor (meant for callers that rebuild the page mid-click) -- this menu keeps its normal button anchor,
    -- behaving exactly like every other checkbox dropdown, including following the options window when moved.
    local cbDD, cbDDRefresh
    local pendingRefresh = false

    local function AfterChange(closeMenu)
        if opts.onChanged then opts.onChanged() end
        pendingRefresh = true
        if closeMenu and cbDD and cbDD._ddMenu then
            cbDD._ddMenu:Hide()
        end
    end

    local function SetChecked(k, checked)
        local store = opts.getStore()
        if not store then return end
        local sel = EllesmereUI.GetVisibilitySelection(store, legacyKey)
        if checked then
            if EllesmereUI.VIS_COMBINABLE_KEYS[k] then
                -- Conditions and Mouseover combine with each other; only Never/Always/orphans get cleared.
                for key in pairs(sel) do
                    if not EllesmereUI.VIS_COMBINABLE_KEYS[key] then sel[key] = nil end
                end
                sel[k] = true
            elseif k == "never" or k == "always" then
                -- Never/Always are exclusive, and terminal: picking one closes the menu like a normal single-select dropdown.
                for key in pairs(sel) do sel[key] = nil end
                sel[k] = true
                EllesmereUI.SetVisibilitySelection(store, legacyKey, sel, opts.applyScalarFn)
                AfterChange(true)
                return
            else
                -- Legacy-orphan re-checked while its row is still visible: restore it as the raw scalar and clear any stale set.
                if opts.applyScalarFn then
                    opts.applyScalarFn(store, k)
                else
                    store[legacyKey] = k
                end
                store.visibilityModes = nil
                AfterChange(true)
                return
            end
        else
            sel[k] = nil
            -- Never-empty invariant: unchecking the last item means Always
            if not next(sel) then sel.always = true end
        end
        EllesmereUI.SetVisibilitySelection(store, legacyKey, sel, opts.applyScalarFn)
        AfterChange(false)
    end

    local function OnMenuClosed()
        if pendingRefresh then
            pendingRefresh = false
            EllesmereUI:RefreshPage(opts.refreshPageArg)
        end
    end

    -- Search pre-build: the row is an absorber, so the dropdown/PP.Point
    -- chrome below would throw. The row's label was already indexed by the
    -- factory stub; nothing here registers.
    if EllesmereUI._prebuilding then return row, h end
    local leftRgn = row._leftRegion
    if leftRgn._control then leftRgn._control:Hide() end
    cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
        leftRgn, opts.width or 210, leftRgn:GetFrameLevel() + 2,
        items, GetChecked, SetChecked, nil, nil, nil, nil, OnMenuClosed)
    PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
    leftRgn._control = cbDD
    leftRgn._lastInline = nil
    EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

    -- Spec Overrides capture overlay: expose the scalar view of the setting (a captured multi applies as its representative single mode).
    leftRgn._captureCfg = {
        type = "dropdown", text = opts.label or "Visibility",
        getValue = function()
            local s = opts.getStore()
            return s and (s[legacyKey] or "always") or "always"
        end,
        setValue = function(v)
            local s = opts.getStore()
            if not s then return end
            if EllesmereUI.VIS_CONDITION_KEYS[v] or v == "never" or v == "always" or v == "mouseover" then
                local one = {}
                one[v] = true
                EllesmereUI.SetVisibilitySelection(s, legacyKey, one, opts.applyScalarFn)
            else
                if opts.applyScalarFn then opts.applyScalarFn(s, v) else s[legacyKey] = v end
                s.visibilityModes = nil
            end
            if opts.onChanged then opts.onChanged() end
        end,
    }

    -- Row-level disabled state (e.g. Action Bars data bars in Blizzard mode): gray and lock the checklist button; the label tooltip is handled by the DualRow config passthrough above.
    if opts.disabledFn then
        local function ApplyChecklistDisabled()
            local off = opts.disabledFn()
            cbDD:SetAlpha(off and 0.3 or 1)
            cbDD:EnableMouse(not off)
        end
        EllesmereUI.RegisterWidgetRefresh(ApplyChecklistDisabled)
        ApplyChecklistDisabled()
    end

    return row, h
end

-------------------------------------------------------------------------------
--  Unified Visibility Row (opts contract for the 10 module callers)
--  ONE control replacing the "Visibility" + "Visibility Options" pair. Every condition is
--  an AXIS with a Show and a Hide lane: Show means the axis must match, Hide means it must
--  not, the two lanes are mutually exclusive per axis, an unconstrained axis imposes
--  nothing, and axes AND together. The three group rows stay ONE OR-group, as the mode
--  engine in EllesmereUI_Visibility.lua already evaluates them. Storage stays split (mode
--  axes through the shared engine, option axes as existing per-axis booleans) -- no
--  evaluator, secure driver, profile sync or spec-override path changes; only lanes with no
--  prior counterpart use a new key (EllesmereUI.VIS_OPT_KEYS).
--  opts = {
--      getStore/legacyKey  = store accessor + scalar key (required)
--      caps                = { noMouseover, noGroupModes, luaDragonriding, lockedTooltips }
--      applyScalarFn       = optional fn(store, mode) for scalar side effects
--      getOption/setOption = optional fn(key)/fn(key, value) when option booleans live
--                            outside getStore() (Resource Bars writes three stores)
--      trueDefaultOpts     = optional set { [visOptKey] = true, ... } for opt-axis keys whose
--                            shipped DEFAULTS value is true; unchecking such a key persists an
--                            explicit false instead of nil, so DeepMergeDefaults on next login
--                            does not re-fill it back to true (the built-in CDM bars ship
--                            housing-hide on, so they need this)
--      onChanged/onOptionChanged = fired after a mode / option write (latter falls back)
--      extraItems          = { { key, label, tooltip, get, set }, ... } single-lane rows
--      label/width/tooltip/disabledFn/disabledTooltip/rawTooltip/refreshPageArg
--  }
--  rightCfg: DualRow right-slot config -- the old Visibility Options dropdown's old slot,
--  now free for whatever the page needs. Returns row, height, same as W:DualRow.
-------------------------------------------------------------------------------

EllesmereUI.VIS_ROW_ITEMS = {
    { key = "never",     label = "Never" },
    { key = "always",    label = "Always" },
    { key = "mouseover", label = "Mouseover",
      tooltip = "Reveal on hover only. Combines with the conditions below: hover-reveals while they all pass, stays hidden while any fails.",
      tooltipAny = "Reveal on hover only. Combines with the conditions below: hover-reveals while at least ONE passes, stays hidden while none does." },
    -- Modifiers, not conditions: they decide how the rows below combine, so they stay
    -- out of the summary and the Show/Hide lane pairs. Radio pair (matchValue) over one
    -- scalar: picking one unpicks the other, there is no "neither" state.
    { isHeader = true, label = "Match Mode" },
    { key = "matchAll", label = "Match All Conditions", modifier = true, matchValue = "all",
      tooltip = "Every condition you set has to match. The default." },
    { key = "matchAny", label = "Match Any Condition", modifier = true, matchValue = "any",
      tooltip = "This element shows as soon as ONE condition matches, and a Hide lane then means show while that condition is false." },
    { isHeader = true, label = "Show", rightLabel = "Hide" },
    { key = "combat", label = "In Combat", axis = "mode",
      show = "in_combat", hide = "out_of_combat" },
    { key = "in_raid",  label = "In Raid Group", axis = "group" },
    { key = "in_party", label = "In Party",      axis = "group" },
    { key = "solo",     label = "Solo",          axis = "group" },
    { key = "skyAirborne", label = "Skyriding (Airborne)", axis = "mode",
      show = "show_dragonriding", hide = "show_not_dragonriding",
      tooltip = "Only while AIRBORNE on a glide-capable mount or flight form. For the mount itself, ground included, use Skyriding Mount." },
    { key = "skyMount", label = "Skyriding Mount", axis = "opt",
      show = "visOnlySkyriding", hide = "visHideDragonriding",
      tooltip = "While on a glide-capable mount, ground included, where Blizzard shows its vigor HUD. Skyriding (Airborne) additionally requires you to be flying." },
    { key = "instances", label = "Instances", axis = "opt",
      show = "visOnlyInstances", hide = "visHideInstances",
      tooltip = "Dungeons, raids, scenarios, arenas and battlegrounds. Garrisons do not count." },
    { key = "housing", label = "Housing", axis = "opt",
      show = "visOnlyHousing", hide = "visHideHousing",
      tooltip = "While you are inside a house or plot." },
    { key = "mounted", label = "Mounted", axis = "opt",
      show = "visOnlyMounted", hide = "visHideMounted",
      tooltip = "Druid travel, aquatic and flight forms count as mounted." },
    { key = "target", label = "Target", axis = "opt",
      show = "visHideNoTarget", hide = "visHideWithTarget",
      tooltip = "*Blizzard's auto targeting (soft target) setting can cause brief flickering when your actual target dies but a soft-target is still active." },
    { key = "enemyTarget", label = "Enemy Target", axis = "opt",
      show = "visHideNoEnemy", hide = "visHideWithEnemy",
      tooltip = "A target you can attack." },
}

-------------------------------------------------------------------------------
--  Attaches ONE visibility checklist to a DualRow region. Split out of
--  BuildVisibilityRow so a single row can carry two independent ones (Action Bars
--  puts Micro Menu and Bag Bar visibility side by side). Callers that want the
--  standard labelled row use BuildVisibilityRow; this is the raw attach.
--  The caller must have skipped the search pre-build pass already.
-------------------------------------------------------------------------------
function EllesmereUI.AttachVisibilityChecklist(region, opts)
    local PP = EllesmereUI.PP
    local caps = opts.caps or {}
    local legacyKey = opts.legacyKey or "visibility"
    local GROUP_KEYS = (EllesmereUI.VIS_AXES and EllesmereUI.VIS_AXES.group)
        or { "in_raid", "in_party", "solo" }

    -- Per-module row list. `listed` collects the legacy SCALAR values this row can
    -- actually reach, so the orphan rule below only fires for genuinely foreign ones.
    local items, defs, listed = {}, {}, {}
    -- Defined below, forward-declared because the rows built here close over them.
    local GetMatchAny

    -- The stored scalar when it is a legacy alias this row cannot express, else nil.
    -- Read at build (the orphan's own row) and live by the Match Mode rows, which lock
    -- while an orphan is stored: Any hands an orphan back to the caller's legacy chain,
    -- which knows nothing about the option lanes. Never/Always stay clickable as the exit.
    local function OrphanScalar()
        local store = opts.getStore()
        if not store then return nil end
        local sel, isMulti = EllesmereUI.GetVisibilitySelection(store, legacyKey)
        if isMulti then return nil end
        local cur = next(sel)
        if cur and not listed[cur] then return cur end
        return nil
    end
    local function OrphanActive() return OrphanScalar() ~= nil end
    for _, def in ipairs(EllesmereUI.VIS_ROW_ITEMS) do
        if def.isHeader then
            items[#items + 1] = def
        elseif not (def.key == "mouseover" and caps.noMouseover) then
            local item = { key = def.key, label = def.label, tooltip = def.tooltip,
                           dual = def.axis and true or nil,
                           isModifier = def.modifier }
            if caps.noGroupModes and def.axis == "group" then
                item.locked = true
                item.lockedTooltip = (caps.lockedTooltips and caps.lockedTooltips[def.key])
                    or "This element cannot use group-based visibility."
            end
            -- Only the airborne row needs the takeoff/landing edge; the mount row
            -- rides PLAYER_CAN_GLIDE_CHANGED, which is always registered.
            if caps.luaDragonriding and def.key == "skyAirborne" then
                item.lockedFn = function() return not EllesmereUI._hasGlidingEvent end
                item.lockedTooltip = "Requires a client with gliding events."
            end
            if def.modifier then
                item.lockedFn = OrphanActive
                item.lockedTooltip = "Not available while a legacy visibility value is selected. Pick Never or Always first."
            end
            -- Rows whose tooltip states a combining rule have to restate it under Any.
            if def.tooltipAny then
                item.tooltip = function()
                    return GetMatchAny() and def.tooltipAny or def.tooltip
                end
            end
            items[#items + 1] = item
            defs[def.key] = def
            if def.axis == "mode" then
                listed[def.show] = true; listed[def.hide] = true
            elseif def.axis == "group" then
                listed[def.key] = true
            elseif def.modifier then
                -- Never a stored scalar, so it must not shadow the orphan rule.
            elseif not def.axis then
                listed[def.key] = true
            end
        end
    end

    if opts.extraItems then
        for _, ex in ipairs(opts.extraItems) do
            items[#items + 1] = { key = ex.key, label = ex.label, tooltip = ex.tooltip }
            defs[ex.key] = { key = ex.key, axis = "extra", get = ex.get, set = ex.set }
        end
    end

    -- Legacy-orphan rule, unchanged from the old checklist: a stored scalar this row
    -- cannot reach renders as a checked entry only while it is the current value.
    do
        local cur = OrphanScalar()
        if cur then
            items[#items + 1] = { key = cur, label = cur }
            defs[cur] = { key = cur, orphan = true }
        end
    end

    local function Sel()
        local store = opts.getStore()
        if not store then return nil end
        return EllesmereUI.GetVisibilitySelection(store, legacyKey), store
    end

    local function WriteSel(sel, store)
        -- Never-empty invariant: clearing the last condition means Always.
        if not next(sel) then sel.always = true end
        EllesmereUI.SetVisibilitySelection(store, legacyKey, sel, opts.applyScalarFn)
    end

    local function GetOpt(k)
        if opts.getOption then return opts.getOption(k) == true end
        local store = opts.getStore()
        return (store and store[k]) == true
    end

    local function SetOpt(k, v)
        -- Uncheck normally persists as nil ("never set"), which is correct for every
        -- shipped-off key. A key whose DEFAULTS entry is true needs an explicit false
        -- instead, or DeepMergeDefaults re-fills the nil back to true on next login.
        local storedValue
        if v then
            storedValue = true
        elseif opts.trueDefaultOpts and opts.trueDefaultOpts[k] then
            storedValue = false
        else
            storedValue = nil
        end
        if opts.setOption then opts.setOption(k, storedValue); return end
        local store = opts.getStore()
        if store then store[k] = storedValue end
    end

    -- The match is a store-level scalar, but it fans out like the option lanes do
    -- (Resource Bars writes health/primary/secondary through these hooks), so it rides them.
    GetMatchAny = function()
        if opts.getOption then return opts.getOption("visibilityMatch") == "any" end
        local store = opts.getStore()
        return (store and store.visibilityMatch) == "any"
    end

    local function SetMatchAny(on)
        if opts.setOption then opts.setOption("visibilityMatch", on and "any" or nil); return end
        local store = opts.getStore()
        if store then store.visibilityMatch = on and "any" or nil end
    end

    -- Option axes live outside the selection, so Always vs. an active Show lane (which
    -- narrows what Always claims is unrestricted) is reconciled in GetChecked/SetChecked.
    -- Same under Any: always is not a tallied axis, so a lone Show lane narrows the same way.
    local function AnyShowOptActive()
        for _, d in pairs(defs) do
            if d.axis == "opt" and GetOpt(d.show) then return true end
        end
        return false
    end

    local cbDD, cbDDRefresh
    local pendingRefresh = false

    -- The module refresh chain runs on every click so changes apply live, but the page
    -- REBUILD waits for menu close: rebuilding under the open menu destroys the button
    -- it is anchored to, and the point of a checklist is setting several axes in one
    -- visit. Terminal picks (Never/Always, orphans) close the menu themselves.
    -- alsoOther: the click wrote a mode AND an option (a lane clearing Never, or Always
    -- clearing the Show lanes), so both caller chains run; neither is a subset of the other
    -- (Action Bars recompiles its housing driver only in the option chain).
    local function AfterChange(closeMenu, isOption, alsoOther)
        local optionFn = (isOption or alsoOther) and opts.onOptionChanged
        local modeFn = ((not isOption) or alsoOther) and opts.onChanged
        if optionFn then optionFn() end
        if modeFn then modeFn() end
        -- A caller that supplies only onChanged still gets that chain for option writes.
        if not optionFn and not modeFn and opts.onChanged then opts.onChanged() end
        pendingRefresh = true
        if closeMenu and cbDD and cbDD._ddMenu then cbDD._ddMenu:Hide() end
    end

    local function GetChecked(k, neg)
        local def = defs[k]
        if not def then return false end
        if def.modifier then
            return (def.matchValue == "any") == GetMatchAny()
        end
        if def.axis == "extra" then return def.get() == true end
        if def.axis == "opt" then return GetOpt(neg and def.hide or def.show) end
        local sel = Sel()
        if not sel then return k == "always" end
        if def.axis == "mode" then return sel[neg and def.hide or def.show] == true end
        if def.axis == "group" then
            if not neg then return sel[def.key] == true end
            -- Hide-lane sugar: in a three-way OR-group, "not in a raid" IS "in a party
            -- or solo". No key of its own, no evaluator branch, no driver change.
            if sel[def.key] then return false end
            for i = 1, #GROUP_KEYS do
                if GROUP_KEYS[i] ~= def.key and not sel[GROUP_KEYS[i]] then return false end
            end
            return true
        end
        if k == "always" then return sel.always == true and not AnyShowOptActive() end
        return sel[k] == true
    end

    local function SetChecked(k, checked, neg)
        local def = defs[k]
        if not def then return end

        -- Modifier: a radio pair over one scalar; picking one unpicks the other and
        -- deliberately clears nothing else.
        if def.modifier then
            SetMatchAny(def.matchValue == "any")
            AfterChange(false, true)
            return
        end

        if def.axis == "extra" then
            def.set(checked)
            AfterChange(false, true)
            return
        end

        if def.axis == "opt" then
            local lane, other = def.show, def.hide
            if neg then lane, other = def.hide, def.show end
            SetOpt(lane, checked)
            if checked then SetOpt(other, false) end
            -- Checking a lane under Never leaves Never (WriteSel's never-empty invariant
            -- lands on Always, which the lane then narrows); unchecking one leaves Never alone.
            local clearedNever = false
            if checked then
                local sel, store = Sel()
                if store and sel.never then
                    sel.never = nil
                    WriteSel(sel, store)
                    clearedNever = true
                end
            end
            AfterChange(false, true, clearedNever)
            return
        end

        local sel, store = Sel()
        if not store then return end
        -- Any condition write clears the exclusive scalars (Never/Always/orphan) but
        -- combines with every other axis.
        if def.axis or k == "mouseover" then
            for key in pairs(sel) do
                if not EllesmereUI.VIS_COMBINABLE_KEYS[key] then sel[key] = nil end
            end
        end

        if def.axis == "mode" then
            local lane, other = def.show, def.hide
            if neg then lane, other = def.hide, def.show end
            sel[lane] = checked or nil
            if checked then sel[other] = nil end
            WriteSel(sel, store)
            AfterChange(false)
            return
        end

        if def.axis == "group" then
            if not neg then
                sel[def.key] = checked or nil
            elseif checked then
                sel[def.key] = nil
                for i = 1, #GROUP_KEYS do
                    if GROUP_KEYS[i] ~= def.key then sel[GROUP_KEYS[i]] = true end
                end
            else
                -- Unchecking Hide drops the whole group constraint: the state it
                -- encoded (the other two checked) has no other representation.
                for i = 1, #GROUP_KEYS do sel[GROUP_KEYS[i]] = nil end
            end
            WriteSel(sel, store)
            AfterChange(false)
            return
        end

        if k == "mouseover" then
            sel.mouseover = checked or nil
            WriteSel(sel, store)
            AfterChange(false)
            return
        end

        if k == "never" or k == "always" then
            -- Exclusive and terminal, like a plain single-select.
            for key in pairs(sel) do sel[key] = nil end
            if checked then sel[k] = true end
            WriteSel(sel, store)
            -- Always clears the Show lanes (else GetChecked keeps its box unchecked and the
            -- click is a no-op); Hide lanes survive, and Never leaves every lane untouched.
            local clearedOpts = false
            if k == "always" and checked then
                for _, d in pairs(defs) do
                    if d.axis == "opt" and GetOpt(d.show) then
                        SetOpt(d.show, false)
                        clearedOpts = true
                    end
                end
            end
            AfterChange(true, false, clearedOpts)
            return
        end

        -- Legacy orphan re-checked while its row is still visible.
        if checked then
            if opts.applyScalarFn then opts.applyScalarFn(store, k) else store[legacyKey] = k end
            store.visibilityModes = nil
            SetMatchAny(false)
            AfterChange(true)
        end
    end

    local function OnMenuClosed()
        if pendingRefresh then
            pendingRefresh = false
            EllesmereUI:RefreshPage(opts.refreshPageArg)
        end
    end

    local leftRgn = region
    if leftRgn._control then leftRgn._control:Hide() end
    cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
        leftRgn, opts.width or 210, leftRgn:GetFrameLevel() + 2,
        items, GetChecked, SetChecked, nil, 12, nil, nil, OnMenuClosed,
        { emptyLabel = "Always",
          -- Both of these read the match live: under Any the conditions are OR'd, and
          -- a Hide lane stops being a veto and becomes a disjunct of its own.
          separatorFn = function() return GetMatchAny() and " or " or ", " end,
          hideLaneTooltip = function()
              return GetMatchAny() and "Show while this condition is false"
                  or "Hide while this condition is true"
          end })
    PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
    leftRgn._control = cbDD
    leftRgn._lastInline = nil
    EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

    -- Spec Overrides capture overlay: exposes the scalar view (a captured multi applies
    -- as its representative single mode). Option axes are not spec-capturable, same as
    -- before the merge.
    leftRgn._captureCfg = {
        type = "dropdown", text = opts.label or "Visibility",
        getValue = function()
            local s = opts.getStore()
            return s and (s[legacyKey] or "always") or "always"
        end,
        setValue = function(v)
            local s = opts.getStore()
            if not s then return end
            if EllesmereUI.VIS_CONDITION_KEYS[v] or v == "never" or v == "always" or v == "mouseover" then
                local one = {}
                one[v] = true
                EllesmereUI.SetVisibilitySelection(s, legacyKey, one, opts.applyScalarFn)
            else
                if opts.applyScalarFn then opts.applyScalarFn(s, v) else s[legacyKey] = v end
                s.visibilityModes = nil
                -- Same reset as the row's orphan branch: Any cannot express an orphan.
                SetMatchAny(false)
            end
            if opts.onChanged then opts.onChanged() end
        end,
    }

    if opts.disabledFn then
        local function ApplyChecklistDisabled()
            local off = opts.disabledFn()
            cbDD:SetAlpha(off and 0.3 or 1)
            cbDD:EnableMouse(not off)
        end
        EllesmereUI.RegisterWidgetRefresh(ApplyChecklistDisabled)
        ApplyChecklistDisabled()
    end

end

function EllesmereUI.BuildVisibilityRow(W, parent, y, opts, rightCfg)
    -- The placeholder slot the checklist replaces; W:DualRow only knows plain widgets.
    local function Slot(o)
        return { type = "dropdown", text = o.label or "Visibility",
                 values = { __placeholder = "..." }, order = { "__placeholder" },
                 tooltip = o.tooltip,
                 disabled = o.disabledFn,
                 disabledTooltip = o.disabledTooltip,
                 rawTooltip = o.rawTooltip,
                 getValue = function() return "__placeholder" end,
                 setValue = function() end }
    end

    -- opts.rightVis: a second, fully independent visibility checklist in the right
    -- slot (its own store, legacyKey, caps and callbacks). Mutually exclusive with
    -- rightCfg, which stays the way to put any ordinary widget there.
    local rightVis = opts.rightVis
    local row, h = W:DualRow(parent, y, Slot(opts),
        rightVis and Slot(rightVis) or rightCfg or { type = "label", text = "" })

    -- Search pre-build: the row is an absorber, so the chrome below would throw. The
    -- row's labels were already indexed by the factory stubs; nothing here registers.
    if EllesmereUI._prebuilding then return row, h end

    EllesmereUI.AttachVisibilityChecklist(row._leftRegion, opts)
    if rightVis then
        EllesmereUI.AttachVisibilityChecklist(row._rightRegion, rightVis)
    end

    return row, h
end
-------------------------------------------------------------------------------
--  BuildReorderCBDropdown
--  Checkbox dropdown whose rows can also be drag-reordered vertically. Row visuals match BuildVisOptsCBDropdown;
--  the drag behavior matches the Macro Factory per-macro menus (3px threshold, floating row, insertion line, contents shuffle on drop).
--  items: array in initial display order:
--      { key = "...", label = "...", fixed = true|nil }
--  fixed rows are checkbox-only and pinned below the movable rows.
--  getFn(key) -> checked; setFn(key, checked) fires on row click.
--  opts = {
--      setOrder = function(orderedMovableKeys),  -- fired on every drop
--      onClose  = function(orderChanged),        -- fired once per menu close
--      hint     = "Drag to Reorder",             -- text above the rows
--      hint2    = "...",                         -- optional second hint line
--  }
--  Returns ddBtn, RefreshAll (same contract as BuildVisOptsCBDropdown).
-------------------------------------------------------------------------------
function EllesmereUI.BuildReorderCBDropdown(parentFrame, ddW, fLevel, items, getFn, setFn, opts)
    opts = opts or {}
    local PP = EllesmereUI.PP or EllesmereUI.PanelPP
    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
    -- Options panel is Expressway-locked by design (locale-aware: CJK/Cyrillic get the system glyph font). The user's global font intentionally does not restyle the settings UI.
    local fontPath = EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"

    -- Split movable / fixed, preserving the given order
    local movable, fixedItems = {}, {}
    for _, it in ipairs(items) do
        if it.fixed then fixedItems[#fixedItems + 1] = it
        else movable[#movable + 1] = it end
    end

    local ddBtn = CreateFrame("Button", nil, parentFrame)
    PP.Size(ddBtn, ddW, 30)
    ddBtn:SetFrameLevel(fLevel)
    local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints()
    ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
    local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
    local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
    ddLbl:SetFont(fontPath, 13, "")
    ddLbl:SetTextColor(1, 1, 1, EllesmereUI.DD_TXT_A)
    ddLbl:SetJustifyH("LEFT")
    ddLbl:SetWordWrap(false)
    ddLbl:SetMaxLines(1)
    ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
    local arrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, PP)
    ddLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

    local function SummaryLabel()
        local names = {}
        local total = 0
        local function collect(list)
            for _, item in ipairs(list) do
                total = total + 1
                if getFn(item.key) then names[#names + 1] = EllesmereUI.L(item.label) end
            end
        end
        collect(movable); collect(fixedItems)
        if #names == 0 then return EllesmereUI.L("None") end
        if #names == total then return EllesmereUI.L("All") end
        return table.concat(names, ", ")
    end
    local function UpdateLabel()
        ddLbl:SetText(SummaryLabel())
    end
    UpdateLabel()

    local menu
    local orderChanged = false
    local allRows = {}

    local ITEM_H = 28
    local HINT_H = opts.hint2 and 32 or 18
    local DIV_H = 7

    local function EnsureMenu()
        if menu then return end
        local ROWS_BASE_Y = -4 - HINT_H
        local menuH = 4 + HINT_H + #movable * ITEM_H
            + ((#fixedItems > 0) and (DIV_H + #fixedItems * ITEM_H) or 0) + 4
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(200)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetSize(ddW, menuH)
        menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
        menu:Hide()
        local mBg = menu:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints()
        mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA or 0.92)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)

        -- Hint line(s) above the rows
        local hint = menu:CreateFontString(nil, "OVERLAY")
        hint:SetFont(fontPath, 10, "")
        hint:SetTextColor(1, 1, 1, 0.25)
        if opts.hint2 then
            hint:SetPoint("TOP", menu, "TOP", 0, -6)
            local hint2 = menu:CreateFontString(nil, "OVERLAY")
            hint2:SetFont(fontPath, 9, "")
            hint2:SetTextColor(1, 1, 1, 0.25)
            hint2:SetPoint("TOP", hint, "BOTTOM", 0, -3)
            hint2:SetText(EllesmereUI.L(opts.hint2))
        else
            hint:SetPoint("TOP", menu, "TOP", 0, -4 - (HINT_H - 10) / 2)
        end
        hint:SetText(EllesmereUI.L(opts.hint or "Drag to Reorder"))

        local isDragging = false
        local insLine = menu:CreateTexture(nil, "OVERLAY", nil, 7)
        insLine:SetHeight(2)
        insLine:SetColorTexture(EG.r, EG.g, EG.b, 0.9)
        insLine:Hide()

        local function SlotY(i) return ROWS_BASE_Y - (i - 1) * ITEM_H end

        local function BuildRow(item, slotY, draggable)
            local row = CreateFrame("Button", nil, menu)
            row:SetHeight(ITEM_H)
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, slotY)
            row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, slotY)
            row:SetFrameLevel(menu:GetFrameLevel() + 2)
            row._item = item
            row._slotY = slotY
            local box = CreateFrame("Frame", nil, row)
            box:SetSize(16, 16)
            box:SetPoint("LEFT", row, "LEFT", 10, 0)
            local boxBg = box:CreateTexture(nil, "BACKGROUND")
            boxBg:SetAllPoints()
            boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
            local boxBrd = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6, PP)
            local chk = box:CreateTexture(nil, "ARTWORK")
            PP.SetInside(chk, box, 2, 2)
            chk:SetColorTexture(EG.r, EG.g, EG.b, 1)
            chk:SetSnapToPixelGrid(false)
            local lbl = row:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(fontPath, 13, "")
            lbl:SetTextColor(0.75, 0.75, 0.75, 1)
            lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
            lbl:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
            lbl:SetMaxLines(1)
            lbl:SetText(EllesmereUI.L(item.label))
            local hl = row:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0)
            local function UpdateCheck()
                if getFn(row._item.key) then
                    chk:Show()
                    boxBrd:SetColor(EG.r, EG.g, EG.b, 0.8)
                else
                    chk:Hide()
                    boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
            UpdateCheck()
            row._updateCheck = UpdateCheck
            row._lbl = lbl
            row:SetScript("OnEnter", function()
                if isDragging then return end
                lbl:SetTextColor(1, 1, 1, 1)
                hl:SetColorTexture(1, 1, 1, 0.04)
            end)
            row:SetScript("OnLeave", function()
                if isDragging then return end
                lbl:SetTextColor(0.75, 0.75, 0.75, 1)
                hl:SetColorTexture(1, 1, 1, 0)
            end)
            row:SetScript("OnClick", function()
                if isDragging then return end
                setFn(row._item.key, not getFn(row._item.key))
                UpdateLabel()
                for _, r in ipairs(allRows) do
                    if r._updateCheck then r._updateCheck() end
                end
            end)
            allRows[#allRows + 1] = row
            return row
        end

        -- Movable rows sit at fixed slots; drops shuffle row CONTENTS, not frames, so slot geometry stays constant for the drag math.
        local movableRows = {}
        local function RefreshMovableRows()
            for i = 1, #movableRows do
                local rf = movableRows[i]
                rf._item = movable[i]
                rf._lbl:SetText(EllesmereUI.L(movable[i].label))
                rf._updateCheck()
            end
        end

        -- Gap index (1..#movable+1) the cursor points at: walk the slot midpoints, skipping the dragged row's own slot -- the same logic as the raid frames Sort By reorder menu, so the insertion line and the drop target always agree.
        local function TargetGap(cursorY, fromIdx)
            local mT = menu:GetTop() or 0
            local iI = #movable
            for i = 1, #movable do
                if i ~= fromIdx then
                    local mid = mT + SlotY(i) - ITEM_H / 2
                    if cursorY > mid then iI = i; break end
                    iI = i + 1
                end
            end
            return math.max(1, math.min(iI, #movable + 1))
        end

        for i = 1, #movable do
            local row = BuildRow(movable[i], SlotY(i), true)
            movableRows[i] = row

            local dsY, dgO, dgFrom
            row:SetScript("OnMouseDown", function(_, b)
                if b ~= "LeftButton" then return end
                local _, cy = GetCursorPosition()
                dsY = cy
            end)
            row:SetScript("OnMouseUp", function(self, b)
                if b ~= "LeftButton" then return end
                dsY = nil
                if not isDragging then return end
                isDragging = false
                insLine:Hide()
                self:SetFrameLevel(menu:GetFrameLevel() + 2)
                self:SetAlpha(1)
                -- Snap the floated row back to its slot
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, self._slotY)
                self:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, self._slotY)
                local _, cy = GetCursorPosition()
                cy = cy / menu:GetEffectiveScale()
                local from
                for mi = 1, #movable do
                    if movable[mi] == self._item then from = mi; break end
                end
                -- Gap -> insertion index: removing the row first shifts everything after it up one, so downward moves adjust by -1 (same as the raid frames Sort By drop).
                local iI = TargetGap(cy, from)
                if from and from < iI then iI = iI - 1 end
                local to = math.max(1, math.min(iI, #movable))
                if from and from ~= to then
                    local mv = table.remove(movable, from)
                    table.insert(movable, to, mv)
                    orderChanged = true
                    if opts.setOrder then
                        local keys = {}
                        for mi = 1, #movable do keys[mi] = movable[mi].key end
                        opts.setOrder(keys)
                    end
                    UpdateLabel()
                end
                RefreshMovableRows()
            end)
            row:SetScript("OnUpdate", function(self)
                if not dsY then return end
                local _, cy = GetCursorPosition()
                if not isDragging then
                    if math.abs(cy - dsY) < 3 then return end
                    isDragging = true
                    local sc = menu:GetEffectiveScale()
                    dgO = (cy / sc) - (self:GetTop() or 0)
                    dgFrom = nil
                    for mi = 1, #movable do
                        if movable[mi] == self._item then dgFrom = mi; break end
                    end
                    self:SetFrameLevel(menu:GetFrameLevel() + 10)
                    self:SetAlpha(0.8)
                    for _, rf in ipairs(movableRows) do
                        if rf._lbl then rf._lbl:SetTextColor(0.75, 0.75, 0.75, 1) end
                    end
                end
                local sc = menu:GetEffectiveScale()
                local cY = cy / sc
                local mT = menu:GetTop() or 0
                local lY = cY - (dgO or 0) - mT
                lY = math.max(ROWS_BASE_Y - (#movable - 1) * ITEM_H, math.min(lY, ROWS_BASE_Y))
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, lY)
                self:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, lY)
                local lnY = SlotY(TargetGap(cY, dgFrom)) + 1
                insLine:ClearAllPoints()
                insLine:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, lnY)
                insLine:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -8, lnY)
                insLine:Show()
            end)
        end

        -- Divider + fixed (non-draggable) rows below the movable group
        if #fixedItems > 0 then
            local divY = ROWS_BASE_Y - #movable * ITEM_H - 3
            local dl = menu:CreateTexture(nil, "ARTWORK")
            dl:SetHeight(1)
            dl:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, divY)
            dl:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -10, divY)
            dl:SetColorTexture(1, 1, 1, 0.08)
            for i = 1, #fixedItems do
                BuildRow(fixedItems[i], ROWS_BASE_Y - #movable * ITEM_H - DIV_H - (i - 1) * ITEM_H, false)
            end
        end

        -- Refresh check visuals whenever the menu opens
        menu:HookScript("OnShow", function()
            for _, r in ipairs(allRows) do
                if r._updateCheck then r._updateCheck() end
            end
        end)

        -- One close notification per open/close cycle (reload prompts hook this)
        menu:HookScript("OnHide", function()
            isDragging = false
            insLine:Hide()
            local changed = orderChanged
            orderChanged = false
            if opts.onClose then opts.onClose(changed) end
        end)

        ddBtn._ddMenu = menu
    end

    local function ApplyNormal()
        ddLbl:SetTextColor(1, 1, 1, EllesmereUI.DD_TXT_A)
        ddBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
        ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
    end
    local function ApplyHover()
        ddLbl:SetTextColor(1, 1, 1, EllesmereUI.DD_TXT_HA)
        ddBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_HA)
        ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
    end
    ddBtn:SetScript("OnEnter", ApplyHover)
    ddBtn:SetScript("OnLeave", function()
        if not (menu and menu:IsShown()) then ApplyNormal() end
    end)

    local function ShowMenu()
        EnsureMenu()
        if menu:IsShown() then
            menu:Hide()
            return
        end
        local btnScale = ddBtn:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        menu:SetScale(btnScale / uiScale)
        ApplyHover()
        menu:Show()
        menu:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver() and not ddBtn:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                self:Hide()
            end
        end)
    end
    ddBtn:SetScript("OnClick", ShowMenu)
    ddBtn:HookScript("OnHide", function() if menu then menu:Hide() end end)

    local function RefreshAll()
        UpdateLabel()
        for _, r in ipairs(allRows) do
            if r._updateCheck then r._updateCheck() end
        end
    end
    return ddBtn, RefreshAll
end

-------------------------------------------------------------------------------
--  BuildUnlockPlaceholder
--  Reusable overlay that mirrors the unlock mode mover style. Shows accent-colored text (default "Move in
--  Unlock Mode") and opens unlock mode on click.
--  opts = {
--      parent   = frame,          -- parent frame to overlay
--      text     = "...",          -- optional, defaults to "Move in Unlock Mode"
--      level    = number,         -- optional frame level override
--      onClick  = function,       -- optional custom click handler (default: toggle unlock mode)
--  }
--  Returns the placeholder frame.
-------------------------------------------------------------------------------
function EllesmereUI.BuildUnlockPlaceholder(opts)
    local parent = opts.parent
    local eg = EllesmereUI.ELLESMERE_GREEN
    local ar, ag, ab = eg.r, eg.g, eg.b

    local f = CreateFrame("Button", nil, parent)
    f:SetAllPoints(parent)
    if opts.level then
        f:SetFrameLevel(opts.level)
    else
        f:SetFrameLevel(parent:GetFrameLevel() + 10)
    end
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp")

    -- Dark background matching unlock mode movers
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
    f._bg = bg

    -- Accent border at 60% alpha
    f._brd = EllesmereUI.MakeBorder(f, ar, ag, ab, 0.6)

    -- White centered label matching unlock mode mover style
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetFont(fontPath, 10, "OUTLINE, SLUG")
    label:SetText(EllesmereUI.L(opts.text or "Move in Unlock Mode"))
    label:SetTextColor(1, 1, 1, 0.9)
    label:SetPoint("CENTER")
    f._label = label

    -- Hover: accent text + brighten border
    local brd = f._brd
    f:SetScript("OnEnter", function()
        label:SetTextColor(ar, ag, ab, 1)
        if brd then brd:SetColor(ar, ag, ab, 0.85) end
    end)
    f:SetScript("OnLeave", function()
        label:SetTextColor(1, 1, 1, 0.9)
        if brd then brd:SetColor(ar, ag, ab, 0.6) end
    end)

    -- Click: open unlock mode (or custom handler)
    f:SetScript("OnClick", opts.onClick or function()
        if EllesmereUI.ToggleUnlockMode then
            EllesmereUI:ToggleUnlockMode()
        end
    end)

    return f
end
