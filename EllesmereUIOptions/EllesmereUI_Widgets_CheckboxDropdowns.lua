if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_CheckboxDropdowns.lua
--  Checkbox dropdowns shared by the options pages: the empty-filter
--  warning, BuildVisOptsCBDropdown and its drag-reorder variant, and the
--  slider dropdown (BuildSliderDropdown). Loads right after
--  EllesmereUI_Widgets.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI

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

-------------------------------------------------------------------------------
--  Shared Visibility Options Checkbox Dropdown
--  Reusable across CDM, Action Bars, Resource Bars, Unit Frames.
--  items = EllesmereUI.VIS_OPT_ITEMS (or a subset)
--  getFn(key) -> bool, setFn(key, bool)
--  onMenuClosed (optional) fires once each time the open menu hides --
--  callers that defer page rebuilds while the menu is open flush there.
--  opts.dimLocked: locked rows dim their checkbox too, not only the label.
--  opts.noAllLabel: the summary names every checked row even when all are
--  checked (a selection, not a filter: never "All").
--  opts.disabled (fn) + disabledTooltip/rawTooltip/requireState (as
--  ResolveDisabledTip): greyed and click-blocked while it answers true, the
--  reason on hover, re-checked with the page's widgets.
--  Returns: ddBtn, refreshFn
-------------------------------------------------------------------------------
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
        -- A LIVE override replaces the whole setting, whether it is being edited or just
        -- applied, so the summary is what it holds and nothing else. Mixing it with the
        -- rows below reads as one selection that exists nowhere ("Always or Solo"), and
        -- it is also the only place that still tells the truth while the rows underneath
        -- show the shared value they edit.
        local held = opts.ovHeldFn and opts.ovHeldFn()
        if held then
            for _, item in ipairs(items) do
                if item.key == held then return EllesmereUI.L(item.label) end
            end
        end
        for _, item in ipairs(items) do
            -- isModifier rows (the Visibility match toggle) are not conditions: excluded
            -- from the summary and from the "All" shortcut. item.excludeFromSummaryFn
            -- opts a row out the same way (e.g. locked behind an unlearned talent).
            if not item.isHeader and not item.isTopAction and not item.isModifier
               and not (item.excludeFromSummaryFn and item.excludeFromSummaryFn()) then
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
        elseif #names == total and not opts.noAllLabel then base = EllesmereUI.L("All")
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
        menu = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(200)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetSize(ddW, menuH)
        menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
        menu:Hide()
        -- Controller cursor: the list blocks what is under it but is not a stop itself;
        -- Cancel clicks the dropdown button (it toggles the list closed).
        if EllesmereUI.PadCP() then
            EllesmereUI.PadHint(menu, "nodepass")
            menu.CloseButton = ddBtn
        end
        local mBg = menu:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints()
        mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
        local ppScale = EllesmereUI.GetPopupScale() or 1
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
                    EllesmereUI.HideWidgetTooltip()
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
        -- Controller cursor: it scrolls the list to the row itself; the pointer-drag thumb is no stop.
        EllesmereUI.PadHint(cbThumb, "nodeignore")

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
        -- Published for the refreshers below: the rows are parented to the SCROLL CHILD,
        -- so a menu:GetChildren() walk never reaches them.
        menu._rows = _allRows
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
                boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
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
            -- Opt-in dimmed rows (item.dimFn): a pick that has no effect here right now
            -- (it shows somewhere else) rests dimmed but stays clickable, and hovering it
            -- shows item.dimTooltip (string or function) in place of item.tooltip.
            local function Dimmed()
                return (item.dimFn and item.dimFn()) and true or false
            end
            -- Modifier rows rest in the accent only while active; read live, since a
            -- sibling's click flips the checked state (UpdateCheck runs on every row).
            local function RestColor()
                if item.isModifier and getFn(item.key) then
                    return EllesmereUI.ELLESMERE_GREEN.r, EllesmereUI.ELLESMERE_GREEN.g, EllesmereUI.ELLESMERE_GREEN.b
                end
                if Dimmed() then return 0.5, 0.5, 0.5 end
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
                negBg:SetColorTexture(0.114, 0.106, 0.099, 1)
                negBrd = EllesmereUI.MakeBorder(negBox, 0.4, 0.4, 0.4, 0.6, PP)
                negChk = negBox:CreateTexture(nil, "ARTWORK")
                PP.SetInside(negChk, negBox, 2, 2)
                negChk:SetColorTexture(0.85, 0.3, 0.3, 1)
                negChk:SetSnapToPixelGrid(false)
            end
            -- Opt-in colour swatch (item.swatch = { get = fn -> r, g, b, a, set = fn(r, g, b, a),
            -- hasAlpha, disabled = fn, disabledTooltip (+ rawTooltip / requireState, as
            -- ResolveDisabledTip) }): its own button at the row's right edge, so a click
            -- opens the colour picker and never toggles the row. While disabled it dims
            -- and a blocker takes its clicks and explains the requirement.
            local sw, swUpdate, swBlock
            if item.swatch then
                local spec = item.swatch
                sw, swUpdate = EllesmereUI.BuildColorSwatch(row, row:GetFrameLevel() + 1,
                    spec.get, spec.set, spec.hasAlpha, 16)
                sw:ClearAllPoints()
                sw:SetPoint("RIGHT", row, "RIGHT", negBox and -32 or -10, 0)
                lbl:SetPoint("RIGHT", sw, "LEFT", -6, 0)
                swBlock = CreateFrame("Frame", nil, sw)
                swBlock:SetAllPoints()
                swBlock:SetFrameLevel(sw:GetFrameLevel() + 10)
                swBlock:EnableMouse(true)
                swBlock:SetScript("OnEnter", function()
                    local tip = EllesmereUI.ResolveDisabledTip(spec)
                    if tip then EllesmereUI.ShowWidgetTooltip(sw, tip) end
                end)
                swBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                swBlock:Hide()
            end
            local function ShowLaneLocked()
                return item.showLockedFn and item.showLockedFn() or false
            end
            -- item.ovLockedFn is the override-session lock: it blocks the click like any
            -- other lock, but is painted and explained differently, because the row is not
            -- merely unavailable here -- it cannot be captured into an override at all.
            local function OvLocked()
                return (item.ovLockedFn and item.ovLockedFn()) and true or false
            end
            local function RowLocked()
                if OvLocked() or item.locked then return true end
                return (item.lockedFn and item.lockedFn()) and true or false
            end
            local function LockedTip()
                local lt = (OvLocked() and item.ovLockedTooltip) or item.lockedTooltip
                if type(lt) == "function" then lt = lt() end
                return lt
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
                if sw then
                    swUpdate()
                    local off = item.swatch.disabled and item.swatch.disabled() or false
                    sw:SetAlpha(off and 0.3 or 1)
                    swBlock:SetShown(off and true or false)
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
                    local lt = LockedTip()
                    if lt then
                        EllesmereUI.ShowWidgetTooltip(row, lt)
                    end
                    return
                end
                lbl:SetTextColor(1, 1, 1, 1)
                hl:SetColorTexture(1, 1, 1, 0.04)
                local tip = item.tooltip
                if item.dimTooltip and Dimmed() then tip = item.dimTooltip end
                if type(tip) == "function" then tip = tip() end
                if tip then
                    EllesmereUI.ShowWidgetTooltip(row, tip)
                end
            end)
            row:SetScript("OnLeave", function()
                if row._isLocked then
                    if item.lockedTooltip or item.ovLockedTooltip then
                        EllesmereUI.HideWidgetTooltip()
                    end
                    return
                end
                lbl:SetTextColor(RestColor())
                hl:SetColorTexture(1, 1, 1, 0)
                if item.tooltip or item.dimTooltip then
                    EllesmereUI.HideWidgetTooltip()
                end
            end)
            local function UpdateLocked()
                local isLocked = RowLocked()
                -- Mouse stays enabled so locked rows can explain themselves on hover; clicks are guarded independently in OnClick.
                row._isLocked = isLocked and true or false
                if isLocked then
                    lbl:SetTextColor(0.4, 0.4, 0.4, 0.5)
                else
                    lbl:SetTextColor(RestColor())
                end
                -- opts.dimLocked: a locked row's checkbox dims with its label, so a
                -- checked one reads as fixed rather than clickable (dual rows keep
                -- their own lane dimming).
                if opts.dimLocked and box and not item.dual then
                    box:SetAlpha(isLocked and 0.4 or 1)
                end
            end
            row._updateLocked = UpdateLocked
            UpdateLocked()
            local function AfterToggle()
                -- opts.notifyWrites: join the primary capture path every other widget's
                -- setter uses. Without it a checklist has only the polling fallback,
                -- whose mouse attribution is CLEARED while the menu (a UIParent child
                -- with no popup marker) holds focus, so an override session never sees
                -- the write when it happens. ddBtn's parent carries the row's
                -- _captureCfg, so the slot is attributed exactly. Opt-in: every other
                -- checklist keeps the behaviour it has always had.
                if opts.notifyWrites and EllesmereUI._NotifySettingWrite then
                    EllesmereUI._NotifySettingWrite(ddBtn)
                end
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
                if RowLocked() then return end
                if negBox and ShowLaneLocked() then
                    setFn(item.key, not getFn(item.key, true), true)
                else
                    setFn(item.key, not getFn(item.key))
                end
                AfterToggle()
            end)
            if negBox then
                negBox:SetScript("OnClick", function()
                    if RowLocked() then return end
                    setFn(item.key, not getFn(item.key, true), true)
                    AfterToggle()
                end)
                negBox:SetScript("OnEnter", function()
                    if row._isLocked then
                        local lt = LockedTip()
                        if lt then EllesmereUI.ShowWidgetTooltip(negBox, lt) end
                        return
                    end
                    lbl:SetTextColor(1, 1, 1, 1)
                    hl:SetColorTexture(1, 1, 1, 0.04)
                    local hlt = opts.hideLaneTooltip
                    if type(hlt) == "function" then hlt = hlt(item.key) end
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
            -- Marks the contiguous run the override overlay below seals off.
            row._ovBlock = item.ovLockedFn and true or nil
            _allRows[#_allRows + 1] = { frame = row, isHeader = false, label = item.label, height = ITEM_H }
            yOff = yOff - ITEM_H

            end -- isHeader else
        end

        -- Override session: the excluded rows are sealed off as ONE block rather than
        -- marked one by one -- 1px red border, a 5% red wash, a lock glyph with a caption
        -- and a click blocker holding the explanation, the same treatment SetSlotMark
        -- gives an override-red slot in the panel.
        -- Parented to the scroll child so it travels with the rows.
        if opts.ovLockedFn then
            local first, last
            for i = 1, #_allRows do
                if _allRows[i].frame._ovBlock then
                    -- A header sitting directly on top of the run introduces it.
                    if not first then
                        first = (i > 1 and _allRows[i - 1].isHeader) and (i - 1) or i
                    end
                    last = i
                end
            end
            if first and last then
                local seal = CreateFrame("Button", nil, itemParent)
                seal:SetPoint("TOPLEFT", _allRows[first].frame, "TOPLEFT", 1, 0)
                -- The 4px scrollbar track sits 4px off the right edge, ON the scroll
                -- frame rather than in here, so the seal stops short of it instead of
                -- running underneath and having the bar cut through its border.
                seal:SetPoint("BOTTOMRIGHT", _allRows[last].frame, "BOTTOMRIGHT", -9, 0)
                seal:SetFrameLevel(menu:GetFrameLevel() + 8)
                local wash = seal:CreateTexture(nil, "BACKGROUND")
                wash:SetAllPoints()
                wash:SetColorTexture(0.9, 0.2, 0.2, 0.05)
                if PP and PP.CreateBorder then
                    PP.CreateBorder(seal, 0.9, 0.2, 0.2, 0.9, 1, "OVERLAY", 7)
                end
                -- Caption on the block's top edge rather than across its middle: the wash
                -- is deliberately faint, so a centred label would land on readable rows.
                local sealLbl = seal:CreateFontString(nil, "OVERLAY", nil, 7)
                sealLbl:SetFont(fontPath, 11, "")
                sealLbl:SetTextColor(1, 0.35, 0.35, 1)
                sealLbl:SetPoint("TOPRIGHT", seal, "TOPRIGHT", -6, -5)
                sealLbl:SetText(EllesmereUI.L("Not overridable"))
                -- The section header's divider line runs straight THROUGH the caption at
                -- this height. A plate in the menu's own background colour cuts the line
                -- for the width of the text: the seal sits at a higher frame level than
                -- the header, so anything it draws covers that line.
                local plate = seal:CreateTexture(nil, "ARTWORK", nil, 6)
                plate:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G,
                    EllesmereUI.DD_BG_B, 1)
                plate:SetPoint("TOPLEFT", sealLbl, "TOPLEFT", -5, 2)
                plate:SetPoint("BOTTOMRIGHT", sealLbl, "BOTTOMRIGHT", 5, -2)
                seal:EnableMouse(true)
                seal:SetScript("OnEnter", function(self)
                    if opts.ovLockedTooltip then
                        EllesmereUI.ShowWidgetTooltip(self, opts.ovLockedTooltip)
                    end
                end)
                seal:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                end)
                menu._ovSeal = seal
                seal:SetShown(opts.ovLockedFn())
            end
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
                -- The override seal is anchored to the FIRST and LAST row of its run,
                -- which this filter hides and repositions without touching the seal. Drop
                -- it while a filter is active rather than re-deriving the run: with rows
                -- missing there is no contiguous block left to mark, and a stale seal is a
                -- mouse-enabled frame parked over whatever rows did survive.
                if menu._ovSeal then
                    menu._ovSeal:SetShown(t == "" and opts.ovLockedFn
                        and opts.ovLockedFn() or false)
                end
                child:SetHeight(math.max(1, math.abs(visY)))
                sf:SetVerticalScroll(0)
                UpdateCBThumb()
            end)
            menu:HookScript("OnShow", function()
                searchEdit:SetText("")
                -- Not under the controller cursor: focus would pop its on-screen keyboard over the list.
                if not EllesmereUI.PadCursorShown() then searchEdit:SetFocus() end
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

        if EllesmereUI.PadCP() then
            -- Controller cursor (ShowMenu calls this only while it is shown): list back
            -- to the top, cursor onto the first row.
            menu._padFocus = function()
                sf:SetVerticalScroll(0)
                UpdateCBThumb()
                local first
                for i = 1, #_allRows do
                    local r = _allRows[i]
                    if not r.isHeader and r.frame:IsShown() then first = r.frame; break end
                end
                EllesmereUI.PadFocus(first or menu)
            end
            EllesmereUI.TrackOverlay(menu)
        end
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
        -- A static menu is built once and reused, so anything that changed while it was
        -- closed would show stale: refresh checked state AND locks on every open. The
        -- case that matters is an override session starting between two opens.
        for _, r in ipairs(menu._rows or {}) do
            if r.frame._updateCheck then r.frame._updateCheck() end
            if r.frame._updateLocked then r.frame._updateLocked() end
        end
        if menu._ovSeal then menu._ovSeal:SetShown(opts.ovLockedFn()) end
        -- Match the panel's effective scale since menu lives on UIParent
        local btnScale = ddBtn:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        menu:SetScale(btnScale / uiScale)
        ApplyHover()
        menu:Show()
        -- Track the open menu globally so popup outside-click watchers don't treat clicks on rows that extend below the popup as a dismissing outside click.
        EllesmereUI._openDropdownMenu = menu
        menu:SetScript("OnUpdate", function(self)
            -- Close when left-clicking outside the menu and button. The shared colour
            -- picker is a separate popup a row swatch opens: working in it keeps the menu.
            local cp = EllesmereUI._colorPickerPopup
            if not self:IsMouseOver() and not ddBtn:IsMouseOver() and IsMouseButtonDown("LeftButton")
                and not (cp and cp:IsShown()) then
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
            -- Controller cursor: back onto the dropdown button (a no-op once that is hidden too).
            if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(ddBtn) end
        end)
        if menu._padFocus and EllesmereUI.PadCursorShown() then menu._padFocus() end
    end

    ddBtn:SetScript("OnClick", function() ShowMenu() end)
    ddBtn:HookScript("OnHide", function() if menu then menu:Hide() end end)

    local function RefreshAll()
        UpdateLabel()
        if menu then
            for _, r in ipairs(menu._rows or {}) do
                if r.frame._updateCheck then r.frame._updateCheck() end
                if r.frame._updateLocked then r.frame._updateLocked() end
            end
            if menu._ovSeal then menu._ovSeal:SetShown(opts.ovLockedFn()) end
        end
    end

    if opts.disabled then
        local block = CreateFrame("Frame", nil, ddBtn)
        block:SetAllPoints()
        block:SetFrameLevel(ddBtn:GetFrameLevel() + 20)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            local tip = EllesmereUI.ResolveDisabledTip(opts)
            if tip then EllesmereUI.ShowWidgetTooltip(ddBtn, tip) end
        end)
        block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function DisabledState()
            local off = opts.disabled() and true or false
            ddBtn:SetAlpha(off and 0.4 or 1)
            block:SetShown(off)
            if off and menu then menu:Hide() end
        end
        DisabledState()
        EllesmereUI.RegisterWidgetRefresh(DisabledState)
    end
    return ddBtn, RefreshAll
end

-------------------------------------------------------------------------------
--  Spec picker items for BuildVisOptsCBDropdown (the "Select a Spec" lists):
--  "All Specs" first (key EllesmereUI.SPEC_PICK_ALL, an action row), then on
--  retail every class's specs under its class header, classes in alphabetical
--  order, with opts.roles adding the All Healers / All Tanks / All DPS action
--  rows (keys SPEC_PICK_HEALERS / _TANKS / _DPS) after it. WoW Forever lists
--  one row per class instead, keyed by its class token and standing for every
--  retail spec of the class (EllesmereUI.ForeverClassSpecIDs; the caller's
--  getter and setter expand it), and no role rows. opts.allLockedFn locks the
--  action rows; opts.lockedFn(specID) locks a spec row, and a Forever class row
--  while any spec of its class is locked. Returns the items and the role table
--  ({ [SPEC_PICK_HEALERS] = spec IDs, ... }, empty on Forever).
-------------------------------------------------------------------------------
EllesmereUI.SPEC_PICK_ALL, EllesmereUI.SPEC_PICK_HEALERS = 0, -1
EllesmereUI.SPEC_PICK_TANKS, EllesmereUI.SPEC_PICK_DPS = -2, -3
function EllesmereUI.SpecPickItems(opts)
    opts = opts or {}
    local lockedFn, allLockedFn = opts.lockedFn, opts.allLockedFn
    local items, roles = {}, {}
    items[1] = { key = EllesmereUI.SPEC_PICK_ALL, label = "All Specs", isAction = true, lockedFn = allLockedFn }
    if EllesmereUI.IS_FOREVER then
        local classes = EllesmereUI.ForeverClasses()
        for n = 1, #classes do
            local token = classes[n]
            local ids = EllesmereUI.ForeverClassSpecIDs(token)
            items[#items + 1] = { key = token, label = EllesmereUI.ForeverClassName(token),
                lockedFn = lockedFn and function()
                    for i = 1, #ids do
                        if lockedFn(ids[i]) then return true end
                    end
                    return false
                end or nil }
        end
        return items, roles
    end
    if opts.roles then
        items[#items + 1] = { key = EllesmereUI.SPEC_PICK_HEALERS, label = "All Healers", isAction = true, lockedFn = allLockedFn }
        items[#items + 1] = { key = EllesmereUI.SPEC_PICK_TANKS, label = "All Tanks", isAction = true, lockedFn = allLockedFn }
        items[#items + 1] = { key = EllesmereUI.SPEC_PICK_DPS, label = "All DPS", isAction = true, lockedFn = allLockedFn }
    end
    local classList = {}
    for classID = 1, (GetNumClasses and GetNumClasses() or 13) do
        local className = GetClassInfo(classID)
        if className then
            classList[#classList + 1] = { classID = classID, className = className }
        end
    end
    table.sort(classList, function(a, b) return a.className < b.className end)
    local healers, tanks, dps = {}, {}, {}
    for _, cls in ipairs(classList) do
        items[#items + 1] = { isHeader = true, label = cls.className }
        for specIndex = 1, (C_SpecializationInfo.GetNumSpecializationsForClassID(cls.classID) or 0) do
            local specID, specName, _, _, role = GetSpecializationInfoForClassID(cls.classID, specIndex)
            if specID and specName then
                local sid = specID
                items[#items + 1] = { key = specID, label = specName,
                    lockedFn = lockedFn and function() return lockedFn(sid) end or nil }
                if role == "HEALER" then healers[#healers + 1] = specID
                elseif role == "TANK" then tanks[#tanks + 1] = specID
                else dps[#dps + 1] = specID end
            end
        end
    end
    roles[EllesmereUI.SPEC_PICK_HEALERS] = healers
    roles[EllesmereUI.SPEC_PICK_TANKS] = tanks
    roles[EllesmereUI.SPEC_PICK_DPS] = dps
    return items, roles
end

-------------------------------------------------------------------------------
--  BuildReorderCBDropdown
--  Checkbox dropdown whose rows can also be drag-reordered vertically. Row visuals match BuildVisOptsCBDropdown;
--  the drag behavior matches the Macro Factory per-macro menus (3px threshold, floating row, insertion line, contents shuffle on drop).
--  items: array in initial display order:
--      { key = "...", label = "...", fixed = true|nil }
--  fixed rows are checkbox-only and pinned below the movable rows.
--  getFn(key) -> checked; setFn(key, checked, orderedMovableKeys) fires on row click.
--  opts = {
--      setOrder = function(orderedMovableKeys),  -- fired on every drop
--      onClose  = function(orderChanged),        -- fired once per menu close
--      hint     = "Drag to Reorder",             -- text above the rows
--      hint2    = "...",                         -- optional second hint line
--      canReorder = function() -> boolean,       -- optional drag guard
--      summaryLabel = function(movable, fixed, getFn) -> string,
--      head     = { { key, label }, ... },       -- plain rows (no box) at the top, a divider under them
--      onHead   = function(key),
--      tail     = { { key, label }, ... },       -- plain rows at the bottom, a divider above them
--      onTail   = function(key),
--      tailSelected = function(key) -> boolean,  -- shows a tail row as the current choice
--      openOrder = function() -> keys | nil,     -- on every open: these movable rows first, in this
--  }                                             -- order, the rest in their first order
--  A plain row calls its callback, then closes the menu (onClose sees the pick).
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
    local head, tail = opts.head or {}, opts.tail or {}
    -- The movable rows' first order (opts.openOrder sorts from it).
    local baseMovable = {}
    for i = 1, #movable do baseMovable[i] = movable[i] end
    local function MovableKeys()
        local keys = {}
        for i = 1, #movable do keys[i] = movable[i].key end
        return keys
    end
    local plainPaints = {}
    local function PaintPlainRows()
        for i = 1, #plainPaints do plainPaints[i]() end
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
        if opts.summaryLabel then return opts.summaryLabel(movable, fixedItems, getFn) end
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
        local HEAD_H = (#head > 0) and (#head * ITEM_H + DIV_H) or 0
        local TAIL_H = (#tail > 0) and (DIV_H + #tail * ITEM_H) or 0
        local ROWS_BASE_Y = -4 - HEAD_H - HINT_H
        local menuH = 4 + HEAD_H + HINT_H + #movable * ITEM_H
            + ((#fixedItems > 0) and (DIV_H + #fixedItems * ITEM_H) or 0) + TAIL_H + 4
        menu = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(200)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetSize(ddW, menuH)
        menu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
        menu:Hide()
        local mBg = menu:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints()
        mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
        -- Controller cursor: the list blocks what is under it but is not a stop itself;
        -- Cancel clicks the dropdown button (it toggles the list closed).
        if EllesmereUI.PadCP() then
            EllesmereUI.PadHint(menu, "nodepass")
            menu.CloseButton = ddBtn
        end

        -- Hint line(s) above the rows
        local hint = menu:CreateFontString(nil, "OVERLAY")
        hint:SetFont(fontPath, 10, "")
        hint:SetTextColor(1, 1, 1, 0.25)
        if opts.hint2 then
            hint:SetPoint("TOP", menu, "TOP", 0, -6 - HEAD_H)
            local hint2 = menu:CreateFontString(nil, "OVERLAY")
            hint2:SetFont(fontPath, 9, "")
            hint2:SetTextColor(1, 1, 1, 0.25)
            hint2:SetPoint("TOP", hint, "BOTTOM", 0, -3)
            hint2:SetText(EllesmereUI.L(opts.hint2))
        else
            hint:SetPoint("TOP", menu, "TOP", 0, -4 - HEAD_H - (HINT_H - 10) / 2)
        end
        hint:SetText(EllesmereUI.L(opts.hint or "Drag to Reorder"))

        -- A plain row (head or tail): its label alone; its callback runs before
        -- the menu closes, so onClose sees the pick. A tail row shows the
        -- current choice.
        local function BuildPlainRow(item, slotY, onPick, selFn)
            local row = CreateFrame("Button", nil, menu)
            row:SetHeight(ITEM_H)
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, slotY)
            row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, slotY)
            row:SetFrameLevel(menu:GetFrameLevel() + 2)
            local lbl = row:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(fontPath, 13, "")
            lbl:SetPoint("LEFT", row, "LEFT", 10, 0)
            lbl:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
            lbl:SetMaxLines(1)
            lbl:SetText(EllesmereUI.L(item.label))
            local hl = row:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            local hover = false
            local function Paint()
                local lit = hover or (selFn and selFn(item.key))
                lbl:SetTextColor(lit and 1 or 0.75, lit and 1 or 0.75, lit and 1 or 0.75, 1)
                hl:SetColorTexture(1, 1, 1, lit and 0.04 or 0)
            end
            Paint()
            plainPaints[#plainPaints + 1] = Paint
            row:SetScript("OnEnter", function() hover = true; Paint() end)
            row:SetScript("OnLeave", function() hover = false; Paint() end)
            row:SetScript("OnClick", function()
                hover = false
                if onPick then onPick(item.key) end
                menu:Hide()
                UpdateLabel()
            end)
        end
        for i = 1, #head do
            BuildPlainRow(head[i], -4 - (i - 1) * ITEM_H, opts.onHead)
        end
        if #head > 0 then
            local hd = menu:CreateTexture(nil, "ARTWORK")
            hd:SetHeight(1)
            hd:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -4 - #head * ITEM_H - 3)
            hd:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -10, -4 - #head * ITEM_H - 3)
            hd:SetColorTexture(1, 1, 1, 0.08)
        end

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
            boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
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
                if row._suppressClick then row._suppressClick = nil; return end
                if isDragging then return end
                setFn(row._item.key, not getFn(row._item.key), MovableKeys())
                UpdateLabel()
                for _, r in ipairs(allRows) do
                    if r._updateCheck then r._updateCheck() end
                end
                PaintPlainRows()
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
            local DragUpdate
            row:SetScript("OnMouseDown", function(self, b)
                if b ~= "LeftButton" then return end
                row._suppressClick = nil
                if opts.canReorder and not opts.canReorder() then return end
                local _, cy = GetCursorPosition()
                dsY = cy
                self:SetScript("OnUpdate", DragUpdate)
            end)
            row:SetScript("OnMouseUp", function(self, b)
                if b ~= "LeftButton" then return end
                dsY = nil
                self:SetScript("OnUpdate", nil)
                if not isDragging then return end
                self._suppressClick = true
                isDragging = false
                insLine:Hide()
                self:SetFrameLevel(menu:GetFrameLevel() + 2)
                self:SetAlpha(1)
                -- Snap the floated row back to its slot
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, self._slotY)
                self:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, self._slotY)
                if opts.canReorder and not opts.canReorder() then
                    RefreshMovableRows()
                    return
                end
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
            DragUpdate = function(self)
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
            end
            row._cancelDrag = function(self)
                if not dsY then return end
                dsY = nil
                self:SetScript("OnUpdate", nil)
                self:SetFrameLevel(menu:GetFrameLevel() + 2)
                self:SetAlpha(1)
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, self._slotY)
                self:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, self._slotY)
            end
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

        -- Divider + plain tail rows at the bottom
        if #tail > 0 then
            local tailTop = ROWS_BASE_Y - #movable * ITEM_H
                - ((#fixedItems > 0) and (DIV_H + #fixedItems * ITEM_H) or 0)
            local td = menu:CreateTexture(nil, "ARTWORK")
            td:SetHeight(1)
            td:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, tailTop - 3)
            td:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -10, tailTop - 3)
            td:SetColorTexture(1, 1, 1, 0.08)
            for i = 1, #tail do
                BuildPlainRow(tail[i], tailTop - DIV_H - (i - 1) * ITEM_H, opts.onTail, opts.tailSelected)
            end
        end

        -- Every open: the caller's row order (opts.openOrder), then the check
        -- and choice visuals.
        menu:HookScript("OnShow", function()
            if opts.openOrder then
                local keys = opts.openOrder()
                local byKey, used, n = {}, {}, 0
                for _, it in ipairs(baseMovable) do byKey[it.key] = it end
                if keys then
                    for _, k in ipairs(keys) do
                        local it = byKey[k]
                        if it and not used[k] then
                            n = n + 1
                            movable[n] = it
                            used[k] = true
                        end
                    end
                end
                for _, it in ipairs(baseMovable) do
                    if not used[it.key] then
                        n = n + 1
                        movable[n] = it
                    end
                end
                RefreshMovableRows()
            end
            for _, r in ipairs(allRows) do
                if r._updateCheck then r._updateCheck() end
            end
            PaintPlainRows()
        end)

        -- One close notification per open/close cycle (reload prompts hook this)
        menu:HookScript("OnHide", function()
            for _, row in ipairs(movableRows) do row:_cancelDrag() end
            isDragging = false
            insLine:Hide()
            -- Controller cursor: back onto the dropdown button before onClose, so a
            -- prompt it opens can still take the cursor (a no-op once the button is hidden).
            if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(ddBtn) end
            local changed = orderChanged
            orderChanged = false
            if opts.onClose then opts.onClose(changed) end
        end)

        EllesmereUI.TrackOverlay(menu)
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
        -- Controller cursor: into the opened list.
        if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(menu) end
    end
    ddBtn:SetScript("OnClick", ShowMenu)
    ddBtn:HookScript("OnHide", function() if menu then menu:Hide() end end)

    local function RefreshAll()
        UpdateLabel()
        for _, r in ipairs(allRows) do
            if r._updateCheck then r._updateCheck() end
        end
        PaintPlainRows()
    end
    return ddBtn, RefreshAll
end

-------------------------------------------------------------------------------
--  Slider dropdown: a dropdown button whose menu is a short stack of sliders
--  (label, track and value box per row), several related amounts behind one
--  control. items[i] = { label, tooltip, min, max, step, get = fn -> number,
--  set = fn(v) }; tooltip shows over the row's label. The button reads the
--  labels of the rows away from their minimum ("None" when none, "All" when
--  every one). opts.menuW = the menu width (default 320); the menu opens
--  right-aligned under the button, stays open while a slider is dragged past
--  its edge and runs nothing while closed.
--  Returns: ddBtn, refreshFn
-------------------------------------------------------------------------------
function EllesmereUI.BuildSliderDropdown(parentFrame, ddW, fLevel, items, opts)
    local PP = EllesmereUI.PP
    opts = opts or {}
    local fontPath = EllesmereUI.EXPRESSWAY
    local ddBtn = CreateFrame("Button", nil, parentFrame)
    PP.Size(ddBtn, ddW, 30)
    ddBtn:SetFrameLevel(fLevel)
    local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints()
    local ddBrd = EllesmereUI.MakeBorder(ddBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
    local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
    ddLbl:SetFont(fontPath, 13, "")
    ddLbl:SetJustifyH("LEFT")
    ddLbl:SetWordWrap(false)
    ddLbl:SetMaxLines(1)
    ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
    local arrow = EllesmereUI.MakeDropdownArrow(ddBtn, 12, PP)
    ddLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

    local function Paint(hover)
        ddLbl:SetTextColor(1, 1, 1, hover and EllesmereUI.DD_TXT_HA or EllesmereUI.DD_TXT_A)
        ddBrd:SetColor(1, 1, 1, hover and EllesmereUI.DD_BRD_HA or EllesmereUI.DD_BRD_A)
        ddBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B,
            hover and EllesmereUI.DD_BG_HA or EllesmereUI.DD_BG_A)
    end
    Paint(false)

    local function UpdateLabel()
        local names = {}
        for _, item in ipairs(items) do
            local v = item.get()
            if v and v ~= (item.min or 0) then names[#names + 1] = EllesmereUI.L(item.label) end
        end
        if #names == 0 then
            ddLbl:SetText(EllesmereUI.L("None"))
        elseif #names == #items then
            ddLbl:SetText(EllesmereUI.L("All"))
        else
            ddLbl:SetText(table.concat(names, ", "))
        end
    end
    UpdateLabel()

    local menu, refreshers
    local ROW_H, PAD, TRACK_W = 34, 6, 140
    local function EnsureMenu()
        if menu then return end
        menu = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(200)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        -- The page under the menu must not scroll away from it.
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function() end)
        menu:SetSize(opts.menuW or 320, PAD * 2 + #items * ROW_H)
        menu:SetPoint("TOPRIGHT", ddBtn, "BOTTOMRIGHT", 0, -2)
        menu:Hide()
        -- Controller cursor: the menu blocks what is under it but is not a stop
        -- itself; Cancel clicks the button (it toggles the menu closed).
        if EllesmereUI.PadCP() then
            EllesmereUI.PadHint(menu, "nodepass")
            menu.CloseButton = ddBtn
        end
        local mBg = menu:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints()
        mBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
        EllesmereUI.MakeBorder(menu, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)

        refreshers = {}
        for i, item in ipairs(items) do
            local y = -(PAD + (i - 1) * ROW_H)
            local row = CreateFrame("Frame", nil, menu)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, y)
            row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, y)
            row:SetFrameLevel(menu:GetFrameLevel() + 2)
            local track, valBox, refresh = EllesmereUI.BuildSliderCore(row, TRACK_W, 4, 14, 40, 24, 12,
                EllesmereUI.SL_INPUT_A, item.min or 0, item.max or 100, item.step or 1,
                item.get,
                function(v)
                    item.set(v)
                    UpdateLabel()
                    -- Attributed to the button: its row carries the override
                    -- capture config, the menu sits on the overlay parent.
                    EllesmereUI._NotifySettingWrite(ddBtn)
                end, true)
            PP.Point(valBox, "RIGHT", row, "RIGHT", -12, 0)
            PP.Point(track, "RIGHT", valBox, "LEFT", -12, 0)
            refreshers[i] = refresh
            local lbl = row:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(fontPath, 13, "")
            lbl:SetTextColor(1, 1, 1, 0.85)
            lbl:SetJustifyH("LEFT")
            lbl:SetWordWrap(false)
            lbl:SetPoint("LEFT", row, "LEFT", 14, 0)
            lbl:SetPoint("RIGHT", track, "LEFT", -12, 0)
            lbl:SetText(EllesmereUI.L(item.label))
            if item.tooltip then
                row:EnableMouse(true)
                row:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(lbl, item.tooltip) end)
                row:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
            if i < #items then
                local div = row:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                div:SetHeight(1)
                div:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 0)
                div:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 0)
            end
        end

        menu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            if EllesmereUI._openDropdownMenu == self then EllesmereUI._openDropdownMenu = nil end
            Paint(ddBtn:IsMouseOver())
            -- Controller cursor: back onto the button (a no-op once that is hidden too).
            if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(ddBtn) end
        end)
        if EllesmereUI.PadCP() then EllesmereUI.TrackOverlay(menu) end
    end

    -- Whether the button scrolls with the page (decided on the first open).
    local inScroll
    local function ShowMenu()
        EnsureMenu()
        if menu:IsShown() then
            menu:Hide()
            return
        end
        for i = 1, #refreshers do refreshers[i]() end
        -- The menu lives on the overlay parent: match the panel's scale.
        menu:SetScale(ddBtn:GetEffectiveScale() / UIParent:GetEffectiveScale())
        Paint(true)
        menu:Show()
        EllesmereUI._openDropdownMenu = menu
        local sf = EllesmereUI._scrollFrame
        if inScroll == nil then
            inScroll = false
            local child = sf and sf.GetScrollChild and sf:GetScrollChild()
            local p = ddBtn:GetParent()
            while child and p do
                if p == child then inScroll = true; break end
                p = p:GetParent()
            end
        end
        menu:SetScript("OnUpdate", function(self)
            -- A left click outside the menu and its button closes it; never
            -- mid-drag, so a slider dragged past the menu's edge keeps it.
            if not EllesmereUI._sliderDragging and IsMouseButtonDown("LeftButton")
               and not self:IsMouseOver() and not ddBtn:IsMouseOver() then
                self:Hide()
                return
            end
            -- The button scrolled out of the page's visible area.
            if inScroll then
                local top, bot, b = sf:GetTop(), sf:GetBottom(), ddBtn:GetBottom()
                if top and bot and b and (b < bot or b > top) then self:Hide() end
            end
        end)
        if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(menu) end
    end
    ddBtn:SetScript("OnEnter", function() Paint(true) end)
    ddBtn:SetScript("OnLeave", function()
        if not (menu and menu:IsShown()) then Paint(false) end
    end)
    ddBtn:SetScript("OnClick", ShowMenu)
    ddBtn:HookScript("OnHide", function() if menu then menu:Hide() end end)

    local function RefreshAll()
        UpdateLabel()
        if menu and menu:IsShown() then
            for i = 1, #refreshers do refreshers[i]() end
        end
    end
    return ddBtn, RefreshAll
end

