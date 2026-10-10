if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_RowAddons.lua
--  Row add-ons: inline toggle, cog and button, the row-label and button
--  menus, the less-common expander, inline swatches, the section gates and
--  the cursor anchor row. Reads BuildCogPopup and BuildColorSwatch, so it
--  loads after EllesmereUI_Widgets_CogPopup.lua.
--  DEFERRED: body runs on first EllesmereUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()
local PP = EllesmereUI.PanelPP
local RegisterWidgetRefresh = EllesmereUI.RegisterWidgetRefresh
local MakeStyledButton = EllesmereUI.MakeStyledButton
local WB_COLOURS = EllesmereUI.WB_COLOURS
local ShowWidgetTooltip = EllesmereUI.ShowWidgetTooltip
local HideWidgetTooltip = EllesmereUI.HideWidgetTooltip
local ResolveDisabledTip = EllesmereUI.ResolveDisabledTip
local BuildToggleControl = EllesmereUI.BuildToggleControl
local BuildColorSwatch = EllesmereUI.BuildColorSwatch
local BuildCogPopup = EllesmereUI.BuildCogPopup
local BuildDropdownMenu = EllesmereUI.BuildDropdownMenu
local WireDropdownScripts = EllesmereUI.WireDropdownScripts

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

-- Inline cog button on a DualRow half-region, left of its control (or of the last inline item). Returns cogBtn, showFn; nil during the search prebuild.
-- opts: BuildCogPopup's own opts (title, rows, captureRegion, minWidth, ...) or show(btn) + optional isOpen(btn) for a custom popup; icon, size (26), gap (8), anchorTo,
--   chain (default true: anchors to and becomes region._lastInline), tip, disabled + disabledTooltip/rawTooltip/requireState (as ResolveDisabledTip; default: the host control's).
-- Alpha: 0.15 disabled, 0.4 idle, 0.7 hovered or while its popup is open. Disabled blocks the click and shows the requirement tooltip.
local function BuildInlineCog(rgn, opts)
    if EllesmereUI._prebuilding then return end
    -- A disabled cog with no tooltip of its own explains itself with its host control's requirement.
    local tipSrc = (opts.disabled and not opts.disabledTooltip) and rgn._cfg or opts
    if opts.disabled and not (tipSrc and tipSrc.disabledTooltip) and EllesmereUI.IsDevModeActive() then
        error("BuildInlineCog: disabled needs a disabledTooltip", 2)
    end
    local show = opts.show or select(2, BuildCogPopup(opts))
    local size = opts.size or 26
    local btn = CreateFrame("Button", nil, rgn)
    btn:SetSize(size, size)
    PP.Point(btn, "RIGHT", opts.anchorTo or (opts.chain ~= false and rgn._lastInline) or rgn._control or rgn, "LEFT", -(opts.gap or 8), 0)
    if opts.chain ~= false then rgn._lastInline = btn end
    btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(opts.icon or EllesmereUI.COGS_ICON)
    btn._icon = tex

    local block
    if opts.disabled then
        block = CreateFrame("Frame", nil, btn)
        block:SetAllPoints()
        block:SetFrameLevel(btn:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            local tip = tipSrc and ResolveDisabledTip(tipSrc)
            if tip then ShowWidgetTooltip(btn, tip) end
        end)
        block:SetScript("OnLeave", function() HideWidgetTooltip() end)
    end
    local function State()
        local off = opts.disabled and opts.disabled()
        local pf = type(show) == "table" and show._popupFrame
        local open = (opts.isOpen and opts.isOpen(btn)) or (pf and pf:IsShown() and pf._owner == btn)
        btn:SetAlpha(off and 0.15 or ((open or btn:IsMouseOver()) and 0.7 or 0.4))
        if block then block:SetShown(off and true or false) end
    end
    btn._euiCogState = State

    btn:SetScript("OnEnter", function(self)
        State()
        if opts.tip then ShowWidgetTooltip(self, opts.tip) end
    end)
    btn:SetScript("OnLeave", function()
        State()
        if opts.tip then HideWidgetTooltip() end
    end)
    btn:SetScript("OnClick", function(self) show(self) end)
    State()
    if opts.disabled then RegisterWidgetRefresh(State) end
    return btn, show
end

-- Inline text button on a DualRow half-region, left of its last inline item or
-- control (or at the half's right edge when it has neither, e.g. a label half).
-- opts: width (110), height (24), gap (8), chain (default true: becomes
-- region._lastInline), disabled + disabledTooltip/rawTooltip/requireState (as
-- ResolveDisabledTip): greyed, click-blocked and explaining itself while
-- disabled, re-checked with the page's widgets. Returns the button; nil during
-- the search prebuild.
function EllesmereUI.BuildInlineButton(rgn, text, onClick, opts)
    if EllesmereUI._prebuilding then return end
    opts = opts or {}
    local btn = CreateFrame("Button", nil, rgn)
    PP.Size(btn, opts.width or 110, opts.height or 24)
    local anchor = (opts.chain ~= false and rgn._lastInline) or rgn._control
    if anchor then
        PP.Point(btn, "RIGHT", anchor, "LEFT", -(opts.gap or 8), 0)
    else
        PP.Point(btn, "RIGHT", rgn, "RIGHT", -20, 0)
    end
    if opts.chain ~= false then rgn._lastInline = btn end
    btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
    MakeStyledButton(btn, text, 11, WB_COLOURS, onClick)
    if opts.disabled then
        local function State()
            local off = opts.disabled() and true or false
            btn:SetEnabled(not off)
            btn:SetAlpha(off and 0.35 or 1)
        end
        -- A disabled button still gets hover: show why it is locked.
        btn:HookScript("OnEnter", function(self)
            if not opts.disabled() then return end
            local tip = ResolveDisabledTip(opts)
            if tip then ShowWidgetTooltip(self, tip) end
        end)
        btn:HookScript("OnLeave", function() HideWidgetTooltip() end)
        State()
        RegisterWidgetRefresh(State)
    end
    return btn
end

-------------------------------------------------------------------------------
--  Row-Label and Button Menus
--  The standard dropdown list opened from something that is not a dropdown
--  control: a DualRow half's own label (BuildRowLabelMenu) or a button
--  (AttachButtonMenu). The list is built on first open, takes the standard
--  open/close behaviour and closes when its button hides. A pick writes its
--  caption into a hidden stand-in, never over the label or the button's text.
-------------------------------------------------------------------------------
local ROW_MENU_ARROW = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
-- WireDropdownScripts paints a dropdown button's border and background; these
-- buttons keep their own look.
local NO_PAINT = { SetColor = function() end, SetColorTexture = function() end }
local function NoSelection() return nil end

-- The accent, or a darker white when the accent itself is near white.
local function RowMenuLitColor()
    local ac = EllesmereUI.ELLESMERE_GREEN
    if ac.r > 0.9 and ac.g > 0.9 and ac.b > 0.9 then return 0.72, 0.72, 0.72 end
    return ac.r, ac.g, ac.b
end

-- A button over the half's label, with a chevron after the label: label and
-- chevron white at rest, in the accent while hovered or while the list is open.
-- opts: order, values, getValue(), setValue(v), itemDisabled(v) (nil, true or a
--   tooltip string, as BuildDropdownMenu's disabledValuesFn), tooltip (on hover
--   while the list is closed), menuWidth (170); optional locked() + lockTip() +
--   rawLockTip (as ResolveDisabledTip's rawTooltip): while locked the chevron
--   hides, clicks do nothing and hover explains the lock, re-checked with the
--   page's widgets. Never touches region._lastInline or region._control.
-- Returns the button; nil during the search prebuild.
local function BuildRowLabelMenu(rgn, opts)
    if EllesmereUI._prebuilding then return end
    local label = rgn._label
    if not label then return end
    local locked = opts.locked
    local lockCfg = locked and { disabledTooltip = opts.lockTip, rawTooltip = opts.rawLockTip }
    local btn = CreateFrame("Button", nil, rgn)
    btn:SetFrameLevel(rgn:GetFrameLevel() + 12)
    local arrow = btn:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(ROW_MENU_ARROW)
    arrow:SetSize(17, 17)
    arrow:SetPoint("LEFT", label, "LEFT", math.ceil(label:GetStringWidth()) + 6, -1)
    btn:SetPoint("TOPLEFT", label, "TOPLEFT", -4, 5)
    btn:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", 2, -2)
    local menu
    local function Lit(on)
        if on then
            local r, g, b = RowMenuLitColor()
            arrow:SetVertexColor(r, g, b)
            label:SetTextColor(r, g, b)
        else
            arrow:SetVertexColor(1, 1, 1)
            label:SetTextColor(EllesmereUI.TEXT_WHITE_R, EllesmereUI.TEXT_WHITE_G, EllesmereUI.TEXT_WHITE_B)
        end
    end
    local function OnEnter()
        if locked and locked() then
            local tip = ResolveDisabledTip(lockCfg)
            if tip then ShowWidgetTooltip(btn, tip) end
            return
        end
        Lit(true)
        if opts.tooltip and not (menu and menu:IsShown()) then ShowWidgetTooltip(btn, opts.tooltip) end
    end
    local function OnLeave()
        if not (menu and menu:IsShown()) then Lit(false) end
        HideWidgetTooltip()
    end
    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)
    local proxyLbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
    proxyLbl:Hide()
    local function EnsureMenu()
        if menu then return menu end
        local m, _, refresh = BuildDropdownMenu(btn, opts.menuWidth or 170, opts.order, opts.values,
            opts.getValue or NoSelection, opts.setValue, proxyLbl, "regular", opts.itemDisabled)
        menu = m
        -- The wiring takes the button's hover scripts: its own run again after.
        WireDropdownScripts(btn, proxyLbl, NO_PAINT, NO_PAINT, menu, refresh, EllesmereUI.RD_DD_COLOURS, true)
        btn:HookScript("OnEnter", OnEnter)
        btn:HookScript("OnLeave", OnLeave)
        menu:HookScript("OnShow", function() Lit(true) end)
        menu:HookScript("OnHide", function() Lit(btn:IsMouseOver()) end)
        return menu
    end
    btn:SetScript("OnClick", function()
        if locked and locked() then return end
        HideWidgetTooltip()
        local m = EnsureMenu()
        if m:IsShown() then m:Hide() else m:Show() end
    end)
    btn:HookScript("OnHide", function() if menu then menu:Hide() end end)
    Lit(false)
    if locked then
        -- Disabled while locked, still hovered to explain the lock.
        btn:SetMotionScriptsWhileDisabled(true)
        local function SyncLock()
            local off = locked() and true or false
            arrow:SetShown(not off)
            btn:SetEnabled(not off)
        end
        SyncLock()
        RegisterWidgetRefresh(SyncLock)
    end
    return btn
end

-- The list hangs off the button, as wide as the button unless opts.width says
-- otherwise; the button keeps its own hover look, held while the list shows.
-- opts: width, order, values, getValue() (default: nothing selected),
--   setValue(v), itemDisabled(v) (as BuildRowLabelMenu). Returns the toggle the
--   button's click calls; nil during the search prebuild.
local function AttachButtonMenu(btn, opts)
    if EllesmereUI._prebuilding then return end
    local enter, leave = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
    local proxyLbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
    proxyLbl:Hide()
    local menu
    local function EnsureMenu()
        if menu then return menu end
        local m, _, refresh = BuildDropdownMenu(btn, opts.width or btn:GetWidth(), opts.order, opts.values,
            opts.getValue or NoSelection, opts.setValue, proxyLbl, "regular", opts.itemDisabled)
        menu = m
        WireDropdownScripts(btn, proxyLbl, NO_PAINT, NO_PAINT, menu, refresh, EllesmereUI.RD_DD_COLOURS, true)
        if enter then btn:HookScript("OnEnter", enter) end
        if leave then
            btn:HookScript("OnLeave", function(self) if not menu:IsShown() then leave(self) end end)
            menu:HookScript("OnHide", function() if not btn:IsMouseOver() then leave(btn) end end)
        end
        return menu
    end
    btn:HookScript("OnHide", function() if menu then menu:Hide() end end)
    return function()
        local m = EnsureMenu()
        if m:IsShown() then m:Hide() else m:Show() end
    end
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
--  Sections start collapsed; expansion is session-only per sectionKey (never saved). Clicking the link forces
--  RefreshPage(true) to re-run the page builder -- the no-arg fast path only re-reads values and would never
--  reveal the collapsed rows.
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
    btn:SetScript("OnEnter", function()
        fs:SetTextColor(EG.r, EG.g, EG.b); fs:SetAlpha(1)
        leftArrow:SetVertexColor(EG.r, EG.g, EG.b); leftArrow:SetAlpha(1)
        rightArrow:SetVertexColor(EG.r, EG.g, EG.b); rightArrow:SetAlpha(1)
    end)
    btn:SetScript("OnLeave", function()
        fs:SetTextColor(1, 1, 1); fs:SetAlpha(0.7)
        leftArrow:SetVertexColor(1, 1, 1); leftArrow:SetAlpha(0.7)
        rightArrow:SetVertexColor(1, 1, 1); rightArrow:SetAlpha(0.7)
    end)
    btn:SetScript("OnClick", function()
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
    -- Active search (either box): sections render force-expanded with NO link line at all; clearing the search collapses them back. Transient flag -- the session Show/Hide state below is untouched and restores afterwards (see SetLessCommonSearchActive).
    if EllesmereUI._lessCommonSearchActive then return true, y end
    local sess = EllesmereUI._lessCommonExpanded
    if not sess then sess = {}; EllesmereUI._lessCommonExpanded = sess end
    -- Expanded: render nothing here -- the caller builds the rows, then FinishLessCommonExpander places the "Hide ..." link below them.
    if sess[sectionKey] then return true, y end
    return false, BuildLessCommonLink(parent, y, sectionKey, label, false)
end

-- Call after the wrapped rows (safe to call unconditionally: no-ops while the section is collapsed, during the search pre-build or during an active search).
local function FinishLessCommonExpander(parent, y, sectionKey, label)
    if EllesmereUI._prebuilding then return y end
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
    EllesmereUI:InvalidatePageCache()
    EllesmereUI:RefreshPage(true)
end

-------------------------------------------------------------------------------
--  BuildInlineSwatches(region, swatches, opts)
--  Inline form of the multiSwatch half: builds the same swatch list (tooltip, hasAlpha, getValue/setValue,
--  onClick override, per-swatch disabled+disabledTooltip, refreshAlpha) to the LEFT of the region's control, so a
--  slider (or any control half) can host its color swatches on the same row. Chains region._lastInline, so a cog
--  button built afterwards lands left of the swatches. opts.disabled/opts.disabledTooltip mirror the row-level disabled state of the multiSwatch form.
--  opts.size: the swatch size (nil = BuildColorSwatch's default 24).
-------------------------------------------------------------------------------
local function BuildInlineSwatches(region, swatches, opts)
    opts = opts or {}
    local level = region:GetFrameLevel() + 3
    local anchorTo = region._lastInline or region._control
    for i = #swatches, 1, -1 do
        local sc = swatches[i]
        local swatch, updateSwatch = BuildColorSwatch(region, level, sc.getValue, sc.setValue, sc.hasAlpha, opts.size)
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

EllesmereUI.BuildInlineToggle    = BuildInlineToggle
EllesmereUI.BuildInlineCog       = BuildInlineCog
EllesmereUI.BuildRowLabelMenu    = BuildRowLabelMenu
EllesmereUI.AttachButtonMenu     = AttachButtonMenu
EllesmereUI.BuildLessCommonExpander   = BuildLessCommonExpander
EllesmereUI.FinishLessCommonExpander  = FinishLessCommonExpander
EllesmereUI.SetLessCommonSearchActive = SetLessCommonSearchActive
EllesmereUI.SectionToggleSetValue     = SectionToggleSetValue
EllesmereUI.DependentSetValue         = DependentSetValue

-------------------------------------------------------------------------------
--  BuildCursorAnchorRow
--  Shared "Anchor to Cursor" row used by CDM, Resource Bars, and any future section that supports cursor anchoring.
--  opts:
--    W           = widget factory (the W: table from options page)
--    parent      = parent frame
--    getData     = function() -> settings table with anchorTo, anchorPosition, anchorOffsetX, anchorOffsetY
--    onApply     = function() -> rebuild/refresh after value change
--    disabledFn  = (optional) function() -> true when the whole row is disabled
--    disabledTip = (optional) tooltip string for disabled state
--  Returns: row, height (same as W:DualRow)
-------------------------------------------------------------------------------
local function BuildCursorAnchorRow(opts)
    local W          = opts.W
    local parent     = opts.parent
    local getData    = opts.getData
    local onApply    = opts.onApply

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
                      reload    = true,
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
        local regions = { row._leftRegion:GetRegions() }
        for i = 1, #regions do
            local reg = regions[i]
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
    BuildInlineCog(row._rightRegion, {
        title = "Cursor Offset", icon = EllesmereUI.DIRECTIONS_ICON,
        rows = {
            { type = "slider", label = "X Offset", min = -125, max = 125, step = 1,
              get = function() return getData().anchorOffsetX or 0 end,
              set = function(v) getData().anchorOffsetX = v; onApply() end },
            { type = "slider", label = "Y Offset", min = -125, max = 125, step = 1,
              get = function() return getData().anchorOffsetY or 0 end,
              set = function(v) getData().anchorOffsetY = v; onApply() end },
        },
    })

    return row, h
end
EllesmereUI.BuildCursorAnchorRow = BuildCursorAnchorRow

end  -- end deferred init
