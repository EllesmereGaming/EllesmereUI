if EUI_CLIENT_BLOCKED then return end 




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local S = addon.Style
local P = addon.Pixel
local Snap = P.Snap
local Unpack = S.Unpack

local EUI = EllesmereUI
local ICONS = EUI.ICONS_PATH




local G = EUI.ELLESMERE_GREEN
local DARK_BG, TEXT_DIM, TEXT_SECTION = EUI.DARK_BG, EUI.TEXT_DIM, EUI.TEXT_SECTION
local BORDER = EUI.BORDER_COLOR

S.color = {
    canvas       = { DARK_BG.r, DARK_BG.g, DARK_BG.b },

    control      = { EUI.BTN_BG_R, EUI.BTN_BG_G, EUI.BTN_BG_B, EUI.BTN_BG_A },
    controlHover = { EUI.BTN_BG_R, EUI.BTN_BG_G, EUI.BTN_BG_B, EUI.BTN_BG_HA },
    controlDown  = { 0, 0, 0, 0.30 },
    controlBorder      = { 1, 1, 1, EUI.BTN_BRD_A },
    controlBorderHover = { 1, 1, 1, EUI.BTN_BRD_HA },


    inset        = { 0, 0, 0, 0.50 },
    insetDeep    = { 0, 0, 0, 0.60 },

    border       = { BORDER.r, BORDER.g, BORDER.b, BORDER.a },
    borderBright = { 1, 1, 1, EUI.DD_BRD_A },

    text         = { EUI.TEXT_WHITE.r, EUI.TEXT_WHITE.g, EUI.TEXT_WHITE.b, 1 },
    textMuted    = { TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a },
    textFaint    = { TEXT_SECTION.r, TEXT_SECTION.g, TEXT_SECTION.b, TEXT_SECTION.a },

    rowOdd       = { 0, 0, 0, EUI.ROW_BG_ODD },
    rowEven      = { 0, 0, 0, EUI.ROW_BG_EVEN },
    rowHover     = { 1, 1, 1, EUI.DD_ITEM_HL_A },
    rowStripe    = { 0, 0, 0, EUI.ROW_BG_ODD },


    accent       = { G.r, G.g, G.b },
    accentDim    = { G.r * 0.7, G.g * 0.7, G.b * 0.7 },
    accentPale   = { G.r + (1 - G.r) * 0.4, G.g + (1 - G.g) * 0.4, G.b + (1 - G.b) * 0.4 },


    good         = { 0.400, 0.780, 0.541 },
    bad          = { 1.000, 0.349, 0.349 },
}
local color = S.color

color.check        = color.accent
color.surface      = color.control
color.surfaceHover = color.controlHover


color.canvasTop    = color.canvas
color.canvasMid    = color.canvas
color.canvasBottom = color.canvas


color.band         = { 0, 0, 0, 0.35 }
color.rail         = { 0, 0, 0, 0.25 }
color.railText     = color.textFaint
color.card         = { EUI.BTN_BG_R, EUI.BTN_BG_G, EUI.BTN_BG_B }
color.cardRaised   = { EUI.DD_BG_R, EUI.DD_BG_G, EUI.DD_BG_B }
color.cardLift     = { 1, 1, 1, 0.03 }


color.rule         = { 1, 1, 1, 0.06 }
color.edge         = { 1, 1, 1, 0.10 }
color.edgeBright   = { 1, 1, 1, 0.15 }
color.steel        = { 1, 1, 1, EUI.BTN_BRD_A }
color.steelBright  = { 1, 1, 1, EUI.BTN_BRD_HA }

color.danger       = { 0.769, 0.282, 0.353 }
color.dangerEdge   = { 0.420, 0.200, 0.251 }
color.dangerText   = { 0.878, 0.541, 0.588 }
color.urgent       = { 0.878, 0.439, 0.541 }
color.warn         = { 0.851, 0.627, 0.306 }


color.neutral600   = { EUI.TG_KNOB_OFF_R, EUI.TG_KNOB_OFF_G, EUI.TG_KNOB_OFF_B, EUI.TG_KNOB_OFF_A }
color.neutral700   = { EUI.TG_OFF_R, EUI.TG_OFF_G, EUI.TG_OFF_B, EUI.TG_OFF_A }
color.knob         = { EUI.TG_KNOB_ON_R, EUI.TG_KNOB_ON_G, EUI.TG_KNOB_ON_B, EUI.TG_KNOB_ON_A }


color.windowEdge   = { 1, 1, 1, EUI.RESKIN.BRD_ALPHA }
color.headerTop    = { 0, 0, 0, 0.50 }
color.headerBottom = color.headerTop






local accentPainters = setmetatable({}, { __mode = "k" })
local function OnAccent(widget, paint) accentPainters[widget] = paint end


local VIEWS = { "council", "voter", "session", "options", "queue", "queueBags" }

local function AccentChanged(r, g, b)
    local a, dim, pale = color.accent, color.accentDim, color.accentPale
    a[1], a[2], a[3] = r, g, b
    dim[1], dim[2], dim[3] = r * 0.7, g * 0.7, b * 0.7
    pale[1], pale[2], pale[3] = r + (1 - r) * 0.4, g + (1 - g) * 0.4, b + (1 - b) * 0.4
    for widget, paint in pairs(accentPainters) do pcall(paint, widget) end
    local callbacks = addon.Callbacks
    if callbacks and callbacks.Invalidate then
        for i = 1, #VIEWS do callbacks:Invalidate(VIEWS[i]) end
    end
end
EUI.RegAccent({ type = "callback", fn = AccentChanged })




local size = {
    PAD       = 15,
    ROW_PAD   = 10,
    GAP       = 9,
    ITEM_GAP  = 3,
    SECTION   = 11,

    HEADER_H  = 35,
    CLOSE     = 20,

    CTRL_H    = 22,
    BTN_H     = 27,
    BTN_H_SM  = 22,
    BTN_W     = 135,
    BTN_PAD   = 11,
    BTN_PAD_FOOTER = 22,
    BTN_W_SM  = 22,

    COUNT_H   = 20,

    ICON      = 44,
    ICON_SM   = 22,

    FOOTER_H  = 48,

    SET_ROW_H = 44,
    LIST_ROW  = 34,
    GROUP_ROW = 40,


    SCROLLBAR_W   = 4,
    SCROLLBAR_GAP = 4,

    TITLE_GAP = 0,
    TAG_GAP   = 9,
}

size.VPAD     = 5
size.ROW_H    = size.CTRL_H + size.VPAD * 2
size.ROW_H_SM = size.BTN_H_SM + size.VPAD
size.HEADER_LOGO_PAD = 0
size.HEADER_LOGO_H = size.HEADER_H

S.size = size


S.radius = { CHIP = 0, SM = 0, CTRL = 0, MD = 0, LG = 0, WINDOW = 0 }
S.rounded = false






local FONT_KEY = "lootCouncil"
local GLYPH_LOCALES = {
    { "korean", "koKR" }, { "simplifiedchinese", "zhCN" }, { "traditionalchinese", "zhTW" },
}

local function FontMembers(path, height, flags)
    local cyrillic = EUI.FONT_CYRILLIC[EUI.GetFontName(FONT_KEY) or ""]
        or path == EUI.LOCALE_FONT_FALLBACK
    local members = {
        { alphabet = "roman", file = path, height = height, flags = flags },
        { alphabet = "russian", file = cyrillic and path or EUI.LocaleGlyphFont("ruRU"),
          height = height, flags = flags },
    }
    for _, pair in ipairs(GLYPH_LOCALES) do
        members[#members + 1] = { alphabet = pair[1], file = EUI.LocaleGlyphFont(pair[2]),
            height = height, flags = flags }
    end
    return members
end

local fontDefinitions = setmetatable({}, { __mode = "k" })

local function MakeFont(name, fontSize, fontColor)
    local path = EUI.GetFontPath(FONT_KEY)
    local flags = EUI.GetFontOutlineFlag(FONT_KEY) or ""
    local f
    if type(CreateFontFamily) == "function" then
        local ok, family = pcall(CreateFontFamily, name, FontMembers(path, fontSize, flags))
        if ok then f = family end
    end
    if not f then
        f = CreateFont(name)
        f:SetFont(path, fontSize, flags)
    end
    f:SetTextColor(Unpack(fontColor))

    if EUI.GetFontUseShadow(FONT_KEY) then
        f:SetShadowColor(0, 0, 0, 1)
        f:SetShadowOffset(1, -1)
    else
        f:SetShadowColor(0, 0, 0, 0)
        f:SetShadowOffset(0, 0)
    end
    fontDefinitions[f] = { name = name, color = fontColor }
    return f
end




S.fontTitle        = MakeFont("EllesmereUISimpleLootCouncilFontTitle",         20.6, color.text)
S.fontHeading       = MakeFont("EllesmereUISimpleLootCouncilFontHeading",       11,   color.textFaint)
S.fontMicro         = MakeFont("EllesmereUISimpleLootCouncilFontMicro",         10,   color.textFaint)
S.fontRaidTeamHeader = MakeFont("EllesmereUISimpleLootCouncilFontRaidTeamHeader", 14, color.textFaint)
S.fontBody          = MakeFont("EllesmereUISimpleLootCouncilFontBody",          12,   color.text)
S.fontSetting       = MakeFont("EllesmereUISimpleLootCouncilFontSetting",       13,   color.text)
S.fontInput         = MakeFont("EllesmereUISimpleLootCouncilFontInput",         12,   color.text)
S.fontButton        = MakeFont("EllesmereUISimpleLootCouncilFontButton",        12,   color.text)
S.fontSmall         = MakeFont("EllesmereUISimpleLootCouncilFontSmall",         11,   color.textMuted)
S.fontBadge         = MakeFont("EllesmereUISimpleLootCouncilFontBadge",         14,   color.textMuted)
S.fontTag           = MakeFont("EllesmereUISimpleLootCouncilFontTag",           15,   color.textFaint)
S.fontHint          = MakeFont("EllesmereUISimpleLootCouncilFontHint",          11,   color.textFaint)

S.fontNotice        = MakeFont("EllesmereUISimpleLootCouncilFontNotice",        16,   color.bad)
S.fontNum          = MakeFont("EllesmereUISimpleLootCouncilFontNum",           12,   color.text)
S.fontNumSmall      = MakeFont("EllesmereUISimpleLootCouncilFontNumSmall",      11,   color.textMuted)
S.fontNumLarge      = MakeFont("EllesmereUISimpleLootCouncilFontNumLarge",      14,   color.text)
S.fontNumHint       = MakeFont("EllesmereUISimpleLootCouncilFontNumHint",       11,   color.textMuted)
S.fontNumHuge       = MakeFont("EllesmereUISimpleLootCouncilFontNumHuge",       18,   color.text)






S.logo      = { loaded = true }
S.logoPride = { loaded = true }


function S.GamepadUI() return EUI.PadGamepadUI() end





function S.Fill(frame, c, alpha, layer)
    local r, g, b, a = Unpack(c, alpha)
    local t = EUI.SolidTex(frame, layer or "BACKGROUND", r, g, b, a)
    t:SetAllPoints(frame)
    P.Crisp(t)
    return t
end

function S.CanvasFill(frame, c, alpha, layer)
    return S.Fill(frame, c, alpha, layer), nil
end

function S.RoundFill(frame, c, _, layer, subLayer)
    local t = S.Fill(frame, c, nil, layer)
    if subLayer then t:SetDrawLayer(layer or "BACKGROUND", subLayer) end
    return t
end


local borders = setmetatable({}, { __mode = "k" })

function S.Border(frame, c, layer, thickness)
    local existing = borders[frame]
    if existing then
        if c then existing:SetColor(c) end
        if thickness then existing:SetThickness(thickness) end
        return existing
    end
    local r, g, b, a = Unpack(c or color.border)
    local container = EUI.PP.CreateBorder(frame, r, g, b, a, thickness or 1, layer or "BORDER")
    local handle = {
        SetColor = function(_, nc) EUI.PP.SetBorderColor(frame, Unpack(nc)) end,
        SetShown = function(_, on)
            if on then EUI.PP.ShowBorder(frame) else EUI.PP.HideBorder(frame) end
        end,
        SetThickness = function(_, n) EUI.PP.SetBorderSize(frame, n or 1) end,
        Frame = container,
    }
    borders[frame] = handle
    return handle
end

function S.RoundBorder(frame, c, layer)
    return S.Border(frame, c, layer)
end

function S.Panel(frame, c, alpha, _, borderColor, layer)
    local fill = S.Fill(frame, c, alpha, layer)
    local border = borderColor and S.Border(frame, borderColor, "BORDER") or nil
    return fill, nil, border
end


function S.Inset(parent, deep)
    local f = CreateFrame("Frame", nil, parent)
    S.Fill(f, deep and color.insetDeep or color.inset)
    f.border = S.Border(f, color.borderBright)
    return f
end





local function IconGlyph(button, file, extent)
    local tex = button:CreateTexture(nil, "OVERLAY")
    P.Size(tex, extent, extent)
    tex:SetPoint("CENTER")
    tex:SetTexture(ICONS .. file)
    return { SetColor = function(_, c) tex:SetVertexColor(Unpack(c)) end }
end


local function PlusGlyph(button, extent)
    local bars = {}
    local thickness = math.max(P.Hairline(), extent / 9)
    for i = 1, 2 do
        local bar = button:CreateTexture(nil, "OVERLAY")
        bar:SetColorTexture(1, 1, 1, 1)
        if i == 1 then P.Size(bar, extent, thickness) else P.Size(bar, thickness, extent) end
        bar:SetPoint("CENTER")
        bars[i] = bar
    end
    return {
        SetColor = function(_, c)
            for i = 1, #bars do bars[i]:SetVertexColor(Unpack(c)) end
        end,
    }
end






local INK      = { 1, 1, 1, EUI.BTN_TXT_A }
local INK_HOVER = { 1, 1, 1, EUI.BTN_TXT_HA }



function S.Button(parent, text, opts)
    opts = opts or {}

    local b = CreateFrame("Button", nil, parent)
    local h = opts.height or (opts.compact and size.BTN_H_SM or size.BTN_H)
    local w = opts.width or size.BTN_W
    local font = opts.font or S.fontBody

    local _, fontHeight = font:GetFont()
    fontHeight = tonumber(fontHeight) or 12
    h = math.max(h, math.ceil(fontHeight * 1.6))
    w = math.max(w, h)
    P.Size(b, w, h)

    local bg, border, label = EUI.MakeStyledButton(b, "", fontHeight, EUI.WB_COLOURS)
    label:SetFontObject(font)
    label:SetAlpha(1)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    label:SetMaxLines(1)

    local bare = opts.glyph == "close"
    if bare then
        bg:Hide()
        border:SetColor(0, 0, 0, 0)
    end

    local fill     = { EUI.BTN_BG_R, EUI.BTN_BG_G, EUI.BTN_BG_B, EUI.BTN_BG_A }
    local fillOver = { EUI.BTN_BG_R, EUI.BTN_BG_G, EUI.BTN_BG_B, EUI.BTN_BG_HA }
    local down     = color.controlDown

    local edge, ink, brightEdge, inkOver
    if opts.danger then
        edge, ink, brightEdge, inkOver = color.dangerEdge, color.dangerText, color.danger, color.dangerText
    elseif opts.primary then
        edge, ink, brightEdge, inkOver = color.accent, color.accent, color.accent, color.accent
    elseif bare then
        edge, ink, brightEdge, inkOver = color.border, { 1, 1, 1, 0.7 }, color.border, { 1, 1, 1, 0.9 }
    else
        edge, ink = color.controlBorder, INK
        brightEdge, inkOver = color.controlBorderHover, INK_HOVER
    end
    local defaultEdge, defaultInk, defaultBright, defaultInkOver = edge, ink, brightEdge, inkOver

    local fixedWidth = opts.fixedWidth or opts.glyph or w <= 24
    local pad = opts.labelPad or (w <= 24 and 1 or size.BTN_PAD)

    local function placeLabel(dy)
        label:SetPoint("LEFT", b, "LEFT", Snap(pad), dy)
        label:SetPoint("RIGHT", b, "RIGHT", Snap(-pad), dy)
    end
    label:ClearAllPoints()
    placeLabel(0)
    label:SetText(text)
    b.Label = label


    local basePad, squeeze = pad, nil
    local function fitLabel()
        if fixedWidth then return end
        local current = label:GetText()
        if not current or current == "" then return end
        local textWidth = label:GetUnboundedStringWidth()
        if type(textWidth) ~= "number" or textWidth <= 0 then return end
        b.slcNatural = math.max(h, Snap(math.ceil(textWidth)) + 2 * Snap(basePad))
        if squeeze then
            P.Size(b, squeeze.w, squeeze.h)
        else
            P.Size(b, b.slcNatural, nil)
        end
    end
    fitLabel()
    P.AfterLayout(fitLabel)
    P.OnRescale(fitLabel)


    if opts.share and not fixedWidth then
        b.slcShare = true
        local probe = S.Label(b, opts.font or S.fontBody, "LEFT")
        probe:Hide()
        local function lines(words, inner)
            local count, line = 1, nil
            for _, word in ipairs(words) do
                local try = line and (line .. " " .. word) or word
                probe:SetText(try)
                if not line or probe:GetUnboundedStringWidth() <= inner then
                    line = try
                else
                    count, line = count + 1, word
                end
            end
            return count
        end
        function b:MinSqueezeWidth()
            local current = label:GetText() or ""
            if b.slcMinFor == current then return b.slcMin end
            local words = {}
            for word in current:gmatch("%S+") do words[#words + 1] = word end
            local longest = 0
            for _, word in ipairs(words) do
                probe:SetText(word)
                longest = math.max(longest, math.ceil(probe:GetUnboundedStringWidth() or 0))
            end
            probe:SetText(current)
            local inner = math.max(longest, math.ceil((probe:GetUnboundedStringWidth() or 0) / 2))
            local limit = inner + math.ceil((probe:GetUnboundedStringWidth() or 0))
            while #words > 1 and inner < limit and lines(words, inner) > 2 do inner = inner + 2 end
            b.slcMinFor = current
            b.slcMin = math.min(b.slcNatural or inner, inner + 2 * 8 + 2)
            return b.slcMin
        end
        function b:SetSqueeze(width)
            local same = (width == nil and squeeze == nil) or (squeeze and squeeze.w == width)
            if same then return end
            squeeze = width and { w = width, h = math.ceil(fontHeight * 2.5) + 8 } or nil
            pad = squeeze and 8 or basePad
            placeLabel(0)
            label:SetWordWrap(squeeze ~= nil)
            label:SetMaxLines(squeeze and 2 or 1)
            if squeeze then P.Size(b, squeeze.w, squeeze.h) else P.Size(b, b.slcNatural or w, h) end
        end
    end

    local glyph
    if opts.glyph == "close" then
        label:Hide()
        glyph = IconGlyph(b, "eui-close.png", 12)
    elseif opts.glyph == "plus" then
        label:Hide()
        glyph = PlusGlyph(b, math.floor(math.min(w, h) * 0.46))
    elseif opts.glyph == "chat" then
        label:Hide()
        glyph = IconGlyph(b, "eui-edit.png", math.floor(math.min(w, h) * 0.6))
    end
    b.Glyph = glyph

    local function setInk(c)
        label:SetTextColor(Unpack(c))
        if glyph then glyph:SetColor(c) end
    end

    local enabled, selected, hovered = true, false, false

    local function paintFill(c)
        if not bare then bg:SetColorTexture(Unpack(c)) end
    end
    local function paintEdge(c)
        if not bare then border:SetColor(Unpack(c)) end
    end

    local function rest()
        if selected then
            paintFill({ edge[1], edge[2], edge[3], 0.18 })
            paintEdge(brightEdge)
        else
            paintFill(fill)
            paintEdge(edge)
        end
        setInk(ink)
    end
    local function over()
        paintFill(selected and { edge[1], edge[2], edge[3], 0.24 } or fillOver)
        paintEdge(brightEdge)
        setInk(inkOver)
    end
    rest()

    b:SetScript("OnEnter", function(self)
        hovered = true
        if enabled then over() end
        if self.slcHoverIn then self.slcHoverIn(self) end
    end)
    b:SetScript("OnLeave", function(self)
        hovered = false
        if enabled then rest() end
        if self.slcHoverOut then self.slcHoverOut(self) end
    end)
    b:SetScript("OnMouseDown", function()
        if not enabled then return end
        paintFill(down)
        label:ClearAllPoints()
        placeLabel(-1)
    end)
    b:SetScript("OnMouseUp", function(self)
        if not enabled then return end
        if self:IsMouseOver() then over() else rest() end
        label:ClearAllPoints()
        placeLabel(0)
    end)

    function b:SetLabel(t)
        label:SetText(t)
        fitLabel()
    end

    function b:SetSelected(on)
        selected = on and true or false
        if enabled then if hovered then over() else rest() end end
    end


    function b:SetColour(c, inkColour)
        if c then
            edge, brightEdge = c, c
            ink = inkColour or color.text
            inkOver = ink
        else
            edge, ink, brightEdge, inkOver = defaultEdge, defaultInk, defaultBright, defaultInkOver
        end
        if enabled then if hovered then over() else rest() end end
    end

    function b:SetEnabled(on)
        enabled = on and true or false
        if enabled then
            if hovered then over() else rest() end
            b:EnableMouse(true)
        else
            paintFill({ 0, 0, 0, 0.20 })
            setInk(color.textFaint)
            paintEdge(color.border)
            b:EnableMouse(b.slcReason ~= nil)
        end
    end


    b:HookScript("OnEnter", function(self)
        if enabled or not self.slcReason then return end
        EUI.ShowWidgetTooltip(self, self.slcReason, { force = true })
    end)
    b:HookScript("OnLeave", function(self)
        if not self.slcReason then return end
        EUI.HideWidgetTooltip()
    end)

    function b:SetDisabledReason(reason)
        b.slcReason = reason
        if not enabled then b:EnableMouse(reason ~= nil) end
    end


    local rawSetScript = b.SetScript
    function b:SetScript(handler, fn)
        if handler == "OnClick" and fn then
            return rawSetScript(self, handler, function(...)
                if not enabled then return end
                return fn(...)
            end)
        end
        return rawSetScript(self, handler, fn)
    end
    b:SetScript("OnClick", nil)

    OnAccent(b, function()
        if enabled then if hovered then over() else rest() end end
    end)
    return b
end

function S.EditBox(parent, width, height)
    local holder = S.Inset(parent)
    P.Size(holder, width, height or size.CTRL_H)

    local e = CreateFrame("EditBox", nil, holder)
    P.Point(e, "TOPLEFT", 6, 0)
    P.Point(e, "BOTTOMRIGHT", -6, 0)
    e:SetFontObject(S.fontInput)
    e:SetAutoFocus(false)
    e:SetTextInsets(0, 0, 0, 0)

    e:HookScript("OnEditFocusGained", function() holder.border:SetColor(color.accent) end)
    e:HookScript("OnEditFocusLost", function() holder.border:SetColor(color.borderBright) end)
    e:HookScript("OnEnter", function() holder.border:SetColor(color.steelBright) end)
    e:HookScript("OnLeave", function()
        holder.border:SetColor(e:HasFocus() and color.accent or color.borderBright)
    end)
    OnAccent(e, function() if e:HasFocus() then holder.border:SetColor(color.accent) end end)

    holder.EditBox = e
    return holder, e
end



local SWITCH_W, SWITCH_H, KNOB_PAD = 40, 20, 2
local SWITCH_ANIM = 0.075

local function Lerp(a, b, t) return a * (1 - t) + b * t end

function S.Switch(parent, onToggle)
    local b = CreateFrame("Button", nil, parent)
    P.Size(b, SWITCH_W, SWITCH_H)

    local track = S.Fill(b, color.neutral700)
    local knob = b:CreateTexture(nil, "ARTWORK")
    P.Crisp(knob)

    local pad      = P.Snap(KNOB_PAD)
    local knobSize = P.Snap(SWITCH_H) - pad * 2
    local restOn   = P.Snap(SWITCH_W) - pad - knobSize

    local function PlaceKnob(x)
        knob:ClearAllPoints()
        knob:SetPoint("TOPLEFT", b, "TOPLEFT", x, -pad)
        knob:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", x, pad)
        knob:SetWidth(knobSize)
    end

    local function OnOffset()
        local width = b:GetWidth()
        if width and width > 0 then return width - pad - knobSize end
        return restOn
    end

    local checked, enabled = false, true
    local progress, target = 0, 0

    local function Paint(p)
        local x
        if p <= 0 then x = pad
        elseif p >= 1 then x = OnOffset()
        else x = P.Snap(Lerp(pad, OnOffset(), p), b) end
        PlaceKnob(x)

        local off, on = color.neutral700, color.accent
        track:SetColorTexture(Lerp(off[1], on[1], p), Lerp(off[2], on[2], p),
            Lerp(off[3], on[3], p), Lerp(off[4], EUI.TG_ON_A, p))
        local ko, kn = color.neutral600, color.knob
        knob:SetColorTexture(Lerp(ko[1], kn[1], p), Lerp(ko[2], kn[2], p),
            Lerp(ko[3], kn[3], p), Lerp(ko[4], kn[4], p))
    end

    local function Step(self, elapsed)
        local direction = target > progress and 1 or -1
        progress = progress + direction * (elapsed / SWITCH_ANIM)
        if (direction > 0 and progress >= target)
            or (direction < 0 and progress <= target) then
            progress = target
            self:SetScript("OnUpdate", nil)
        end
        Paint(progress)
    end

    function b:SetChecked(on)
        checked = on and true or false
        progress = checked and 1 or 0
        target = progress
        b:SetScript("OnUpdate", nil)
        Paint(progress)
    end
    function b:GetChecked() return checked end

    function b:SetEnabled(on)
        enabled = on and true or false
        b:EnableMouse(enabled)
        Paint(progress)
    end

    local function Toggle()
        if not enabled then return end
        checked = not checked
        target = checked and 1 or 0
        b:SetScript("OnUpdate", Step)
        if onToggle then onToggle(checked) end
    end
    b.Toggle = Toggle

    b:SetScript("OnEnter", function(self)
        if self.slcHoverIn then self.slcHoverIn(self) end
    end)
    b:SetScript("OnLeave", function(self)
        if self.slcHoverOut then self.slcHoverOut(self) end
    end)
    b:SetScript("OnClick", Toggle)

    OnAccent(b, function() Paint(progress) end)
    Paint(0)
    return b
end


function S.Chip(parent, text, c, opts)
    opts = opts or {}
    local chip = CreateFrame("Frame", nil, parent)

    local label = S.Label(chip, opts.font or S.fontMicro, "CENTER")
    label:SetText(text or "")
    P.Point(label, "CENTER", chip, "CENTER", 0, 0)

    local fill = chip:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(chip)
    P.Crisp(fill)
    local border = S.Border(chip, c or color.textMuted, "BORDER")

    function chip:SetChipColor(nc)
        nc = nc or color.textMuted
        fill:SetColorTexture(Unpack(nc, 0.12))
        border:SetColor(nc)
        label:SetTextColor(Unpack(opts.textColor or nc))
    end

    function chip:SetText(value)
        label:SetText(value or "")
        chip:Fit()
    end


    function chip:Fit()
        local padding = opts.padding or 7
        if opts.maxWidth then label:SetWidth(0) end
        local desired = math.max(opts.minWidth or 0,
            label:GetStringWidth() + padding * 2)
        local width = opts.maxWidth and math.min(opts.maxWidth, desired) or desired
        if opts.maxWidth then
            label:SetWidth(math.max(1, width - padding * 2))
        end
        P.Size(chip, width, opts.height or 17)
    end

    chip:SetChipColor(c)
    chip:Fit()
    chip.Label = label
    return chip
end


function S.Checkbox(parent, boxSize, onToggle)
    local b = CreateFrame("Button", nil, parent)
    P.Size(b, boxSize or size.CTRL_H, boxSize or size.CTRL_H)

    local box = { EUI.CB_BOX_R, EUI.CB_BOX_G, EUI.CB_BOX_B, 1 }
    local bg = S.Fill(b, box)
    local border = S.Border(b, color.border)

    local fill = b:CreateTexture(nil, "ARTWORK")
    P.Point(fill, "TOPLEFT", 3, -3)
    P.Point(fill, "BOTTOMRIGHT", -3, 3)
    P.Crisp(fill)
    fill:Hide()

    local checked, hovered = false, false
    local function Paint()
        fill:SetColorTexture(Unpack(color.accent))
        fill:SetShown(checked)
        if checked then
            bg:SetColorTexture(Unpack(box))
            border:SetColor({ color.accent[1], color.accent[2], color.accent[3], EUI.CB_ACT_BRD_A })
        else
            local a = hovered and 1 or 0.8
            bg:SetColorTexture(box[1], box[2], box[3], a)
            border:SetColor({ BORDER.r, BORDER.g, BORDER.b, EUI.CB_BRD_A * a })
        end
    end

    function b:SetChecked(on)
        checked = on and true or false
        Paint()
    end
    function b:GetChecked() return checked end

    b:SetScript("OnEnter", function(self)
        hovered = true
        Paint()
        if self.slcHoverIn then self.slcHoverIn(self) end
    end)
    b:SetScript("OnLeave", function(self)
        hovered = false
        Paint()
        if self.slcHoverOut then self.slcHoverOut(self) end
    end)

    if onToggle then
        b:SetScript("OnClick", function(self)
            local value = not self:GetChecked()
            self:SetChecked(value)
            onToggle(value)
        end)
    end

    OnAccent(b, Paint)
    Paint()
    return b
end


local function SizedFont(fontObject, pointSize)
    local definition = fontDefinitions[fontObject]
    if not definition then return nil end
    definition.sizes = definition.sizes or {}
    local sized = definition.sizes[pointSize]
    if not sized then
        sized = MakeFont(definition.name .. "Size" .. tostring(pointSize), pointSize, definition.color)
        definition.sizes[pointSize] = sized
    end
    return sized
end



function S.Heading(parent, x, width, y, text, opts)
    opts = opts or {}

    local fontObject = opts.font or S.fontMicro
    local face, baseSize, flags = fontObject:GetFont()
    local pointSize = opts.fontSize or baseSize

    local f = CreateFrame("Frame", nil, parent)
    local H = 20
    if type(pointSize) == "number" then
        H = math.max(H, math.ceil(pointSize * 1.7))
    end
    P.Size(f, width, H)
    P.Point(f, "TOPLEFT", parent, "TOPLEFT", x, y)

    local anchor, anchorPoint, anchorGap = f, "LEFT", 0

    if opts.tick then
        local tick = f:CreateTexture(nil, "ARTWORK")
        P.Size(tick, 2, 11)
        tick:SetColorTexture(Unpack(color.accent))
        P.Crisp(tick)
        P.Point(tick, "LEFT", f, "LEFT", 0, 0)
        f.Tick = tick
        anchor, anchorPoint, anchorGap = tick, "RIGHT", 9
        OnAccent(tick, function() tick:SetColorTexture(Unpack(color.accent)) end)
    end

    local fs = S.Label(f, fontObject, "LEFT")
    if opts.fontSize and face then
        local sized = SizedFont(fontObject, opts.fontSize)
        if sized then fs:SetFontObject(sized) else fs:SetFont(face, opts.fontSize, flags) end
    end
    if opts.color then
        fs:SetTextColor(Unpack(opts.color))
    elseif opts.fontSize and face then
        fs:SetTextColor(fontObject:GetTextColor())
    end
    fs:SetText(text and addon.Locale.Upper(text) or "")
    fs:SetPoint("LEFT", anchor, anchorPoint, Snap(anchorGap), 0)
    f.Text = fs

    local right
    if opts.right ~= nil then
        right = S.Label(f, opts.rightFont or S.fontSmall, "RIGHT")
        right:SetText(opts.right)
        P.Point(right, "RIGHT", f, "RIGHT", 0, 0)
        f.Right = right
    end

    local function boundText()
        local actualWidth = f:GetWidth()
        if actualWidth <= 0 then actualWidth = width end
        local left = opts.tick and 11 or 0
        local reserved = right and right:GetUnboundedStringWidth() + size.GAP * 2 or size.GAP
        local available = math.max(0, actualWidth - left - reserved)
        local used = math.min(available, fs:GetUnboundedStringWidth())
        fs:SetPoint("RIGHT", f, "LEFT", Snap(left + used), 0)
    end
    if not opts.fullText then
        boundText()
        P.AfterLayout(boundText)
        P.OnRescale(boundText)
        f:HookScript("OnSizeChanged", boundText)
        hooksecurefunc(fs, "SetText", boundText)
    end

    local rule = S.FadeRule(f)
    rule:SetPoint("LEFT", fs, "RIGHT", Snap(size.GAP), 0)
    if right then
        rule:SetPoint("RIGHT", right, "LEFT", Snap(-size.GAP), 0)
    else
        rule:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    end

    function f:SetRight(value)
        if right then right:SetText(value or "") end
        boundText()
    end

    f.Rule = rule
    return f, H
end



function S.FooterBar(window)
    local bar = CreateFrame("Frame", nil, window)
    bar:SetFrameLevel(window:GetFrameLevel() + 2)
    P.Point(bar, "BOTTOMLEFT", window, "BOTTOMLEFT", 0, 0)
    P.Point(bar, "BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 0)
    P.Size(bar, nil, size.FOOTER_H)

    S.Fill(bar, color.band)
    local rule = S.FadeRule(bar)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")

    bar.slcLeft, bar.slcRight = size.PAD, size.PAD
    local leftRun, rightRun = {}, {}
    local leftText

    local function Place(run, side, sign, start)
        local offset = start
        for _, button in ipairs(run) do
            if button:IsShown() then
                button:ClearAllPoints()
                P.Point(button, side, bar, side, sign * offset, 0)
                offset = offset + button:GetWidth() + size.GAP
            end
        end
        return offset
    end

    local function RunWidth(run)
        local total, n = 0, 0
        for _, button in ipairs(run) do
            if button:IsShown() then
                n = n + 1
                total = total + (button.slcNatural or button:GetWidth())
            end
        end
        return total + math.max(n - 1, 0) * size.GAP, n
    end

    local function Share(run, avail)
        local pool, budget = {}, avail
        for _, button in ipairs(run) do
            if button:IsShown() then
                budget = budget - size.GAP
                if button.SetSqueeze then
                    pool[#pool + 1] = button
                else
                    budget = budget - button:GetWidth()
                end
            end
        end
        budget = budget + size.GAP
        local natural = 0
        for _, button in ipairs(pool) do natural = natural + (button.slcNatural or 0) end
        if natural <= budget then
            for _, button in ipairs(pool) do button:SetSqueeze(nil) end
            return
        end
        local width, minTotal, wants = {}, 0, {}
        for _, button in ipairs(pool) do
            width[button] = button:MinSqueezeWidth()
            minTotal = minTotal + width[button]
            wants[button] = button.slcNatural or width[button]
        end
        if minTotal > budget then
            local scale = budget / minTotal
            for _, button in ipairs(pool) do width[button] = math.floor(width[button] * scale) end
        else
            local extra = budget - minTotal
            table.sort(pool, function(a, c)
                return (wants[a] - width[a]) < (wants[c] - width[c])
            end)
            for i, button in ipairs(pool) do
                local give = math.min(wants[button] - width[button],
                    math.floor(extra / (#pool - i + 1)))
                width[button] = width[button] + give
                extra = extra - give
            end
        end
        for _, button in ipairs(pool) do button:SetSqueeze(width[button]) end
    end

    local reflowing
    function bar:Reflow()
        if reflowing then return end
        reflowing = true
        local windowW = window:GetWidth()
        if type(windowW) == "number" and windowW > 0 then
            local avail = windowW - 2 * size.PAD
            Share(leftRun, avail - RunWidth(rightRun) - size.GAP)
            Share(rightRun, avail - RunWidth(leftRun) - size.GAP)
        end
        bar.slcLeft = Place(leftRun, "LEFT", 1, size.PAD)
        bar.slcRight = Place(rightRun, "RIGHT", -1, size.PAD)
        reflowing = false
        if leftText then
            leftText:ClearAllPoints()
            P.Point(leftText, "LEFT", bar, "LEFT", bar.slcLeft, 0)
            P.Point(leftText, "RIGHT", bar, "RIGHT", -bar.slcRight, 0)
        end
    end

    function bar:Add(button, rightAlign)
        table.insert(rightAlign and rightRun or leftRun, button)
        button:HookScript("OnSizeChanged", function() bar:Reflow() end)
        bar:Reflow()
        return button
    end

    function bar:AddText(fontObject)
        local fs = S.Label(bar, fontObject or S.fontSmall, "LEFT")
        leftText = fs
        P.Point(fs, "LEFT", bar, "LEFT", bar.slcLeft, 0)
        return fs
    end

    return bar
end


function S.EmptyState(parent, title, body, width)
    local f = CreateFrame("Frame", nil, parent)
    P.Size(f, width, 150)
    S.Fill(f, color.cardLift)
    S.Border(f, color.edge, "BORDER")

    local box = CreateFrame("Frame", nil, f)
    P.Size(box, 38, 38)
    P.Point(box, "TOP", f, "TOP", 0, -30)
    S.Fill(box, color.rail)
    S.Border(box, color.edge, "BORDER")

    local inner = CreateFrame("Frame", nil, box)
    P.Size(inner, 16, 12)
    P.Point(inner, "CENTER", box, "CENTER", 0, 0)
    S.Border(inner, color.neutral700, "ARTWORK")

    local heading = S.Label(f, S.fontButton, "CENTER")
    heading:SetText(title or "")
    P.Point(heading, "TOP", box, "BOTTOM", 0, -9)

    local copy = S.Label(f, S.fontSmall, "CENTER", "wrap")
    copy:SetText(body or "")
    P.Size(copy, math.min(250, width - 44), 0)
    P.Point(copy, "TOP", heading, "BOTTOM", 0, -6)

    P.AfterLayout(function()
        P.Size(f, nil, 30 + 38 + 9 + 18 + 6
            + math.ceil(copy:GetStringHeight()) + 30)
    end)

    f.Title = heading
    f.Body = copy
    return f
end


function S.FadeRule(parent)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(Unpack(color.rule))
    P.Crisp(rule)
    local function thickness() rule:SetHeight(P.Hairline()) end
    thickness()
    P.OnRescale(thickness)
    return rule
end





function S.ProgressBar(parent, height)
    local bar = CreateFrame("Frame", nil, parent)
    P.Size(bar, nil, height or 4)

    S.Fill(bar, color.insetDeep)

    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(Unpack(color.accent))
    P.Crisp(fill)
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    bar.Fill = fill


    function bar:SetProgress(fraction, neutral)
        fraction = math.max(0, math.min(1, fraction or 0))
        local width = self:GetWidth() or 0
        if width <= 0 then
            fill:Hide()
            return
        end
        if fraction <= 0 then
            if neutral then
                fill:Hide()
                return
            end
            fill:Show()
            fill:SetWidth(width)
            fill:SetColorTexture(Unpack(color.bad))
            return
        end
        fill:Show()
        fill:SetWidth(width * fraction)
        if neutral or fraction > 0.33 then
            fill:SetColorTexture(Unpack(color.accent))
        else
            fill:SetColorTexture(Unpack(color.warn))
        end
    end

    return bar
end







function S.ScrollBar(parent)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(size.SCROLLBAR_W)

    S.Fill(bar, { 1, 1, 1, 0.02 })
    local thumb = bar:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(1, 1, 1, 0.27)
    thumb:SetSize(size.SCROLLBAR_W, 36)
    bar:SetThumbTexture(thumb)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:Hide()
    bar:EnableMouseWheel(true)
    return bar
end



local function BarFacade(scroll, maximum, scrollTo)
    local listeners = {}
    local facade = {}
    function facade:SetValue(v) scrollTo(v) end
    function facade:GetValue() return scroll:GetVerticalScroll() or 0 end
    function facade:GetMinMaxValues() return 0, maximum() end
    function facade:SetMinMaxValues() end
    function facade:HookScript(handler, fn)
        if handler == "OnValueChanged" then listeners[#listeners + 1] = fn end
    end
    facade.SetScript = facade.HookScript
    function facade:SetPoint() end
    function facade:ClearAllPoints() end
    function facade:Show() end
    function facade:Hide() end
    function facade:SetShown() end
    function facade:IsShown() return maximum() > 0 end
    local function Notify(v)
        for i = 1, #listeners do listeners[i](facade, v) end
    end
    return facade, Notify
end

function S.AttachScrollBar(scroll, parent, step)
    local notify
    local UpdateThumb, ScrollTo = EUI.AttachSmoothScrollbar(scroll, {
        step = (step or size.ROW_H) * 2, trackParent = parent, width = size.SCROLLBAR_W,
        onScroll = function(v) if notify then notify(v) end end,
    })
    local bar
    bar, notify = BarFacade(scroll, function() return EUI.SafeScrollRange(scroll) end, ScrollTo)
    bar.UpdateThumb = UpdateThumb
    scroll.ScrollBar = bar
    return bar
end



function S.ScrollRegion(parent, step)
    local region = CreateFrame("Frame", nil, parent)

    local viewport = CreateFrame("ScrollFrame", nil, region)
    viewport:SetPoint("TOPLEFT")
    viewport:SetPoint("BOTTOMRIGHT", -(size.SCROLLBAR_W + size.SCROLLBAR_GAP), 0)

    local child = CreateFrame("Frame", nil, viewport)
    child:SetSize(1, 1)
    viewport:SetScrollChild(child)

    local function Maximum()
        return math.max(0, (child:GetHeight() or 0) - (viewport:GetHeight() or 0))
    end

    local notify
    local UpdateThumb, ScrollTo = EUI.AttachSmoothScrollbar(viewport, {
        step = (step or size.ROW_H) * 2, child = child, trackParent = region,
        width = size.SCROLLBAR_W, rightInset = 0, topInset = 0, bottomInset = 0,
        onScroll = function(v) if notify then notify(v) end end,
    })
    local bar
    bar, notify = BarFacade(viewport, Maximum, ScrollTo)

    function region:SetContentHeight(height)
        height = math.max(1, height or 1)
        child:SetHeight(height)
        child:SetWidth(math.max(1, viewport:GetWidth()))

        local function Reconcile()
            child:SetWidth(math.max(1, viewport:GetWidth()))
            if (viewport:GetVerticalScroll() or 0) > Maximum() then ScrollTo(Maximum()) end
            UpdateThumb()
        end
        Reconcile()
        P.AfterLayout(Reconcile)
    end

    region.Viewport = viewport
    region.Content = child
    region.ScrollBar = bar
    return region
end







function S.TextTooltip(owner, text)
    local edge = S.WindowOf(owner)
    local ownerRight, edgeRight = owner:GetRight(), edge:GetRight()
    local opts
    if type(ownerRight) == "number" and type(edgeRight) == "number" then
        local dx = (edgeRight * edge:GetEffectiveScale() - ownerRight * owner:GetEffectiveScale())
            / UIParent:GetEffectiveScale()
        opts = { anchorPoint = "LEFT", anchorTo = "RIGHT", anchorX = dx + 2 * P.Hairline(),
            justify = "LEFT" }
    else
        opts = { anchor = "right", justify = "LEFT" }
    end
    EUI.ShowWidgetTooltip(owner, text, opts)
end

function S.HideTextTooltip()
    EUI.HideWidgetTooltip()
end



function S.ClassColor(classFile)
    if not classFile or not C_ClassColor.GetClassColor(classFile) then return end
    local c = EUI.GetClassColor(classFile)
    return c.r, c.g, c.b
end



local function MenuItems(items)
    local out = {}
    for _, item in ipairs(items) do
        if item == "-" then
            out[#out + 1] = "---"
        elseif item.title then
            out[#out + 1] = { text = item.title, noLoc = true, isDisabled = function() return true end }
        else
            local checked, disabled = item.checked, item.disabled
            if type(checked) == "function" then checked = checked() end
            out[#out + 1] = {
                text = item.text,
                noLoc = true,
                onClick = item.onClick,
                isActive = checked and true or nil,
                isDisabled = disabled and (type(disabled) == "function" and disabled
                    or function() return true end) or nil,
                children = item.children and MenuItems(item.children) or nil,
            }
        end
    end
    return out
end


local function MenuOpts(opts)
    local out = { fontKey = FONT_KEY }
    for key, value in pairs(opts or {}) do out[key] = value end
    return out
end

function S.ContextMenu(anchor, items, opts)
    EUI.ShowContextMenu(anchor, MenuItems(items), MenuOpts(opts))
end


local SELECT_PAD, SELECT_MIN_W = 8, 96
local selectOwner

function S.SelectButton(parent)
    local select = CreateFrame("Button", nil, parent)
    local bg = S.Fill(select, { EUI.DD_BG_R, EUI.DD_BG_G, EUI.DD_BG_B, EUI.DD_BG_A })
    local border = S.Border(select, { 1, 1, 1, EUI.DD_BRD_A })

    local text = S.Label(select, S.fontBody, "LEFT")
    text:SetTextColor(1, 1, 1, EUI.DD_TXT_A)
    P.Point(text, "LEFT", select, "LEFT", SELECT_PAD, 0)
    EUI.MakeDropdownArrow(select)

    local reserved = 17 + 4 + SELECT_PAD
    P.Point(text, "RIGHT", select, "RIGHT", -reserved, 0)

    select:SetScript("OnEnter", function(self)
        bg:SetColorTexture(EUI.DD_BG_R, EUI.DD_BG_G, EUI.DD_BG_B, EUI.DD_BG_HA)
        border:SetColor({ 1, 1, 1, EUI.DD_BRD_HA })
        text:SetTextColor(1, 1, 1, EUI.DD_TXT_HA)
        if self.slcHoverIn then self.slcHoverIn(self) end
    end)
    select:SetScript("OnLeave", function(self)
        bg:SetColorTexture(EUI.DD_BG_R, EUI.DD_BG_G, EUI.DD_BG_B, EUI.DD_BG_A)
        border:SetColor({ 1, 1, 1, EUI.DD_BRD_A })
        text:SetTextColor(1, 1, 1, EUI.DD_TXT_A)
        if self.slcHoverOut then self.slcHoverOut(self) end
    end)

    select.Text = text
    select.Chrome = SELECT_PAD + reserved
    select.MinWidth = SELECT_MIN_W
    return select
end


function S.ShowSelectMenu(owner, choices, current, onPick)
    local items = {}
    for i, o in ipairs(choices) do
        local value = o.value
        items[i] = { text = o.text, noLoc = true, isActive = value == current or nil,
            onClick = function() onPick(value) end }
    end
    selectOwner = owner
    EUI.ShowContextMenu(owner, items, { below = true, minWidth = owner:GetWidth(), fontKey = FONT_KEY })
end

function S.HideSelectMenu()
    if selectOwner and EUI.ContextMenuOwner() == selectOwner then EUI.CloseContextMenu() end
end





local ICON_EDGE = { 0, 0, 0, 1 }

function S.ItemIcon(parent, iconSize)
    local b = CreateFrame("Button", nil, parent)
    iconSize = math.max(iconSize or size.ICON_SM, 12)
    P.Size(b, iconSize, iconSize)

    local tex = b:CreateTexture(nil, "ARTWORK")
    P.Point(tex, "TOPLEFT", 1, -1)
    P.Point(tex, "BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.Texture = tex

    local border = S.Border(b, ICON_EDGE, "OVERLAY")

    function b:SetItem(link)
        b.link = link
        if not link then
            tex:SetTexture(nil)
            return
        end
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
        tex:SetTexture(icon or 134400)
    end

    function b:SetQualityBorder(quality)
        if not quality then border:SetColor(ICON_EDGE) return end
        local r, g, bl = C_Item.GetItemQualityColor(quality)
        if r then border:SetColor({ r, g, bl }) end
    end

    function b:SetBorderColor(c)
        border:SetColor(c or ICON_EDGE)
    end

    b:SetScript("OnEnter", function(self)
        if self.slcHoverIn then self.slcHoverIn(self) end
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        S.SetTooltipItem(self.link)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.slcHoverOut then self.slcHoverOut(self) end
    end)
    b:SetScript("OnClick", function(self)
        S.ItemModifiedClick(self.link)
    end)

    return b
end





local TAG_H = 27
local TAG_SQUARE_H = 18
local TAG_INSET = 5
local TITLE_BAND_RATIO = 1.7
local TITLE_INSET = 10


function S.HeaderHeight(options)
    options = options or {}
    if options.headerHeight then return options.headerHeight end
    local tagH = options.squareTag and TAG_SQUARE_H or TAG_H
    local _, titleFontH = S.fontTitle:GetFont()
    return math.max(size.HEADER_H,
                    math.ceil((titleFontH or 20.6) * TITLE_BAND_RATIO),
                    tagH + TAG_INSET * 2)
end

local WINDOW_ALPHA = EUI.RESKIN.CTX_ALPHA



function S.Window(globalName, key, width, height, title, options)
    options = options or {}
    local f = CreateFrame("Frame", globalName, UIParent)
    P.Size(f, width, height)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:Hide()

    S.CanvasFill(f, color.canvas, WINDOW_ALPHA)

    local edge = CreateFrame("Frame", nil, f)
    edge:EnableMouse(false)
    edge:SetAllPoints()
    edge:SetFrameLevel(f:GetFrameLevel() + 4)
    S.Border(edge, color.windowEdge, "OVERLAY")
    f.Edge = edge

    local headerH = S.HeaderHeight(options)
    f.HeaderHeight = headerH

    local header = CreateFrame("Frame", nil, f)
    header:SetFrameLevel(f:GetFrameLevel() + 1)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    P.Size(header, nil, headerH)
    S.Fill(header, color.headerTop)
    f.Header = header

    local separator = S.FadeRule(header)
    separator:SetPoint("BOTTOMLEFT")
    separator:SetPoint("BOTTOMRIGHT")

    local close = S.Button(f, "", { width = size.CLOSE, height = size.CLOSE, glyph = "close" })
    close:SetFrameLevel(header:GetFrameLevel() + 2)
    local closeInset = (headerH - size.CLOSE) * 0.5
    P.Point(close, "TOPRIGHT", f, "TOPRIGHT", -closeInset, -closeInset)
    close:SetScript("OnClick", function() f:Hide() end)
    f.Close = close

    if EUI.PadCP() then f.CloseButton = close end

    local badgeFont = options.badgeFont or S.fontSmall
    local _, badgeFontH = badgeFont:GetFont()
    badgeFontH = badgeFontH or 11
    local badge = S.Label(header, badgeFont, "RIGHT")
    P.Point(badge, "RIGHT", close, "LEFT", -size.GAP, 0)
    P.Size(badge,
        math.max(90, math.ceil(90 * badgeFontH / 11)),
        math.max(size.CLOSE, math.ceil(size.CLOSE * badgeFontH / 11)))
    f.Badge = badge


    local mark = header:CreateTexture(nil, "ARTWORK")
    P.Size(mark, 1, 1)
    mark:SetColorTexture(0, 0, 0, 0)
    P.Point(mark, "LEFT", header, "LEFT", TITLE_INSET - 1, 0)
    f.Tick = mark

    local titleText = S.Label(header, S.fontTitle, "LEFT")
    P.Point(titleText, "LEFT", mark, "RIGHT", size.TITLE_GAP, 0)
    f.Title = titleText

    local tag
    if options.squareTag then
        tag = S.Button(header, "", {
            height = TAG_SQUARE_H, width = options.tagWidth or 78,
            font = S.fontHeading, labelPad = 6, fixedWidth = true,
        })
        tag:EnableMouse(false)
    else
        tag = S.Chip(header, "", color.textMuted,
            { height = TAG_H, font = S.fontTag, padding = 8, square = true })
    end
    P.Point(tag, "LEFT", titleText, "RIGHT", size.TAG_GAP, 0)
    tag:Hide()
    f.Tag = tag


    local wordmark = options.logo and T["Simple Loot Council"] or nil
    S.InstallWindowTitle(f, key, titleText, mark, badge, tag, options.squareTag,
        wordmark or title)
    if wordmark then
        function f:ApplyLogo()
            local text = T["Simple Loot Council"]
            if S.PrideActive() and not text:find("[\128-\255]") then text = S.Rainbow(text) end
            self.Title:SetText(text)
            if self.ClampTitle then P.AfterLayout(self.ClampTitle) end
        end
        f:ApplyLogo()
        S.logoWindows[#S.logoWindows + 1] = f
    end

    local content = CreateFrame("Frame", nil, f)
    content:SetFrameLevel(f:GetFrameLevel() + 1)
    P.Point(content, "TOPLEFT", f, "TOPLEFT", size.PAD, -(headerH + size.PAD))
    P.Point(content, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -size.PAD, size.PAD)
    content.slcWidth = width - size.PAD * 2
    f.Content = content

    S.InstallWindowGeometry(f, key, header, close)



    if globalName then EUI.RegisterEscapeClose(f) end
    return f
end







function S.Confirm(options)
    options = options or {}

    local body = options.body or ""
    local prompt, detail = body:match("^(.-)\n\n(.*)$")
    if not prompt then prompt = body end
    prompt = (prompt:gsub("%s+$", ""))
    detail = detail and (detail:gsub("%s+$", "")) or nil
    if detail == "" then detail = nil end

    local acknowledge = options.acknowledge and true or false
    local alternate = not acknowledge and options.alternate or nil

    return EUI:ShowConfirmPopup({
        title       = options.title or T["Are you sure?"],
        message     = prompt,
        disclaimer  = detail,
        checkbox    = alternate,
        confirmText = acknowledge and T["OK"] or (options.accept or T["Confirm"]),
        cancelText  = T["Cancel"],
        hideCancel  = acknowledge or nil,
        onConfirm   = function(checked)
            if acknowledge then return end
            if checked and alternate then
                if options.onAlternate then options.onAlternate() end
            elseif options.onAccept then
                options.onAccept()
            end
        end,
    })
end
