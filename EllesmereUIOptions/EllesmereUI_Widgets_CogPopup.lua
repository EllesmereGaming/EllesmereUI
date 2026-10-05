if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_CogPopup.lua
--  BuildCogPopup, the shared cog settings popup. Reads BuildColorSwatch, so
--  it loads after EllesmereUI_Widgets_Color.lua.
--  DEFERRED: body runs on first EllesmereUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()
local PP = EllesmereUI.PanelPP
local SolidTex = EllesmereUI.SolidTex
local MakeFont = EllesmereUI.MakeFont
local MakeBorder = EllesmereUI.MakeBorder
local MakeDropdownArrow = EllesmereUI.MakeDropdownArrow
local EXPRESSWAY = EllesmereUI.EXPRESSWAY
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN
local BORDER_COLOR = EllesmereUI.BORDER_COLOR
local WI = EllesmereUI._widgetInternals
local PixelizeSliderCfg = WI.PixelizeSliderCfg
local ResolveDisabledTip = EllesmereUI.ResolveDisabledTip
local DDText = EllesmereUI.DDText
local BuildSliderCore = EllesmereUI.BuildSliderCore
local BuildDropdownControl = EllesmereUI.BuildDropdownControl
local BuildToggleControl = EllesmereUI.BuildToggleControl
local BuildColorSwatch = EllesmereUI.BuildColorSwatch

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
    -- row.hidden (a function): the row is left out while it returns true. A
    -- popup with such rows builds one frame per set of shown rows (cached, so
    -- a flip back reuses it) and swaps to the matching one when a change made
    -- inside it flips a row; a popup without them builds once, as always.
    local dynamic = false
    if opts.rows then
        for _, row in ipairs(opts.rows) do
            if row.hidden then dynamic = true; break end
        end
    end
    local variants = dynamic and {} or nil
    local function HiddenSig()
        if not dynamic then return "" end
        local sig = ""
        for i, row in ipairs(opts.rows) do
            if row.hidden and row.hidden() then sig = sig .. i .. "," end
        end
        return sig
    end
    local SwapVariant  -- set below showFn; the refresh pass calls it

    -- Spec Overrides auto-capture: cog row writes attribute to the cog's anchor button, which sits inside the host slot's region.
    if opts.rows then
        for _, row in ipairs(opts.rows) do
            if row.set then
                local _s = row.set
                row.set = function(...)
                    _s(...)
                    EllesmereUI._NotifySettingWrite(popupOwner or opts.captureRegion)
                end
            end
        end
    end

    local function CreatePopup(sig)
        local rowWidgets = {}  -- per-row refresh info
        -- The rows this frame shows (all of them without row.hidden).
        local rows = opts.rows
        if dynamic then
            rows = {}
            for _, row in ipairs(opts.rows) do
                if not (row.hidden and row.hidden()) then rows[#rows + 1] = row end
            end
        end
        -- Measure slider labels to find maxLblW
        local tmpFS = UIParent:CreateFontString(nil, "OVERLAY")
        tmpFS:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
        local COG_DD_W = 130
        local maxLblW = 0
        -- Widest label + dropdown pair (a dropdown or checkbox-list row may ask
        -- for a wider control with row.ddWidth; every other row uses COG_DD_W).
        local maxDDNeed = COG_DD_W
        for _, row in ipairs(opts.rows) do
            if row.type == "slider" or row.type == "input" then
                tmpFS:SetText(EllesmereUI.L(row.label))
                local w = tmpFS:GetStringWidth()
                if w > maxLblW then maxLblW = w end
            elseif row.type == "dropdown" or row.type == "segmented" or row.type == "reordercheck" then
                tmpFS:SetText(EllesmereUI.L(row.label))
                local w = tmpFS:GetStringWidth() + (((row.type == "dropdown" or row.type == "reordercheck") and row.ddWidth) or COG_DD_W)
                if w > maxDDNeed then maxDDNeed = w end
            end
        end
        tmpFS:Hide()
        if maxLblW < 10 then maxLblW = 60 end

        local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
        local TARGET_W = opts.minWidth or 260
        local SLIDER_W = math.max(80, TARGET_W - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
        local POPUP_W = math.max(opts.minWidth or MIN_POPUP_W, SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD)
        -- Widen for dropdown rows (label + gap + dropdown + padding)
        local ddNeeded = SIDE_PAD + maxDDNeed + LABEL_SLIDER_GAP + SIDE_PAD
        if ddNeeded > POPUP_W then POPUP_W = ddNeeded end
        if opts.minWidth and opts.minWidth > POPUP_W then POPUP_W = opts.minWidth end
        -- Stretch the track to fill a widened popup so no gap opens between the slider and its value box. Gated on minWidth so un-widened cog popups keep their original slider width.
        if opts.minWidth then
            SLIDER_W = math.max(SLIDER_W, POPUP_W - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
        end

        local totalH = TOP_PAD + TITLE_H + TITLE_GAP
        for i, row in ipairs(rows) do
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

        local pf = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
        pf:SetSize(POPUP_W, totalH)
        pf:SetFrameStrata(opts.frameStrata or "DIALOG"); pf:SetFrameLevel(opts.frameLevel or 200)
        pf:EnableMouse(true); pf:Hide()
        -- Spec Overrides auto-capture: edits inside this popup attribute to the slot whose cog opened it.
        pf._euiOptionsPopup = true
        -- Controller cursor: the popup blocks what is under it but is not a stop itself.
        EllesmereUI.PadHint(pf, "nodepass")

        -- Match panel scale so the popup matches scrollable-area widgets
        local ppScale = EllesmereUI.GetPopupScale() or 1
        pf:SetScale(ppScale)
        if EllesmereUI._popupFrames then
            EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = pf }
        end

        local bg = SolidTex(pf, "BACKGROUND", 0.077, 0.068, 0.058, opts.bgAlpha or 0.95)
        bg:SetAllPoints()
        MakeBorder(pf, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15, PP)

        local titleFS = MakeFont(pf, TITLE_H, "", 1, 1, 1)
        titleFS:SetAlpha(0.7)
        titleFS:SetPoint("TOP", pf, "TOP", 0, -TOP_PAD)
        titleFS:SetText(EllesmereUI.L(opts.title or ""))

        local curY = -(TOP_PAD + TITLE_H + TITLE_GAP)
        -- A dropdown-height row's disabled overlay (row.disabled set): dims the row,
        -- blocks it and explains the lock; the refresh shows it while disabled.
        local function RowDisabledOverlay(row, y)
            if not row.disabled then return nil end
            local dis = CreateFrame("Frame", nil, pf)
            dis:SetPoint("TOPLEFT", pf, "TOPLEFT", 1, y)
            dis:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -1, y)
            dis:SetHeight(DROPDOWN_ROW_H)
            dis:SetFrameLevel(pf:GetFrameLevel() + 10)
            dis:EnableMouse(true)
            local disTex = SolidTex(dis, "OVERLAY", 0.077, 0.068, 0.058, 0.70)
            disTex:SetAllPoints()
            dis:SetScript("OnEnter", function(self)
                local tip = ResolveDisabledTip(row)
                if tip and EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, tip)
                end
            end)
            dis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            return dis
        end
        for i, row in ipairs(rows) do
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
                        EllesmereUI.ShowWidgetTooltip(lbl, row.tooltip)
                    end)
                    hitFrame:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
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
                    local disTex = SolidTex(sliderDis, "OVERLAY", 0.077, 0.068, 0.058, 0.70)
                    disTex:SetAllPoints()
                    sliderDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    sliderDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
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
                        EllesmereUI.ShowWidgetTooltip(lbl, row.tooltip)
                    end)
                    hitFrame:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
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
                    local disTex = SolidTex(toggleDis, "OVERLAY", 0.077, 0.068, 0.058, 0.70)
                    disTex:SetAllPoints()
                    toggleDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    toggleDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                end

                rowWidgets[#rowWidgets + 1] = { type = "toggle", updateVisual = UpdateToggleVisual, disOverlay = toggleDis, disCheck = row.disabled }
                curY = curY - TOGGLE_ROW_H
            elseif row.type == 'dropdown' then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
                lbl:SetPoint('LEFT', pf, 'TOPLEFT', SIDE_PAD, curY - DROPDOWN_ROW_H / 2 - 1)

                -- Cog-popup dropdowns render 10% smaller than the panel dropdowns.
                local DD_SCALE = 0.9
                local ddBtn, ddLbl = BuildDropdownControl(pf, row.ddWidth or COG_DD_W, pf:GetFrameLevel() + 2, row.values, row.order, row.get, function(v)
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
                local ddDis = RowDisabledOverlay(row, curY)

                rowWidgets[#rowWidgets + 1] = { type = 'dropdown', btn = ddBtn, lbl = ddLbl, get = row.get, values = row.values, refresh = ddBtn._ddRefresh, disOverlay = ddDis, disCheck = row.disabled }
                curY = curY - DROPDOWN_ROW_H
            elseif row.type == 'reordercheck' then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
                lbl:SetPoint('LEFT', pf, 'TOPLEFT', SIDE_PAD, curY - DROPDOWN_ROW_H / 2 - 1)

                local items = type(row.items) == "function" and row.items() or row.items or {}
                local ddBtn, refresh = EllesmereUI.BuildReorderCBDropdown(
                    pf, row.ddWidth or COG_DD_W, pf:GetFrameLevel() + 2, items,
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
                local rcDis = RowDisabledOverlay(row, curY)

                rowWidgets[#rowWidgets + 1] = { type = 'reordercheck', btn = ddBtn, refresh = refresh, disOverlay = rcDis, disCheck = row.disabled }
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
                    local disTex = SolidTex(segDis, "OVERLAY", 0.077, 0.068, 0.058, 0.70)
                    disTex:SetAllPoints()
                    segDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    segDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                end

                rowWidgets[#rowWidgets + 1] = { type = 'segmented', seg = seg, refresh = segRefresh, disOverlay = segDis, disCheck = row.disabled }
                curY = curY - TOGGLE_ROW_H
            elseif row.type == 'colorpicker' then
                local lbl = MakeFont(pf, 11, nil, 1, 1, 1); lbl:SetAlpha(0.6)
                lbl:SetText(EllesmereUI.L(row.label))
                lbl:SetPoint('LEFT', pf, 'TOPLEFT', SIDE_PAD, curY - ROW_H / 2 - 1)

                if row.tooltip then
                    local hitFrame = CreateFrame("Frame", nil, pf)
                    hitFrame:SetPoint("TOPLEFT", lbl, "TOPLEFT", -2, 2)
                    hitFrame:SetPoint("BOTTOMRIGHT", lbl, "BOTTOMRIGHT", 2, -2)
                    hitFrame:SetFrameLevel(pf:GetFrameLevel() + 3)
                    hitFrame:EnableMouse(true)
                    hitFrame:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(lbl, row.tooltip)
                    end)
                    hitFrame:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

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
                    cpSwBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

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
                    cpLblBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                end

                rowWidgets[#rowWidgets + 1] = { type = 'colorpicker', updateSwatch = cpUpdate, swatch = cpSwatch, lbl = lbl, swBlock = cpSwBlock, lblBlock = cpLblBlock, disCheck = row.disabled }

                if row.disabled then
                    local initDis = type(row.disabled) == "function" and row.disabled() or row.disabled
                    cpSwatch:SetAlpha(initDis and 0.3 or 1)
                    -- Label dims by alpha rather than the dark row overlay the other
                    -- types use: that overlay would tint the swatch's own color.
                    lbl:SetAlpha(initDis and 0.2 or 0.6)
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
                            EllesmereUI._NotifySettingWrite(popupOwner or opts.captureRegion)
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
                            EllesmereUI._NotifySettingWrite(popupOwner or opts.captureRegion)
                            if pf._refresh then pf._refresh() end
                        end)
                    end
                    if sc.tooltip then
                        swatch:HookScript('OnEnter', function()
                            EllesmereUI.ShowWidgetTooltip(swatch, sc.tooltip)
                        end)
                        swatch:HookScript('OnLeave', function()
                            EllesmereUI.HideWidgetTooltip()
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
                    local disTex = SolidTex(mswDis, "OVERLAY", 0.077, 0.068, 0.058, 0.70)
                    disTex:SetAllPoints()
                    mswDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    mswDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    local initDis = type(row.disabled) == "function" and row.disabled() or row.disabled
                    if initDis then mswDis:Show() else mswDis:Hide() end
                end

                rowWidgets[#rowWidgets + 1] = { type = 'multiswatch', updates = mswUpdates, alphaFns = mswAlphas, disOverlay = mswDis, disCheck = row.disabled }
                curY = curY - ROW_H
            elseif row.type == 'input' then
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
                        EllesmereUI.ShowWidgetTooltip(lbl, row.tooltip)
                    end)
                    hitFrame:SetScript("OnLeave", function()
                        EllesmereUI.HideWidgetTooltip()
                    end)
                end

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
                    local disTex = SolidTex(inputDis, "OVERLAY", 0.077, 0.068, 0.058, 0.70)
                    disTex:SetAllPoints()
                    inputDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then
                            EllesmereUI.ShowWidgetTooltip(self, tip)
                        end
                    end)
                    inputDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
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
                local FONT = (EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                local menu = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
                menu:SetFrameStrata("FULLSCREEN_DIALOG")
                menu:SetFrameLevel(220)
                menu:SetClampedToScreen(true)
                menu:SetWidth(RR_W)
                menu:Hide()
                -- Controller cursor: Cancel clicks the button (it toggles the list closed).
                if EllesmereUI.PadCP() then menu.CloseButton = ddBtn end
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
                menu:SetScript("OnHide", function(self)
                    self:SetScript("OnUpdate", nil)
                    -- Controller cursor: back onto the button (a no-op once the popup hid it too).
                    if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(ddBtn) end
                end)

                local mY = -2
                local ht = menu:CreateFontString(nil, "OVERLAY")
                ht:SetFont(FONT, 10, "")
                ht:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, mY - 4)
                ht:SetTextColor(1, 1, 1, 0.25)
                ht:SetText(EllesmereUI.L(row.hint or "Drag to Reorder"))
                mY = mY - 18

                -- Height cap: rows live on a scroll child. Menus longer than
                -- row.maxVisible rows clamp to that many and mousewheel-scroll;
                -- the drag math below is scroll-child-relative, so reordering
                -- keeps working while scrolled. No maxVisible = full height,
                -- scrolling never engages (exact legacy behavior).
                local scroller = CreateFrame("ScrollFrame", nil, menu)
                scroller:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, mY)
                scroller:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, mY)
                scroller:SetFrameLevel(menu:GetFrameLevel() + 1)
                local sChild = CreateFrame("Frame", nil, scroller)
                scroller:SetScrollChild(sChild)
                local maxScroll = 0
                menu:EnableMouseWheel(true)
                menu:SetScript("OnMouseWheel", function(_, delta)
                    if maxScroll <= 0 then return end
                    local nv = (scroller:GetVerticalScroll() or 0) - delta * MH * 2
                    if nv < 0 then nv = 0 elseif nv > maxScroll then nv = maxScroll end
                    scroller:SetVerticalScroll(nv)
                end)

                local cbBaseY = 0
                local rowFrames, rowPool = {}, {}
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

                -- Runs on the pressed row only, from mouse down to mouse up.
                local function DragUpdate(self)
                    if not dsY then return end
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
                end

                local function MakeRow()
                    local rf = CreateFrame("Button", nil, sChild)
                    rf:SetHeight(MH)
                    rf:SetFrameLevel(menu:GetFrameLevel() + 2)

                    local rl = rf:CreateFontString(nil, "OVERLAY")
                    rl:SetFont(FONT, 13, "")
                    rl:SetPoint("LEFT", rf, "LEFT", 20, 0)
                    rl:SetJustifyH("LEFT")
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
                        self:SetScript("OnUpdate", DragUpdate)
                    end)

                    rf:SetScript("OnMouseUp", function(self, b)
                        if b ~= "LeftButton" or dragRow ~= self then return end
                        self:SetScript("OnUpdate", nil)
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
                    return rf
                end

                -- row.items() is read again on every open: a cached popup must
                -- not keep a list that changed since (the stats shown right
                -- now, a tracked spell list). An unchanged list keeps its rows.
                local itemSig
                local function Populate()
                    local items = (row.items and row.items()) or {}
                    local sig = ""
                    for _, it in ipairs(items) do
                        sig = sig .. tostring(it.key) .. "\n" .. tostring(it.label) .. "\n"
                    end
                    if sig == itemSig then return end
                    itemSig = sig
                    wipe(rowFrames)
                    for ci, it in ipairs(items) do
                        local rf = rowPool[ci] or MakeRow()
                        rowPool[ci] = rf
                        local ry = cbBaseY - (ci - 1) * MH
                        rf._baseY, rf._cbIndex, rf._key = ry, ci, it.key
                        rf._lbl:SetText(it.label)
                        rf:ClearAllPoints()
                        rf:SetPoint("TOPLEFT", sChild, "TOPLEFT", 1, ry)
                        rf:SetPoint("TOPRIGHT", sChild, "TOPRIGHT", -1, ry)
                        rf:Show()
                        rowFrames[ci] = rf
                    end
                    for i = #items + 1, #rowPool do rowPool[i]:Hide() end
                    local visN = #items
                    if row.maxVisible and row.maxVisible > 0 and visN > row.maxVisible then
                        visN = row.maxVisible
                    end
                    local listH, visH = #items * MH, visN * MH
                    scroller:SetHeight(math.max(visH, 1))
                    sChild:SetSize(RR_W, math.max(listH, 1))
                    scroller:SetVerticalScroll(0)
                    maxScroll = math.max(0, listH - visH)
                    menu:SetHeight(20 + visH + 4)
                end
                Populate()
                EllesmereUI.TrackOverlay(menu)

                ddBtn:SetScript("OnClick", function()
                    if menu:IsShown() then
                        menu:Hide()
                    else
                        Populate()
                        menu:Show()
                    end
                    -- Controller cursor: into the opened list.
                    if EllesmereUI.PadCursorShown() and menu:IsShown() then EllesmereUI.PadFocus(menu) end
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
                    local disTex = SolidTex(reorderDis, "OVERLAY", 0.077, 0.068, 0.058, 0.70)
                    disTex:SetAllPoints()
                    reorderDis:SetScript("OnEnter", function(self)
                        local tip = ResolveDisabledTip(row)
                        if tip and EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(self, tip) end
                    end)
                    reorderDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
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
                        if rw.lbl then rw.lbl:SetAlpha(dis and 0.2 or 0.6) end
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
                    if rw.disOverlay then
                        local dis = rw.disCheck
                        if type(dis) == "function" then dis = dis() end
                        rw.disOverlay:SetShown(dis and true or false)
                        if dis and rw.btn._ddMenu then rw.btn._ddMenu:Hide() end
                    end
                    if rw.refresh then rw.refresh() end
                end
            end
            -- A change made inside flipped a row.hidden: the matching frame takes over.
            if dynamic and pf:IsShown() and HiddenSig() ~= pf._sig then SwapVariant() end
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
            local owner = popupOwner
            popupOwner = nil; pf._owner = nil
            -- Dim the anchor back to cog idle alpha; skipped via noOwnerDim when the anchor isn't a cog (e.g. a preview icon) and must not fade.
            if owner and owner._euiCogState then owner._euiCogState()
            elseif owner and not opts.noOwnerDim then owner:SetAlpha(0.4) end
            -- Controller cursor: back onto the cog (not for the hover-opened popups,
            -- where it stays free; a no-op once the cog is hidden).
            if owner and not opts.noOwnerDim and EllesmereUI.PadCursorShown() then
                EllesmereUI.PadFocus(owner)
            end
        end)

        -- Close when the main EllesmereUI frame hides
        if EllesmereUI._mainFrame then
            EllesmereUI._mainFrame:HookScript("OnHide", function()
                if pf:IsShown() then pf:Hide() end
            end)
        end

        EllesmereUI.TrackOverlay(pf)
        popupFrame = pf
        pf._sig = sig
        if variants then variants[sig] = pf end
        return pf
    end

    -- showFn: toggle popup anchored to a button. Wrapped in a callable table so callers can access showFn._popupFrame.
    local showFn = setmetatable({}, { __call = function(self, anchorBtn)
        if dynamic then
            -- The frame for the rows shown right now (built on first need).
            local cur = popupFrame
            local want = variants[HiddenSig()] or CreatePopup(HiddenSig())
            popupFrame = cur
            if popupFrame ~= want then
                if popupFrame and popupFrame:IsShown() then popupFrame:Hide() end
                popupFrame = want
            end
            self._popupFrame = popupFrame
        elseif not popupFrame then CreatePopup(); self._popupFrame = popupFrame end

        -- Toggle off if same anchor clicked while visible
        if popupOwner == anchorBtn and popupFrame:IsShown() then
            popupFrame:Hide(); return
        end
        local prevOwner = popupOwner
        popupOwner = anchorBtn; popupFrame._owner = anchorBtn
        if prevOwner and prevOwner ~= anchorBtn and prevOwner._euiCogState then prevOwner._euiCogState() end

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
        if anchorBtn._euiCogState then anchorBtn._euiCogState() end
        -- Controller cursor: Cancel clicks the anchor again (a second click on the same
        -- anchor closes the popup), and the cursor moves into the popup. Not for the
        -- hover-opened popups (noOwnerDim: the anchor is a menu row, not a cog), where
        -- the cursor must stay free to walk past the row.
        if EllesmereUI.PadCP() and not opts.noOwnerDim then
            popupFrame.CloseButton = anchorBtn.Click and anchorBtn or nil
            if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(popupFrame) end
        end
    end })

    -- Open, a change made inside flipped a row.hidden: the frame for the new
    -- set of rows takes the same anchor, without the open animation.
    SwapVariant = function()
        local owner = popupOwner
        if not (dynamic and owner) then return end
        local old = popupFrame
        local want = variants[HiddenSig()] or CreatePopup(HiddenSig())
        popupFrame = old
        if want == old then return end
        if old then old:Hide() end  -- its OnHide lets go of the owner
        popupFrame = want
        showFn._popupFrame = want
        popupOwner = owner; want._owner = owner
        want._refresh()
        want:ClearAllPoints()
        want:SetPoint("TOP", owner, "BOTTOM", 0, -5)
        want:SetAlpha(1)
        want:Show()
        want:SetScript("OnUpdate", want._clickOutside)
        if owner._euiCogState then owner._euiCogState() end
        if EllesmereUI.PadCP() and not opts.noOwnerDim then
            want.CloseButton = owner.Click and owner or nil
            if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(want) end
        end
    end

    return popupFrame, showFn
end

EllesmereUI.BuildCogPopup       = BuildCogPopup
end  -- end deferred init
