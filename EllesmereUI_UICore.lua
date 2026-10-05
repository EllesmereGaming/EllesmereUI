if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_UICore.lua
--  Always-resident UI primitives consumed by BOTH runtime code (bags, meters,
--  skins, minimap, login popups) and the options surface: widget tooltip,
--  disabled-tooltip wrapper, styled buttons, accent/theme/profile-accent
--  system, pooled context menu. Lives in the parent, before
--  EllesmereUI_Widgets.lua, so runtime callers keep working when the options
--  surface is LoadOnDemand.
-------------------------------------------------------------------------------

local PP         = EllesmereUI.PanelPP
local SolidTex   = EllesmereUI.SolidTex
local MakeFont   = EllesmereUI.MakeFont
local MakeBorder = EllesmereUI.MakeBorder
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN

-- Button visual constants
local BTN_BG_R   = EllesmereUI.BTN_BG_R
local BTN_BG_G   = EllesmereUI.BTN_BG_G
local BTN_BG_B   = EllesmereUI.BTN_BG_B
local BTN_BG_A   = EllesmereUI.BTN_BG_A
local BTN_BG_HA  = EllesmereUI.BTN_BG_HA
local BTN_BRD_A  = EllesmereUI.BTN_BRD_A
local BTN_BRD_HA = EllesmereUI.BTN_BRD_HA
local BTN_TXT_A  = EllesmereUI.BTN_TXT_A
local BTN_TXT_HA = EllesmereUI.BTN_TXT_HA

-------------------------------------------------------------------------------
--  Styled Buttons
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
    lbl:SetText(EllesmereUI.L(text))
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

EllesmereUI.MakeStyledButton = MakeStyledButton
EllesmereUI.WB_COLOURS       = WB_COLOURS
EllesmereUI.RB_COLOURS       = RB_COLOURS

-- Global disabled-widget tooltip: "This option requires ___ to be enabled". requirement = human-readable name ("Show Class Power", "a non-None slot"). state = "enabled" (default) or "disabled" picks the trailing verb.
local function DisabledTooltip(requirement, state)
    -- Already a whole sentence: skip the wrapper but still translate it (the
    -- catalog keys whole sentences; L() is identity on English/missing key).
    if type(requirement) == "string" and requirement:find("^This option") then
        return EllesmereUI.L(requirement)
    end
    local verb = (state == "disabled") and "disabled" or "enabled"
    -- Positional template so wrapper sentence, requirement noun and verb each localize independently (translator controls word order).
    return EllesmereUI.Lf("This option requires %1$s to be %2$s", EllesmereUI.L(requirement), EllesmereUI.L(verb))
end
EllesmereUI.DisabledTooltip = DisabledTooltip

-------------------------------------------------------------------------------
--  Shared Tooltip  (single frame, lazily created, reused by all widgets)
-------------------------------------------------------------------------------
local tooltipFrame

local function GetTooltipFrame()
    if not tooltipFrame then
        tooltipFrame = CreateFrame("Frame", nil, UIParent)
        tooltipFrame:SetFrameStrata("TOOLTIP")
        tooltipFrame:SetFrameLevel(200)
        tooltipFrame:SetSize(250, 40)
        local bg = tooltipFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        tooltipFrame.bg = bg
        MakeBorder(tooltipFrame, 1, 1, 1, 0.15, PP)
        tooltipFrame.text = MakeFont(tooltipFrame, 10, nil, 1, 1, 1, 0.80)
        tooltipFrame.text:SetPoint("TOPLEFT", 8, -8)
        tooltipFrame.text:SetPoint("TOPRIGHT", -8, -8)
        tooltipFrame.text:SetWordWrap(true)
        tooltipFrame.text:SetSpacing(3)
        tooltipFrame:Hide()
    end
    -- Unified user-customizable background (shared with the Blizzard tooltip reskin via GetTooltipBg), re-applied each call so a settings change shows on the next tooltip. Border is fixed (not customizable).
    tooltipFrame.bg:SetColorTexture(EllesmereUI.GetTooltipBg())
    return tooltipFrame
end

-- True when the anchor lives in the options panel or a registered popup (cog/confirm), so its tooltip rides the user's panel-scale slider. In-game anchors (bags, minimap, meters) stay at scale 1.
local function IsPanelFamilyAnchor(region)
    local mf = EllesmereUI._mainFrame
    local pops = EllesmereUI._popupFrames
    local node = region
    while node do
        if node == mf then return true end
        if pops then
            for i = 1, #pops do
                if pops[i].popup == node then return true end
            end
        end
        node = node:GetParent()
    end
    return false
end

-- opts (optional): { color = {r,g,b}, width = number } overrides text colour / forces width
local function ShowWidgetTooltip(label, text, opts)
    -- Suppress in M+/raid/PvP combat: frame APIs return secret values in tainted execution; opts.force bypasses.
    if not (opts and opts.force) then
        local _, iType = IsInInstance()
        if iType == "party" and C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
           and C_ChallengeMode.IsChallengeModeActive() then return end
        if iType == "raid" and InCombatLockdown() then return end
        if (iType == "pvp" or iType == "arena") and InCombatLockdown() then return end
    end
    -- text may be a function for dynamic text; resolved after suppression checks so it isn't called when nothing will show.
    if type(text) == "function" then text = text() end
    local tt = GetTooltipFrame()
    local MAX_W = 250
    local PAD = 8  -- horizontal padding each side (matches text anchor insets)
    if opts and opts.width then
        tt:SetWidth(opts.width)
    else
        -- Natural single-line width is measured after Show, then clamped to MAX_W
        tt:SetWidth(MAX_W)
    end
    if opts and opts.color then
        tt.text:SetTextColor(opts.color[1], opts.color[2], opts.color[3], opts.color[4] or 0.80)
    else
        tt.text:SetTextColor(1, 1, 1, 0.80)
    end
    if opts and opts.justify then
        tt.text:SetJustifyH(opts.justify)
    else
        tt.text:SetJustifyH("CENTER")
    end
    tt.text:SetText(EllesmereUI.L(text))
    -- Scale must be set before anchoring: the cursor branch divides by the tooltip's effective scale (reset to 1 in HideWidgetTooltip).
    local ttScaleMult = opts and opts.scale
    if not ttScaleMult then
        ttScaleMult = 1
        local us = EllesmereUIDB and EllesmereUIDB.panelScale
        if us and us ~= 1 and label and label.GetParent and IsPanelFamilyAnchor(label) then
            ttScaleMult = us
        end
    end
    tt:SetScale(ttScaleMult)
    tt:ClearAllPoints()
    if opts and opts.anchorPoint then
        -- Custom anchor: opts.anchorPoint on tooltip -> opts.anchorTo on label
        tt:SetPoint(opts.anchorPoint, label, opts.anchorTo or opts.anchorPoint, opts.anchorX or 0, opts.anchorY or 0)
    elseif opts and opts.anchor == "cursor" then
        local scale = tt:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        tt:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx / scale, cy / scale + 4)
    elseif opts and opts.anchor == "below" then
        tt:SetPoint("TOP", label, "BOTTOM", 0, -4)
    elseif opts and opts.anchor == "left" then
        tt:SetPoint("RIGHT", label, "LEFT", -4, 0)
    elseif opts and opts.anchor == "right" then
        tt:SetPoint("LEFT", label, "RIGHT", 4, 0)
    else
        tt:SetPoint("BOTTOM", label, "TOP", 0, 4)
    end
    -- Show at alpha 0 BEFORE measuring: font geometry must be computed on a visible frame (GetStringHeight is wrong on hidden frames).
    tt:SetAlpha(0)
    tt:Show()
    -- Auto-size: natural text width + padding, capped at MAX_W
    if not (opts and opts.width) then
        local sw = tt.text:GetStringWidth()
        if issecretvalue and issecretvalue(sw) then
            tt:SetWidth(MAX_W)
        else
            local naturalW = sw + PAD * 2
            tt:SetWidth(math.min(naturalW, MAX_W))
        end
    end
    tt:SetHeight(10)
    local textH = tt.text:GetStringHeight()
    if issecretvalue and issecretvalue(textH) then
        tt:SetHeight(26)
    else
        tt:SetHeight(textH + 16)
    end
    -- Clamp to screen edges; skipped when frame metrics are secret (tainted M+)
    local ttScale = tt:GetEffectiveScale()
    local _ttLeft = tt:GetLeft()
    local _ttRight = tt:GetRight()
    local _isv = issecretvalue
    if not (_isv and (_isv(ttScale) or _isv(_ttLeft) or _isv(_ttRight))) then
        local screenW = GetScreenWidth() * UIParent:GetEffectiveScale()
        local ttLeft = (_ttLeft or 0) * ttScale
        local ttRight = (_ttRight or 0) * ttScale
        if ttLeft < 0 then
            local pt, rel, relPt, px, py = tt:GetPoint(1)
            if pt then
                tt:SetPoint(pt, rel, relPt, (px or 0) - ttLeft / ttScale, py or 0)
            end
        elseif ttRight > screenW then
            local pt, rel, relPt, px, py = tt:GetPoint(1)
            if pt then
                tt:SetPoint(pt, rel, relPt, (px or 0) - (ttRight - screenW) / ttScale, py or 0)
            end
        end
        local screenH = GetScreenHeight() * UIParent:GetEffectiveScale()
        local ttTop = (tt:GetTop() or 0) * ttScale
        local ttBottom = (tt:GetBottom() or 0) * ttScale
        if ttBottom < 0 then
            local pt, rel, relPt, px, py = tt:GetPoint(1)
            if pt then
                tt:SetPoint(pt, rel, relPt, px or 0, (py or 0) - ttBottom / ttScale)
            end
        elseif ttTop > screenH then
            local pt, rel, relPt, px, py = tt:GetPoint(1)
            if pt then
                tt:SetPoint(pt, rel, relPt, px or 0, (py or 0) - (ttTop - screenH) / ttScale)
            end
        end
    end
    -- Cancel an in-progress fade-out so its OnFinished doesn't hide us
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

local function HideWidgetTooltip(instant)
    local tt = GetTooltipFrame()
    if not tt:IsShown() then return end
    if tt._fadeOutAG then tt._fadeOutAG:Stop() end
    if tt._fadeAG then tt._fadeAG:Stop() end
    if instant then
        tt:SetAlpha(0); tt:Hide(); tt:SetScale(1)
        return
    end
    -- Fade out; the scale reset must wait until the fade completes, or the still-fading tooltip visibly resizes whenever panel scale ~= 1 (ShowWidgetTooltip re-sets the scale before anchoring anyway).
    if not tt._fadeOutAG then
        tt._fadeOutAG = tt:CreateAnimationGroup()
        tt._fadeOut = tt._fadeOutAG:CreateAnimation("Alpha")
        tt._fadeOut:SetDuration(0.25)
        tt._fadeOut:SetSmoothing("IN")
    end
    tt._fadeOut:SetFromAlpha(tt:GetAlpha())
    tt._fadeOut:SetToAlpha(0)
    tt._fadeOutAG:SetScript("OnFinished", function() tt:SetAlpha(0); tt:Hide(); tt:SetScale(1) end)
    tt._fadeOutAG:Play()
end

EllesmereUI.ShowWidgetTooltip = ShowWidgetTooltip
EllesmereUI.HideWidgetTooltip = HideWidgetTooltip

-------------------------------------------------------------------------------
--  Theme / Accent / Per-Profile Accent
-------------------------------------------------------------------------------

-- Theme API -- exposed so General Options can read/write
EllesmereUI.DEFAULT_ACCENT = { r = EllesmereUI.DEFAULT_ACCENT_R, g = EllesmereUI.DEFAULT_ACCENT_G, b = EllesmereUI.DEFAULT_ACCENT_B }

EllesmereUI.GetAccentColor = function()
    return ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b
end

--- Active theme name (default per client: EllesmereUI.DEFAULT_THEME)
EllesmereUI.GetActiveTheme = function()
    return EllesmereUIDB and EllesmereUIDB.activeTheme or EllesmereUI.DEFAULT_THEME
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

--- Internal: snap accent to all registered one-time elements (no transition). Colour objects are reused to avoid per-tick allocations.
local _gradStart = CreateColor(0, 0, 0, 0)
local _gradEnd   = CreateColor(0, 0, 0, 0)

local function UpdateAccentElements(r, g, b)
    for _, entry in ipairs(EllesmereUI._accentElements) do
        if entry.type == "solid" and entry.obj then
            entry.obj:SetColorTexture(r, g, b, entry.a or 1)
        elseif entry.type == "gradient" and entry.obj then
            entry.obj:SetColorTexture(r, g, b, 1)
            _gradStart.r, _gradStart.g, _gradStart.b, _gradStart.a = r, g, b, entry.startA or 0.15
            _gradEnd.r, _gradEnd.g, _gradEnd.b, _gradEnd.a = r, g, b, 0
            entry.obj:SetGradient("HORIZONTAL", _gradStart, _gradEnd)
        elseif entry.type == "vertex" and entry.obj then
            entry.obj:SetVertexColor(r, g, b, 1)
        elseif entry.type == "callback" and entry.fn then
            entry.fn(r, g, b)
        end
    end
end

--- Internal: apply accent instantly (for color picker dragging, resets, etc.)
local function ApplyAccentLive(r, g, b)
    -- Canonical colour table updated in place, then registered one-time elements
    ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = r, g, b
    UpdateAccentElements(r, g, b)

    -- Cached popups rebuild with the new accent
    EllesmereUI._InvalidateConfirmPopup()

    -- Fast path only; a full rebuild would churn memory
    EllesmereUI:RefreshPage()
end

--- SetActiveTheme: persists and applies with an animated transition. Changes only the options panel background; accent colour is independent (accent swatch / class colour toggle).
EllesmereUI.SetActiveTheme = function(theme)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.activeTheme = theme
    ELLESMERE_GREEN._themeEnabled = true
    local r, g, b = ResolveThemeColor(theme)

    if EllesmereUI._applyThemeBG then
        EllesmereUI._applyThemeBG(theme, r, g, b)
    end
end

--- SetAccentColor: persists accent color (per-profile) and applies live.
EllesmereUI.SetAccentColor = function(r, g, b)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    -- Persist on the active profile; the global root stays frozen as fallback.
    EllesmereUI.SetActiveProfileAccent({ r = r, g = g, b = b }, false)
    ApplyAccentLive(r, g, b)
end

--- Applies accent live without persisting (custom/class accent mode switches).
EllesmereUI.ApplyAccentColorLive = function(r, g, b)
    ApplyAccentLive(r, g, b)
end

-------------------------------------------------------------------------------
--  Per-profile UI accent color: lives per-profile as `euiAccent`. Resolution
--  order: current profile's euiAccent -> frozen global root -> theme color.
--  The global keys EllesmereUIDB.customAccentColor / useClassAccentColor stay
--  in SavedVariables permanently as that fallback and are NEVER written at
--  runtime, so profiles without euiAccent keep their existing accent until
--  edited. The EUI Options Theme (activeTheme / panel background) is separate and global.
-------------------------------------------------------------------------------
function EllesmereUI.GetActiveProfileData()
    local db = EllesmereUIDB
    if not db or not db.profiles then return nil end
    return db.profiles[db.activeProfile or "Default"]
end

-- Writer used by the accent swatch. `custom` and `useClass` are each optional; pass nil to leave unchanged.
function EllesmereUI.SetActiveProfileAccent(custom, useClass)
    local db = EllesmereUIDB
    if not db then return end
    db.profiles = db.profiles or {}
    local name = db.activeProfile or "Default"
    local p = db.profiles[name]
    if not p then p = {}; db.profiles[name] = p end
    p.euiAccent = p.euiAccent or {}
    if custom   ~= nil then p.euiAccent.custom   = custom   end
    if useClass ~= nil then p.euiAccent.useClass = useClass end
end

-- Swatch display helper: CURRENT profile's accent state, falling back to the frozen global root. `~= nil` on the bool so profile useClass=false correctly overrides a global useClass=true.
function EllesmereUI.GetActiveAccentState()
    local p   = EllesmereUI.GetActiveProfileData()
    local acc = p and p.euiAccent
    local useClass
    if acc and acc.useClass ~= nil then
        useClass = acc.useClass
    else
        useClass = (EllesmereUIDB and EllesmereUIDB.useClassAccentColor) or false
    end
    local custom = (acc and acc.custom) or (EllesmereUIDB and EllesmereUIDB.customAccentColor)
    return useClass, custom
end

-- Accent for a given profile table. Returns useClass(bool), r, g, b. Order: profile euiAccent -> frozen global root -> theme color (falling back to the default accent), which keeps a non-default theme with no custom accent looking unchanged.
function EllesmereUI.ResolveProfileAccent(profileData)
    local themeR, themeG, themeB = ResolveThemeColor(EllesmereUI.GetActiveTheme())
    local acc = profileData and profileData.euiAccent
    -- 1) per-profile
    if acc and acc.useClass then
        local c = EllesmereUI.CLASS_COLOR_MAP[EllesmereUI._playerClass]
        if c then return true, c.r, c.g, c.b end
    end
    if acc and acc.custom then
        local ca = acc.custom
        return false, ca.r or themeR, ca.g or themeG, ca.b or themeB
    end
    -- 2) frozen global root -- ONLY when the profile has no explicit euiAccent. An explicit per-profile opt-out (useClass=false, no custom yet) must NOT fall through to the global class color; it drops to the global custom/theme terminal below, matching the displayed Custom swatch state.
    if (not acc) and EllesmereUIDB and EllesmereUIDB.useClassAccentColor then
        local c = EllesmereUI.CLASS_COLOR_MAP[EllesmereUI._playerClass]
        if c then return true, c.r, c.g, c.b end
    end
    local gca = EllesmereUIDB and EllesmereUIDB.customAccentColor
    if gca then return false, gca.r or themeR, gca.g or themeG, gca.b or themeB end
    -- 3) theme color
    return false, themeR, themeG, themeB
end

-- Live accent RGB for the active profile (used at login / on profile swap).
function EllesmereUI.ResolveActiveAccent()
    local _, r, g, b = EllesmereUI.ResolveProfileAccent(EllesmereUI.GetActiveProfileData())
    return r, g, b
end

-- Single live re-apply entrypoint: re-resolves the active profile's accent and applies it to ELLESMERE_GREEN + all registered elements without persisting.
function EllesmereUI.RefreshAccent()
    local r, g, b = EllesmereUI.ResolveActiveAccent()
    ApplyAccentLive(r, g, b)
end

--- Class color for the current player
EllesmereUI.GetPlayerClassColor = function()
    local clr = EllesmereUI.CLASS_COLOR_MAP[EllesmereUI._playerClass]
    if clr then return clr.r, clr.g, clr.b end
    return EllesmereUI.DEFAULT_ACCENT_R, EllesmereUI.DEFAULT_ACCENT_G, EllesmereUI.DEFAULT_ACCENT_B
end

--- Clears the saved custom accent, reverting to the theme default.
EllesmereUI.ResetAccentColor = function()
    if EllesmereUIDB then EllesmereUIDB.accentColor = nil end
    local theme = EllesmereUI.GetActiveTheme()
    local r, g, b = ResolveThemeColor(theme)
    ApplyAccentLive(r, g, b)
end

--- Wipes all style/theme settings back to defaults; called by the global "Reset to Defaults" button before ReloadUI().
EllesmereUI.ResetTheme = function()
    if not EllesmereUIDB then return end
    EllesmereUIDB.accentColor   = nil
    EllesmereUIDB.activeTheme   = nil
end

-------------------------------------------------------------------------------
--  ShowContextMenu(anchor, items, opts)
--  Shared pooled context menu used by Blizz UI Enhanced (character sheet gear-set cog, etc.). Pops up at the cursor.
--  items = { { text = "Foo", onClick = fn, isDisabled = fn? }, ... }
--  Opt-in item forms:
--    "---"               a separator line
--    isActive = true     accent label on a highlight while not hovered
--    tooltip = "..."     widget tooltip while hovered
--    children = { ... }  a submenu of items, opened on hover (arrow on the row)
--    isInput = true      a number box: getValue() fills it, Enter hands
--                        setValue(v) the whole number, floored at min (or 1)
--  opts (optional): below = true hangs the menu off `anchor`'s bottom-left edge
--  instead of the cursor (the dropdown placement of the options widgets);
--  minWidth widens the menu to the anchor's width so it reads as a dropdown.
--  above = true opens it upward, right edges aligned with `anchor` (growing
--  up from the cursor without one). look = "meter" is the Damage Meters header
--  menu's look: 22px rows, 11px plain (shadowless) labels, no inner padding,
--  the context-menu background and the Blizz UI Enhanced popup-menu border.
--  look = "meterForever" is its WoW Forever variant: the panel in WoW
--  Forever's dropdown art and gold lit labels (the meter look's panel on a
--  client without the art). fontKey sets the labels in that module's font,
--  through ApplyModuleFont unless the look keeps plain labels (else the
--  global font).
--  Behavior: click-outside-to-dismiss (polled ~10hz); a second call from the same
--  anchor while its menu is open closes it (toggle); auto-closes on combat entry so
--  insecure clicks can't taint protected paths while lockdown is active. One menu
--  is open at a time: ContextMenuOwner() returns its anchor, CloseContextMenu()
--  closes it.
-------------------------------------------------------------------------------
local CTX_ARROW = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow.png"
-- Row metrics and dressing per look. Each look keeps its own panels: the
-- popup-menu border replaces a panel's own border for good.
local CTX_LOOKS = {
    default = { rowH = 26, sepH = 7, pad = 4, size = 12, minW = 140, textPad = 40,
                left = 10, right = -10 },
    meter   = { rowH = 22, sepH = 7, pad = 0, size = 11, minW = 100, textPad = 50,
                left = 8, right = -18, noWrap = true, ctxBg = true, popupBorder = true,
                plainFont = true },
    -- atlas: the panel's art in place of its fill and borders (drawn past
    -- its edges); lit: the hovered and active label colour.
    meterForever = { rowH = 22, sepH = 7, pad = 0, size = 11, minW = 100, textPad = 50,
                left = 8, right = -18, noWrap = true, ctxBg = true, popupBorder = true,
                plainFont = true, atlas = "common-dropdown-bg", lit = { r = 1, g = 0.82, b = 0 } },
}
local _ctxPanels = {}  -- look -> its top-level panel
local _ctxOpen         -- the top-level panel on screen, if any
local CtxShowSub

local function CtxRoot(panel)
    return panel._root or panel
end

-- Lit: hovered or active.
local function CtxPaint(row, lit)
    row._hl:SetColorTexture(1, 1, 1, lit and (EllesmereUI.DD_ITEM_HL_A or 0.08) or 0)
    local EG = lit and (row._panel._look.lit or EllesmereUI.ELLESMERE_GREEN)
    if EG then
        row._lbl:SetTextColor(EG.r, EG.g, EG.b, 1)
    else
        row._lbl:SetTextColor(1, 1, 1, 1)
    end
end

local function CtxRowEnter(row)
    local sub = row._panel._sub
    if row._disabled then
        if sub then sub:Hide() end
        return
    end
    local item = row._item
    CtxPaint(row, true)
    if item.tooltip then
        CtxRoot(row._panel)._tip = true
        EllesmereUI.ShowWidgetTooltip(row, item.tooltip)
    end
    if item.children then
        CtxShowSub(row, item.children)
    elseif sub then
        sub:Hide()
    end
end

local function CtxRowLeave(row)
    if row._disabled then return end
    local item = row._item
    if item.tooltip then
        CtxRoot(row._panel)._tip = nil
        EllesmereUI.HideWidgetTooltip()
    end
    CtxPaint(row, item.isActive)
    -- A submenu stays open while the pointer moved into it.
    local sub = row._panel._sub
    if sub and item.children and not (sub:IsShown() and sub:IsMouseOver()) then
        sub:Hide()
    end
end

local function CtxRowClick(row)
    local item = row._item
    if row._disabled or item.children then return end
    CtxRoot(row._panel):Hide()
    if item.onClick then item.onClick() end
end

local function CtxBoxCommit(box)
    local item = box:GetParent()._item
    local v = math.max(item.min or 1, math.floor(box:GetNumber() + 0.5))
    box:SetNumber(v)
    if item.setValue then item.setValue(v) end
    box:ClearFocus()
end

local function CtxBoxEscape(box)
    box:ClearFocus()
end

-- Combat closes a menu: the event is registered only while it is shown.
local function CtxPanelShown(self)
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
end

local function CtxPanelHidden(self)
    self:SetScript("OnUpdate", nil)
    -- Hidden along with UIParent (Alt-Z, a cinematic): a styled look closes
    -- for real; the default look stays shown and keeps its combat close.
    if self:IsShown() and self._look ~= CTX_LOOKS.default then self:Hide() end
    if not self:IsShown() then self:UnregisterEvent("PLAYER_REGEN_DISABLED") end
    self._owner = nil
    self._src = nil
    local rows = self._items
    for i = 1, #rows do
        local box = rows[i]._box
        if box then box:ClearFocus() end
    end
    if self._sub then self._sub:Hide() end
    if _ctxOpen == self then _ctxOpen = nil end
    if self._tip then
        self._tip = nil
        EllesmereUI.HideWidgetTooltip()
    end
end

-- Unregister first: hiding a panel that is already invisible fires no OnHide.
local function CtxPanelEvent(self)
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:Hide()
end

-- Throttled click-outside poll (~10hz), set on the top-level panel while shown.
local function CtxPoll(self, dt)
    self._elapsed = self._elapsed + dt
    if self._elapsed < 0.1 then return end
    self._elapsed = 0
    if self:IsMouseOver() or not IsMouseButtonDown("LeftButton") then return end
    -- A click on the owner is left to the owner: its OnClick reaches
    -- ShowContextMenu with the menu still open and toggles it closed.
    local owner = self._owner
    if owner and owner.IsMouseOver and owner:IsMouseOver() then return end
    local sub = self._sub
    while sub and sub:IsShown() do
        if sub:IsMouseOver() then return end
        sub = sub._sub
    end
    self:Hide()
end

local function CtxNewPanel(look, level)
    local RS = EllesmereUI.RESKIN or {}
    local p = CreateFrame("Frame", nil, UIParent)
    p:Hide()
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel(200 + level * 10)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(RS.BG_R or 0.067, RS.BG_G or 0.067, RS.BG_B or 0.067,
        look.ctxBg and (RS.CTX_ALPHA or 0.95) or (RS.QT_ALPHA or 0.97))
    p._bg = bg
    local PP_L = EllesmereUI.PP
    if look.atlas and C_Texture.GetAtlasInfo(look.atlas) then
        local art = p:CreateTexture(nil, "BACKGROUND", nil, -1)
        art:SetAtlas(look.atlas)
        art:SetPoint("TOPLEFT", p, "TOPLEFT", -10, 7)
        art:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 10, -13)
        art:SetAlpha(0.925)
        bg:SetColorTexture(0, 0, 0, 0)
        p._art = art
    elseif PP_L and PP_L.CreateBorder then
        PP_L.CreateBorder(p, 1, 1, 1, RS.BRD_ALPHA or 0.18, 1)
    end
    p._look, p._level = look, level
    p._items = {}
    p._elapsed = 0
    p:SetScript("OnShow", CtxPanelShown)
    p:SetScript("OnHide", CtxPanelHidden)
    p:SetScript("OnEvent", CtxPanelEvent)
    return p
end

local function CtxRow(panel, i)
    local row = panel._items[i]
    if row then return row end
    local look = panel._look
    row = CreateFrame("Button", nil, panel)
    local hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    hl:SetAllPoints()
    row._hl = hl
    local lbl = row:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("LEFT", row, "LEFT", look.left, 0)
    lbl:SetPoint("RIGHT", row, "RIGHT", look.right, 0)
    lbl:SetJustifyH("LEFT")
    if look.noWrap then lbl:SetWordWrap(false) end
    row._lbl = lbl
    row._panel = panel
    row:SetScript("OnEnter", CtxRowEnter)
    row:SetScript("OnLeave", CtxRowLeave)
    row:SetScript("OnClick", CtxRowClick)
    panel._items[i] = row
    return row
end

-- Separator line, submenu arrow and number box: made on a row's first need.
local function CtxSep(row)
    local sep = row._sep
    if not sep then
        sep = row:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("LEFT", row, "LEFT", 6, 0)
        sep:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        sep:SetColorTexture(1, 1, 1, 0.12)
        row._sep = sep
    end
    return sep
end

local function CtxArrow(row)
    local arrow = row._arrow
    if not arrow then
        arrow = row:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture(CTX_ARROW)
        arrow:SetSize(19, 19)
        arrow:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        arrow:SetRotation(math.pi / 2)
        row._arrow = arrow
    end
    return arrow
end

local function CtxBox(row, fontPath, outline)
    local box = row._box
    if not box then
        box = CreateFrame("EditBox", nil, row)
        box:SetSize(50, 18)
        box:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        box:SetFrameLevel(row:GetFrameLevel() + 3)
        box:SetFont(fontPath, 10, outline)
        box:SetTextColor(1, 1, 1, 0.9)
        box:SetJustifyH("CENTER")
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.4)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(5)
        box:SetScript("OnEnterPressed", CtxBoxCommit)
        box:SetScript("OnEscapePressed", CtxBoxEscape)
        row._box = box
    end
    box:SetFont(fontPath, 10, outline)
    return box
end

local function CtxLayout(panel, items, minW, fontKey)
    local look = panel._look
    if look.popupBorder and not panel._art and EllesmereUI._applyBlizzardConfiguredBorder
       and C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin") then
        pcall(EllesmereUI._applyBlizzardConfiguredBorder, panel, "popupMenu", 1)
    end
    local L, size = EllesmereUI.L, look.size
    local fontPath, outline
    if fontKey then
        fontPath, outline = EllesmereUI.GetFontPath(fontKey), EllesmereUI.GetFontOutlineFlag(fontKey)
    else
        fontPath = (EllesmereUI.GetFontPath()) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        outline  = (EllesmereUI.GetFontOutlineFlag()) or ""
    end

    -- Hide pooled rows past the current item count
    local rows = panel._items
    for i = 1, #rows do rows[i]:Hide() end

    local mfs = panel._measureFS
    if not mfs then
        mfs = panel:CreateFontString(nil, "OVERLAY")
        panel._measureFS = mfs
    end
    mfs:SetFont(fontPath, size, outline)
    local widest = 0
    for _, item in ipairs(items) do
        if type(item) == "table" then
            mfs:SetText(L(item.text or ""))
            local w = mfs:GetStringWidth() or 0
            if w > widest then widest = w end
        end
    end
    mfs:SetText("")
    mfs:Hide()

    local pad = look.pad
    local width = math.max(minW or look.minW, widest + look.textPad)
    local y = pad
    for i, item in ipairs(items) do
        local row = CtxRow(panel, i)
        local lbl = row._lbl
        -- A row keeps the shadow a module font primed it with; clear it on
        -- the plain path.
        if fontKey and not look.plainFont then
            EllesmereUI.ApplyModuleFont(lbl, fontPath, size, fontKey, outline)
            row._primed = true
        else
            if row._primed then
                EllesmereUI.PrimeFontShadow(lbl, false)
                row._primed = nil
            end
            lbl:SetFont(fontPath, size, outline)
        end
        row._hl:SetColorTexture(1, 1, 1, 0)
        if row._sep then row._sep:Hide() end
        if row._arrow then row._arrow:Hide() end
        if row._box then row._box:Hide() end
        local h = look.rowH
        if item == "---" then
            h = look.sepH
            row._item, row._disabled = nil, true
            lbl:SetText("")
            CtxSep(row):Show()
            row:EnableMouse(false)
        else
            row._item = item
            lbl:SetText(L(item.text or ""))
            if item.isInput then
                row._disabled = true
                lbl:SetTextColor(1, 1, 1, 1)
                row:EnableMouse(false)
                local box = CtxBox(row, fontPath, outline)
                box:SetNumber(item.getValue and item.getValue() or 0)
                box:Show()
            else
                local disabled = item.isDisabled and item.isDisabled()
                row._disabled = disabled
                row:EnableMouse(true)
                if item.children then
                    local arrow = CtxArrow(row)
                    arrow:SetVertexColor(1, 1, 1, disabled and 0.2 or 0.75)
                    arrow:Show()
                end
                if disabled then
                    lbl:SetTextColor(0.4, 0.4, 0.4, 0.5)
                else
                    CtxPaint(row, item.isActive)
                end
            end
        end
        row:SetSize(width - pad * 2, h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", pad, -y)
        row:Show()
        y = y + h
    end
    panel:SetSize(width, y + pad)
end

-- Beside the row, flipped to its left when it would run off the screen.
CtxShowSub = function(row, children)
    local parent = row._panel
    local sub = parent._sub
    if not sub then
        sub = CtxNewPanel(parent._look, parent._level + 1)
        sub._root = CtxRoot(parent)
        parent._sub = sub
    end
    -- Already showing this row's items: nothing changes while a menu is open.
    if sub:IsShown() and sub._src == children and sub._srcRow == row then return end
    CtxLayout(sub, children, nil, CtxRoot(parent)._fontKey)
    sub._src, sub._srcRow = children, row
    sub:ClearAllPoints()
    local right, screen = row:GetRight(), UIParent:GetRight()
    if right and screen and right + sub:GetWidth() > screen then
        sub:SetPoint("TOPRIGHT", row, "TOPLEFT", 0, 0)
    else
        sub:SetPoint("TOPLEFT", row, "TOPRIGHT", 0, 0)
    end
    sub:Show()
end

local function ShowContextMenu(anchor, items, opts)
    -- Toggle: the owner's click while its own menu is open closes it.
    if anchor and _ctxOpen and _ctxOpen._owner == anchor then
        _ctxOpen:Hide()
        return
    end
    local look = CTX_LOOKS[opts and opts.look] or CTX_LOOKS.default
    local panel = _ctxPanels[look]
    if not panel then
        panel = CtxNewPanel(look, 0)
        _ctxPanels[look] = panel
    end
    if _ctxOpen and _ctxOpen ~= panel then _ctxOpen:Hide() end
    if panel._sub then panel._sub:Hide() end
    panel._owner = anchor
    panel._fontKey = opts and opts.fontKey

    CtxLayout(panel, items, opts and opts.minWidth, panel._fontKey)

    panel:ClearAllPoints()
    if opts and opts.below and anchor then
        -- Dropdown placement: under the anchor, left edges aligned (screen
        -- clamping still applies).
        panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    elseif opts and opts.above and anchor then
        panel:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
    else
        -- Position at cursor
        local scale = panel:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        panel:SetPoint((opts and opts.above) and "BOTTOMLEFT" or "TOPLEFT",
            UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    end
    _ctxOpen = panel
    panel:Show()

    panel._elapsed = 0
    panel:SetScript("OnUpdate", CtxPoll)
end

EllesmereUI.ShowContextMenu = ShowContextMenu

-- The open menu's anchor (nil when none is open or it sits at the cursor).
function EllesmereUI.ContextMenuOwner()
    return _ctxOpen and _ctxOpen._owner
end

function EllesmereUI.CloseContextMenu()
    if _ctxOpen then _ctxOpen:Hide() end
end

-------------------------------------------------------------------------------
--  Unit display names. WoW Forever characters carry a surname, which
--  UnitName hands back as its second value (retail: the realm), and
--  Blizzard's own frames show "First Last". Pass UnitName's two returns in:
--      EllesmereUI.WithSurname(UnitName(unit))
--  Retail gets the first value back unchanged. A secret name (protected
--  content) comes back as is, first name only: it cannot be inspected or
--  joined. Your own surname follows Blizzard's show-surname preference.
--  Joined names are cached per name pair, so repaints build no strings.
-------------------------------------------------------------------------------
do
    local IS_FOREVER = EllesmereUI.IS_FOREVER == true
    local SEP = Constants and Constants.CharacterNameSeparatorConsts
        and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
    local joined = {}   -- [name][surname] = the display string

    function EllesmereUI.WithSurname(name, surname)
        if not IS_FOREVER then return name end
        if issecretvalue(name) or issecretvalue(surname) then return name end
        if type(name) ~= "string" or type(surname) ~= "string" or surname == "" then return name end
        local PI = C_PlayerInfo
        if PI and PI.ShouldDisplaySurname and not PI.ShouldDisplaySurname() then
            local myName, mySurname = (UnitNameUnmodified or UnitName)("player")
            if name == myName and surname == mySurname then return name end
        end
        local row = joined[name]
        if not row then row = {}; joined[name] = row end
        local full = row[surname]
        if not full then
            local tail = SEP .. surname
            -- Some units already carry it in the first value.
            full = (name:sub(-#tail) == tail) and name or (name .. tail)
            row[surname] = full
        end
        return full
    end

    -- Name Format (WoW Forever only; nil on retail, where no caller runs):
    --     EllesmereUI.ForeverShortName(name, mode)
    -- mode "first" keeps the name's first word, "last" its last; any other
    -- mode (nil = First and Last) returns it unchanged, as does a one-word,
    -- secret or non-string name. Words split at spaces and at the surname
    -- separator. Short forms are cached per mode and name, so repaints build
    -- no strings; a mode's cache is wiped once it holds 256 names.
    if IS_FOREVER then
        local short = { first = {}, last = {} }   -- [mode][name] = short form
        local count = { first = 0, last = 0 }
        local sepPat = (SEP ~= " " and SEP ~= "") and SEP:gsub("%W", "%%%0") or nil

        function EllesmereUI.ForeverShortName(name, mode)
            local cache = short[mode]
            if not cache or issecretvalue(name) or type(name) ~= "string" then return name end
            local s = cache[name]
            if s then return s end
            local words = sepPat and name:gsub(sepPat, " ") or name
            if mode == "first" then
                s = words:match("^%s*(%S+)")
            else
                s = words:match("(%S+)%s*$")
            end
            s = s or name
            if count[mode] >= 256 then wipe(cache); count[mode] = 0 end
            cache[name] = s
            count[mode] = count[mode] + 1
            return s
        end
    end
end

-------------------------------------------------------------------------------
--  Threat % text paint (WoW Forever only; nil on retail, where no caller runs).
--      EllesmereUI.PaintThreatPct(fs, pct, status, isTanking, colorByThreat)
--  Pass UnitDetailedThreatSituation's first three returns. The percent can be
--  secret and goes straight to SetFormattedText. Colour: white when
--  colorByThreat is off; the status colour while status is readable; else the
--  isTanking fold between the has-aggro and low-threat colours; else white.
--  Only the plain white mode is remembered per font string (never a value).
--      EllesmereUI.PaintThreatGap(fs, text, ahead, colorOn, aheadC, behindC)
--  The Threat Gap text: the formatted gap in aheadC or behindC by who leads,
--  or white while colorOn is off (the same white memory).
-------------------------------------------------------------------------------
if EllesmereUI.IS_FOREVER then
    local aggR, aggG, aggB, lowR, lowG, lowB, fold
    local white  -- [fs] = true while its last paint was plain white (weak keys)

    local function PaintWhite(fs)
        if not white then white = setmetatable({}, { __mode = "k" }) end
        if white[fs] then return end
        white[fs] = true
        fs:SetTextColor(1, 1, 1)
    end

    function EllesmereUI.PaintThreatPct(fs, pct, status, isTanking, colorByThreat)
        fs:SetFormattedText("%.0f%%", pct)
        if not colorByThreat then return PaintWhite(fs) end
        if type(status) == "number" and not issecretvalue(status) then
            fs:SetTextColor(GetThreatStatusColor(status))
        elseif type(isTanking) == "boolean" then
            if not fold then
                aggR, aggG, aggB = GetThreatStatusColor(3)
                lowR, lowG, lowB = GetThreatStatusColor(0)
                fold = C_CurveUtil.EvaluateColorValueFromBoolean
            end
            fs:SetTextColor(fold(isTanking, aggR, lowR), fold(isTanking, aggG, lowG), fold(isTanking, aggB, lowB))
        else
            return PaintWhite(fs)
        end
        if white and white[fs] then white[fs] = nil end
    end

    function EllesmereUI.PaintThreatGap(fs, text, ahead, colorOn, aheadC, behindC)
        fs:SetText(text)
        if not colorOn then return PaintWhite(fs) end
        local c = ahead and aheadC or behindC
        fs:SetTextColor(c.r, c.g, c.b)
        if white and white[fs] then white[fs] = nil end
    end
end -- IS_FOREVER

-------------------------------------------------------------------------------
--  Controller support: ConsolePort interop and Blizzard's native gamepad
--  pointer. This header is the one comment in the suite that names that addon;
--  call sites say "controller cursor". The public cursor API of the addon is
--  the only thing used (its `ConsolePort` global, looked up live on every call
--  so load order never matters). Mouse/keyboard players pay one table lookup
--  or one C call at an edge that already runs (open, show, click, Escape):
--  nothing here registers an event, runs an OnUpdate or ticker, creates a
--  frame or writes SavedVariables unless a controller signal is present or
--  a feature follows PadConnected() through WatchPad (its three events stay
--  registered only while a watcher exists).
--    PadCP()                the controller UI addon's API table, or nil
--    PadNative()            Blizzard's gamepad is the active input right now
--    PadInUse()             PadCP() or PadNative(): the controller signal
--    PadConnected()         gamepad support is on and a controller is
--                           connected (not the last input: no mouse flicker)
--    WatchPad(owner, fn)    fn(padOn) once per burst of PadConnected() edges
--    UnwatchPad(owner)      stop following; the last one drops the events
--    PadGamepadUI()         WoW Forever's Gamepad interface style is on
--    RaiseGamePadCursor()   gamepad pointer on at a user-requested open
--    RegisterPadFrame(f)    a NAMED, hidden window root we own joins the
--                           controller cursor, once (never HUD frames)
--    PadHint(f, attr, v)    controller-cursor node attribute on OUR frame
--    PadCursorShown()       the controller cursor is on screen
--    PadFocus(node)         move the controller cursor onto node
--    OverlayParent()        parent for nameless screen-level overlays
--    TrackOverlay(f)        keep the overlay layer shown while f is
-------------------------------------------------------------------------------
do
    local IS_FOREVER = EllesmereUI.IS_FOREVER == true

    local function PadCP()
        local cp = _G.ConsolePort
        if type(cp) == "table" and cp.AddInterfaceCursorFrame then return cp end
    end

    -- The active-device query Blizzard documents beside GAME_PAD_ACTIVE_CHANGED;
    -- false while the mouse or keyboard was the last input.
    local function PadNative()
        return IsUsingGamepad() and C_GamePad.IsEnabled() or false
    end

    local function PadInUse()
        return PadCP() ~= nil or PadNative()
    end

    -- Connected, not in use: gamepad support is on (the GamePadEnable CVar)
    -- and a device reports a raw state, so touching the mouse never changes
    -- it. Read live; a feature that follows it registers through WatchPad
    -- below, never on the device events itself.
    local function PadConnected()
        if not C_GamePad.IsEnabled() then return false end
        for _, id in ipairs(C_GamePad.GetAllDeviceIDs()) do
            if C_GamePad.GetDeviceRawState(id) then return true end
        end
        return false
    end

    -- Forever's Gamepad interface style replaces the free pointer with D-pad
    -- navigation; read live (no event), false on retail.
    local function PadGamepadUI()
        if not IS_FOREVER then return false end
        local style, types = C_InputInterfaceStyle, Enum.InputDeviceInterfaceType
        return style ~= nil and types ~= nil and style.GetCurrentStyle() == types.Gamepad
    end

    EllesmereUI.PadCP        = PadCP
    EllesmereUI.PadNative    = PadNative
    EllesmereUI.PadInUse     = PadInUse
    EllesmereUI.PadConnected = PadConnected
    EllesmereUI.PadGamepadUI = PadGamepadUI

    -- Following PadConnected(): one shared watcher for every feature that hides
    -- or shows something with the controller. Its frame is built at the first
    -- WatchPad and holds GAME_PAD_CONNECTED / GAME_PAD_DISCONNECTED and the
    -- GamePadEnable CVAR_UPDATE only while at least one watcher exists. Edges
    -- come in bursts (a reconnect is DISCONNECTED then CONNECTED, a second pad
    -- adds its own, the CVar can land beside them), so a burst arms ONE flush
    -- next frame that reads PadConnected() once and calls every watcher's
    -- fn(padOn). WatchPad never calls fn itself: the caller reads
    -- PadConnected() when it starts watching. Watching again replaces fn.
    do
        local watchers, watchFrame, flushArmed, flushOwners

        local function FlushPad()
            flushArmed = nil
            if next(watchers) == nil then return end
            -- Snapshot first: a watcher may watch or unwatch while this runs.
            local n = 0
            for owner in pairs(watchers) do
                n = n + 1
                flushOwners[n] = owner
            end
            local on = PadConnected()
            -- One failing watcher must not stop the rest (or strand the
            -- snapshot slots): report it and carry on.
            for i = 1, n do
                local fn = watchers[flushOwners[i]]
                flushOwners[i] = nil
                if fn then
                    local ok, err = pcall(fn, on)
                    if not ok then geterrorhandler()(err) end
                end
            end
        end

        local function OnPadEdge(_, event, name)
            -- CVAR_UPDATE fires for every cvar, dozens of times at login.
            if event == "CVAR_UPDATE" and name ~= "GamePadEnable" then return end
            if flushArmed then return end
            flushArmed = true
            C_Timer.After(0, FlushPad)
        end

        function EllesmereUI.WatchPad(owner, fn)
            if owner == nil or not fn then return end
            if not watchFrame then
                watchers, flushOwners = {}, {}
                watchFrame = CreateFrame("Frame")
                watchFrame:SetScript("OnEvent", OnPadEdge)
            end
            if next(watchers) == nil then
                watchFrame:RegisterEvent("GAME_PAD_CONNECTED")
                watchFrame:RegisterEvent("GAME_PAD_DISCONNECTED")
                watchFrame:RegisterEvent("CVAR_UPDATE")
            end
            watchers[owner] = fn
        end

        function EllesmereUI.UnwatchPad(owner)
            if not watchers or owner == nil or watchers[owner] == nil then return end
            watchers[owner] = nil
            if next(watchers) == nil then watchFrame:UnregisterAllEvents() end
        end
    end

    -- Blizzard's own open-edge call (ShowUIPanel, the pause menu, single bags).
    -- Never turned off here: Back/Escape (CloseAllWindows) owns that edge. The
    -- controller UI addon drives the pointer itself, so it is left alone then.
    function EllesmereUI.RaiseGamePadCursor()
        if not CanAutoSetGamePadCursorControl(true) then return end
        if PadCP() or PadGamepadUI() then return end
        SetGamePadCursorControl(true)
    end

    -- Registration is remembered by name in the addon's saved data, so only
    -- stable global names; register once, while hidden, after the frame's last
    -- SetScript of OnShow/OnHide (the addon hooks those). Never remove one.
    local padRoots
    function EllesmereUI.RegisterPadFrame(f)
        local cp = PadCP()
        if not cp or not f or not f:GetName() then return end
        if not padRoots then padRoots = {} end
        if padRoots[f] then return end
        padRoots[f] = true
        cp:AddInterfaceCursorFrame(f)
    end

    -- nodeignore / nodepass / nodepriority / hidekeyboard ... (v nil = true)
    function EllesmereUI.PadHint(f, attr, v)
        if not f or not PadCP() then return end
        if f:IsProtected() and InCombatLockdown() then return end
        if v == nil then v = true end
        f:SetAttribute(attr, v)
    end

    function EllesmereUI.PadCursorShown()
        local cp = PadCP()
        return (cp and cp:IsCursorActive()) and true or false
    end

    -- Only while the cursor is already on screen; a no-op otherwise.
    function EllesmereUI.PadFocus(node)
        local cp = PadCP()
        if cp and node then cp:SetCursorNodeIfActive(node) end
    end

    -- Overlay layer: nameless screen-level overlays (dropdown lists, cog
    -- popups, click-away catchers) cannot join the controller cursor, so while
    -- the controller UI addon is loaded they hang off one named full-screen
    -- layer that is shown exactly while one of them is. Without it the parent
    -- is UIParent and nothing else happens. Show/Hide/SetShown are post-hooked
    -- on the overlay (not OnShow: a child of a hidden layer never fires it, and
    -- dropdowns SetScript their OnShow/OnHide later).
    local layer, overlayOpen, overlayTracked

    local function OverlaySync(f)
        if f:IsShown() and f:GetParent() == layer then
            overlayOpen[f] = true
        else
            overlayOpen[f] = nil
        end
        if next(overlayOpen) then
            if not layer:IsShown() then layer:Show() end
        elseif layer:IsShown() then
            layer:Hide()
        end
    end

    function EllesmereUI.OverlayParent()
        if layer then return layer end
        if not PadCP() then return UIParent end
        layer = CreateFrame("Frame", "EllesmereUI_PadOverlayLayer", UIParent)
        layer:SetAllPoints(UIParent)
        layer:Hide()
        overlayOpen, overlayTracked = {}, {}
        EllesmereUI._overlayLayer = layer
        EllesmereUI.RegisterPadFrame(layer)
        return layer
    end

    -- Every frame parented to OverlayParent() must be tracked (create it
    -- hidden, then call this after its scripts are set). No-op for any frame
    -- not parented to the layer.
    function EllesmereUI.TrackOverlay(f)
        if not layer or not f or overlayTracked[f] or f:GetParent() ~= layer then return end
        overlayTracked[f] = true
        hooksecurefunc(f, "Show", OverlaySync)
        hooksecurefunc(f, "Hide", OverlaySync)
        hooksecurefunc(f, "SetShown", OverlaySync)
        OverlaySync(f)
    end
end
