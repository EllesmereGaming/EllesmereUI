if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_ThreatMeter.lua  (WoW Forever only)
--  Threat on your target (or focus) for everyone in the group, one bar each,
--  sorted by threat, with an optional pull aggro line and a warning sound. The
--  data comes from the ThreatData file and the window chrome (header buttons,
--  menus, lock, grip, drag and snapping) from the Window file, both listed
--  before this one. A fixed-size window: rows past what fits scroll with the
--  mouse wheel.
-------------------------------------------------------------------------------
local ADDON_NAME, module = ...
local ns = module.ThreatMeter
local EUI = EllesmereUI
local Look = ns.Look

local UPDATE_DELAY = 0.2
local FOLLOW_INTERVAL = 0.5
local PREVIEW_SECONDS = 10
local MIN_W, MIN_H = ns.MIN_W, ns.MIN_H
local UNLOCK_KEY = "EUI_ThreatMeter"
local BORDER_KEY = "threatmeter"
EUI.RegisterBorderDefaults(BORDER_KEY, EUI.BORDER_DEFAULTS_BARS)
ns.BORDER_KEY = BORDER_KEY

-- Forward declarations (window scripts and the unlock element call these).
local RequestUpdate, Repaint, CreateWindow

-------------------------------------------------------------------------------
--  Settings: EllesmereUIDB.threatMeter, account-wide. Read() never creates the
--  table and Get() falls back to DEFAULTS, so nothing is written until the
--  user changes something (Cfg() is the write accessor). Default tables are
--  shared: callers read them, and writers assign a new table.
--  position is { point, relPoint, x, y } (unlock mode and the default) or
--  { x, y } (a header drag or grip resize: the top-left corner from the
--  screen's bottom-left). onlyWithThreat = false keeps the meter on screen
--  while it has nothing to list.
-------------------------------------------------------------------------------
local DEFAULTS = {
    enabled = false, source = "target", focusEnabled = false, pets = true,
    width = 320, height = 210, barHeight = 18, fontSize = 11, barSpacing = 2,
    position = { point = "CENTER", relPoint = "CENTER", x = 400, y = -100 },
    locked = false, snapDisabled = false, onlyWithThreat = true,
    growUp = false, showHeader = true,
    pullBar = true, pullColor = { r = 0, g = 0.55, b = 0 },
    showValue = true, showPercent = true, percentMode = "pull",
    warnSound = false, warnSoundKey = "none", warnAt = 80, warnSkipTank = true,
    playerColorOn = false, playerColor = { r = 0.8, g = 0.1, b = 0.1 },
    tankColorOn = false, tankColor = { r = 0.1, g = 0.6, b = 0.1 },
    font = "__global", outlineMode = "__global",
}

-- Appearance groups, stored under appearance[group] (the Damage Meters shape).
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
        borderTextureOffset = false, borderTextureShiftX = 0, borderTextureShiftY = 0,
        borderTextureOffsetY = false },
}

local _NOCFG = {}
local function Read()
    return EllesmereUIDB and EllesmereUIDB.threatMeter or _NOCFG
end

local function Cfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.threatMeter = EllesmereUIDB.threatMeter or {}
    return EllesmereUIDB.threatMeter
end

local Get

local function Triplet(r, g, b)
    if r == nil then return nil end
    return { r = r, g = g or 0, b = b or 0 }
end

-- Earlier versions saved these settings under other names (and scales). A
-- read falls through to the old key while the new one is unset; nothing is
-- migrated and the old keys are never removed.
local LEGACY = {
    position   = function(c) return c.pos end,
    pets       = function(c) if c.ignorePets ~= nil then return not c.ignorePets end end,
    fontSize   = function(c) return c.textSize end,
    barSpacing = function(c) return c.spacing end,
    playerColor = function(c) return Triplet(c.playerR, c.playerG, c.playerB) end,
    tankColor   = function(c) return Triplet(c.tankR, c.tankG, c.tankB) end,
    pullColor   = function(c) return Triplet(c.pullR, c.pullG, c.pullB) end,
    -- A chosen bar count becomes a window tall enough to show that many rows.
    height = function(c)
        local n = c.maxBars
        if type(n) ~= "number" then return nil end
        local gap = Get("barSpacing")
        local header = Get("showHeader") and ns.GetStyleValue("header", "hdrHeight") or 0
        return header + n * (Get("barHeight") + gap) - gap
    end,
}
local LEGACY_STYLE = {
    bars = { barTexture = function(c) return c.texture end },
    colors = {
        bgAlpha = function(c) return c.bgA end,
        barFillAlpha = function(c)
            if type(c.barOpacity) == "number" then return c.barOpacity / 100 end
        end,
    },
    borders = {
        windowBorderSize = function(c) return c.borderSize end,
        windowBorderColor = function(c)
            if c.borderR == nil then return nil end
            return { r = c.borderR, g = c.borderG or 0, b = c.borderB or 0, a = 1 }
        end,
    },
}

Get = function(key)
    local c = Read()
    local v = c[key]
    if v == nil then
        local legacy = LEGACY[key]
        if legacy then v = legacy(c) end
        if v == nil then v = DEFAULTS[key] end
    end
    return v
end

function ns.GetStyleValue(group, key)
    local c = Read()
    local v
    local ap = c.appearance
    if type(ap) == "table" and type(ap[group]) == "table" then v = ap[group][key] end
    if v == nil then
        local legacy = LEGACY_STYLE[group]
        legacy = legacy and legacy[key]
        if legacy then v = legacy(c) end
        if v == nil then v = STYLE_DEFAULTS[group][key] end
    end
    return v
end

-- A fresh merged copy of one appearance group (options getters).
function ns.GetStyleGroup(group)
    local result = {}
    for key in pairs(STYLE_DEFAULTS[group]) do result[key] = ns.GetStyleValue(group, key) end
    return result
end

-- Writes into the real saved appearance[group] table (created on first write)
-- and restyles. Callers whose toggle gates other rows refresh the page.
function ns.SetStyleValues(group, values)
    local c = Cfg()
    local ap = c.appearance
    if type(ap) ~= "table" then ap = {}; c.appearance = ap end
    local saved = ap[group]
    if type(saved) ~= "table" then saved = {}; ap[group] = saved end
    for key, value in pairs(values) do saved[key] = EUI.Lite.DeepCopy(value) end
    ns.ApplyStyle()
end

function ns.SetStyleValue(group, key, value)
    local c = Cfg()
    local ap = c.appearance
    if type(ap) ~= "table" then ap = {}; c.appearance = ap end
    local saved = ap[group]
    if type(saved) ~= "table" then saved = {}; ap[group] = saved end
    saved[key] = EUI.Lite.DeepCopy(value)
    ns.ApplyStyle()
end

ns.Get, ns.Cfg, ns.Read = Get, Cfg, Read

-------------------------------------------------------------------------------
--  Look (Global Settings > Style): "eui", "blizzard" or "classic", from the
--  account-wide flags useBlizzardStyle / useClassicStyle (Classic wins when
--  both are set). Read on the first call once the settings exist and kept
--  for the session: the art is set up once, so a flag the Style page writes
--  takes effect after the reload it asks for. On the addon's namespace,
--  where the Style page looks it up.
-------------------------------------------------------------------------------
local styleKey, forever
function module.TM_Style()
    if not styleKey then
        if not EllesmereUIDB then return "eui" end
        local c = Read()
        styleKey = (c.useClassicStyle and "classic") or (c.useBlizzardStyle and "blizzard") or "eui"
        -- Blizzard Style's WoW Forever variant, latched with it: the sibling
        -- flag the Style page writes together with the Blizzard one.
        forever = styleKey == "blizzard" and c.useForeverStyle == true
    end
    return styleKey
end
ns.TM_Style = module.TM_Style

-- True when the meter draws the WoW Forever variant this session (TM_Style
-- still reads "blizzard" then).
function module.TM_Forever()
    if not styleKey then module.TM_Style() end
    return forever == true
end

-- A stock look's one-time defaults on the account table c, once each (the
-- stamps; the controls stay the user's afterwards): Blizzard Style's lighter
-- background (WoW Forever's a little stronger, under its bronze frame),
-- Classic WoW UI's near-black window, the game's own bar fill and a
-- quarter-black bar track. The Style page runs them on the switch (a reload
-- follows; isForever for the WoW Forever variant); the login runs Classic's
-- for a table that arrived already switched.
function module.TM_SeedStock(c, key, isForever)
    if key == "blizzard" then
        if c.blizzBgAlphaSeeded then return end
        c.blizzBgAlphaSeeded = true
    elseif key == "classic" then
        if c.classicSeeded then return end
        c.classicSeeded = true
    else
        return
    end
    local ap = c.appearance
    if type(ap) ~= "table" then ap = {}; c.appearance = ap end
    local colors = ap.colors
    if type(colors) ~= "table" then colors = {}; ap.colors = colors end
    if key == "blizzard" then
        colors.bgAlpha = isForever and 0.65 or 0.4
        return
    end
    local bars = ap.bars
    if type(bars) ~= "table" then bars = {}; ap.bars = bars end
    colors.bgR, colors.bgG, colors.bgB = 16 / 255, 16 / 255, 16 / 255
    bars.barTexture = "blizzard"
    colors.barBgR, colors.barBgG, colors.barBgB, colors.barBgAlpha = 0, 0, 0, 0.25
    colors.barBgUseClassColor = false
end

-- The header menus: the shared context menu in the look's menu art, opening
-- upward from the header button.
local MENU_OPTS = { above = true, look = "meter", fontKey = "essentials" }

-- The look's painters go in once, before the first surface is built.
local lookReady
local function EnsureLook()
    if lookReady then return end
    lookReady = true
    ns.UseLook(module.TM_Style(), module.TM_Forever())
    MENU_OPTS.look = Look.menuLook
end

local function TrackedUnit()
    if Get("focusEnabled") and Get("source") == "focus" then return "focus" end
    return "target"
end
ns.GetTrackedUnit = TrackedUnit

function ns.SetFocusEnabled(enabled)
    local c = Cfg()
    c.focusEnabled = enabled
    if not enabled and c.source == "focus" then c.source = nil end
end

ns.DisplayValues = { none = "None", value = "Threat Value", relative = "Tank %", pull = "Pull %",
    value_relative = "Threat Value + Tank %", value_pull = "Threat Value + Pull %" }
ns.DisplayOrder = { "none", "value", "relative", "pull", "value_relative", "value_pull" }

function ns.GetDisplayedValue()
    local value, percent = Get("showValue"), Get("showPercent")
    if not percent then return value and "value" or "none" end
    local pull = Get("percentMode") == "pull"
    if value then return pull and "value_pull" or "value_relative" end
    return pull and "pull" or "relative"
end

function ns.SetDisplayedValue(v)
    if not ns.DisplayValues[v] then return end
    local c = Cfg()
    c.showValue = v == "value" or v == "value_relative" or v == "value_pull"
    c.showPercent = v ~= "none" and v ~= "value"
    if c.showPercent then c.percentMode = v:find("pull", 1, true) and "pull" or "relative" end
end

-- No maximum: a grip drag stops at the screen's edge instead.
local function ClampW(w) return math.max(MIN_W, w) end
local function ClampH(h) return math.max(MIN_H, h) end

-------------------------------------------------------------------------------
--  Media: bar textures and the warning sound list, built on first use.
-------------------------------------------------------------------------------
local textures
function ns.BarTextures()
    if not textures then
        local names, order
        textures, names, order = EUI.BuildBarTextureTables(true)
        -- The game's own bar fill, second in the list (Classic WoW UI seeds it).
        textures.blizzard = "Interface\\TargetingFrame\\UI-StatusBar"
        names.blizzard = "Blizzard"
        table.insert(order, 2, "blizzard")
        EUI.AppendSharedMediaTextures(names, order, nil, textures)
        ns.BarTextureNames, ns.BarTextureOrder = names, order
    end
    return textures
end

local soundPaths, soundNames, soundOrder
function ns.Sounds()
    if not soundPaths then
        soundPaths, soundNames, soundOrder = EUI.BuildAlertSoundTables()
        EUI.AppendSharedMediaSounds(soundPaths, soundNames, soundOrder)
    end
    return soundPaths, soundNames, soundOrder
end

-- A SharedMedia sound is a file path or a SoundKit id.
function ns.PlaySoundKey(key)
    local path = ns.Sounds()[key]
    if type(path) == "number" then
        if path ~= 1 then PlaySound(path, "Master") end
    elseif path then
        PlaySoundFile(path, "Master")
    end
end

-------------------------------------------------------------------------------
--  Style memo: every setting the paint reads, resolved once. A settings write
--  clears it (ApplyStyle); a global font, outline, accent or colour-palette
--  (class colours) change rebuilds it.
--  Frames and rows stamp the table they were painted with, so a new table
--  restyles each of them once.
-------------------------------------------------------------------------------
local cachedStyle
local CLASS_ICON_DIR = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\"

local function Style()
    local font = EUI.GetFontPath("essentials")
    local outline = EUI.GetFontOutlineFlag("essentials")
    local accent = EUI.ELLESMERE_GREEN
    local colorGen = EUI._dmGen
    local dm = cachedStyle
    if dm and dm.globalFont == font and dm.globalOutline == outline and dm.colorGen == colorGen
        and dm.accentR == accent.r and dm.accentG == accent.g and dm.accentB == accent.b then
        return dm
    end
    dm = {}
    for group, defaults in pairs(STYLE_DEFAULTS) do
        for key in pairs(defaults) do dm[key] = ns.GetStyleValue(group, key) end
    end
    dm.barHeight, dm.barSpacing, dm.fontSize = Get("barHeight"), Get("barSpacing"), Get("fontSize")
    dm.showHeader, dm.growUp = Get("showHeader"), Get("growUp")
    -- The look is latched for the session before the window is built. A
    -- look's header band may add a rail under the configured height; the
    -- title and buttons rise by half of it to stay centred above it.
    local rail = dm.showHeader and Look.HeaderRail(dm.hdrHeight) or 0
    dm.headerHeight = dm.showHeader and dm.hdrHeight + rail or 0
    dm.hdrLift = rail / 2
    dm.inset = Look.inset
    dm.iconSize = Look.IconSize(22)
    dm.focusEnabled, dm.tracked = Get("focusEnabled"), TrackedUnit()
    dm.pullColor, dm.playerColor, dm.tankColor = Get("pullColor"), Get("playerColor"), Get("tankColor")
    dm.playerColorOn, dm.tankColorOn = Get("playerColorOn"), Get("tankColorOn")
    local showValue, showPercent = Get("showValue"), Get("showPercent")
    dm.showValue, dm.showPercent = showValue, showPercent
    dm.pullPercent = Get("percentMode") == "pull"
    -- The widest value text a row realistically shows; the first row painted
    -- with this style measures it in the row font to size the value column.
    local sampleValue = EUI.AbbreviateNumber(888888)
    dm.valueSample = showValue and showPercent and (sampleValue .. "  888%")
        or (showValue and sampleValue or (showPercent and "888%" or nil))
    local fontKey, outlineMode = Get("font"), Get("outlineMode")
    dm.textFont = fontKey ~= "__global" and EUI.ResolveFontName(fontKey) or nil
    if outlineMode == "outline" then dm.textFlag = EUI.SlugFlag("OUTLINE, SLUG")
    elseif outlineMode == "thick" then dm.textFlag = EUI.SlugFlag("THICKOUTLINE, SLUG")
    elseif outlineMode == "none" then dm.textFlag = "" end
    dm.texturePath = EUI.ResolveTexturePath(ns.BarTextures(), dm.barTexture, "Interface\\Buttons\\WHITE8X8")
    if dm.iconStyle ~= "none" and dm.iconStyle ~= "blizzard" then
        dm.iconPath = CLASS_ICON_DIR .. dm.iconStyle .. ".tga"
    end
    dm.accent = accent
    dm.globalFont, dm.globalOutline, dm.colorGen = font, outline, colorGen
    dm.accentR, dm.accentG, dm.accentB = accent.r, accent.g, accent.b
    cachedStyle = dm
    return dm
end

-- nil textFont / textFlag leave the module's font and outline to ApplyModuleFont.
local function Font(fs, size, dm)
    EUI.ApplyModuleFont(fs, dm.textFont, size, "essentials", dm.textFlag)
end

local function PaintText(fs, color)
    fs:SetTextColor(color.r, color.g, color.b)
end

-- The window border takes the plain border defaults (as the Damage Meters
-- window does), the bars this meter's own. A stock look draws neither.
local function Border(target, dm, window)
    local size, texture, exact, r, g, b, a
    if window then
        local color = dm.windowBorderColor
        size, texture, exact = dm.windowBorderSize, dm.windowBorderTexture, dm.windowBorderSizePx
        r, g, b, a = color.r or 0, color.g or 0, color.b or 0, color.a or 1
    else
        size, texture, exact = dm.borderSize, dm.borderTexture, dm.borderSizePx
        r, g, b, a = dm.borderR, dm.borderG, dm.borderB, dm.borderA
    end
    size = Look.stock and 0 or (size or 0)
    local px = size > 0 and EUI.BorderPx(exact, size, texture) or nil
    if window then
        EUI.ApplyBorderStyle(target, size, r, g, b, a, texture, nil, nil, nil, nil, nil, nil, nil, px)
        return
    end
    EUI.ApplyBorderStyle(target, size, r, g, b, a, texture,
        dm.borderTextureOffset or nil, dm.borderTextureOffsetY or nil,
        dm.borderTextureShiftX or nil, dm.borderTextureShiftY or nil,
        BORDER_KEY, size, nil, px)
end

-- A size in physical pixels, in UI units.
local function PhysicalPixels(v)
    local PP = EUI.PP
    return PP.Scale((v or 0) * PP.mult)
end

-------------------------------------------------------------------------------
--  Surface: the live meter and the options preview share this structure,
--  the chrome paint and the row renderer.
-------------------------------------------------------------------------------
-- The Damage Meters window layout: the header across the top (inset under a
-- stock look), its buttons from the right edge with the title running up to
-- the leftmost one (the engine truncates it: a mob name can be secret), the
-- window background below the header, and the window border above the
-- header. The live window reports the border's reach to size matching.
local function ApplyChrome(dm, s)
    if s._style == dm then return end
    s._style = dm
    local header, inset = s.header, dm.inset
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", s, "TOPLEFT", inset, -inset)
    header:SetPoint("TOPRIGHT", s, "TOPRIGHT", -inset, -inset)
    header:SetHeight(dm.showHeader and dm.headerHeight or 0.001)
    header:SetShown(dm.showHeader)
    local bg = dm.hdrBgColor
    Look.HeaderBg(header.bg, bg.r, bg.g, bg.b, dm.hdrBgAlpha, dm.bgR, dm.bgG, dm.bgB)
    if not Look.HeaderLine(header.line) then
        local size, line = dm.hdrBottomBorderSize or 0, dm.hdrBottomBorderColor
        header.line:SetHeight(PhysicalPixels(size))
        header.line:SetColorTexture(line.r or 0, line.g or 0, line.b or 0, line.a or 1)
        header.line:SetShown(size > 0 and not Look.stock)
    end
    Font(s.title, dm.hdrFontSize, dm)
    -- A look may colour the accented title its own way (WoW Forever's gold).
    PaintText(s.title, dm.hdrTextUseAccent ~= false and (Look.titleColor or dm.accent) or dm.hdrTextColor)
    local source = s.sourceBtn
    Font(source.label, dm.hdrFontSize, dm)
    source.label:SetText(dm.tracked == "focus" and EllesmereUI.L("Focus") or EllesmereUI.L("Target"))
    source:SetShown(dm.focusEnabled)
    local leftmost = ns.LayoutHeaderButtons(s, dm.iconSize, dm.hdrLift)
    local ty = dm.hdrTextOffY + dm.hdrLift
    s.title:ClearAllPoints()
    s.title:SetPoint("LEFT", header, "LEFT", 6 + dm.hdrTextOffX, ty)
    if leftmost then
        s.title:SetPoint("RIGHT", leftmost, "LEFT", -6, dm.hdrTextOffY)
    else
        s.title:SetPoint("RIGHT", header, "RIGHT", -6, ty)
    end
    s.bg:ClearAllPoints()
    s.bg:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -dm.headerHeight)
    s.bg:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
    Look.WindowBg(s.bg, dm.bgR, dm.bgG, dm.bgB, dm.bgAlpha)
    local border = s.border
    border:ClearAllPoints()
    if dm.windowBorderIncludeHeader == false then
        border:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    else
        border:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
    end
    border:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
    border:SetFrameLevel(header:GetFrameLevel() + 4)
    Border(border, dm, true)
    if s.unlockKey then EUI.MatchPadChanged(s.unlockKey) end
end

-- live: the meter window (header buttons take the mouse and show tooltips);
-- otherwise the settings preview, whose header only shows them.
local function CreateSurface(parent, name, live)
    EnsureLook()
    local surface = CreateFrame("Frame", name, parent)
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
    surface.settingsBtn = ns.MakeHeaderButton(surface, "settings", "dm_settings.png",
        live and EllesmereUI.L("Settings") or nil)
    surface.sourceBtn = ns.MakeHeaderTextButton(surface, "source",
        live and EllesmereUI.L("Tracked Unit") or nil)
    if not live then
        surface.settingsBtn:EnableMouse(false)
        surface.sourceBtn:EnableMouse(false)
    end
    -- Fonts are set before any text is.
    ApplyChrome(Style(), surface)
    return surface
end

local function MakeRow(i, surface, rows)
    local row = CreateFrame("Frame", nil, surface)
    row.fill = CreateFrame("StatusBar", nil, row)
    row.fill:SetAllPoints()
    row.fill:SetMinMaxValues(0, 100)
    row.border = CreateFrame("Frame", nil, row)
    row.border:SetAllPoints()
    row.border:SetFrameLevel(row.fill:GetFrameLevel() + 1)
    -- Border styling hides its frame when the border size is zero, so the text
    -- gets its own always-visible parent above that frame.
    row.text = CreateFrame("Frame", nil, row)
    row.text:SetAllPoints()
    row.text:SetFrameLevel(row.border:GetFrameLevel() + 1)
    row.classIcon = row.text:CreateTexture(nil, "ARTWORK")
    row.petIcon = row.text:CreateTexture(nil, "ARTWORK")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.label = row.text:CreateFontString(nil, "OVERLAY")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.value = row.text:CreateFontString(nil, "OVERLAY")
    row.value:SetJustifyH("RIGHT")
    -- Your own row: a thin white stripe on the bar's left edge.
    row.self = row.fill:CreateTexture(nil, "OVERLAY")
    row.self:SetPoint("TOPLEFT")
    row.self:SetPoint("BOTTOMLEFT")
    row.self:SetWidth(2)
    row.self:SetColorTexture(1, 1, 1, 0.95)
    rows[i] = row
    return row
end

local BLIZZARD_CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local PET_ICON = EUI.ClientIcon(132161)

-- Class icon (none for a pet) plus the pet icon; returns the width they take.
local function RowIcons(row, class, isPet, dm)
    row.classIcon:Hide()
    row.petIcon:Hide()
    local style = dm.iconStyle
    if style == "none" then return 0 end
    if isPet then class = nil end
    local size, x = dm.barHeight, 0
    local coords
    if style == "blizzard" then
        -- Threat units give no reliable specialization, so this is the class art.
        coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            row.classIcon:SetTexture(BLIZZARD_CLASS_ICONS)
            local zoom = dm.classIconZoom
            local dx, dy = (coords[2] - coords[1]) * zoom, (coords[4] - coords[3]) * zoom
            row.classIcon:SetTexCoord(coords[1] + dx, coords[2] - dx, coords[3] + dy, coords[4] - dy)
        end
    else
        coords = class and EUI.CLASS_ICON_SPRITE_COORDS[class]
        if coords then
            row.classIcon:SetTexture(dm.iconPath)
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
        row.petIcon:SetTexture(PET_ICON)
        row.petIcon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
        row.petIcon:SetSize(size, size)
        row.petIcon:ClearAllPoints()
        row.petIcon:SetPoint("LEFT", row, "LEFT", x, 0)
        row.petIcon:Show()
        x = x + size + 2
    end
    return x
end

-- Paints one row, touching only what changed since its last paint: the style
-- (fonts, texture, borders), the entry's identity (unit or sample, roster
-- generation: class, icons, own stripe, name), who holds aggro (colours), and
-- the numbers (fill and value text).
local function PaintRow(row, e, dm, top, gen)
    local restyle = row._style ~= dm
    if restyle then
        Font(row.label, dm.fontSize, dm)
        Font(row.value, dm.fontSize, dm)
        row.fill:SetStatusBarTexture(dm.texturePath)
        Border(row.border, dm, false)
        if not dm.valueWidth then
            local w = 0
            if dm.valueSample then
                row.value:SetText(dm.valueSample)
                w = math.ceil(row.value:GetUnboundedStringWidth()) + 2
            end
            dm.valueWidth = w
        end
        row.value:SetWidth(dm.valueWidth)
        Look.RowStyled(row, dm)
        row._style = dm
    end
    if restyle or row._key ~= e.key or row._gen ~= gen then
        row._key, row._gen = e.key, gen
        local class = e.class
        if e.unit then class = ns.ClassOf(e.unit) end
        local isPet = e.isPet == true
        if restyle or row._class ~= class or row._isPet ~= isPet then
            -- The texts sit inside the fill wherever the look seats it.
            local left, right = Look.SeatFill(row, RowIcons(row, class, isPet, dm), dm)
            row.value:ClearAllPoints()
            row.value:SetPoint("RIGHT", -5 - right + dm.rightTextOffsetX, dm.rightTextOffsetY)
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", left + 5 + dm.leftTextOffsetX, dm.leftTextOffsetY)
            row.label:SetPoint("RIGHT", row.value, "LEFT", -5, 0)
            row._class, row._isPet = class, isPet
        end
        row._own = e.own == true
        row.self:SetShown(row._own)
        row._aggro, row._name = nil, nil
        if not e.unit then row.label:SetText(e.pull and EllesmereUI.L("Pull Aggro") or e.name) end
    end
    -- A live name is re-read (it can arrive after the roster does). A secret
    -- name goes straight to the font string and cannot be compared.
    if e.unit then
        local name = EUI.WithSurname(UnitName(e.unit))
        if issecretvalue(name) then
            row.label:SetText(name)
            row._name = nil
        elseif name ~= row._name then
            row.label:SetText(name or e.unit)
            row._name = name
        end
    end
    local aggro = e.tanking == true
    if row._aggro ~= aggro then
        row._aggro = aggro
        local class = row._class
        local color = class and RAID_CLASS_COLORS[class] and EUI.GetClassColor(class)
        local fill
        if e.pull then fill = dm.pullColor
        elseif row._own and dm.playerColorOn then fill = dm.playerColor
        elseif aggro and dm.tankColorOn then fill = dm.tankColor
        elseif dm.showClassColor ~= false and color then fill = color
        elseif dm.barColorUseAccent ~= false then fill = dm.accent
        else fill = dm.barColor end
        row.fill:SetStatusBarColor(fill.r, fill.g, fill.b, dm.barFillAlpha)
        local bg = dm.barBgUseClassColor and color
        Look.RowBg(row.bg, bg and bg.r or dm.barBgR, bg and bg.g or dm.barBgG,
            bg and bg.b or dm.barBgB, dm.barBgAlpha)
        PaintText(row.label, dm.leftTextUseClassColor and color or dm.leftTextColor)
        PaintText(row.value, dm.rightTextUseClassColor and color or dm.rightTextColor)
    end
    -- Every bar shares one scale: raw threat against the top of the whole list.
    local fillValue = top > 0 and e.raw * 100 / top or 0
    if row._fill ~= fillValue then
        row._fill = fillValue
        row.fill:SetValue(fillValue)
    end
    -- The pull line shows its threat value; alone, its percent (Pull %: 100,
    -- Tank %: where the line sits against the tank's threat).
    local raw = dm.showValue and e.raw or nil
    local pct
    if dm.showPercent and not (e.pull and raw) then
        if dm.pullPercent then pct = e.scaled else pct = e.rawPct end
    end
    if restyle or row._vRaw ~= raw or row._vPct ~= pct then
        row._vRaw, row._vPct = raw, pct
        if raw and pct then
            row.value:SetFormattedText("%s  %.0f%%", EUI.AbbreviateNumber(raw), pct)
        elseif raw then
            row.value:SetText(EUI.AbbreviateNumber(raw))
        elseif pct then
            row.value:SetFormattedText("%.0f%%", pct)
        else
            row.value:SetText("")
        end
    end
end

local function RenderRows(s, list, first, count, dm, top)
    local rows, gen = s.rows, ns.rosterGen
    local step, inset = dm.barHeight + dm.barSpacing, dm.inset
    for i = 1, count do
        local row = rows[i] or MakeRow(i, s, rows)
        local index = dm.growUp and (count - i) or (i - 1)
        local y = -inset - dm.headerHeight - index * step
        if row._y ~= y or row._style ~= dm then
            -- Both anchors share the top edge: a vertical-centre anchor to the
            -- window would overconstrain the height.
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", s, "TOPLEFT", inset, y)
            row:SetPoint("TOPRIGHT", s, "TOPRIGHT", -inset, y)
            row:SetHeight(dm.barHeight)
            row._y = y
        end
        PaintRow(row, list[i + first], dm, top, gen)
    end
    local shown = s._count or #rows
    for i = count + 1, shown do rows[i]:Hide() end
    for i = shown + 1, count do rows[i]:Show() end
    s._count = count
end

-------------------------------------------------------------------------------
--  Preview group (options header, unlock mode, /euitm test): a tank holding
--  aggro, you (ranged: you pull at 130% of the tank's threat) and a few others,
--  through the same pull line and sort as live data. Built once per Include
--  Pets / pull bar pair.
-------------------------------------------------------------------------------
local DEMO_TANK = 12000
local DEMO = {
    { class = "WARRIOR", raw = 12000, tank = true },
    { own = true, raw = 10080, reach = 1.3 },
    { class = "ROGUE", raw = 8040, reach = 1.1 },
    { class = "HUNTER", raw = 5160, reach = 1.3 },
    { class = "HUNTER", raw = 3120, reach = 1.1, isPet = true },
    { class = "PRIEST", raw = 2160, reach = 1.3 },
}
local demoList, demoEntries, demoPull = {}, {}, {}
local demoPets, demoPullBar

local function DemoEntry(i, s)
    local e = { key = s, raw = s.raw, order = i, pull = false,
        isPet = s.isPet == true, own = s.own == true, tanking = s.tank == true }
    e.scaled = s.tank and 100 or s.raw * 100 / (DEMO_TANK * s.reach)
    e.rawPct = s.raw * 100 / DEMO_TANK
    if s.own then
        local _, class = UnitClass("player")
        e.class, e.name = class, EUI.WithSurname(UnitName("player"))
    elseif s.tank then
        e.class, e.name = s.class, EllesmereUI.L("Tank")
    elseif s.isPet then
        e.class, e.name = s.class, EllesmereUI.L("Pet")
    else
        e.class = s.class
        e.name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[s.class]) or s.class
    end
    return e
end

local function DemoList()
    local pets, pullBar = Get("pets"), Get("pullBar")
    if demoPets == pets and demoPullBar == pullBar then return demoList end
    demoPets, demoPullBar = pets, pullBar
    wipe(demoList)
    local me
    for i, s in ipairs(DEMO) do
        if pets or not s.isPet then
            local e = demoEntries[i]
            if not e then e = DemoEntry(i, s); demoEntries[i] = e end
            if e.own then me = e end
            demoList[#demoList + 1] = e
        end
    end
    if pullBar and ns.FillPullEntry(demoPull, me, DEMO_TANK) then demoList[#demoList + 1] = demoPull end
    table.sort(demoList, ns.ByThreat)
    return demoList
end

-------------------------------------------------------------------------------
--  Options preview: its own surface in the page's content header, drawn with
--  the live meter's style and renderer. No threat reads, no saved writes.
-------------------------------------------------------------------------------
local settingsPreview
local hookedParents = setmetatable({}, { __mode = "k" })

local function RefreshPreview(self)
    local parent = self:GetParent()
    if not parent then return end
    local dm = Style()
    local list = DemoList()
    local n = #list
    local width = ClampW(Get("width"))
    local height = 2 * dm.inset + dm.headerHeight + n * dm.barHeight + math.max(0, n - 1) * dm.barSpacing
    self:SetSize(width, height)
    local pw = parent:GetWidth()
    local available = (pw > 0 and pw) or self.availableWidth or width + 40
    self:SetScale(math.min(1, math.max(100, available - 40) / width))
    self:ClearAllPoints()
    self:SetPoint("CENTER", parent, "CENTER", 0, 0)
    ApplyChrome(dm, self)
    RenderRows(self, list, 0, n, dm, list[1].raw)
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
        view.title:SetFormattedText(EllesmereUI.L("Threat - %s"), EllesmereUI.L("Training Dummy"))
        view.Refresh = RefreshPreview
        view:SetScript("OnShow", RefreshPreview)
    end
    -- Frames outlive a page rebuild, so the surface is reused.
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
--  Live meter
-------------------------------------------------------------------------------
local frame, events, pendingUpdate, followTicker, previewUntil
local chrome         -- the window's lock / grip / drag handle (AttachChrome)
local mobUnit        -- the mob token the last pass resolved, nil when none
local threatOn       -- the two threat events are registered
local flagsUnit      -- the tracked unit UNIT_FLAGS is registered for
local shownList      -- the list on screen (the mouse wheel repaints it)
local titleStamp     -- the mob GUID (or the preview) the title shows
local warned, warnedMob
local offset = 0     -- rows scrolled past
local DEMO_STAMP, EMPTY_STAMP, EMPTY = {}, {}, {}
local visState = {}

-- A tank does not want to be warned about holding aggro: tank role, Bear or Dire
-- Bear Form, or Defensive Stance.
local function PlayerIsTank()
    if UnitGroupRolesAssigned("player") == "TANK" then return true end
    local form = GetShapeshiftFormID()
    return form == 5 or form == 8 or form == 18
end

-- Plays once when your pull percent reaches the threshold on a mob; re-arms
-- when it drops back below, and for each new mob.
local function CheckWarning(me, guid)
    if not Get("warnSound") then warned, warnedMob = false, nil; return end
    if guid ~= warnedMob then warned, warnedMob = false, guid end
    local over = me and not me.tanking and me.scaled >= Get("warnAt")
        and not (Get("warnSkipTank") and PlayerIsTank())
    if over and not warned then ns.PlaySoundKey(Get("warnSoundKey")) end
    warned = over and true or false
end

local function Flag(v)
    return not issecretvalue(v) and v == true
end

-- Visibility; "in combat" also counts your pet's and the watched mob's combat.
function ns.IsVisible(c, state)
    if c.visibilityMatch ~= "any" and EUI.CheckVisibilityOptions(c) then return false end
    local result = EUI.EvalVisibilityExtended(c, "visibility", state, EUI.VIS_CAPS_DEFAULT)
    if result ~= nil then return result == true end
    if c.visibility == "in_combat" then return state.inCombat end
    if c.visibility == "out_of_combat" then return not state.inCombat end
    return EUI.EvalVisibility(c) == true
end

-- mob is nil for the empty header (Only With Threat off).
local function Visible(mob)
    local state = visState
    state.inCombat = InCombatLockdown() or (Get("pets") and Flag(UnitAffectingCombat("pet")))
        or (mob ~= nil and Flag(UnitAffectingCombat(mob)))
    state.inRaid = IsInRaid()
    state.inParty = not state.inRaid and GetNumSubgroupMembers() > 0
    return ns.IsVisible(Read(), state)
end

-- The two threat events fire for every unit in every fight nearby, so they are
-- registered only while a mob resolves. Every way a mob can start resolving
-- (target, focus, their target, attackable flags) stays registered with the
-- meter on, and a resolved mob keeps them while the meter hides empty, so the
-- threat that fills it is always received.
local function SetThreatEvents(on)
    if on == threatOn then return end
    threatOn = on
    if on then
        events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    else
        events:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    end
end

-- No threat event names a derived token (targettarget), so while the meter
-- follows what a friendly unit is fighting and that mob has no nameplate or
-- boss token, nothing reports its threat moving. Re-read on a short interval
-- in that one case, and only in combat.
local function SetFollow(on)
    if on then
        if not followTicker then followTicker = C_Timer.NewTicker(FOLLOW_INTERVAL, RequestUpdate) end
    elseif followTicker then
        followTicker:Cancel()
        followTicker = nil
    end
end

local function Paint(list, dm)
    local step = dm.barHeight + dm.barSpacing
    local area = frame:GetHeight() - 2 * dm.inset - dm.headerHeight
    local capacity = math.floor((area + dm.barSpacing) / step)
    if capacity < 1 then capacity = 1 end
    local n = #list
    local maxOffset = n - capacity
    if maxOffset < 0 then maxOffset = 0 end
    if offset > maxOffset then offset = maxOffset end
    local count = n - offset
    if count > capacity then count = capacity end
    RenderRows(frame, list, offset, count, dm, n > 0 and list[1].raw or 0)
end

local function Show(list, dm, stamp, mob)
    ApplyChrome(dm, frame)
    if stamp == nil or stamp ~= titleStamp then
        if stamp ~= nil then offset = 0 end
        titleStamp = stamp
        if mob then
            frame.title:SetFormattedText(EllesmereUI.L("Threat - %s"), EUI.WithSurname(UnitName(mob)))
        else
            frame.title:SetText(EllesmereUI.L("Threat Meter"))
        end
    end
    shownList = list
    Paint(list, dm)
    frame:Show()
end

local function Empty()
    warned, warnedMob = false, nil
    shownList = nil
    frame:Hide()
end

-- Only With Threat off: the header over an empty bar area, titled with the
-- mob when one resolves (stamp: its GUID, EMPTY_STAMP without a mob).
local function ShowEmpty(dm, stamp, mob)
    warned, warnedMob = false, nil
    Show(EMPTY, dm, stamp, mob)
end

Repaint = function()
    if shownList and frame and frame:IsShown() then Paint(shownList, Style()) end
end

local function Update()
    pendingUpdate = false
    if not (frame and events) then return end
    if not Get("enabled") then
        SetFollow(false)
        Empty()
        return
    end
    local dm = Style()
    local tracked = TrackedUnit()
    if tracked ~= flagsUnit then
        events:RegisterUnitEvent("UNIT_FLAGS", "pet", tracked)
        flagsUnit = tracked
    end
    if previewUntil and GetTime() >= previewUntil then previewUntil = nil end
    -- Preview rows while previewing or while unlock mode is open. Combat lifts
    -- unlock mode and real rows show there; it comes back a moment after
    -- combat with no edge of its own, so the open session out of combat is the
    -- test (the combat-end pass already sees it).
    if previewUntil or (EUI:IsUnlockModeActive() and not InCombatLockdown()) then
        mobUnit = nil
        SetThreatEvents(false)
        SetFollow(false)
        warned, warnedMob = false, nil
        Show(DemoList(), dm, DEMO_STAMP, nil)
        return
    end
    local mob = ns.ResolveSource(tracked)
    mobUnit = mob
    SetThreatEvents(mob ~= nil)
    -- Only With Threat (the default) hides the meter while nothing is listed;
    -- with it off the header stays up whenever the visibility settings allow.
    local keep = Get("onlyWithThreat") == false
    if not (mob or keep) or not Visible(mob) then
        SetFollow(false)
        Empty()
        return
    end
    if not mob then
        SetFollow(false)
        ShowEmpty(dm, EMPTY_STAMP, nil)
        return
    end
    SetFollow(mob ~= tracked and InCombatLockdown())
    local me, tankRaw = ns.Collect(mob, Get("pets"))
    local list = ns.list
    if #list == 0 and not keep then
        Empty()
        return
    end
    local guid = UnitGUID(mob)
    if issecretvalue(guid) then guid = nil end
    if #list == 0 then
        ShowEmpty(dm, guid, mob)
        return
    end
    CheckWarning(me, guid)
    if Get("pullBar") then ns.AddPullEntry(me, tankRaw) end
    ns.Sort()
    Show(list, dm, guid, mob)
end

-- Threat updates arrive per unit, so a raid pull is a burst; one redraw per
-- short window covers the whole burst.
RequestUpdate = function()
    if pendingUpdate then return end
    pendingUpdate = true
    C_Timer.After(UPDATE_DELAY, Update)
end

-- Resets run before the pending check so a burst never swallows them. Then each
-- unit event is probed: a threat-list change counts only for the mob shown (a
-- secret comparison counts as a match), a threat-situation or pet change only
-- for a unit the meter lists, a target or flags change only for the tracked
-- unit (or the pet). Combat, zone and roster edges also reach the meter through
-- the shared visibility dispatcher.
local function OnEvent(_, event, unit)
    if event == "GROUP_ROSTER_UPDATE" then
        ns.RosterChanged()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        if (event == "PLAYER_FOCUS_CHANGED") ~= (TrackedUnit() == "focus") then return end
        offset = 0
        warned, warnedMob = false, nil
    end
    if pendingUpdate then return end
    if event == "UNIT_THREAT_LIST_UPDATE" then
        local mob = mobUnit
        if not mob then return end
        if unit ~= mob then
            local same = UnitIsUnit(unit, mob)
            if not issecretvalue(same) and not same then return end
        end
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
        if not (ns.MEMBER_UNITS[unit] or (ns.PET_UNITS[unit] and Get("pets"))) then return end
    elseif event == "UNIT_PET" then
        if not (ns.MEMBER_UNITS[unit] and Get("pets")) then return end
    elseif event == "UNIT_TARGET" or event == "UNIT_FLAGS" then
        if unit == "pet" then
            if not Get("pets") then return end
        elseif unit ~= TrackedUnit() then
            return
        end
    end
    RequestUpdate()
end

-- The grip owns the anchor while it is held.
local function SetSavedPoint()
    if chrome and chrome.resizing then return end
    local p = Get("position")
    frame:ClearAllPoints()
    if type(p) == "table" and p.point then
        frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    elseif type(p) == "table" and p.x and p.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        p = DEFAULTS.position
        frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    end
end

-- The saved spot, then the unlock-mode anchor when the meter has one.
local function Position()
    if chrome and chrome.resizing then return end
    SetSavedPoint()
    EUI.ReapplyOwnAnchor(UNLOCK_KEY)
end

-- A resize keeps the top-left corner. A saved point-format spot (unlock
-- mode's, or the default) is rewritten as that corner first: a size change
-- re-applies a saved centre, which would pull the window back mid-drag.
local function PinPosition(left, top)
    local p = Get("position")
    if left and top and type(p) == "table" and p.point then
        Cfg().position = { x = left, y = top }
    end
end

-- A header drag: the corner is the saved spot, and it replaces any unlock-mode
-- anchor on the meter (elements anchored to the meter follow it).
local function SaveMove(left, top)
    Cfg().position = { x = left, y = top }
    local anchors = EllesmereUIDB and EllesmereUIDB.unlockAnchors
    if anchors then anchors[UNLOCK_KEY] = nil end
    EUI.ScheduleSettleReapply()
end

-- Unlock mode owns the position while it is open (a first build still places
-- the frame, so its mover has a spot to start from).
local function ApplyGeometry(firstBuild)
    if chrome and chrome.resizing then return end
    frame:SetSize(ClampW(Get("width")), ClampH(Get("height")))
    if firstBuild or not EUI._unlockActive then Position() end
end

function ns.Apply()
    cachedStyle = nil
    if Get("enabled") then
        if not frame then CreateWindow() end
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("PLAYER_FOCUS_CHANGED")
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterEvent("UNIT_PET")
        events:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
        flagsUnit = nil
        -- The roster memos missed every change made while the meter was off.
        ns.RosterChanged()
        EUI.UnregisterVisibilityUpdater(RequestUpdate)
        EUI.RegisterVisibilityUpdater(RequestUpdate)
        -- A reset may have cleared the lock.
        chrome.SyncLock()
        ApplyGeometry()
        RequestUpdate()
    else
        if events then events:UnregisterAllEvents() end
        threatOn, flagsUnit, mobUnit, previewUntil = false, nil, nil, nil
        EUI.UnregisterVisibilityUpdater(RequestUpdate)
        SetFollow(false)
        warned, warnedMob = false, nil
        shownList = nil
        if frame then frame:Hide() end
    end
    -- A reset also reaches a Damage Meters Threat window (ThreatFeed file).
    ns.FeedChanged()
    RefreshSettingsPreview()
end

function ns.ApplyStyle()
    cachedStyle = nil
    if frame and Get("enabled") then RequestUpdate() end
    ns.FeedChanged()
    RefreshSettingsPreview()
end

-- Ten seconds of preview rows on the live meter.
function ns.Preview()
    if not (frame and Get("enabled")) then return false end
    previewUntil = GetTime() + PREVIEW_SECONDS
    RequestUpdate()
    C_Timer.After(PREVIEW_SECONDS, RequestUpdate)
    return true
end

-------------------------------------------------------------------------------
--  Header menus. Independent of the load-on-demand options addon, so they also
--  work in combat before the settings window has ever opened. A change
--  restyles the meter and refreshes an open settings page. They are the
--  shared context menu in the Damage Meters look (MENU_OPTS).
-------------------------------------------------------------------------------
local function OpenSettings()
    EUI:NavigateToElementSettings("EllesmereUIForeverEssentials", "Threat")
end

local function Changed()
    ns.ApplyStyle()
    EUI:RefreshPage()
end

local function SetSource(unit)
    Cfg().source = unit
    offset = 0
    Changed()
end

local function SourceItems()
    local tracked = TrackedUnit()
    return {
        { text = EllesmereUI.L("Target"), isActive = tracked == "target",
          onClick = function() SetSource("target") end },
        { text = EllesmereUI.L("Focus"), isActive = tracked == "focus",
          onClick = function() SetSource("focus") end },
    }
end

-- The menu's Width and Height boxes keep the top-left corner, as the grip does.
local function ResizeTo(width, height, key)
    local left, top = ns.WindowCorner(frame)
    PinPosition(left, top)
    frame:SetSize(width, height)
    if left then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    local size = key == "width" and frame:GetWidth() or frame:GetHeight()
    Cfg()[key] = math.floor(size + 0.5)
end

-- What the list shows (tracked unit, displayed value, pets), appended to
-- `items`. Also the head of a Damage Meters Threat window's settings menu.
local function DataItems(items)
    if Get("focusEnabled") then
        items[#items + 1] = { text = EllesmereUI.L("Tracked Unit"), children = SourceItems() }
    end
    local shown, values = ns.GetDisplayedValue(), {}
    for _, key in ipairs(ns.DisplayOrder) do
        local value = key
        values[#values + 1] = { text = EllesmereUI.L(ns.DisplayValues[value]), isActive = shown == value,
            onClick = function()
                ns.SetDisplayedValue(value)
                Changed()
            end }
    end
    items[#items + 1] = { text = EllesmereUI.L("Displayed Value"), children = values }
    -- The options page's label: checked while pets are left out.
    items[#items + 1] = { text = EllesmereUI.L("Ignore Pets"), isActive = not Get("pets"),
        onClick = function()
            Cfg().pets = not Get("pets")
            Changed()
        end }
    return items
end
ns.DataMenuItems = DataItems

local function ShowQuickMenu(anchor)
    local items = DataItems({})
    items[#items + 1] = { text = EllesmereUI.L("Warning Sound"), isActive = Get("warnSound") == true,
        onClick = function()
            Cfg().warnSound = not Get("warnSound")
            Changed()
        end }
    items[#items + 1] = "---"
    items[#items + 1] = { text = EllesmereUI.L("Width"), isInput = true, min = MIN_W,
        getValue = function() return math.floor(frame:GetWidth() + 0.5) end,
        setValue = function(v) ResizeTo(math.max(MIN_W, v), frame:GetHeight(), "width") end }
    items[#items + 1] = { text = EllesmereUI.L("Height"), isInput = true, min = MIN_H,
        getValue = function() return math.floor(frame:GetHeight() + 0.5) end,
        setValue = function(v) ResizeTo(frame:GetWidth(), math.max(MIN_H, v), "height") end }
    local snapOff = Get("snapDisabled") == true
    items[#items + 1] = { text = snapOff and EllesmereUI.L("Enable Snapping") or EllesmereUI.L("Disable Snapping"),
        onClick = function() Cfg().snapDisabled = (not snapOff) or nil end }
    items[#items + 1] = { text = EllesmereUI.L("Settings"), isDisabled = InCombatLockdown, onClick = OpenSettings }
    EUI.ShowContextMenu(anchor, items, MENU_OPTS)
end

local function ShowSourceMenu(anchor)
    EUI.ShowContextMenu(anchor, SourceItems(), MENU_OPTS)
end

-------------------------------------------------------------------------------
--  Window: the Damage Meters window's controls (Window file): header drag,
--  corner grip, lock icon, snapping. The mouse wheel scrolls rows; a height
--  change repaints them for the rows that now fit.
-------------------------------------------------------------------------------
CreateWindow = function()
    frame = CreateSurface(UIParent, "EllesmereUIThreatMeterFrame", true)
    ns.frame = frame
    frame.unlockKey = UNLOCK_KEY
    frame:Hide()
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    -- Motion only (the hover fade): clicks on the bar area reach the world.
    frame:EnableMouseMotion(true)
    frame.settingsBtn.onClick = ShowQuickMenu
    frame.sourceBtn.onClick = ShowSourceMenu
    chrome = ns.AttachChrome(frame, {
        IsLocked = function() return Get("locked") == true end,
        SetLocked = function(locked) Cfg().locked = locked or nil end,
        SnapDisabled = function() return Get("snapDisabled") == true end,
        CanMove = function() return not EUI._unlockActive end,
        PinPosition = PinPosition,
        SaveMove = SaveMove,
        SaveSize = function(width, height)
            local c = Cfg()
            c.width, c.height = width, height
        end,
    })
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 2)
        Repaint()
    end)
    local lastHeight
    frame:HookScript("OnSizeChanged", function(_, _, height)
        if height == lastHeight then return end
        lastHeight = height
        Repaint()
    end)
    -- An accent change repaints the title and accent-coloured bars.
    EUI.RegAccent({ type = "callback", fn = function()
        if frame:IsShown() then RequestUpdate() end
        RefreshSettingsPreview()
    end })
    ApplyGeometry(true)
end

-------------------------------------------------------------------------------
--  Unlock mode. Registered at login whatever the enable state (an element
--  anchored to the meter keeps its link while the meter is off); nothing is
--  built while the meter is off, and the size reads the settings until it is.
--  A size set outside unlock mode (a width or height match) is not saved.
-------------------------------------------------------------------------------
local function SetUnlockSize(key, v, low)
    if not frame then return end
    v = EUI.PP.Snap(math.max(low, v or low))
    if key == "width" then frame:SetWidth(v) else frame:SetHeight(v) end
    if EUI._unlockActive then Cfg()[key] = math.floor(v + 0.5) end
end

-- How far a textured window border reaches past the window, so size matching
-- lines up with what is on screen. nil for a solid border or a stock look.
local function WindowBorderPad()
    if Look.stock then return nil end
    local size = ns.GetStyleValue("borders", "windowBorderSize") or 0
    local texture = ns.GetStyleValue("borders", "windowBorderTexture") or "solid"
    if size <= 0 or texture == "solid" then return nil end
    local color = ns.GetStyleValue("borders", "windowBorderColor")
    local l, r, t, b = EUI.BorderReach(size, texture, nil, nil, nil, nil, nil, nil,
        EUI.BorderPx(ns.GetStyleValue("borders", "windowBorderSizePx"), size, texture), nil,
        color and color.a or 1)
    if not l then return nil end
    if ns.GetStyleValue("borders", "windowBorderIncludeHeader") == false and Get("showHeader") then
        t = t - ns.GetStyleValue("header", "hdrHeight")
    end
    local pw = (l > 0 and l or 0) + (r > 0 and r or 0)
    local ph = (t > 0 and t or 0) + (b > 0 and b or 0)
    if pw <= 0 and ph <= 0 then return nil end
    return pw, ph
end

local function RegisterUnlock()
    EUI:RegisterUnlockElements({
        EUI.MakeUnlockElement({
            key      = UNLOCK_KEY,
            label    = "Threat Meter",
            group    = "Forever Essentials",
            order    = 731,
            isHidden = function() return not Get("enabled") end,
            getFrame = function()
                if not Get("enabled") then return nil end
                if not frame then CreateWindow() end
                return frame
            end,
            getSize = function()
                if frame then return frame:GetSize() end
                return ClampW(Get("width")), ClampH(Get("height"))
            end,
            getMatchPad = WindowBorderPad,
            setWidth = function(_, w) SetUnlockSize("width", w, MIN_W) end,
            setHeight = function(_, h) SetUnlockSize("height", h, MIN_H) end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                Cfg().position = { point = point, relPoint = relPoint or point, x = x, y = y }
                if frame and not EUI._unlockActive then SetSavedPoint() end
            end,
            -- A copy; a dragged corner reads as TOPLEFT of the screen's
            -- BOTTOMLEFT (never re-applied on a size change, unlike a centre).
            loadPos = function()
                local p = Get("position")
                if type(p) ~= "table" then return nil end
                if p.point then
                    return { point = p.point, relPoint = p.relPoint or p.point, x = p.x or 0, y = p.y or 0 }
                end
                if p.x and p.y then
                    return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = p.x, y = p.y }
                end
            end,
            clearPos = function()
                local c = Read()
                if c ~= _NOCFG then c.position, c.pos = nil, nil end
                if frame then SetSavedPoint() end
            end,
            applyPos = function()
                if not Get("enabled") then return end
                if not frame then CreateWindow() end
                SetSavedPoint()
            end,
        }),
    }, ADDON_NAME)
    -- The border was painted before the element existed: record its reach.
    EUI.MatchPadChanged(UNLOCK_KEY)
end

-- Opening or closing unlock mode swaps between preview and real rows.
local function OnUnlockModeChanged()
    if frame and Get("enabled") then RequestUpdate() end
end

-- Options-page and reset entry points.
EUI._ThreatMeter = {
    Get = Get, Cfg = Cfg, Read = Read,
    Apply = ns.Apply,
    ApplyStyle = ns.ApplyStyle,
    ApplyPosition = function() if frame then Position() end end,
    Preview = ns.Preview,
    Sounds = ns.Sounds,
}

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if module.TM_Style() == "classic" then module.TM_SeedStock(Cfg(), "classic") end
    EnsureLook()
    ns.Apply()
    RegisterUnlock()
    EUI:RegisterUnlockModeListener(UNLOCK_KEY, OnUnlockModeChanged)
end)

-------------------------------------------------------------------------------
--  /euitm
-------------------------------------------------------------------------------
-- Chat feedback; nothing prints in combat.
local function Say(msg)
    if InCombatLockdown() then return end
    EUI.Print(EUI.COLOR_CODES.BRAND .. "EllesmereUI:|r " .. msg)
end

SLASH_ELLESMEREUITHREAT1 = "/euitm"
SlashCmdList.ELLESMEREUITHREAT = function(input)
    local cmd = (input or ""):lower():match("^%s*(.-)%s*$")
    if cmd == "test" then
        if not ns.Preview() then Say(EllesmereUI.L("Enable the threat meter first.")) end
    elseif cmd == "target" or cmd == "focus" then
        Cfg().source = Get("focusEnabled") and cmd or "target"
        offset = 0
        ns.ApplyStyle()
        EUI:RefreshPage()
    elseif cmd == "show" or cmd == "hide" then
        Cfg().enabled = cmd == "show"
        ns.Apply()
        EUI:RefreshPage()
    elseif cmd == "pets" then
        local pets = not Get("pets")
        Cfg().pets = pets
        ns.ApplyStyle()
        EUI:RefreshPage()
        Say(pets and EllesmereUI.L("Pets shown") or EllesmereUI.L("Pets hidden"))
    elseif cmd == "reset" then
        -- The older keys too: a saved bar count would otherwise size the window.
        local c = Read()
        if c ~= _NOCFG then c.position, c.pos, c.width, c.height, c.maxBars = nil, nil, nil, nil, nil end
        ns.Apply()
    else
        Say("/euitm test, target, focus, show, hide, pets, reset")
    end
end
