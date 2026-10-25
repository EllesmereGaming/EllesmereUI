if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Popups.lua
--  Popup scale helper, announcement shell and buttons, reload helpers, and
--  the confirm / info / input popups. Loads right after EllesmereUI.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI

local PanelPP         = EllesmereUI.PanelPP
local MakeFont        = EllesmereUI.MakeFont
local MakeBorder      = EllesmereUI.MakeBorder
local SolidTex        = EllesmereUI.SolidTex
local lerp            = EllesmereUI.lerp
local ELLESMERE_GREEN = EllesmereUI.ELLESMERE_GREEN
local BORDER_COLOR    = EllesmereUI.BORDER_COLOR
local TEXT_DIM        = EllesmereUI.TEXT_DIM

-------------------------------------------------------------------------------
--  Popup Scale Helper -- pixel-perfect base scale * user panel scale, so popups grow/shrink with the main panel when the scale slider moves.
-------------------------------------------------------------------------------
local _popupFrames = {}   -- { popup, dimmer } pairs to update on scale change
EllesmereUI._popupFrames = _popupFrames

local function GetPopupScale()
    local physW = (GetPhysicalScreenSize())
    local baseScale = GetScreenWidth() / physW
    local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
    return baseScale * userScale
end
EllesmereUI.GetPopupScale = GetPopupScale

-- Reference density for dialog popups: 1440p at 0.64 UI scale (the suite's design reference),
-- where popups render at 768/(1440*0.64) = 0.8333 physical px/unit. Applied as a CONSTANT it
-- pins that size on every display, fixing both defects of the old squared scale: size no longer
-- moves INVERSELY with UI scale, nor grows QUADRATICALLY with the Window Scale slider; px/unit
-- is 0.8333 * panelScale. THE INVARIANT: every popup occupies the same screen fraction it does
-- at 1440p/0.64 -- screen-height fraction = (units * POPUP_REF_DENSITY * panelScale) / physH,
-- which holds exactly when panelScale == physH/1440 (what the Startup seed and the
-- panel_scale_highdpi_reset_v3 migration set it to). Do NOT "fix" this constant to 1.0: that
-- normalizes every display to 1 px/unit, 20% larger than the reference. Deliberate deviation:
-- the seed is FLOORED at 1, so below 1440p the fraction runs larger than reference (1080p by
-- 33%); enforcing it there would seed 0.75 and shrink the options panel a quarter for the
-- largest resolution segment (accepted trade). On the namespace, not a file local: 200-local cap.
EllesmereUI.POPUP_REF_DENSITY = 768 / (1440 * 0.64)

-- Scale a dialog sets on ITSELF, atop the dimmer that already carries GetPopupScale(). mult =
-- the dialog's own relative bump (1, or 1.15 for intro popups); ALWAYS route through this so the reference density lives in exactly one place.
function EllesmereUI.PopupBump(mult)
    return (mult or 1) * EllesmereUI.POPUP_REF_DENSITY
end

-- Dialog popups sit on a dimmer GetPopupScale has ALREADY scaled, so a dialog that also
-- SetScale(ppScale)s itself renders at ppScale SQUARED (baseScale = 768/(physH*uiScale) means
-- panelScale^2 * baseScale px/unit): oversizing popups everywhere, and (uiScale in the
-- denominator) BIGGER as UI scale drops. Dialogs take their scale ONCE from the dimmer and set
-- only their own relative bump, so px/unit == panelScale, exactly matching the options panel.
-- Units are easy to get wrong: GetEffectiveScale() is NOT physical px/unit. WoW maps the UI
-- through a 768-tall virtual space, so px/unit = GetEffectiveScale() * physH/768; baseScale is
-- then exactly 1 at the pixel-perfect uiScale (768/physH) on every resolution, which collapses
-- the corrected formula to panelScale.
-- _popupFrames entries come in TWO shapes, and the shape decides where the scale belongs (see
-- RefreshPopupScales): { popup = p } -- unscaled parent, popup carries the scale; { popup = p,
-- dimmer = d } -- scaled dimmer, popup carries only its bump. The raid-frame manager popups and
-- the nameplate filter panel are the former and were never doubled, why GetPopupScale itself is unchanged.

-- Hard ceiling for modal setup popups: they sit on a full-screen dimmer that eats every click
-- behind it, so one overflowing the display puts its buttons off-screen with no way back to the
-- game menu. Measured, not derived: GetEffectiveScale reports what the frame really renders at,
-- including every stacked parent scale, so this holds whatever the upstream scale math does (only ever shrinks).
function EllesmereUI.ClampPopupToScreen(popup, w, h)
    if not popup or not w or not h or w <= 0 or h <= 0 then return end
    local es = popup:GetEffectiveScale()
    if type(es) ~= "number" or es <= 0 then return end
    local pw, ph = GetPhysicalScreenSize()
    if type(pw) ~= "number" or type(ph) ~= "number" or pw <= 0 or ph <= 0 then return end
    local fit = math.min((pw * 0.92) / (w * es), (ph * 0.92) / (h * es))
    if fit >= 1 then return end
    popup:SetScale(popup:GetScale() * fit)
end

-- Announcement popup shell: full-screen dimmer (name.."Dimmer") and a centred panel
-- (name.."Popup") with an edge of physical pixels and Escape handling. opts: w, h; bump
-- (PopupBump mult; nil = caller scales both frames later); strata; dimAlpha; bg {r,g,b};
-- edge {r,g,b,a}; edgePx; clamp (ClampPopupToScreen); onEscape (nil = Escape is only
-- swallowed); onDimmerDown. Other keys propagate. Returns dimmer, popup.
function EllesmereUI.BuildPopupShell(name, opts)
    local strata = opts.strata or "FULLSCREEN_DIALOG"
    local dimmer = CreateFrame("Frame", name .. "Dimmer", UIParent)
    dimmer:SetFrameStrata(strata)
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    if opts.onDimmerDown then dimmer:SetScript("OnMouseDown", opts.onDimmerDown) end
    if opts.bump then dimmer:SetScale(GetPopupScale()) end
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, opts.dimAlpha or 0.35)

    local popup = CreateFrame("Frame", name .. "Popup", dimmer)
    if opts.bump then popup:SetScale(EllesmereUI.PopupBump(opts.bump)) end
    popup:SetFrameStrata(strata)
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    PanelPP.Size(popup, opts.w, opts.h)
    if opts.clamp then EllesmereUI.ClampPopupToScreen(popup, opts.w, opts.h) end
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    popup:EnableMouse(true)

    local c = opts.bg or { 0.077, 0.068, 0.058 }
    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(c[1], c[2], c[3], 1)

    -- Edge width is read after every scale above, so it lands on whole physical pixels.
    local e = opts.edge or { 1, 1, 1, 0.15 }
    local edgeW = (1 / (popup:GetEffectiveScale() or 1)) * (opts.edgePx or 1)
    local function MakeEdge()
        local t = popup:CreateTexture(nil, "BORDER")
        t:SetColorTexture(e[1], e[2], e[3], e[4])
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        return t
    end
    local spT = MakeEdge(); spT:SetPoint("TOPLEFT", 0, 0); spT:SetPoint("TOPRIGHT", 0, 0); spT:SetHeight(edgeW)
    local spB = MakeEdge(); spB:SetPoint("BOTTOMLEFT", 0, 0); spB:SetPoint("BOTTOMRIGHT", 0, 0); spB:SetHeight(edgeW)
    local spL = MakeEdge(); spL:SetPoint("TOPLEFT", spT, "BOTTOMLEFT"); spL:SetPoint("BOTTOMLEFT", spB, "TOPLEFT"); spL:SetWidth(edgeW)
    local spR = MakeEdge(); spR:SetPoint("TOPRIGHT", spT, "BOTTOMRIGHT"); spR:SetPoint("BOTTOMRIGHT", spB, "TOPRIGHT"); spR:SetWidth(edgeW)

    local onEscape = opts.onEscape
    -- EnableKeyboard and SetPropagateKeyboardInput are protected in combat:
    -- a shell built there never takes the keyboard, and in combat a shown one
    -- stands aside (keys reach the game, its buttons still answer).
    if not InCombatLockdown() then
        popup:EnableKeyboard(true)
        popup:SetPropagateKeyboardInput(true)
    end
    popup:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" and onEscape then onEscape() end
    end)
    -- Controller Back takes the Escape route (swallowed when there is none). It
    -- counts only when a controller is in use at the show, so the keyboard path
    -- never changes. The dimmer is born shown: with a controller it is hidden
    -- first so the caller's Show() is a real show edge.
    if EllesmereUI.RegisterEscapeClose then
        if EllesmereUI.PadInUse() then dimmer:Hide() end
        EllesmereUI.RegisterEscapeClose(dimmer, {
            padOnly = true,
            modal = not onEscape,
            onEscape = onEscape and function() onEscape() end or nil,
        })
    end
    -- Controller cursor: the panel is a blocker, not a stop.
    EllesmereUI.PadHint(popup, "nodepass")
    return dimmer, popup
end

-- Announcement action button, 38 tall: primary is bright, secondary dim. opts: w;
-- secondary; hoverA (secondary border alpha on hover); hoverRGB {r,g,b} (secondary
-- hovers to that colour instead, border alpha 0.95). The caller anchors it.
function EllesmereUI.MakeActionButton(parent, font, text, r, g, b, opts)
    local secondary, hoverRGB = opts.secondary, opts.hoverRGB
    local btn = CreateFrame("Button", nil, parent)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    PanelPP.Size(btn, opts.w, 38)
    local bbg = btn:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.077, 0.068, 0.058, 0.92)
    local brd = MakeBorder(btn, r, g, b, secondary and 0.35 or 0.9, PanelPP)
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(font, 15, "")
    PanelPP.Point(lbl, "CENTER", btn, "CENTER", 0, 0)
    lbl:SetTextColor(r, g, b, secondary and 0.55 or 0.9)
    lbl:SetText(text)
    btn:SetScript("OnEnter", function()
        if secondary and hoverRGB then
            lbl:SetTextColor(hoverRGB[1], hoverRGB[2], hoverRGB[3], 1)
            brd:SetColor(hoverRGB[1], hoverRGB[2], hoverRGB[3], 0.95)
        else
            lbl:SetTextColor(r, g, b, 1)
            brd:SetColor(r, g, b, secondary and opts.hoverA or 1)
        end
    end)
    btn:SetScript("OnLeave", function()
        lbl:SetTextColor(r, g, b, secondary and 0.55 or 0.9)
        brd:SetColor(r, g, b, secondary and 0.35 or 0.9)
    end)
    return btn
end

-- Fading popup button (confirm and input popups): 125x27; text and border lerp from the
-- default to the hover colours over 0.1s. Exposes btn._lbl, btn._resetAnim and
-- btn._setColors (new colours, same argument order as the defaults below).
function EllesmereUI.MakePopupButton(parent, anchorPoint, anchorTo, anchorRef, xOff, yOff, defR, defG, defB, defA, hovR, hovG, hovB, hovA, bDefR, bDefG, bDefB, bDefA, bHovR, bHovG, bHovB, bHovA)
    local FADE_DUR = 0.1
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(125, 27)
    btn:SetPoint(anchorPoint, anchorTo, anchorRef, xOff, yOff)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)

    local bg = SolidTex(btn, "BACKGROUND", 0, 0, 0, 0.5)
    bg:SetAllPoints()
    local brd = MakeBorder(btn, bDefR, bDefG, bDefB, bDefA)

    local lbl = MakeFont(btn, 12, nil, defR, defG, defB)
    lbl:SetAlpha(defA)
    lbl:SetPoint("CENTER")

    local progress, target = 0, 0
    local function Apply(t)
        lbl:SetTextColor(lerp(defR, hovR, t), lerp(defG, hovG, t), lerp(defB, hovB, t), lerp(defA, hovA, t))
        brd:SetColor(lerp(bDefR, bHovR, t), lerp(bDefG, bHovG, t), lerp(bDefB, bHovB, t), lerp(bDefA, bHovA, t))
    end

    local function OnUpdate(self, elapsed)
        local dir = (target == 1) and 1 or -1
        progress = progress + dir * (elapsed / FADE_DUR)
        if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
            progress = target
            self:SetScript("OnUpdate", nil)
        end
        Apply(progress)
    end

    btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
    btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)

    btn._lbl = lbl
    btn._resetAnim = function() progress = 0; target = 0; Apply(0); btn:SetScript("OnUpdate", nil) end
    -- Replaces the default and hover colours and repaints at the current hover progress.
    btn._setColors = function(...)
        defR, defG, defB, defA, hovR, hovG, hovB, hovA,
            bDefR, bDefG, bDefB, bDefA, bHovR, bHovG, bHovB, bHovA = ...
        lbl:SetAlpha(defA)
        Apply(progress)
    end
    return btn
end

-- Re-apply the scale to the frame that OWNS it. A popup registered with a dimmer takes its
-- scale from that dimmer and carries only its bump, so writing GetPopupScale() onto the popup
-- here would restore the squared double-scale on the first slider change; scaling the dimmer also keeps it from holding its creation-time scale forever while the popup rescales underneath it.
local function RefreshPopupScales()
    local s = GetPopupScale()
    for _, entry in ipairs(_popupFrames) do
        if entry.dimmer then
            entry.dimmer:SetScale(s)
        elseif entry.popup then
            entry.popup:SetScale(s)
        end
    end
end

-- Register so popups rescale when the user adjusts the panel scale slider
if not EllesmereUI._onScaleChanged then EllesmereUI._onScaleChanged = {} end
EllesmereUI._onScaleChanged[#EllesmereUI._onScaleChanged + 1] = RefreshPopupScales

-------------------------------------------------------------------------------
--  Custom Confirmation Popup  (matches EllesmereUI aesthetic)
--  Usage:  EllesmereUI:ShowConfirmPopup({ title, message, confirmText, cancelText, onConfirm, onCancel })
-------------------------------------------------------------------------------
local confirmPopup

-- Helper: wire Escape key to dismiss a popup via its dimmer
-- Keyboard for a popup of ours: `frame` takes the keys, `host` (its dimmer,
-- when it has one) shows and hides it. EnableKeyboard and
-- SetPropagateKeyboardInput are protected in combat, so the frame takes the
-- keyboard now and each time the host shows, only out of combat, passing keys
-- on by default; its OnKeyDown returns first in combat (keys reach the game,
-- Escape stands aside, the buttons still answer). It lets go when the host
-- hides out of combat, so a popup shown again in combat holds no keyboard
-- (an Escape that closed it left propagation off).
function EllesmereUI.PopupTakeKeys(frame, host)
    local function Take()
        if InCombatLockdown() then return end
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
    end
    if host then
        host:HookScript("OnShow", Take)
        host:HookScript("OnHide", function()
            if not InCombatLockdown() then frame:EnableKeyboard(false) end
        end)
    end
    Take()
end

local function WirePopupEscape(popup, dimmer)
    -- EnableKeyboard and SetPropagateKeyboardInput are protected in combat:
    -- the popup takes the keyboard only while shown out of combat, passing
    -- keys on by default, and in combat it stands aside (keys reach the
    -- game, Escape does not close it, its buttons still answer).
    local function TakeKeys(on)
        if InCombatLockdown() then return end
        popup:EnableKeyboard(on)
        if on then popup:SetPropagateKeyboardInput(true) end
    end
    popup:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            if popup._modal then
                -- Modal popups swallow Escape: the user must click a button.
                self:SetPropagateKeyboardInput(false)
                return
            end
            self:SetPropagateKeyboardInput(false)
            dimmer:Hide()
            if popup._onCancel then popup._onCancel() end
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    -- Release keyboard capture when the popup is dismissed
    dimmer:HookScript("OnHide", function() TakeKeys(false) end)
    dimmer:HookScript("OnShow", function() TakeKeys(true) end)
    if dimmer:IsShown() then TakeKeys(true) end
    -- Controller Back takes the same route as Escape (modal popups swallow it).
    -- It counts only when a controller is in use at the show, so the keyboard
    -- path never changes.
    if EllesmereUI.RegisterEscapeClose then
        EllesmereUI.RegisterEscapeClose(dimmer, {
            padOnly = true,
            modal = function() return popup._modal end,
            onEscape = function()
                dimmer:Hide()
                if popup._onCancel then popup._onCancel() end
            end,
        })
    end
    -- Controller cursor: the panel is a blocker, not a stop.
    EllesmereUI.PadHint(popup, "nodepass")
end

local function CreateConfirmPopup()
    if confirmPopup then return confirmPopup end

    local POPUP_W, POPUP_H = 390, 176

    -- Full-screen dimming overlay
    local dimmer = CreateFrame("Frame", "EUIConfirmDimmer", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetFrameLevel(100)  -- above unlock mode movers (level ~21)
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:Hide()

    local dimTex = SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
    dimTex:SetAllPoints()

    -- Popup frame
    local popup = CreateFrame("Frame", "EUIConfirmPopup", dimmer)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)

    -- Popups render at default UI scale (dimmer stays at 1 to cover the full screen).

    -- Background: flat dark default, optional stone atlas for modern style
    local popBgFlat = SolidTex(popup, "BACKGROUND", 0.077, 0.068, 0.058, 1)
    popBgFlat:SetAllPoints()
    local popBgAtlas = popup:CreateTexture(nil, "BACKGROUND")
    popBgAtlas:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    popBgAtlas:SetTexCoord(0.25, 1, 0, 0.75)
    popBgAtlas:SetAllPoints()
    popBgAtlas:Hide()
    local popBgOverlay = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
    popBgOverlay:SetColorTexture(0, 0, 0, 0.6)
    popBgOverlay:SetAllPoints()
    popBgOverlay:Hide()
    popup._popBgFlat = popBgFlat
    popup._popBgAtlas = popBgAtlas
    popup._popBgOverlay = popBgOverlay

    -- Pixel-perfect border
    MakeBorder(popup, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

    -- Title
    local title = MakeFont(popup, 16, "", 1, 1, 1)
    title:SetPoint("TOP", popup, "TOP", 0, -20)
    popup._title = title

    -- Message
    local msg = MakeFont(popup, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    msg:SetPoint("TOP", title, "BOTTOM", 0, -10)
    msg:SetWidth(POPUP_W - 60)
    msg:SetJustifyH("CENTER")
    msg:SetWordWrap(true)
    msg:SetSpacing(4)
    popup._msg = msg

    -- Disclaimer (smaller, italic, below message)
    local disc = popup:CreateFontString(nil, "OVERLAY")
    disc:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
    disc:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a * 0.7)
    disc:SetPoint("TOP", msg, "BOTTOM", 0, -8)
    disc:SetWidth(POPUP_W - 60)
    disc:SetJustifyH("CENTER")
    disc:SetWordWrap(true)
    disc:Hide()
    popup._disclaimer = disc

    -- Scale/resolution mismatch warning (red, below disclaimer)
    local scaleWarn = MakeFont(popup, 10, nil, 1, 0.2, 0.2, 1)
    scaleWarn:SetWidth(POPUP_W - 40)
    scaleWarn:SetJustifyH("CENTER")
    scaleWarn:SetWordWrap(true)
    scaleWarn:SetSpacing(2)
    scaleWarn:Hide()
    popup._scaleWarnLabel = scaleWarn
    popup._baseH = POPUP_H

    -- Button dimensions
    local BTN_H = 27
    local BTN_GAP = 16
    local BTN_Y = 13

    -- Cancel button (left) -- dim white style
    local EG = ELLESMERE_GREEN
    local cancelBtn = EllesmereUI.MakePopupButton(popup,
        "BOTTOMRIGHT", popup, "BOTTOM", -(BTN_GAP / 2), BTN_Y,
        1, 1, 1, 0.7,                                         -- default text
        1, 1, 1, 0.9,                                         -- hovered text
        1, 1, 1, 0.5,                                         -- default border
        1, 1, 1, 0.6                                           -- hovered border
    )

    -- Confirm button (right) -- green style
    local confirmBtn = EllesmereUI.MakePopupButton(popup,
        "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, BTN_Y,
        EG.r, EG.g, EG.b, 0.9,        -- default text
        EG.r, EG.g, EG.b, 1,           -- hovered text
        EG.r, EG.g, EG.b, 0.9,         -- default border
        EG.r, EG.g, EG.b, 1            -- hovered border
    )

    popup._cancelBtn  = cancelBtn
    popup._confirmBtn = confirmBtn

    -- Optional checkbox (above buttons, centered)
    local cbRow = CreateFrame("Button", nil, popup)
    cbRow:SetSize(POPUP_W - 60, 18)
    cbRow:SetPoint("BOTTOM", popup, "BOTTOM", 0, BTN_Y + BTN_H + 10)
    cbRow:SetFrameLevel(popup:GetFrameLevel() + 2)

    local cbBox = CreateFrame("Frame", nil, cbRow)
    cbBox:SetSize(14, 14)
    cbBox:SetPoint("LEFT", cbRow, "LEFT", 0, 0)
    cbBox:SetFrameLevel(cbRow:GetFrameLevel() + 1)
    local cbBoxBg = SolidTex(cbBox, "BACKGROUND", 0.103, 0.095, 0.088, 1)
    cbBoxBg:SetAllPoints()
    MakeBorder(cbBox, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.25)
    local cbCheck = SolidTex(cbBox, "ARTWORK", EG.r, EG.g, EG.b, 1)
    cbCheck:SetPoint("TOPLEFT", 3, -3)
    cbCheck:SetPoint("BOTTOMRIGHT", -3, 3)
    cbCheck:Hide()

    local cbLabel = MakeFont(cbRow, 11, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    cbLabel:SetPoint("LEFT", cbBox, "RIGHT", 6, 0)

    popup._cbChecked = false
    cbRow:SetScript("OnClick", function()
        popup._cbChecked = not popup._cbChecked
        if popup._cbChecked then cbCheck:Show() else cbCheck:Hide() end
    end)
    cbRow:Hide()
    popup._cbRow = cbRow
    popup._cbCheck = cbCheck
    popup._cbLabel = cbLabel

    -- Close on dimmer click outside the popup; modal popups ignore dimmer clicks.
    popup:EnableMouse(true)
    dimmer:SetScript("OnMouseDown", function()
        if popup._modal then return end
        if not popup:IsMouseOver() then
            dimmer:Hide()
            if popup._onCancel then popup._onCancel() end
        end
    end)

    -- Close on Escape
    WirePopupEscape(popup, dimmer)

    popup._dimmer = dimmer
    confirmPopup = popup
    return popup
end

-- Repaints the cached popup's accent parts (the confirm button and the checkbox
-- tick) with the current accent; the popup itself is built once and reused.
local function InvalidateConfirmPopup()
    local popup = confirmPopup
    if not popup then return end
    local EG = ELLESMERE_GREEN
    popup._confirmBtn._setColors(
        EG.r, EG.g, EG.b, 0.9,   EG.r, EG.g, EG.b, 1,
        EG.r, EG.g, EG.b, 0.9,   EG.r, EG.g, EG.b, 1)
    popup._cbCheck:SetColorTexture(EG.r, EG.g, EG.b, 1)
end
EllesmereUI._InvalidateConfirmPopup = InvalidateConfirmPopup

-- Reload the UI from our own code: the reload is asked for at once, then the
-- caller's optional pre-reload `work` runs. WoW Forever lets addon code reload
-- only inside a click or keypress (in or out of combat), never from an event
-- or a timer, so every caller runs from one: a button, a confirm popup or a
-- slash command. It also refused a reload asked for late in the click, after
-- the confirm popup had closed and the caller's work had run (build 70425),
-- so the reload comes before anything else the click does. The client
-- reloads only once the click's code has finished, so `work` still runs and
-- is saved. Code that may run from an event asks with a confirm popup
-- (reload = true), whose click reloads. `title` and `message` name the reload
-- for its callers; nothing shows them.
function EllesmereUI.RequestReload(title, message, work)
    ReloadUI()
    if work then work() end
end

function EllesmereUI:ShowConfirmPopup(opts)
    -- reload = true: confirming reloads the UI from the click (RequestReload),
    -- the caller's own onConfirm, if it has one, running after the reload is
    -- asked for as its pre-reload work. The caller's table is left as is.
    if opts.reload then
        local o = {}
        for k, v in pairs(opts) do o[k] = v end
        o.reload = nil
        local work = opts.onConfirm
        o.onConfirm = function(checked)
            EllesmereUI.RequestReload(nil, nil, work and function() work(checked) end)
        end
        opts = o
    end
    -- Force-close any widget tooltip so it doesn't linger behind the popup
    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    local popup = CreateConfirmPopup()
    popup._dimmer:SetFrameLevel(opts.frameLevel or 100)

    -- Background style: flat (default) or modern Blizzard stone
    local modern = opts.modernBlizz
    popup._popBgFlat:SetShown(not modern)
    popup._popBgAtlas:SetShown(modern == true)
    popup._popBgOverlay:SetShown(modern == true)

    popup._title:SetText(EllesmereUI.L(opts.title or "Confirm"))
    popup._msg:SetText(EllesmereUI.L(opts.message or "Are you sure?"))
    if opts.disclaimer then
        popup._disclaimer:SetText(EllesmereUI.L(opts.disclaimer))
        popup._disclaimer:Show()
    else
        popup._disclaimer:SetText("")
        popup._disclaimer:Hide()
    end

    -- Scale/resolution mismatch warning (red)
    local scaleWarnH = 0
    if opts.scaleWarning and opts.scaleWarning ~= "" then
        popup._scaleWarnLabel:ClearAllPoints()
        if opts.disclaimer and opts.disclaimer ~= "" then
            popup._scaleWarnLabel:SetPoint("TOP", popup._disclaimer, "BOTTOM", 0, -14)
        else
            popup._scaleWarnLabel:SetPoint("TOP", popup._msg, "BOTTOM", 0, -14)
        end
        popup._scaleWarnLabel:SetText(EllesmereUI.L(opts.scaleWarning))
        popup._scaleWarnLabel:Show()
        scaleWarnH = 16
    else
        popup._scaleWarnLabel:SetText("")
        popup._scaleWarnLabel:Hide()
    end
    -- Optional checkbox
    local cbH = 0
    if opts.checkbox then
        popup._cbChecked = false
        popup._cbCheck:Hide()
        popup._cbLabel:SetText(EllesmereUI.L(opts.checkbox))
        local rowW = 14 + 6 + popup._cbLabel:GetStringWidth()
        popup._cbRow:SetWidth(rowW)
        popup._cbRow:ClearAllPoints()
        popup._cbRow:SetPoint("BOTTOM", popup, "BOTTOM", 0, 13 + 27 + 10)
        popup._cbRow:Show()
        cbH = 28
    else
        popup._cbRow:Hide()
    end

    -- The base height affords roughly three message lines; a longer message or a
    -- disclaimer grows the popup by the measured overflow, so no text runs under
    -- the buttons. A secret metric (tainted M+ execution) counts as no overflow.
    local isv = issecretvalue
    local textH = popup._msg:GetStringHeight() or 0
    if isv and isv(textH) then textH = 0 end
    if opts.disclaimer then
        local discH = popup._disclaimer:GetStringHeight() or 0
        if isv and isv(discH) then discH = 0 end
        textH = textH + discH + 8
    end
    local overflowH = math.max(0, textH - 44)

    -- Optional type-to-confirm gate (lazy, like the macro overlay): the user must type the given
    -- word (case-insensitive) before confirm accepts clicks. NOT supported with confirmMacro (secure overlay clicks cannot be gated).
    local typeH = 0
    popup._typeGateOn = nil
    popup._padGate = nil
    -- Controller: the word cannot be typed, so the gate becomes a second press of confirm.
    local padGate = opts.typeToConfirm and EllesmereUI.PadInUse()
    if opts.typeToConfirm and not padGate then
        if not popup._typeRow then
            local row = CreateFrame("Frame", nil, popup)
            row:SetSize(220, 26)
            row:SetFrameLevel(popup:GetFrameLevel() + 2)
            local tLbl = MakeFont(row, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            tLbl:SetPoint("LEFT", row, "LEFT", 0, 0)
            local box = CreateFrame("EditBox", nil, row)
            box:SetSize(110, 26)
            box:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            box:SetAutoFocus(false)
            box:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
            box:SetTextColor(1, 1, 1, 1)
            box:SetTextInsets(8, 8, 0, 0)
            box:SetMaxLetters(24)
            SolidTex(box, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
            MakeBorder(box, 1, 1, 1, 0.12)
            box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            box:SetScript("OnTextChanged", function(self)
                if not popup._typeGateOn then return end
                local ok = strlower(strtrim(self:GetText() or "")) == popup._typeWant
                popup._typeGateOk = ok
                popup._confirmBtn:SetAlpha(ok and 1 or 0.3)
            end)
            box:SetScript("OnEnterPressed", function(self)
                -- The confirm runs first in the keypress, as a click on it
                -- would (a reload it asks for comes first), then the focus clears.
                if popup._typeGateOk then
                    local click = popup._confirmBtn:GetScript("OnClick")
                    if click then click(popup._confirmBtn) end
                end
                self:ClearFocus()
            end)
            row._label = tLbl
            row._box = box
            popup._typeRow = row
        end
        local row = popup._typeRow
        popup._typeGateOn = true
        popup._typeGateOk = false
        popup._typeWant = strlower(strtrim(tostring(opts.typeToConfirm)))
        row._label:SetText(string.format(EllesmereUI.L('Type "%s" to enable:'), tostring(opts.typeToConfirm)))
        row._box:SetText("")
        row:SetWidth(row._label:GetStringWidth() + 10 + 110)
        row:ClearAllPoints()
        row:SetPoint("BOTTOM", popup, "BOTTOM", 0, 13 + 27 + 10 + cbH)
        row:Show()
        typeH = 36
    elseif popup._typeRow then
        popup._typeRow._box:ClearFocus()
        popup._typeRow:Hide()
    end
    if padGate then
        local lbl = popup._padGateLbl
        if not lbl then
            lbl = MakeFont(popup, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            lbl:SetWidth(popup:GetWidth() - 60)
            lbl:SetJustifyH("CENTER")
            popup._padGateLbl = lbl
        end
        popup._typeGateOn = true
        popup._typeGateOk = false
        popup._padGate = true
        lbl:ClearAllPoints()
        lbl:SetPoint("BOTTOM", popup, "BOTTOM", 0, 13 + 27 + 10 + cbH + 6)
        lbl:SetText(EllesmereUI.Lf('Press "%1$s" twice to continue.', EllesmereUI.L(opts.confirmText or "Confirm")))
        lbl:Show()
        typeH = 36
    elseif popup._padGateLbl then
        popup._padGateLbl:Hide()
    end

    popup:SetHeight((popup._baseH or 176) + overflowH + scaleWarnH + cbH + typeH)
    popup._cancelBtn._lbl:SetText(EllesmereUI.L(opts.cancelText or "Cancel"))
    popup._confirmBtn._lbl:SetText(EllesmereUI.L(opts.confirmText or "Confirm"))
    -- onDismiss: called on escape/click-outside. Falls back to onCancel if not provided.
    popup._onCancel = opts.onDismiss or opts.onCancel or nil
    popup._modal = opts.modal and true or false
    -- This show's handle (returned below, for CloseConfirmPopup).
    local handle = {}
    popup._handle = handle

    -- Single-button mode: hide cancel, center confirm
    if opts.hideCancel then
        popup._cancelBtn:Hide()
        popup._confirmBtn:ClearAllPoints()
        popup._confirmBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 13)
    else
        popup._cancelBtn:Show()
        popup._confirmBtn:ClearAllPoints()
        popup._confirmBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 8, 13)
    end
    -- Controller cursor: its cancel press backs out through the visible Cancel,
    -- which is also its first stop, only when Cancel is what Escape does (not
    -- for a modal popup, which needs an answer, nor when onDismiss differs).
    if EllesmereUI.PadCP() then
        local backIsCancel = not (opts.hideCancel or opts.modal or opts.onDismiss)
        popup.CloseButton = backIsCancel and popup._cancelBtn or nil
        EllesmereUI.PadHint(popup._cancelBtn, "nodepriority", backIsCancel and 1 or false)
    end

    -- Reset hover states
    popup._cancelBtn._resetAnim()
    popup._confirmBtn._resetAnim()
    -- confirmDisabled: the confirm stays visible but dark and inert (the
    -- popup is pooled, so both states are re-asserted on every show).
    local confirmOff = opts.confirmDisabled and true or false
    popup._confirmBtn:SetAlpha((popup._typeGateOn or confirmOff) and 0.3 or 1)
    popup._confirmBtn:EnableMouse(not confirmOff)

    popup._cancelBtn:SetScript("OnClick", function()
        popup._dimmer:Hide()
        if opts.onCancel then opts.onCancel() end
    end)

    -- Macro overlay: a protected action (/logout) needs a hardware event routed
    -- through InsecureActionButtonTemplate.
    if opts.confirmMacro then
        if not popup._macroOverlay then
            local ov = CreateFrame("Button", "EUIConfirmMacroOverlay", popup._confirmBtn, "InsecureActionButtonTemplate")
            ov:SetAllPoints(popup._confirmBtn)
            ov:SetFrameLevel(popup._confirmBtn:GetFrameLevel() + 5)
            -- Mouse-up clicks only, and the attribute says so: left unset, the
            -- secure click handler follows the key-down CVar (on by default)
            -- and acts on the press, which an up-only button never delivers.
            ov:RegisterForClicks("AnyUp")
            ov:SetAttribute("useOnKeyDown", false)
            -- Forward hover visuals to the real button underneath
            ov:SetScript("OnEnter", function() popup._confirmBtn:GetScript("OnEnter")(popup._confirmBtn) end)
            ov:SetScript("OnLeave", function() popup._confirmBtn:GetScript("OnLeave")(popup._confirmBtn) end)
            -- Stored callback, not a new hook per ShowConfirmPopup call (they accumulate).
            ov:HookScript("OnClick", function()
                popup._dimmer:Hide()
                if ov._postAction then ov._postAction() end
            end)
            popup._macroOverlay = ov
        end
        local ov = popup._macroOverlay
        ov:SetAttribute("type", "macro")
        ov:SetAttribute("macrotext", opts.confirmMacro)
        ov._postAction = opts.onConfirm
        ov:Show()
        -- Hide the normal confirm click so it doesn't double-fire
        popup._confirmBtn:SetScript("OnClick", nil)
    else
        if popup._macroOverlay then
            popup._macroOverlay:Hide()
        end
        popup._confirmBtn:SetScript("OnClick", function()
            if opts.confirmDisabled then return end
            if popup._typeGateOn and not popup._typeGateOk then
                -- Controller gate: the first press arms, the second confirms.
                if popup._padGate then
                    popup._typeGateOk = true
                    popup._padArmT = GetTime()
                    popup._confirmBtn:SetAlpha(1)
                    popup._padGateLbl:SetText(EllesmereUI.L("Press again to confirm."))
                end
                return
            end
            -- Controller gate: a double tap or a bounced press is not a second press.
            if popup._padGate and GetTime() - (popup._padArmT or 0) < 0.5 then return end
            -- The callback runs before the popup closes, as Blizzard's own
            -- popups do, so a reload it asks for comes first in the click
            -- (RequestReload). The popup then closes only while it still
            -- shows this request: the callback may have opened the next one.
            if opts.onConfirm then opts.onConfirm(popup._cbChecked) end
            if popup._handle == handle then popup._dimmer:Hide() end
        end)
    end

    -- Counter-scale the popup to the options panel (same formula as its root frame, which may not exist yet); the dimmer stays at 1 so it still covers the full screen.
    popup:SetScale(GetPopupScale())


    popup._dimmer:Show()
    -- Controller cursor: move it into the popup (the safe button is its first stop).
    EllesmereUI.PadFocus(popup)
    return handle
end

-- Closes the confirm popup only while it still shows the request whose handle
-- ShowConfirmPopup returned (the popup is shared, so never another caller's
-- dialog), without running any of its callbacks.
function EllesmereUI:CloseConfirmPopup(handle)
    local popup = confirmPopup
    if handle and popup and popup._handle == handle then popup._dimmer:Hide() end
end

-- There is no beta-reset welcome popup or wipe gate (EllesmereUI:ShowWelcomePopup does not exist); manual reset lives in Global Settings > Reset.

-------------------------------------------------------------------------------
--  Scrollable Info Popup  (read-only content with custom scroll + close button)
--  Usage:  EllesmereUI:ShowInfoPopup({ title, content, width, height })
--          content is a plain string; the popup handles word-wrap and scrolling.
-------------------------------------------------------------------------------
local infoPopup

local function CreateInfoPopup()
    if infoPopup then return infoPopup end

    local POPUP_W, POPUP_H = 400, 310

    -- Dimmer
    local dimmer = CreateFrame("Frame", "EUIInfoDimmer", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:Hide()

    local dimTex = SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
    dimTex:SetAllPoints()

    -- Popup frame
    local popup = CreateFrame("Frame", "EUIInfoPopup", dimmer)
    popup:SetSize(POPUP_W, POPUP_H)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    popup:EnableMouse(true)

    local popBg = SolidTex(popup, "BACKGROUND", 0.077, 0.068, 0.058, 1)
    popBg:SetAllPoints()
    MakeBorder(popup, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

    -- Title
    local title = MakeFont(popup, 15, "", 1, 1, 1)
    title:SetPoint("TOP", popup, "TOP", 0, -20)
    popup._title = title

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", nil, popup)
    sf:SetPoint("TOPLEFT", popup, "TOPLEFT", 28, -50)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -20, 52)
    sf:SetFrameLevel(popup:GetFrameLevel() + 1)
    sf:EnableMouseWheel(true)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth() or (POPUP_W - 48))
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    -- Content FontString
    local contentFS = sc:CreateFontString(nil, "OVERLAY")
    contentFS:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
    contentFS:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.80)
    contentFS:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0)
    contentFS:SetWidth((POPUP_W - 48) - 10)
    contentFS:SetJustifyH("LEFT")
    contentFS:SetWordWrap(true)
    contentFS:SetSpacing(3)
    popup._contentFS = contentFS

    local _, scrollTo = EllesmereUI.AttachSmoothScrollbar(sf)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(100, 26)
    closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 16)
    closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    EllesmereUI.MakeStyledButton(closeBtn, "Close", 11,
        EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)
    -- Controller cursor: its cancel press closes through this button.
    if EllesmereUI.PadCP() then popup.CloseButton = closeBtn end

    -- Click dimmer to close
    dimmer:SetScript("OnMouseDown", function()
        if not popup:IsMouseOver() then dimmer:Hide() end
    end)

    -- Escape to close
    WirePopupEscape(popup, dimmer)

    -- Reset scroll on hide
    dimmer:HookScript("OnHide", function() scrollTo(0) end)

    popup._dimmer = dimmer
    popup._scrollFrame = sf
    popup._scrollChild = sc
    infoPopup = popup
    return popup
end

function EllesmereUI:ShowInfoPopup(opts)
    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    local popup = CreateInfoPopup()

    popup._title:SetText(EllesmereUI.L(opts.title or "Information"))
    popup._contentFS:SetText(EllesmereUI.L(opts.content) or "")

    -- Resize scroll child to fit content after a frame
    C_Timer.After(0.01, function()
        local h = popup._contentFS:GetStringHeight() or 100
        popup._scrollChild:SetHeight(h + 10)
    end)

    popup._dimmer:Show()
    -- Controller cursor: move it into the popup.
    EllesmereUI.PadFocus(popup)
end

-------------------------------------------------------------------------------
--  Custom Input Popup  (matches EllesmereUI aesthetic, with EditBox)
--  Usage:  EllesmereUI:ShowInputPopup({ title, message, placeholder, confirmText, cancelText, onConfirm, onCancel })
--          onConfirm receives the entered text as its first argument. A copy box for
--          a link: initialText + selectText (starts selected) + hideCancel (one button).
-------------------------------------------------------------------------------
function EllesmereUI:ShowInputPopup(opts)
    if not self._inputPopup then
        local POPUP_W, POPUP_H = 390, 194

        local dimmer = CreateFrame("Frame", "EUIInputDimmer", UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:EnableMouseWheel(true)
        dimmer:SetScript("OnMouseWheel", function() end)
        dimmer:Hide()

        local dimTex = SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
        dimTex:SetAllPoints()

        local popup = CreateFrame("Frame", "EUIInputPopup", dimmer)
        popup:SetSize(POPUP_W, POPUP_H)
        popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)

        local popBgFlat = SolidTex(popup, "BACKGROUND", 0.077, 0.068, 0.058, 1)
        popBgFlat:SetAllPoints()
        local popBgAtlas = popup:CreateTexture(nil, "BACKGROUND")
        popBgAtlas:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
        popBgAtlas:SetTexCoord(0.25, 1, 0, 0.75)
        popBgAtlas:SetAllPoints()
        popBgAtlas:Hide()
        local popBgOverlay = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
        popBgOverlay:SetColorTexture(0, 0, 0, 0.6)
        popBgOverlay:SetAllPoints()
        popBgOverlay:Hide()
        popup._popBgFlat = popBgFlat
        popup._popBgAtlas = popBgAtlas
        popup._popBgOverlay = popBgOverlay

        MakeBorder(popup, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

        local title = MakeFont(popup, 16, "", 1, 1, 1)
        title:SetPoint("TOP", popup, "TOP", 0, -20)
        popup._title = title

        local msg = MakeFont(popup, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        msg:SetPoint("TOP", title, "BOTTOM", 0, -8)
        msg:SetWidth(POPUP_W - 60)
        msg:SetJustifyH("CENTER")
        msg:SetWordWrap(true)
        msg:SetSpacing(4)
        popup._msg = msg

        local INPUT_W, INPUT_H = 270, 28
        local inputFrame = CreateFrame("Frame", nil, popup)
        inputFrame:SetSize(INPUT_W, INPUT_H)
        inputFrame:SetPoint("TOP", msg, "BOTTOM", 0, -12)
        inputFrame:SetFrameLevel(popup:GetFrameLevel() + 2)

        local iBg = SolidTex(inputFrame, "BACKGROUND", 0, 0, 0, 0.5)
        iBg:SetAllPoints()
        local iBrd = MakeBorder(inputFrame, 1, 1, 1, 0.2)

        -- Red flash animation for empty-input validation
        local FLASH_DUR = 0.7
        local flashElapsed = 0
        local flashing = false
        local flashFrame = CreateFrame("Frame", nil, inputFrame)
        flashFrame:Hide()
        flashFrame:SetScript("OnUpdate", function(self, elapsed)
            flashElapsed = flashElapsed + elapsed
            if flashElapsed >= FLASH_DUR then
                flashing = false
                self:Hide()
                iBrd:SetColor(1, 1, 1, 0.2)
                return
            end
            local t = flashElapsed / FLASH_DUR
            local r = lerp(0.9, 1, t)
            local g = lerp(0.15, 1, t)
            local b = lerp(0.15, 1, t)
            local a = lerp(0.7, 0.2, t)
            iBrd:SetColor(r, g, b, a)
        end)

        popup._flashEmpty = function()
            flashElapsed = 0
            flashing = true
            iBrd:SetColor(0.9, 0.15, 0.15, 0.7)
            flashFrame:Show()
            popup._editBox:SetFocus()
        end

        local editBox = CreateFrame("EditBox", nil, inputFrame)
        editBox:SetPoint("TOPLEFT", 12, -1)
        editBox:SetPoint("BOTTOMRIGHT", -12, 1)
        editBox:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
        editBox:SetTextColor(1, 1, 1, 0.9)
        editBox:SetAutoFocus(false)
        editBox:SetMaxLetters(30)

        local placeholder = editBox:CreateFontString(nil, "ARTWORK")
        placeholder:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
        placeholder:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a * 0.5)
        placeholder:SetPoint("LEFT", editBox, "LEFT", 0, 0)
        popup._placeholder = placeholder

        editBox:SetScript("OnTextChanged", function(self)
            local text = self:GetText() or ""
            if text == "" then placeholder:Show() else placeholder:Hide() end
            if popup._maxCount then
                local count = strlenutf8 and strlenutf8(text) or #text
                popup._countLabel:SetText(count .. "/" .. popup._maxCount)
            end
        end)
        popup._editBox = editBox

        -- Optional warning text (shown below the input field)
        local warnLabel = MakeFont(popup, 10, nil, 1, 0.65, 0.2, 0.85)
        warnLabel:SetPoint("TOP", inputFrame, "BOTTOM", 0, -8)
        warnLabel:SetWidth(POPUP_W - 40)
        warnLabel:SetJustifyH("CENTER")
        warnLabel:SetWordWrap(true)
        warnLabel:SetSpacing(2)
        warnLabel:Hide()
        popup._warnLabel = warnLabel
        popup._inputFrame = inputFrame  -- store so reuse block can anchor against it

        -- Optional scale/resolution mismatch warning (red, shown below the orange warning)
        local scaleWarnLabel = MakeFont(popup, 10, nil, 1, 0.2, 0.2, 1)
        scaleWarnLabel:SetWidth(POPUP_W - 40)
        scaleWarnLabel:SetJustifyH("CENTER")
        scaleWarnLabel:SetWordWrap(true)
        scaleWarnLabel:SetSpacing(2)
        scaleWarnLabel:Hide()
        popup._scaleWarnLabel = scaleWarnLabel

        -- Optional extra button (shown above the input field, e.g. "Add Current Zone")
        local EXTRA_BTN_W, EXTRA_BTN_H = 160, 28
        local extraBtn = CreateFrame("Button", nil, popup)
        extraBtn:SetSize(EXTRA_BTN_W, EXTRA_BTN_H)
        extraBtn:SetPoint("TOP", inputFrame, "BOTTOM", 0, -6)
        extraBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        local extraBg = SolidTex(extraBtn, "BACKGROUND", 0, 0, 0, 0.5)
        extraBg:SetAllPoints()
        MakeBorder(extraBtn, 1, 1, 1, 0.25)
        local extraLbl = MakeFont(extraBtn, 12, nil, 1, 1, 1)
        extraLbl:SetAlpha(0.6)
        extraLbl:SetPoint("CENTER")
        do
            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function Apply(t)
                extraLbl:SetTextColor(1, 1, 1, lerp(0.6, 0.9, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / FADE_DUR)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target; self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            extraBtn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
            extraBtn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
            extraBtn._resetAnim = function() progress = 0; target = 0; Apply(0); extraBtn:SetScript("OnUpdate", nil) end
        end
        extraBtn:Hide()
        popup._extraBtn = extraBtn
        popup._extraLbl = extraLbl

        local BTN_GAP = 16
        local BTN_Y = 18

        local EG = ELLESMERE_GREEN
        local cancelBtn = EllesmereUI.MakePopupButton(popup,
            "BOTTOMRIGHT", popup, "BOTTOM", -(BTN_GAP / 2), BTN_Y,
            1, 1, 1, 0.7,   1, 1, 1, 0.9,
            1, 1, 1, 0.5,   1, 1, 1, 0.6
        )
        local confirmBtn = EllesmereUI.MakePopupButton(popup,
            "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, BTN_Y,
            EG.r, EG.g, EG.b, 0.9,   EG.r, EG.g, EG.b, 1,
            EG.r, EG.g, EG.b, 0.9,   EG.r, EG.g, EG.b, 1
        )

        popup._cancelBtn  = cancelBtn
        popup._confirmBtn = confirmBtn
        popup._btnGap, popup._btnY = BTN_GAP, BTN_Y

        popup:EnableMouse(true)
        dimmer:SetScript("OnMouseDown", function()
            if not popup:IsMouseOver() then
                dimmer:Hide()
                if popup._onCancel then popup._onCancel() end
            end
        end)

        WirePopupEscape(popup, dimmer)

        editBox:SetScript("OnEnterPressed", function()
            if popup._multiline then return end
            local txt = editBox:GetText()
            if txt and (txt ~= "" or popup._allowEmpty) then
                -- The callback before the close, as the confirm button runs it.
                local shown = popup._handle
                if popup._onConfirmCb then popup._onConfirmCb(txt) end
                if popup._handle == shown then dimmer:Hide() end
            else
                popup._flashEmpty()
            end
        end)
        editBox:SetScript("OnEscapePressed", function()
            dimmer:Hide()
            if popup._onCancel then popup._onCancel() end
        end)

        popup._dimmer = dimmer
        self._inputPopup = popup
    end

    local popup = self._inputPopup

    -- Create-once singleton: its creation-time frame level loses to any FULLSCREEN_DIALOG
    -- frame born later (popup dimmers ~1-11, dropdown menus at 200), which then draws OVER
    -- this modal; re-raise on every show (descendants shift with the parent, keeping relative offsets).
    popup._dimmer:SetFrameLevel(300)

    -- Background style: flat (default) or modern Blizzard stone
    local modern = opts.modernBlizz
    popup._popBgFlat:SetShown(not modern)
    popup._popBgAtlas:SetShown(modern == true)
    popup._popBgOverlay:SetShown(modern == true)

    popup._title:SetText(EllesmereUI.L(opts.title or "Enter Name"))
    popup._msg:SetText(EllesmereUI.L(opts.message or ""))
    popup._placeholder:SetText(EllesmereUI.L(opts.placeholder or "Enter name..."))
    popup._cancelBtn._lbl:SetText(EllesmereUI.L(opts.cancelText or "Cancel"))
    popup._confirmBtn._lbl:SetText(EllesmereUI.L(opts.confirmText or "Save"))
    -- Single-button mode (a copy box): hide Cancel, centre the confirm button.
    popup._cancelBtn:SetShown(not opts.hideCancel)
    popup._confirmBtn:ClearAllPoints()
    if opts.hideCancel then
        popup._confirmBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, popup._btnY)
    else
        popup._confirmBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", popup._btnGap / 2, popup._btnY)
    end
    popup._selectText = opts.selectText == true
    popup._onCancel = opts.onDismiss or opts.onCancel or nil
    popup._onConfirmCb = opts.onConfirm or nil
    -- This show's request: a confirm closes the popup only while it still shows it.
    local handle = {}
    popup._handle = handle
    popup._allowEmpty = opts.allowEmpty == true
    popup._multiline = opts.multiline == true

    popup._editBox:SetMaxLetters(opts.maxLetters or 30)
    popup._editBox:SetMultiLine(popup._multiline)
    popup._editBox:SetJustifyV(popup._multiline and "TOP" or "MIDDLE")
    popup._inputFrame:SetHeight(opts.inputHeight or 28)
    popup._editBox:ClearAllPoints()
    popup._editBox:SetPoint("TOPLEFT", popup._inputFrame, "TOPLEFT", 12, popup._multiline and -8 or -1)
    -- A multi-line box keeps the letter count inside its bottom-right corner,
    -- under the text; a single-line box has no room under its text, so its
    -- count sits beside its right edge and the box keeps its full height.
    local countInside = opts.showCount and popup._multiline
    popup._editBox:SetPoint("BOTTOMRIGHT", popup._inputFrame, "BOTTOMRIGHT", -12, countInside and 18 or 1)
    popup._placeholder:ClearAllPoints()
    if popup._multiline then
        popup._placeholder:SetPoint("TOPLEFT", popup._editBox, "TOPLEFT", 0, -1)
    else
        popup._placeholder:SetPoint("LEFT", popup._editBox, "LEFT", 0, 0)
    end
    if opts.showCount and not popup._countLabel then
        popup._countLabel = MakeFont(popup._inputFrame, 9, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    end
    popup._maxCount = opts.showCount and (opts.maxLetters or 0) or nil
    if popup._countLabel then
        popup._countLabel:SetShown(popup._maxCount and popup._maxCount > 0)
        popup._countLabel:ClearAllPoints()
        if countInside then
            popup._countLabel:SetPoint("BOTTOMRIGHT", popup._inputFrame, "BOTTOMRIGHT", -8, 5)
        else
            popup._countLabel:SetPoint("LEFT", popup._inputFrame, "RIGHT", 8, 0)
        end
    end
    local initText = opts.initialText or ""
    popup._editBox:SetText(initText)
    if popup._maxCount then
        local count = strlenutf8 and strlenutf8(initText) or #initText
        popup._countLabel:SetText(count .. "/" .. popup._maxCount)
    end
    if initText == "" then popup._placeholder:Show() else popup._placeholder:Hide() end

    popup._cancelBtn._resetAnim()
    popup._confirmBtn._resetAnim()

    -- Extra button (e.g. "Add Current Zone")
    local extraH = 0
    if opts.extraButton then
        popup._extraLbl:SetText(opts.extraButton.text or "Extra")
        popup._extraBtn._resetAnim()
        popup._extraBtn:SetScript("OnClick", function()
            if opts.extraButton.onClick then opts.extraButton.onClick(popup._editBox) end
        end)
        popup._extraBtn:Show()
        extraH = 26
    else
        popup._extraBtn:Hide()
    end

    -- Optional warning text below the input field
    local warnH = 0
    if opts.warning and opts.warning ~= "" then
        popup._warnLabel:ClearAllPoints()
        popup._warnLabel:SetPoint("TOP", popup._inputFrame, "BOTTOM", 0, -18)
        popup._warnLabel:SetText(opts.warning)
        popup._warnLabel:Show()
        warnH = 24
    else
        popup._warnLabel:SetText("")
        popup._warnLabel:Hide()
    end

    -- Optional scale/resolution mismatch warning (red)
    local scaleWarnH = 0
    if opts.scaleWarning and opts.scaleWarning ~= "" then
        popup._scaleWarnLabel:ClearAllPoints()
        if opts.warning and opts.warning ~= "" then
            popup._scaleWarnLabel:SetPoint("TOP", popup._warnLabel, "BOTTOM", 0, -14)
        else
            popup._scaleWarnLabel:SetPoint("TOP", popup._inputFrame, "BOTTOM", 0, -18)
        end
        popup._scaleWarnLabel:SetText(EllesmereUI.L(opts.scaleWarning))
        popup._scaleWarnLabel:Show()
        scaleWarnH = 30
    else
        popup._scaleWarnLabel:SetText("")
        popup._scaleWarnLabel:Hide()
    end

    popup:SetHeight(194 + math.max(0, (opts.inputHeight or 28) - 28) + extraH + warnH + scaleWarnH)

    popup._cancelBtn:SetScript("OnClick", function()
        popup._dimmer:Hide()
        if opts.onCancel then opts.onCancel() end
    end)
    -- Controller cursor: its cancel press backs out through Cancel only when
    -- Cancel shows and is what Escape does (onDismiss differs from it).
    if EllesmereUI.PadCP() then
        popup.CloseButton = (not (opts.onDismiss or opts.hideCancel)) and popup._cancelBtn or nil
    end
    popup._confirmBtn:SetScript("OnClick", function()
        local txt = popup._editBox:GetText()
        if txt and (txt ~= "" or opts.allowEmpty) then
            -- The callback runs before the popup closes, so a reload it asks
            -- for comes first in the click (RequestReload); the popup closes
            -- only while it still shows this request.
            if opts.onConfirm then opts.onConfirm(txt) end
            if popup._handle == handle then popup._dimmer:Hide() end
        else
            popup._flashEmpty()
        end
    end)

    popup._dimmer:Show()
    C_Timer.After(0.05, function()
        popup._editBox:SetFocus()
        if popup._selectText then popup._editBox:HighlightText() end
    end)
end

-------------------------------------------------------------------------------
--  Quantity window (the Bags stack splitter, Blizzard Skins+' Merchant Bulk
--  Buy): a small window over a button with a title, a close button,
--  - [amount] + and "/ max", an optional text line and a row of action
--  buttons. Amounts are whole steps from one step up to the max (0 while not
--  even one step fits); Shift on -/+ moves by the range's shiftStep when set.
--  Built once per caller, dressed by opts.skin, refilled on every use:
--    d:SetRange(step, max[, shiftStep]), d:SetValue(n), d:Current(),
--    d:Open(owner), d:FocusInput(); d._eb, d._extra, d._buttons[key].
--  opts: name, width, height, title, editWidth, maxLetters, extraLine,
--    buttons = { { key, label, width, height, point ("BOTTOMLEFT", "BOTTOM" or
--    "BOTTOMRIGHT"), onClick, tooltip, primary } }, onEnter, onChange(n),
--    onShow, onHide, skin = { frame(d), font(fs, size), button(parent, w, h,
--    label) -> button, editBox(eb), close(btn) }.
-------------------------------------------------------------------------------
function EllesmereUI.CreateQuantityDialog(opts)
    local skin = opts.skin
    local d = CreateFrame("Frame", opts.name, UIParent)
    d:SetFrameStrata("DIALOG")
    d:SetSize(opts.width, opts.height)
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    d:EnableMouseWheel(true)
    d:Hide()
    d._step, d._max = 1, 1
    skin.frame(d)

    local title = d:CreateFontString(nil, "OVERLAY")
    skin.font(title, 13)
    title:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -9)
    title:SetTextColor(1, 1, 1, 0.9)
    title:SetText(opts.title)

    local close = CreateFrame("Button", nil, d)
    skin.close(close)
    close:SetScript("OnClick", function() d:Hide() end)
    -- Controller cursor: Cancel finds the window's close button.
    if EllesmereUI.PadCP() then d.CloseButton = close end

    local eb = CreateFrame("EditBox", nil, d)
    local function Clamped(n)
        if d._max < d._step then return 0 end
        return Clamp(math.floor(n / d._step) * d._step, d._step, d._max)
    end
    function d:Current() return Clamped(eb:GetNumber() or 0) end
    function d:SetValue(n)
        n = Clamped(n)
        eb:SetText(tostring(n))
        eb:SetCursorPosition(#eb:GetText())
        if opts.onChange then opts.onChange(n) end
    end
    function d:SetRange(step, top, shiftStep)
        d._step, d._max, d._shiftStep = math.max(step or 1, 1), top, shiftStep
        d._maxLbl:SetText("/ " .. top)
    end
    local function Nudge(dir)
        d:SetValue(d:Current() + dir * ((IsShiftKeyDown() and d._shiftStep) or d._step))
    end

    local minus = skin.button(d, 22, 22, "-")
    minus:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -30)
    minus:SetScript("OnClick", function() Nudge(-1) end)

    eb:SetSize(opts.editWidth or 56, 22)
    eb:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(opts.maxLetters or 5)
    eb:SetTextColor(1, 1, 1, 1)
    eb:SetJustifyH("CENTER")
    eb:SetTextInsets(4, 4, 0, 0)
    skin.editBox(eb)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        if self:GetNumber() > d._max then
            d:SetValue(d._max)
        elseif opts.onChange then
            opts.onChange(d:Current())
        end
    end)
    eb:SetScript("OnEditFocusLost", function()
        if d:IsShown() then d:SetValue(d:Current()) end
    end)
    eb:SetScript("OnEnterPressed", function() if opts.onEnter then opts.onEnter() end end)
    eb:SetScript("OnEscapePressed", function() d:Hide() end)
    -- Controller cursor: the -/+ buttons cover the amount, so no on-screen
    -- keyboard for this box.
    EllesmereUI.PadHint(eb, "hidekeyboard")
    d._eb = eb

    local plus = skin.button(d, 22, 22, "+")
    plus:SetPoint("LEFT", eb, "RIGHT", 4, 0)
    plus:SetScript("OnClick", function() Nudge(1) end)

    local maxLbl = d:CreateFontString(nil, "OVERLAY")
    skin.font(maxLbl, 12)
    maxLbl:SetPoint("LEFT", plus, "RIGHT", 8, 0)
    maxLbl:SetTextColor(0.7, 0.7, 0.7, 1)
    d._maxLbl = maxLbl

    if opts.extraLine then
        local line = d:CreateFontString(nil, "OVERLAY")
        skin.font(line, 12)
        line:SetPoint("TOPLEFT", minus, "BOTTOMLEFT", 0, -9)
        line:SetPoint("RIGHT", d, "RIGHT", -10, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        line:SetTextColor(1, 1, 1, 0.9)
        d._extra = line
    end

    d._buttons = {}
    for _, spec in ipairs(opts.buttons) do
        local b = skin.button(d, spec.width, spec.height, spec.label)
        local p = spec.point
        b:SetPoint(p, d, p, (p == "BOTTOMLEFT" and 10) or (p == "BOTTOMRIGHT" and -10) or 0, 10)
        b:SetScript("OnClick", spec.onClick)
        if spec.tooltip then
            b:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(b, spec.tooltip) end)
            b:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        end
        d._buttons[spec.key] = b
        if spec.primary then d._primary = b end
    end

    d:SetScript("OnMouseWheel", function(_, delta) Nudge(delta > 0 and 1 or -1) end)
    d:SetScript("OnShow", function() if opts.onShow then opts.onShow() end end)
    d:SetScript("OnHide", function()
        eb:ClearFocus()
        if opts.onHide then opts.onHide() end
    end)
    EllesmereUI.RegisterEscapeClose(d)

    function d:Open(owner)
        d:ClearAllPoints()
        d:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -4, 6)
        d:Show()
    end
    -- Keyboard on the amount, or, with a controller cursor on screen, the
    -- cursor on the primary button (focus would raise the on-screen keyboard).
    function d:FocusInput()
        if EllesmereUI.PadCursorShown() then
            EllesmereUI.PadFocus(d._primary)
        else
            eb:SetFocus()
            eb:HighlightText()
        end
    end
    return d
end

-- Blizzard's StackSplitFrame when it is open on owner and ours to take over:
-- returns its max. Not when a key is still held in it (its OnHide replays key
-- releases through RunBinding, which must not run from our code), nor under
-- WoW Forever's Gamepad interface style (the popup is part of the controller
-- navigation).
function EllesmereUI.StackSplitFor(owner)
    local ssf = StackSplitFrame
    if not ssf or not ssf:IsShown() or ssf.owner ~= owner then return nil end
    if ssf.down and next(ssf.down) then return nil end
    if EllesmereUI.PadGamepadUI() then return nil end
    return ssf.maxStack or 0
end

-- Takes Blizzard's StackSplitFrame away once StackSplitFor said yes: Hide
-- only, no field writes on Blizzard's popup. Its OnHide runs under this call
-- and writes owner.hasStackSplit = 0 onto the button it was open on.
function EllesmereUI.TakeStackSplit()
    StackSplitFrame:Hide()
end
