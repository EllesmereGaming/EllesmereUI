if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnlockMode_Filter.lua
--  Unlock Mode element filter: a funnel icon and a box right of the top
--  banner's logo, Snap Elements moved to its left; the banner grows on both
--  sides to make room (its art is drawn in slices that stretch only the
--  plain bar, the logo stays whole) and stays on screen with - and +.
--  Typing hides every overlay whose name lacks one of the typed words; the
--  real frames are never touched. Not saved: hiding the banner clears it.
--  Loaded after EUI_UnlockMode_Session.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
EUI_NS.unlockParts = EUI_NS.unlockParts or {}

-- Filter text -> lower-case words, nil when there are none.
local function ParseFilter(text)
    if type(text) ~= "string" then return nil end
    local words
    for w in text:lower():gmatch("%S+") do
        words = words or {}
        words[#words + 1] = w
    end
    return words
end

local function HasAllWords(words, name)
    if type(name) ~= "string" or name == "" then return false end
    name = name:lower()
    for i = 1, #words do
        if not name:find(words[i], 1, true) then return false end
    end
    return true
end

-- True when the filter keeps an element: no words, or every word (a plain
-- substring, any case) in its label or in the label as shown (translated).
local function FilterKeeps(words, label)
    if not words then return true end
    if HasAllWords(words, label) then return true end
    local shown = EllesmereUI.L and EllesmereUI.L(label)
    return shown ~= label and HasAllWords(words, shown) or false
end

-- Banner art (media/eui-unlocked-banner-2*.png, 1144x120): slanted ends in
-- columns 0-58 and 1085-1143, the logo in 519-621, plain bar (identical
-- columns with the accent line) in 59-518 and 622-1084.
local BANNER_W, BANNER_H = 1144, 120
local END_W, LOGO_L, LOGO_R = 59, 519, 622
local FLAT_L1, FLAT_L2, FLAT_R1, FLAT_R2 = 100, 500, 650, 1050
local BANNER_TEX = "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-banner-2.png"
local FILTER_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\filter.png"
-- CreateHUD's own numbers (EUI_UnlockMode_Session.lua): the toggles' inner
-- edges beside the logo and their gaps, the clearance it keeps between Exit /
-- Save & Exit and the toggles, the - and + buttons outside those (10 + 30),
-- and the banner scale range.
local UP_LEFT, UP_RIGHT, UP_GAP_L, UP_GAP_R1, UP_GAP_R2 = -66, 62, 20, 7, 2
local CLEAR, SCALE_BTN = 15, 40
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 1.0, 1.5, 0.1
local ICON_SZ, BOX_GAP, CHAIN_GAP = 28, 6, 20
local BOX_MIN, BOX_MAX = 100, 200
local ALPHA_OFF, ALPHA_ON, ALPHA_HOVER = 0.30, 0.60, 0.9  -- as the bar's toggles

EUI_NS.unlockParts.Filter = function(UM)
local movers, blizzOverlays = UM.movers, UM._blizzOwnedOverlays

local words, lastKey = nil, ""

local function Hides(key)
    return words ~= nil and not FilterKeeps(words, UM.GetBarLabel(key))
end
UM.FilterHides = Hides  -- ghost sync (EUI_UnlockMode_Positions.lua)

-- Mover OnShow hook (CreateMover): every show path ends here.
function UM.FilterOnShow(m)
    if words and Hides(m._barKey) then m:Hide() end
end

-- As the Shift+Right Click hide, without its session flag.
local function HideMover(m)
    m._hoverPending = false
    if UM.selectedMover == m then UM.DeselectMover() end
    if UM.hoveredMover == m then UM.hoveredMover = nil end
    if m._hideOverlayText then m._hideOverlayText() end
    if m._cogBtn then m._cogBtn:Hide() end
    m:Hide()
end

local function Apply()
    if not UM.isUnlocked then return end
    -- A pick mode survives the filter (it helps find the target) unless its own mover hides.
    if UM.pickModeMover and UM.pickMode and Hides(UM.pickModeMover._barKey) then UM.CancelPickMode() end
    if UM.selectElementPicker and Hides(UM.selectElementPicker._barKey) then UM.CancelPickMode() end
    local alpha = UM.darkOverlaysEnabled and 1 or UM.MOVER_ALPHA
    for _, m in pairs(movers) do
        if Hides(m._barKey) then
            if m:IsShown() then HideMover(m) end
        elseif not m:IsShown() and not m._tempHidden then
            m:Sync()
            if m:IsShown() then m:SetAlpha(alpha) end
        end
    end
    for label, ov in pairs(blizzOverlays) do
        if words and not FilterKeeps(words, label) then
            if ov:IsShown() then
                ov._forceCollapse()
                ov:Hide()
                ov._filterHidden = true
            end
        elseif ov._filterHidden then
            ov._filterHidden = nil
            if not ov._tempHidden then ov:SetAlpha(1); ov:Show() end
        end
    end
    -- Ghosts hide themselves in their sync; a refresh brings the kept ones back.
    if EllesmereUI._RefreshFallbackGhosts then EllesmereUI._RefreshFallbackGhosts() end
    if EllesmereUI._RefreshOverrideGhosts then EllesmereUI._RefreshOverrideGhosts() end
    -- Resting alpha: one hidden during the open fade-in missed its ramp (a running fade resets it).
    if EllesmereUI._SetFallbackGhostsAlpha then EllesmereUI._SetFallbackGhostsAlpha(1) end
    if EllesmereUI._SetOverrideGhostsAlpha then EllesmereUI._SetOverrideGhostsAlpha(1) end
end

-- The banner art in five pieces, so the banner can grow on both sides: its
-- own texture keeps the logo at its place and size, the slanted ends stay 1:1
-- at the edges, and only plain bar stretches between them. The pieces follow
-- the art swap of special sessions.
local function SliceBanner(hud)
    local logo = hud._bannerTex
    local lEnd, lFlat = hud:CreateTexture(nil, "ARTWORK"), hud:CreateTexture(nil, "ARTWORK")
    local rFlat, rEnd = hud:CreateTexture(nil, "ARTWORK"), hud:CreateTexture(nil, "ARTWORK")
    local function Coords()
        logo:SetTexCoord(LOGO_L / BANNER_W, LOGO_R / BANNER_W, 0, 1)
        lEnd:SetTexCoord(0, END_W / BANNER_W, 0, 1)
        lFlat:SetTexCoord(FLAT_L1 / BANNER_W, FLAT_L2 / BANNER_W, 0, 1)
        rFlat:SetTexCoord(FLAT_R1 / BANNER_W, FLAT_R2 / BANNER_W, 0, 1)
        rEnd:SetTexCoord((BANNER_W - END_W) / BANNER_W, 1, 0, 1)
    end
    logo:ClearAllPoints()
    logo:SetSize(LOGO_R - LOGO_L, BANNER_H)
    logo:SetPoint("TOPLEFT", hud, "TOP", LOGO_L - BANNER_W / 2, 0)
    lEnd:SetSize(END_W, BANNER_H)
    lEnd:SetPoint("TOPLEFT", hud, "TOPLEFT", 0, 0)
    rEnd:SetSize(END_W, BANNER_H)
    rEnd:SetPoint("TOPRIGHT", hud, "TOPRIGHT", 0, 0)
    lFlat:SetPoint("TOPLEFT", lEnd, "TOPRIGHT", 0, 0)
    lFlat:SetPoint("BOTTOMRIGHT", logo, "BOTTOMLEFT", 0, 0)
    rFlat:SetPoint("TOPLEFT", logo, "TOPRIGHT", 0, 0)
    rFlat:SetPoint("BOTTOMRIGHT", rEnd, "BOTTOMLEFT", 0, 0)
    local pieces = { lEnd, lFlat, rFlat, rEnd }
    for i = 1, #pieces do
        local t = pieces[i]
        t:SetTexture(BANNER_TEX)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
    end
    Coords()
    hooksecurefunc(logo, "SetTexture", function(_, path)
        for i = 1, #pieces do pieces[i]:SetTexture(path) end
        Coords()
    end)
end

-- Sizes the box and the banner for a half screen width V (banner units at
-- banner scale 100%, nil = no limit) and returns the half width the banner
-- then needs: its art (whole slanted ends) or its - and + buttons, whichever
-- reaches farther. The box fills the right half out to the left half's edge;
-- the banner grows as far as the farther half moved
-- out from where CreateHUD put it, so Exit and Save & Exit keep their gaps.
-- When that does not fit: the box shrinks to BOX_MIN, then the banner only
-- keeps CreateHUD's minimum clearance.
local function Layout(hud, frame, V)
    local half = BANNER_W / 2
    local wS, wC, wH = hud._magnetBtn:GetWidth(), hud._coordBtn:GetWidth(), hud._hoverBtn:GetWidth()
    local upL = -UP_LEFT + hud._gridBtn:GetWidth() + hud._darkOverlayBtn:GetWidth() + hud._flashBtn:GetWidth() + 2 * UP_GAP_L
    local upR = UP_RIGHT + wS + UP_GAP_R1 + wC + UP_GAP_R2 + wH
    local left = upL + wS + CHAIN_GAP
    local fixed = UP_RIGHT + ICON_SZ + BOX_GAP + CHAIN_GAP + wC + CHAIN_GAP + wH
    local exit, save = hud._exitBtn, hud._saveBtn
    local exitIn, saveIn = select(4, exit:GetPoint(1)), -select(4, save:GetPoint(1))
    local function Outer(e) return math.max(half + e, half + e - math.min(exitIn, saveIn) + SCALE_BTN) end
    local boxW = math.max(BOX_MIN, math.min(BOX_MAX, math.floor(left - fixed + 0.5)))
    local e = math.max(0, left - upL, fixed + boxW - upR)
    if V and Outer(math.ceil(e)) > V then
        boxW = BOX_MIN
        e = math.max(0, left - upL, fixed + boxW - upR)
        if Outer(math.ceil(e)) > V then
            e = math.max(0, left + CLEAR + exitIn + exit:GetWidth() - half,
                fixed + boxW + CLEAR + saveIn + save:GetWidth() - half)
        end
    end
    e = math.ceil(e)
    hud:SetWidth(BANNER_W + 2 * e)
    frame:SetWidth(boxW)
    return Outer(e)
end

-- Keeps the banner and its - and + on screen: a banner scale that no longer
-- fits (a smaller screen) shows at the largest step that does, without saving
-- it, and + greys where the next step would not fit.
local function MakeFit(hud, frame)
    local s0 = EllesmereUIDB and EllesmereUIDB.unlockBannerScale or SCALE_MIN
    local base = hud:GetScale() / math.max(SCALE_MIN, math.min(SCALE_MAX, s0))  -- scale at 100%
    local greyed = false
    return function()
        local V = GetScreenWidth() / (2 * base)
        local fitMax = V / Layout(hud, frame, V)
        local s = hud:GetScale() / base
        local target = s
        if s > math.max(SCALE_MIN, fitMax) + 0.001 then
            target = math.max(SCALE_MIN, math.floor(fitMax / SCALE_STEP + 0.001) * SCALE_STEP)
        end
        -- CreateHUD's scale setter also resets +, which clears a grey of ours.
        if target ~= s or greyed then hud._applyBannerScale(target, true) end
        greyed = false
        local plus = hud._plusBtn
        if hud:GetScale() / base + SCALE_STEP > fitMax + 0.001 and not plus._isDisabled then
            plus._isDisabled = true  -- as CreateHUD's RefreshScaleBtns at its maximum
            plus._shadow:SetTextColor(0.35, 0.35, 0.35, 0.3)
            plus._label:SetTextColor(0.35, 0.35, 0.35, 0.5)
            greyed = true
        end
    end
end

-- Called by CreateHUD with the banner and the toggles' vertical center.
-- Left of the logo: Exit, Cursor Light, Dark Overlays, Grid Lines and Snap
-- Elements (moved over); right of it: the funnel, the box, Coordinates,
-- Hover Top Bar and Save & Exit.
function UM.BuildFilter(hud, centerY)
    SliceBanner(hud)
    local FONT_PATH = UM.FONT_PATH
    local BR, BG, BB = EllesmereUI.BORDER_R or 1, EllesmereUI.BORDER_G or 1, EllesmereUI.BORDER_B or 1

    -- Snap Elements next to the logo's left side, its label outside like the other left toggles.
    local snap = hud._magnetBtn
    snap:ClearAllPoints()
    snap:SetPoint("RIGHT", hud, "TOP", UP_LEFT, centerY)
    snap._tex:ClearAllPoints()
    snap._tex:SetPoint("RIGHT", snap, "RIGHT", 0, 0)
    snap._label:ClearAllPoints()
    snap._label:SetPoint("RIGHT", snap._tex, "LEFT", -5, 0)
    snap._label:SetJustifyH("RIGHT")
    -- Grid, then Dark Overlays and Cursor Light hung off it, left of Snap Elements.
    hud._gridBtn:ClearAllPoints()
    hud._gridBtn:SetPoint("RIGHT", snap, "LEFT", -CHAIN_GAP, 0)

    -- Funnel icon next to the logo's right side: the box's focus button and tooltip anchor.
    local icon = CreateFrame("Button", nil, hud)
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", hud, "TOP", UP_RIGHT, centerY)
    icon:SetFrameLevel(hud:GetFrameLevel() + 2)
    local iconTex = icon:CreateTexture(nil, "OVERLAY")
    iconTex:SetAllPoints()
    iconTex:SetTexture(FILTER_ICON)
    iconTex:SetAlpha(ALPHA_OFF)

    -- The box, as tall as the Exit and Save & Exit buttons; Layout sets its width.
    local frame = CreateFrame("Frame", nil, hud)
    frame:SetSize(BOX_MIN, hud._exitBtn:GetHeight())
    frame:SetPoint("LEFT", icon, "RIGHT", BOX_GAP, 0)
    frame:SetFrameLevel(hud:GetFrameLevel() + 2)
    -- Coordinates and Hover Top Bar right of the box, spaced as the left toggles.
    hud._coordBtn:ClearAllPoints()
    hud._coordBtn:SetPoint("LEFT", frame, "RIGHT", CHAIN_GAP, 0)
    hud._hoverBtn:ClearAllPoints()
    hud._hoverBtn:SetPoint("LEFT", hud._coordBtn, "RIGHT", CHAIN_GAP, 0)

    local Fit = MakeFit(hud, frame)
    Fit()
    hud:HookScript("OnShow", Fit)
    hud._minusBtn:HookScript("OnClick", Fit)
    hud._plusBtn:HookScript("OnClick", Fit)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(EllesmereUI.SL_INPUT_R or 0.03, EllesmereUI.SL_INPUT_G or 0.023,
        EllesmereUI.SL_INPUT_B or 0.018, 0.9)
    local brd = EllesmereUI.MakeBorder(frame, BR, BG, BB, 0.20)

    local box = CreateFrame("EditBox", nil, frame)
    box:SetAllPoints()
    box:SetAutoFocus(false)
    box:EnableMouse(true)
    box:SetFont(FONT_PATH, 11, "")
    box:SetTextColor(1, 1, 1, 0.9)
    box:SetTextInsets(6, 18, 0, 0)
    box:SetMaxLetters(40)

    local hint = frame:CreateFontString(nil, "OVERLAY")
    hint:SetFont(FONT_PATH, 10, "")
    hint:SetPoint("LEFT", frame, "LEFT", 6, 0)
    hint:SetTextColor(1, 1, 1, 0.35)
    hint:SetText(EllesmereUI.L("Filter elements..."))

    local clear = CreateFrame("Button", nil, frame)
    clear:SetSize(16, 16)
    clear:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
    clear:SetFrameLevel(box:GetFrameLevel() + 2)
    clear:Hide()
    local x = clear:CreateFontString(nil, "OVERLAY")
    x:SetFont(FONT_PATH, 12, "")
    x:SetPoint("CENTER")
    x:SetTextColor(1, 1, 1, 0.45)
    x:SetText("x")
    clear:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1, 1) end)
    clear:SetScript("OnLeave", function() x:SetTextColor(1, 1, 1, 0.45) end)
    clear:SetScript("OnClick", function() box:SetText(""); box:ClearFocus() end)

    -- Box border and icon follow hover and focus; the icon also shows whether a filter is set.
    local iconHover = false
    local function Border()
        brd:SetColor(BR, BG, BB, (box:HasFocus() or box:IsMouseOver()) and 0.40 or 0.20)
        iconTex:SetAlpha((iconHover or box:HasFocus()) and ALPHA_HOVER or (words and ALPHA_ON or ALPHA_OFF))
    end
    local function ShowTip(owner)
        -- Below the bar: above it is off screen, and on the bar the banner (level 900) covers it.
        EllesmereUI.ShowWidgetTooltip(owner, EllesmereUI.L("Show only the elements whose name contains every word typed here. Escape clears it."),
            { anchorPoint = "TOP", anchorTo = "BOTTOM", anchorY = -24 * hud:GetScale() })
    end
    box:SetScript("OnEnter", function(self)
        Border()
        ShowTip(self)
    end)
    box:SetScript("OnLeave", function()
        Border()
        EllesmereUI.HideWidgetTooltip()
    end)
    icon:SetScript("OnEnter", function(self)
        iconHover = true
        Border()
        ShowTip(self)
    end)
    icon:SetScript("OnLeave", function()
        iconHover = false
        Border()
        EllesmereUI.HideWidgetTooltip()
    end)
    icon:SetScript("OnClick", function() box:SetFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- A click anywhere else gives the keyboard back (arrow keys nudge again).
    box:SetScript("OnEditFocusGained", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        Border()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        Border()
    end)
    box:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not clear:IsMouseOver() and not icon:IsMouseOver() then self:ClearFocus() end
    end)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text == "" then hint:Show(); clear:Hide() else hint:Hide(); clear:Show() end
        local w = ParseFilter(text)
        local key = w and table.concat(w, " ") or ""
        if key == lastKey then return end
        words, lastKey = w, key
        Apply()
        Border()
    end)
    -- Closing Unlock Mode (or a combat suspend) hides the banner: start clean.
    hud:HookScript("OnHide", function()
        words, lastKey = nil, ""
        for _, ov in pairs(blizzOverlays) do ov._filterHidden = nil end
        box:ClearFocus()
        box:SetText("")
        iconHover = false
        Border()
    end)

    hud._filterBox, hud._filterIcon, hud._filterClear = box, icon, clear
end
end
