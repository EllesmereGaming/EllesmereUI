-------------------------------------------------------------------------------
--  EllesmereUI_VideoGuides.lua
--
--  Reusable VIDEO GUIDE popup engine: announcement-quality popups whose body
--  is a pre-selected read-only URL box (the only keystroke a user needs is
--  Ctrl+C) plus a single Okay button. Each guide brings its own unique top
--  art via an `art` callback drawing into the engine's header band.
--
--  API (EllesmereUI.VideoGuides):
--    Register(id, def) -- def = { title, blurb, url, footnote?, eyebrow?,
--                        accent?, height?, art = function(popup, ctx) }
--    Show(id)          -- show unconditionally (future section icons call this)
--    FireOnce(id)      -- first time ever: stamps seen + shows, returns true
--                        (callers use true to swallow the triggering click)
--    HasSeen(id)       -- reads the per-account seen map
--
--  Seen map: EllesmereUIDB.videoGuidesSeen[id] = true (per account, one flat
--  key for all guides forever). The shell (dimmer/popup/chrome) is built once
--  and reused; per-guide art containers are built once and swapped. Zero cost
--  at load: nothing is created until the first Show.
--
--  Guide #1 (settings_overrides) registers at the bottom of this file and is
--  fired by the spec-override toolbar glyph's first-ever click.
-------------------------------------------------------------------------------

local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

-- Suite-only: guides describe suite surfaces. Trigger sites nil-guard on
-- EllesmereUI.VideoGuides so standalone builds degrade to normal clicks.
local EUI_HOST_ADDON = ...
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
if IS_STANDALONE then return end

local PP = EllesmereUI.PanelPP
local MakeBorder = EllesmereUI.MakeBorder

-- The override system's gold (used by guide art, exposed via ctx).
local GOLD = { r = 1, g = 0.82, b = 0.30 }

local POPUP_W, POPUP_H = 470, 368
local ART_H = 88

local guides = {}      -- id -> def
local artFrames = {}   -- id -> built art container (band frame)

local function MarkSeen(id)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.videoGuidesSeen then EllesmereUIDB.videoGuidesSeen = {} end
    EllesmereUIDB.videoGuidesSeen[id] = true
end

local function HasSeen(id)
    return (EllesmereUIDB and EllesmereUIDB.videoGuidesSeen
        and EllesmereUIDB.videoGuidesSeen[id]) or false
end

-- Right-pointing solid triangle: collapse the right edge of a color texture
-- to its vertical midpoint. Vertex indices: 1=UpperLeft, 2=LowerLeft,
-- 3=UpperRight, 4=LowerRight. Positive y offset is up.
local function MakeTriangle(parent, w, h, r, g, b, a)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(r, g, b, a or 1)
    PP.Size(t, w, h)
    t:SetVertexOffset(3, 0, -h / 2)
    t:SetVertexOffset(4, 0, h / 2)
    return t
end

-- Square play badge: dark chip, colored border (matches whatever art it sits
-- beside), white triangle nudged right for optical centering.
local function MakePlayBadge(parent, size, color)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetFrameLevel(parent:GetFrameLevel() + 3)
    PP.Size(badge, size, size)
    local chip = badge:CreateTexture(nil, "BACKGROUND")
    chip:SetAllPoints()
    chip:SetColorTexture(0.05, 0.06, 0.08, 0.95)
    MakeBorder(badge, color.r, color.g, color.b, 0.85, PP)
    local tri = MakeTriangle(badge, math.floor(size * 0.36), math.floor(size * 0.42), 1, 1, 1, 0.95)
    PP.Point(tri, "CENTER", badge, "CENTER", size * 0.05, 0)
    return badge
end

-------------------------------------------------------------------------------
--  Tutorial tips: small one-time play badges attached beside UI entry points
--  (nav rows, section headers). Clicking one opens its video guide and
--  retires the badge FOREVER (per account). The "Enable Tutorial Tips"
--  toggle (Global Settings -> General) hides them all. Visual: a 16px play
--  chip in the suite accent with a slow, calm alpha breath -- present but
--  never in the way.
-------------------------------------------------------------------------------
local liveTips = {}   -- tipId -> tip frame (RefreshTips re-evaluates these)
local RefreshTips     -- forward declaration (AttachTip's click handler uses it)

local function TipsEnabled()
    return not (EllesmereUIDB and EllesmereUIDB.tutorialTipsDisabled)
end

local function TipSeen(id)
    return (EllesmereUIDB and EllesmereUIDB.tutorialTipsSeen
        and EllesmereUIDB.tutorialTipsSeen[id]) or false
end

local function MarkTipSeen(id)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.tutorialTipsSeen then EllesmereUIDB.tutorialTipsSeen = {} end
    EllesmereUIDB.tutorialTipsSeen[id] = true
end

-------------------------------------------------------------------------------
--  Shell: built once, reused for every guide. `ui` holds every retintable /
--  retextable piece; `cur` is the accent table the hover closures read (the
--  shell outlives any single guide, so closures must never capture r,g,b).
-------------------------------------------------------------------------------
local ui        -- nil until first Show
local cur = { r = 0, g = 0, b = 0 }
local FONT

local function Dismiss()
    if not ui then return end
    ui.eb:ClearFocus()
    ui.dimmer:Hide()
end

local function BuildShell()
    if ui then return end
    FONT = EllesmereUI._font or ("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf")
    ui = {}

    -- Dimmer: eats stray clicks/wheel; clicking anywhere outside the panel
    -- closes the guide (the popup itself is mouse-enabled, so clicks over it
    -- never reach this handler).
    local dimmer = CreateFrame("Frame", "EUIVideoGuideDimmer", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:SetScript("OnMouseDown", Dismiss)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.35)
    ui.dimmer = dimmer

    -- Panel
    local popup = CreateFrame("Frame", "EUIVideoGuidePopup", dimmer)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    PP.Size(popup, POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:EnableMouse(true)
    ui.popup = popup

    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.08, 0.10, 1)

    -- 1 physical-pixel white border (announcement chrome), scale-derived.
    local onePhys = 1 / (popup:GetEffectiveScale() or 1)
    local BRD_A = 0.15
    local function MakeEdge()
        local t = popup:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 1, 1, BRD_A)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        return t
    end
    local spT = MakeEdge(); spT:SetPoint("TOPLEFT", 0, 0); spT:SetPoint("TOPRIGHT", 0, 0); spT:SetHeight(onePhys)
    local spB = MakeEdge(); spB:SetPoint("BOTTOMLEFT", 0, 0); spB:SetPoint("BOTTOMRIGHT", 0, 0); spB:SetHeight(onePhys)
    local spL = MakeEdge(); spL:SetPoint("TOPLEFT", spT, "BOTTOMLEFT"); spL:SetPoint("BOTTOMLEFT", spB, "TOPLEFT"); spL:SetWidth(onePhys)
    local spR = MakeEdge(); spR:SetPoint("TOPRIGHT", spT, "BOTTOMRIGHT"); spR:SetPoint("BOTTOMRIGHT", spB, "TOPRIGHT"); spR:SetWidth(onePhys)

    -- Art band: full-bleed dark well flush to the top edge, accent rule
    -- underneath. Per-guide art containers are children created in SetGuide.
    local well = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
    well:SetColorTexture(0.045, 0.055, 0.07, 1)
    PP.Point(well, "TOPLEFT", popup, "TOPLEFT", 0, 0)
    PP.Point(well, "TOPRIGHT", popup, "TOPRIGHT", 0, 0)
    well:SetHeight(ART_H)
    local rule = popup:CreateTexture(nil, "BACKGROUND", nil, 2)
    PP.Point(rule, "TOPLEFT", popup, "TOPLEFT", 0, -ART_H)
    PP.Point(rule, "TOPRIGHT", popup, "TOPRIGHT", 0, -ART_H)
    rule:SetHeight(1)
    ui.rule = rule

    -- Eyebrow: play triangle + "VIDEO GUIDE"
    local eyebrow = popup:CreateFontString(nil, "OVERLAY")
    eyebrow:SetFont(FONT, 13, "")
    PP.Point(eyebrow, "TOP", popup, "TOP", 0, -(ART_H + 16))
    ui.eyebrow = eyebrow
    local tri = MakeTriangle(popup, 9, 10, 1, 1, 1, 0.9)
    PP.Point(tri, "RIGHT", eyebrow, "LEFT", -7, 0)
    ui.tri = tri

    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 25, "")
    title:SetTextColor(1, 1, 1, 1)
    PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
    ui.title = title

    -- Blurb
    local blurb = popup:CreateFontString(nil, "OVERLAY")
    blurb:SetFont(FONT, 14, "")
    blurb:SetTextColor(1, 1, 1, 0.55)
    blurb:SetWidth(POPUP_W - 80)
    blurb:SetJustifyH("CENTER")
    blurb:SetWordWrap(true)
    PP.Point(blurb, "TOP", title, "BOTTOM", 0, -12)
    ui.blurb = blurb

    -- URL well + read-only EditBox (always-selected; Ctrl+C is the point)
    local urlWell = CreateFrame("Frame", nil, popup)
    urlWell:SetFrameLevel(popup:GetFrameLevel() + 2)
    PP.Size(urlWell, 350, 34)
    PP.Point(urlWell, "TOP", blurb, "BOTTOM", 0, -18)
    local wbg = urlWell:CreateTexture(nil, "BACKGROUND")
    wbg:SetAllPoints()
    wbg:SetColorTexture(0.03, 0.045, 0.06, 1)
    -- Neutral border (never accent-tinted): the link-blue text carries the
    -- "this is the link" read on its own.
    MakeBorder(urlWell, 1, 1, 1, 0.22, PP)

    -- Hint under the well (also doubles as the Ctrl+C confirmation line)
    local hint = popup:CreateFontString(nil, "OVERLAY")
    hint:SetFont(FONT, 11, "")
    hint:SetTextColor(1, 1, 1, 0.45)
    PP.Point(hint, "TOP", urlWell, "BOTTOM", 0, -8)
    ui.hint = hint

    local eb = CreateFrame("EditBox", nil, urlWell)
    eb:SetAllPoints(urlWell)
    eb:SetMultiLine(false)
    eb:SetAutoFocus(false)
    eb:SetFont(FONT, 13, "")
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(12, 12, 0, 0)
    eb:SetTextColor(0.55, 0.75, 1.0, 1)   -- link blue
    eb:SetScript("OnMouseUp", function(self)
        C_Timer.After(0, function() self:SetFocus(); self:HighlightText() end)
    end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- Read-only: typing/paste/cut restore the URL and re-select.
    eb:SetScript("OnChar", function(self)
        self:SetText(self._readOnly or ""); self:HighlightText()
    end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(self._readOnly or ""); self:HighlightText() end
    end)
    eb:SetScript("OnEscapePressed", function(self) Dismiss() end)
    eb:SetScript("OnEnterPressed", function(self) Dismiss() end)
    eb:SetScript("OnKeyDown", function(self, key)
        if key == "C" and IsControlKeyDown() then
            hint:SetText("Link copied - paste it into your browser")
            hint:SetTextColor(cur.r, cur.g, cur.b, 0.9)
        end
    end)
    ui.eb = eb

    -- Single centered Okay button (accent primary)
    local okBtn = CreateFrame("Button", nil, popup)
    okBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    PP.Size(okBtn, 160, 36)
    PP.Point(okBtn, "BOTTOM", popup, "BOTTOM", 0, 42)
    local okBg = okBtn:CreateTexture(nil, "BACKGROUND")
    okBg:SetAllPoints()
    okBg:SetColorTexture(0.06, 0.08, 0.10, 0.92)
    ui.okBrd = MakeBorder(okBtn, 1, 1, 1, 0.9, PP)
    local okLbl = okBtn:CreateFontString(nil, "OVERLAY")
    okLbl:SetFont(FONT, 15, "")
    PP.Point(okLbl, "CENTER", okBtn, "CENTER", 0, 0)
    okLbl:SetText("Okay")
    ui.okLbl = okLbl
    okBtn:SetScript("OnEnter", function()
        okLbl:SetTextColor(cur.r, cur.g, cur.b, 1)
        ui.okBrd:SetColor(cur.r, cur.g, cur.b, 1)
    end)
    okBtn:SetScript("OnLeave", function()
        okLbl:SetTextColor(cur.r, cur.g, cur.b, 0.9)
        ui.okBrd:SetColor(cur.r, cur.g, cur.b, 0.9)
    end)
    okBtn:SetScript("OnClick", function() Dismiss() end)

    -- Footnote
    local footnote = popup:CreateFontString(nil, "OVERLAY")
    footnote:SetFont(FONT, 12, "")
    footnote:SetTextColor(1, 1, 1, 0.35)
    footnote:SetWidth(POPUP_W - 80)
    footnote:SetJustifyH("CENTER")
    PP.Point(footnote, "BOTTOM", popup, "BOTTOM", 0, 16)
    ui.footnote = footnote

    -- Escape closes (the EditBox path handles it while focused; this path
    -- covers an unfocused box). Propagate everything else.
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then Dismiss() end
    end)
end

--- Populates the shared shell for one guide: texts, accent retints, art swap.
local function SetGuide(id, def)
    local accent = def.accent or EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.83, b = 0.62 }
    cur.r, cur.g, cur.b = accent.r, accent.g, accent.b

    PP.Size(ui.popup, POPUP_W, def.height or POPUP_H)
    ui.eyebrow:SetText(def.eyebrow or "VIDEO GUIDE")
    ui.eyebrow:SetTextColor(accent.r, accent.g, accent.b, 0.9)
    ui.tri:SetColorTexture(accent.r, accent.g, accent.b, 0.9)
    ui.rule:SetColorTexture(accent.r, accent.g, accent.b, 0.35)
    ui.title:SetText(def.title or "")
    ui.blurb:SetText(def.blurb or "")
    ui.hint:SetText("Ctrl+C to copy, Escape to close")
    ui.hint:SetTextColor(1, 1, 1, 0.45)
    ui.okLbl:SetTextColor(accent.r, accent.g, accent.b, 0.9)
    ui.okBrd:SetColor(accent.r, accent.g, accent.b, 0.9)
    ui.footnote:SetText(def.footnote or "")

    ui.eb._readOnly = def.url or ""
    ui.eb:SetText(def.url or "")
    ui.eb:SetCursorPosition(0)

    -- Art swap: hide every built band, then build-once-and-show this one.
    for _, band in pairs(artFrames) do band:Hide() end
    if def.art then
        local band = artFrames[id]
        if not band then
            band = CreateFrame("Frame", nil, ui.popup)
            band:SetFrameLevel(ui.popup:GetFrameLevel() + 1)
            -- 2-unit inset keeps child-frame art off the popup's 1px border.
            PP.Point(band, "TOPLEFT", ui.popup, "TOPLEFT", 2, -2)
            PP.Point(band, "TOPRIGHT", ui.popup, "TOPRIGHT", -2, -2)
            band:SetHeight(ART_H - 2)
            artFrames[id] = band
            local ctx = {
                band = band,
                W = POPUP_W - 4,
                H = ART_H - 2,
                PP = PP,
                MakeBorder = MakeBorder,
                FONT = FONT,
                accent = { r = accent.r, g = accent.g, b = accent.b },
                GOLD = GOLD,
                MakeTriangle = MakeTriangle,
                MakePlayBadge = function(parent, size, color)
                    return MakePlayBadge(parent, size, color or accent)
                end,
            }
            -- Art failures must never break the popup: plain well on error.
            local ok = pcall(def.art, ui.popup, ctx)
            if not ok then band:Hide() end
        end
        band:Show()
    end
end

local function Show(id)
    local def = guides[id]
    if not def then return false end
    -- The trigger's widget tooltip is still on screen at click time.
    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    BuildShell()
    local ppScale = (EllesmereUI.GetPopupScale and EllesmereUI.GetPopupScale()) or 1
    ui.dimmer:SetScale(ppScale)
    ui.popup:SetScale(ppScale * 1.15)
    SetGuide(id, def)
    ui.dimmer:Show()
    -- Pre-select the URL so the only keystroke needed is Ctrl+C.
    local eb = ui.eb
    C_Timer.After(0, function() eb:SetFocus(); eb:HighlightText() end)
    return true
end

--- Attaches a one-time tutorial tip badge to a region. tipId doubles as the
--- guide id shown on click (override via opts.guide). opts: point/relPoint/
--- x/y (default: inside the region's right edge), size (16), tooltip.
--- Shift + right click on any badge disables them all (writes the same key
--- as the Global Settings "Enable Tutorial Tips" toggle, which re-enables).
--- Idempotent per tipId; never builds a retired tip. Returns the tip frame.
local function AttachTip(region, tipId, opts)
    if not region or not tipId then return nil end
    local existing = liveTips[tipId]
    if existing then
        existing:SetShown(TipsEnabled() and not TipSeen(tipId))
        return existing
    end
    if TipSeen(tipId) then return nil end
    opts = opts or {}
    local size = opts.size or 16

    local tip = CreateFrame("Button", nil, region)
    tip:SetFrameLevel(region:GetFrameLevel() + 5)
    PP.Size(tip, size, size)
    PP.Point(tip, opts.point or "RIGHT", region, opts.relPoint or "RIGHT",
        opts.x or -10, opts.y or 0)
    -- Bare accent-tinted play icon -- no chip background, no border. The
    -- button itself stays full-size as the click/hover target. RegAccent
    -- keeps the tint live when the accent color changes (dedupes by obj).
    local icon = tip:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\play.png")
    local EG = EllesmereUI.ELLESMERE_GREEN
    if EG then
        icon:SetVertexColor(EG.r, EG.g, EG.b, 1)
        if EllesmereUI.RegAccent then
            EllesmereUI.RegAccent({ type = "vertex", obj = icon })
        end
    else
        icon:SetVertexColor(1, 1, 1, 0.9)
    end

    -- Deliberately STATIC (no pulse): the badge stays on the UI until
    -- clicked or disabled, so it must read as a quiet help affordance the
    -- user consults on their own time -- never as a notification begging
    -- for a click. Slightly dimmed idle, full brightness on hover.
    tip:SetAlpha(0.8)

    local tipText = opts.tooltip or "Video Guide"
    tip:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if EllesmereUI.ShowWidgetTooltip then
            local t = (EllesmereUI.L and EllesmereUI.L(tipText)) or tipText
            local hint = (EllesmereUI.L and EllesmereUI.L("Shift + right click to hide video guide icons"))
                or "Shift + right click to hide video guide icons"
            EllesmereUI.ShowWidgetTooltip(self, t .. "\n|cff909090" .. hint .. "|r")
        end
    end)
    tip:SetScript("OnLeave", function(self)
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        self:SetAlpha(0.8)
    end)
    tip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tip:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            -- Shift + right click: hide ALL video guide icons. Identical to
            -- turning off Enable Tutorial Tips in Global Settings (same key,
            -- same true-vs-nil convention), so that toggle reads OFF and can
            -- turn them back on.
            if not IsShiftKeyDown() then return end
            if not EllesmereUIDB then EllesmereUIDB = {} end
            EllesmereUIDB.tutorialTipsDisabled = true
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            RefreshTips()
            -- Re-run the active page's widget refreshers so the Global
            -- Settings toggle flips live if it is on screen right now.
            if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
            return
        end
        -- One shot: retire forever, then open the guide.
        MarkTipSeen(tipId)
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        self:Hide()
        Show(opts.guide or tipId)
    end)

    tip:SetShown(TipsEnabled())
    liveTips[tipId] = tip
    return tip
end

--- Re-evaluates every attached tip (the Enable Tutorial Tips toggle calls
--- this so flipping the setting takes effect live). Assigns the forward
--- declaration above AttachTip, whose click handler also calls it.
RefreshTips = function()
    for id, tip in pairs(liveTips) do
        tip:SetShown(TipsEnabled() and not TipSeen(id))
    end
end

EllesmereUI.VideoGuides = {
    Register = function(id, def) guides[id] = def end,
    Show = Show,
    HasSeen = HasSeen,
    -- Stamps BEFORE showing: a crash/reload mid-popup can never re-fire a
    -- once-ever guide (it stays reachable via Show).
    FireOnce = function(id)
        if HasSeen(id) then return false end
        if not guides[id] then return false end
        MarkSeen(id)
        return Show(id)
    end,
    AttachTip = AttachTip,
    RefreshTips = RefreshTips,
    TipsEnabled = TipsEnabled,
}

-- Reset command: clears the seen state for every video guide popup and every
-- tutorial tip badge, so all of them show again as if never clicked. Live
-- badges on the current UI reappear immediately.
SLASH_EUIVIDEOS1 = "/euivideos"
SlashCmdList["EUIVIDEOS"] = function()
    if EllesmereUIDB then
        EllesmereUIDB.videoGuidesSeen = nil
        EllesmereUIDB.tutorialTipsSeen = nil
    end
    RefreshTips()
    print("|cff00ff98EllesmereUI:|r Video guides and tutorial tips reset. Badges are back; one-time popups will fire again.")
end

-------------------------------------------------------------------------------
--  Guide #1: Settings Overrides
--  Fired by the spec-override toolbar glyph's first-ever click (see the
--  OnClick in EllesmereUI_SpecOverrides.lua / SpecOverrides_SetupButton).
-------------------------------------------------------------------------------
do
    local MODERN_SPRITE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\modern.tga"
    local ART_COORDS = {
        { 0, 0.125, 0, 0.125 },         -- WARRIOR
        { 0, 0.125, 0.25, 0.375 },      -- PALADIN
        { 0.125, 0.25, 0.25, 0.375 },   -- DEATHKNIGHT
    }

    EllesmereUI.VideoGuides.Register("settings_overrides", {
        title = "Settings Overrides",
        blurb = "Settings Overrides are the most powerful system in EllesmereUI, and the deepest. A few minutes with this video will save you hours of working it out on your own.",
        url = "https://youtu.be/8VKV26lrGSc",
        art = function(popup, ctx)
            local PPx, band = ctx.PP, ctx.band
            -- Ghost card behind (the layered-overrides read).
            local ghost = CreateFrame("Frame", nil, band)
            ghost:SetFrameLevel(band:GetFrameLevel() + 1)
            PPx.Size(ghost, 150, 52)
            PPx.Point(ghost, "CENTER", band, "CENTER", -39, -6)
            local gbg = ghost:CreateTexture(nil, "BACKGROUND")
            gbg:SetAllPoints()
            gbg:SetColorTexture(0.10, 0.11, 0.13, 1)
            ctx.MakeBorder(ghost, 1, 1, 1, 0.08, PPx)

            -- Gold override-group card (tank class glyphs + gold name line).
            local card = CreateFrame("Frame", nil, band)
            card:SetFrameLevel(band:GetFrameLevel() + 2)
            PPx.Size(card, 150, 52)
            PPx.Point(card, "CENTER", band, "CENTER", -31, 2)
            local cbg = card:CreateTexture(nil, "BACKGROUND")
            cbg:SetAllPoints()
            cbg:SetColorTexture(0.12, 0.13, 0.15, 1)
            ctx.MakeBorder(card, ctx.GOLD.r, ctx.GOLD.g, ctx.GOLD.b, 0.85, PPx)

            local ICON, GAP = 20, 8
            local rowW = #ART_COORDS * ICON + (#ART_COORDS - 1) * GAP
            for k, c in ipairs(ART_COORDS) do
                local tex = card:CreateTexture(nil, "ARTWORK")
                PPx.Size(tex, ICON, ICON)
                PPx.Point(tex, "LEFT", card, "LEFT",
                    (150 - rowW) / 2 + (k - 1) * (ICON + GAP), 5)
                tex:SetTexture(MODERN_SPRITE)
                tex:SetTexCoord(c[1], c[2], c[3], c[4])
            end
            local line = card:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(ctx.GOLD.r, ctx.GOLD.g, ctx.GOLD.b, 0.75)
            PPx.Size(line, 56, 3)
            PPx.Point(line, "BOTTOM", card, "BOTTOM", 0, 6)

            -- Play badge standing beside the card with a clear gap, border
            -- matching the card's gold: "watch the video about this system".
            local badge = ctx.MakePlayBadge(band, 44, ctx.GOLD)
            PPx.Point(badge, "LEFT", card, "RIGHT", 18, 0)
        end,
    })
end

-------------------------------------------------------------------------------
--  Guide #2: Unlock Mode
--  Entry point: the tutorial tip badge on the Unlock Mode nav row (attached
--  in EllesmereUI.lua where the sidebar builds).
-------------------------------------------------------------------------------
do
    EllesmereUI.VideoGuides.Register("unlock_mode", {
        title = "Unlock Mode",
        blurb = "Unlock Mode is how you move and resize everything in EllesmereUI, and it is packed with tools: anchors, width matching, fallback anchors, per-group layouts. This video gets you fluent fast.",
        url = "https://youtu.be/h0zndXt-d_4",
        art = function(popup, ctx)
            local PPx, band = ctx.PP, ctx.band
            local EG = ctx.accent
            -- Two mover boxes (the unlock-mode read): a small one anchored to
            -- a large one, joined by an accent anchor line with an endpoint
            -- dot -- movers + anchors in one glance.
            local big = CreateFrame("Frame", nil, band)
            big:SetFrameLevel(band:GetFrameLevel() + 2)
            PPx.Size(big, 120, 46)
            PPx.Point(big, "CENTER", band, "CENTER", -58, 0)
            local bbg = big:CreateTexture(nil, "BACKGROUND")
            bbg:SetAllPoints()
            bbg:SetColorTexture(EG.r, EG.g, EG.b, 0.10)
            ctx.MakeBorder(big, EG.r, EG.g, EG.b, 0.7, PPx)
            -- Drag grip dots in the big mover's center.
            for k = 1, 3 do
                local dot = big:CreateTexture(nil, "ARTWORK")
                dot:SetColorTexture(1, 1, 1, 0.5)
                PPx.Size(dot, 3, 3)
                PPx.Point(dot, "CENTER", big, "CENTER", (k - 2) * 8, 0)
            end

            local small = CreateFrame("Frame", nil, band)
            small:SetFrameLevel(band:GetFrameLevel() + 2)
            PPx.Size(small, 56, 30)
            PPx.Point(small, "LEFT", big, "RIGHT", 26, 0)
            local sbg = small:CreateTexture(nil, "BACKGROUND")
            sbg:SetAllPoints()
            sbg:SetColorTexture(1, 1, 1, 0.05)
            ctx.MakeBorder(small, 1, 1, 1, 0.30, PPx)

            -- Anchor line joining them, with an endpoint dot on the small box.
            local line = band:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(EG.r, EG.g, EG.b, 0.8)
            PPx.Size(line, 26, 2)
            PPx.Point(line, "LEFT", big, "RIGHT", 0, 0)
            local anchorDot = band:CreateTexture(nil, "OVERLAY")
            anchorDot:SetColorTexture(EG.r, EG.g, EG.b, 1)
            PPx.Size(anchorDot, 6, 6)
            PPx.Point(anchorDot, "CENTER", small, "LEFT", 0, 0)

            -- Play badge beside the cluster.
            local badge = ctx.MakePlayBadge(band, 44)
            PPx.Point(badge, "LEFT", small, "RIGHT", 18, 0)
        end,
    })
end

-------------------------------------------------------------------------------
--  Guide #3: Cooldown Manager
--  Entry point: the tutorial tip badge in the sidebar, in the indent gutter
--  left of the "Cooldown Manager" label (attached in EllesmereUI.lua's
--  CreateAddonChildRow).
-------------------------------------------------------------------------------
do
    EllesmereUI.VideoGuides.Register("cooldown_manager", {
        title = "Cooldown Manager",
        blurb = "The Cooldown Manager can do far more than show cooldowns, it also has per-spell settings, bar glows, tracking bars and more! Check out some tips and tricks for getting more from it.",
        url = "https://youtu.be/AUNHEMzHw74",
        art = function(popup, ctx)
            local PPx, band = ctx.PP, ctx.band
            local EG = ctx.accent

            -- Three cooldown icon chips (the CDM read): the middle one lit
            -- with an accent border (the ready glow), the first keeping a
            -- dark lower half as a cooldown sweep still running.
            -- Cluster centering: the chips/bars block is BAR_W wide with the
            -- 44px play badge hanging 18px off its right edge, so seating the
            -- block's center at -(44+18)/2 centers block + badge as ONE unit.
            local ICON, GAP = 26, 7
            local BADGE, BADGE_GAP = 44, 18
            local baseX = -(BADGE + BADGE_GAP) / 2
            local chips = {}
            for k = 1, 3 do
                local chip = CreateFrame("Frame", nil, band)
                chip:SetFrameLevel(band:GetFrameLevel() + 2)
                PPx.Size(chip, ICON, ICON)
                PPx.Point(chip, "CENTER", band, "CENTER", baseX + (k - 2) * (ICON + GAP), 14)
                local cbg = chip:CreateTexture(nil, "BACKGROUND")
                cbg:SetAllPoints()
                if k == 2 then
                    cbg:SetColorTexture(EG.r * 0.22, EG.g * 0.22, EG.b * 0.22, 1)
                    ctx.MakeBorder(chip, EG.r, EG.g, EG.b, 0.9, PPx)
                else
                    cbg:SetColorTexture(0.10, 0.11, 0.13, 1)
                    ctx.MakeBorder(chip, 1, 1, 1, 0.15, PPx)
                end
                chips[k] = chip
            end
            local sweep = chips[1]:CreateTexture(nil, "ARTWORK")
            sweep:SetColorTexture(0, 0, 0, 0.6)
            PPx.Point(sweep, "BOTTOMLEFT", chips[1], "BOTTOMLEFT", 1, 1)
            PPx.Point(sweep, "BOTTOMRIGHT", chips[1], "BOTTOMRIGHT", -1, 1)
            sweep:SetHeight(11)

            -- Two tracking bars under the chips at different progress:
            -- accent fill + white spark each.
            local BAR_W = ICON * 3 + GAP * 2
            local function MakeBar(anchorTo, gapY, fillW)
                local bar = CreateFrame("Frame", nil, band)
                bar:SetFrameLevel(band:GetFrameLevel() + 2)
                PPx.Size(bar, BAR_W, 8)
                PPx.Point(bar, "TOP", anchorTo, "BOTTOM", 0, gapY)
                local wbg = bar:CreateTexture(nil, "BACKGROUND")
                wbg:SetAllPoints()
                wbg:SetColorTexture(0.10, 0.11, 0.13, 1)
                ctx.MakeBorder(bar, 1, 1, 1, 0.15, PPx)
                local fill = bar:CreateTexture(nil, "ARTWORK")
                fill:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
                PPx.Size(fill, fillW, 6)
                PPx.Point(fill, "LEFT", bar, "LEFT", 1, 0)
                local spark = bar:CreateTexture(nil, "OVERLAY")
                spark:SetColorTexture(1, 1, 1, 0.9)
                PPx.Size(spark, 2, 12)
                PPx.Point(spark, "CENTER", fill, "RIGHT", 0, 0)
                return bar
            end
            local bar1 = MakeBar(chips[2], -7, 57)
            MakeBar(bar1, -5, 30)

            -- Play badge beside the cluster, centered on the cluster's
            -- vertical middle (chips sit at +14; chips + two bars span
            -- symmetrically around 0).
            local badge = ctx.MakePlayBadge(band, BADGE)
            PPx.Point(badge, "LEFT", chips[3], "RIGHT", BADGE_GAP, -14)
        end,
    })
end
