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
            EllesmereUI._NotifySettingWrite(parent)
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
-- Shared with hand-placed controls that explain a site's lock the way its widgets do.
EllesmereUI.ResolveDisabledTip = ResolveDisabledTip

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
            EllesmereUI._NotifySettingWrite(ddBtn)
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
    -- Caption font override ({ path, size, flags }) and native atlas icon colours, so a
    -- menu can match the UI it opens from (e.g. the CDM options' own flyouts).
    local _moLabelFont = _menuOpts and _menuOpts.labelFont
    local _moIconNative = _menuOpts and _menuOpts.iconNativeColor
    -- Optional in-menu search box (_menuOpts.searchable): filter field hides non-matching items and repositions the rest. Flat lists only (no subnav, no dividers).
    local _moSearchable = _menuOpts and _menuOpts.searchable
    local SEARCH_H = 26
    local searchPad = _moSearchable and (SEARCH_H + 8) or 0
    local searchEdit, searchPlaceholder
    local searchResetScroll  -- assigned inside the scrolling branch; nil otherwise
    local padInit, padStepSync, padReveal  -- controller helpers: padInit (scrolling branch only) builds the other two on first use
    local mBgR, mBgG, mBgB, mBgA = DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_HA
    local mBrR, mBrG, mBrB, mBrA = 1, 1, 1, DD_BRD_A
    -- Parent to a caller-supplied frame (a scaled popup) when given so the menu INHERITS its scale and layers within it -- no manual scale matching, nested dropdowns don't render giant/behind. Else UIParent (the controller-cursor overlay layer while one is loaded), so page dropdowns escape the scroll-frame clip.
    local menu = CreateFrame("Frame", nil, (_menuOpts and _menuOpts.parent) or EllesmereUI.OverlayParent())
    -- Spec Overrides auto-capture: edits through this menu attribute to the slot whose dropdown opened it.
    menu._euiOptionsPopup = true
    -- Controller cursor: the list blocks what is under it but is not a stop itself.
    EllesmereUI.PadHint(menu, "nodepass")
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
        local fontPath = (_moLabelFont and _moLabelFont[1]) or EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
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

                local flyout = CreateFrame('Frame', nil, EllesmereUI.OverlayParent())
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
                -- Controller cursor: not a stop; Cancel clicks the dropdown button, closing the whole list.
                if EllesmereUI.PadCP() then
                    EllesmereUI.PadHint(flyout, "nodepass")
                    flyout.CloseButton = ddBtn
                end

                -- Declared before the children: under the controller cursor they keep the flyout open too.
                local flyoutTimer
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
                            -- Controller cursor: the hidden pointer is never over the flyout, so a child
                            -- keeps it open itself (the mouse path relies on IsMouseOver instead).
                            if flyoutTimer and EllesmereUI.PadCursorShown() then
                                flyoutTimer:Cancel(); flyoutTimer = nil
                            end
                        end)
                        ci:SetScript('OnLeave', function()
                            cLbl:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                            local cur = getValue()
                            cHl:SetAlpha(ci._key == cur and DD_ITEM_SEL_A or 0)
                            -- Controller cursor: leaving a child starts the same close check the parent row
                            -- uses; the next child or the parent row cancels it.
                            if EllesmereUI.PadCursorShown() then
                                if flyoutTimer then flyoutTimer:Cancel() end
                                flyoutTimer = C_Timer.NewTimer(0.25, function()
                                    if not flyout:IsMouseOver() and not item:IsMouseOver() then
                                        flyout:Hide()
                                    end
                                    flyoutTimer = nil
                                end)
                            end
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
                EllesmereUI.TrackOverlay(flyout)
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
                -- Optional second return: a look table for layered swatches,
                -- { base = {r,g,b} solid layer under the texture, tint = {r,g,b},
                --   tile = true } so a row can mirror a compound fill.
                local bgPath, bgLook = _moBackground(key)
                if bgPath then
                    if bgLook and bgLook.base then
                        local b = bgLook.base
                        local baseTex = item:CreateTexture(nil, "BACKGROUND", nil, 0)
                        baseTex:SetAllPoints()
                        baseTex:SetColorTexture(b[1], b[2], b[3], 1)
                        baseTex:SetAlpha(0.45)
                    end
                    local tile = bgLook and bgLook.tile and "REPEAT" or nil
                    local bgTex = item:CreateTexture(nil, "BACKGROUND", nil, 1)
                    bgTex:SetAllPoints()
                    bgTex:SetTexture(bgPath, tile, tile)
                    if tile then bgTex:SetHorizTile(true); bgTex:SetVertTile(true) end
                    bgTex:SetAlpha(0.45)
                    if bgLook and bgLook.tint then
                        -- Alpha rides the colour write (one alpha channel per texture).
                        local t = bgLook.tint
                        bgTex:SetVertexColor(t[1], t[2], t[3], 0.45)
                    elseif _moBgVertexColor then
                        local vr, vg, vb = _moBgVertexColor()
                        if vr then bgTex:SetVertexColor(vr, vg, vb, 1) end
                    end
                end
            end
            local iLbl = MakeFont(item, 13, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
            if _moLabelFont then iLbl:SetFont(_moLabelFont[1], _moLabelFont[2] or 13, _moLabelFont[3] or "") end
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
                        -- Atlas icons carry an intrinsic colour; SetVertexColor only scales it, so desaturate first, then tint to #929292
                        -- (skipped when the menu keeps native colours).
                        local _nr, _ng, _nb = 0.573, 0.573, 0.573
                        local nrmTex = iconBtn:GetNormalTexture()
                        if nrmTex and not _moIconNative then
                            if nrmTex.SetDesaturated then nrmTex:SetDesaturated(true) end
                            nrmTex:SetVertexColor(_nr, _ng, _nb, 1)
                        end
                        local psdTex = iconBtn:GetPushedTexture()
                        if psdTex and not _moIconNative then
                            if psdTex.SetDesaturated then psdTex:SetDesaturated(true) end
                            psdTex:SetVertexColor(_nr, _ng, _nb, 1)
                        end
                        local hlTex = iconBtn:GetHighlightTexture()
                        if hlTex then
                            if not _moIconNative then
                                if hlTex.SetDesaturated then hlTex:SetDesaturated(true) end
                                hlTex:SetVertexColor(_nr, _ng, _nb, 1)
                            end
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
        -- Controller cursor: it scrolls the list to the selected row itself; the pointer-drag thumb is no stop.
        EllesmereUI.PadHint(ddThumb, "nodeignore")

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

        -- Controller helpers, built by the first open that runs with a controller
        -- (menu._padOpen), so a list never opened with one carries none of them.
        padInit = function()
            padInit = nil
            -- The gamepad-driven pointer has no mouse wheel: one step strip above
            -- and one below the list, built the first time that pointer drives the
            -- menu and shown only while it does; the list gives up their height
            -- only then.
            local PAD_STEP_H = 16
            local padUp, padDown
            local function PadStepClick(self)
                local base = ddSmoothing and ddScrollTarget or sf:GetVerticalScroll()
                DDSmoothScrollTo(base + self._dir * SCROLL_STEP)
            end
            local function MakePadStep(dir, edge, y)
                local b = CreateFrame("Button", nil, menu)
                b:SetHeight(PAD_STEP_H)
                b:SetPoint(edge .. "LEFT", menu, edge .. "LEFT", 1, y)
                b:SetPoint(edge .. "RIGHT", menu, edge .. "RIGHT", -1, y)
                b:SetFrameLevel(menu:GetFrameLevel() + 3)
                b._dir = dir
                local hl = SolidTex(b, "ARTWORK", 1, 1, 1, 1)
                hl:SetAllPoints(); hl:SetAlpha(0)
                local arrow = b:CreateTexture(nil, "OVERLAY")
                arrow:SetSize(18, 18)
                arrow:SetPoint("CENTER")
                arrow:SetTexture(MEDIA_PATH .. "icons/eui-arrow.png")
                if dir < 0 then arrow:SetRotation(math.pi) end
                arrow:SetAlpha(0.6)
                b:SetScript("OnEnter", function() hl:SetAlpha(DD_ITEM_HL_A); arrow:SetAlpha(1) end)
                b:SetScript("OnLeave", function() hl:SetAlpha(0); arrow:SetAlpha(0.6) end)
                b:SetScript("OnClick", PadStepClick)
                -- The controller cursor scrolls the list by itself; the strips serve the pointer.
                EllesmereUI.PadHint(b, "nodeignore")
                return b
            end
            padStepSync = function(show)
                if not padUp then
                    if not show then return end
                    padUp = MakePadStep(-1, "TOP", -searchPad)
                    padDown = MakePadStep(1, "BOTTOM", 0)
                end
                padUp:SetShown(show); padDown:SetShown(show)
                local inset = show and PAD_STEP_H or 0
                sf:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, -searchPad - inset)
                sf:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, inset)
            end

            -- Controller cursor: scroll the row it is about to land on into view;
            -- true when that row is inside the visible list afterwards.
            padReveal = function(it)
                local top, itTop = innerContainer:GetTop(), it:GetTop()
                if not (top and itTop) then return false end
                local maxScroll = EllesmereUI.SafeScrollRange(sf)
                local y = (top - itTop) - (sf:GetHeight() - it:GetHeight()) / 2
                y = math.max(0, math.min(maxScroll, y))
                ddSmoothing = false
                ddSmoothFrame:Hide()
                ddScrollTarget = y
                sf:SetVerticalScroll(y)
                UpdateDDThumb()
                local sTop, sBot, iTop, iBot = sf:GetTop(), sf:GetBottom(), it:GetTop(), it:GetBottom()
                return (sTop and sBot and iTop and iBot and iBot < sTop and iTop > sBot) and true or false
            end
        end

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
        -- Focus the dropdown search on open (not under the controller cursor: focus
        -- would pop its on-screen keyboard over the list; its Special press focuses).
        local function FocusSearch()
            searchEdit:SetText("")
            ApplySearchFilter("")
            if not EllesmereUI.PadCursorShown() then searchEdit:SetFocus() end
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

    -- Controller open edge, run by the menu's OnShow (WireDropdownScripts): the
    -- no-wheel step strips for the gamepad-driven pointer, then the controller
    -- cursor onto the selected row (the first row when none is), scrolled into
    -- view. Mouse and keyboard stop at the first gate, unless strips an earlier
    -- controller open showed must be put away.
    menu._padOpen = function()
        if not padStepSync and not EllesmereUI.PadInUse() then return end
        if padInit then padInit() end
        local cursor = EllesmereUI.PadCursorShown()
        -- The controller cursor scrolls the list itself, so the strips are for the pointer only.
        if padStepSync then padStepSync(not cursor and EllesmereUI.PadNative()) end
        if not cursor then return end
        local cur, target = getValue(), nil
        for i = 1, #menuItems do
            local it = menuItems[i]
            if it:IsShown() then
                if not target then target = it end
                if it._key == cur or (it._subnavChildKeys and it._subnavChildKeys[cur]) then
                    target = it
                    break
                end
            end
        end
        -- A row still clipped by the list (its range not laid out yet) cannot take
        -- the cursor: fall back to the first drawn stop in the list.
        if target and padReveal and not padReveal(target) then target = nil end
        EllesmereUI.PadFocus(target or menu)
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
    -- Controller cursor: its Cancel press clicks the dropdown button, which closes the list.
    if EllesmereUI.PadCP() then menu.CloseButton = ddBtn end
    menu:SetScript("OnShow", function(self)
        -- Detect custom parenting via GetParent(); _menuOpts is out of scope here. The
        -- controller-cursor overlay layer covers UIParent 1:1, so it counts as UIParent.
        local mp = menu:GetParent()
        if mp ~= UIParent and mp ~= EllesmereUI._overlayLayer then
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
        -- Controller open edge (step strips, cursor into the list); returns at once without one.
        if menu._padOpen then menu._padOpen() end
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
        -- Controller cursor: back onto the dropdown button (a no-op once that is hidden too).
        if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(ddBtn) end
    end)
    -- A no-op unless the menu sits on the controller-cursor overlay layer.
    EllesmereUI.TrackOverlay(menu)
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
            EllesmereUI._NotifySettingWrite(parent)
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
            EllesmereUI:RefreshPage()
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

    local padNudged = false  -- controller cursor press in progress (see OnMouseDown)
    trackFrame:EnableMouse(true)
    trackFrame:RegisterForDrag("LeftButton")
    trackFrame:SetScript("OnDragStart", function() end)   -- swallow drag so parent window doesn't move
    trackFrame:SetScript("OnDragStop",  function() end)
    trackFrame:SetScript("OnMouseDown", function(_, button)
        if thumb._sliderDisabled then return end
        -- Controller cursor: its press runs this track's mouse scripts with no mouse
        -- button down, so the hidden pointer's position means nothing. Such a press
        -- nudges one step instead (left click up, right click down) and its release
        -- is swallowed.
        if EllesmereUI.PadCursorShown() and not IsMouseButtonDown(button) then
            padNudged = true
            local v = SnapStep(currentVal + (button == "RightButton" and -step or step))
            if v ~= currentVal then
                setValue(v); currentVal = v; rawDragVal = v; lastSnapped = v; UpdateSliderVisual(v)
                -- Same widget-state refresh a typed value gets (CommitInput).
                if not EllesmereUI._sliderDragging then EllesmereUI:RefreshPage() end
            end
            return
        end
        if button == "LeftButton" then BeginDrag() end
    end)
    trackFrame:SetScript("OnMouseUp", function(_, button)
        if padNudged then padNudged = false; return end
        if thumb._sliderDisabled then return end
        if button == "LeftButton" then EndDrag() end
    end)
    -- Controller cursor: the track is the one stop; the pointer-drag thumb is skipped.
    EllesmereUI.PadHint(thumb, "nodeignore")
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
--  Border Size in pixels (the one control every bordered surface uses). Builds a
--  DualRow slider cfg over a surface's legacy size key and its "<key>Px" companion
--  (see EllesmereUI.BorderPx in EllesmereUI.lua). The slider SHOWS the pixels on
--  screen: the exact size when one is set and still paired with the legacy step +
--  texture, else the legacy size (solid = the step; textured = its edge at UIParent
--  scale, 0 = hidden). It WRITES only on a real change: solid 0-4 keeps writing the
--  legacy key alone (clearing a set exact size with false); anything else writes
--  the nearest legacy step (old builds, legacy syncs and overrides keep working)
--  and the exact size beside it. The range is the same on both styles, so a style
--  pick never needs the row rebuilt.
--  spec: getStep() -> number step (labels mapped by the caller), setStep(step),
--        getTex() -> texture key, getPx() -> raw *Px value, setPx(v), apply()
--        (refresh/render after a write), plus any cfg fields to pass through
--        (disabled, disabledTooltip, requireState, rawTooltip, tooltip, text).
-------------------------------------------------------------------------------
function EllesmereUI.BorderPxSliderCfg(spec)
    local gamePP = EllesmereUI.PP
    local mult = (gamePP and gamePP.mult) or 1
    -- The largest legacy edge (Strong = 32 units) must stay reachable at any UI
    -- scale, to the next multiple of 8.
    local maxPx = math.max(32, math.ceil(32 / mult))
    maxPx = math.ceil(maxPx / 8) * 8
    local function Shown()
        local step, tex = spec.getStep(), spec.getTex()
        local px = EllesmereUI.BorderPx(spec.getPx(), step, tex)
        if px then return px end
        return EllesmereUI.BorderLegacyPx(step, tex)
    end
    local cfg = {
        type = "slider", text = spec.text or "Border Size",
        min = 0, max = spec.max or maxPx, step = 1,
        tooltip = spec.tooltip or "Border size in pixels; for a textured style this is the size of its edge art.",
        getValue = Shown,
        setValue = function(v)
            v = math.floor(v + 0.5)
            if v == Shown() then return end          -- a click that changed nothing
            local tex = spec.getTex()
            local solid = not tex or tex == "" or tex == "solid"
            if solid and v <= 4 then
                spec.setStep(v)
                if spec.getPx() then spec.setPx(false) end
            else
                local step = EllesmereUI.BorderPxStep(v, tex)
                if v <= 0 then
                    spec.setStep(0)
                    if spec.getPx() then spec.setPx(false) end
                else
                    spec.setStep(step)
                    spec.setPx(EllesmereUI.BorderPxString(v, step, tex))
                end
            end
            if spec.apply then spec.apply() end
        end,
    }
    for k, v in pairs(spec) do
        if cfg[k] == nil and k ~= "getStep" and k ~= "setStep" and k ~= "getTex"
           and k ~= "getPx" and k ~= "setPx" and k ~= "apply" and k ~= "max" then
            cfg[k] = v
        end
    end
    return cfg
end

-------------------------------------------------------------------------------
--  Border Width Offset | Border Height Offset: the textured border's outward offsets as their
--  own DualRow (shown only while a textured style is selected; the caller builds
--  the row conditionally). Each slider SHOWS what is drawn: the stored override
--  when one is set, else the texture's default for the surface's registry row,
--  scaled to an active exact size exactly as ApplyBorderStyle scales it. It
--  compares in whole slider units: it WRITES nothing on a click that changes
--  nothing, writes nil (follow the default again) when the value lands on the
--  default the slider shows, and stores an override otherwise -- so the
--  per-texture defaults keep seeding the value. With no exact size the shown
--  default is the registry's own whole number.
--  spec: addonKey (nil = the renderer passes none: global per-texture defaults),
--        getTex(), getStep() (the numeric step the renderer passes), getSizeKey()
--        (the registry sizeKey the renderer passes), getPx() (raw companion),
--        getX()/setX(v), getY()/setY(v), apply(), plus pass-through cfg fields.
--  Returns leftCfg, rightCfg.
-------------------------------------------------------------------------------
function EllesmereUI.BorderOffsetRowCfgs(spec)
    local function Defaults()
        local tex = spec.getTex()
        local dx, dy
        if spec.addonKey then
            dx, dy = EllesmereUI.GetBorderDefaults(spec.addonKey, tex, spec.getSizeKey())
        else
            dx = EllesmereUI.GetBorderTextureDefaultOffset(tex)
            dy = EllesmereUI.GetBorderTextureDefaultOffsetY(tex)
        end
        -- An active exact size scales the step's defaults (ApplyBorderStyle's rule).
        local px = EllesmereUI.BorderPx(spec.getPx(), spec.getStep(), tex)
        if px then
            local PPg = EllesmereUI.PP
            local EM = EllesmereUI.BORDER_EDGE_MAP
            local f = (px * PPg.mult) / (EM[spec.getStep()] or EM[1])
            return PPg.Snap(dx * f), PPg.Snap(dy * f)
        end
        return dx, dy
    end
    local lo, hi = spec.min or -25, spec.max or 25
    -- A value as the slider shows it (SnapStep: whole units, clamped).
    local function Unit(x) return math.max(lo, math.min(hi, math.floor(x + 0.5))) end
    local function Make(text, get, set, pick)
        local cfg = {
            type = "slider", text = text, min = lo, max = hi, step = 1,
            getValue = function()
                local v = get()
                if v ~= nil then return v end
                return Unit(pick(Defaults()))
            end,
            setValue = function(v)
                v = Unit(v)
                local cur = get()
                local def = Unit(pick(Defaults()))
                if v == (cur ~= nil and Unit(cur) or def) then return end
                if v == def then set(nil) else set(v) end
                if spec.apply then spec.apply() end
            end,
        }
        for k, val in pairs(spec) do
            if cfg[k] == nil and k ~= "addonKey" and k ~= "getTex" and k ~= "getStep" and k ~= "getSizeKey"
               and k ~= "getPx" and k ~= "getX" and k ~= "setX" and k ~= "getY" and k ~= "setY"
               and k ~= "apply" and k ~= "min" and k ~= "max" then
                cfg[k] = val
            end
        end
        return cfg
    end
    return Make("Border Width Offset", spec.getX, spec.setX, function(x) return x end),
           Make("Border Height Offset", spec.getY, spec.setY, function(_, y) return y end)
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

-- Helpers the other EllesmereUI_Widgets_*.lua files share; not public API.
EllesmereUI._widgetInternals = {
    SL = SL,
    TagOptionRow = TagOptionRow,
    DDResolveLabel = DDResolveLabel,
    IndexSlotForSearch = IndexSlotForSearch,
    AddControlDisabledTooltip = AddControlDisabledTooltip,
    PixelizeSliderCfg = PixelizeSliderCfg,
    QueueLabelClamp = QueueLabelClamp,
    LabelTooltipText = LabelTooltipText,
}

-------------------------------------------------------------------------------
--  Exports  (widget helpers EllesmereUI table for EllesmereUI_Presets.lua)
-------------------------------------------------------------------------------
EllesmereUI.DDText              = DDText
EllesmereUI.BuildDropdownMenu   = BuildDropdownMenu
EllesmereUI.WireDropdownScripts = WireDropdownScripts
EllesmereUI.WD_DD_COLOURS       = WD_DD_COLOURS
EllesmereUI.RD_DD_COLOURS       = RD_DD_COLOURS
--------------------------------------------------------------------------------
--  Preview click-to-navigate kit (options pages with a clickable preview)
--------------------------------------------------------------------------------
-- MakeSettingGlow: returns play(target, holdWhile). One frame per returned
-- function, reparented on each play, so a new glow cancels the last one.
-- opts: color {r,g,b} (read on first play), thickness (number or function,
-- default 2), noSnap. holdWhile pulses while it returns true and the target
-- is visible, then plays the normal 0.75s fade.
EllesmereUI.MakeSettingGlow = function(opts)
    local glow
    return function(targetFrame, holdWhile)
        if not targetFrame then return end
        if not glow then
            glow = CreateFrame("Frame")
            local c = opts.color
            local px = opts.thickness or 2
            if type(px) == "function" then px = px() end
            local function MkEdge()
                local t = glow:CreateTexture(nil, "OVERLAY", nil, 7)
                t:SetColorTexture(c.r, c.g, c.b, 1)
                if opts.noSnap and t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
                return t
            end
            local top, bot, lft, rgt = MkEdge(), MkEdge(), MkEdge(), MkEdge()
            top:SetHeight(px); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
            bot:SetHeight(px); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
            lft:SetWidth(px)
            lft:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); lft:SetPoint("BOTTOMLEFT", bot, "TOPLEFT")
            rgt:SetWidth(px)
            rgt:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT"); rgt:SetPoint("BOTTOMRIGHT", bot, "TOPRIGHT")
        end
        glow:SetParent(targetFrame)
        glow:SetAllPoints(targetFrame)
        glow:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
        glow:SetAlpha(1)
        glow:Show()
        local elapsed = 0
        glow:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if holdWhile then
                if targetFrame:IsVisible() and holdWhile() then
                    self:SetAlpha(0.35 + 0.65 * math.abs(math.sin(elapsed * 3)))
                    return
                end
                -- Released: restart the clock so the fade plays from full alpha.
                holdWhile, elapsed = nil, 0
            end
            if elapsed >= 0.75 then
                self:Hide(); self:SetScript("OnUpdate", nil); return
            end
            self:SetAlpha(1 - elapsed / 0.75)
        end)
    end
end

-- CreatePreviewHitOverlay: clickable button over a preview element that calls
-- navigate(key). opts (per call): hlAnchor, hlBehindText, parent, showWith.
-- style (per page): container = draw the hover border on a child frame (and
-- hlBehindText adds a frame at element level+1); tightText = AB text sizing.
-- Returns btn, hlBase, hlCont (the last two only with style.container).
EllesmereUI.CreatePreviewHitOverlay = function(element, navigate, key, isText, frameLevelOverride, opts, style)
    local tight = style and style.tightText
    local anchor = isText and element:GetParent() or element
    if not anchor.CreateTexture then anchor = anchor:GetParent() end
    local btn = CreateFrame("Button", nil, anchor)
    if isText then
        local minS, pad = tight and 1 or 4, tight and 2 or 4
        local function ResizeToText()
            local ok, tw, th = pcall(function()
                local w = element:GetStringWidth() or 0
                local hh = element:GetStringHeight() or 0
                if w < minS then w = minS end
                if hh < minS then hh = minS end
                return w, hh
            end)
            if not ok then tw = 40; th = 12 end
            btn:SetSize(tw + pad, th + pad)
        end
        ResizeToText()
        local justify = element:GetJustifyH()
        if justify == "RIGHT" then btn:SetPoint("RIGHT", element, "RIGHT", tight and 0 or 2, 0)
        elseif justify == "CENTER" then btn:SetPoint("CENTER", element, "CENTER", tight and -1 or 0, 0)
        else btn:SetPoint("LEFT", element, "LEFT", -2, 0) end
        btn:SetScript("OnShow", function() ResizeToText() end)
        btn._resizeToText = ResizeToText
    else
        btn:SetAllPoints(opts and opts.hlAnchor or element)
    end
    -- opts.parent hosts the button outside a SetClipsChildren ancestor (which
    -- blocks mouse to descendants); opts.showWith re-ties its visibility.
    if opts and opts.parent then btn:SetParent(opts.parent) end
    btn:SetFrameLevel(frameLevelOverride or (anchor:GetFrameLevel() + 20))
    btn:RegisterForClicks("LeftButtonDown")
    local c = EllesmereUI.ELLESMERE_GREEN
    local hlBase, hlCont, brd
    if style and style.container then
        if opts and opts.hlBehindText then
            hlBase = CreateFrame("Frame", nil, element)
            hlBase:SetAllPoints()
            hlBase:SetFrameLevel(element:GetFrameLevel() + 1)
        else
            hlBase = (opts and opts.hlAnchor) or btn
        end
        hlCont = CreateFrame("Frame", nil, hlBase)
        hlCont:SetAllPoints()
        hlCont:SetFrameLevel(hlBase:GetFrameLevel() + 1)
        brd = EllesmereUI.PP.CreateBorder(hlCont, c.r, c.g, c.b, 1, 2, "OVERLAY", 7)
    else
        local hlTarget = (opts and opts.hlBehindText) and element or (opts and opts.hlAnchor) or btn
        brd = EllesmereUI.PP.CreateBorder(hlTarget, c.r, c.g, c.b, 1, 2, "OVERLAY", 7)
    end
    brd:Hide()
    btn:SetScript("OnEnter", function() brd:Show() end)
    btn:SetScript("OnLeave", function() brd:Hide() end)
    btn:SetScript("OnMouseDown", function() navigate(key) end)
    local sw = opts and opts.showWith
    if sw then
        sw:HookScript("OnShow", function() btn:Show() end)
        sw:HookScript("OnHide", function() btn:Hide() end)
        btn:SetShown(sw:IsShown())
    end
    return btn, hlBase, hlCont
end

-- DismissPreviewHint: first preview click marks the hint dismissed and fades
-- it out over 0.3s while the content header shrinks back to headerBaseH.
-- startY: fallback hint offset. The header shrinks by hintH, the height the
-- hint added, so it lands exactly on headerBaseH.
EllesmereUI.DismissPreviewHint = function(hint, headerBaseH, hintH, startY)
    if (EllesmereUIDB and EllesmereUIDB.previewHintDismissed) or not (hint and hint:IsShown()) then return end
    EllesmereUIDB = EllesmereUIDB or {}
    EllesmereUIDB.previewHintDismissed = true
    local _, anchorTo, _, _, y0 = hint:GetPoint(1)
    y0 = y0 or startY
    anchorTo = anchorTo or hint:GetParent()
    local startHeaderH = headerBaseH + hintH
    local steps = 0
    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        steps = steps + 1
        local progress = steps * 0.016 / 0.3
        if progress >= 1 then
            hint:Hide(); ticker:Cancel()
            if headerBaseH > 0 then EllesmereUI:SetContentHeaderHeightSilent(headerBaseH) end
            return
        end
        hint:SetAlpha(0.45 * (1 - progress))
        hint:ClearAllPoints()
        hint:SetPoint("BOTTOM", anchorTo, "BOTTOM", 0, y0 + progress * 12)
        local hh = startHeaderH - hintH * progress
        if hh > 0 then EllesmereUI:SetContentHeaderHeightSilent(hh) end
    end)
end

EllesmereUI.BuildSliderCore     = BuildSliderCore
EllesmereUI.BuildDropdownControl = BuildDropdownControl
EllesmereUI.BuildToggleControl   = BuildToggleControl
EllesmereUI.BuildCheckboxControl = BuildCheckboxControl

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
        menu = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
        EllesmereUI._pickMenu = menu
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(220)
        menu:EnableMouse(true)
        menu:SetClampedToScreen(true)
        local bg = menu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.067, 0.067, 0.067, 0.98)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, 0.2)

        local catcher = CreateFrame("Button", nil, EllesmereUI.OverlayParent())
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(210)
        catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        catcher:SetScript("OnClick", function() menu:Hide() end)
        catcher:Hide()
        menu._catcher = catcher
        menu:SetScript("OnHide", function(self)
            self._catcher:Hide()
            -- Controller cursor: back onto the tile that opened it (set only under that cursor).
            local opener = self._padOpener
            if opener then
                self._padOpener = nil
                if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(opener) end
            end
        end)
        menu:SetScript("OnShow", function(self) self._catcher:Show() end)
        -- Controller cursor: on its overlay layer the menu is created hidden, so the
        -- layer shows only with it; the menu and its catcher block what they cover
        -- without being stops, and Cancel clicks the catcher (closing the menu).
        if EllesmereUI.PadCP() then
            menu:Hide()
            EllesmereUI.PadHint(menu, "nodepass")
            EllesmereUI.PadHint(catcher, "nodepass")
            menu.CloseButton = catcher
            EllesmereUI.TrackOverlay(catcher)
            EllesmereUI.TrackOverlay(menu)
        end

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
    -- Controller cursor: the hidden pointer is not on the tile; open at the tile, cursor into the list.
    local padCursor = EllesmereUI.PadCursorShown()
    if padCursor and anchor then
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    else
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 2, cy / scale + 2)
    end
    menu:Show()
    if padCursor then
        menu._padOpener = anchor
        EllesmereUI.PadFocus(menu)
    end
end

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
