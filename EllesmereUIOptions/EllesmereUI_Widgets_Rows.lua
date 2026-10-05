if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_Rows.lua
--  Factory rows: buttons, the keybind button, DualRow, TripleRow and the
--  other multi-slot rows. Reads BuildColorSwatch, so it loads after
--  EllesmereUI_Widgets_Color.lua.
--  DEFERRED: body runs on first EllesmereUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()
local PP = EllesmereUI.PanelPP
local SolidTex = EllesmereUI.SolidTex
local MakeFont = EllesmereUI.MakeFont
local MakeBorder = EllesmereUI.MakeBorder
local RowBg = EllesmereUI.RowBg
local MakeDropdownArrow = EllesmereUI.MakeDropdownArrow
local RegisterWidgetRefresh = EllesmereUI.RegisterWidgetRefresh
local EXPRESSWAY = EllesmereUI.EXPRESSWAY
local CONTENT_PAD = EllesmereUI.CONTENT_PAD
local TEXT_WHITE_R = EllesmereUI.TEXT_WHITE_R
local TEXT_WHITE_G = EllesmereUI.TEXT_WHITE_G
local TEXT_WHITE_B = EllesmereUI.TEXT_WHITE_B
local BORDER_R = EllesmereUI.BORDER_R
local BORDER_G = EllesmereUI.BORDER_G
local BORDER_B = EllesmereUI.BORDER_B
local DD_BG_R = EllesmereUI.DD_BG_R
local DD_BG_G = EllesmereUI.DD_BG_G
local DD_BG_B = EllesmereUI.DD_BG_B
local DD_BG_A = EllesmereUI.DD_BG_A
local DD_BG_HA = EllesmereUI.DD_BG_HA
local DD_BRD_A = EllesmereUI.DD_BRD_A
local DD_TXT_A = EllesmereUI.DD_TXT_A
local DUAL_ITEM_W = EllesmereUI.DUAL_ITEM_W
local DUAL_GAP = EllesmereUI.DUAL_GAP
local TRIPLE_ITEM_W = EllesmereUI.TRIPLE_ITEM_W
local TRIPLE_GAP = EllesmereUI.TRIPLE_GAP
local MakeStyledButton = EllesmereUI.MakeStyledButton
local WB_COLOURS = EllesmereUI.WB_COLOURS
local RB_COLOURS = EllesmereUI.RB_COLOURS
local ShowWidgetTooltip = EllesmereUI.ShowWidgetTooltip
local HideWidgetTooltip = EllesmereUI.HideWidgetTooltip
local DisabledTooltip = EllesmereUI.DisabledTooltip
local isRussian = GetLocale() == "ruRU"
local WI = EllesmereUI._widgetInternals
local SL = WI.SL
local TagOptionRow = WI.TagOptionRow
local DDResolveLabel = WI.DDResolveLabel
local IndexSlotForSearch = WI.IndexSlotForSearch
local AddControlDisabledTooltip = WI.AddControlDisabledTooltip
local PixelizeSliderCfg = WI.PixelizeSliderCfg
local QueueLabelClamp = WI.QueueLabelClamp
local LabelTooltipText = WI.LabelTooltipText
local WidgetFactory = EllesmereUI.Widgets
local ResolveDisabledTip = EllesmereUI.ResolveDisabledTip
local BuildDropdownMenu = EllesmereUI.BuildDropdownMenu
local WireDropdownScripts = EllesmereUI.WireDropdownScripts
local WD_DD_COLOURS = EllesmereUI.WD_DD_COLOURS
local BuildSliderCore = EllesmereUI.BuildSliderCore
local BuildDropdownControl = EllesmereUI.BuildDropdownControl
local BuildToggleControl = EllesmereUI.BuildToggleControl
local BuildCheckboxControl = EllesmereUI.BuildCheckboxControl
local BuildColorSwatch = EllesmereUI.BuildColorSwatch

-- cfg.tooltipOnControl: a slider's tooltip also shows while hovering the slider
-- itself, not only its label (true = cfg.tooltip; a string = its own text for
-- the slider, the label keeping cfg.tooltip). One motion-only hit frame spans
-- the track, thumb and value box, so crossing the thumb or the gap never blinks
-- the tooltip. A frame that takes motion is still the mouse focus and would
-- drop every click, so clicks (and motion, for the value box's text cursor)
-- propagate to the controls beneath. Never shown mid-drag or while disabled
-- (the disabled tooltip covers that); a press hides it.
local function AttachSliderTooltip(region, label, cfg, trackFrame, thumb, valBox)
    local own = type(cfg.tooltipOnControl) == "string" and cfg.tooltipOnControl
    if not (own or (cfg.tooltip and cfg.tooltipOnControl)) then return end
    local hit = CreateFrame("Frame", nil, region)
    -- Starts half a thumb before the track: the thumb overhangs it at the minimum.
    local overhang = thumb and thumb:GetWidth() / 2 or 0
    hit:SetPoint("TOPLEFT", trackFrame, "LEFT", -overhang, valBox:GetHeight() / 2)
    hit:SetPoint("BOTTOMRIGHT", valBox, "BOTTOMRIGHT")
    -- Above the thumb and value box, below the disabled-tooltip hit (+10).
    hit:SetFrameLevel(trackFrame:GetFrameLevel() + 5)
    hit:SetMouseClickEnabled(false)
    EllesmereUI.PadHint(hit, "nodeignore")
    hit:SetScript("OnEnter", function()
        if EllesmereUI._sliderDragging or (cfg.disabled and cfg.disabled()) then return end
        ShowWidgetTooltip(hit, own or LabelTooltipText(region, label, cfg.tooltip), cfg.tooltipOpts)
    end)
    local function Hide() HideWidgetTooltip() end
    hit:SetScript("OnLeave", Hide)
    hit:SetPropagateMouseClicks(true)
    hit:SetPropagateMouseMotion(true)
    trackFrame:HookScript("OnMouseDown", Hide)
    if thumb then thumb:HookScript("OnMouseDown", Hide) end
    valBox:HookScript("OnMouseDown", Hide)
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

-- Keybind capture button: left-click arms, the next key (with its modifiers) is the
-- chord, Escape cancels, right-click unbinds. set(chord) writes, set(nil) unbinds;
-- the caller anchors it. opts: w, h, pp (default PanelPP), level, font, get, set,
-- tooltip, disabled + disabledTip (string, or fn returning one), mouse (armed clicks bind mouse chords),
-- plainMouse (with mouse: an armed bare left/right click binds too, so unbind
-- is a right-click from rest), canArm (returns false to refuse arming).
-- Returns btn, refresh.
function EllesmereUI.BuildKeybindButton(parent, opts)
    local btn = CreateFrame("Button", nil, parent)
    local pp = opts.pp or PP
    pp.Size(btn, opts.w, opts.h)
    btn:SetFrameLevel(parent:GetFrameLevel() + (opts.level or 2))
    if opts.mouse then
        btn:RegisterForClicks("AnyUp")
    else
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    local bg = SolidTex(btn, "BACKGROUND", DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
    bg:SetAllPoints()
    btn._border = MakeBorder(btn, 1, 1, 1, DD_BRD_A, pp)
    local lbl = MakeFont(btn, opts.font or 12, nil, 1, 1, 1)
    lbl:SetAlpha(DD_TXT_A)
    lbl:SetPoint("CENTER")

    local disabled = opts.disabled
    local listening = false
    -- Controller buttons: padArmed while they are captured; padHeld is the button
    -- whose press ended capture, kept captured until its release.
    local padArmed, padWired, padHeld = false, false, nil
    local function Stop()
        listening = false
        btn:EnableKeyboard(false)
        if padArmed and not padHeld then padArmed = false; btn:EnableGamePadButton(false) end
        -- OnLeave keeps the hover look while armed; drop it once capture ends.
        if not btn:IsMouseOver() then
            bg:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
            btn._border:SetColor(1, 1, 1, DD_BRD_A)
        end
    end
    local function FormatKey(key)
        if not key or key == "" then return EllesmereUI.L("Not Bound") end
        local parts = {}
        for mod in key:gmatch("(%u+)%-") do
            parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
        end
        parts[#parts + 1] = key:match("[^%-]+$") or key
        return table.concat(parts, " + ")
    end
    local function Refresh()
        if disabled then
            local off = disabled()
            -- Mouse stays on so the disabled tooltip can show; OnClick refuses.
            btn:SetAlpha(off and 0.3 or 1)
            if parent._label then parent._label:SetAlpha(off and 0.3 or 1) end
            if off and listening then Stop() end
        end
        if not listening then lbl:SetText(FormatKey(opts.get())) end
    end
    local function Commit(chord)
        Stop()
        opts.set(chord)
        Refresh()
    end

    btn:SetScript("OnClick", function(self, button)
        if disabled and disabled() then return end
        -- OnKeyDown never sees mouse buttons; plain left/right keep arm/unbind
        -- unless plainMouse.
        if opts.mouse and listening and ((button ~= "LeftButton" and button ~= "RightButton")
            or IsModifierKeyDown() or opts.plainMouse) then
            Commit(CreateKeyChordStringUsingMetaKeyState(GetConvertedKeyOrButton(button)))
            return
        end
        if button == "RightButton" then Commit(nil); return end
        if button ~= "LeftButton" or listening then return end
        if opts.canArm and not opts.canArm() then return end
        listening = true
        lbl:SetText(EllesmereUI.L("Press a key..."))
        self:EnableKeyboard(true)
        -- Controller in use: its buttons are captured too, only while armed (Stop turns it off).
        if EllesmereUI.PadInUse() then
            if not padWired then
                padWired = true
                -- Armed: the button bound to the pause menu cancels, as Escape does on the
                -- keyboard; a button set up as an emulated modifier passes through so it can
                -- be held for a chord; anything else is the chord. The press that ends capture
                -- is consumed down AND up (padHeld): a controller cursor clicks on release, so
                -- a loose release would click this button again (re-arm, or unbind).
                self:SetScript("OnGamePadButtonDown", function(s, key)
                    if not listening then
                        s:SetPropagateKeyboardInput(true)
                        return
                    end
                    if GetBindingFromClick(key) == "TOGGLEGAMEMENU" then
                        s:SetPropagateKeyboardInput(false)
                        padHeld = key
                        Stop(); Refresh()
                        return
                    end
                    local k = GetConvertedKeyOrButton(key)
                    if IsKeyPressIgnoredForBinding(k) or k == GetCVar("GamePadEmulateShift")
                        or k == GetCVar("GamePadEmulateCtrl") or k == GetCVar("GamePadEmulateAlt") then
                        s:SetPropagateKeyboardInput(true)
                        return
                    end
                    s:SetPropagateKeyboardInput(false)
                    padHeld = key
                    Commit(CreateKeyChordStringUsingMetaKeyState(k))
                end)
                self:SetScript("OnGamePadButtonUp", function(s, key)
                    if key ~= padHeld then
                        s:SetPropagateKeyboardInput(true)
                        return
                    end
                    s:SetPropagateKeyboardInput(false)
                    padHeld = nil
                    if not listening then padArmed = false; s:EnableGamePadButton(false) end
                end)
            end
            padArmed = true
            self:EnableGamePadButton(true)
        end
    end)
    btn:SetScript("OnKeyDown", function(self, key)
        -- Bare modifiers pass through so they can be held for the chord.
        if not listening or IsKeyPressIgnoredForBinding(key) then
            self:SetPropagateKeyboardInput(true)
            return
        end
        self:SetPropagateKeyboardInput(false)
        if key == "ESCAPE" then Stop(); Refresh(); return end
        Commit(CreateKeyChordStringUsingMetaKeyState(key))
    end)
    btn:SetScript("OnEnter", function(self)
        if disabled and disabled() then
            local tip = opts.disabledTip
            if type(tip) == "function" then tip = tip() end
            ShowWidgetTooltip(self, DisabledTooltip(tip))
            return
        end
        bg:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_HA)
        btn._border:SetColor(1, 1, 1, 0.3)
        ShowWidgetTooltip(self, opts.tooltip or EllesmereUI.L("Left-click to set a keybind.\nRight-click to unbind."))
    end)
    btn:SetScript("OnLeave", function()
        HideWidgetTooltip()
        if listening then return end
        bg:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
        btn._border:SetColor(1, 1, 1, DD_BRD_A)
    end)
    btn:SetScript("OnHide", function()
        if listening then Stop(); Refresh() end
        -- A hidden button gets no release: drop a controller press still held.
        if padHeld then padHeld = nil; padArmed = false; btn:EnableGamePadButton(false) end
        -- Hidden is never hovered: always come back in the resting look.
        bg:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
        btn._border:SetColor(1, 1, 1, DD_BRD_A)
        HideWidgetTooltip()
    end)

    Refresh()
    return btn, Refresh
end

-- DualRow: two widgets side by side on one full-width row, 1px center divider.
-- Slider:      { type="slider", text, min, max, step, getValue, setValue }
-- Dropdown:    { type="dropdown", text, values, getValue, setValue, order }
-- Toggle:      { type="toggle", text, getValue, setValue }
-- ColorPicker: { type="colorpicker", text, getValue, setValue, hasAlpha }
function WidgetFactory:DualRow(parent, yOffset, leftCfg, rightCfg)
    local ROW_H = 50
    local SIDE_PAD = 20  -- padding inside each half
    -- Blizzard Style: a row whose every control is gated for the active style is built (callers still hang cogs and sync icons on its regions) but hidden, takes no row background or search entry, and returns no height, so the page reads as if it were not there.
    local BS = EllesmereUI.BlizzStyle
    local hiddenRow = BS and BS.RowHidden and BS.RowHidden(leftCfg, rightCfg)
    local frame = CreateFrame("Frame", nil, parent)
    local totalW = parent:GetWidth() - CONTENT_PAD * 2
    PP.Size(frame, totalW, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)
    if not rightCfg then frame._skipRowDivider = true end
    if not hiddenRow then
        RowBg(frame, parent)
        -- Search metadata: combined label on the frame (inline page search), one global-index entry per slot.
        local dualLabel = (leftCfg and leftCfg.text or "")
        if rightCfg and rightCfg.text then dualLabel = dualLabel .. " " .. rightCfg.text end
        TagOptionRow(frame, parent, dualLabel, nil, true)
        IndexSlotForSearch(parent, leftCfg and leftCfg.text, leftCfg and leftCfg.tooltip)
        IndexSlotForSearch(parent, rightCfg and rightCfg.text, rightCfg and rightCfg.tooltip)
    end

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
        region._cfg = cfg
        region._labelHasHit = (cfg.tooltip or cfg.disabledTooltip) and true or false

        -- Label tooltip. For dropdowns the hitFrame is created after the dropdown button so it can check whether the menu is open.
        -- A half-row button hides its label (the button explains its own lock, below).
        if (cfg.tooltip or cfg.disabledTooltip) and t ~= "dropdown" and t ~= "button" then
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
            AttachSliderTooltip(region, label, cfg, trackFrame, slThumb, valBox)
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
                            -- cfg.itemRequireState: "disabled" flips the wrapper's verb
                            -- for a bare requirement noun (nil = "enabled", as before).
                            if tip then return DisabledTooltip(tip, cfg.itemRequireState) end
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
            AddControlDisabledTooltip(btn, cfg)
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

    if hiddenRow then
        -- The inline page search re-shows and re-anchors every row it has
        -- collected whenever it resets; keep this one out of its hands.
        frame._searchIgnore = true
        frame:Hide()
        return frame, 0
    end
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
        region._cfg = cfg
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
            AttachSliderTooltip(region, label, cfg, trackFrame, slThumb, valBox)
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
                            -- cfg.itemRequireState: "disabled" flips the wrapper's verb
                            -- for a bare requirement noun (nil = "enabled", as before).
                            if tip then return DisabledTooltip(tip, cfg.itemRequireState) end
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

end  -- end deferred init
