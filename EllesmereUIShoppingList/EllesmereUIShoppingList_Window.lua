if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIShoppingList_Window.lua
--  The list window, built to offer what a Damage Meters window offers: a
--  styled header (title, height, opacity, bottom line, glyph buttons that can
--  show on mouseover only), a window border and background, one styled bar
--  per entry, a resize grip, and a lock that stops dragging and resizing.
--  Unlock Mode can always place it.
--
--  The rows come from ns.BuildRows (the Data file) as plain entries:
--    { kind = "section" | "recipe" | "reagent" | "vendor" | "cooldown",
--      key, name, icon, state = "complete" | "partial" | "missing" | nil,
--      ready (a green check), fill (0..100), right (text), tag (text),
--      collapsed, ... }
--  The live window and the options preview share the surface and renderer.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EUI = ns.EUI

local MEDIA = "Interface\\AddOns\\EllesmereUIShoppingList\\Media\\"
local RESIZE_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\resize_element.png"
local COLLAPSE_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"
local EXPAND_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
local MIN_W, MIN_H = 160, 60
local ICON_ALPHA, ICON_HOVER_ALPHA = 0.4, 0.9
local BORDER_KEY = "shoppinglist"
local UNLOCK_KEY = ns.UNLOCK_KEY
EUI.RegisterBorderDefaults(BORDER_KEY, EUI.BORDER_DEFAULTS_BARS)
ns.BORDER_KEY = BORDER_KEY
ns.MIN_W, ns.MIN_H = MIN_W, MIN_H

local Get = ns.Get
local RowOnClick, RowOnEnter, RowOnLeave  -- live rows only (defined with the window)

-------------------------------------------------------------------------------
--  Bar textures (built on first use; the options page reads the lists).
-------------------------------------------------------------------------------
local textures
function ns.BarTextures()
    if not textures then
        local names, order
        textures, names, order = EUI.BuildBarTextureTables(true)
        EUI.AppendSharedMediaTextures(names, order, nil, textures)
        ns.BarTextureNames, ns.BarTextureOrder = names, order
    end
    return textures
end

-------------------------------------------------------------------------------
--  Formatting shared with the other files.
-------------------------------------------------------------------------------
function ns.FormatCount(have, need)
    local fmt = Get("numberFormat")
    if fmt == "spaced" then return have .. " / " .. need end
    if fmt == "missing" then
        local left = need - have
        if left <= 0 then return EUI.L("Done") end
        return string.format(EUI.L("%d missing"), left)
    end
    if fmt == "percent" then
        if need <= 0 then return "100%" end
        return string.format("%d%%", math.floor(math.min(have, need) * 100 / need))
    end
    return have .. "/" .. need
end

-- The ready mark: Blizzard's ready-check tick (a file every client ships).
ns.CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"

function ns.FormatQty(qty)
    if Get("qtyFormat") == "x" then return "x" .. qty end
    return tostring(qty)
end

function ns.FormatMoney(copper)
    return C_CurrencyInfo.GetCoinTextureString(math.floor(copper + 0.5))
end

-- Remaining time as "3h 12m" / "12m" / "<1m".
function ns.FormatRemaining(seconds)
    if seconds < 60 then return EUI.L("<1m") end
    local m = math.floor(seconds / 60)
    local h = math.floor(m / 60)
    local d = math.floor(h / 24)
    if d > 0 then return string.format("%dd %dh", d, h % 24) end
    if h > 0 then return string.format("%dh %dm", h, m % 60) end
    return string.format("%dm", m)
end

-------------------------------------------------------------------------------
--  Style memo: every setting the paint reads, resolved once. ns.RestyleWindow
--  clears it; a global font, outline or accent change rebuilds it. Frames and
--  rows stamp the table they were painted with.
-------------------------------------------------------------------------------
local cachedStyle

local function Style()
    local font = EUI.GetFontPath(ns.FONT_KEY)
    local outline = EUI.GetFontOutlineFlag(ns.FONT_KEY)
    local accent = EUI.ELLESMERE_GREEN
    local dm = cachedStyle
    if dm and dm.globalFont == font and dm.globalOutline == outline
        and dm.accentR == accent.r and dm.accentG == accent.g and dm.accentB == accent.b then
        return dm
    end
    dm = {}
    for key in pairs(ns.DEFAULTS) do dm[key] = Get(key) end
    dm.headerHeight = dm.hdrHeight
    dm.iconSize = math.min(dm.hdrIconSize, dm.hdrHeight)
    dm.texturePath = EUI.ResolveTexturePath(ns.BarTextures(), dm.barTexture, "Interface\\Buttons\\WHITE8X8")
    dm.accent = accent
    dm.globalFont, dm.globalOutline = font, outline
    dm.accentR, dm.accentG, dm.accentB = accent.r, accent.g, accent.b
    cachedStyle = dm
    return dm
end
ns.Style = Style

local function Font(fs, size)
    EUI.ApplyModuleFont(fs, nil, size, ns.FONT_KEY)
end

local function PaintText(fs, c)
    fs:SetTextColor(c.r, c.g, c.b)
end

-- A size in physical pixels, in UI units.
local function PhysicalPixels(v)
    local PP = EUI.PP
    return PP.Scale(v * PP.mult)
end

local function Border(target, dm, window)
    if window then
        local size, texture = dm.windowBorderSize, dm.windowBorderTexture
        local c = dm.windowBorderColor
        local px = size > 0 and EUI.BorderPx(dm.windowBorderSizePx, size, texture) or nil
        EUI.ApplyBorderStyle(target, size, c.r, c.g, c.b, c.a or 1, texture,
            nil, nil, nil, nil, nil, nil, nil, px)
        return
    end
    local size, texture = dm.borderSize, dm.borderTexture
    local px = size > 0 and EUI.BorderPx(dm.borderSizePx, size, texture) or nil
    EUI.ApplyBorderStyle(target, size, dm.borderR, dm.borderG, dm.borderB, dm.borderA, texture,
        nil, nil, nil, nil, BORDER_KEY, size, nil, px)
end

-------------------------------------------------------------------------------
--  Header buttons, laid out from the right edge in list order. A glyph idles
--  at 0.4 and brightens on hover; with Mouseover Icons they show only while
--  the window is hovered.
-------------------------------------------------------------------------------
local function HeaderEnter(btn)
    btn.icon:SetVertexColor(btn._r, btn._g, btn._b, ICON_HOVER_ALPHA)
    if btn.tooltip and EUI.ContextMenuOwner() ~= btn then
        EUI.ShowWidgetTooltip(btn, EUI.L(type(btn.tooltip) == "function" and btn.tooltip() or btn.tooltip))
    end
    if btn.surface.onHover then btn.surface.onHover() end
end

local function HeaderLeave(btn)
    btn.icon:SetVertexColor(btn._r, btn._g, btn._b, ICON_ALPHA)
    EUI.HideWidgetTooltip()
    if btn.surface.onHover then btn.surface.onHover() end
end

local function HeaderClick(btn, button)
    EUI.HideWidgetTooltip()
    if btn.onClick then btn.onClick(btn, button) end
end

local function MakeHeaderButton(surface, key, file, tooltip)
    local header = surface.header
    local btn = CreateFrame("Button", nil, header)
    btn:SetFrameLevel(header:GetFrameLevel() + 2)
    btn.key, btn.tooltip, btn.surface = key, tooltip, surface
    btn._r, btn._g, btn._b = 1, 1, 1
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture(file)
    btn.icon:SetDesaturated(true)
    btn.icon:SetVertexColor(1, 1, 1, ICON_ALPHA)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnEnter", HeaderEnter)
    btn:SetScript("OnLeave", HeaderLeave)
    btn:SetScript("OnClick", HeaderClick)
    local list = surface.hdrBtns
    list[#list + 1] = btn
    return btn
end

local function LayoutHeaderButtons(surface, size)
    local header = surface.header
    local used, leftmost = 0, nil
    for _, btn in ipairs(surface.hdrBtns) do
        if btn:IsShown() then
            btn:SetSize(size, size)
            btn:ClearAllPoints()
            btn:SetPoint("RIGHT", header, "RIGHT", -(used + 2), 0)
            used = used + size
            leftmost = btn
        end
    end
    return leftmost
end

-- The glyph colour: accent or custom (the Damage Meters header's Icon Size swatches).
local function TintHeaderButtons(surface, dm)
    local c = dm.iconColorUseAccent and dm.accent or dm.iconColor
    for _, btn in ipairs(surface.hdrBtns) do
        btn._r, btn._g, btn._b = c.r, c.g, c.b
        btn.icon:SetVertexColor(c.r, c.g, c.b, ICON_ALPHA)
    end
end

-------------------------------------------------------------------------------
--  Surface
-------------------------------------------------------------------------------
local function ApplyChrome(dm, s)
    if s._style == dm then return end
    s._style = dm
    local header = s.header
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0)
    header:SetHeight(dm.headerHeight)
    local hb = dm.hdrBgColor
    header.bg:SetColorTexture(hb.r, hb.g, hb.b, dm.hdrBgAlpha)
    local lineSize, line = dm.hdrBottomBorderSize, dm.hdrBottomBorderColor
    header.line:SetHeight(PhysicalPixels(lineSize))
    header.line:SetColorTexture(line.r, line.g, line.b, line.a or 1)
    header.line:SetShown(lineSize > 0)
    Font(s.title, dm.hdrFontSize)
    PaintText(s.title, dm.hdrTextUseAccent and dm.accent or dm.hdrTextColor)
    TintHeaderButtons(s, dm)
    local leftmost = LayoutHeaderButtons(s, dm.iconSize)
    s.title:ClearAllPoints()
    s.title:SetPoint("LEFT", header, "LEFT", 6 + dm.hdrTextOffX, dm.hdrTextOffY)
    if leftmost then
        s.title:SetPoint("RIGHT", leftmost, "LEFT", -6, dm.hdrTextOffY)
    else
        s.title:SetPoint("RIGHT", header, "RIGHT", -6, dm.hdrTextOffY)
    end
    s.bg:ClearAllPoints()
    s.bg:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -dm.headerHeight)
    s.bg:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
    s.bg:SetColorTexture(dm.bgR, dm.bgG, dm.bgB, dm.bgAlpha)
    local border = s.border
    border:ClearAllPoints()
    if not dm.windowBorderIncludeHeader then
        border:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    else
        border:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
    end
    border:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
    -- Show Behind: the border under the header and rows instead of over them.
    border:SetFrameLevel(dm.windowBorderBehind and s:GetFrameLevel() or (header:GetFrameLevel() + 4))
    Border(border, dm, true)
    if s.caption then Font(s.caption, 10) end
    if s.unlockKey then EUI.MatchPadChanged(s.unlockKey) end
end

local function CreateSurface(parent, name, live)
    local surface = CreateFrame("Frame", name, parent)
    surface.live = live == true
    surface.rows = {}
    surface.hdrBtns = {}
    surface.bg = surface:CreateTexture(nil, "BACKGROUND")
    surface.border = CreateFrame("Frame", nil, surface)
    surface.border:EnableMouse(false)
    local header = CreateFrame("Frame", nil, surface)
    surface.header = header
    header:SetFrameLevel(surface:GetFrameLevel() + 5)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.line = header:CreateTexture(nil, "OVERLAY", nil, 7)
    header.line:SetPoint("BOTTOMLEFT")
    header.line:SetPoint("BOTTOMRIGHT")
    surface.title = header:CreateFontString(nil, "OVERLAY")
    surface.title:SetJustifyH("LEFT")
    surface.title:SetWordWrap(false)
    -- Rightmost first.
    surface.settingsBtn = MakeHeaderButton(surface, "settings", MEDIA .. "dm_settings.png",
        live and "Settings" or nil)
    surface.clearBtn = MakeHeaderButton(surface, "clear", MEDIA .. "dm_reset.png",
        live and "Clear List" or nil)
    surface.collapseBtn = MakeHeaderButton(surface, "collapse", COLLAPSE_ICON,
        live and function() return Get("collapsed") and "Expand" or "Collapse" end or nil)
    surface.lockBtn = MakeHeaderButton(surface, "lock", MEDIA .. "dm_unlock_top.png",
        live and function() return Get("locked") and "Locked" or "Unlocked" end or nil)
    if not live then
        for _, btn in ipairs(surface.hdrBtns) do btn:EnableMouse(false) end
    end
    ApplyChrome(Style(), surface)
    return surface
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local function MakeRow(surface, rows, i)
    local row = CreateFrame("Button", nil, surface)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.fill = CreateFrame("StatusBar", nil, row)
    row.fill:SetMinMaxValues(0, 100)
    row.border = CreateFrame("Frame", nil, row)
    row.border:SetAllPoints(row.fill)
    row.border:SetFrameLevel(row.fill:GetFrameLevel() + 1)
    row.border:EnableMouse(false)
    -- Border styling hides its frame at size 0: the texts get their own parent above it.
    row.text = CreateFrame("Frame", nil, row)
    row.text:SetAllPoints()
    row.text:SetFrameLevel(row.border:GetFrameLevel() + 1)
    row.text:EnableMouse(false)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.icon = row.text:CreateTexture(nil, "ARTWORK")
    row.label = row.text:CreateFontString(nil, "OVERLAY")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.value = row.text:CreateFontString(nil, "OVERLAY")
    row.value:SetJustifyH("RIGHT")
    row.value:SetWordWrap(false)
    row.tag = row.text:CreateFontString(nil, "OVERLAY")
    row.tag:SetJustifyH("RIGHT")
    row.surface = surface
    if surface.live then
        row:SetScript("OnClick", RowOnClick)
        row:SetScript("OnEnter", RowOnEnter)
        row:SetScript("OnLeave", RowOnLeave)
    else
        row:EnableMouse(false)
    end
    rows[i] = row
    return row
end

-- Icon, fill seat and text anchors: redone when the style or the icon's presence changes.
local function SeatRow(row, e, dm, hasIcon)
    local size = dm.barHeight
    local x = 0
    if hasIcon then
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetSize(size, size)
        local z = dm.iconZoom
        row.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        x = size + 2
    end
    row.icon:SetShown(hasIcon)
    row.fill:ClearAllPoints()
    row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
    row.fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.bg:ClearAllPoints()
    row.bg:SetAllPoints(row.fill)
    row.value:ClearAllPoints()
    row.value:SetPoint("RIGHT", row, "RIGHT", -5 + dm.rightTextOffsetX, dm.rightTextOffsetY)
    row.tag:ClearAllPoints()
    row.tag:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", x + 5 + dm.leftTextOffsetX, dm.leftTextOffsetY)
    row.label:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
end

local function PaintRow(row, e, dm)
    local restyle = row._style ~= dm
    if restyle then
        Font(row.label, dm.leftFontSize)
        Font(row.value, dm.rightFontSize)
        Font(row.tag, math.max(8, dm.rightFontSize - 2))
        row.fill:SetStatusBarTexture(dm.texturePath)
        Border(row.border, dm, false)
        row._style = dm
    end
    row.entry = e
    local isSection = e.kind == "section"
    local hasIcon = not isSection and dm.iconStyle ~= "none" and e.icon ~= nil
    if restyle or row._hasIcon ~= hasIcon then
        SeatRow(row, e, dm, hasIcon)
        row._hasIcon = hasIcon
    end
    if hasIcon then row.icon:SetTexture(e.icon) end

    local label = e.name or ""
    if isSection then
        label = (e.collapsed and "+ " or "- ") .. label
        PaintText(row.label, dm.sectionTextUseAccent and dm.accent or dm.sectionTextColor)
    else
        PaintText(row.label, dm.leftTextColor)
    end
    row.label:SetText(label)
    -- Ready (enough of a reagent, a recipe you can craft, a cooldown that is
    -- up): the green check takes the tag's place.
    row.tag:SetText(e.ready and ns.CHECK or (e.tag or ""))
    row.value:SetText(e.right or "")

    PaintText(row.value, dm.rightTextColor)
    if isSection then
        row.fill:Hide()
        row.bg:Hide()
        row.border:SetAlpha(0)
        return
    end
    row.fill:Show()
    row.bg:Show()
    row.border:SetAlpha(1)
    local fillColor = dm.colorMode == "custom" and dm.barColor or dm.accent
    row.fill:SetStatusBarColor(fillColor.r, fillColor.g, fillColor.b, dm.barFillAlpha)
    row.fill:SetValue(e.fill or 0)
    row.bg:SetColorTexture(dm.barBgR, dm.barBgG, dm.barBgB, dm.barBgAlpha)
    -- Border Follows Bar: the bar border wraps the filled part only.
    if dm.borderFollowFill then
        local tex = row.fill:GetStatusBarTexture()
        row.border:ClearAllPoints()
        row.border:SetPoint("TOPLEFT", row.fill, "TOPLEFT", 0, 0)
        row.border:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 0, 0)
        row.border:SetShown((e.fill or 0) > 0)
    elseif restyle then
        row.border:ClearAllPoints()
        row.border:SetAllPoints(row.fill)
        row.border:Show()
    end
end

local function RenderRows(s, list, first, count, dm)
    local rows = s.rows
    local step = dm.barHeight + dm.barSpacing
    for i = 1, count do
        local row = rows[i] or MakeRow(s, rows, i)
        local y = -dm.headerHeight - dm.barSpacing - (i - 1) * step
        if row._y ~= y or row._style ~= dm then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", s, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, y)
            row:SetHeight(dm.barHeight)
            row._y = y
        end
        PaintRow(row, list[i + first], dm)
        row:Show()
    end
    for i = count + 1, #rows do
        rows[i]:Hide()
        rows[i].entry = nil
    end
end

-------------------------------------------------------------------------------
--  Preview entries (options header, unlock mode while the list is empty).
--  Real item IDs so the icons are the game's; names fall back to English.
-------------------------------------------------------------------------------
local DEMO = {
    { kind = "section", key = "recipes", name = "Recipes", right = "2" },
    { kind = "recipe", item = 13452, name = "Elixir of the Mongoose", qty = 4 },
    { kind = "recipe", item = 12360, name = "Transmute: Arcanite", qty = 2, fixedName = true },
    { kind = "section", key = "reagents", name = "Reagents", right = "1/5" },
    { kind = "reagent", item = 8925, name = "Crystal Vial", have = 0, need = 4, tag = "vendor" },
    { kind = "reagent", item = 12655, name = "Enchanted Thorium Bar", have = 0, need = 2, tag = "craft" },
    { kind = "reagent", item = 13466, name = "Plaguebloom", have = 2, need = 8 },
    { kind = "reagent", item = 13465, name = "Mountain Silversage", have = 6, need = 10 },
    { kind = "reagent", item = 12359, name = "Thorium Bar", have = 2, need = 2 },
}
local demoList

local function StateOf(have, need)
    if have >= need then return "complete" end
    if have > 0 then return "partial" end
    return "missing"
end
ns.StateOf = StateOf

function ns.DemoList()
    demoList = demoList or {}
    wipe(demoList)
    for i, d in ipairs(DEMO) do
        local e = { kind = d.kind, key = d.key or i,
            tag = (d.tag == "vendor" and ns.VENDOR_ICON) or (d.tag == "craft" and ns.CRAFT_ICON) or nil }
        e.name = (not d.fixedName and d.item and C_Item.GetItemNameByID(d.item)) or EUI.L(d.name)
        e.icon = d.item and C_Item.GetItemIconByID(d.item) or nil
        if d.kind == "recipe" then
            e.fill, e.right = 100, ns.FormatQty(d.qty)
        elseif d.kind == "reagent" then
            e.state = StateOf(d.have, d.need)
            e.ready = e.state == "complete"
            e.fill = math.min(100, d.have * 100 / d.need)
            e.right = ns.FormatCount(d.have, d.need)
        else
            e.right = d.right
        end
        demoList[#demoList + 1] = e
    end
    return demoList
end

-------------------------------------------------------------------------------
--  Options preview: its own surface in the page's content header.
-------------------------------------------------------------------------------
local settingsPreview
local hookedParents = setmetatable({}, { __mode = "k" })

local function RefreshPreview(self)
    local parent = self:GetParent()
    if not parent then return end
    local dm = Style()
    local list = ns.DemoList()
    local n = #list
    local width = math.max(MIN_W, Get("width"))
    local height = dm.headerHeight + dm.barSpacing + n * (dm.barHeight + dm.barSpacing) + 26
    self:SetSize(width, height)
    local pw = parent:GetWidth()
    local available = (pw > 0 and pw) or self.availableWidth or width + 40
    self:SetScale(math.min(1, math.max(100, available - 40) / width))
    self:ClearAllPoints()
    self:SetPoint("CENTER", parent, "CENTER", 0, 0)
    ApplyChrome(dm, self)
    self.title:SetText(ns.TitleText(nil))
    RenderRows(self, list, 0, n, dm)
    self.previewHeight = height * self:GetScale() + 30
    if self.onHeightChanged then self.onHeightChanged(self.previewHeight) end
end

local function RefreshSettingsPreview()
    if settingsPreview and settingsPreview:IsVisible() then RefreshPreview(settingsPreview) end
end

function ns.CreateSettingsPreview(parent, availableWidth, onHeightChanged)
    local view = settingsPreview
    if not view then
        view = CreateSurface(parent)
        settingsPreview = view
        view.caption = view:CreateFontString(nil, "OVERLAY")
        view.caption:SetPoint("BOTTOM", 0, 6)
        view.caption:SetTextColor(0.65, 0.65, 0.65)
        Font(view.caption, 10)
        view.caption:SetText(EUI.L("Preview"))
        view.Refresh = RefreshPreview
        view:SetScript("OnShow", RefreshPreview)
    end
    view.availableWidth, view.onHeightChanged = availableWidth, onHeightChanged
    view:SetParent(parent)
    if not hookedParents[parent] then
        hookedParents[parent] = true
        local lastWidth
        parent:HookScript("OnSizeChanged", function(_, width)
            if width == lastWidth then return end
            lastWidth = width
            if settingsPreview:GetParent() == parent and settingsPreview:IsVisible() then
                RefreshPreview(settingsPreview)
            end
        end)
    end
    RefreshPreview(view)
    view:Show()
    return view
end

-------------------------------------------------------------------------------
--  Title: the custom text (blank: "Shopping List"), plus the list's cost.
-------------------------------------------------------------------------------
function ns.TitleText(cost)
    local base = EUI.L("Shopping List")
    local t = Get("titleText")
    if type(t) == "string" and t:match("%S") then base = t end
    if cost and cost > 0 and Get("costInHeader") then
        return base .. "  |cffffffff" .. ns.FormatMoney(cost) .. "|r"
    end
    return base
end

-------------------------------------------------------------------------------
--  Live window
-------------------------------------------------------------------------------
local frame, grip
local offset = 0
local shownList
local liveList = {}
local minuteTicker

local function IsLocked() return Get("locked") == true end

local function CanMove()
    return not IsLocked() and not EUI._unlockActive
end

local function SetSavedPoint()
    local p = Get("position")
    frame:ClearAllPoints()
    if type(p) == "table" and p.point then
        frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    elseif type(p) == "table" and p.x and p.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end
end

local function Position()
    SetSavedPoint()
    EUI.ReapplyOwnAnchor(UNLOCK_KEY)
end

-- A drag or resize saves the top-left corner and drops any unlock-mode anchor.
local function SaveCorner()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return end
    local PP = EUI.PP
    left, top = PP.Snap(left), PP.Snap(top)
    ns.Set("position", { x = left, y = top })
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    local anchors = EllesmereUIDB and EllesmereUIDB.unlockAnchors
    if anchors then anchors[UNLOCK_KEY] = nil end
    EUI.ScheduleSettleReapply()
end

local function HeaderOnly()
    return Get("collapsed") == true
end

local function ApplyGeometry()
    local dm = Style()
    local w = math.max(MIN_W, Get("width"))
    local h = HeaderOnly() and dm.headerHeight or math.max(MIN_H, Get("height"))
    frame:SetSize(w, h)
end

-- Hover: grip fades in, and Mouseover Icons show the header glyphs.
local function UpdateHover()
    if not frame then return end
    local over = frame:IsShown() and frame:IsMouseOver()
    local showIcons = over or not Get("hdrMouseoverIcons")
    for _, btn in ipairs(frame.hdrBtns) do btn:SetAlpha(showIcons and 1 or 0) end
    if grip then
        local gripOn = over and not IsLocked() and not HeaderOnly()
        grip:SetShown(not IsLocked() and not HeaderOnly())
        if not grip:IsMouseOver() then grip:SetAlpha(gripOn and 0.3 or 0) end
    end
end

local function SyncLockIcon()
    frame.lockBtn.icon:SetTexture(MEDIA .. (IsLocked() and "dm_locked_top.png" or "dm_unlock_top.png"))
    frame.collapseBtn.icon:SetTexture(HeaderOnly() and EXPAND_ICON or COLLAPSE_ICON)
    UpdateHover()
end

-- Visibility: never while off; always in unlock mode; while a profession is
-- open with Show With Profession; else the shared rules and Hide When Empty.
-- Returns true, false or "mouseover".
local function Visible(isEmpty)
    if not ns.active then return false end
    if EUI._unlockActive then return true end
    if ns.professionOpen and Get("showWithProfession") then return true end
    if isEmpty and Get("hideWhenEmpty") then return false end
    local r = EUI.EvalVisibility(ns.P())
    if not r then return false end
    if r == "mouseover" then return "mouseover" end
    return true
end

local function Paint(list, dm)
    local area = frame:GetHeight() - dm.headerHeight - dm.barSpacing
    local step = dm.barHeight + dm.barSpacing
    local capacity = math.max(0, math.floor((area + dm.barSpacing) / step))
    if HeaderOnly() then capacity = 0 end
    local n = #list
    local maxOffset = math.max(0, n - capacity)
    if offset > maxOffset then offset = maxOffset end
    local count = math.min(capacity, n - offset)
    RenderRows(frame, list, offset, count, dm)
end

-- The minute ticker exists only while a cooldown row with time left is shown.
local function SetMinuteTicker(on)
    if on and not minuteTicker then
        minuteTicker = C_Timer.NewTicker(60, function() ns.Invalidate() end)
    elseif not on and minuteTicker then
        minuteTicker:Cancel()
        minuteTicker = nil
    end
end

local function Refresh()
    if not frame then return end
    if not ns.active then
        SetMinuteTicker(false)
        frame:Hide()
        return
    end
    local dm = Style()
    ApplyChrome(dm, frame)
    wipe(liveList)
    local cost, ticking = 0, false
    if ns.BuildRows then cost, ticking = ns.BuildRows(liveList) end
    local list = liveList
    if #list == 0 and EUI._unlockActive then list = ns.DemoList() end
    shownList = list
    local vis = Visible(#liveList == 0)
    if vis == "mouseover" then
        -- The shared mouseover scan shows it on hover; a refresh only hides it
        -- once the pointer is away.
        if not frame:IsMouseOver() then frame:Hide() end
    else
        frame:SetShown(vis == true)
    end
    SetMinuteTicker(ticking and vis == true)
    frame.title:SetText(ns.TitleText(cost))
    if frame:IsShown() then Paint(list, dm) end
    SyncLockIcon()
end
ns.RefreshWindow = Refresh

function ns.RestyleWindow()
    cachedStyle = nil
    if frame then
        ApplyGeometry()
        Refresh()
    end
    RefreshSettingsPreview()
end

-------------------------------------------------------------------------------
--  Header menu (settings glyph): the most used toggles, and the options page.
-------------------------------------------------------------------------------
local MENU_OPTS = { below = true, fontKey = ns.FONT_KEY }

local function Toggle(key)
    ns.Set(key, not Get(key))
    ns.Apply()
    EUI:RefreshPage()
end

local function ShowQuickMenu(anchor)
    local items = {
        { text = EUI.L("Hide Completed Reagents"), isActive = Get("hideCompleted") == true,
          onClick = function() Toggle("hideCompleted") end },
        { text = EUI.L("Show With Profession Window"), isActive = Get("showWithProfession") == true,
          onClick = function() Toggle("showWithProfession") end },
        { text = EUI.L("Hide When Empty"), isActive = Get("hideWhenEmpty") == true,
          onClick = function() Toggle("hideWhenEmpty") end },
        "---",
        { text = EUI.L("Settings"), isDisabled = InCombatLockdown,
          onClick = function() EUI:NavigateToElementSettings(ADDON_NAME, "General") end },
    }
    EUI.ShowContextMenu(anchor, items, MENU_OPTS)
end
ns.MENU_OPTS = MENU_OPTS

local function ConfirmClear()
    EUI:ShowConfirmPopup({
        title = "Clear Shopping List",
        message = "Remove every tracked recipe and vendor item from this character's list?",
        confirmText = "Clear",
        onConfirm = function() if ns.ClearList then ns.ClearList() end end,
    })
end

local function CreateWindow()
    frame = CreateSurface(UIParent, "EllesmereUIShoppingListFrame", true)
    ns.frame = frame
    frame.unlockKey = UNLOCK_KEY
    frame:Hide()
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_W, MIN_H)
    frame:SetDontSavePosition(true)
    frame:EnableMouse(true)

    frame.settingsBtn.onClick = ShowQuickMenu
    frame.clearBtn.onClick = ConfirmClear
    frame.collapseBtn.onClick = function()
        ns.Set("collapsed", not HeaderOnly())
        offset = 0
        ApplyGeometry()
        Refresh()
    end
    frame.lockBtn.onClick = function(btn)
        ns.Set("locked", not IsLocked())
        SyncLockIcon()
        EUI.HideWidgetTooltip()
        EUI.ShowWidgetTooltip(btn, EUI.L(IsLocked() and "Locked" or "Unlocked"))
        EUI:RefreshPage()
    end
    frame.onHover = UpdateHover

    local header = frame.header
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() if CanMove() then frame:StartMoving() end end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SaveCorner()
    end)
    header:SetScript("OnEnter", UpdateHover)
    header:SetScript("OnLeave", UpdateHover)
    frame:SetScript("OnEnter", UpdateHover)
    frame:SetScript("OnLeave", UpdateHover)

    grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 15)
    local gt = grip:CreateTexture(nil, "ARTWORK")
    gt:SetAllPoints()
    gt:SetTexture(RESIZE_ICON)
    gt:SetDesaturated(true)
    grip:SetAlpha(0)
    grip:SetScript("OnEnter", function(self) if not IsLocked() then self:SetAlpha(0.7) end end)
    grip:SetScript("OnLeave", function() UpdateHover() end)
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and CanMove() then frame:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        ns.Set("width", math.floor(frame:GetWidth() + 0.5))
        ns.Set("height", math.floor(frame:GetHeight() + 0.5))
        SaveCorner()
        Refresh()
    end)

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        if shownList then Paint(shownList, Style()) end
    end)
    local lastHeight
    frame:HookScript("OnSizeChanged", function(_, _, height)
        if height == lastHeight then return end
        lastHeight = height
        if shownList and frame:IsShown() then Paint(shownList, Style()) end
    end)
    frame:HookScript("OnHide", function()
        local owner = EUI.ContextMenuOwner()
        if owner and owner:GetParent() == header then EUI.CloseContextMenu() end
    end)

    EUI.RegAccent({ type = "callback", fn = function()
        if frame:IsShown() then Refresh() end
        RefreshSettingsPreview()
    end })
    ApplyGeometry()
    Position()
end

-- Row clicks and hovers go to whoever handles them (Data file); the window
-- only knows sections.
RowOnClick = function(row, button)
    local e = row.entry
    if not e then return end
    if e.kind == "section" then
        if ns.ToggleSection then ns.ToggleSection(e.key) end
        return
    end
    if ns.RowClick then ns.RowClick(row, e, button) end
end

RowOnEnter = function(row)
    UpdateHover()
    local e = row.entry
    if not (e and Get("showHoverTooltip") and ns.RowTooltip) then return end
    ns.RowTooltip(row, e)
end

RowOnLeave = function()
    UpdateHover()
    GameTooltip:Hide()
end

local refreshHooked = false
local function WantsMouseover()
    return ns.active and EUI.VisWantsMouseover(ns.P(), "visibility")
end
function ns.ApplyWindow()
    cachedStyle = nil
    if ns.active then
        if not frame then CreateWindow() end
        ApplyGeometry()
        if not EUI._unlockActive then Position() end
        if not refreshHooked then
            refreshHooked = true
            ns.OnChanged(Refresh)
        end
        -- Combat, zone and group edges reach the window through the shared
        -- visibility dispatcher, only while the module is on.
        EUI.UnregisterVisibilityUpdater(Refresh)
        EUI.RegisterVisibilityUpdater(Refresh)
        if EUI.RegisterMouseoverTarget then
            EUI.UnregisterMouseoverTarget(frame)
            EUI.RegisterMouseoverTarget(frame, WantsMouseover)
        end
        Refresh()
    else
        EUI.UnregisterVisibilityUpdater(Refresh)
        if frame and EUI.UnregisterMouseoverTarget then EUI.UnregisterMouseoverTarget(frame) end
        if frame then
            SetMinuteTicker(false)
            frame:Hide()
        end
    end
    RefreshSettingsPreview()
end

-------------------------------------------------------------------------------
--  Unlock mode. Registered at login whatever the enable state (an element
--  anchored to the window keeps its link while it is off); nothing is built
--  while the module is off.
-------------------------------------------------------------------------------
local function SetUnlockSize(key, v, low)
    if not frame then return end
    v = EUI.PP.Snap(math.max(low, v or low))
    if key == "width" then frame:SetWidth(v) else frame:SetHeight(v) end
    if EUI._unlockActive then ns.Set(key, math.floor(v + 0.5)) end
end

local unlockRegistered = false
function ns.RegisterUnlock()
    if unlockRegistered then return end
    unlockRegistered = true
    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key      = UNLOCK_KEY,
            label    = "Shopping List",
            group    = "Shopping List",
            order    = 735,
            isHidden = function() return not ns.active end,
            getFrame = function()
                if not ns.active then return nil end
                if not frame then CreateWindow() end
                return frame
            end,
            getSize = function()
                if frame then return frame:GetSize() end
                return math.max(MIN_W, Get("width")), math.max(MIN_H, Get("height"))
            end,
            setWidth = function(_, w) SetUnlockSize("width", w, MIN_W) end,
            setHeight = function(_, h) SetUnlockSize("height", h, MIN_H) end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                ns.Set("position", { point = point, relPoint = relPoint or point, x = x or 0, y = y or 0 })
                if frame and not EUI._unlockActive then SetSavedPoint() end
            end,
            loadPos = function()
                local p = Get("position")
                if type(p) ~= "table" then return nil end
                if p.point then
                    return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
                end
                if p.x and p.y then
                    return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = p.x, y = p.y }
                end
            end,
            clearPos = function()
                ns.Set("position", nil)
                if frame then SetSavedPoint() end
            end,
            applyPos = function()
                if not ns.active then return end
                if not frame then CreateWindow() end
                SetSavedPoint()
            end,
        }),
    }, ADDON_NAME)
    EUI:RegisterUnlockModeListener(UNLOCK_KEY, function()
        if frame and ns.active then Refresh() end
    end)
end

ns.slashCommands.test = function()
    if not frame then
        ns.Say(EUI.L("Enable the Shopping List first."))
        return
    end
    frame:Show()
    Paint(ns.DemoList(), Style())
end
