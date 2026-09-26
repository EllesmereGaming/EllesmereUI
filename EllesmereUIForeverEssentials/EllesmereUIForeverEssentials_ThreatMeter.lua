if EUI_CLIENT_BLOCKED then return end
local addon, module = ...
local ns = module.ThreatMeter
local EUI = EllesmereUI
local UI_REV = "essentials-merged-20260925"
if not (EUI and EUI.IS_FOREVER and ns) then return end

local defaults = {
    enabled = false, source = "target", focusEnabled = false, pets = false,
    width = 320, height = 210, barHeight = 18, fontSize = 11,
    locked = false, barSpacing = 2, appearance = {},
    pullBar = false, pullColor = { r = 0, g = 0.55, b = 0 },
    showValue = true, showPercent = true, percentMode = "relative", showHeader = true,
    warnSound = false, warnSoundKey = "none", warnAt = 80, warnSkipTank = false,
    playerColorOn = false, playerColor = { r = 0.8, g = 0.1, b = 0.1 },
    tankColorOn = false, tankColor = { r = 0.1, g = 0.6, b = 0.1 },
    font = "__global", outlineMode = "__global", growUp = false,
}
local frame, title, rows
local CreateWindow, SetActive
local active = false
local threatBuffer, visibilityState = {}, {}
local tokenBuffer = { tokens = {}, candidates = {} }
local emptyEntries, pullEntry = {}, {}
local preview, offset = false, 0
local settingsPreview
local textures
function ns.BarTextures()
    if not textures then
        local names, order
        textures, names, order = EUI.BuildBarTextureTables(true)
        if EUI.AppendSharedMediaTextures then EUI.AppendSharedMediaTextures(names, order, nil, textures) end
        ns.BarTextureNames, ns.BarTextureOrder = names, order
    end
    return textures
end
local initializedConfig
local cachedStyle, styleConfig
local function Config()
    EllesmereUIDB = EllesmereUIDB or {}
    EllesmereUIDB.threatMeter = EllesmereUIDB.threatMeter or {}
    local c = EllesmereUIDB.threatMeter
    if c == initializedConfig then return c end
    for key, value in pairs(defaults) do
        if c[key] == nil then
            if type(value) == "table" then
                c[key] = {}; for k, v in pairs(value) do c[key][k] = v end
            else c[key] = value end
        end
    end
    initializedConfig = c
    return c
end
ns.Config = Config
function ns.GetTrackedUnit()
    local c = Config()
    return c.focusEnabled and c.source == "focus" and "focus" or "target"
end
function ns.SetFocusEnabled(enabled)
    local c = Config()
    c.focusEnabled = enabled
    if not enabled then c.source = "target" end
end
ns.DisplayValues = { none = "None", value = "Threat Value", relative = "Tank %", pull = "Pull %",
    value_relative = "Threat Value + Tank %", value_pull = "Threat Value + Pull %" }
ns.DisplayOrder = { "none", "value", "relative", "pull", "value_relative", "value_pull" }
function ns.GetDisplayedValue()
    local c = Config()
    if not c.showPercent then return c.showValue and "value" or "none" end
    return (c.showValue and "value_" or "") .. c.percentMode
end
function ns.SetDisplayedValue(v)
    if not ns.DisplayValues[v] then return end
    local c = Config()
    c.showValue = v == "value" or v == "value_relative" or v == "value_pull"
    c.showPercent = v ~= "none" and v ~= "value"
    if c.showPercent then c.percentMode = v:find("pull", 1, true) and "pull" or "relative" end
end
local function Say(s) print("|cff0cd29fEUI Threat:|r " .. s) end
local function Font(fs, size)
    local c = Config()
    local font = c.font ~= "__global" and EUI.ResolveFontName(c.font) or nil
    local flag
    if c.outlineMode == "outline" then flag = EUI.SlugFlag("OUTLINE, SLUG")
    elseif c.outlineMode == "thick" then flag = EUI.SlugFlag("THICKOUTLINE, SLUG")
    elseif c.outlineMode == "none" then flag = "" end
    EUI.ApplyModuleFont(fs, font, size, "essentials", flag)
end
local STYLE_DEFAULTS = {
    bars = { barTexture = "atrocity", iconStyle = "blizzard", classIconZoom = 0.06,
        leftTextOffsetX = 0, leftTextOffsetY = 0, rightTextOffsetX = 0, rightTextOffsetY = 0 },
    header = { hdrHeight = 22, hdrFontSize = 11, hdrBgColor = { r = 0.106, g = 0.106, b = 0.106 },
        hdrBgAlpha = 1, hdrTextUseAccent = true, hdrTextColor = { r = 1, g = 1, b = 1 },
        hdrTextOffX = 0, hdrTextOffY = 0, hdrBottomBorderSize = 0,
        hdrBottomBorderColor = { r = 0, g = 0, b = 0, a = 1 } },
    colors = { showClassColor = true, barColorUseAccent = true, barColor = { r = 0.35, g = 0.55, b = 0.8 },
        barFillAlpha = 1, bgR = 0, bgG = 0, bgB = 0, bgAlpha = 0.75,
        barBgR = 0, barBgG = 0, barBgB = 0, barBgAlpha = 0.045, barBgUseClassColor = false,
        leftTextUseClassColor = false, rightTextUseClassColor = false,
        leftTextColor = { r = 1, g = 1, b = 1 }, rightTextColor = { r = 1, g = 1, b = 1 } },
    borders = { windowBorderTexture = "solid", windowBorderSize = 0, windowBorderSizePx = false,
        windowBorderColor = { r = 0, g = 0, b = 0, a = 1 }, windowBorderIncludeHeader = true,
        borderTexture = "solid", borderSize = 0, borderSizePx = false,
        borderR = 0, borderG = 0, borderB = 0, borderA = 1,
        borderTextureOffset = false, borderTextureOffsetY = false, borderTextureShiftX = 0, borderTextureShiftY = 0 },
}
local Copy = EUI.Lite.DeepCopy
local soundPaths, soundNames, soundOrder
function ns.Sounds()
    if not soundPaths then
        soundPaths, soundNames, soundOrder = EUI.BuildAlertSoundTables()
        EUI.AppendSharedMediaSounds(soundPaths, soundNames, soundOrder)
    end
    return soundPaths, soundNames, soundOrder
end
function ns.PlaySoundKey(key)
    local path = ns.Sounds()[key]
    if type(path) == "number" then
        if path ~= 1 then PlaySound(path, "Master") end
    elseif path then PlaySoundFile(path, "Master") end
end
local warned, warningMob = false, nil
function ns.CheckWarning(me, source)
    local c = Config()
    if not c.enabled or not c.warnSound or not source or not me then
        warned, warningMob = false, nil
        return
    end
    local identity = ns.PublicCall(UnitGUID, source) or source
    if warningMob ~= identity then warned = false; warningMob = identity end
    local form = ns.PublicCall(GetShapeshiftFormID)
    local tank = ns.PublicCall(UnitGroupRolesAssigned, "player") == "TANK" or form == 5 or form == 8 or form == 18
    local scaled = ns.PublicNumber(me.scaledKey)
    local over = not me.holdsAggro and scaled
        and scaled >= c.warnAt and not (c.warnSkipTank and tank)
    if over and not warned then ns.PlaySoundKey(c.warnSoundKey) end
    warned = over and true or false
end

local function PrepareEntries(entries)
    local me
    for _, entry in ipairs(entries) do
        if entry.own or (entry.unit and ns.PublicCall(UnitIsUnit, entry.unit, "player") == true) then me = entry; break end
    end
    if Config().pullBar then
        local pull = ns.PullEntry(me, pullEntry)
        if pull then entries[#entries + 1] = pull end -- reference follows the sorted participants
    end
    return me
end
function ns.GetStyleGroup(group)
    local c = Config()
    local source = c.appearance and c.appearance[group] or {}
    local result = {}
    for key, fallback in pairs(STYLE_DEFAULTS[group]) do
        local value = source[key]
        if value == nil then value = fallback end
        result[key] = value
    end
    return result
end
function ns.SetStyleValues(group, values)
    local c = Config()
    c.appearance[group] = c.appearance[group] or {}
    for key, value in pairs(values) do c.appearance[group][key] = Copy(value) end
    ns.ApplyStyle()
    if EUI.RefreshPage then EUI:RefreshPage() end
end
local function Style()
    local c = Config()
    local font = EUI.GetFontPath("essentials")
    local outline = EUI.GetFontOutlineFlag("essentials")
    local accent = EUI.ELLESMERE_GREEN or {}
    if cachedStyle and styleConfig == c and cachedStyle.globalFont == font and cachedStyle.globalOutline == outline
        and cachedStyle.accentR == accent.r and cachedStyle.accentG == accent.g and cachedStyle.accentB == accent.b then
        return cachedStyle, cachedStyle.barHeight, cachedStyle.barSpacing
    end
    local dm = {}
    for group in pairs(STYLE_DEFAULTS) do
        for key, value in pairs(ns.GetStyleGroup(group)) do dm[key] = value end
    end
    dm.barHeight, dm.barSpacing = c.barHeight, c.barSpacing
    dm.fontSize = c.fontSize
    dm.globalFont, dm.globalOutline = font, outline
    dm.accentR, dm.accentG, dm.accentB = accent.r, accent.g, accent.b
    cachedStyle, styleConfig = dm, c
    return dm, dm.barHeight, dm.barSpacing
end
local function Accent()
    return EUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
end
local function PaintText(fs, color)
    color = color or { r = 1, g = 1, b = 1 }
    fs:SetTextColor(color.r, color.g, color.b)
end
local function Border(target, cfg, window)
    local size = (window and cfg.windowBorderSize or cfg.borderSize) or 0
    local texture = (window and cfg.windowBorderTexture or cfg.borderTexture) or "solid"
    local color = window and cfg.windowBorderColor or
        { r = cfg.borderR, g = cfg.borderG, b = cfg.borderB, a = cfg.borderA }
    color = color or {}
    local exact
    if window then exact = cfg.windowBorderSizePx else exact = cfg.borderSizePx end
    local px = size > 0 and EUI.BorderPx(exact, size, texture) or nil
    EUI.ApplyBorderStyle(target, size, color.r or 0, color.g or 0, color.b or 0, color.a or 1,
        texture, not window and cfg.borderTextureOffset or nil, not window and cfg.borderTextureOffsetY or nil,
        not window and cfg.borderTextureShiftX or nil, not window and cfg.borderTextureShiftY or nil,
        "damagemeters", size, nil, px)
end
local function ApplyStyle(dm, frame, title)
    local c, header = Config(), frame.header
    frame.sourceBtn.label:SetText(ns.GetTrackedUnit() == "focus" and "Focus" or "Target")
    if frame._style == dm then return frame._headerHeight end
    frame._style = dm
    local hd, colors, borders = dm, dm, dm
    header:SetHeight(c.showHeader and (hd.hdrHeight or 22) or 0.001)
    header:SetShown(c.showHeader)
    local bg = hd.hdrBgColor or { r = 0.106, g = 0.106, b = 0.106 }
    header.bg:SetColorTexture(bg.r, bg.g, bg.b, hd.hdrBgAlpha or 1)
    Font(title, hd.hdrFontSize or c.fontSize)
    title:ClearAllPoints()
    title:SetPoint("LEFT", 6 + (hd.hdrTextOffX or 0), hd.hdrTextOffY or 0)
    title:SetPoint("RIGHT", (c.focusEnabled and -82 or -28) + (hd.hdrTextOffX or 0), hd.hdrTextOffY or 0)
    Font(frame.sourceBtn.label, hd.hdrFontSize or c.fontSize)
    local iconSize = math.min(22, hd.hdrHeight or 22)
    frame.settingsBtn.icon:SetSize(iconSize, iconSize)
    frame.sourceBtn:SetShown(c.focusEnabled)
    PaintText(title, hd.hdrTextUseAccent ~= false and Accent() or hd.hdrTextColor)
    header.line:SetHeight(math.max(1, hd.hdrBottomBorderSize or 0))
    local line = hd.hdrBottomBorderColor or {}
    header.line:SetColorTexture(line.r or 0, line.g or 0, line.b or 0, line.a or 1)
    header.line:SetShown((hd.hdrBottomBorderSize or 0) > 0)
    frame.bg:SetColorTexture(colors.bgR or 0, colors.bgG or 0, colors.bgB or 0, colors.bgAlpha or 0.75)
    local target = frame.border
    target:ClearAllPoints()
    if borders.windowBorderIncludeHeader == false then
        target:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    else target:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0) end
    target:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    target:SetFrameLevel(header:GetFrameLevel() + 4)
    Border(target, borders, true)
    frame._headerHeight = c.showHeader and header:GetHeight() or 0
    return frame._headerHeight
end

-- Live meter and settings preview have the same visual structure.
local function CreateSurface(parent, name)
    ns.BarTextures()
    local surface = CreateFrame("Frame", name, parent)
    surface.rows = {}
    surface.bg = surface:CreateTexture(nil, "BACKGROUND")
    surface.bg:SetAllPoints()
    surface.border = CreateFrame("Frame", nil, surface)
    local header = CreateFrame("Frame", nil, surface)
    surface.header = header
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.line = header:CreateTexture(nil, "OVERLAY")
    header.line:SetPoint("BOTTOMLEFT")
    header.line:SetPoint("BOTTOMRIGHT")
    surface.title = header:CreateFontString(nil, "OVERLAY")
    Font(surface.title, Config().fontSize)
    surface.title:SetJustifyH("LEFT")
    -- Same EUI glyph size and idle/hover opacity as Damage Meter headers.
    local settings = CreateFrame("Button", nil, header)
    surface.settingsBtn = settings
    settings:SetWidth(22)
    settings:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    settings:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    settings:SetFrameLevel(header:GetFrameLevel() + 2)
    settings.icon = settings:CreateTexture(nil, "ARTWORK")
    settings.icon:SetSize(22, 22)
    settings.icon:SetPoint("CENTER", settings, "CENTER", 0, 0)
    settings.icon:SetTexture("Interface\\AddOns\\EllesmereUIForeverEssentials\\Media\\dm_settings.png")
    settings.icon:SetDesaturated(true)
    settings.icon:SetVertexColor(1, 1, 1, 0.4)
    settings:SetScript("OnEnter", function() settings.icon:SetVertexColor(1, 1, 1, 0.9) end)
    settings:SetScript("OnLeave", function() settings.icon:SetVertexColor(1, 1, 1, 0.4) end)
    local source = CreateFrame("Button", nil, header)
    surface.sourceBtn = source
    source:SetWidth(54)
    source:SetPoint("TOPRIGHT", header, "TOPRIGHT", -25, 0)
    source:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -25, 0)
    source:SetFrameLevel(header:GetFrameLevel() + 2)
    source.label = source:CreateFontString(nil, "OVERLAY")
    source.label:SetAllPoints(source)
    source.label:SetJustifyH("CENTER")
    source.label:SetJustifyV("MIDDLE")
    Font(source.label, 11)
    source.label:SetTextColor(1, 1, 1, 0.65)
    source:SetScript("OnEnter", function() source.label:SetTextColor(1, 1, 1, 1) end)
    source:SetScript("OnLeave", function() source.label:SetTextColor(1, 1, 1, 0.65) end)
    return surface
end
local function Position()
    frame:ClearAllPoints()
    local p = Config().position
    if p then frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else frame:SetPoint("CENTER", UIParent, "CENTER", 340, -120) end
end
local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    Config().position = { point = point, relPoint = relPoint, x = x, y = y }
end

local function MakeRow(i, frame, rows)
    local row = CreateFrame("Frame", nil, frame)
    row.fill = CreateFrame("StatusBar", nil, row)
    row.fill:SetAllPoints()
    row.fill:SetMinMaxValues(0, 100)
    row.border = CreateFrame("Frame", nil, row)
    row.border:SetAllPoints()
    row.border:SetFrameLevel(row.fill:GetFrameLevel() + 1)
    -- Border styling hides its frame when the border size is zero.
    -- Text must have an independent, always-visible parent above that frame.
    row.text = CreateFrame("Frame", nil, row)
    row.text:SetAllPoints()
    row.text:SetFrameLevel(row.border:GetFrameLevel() + 1)
    row.classIcon = row.text:CreateTexture(nil, "ARTWORK")
    row.petIcon = row.text:CreateTexture(nil, "ARTWORK")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.045)
    row.label = row.text:CreateFontString(nil, "OVERLAY")
    row.label:SetPoint("LEFT", 5, 0)
    row.label:SetJustifyH("LEFT")
    row.value = row.text:CreateFontString(nil, "OVERLAY")
    row.value:SetPoint("RIGHT", -5, 0)
    row.value:SetWidth(64)
    row.value:SetJustifyH("RIGHT")
    row.label:SetPoint("RIGHT", row.value, "LEFT", -5, 0)
    row.self = row.fill:CreateTexture(nil, "OVERLAY")
    row.self:SetPoint("TOPLEFT")
    row.self:SetPoint("BOTTOMLEFT")
    row.self:SetWidth(2)
    row.self:SetColorTexture(1, 1, 1, 0.95)
    rows[i] = row
    return row
end

local demo = {
    { name = "Tank", class = "WARRIOR", percent = 100 },
    { name = "You", class = "MAGE", percent = 84, own = true },
    { name = "Rogue", class = "ROGUE", percent = 67 },
    { name = "Hunter", class = "HUNTER", percent = 43 },
    { name = "Pet", class = "HUNTER", isPet = true, percent = 26 },
    { name = "Healer", class = "PRIEST", percent = 18 },
}

local function PreviewEntries()
    local entries = {}
    for i, sample in ipairs(demo) do
        if Config().pets or not sample.isPet then
            local entry = Copy(sample)
            entry.rawKey, entry.threat = sample.percent * 120, sample.percent * 120
            entry.scaledKey = i == 1 and 100 or sample.percent / 1.1
            entry.displayPercent, entry.holdsAggro = sample.percent, i == 1
            entry.percent = entry.scaledKey -- same entry contract as the live threat API
            entries[#entries + 1] = entry
        end
    end
    PrepareEntries(entries)
    return entries
end

local function RowIcons(row, class, isPet, dm, size)
    -- Reset reused rows before assigning icons: a pet can become a player row
    -- after sorting or changing Include Pets.
    row.classIcon:Hide()
    row.petIcon:Hide()
    local style = dm.iconStyle or "blizzard"
    if style == "none" then return 0 end
    if isPet then class = nil end -- pets have one pet icon, never a second class icon
    local x = 0
    local coords
    if style == "blizzard" then
        -- Threat units do not provide reliable specialization art. Use the same
        -- class fallback as Damage Meters instead of guessing a specialization.
        coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            local zoom = dm.classIconZoom or 0.06
            local dx, dy = (coords[2] - coords[1]) * zoom, (coords[4] - coords[3]) * zoom
            row.classIcon:SetTexCoord(coords[1] + dx, coords[2] - dx, coords[3] + dy, coords[4] - dy)
        end
    else
        coords = class and EUI.CLASS_ICON_SPRITE_COORDS and EUI.CLASS_ICON_SPRITE_COORDS[class]
        if coords then
            row.classIcon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\" .. style .. ".tga")
            row.classIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        end
    end
    if coords then
        row.classIcon:SetSize(size, size)
        row.classIcon:ClearAllPoints()
        row.classIcon:SetPoint("LEFT", row, "LEFT", x, 0)
        row.classIcon:Show()
        x = x + size + 2
    end
    if isPet then
        row.petIcon:SetTexture(132161) -- generic pet / Beast Call icon
        row.petIcon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
        row.petIcon:SetSize(size, size)
        row.petIcon:ClearAllPoints()
        row.petIcon:SetPoint("LEFT", row, "LEFT", x, 0)
        row.petIcon:Show()
        x = x + size + 2
    end
    return x
end

local function RenderRows(frame, entries, offset, count, dm, barHeight, spacing, headerHeight, testing)
    local rows, colors, borders = frame.rows, dm, dm
    local c = Config()
    local fontSize = dm.fontSize or c.fontSize
    local texture = EUI.ResolveTexturePath(textures, dm.barTexture or "atrocity", "Interface\\Buttons\\WHITE8X8")
    for i = 1, count do
        local data = entries[i + offset]
        local row = rows[i] or MakeRow(i, frame, rows)
        local index = c.growUp and (count - i) or (i - 1)
        local rowY = -headerHeight - index * (barHeight + spacing)
        -- Both anchors must share the top edge. A RIGHT (vertical-center)
        -- anchor to the window overconstrains height and overlaps row content.
        if row._layoutY ~= rowY or row._style ~= dm then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, rowY)
            row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, rowY)
            row:SetHeight(barHeight)
        end
        local class, own, name, isPet
        if data.pull then
            name, own, isPet = "Pull Aggro", false, false
        elseif testing then
            class, own, name, isPet = data.class, data.own, data.name, data.isPet
            if own then class = ns.UnitAppearance("player") end
        else
            class, isPet = ns.UnitAppearance(data.unit, tokenBuffer.tokens)
            own = UnitIsUnit(data.unit, "player")
            if ns.IsSecret(own) then own = false end
            name = EUI.WithSurname(UnitName(data.unit))
            if not ns.IsSecret(name) and name == nil then name = data.unit end
        end
        local restyle = row._style ~= dm
        local iconsChanged = restyle or row._class ~= class or row._isPet ~= isPet
        if iconsChanged then
            row._iconWidth = RowIcons(row, class, isPet, dm, barHeight)
            row._class, row._isPet = class, isPet
        end
        local iconWidth = row._iconWidth
        if restyle or iconsChanged then
            row.fill:ClearAllPoints()
            row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", iconWidth, 0)
            row.fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            row.label:ClearAllPoints()
            row.value:ClearAllPoints()
            row.value:SetPoint("RIGHT", -5 + (dm.rightTextOffsetX or 0), dm.rightTextOffsetY or 0)
            row.label:SetPoint("LEFT", iconWidth + 5 + (dm.leftTextOffsetX or 0), dm.leftTextOffsetY or 0)
            row.label:SetPoint("RIGHT", row.value, "LEFT", -5, 0)
        end
        if restyle then
            Font(row.label, fontSize)
            Font(row.value, fontSize)
            row.fill:SetStatusBarTexture(texture)
            Border(row.border, borders, false)
            row._style = dm
        end
        local color = class and RAID_CLASS_COLORS[class] and EUI.GetClassColor(class)
        local fillColor = colors.showClassColor ~= false and color or nil
        fillColor = fillColor or (colors.barColorUseAccent ~= false and Accent() or colors.barColor) or Accent()
        if data.pull then fillColor = c.pullColor
        elseif own and c.playerColorOn then fillColor = c.playerColor
        elseif data.holdsAggro and c.tankColorOn then fillColor = c.tankColor end
        row.fill:SetStatusBarColor(fillColor.r, fillColor.g, fillColor.b, colors.barFillAlpha or 1)
        local bg = colors.barBgUseClassColor and color
        row.bg:SetColorTexture(bg and bg.r or colors.barBgR, bg and bg.g or colors.barBgG,
            bg and bg.b or colors.barBgB, colors.barBgAlpha)
        PaintText(row.label, colors.leftTextUseClassColor and color or colors.leftTextColor)
        PaintText(row.value, colors.rightTextUseClassColor and color or colors.rightTextColor)
        -- No arithmetic/formatting in Lua: hand possibly secret percentages to UI sinks.
        row.value:SetWidth(c.showValue and c.showPercent and 140 or (c.showValue and 80 or (c.showPercent and 90 or 0)))
        local value = data.displayPercent
        local percent = value
        if c.percentMode == "pull" then percent = data.percent
        elseif data.pullPercent then percent = nil end -- do not label a pull fallback as tank %
        if data.pull then value, percent = 100, 100 end
        if type(value) == "number" then row.fill:SetValue(value) else row.fill:SetValue(0) end
        if data.aggroOnly then
            row.fill:SetValue(100)
            row.value:SetText((c.showValue or c.showPercent) and "Aggro" or "")
        else
            local raw = c.showValue and data.threat
            local rawFormat, rawText
            if type(raw) == "number" then
                if ns.IsSecret(raw) then rawFormat, rawText = "%.0f", raw
                elseif ns.PublicNumber(raw) then rawFormat, rawText = "%s", EUI.AbbreviateNumber(raw) end
            end
            local pctFormat = "%.0f%%"
            if not c.showPercent or (data.pull and rawFormat) then percent = nil end
            if rawFormat and type(percent) == "number" then
                row.value:SetFormattedText(rawFormat .. "  " .. pctFormat, rawText, percent)
            elseif rawFormat then row.value:SetFormattedText(rawFormat, rawText)
            elseif type(percent) == "number" then row.value:SetFormattedText(pctFormat, percent)
            else row.value:SetText((c.showValue or c.showPercent) and "?" or "") end
        end
        row.label:SetText(name)
        row._threatUnit = data.pull and "pull" or (testing and "preview" or data.unit)
        row._aggroOnly = data.aggroOnly == true
        row._aggroPriority = data.priority or 0
        row._layoutY = rowY
        row.self:SetShown(own == true)
        row:Show()
    end
    for i = count + 1, #rows do rows[i]:Hide() end
end

-- A separate settings-only frame shares the live meter's styling and renderer.
-- It has no drag/resize handlers, threat queries, or saved-position writes.
function ns.CreateSettingsPreview(parent, availableWidth, onHeightChanged)
    local view = settingsPreview
    if not view then
        view = CreateSurface(parent)
        settingsPreview = view
        view.title:SetText("Threat - Training Dummy")
        view.caption = view:CreateFontString(nil, "OVERLAY")
        Font(view.caption, 10)
        view.caption:SetPoint("BOTTOM", 0, 6)
        view.caption:SetTextColor(0.65, 0.65, 0.65)
        view.caption:SetText("Preview")
        function view:Refresh()
            local parent = self:GetParent()
            if not parent then return end
            local dm, barHeight, spacing = Style()
            local entries = PreviewEntries()
            local headerHeight = Config().showHeader and (dm.hdrHeight or 22) or 0
            local height = headerHeight + #entries * barHeight + math.max(0, #entries - 1) * spacing + 26
            local width = Config().width
            self:SetSize(width, height)
            local available = parent:GetWidth() > 0 and parent:GetWidth() or self.availableWidth
            self:SetScale(math.min(1, math.max(100, available - 40) / width))
            self:ClearAllPoints()
            self:SetPoint("CENTER", parent, "CENTER", 0, 0)
            local actualHeader = ApplyStyle(dm, self, self.title)
            Font(self.caption, 10)
            RenderRows(self, entries, 0, #entries, dm, barHeight, spacing, actualHeader, true)
            self.previewHeight = height * self:GetScale() + 30
            if self.onHeightChanged then self.onHeightChanged(self.previewHeight) end
        end
        view:SetScript("OnShow", function(self) self:Refresh() end)
    end
    -- WoW frames survive Lua GC. Reuse the surface when the page is rebuilt.
    view.availableWidth, view.onHeightChanged = availableWidth, onHeightChanged
    view:SetParent(parent)
    if not parent._threatPreviewResizeHook then
        parent._threatPreviewResizeHook = true
        local lastWidth
        parent:HookScript("OnSizeChanged", function(_, width)
            if width == lastWidth then return end
            lastWidth = width
            if settingsPreview:GetParent() == parent and settingsPreview:IsVisible() then settingsPreview:Refresh() end
        end)
    end
    view:Refresh()
    view:Show()
    return view
end

-- Threat includes pet/observed combat, using the shared evaluator's existing
-- state argument. Only the single combat modes need a local fallback.
local visibilityCaps = { partyIncludesRaid = false }
function ns.IsVisible(c, state)
    if c.visibilityMatch ~= "any" and EUI.CheckVisibilityOptions(c) then return false end
    local result = EUI.EvalVisibilityExtended(c, "visibility", state, visibilityCaps)
    if result ~= nil then return result == true end
    if c.visibility == "in_combat" then return state.inCombat end
    if c.visibility == "out_of_combat" then return not state.inCombat end
    return EUI.EvalVisibility(c) == true
end

function ns.Refresh()
    if not frame then return end
    local c = Config()
    local testing = preview or (c.enabled and EUI._unlockActive)
    if not c.enabled and not preview then
        frame:Hide()
        ns.CheckWarning(nil, nil)
        return
    end
    local source = ns.ResolveSource(ns.GetTrackedUnit())
    local petCombat = c.pets and UnitAffectingCombat and UnitAffectingCombat("pet")
    petCombat = not ns.IsSecret(petCombat) and petCombat == true
    local observedCombat = source and UnitAffectingCombat and UnitAffectingCombat(source)
    observedCombat = not ns.IsSecret(observedCombat) and observedCombat == true
    local state = visibilityState
    state.inCombat = InCombatLockdown() or petCombat or observedCombat
    state.inRaid = IsInRaid()
    state.inParty = not state.inRaid and GetNumSubgroupMembers() > 0
    local visible = testing or ns.IsVisible(c, state)
    frame:SetShown(visible)
    if not visible then ns.CheckWarning(nil, nil); return end
    local dm, barHeight, spacing = Style()
    local headerHeight = ApplyStyle(dm, frame, title)
    local entries = emptyEntries
    title:SetText("Threat")
    if testing then
        entries = PreviewEntries()
        title:SetText("Threat - Preview")
    elseif source then
        title:SetFormattedText("Threat - %s", EUI.WithSurname(UnitName(source))) -- UI sink accepts secret names
        if UnitDetailedThreatSituation then
            entries = ns.ReadThreat(ns.ThreatTokens(c.pets, source, tokenBuffer), source, UnitDetailedThreatSituation, threatBuffer)
        end
    end
    if not testing then
        local me = PrepareEntries(entries)
        ns.CheckWarning(me, source)
    else ns.CheckWarning(nil, nil) end
    local capacity = math.max(1, math.floor((frame:GetHeight() - headerHeight + spacing) / (barHeight + spacing)))
    offset = math.min(offset, math.max(0, #entries - capacity))
    local count = math.min(capacity, #entries - offset)
    RenderRows(frame, entries, offset, count, dm, barHeight, spacing, headerHeight, testing)
end

function ns.ApplyStyle()
    SetActive()
    cachedStyle = nil
    ns.Refresh()
    if settingsPreview and settingsPreview:IsVisible() then settingsPreview:Refresh() end
end
function ns.Apply()
    SetActive()
    if not frame then return end
    frame:SetSize(Config().width, Config().height)
    Position()
    offset = 0
    ns.ApplyStyle()
end
function ns.SetPreview(value)
    preview = value
    offset = 0
    SetActive()
    ns.Refresh()
end
function ns.IsPreview() return preview end

function ns.Diagnose()
    local version, build, _, iface = GetBuildInfo()
    Say("build=" .. tostring(version) .. "/" .. tostring(build) .. " interface=" .. tostring(iface))
    Say("source=" .. ns.GetTrackedUnit() .. " combat=" .. tostring(InCombatLockdown()))
    local source = ns.ResolveSource(ns.GetTrackedUnit())
    Say("resolved=" .. tostring(source))
    Say("code: data=" .. tostring(ns.THREAT_DATA_REV) .. " ui=" .. UI_REV)
    if not UnitDetailedThreatSituation then Say("Threat API unavailable"); return end
    local keys = { "tanking", "status", "scaled%", "raw%", "threat" }
    local function Describe(v)
        if ns.IsSecret(v) then return "SECRET (" .. type(v) .. ")" end
        return tostring(v)
    end
    -- Report the last rendered state before fetching new API values. The two
    -- snapshots may differ if the enemy changes victims during this command.
    Say("rendered: scroll=" .. offset .. " preview=" .. tostring(preview))
    for i, row in ipairs(rows or {}) do
        if row:IsShown() then
            local top = row:GetTop()
            Say("row=" .. i .. " unit=" .. tostring(row._threatUnit)
                .. " aggroOnly=" .. tostring(row._aggroOnly)
                .. " priority=" .. tostring(row._aggroPriority)
                .. " layoutY=" .. tostring(row._layoutY) .. " screenTop=" .. Describe(top))
        end
    end
    if not source then Say("No hostile target/focus resolved"); return end
    local tokens = ns.ThreatTokens(Config().pets, source)
    local ordered, restricted, sorted, hasAggro = ns.ReadThreat(tokens, source, UnitDetailedThreatSituation)
    Say("collected: restricted=" .. tostring(restricted) .. " sorted=" .. tostring(sorted) .. " aggro=" .. tostring(hasAggro))
    for i, entry in ipairs(ordered) do
        Say("rank=" .. i .. " unit=" .. entry.unit .. " aggroOnly=" .. tostring(entry.aggroOnly == true)
            .. " priority=" .. entry.priority .. " tier=" .. entry.sortTier .. " score=" .. entry.sortValue)
    end
    -- Include self and a few teammates without printing names or secret data.
    local inspected = { "player" }
    for _, token in ipairs(tokens) do
        if token ~= "player" and #inspected < 6 then inspected[#inspected + 1] = token end
    end
    for _, token in ipairs(inspected) do
        local ok, a, b, c, d, e = pcall(UnitDetailedThreatSituation, token, source)
        if not ok then Say(token .. ": API call failed")
        else
            local values, parts = { a, b, c, d, e }, {}
            for i = 1, 5 do parts[i] = keys[i] .. "=" .. Describe(values[i]) end
            Say(token .. ": " .. table.concat(parts, ", "))
        end
    end
end

local function OpenSettings()
    if InCombatLockdown() then Say("Open full settings after combat."); return end
    EUI:NavigateToElementSettings("EllesmereUIForeverEssentials", "Threat")
end

-- Kept independent of the load-on-demand options addon so quick toggles also
-- work in combat before the settings window has ever been opened.
function ns.QuickMenuItems(page)
    local items = {}
    local function Toggle(key, label)
        items[#items + 1] = { label = label,
            action = function() Config()[key] = not Config()[key] end }
    end
    if page and page ~= "source" then items[#items + 1] = { label = "< Back", page = "main" } end
    if page == "source" then
        for _, key in ipairs(Config().focusEnabled and { "target", "focus" } or { "target" }) do
            local value = key
            items[#items + 1] = { label = value == "target" and "Target" or "Focus",
                action = function() Config().source = value; offset = 0 end }
        end
    elseif page == "values" then
        for _, key in ipairs(ns.DisplayOrder) do
            local value = key
            items[#items + 1] = { label = ns.DisplayValues[value],
                action = function() ns.SetDisplayedValue(value) end }
        end
    else
        if Config().focusEnabled then
            items[#items + 1] = { label = "Tracked Unit: " .. (ns.GetTrackedUnit() == "focus" and "Focus" or "Target") .. " >", page = "source" }
        end
        items[#items + 1] = { label = "Displayed Value >", page = "values" }
        Toggle("pets", "Include Pets")
        Toggle("warnSound", "Warning Sound")
        Toggle("locked", "Lock Position")
        items[#items + 1] = { label = "Threat Settings...", action = function() OpenSettings() end, navigate = true }
    end
    return items
end

function ns.ShowQuickMenu(anchor, page)
    local items = {}
    for _, item in ipairs(ns.QuickMenuItems(page ~= "main" and page or nil)) do
        items[#items + 1] = { text = item.label,
            onClick = function()
                if item.page then ns.ShowQuickMenu(anchor, item.page); return end
                item.action()
                if not item.navigate then
                    ns.ApplyStyle()
                    if EUI.RefreshPage then EUI:RefreshPage() end
                end
            end }
    end
    EUI.ShowContextMenu(anchor, items, { below = true })
end

CreateWindow = function()
    frame = CreateSurface(UIParent, "EllesmereUIThreatMeterFrame")
    ns.frame = frame
    rows, title = frame.rows, frame.title
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(200, 100, 700, 900)
    local header = frame.header
    local settings = frame.settingsBtn
    settings:SetScript("OnClick", function(self) ns.ShowQuickMenu(self) end)
    frame.sourceBtn:SetScript("OnClick", function(self) ns.ShowQuickMenu(self, "source") end)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() if not Config().locked and not EUI._unlockActive then frame:StartMoving() end end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePosition() end)
    local resize = CreateFrame("Button", nil, frame)
    resize:SetPoint("BOTTOMRIGHT")
    resize:SetSize(16, 16)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not Config().locked and not EUI._unlockActive then frame:StartSizing("BOTTOMRIGHT") end
    end)
    resize:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        Config().width, Config().height = frame:GetSize()
        SavePosition()
        ns.Refresh()
    end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        ns.Refresh()
    end)
    frame:SetSize(Config().width, Config().height)
    Position()
    EUI:RegisterUnlockElements({ EUI.MakeUnlockElement({
        key = "EUI_ThreatMeter", label = "Threat Meter", group = "Forever Essentials", order = 731,
        getFrame = function() if Config().enabled or preview then return frame end end,
        getSize = function() return frame:GetSize() end,
        setWidth = function(_, width) Config().width = math.max(200, width); frame:SetWidth(Config().width); ns.Refresh() end,
        setHeight = function(_, height) Config().height = math.max(100, height); frame:SetHeight(Config().height); ns.Refresh() end,
        savePos = function(_, point, relPoint, x, y)
            Config().position = { point = point, relPoint = relPoint or point, x = x, y = y }
        end,
        loadPos = function()
            local p = Config().position
            if p then return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y } end
        end,
        clearPos = function() Config().position = nil end,
        applyPos = Position,
    }) }, addon)
end

local threatEvents = {
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_TARGET", "UNIT_PET",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "GROUP_ROSTER_UPDATE",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_MOUSEOVER_UNIT",
    "UNIT_FLAGS", "UNIT_NAME_UPDATE", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ROLES_ASSIGNED", "UPDATE_SHAPESHIFT_FORM",
}
local function OnEvent(_, event, unit)
    local source = ns.GetTrackedUnit()
    if event == "UNIT_THREAT_LIST_UPDATE" and unit then
        local hostile = ns.ResolveSource(source)
        if not hostile or ns.PublicCall(UnitIsUnit, hostile, unit) == false then return end
    end
    if (event == "PLAYER_TARGET_CHANGED" and source == "target")
        or (event == "PLAYER_FOCUS_CHANGED" and source == "focus")
        or event == "PLAYER_ENTERING_WORLD" then
        warned, warningMob = false, nil
        offset = 0
    end
    ns.Refresh()
end
SetActive = function()
    local enabled = Config().enabled or preview
    if enabled == active then return end
    active = enabled
    if enabled then
        if not frame then CreateWindow() end
        for _, event in ipairs(threatEvents) do module.addon:RegisterEvent(event, OnEvent) end
        EUI.RegisterVisibilityUpdater(ns.Refresh)
    else
        for _, event in ipairs(threatEvents) do module.addon:UnregisterEvent(event) end
        EUI.UnregisterVisibilityUpdater(ns.Refresh)
        frame:Hide()
        ns.CheckWarning(nil, nil)
    end
end
EUI._ThreatMeter = { Apply = ns.Apply, ApplyStyle = ns.ApplyStyle,
    ApplyPosition = function() if frame then Position() end end,
    Cfg = Config, Get = function(key) return Config()[key] end, Sounds = ns.Sounds }
-- Reuse the parent module's lifecycle; disabled Threat adds no bootstrap frame.
module.addon.OnEnable = function() ns.Apply() end

SLASH_ELLESMEREUITHREAT1 = "/euitm"
SlashCmdList.ELLESMEREUITHREAT = function(input)
    local cmd = (input or ""):lower():match("^%s*(.-)%s*$")
    local c = Config()
    if cmd == "test" then ns.SetPreview(not preview)
    elseif cmd == "debug" then ns.Diagnose()
    elseif cmd == "target" or cmd == "focus" then c.source = c.focusEnabled and cmd or "target"; offset = 0; ns.Apply()
    elseif cmd == "show" then c.enabled = true; ns.Apply()
    elseif cmd == "hide" then c.enabled = false; preview = false; ns.Apply()
    elseif cmd == "lock" then c.locked = not c.locked; Say(c.locked and "Locked" or "Unlocked")
    elseif cmd == "pets" then c.pets = not c.pets; ns.ApplyStyle(); Say(c.pets and "Pets shown" or "Pets hidden")
    elseif cmd == "reset" then c.position = nil; c.width = 320; c.height = 210; ns.Apply()
    else Say("/euitm test | debug | target | focus | show | hide | lock | pets | reset") end
end
