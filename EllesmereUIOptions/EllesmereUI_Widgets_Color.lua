if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_Color.lua
--  Color widgets: HSV helpers, the color picker popup, the color swatches
--  and the factory's color rows. Loads right after EllesmereUI_Widgets.lua.
--  DEFERRED: body runs on first EllesmereUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()
local PP = EllesmereUI.PanelPP
local MakeFont = EllesmereUI.MakeFont
local MakeBorder = EllesmereUI.MakeBorder
local RowBg = EllesmereUI.RowBg
local RegisterWidgetRefresh = EllesmereUI.RegisterWidgetRefresh
local EXPRESSWAY = EllesmereUI.EXPRESSWAY
local CONTENT_PAD = EllesmereUI.CONTENT_PAD
local TEXT_WHITE = EllesmereUI.TEXT_WHITE
local MEDIA_PATH = EllesmereUI.MEDIA_PATH
local CS = EllesmereUI.CS
local TEXT_DIM_R = EllesmereUI.TEXT_DIM_R
local TEXT_DIM_G = EllesmereUI.TEXT_DIM_G
local TEXT_DIM_B = EllesmereUI.TEXT_DIM_B
local TEXT_DIM_A = EllesmereUI.TEXT_DIM_A
local BORDER_R = EllesmereUI.BORDER_R
local BORDER_G = EllesmereUI.BORDER_G
local BORDER_B = EllesmereUI.BORDER_B
local MakeStyledButton = EllesmereUI.MakeStyledButton
local RB_COLOURS = EllesmereUI.RB_COLOURS
local ShowWidgetTooltip = EllesmereUI.ShowWidgetTooltip
local HideWidgetTooltip = EllesmereUI.HideWidgetTooltip
local WI = EllesmereUI._widgetInternals
local TagOptionRow = WI.TagOptionRow
local WidgetFactory = EllesmereUI.Widgets

-------------------------------------------------------------------------------
--  HSV RGB Conversion Helpers
-------------------------------------------------------------------------------
local function HSVtoRGB(h, s, v)
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if     h < 60  then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else                r, g, b = c, 0, x
    end
    return r + m, g + m, b + m
end

local function RGBtoHSV(r, g, b)
    local mx = math.max(r, g, b)
    local mn = math.min(r, g, b)
    local d = mx - mn
    local h, s, v
    v = mx
    s = (mx == 0) and 0 or (d / mx)
    if d == 0 then
        h = 0
    elseif mx == r then
        h = 60 * (((g - b) / d) % 6)
    elseif mx == g then
        h = 60 * (((b - r) / d) + 2)
    else
        h = 60 * (((r - g) / d) + 4)
    end
    return h, s, v
end

-------------------------------------------------------------------------------
--  Color Picker recent-colors & favorites (file-scope, shared per session)
-------------------------------------------------------------------------------
local PICKER_MAX_SWATCHES = 10

local function GetPickerDB()
    if not EllesmereUIDB then return {} end
    if not EllesmereUIDB.colorPicker then EllesmereUIDB.colorPicker = {} end
    return EllesmereUIDB.colorPicker
end
local function GetRecentColorsDB()
    local db = GetPickerDB(); if not db.recentColors then db.recentColors = {} end; return db.recentColors
end
local function GetFavoritesDB()
    local db = GetPickerDB(); if not db.favorites then db.favorites = {} end; return db.favorites
end
local function ColorKey(r, g, b)
    return string.format("%d-%d-%d", math.floor(r*255+.5), math.floor(g*255+.5), math.floor(b*255+.5))
end
local function RecordRecentColor(r, g, b)
    local db = GetRecentColorsDB(); local key = ColorKey(r, g, b)
    for i = #db, 1, -1 do
        if ColorKey(db[i][1], db[i][2], db[i][3]) == key then table.remove(db, i) end
    end
    table.insert(db, 1, { r, g, b })
    while #db > PICKER_MAX_SWATCHES do table.remove(db) end
end
local function IsFavorite(r, g, b)
    local key = ColorKey(r, g, b)
    for _, c in ipairs(GetFavoritesDB()) do
        if ColorKey(c[1], c[2], c[3]) == key then return true end
    end
    return false
end
local function ToggleFavorite(r, g, b)
    local db = GetFavoritesDB(); local key = ColorKey(r, g, b)
    for i = #db, 1, -1 do
        if ColorKey(db[i][1], db[i][2], db[i][3]) == key then table.remove(db, i); return false end
    end
    table.insert(db, 1, { r, g, b })
    while #db > PICKER_MAX_SWATCHES do table.remove(db) end
    return true
end

-------------------------------------------------------------------------------
--  Custom Color Picker Popup (singleton, replaces Blizzard ColorPickerFrame)
-------------------------------------------------------------------------------
local function BuildColorPickerPopup()
    local PAD = 31
    local PAD_TOP = 21
    local SV_SIZE = 200
    local BAR_W = 20
    local BAR_GAP = 10
    local RIGHT_W = 70
    local RIGHT_GAP = 19
    local PAD_RIGHT = 26
    local POPUP_H = PAD_TOP + 28 + SV_SIZE + 80 + PAD
    local BASE_W = PAD + SV_SIZE + BAR_GAP + BAR_W + BAR_GAP + BAR_W + RIGHT_GAP + RIGHT_W + PAD_RIGHT
    local BASE_W_NO_ALPHA = PAD + SV_SIZE + BAR_GAP + BAR_W + RIGHT_GAP + RIGHT_W + PAD_RIGHT
    -- Extra RIGHT COLUMN height when the picker has an alpha slider, so OK/Cancel clear the Opacity input inserted below Hex#. Popup height and the left-side favorites/recent rows are NOT affected.
    local OPACITY_BLOCK_H = 50

    local currentH, currentS, currentV, currentA = 0, 1, 1, 1
    local prevR, prevG, prevB, prevA = 1, 1, 1, 1
    local swatchFunc, opacityFunc, cancelFunc
    local hasOpacity = false
    local updating = false

    local popup = CreateFrame("Frame", "EllesmereUIColorPicker", UIParent)
    popup:SetSize(BASE_W, POPUP_H)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(400)
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:Hide()

    -- Click-off close via GLOBAL_MOUSE_DOWN (non-blocking: preserves hover/click on every other frame)
    local clickOffFrame = CreateFrame("Frame")
    clickOffFrame:Hide()
    clickOffFrame:SetScript("OnEvent", function(_, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            if popup:IsShown() and not popup:IsMouseOver() then
                if cancelFunc then cancelFunc() end
                popup:Hide()
            end
        end
    end)
    popup:HookScript("OnShow", function()
        -- Defer registration one frame so the mouse-down that opened the popup doesn't immediately trigger click-outside-to-close.
        C_Timer.After(0, function()
            if popup:IsShown() then
                clickOffFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
                clickOffFrame:Show()
            end
        end)
    end)
    popup:HookScript("OnHide", function()
        clickOffFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        clickOffFrame:Hide()
    end)

    local bg = popup:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.08, 0.10, 1)

    MakeBorder(popup, BORDER_R, BORDER_G, BORDER_B, 0.15, PP)

    -- Title bar (draggable)
    local titleBar = CreateFrame("Frame", nil, popup)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT"); titleBar:SetPoint("TOPRIGHT")
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() popup:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)
    local titleLbl = MakeFont(titleBar, 12, nil, 1, 1, 1)
    titleLbl:SetAlpha(0.5); titleLbl:SetPoint("CENTER", 0, -10); titleLbl:SetText(EllesmereUI.L("Color Picker"))

    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(25, 25)
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -13, -12)
    closeBtn:SetFrameLevel(popup:GetFrameLevel() + 5)
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetAllPoints()
    closeIcon:SetTexture(MEDIA_PATH .. "icons/close-popup-4.png")
    closeIcon:SetAlpha(0.40)
    closeIcon:SetSnapToPixelGrid(false)
    closeIcon:SetTexelSnappingBias(0)
    closeBtn:SetScript("OnEnter", function() closeIcon:SetAlpha(0.50) end)
    closeBtn:SetScript("OnLeave", function() closeIcon:SetAlpha(0.40) end)
    closeBtn:SetScript("OnClick", function()
        if cancelFunc then cancelFunc() end
        popup:Hide()
    end)

    -- Getters kept Blizzard-API-compatible
    local outR, outG, outB, outA = 1, 1, 1, 1
    function popup:GetColorRGB() return outR, outG, outB end
    function popup:GetColorAlpha() return outA end

    -- Forward declarations
    local UpdateSVPadHue, UpdateSVCrosshair, UpdateHueIndicator
    local UpdateAlphaBar, UpdateHexInput, UpdateOpacityInput
    local newPreviewTex, prevPreviewTex

    local function FireCallbacks()
        if swatchFunc then swatchFunc() end
        if hasOpacity and opacityFunc then opacityFunc() end
    end

    local function UpdateAllControls()
        if updating then return end
        updating = true
        local r, g, b = HSVtoRGB(currentH, currentS, currentV)
        outR, outG, outB, outA = r, g, b, currentA
        if UpdateSVPadHue then UpdateSVPadHue(currentH) end
        if UpdateSVCrosshair then UpdateSVCrosshair(currentS, currentV) end
        if UpdateHueIndicator then UpdateHueIndicator(currentH) end
        if UpdateAlphaBar then UpdateAlphaBar(r, g, b, currentA) end
        if UpdateHexInput then UpdateHexInput(r, g, b) end
        if UpdateOpacityInput then UpdateOpacityInput(currentA) end
        if newPreviewTex then newPreviewTex:SetColorTexture(r, g, b, currentA) end
        updating = false
    end

    local svPad = CreateFrame("Frame", nil, popup)
    svPad:SetSize(SV_SIZE, SV_SIZE)
    svPad:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, -(PAD_TOP + 28))
    svPad:EnableMouse(true)

    local svHue = svPad:CreateTexture(nil, "BACKGROUND")
    svHue:SetAllPoints(); svHue:SetColorTexture(1, 0, 0, 1)

    local svWhite = svPad:CreateTexture(nil, "BORDER")
    svWhite:SetAllPoints(); svWhite:SetColorTexture(1, 1, 1, 1)
    svWhite:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))

    local svBlack = svPad:CreateTexture(nil, "ARTWORK")
    svBlack:SetAllPoints(); svBlack:SetColorTexture(0, 0, 0, 1)
    svBlack:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))

    MakeBorder(svPad, 1, 1, 1, 0.06, PP)

    local ARM = 6
    local chT = svPad:CreateTexture(nil, "OVERLAY", nil, 7); chT:SetSize(1, ARM); chT:SetColorTexture(1,1,1,0.9)
    local chB = svPad:CreateTexture(nil, "OVERLAY", nil, 7); chB:SetSize(1, ARM); chB:SetColorTexture(1,1,1,0.9)
    local chL = svPad:CreateTexture(nil, "OVERLAY", nil, 7); chL:SetSize(ARM, 1); chL:SetColorTexture(1,1,1,0.9)
    local chR = svPad:CreateTexture(nil, "OVERLAY", nil, 7); chR:SetSize(ARM, 1); chR:SetColorTexture(1,1,1,0.9)

    UpdateSVPadHue = function(h)
        local r, g, b = HSVtoRGB(h, 1, 1)
        svHue:SetColorTexture(r, g, b, 1)
    end
    UpdateSVCrosshair = function(s, v)
        local x = s * SV_SIZE
        local y = -(1 - v) * SV_SIZE
        chT:ClearAllPoints(); chT:SetPoint("BOTTOM", svPad, "TOPLEFT", x, y + 2)
        chB:ClearAllPoints(); chB:SetPoint("TOP", svPad, "TOPLEFT", x, y - 2)
        chL:ClearAllPoints(); chL:SetPoint("RIGHT", svPad, "TOPLEFT", x - 2, y)
        chR:ClearAllPoints(); chR:SetPoint("LEFT", svPad, "TOPLEFT", x + 2, y)
    end

    local svDragging = false
    local function SVFromCursor()
        local cx, cy = GetCursorPosition()
        local scale = svPad:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local left, bottom = svPad:GetLeft(), svPad:GetBottom()
        local s = math.max(0, math.min(1, (cx - left) / SV_SIZE))
        local v = math.max(0, math.min(1, (cy - bottom) / SV_SIZE))
        return s, v
    end
    svPad:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            svDragging = true
            currentS, currentV = SVFromCursor()
            UpdateAllControls(); FireCallbacks()
            self:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then svDragging = false; self:SetScript("OnUpdate", nil); return end
                currentS, currentV = SVFromCursor()
                UpdateAllControls(); FireCallbacks()
            end)
        end
    end)
    svPad:SetScript("OnMouseUp", function(self) svDragging = false; self:SetScript("OnUpdate", nil) end)

    local hueBar = CreateFrame("Frame", nil, popup)
    hueBar:SetSize(BAR_W, SV_SIZE)
    hueBar:SetPoint("TOPLEFT", svPad, "TOPRIGHT", BAR_GAP, 0)
    hueBar:EnableMouse(true)

    local HUE_COLORS = {
        {1,0,0}, {1,1,0}, {0,1,0}, {0,1,1}, {0,0,1}, {1,0,1}, {1,0,0},
    }
    local segH = SV_SIZE / 6
    for i = 1, 6 do
        local seg = hueBar:CreateTexture(nil, "BACKGROUND")
        seg:SetSize(BAR_W, segH); seg:SetPoint("TOPLEFT", hueBar, "TOPLEFT", 0, -(i-1)*segH)
        seg:SetColorTexture(1,1,1,1)
        local top, bot = HUE_COLORS[i], HUE_COLORS[i+1]
        seg:SetGradient("VERTICAL", CreateColor(bot[1],bot[2],bot[3],1), CreateColor(top[1],top[2],top[3],1))
    end
    MakeBorder(hueBar, 1, 1, 1, 0.06, PP)

    local hueInd = hueBar:CreateTexture(nil, "OVERLAY", nil, 7)
    hueInd:SetSize(BAR_W + 4, 2); hueInd:SetColorTexture(1,1,1,1)

    UpdateHueIndicator = function(h)
        hueInd:ClearAllPoints()
        hueInd:SetPoint("CENTER", hueBar, "TOPLEFT", BAR_W/2, -(h/360)*SV_SIZE)
    end

    local hueDragging = false
    local function HueFromCursor()
        local _, cy = GetCursorPosition()
        cy = cy / hueBar:GetEffectiveScale()
        return math.max(0, math.min(1, (hueBar:GetTop() - cy) / SV_SIZE)) * 360
    end
    hueBar:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            hueDragging = true; currentH = HueFromCursor(); UpdateAllControls(); FireCallbacks()
            self:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then hueDragging = false; self:SetScript("OnUpdate", nil); return end
                currentH = HueFromCursor(); UpdateAllControls(); FireCallbacks()
            end)
        end
    end)
    hueBar:SetScript("OnMouseUp", function(self) hueDragging = false; self:SetScript("OnUpdate", nil) end)

    local alphaBar = CreateFrame("Frame", nil, popup)
    alphaBar:SetSize(BAR_W, SV_SIZE)
    alphaBar:SetPoint("TOPLEFT", hueBar, "TOPRIGHT", BAR_GAP, 0)
    alphaBar:EnableMouse(true)

    local CK = 10  -- coarse checkerboard cell: 2 cols x 20 rows = 40 textures
    local ckCols = math.ceil(BAR_W / CK)
    local ckRows = math.ceil(SV_SIZE / CK)
    for row = 0, ckRows - 1 do
        for col = 0, ckCols - 1 do
            local c = ((row + col) % 2 == 0) and 0.3 or 0.15
            local ck = alphaBar:CreateTexture(nil, "BACKGROUND")
            ck:SetSize(CK, CK); ck:SetPoint("TOPLEFT", alphaBar, "TOPLEFT", col * CK, -row * CK)
            ck:SetColorTexture(c, c, c, 1)
        end
    end

    local alphaGrad = alphaBar:CreateTexture(nil, "ARTWORK")
    alphaGrad:SetAllPoints(); alphaGrad:SetColorTexture(1,0,0,1)

    local alphaInd = alphaBar:CreateTexture(nil, "OVERLAY", nil, 7)
    alphaInd:SetSize(BAR_W+4, 2); alphaInd:SetColorTexture(1,1,1,1)
    MakeBorder(alphaBar, 1, 1, 1, 0.06, PP)

    -- Reused CreateColor objects: no per-frame allocation during drag
    local alphaColorBot = CreateColor(0, 0, 0, 0)
    local alphaColorTop = CreateColor(0, 0, 0, 1)

    UpdateAlphaBar = function(r, g, b, a)
        alphaColorBot.r, alphaColorBot.g, alphaColorBot.b, alphaColorBot.a = r, g, b, 0
        alphaColorTop.r, alphaColorTop.g, alphaColorTop.b, alphaColorTop.a = r, g, b, 1
        alphaGrad:SetGradient("VERTICAL", alphaColorBot, alphaColorTop)
        alphaInd:ClearAllPoints()
        alphaInd:SetPoint("CENTER", alphaBar, "TOPLEFT", BAR_W/2, -(1-a)*SV_SIZE)
    end

    local alphaDragging = false
    local function AlphaFromCursor()
        local _, cy = GetCursorPosition()
        cy = cy / alphaBar:GetEffectiveScale()
        return 1 - math.max(0, math.min(1, (alphaBar:GetTop() - cy) / SV_SIZE))
    end
    alphaBar:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            alphaDragging = true; currentA = AlphaFromCursor(); UpdateAllControls(); FireCallbacks()
            self:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then alphaDragging = false; self:SetScript("OnUpdate", nil); return end
                currentA = AlphaFromCursor(); UpdateAllControls(); FireCallbacks()
            end)
        end
    end)
    alphaBar:SetScript("OnMouseUp", function(self) alphaDragging = false; self:SetScript("OnUpdate", nil) end)

    -- Controller cursor: the three pads read the pointer position, which its presses
    -- do not move, so they are skipped (Hex#, Opacity and the swatches set colours);
    -- the drag bar is no stop, and Cancel clicks the close button.
    if EllesmereUI.PadCP() then
        EllesmereUI.PadHint(svPad, "nodeignore")
        EllesmereUI.PadHint(hueBar, "nodeignore")
        EllesmereUI.PadHint(alphaBar, "nodeignore")
        EllesmereUI.PadHint(titleBar, "nodepass")
        popup.CloseButton = closeBtn
    end

    ---------------------------------------------------------------------------
    --  Right column: New, Prev, Hex#, OK
    ---------------------------------------------------------------------------
    local rightCol = CreateFrame("Frame", nil, popup)
    rightCol:SetSize(RIGHT_W, SV_SIZE)
    rightCol:SetPoint("TOPLEFT", alphaBar, "TOPRIGHT", RIGHT_GAP, 0)

    local nl = MakeFont(rightCol, 10, nil, 1,1,1); nl:SetAlpha(TEXT_DIM_A)
    nl:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0); nl:SetText(EllesmereUI.L("New"))

    newPreviewTex = rightCol:CreateTexture(nil, "ARTWORK")
    newPreviewTex:SetSize(RIGHT_W, 26); newPreviewTex:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -14)
    newPreviewTex:SetColorTexture(1,1,1,1)

    -- Prev preview sits directly below New
    local prevPrev = rightCol:CreateTexture(nil, "ARTWORK")
    prevPrev:SetSize(RIGHT_W, 26); prevPrev:SetPoint("TOPLEFT", newPreviewTex, "BOTTOMLEFT", 0, -4)
    prevPrev:SetColorTexture(1,1,1,1)
    prevPreviewTex = prevPrev

    -- Clicking the prev swatch restores the previous color
    local prevBtn = CreateFrame("Button", nil, rightCol)
    prevBtn:SetAllPoints(prevPrev)
    prevBtn:SetFrameLevel(rightCol:GetFrameLevel() + 5)
    prevBtn:SetScript("OnClick", function()
        currentH, currentS, currentV = RGBtoHSV(prevR, prevG, prevB)
        currentA = hasOpacity and prevA or 1
        UpdateAllControls(); FireCallbacks()
    end)

    local pl = MakeFont(rightCol, 10, nil, 1,1,1); pl:SetAlpha(TEXT_DIM_A)
    pl:SetPoint("TOPLEFT", prevPrev, "BOTTOMLEFT", 0, -6); pl:SetText(EllesmereUI.L("Prev"))

    local hexLbl = MakeFont(rightCol, 10, nil, 1,1,1); hexLbl:SetAlpha(TEXT_DIM_A)
    hexLbl:SetPoint("TOPLEFT", pl, "BOTTOMLEFT", 0, -21); hexLbl:SetText(EllesmereUI.L("Hex#"))

    local hexBox = CreateFrame("EditBox", nil, rightCol)
    hexBox:SetSize(RIGHT_W, 24); hexBox:SetPoint("TOPLEFT", hexLbl, "BOTTOMLEFT", 0, -4)
    hexBox:SetFont(EXPRESSWAY, 10, ""); hexBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
    hexBox:SetMaxLetters(6); hexBox:SetAutoFocus(false); hexBox:EnableMouse(true)
    hexBox:SetJustifyH("CENTER")
    local hbg = hexBox:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(); hbg:SetColorTexture(0.22, 0.24, 0.28, 0.5)
    MakeBorder(hexBox, 1, 1, 1, 0.04, PP)

    local lastValidHex = "FFFFFF"
    local lastHexR, lastHexG, lastHexB = -1, -1, -1
    UpdateHexInput = function(r, g, b)
        if hexBox:HasFocus() then return end
        local ri, gi, bi = math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5)
        if ri == lastHexR and gi == lastHexG and bi == lastHexB then return end
        lastHexR, lastHexG, lastHexB = ri, gi, bi
        local hex = string.format("%02X%02X%02X", ri, gi, bi)
        lastValidHex = hex; hexBox:SetText(hex)
    end
    local function CommitHex()
        local txt = hexBox:GetText():upper():gsub("[^%dA-F]", "")
        if #txt == 6 then
            local ri, gi, bi = tonumber(txt:sub(1,2),16)/255, tonumber(txt:sub(3,4),16)/255, tonumber(txt:sub(5,6),16)/255
            currentH, currentS, currentV = RGBtoHSV(ri, gi, bi)
            lastValidHex = txt; UpdateAllControls(); FireCallbacks()
        else hexBox:SetText(lastValidHex) end
    end
    local hexEscaping = false
    hexBox:SetScript("OnEnterPressed", function() CommitHex(); hexBox:ClearFocus() end)
    hexBox:SetScript("OnEscapePressed", function()
        hexEscaping = true
        hexBox:SetText(lastValidHex)
        hexBox:ClearFocus()
        hexEscaping = false
        if cancelFunc then cancelFunc() end
        popup:Hide()
    end)
    hexBox:SetScript("OnEditFocusLost", function()
        if not hexEscaping then CommitHex() end
    end)
    hexBox:SetScript("OnEditFocusGained", function() hexBox:HighlightText() end)
    hexBox:SetScript("OnTextChanged", function(self, userInput)
        if not self:HasFocus() then return end
        local txt = self:GetText():upper():gsub("[^%dA-F]", "")
        if #txt == 6 then
            local ri, gi, bi = tonumber(txt:sub(1,2),16)/255, tonumber(txt:sub(3,4),16)/255, tonumber(txt:sub(5,6),16)/255
            currentH, currentS, currentV = RGBtoHSV(ri, gi, bi)
            lastValidHex = txt; UpdateAllControls(); FireCallbacks()
        end
    end)

    -- Opacity input: shown only with an alpha slider, below Hex# and styled identically. Integer percentage, 0-100.
    local opacityLbl = MakeFont(rightCol, 10, nil, 1,1,1); opacityLbl:SetAlpha(TEXT_DIM_A)
    opacityLbl:SetPoint("TOPLEFT", hexBox, "BOTTOMLEFT", 0, -10); opacityLbl:SetText(EllesmereUI.L("Opacity"))

    local opacityBox = CreateFrame("EditBox", nil, rightCol)
    opacityBox:SetSize(RIGHT_W, 24); opacityBox:SetPoint("TOPLEFT", opacityLbl, "BOTTOMLEFT", 0, -4)
    opacityBox:SetFont(EXPRESSWAY, 10, ""); opacityBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
    opacityBox:SetMaxLetters(3); opacityBox:SetAutoFocus(false); opacityBox:EnableMouse(true)
    opacityBox:SetNumeric(true); opacityBox:SetJustifyH("CENTER")
    local obg = opacityBox:CreateTexture(nil, "BACKGROUND")
    obg:SetAllPoints(); obg:SetColorTexture(0.22, 0.24, 0.28, 0.5)
    MakeBorder(opacityBox, 1, 1, 1, 0.04, PP)

    local lastOpacityPct = -1
    UpdateOpacityInput = function(a)
        if opacityBox:HasFocus() then return end
        local pct = math.floor((a or 1) * 100 + 0.5)
        if pct == lastOpacityPct then return end
        lastOpacityPct = pct
        opacityBox:SetText(tostring(pct))
    end
    -- Parse the box and apply as alpha. commit=true snaps back to the live value when unparseable (Enter/focus loss).
    local function ApplyOpacityText(commit)
        local n = tonumber(opacityBox:GetText())
        if n then
            n = math.max(0, math.min(100, math.floor(n + 0.5)))
            currentA = n / 100
            lastOpacityPct = n
            UpdateAllControls(); FireCallbacks()
            return true
        elseif commit then
            opacityBox:SetText(tostring(math.floor(currentA * 100 + 0.5)))
        end
        return false
    end
    local opacityEscaping = false
    opacityBox:SetScript("OnEnterPressed", function() ApplyOpacityText(true); opacityBox:ClearFocus() end)
    opacityBox:SetScript("OnEscapePressed", function()
        opacityEscaping = true
        opacityBox:SetText(tostring(math.floor(currentA * 100 + 0.5)))
        opacityBox:ClearFocus()
        opacityEscaping = false
        if cancelFunc then cancelFunc() end
        popup:Hide()
    end)
    opacityBox:SetScript("OnEditFocusLost", function() if not opacityEscaping then ApplyOpacityText(true) end end)
    opacityBox:SetScript("OnEditFocusGained", function() opacityBox:HighlightText() end)
    opacityBox:SetScript("OnTextChanged", function(self, userInput)
        if not self:HasFocus() then return end
        ApplyOpacityText(false)
    end)
    opacityLbl:Hide(); opacityBox:Hide()

    -- OK button, bottom of the right column (reset/reload button style)
    local okBtn = CreateFrame("Button", nil, rightCol)
    okBtn:SetSize(RIGHT_W, 21)
    okBtn:SetPoint("BOTTOMLEFT", rightCol, "BOTTOMLEFT", 0, 0)
    okBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    local _confirmed = false
    MakeStyledButton(okBtn, "OK", 10, RB_COLOURS, function()
        RecordRecentColor(HSVtoRGB(currentH, currentS, currentV))
        -- Fire on OK even when nothing changed, to confirm the selection
        FireCallbacks()
        _confirmed = true; popup:Hide()
    end)

    -- Cancel text above OK button
    local cancelBtn = CreateFrame("Button", nil, rightCol)
    cancelBtn:SetSize(RIGHT_W, 14)
    cancelBtn:SetPoint("BOTTOM", okBtn, "TOP", 0, 5)
    cancelBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY")
    cancelText:SetFont(EXPRESSWAY, 10, "")
    cancelText:SetPoint("CENTER")
    cancelText:SetText(EllesmereUI.L("cancel"))
    cancelText:SetTextColor(1, 1, 1, 0.4)
    cancelBtn:SetScript("OnEnter", function() cancelText:SetTextColor(1, 1, 1, 0.7) end)
    cancelBtn:SetScript("OnLeave", function() cancelText:SetTextColor(1, 1, 1, 0.4) end)
    cancelBtn:SetScript("OnClick", function()
        _confirmed = false
        popup:Hide()
    end)

    ---------------------------------------------------------------------------
    --  Favorites & Recent Colors (below HSV picker)
    ---------------------------------------------------------------------------
    local RefreshSwatchRows
    local SWATCH_SZ      = 19
    local SWATCH_SPACING = 4

    local function MakeSwatchBtn(parent, isFavorites)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(SWATCH_SZ, SWATCH_SZ)
        btn:SetFrameLevel(parent:GetFrameLevel() + 2)
        local tex = btn:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints(); btn._tex = tex
        btn:SetScript("OnEnter", function(self)
            local c = self._color; if not c then return end
            local hex = string.format("%02X%02X%02X",
                math.floor(c[1]*255+.5), math.floor(c[2]*255+.5), math.floor(c[3]*255+.5))
            local hint = isFavorites and EllesmereUI.L("Right-click: remove favorite")
                                      or  EllesmereUI.L("Right-click: favorite")
            -- Anchor on the hovered swatch so the tooltip sits directly above it (default placement is BOTTOM -> anchor TOP).
            ShowWidgetTooltip(self, "|cff"..hex.."#|r"..hex.."\n"..hint)
        end)
        btn:SetScript("OnLeave", function() HideWidgetTooltip() end)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(self, mouseButton)
            local c = self._color; if not c then return end
            if mouseButton == "RightButton" then
                if isFavorites or not IsFavorite(c[1], c[2], c[3]) then
                    ToggleFavorite(c[1], c[2], c[3])
                end
                RefreshSwatchRows()
            else
                currentH, currentS, currentV = RGBtoHSV(c[1], c[2], c[3])
                UpdateAllControls(); FireCallbacks()
            end
        end)
        btn:Hide()
        return btn
    end

    local favLbl = MakeFont(popup, 10, nil, 1,1,1); favLbl:SetAlpha(TEXT_DIM_A)
    favLbl:SetPoint("TOPLEFT", svPad, "BOTTOMLEFT", 0, -10)
    favLbl:SetText(EllesmereUI.L("Favorites"))

    local favRow = CreateFrame("Frame", nil, popup)
    favRow:SetSize(BASE_W - PAD - PAD_RIGHT, SWATCH_SZ)
    favRow:SetPoint("TOPLEFT", favLbl, "BOTTOMLEFT", 0, -3)
    favRow._label = favLbl; favRow._isFavorites = true

    local rcLbl = MakeFont(popup, 10, nil, 1,1,1); rcLbl:SetAlpha(TEXT_DIM_A)
    rcLbl:SetPoint("TOPLEFT", favRow, "BOTTOMLEFT", 0, -8)
    rcLbl:SetText(EllesmereUI.L("Recent Colors"))

    local rcRow = CreateFrame("Frame", nil, popup)
    rcRow:SetSize(BASE_W - PAD - PAD_RIGHT, SWATCH_SZ)
    rcRow:SetPoint("TOPLEFT", rcLbl, "BOTTOMLEFT", 0, -3)
    rcRow._label = rcLbl; rcRow._isFavorites = false

    local favSwatches, rcSwatches = {}, {}

    local function PopulateSwatchRow(swatchPool, row, data)
        local count = math.min(#data, PICKER_MAX_SWATCHES)
        for i = 1, math.max(count, #swatchPool) do
            local btn = swatchPool[i]
            if not btn then btn = MakeSwatchBtn(row, row._isFavorites); swatchPool[i] = btn end
            if i <= count then
                btn._color = data[i]
                btn._tex:SetColorTexture(data[i][1], data[i][2], data[i][3], 1)
                btn:Show(); btn:ClearAllPoints()
                if i == 1 then btn:SetPoint("LEFT", row, "LEFT", 0, 0)
                else btn:SetPoint("LEFT", swatchPool[i-1], "RIGHT", SWATCH_SPACING, 0) end
            else
                btn:Hide()
            end
        end
    end

    RefreshSwatchRows = function()
        PopulateSwatchRow(favSwatches, favRow, GetFavoritesDB())
        PopulateSwatchRow(rcSwatches,  rcRow,  GetRecentColorsDB())
    end

    -- Controller cursor: the swatch that opened the picker (set only when it opened under that cursor).
    local padOpener
    popup:SetScript("OnHide", function()
        EllesmereUI._colorPickerOpen = false
        if not _confirmed and cancelFunc then cancelFunc() end
        _confirmed = false
        svDragging = false; hueDragging = false; alphaDragging = false
        svPad:SetScript("OnUpdate", nil)
        hueBar:SetScript("OnUpdate", nil)
        alphaBar:SetScript("OnUpdate", nil)
        local checks = EllesmereUI._deferredDriftChecks
        EllesmereUI._deferredDriftChecks = nil
        if checks then for fn in pairs(checks) do fn() end end
        -- Re-evaluate widget state (sync icons, disabled overlays) now the picked color is committed. Fast path: no rebuild.
        EllesmereUI:RefreshPage()
        -- Controller cursor: back onto that swatch (a no-op once it is hidden).
        if padOpener then
            local opener = padOpener
            padOpener = nil
            if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(opener) end
        end
    end)
    EllesmereUI.RegisterEscapeClose(popup)

    function popup:Open(info, anchorFrame)
        if popup:IsShown() and cancelFunc then cancelFunc() end
        swatchFunc = info.swatchFunc
        opacityFunc = info.opacityFunc
        cancelFunc = info.cancelFunc
        hasOpacity = info.hasOpacity or false
        local r, g, b = info.r or 0, info.g or 0, info.b or 0
        local a = info.opacity or 1
        prevR, prevG, prevB, prevA = r, g, b, a
        currentH, currentS, currentV = RGBtoHSV(r, g, b)
        currentA = hasOpacity and a or 1
        prevPreviewTex:SetColorTexture(r, g, b, hasOpacity and a or 1)
        -- Reposition the right column by alpha-bar visibility. With an alpha slider ONLY the right column grows taller, so OK/Cancel clear the Opacity input below Hex#. Favorites/recent rows sit on the LEFT, clear of that column, so they and the popup height stay put.
        rightCol:ClearAllPoints()
        if hasOpacity then
            alphaBar:Show()
            popup:SetWidth(BASE_W)
            rightCol:SetPoint("TOPLEFT", alphaBar, "TOPRIGHT", RIGHT_GAP, 0)
            rightCol:SetHeight(SV_SIZE + OPACITY_BLOCK_H)
            opacityLbl:Show(); opacityBox:Show()
        else
            alphaBar:Hide()
            popup:SetWidth(BASE_W_NO_ALPHA)
            rightCol:SetPoint("TOPLEFT", hueBar, "TOPRIGHT", RIGHT_GAP, 0)
            rightCol:SetHeight(SV_SIZE)
            opacityLbl:Hide(); opacityBox:Hide()
        end
        popup:ClearAllPoints()
        -- Horizontally centered on the cursor; vertical placement flips if needed
        local cx, cy = GetCursorPosition()
        local scale = popup:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        -- Controller cursor: the hidden pointer is nowhere near the swatch it pressed.
        if anchorFrame and EllesmereUI.PadCursorShown() then
            padOpener = anchorFrame
            local ax, ay = anchorFrame:GetCenter()
            if ax and ay then
                local r = anchorFrame:GetEffectiveScale() / scale
                cx, cy = ax * r, ay * r
            end
        end
        local pw = popup:GetWidth()
        local ph = popup:GetHeight()
        local x = cx - pw * 0.5
        local y = cy - 30  -- popup top 30px below the cursor
        -- Flip above the cursor if that would drop below the options window
        local mainFrame = EllesmereUI._mainFrame
        if mainFrame and mainFrame:IsShown() then
            local mBot = mainFrame:GetBottom()
            if mBot and (y - ph) < mBot then
                y = cy + 30 + ph  -- popup bottom 30px above the cursor
            end
        end
        popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        EllesmereUI._colorPickerOpen = true
        RefreshSwatchRows()
        popup:Show(); UpdateAllControls()
        -- Controller cursor: into the picker, on OK (its first stop would be the close box).
        if EllesmereUI.PadCursorShown() then EllesmereUI.PadFocus(okBtn) end
    end

    -- Spec Overrides auto-capture: color picker edits attribute to the slot whose swatch opened it.
    popup._euiOptionsPopup = true
    EllesmereUI._colorPickerPopup = popup
    return popup
end

function EllesmereUI:ShowColorPicker(info, anchorFrame)
    local popup = self._colorPickerPopup or BuildColorPickerPopup()
    popup:Open(info, anchorFrame)
end

-- Shared color swatch: border + fill + UpdateSwatch + OnClick. Returns swatch (Button), UpdateSwatch (function), caller positions it. Border textures are deferred until first show to keep page builds light.
local function BuildColorSwatch(parentFrame, baseLevel, getValue, setValue, hasAlpha, overrideSize)
    -- Spec Overrides auto-capture (see BuildToggleControl): fires for direct swatch writes and every color-picker change routed through it.
    do
        local _s = setValue
        setValue = function(...)
            _s(...)
            EllesmereUI._NotifySettingWrite(parentFrame)
        end
    end
    do local _r = setValue; setValue = function(...) _r(...); EllesmereUI._settingsChanged = true end end
    local SWATCH_SZ = overrideSize or 24
    local swatch = CreateFrame("Button", nil, parentFrame)
    PP.Size(swatch, SWATCH_SZ, SWATCH_SZ)
    swatch:SetFrameLevel(baseLevel)

    -- Color fill: 1 texture, always created immediately
    local sFill = swatch:CreateTexture(nil, "ARTWORK")
    sFill:SetAllPoints()

    local borderBuilt = false

    local function BuildBorder()
        if borderBuilt then return end
        borderBuilt = true
        local T = CS.BRD_THICK

        local wt = swatch:CreateTexture(nil, "BORDER")
        wt:SetColorTexture(1, 1, 1, 1)
        wt:SetPoint("BOTTOMLEFT", swatch, "TOPLEFT", -T, 0); wt:SetPoint("BOTTOMRIGHT", swatch, "TOPRIGHT", T, 0); PP.Height(wt, T)
        local wb = swatch:CreateTexture(nil, "BORDER")
        wb:SetColorTexture(1, 1, 1, 1)
        wb:SetPoint("TOPLEFT", swatch, "BOTTOMLEFT", -T, 0); wb:SetPoint("TOPRIGHT", swatch, "BOTTOMRIGHT", T, 0); PP.Height(wb, T)
        local wl = swatch:CreateTexture(nil, "BORDER")
        wl:SetColorTexture(1, 1, 1, 1)
        wl:SetPoint("TOPLEFT", swatch, "TOPLEFT", -T, 0); wl:SetPoint("BOTTOMLEFT", swatch, "BOTTOMLEFT", -T, 0); PP.Width(wl, T)
        local wr = swatch:CreateTexture(nil, "BORDER")
        wr:SetColorTexture(1, 1, 1, 1)
        wr:SetPoint("TOPRIGHT", swatch, "TOPRIGHT", T, 0); wr:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", T, 0); PP.Width(wr, T)
    end

    local function UpdateSwatch()
        local r, g, b, a = getValue()
        sFill:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    end

    -- Initial fill color (no border needed yet)
    do
        local r, g, b, a = getValue()
        sFill:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    end

    -- Border builds lazily on first show, or now if already visible
    swatch:HookScript("OnShow", function()
        if not borderBuilt then BuildBorder() end
    end)
    if swatch:IsVisible() then BuildBorder() end

    swatch:SetScript("OnClick", function()
        local r, g, b, a = getValue()
        r, g, b, a = r or 0, g or 0, b or 0, a or 1
        local snapR, snapG, snapB, snapA = r, g, b, a
        local function OnColorChanged()
            local popup = EllesmereUI._colorPickerPopup
            if not popup then return end
            local cr, cg, cb = popup:GetColorRGB()
            local ca = hasAlpha and popup:GetColorAlpha() or 1
            sFill:SetColorTexture(cr, cg, cb, ca)
            setValue(cr, cg, cb, ca)
            UpdateSwatch()
        end
        local info = {
            swatchFunc = function() OnColorChanged() end,
            hasOpacity = hasAlpha,
            opacityFunc = function() OnColorChanged() end,
            opacity = a,
            cancelFunc = function() setValue(snapR, snapG, snapB, snapA); UpdateSwatch() end,
            r = r, g = g, b = b,
        }
        EllesmereUI:ShowColorPicker(info, swatch)
    end)

    -- Spec Overrides capture: an inline swatch belongs to its hosting slot (options files pass the DualRow half-region as parent), so it joins that slot's capture group. AddCaptureAccessor dedupes by getValue identity, so factory-built swatches whose accessors are stashed separately never double.
    if EllesmereUI.AddCaptureAccessor and not parentFrame._noCapture then
        EllesmereUI.AddCaptureAccessor(parentFrame, {
            type = "colorpicker", hasAlpha = hasAlpha,
            getValue = getValue, setValue = setValue,
        })
    end

    return swatch, UpdateSwatch
end

-- default/custom/class color swatch trio; callers track a mode string. opts:
--   getMode()           -> "default" | "custom" | "class"
--   setMode(mode)       -> store the new mode
--   getCustomRGB()      -> r, g, b of the custom color
--   setCustomRGB(r,g,b) -> store the picked color
--   onChange()          -> optional, called after any swatch click
--   disabled()          -> optional, true to disable all swatches
--   disabledAlpha       -> optional alpha while disabled (default 0.3)
--   hasAlpha, overrideSize -> forwarded to BuildColorSwatch
-- Returns customSwatch, defaultSwatch, classSwatch, Update.
local DEFAULT_UNTINTED_R, DEFAULT_UNTINTED_G, DEFAULT_UNTINTED_B = 1.0, 0.788, 0.137
local function BuildTrioColorSwatch(parentFrame, baseLevel, opts)
    local customSwatch, updateCustom = BuildColorSwatch(parentFrame, baseLevel,
        function()
            local r, g, b = opts.getCustomRGB()
            return r, g, b, 1
        end,
        function(r, g, b)
            opts.setCustomRGB(r, g, b)
            opts.setMode("custom")
            if opts.onChange then opts.onChange() end
        end,
        opts.hasAlpha, opts.overrideSize)
    customSwatch:HookScript("OnEnter", function()
        ShowWidgetTooltip(customSwatch, "Custom Color")
    end)
    customSwatch:HookScript("OnLeave", function() HideWidgetTooltip() end)
    -- Suite-wide multiSwatch convention: clicking an INACTIVE custom swatch only selects custom mode; the picker opens on a second click while custom is already active.
    customSwatch._eabOrigClick = customSwatch:GetScript("OnClick")
    customSwatch:SetScript("OnClick", function(self)
        if opts.getMode() ~= "custom" then
            opts.setMode("custom")
            if opts.onChange then opts.onChange() end
            return
        end
        if self._eabOrigClick then self._eabOrigClick(self) end
    end)

    local defaultSwatch = BuildColorSwatch(parentFrame, baseLevel,
        function() return DEFAULT_UNTINTED_R, DEFAULT_UNTINTED_G, DEFAULT_UNTINTED_B, 1 end,
        function() end,
        opts.hasAlpha, opts.overrideSize)
    defaultSwatch:SetScript("OnClick", function()
        opts.setMode("default")
        if opts.onChange then opts.onChange() end
    end)
    defaultSwatch:SetScript("OnEnter", function()
        ShowWidgetTooltip(defaultSwatch, "Default")
    end)
    defaultSwatch:SetScript("OnLeave", function() HideWidgetTooltip() end)

    local classSwatch
    if opts.hasClassColor then
        classSwatch = BuildColorSwatch(parentFrame, baseLevel,
            function()
                local cc = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                return cc.r, cc.g, cc.b, 1
            end,
            function() end,
            opts.hasAlpha, opts.overrideSize)
        classSwatch:SetScript("OnClick", function()
            opts.setMode("class")
            if opts.onChange then opts.onChange() end
        end)
        classSwatch:SetScript("OnEnter", function()
            ShowWidgetTooltip(classSwatch, "Class Colored")
        end)
        classSwatch:SetScript("OnLeave", function() HideWidgetTooltip() end)
    end

    local function Update()
        local disabled = opts.disabled and opts.disabled()
        local mode = opts.getMode()
        if disabled then
            local a = opts.disabledAlpha or 0.3
            customSwatch:SetAlpha(a)
            defaultSwatch:SetAlpha(a)
            if classSwatch then classSwatch:SetAlpha(a) end
        else
            customSwatch:SetAlpha(mode == "custom" and 1 or 0.3)
            defaultSwatch:SetAlpha(mode == "default" and 1 or 0.3)
            if classSwatch then classSwatch:SetAlpha(mode == "class" and 1 or 0.3) end
        end
        updateCustom()
    end
    Update()
    RegisterWidgetRefresh(Update)

    return customSwatch, defaultSwatch, classSwatch, Update
end

-- Color Picker row (swatch that opens the EllesmereUI picker popup)
function WidgetFactory:ColorPicker(parent, text, yOffset, getValue, setValue, hasAlpha)
    local ROW_H = 50
    local frame = CreateFrame("Frame", nil, parent)
    PP.Size(frame, parent:GetWidth() - CONTENT_PAD * 2, ROW_H)
    PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", CONTENT_PAD, yOffset)

    RowBg(frame, parent)
    TagOptionRow(frame, parent, text)

    local label = MakeFont(frame, 14, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b)
    PP.Point(label, "LEFT", frame, "LEFT", 20, 0)
    label:SetText(EllesmereUI.L(text))

    local swatch, UpdateSwatch = BuildColorSwatch(frame, frame:GetFrameLevel() + 1, getValue, setValue, hasAlpha)
    PP.Point(swatch, "RIGHT", frame, "RIGHT", -20, 0)

    -- Public refresh so external code can update the swatch after bar changes
    frame.RefreshSwatch = UpdateSwatch
    RegisterWidgetRefresh(function() UpdateSwatch() end)

    return frame, ROW_H
end

EllesmereUI.BuildColorSwatch    = BuildColorSwatch
EllesmereUI.BuildTrioColorSwatch = BuildTrioColorSwatch
end  -- end deferred init
