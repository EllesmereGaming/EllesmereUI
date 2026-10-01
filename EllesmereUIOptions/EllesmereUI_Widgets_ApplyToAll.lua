if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_ApplyToAll.lua
--  Apply to All / Apply to Multiple: the sync flashes, the multi-apply
--  dropdown and the sync icon.
--  DEFERRED: body runs on first EllesmereUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()
local PP = EllesmereUI.PanelPP
local EXPRESSWAY = EllesmereUI.EXPRESSWAY
local ShowWidgetTooltip = EllesmereUI.ShowWidgetTooltip
local HideWidgetTooltip = EllesmereUI.HideWidgetTooltip

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

    -- Controller cursor loaded: the one gate for everything controller-only below.
    local padCP = EllesmereUI.PadCP()
    local menu = CreateFrame("Frame", nil, EllesmereUI.OverlayParent())
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

    local ppScale = EllesmereUI.GetPopupScale() or 1
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
    local blocker = CreateFrame("Button", nil, EllesmereUI.OverlayParent())
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
        -- Controller cursor: back onto the sync link that opened it (a no-op once that is hidden).
        if padCP and EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(anchorFrame) end
    end)

    -- Controller cursor: the popup and its catcher block what they cover without
    -- being stops, and Cancel clicks the catcher (closing the popup).
    if padCP then
        EllesmereUI.PadHint(menu, "nodepass")
        EllesmereUI.PadHint(blocker, "nodepass")
        menu.CloseButton = blocker
        EllesmereUI.TrackOverlay(blocker)
        EllesmereUI.TrackOverlay(menu)
    end

    _activeMultiApplyDropdown = menu
    menu:Show()
    if padCP and EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(menu) end
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

EllesmereUI.BuildSyncIcon       = BuildSyncIcon
EllesmereUI.BuildMultiApplyDropdown = BuildMultiApplyDropdown
end  -- end deferred init
