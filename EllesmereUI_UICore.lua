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
local lerp       = EllesmereUI.lerp
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

--- Active theme name (default "EllesmereUI")
EllesmereUI.GetActiveTheme = function()
    return EllesmereUIDB and EllesmereUIDB.activeTheme or "EllesmereUI"
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
        ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = accentFadeTo.r, accentFadeTo.g, accentFadeTo.b
        UpdateAccentElements(accentFadeTo.r, accentFadeTo.g, accentFadeTo.b)
        -- Fast-path refresh only: widget callbacks re-read the accent. NEVER force-rebuild (RefreshPage(true)) here -- a full teardown+rebuild in one frame hitches the renderer into a visible blink, and UpdateAccentElements already snapped every one-time element.
        for i = 1, #EllesmereUI._widgetRefreshList do EllesmereUI._widgetRefreshList[i]() end
        -- Deferred full GC, 2 frames out: collecting in the same frame as the transition completion hitches the renderer into a visible blink; by frame +2 the GC is the only work in the tick.
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
    local t = accentFadeProgress  -- smooth ease-in-out
    t = t < 0.5 and (2 * t * t) or (1 - (-2 * t + 2) * (-2 * t + 2) / 2)
    local r = lerp(accentFadeFrom.r, accentFadeTo.r, t)
    local g = lerp(accentFadeFrom.g, accentFadeTo.g, t)
    local b = lerp(accentFadeFrom.b, accentFadeTo.b, t)
    ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = r, g, b
    -- RegAccent elements (sidebar, tabs, footer) are cheap: every frame.
    UpdateAccentElements(r, g, b)
    -- Widget refreshes (toggles, sliders, checkboxes) are heavier: throttled.
    accentRefreshAccum = accentRefreshAccum + elapsed
    if accentRefreshAccum >= ACCENT_REFRESH_INTERVAL then
        accentRefreshAccum = 0
        for i = 1, #EllesmereUI._widgetRefreshList do EllesmereUI._widgetRefreshList[i]() end
    end
end)

--- Internal: apply accent with animated transition (for theme switches)
local function ApplyAccentAnimated(r, g, b)
    accentFadeFrom.r, accentFadeFrom.g, accentFadeFrom.b = ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b
    accentFadeTo.r, accentFadeTo.g, accentFadeTo.b = r, g, b
    accentFadeProgress = 0
    accentRefreshAccum = 0

    -- Invalidate cached popups so they rebuild with the new accent
    EllesmereUI._InvalidateConfirmPopup()

    -- OnUpdate lerps ELLESMERE_GREEN and refreshes widgets each tick
    accentFadeTicker:Show()
end

--- Internal: apply accent instantly (for color picker dragging, resets, etc.)
local function ApplyAccentLive(r, g, b)
    accentFadeTicker:Hide()  -- stop any running transition
    accentFadeProgress = 1

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
--  ShowContextMenu(anchor, items)
--  Shared pooled context menu used by Blizz UI Enhanced (character sheet gear-set cog, etc.). Pops up at the cursor.
--  items = { { text = "Foo", onClick = fn, isDisabled = fn? }, ... }
--  Behavior: click-outside-to-dismiss (polled ~10hz); auto-closes on combat entry so insecure clicks can't taint protected paths while lockdown is active.
-------------------------------------------------------------------------------
local _ctxMenu
local function ShowContextMenu(anchor, items)
    local PP_L = EllesmereUI.PP
    if not _ctxMenu then
        _ctxMenu = CreateFrame("Frame", nil, UIParent)
        _ctxMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        _ctxMenu:SetFrameLevel(200)
        _ctxMenu:SetClampedToScreen(true)
        _ctxMenu:EnableMouse(true)

        local RS = EllesmereUI.RESKIN or {}
        local bg = _ctxMenu:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(RS.BG_R or 0.067, RS.BG_G or 0.067, RS.BG_B or 0.067, RS.QT_ALPHA or 0.97)
        _ctxMenu._bg = bg

        if PP_L and PP_L.CreateBorder then
            PP_L.CreateBorder(_ctxMenu, 1, 1, 1, RS.BRD_ALPHA or 0.18, 1)
        end

        _ctxMenu._items = {}
        _ctxMenu._elapsed = 0

        -- Throttled click-outside poll (~10hz)
        _ctxMenu._pollClickOff = function(self, dt)
            self._elapsed = self._elapsed + dt
            if self._elapsed < 0.1 then return end
            self._elapsed = 0
            if not self:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                self:Hide()
            end
        end

        _ctxMenu:HookScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        -- Combat entry closes the menu to avoid tainting protected paths.
        _ctxMenu:RegisterEvent("PLAYER_REGEN_DISABLED")
        _ctxMenu:SetScript("OnEvent", function(self) self:Hide() end)
    end

    -- Hide pooled rows past the current item count
    for _, btn in ipairs(_ctxMenu._items) do btn:Hide() end

    local ITEM_H = 26
    local MENU_PAD = 4
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local outline  = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""

    if not _ctxMenu._measureFS then
        _ctxMenu._measureFS = _ctxMenu:CreateFontString(nil, "OVERLAY")
    end
    local mfs = _ctxMenu._measureFS
    mfs:SetFont(fontPath, 12, outline)
    local maxTextW = 0
    for _, item in ipairs(items) do
        mfs:SetText(EllesmereUI.L(item.text or ""))
        local w = mfs:GetStringWidth() or 0
        if w > maxTextW then maxTextW = w end
    end
    mfs:SetText("")
    mfs:Hide()

    local MENU_W = math.max(140, maxTextW + 40)
    local EG = EllesmereUI.ELLESMERE_GREEN
    local hlAlpha = EllesmereUI.DD_ITEM_HL_A or 0.08

    for i, item in ipairs(items) do
        local btn = _ctxMenu._items[i]
        if not btn then
            btn = CreateFrame("Button", nil, _ctxMenu)
            local hl = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
            hl:SetAllPoints()
            btn._hl = hl
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetPoint("LEFT", btn, "LEFT", 10, 0)
            lbl:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
            lbl:SetJustifyH("LEFT")
            btn._lbl = lbl
            _ctxMenu._items[i] = btn
        end
        btn:SetSize(MENU_W - MENU_PAD * 2, ITEM_H)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", _ctxMenu, "TOPLEFT", MENU_PAD, -(MENU_PAD + (i - 1) * ITEM_H))
        btn._hl:SetColorTexture(1, 1, 1, 0)
        btn._lbl:SetFont(fontPath, 12, outline)
        btn._lbl:SetText(EllesmereUI.L(item.text or ""))

        local disabled = item.isDisabled and item.isDisabled()
        if disabled then
            btn._lbl:SetTextColor(0.4, 0.4, 0.4, 0.5)
            btn._onClick = nil
            btn:SetScript("OnClick", nil)
            btn:SetScript("OnEnter", function() btn._lbl:SetTextColor(0.4, 0.4, 0.4, 0.5) end)
            btn:SetScript("OnLeave", function() btn._lbl:SetTextColor(0.4, 0.4, 0.4, 0.5) end)
        else
            btn._lbl:SetTextColor(1, 1, 1, 1)
            btn._onClick = item.onClick
            btn:SetScript("OnClick", function()
                _ctxMenu:Hide()
                if btn._onClick then btn._onClick() end
            end)
            btn:SetScript("OnEnter", function()
                btn._hl:SetColorTexture(1, 1, 1, hlAlpha)
                if EG then
                    btn._lbl:SetTextColor(EG.r, EG.g, EG.b, 1)
                else
                    btn._lbl:SetTextColor(1, 1, 1, 1)
                end
            end)
            btn:SetScript("OnLeave", function()
                btn._hl:SetColorTexture(1, 1, 1, 0)
                btn._lbl:SetTextColor(1, 1, 1, 1)
            end)
        end
        btn:Show()
    end

    _ctxMenu:SetSize(MENU_W, MENU_PAD * 2 + #items * ITEM_H)

    -- Position at cursor
    local scale = _ctxMenu:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    _ctxMenu:ClearAllPoints()
    _ctxMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    _ctxMenu:Show()

    _ctxMenu._elapsed = 0
    _ctxMenu:SetScript("OnUpdate", _ctxMenu._pollClickOff)
end

EllesmereUI.ShowContextMenu = ShowContextMenu
