-------------------------------------------------------------------------------
--  EllesmereUI.lua  -  Custom Options Panel for EllesmereUI
--  Design-first scaffold: background, sidebar, header, content area, controls
--  Meant to be shared across the entire EllesmereUI addon suite.
-------------------------------------------------------------------------------
if EllesmereUI and EllesmereUI._loaded then return end   -- already loaded by another addon in the suite

local EUI_HOST_ADDON = ...

-------------------------------------------------------------------------------
--  Constants & Colours (BURNE STAY AWAY FROM THIS SECTION)
-------------------------------------------------------------------------------
--  Visual Settings  (edit these to adjust the look -- values only, no tables)
-------------------------------------------------------------------------------
-- Accent colour  (#0CD29D teal) -- canonical default
local DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B = 12/255, 210/255, 157/255

-- Theme presets: { accentR, accentG, accentB, bgFile }
-- bgFile is relative to MEDIA_PATH (resolved later after MEDIA_PATH is defined)
local THEME_PRESETS = {
    ["EllesmereUI"]    = { r = 12/255,  g = 210/255, b = 157/255 },  -- #0CD29D
    ["Horde"]          = { r = 255/255, g = 90/255,  b = 31/255  },  -- #FF5A1F
    ["Alliance"]       = { r = 63/255,  g = 167/255, b = 255/255 },  -- #3FA7FF
    ["Faction (Auto)"] = nil,  -- resolved at runtime to Horde or Alliance
    ["Midnight"]       = { r = 120/255, g = 65/255,  b = 200/255 },  -- #7841C8  deep purple void
    ["Dark"]           = { r = 1,       g = 1,       b = 1       },  -- white accent
    ["Class Colored"]  = nil,  -- resolved at runtime from player class
    ["Custom Color"]   = nil,  -- user-chosen via color picker
}
local THEME_ORDER = { "EllesmereUI", "Horde", "Alliance", "Faction (Auto)", "Midnight", "Dark", "Class Colored", "Custom Color" }
-- Background file paths per theme (relative to MEDIA_PATH, in backgrounds/ subfolder)
local THEME_BG_FILES = {
    ["EllesmereUI"]   = "backgrounds\\eui-bg-all-compressed.png",
    ["Horde"]         = "backgrounds\\eui-bg-horde-compressed.png",
    ["Alliance"]      = "backgrounds\\eui-bg-alliance-compressed.png",
    ["Midnight"]      = "backgrounds\\eui-bg-midnight-compressed.png",
    ["Dark"]          = "backgrounds\\eui-bg-dark-compressed.png",
    ["Class Colored"] = "backgrounds\\eui-bg-all-compressed.png",
    ["Custom Color"]  = "backgrounds\\eui-bg-all-compressed.png",
}

--- Resolve "Faction (Auto)" to "Horde" or "Alliance" based on the player's faction.
--- For all other themes, returns the theme unchanged.
local function ResolveFactionTheme(theme)
    if theme == "Faction (Auto)" then
        local faction = UnitFactionGroup("player")
        return (faction == "Horde") and "Horde" or "Alliance"
    end
    return theme
end

-- EllesmereUIDB is initialized from SavedVariables at ADDON_LOADED time.
-- Do NOT create it here -- that would overwrite saved data.

-- Panel background
local PANEL_BG_R, PANEL_BG_G, PANEL_BG_B     = 0.05, 0.07, 0.09

-- Global border  (white + alpha -- adapts to any background tint)
local BORDER_R, BORDER_G, BORDER_B            = 1, 1, 1
local BORDER_A                                = 0.05

-- Text  (white + alpha -- adapts to any background tint)
local TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B = 1, 1, 1
local TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B       = 1, 1, 1
local TEXT_DIM_A                              = 0.53
local TEXT_SECTION_R, TEXT_SECTION_G, TEXT_SECTION_B = 1, 1, 1
local TEXT_SECTION_A                          = 0.41

-- Row alternating background alpha  (black overlay on option rows)
local ROW_BG_ODD        = 0.1
local ROW_BG_EVEN       = 0.2

-- Slider  (white + alpha for track -- adapts to any background tint)
local SL_TRACK_R, SL_TRACK_G, SL_TRACK_B     = 1, 1, 1               -- track bg (white + alpha)
local SL_TRACK_A                              = 0.16                   -- track bg alpha
local SL_FILL_A                               = 0.75                   -- filled portion alpha (colour = accent)
local SL_INPUT_R, SL_INPUT_G, SL_INPUT_B     = 0.02, 0.03, 0.04      -- input box background (darker than bg, stays as-is)
local SL_INPUT_A                              = 0.25                   -- input box alpha (all sliders)
local SL_INPUT_BRD_A                          = 0.02                   -- input box border alpha (white)

-- Multi-widget slider overrides  (applied additively in BuildSliderCore)
local MW_INPUT_ALPHA_BOOST                    = 0.15                   -- additive alpha boost for multi-widget input fields
local MW_TRACK_ALPHA_BOOST                    = 0.06                   -- additive alpha boost for multi-widget slider track

-- Toggle  (white + alpha for off states -- adapts to any background tint)
local TG_OFF_R, TG_OFF_G, TG_OFF_B          = 0.267, 0.267, 0.267    -- track when OFF (#444)
local TG_OFF_A                               = 0.65                   -- track OFF alpha
local TG_ON_A                                = 0.75                    -- track alpha at full ON (colour = accent)
local TG_KNOB_OFF_R, TG_KNOB_OFF_G, TG_KNOB_OFF_B = 1, 1, 1         -- knob when OFF (white + alpha)
local TG_KNOB_OFF_A                          = 0.5                    -- knob OFF alpha
local TG_KNOB_ON_R, TG_KNOB_ON_G, TG_KNOB_ON_B    = 1, 1, 1          -- knob when ON
local TG_KNOB_ON_A                           = 1                       -- knob ON alpha

-- Checkbox
local CB_BOX_R, CB_BOX_G, CB_BOX_B           = 0.10, 0.12, 0.16       -- box background
local CB_BRD_A, CB_ACT_BRD_A                  = 0.05, 0.15             -- box border alpha / checked border alpha

-- Button / WideButton
local BTN_BG_R, BTN_BG_G, BTN_BG_B           = 0.061, 0.095, 0.120   -- background
local BTN_BG_A                                = 0.6
local BTN_BG_HA                               = 0.65                   -- background alpha hovered
local BTN_BRD_A                               = 0.3                    -- border alpha (colour = white)
local BTN_BRD_HA                              = 0.45                   -- border alpha hovered
local BTN_TXT_A                               = 0.55                   -- text alpha (colour = white)
local BTN_TXT_HA                              = 0.70                   -- text alpha hovered

-- Dropdown
local DD_BG_R, DD_BG_G, DD_BG_B              = 0.075, 0.113, 0.141   -- background
local DD_BG_A                                 = 0.9
local DD_BG_HA                                = 0.98                   -- background alpha hovered
local DD_BRD_A                                = 0.20                   -- border alpha (colour = white)
local DD_BRD_HA                               = 0.30                   -- border alpha hovered
local DD_TXT_A                                = 0.50                   -- selected value text alpha (colour = white)
local DD_TXT_HA                               = 0.60                   -- selected value text alpha hovered
local DD_ITEM_HL_A                            = 0.08                   -- menu item highlight alpha (hover)
local DD_ITEM_SEL_A                           = 0.04                   -- menu item highlight alpha (active selection)

-- Sidebar nav  (white + alpha -- adapts to any background tint)
-- NAV values inlined directly into NAV_* locals below to avoid an extra file-scope local

-- Multi-widget layout  (dual = 2-up, triple = 3-up -- shared by all widget types)
local DUAL_ITEM_W       = 350              -- width of each item in a 2-up row
local DUAL_GAP          = 42               -- gap between 2-up items
local TRIPLE_ITEM_W     = 180              -- width of each item in a 3-up row
local TRIPLE_GAP        = 50               -- gap between 3-up items

-- Color swatch border (packed into table)
local CS = {
    BRD_THICK = 1, SAT_THRESH = 0.25, CHROMA_MIN = 0.15,
    SOLID_R = 1, SOLID_G = 1, SOLID_B = 1, SOLID_A = 1,
}

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  Derived / Internal  (built from visual settings -- no need to edit below)
-------------------------------------------------------------------------------
local ELLESMERE_GREEN
do
    -- NOTE: CLASS_COLOR_MAP is defined below, so at file-parse time we can only
    -- resolve preset themes. Class/Custom themes are fully resolved in PLAYER_LOGIN.
    local db = EllesmereUIDB or {}
    local theme = ResolveFactionTheme(db.activeTheme or "EllesmereUI")
    local r, g, b
    if theme == "Custom Color" then
        local sa = db.accentColor
        r, g, b = sa and sa.r or DEFAULT_ACCENT_R, sa and sa.g or DEFAULT_ACCENT_G, sa and sa.b or DEFAULT_ACCENT_B
    else
        local preset = THEME_PRESETS[theme]
        if preset then
            r, g, b = preset.r, preset.g, preset.b
        else
            r, g, b = DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B
        end
    end
    ELLESMERE_GREEN = { r = r, g = g, b = b, _themeEnabled = true }
end

-- Registry for one-time accent-colored elements (sidebar indicators, glows,
-- tab underlines, footer buttons, popup confirm button, etc.)
-- Each entry is { type="solid"|"gradient"|"font"|"callback", obj=..., ... }
local _accentElements = {}
local function RegAccent(entry)
    _accentElements[#_accentElements + 1] = entry
end
local DARK_BG         = { r = PANEL_BG_R, g = PANEL_BG_G, b = PANEL_BG_B }
local BORDER_COLOR    = { r = BORDER_R, g = BORDER_G, b = BORDER_B, a = BORDER_A }
local TEXT_WHITE      = { r = TEXT_WHITE_R, g = TEXT_WHITE_G, b = TEXT_WHITE_B }
local TEXT_DIM        = { r = TEXT_DIM_R, g = TEXT_DIM_G, b = TEXT_DIM_B, a = TEXT_DIM_A }
local TEXT_SECTION    = { r = TEXT_SECTION_R, g = TEXT_SECTION_G, b = TEXT_SECTION_B, a = TEXT_SECTION_A }

-- Sidebar nav states
local NAV_SELECTED_TEXT   = { r = TEXT_WHITE_R, g = TEXT_WHITE_G, b = TEXT_WHITE_B, a = 1 }
local NAV_SELECTED_ICON_A = 1
local NAV_ENABLED_TEXT    = { r = TEXT_WHITE_R, g = TEXT_WHITE_G, b = TEXT_WHITE_B, a = 0.6 }
local NAV_ENABLED_ICON_A  = 0.60
local NAV_DISABLED_TEXT   = { r = 1, g = 1, b = 1, a = 0.11 }
local NAV_DISABLED_ICON_A = 0.20
local NAV_HOVER_ENABLED_TEXT  = { r = 1, g = 1, b = 1, a = 0.86 }
local NAV_HOVER_DISABLED_TEXT = { r = 1, g = 1, b = 1, a = 0.39 }

-- Dropdown widget colours: widgets reference DD_BG_*, DD_BRD_*, DD_TXT_* directly

local BG_WIDTH, BG_HEIGHT = 1500, 1154
local CLICK_W, CLICK_H    = 1300, 946
local SIDEBAR_W  = 295
local HEADER_H   = 138      -- title + desc + banner glow + dark band for tabs
local TAB_BAR_H  = 40
local FOOTER_H   = 82
local CONTENT_PAD = 45
local CONTENT_HEADER_TOP_PAD = 10  -- extra top padding on scroll content when header is present

-- Paths  (media lives in EllesmereUI/media inside the parent addon folder)
local ADDON_PATH = "Interface\\AddOns\\" .. EUI_HOST_ADDON .. "\\"
local MEDIA_PATH = "Interface\\AddOns\\EllesmereUI\\media\\"
local _, playerClass = UnitClass("player")

local CLASS_ART_MAP = {
    DEATHKNIGHT  = "dk.png",
    DEMONHUNTER  = "dh.png",
    DRUID        = "druid.png",
    EVOKER       = "evoker.png",
    HUNTER       = "hunter.png",
    MAGE         = "mage.png",
    MONK         = "monk.png",
    PALADIN      = "paladin.png",
    PRIEST       = "priest.png",
    ROGUE        = "rogue.png",
    SHAMAN       = "shaman.png",
    WARLOCK      = "warlock.png",
    WARRIOR      = "warrior.png",
}

-- Official WoW class colors (from RAID_CLASS_COLORS)
local CLASS_COLOR_MAP = {
    DEATHKNIGHT  = { r = 0.77, g = 0.12, b = 0.23 },  -- #C41E3A
    DEMONHUNTER  = { r = 0.64, g = 0.19, b = 0.79 },  -- #A330C9
    DRUID        = { r = 1.00, g = 0.49, b = 0.04 },  -- #FF7C0A
    EVOKER       = { r = 0.20, g = 0.58, b = 0.50 },  -- #33937F
    HUNTER       = { r = 0.67, g = 0.83, b = 0.45 },  -- #AAD372
    MAGE         = { r = 0.25, g = 0.78, b = 0.92 },  -- #3FC7EB
    MONK         = { r = 0.00, g = 1.00, b = 0.60 },  -- #00FF98
    PALADIN      = { r = 0.96, g = 0.55, b = 0.73 },  -- #F48CBA
    PRIEST       = { r = 1.00, g = 1.00, b = 1.00 },  -- #FFFFFF
    ROGUE        = { r = 1.00, g = 0.96, b = 0.41 },  -- #FFF468
    SHAMAN       = { r = 0.00, g = 0.44, b = 0.87 },  -- #0070DD
    WARLOCK      = { r = 0.53, g = 0.53, b = 0.93 },  -- #8788EE
    WARRIOR      = { r = 0.78, g = 0.61, b = 0.43 },  -- #C69B6D
}

-- Font (Expressway lives in EllesmereUI/media)
local EXPRESSWAY = MEDIA_PATH .. "fonts\\Expressway.ttf"

-- Locale-specific system font fallback for clients whose language requires
-- glyphs not present in our custom fonts (CJK, Cyrillic, etc.)
local LOCALE_FONT_FALLBACK
do
    local _locale = GetLocale()
    if _locale == "zhCN" or _locale == "zhTW" then
        LOCALE_FONT_FALLBACK = "Fonts\\ARKai_T.ttf"
    elseif _locale == "koKR" then
        LOCALE_FONT_FALLBACK = "Fonts\\2002.TTF"
    elseif _locale == "ruRU" then
        LOCALE_FONT_FALLBACK = "Fonts\\FRIZQT___CYR.TTF"
    end
end
-------------------------------------------------------------------------------
--  Addon Roster  --  per-addon icon on/off from EllesmereUI/media
-------------------------------------------------------------------------------
local ICONS_PATH    = MEDIA_PATH .. "icons\\"

local ADDON_ROSTER = {
    { folder = "EllesmereUIActionBars",        display = "Action Bars",        search_name = "EllesmereUI Action Bars",        icon_on = ICONS_PATH .. "sidebar\\actionbars-ig-on.png",      icon_off = ICONS_PATH .. "sidebar\\actionbars-ig.png"      },
    { folder = "EllesmereUINameplates",        display = "Nameplates",         search_name = "EllesmereUI Nameplates",         icon_on = ICONS_PATH .. "sidebar\\nameplates-ig-on.png",      icon_off = ICONS_PATH .. "sidebar\\nameplates-ig.png"      },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",        search_name = "EllesmereUI Unit Frames",        icon_on = ICONS_PATH .. "sidebar\\unitframes-ig-on.png",      icon_off = ICONS_PATH .. "sidebar\\unitframes-ig.png"      },
    { folder = "EllesmereUIRaidFrames",        display = "Raid Frames",        search_name = "EllesmereUI Raid Frames",        icon_on = ICONS_PATH .. "sidebar\\raidframes-ig-on.png",      icon_off = ICONS_PATH .. "sidebar\\raidframes-ig.png",      comingSoon = true },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",   search_name = "EllesmereUI Cooldown Manager",   icon_on = ICONS_PATH .. "sidebar\\cdmeffects-ig-on.png",      icon_off = ICONS_PATH .. "sidebar\\cdmeffects-ig.png"      },
    { folder = "EllesmereUIResourceBars",      display = "Resource Bars",      search_name = "EllesmereUI Resource Bars",      icon_on = ICONS_PATH .. "sidebar\\resourcebars-ig-on-2.png",  icon_off = ICONS_PATH .. "sidebar\\resourcebars-ig-2.png"  },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders", search_name = "EllesmereUI AuraBuff Reminders", icon_on = ICONS_PATH .. "sidebar\\beacons-ig-on.png",         icon_off = ICONS_PATH .. "sidebar\\beacons-ig.png"         },
    { folder = "EllesmereUICursor",            display = "Cursor",             search_name = "EllesmereUI Cursor",             icon_on = ICONS_PATH .. "sidebar\\cursor-ig-on.png",          icon_off = ICONS_PATH .. "sidebar\\cursor-ig.png"          },
    { folder = "EllesmereUIBasics",            display = "Basics",             search_name = "EllesmereUI Basics",             icon_on = ICONS_PATH .. "sidebar\\basics-ig-on-2.png",        icon_off = ICONS_PATH .. "sidebar\\basics-ig-2.png",        comingSoon = true },
    { folder = "EllesmereUIPartyMode",         display = "Party Mode",         search_name = "EllesmereUI Party Mode",         icon_on = ICONS_PATH .. "sidebar\\partymode-ig-on.png",       icon_off = ICONS_PATH .. "sidebar\\partymode-ig.png",       alwaysLoaded = true },
}

local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name)
    elseif IsAddOnLoaded then return IsAddOnLoaded(name) end
    return false
end

-------------------------------------------------------------------------------
--  Forward declarations
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI or {}
_G.EllesmereUI = EllesmereUI
EllesmereUI._loaded = true
EllesmereUI.GLOBAL_KEY = "_EUIGlobal"
EllesmereUI.ADDON_ROSTER = ADDON_ROSTER
EllesmereUI.LOCALE_FONT_FALLBACK = LOCALE_FONT_FALLBACK
EllesmereUI.EXPRESSWAY = LOCALE_FONT_FALLBACK or EXPRESSWAY

local mainFrame, bgFrame, clickArea, sidebar, contentFrame
local headerFrame, tabBar, scrollFrame, scrollChild, footerFrame, contentHeaderFrame
local sidebarButtons = {}
local activeModule, activePage
local _lastPagePerModule = {}
local modules = {}
local scrollTarget = 0
local isSmoothing = false
local smoothFrame
local UpdateScrollThumb
local suppressScrollRangeChanged = false
-- Sidebar nav layout constants (set once in CreateMainFrame, used by RefreshSidebarStates)
local _sidebarNavRowH = 50
local _sidebarAddonNavTop = -228  -- NAV_TOP(-128) - NAV_ROW_H(50) * 2
local lastHeaderPadded = false
local skipScrollChildReanchor = false

-- Widget refresh registry: widgets register a Refresh callback so
-- RefreshPage can update values in-place without rebuilding frames.
local _widgetRefreshList = {}
local function RegisterWidgetRefresh(fn)
    _widgetRefreshList[#_widgetRefreshList + 1] = fn
end
EllesmereUI.RegisterWidgetRefresh = RegisterWidgetRefresh
local function ClearWidgetRefreshList()
    for i = 1, #_widgetRefreshList do _widgetRefreshList[i] = nil end
end

-- Hide all children/regions of a frame without orphaning them
local HideAllChildren
do
    local _hideAllScratch = {}
    local function _packIntoScratch(...)
        local n = select("#", ...)
        for i = 1, n do _hideAllScratch[i] = select(i, ...) end
        return n
    end
    HideAllChildren = function(parent, keepSet)
        -- Pack children into reusable scratch table (one GetChildren call)
        local n = _packIntoScratch(parent:GetChildren())
        for i = 1, n do
            if not (keepSet and keepSet[_hideAllScratch[i]]) then _hideAllScratch[i]:Hide() end
            _hideAllScratch[i] = nil
        end
        -- Pack regions into same scratch table (one GetRegions call)
        n = _packIntoScratch(parent:GetRegions())
        for i = 1, n do
            if not (keepSet and keepSet[_hideAllScratch[i]]) then _hideAllScratch[i]:Hide() end
            _hideAllScratch[i] = nil
        end
    end
end

-- OnShow callbacks -- available immediately; mainFrame hooks in when created
local _onShowCallbacks = {}
function EllesmereUI:RegisterOnShow(fn)
    _onShowCallbacks[#_onShowCallbacks + 1] = fn
end

-- OnHide callbacks -- fired when the settings panel closes
local _onHideCallbacks = {}
function EllesmereUI:RegisterOnHide(fn)
    _onHideCallbacks[#_onHideCallbacks + 1] = fn
end

-------------------------------------------------------------------------------
--  Utilities
-------------------------------------------------------------------------------
local function MakeFont(parent, size, flags, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(LOCALE_FONT_FALLBACK or EXPRESSWAY, size, flags or "")
    if r then fs:SetTextColor(r, g, b, a or 1) end
    return fs
end

local function SolidTex(parent, layer, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

-- Forward declaration: PP is populated after the Pixel Perfect do-block below
local PP

-- 4-sided 1px border on the BORDER layer (renders above BACKGROUND fill).
-- Returns a table { t, b, l, r } so callers can update color via SetColor().
-- Disable WoW's pixel snapping on a texture/frame so 1px elements never
-- round to 0 at sub-pixel positions.
local function DisablePixelSnap(obj)
    if obj.SetSnapToPixelGrid then
        obj:SetSnapToPixelGrid(false)
        obj:SetTexelSnappingBias(0)
    end
end

-- Create a dropdown arrow texture for dropdown buttons.
-- Uses a 30--30 square canvas image with the arrow centered, anchored via
-- two-point attachment so it inherits the parent's pixel-aligned bounds.
local function MakeDropdownArrow(parent, xPad, ppOverride)
    local pp = ppOverride or PP
    local arrow = parent:CreateTexture(nil, "ARTWORK")
    pp.DisablePixelSnap(arrow)
    arrow:SetTexture(ICONS_PATH .. "eui-arrow.png")
    local pad = (xPad or 12) + 5
    local sz = 26
    pp.Point(arrow, "TOPRIGHT", parent, "RIGHT", -(pad - sz/2), sz/2)
    pp.Point(arrow, "BOTTOMLEFT", parent, "RIGHT", -(pad + sz/2), -sz/2)
    return arrow
end

local function MakeBorder(parent, r, g, b, a, ppOverride)
    -- Wrapper around PP.CreateBorder that returns the legacy MakeBorder API.
    -- ppOverride: pass PanelPP for panel context, defaults to real PP for game context.
    local pp = ppOverride or PP
    local alpha = a or 1
    r = r or 0; g = g or 0; b = b or 0
    local bf = CreateFrame("Frame", nil, parent)
    bf:SetAllPoints(parent)
    bf:SetFrameLevel(parent:GetFrameLevel() + 1)
    bf:EnableMouse(false)

    -- Use the unified border system (returns a single BackdropTemplate frame)
    local brd = PP.CreateBorder(bf, r, g, b, alpha, 1, "BORDER", 7)

    -- Re-snap edges when panel scale changes
    if not EllesmereUI._onScaleChanged then EllesmereUI._onScaleChanged = {} end
    EllesmereUI._onScaleChanged[#EllesmereUI._onScaleChanged + 1] = function()
        PP.SetBorderSize(bf, 1)
    end

    return {
        _frame = bf,
        edges = brd,
        SetColor = function(self, cr, cg, cb, ca)
            PP.SetBorderColor(bf, cr, cg, cb, ca or 1)
        end,
    }
end

-- Alternating row backgrounds: evens get a subtle dark overlay, odds get nothing
-- Tracked per parent so each section's counter resets independently
-- When inside a split column (parent._splitParent exists), the bg is created on
-- the splitParent frame so it naturally spans the full width, anchored to the
-- widget frame's top/bottom edges for vertical positioning.
local rowCounters = {}
local function RowBg(frame, parent)
    if not rowCounters[parent] then rowCounters[parent] = 0 end
    rowCounters[parent] = rowCounters[parent] + 1
    local alpha = (rowCounters[parent] % 2 == 0) and ROW_BG_EVEN or ROW_BG_ODD
    local splitParent = parent._splitParent
    local bgParent = splitParent or frame
    local bg = bgParent:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, alpha)
    -- RowBg is always panel context — use PanelPP (resolved lazily since
    -- PanelPP is defined after this function in the file)
    local ppp = EllesmereUI.PanelPP or PP
    ppp.DisablePixelSnap(bg)
    bg:SetIgnoreParentAlpha(true)
    if splitParent then
        bg:SetPoint("LEFT", splitParent, "LEFT", 0, 0)
        bg:SetPoint("RIGHT", splitParent, "RIGHT", 0, 0)
        bg:SetPoint("TOP", frame, "TOP", 0, 0)
        bg:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    else
        bg:SetAllPoints()
    end
    -- Center divider (1px vertical line at the horizontal midpoint of the row)
    -- Only shown when parent._showRowDivider is set (e.g. Display page dual-column layout)
    if parent._showRowDivider and not frame._skipRowDivider then
        local div = frame:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.06)
        if div.SetSnapToPixelGrid then div:SetSnapToPixelGrid(false); div:SetTexelSnappingBias(0) end
        div:SetWidth(1)
        ppp.Point(div, "TOP",    frame, "TOP",    0, 0)
        ppp.Point(div, "BOTTOM", frame, "BOTTOM", 0, 0)
    end
end
-- Reset row counter (call from ClearContent so each rebuild starts fresh)
local function ResetRowCounters()
    wipe(rowCounters)
end

local function lerp(a, b, t) return a + (b - a) * t end

-------------------------------------------------------------------------------
--  Exports  (shared locals EllesmereUI table for split files)
-------------------------------------------------------------------------------
-- Visual constants (tables)
EllesmereUI.ELLESMERE_GREEN = ELLESMERE_GREEN
EllesmereUI.DARK_BG         = DARK_BG
EllesmereUI.BORDER_COLOR    = BORDER_COLOR
EllesmereUI.TEXT_WHITE       = TEXT_WHITE
EllesmereUI.TEXT_DIM         = TEXT_DIM
EllesmereUI.TEXT_SECTION     = TEXT_SECTION
EllesmereUI.CS              = CS

-- Shared icon paths
EllesmereUI.COGS_ICON       = MEDIA_PATH .. "icons\\cogs-3.png"
EllesmereUI.UNDO_ICON       = MEDIA_PATH .. "icons\\undo.png"
EllesmereUI.RESIZE_ICON     = MEDIA_PATH .. "icons\\eui-resize-5.png"
EllesmereUI.DIRECTIONS_ICON = MEDIA_PATH .. "icons\\eui-directions.png"
EllesmereUI.SYNC_ICON       = MEDIA_PATH .. "icons\\sync.png"

-- Numeric constants
EllesmereUI.TEXT_WHITE_R = TEXT_WHITE_R
EllesmereUI.TEXT_WHITE_G = TEXT_WHITE_G
EllesmereUI.TEXT_WHITE_B = TEXT_WHITE_B
EllesmereUI.TEXT_DIM_R = TEXT_DIM_R
EllesmereUI.TEXT_DIM_G = TEXT_DIM_G
EllesmereUI.TEXT_DIM_B = TEXT_DIM_B
EllesmereUI.TEXT_DIM_A = TEXT_DIM_A
EllesmereUI.TEXT_SECTION_R = TEXT_SECTION_R
EllesmereUI.TEXT_SECTION_G = TEXT_SECTION_G
EllesmereUI.TEXT_SECTION_B = TEXT_SECTION_B
EllesmereUI.TEXT_SECTION_A = TEXT_SECTION_A
EllesmereUI.ROW_BG_ODD  = ROW_BG_ODD
EllesmereUI.ROW_BG_EVEN = ROW_BG_EVEN
EllesmereUI.BORDER_R = BORDER_R
EllesmereUI.BORDER_G = BORDER_G
EllesmereUI.BORDER_B = BORDER_B
EllesmereUI.CONTENT_PAD = CONTENT_PAD
-- Slider
EllesmereUI.SL_TRACK_R = SL_TRACK_R
EllesmereUI.SL_TRACK_G = SL_TRACK_G
EllesmereUI.SL_TRACK_B = SL_TRACK_B
EllesmereUI.SL_TRACK_A = SL_TRACK_A
EllesmereUI.SL_FILL_A  = SL_FILL_A
EllesmereUI.SL_INPUT_R = SL_INPUT_R
EllesmereUI.SL_INPUT_G = SL_INPUT_G
EllesmereUI.SL_INPUT_B = SL_INPUT_B
EllesmereUI.SL_INPUT_A = SL_INPUT_A
EllesmereUI.SL_INPUT_BRD_A = SL_INPUT_BRD_A
EllesmereUI.MW_INPUT_ALPHA_BOOST = MW_INPUT_ALPHA_BOOST
EllesmereUI.MW_TRACK_ALPHA_BOOST = MW_TRACK_ALPHA_BOOST
-- Toggle
EllesmereUI.TG_OFF_R = TG_OFF_R
EllesmereUI.TG_OFF_G = TG_OFF_G
EllesmereUI.TG_OFF_B = TG_OFF_B
EllesmereUI.TG_OFF_A = TG_OFF_A
EllesmereUI.TG_ON_A  = TG_ON_A
EllesmereUI.TG_KNOB_OFF_R = TG_KNOB_OFF_R
EllesmereUI.TG_KNOB_OFF_G = TG_KNOB_OFF_G
EllesmereUI.TG_KNOB_OFF_B = TG_KNOB_OFF_B
EllesmereUI.TG_KNOB_OFF_A = TG_KNOB_OFF_A
EllesmereUI.TG_KNOB_ON_R  = TG_KNOB_ON_R
EllesmereUI.TG_KNOB_ON_G  = TG_KNOB_ON_G
EllesmereUI.TG_KNOB_ON_B  = TG_KNOB_ON_B
EllesmereUI.TG_KNOB_ON_A  = TG_KNOB_ON_A
-- Checkbox
EllesmereUI.CB_BOX_R = CB_BOX_R
EllesmereUI.CB_BOX_G = CB_BOX_G
EllesmereUI.CB_BOX_B = CB_BOX_B
EllesmereUI.CB_BRD_A     = CB_BRD_A
EllesmereUI.CB_ACT_BRD_A = CB_ACT_BRD_A
-- Button
EllesmereUI.BTN_BG_R  = BTN_BG_R
EllesmereUI.BTN_BG_G  = BTN_BG_G
EllesmereUI.BTN_BG_B  = BTN_BG_B
EllesmereUI.BTN_BG_A  = BTN_BG_A
EllesmereUI.BTN_BG_HA = BTN_BG_HA
EllesmereUI.BTN_BRD_A  = BTN_BRD_A
EllesmereUI.BTN_BRD_HA = BTN_BRD_HA
EllesmereUI.BTN_TXT_A  = BTN_TXT_A
EllesmereUI.BTN_TXT_HA = BTN_TXT_HA
-- Dropdown
EllesmereUI.DD_BG_R  = DD_BG_R
EllesmereUI.DD_BG_G  = DD_BG_G
EllesmereUI.DD_BG_B  = DD_BG_B
EllesmereUI.DD_BG_A  = DD_BG_A
EllesmereUI.DD_BG_HA = DD_BG_HA
EllesmereUI.DD_BRD_A  = DD_BRD_A
EllesmereUI.DD_BRD_HA = DD_BRD_HA
EllesmereUI.DD_TXT_A  = DD_TXT_A
EllesmereUI.DD_TXT_HA = DD_TXT_HA
EllesmereUI.DD_ITEM_HL_A  = DD_ITEM_HL_A
EllesmereUI.DD_ITEM_SEL_A = DD_ITEM_SEL_A
-- Layout
EllesmereUI.DUAL_ITEM_W  = DUAL_ITEM_W
EllesmereUI.DUAL_GAP     = DUAL_GAP
EllesmereUI.TRIPLE_ITEM_W = TRIPLE_ITEM_W
EllesmereUI.TRIPLE_GAP    = TRIPLE_GAP

-- Table constants
EllesmereUI.CLASS_COLOR_MAP = CLASS_COLOR_MAP
EllesmereUI.CLASS_ART_MAP   = CLASS_ART_MAP

-------------------------------------------------------------------------------
--  Pixel Perfect System
--  Ensures all UI elements snap to exact physical pixel boundaries regardless
--  of UI scale, monitor resolution, or element scale.  Uses the standard
--  approach but implemented independently.
--
--  Core idea:
--    perfect = 768 / physicalScreenHeight   (1 pixel in WoW's 768-based coord)
--    mult    = perfect / UIParent:GetScale() (1 physical pixel in current scale)
--    Scale(x) snaps any value to the nearest mult boundary.
--
--  Usage in addons:
--    local PP = EllesmereUI.PP
--    PP.Size(frame, w, h)   PP.Point(frame, ...)   PP.Width(frame, w)
--    PP.Height(frame, h)    PP.SetInside(obj, anchor, x, y)
--    PP.SetOutside(obj, anchor, x, y)   PP.DisablePixelSnap(texture)
--    PP.Scale(x)  -- returns snapped value
-------------------------------------------------------------------------------
do
    local GetPhysicalScreenSize = GetPhysicalScreenSize
    local InCombatLockdown = InCombatLockdown
    local type = type

    local PP = {}
    EllesmereUI.PP = PP

    ---------------------------------------------------------------------------
    --  Core pixel-perfect values
    ---------------------------------------------------------------------------
    PP.physicalWidth, PP.physicalHeight = GetPhysicalScreenSize()

    -- 768 is WoW's reference height; this gives us the size of 1 physical
    -- pixel in WoW's coordinate system at scale 1.0
    PP.perfect = 768 / PP.physicalHeight

    -- mult = size of 1 physical pixel in the current UIParent scale.
    -- When UIParent scale == perfect, mult == 1 and every integer is
    -- automatically pixel-perfect with no snapping needed.
    PP.mult = PP.perfect / (UIParent and UIParent:GetScale() or 1)

    --- Returns the ideal pixel-perfect scale, clamped to WoW's valid range.
    function PP.PixelBestSize()
        return max(0.4, min(PP.perfect, 1.15))
    end

    --- Recalculate mult after a scale or resolution change.
    function PP.UpdateMult()
        PP.physicalWidth, PP.physicalHeight = GetPhysicalScreenSize()
        PP.perfect = 768 / PP.physicalHeight
        local uiScale = EllesmereUIDB and EllesmereUIDB.ppUIScale or PP.PixelBestSize()
        PP.mult = PP.perfect / uiScale
    end

    --- Apply a new UI scale. Stores it, sets UIParent, recalculates mult.
    --- Defers to PLAYER_REGEN_ENABLED if called during combat.
    function PP.SetUIScale(newScale)
        if InCombatLockdown() then
            local deferFrame = CreateFrame("Frame")
            deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            deferFrame:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                PP.SetUIScale(newScale)
            end)
            return
        end
        if not EllesmereUIDB then EllesmereUIDB = {} end
        -- Only trigger frame rebuilds when the scale is actually changing.
        -- On login, Blizzard may reset UIParent scale, so we re-apply the
        -- stored value -- but if UIParent is already at the correct scale
        -- the frames are already positioned correctly and rebuilding them
        -- would shift user-customized positions unnecessarily.
        local currentScale = UIParent and UIParent:GetScale() or 1
        local scaleChanged = math.abs(currentScale - newScale) > 0.0001
        EllesmereUIDB.ppUIScale = newScale
        UIParent:SetScale(newScale)
        PP.UpdateMult()
        -- Rebuild child addon frames only when the scale actually changed.
        if scaleChanged then
            if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
            if _G._ERB_Apply then _G._ERB_Apply() end
            if _G._EAB_Apply then _G._EAB_Apply() end
        end
    end

    ---------------------------------------------------------------------------
    --  Scale(x)  — snap a value to the nearest physical-pixel boundary.
    --  Used for frame sizes, positions, and offsets.
    --
    --  Divides x into whole-pixel chunks of size `mult`, then truncates
    --  the fractional remainder so the result lands exactly on a pixel
    --  boundary.  Positive values floor, negative values ceil, so the
    --  magnitude always rounds toward zero.
    ---------------------------------------------------------------------------
    function PP.Scale(x)
        if x == 0 then return 0 end
        local m = PP.mult
        if m == 1 then return x end
        local pixels = x / m
        pixels = x > 0 and math.floor(pixels) or math.ceil(pixels)
        return pixels * m
    end

    ---------------------------------------------------------------------------
    --  SnapForES(x, effectiveScale)
    --
    --  Snap a value to a whole number of physical pixels at the given
    --  effective scale.  Uses the same approach as the border system:
    --    onePixel = perfect / es   (size of 1 physical pixel in frame coords)
    --    physPixels = floor(x / onePixel + 0.5)   (round to nearest whole pixel)
    --    result = physPixels * onePixel
    --
    --  This guarantees every element sized through this function is exactly
    --  N physical pixels, eliminating sub-pixel drift between siblings.
    ---------------------------------------------------------------------------
    function PP.SnapForES(x, es)
        if x == 0 then return 0 end
        local onePixel = PP.perfect / es
        local physPixels = math.floor(x / onePixel + 0.5)
        return physPixels * onePixel
    end

    ---------------------------------------------------------------------------
    --  Convenience wrappers — pixel-snapped frame geometry
    ---------------------------------------------------------------------------
    function PP.Size(frame, w, h)
        local sw = PP.Scale(w)
        frame:SetSize(sw, h and PP.Scale(h) or sw)
    end

    function PP.Width(frame, w)
        frame:SetWidth(PP.Scale(w))
    end

    function PP.Height(frame, h)
        frame:SetHeight(PP.Scale(h))
    end

    function PP.Point(obj, anchor, p1, p2, p3, p4)
        if not p1 then p1 = obj:GetParent() end
        if type(p1) == "number" then p1 = PP.Scale(p1) end
        if type(p2) == "number" then p2 = PP.Scale(p2) end
        if type(p3) == "number" then p3 = PP.Scale(p3) end
        if type(p4) == "number" then p4 = PP.Scale(p4) end
        obj:SetPoint(anchor, p1, p2, p3, p4)
    end

    function PP.SetInside(obj, anchor, xOff, yOff)
        anchor = anchor or obj:GetParent()
        local inset = PP.Scale(xOff or 1)
        local insetY = PP.Scale(yOff or 1)
        obj:ClearAllPoints()
        PP.DisablePixelSnap(obj)
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -insetY)
        obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, insetY)
    end

    function PP.SetOutside(obj, anchor, xOff, yOff)
        anchor = anchor or obj:GetParent()
        local outset = PP.Scale(xOff or 1)
        local outsetY = PP.Scale(yOff or 1)
        obj:ClearAllPoints()
        PP.DisablePixelSnap(obj)
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -outset, outsetY)
        obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", outset, -outsetY)
    end

    ---------------------------------------------------------------------------
    --  DisablePixelSnap — prevent WoW's engine from rounding texture
    --  coordinates to the nearest pixel, which causes blurry edges on
    --  sub-pixel-sized elements.
    ---------------------------------------------------------------------------
    function PP.DisablePixelSnap(obj)
        if not obj or obj.PixelSnapDisabled then return end

        -- Textures and FontStrings expose SetSnapToPixelGrid directly
        local target = obj
        if not obj.SetSnapToPixelGrid and obj.GetStatusBarTexture then
            -- StatusBars need their inner texture unsnapped instead
            target = obj:GetStatusBarTexture()
            if type(target) ~= "table" or not target.SetSnapToPixelGrid then
                obj.PixelSnapDisabled = true
                return
            end
        end

        if target.SetSnapToPixelGrid then
            target:SetSnapToPixelGrid(false)
            target:SetTexelSnappingBias(0)
        end
        obj.PixelSnapDisabled = true
    end

    ---------------------------------------------------------------------------
    --  Global Pixel Snap Prevention
    --
    --  WoW re-enables pixel snapping whenever a texture's properties change
    --  (SetTexture, SetColorTexture, SetVertexColor, SetTexCoord, etc.).
    --  This hooks the widget metatables so that every texture/statusbar in
    --  the game automatically has pixel snapping disabled after any property
    --  change. Without this, manual DisablePixelSnap calls get undone by
    --  Blizzard's code on spell swaps, page changes, combat transitions, etc.
    ---------------------------------------------------------------------------
    local function WatchPixelSnap(frame, snap)
        if (frame and not frame:IsForbidden()) and frame.PixelSnapDisabled and snap then
            frame.PixelSnapDisabled = nil
        end
    end

    local function HookPixelSnap(object)
        local mk = getmetatable(object)
        if not mk then return end
        mk = mk.__index
        if not mk or mk.DisabledPixelSnap then return end

        if mk.SetSnapToPixelGrid or mk.SetStatusBarTexture or mk.SetColorTexture
           or mk.SetVertexColor or mk.CreateTexture or mk.SetTexCoord or mk.SetTexture then
            if mk.SetSnapToPixelGrid then hooksecurefunc(mk, "SetSnapToPixelGrid", WatchPixelSnap) end
            if mk.SetStatusBarTexture then hooksecurefunc(mk, "SetStatusBarTexture", PP.DisablePixelSnap) end
            if mk.SetColorTexture then hooksecurefunc(mk, "SetColorTexture", PP.DisablePixelSnap) end
            if mk.SetVertexColor then hooksecurefunc(mk, "SetVertexColor", PP.DisablePixelSnap) end
            if mk.CreateTexture then hooksecurefunc(mk, "CreateTexture", PP.DisablePixelSnap) end
            if mk.SetTexCoord then hooksecurefunc(mk, "SetTexCoord", PP.DisablePixelSnap) end
            if mk.SetTexture then hooksecurefunc(mk, "SetTexture", PP.DisablePixelSnap) end
            mk.DisabledPixelSnap = true
        end
    end

    -- Hook all known widget types by creating one of each and hooking its metatable
    local hookFrame = CreateFrame("Frame")
    HookPixelSnap(hookFrame)
    HookPixelSnap(hookFrame:CreateTexture())
    HookPixelSnap(hookFrame:CreateFontString())
    HookPixelSnap(hookFrame:CreateMaskTexture())

    -- Enumerate all existing frame types to catch any we missed
    local hookedTypes = { Frame = true }
    local enumObj = EnumerateFrames()
    while enumObj do
        local objType = enumObj:GetObjectType()
        if not enumObj:IsForbidden() and not hookedTypes[objType] then
            HookPixelSnap(enumObj)
            hookedTypes[objType] = true
        end
        enumObj = EnumerateFrames(enumObj)
    end

    -- Also hook ScrollFrame and StatusBar metatables
    HookPixelSnap(CreateFrame("ScrollFrame"))
    do
        local sb = CreateFrame("StatusBar")
        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        HookPixelSnap(sb)
        local sbt = sb:GetStatusBarTexture()
        if sbt then HookPixelSnap(sbt) end
    end

    ---------------------------------------------------------------------------
    --  UNIFIED BORDER SYSTEM
    --
    --  All borders across every EllesmereUI addon use this single API.
    --  Uses 4 manual texture strips for pixel-perfect edge rendering.
    --  Each strip is exactly borderSize * mult UI units thick, which maps
    --  to exactly borderSize physical pixels. No BackdropTemplate, no
    --  sub-pixel interpolation.
    --
    --  _ppBorders is a container Frame (supports Show/Hide/SetShown).
    --  The 4 textures are stored as _ppBorders._top, _bottom, _left, _right.
    --
    --  API:
    --    PP.CreateBorder(frame, r, g, b, a, borderSize, drawLayer, subLevel)
    --    PP.SetBorderSize(frame, borderSize)
    --    PP.SetBorderColor(frame, r, g, b, a)
    --    PP.UpdateBorder(frame, borderSize, r, g, b, a)
    --    PP.HideBorder(frame)
    --    PP.ShowBorder(frame)
    ---------------------------------------------------------------------------

    local function SnapBorderTextures(container, frame, borderSize)
        -- Calculate thickness that maps to exactly N physical pixels in this
        -- frame's coordinate space, regardless of parent scale chains.
        --   physPixels = borderSize (always an integer: 1, 2, 3 …)
        --   1 physical pixel in screen coords = 1 / physicalHeight
        --   1 physical pixel in frame coords  = (1 / physicalHeight) / effectiveScale
        --                                     = perfect / (768 * effectiveScale)
        -- Simplified: perfect / es  gives 1 physical pixel in frame coords.
        local es = container:GetEffectiveScale()
        local onePixel = es > 0 and (PP.perfect / es) or PP.mult
        local t = math.max(onePixel, math.floor((borderSize or 1) + 0.5) * onePixel)
        local top, bottom, left, right = container._top, container._bottom, container._left, container._right

        -- Top: full width, sits at the top edge
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        top:SetHeight(t)

        -- Bottom: full width, sits at the bottom edge
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(t)

        -- Left: between top and bottom strips
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
        left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
        left:SetWidth(t)

        -- Right: between top and bottom strips
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
        right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
        right:SetWidth(t)
    end

    ---------------------------------------------------------------------------
    --  Border registry — tracks all border containers for centralized re-snap
    --  when UI scale or resolution changes. Avoids per-border OnUpdate overhead.
    ---------------------------------------------------------------------------
    local allBorders = {}
    local allBordersN = 0

    local function RegisterBorder(container, frame)
        allBordersN = allBordersN + 1
        allBorders[allBordersN] = { container = container, frame = frame }
    end

    --- Re-snap every registered border. Called on scale/resolution changes.
    function PP.ResnapAllBorders()
        for i = 1, allBordersN do
            local entry = allBorders[i]
            local c, f = entry.container, entry.frame
            if c and f then
                SnapBorderTextures(c, f, f._ppBorderSize or 1)
            end
        end
    end

    function PP.CreateBorder(frame, r, g, b, a, borderSize, drawLayer, subLevel)
        if frame._ppBorders then return frame._ppBorders end
        r = r or 0; g = g or 0; b = b or 0; a = a or 1
        borderSize = borderSize or 1
        drawLayer = drawLayer or "OVERLAY"
        subLevel = subLevel or 1

        local container = CreateFrame("Frame", nil, frame)
        container:SetAllPoints(frame)
        -- Don't bump frame level — the textures' drawLayer and subLevel
        -- control visual stacking. Keeping the container at the parent's
        -- level avoids covering sibling frames like glow overlays.
        container:SetFrameLevel(frame:GetFrameLevel())

        local function MakeTex()
            local tex = container:CreateTexture(nil, drawLayer, nil, subLevel)
            tex:SetColorTexture(r, g, b, a)
            PP.DisablePixelSnap(tex)
            return tex
        end

        container._top = MakeTex()
        container._bottom = MakeTex()
        container._left = MakeTex()
        container._right = MakeTex()

        -- Initial snap (effective scale may not be final yet)
        SnapBorderTextures(container, frame, borderSize)

        -- Short-lived OnUpdate: re-snap for 2 frames to catch the final
        -- effective scale after parent frames finish layout, then stop.
        local ticks = 0
        container:SetScript("OnUpdate", function(self)
            ticks = ticks + 1
            SnapBorderTextures(self, frame, frame._ppBorderSize or 1)
            if ticks >= 2 then
                self:SetScript("OnUpdate", nil)
            end
        end)

        -- Register for centralized re-snap on scale/resolution changes
        RegisterBorder(container, frame)

        frame._ppBorders = container
        frame._ppBorderSize = borderSize
        frame._ppBorderColor = { r, g, b, a }
        return container
    end

    function PP.SetBorderSize(frame, borderSize)
        local container = frame._ppBorders
        if not container then return end
        borderSize = borderSize or 1
        SnapBorderTextures(container, frame, borderSize)
        frame._ppBorderSize = borderSize
    end

    function PP.SetBorderColor(frame, r, g, b, a)
        local container = frame._ppBorders
        if not container then return end
        a = a or 1
        frame._ppBorderColor = { r, g, b, a }
        container._top:SetColorTexture(r, g, b, a)
        container._bottom:SetColorTexture(r, g, b, a)
        container._left:SetColorTexture(r, g, b, a)
        container._right:SetColorTexture(r, g, b, a)
    end

    function PP.UpdateBorder(frame, borderSize, r, g, b, a)
        if r then PP.SetBorderColor(frame, r, g, b, a) end
        PP.SetBorderSize(frame, borderSize)
    end

    function PP.HideBorder(frame)
        local container = frame._ppBorders
        if container then container:Hide() end
    end

    function PP.ShowBorder(frame)
        local container = frame._ppBorders
        if container then container:Show() end
    end

    ---------------------------------------------------------------------------
    --  Scale change watcher
    ---------------------------------------------------------------------------
    local scaleWatcher = CreateFrame("Frame")
    scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
    scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    scaleWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    scaleWatcher:SetScript("OnEvent", function(_, event)
        if event == "DISPLAY_SIZE_CHANGED" then
            -- Resolution changed — recalculate perfect and re-apply scale
            PP.physicalWidth, PP.physicalHeight = GetPhysicalScreenSize()
            PP.perfect = 768 / PP.physicalHeight
            -- Only auto-update if user explicitly opted into auto scale
            if EllesmereUIDB and EllesmereUIDB.ppUIScaleAuto == true then
                PP.SetUIScale(PP.PixelBestSize())
            else
                PP.UpdateMult()
            end
        else
            PP.UpdateMult()
        end
        -- Re-snap all borders with the new scale values
        PP.ResnapAllBorders()
        -- Re-sync panel scale so pixel-perfect stays accurate after
        -- loading screens, resolution changes, or UI scale changes
        local mf = EllesmereUI._mainFrame
        if mf and mf:IsShown() then
            local physW = (GetPhysicalScreenSize())
            local sw = GetScreenWidth()
            if physW and physW > 0 and sw and sw > 0 then
                local baseScale = sw / physW
                local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
                mf:SetScale(baseScale * userScale)
                if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end
            end
        end
    end)
end

-- File-level PP reference for code outside the do block
PP = EllesmereUI.PP

-------------------------------------------------------------------------------
--  Panel Pixel Perfect (PanelPP)
--  The options panel runs at effective scale = baseScale * userScale.
--  At userScale 1.0, 1 unit = 1 physical pixel and integer rounding suffices.
--  At other scales (e.g. 101%), 1 unit ≠ 1 pixel, so PanelPP computes its
--  own mult (size of 1 physical pixel in panel units) and snaps to that grid,
--  exactly like PP does for UIParent but using the panel's own scale.
-------------------------------------------------------------------------------
do
    local PanelPP = {}
    EllesmereUI.PanelPP = PanelPP

    local floor, type = math.floor, type

    -- mult = size of 1 physical pixel in panel coordinate units.
    -- At userScale 1.0 this is 1.0; at 1.01 it's ~0.9901.
    -- Recalculated by UpdateMult() when the panel scale changes.
    PanelPP.mult = 1

    function PanelPP.UpdateMult()
        local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
        if userScale == 0 then userScale = 1 end
        -- 1 physical pixel = 1/userScale panel units
        PanelPP.mult = 1 / userScale
    end

    -- Snap a value to the nearest physical pixel boundary in panel coords
    function PanelPP.Scale(x)
        if x == 0 then return 0 end
        local m = PanelPP.mult
        if m == 1 then return floor(x + 0.5) end
        -- Same snapping algorithm as PP.Scale
        local y = m > 1 and m or -m
        return x - x % (x < 0 and y or -y)
    end

    function PanelPP.Size(frame, w, h)
        local sw = PanelPP.Scale(w)
        frame:SetSize(sw, h and PanelPP.Scale(h) or sw)
    end

    function PanelPP.Width(frame, w)
        frame:SetWidth(PanelPP.Scale(w))
    end

    function PanelPP.Height(frame, h)
        frame:SetHeight(PanelPP.Scale(h))
    end

    function PanelPP.Point(obj, arg1, arg2, arg3, arg4, arg5)
        if not arg2 then arg2 = obj:GetParent() end
        if type(arg2) == "number" then arg2 = PanelPP.Scale(arg2) end
        if type(arg3) == "number" then arg3 = PanelPP.Scale(arg3) end
        if type(arg4) == "number" then arg4 = PanelPP.Scale(arg4) end
        if type(arg5) == "number" then arg5 = PanelPP.Scale(arg5) end
        obj:SetPoint(arg1, arg2, arg3, arg4, arg5)
    end

    function PanelPP.SetInside(obj, anchor, xOff, yOff)
        if not anchor then anchor = obj:GetParent() end
        local x = PanelPP.Scale(xOff or 1)
        local y = PanelPP.Scale(yOff or 1)
        obj:ClearAllPoints()
        PanelPP.DisablePixelSnap(obj)
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -y)
        obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -x, y)
    end

    function PanelPP.SetOutside(obj, anchor, xOff, yOff)
        if not anchor then anchor = obj:GetParent() end
        local x = PanelPP.Scale(xOff or 1)
        local y = PanelPP.Scale(yOff or 1)
        obj:ClearAllPoints()
        PanelPP.DisablePixelSnap(obj)
        obj:SetPoint("TOPLEFT", anchor, "TOPLEFT", -x, y)
        obj:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", x, -y)
    end

    -- DisablePixelSnap is scale-independent — just reuse PP's version
    PanelPP.DisablePixelSnap = PP.DisablePixelSnap

    -- Panel borders delegate to the unified PP border system
    PanelPP.CreateBorder  = PP.CreateBorder
    PanelPP.SetBorderSize = PP.SetBorderSize
    PanelPP.SetBorderColor = PP.SetBorderColor
    PanelPP.UpdateBorder  = PP.UpdateBorder
    PanelPP.HideBorder    = PP.HideBorder
    PanelPP.ShowBorder    = PP.ShowBorder
end

-- File-level PanelPP reference for panel layout code outside the do block
local PanelPP = EllesmereUI.PanelPP

-------------------------------------------------------------------------------
--  Global Color System
--  Central source of truth for class, power, and resource colors.
--  Stored in EllesmereUIDB.customColors; falls back to WoW defaults.
-------------------------------------------------------------------------------

-- Default power colors (from WoW's PowerBarColor)
EllesmereUI.DEFAULT_POWER_COLORS = {
    MANA         = { r = 0x33/255, g = 0x59/255, b = 0xD9/255 },
    RAGE         = { r = 1.000, g = 0.000, b = 0.000 },
    FOCUS        = { r = 1.000, g = 0.500, b = 0.250 },
    ENERGY       = { r = 1.000, g = 1.000, b = 0.000 },
    RUNIC_POWER  = { r = 0.000, g = 0.820, b = 1.000 },
    LUNAR_POWER  = { r = 0.300, g = 0.520, b = 0.900 },
    INSANITY     = { r = 0.400, g = 0.000, b = 0.800 },
    MAELSTROM    = { r = 0.000, g = 0.500, b = 1.000 },
    FURY         = { r = 0.788, g = 0.259, b = 0.992 },
    PAIN         = { r = 1.000, g = 0.612, b = 0.000 },
}

-- Default resource colors (class-specific resource pips)
EllesmereUI.DEFAULT_RESOURCE_COLORS = {
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
    MONK        = { r = 0.00, g = 1.00, b = 0.60 },
    WARLOCK     = { r = 0.58, g = 0.51, b = 0.79 },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    DEMONHUNTER = { r = 0.34, g = 0.06, b = 0.46 },
}

-- Class -> primary power type name mapping
EllesmereUI.CLASS_POWER_MAP = {
    WARRIOR      = "RAGE",
    PALADIN      = "MANA",
    HUNTER       = "FOCUS",
    ROGUE        = "ENERGY",
    PRIEST       = "MANA",
    DEATHKNIGHT  = "RUNIC_POWER",
    SHAMAN       = "MANA",
    MAGE         = "MANA",
    WARLOCK      = "MANA",
    MONK         = "ENERGY",
    DRUID        = "MANA",
    DEMONHUNTER  = "FURY",
    EVOKER       = "MANA",
}

-- Class -> resource type mapping (nil = no class resource)
EllesmereUI.CLASS_RESOURCE_MAP = {
    ROGUE       = "ComboPoints",
    DRUID       = "ComboPoints",
    PALADIN     = "HolyPower",
    MONK        = "Chi",
    WARLOCK     = "SoulShards",
    MAGE        = "ArcaneCharges",
    EVOKER      = "Essence",
    DEATHKNIGHT = "Runes",
    DEMONHUNTER = "SoulFragments",
}

-- Darken a color by a fraction (for default gradient secondary)
function EllesmereUI.DarkenColor(r, g, b, frac)
    frac = frac or 0.10
    return r * (1 - frac), g * (1 - frac), b * (1 - frac)
end

-- Get the custom colors DB table (lazy-init)
function EllesmereUI.GetCustomColorsDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.customColors then EllesmereUIDB.customColors = {} end
    return EllesmereUIDB.customColors
end

-------------------------------------------------------------------------------
--  Global Font System
-------------------------------------------------------------------------------
-- Canonical font name → filename mapping (shared across all addons)
EllesmereUI.FONT_FILES = {
    ["Expressway"]          = "Expressway.TTF",
    ["Avant Garde"]         = "Avant Garde.ttf",
    ["Arial Bold"]          = "Arial Bold.TTF",
    ["Poppins"]             = "Poppins.ttf",
    ["Fira Sans Medium"]    = "FiraSans Medium.ttf",
    ["Arial Narrow"]        = "Arial Narrow.ttf",
    ["Changa"]              = "Changa.ttf",
    ["Cinzel Decorative"]   = "Cinzel Decorative.ttf",
    ["Exo"]                 = "Exo.otf",
    ["Fira Sans Bold"]      = "FiraSans Bold.ttf",
    ["Fira Sans Light"]     = "FiraSans Light.ttf",
    ["Future X Black"]      = "Future X Black.otf",
    ["Gotham Narrow Ultra"] = "Gotham Narrow Ultra.otf",
    ["Gotham Narrow"]       = "Gotham Narrow.otf",
    ["Russo One"]           = "Russo One.ttf",
    ["Ubuntu"]              = "Ubuntu.ttf",
    ["Homespun"]            = "Homespun.ttf",
    ["Friz Quadrata"]       = nil,  -- Blizzard font
    ["Arial"]               = nil,  -- Blizzard font
    ["Morpheus"]            = nil,  -- Blizzard font
    ["Skurri"]              = nil,  -- Blizzard font
}
-- Blizzard built-in font paths (not in our media folder)
EllesmereUI.FONT_BLIZZARD = {
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial"]         = "Fonts\\ARIALN.TTF",
    ["Morpheus"]      = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]        = "Fonts\\skurri.ttf",
}
EllesmereUI.FONT_ORDER = {
    "Expressway", "Avant Garde", "Arial Bold", "Poppins", "Fira Sans Medium",
    "---",
    "Arial Narrow", "Changa", "Cinzel Decorative", "Exo",
    "Fira Sans Bold", "Fira Sans Light", "Future X Black",
    "Gotham Narrow Ultra", "Gotham Narrow", "Russo One", "Ubuntu", "Homespun",
    "Friz Quadrata", "Arial", "Morpheus", "Skurri",
}
-- Display name overrides for the font dropdown (key = FONT_ORDER name)
EllesmereUI.FONT_DISPLAY_NAMES = {
    ["Avant Garde"] = "Avant Garde (Naowh)",
}

-- Get the fonts DB table (lazy-init)
function EllesmereUI.GetFontsDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.fonts then
        EllesmereUIDB.fonts = {
            global      = "Expressway",
            outlineMode = "shadow",
        }
    end
    -- Migrate legacy per-addon keys (no longer used)
    local f = EllesmereUIDB.fonts
    f.globalEnabled = nil
    f.actionBars    = nil
    f.nameplates    = nil
    f.unitFrames    = nil
    f.cdm           = nil
    f.resourceBars  = nil
    f.auraBuff      = nil
    f.raidFrames    = nil
    f.minimapChat   = nil
    f.extras        = nil
    return f
end

-- Resolve a font name to a full file path for a given addon
-- addonDir: the addon's Interface\AddOns\<name> path (used to build EllesmereUI/media/fonts/ path)
local function ResolveFontName(fontName)
    -- For locales that need system fonts (CJK, Cyrillic), skip custom fonts
    if LOCALE_FONT_FALLBACK then return LOCALE_FONT_FALLBACK end
    local bliz = EllesmereUI.FONT_BLIZZARD[fontName]
    if bliz then return bliz end
    local file = EllesmereUI.FONT_FILES[fontName]
    if file then
        return MEDIA_PATH .. "fonts\\" .. file
    end
    -- SharedMedia fonts store their path in FONT_SM_PATHS (populated at init)
    local smPath = EllesmereUI._smFontPaths and EllesmereUI._smFontPaths[fontName]
    if smPath then return smPath end
    -- Fallback to Expressway
    return MEDIA_PATH .. "fonts\\Expressway.TTF"
end
EllesmereUI.ResolveFontName = ResolveFontName

-- Get the resolved font path for an addon key (addonKey is ignored — always uses global font)
function EllesmereUI.GetFontPath(addonKey)
    local db = EllesmereUI.GetFontsDB()
    return ResolveFontName(db.global or "Expressway")
end

-- Get the font name (not path) for an addon key (addonKey is ignored — always uses global font)
function EllesmereUI.GetFontName(addonKey)
    local db = EllesmereUI.GetFontsDB()
    return db.global or "Expressway"
end

-- Get the WoW font flag string for the current global outline mode.
-- Returns: "OUTLINE", "THICKOUTLINE", or "" (none/shadow — caller should set shadow offset)
function EllesmereUI.GetFontOutlineFlag()
    local db = EllesmereUI.GetFontsDB()
    local mode = db.outlineMode or "shadow"
    if mode == "outline" then
        return "OUTLINE"
    elseif mode == "thick" then
        return "THICKOUTLINE"
    else
        return ""
    end
end

-- Returns true when the current outline mode uses drop shadow instead of outline.
-- Callers that set SetShadowOffset should check this to decide whether to show shadow.
function EllesmereUI.GetFontUseShadow()
    local db = EllesmereUI.GetFontsDB()
    local mode = db.outlineMode or "shadow"
    return mode == "none" or mode == "shadow"
end

-- Get class color (custom or default)
function EllesmereUI.GetClassColor(classToken)
    local db = EllesmereUI.GetCustomColorsDB()
    if db.class and db.class[classToken] then
        return db.class[classToken]
    end
    local def = CLASS_COLOR_MAP[classToken]
    if def then return { r = def.r, g = def.g, b = def.b } end
    return { r = 1, g = 1, b = 1 }
end

-- Get power color (custom or default)
function EllesmereUI.GetPowerColor(powerKey)
    local db = EllesmereUI.GetCustomColorsDB()
    if db.power and db.power[powerKey] then
        return db.power[powerKey]
    end
    local def = EllesmereUI.DEFAULT_POWER_COLORS[powerKey]
    if def then return { r = def.r, g = def.g, b = def.b } end
    return { r = 1, g = 1, b = 1 }
end

-- Get resource color (custom or default)
function EllesmereUI.GetResourceColor(classToken)
    local db = EllesmereUI.GetCustomColorsDB()
    if db.resource and db.resource[classToken] then
        return db.resource[classToken]
    end
    local def = EllesmereUI.DEFAULT_RESOURCE_COLORS[classToken]
    if def then return { r = def.r, g = def.g, b = def.b } end
    return nil
end

-- Reset colors for a specific class (class color + resource color + power stays)
function EllesmereUI.ResetClassColors(classToken)
    local db = EllesmereUI.GetCustomColorsDB()
    if db.class then db.class[classToken] = nil end
    if db.resource then db.resource[classToken] = nil end
end

-- Reset a specific power color
function EllesmereUI.ResetPowerColor(powerKey)
    local db = EllesmereUI.GetCustomColorsDB()
    if db.power then db.power[powerKey] = nil end
end

-- Power key string -> Enum.PowerType mapping
EllesmereUI.POWER_KEY_TO_ENUM = {
    MANA         = 0,
    RAGE         = 1,
    FOCUS        = 2,
    ENERGY       = 3,
    RUNIC_POWER  = 6,
    LUNAR_POWER  = 8,
    INSANITY     = 13,
    MAELSTROM    = 11,
    FURY         = 17,
    PAIN         = 18,
}

-- Apply custom class colors to oUF (call after settings change)
function EllesmereUI.ApplyColorsToOUF()
    -- 1. Update oUF color objects (unit frames)
    -- NOTE: We intentionally do NOT modify _G.RAID_CLASS_COLORS.
    -- Touching that Blizzard global causes taint in 12.0+.
    local oUF = _G.EllesmereUF
    if oUF and oUF.colors then
        if oUF.colors.class then
            for classToken, _ in pairs(CLASS_COLOR_MAP) do
                local cc = EllesmereUI.GetClassColor(classToken)
                local entry = oUF.colors.class[classToken]
                if entry then
                    if entry.SetRGBA then
                        entry:SetRGBA(cc.r, cc.g, cc.b, 1)
                    else
                        entry[1] = cc.r; entry[2] = cc.g; entry[3] = cc.b
                    end
                end
            end
        end
        if oUF.colors.power then
            for powerKey, enumVal in pairs(EllesmereUI.POWER_KEY_TO_ENUM) do
                local pc = EllesmereUI.GetPowerColor(powerKey)
                local entry = oUF.colors.power[enumVal]
                if entry then
                    if entry.SetRGBA then
                        entry:SetRGBA(pc.r, pc.g, pc.b, 1)
                    else
                        entry[1] = pc.r; entry[2] = pc.g; entry[3] = pc.b
                    end
                end
            end
        end
        if oUF.objects then
            for _, obj in next, oUF.objects do
                obj:UpdateAllElements("ForceUpdate")
            end
        end
    end
    -- 3. Refresh nameplates (enemy + friendly)
    local ns_NP = _G.EllesmereNameplates_NS
    if ns_NP then
        if ns_NP.plates then
            for _, plate in pairs(ns_NP.plates) do
                if plate.UpdateHealthColor then plate:UpdateHealthColor() end
            end
        end
        if ns_NP.friendlyPlates then
            for _, plate in pairs(ns_NP.friendlyPlates) do
                if plate.unit and UnitIsPlayer(plate.unit) then
                    local _, classToken = UnitClass(plate.unit)
                    local cc = classToken and EllesmereUI.GetClassColor(classToken)
                    if cc and plate.health then
                        plate.health:SetStatusBarColor(cc.r, cc.g, cc.b)
                    end
                end
            end
        end
    end
    -- 4. Refresh raid frames
    local ERF = _G.EllesmereUIRaidFrames
    if ERF and ERF.UpdateAllFrames then
        ERF:UpdateAllFrames()
    end
    -- 5. Refresh action bar borders (class-colored borders read RAID_CLASS_COLORS)
    local ok, EAB = pcall(function()
        return EllesmereUI.Lite and EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
    end)
    if ok and EAB and EAB.ApplyBorders and not InCombatLockdown() then
        EAB:ApplyBorders()
        if EAB.ApplyShapes then EAB:ApplyShapes() end
    end
end

-------------------------------------------------------------------------------
--  Manual resource trackers (12.0+ secret-value safe)
--  These track stacks via UNIT_SPELLCAST_SUCCEEDED instead of reading aura
--  data, which returns secret values in combat under Midnight restrictions.
--  Maelstrom Weapon (344179) and Devourer soul fragment auras (1225789,
--  1227702) are whitelisted by Blizzard and remain readable.
-------------------------------------------------------------------------------

-- Tip of the Spear tracker (Survival Hunter)
-- Kill Command (259489) grants 1 stack (2 with Primal Surge talent 1272154).
-- Takedown (1250646) grants 2 stacks when Twin Fang (1272139) is known.
-- Various spender abilities consume 1 stack each.
-- Buff duration: 10 seconds, max 3 stacks.
-- Talent spell: 260285
do
    local stacks, expiresAt = 0, nil
    local MAX = 3
    local DURATION = 10
    local TALENT     = 260285
    local KILL_CMD   = 259489
    local PRIMAL     = 1272154
    local TAKEDOWN   = 1250646
    local TWIN_FANG  = 1272139

    local SPENDERS = {
        [186270]  = true,  -- Raptor Strike
        [265189]  = true,  -- Raptor Strike (ranged)
        [1262293] = true,  -- Raptor Swipe
        [1262343] = true,  -- Raptor Swipe (ranged)
        [259495]  = true,  -- Wildfire Bomb
        [193265]  = true,  -- Hatchet Toss
        [1264949] = true,  -- Chakram
        [1261193] = true,  -- Boomstick
        [1253859] = true,  -- Takedown (also spends)
        [1251592] = true,  -- Flamefang Pitch
    }

    function EllesmereUI.HandleTipOfTheSpear(event, unit, _, spellID)
        if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
            stacks, expiresAt = 0, nil
            return
        end
        if event ~= "UNIT_SPELLCAST_SUCCEEDED" or unit ~= "player" then return end
        if not (C_SpellBook and C_SpellBook.IsSpellKnown(TALENT)) then return end

        if spellID == KILL_CMD then
            local gain = (C_SpellBook.IsSpellKnown(PRIMAL) and 2 or 1)
            stacks = min(MAX, stacks + gain)
            expiresAt = GetTime() + DURATION
        elseif spellID == TAKEDOWN and C_SpellBook.IsSpellKnown(TWIN_FANG) then
            stacks = min(MAX, stacks + 2)
            expiresAt = GetTime() + DURATION
        elseif SPENDERS[spellID] and stacks > 0 then
            stacks = stacks - 1
            if stacks == 0 then expiresAt = nil end
        end
    end

    function EllesmereUI.GetTipOfTheSpear()
        if expiresAt and GetTime() >= expiresAt then
            stacks, expiresAt = 0, nil
        end
        return stacks, MAX
    end
end

-- Improved Whirlwind tracker (Fury Warrior)
-- Whirlwind (190411) sets stacks to max (4).
-- Thunder Clap (6343) / Thunder Blast (435222) also set to max when
-- Crashing Thunder talent (436707) is known.
-- Single-target spenders consume 1 stack each.
-- Buff duration: 20 seconds, max 4 stacks.
-- Required talent: 12950 (Improved Whirlwind)
do
    local stacks, expiresAt = 0, nil
    local MAX = 4
    local DURATION = 20
    local REQUIRED       = 12950
    local CRASHING       = 436707
    local UNHINGED       = 386628
    local BLADESTORM     = 446035
    local BLADESTORM_DUR = 4  -- Bladestorm base duration in seconds

    local GENERATORS = {
        [190411] = true,  -- Whirlwind
        [6343]   = true,  -- Thunder Clap
        [435222] = true,  -- Thunder Blast
    }

    local SPENDERS = {
        [23881]  = true,  -- Bloodthirst
        [85288]  = true,  -- Raging Blow
        [280735] = true,  -- Execute
        [5308]   = true,  -- Execute (base)
        [202168] = true,  -- Impending Victory
        [184367] = true,  -- Rampage
        [335096] = true,  -- Bloodbath
        [335097] = true,  -- Crushing Blow
    }

    -- Bloodthirst / Bloodbath don't consume stacks during Bladestorm
    -- when Unhinged (386628) is talented.  We track Bladestorm activation
    -- via UNIT_SPELLCAST_SUCCEEDED so we never call C_Spell.IsSpellUsable
    -- (which may return secret values in 12.0+).
    local UNHINGED_EXEMPT = { [23881] = true, [335096] = true }
    local bladestormEndsAt = 0

    -- Deduplicate cast events via GUID
    local seenGUID = {}
    local guidCount = 0

    function EllesmereUI.HandleWhirlwindStacks(event, unit, castGUID, spellID)
        if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
            stacks, expiresAt = 0, nil
            bladestormEndsAt = 0
            wipe(seenGUID)
            guidCount = 0
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            -- Clean up GUID cache on combat end to prevent unbounded growth
            wipe(seenGUID)
            guidCount = 0
            return
        end
        if event ~= "UNIT_SPELLCAST_SUCCEEDED" or unit ~= "player" then return end
        if not (C_SpellBook and C_SpellBook.IsSpellKnown(REQUIRED)) then return end

        if castGUID and seenGUID[castGUID] then return end
        if castGUID then
            seenGUID[castGUID] = true
            guidCount = guidCount + 1
            -- Safety: flush if table grows too large (shouldn't happen normally)
            if guidCount > 200 then wipe(seenGUID); guidCount = 0 end
        end

        -- Track Bladestorm activation for Unhinged interaction
        if spellID == BLADESTORM then
            bladestormEndsAt = GetTime() + BLADESTORM_DUR
            return
        end

        if GENERATORS[spellID] then
            -- Thunder Clap / Thunder Blast only count with Crashing Thunder
            if (spellID == 6343 or spellID == 435222)
               and not C_SpellBook.IsSpellKnown(CRASHING) then
                return
            end
            stacks = MAX
            expiresAt = GetTime() + DURATION
        elseif SPENDERS[spellID] and stacks > 0 then
            -- Unhinged: Bloodthirst/Bloodbath don't consume during Bladestorm
            if UNHINGED_EXEMPT[spellID]
               and C_SpellBook.IsSpellKnown(UNHINGED)
               and GetTime() < bladestormEndsAt then
                return
            end
            stacks = max(0, stacks - 1)
            if stacks == 0 then expiresAt = nil end
        end
    end

    function EllesmereUI.GetWhirlwindStacks()
        if not (C_SpellBook and C_SpellBook.IsSpellKnown(REQUIRED)) then
            return 0, 0
        end
        if expiresAt and GetTime() >= expiresAt then
            stacks, expiresAt = 0, nil
        end
        return stacks, MAX
    end
end

-- Get DH Soul Fragment count (current, max)
-- Vengeance: C_Spell.GetSpellCastCount(228477) — returns a SECRET value
-- in 12.0+.  The caller must handle it via StatusBar or similar.
-- Devourer (hero spec 1480): aura 1225789/1227702 — WHITELISTED, safe to read.
function EllesmereUI.GetSoulFragments()
    local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec)
    if specID == 581 then -- Vengeance
        local cur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
        return cur, 6
    elseif specID == 1480 then -- Devourer (hero spec)
        local aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(1225789)
        if not aura then aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(1227702) end
        local cur = aura and aura.applications or 0
        local max = (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(1247534)) and 35 or 50
        return cur, max
    end
    -- Havoc or unknown spec: no soul fragments
    return 0, 0
end

-- Get Enhancement Shaman Maelstrom Weapon stacks (current, max)
-- Buff spell 344179 — WHITELISTED by Blizzard, safe to read in combat.
-- Base max 5 stacks (10 with Raging Maelstrom talent 384143)
function EllesmereUI.GetMaelstromWeapon()
    local aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(344179)
    local max = 5
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(384143) then
        max = 10
    end
    return (aura and aura.applications or 0), max
end

-- Tip of the Spear and Whirlwind Stacks are now tracked manually via
-- HandleTipOfTheSpear / HandleWhirlwindStacks + UNIT_SPELLCAST_SUCCEEDED.
-- See the manual tracker section above.

EllesmereUI.THEME_PRESETS   = THEME_PRESETS
EllesmereUI.THEME_ORDER     = THEME_ORDER

-- Path strings
EllesmereUI.EXPRESSWAY = EXPRESSWAY
EllesmereUI.MEDIA_PATH = MEDIA_PATH
EllesmereUI.ICONS_PATH = ICONS_PATH

-- Utility functions
EllesmereUI.SolidTex          = SolidTex
EllesmereUI.MakeFont          = MakeFont
EllesmereUI.MakeBorder        = MakeBorder
EllesmereUI.DisablePixelSnap  = DisablePixelSnap
EllesmereUI.RowBg             = RowBg
EllesmereUI.ResetRowCounters  = ResetRowCounters
EllesmereUI.lerp              = lerp
EllesmereUI.MakeDropdownArrow = MakeDropdownArrow
EllesmereUI.RegAccent         = RegAccent

-- Internal references (needed by Widget Factory accent system)
EllesmereUI.DEFAULT_ACCENT_R = DEFAULT_ACCENT_R
EllesmereUI.DEFAULT_ACCENT_G = DEFAULT_ACCENT_G
EllesmereUI.DEFAULT_ACCENT_B = DEFAULT_ACCENT_B
EllesmereUI._ResolveFactionTheme = ResolveFactionTheme
EllesmereUI._playerClass     = playerClass
EllesmereUI._accentElements  = _accentElements
EllesmereUI._widgetRefreshList = _widgetRefreshList
EllesmereUI._rowCounters     = rowCounters

-------------------------------------------------------------------------------
--  Lazy-load stub: ResolveThemeColor
--  Minimal version used by PLAYER_LOGIN before Widgets file initializes.
--  The full version (with animated transitions etc.) replaces this in Widgets.
-------------------------------------------------------------------------------
if not EllesmereUI.ResolveThemeColor then
    EllesmereUI.ResolveThemeColor = function(theme)
        theme = ResolveFactionTheme(theme)
        if theme == "Class Colored" then
            local clr = CLASS_COLOR_MAP[playerClass]
            if clr then return clr.r, clr.g, clr.b end
            return DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B
        elseif theme == "Custom Color" then
            local sa = EllesmereUIDB and EllesmereUIDB.accentColor
            return sa and sa.r or DEFAULT_ACCENT_R, sa and sa.g or DEFAULT_ACCENT_G, sa and sa.b or DEFAULT_ACCENT_B
        else
            local preset = THEME_PRESETS[theme]
            if preset then return preset.r, preset.g, preset.b end
            return DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B
        end
    end
end

-------------------------------------------------------------------------------
--  SharedMedia helpers
--  Append LibSharedMedia-3.0 statusbar textures into a runtime texture table.
--  Signature: AppendSharedMediaTextures(names, order, castBarNames, textures)
--    names        – key → display-name string table
--    order        – ordered array of keys (receives "---" + SM keys appended)
--    castBarNames – optional secondary names table (may be nil)
--    textures     – key → texture-path table
--  Safe to call multiple times; duplicate keys are skipped via the textures
--  table guard.
-------------------------------------------------------------------------------
function EllesmereUI.AppendSharedMediaTextures(names, order, castBarNames, textures)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local smTextures = LSM:HashTable("statusbar")
    if not smTextures then return end

    -- Collect SM texture names not already present, sort alphabetically
    local sorted = {}
    for name in pairs(smTextures) do
        local key = "sm:" .. name
        if not textures[key] then
            sorted[#sorted + 1] = name
        end
    end
    if #sorted == 0 then return end
    table.sort(sorted)

    -- Append separator + entries
    order[#order + 1] = "---"
    for _, name in ipairs(sorted) do
        local key = "sm:" .. name
        textures[key]      = smTextures[name]
        names[key]         = name
        order[#order + 1]  = key
        if castBarNames then
            castBarNames[key] = name
        end
    end
end

-------------------------------------------------------------------------------
--  Append LibSharedMedia-3.0 fonts into a runtime font dropdown table.
--  Signature: AppendSharedMediaFonts(values, order, opts)
--    values  – key → { text, font } table (or key → path when keyByName=true)
--    order   – ordered array of keys
--    opts    – optional { keyByName = true } — use display name as key
--  Safe to call multiple times; duplicate keys are skipped.
-------------------------------------------------------------------------------
function EllesmereUI.AppendSharedMediaFonts(values, order, opts)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local smFonts = LSM:HashTable("font")
    if not smFonts then return end

    local keyByName = opts and opts.keyByName
    local sorted = {}
    for name in pairs(smFonts) do
        local key = keyByName and name or ("smf:" .. name)
        if not values[key] then
            sorted[#sorted + 1] = name
        end
    end
    if #sorted == 0 then return end
    table.sort(sorted)

    order[#order + 1] = "---"
    for _, name in ipairs(sorted) do
        local key = keyByName and name or ("smf:" .. name)
        values[key] = { text = name, font = smFonts[name] }
        order[#order + 1] = key
    end
end

-------------------------------------------------------------------------------
--  Deferred file initialization
--  Heavy UI files (Widgets, Presets, UnlockMode, Options) register their
--  init functions here at load time but don't execute until the panel opens.
--  This cuts startup CPU from ~911KB to ~250KB of parsed Lua.
-------------------------------------------------------------------------------
EllesmereUI._deferredInits = {}
EllesmereUI._deferredLoaded = false

function EllesmereUI:EnsureLoaded()
    if self._deferredLoaded then return end
    self._deferredLoaded = true
    for i, fn in ipairs(self._deferredInits) do
        fn()
        self._deferredInits[i] = nil
    end
end

-------------------------------------------------------------------------------
--  Popup Scale Helper
--  Popups use pixel-perfect base scale * user panel scale so they grow/shrink
--  together with the main panel when the user adjusts the scale slider.
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

local function RefreshPopupScales()
    local s = GetPopupScale()
    for _, entry in ipairs(_popupFrames) do
        if entry.popup then entry.popup:SetScale(s) end
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
local function WirePopupEscape(popup, dimmer)
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            dimmer:Hide()
            if popup._onCancel then popup._onCancel() end
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    -- Release keyboard capture when the popup is dismissed
    dimmer:HookScript("OnHide", function()
        popup:EnableKeyboard(false)
    end)
    dimmer:HookScript("OnShow", function()
        popup:EnableKeyboard(true)
    end)
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

    -- Pixel-perfect scale (match main frame, including user panel scale)
    -- Popups render at default UI scale — no custom scaling needed.
    -- (Dimmer stays at scale 1 so it covers the full screen.)

    -- Background
    local popBg = SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 1)
    popBg:SetAllPoints()

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
    disc:SetFont(EXPRESSWAY, 11, "")
    disc:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a * 0.7)
    disc:SetPoint("TOP", msg, "BOTTOM", 0, -8)
    disc:SetWidth(POPUP_W - 60)
    disc:SetJustifyH("CENTER")
    disc:SetWordWrap(true)
    disc:Hide()
    popup._disclaimer = disc

    -- Button dimensions
    local BTN_W, BTN_H = 135, 29
    local BTN_GAP = 16
    local BTN_Y = 13
    local FADE_DUR = 0.1

    -- Helper: create a styled popup button
    -- Button is sized 2px larger than visual area; bg is inset 1px so the border
    -- texture (which fills the full button) peeks out as a 1px border on all sides.
    local function MakePopupButton(parent, anchorPoint, anchorTo, anchorRef, xOff, yOff, defR, defG, defB, defA, hovR, hovG, hovB, hovA, bDefR, bDefG, bDefB, bDefA, bHovR, bHovG, bHovB, bHovA)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(BTN_W + 2, BTN_H + 2)
        btn:SetPoint(anchorPoint, anchorTo, anchorRef, xOff, yOff)
        btn:SetFrameLevel(parent:GetFrameLevel() + 2)

        -- Border: full-size background texture (peeks out 1px on every side)
        local brd = SolidTex(btn, "BACKGROUND", bDefR, bDefG, bDefB, bDefA)
        brd:SetAllPoints()
        -- Fill: inset by 1px on each side to reveal the border
        local bg = SolidTex(btn, "BORDER", 0.06, 0.08, 0.10, .92)
        bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)

        local lbl = MakeFont(btn, 12, nil, defR, defG, defB)
        lbl:SetAlpha(defA)
        lbl:SetPoint("CENTER")

        local progress, target = 0, 0
        local function Apply(t)
            lbl:SetTextColor(lerp(defR, hovR, t), lerp(defG, hovG, t), lerp(defB, hovB, t), lerp(defA, hovA, t))
            brd:SetColorTexture(lerp(bDefR, bHovR, t), lerp(bDefG, bHovG, t), lerp(bDefB, bHovB, t), lerp(bDefA, bHovA, t))
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
        return btn
    end

    -- Cancel button (left) -- dim white style
    local EG = ELLESMERE_GREEN
    local cancelBtn = MakePopupButton(popup,
        "BOTTOMRIGHT", popup, "BOTTOM", -(BTN_GAP / 2), BTN_Y,
        1, 1, 1, 0.7,                                         -- default text
        1, 1, 1, 0.9,                                         -- hovered text
        1, 1, 1, 0.5,                                         -- default border
        1, 1, 1, 0.6                                           -- hovered border
    )

    -- Confirm button (right) -- green style
    local confirmBtn = MakePopupButton(popup,
        "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, BTN_Y,
        EG.r, EG.g, EG.b, 0.9,        -- default text
        EG.r, EG.g, EG.b, 1,           -- hovered text
        EG.r, EG.g, EG.b, 0.9,         -- default border
        EG.r, EG.g, EG.b, 1            -- hovered border
    )

    popup._cancelBtn  = cancelBtn
    popup._confirmBtn = confirmBtn

    -- Close on dimmer click (only when clicking outside the popup)
    popup:EnableMouse(true)
    dimmer:SetScript("OnMouseDown", function()
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

-- Invalidate cached popup so it rebuilds with current accent colors
local function InvalidateConfirmPopup()
    if confirmPopup then
        confirmPopup._dimmer:Hide()
        confirmPopup:Hide()
        confirmPopup._dimmer:SetParent(nil)
        confirmPopup:SetParent(nil)
        confirmPopup = nil
    end
end
EllesmereUI._InvalidateConfirmPopup = InvalidateConfirmPopup

function EllesmereUI:ShowConfirmPopup(opts)
    -- Force-close any widget tooltip so it doesn't linger behind the popup
    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    local popup = CreateConfirmPopup()

    popup._title:SetText(opts.title or "Confirm")
    popup._msg:SetText(opts.message or "Are you sure?")
    if opts.disclaimer then
        popup._disclaimer:SetText(opts.disclaimer)
        popup._disclaimer:Show()
    else
        popup._disclaimer:SetText("")
        popup._disclaimer:Hide()
    end
    popup._cancelBtn._lbl:SetText(opts.cancelText or "Cancel")
    popup._confirmBtn._lbl:SetText(opts.confirmText or "Confirm")
    -- onDismiss: called on escape/click-outside. Falls back to onCancel if not provided.
    popup._onCancel = opts.onDismiss or opts.onCancel or nil

    -- Reset hover states
    popup._cancelBtn._resetAnim()
    popup._confirmBtn._resetAnim()

    popup._cancelBtn:SetScript("OnClick", function()
        popup._dimmer:Hide()
        if opts.onCancel then opts.onCancel() end
    end)

    -- Macro overlay support (e.g. /logout -- protected actions need a hardware
    -- event routed through InsecureActionButtonTemplate).
    if opts.confirmMacro then
        if not popup._macroOverlay then
            local ov = CreateFrame("Button", "EUIConfirmMacroOverlay", popup._confirmBtn, "InsecureActionButtonTemplate")
            ov:SetAllPoints(popup._confirmBtn)
            ov:SetFrameLevel(popup._confirmBtn:GetFrameLevel() + 5)
            -- Forward hover visuals to the real button underneath
            ov:SetScript("OnEnter", function() popup._confirmBtn:GetScript("OnEnter")(popup._confirmBtn) end)
            ov:SetScript("OnLeave", function() popup._confirmBtn:GetScript("OnLeave")(popup._confirmBtn) end)
            -- PostClick fires after the macro executes; use a stored callback
            -- so we don't accumulate hooks on repeated ShowConfirmPopup calls.
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
        if popup._macroOverlay then popup._macroOverlay:Hide() end
        popup._confirmBtn:SetScript("OnClick", function()
            popup._dimmer:Hide()
            if opts.onConfirm then opts.onConfirm() end
        end)
    end

    popup._dimmer:Show()
end

-------------------------------------------------------------------------------
--  Scrollable Info Popup  (read-only content with custom scroll + close button)
--  Usage:  EllesmereUI:ShowInfoPopup({ title, content, width, height })
--          content is a plain string; the popup handles word-wrap and scrolling.
-------------------------------------------------------------------------------
local infoPopup

local function CreateInfoPopup()
    if infoPopup then return infoPopup end

    local POPUP_W, POPUP_H = 400, 310
    local SCROLL_STEP = 45
    local SMOOTH_SPEED = 12

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

    local popBg = SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 1)
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
    contentFS:SetFont(EXPRESSWAY, 11, "")
    contentFS:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.80)
    contentFS:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0)
    contentFS:SetWidth((POPUP_W - 48) - 10)
    contentFS:SetJustifyH("LEFT")
    contentFS:SetWordWrap(true)
    contentFS:SetSpacing(3)
    popup._contentFS = contentFS

    -- Smooth scroll
    local scrollTarget = 0
    local isSmoothing = false
    local smoothFrame = CreateFrame("Frame")
    smoothFrame:Hide()

    -- Scrollbar track
    local scrollTrack = CreateFrame("Frame", nil, sf)
    scrollTrack:SetWidth(4)
    scrollTrack:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -2, -4)
    scrollTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -2, 4)
    scrollTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
    scrollTrack:Hide()

    local trackBg = SolidTex(scrollTrack, "BACKGROUND", 1, 1, 1, 0.02)
    trackBg:SetAllPoints()

    local scrollThumb = CreateFrame("Button", nil, scrollTrack)
    scrollThumb:SetWidth(4)
    scrollThumb:SetHeight(60)
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
    scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
    scrollThumb:EnableMouse(true)
    scrollThumb:RegisterForDrag("LeftButton")
    scrollThumb:SetScript("OnDragStart", function() end)
    scrollThumb:SetScript("OnDragStop", function() end)

    local thumbTex = SolidTex(scrollThumb, "ARTWORK", 1, 1, 1, 0.27)
    thumbTex:SetAllPoints()

    local isDragging = false
    local dragStartY, dragStartScroll

    local function UpdateThumb()
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
        if maxScroll <= 0 then scrollTrack:Hide(); return end
        scrollTrack:Show()
        local trackH = scrollTrack:GetHeight()
        local visH = sf:GetHeight()
        local ratio = visH / (visH + maxScroll)
        local thumbH = math.max(30, trackH * ratio)
        scrollThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
        scrollThumb:ClearAllPoints()
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
    end

    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = sf:GetVerticalScroll()
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
        scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            sf:SetVerticalScroll(scrollTarget)
            UpdateThumb()
            isSmoothing = false
            smoothFrame:Hide()
            return
        end
        local newScroll = cur + diff * math.min(1, SMOOTH_SPEED * elapsed)
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        sf:SetVerticalScroll(newScroll)
        UpdateThumb()
    end)

    local function SmoothScrollTo(target)
        local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
        scrollTarget = math.max(0, math.min(maxScroll, target))
        if not isSmoothing then
            isSmoothing = true
            smoothFrame:Show()
        end
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = tonumber(self:GetVerticalScrollRange()) or 0
        if maxScroll <= 0 then return end
        local base = isSmoothing and scrollTarget or self:GetVerticalScroll()
        SmoothScrollTo(base - delta * SCROLL_STEP)
    end)
    sf:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

    -- Thumb drag
    local function StopDrag()
        if not isDragging then return end
        isDragging = false
        scrollThumb:SetScript("OnUpdate", nil)
    end

    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isSmoothing = false; smoothFrame:Hide()
        isDragging = true
        local _, cy = GetCursorPosition()
        dragStartY = cy / self:GetEffectiveScale()
        dragStartScroll = sf:GetVerticalScroll()
        self:SetScript("OnUpdate", function(self2)
            if not IsMouseButtonDown("LeftButton") then StopDrag(); return end
            isSmoothing = false; smoothFrame:Hide()
            local _, cy2 = GetCursorPosition()
            cy2 = cy2 / self2:GetEffectiveScale()
            local deltaY = dragStartY - cy2
            local trackH = scrollTrack:GetHeight()
            local maxTravel = trackH - self2:GetHeight()
            if maxTravel <= 0 then return end
            local maxScroll = tonumber(sf:GetVerticalScrollRange()) or 0
            local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + (deltaY / maxTravel) * maxScroll))
            scrollTarget = newScroll
            sf:SetVerticalScroll(newScroll)
            UpdateThumb()
        end)
    end)
    scrollThumb:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then StopDrag() end
    end)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(100, 26)
    closeBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 16)
    closeBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
    EllesmereUI.MakeStyledButton(closeBtn, "Close", 11,
        EllesmereUI.RB_COLOURS, function() dimmer:Hide() end)

    -- Click dimmer to close
    dimmer:SetScript("OnMouseDown", function()
        if not popup:IsMouseOver() then dimmer:Hide() end
    end)

    -- Escape to close
    WirePopupEscape(popup, dimmer)

    -- Reset scroll on hide
    dimmer:HookScript("OnHide", function()
        isSmoothing = false; smoothFrame:Hide()
        scrollTarget = 0
        sf:SetVerticalScroll(0)
    end)

    popup._dimmer = dimmer
    popup._scrollFrame = sf
    popup._scrollChild = sc
    infoPopup = popup
    return popup
end

function EllesmereUI:ShowInfoPopup(opts)
    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    local popup = CreateInfoPopup()

    popup._title:SetText(opts.title or "Information")
    popup._contentFS:SetText(opts.content or "")

    -- Resize scroll child to fit content after a frame
    C_Timer.After(0.01, function()
        local h = popup._contentFS:GetStringHeight() or 100
        popup._scrollChild:SetHeight(h + 10)
    end)

    popup._dimmer:Show()
end

-------------------------------------------------------------------------------
--  Custom Input Popup  (matches EllesmereUI aesthetic, with EditBox)
--  Usage:  EllesmereUI:ShowInputPopup({ title, message, placeholder, confirmText, cancelText, onConfirm, onCancel })
--          onConfirm receives the entered text as its first argument.
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

        local popBg = SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 1)
        popBg:SetAllPoints()

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
        inputFrame:SetSize(INPUT_W + 2, INPUT_H + 2)
        inputFrame:SetPoint("TOP", msg, "BOTTOM", 0, -12)
        inputFrame:SetFrameLevel(popup:GetFrameLevel() + 2)

        local iBrdTex = SolidTex(inputFrame, "BACKGROUND", 1, 1, 1, 0.2)
        iBrdTex:SetAllPoints()
        local iBg = SolidTex(inputFrame, "BORDER", 0.06, 0.08, 0.10, 1)
        iBg:SetPoint("TOPLEFT", 1, -1); iBg:SetPoint("BOTTOMRIGHT", -1, 1)
        popup._iBrdTex = iBrdTex

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
                iBrdTex:SetColorTexture(1, 1, 1, 0.2)
                return
            end
            local t = flashElapsed / FLASH_DUR
            -- Fade from red back to default border
            local r = lerp(0.9, 1, t)
            local g = lerp(0.15, 1, t)
            local b = lerp(0.15, 1, t)
            local a = lerp(0.7, 0.2, t)
            iBrdTex:SetColorTexture(r, g, b, a)
        end)

        popup._flashEmpty = function()
            flashElapsed = 0
            flashing = true
            iBrdTex:SetColorTexture(0.9, 0.15, 0.15, 0.7)
            flashFrame:Show()
            popup._editBox:SetFocus()
        end

        local editBox = CreateFrame("EditBox", nil, inputFrame)
        editBox:SetPoint("TOPLEFT", 12, -1)
        editBox:SetPoint("BOTTOMRIGHT", -12, 1)
        editBox:SetFont(EXPRESSWAY, 11, "")
        editBox:SetTextColor(1, 1, 1, 0.9)
        editBox:SetAutoFocus(false)
        editBox:SetMaxLetters(30)

        local placeholder = editBox:CreateFontString(nil, "ARTWORK")
        placeholder:SetFont(EXPRESSWAY, 11, "")
        placeholder:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a * 0.5)
        placeholder:SetPoint("LEFT", editBox, "LEFT", 0, 0)
        popup._placeholder = placeholder

        editBox:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then placeholder:Show() else placeholder:Hide() end
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

        -- Optional extra button (shown above the input field, e.g. "Add Current Zone")
        local EXTRA_BTN_W, EXTRA_BTN_H = 160, 28
        local extraBtn = CreateFrame("Button", nil, popup)
        extraBtn:SetSize(EXTRA_BTN_W, EXTRA_BTN_H)
        extraBtn:SetPoint("TOP", inputFrame, "BOTTOM", 0, -6)
        extraBtn:SetFrameLevel(popup:GetFrameLevel() + 2)
        local extraBrd = SolidTex(extraBtn, "BACKGROUND", 1, 1, 1, 0.25)
        extraBrd:SetAllPoints()
        local extraBg = SolidTex(extraBtn, "BORDER", 0.06, 0.08, 0.10, 0.92)
        extraBg:SetPoint("TOPLEFT", 1, -1); extraBg:SetPoint("BOTTOMRIGHT", -1, 1)
        local extraLbl = MakeFont(extraBtn, 12, nil, 1, 1, 1)
        extraLbl:SetAlpha(0.6)
        extraLbl:SetPoint("CENTER")
        do
            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function Apply(t)
                extraLbl:SetTextColor(1, 1, 1, lerp(0.6, 0.9, t))
                extraBrd:SetColorTexture(1, 1, 1, lerp(0.25, 0.45, t))
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

        local BTN_W, BTN_H = 150, 32
        local BTN_GAP = 16
        local BTN_Y = 18
        local FADE_DUR = 0.1

        local function MakePopupButton(parent, anchorPoint, anchorTo, anchorRef, xOff, yOff, defR, defG, defB, defA, hovR, hovG, hovB, hovA, bDefR, bDefG, bDefB, bDefA, bHovR, bHovG, bHovB, bHovA)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(BTN_W + 2, BTN_H + 2)
            btn:SetPoint(anchorPoint, anchorTo, anchorRef, xOff, yOff)
            btn:SetFrameLevel(parent:GetFrameLevel() + 2)
            local brd = SolidTex(btn, "BACKGROUND", bDefR, bDefG, bDefB, bDefA)
            brd:SetAllPoints()
            local bg = SolidTex(btn, "BORDER", 0.06, 0.08, 0.10, .92)
            bg:SetPoint("TOPLEFT", 1, -1); bg:SetPoint("BOTTOMRIGHT", -1, 1)
            local lbl = MakeFont(btn, 12, nil, defR, defG, defB)
            lbl:SetAlpha(defA)
            lbl:SetPoint("CENTER")
            local progress, target = 0, 0
            local function Apply(t)
                lbl:SetTextColor(lerp(defR, hovR, t), lerp(defG, hovG, t), lerp(defB, hovB, t), lerp(defA, hovA, t))
                brd:SetColorTexture(lerp(bDefR, bHovR, t), lerp(bDefG, bHovG, t), lerp(bDefB, bHovB, t), lerp(bDefA, bHovA, t))
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
            return btn
        end

        local EG = ELLESMERE_GREEN
        local cancelBtn = MakePopupButton(popup,
            "BOTTOMRIGHT", popup, "BOTTOM", -(BTN_GAP / 2), BTN_Y,
            1, 1, 1, 0.7,   1, 1, 1, 0.9,
            1, 1, 1, 0.5,   1, 1, 1, 0.6
        )
        local confirmBtn = MakePopupButton(popup,
            "BOTTOMLEFT", popup, "BOTTOM", BTN_GAP / 2, BTN_Y,
            EG.r, EG.g, EG.b, 0.9,   EG.r, EG.g, EG.b, 1,
            EG.r, EG.g, EG.b, 0.9,   EG.r, EG.g, EG.b, 1
        )

        popup._cancelBtn  = cancelBtn
        popup._confirmBtn = confirmBtn

        popup:EnableMouse(true)
        dimmer:SetScript("OnMouseDown", function()
            if not popup:IsMouseOver() then
                dimmer:Hide()
                if popup._onCancel then popup._onCancel() end
            end
        end)

        WirePopupEscape(popup, dimmer)

        editBox:SetScript("OnEnterPressed", function()
            local txt = editBox:GetText()
            if txt and txt ~= "" then
                dimmer:Hide()
                if popup._onConfirmCb then popup._onConfirmCb(txt) end
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

    popup._title:SetText(opts.title or "Enter Name")
    popup._msg:SetText(opts.message or "")
    popup._placeholder:SetText(opts.placeholder or "Enter name...")
    popup._cancelBtn._lbl:SetText(opts.cancelText or "Cancel")
    popup._confirmBtn._lbl:SetText(opts.confirmText or "Save")
    popup._onCancel = opts.onDismiss or opts.onCancel or nil
    popup._onConfirmCb = opts.onConfirm or nil

    popup._editBox:SetMaxLetters(opts.maxLetters or 30)
    local initText = opts.initialText or ""
    popup._editBox:SetText(initText)
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
        popup._warnLabel:SetText(opts.warning)
        popup._warnLabel:Show()
        warnH = popup._warnLabel:GetStringHeight() + 10
    else
        popup._warnLabel:SetText("")
        popup._warnLabel:Hide()
    end

    popup:SetHeight(194 + extraH + warnH)

    popup._cancelBtn:SetScript("OnClick", function()
        popup._dimmer:Hide()
        if opts.onCancel then opts.onCancel() end
    end)
    popup._confirmBtn:SetScript("OnClick", function()
        local txt = popup._editBox:GetText()
        if txt and txt ~= "" then
            popup._dimmer:Hide()
            if opts.onConfirm then opts.onConfirm(txt) end
        else
            popup._flashEmpty()
        end
    end)

    popup._dimmer:Show()
    C_Timer.After(0.05, function() popup._editBox:SetFocus() end)
end

-------------------------------------------------------------------------------
--  Tab helpers  (forward-declared, defined before CreateMainFrame uses them)
-------------------------------------------------------------------------------
local ClearTabs, CreateTabButton, BuildTabs, UpdateTabHighlight
local UpdateSidebarHighlight, ClearContent

-------------------------------------------------------------------------------
--  Build Main Frame
-------------------------------------------------------------------------------
local function CreateMainFrame()
    if mainFrame then return mainFrame end

    -----------------------------------------------------------------------
    --  Root frame + scaling
    -----------------------------------------------------------------------
    mainFrame = CreateFrame("Frame", "EllesmereUIFrame", UIParent)
    EllesmereUI._mainFrame = mainFrame
    mainFrame:SetSize(BG_WIDTH, BG_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetFrameLevel(100)
    mainFrame:Hide()
    mainFrame:EnableMouse(false)
    mainFrame:SetMovable(true)
    mainFrame:SetScript("OnShow", function()
        -- Recalculate pixel-perfect base scale every time the panel opens
        -- so resolution or UIParent scale changes are picked up immediately
        local physW2 = (GetPhysicalScreenSize())
        local baseScale2 = GetScreenWidth() / physW2
        local userScale2 = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
        mainFrame:SetScale(baseScale2 * userScale2)
        -- Re-sync PanelPP mult for the (possibly new) scale
        if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end
        for _, fn in ipairs(_onShowCallbacks) do fn() end
    end)
    mainFrame:SetScript("OnHide", function()
        for _, fn in ipairs(_onHideCallbacks) do fn() end
    end)

    -- Pixel-perfect scale: make 1 WoW unit = 1 screen pixel
    local physW = (GetPhysicalScreenSize())
    local baseScale = GetScreenWidth() / physW
    local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
    mainFrame:SetScale(baseScale * userScale)
    -- Initialize PanelPP mult for the saved user scale
    if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end

    table.insert(UISpecialFrames, "EllesmereUIFrame")

    -----------------------------------------------------------------------
    --  Background texture  (dual-layer crossfade for smooth transitions)
    -----------------------------------------------------------------------
    bgFrame = CreateFrame("Frame", nil, mainFrame)
    bgFrame:SetAllPoints(mainFrame)
    bgFrame:SetFrameLevel(mainFrame:GetFrameLevel())
    bgFrame:EnableMouse(false)
    bgFrame:SetAlpha(1)  -- mainFrame controls overall window opacity

    -- Permanent base background: backdrop shadow (always visible behind everything)
    local bgBase = bgFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgBase:SetTexture(MEDIA_PATH .. "backgrounds\\eui-bg.png")
    bgBase:SetAllPoints()
    bgBase:SetAlpha(1)

    -- Two background layers for crossfading (A = current, B = incoming)
    -- Only the active layer has a texture set; the idle layer is cleared
    -- after each transition to free GPU memory.
    local bgA = bgFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
    bgA:SetAllPoints()
    bgA:SetAlpha(1)

    local bgB = bgFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgB:SetAllPoints()
    bgB:SetAlpha(0)

    -- Track which layer is "front" (the one fading in)
    local bgFront, bgBack = bgA, bgB
    local bgFadeProgress = 1  -- 1 = fully transitioned (front is fully visible)
    local BG_FADE_DURATION = 0.5

    -- Apply accent hue to background via desaturate + vertex color tint
    -- The base images are teal-themed; desaturating removes the hue,
    -- then vertex color re-tints to the user's chosen accent.
    -- Horde and Alliance have their own dedicated background images
    -- and do NOT get desaturated/tinted -- they're used as-is.
    local function ApplyBgTintToLayer(layer, theme, r, g, b)
        if theme == "EllesmereUI" or theme == "Horde" or theme == "Alliance"
           or theme == "Midnight" or theme == "Dark" then
            -- These themes use their native bg as-is (or no bg for Dark)
            layer:SetDesaturated(false)
            layer:SetVertexColor(1, 1, 1, 1)
        else
            local minBright = 1.10
            local maxBright = 1.60
            local floor     = 0.08
            local lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            local darkFactor = 1 - lum
            local bright = minBright + darkFactor * (maxBright - minBright)
            local fr = math.min(floor + r * bright, 1)
            local fg = math.min(floor + g * bright, 1)
            local fb = math.min(floor + b * bright, 1)
            layer:SetDesaturated(true)
            layer:SetVertexColor(fr, fg, fb, 1)
        end
    end

    -- Background crossfade ticker: old stays solid, new fades in on top.
    -- Uses the same ease-in-out curve as the accent transition so both
    -- animations track visually and the final-frame alpha jump is minimal.
    local bgFadeTicker = CreateFrame("Frame", nil, bgFrame)
    bgFadeTicker:Hide()
    bgFadeTicker:SetScript("OnUpdate", function(self, elapsed)
        bgFadeProgress = bgFadeProgress + elapsed / BG_FADE_DURATION
        if bgFadeProgress >= 1 then
            bgFadeProgress = 1
            bgFront:SetAlpha(1)
            -- bgBack stays solid behind bgFront (completely occluded, zero
            -- visual cost).  Never clear it here -- doing so risks a single-
            -- frame flash.  The next ApplyThemeBG replaces its texture anyway.
            self:Hide()
        else
            -- Ease-in-out: slow start, fast middle, slow end
            local t = bgFadeProgress
            t = t < 0.5 and (2 * t * t) or (1 - (-2 * t + 2) * (-2 * t + 2) / 2)
            bgBack:SetAlpha(1)
            bgFront:SetAlpha(t)
        end
    end)

    --- Apply the full theme: crossfade to new background image + tint
    local function ApplyThemeBG(theme, r, g, b)
        theme = ResolveFactionTheme(theme)
        local file = THEME_BG_FILES[theme] or THEME_BG_FILES["EllesmereUI"]
        local newPath = MEDIA_PATH .. file

        -- Swap roles: old front becomes back, new incoming becomes front
        bgBack, bgFront = bgFront, bgBack

        -- Set up the new front layer with the target texture + tint, on top.
        -- This also serves as the lazy cleanup for the previous transition's
        -- idle layer -- SetTexture here replaces whatever was left over.
        bgFront:SetTexture(newPath)
        ApplyBgTintToLayer(bgFront, theme, r, g, b)
        bgFront:SetDrawLayer("BACKGROUND", 1)
        bgFront:SetAlpha(0)

        -- Old layer stays fully solid underneath
        bgBack:SetDrawLayer("BACKGROUND", 0)
        bgBack:SetAlpha(1)

        -- Start crossfade
        bgFadeProgress = 0
        bgFadeTicker:Show()
    end

    -- For tint-only updates (Custom Color picker dragging), update the front layer directly
    local function ApplyBgTint(r, g, b)
        local theme = ResolveFactionTheme((EllesmereUIDB or {}).activeTheme or "EllesmereUI")
        ApplyBgTintToLayer(bgFront, theme, r, g, b)
    end

    -- Apply initial theme at creation (no crossfade, just set correct texture + tint)
    local _initTheme = ResolveFactionTheme((EllesmereUIDB or {}).activeTheme or "EllesmereUI")
    local _initFile = THEME_BG_FILES[_initTheme] or THEME_BG_FILES["EllesmereUI"]
    bgA:SetTexture(MEDIA_PATH .. _initFile)
    ApplyBgTintToLayer(bgA, _initTheme, ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b)
    EllesmereUI._bgTexture = bgA
    EllesmereUI._applyBgTint = ApplyBgTint
    EllesmereUI._applyThemeBG = ApplyThemeBG

    -----------------------------------------------------------------------
    --  Click area  (1300x946, centred)
    -----------------------------------------------------------------------
    clickArea = CreateFrame("Frame", "EllesmereUIClickArea", mainFrame)
    clickArea:SetSize(CLICK_W, CLICK_H)
    clickArea:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
    clickArea:SetFrameLevel(mainFrame:GetFrameLevel() + 1)
    clickArea:EnableMouse(true)
    clickArea:SetMovable(true)
    clickArea:RegisterForDrag("LeftButton")
    -- No SetClampedToScreen -- the whole window (bg + content) moves as one
    -- and can be dragged freely off any edge.
    clickArea:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
    clickArea:SetScript("OnDragStop",  function() mainFrame:StopMovingOrSizing() end)

    -----------------------------------------------------------------------
    --  Close button  (invisible hit area over background X graphic)
    -----------------------------------------------------------------------
    local closeBtn = CreateFrame("Button", nil, clickArea)
    closeBtn:SetSize(38, 38)
    closeBtn:SetPoint("TOPRIGHT", clickArea, "TOPRIGHT", -17, -11)
    closeBtn:SetFrameLevel(clickArea:GetFrameLevel() + 20)
    closeBtn:SetScript("OnClick", function() EllesmereUI:Hide() end)

    -----------------------------------------------------------------------
    --  Sidebar
    -----------------------------------------------------------------------
    sidebar = CreateFrame("Frame", nil, clickArea)
    sidebar:SetSize(SIDEBAR_W, CLICK_H)
    sidebar:SetPoint("TOPLEFT", clickArea, "TOPLEFT", 0, 0)
    sidebar:SetFrameLevel(clickArea:GetFrameLevel() + 2)

    -- Nav buttons -- start below the logo area with proper spacing
    local NAV_TOP     = -128   -- distance from sidebar top to first nav item
    local NAV_ROW_H   = 50    -- height per nav row (more generous spacing)
    local NAV_ICON_W  = 52    -- exact pixel width
    local NAV_ICON_H  = 37    -- exact pixel height
    local NAV_LEFT    = 20    -- left padding for icon
    _sidebarNavRowH = NAV_ROW_H
    local NAV_TXT_GAP = 14    -- gap between icon and label

    -- Helper: create a 1px horizontal glow line on a sidebar button (TOP or BOTTOM edge)
    local function MakeNavEdgeLine(btn, edge)
        local g = btn:CreateTexture(nil, "BORDER")
        g:SetHeight(1)
        PanelPP.Point(g, edge .. "LEFT", btn, edge .. "LEFT", 0, 0)
        PanelPP.Point(g, edge .. "RIGHT", btn, edge .. "RIGHT", 0, 0)
        g:SetColorTexture(0.7, 0.7, 0.7, 1)
        g:SetGradient("HORIZONTAL", CreateColor(0.7, 0.7, 0.7, 0.5), CreateColor(0.7, 0.7, 0.7, 0))
        g:Hide()
        return g
    end

    -- Helper: create a horizontal gradient glow texture on a sidebar button
    local function MakeNavGradient(btn, r, g, b, startA)
        local tex = btn:CreateTexture(nil, "BACKGROUND")
        tex:SetSize(SIDEBAR_W, NAV_ROW_H)
        tex:SetPoint("LEFT", btn, "LEFT", 0, 0)
        tex:SetColorTexture(r, g, b, 1)
        tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, startA), CreateColor(r, g, b, 0))
        tex:Hide()
        return tex
    end

    -- Helper: attach the shared decoration set to a sidebar nav button
    -- (active indicator, selection glow, top/bottom edge lines, hover glow, hover indicator)
    local function DecorateSidebarButton(btn)
        local EG = ELLESMERE_GREEN
        btn._indicator = SolidTex(btn, "ARTWORK", EG.r, EG.g, EG.b, 1)
        btn._indicator:SetSize(3, NAV_ROW_H)
        btn._indicator:SetPoint("LEFT", btn, "LEFT", -1, 0)
        btn._indicator:Hide()
        RegAccent({ type="solid", obj=btn._indicator, a=1 })

        btn._glow    = MakeNavGradient(btn, EG.r, EG.g, EG.b, 0.15)
        RegAccent({ type="gradient", obj=btn._glow, startA=0.15 })
        btn._glowTop = MakeNavEdgeLine(btn, "TOP")
        btn._glowBot = MakeNavEdgeLine(btn, "BOTTOM")

        local hR, hG, hB = 0.85, 0.95, 0.90
        btn._hoverGlow = MakeNavGradient(btn, hR, hG, hB, 0.03)
        btn._hoverIndicator = SolidTex(btn, "ARTWORK", hR, hG, hB, 0.25)
        btn._hoverIndicator:SetSize(3, NAV_ROW_H)
        btn._hoverIndicator:SetPoint("LEFT", btn, "LEFT", -1, 0)
        btn._hoverIndicator:Hide()
    end

    -------------------------------------------------------------------
    --  Unlock Mode button  (always top, not a module — just triggers unlock)
    -------------------------------------------------------------------
    do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, NAV_ROW_H)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, NAV_TOP)
        btn:SetFrameLevel(sidebar:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        -- Glow layer (behind icon): tinted version of the -on texture
        local iconGlow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        iconGlow:SetTexture(ICONS_PATH .. "sidebar\\unlockmode-ig-on.png")
        iconGlow:SetSize(NAV_ICON_W, NAV_ICON_H)
        iconGlow:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        iconGlow:SetDesaturated(true)
        iconGlow:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
        iconGlow:Hide()
        btn._iconGlow = iconGlow
        RegAccent({ type="vertex", obj=iconGlow })

        -- Icon layer (on top of glow): always the white off texture
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(ICONS_PATH .. "sidebar\\unlockmode-ig.png")
        icon:SetSize(NAV_ICON_W, NAV_ICON_H)
        icon:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        btn._icon    = icon
        btn._iconOn  = ICONS_PATH .. "sidebar\\unlockmode-ig-on.png"
        btn._iconOff = ICONS_PATH .. "sidebar\\unlockmode-ig.png"

        local label = MakeFont(btn, 15, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText("Unlock Mode")
        btn._label = label

        -- Always "loaded" appearance
        label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        icon:SetDesaturated(false)
        icon:SetAlpha(NAV_ENABLED_ICON_A)

        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            hlTex:SetAlpha(0.06)
            self._hoverGlow:Show()
            self._hoverIndicator:Show()
            self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
        end)
        btn:SetScript("OnLeave", function(self)
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        end)
        btn:SetScript("OnClick", function()
            if EllesmereUI._openUnlockMode then
                EllesmereUI._unlockReturnModule = activeModule
                EllesmereUI._unlockReturnPage   = activePage
                C_Timer.After(0, EllesmereUI._openUnlockMode)
            end
        end)

        EllesmereUI._unlockSidebarBtn = btn
    end

    -------------------------------------------------------------------
    --  Global Settings button  (always second, not an addon)
    -------------------------------------------------------------------
    local GLOBAL_KEY = "_EUIGlobal"
    do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, NAV_ROW_H)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, NAV_TOP - NAV_ROW_H)
        btn:SetFrameLevel(sidebar:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        -- Glow layer (behind icon): tinted version of the -on texture
        local iconGlow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        iconGlow:SetTexture(ICONS_PATH .. "sidebar\\settings-ig-on-2.png")
        iconGlow:SetSize(NAV_ICON_W, NAV_ICON_H)
        iconGlow:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        iconGlow:SetDesaturated(true)
        iconGlow:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
        iconGlow:Hide()
        btn._iconGlow = iconGlow
        RegAccent({ type="vertex", obj=iconGlow })

        -- Icon layer (on top of glow): always the white off texture
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(ICONS_PATH .. "sidebar\\settings-ig-2.png")
        icon:SetSize(NAV_ICON_W, NAV_ICON_H)
        icon:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        btn._icon    = icon
        btn._iconOn  = ICONS_PATH .. "sidebar\\settings-ig-on-2.png"
        btn._iconOff = ICONS_PATH .. "sidebar\\settings-ig-2.png"

        local label = MakeFont(btn, 15, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText("Global Settings")
        btn._label = label

        -- No download icon for global settings
        local dlIcon = btn:CreateTexture(nil, "ARTWORK")
        dlIcon:SetSize(18, 18)
        dlIcon:SetPoint("RIGHT", btn, "RIGHT", -14, 0)
        dlIcon:Hide()
        btn._dlIcon = dlIcon

        -- Always "loaded" -- global settings is built-in
        label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        icon:SetDesaturated(false)
        icon:SetAlpha(NAV_ENABLED_ICON_A)
        btn._folder = GLOBAL_KEY
        btn._loaded = true

        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            hlTex:SetAlpha(0.06)
            if activeModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if activeModule ~= self._folder then
                self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnClick", function(self)
            if modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        sidebarButtons[GLOBAL_KEY] = btn
    end

    -- Addon offset: first addon starts two rows below (Unlock Mode + Global Settings)
    local ADDON_NAV_TOP = NAV_TOP - NAV_ROW_H * 2
    _sidebarAddonNavTop = ADDON_NAV_TOP

    for i, info in ipairs(ADDON_ROSTER) do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, NAV_ROW_H)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, ADDON_NAV_TOP - (i - 1) * NAV_ROW_H)
        btn:SetFrameLevel(sidebar:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        -- Glow layer (behind icon): tinted version of the -on texture
        local iconGlow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        iconGlow:SetTexture(info.icon_on)
        iconGlow:SetSize(NAV_ICON_W, NAV_ICON_H)
        iconGlow:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        -- Party Mode icon keeps its original colors (multi-color lights);
        -- all other icons are desaturated + accent-tinted.
        if info.folder == "EllesmereUIPartyMode" then
            iconGlow:SetDesaturated(false)
        else
            iconGlow:SetDesaturated(true)
            iconGlow:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
            RegAccent({ type="vertex", obj=iconGlow })
        end
        iconGlow:Hide()
        btn._iconGlow = iconGlow

        -- Icon layer (on top of glow): always the white off texture
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(info.icon_off)
        icon:SetSize(NAV_ICON_W, NAV_ICON_H)
        icon:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        btn._icon    = icon
        btn._iconOn  = info.icon_on
        btn._iconOff = info.icon_off

        -- Label
        local label = MakeFont(btn, 15, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText(info.display)
        btn._label = label

        -- Download icon (shown for uninstalled addons)
        local dlIcon = btn:CreateTexture(nil, "ARTWORK")
        dlIcon:SetSize(18, 18)
        dlIcon:SetPoint("RIGHT", btn, "RIGHT", -14, 0)
        dlIcon:SetTexture(ICONS_PATH .. "eui-download.png")
        dlIcon:SetDesaturated(true)
        dlIcon:SetAlpha(0.6)
        dlIcon:Hide()
        btn._dlIcon = dlIcon

        -- Default to unloaded appearance (refreshed each time panel opens)
        label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
        icon:SetDesaturated(true)
        icon:SetAlpha(NAV_DISABLED_ICON_A)
        btn._folder = info.folder
        btn._loaded = false
        btn._alwaysLoaded = info.alwaysLoaded or false
        btn._comingSoon = info.comingSoon or false

        -- Hover highlight
        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            -- Show tooltip for coming-soon addons
            if self._comingSoon then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Coming soon")
                end
                return
            end
            -- Show tooltip for disabled (not enabled) addons
            if self._notEnabled then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Enable via Blizzard Addons List")
                end
                return
            end
            hlTex:SetAlpha(0.06)
            if activeModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                if self._loaded then
                    self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
                else
                    self._label:SetTextColor(NAV_HOVER_DISABLED_TEXT.r, NAV_HOVER_DISABLED_TEXT.g, NAV_HOVER_DISABLED_TEXT.b, NAV_HOVER_DISABLED_TEXT.a)
                end
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            if self._comingSoon then return end
            if self._notEnabled then return end
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if activeModule ~= self._folder then
                if self._loaded then
                    self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
                else
                    self._label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
                end
            end
        end)
        btn:SetScript("OnClick", function(self)
            if self._comingSoon then return end
            if self._notEnabled then return end
            if self._loaded and modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        sidebarButtons[info.folder] = btn
    end

    -- Class art (decorative, purely visual -- does not affect layout of any other element)
    do
        local artFile = CLASS_ART_MAP[playerClass] or "warrior.png"
        local classArt = sidebar:CreateTexture(nil, "BACKGROUND", nil, -1)
        classArt:SetTexture(ICONS_PATH .. "sidebar\\class-accent\\" .. artFile)
        classArt:SetSize(156, 145)
        classArt:SetPoint("BOTTOM", sidebar, "BOTTOM", 10, 200)
        classArt:SetAlpha(1)
    end

    -- Version text
    local versionText = MakeFont(sidebar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    versionText:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 18, 18)
    versionText:SetText("v" .. (EllesmereUI.VERSION or "1.0"))
    versionText:SetAlpha(0.5)

    ---------------------------------------------------------------------------
    --  Build deferred vertical opacity slider (above versionText in sidebar)
    ---------------------------------------------------------------------------
    do
        local SLIDER_H    = 60      -- total track height (vertical, shorter)
        local THUMB_W     = 14      -- width of thumb
        local THUMB_H     = 8       -- height of thumb (thin horizontal bar)
        local TRACK_W     = 2       -- thin track line
        local MIN_ALPHA   = 0.50
        local MAX_ALPHA   = 0.99
        local DEFAULT_A   = 0.99

        local opacityFrame = CreateFrame("Frame", nil, sidebar)
        opacityFrame:SetSize(THUMB_W + 12, SLIDER_H + 26)
        opacityFrame:SetPoint("BOTTOM", versionText, "TOP", 0, 16)
        opacityFrame:SetFrameLevel(sidebar:GetFrameLevel() + 5)

        -- Track background (thin vertical line)
        local track = opacityFrame:CreateTexture(nil, "BACKGROUND")
        track:SetWidth(TRACK_W)
        track:SetPoint("TOP", opacityFrame, "TOP", 0, -16)
        track:SetPoint("BOTTOM", opacityFrame, "BOTTOM", 0, 0)
        track:SetColorTexture(1, 1, 1, 0.10)

        -- Thumb (sits on top of track, hides the line behind it)
        local thumb = CreateFrame("Frame", nil, opacityFrame)
        thumb:SetSize(THUMB_W, THUMB_H)
        thumb:SetFrameLevel(opacityFrame:GetFrameLevel() + 2)

        -- Thumb texture (ARTWORK layer, above track's BACKGROUND)
        local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
        thumbTex:SetAllPoints()
        thumbTex:SetColorTexture(1, 1, 1, 0.25)

        -- Solid blocker behind thumb to hide the track line
        local thumbBlocker = thumb:CreateTexture(nil, "BORDER")
        thumbBlocker:SetPoint("TOPLEFT", thumbTex, "TOPLEFT", 0, 0)
        thumbBlocker:SetPoint("BOTTOMRIGHT", thumbTex, "BOTTOMRIGHT", 0, 0)
        thumbBlocker:SetColorTexture(DARK_BG.r, DARK_BG.g, DARK_BG.b, 1)

        local function SetOpacity(alpha)
            alpha = math.max(MIN_ALPHA, math.min(MAX_ALPHA, alpha))
            mainFrame:SetAlpha(alpha)
            -- Position thumb (vertical: bottom = 0 / MIN, top = 1 / MAX)
            local frac = (alpha - MIN_ALPHA) / (MAX_ALPHA - MIN_ALPHA)
            local trackH = track:GetHeight()
            if trackH < 1 then trackH = SLIDER_H end
            local yPos = frac * (trackH - THUMB_H)
            thumb:ClearAllPoints()
            thumb:SetPoint("BOTTOM", track, "BOTTOM", 0, yPos)
        end

        -- Dragging (OnUpdate only while active)
        local dragging = false
        thumb:EnableMouse(true)
        thumb:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                dragging = true
                self:SetScript("OnUpdate", function()
                    if not dragging then return end
                    local _, cy = GetCursorPosition()
                    local scale = opacityFrame:GetEffectiveScale()
                    cy = cy / scale
                    local bot = track:GetBottom() or 0
                    local trackH = track:GetHeight()
                    if trackH < 1 then return end
                    local frac = (cy - bot - THUMB_H / 2) / (trackH - THUMB_H)
                    frac = math.max(0, math.min(1, frac))
                    local alpha = MIN_ALPHA + frac * (MAX_ALPHA - MIN_ALPHA)
                    SetOpacity(alpha)
                end)
            end
        end)
        thumb:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                dragging = false
                self:SetScript("OnUpdate", nil)
            end
        end)

        -- Click on track to jump AND begin dragging immediately
        local trackFrame = CreateFrame("Button", nil, opacityFrame)
        trackFrame:SetPoint("TOPLEFT", track, "TOPLEFT", -(THUMB_W / 2), 0)
        trackFrame:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", (THUMB_W / 2), 0)
        trackFrame:SetFrameLevel(opacityFrame:GetFrameLevel())
        trackFrame:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local _, cy = GetCursorPosition()
            local scale = opacityFrame:GetEffectiveScale()
            cy = cy / scale
            local bot = track:GetBottom() or 0
            local trackH = track:GetHeight()
            if trackH < 1 then return end
            local frac = (cy - bot - THUMB_H / 2) / (trackH - THUMB_H)
            frac = math.max(0, math.min(1, frac))
            local alpha = MIN_ALPHA + frac * (MAX_ALPHA - MIN_ALPHA)
            SetOpacity(alpha)
            -- Start dragging via the thumb's handlers
            dragging = true
            thumb:SetScript("OnUpdate", function()
                if not dragging then return end
                local _, cy2 = GetCursorPosition()
                local sc = opacityFrame:GetEffectiveScale()
                cy2 = cy2 / sc
                local b = track:GetBottom() or 0
                local tH = track:GetHeight()
                if tH < 1 then return end
                local f = (cy2 - b - THUMB_H / 2) / (tH - THUMB_H)
                f = math.max(0, math.min(1, f))
                SetOpacity(MIN_ALPHA + f * (MAX_ALPHA - MIN_ALPHA))
            end)
        end)
        trackFrame:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                dragging = false
                thumb:SetScript("OnUpdate", nil)
            end
        end)

        -- Mouse wheel on the whole area
        opacityFrame:EnableMouseWheel(true)
        opacityFrame:SetScript("OnMouseWheel", function(self, delta)
            local cur = mainFrame:GetAlpha()
            SetOpacity(cur + delta * 0.05)
        end)

        -- Initialize after a frame so track has valid height
        C_Timer.After(0, function() SetOpacity(DEFAULT_A) end)
    end

    -- CPU metric keys for the sidebar performance tracker
    local CPU_METRICS = {}
    if Enum and Enum.AddOnProfilerMetric then
        CPU_METRICS = {
            { key = "SessionAvg",   enum = Enum.AddOnProfilerMetric.SessionAverageTime,   label = "Session Avg"   },
            { key = "RecentAvg",    enum = Enum.AddOnProfilerMetric.RecentAverageTime,    label = "Recent Avg"    },
            { key = "EncounterAvg", enum = Enum.AddOnProfilerMetric.EncounterAverageTime, label = "Encounter Avg" },
            { key = "Last",         enum = Enum.AddOnProfilerMetric.LastTime,             label = "Last"          },
            { key = "Peak",         enum = Enum.AddOnProfilerMetric.PeakTime,             label = "Peak"          },
        }
    end

    local function GatherEUICPU()
        local cpuByKey = {}
        for _, m in ipairs(CPU_METRICS) do cpuByKey[m.key] = 0 end
        for _, info in ipairs(ADDON_ROSTER) do
            if IsAddonLoaded(info.folder) then
                if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric then
                    for _, m in ipairs(CPU_METRICS) do
                        cpuByKey[m.key] = cpuByKey[m.key] + (C_AddOnProfiler.GetAddOnMetric(info.folder, m.enum) or 0)
                    end
                end
            end
        end
        return cpuByKey
    end

    -- Resource usage tracker (CPU for all EUI addons)
    -- Only ticks when the options panel is visible (parented to sidebar,
    -- which is a descendant of mainFrame -- hidden frames don't fire OnUpdate)

    local resCpuText = MakeFont(sidebar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    resCpuText:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -20, 18)
    resCpuText:SetJustifyH("RIGHT")
    resCpuText:SetAlpha(0.5)

    local resCpuLabel = MakeFont(sidebar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    resCpuLabel:SetPoint("BOTTOMRIGHT", resCpuText, "TOPRIGHT", 0, 3)
    resCpuLabel:SetJustifyH("RIGHT")
    resCpuLabel:SetAlpha(0.5)
    resCpuLabel:SetText("CPU Usage:")

    local resPerfLabel = MakeFont(sidebar, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    resPerfLabel:SetPoint("BOTTOMRIGHT", resCpuLabel, "TOPRIGHT", 0, 11)
    resPerfLabel:SetJustifyH("RIGHT")
    resPerfLabel:SetAlpha(0.5)
    resPerfLabel:SetText("All EUI Addons")

    local resDivider = sidebar:CreateTexture(nil, "ARTWORK")
    resDivider:SetColorTexture(1, 1, 1, 0.15)
    resDivider:SetHeight(1)
    resDivider:SetPoint("BOTTOMRIGHT", resPerfLabel, "BOTTOMRIGHT", 0, -5)
    resDivider:SetPoint("BOTTOMLEFT", resPerfLabel, "BOTTOMLEFT", 0, -5)

    local RES_UPDATE_INTERVAL = 5
    local UpdateResourceText

    UpdateResourceText = function()
        local cpuByKey = GatherEUICPU()
        local cpuVal = cpuByKey["RecentAvg"] or 0
        if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric then
            local fps = GetFramerate() or 0
            local pct = 0
            if fps > 0 then
                pct = cpuVal / (1000 / fps) * 100
            end
            resCpuText:SetText("|cffffffff" .. string.format("%.3f MS (%.1f%%)", cpuVal, pct) .. "|r")
        else
            resCpuText:SetText("|cffffffffN/A|r")
        end
    end

    local resUpdateFrame = CreateFrame("Frame", nil, sidebar)
    local resTicker
    resUpdateFrame:SetScript("OnShow", function()
        UpdateResourceText()
        if not resTicker then
            resTicker = C_Timer.NewTicker(RES_UPDATE_INTERVAL, UpdateResourceText)
        end
    end)
    resUpdateFrame:SetScript("OnHide", function()
        if resTicker then resTicker:Cancel(); resTicker = nil end
    end)

    -----------------------------------------------------------------------
    --  Right-side content region
    -----------------------------------------------------------------------
    local rightX = SIDEBAR_W
    local rightW = CLICK_W - SIDEBAR_W   -- 1030

    -- Header  (module title + description, sits over the banner artwork)
    headerFrame = CreateFrame("Frame", nil, clickArea)
    headerFrame:SetSize(rightW, HEADER_H)
    headerFrame:SetPoint("TOPLEFT", clickArea, "TOPLEFT", rightX, 0)
    headerFrame:SetFrameLevel(clickArea:GetFrameLevel() + 3)

    local headerTitle = MakeFont(headerFrame, 36, "", 1, 1, 1)
    headerTitle:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", CONTENT_PAD, -35)
    headerFrame._title = headerTitle

    local headerDesc = MakeFont(headerFrame, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    headerDesc:SetPoint("TOPLEFT", headerTitle, "BOTTOMLEFT", 2, -12)
    headerDesc:SetWidth(rightW - CONTENT_PAD * 2)
    headerDesc:SetJustifyH("LEFT")
    headerFrame._desc = headerDesc

    -----------------------------------------------------------------------
    --  Tab bar  (sits below the header, above scrollable content)
    -----------------------------------------------------------------------
    tabBar = CreateFrame("Frame", nil, clickArea)
    tabBar:SetSize(rightW, TAB_BAR_H)
    tabBar:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", -9, 0)
    tabBar:SetFrameLevel(clickArea:GetFrameLevel() + 4)

    tabBar._tabButtons = {}

    -----------------------------------------------------------------------
    --  Content header  (optional non-scrolling region above the scroll area)
    --  Modules call EllesmereUI:SetContentHeader(buildFunc) to populate it.
    --  buildFunc(frame, width) should build UI into frame and return height.
    -----------------------------------------------------------------------
    local contentBaseTop = HEADER_H + TAB_BAR_H
    local contentMaxH    = CLICK_H - contentBaseTop - FOOTER_H

    contentHeaderFrame = CreateFrame("Frame", nil, clickArea)
    PanelPP.Size(contentHeaderFrame, rightW, 1)
    PanelPP.Point(contentHeaderFrame, "TOPLEFT", clickArea, "TOPLEFT", rightX, -contentBaseTop)
    contentHeaderFrame:SetFrameLevel(clickArea:GetFrameLevel() + 4)
    contentHeaderFrame:EnableMouseWheel(true)
    contentHeaderFrame:SetScript("OnMouseWheel", function(_, delta)
        if scrollFrame then scrollFrame:GetScript("OnMouseWheel")(scrollFrame, delta) end
    end)
    contentHeaderFrame:Hide()
    EllesmereUI._contentHeader = contentHeaderFrame
    local contentHeaderH = 0   -- current header height

    -- Subtle background tint (only visible when header is active)
    local contentHeaderBg = contentHeaderFrame:CreateTexture(nil, "BACKGROUND")
    contentHeaderBg:SetColorTexture(0, 0, 0, 0.1)
    PanelPP.DisablePixelSnap(contentHeaderBg)
    contentHeaderBg:SetAllPoints()

    -- 1px divider at the bottom edge of the content header
    local contentHeaderDiv = contentHeaderFrame:CreateTexture(nil, "OVERLAY")
    contentHeaderDiv:SetColorTexture(1, 1, 1, 0.06)
    PanelPP.DisablePixelSnap(contentHeaderDiv)
    PanelPP.Point(contentHeaderDiv, "BOTTOMLEFT", contentHeaderFrame, "BOTTOMLEFT", 0, 0)
    PanelPP.Point(contentHeaderDiv, "BOTTOMRIGHT", contentHeaderFrame, "BOTTOMRIGHT", 0, 0)
    contentHeaderDiv:SetHeight(1)

    local function ApplyContentLayout()
        local wasSuppressed = suppressScrollRangeChanged
        suppressScrollRangeChanged = true

        scrollFrame:ClearAllPoints()
        PanelPP.Point(scrollFrame, "TOPLEFT", clickArea, "TOPLEFT", rightX, -(contentBaseTop + contentHeaderH))
        -- Anchor bottom to footer top so WoW resolves the height from both
        -- edges.  This avoids rounding mismatches between PanelPP.Point
        -- and PanelPP.Height that caused a 1px flicker at the scroll
        -- area's bottom edge when the content header height changed.
        if footerFrame then
            PanelPP.Point(scrollFrame, "BOTTOMRIGHT", footerFrame, "TOPRIGHT", 0, 0)
        else
            local newH = contentMaxH - contentHeaderH
            PanelPP.Height(scrollFrame, newH)
        end

        suppressScrollRangeChanged = wasSuppressed
        UpdateScrollThumb()
    end

    -----------------------------------------------------------------------
    --  Scrollable content area
    -----------------------------------------------------------------------
    scrollFrame = CreateFrame("ScrollFrame", "EllesmereUIScrollFrame", clickArea)
    EllesmereUI._scrollFrame = scrollFrame
    PanelPP.Size(scrollFrame, rightW, contentMaxH)
    PanelPP.Point(scrollFrame, "TOPLEFT", clickArea, "TOPLEFT", rightX, -contentBaseTop)
    scrollFrame:SetFrameLevel(clickArea:GetFrameLevel() + 3)
    scrollFrame:EnableMouseWheel(true)
    -- Clip child rendering to the scroll viewport so off-screen widgets
    -- are skipped by the renderer. Without this, all widgets on a page
    -- render every frame regardless of scroll position.
    scrollFrame:SetClipsChildren(true)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    PanelPP.Size(scrollChild, rightW, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Thin scrollbar  (hidden when content fits)
    local scrollTrack = CreateFrame("Frame", nil, scrollFrame)
    scrollTrack:SetWidth(4)
    scrollTrack:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -12, -4)
    scrollTrack:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -12, 4)
    scrollTrack:SetFrameLevel(scrollFrame:GetFrameLevel() + 1)
    scrollTrack:Hide()

    local trackBg = SolidTex(scrollTrack, "BACKGROUND", 1, 1, 1, 0.02)
    trackBg:SetAllPoints()

    local scrollThumb = CreateFrame("Button", nil, scrollTrack)
    scrollThumb:SetWidth(4)
    scrollThumb:SetHeight(60)
    scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, 0)
    scrollThumb:SetFrameLevel(scrollTrack:GetFrameLevel() + 1)
    scrollThumb:EnableMouse(true)
    -- Register for drag so the thumb captures drag events before clickArea
    scrollThumb:RegisterForDrag("LeftButton")
    scrollThumb:SetScript("OnDragStart", function() end)
    scrollThumb:SetScript("OnDragStop", function() end)

    -- Invisible wider hit area so the scrollbar is easier to grab
    local scrollHitArea = CreateFrame("Button", nil, scrollFrame)
    scrollHitArea:SetWidth(16)
    scrollHitArea:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", -6, -4)
    scrollHitArea:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", -6, 4)
    scrollHitArea:SetFrameLevel(scrollTrack:GetFrameLevel() + 2)
    scrollHitArea:EnableMouse(true)
    scrollHitArea:RegisterForDrag("LeftButton")
    scrollHitArea:SetScript("OnDragStart", function() end)
    scrollHitArea:SetScript("OnDragStop", function() end)

    local thumbTex = SolidTex(scrollThumb, "ARTWORK", 1, 1, 1, 0.27)
    thumbTex:SetAllPoints()

    local SCROLL_STEP = 60
    local SMOOTH_SPEED = 12   -- lerp speed (higher = snappier, 10-15 feels good)
    local isDragging = false
    local dragStartY, dragStartScroll

    -- Smooth scroll state
    scrollTarget = 0
    isSmoothing = false

    local function StopScrollDrag()
        if not isDragging then return end
        isDragging = false
        scrollThumb:SetScript("OnUpdate", nil)
    end

    UpdateScrollThumb = function()
        local maxScroll = tonumber(scrollFrame:GetVerticalScrollRange()) or 0
        if maxScroll <= 0 then
            scrollTrack:Hide()
            return
        end
        scrollTrack:Show()
        local trackH = scrollTrack:GetHeight()
        local visH   = scrollFrame:GetHeight()
        local visibleRatio = visH / (visH + maxScroll)
        local thumbH = math.max(30, trackH * visibleRatio)
        scrollThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(scrollFrame:GetVerticalScroll()) or 0) / maxScroll
        local maxThumbTravel = trackH - thumbH
        scrollThumb:ClearAllPoints()
        scrollThumb:SetPoint("TOP", scrollTrack, "TOP", 0, -(scrollRatio * maxThumbTravel))
    end

    -- Smooth scroll OnUpdate: lerp toward scrollTarget then stop
    smoothFrame = CreateFrame("Frame")
    smoothFrame:Hide()
    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = scrollFrame:GetVerticalScroll()
        local maxScroll = tonumber(scrollFrame:GetVerticalScrollRange()) or 0
        -- Snap max downward so we never try to scroll past a pixel-aligned boundary
        local scale = scrollFrame:GetEffectiveScale()
        maxScroll = math.floor(maxScroll * scale) / scale
        -- Re-clamp target in case scroll range changed
        scrollTarget = math.max(0, math.min(maxScroll, scrollTarget))
        local diff = scrollTarget - cur
        if math.abs(diff) < 0.3 then
            -- Close enough -- snap to target and stop
            scrollFrame:SetVerticalScroll(scrollTarget)
            UpdateScrollThumb()
            isSmoothing = false
            smoothFrame:Hide()
            return
        end
        local newScroll = cur + diff * math.min(1, SMOOTH_SPEED * elapsed)
        -- Clamp to valid range
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        -- Round toward the target so the last few frames approach
        -- monotonically and never overshoot/bounce back at settlement
        if diff > 0 then
            newScroll = math.ceil(newScroll * scale) / scale
        else
            newScroll = math.floor(newScroll * scale) / scale
        end
        -- Re-clamp after rounding (ceil could push past max)
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        scrollFrame:SetVerticalScroll(newScroll)
        UpdateScrollThumb()
    end)

    local function SmoothScrollTo(target)
        local maxScroll = tonumber(scrollFrame:GetVerticalScrollRange()) or 0
        local scale = scrollFrame:GetEffectiveScale()
        -- Snap max downward so target never exceeds a pixel-aligned boundary
        maxScroll = math.floor(maxScroll * scale) / scale
        scrollTarget = math.max(0, math.min(maxScroll, target))
        -- Snap target to pixel boundary so content is pixel-perfect at rest
        scrollTarget = math.floor(scrollTarget * scale + 0.5) / scale
        -- Re-clamp after snapping (rounding could push above max)
        scrollTarget = math.min(scrollTarget, maxScroll)
        if not isSmoothing then
            isSmoothing = true
            smoothFrame:Show()
        end
    end
    EllesmereUI.SmoothScrollTo = SmoothScrollTo

    -- Instant scroll (for drag, page switch, etc.) -- also cancels any active animation
    local function InstantScrollTo(val)
        isSmoothing = false
        smoothFrame:Hide()
        scrollTarget = val
        local scale = scrollFrame:GetEffectiveScale()
        val = math.floor(val * scale + 0.5) / scale
        scrollFrame:SetVerticalScroll(val)
        UpdateScrollThumb()
    end

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = tonumber(self:GetVerticalScrollRange()) or 0
        if maxScroll <= 0 then return end
        -- Accumulate on top of the current target (not current position) for responsive chained scrolls
        local base = isSmoothing and scrollTarget or self:GetVerticalScroll()
        SmoothScrollTo(base - delta * SCROLL_STEP)
    end)
    scrollFrame:SetScript("OnScrollRangeChanged", function()
        if suppressScrollRangeChanged then return end
        UpdateScrollThumb()
    end)

    local function ScrollThumbOnUpdate(self)
        -- Auto-release when mouse button is no longer held
        if not IsMouseButtonDown("LeftButton") then
            StopScrollDrag()
            return
        end
        -- Cancel any smooth animation during drag
        isSmoothing = false
        smoothFrame:Hide()
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / self:GetEffectiveScale()
        local deltaY = dragStartY - cursorY
        local trackH = scrollTrack:GetHeight()
        local maxThumbTravel = trackH - self:GetHeight()
        if maxThumbTravel <= 0 then return end
        local maxScroll = tonumber(scrollFrame:GetVerticalScrollRange()) or 0
        local newScroll = math.max(0, math.min(maxScroll, dragStartScroll + (deltaY / maxThumbTravel) * maxScroll))
        -- Snap to whole pixels to prevent sub-pixel widget jitter
        local scale = scrollFrame:GetEffectiveScale()
        newScroll = math.floor(newScroll * scale + 0.5) / scale
        scrollTarget = newScroll
        scrollFrame:SetVerticalScroll(newScroll)
        UpdateScrollThumb()
    end

    scrollThumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isSmoothing = false
        smoothFrame:Hide()
        isDragging = true
        local _, cursorY = GetCursorPosition()
        dragStartY = cursorY / self:GetEffectiveScale()
        dragStartScroll = scrollFrame:GetVerticalScroll()
        self:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    scrollThumb:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    -- Hit area: click to jump + drag (same as track click but with wider target)
    scrollHitArea:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        -- Cancel any smooth animation
        isSmoothing = false
        smoothFrame:Hide()
        local maxScroll = tonumber(scrollFrame:GetVerticalScrollRange()) or 0
        if maxScroll <= 0 then return end
        -- Jump to cursor position
        local _, cy = GetCursorPosition()
        cy = cy / scrollTrack:GetEffectiveScale()
        local top = scrollTrack:GetTop() or 0
        local trackH = scrollTrack:GetHeight()
        local thumbH = scrollThumb:GetHeight()
        if trackH <= thumbH then return end
        local frac = (top - cy - thumbH / 2) / (trackH - thumbH)
        frac = math.max(0, math.min(1, frac))
        local newScroll = frac * maxScroll
        local scale = scrollFrame:GetEffectiveScale()
        newScroll = math.floor(newScroll * scale + 0.5) / scale
        scrollTarget = newScroll
        scrollFrame:SetVerticalScroll(newScroll)
        UpdateScrollThumb()
        -- Begin dragging via thumb
        isDragging = true
        dragStartY = cy
        dragStartScroll = newScroll
        scrollThumb:SetScript("OnUpdate", ScrollThumbOnUpdate)
    end)
    scrollHitArea:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        StopScrollDrag()
    end)

    contentFrame = scrollChild

    -----------------------------------------------------------------------
    --  Content header API  (non-scrolling region above scroll area)
    -----------------------------------------------------------------------
    local _contentHeaderCache = {}   -- keyed by "module::page"
    local _chStash = CreateFrame("Frame")  -- hidden off-screen stash for cached header children
    _chStash:Hide()

    local function ClearContentHeaderInner()
        local ch = { contentHeaderFrame:GetChildren() }
        for _, c in ipairs(ch) do c:Hide(); c:SetParent(nil) end
        local rg = { contentHeaderFrame:GetRegions() }
        for _, r in ipairs(rg) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then r:Hide(); r:SetParent(nil) end
        end
        contentHeaderFrame:Hide()
        contentHeaderFrame:SetHeight(1)
        contentHeaderH = 0
        ApplyContentLayout()
    end

    -- Save current content header's children/regions into the cache,
    -- reparenting them to a hidden stash so ClearContentHeaderInner
    -- doesn't destroy them when clearing for other pages.
    local function SaveContentHeaderToCache(cacheKey)
        if not contentHeaderFrame:IsShown() then return false end
        local children = { contentHeaderFrame:GetChildren() }
        local regions = {}
        for _, r in ipairs({ contentHeaderFrame:GetRegions() }) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then regions[#regions + 1] = r end
        end
        if #children == 0 and #regions == 0 then return false end
        -- Move children and regions to stash so ClearContentHeaderInner can't touch them
        for _, c in ipairs(children) do c:Hide(); c:SetParent(_chStash) end
        for _, r in ipairs(regions) do r:Hide(); r:SetParent(_chStash) end
        _contentHeaderCache[cacheKey] = {
            children = children,
            regions  = regions,
            height   = contentHeaderH,
        }
        contentHeaderFrame:Hide()
        contentHeaderFrame:SetHeight(1)
        contentHeaderH = 0
        ApplyContentLayout()
        return true
    end

    -- Restore a previously saved content header from cache.
    local function RestoreContentHeaderFromCache(cacheKey)
        local entry = _contentHeaderCache[cacheKey]
        if not entry then return false end
        -- Hide any current header children first (without orphaning)
        local ch = { contentHeaderFrame:GetChildren() }
        for _, c in ipairs(ch) do c:Hide() end
        local rg = { contentHeaderFrame:GetRegions() }
        for _, r in ipairs(rg) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then r:Hide() end
        end
        -- Reparent cached children and regions back to contentHeaderFrame and show
        for _, c in ipairs(entry.children) do c:SetParent(contentHeaderFrame); c:Show() end
        for _, r in ipairs(entry.regions) do r:SetParent(contentHeaderFrame); r:Show() end
        contentHeaderFrame:Show()
        contentHeaderH = entry.height
        PanelPP.Height(contentHeaderFrame, entry.height)
        ApplyContentLayout()
        return true
    end

    local function InvalidateContentHeaderCache()
        for key, entry in pairs(_contentHeaderCache) do
            for _, c in ipairs(entry.children) do c:Hide(); c:SetParent(nil) end
            for _, r in ipairs(entry.regions) do r:Hide(); r:SetParent(nil) end
            _contentHeaderCache[key] = nil
        end
    end

    function EllesmereUI:SetContentHeader(buildFunc)
        ClearContentHeaderInner()
        contentHeaderFrame:Show()
        local h = buildFunc(contentHeaderFrame, rightW) or 0
        contentHeaderH = h
        PanelPP.Height(contentHeaderFrame, h)
        ApplyContentLayout()
    end

    function EllesmereUI:UpdateContentHeaderHeight(h)
        if not contentHeaderFrame:IsShown() then return end
        local oldActualH = contentHeaderFrame:GetHeight()
        -- Save scroll state BEFORE ApplyContentLayout, which may clobber it
        -- if WoW returns a stale scroll range after the resize.
        local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll() or 0
        local savedTarget = scrollTarget
        contentHeaderH = h
        PanelPP.Height(contentHeaderFrame, h)
        -- Use the ACTUAL height change after PixelUtil snapping, not the
        -- raw requested delta.  PixelUtil rounds to physical pixels at the
        -- frame's effective scale, so the real change may differ from h-oldH
        -- by a sub-pixel amount -- that mismatch caused a 1px content shift.
        local newActualH = contentHeaderFrame:GetHeight()
        local delta = newActualH - oldActualH
        ApplyContentLayout()
        -- Compensate: the scroll frame moved down by |delta| px, so scroll
        -- the content by the same amount to keep the viewport stable.
        if delta ~= 0 and scrollFrame then
            local adjusted = math.max(0, savedScroll + delta)
            scrollFrame:SetVerticalScroll(adjusted)
            if isSmoothing then
                scrollTarget = math.max(0, savedTarget + delta)
            else
                scrollTarget = adjusted
            end
            UpdateScrollThumb()
        end
    end

    -- Silent variant: resizes header without scroll compensation.
    -- Use when the height change is cosmetic (e.g. buff icons toggled)
    -- and the user shouldn't experience any scroll jump.
    function EllesmereUI:SetContentHeaderHeightSilent(h)
        if not contentHeaderFrame:IsShown() then return end
        contentHeaderH = h
        PanelPP.Height(contentHeaderFrame, h)
        ApplyContentLayout()
    end

    function EllesmereUI:ClearContentHeader()
        ClearContentHeaderInner()
    end

    -- Lightweight hide: hides content header without orphaning children.
    -- Used when content header has already been saved to cache.
    function EllesmereUI:HideContentHeader()
        local ch = { contentHeaderFrame:GetChildren() }
        for _, c in ipairs(ch) do c:Hide() end
        local rg = { contentHeaderFrame:GetRegions() }
        for _, r in ipairs(rg) do
            if r ~= contentHeaderBg and r ~= contentHeaderDiv then r:Hide() end
        end
        contentHeaderFrame:Hide()
        contentHeaderFrame:SetHeight(1)
        contentHeaderH = 0
        ApplyContentLayout()
    end

    -- Expose cache functions for SelectPage (outside CreateMainFrame scope)
    function EllesmereUI:SaveContentHeaderToCache(cacheKey)
        return SaveContentHeaderToCache(cacheKey)
    end
    function EllesmereUI:RestoreContentHeaderFromCache(cacheKey)
        return RestoreContentHeaderFromCache(cacheKey)
    end
    function EllesmereUI:InvalidateContentHeaderCache()
        InvalidateContentHeaderCache()
    end

    -----------------------------------------------------------------------
    --  Footer  (Reset to Defaults + Reload UI | Done)
    -----------------------------------------------------------------------
    footerFrame = CreateFrame("Frame", nil, clickArea)
    PanelPP.Size(footerFrame, rightW, FOOTER_H)
    PanelPP.Point(footerFrame, "BOTTOMLEFT", clickArea, "BOTTOMLEFT", rightX, 0)
    footerFrame:SetFrameLevel(clickArea:GetFrameLevel() + 5)

    -----------------------------------------------------------------------
    --  Footer button hover colours  (tweak these to adjust fade targets)
    -----------------------------------------------------------------------
    -- Reset to Defaults / Reload UI  (white, muted)
    local RS_TEXT_R,   RS_TEXT_G,   RS_TEXT_B,   RS_TEXT_A   = 1, 1, 1, .5
    local RS_TEXT_HR,  RS_TEXT_HG,  RS_TEXT_HB,  RS_TEXT_HA  = 1, 1, 1, .7
    local RS_BRD_R,   RS_BRD_G,   RS_BRD_B,   RS_BRD_A     = 1, 1, 1, .4
    local RS_BRD_HR,  RS_BRD_HG,  RS_BRD_HB,  RS_BRD_HA   = 1, 1, 1, .6

    -- Helper: build a footer button with fade hover
    local function MakeFooterBtn(parent, w, h, anchorPoint, anchorTo, anchorRel, ax, ay,
                                  textR, textG, textB, textA, textHR, textHG, textHB, textHA,
                                  brdR, brdG, brdB, brdA, brdHR, brdHG, brdHB, brdHA,
                                  label, onClick)
        local btn = CreateFrame("Button", nil, parent)
        PanelPP.Size(btn, w, h)
        PanelPP.Point(btn, anchorPoint, anchorTo, anchorRel, ax, ay)
        btn:SetFrameLevel(parent:GetFrameLevel() + 1)
        local brd = MakeBorder(btn, brdR, brdG, brdB, brdA, PanelPP)
        local bg = SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, .92)
        bg:SetAllPoints()
        local lbl = MakeFont(btn, 13, nil, textR, textG, textB)
        lbl:SetAlpha(textA); lbl:SetPoint("CENTER"); lbl:SetText(label)
        do
            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function Apply(t)
                lbl:SetTextColor(lerp(textR, textHR, t), lerp(textG, textHG, t), lerp(textB, textHB, t), lerp(textA, textHA, t))
                brd:SetColor(lerp(brdR, brdHR, t), lerp(brdG, brdHG, t), lerp(brdB, brdHB, t), lerp(brdA, brdHA, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / FADE_DUR)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target; self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
            btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
        end
        btn:SetScript("OnClick", function() if onClick then onClick() end end)
        return btn
    end

    local FOOTER_BTN_W, FOOTER_BTN_H = 170, 36
    local FOOTER_BTN_GAP = 20   -- gap between Reset and Reload
    local DONE_BTN_W = 145      -- Done button width
    local FOOTER_PAD = 24       -- symmetric inset from left/right edges
    local FOOTER_Y   = 24       -- vertical offset from bottom

    -- Reset to Defaults  (left side, FOOTER_PAD from left edge)
    local resetBtn = MakeFooterBtn(footerFrame, FOOTER_BTN_W, FOOTER_BTN_H,
        "BOTTOMLEFT", footerFrame, "BOTTOMLEFT", FOOTER_PAD, FOOTER_Y,
        RS_TEXT_R, RS_TEXT_G, RS_TEXT_B, RS_TEXT_A, RS_TEXT_HR, RS_TEXT_HG, RS_TEXT_HB, RS_TEXT_HA,
        RS_BRD_R, RS_BRD_G, RS_BRD_B, RS_BRD_A, RS_BRD_HR, RS_BRD_HG, RS_BRD_HB, RS_BRD_HA,
        "Reset to Defaults", function()
            if not activeModule or not modules[activeModule] or not modules[activeModule].onReset then return end
            local config = modules[activeModule]
            local addonTitle = config.title or activeModule
            local msg = "Are you sure you want to reset all " .. addonTitle .. " settings to their defaults? This will reload your UI."
            local disclaimer
            if activeModule == (EllesmereUI.GLOBAL_KEY or "_EUIGlobal") then
                disclaimer = "This will not reset addon-specific Quick Setup."
            end
            EllesmereUI:ShowConfirmPopup({
                title       = "Reset " .. addonTitle,
                message     = msg,
                disclaimer  = disclaimer,
                confirmText = "Reset & Reload",
                cancelText  = "Cancel",
                onConfirm   = function()
                    config.onReset()
                    ReloadUI()
                end,
            })
        end)

    -- Reload UI  (next to Reset, 40px gap, same white/muted style)
    MakeFooterBtn(footerFrame, FOOTER_BTN_W, FOOTER_BTN_H,
        "BOTTOMLEFT", resetBtn, "BOTTOMRIGHT", FOOTER_BTN_GAP, 0,
        RS_TEXT_R, RS_TEXT_G, RS_TEXT_B, RS_TEXT_A, RS_TEXT_HR, RS_TEXT_HG, RS_TEXT_HB, RS_TEXT_HA,
        RS_BRD_R, RS_BRD_G, RS_BRD_B, RS_BRD_A, RS_BRD_HR, RS_BRD_HG, RS_BRD_HB, RS_BRD_HA,
        "Reload UI", function() ReloadUI() end)

    -- Social icons  (to the left of Done button)
    do
        local SOCIAL_SIZE = 40
        local SOCIAL_GAP  = 12
        local SOCIAL_ALPHA = 0.35
        local SOCIAL_HOVER = 0.70
        local SOCIAL_FADE  = 0.1

        -- Reusable link popup (created once, shared by all social icons)
        local linkPopup, linkBackdrop
        local function HideLinkPopup()
            if linkPopup then linkPopup:Hide() end
            if linkBackdrop then linkBackdrop:Hide() end
        end
        local function ShowLinkPopup(url, anchorBtn)
            if not linkPopup then
                linkBackdrop = CreateFrame("Button", nil, UIParent)
                linkBackdrop:SetFrameStrata("DIALOG")
                linkBackdrop:SetFrameLevel(499)
                linkBackdrop:SetAllPoints(UIParent)
                local bdTex = linkBackdrop:CreateTexture(nil, "BACKGROUND")
                bdTex:SetAllPoints()
                bdTex:SetColorTexture(0, 0, 0, 0.20)
                local fadeIn = linkBackdrop:CreateAnimationGroup()
                fadeIn:SetToFinalAlpha(true)
                local a = fadeIn:CreateAnimation("Alpha")
                a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.2)
                linkBackdrop._fadeIn = fadeIn
                linkBackdrop:RegisterForClicks("AnyUp")
                linkBackdrop:SetScript("OnClick", HideLinkPopup)
                linkBackdrop:Hide()

                linkPopup = CreateFrame("Frame", nil, UIParent)
                linkPopup:SetFrameStrata("DIALOG")
                linkPopup:SetFrameLevel(500)
                linkPopup:SetSize(380, 72)
                local popFade = linkPopup:CreateAnimationGroup()
                popFade:SetToFinalAlpha(true)
                local pa = popFade:CreateAnimation("Alpha")
                pa:SetFromAlpha(0); pa:SetToAlpha(1); pa:SetDuration(0.2)
                linkPopup._fadeIn = popFade

                local bg = SolidTex(linkPopup, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.97)
                bg:SetAllPoints()
                MakeBorder(linkPopup, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

                local hint = MakeFont(linkPopup, 11, nil, TEXT_SECTION.r, TEXT_SECTION.g, TEXT_SECTION.b, TEXT_SECTION.a)
                hint:SetPoint("TOP", linkPopup, "TOP", 0, -10)
                hint:SetText("Press Ctrl+C to copy, then Escape to close")

                local eb = CreateFrame("EditBox", nil, linkPopup)
                eb:SetSize(340, 26)
                eb:SetPoint("TOP", hint, "BOTTOM", 0, -8)
                eb:SetFontObject(GameFontHighlight)
                eb:SetAutoFocus(false)
                eb:SetJustifyH("CENTER")
                local ebBg = SolidTex(eb, "BACKGROUND", 0.10, 0.12, 0.16, 1)
                ebBg:SetPoint("TOPLEFT", -6, 4); ebBg:SetPoint("BOTTOMRIGHT", 6, -4)
                MakeBorder(eb, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.02)
                eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); HideLinkPopup() end)
                eb:SetScript("OnMouseUp", function(self) self:HighlightText() end)
                linkPopup:EnableMouse(true)
                linkPopup:SetScript("OnMouseDown", function() linkPopup._eb:SetFocus(); linkPopup._eb:HighlightText() end)
                linkPopup._eb = eb
            end
            linkPopup._eb:SetText(url)
            linkPopup:ClearAllPoints()
            linkPopup:SetPoint("BOTTOM", anchorBtn, "TOP", 0, 8)
            linkBackdrop:SetAlpha(0); linkBackdrop:Show(); linkBackdrop._fadeIn:Play()
            linkPopup:SetAlpha(0); linkPopup:Show(); linkPopup._fadeIn:Play()
            linkPopup._eb:SetFocus(); linkPopup._eb:HighlightText()
        end

        local socialDefs = {
            { icon = ICONS_PATH .. "twitch-2.png",  url = "https://www.twitch.tv/ellesmere_gaming" },
            { icon = ICONS_PATH .. "discord-2.png", url = "https://discord.gg/FtCsUSC" },
            { icon = ICONS_PATH .. "donate-3.png",  url = "https://www.patreon.com/ellesmere" },
        }

        -- Anchor: rightmost icon sits SOCIAL_GAP to the left of where Done starts
        -- Done is at BOTTOMRIGHT -FOOTER_PAD, so first icon anchor = Done left edge - gap
        local prevAnchor = nil
        for i = #socialDefs, 1, -1 do
            local def = socialDefs[i]
            local btn = CreateFrame("Button", nil, footerFrame)
            PanelPP.Size(btn, SOCIAL_SIZE, SOCIAL_SIZE)
            btn:SetFrameLevel(footerFrame:GetFrameLevel() + 1)
            if not prevAnchor then
                -- Rightmost icon: anchor relative to Done button position
                PanelPP.Point(btn, "BOTTOMRIGHT", footerFrame, "BOTTOMRIGHT",
                    -(FOOTER_PAD + DONE_BTN_W + SOCIAL_GAP + 15), FOOTER_Y + (FOOTER_BTN_H - SOCIAL_SIZE) / 2)
            else
                PanelPP.Point(btn, "RIGHT", prevAnchor, "LEFT", -SOCIAL_GAP, 0)
            end
            prevAnchor = btn

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture(def.icon)
            tex:SetAlpha(SOCIAL_ALPHA)
            PanelPP.DisablePixelSnap(tex)

            local progress, target = 0, 0
            local function Apply(t)
                tex:SetAlpha(lerp(SOCIAL_ALPHA, SOCIAL_HOVER, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / SOCIAL_FADE)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target; self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
            btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
            btn:SetScript("OnClick", function() ShowLinkPopup(def.url, btn) end)
        end
    end

    -- Done  (right side, FOOTER_PAD from right edge, green, closes window)
    do
        local btn = CreateFrame("Button", nil, footerFrame)
        PanelPP.Size(btn, DONE_BTN_W, FOOTER_BTN_H)
        PanelPP.Point(btn, "BOTTOMRIGHT", footerFrame, "BOTTOMRIGHT", -FOOTER_PAD, FOOTER_Y)
        btn:SetFrameLevel(footerFrame:GetFrameLevel() + 1)
        local brd = MakeBorder(btn, ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 0.7, PanelPP)
        local bg = SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, .92)
        bg:SetAllPoints()
        local lbl = MakeFont(btn, 13, nil, ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b)
        lbl:SetAlpha(0.7); lbl:SetPoint("CENTER"); lbl:SetText("Done")
        -- Hover animation reads from ELLESMERE_GREEN live
        local FADE_DUR = 0.1
        local progress, target = 0, 0
        local function Apply(t)
            local EG = ELLESMERE_GREEN
            lbl:SetTextColor(EG.r, EG.g, EG.b, lerp(0.7, 1, t))
            brd:SetColor(EG.r, EG.g, EG.b, lerp(0.7, 1, t))
        end
        local function OnUpdate(self, elapsed)
            local dir = (target == 1) and 1 or -1
            progress = progress + dir * (elapsed / FADE_DUR)
            if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                progress = target; self:SetScript("OnUpdate", nil)
            end
            Apply(progress)
        end
        btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
        btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
        btn:SetScript("OnClick", function() if mainFrame then mainFrame:Hide() end end)
        -- Register for accent updates
        RegAccent({ type="callback", fn=function(r, g, b)
            lbl:SetTextColor(r, g, b, lerp(0.7, 1, progress))
            brd:SetColor(r, g, b, lerp(0.7, 1, progress))
        end })
    end

    return mainFrame
end

-------------------------------------------------------------------------------
--  Tab Bar helpers
-------------------------------------------------------------------------------
ClearTabs = function()
    for _, btn in ipairs(tabBar._tabButtons) do btn:Hide(); btn:SetParent(nil) end
    wipe(tabBar._tabButtons)
end

CreateTabButton = function(index, name)
    local btn = CreateFrame("Button", nil, tabBar)
    btn:SetHeight(TAB_BAR_H)
    btn:SetFrameLevel(tabBar:GetFrameLevel() + 1)

    local label = MakeFont(btn, 16, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    label:SetPoint("CENTER", 0, 0)
    label:SetText(name)
    btn._label = label
    btn._name  = name

    local textW = label:GetStringWidth() or 60
    btn:SetWidth(textW + 30)

    -- Teal underline for active tab
    local underline = SolidTex(btn, "ARTWORK", ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
    underline:SetSize(textW + 14, 2)
    underline:SetPoint("BOTTOM", btn, "BOTTOM", 0, 0)
    underline:Hide()
    btn._underline = underline
    RegAccent({ type="solid", obj=underline, a=1 })

    btn:SetScript("OnEnter", function(self)
        if activePage ~= self._name then self._label:SetTextColor(1, 1, 1, 0.86) end
    end)
    btn:SetScript("OnLeave", function(self)
        if activePage ~= self._name then self._label:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a) end
    end)
    btn:SetScript("OnClick", function(self) EllesmereUI:SelectPage(self._name) end)

    return btn
end

BuildTabs = function(pageNames, disabledPages, disabledTooltips)
    ClearTabs()
    if not pageNames or #pageNames == 0 then tabBar:SetHeight(0.001); return end
    tabBar:SetHeight(TAB_BAR_H)
    local disabledSet = {}
    if disabledPages then
        for _, name in ipairs(disabledPages) do disabledSet[name] = true end
    end
    local xOff = CONTENT_PAD
    for i, name in ipairs(pageNames) do
        local btn = CreateTabButton(i, name)
        btn:SetPoint("BOTTOMLEFT", tabBar, "BOTTOMLEFT", xOff, 0)
        xOff = xOff + btn:GetWidth() + 6
        tabBar._tabButtons[i] = btn
        -- Disable tab if in disabledPages list
        if disabledSet[name] then
            btn:EnableMouse(true)  -- keep mouse enabled for tooltip
            btn._label:SetAlpha(0.30)
            btn._disabled = true
            local tip = disabledTooltips and disabledTooltips[name]
            if tip then
                btn:SetScript("OnEnter", function(self)
                    if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(self, tip) end
                end)
                btn:SetScript("OnLeave", function()
                    if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
                end)
            end
            -- Swallow clicks on disabled tabs
            btn:SetScript("OnClick", function() end)
        end
    end

    ---------------------------------------------------------------------------
    --  Inline search EditBox  (right-aligned in tab bar, always visible)
    ---------------------------------------------------------------------------
    if not tabBar._searchBox then
        local SEARCH_W, SEARCH_H = 180, 28
        local searchFrame = CreateFrame("Frame", nil, tabBar)
        searchFrame:SetSize(SEARCH_W, SEARCH_H)
        searchFrame:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", -CONTENT_PAD, (TAB_BAR_H - SEARCH_H) / 2)
        searchFrame:SetFrameLevel(tabBar:GetFrameLevel() + 2)

        local searchBg = SolidTex(searchFrame, "BACKGROUND", SL_INPUT_R, SL_INPUT_G, SL_INPUT_B, SL_INPUT_A + 0.10)
        searchBg:SetAllPoints()
        local searchBrd = MakeBorder(searchFrame, BORDER_R, BORDER_G, BORDER_B, 0.10)

        local editBox = CreateFrame("EditBox", nil, searchFrame)
        editBox:SetAllPoints()
        editBox:SetAutoFocus(false)
        editBox:SetFont(EXPRESSWAY, 13, "")
        editBox:SetTextColor(TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B, 1)
        editBox:SetTextInsets(10, 24, 0, 0)
        editBox:SetMaxLetters(40)

        local placeholder = MakeFont(searchFrame, 13, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
        placeholder:SetPoint("LEFT", searchFrame, "LEFT", 10, 0)
        placeholder:SetText("Search...")

        -- Clear button (X) on right side — frame level above editBox so clicks register
        local clearBtn = CreateFrame("Button", nil, searchFrame)
        clearBtn:SetSize(20, 20)
        clearBtn:SetPoint("RIGHT", searchFrame, "RIGHT", -4, 0)
        clearBtn:SetFrameLevel(editBox:GetFrameLevel() + 2)
        clearBtn:Hide()
        local clearLabel = MakeFont(clearBtn, 20, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, 0.35)
        clearLabel:SetPoint("CENTER")
        clearLabel:SetText("×")
        clearBtn:SetScript("OnEnter", function() clearLabel:SetTextColor(1, 1, 1, 1) end)
        clearBtn:SetScript("OnLeave", function() clearLabel:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, 0.35) end)
        clearBtn:SetScript("OnClick", function()
            editBox:SetText("")
            editBox:ClearFocus()
        end)

        -- Border hover effect
        searchFrame:SetScript("OnEnter", function() searchBrd:SetColor(BORDER_R, BORDER_G, BORDER_B, 0.15) end)
        searchFrame:SetScript("OnLeave", function() searchBrd:SetColor(BORDER_R, BORDER_G, BORDER_B, 0.10) end)
        editBox:SetScript("OnEditFocusGained", function() searchBrd:SetColor(BORDER_R, BORDER_G, BORDER_B, 0.15) end)
        editBox:SetScript("OnEditFocusLost", function() searchBrd:SetColor(BORDER_R, BORDER_G, BORDER_B, 0.10) end)

        local searchDebounceTimer
        editBox:SetScript("OnTextChanged", function(self, userInput)
            local text = self:GetText() or ""
            if text == "" then
                placeholder:Show()
                clearBtn:Hide()
            else
                placeholder:Hide()
                clearBtn:Show()
            end
            if searchDebounceTimer then searchDebounceTimer:Cancel(); searchDebounceTimer = nil end
            EllesmereUI:ApplyInlineSearch(text, true)
            if text ~= "" then
                searchDebounceTimer = C_Timer.NewTimer(0.5, function()
                    searchDebounceTimer = nil
                    EllesmereUI:ApplyInlineSearch(text)
                end)
            end
        end)

        editBox:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
        end)

        editBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)

        tabBar._searchBox = editBox
        tabBar._searchFrame = searchFrame
    end
    tabBar._searchFrame:Show()
    -- Clear search text when tabs are rebuilt (module switch)
    if tabBar._searchBox:GetText() ~= "" then
        tabBar._searchBox:SetText("")
    end

    -- Defer a relayout so GetStringWidth returns correct values after render
    tabBar:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local x = CONTENT_PAD
        for _, b in ipairs(self._tabButtons) do
            local tw = b._label:GetStringWidth() or 60
            b:SetWidth(tw + 30)
            if b._underline then b._underline:SetWidth(tw + 14) end
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 0)
            x = x + b:GetWidth() + 6
        end
    end)
end

UpdateTabHighlight = function(selectedName)
    for _, btn in ipairs(tabBar._tabButtons) do
        if btn._disabled then
            -- disabled tab: keep dimmed, no underline
        elseif btn._name == selectedName then
            btn._label:SetTextColor(1, 1, 1, 1)
            btn._underline:Show()
        else
            btn._label:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            btn._underline:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  Inline Search  (filter sections on the current page)
-------------------------------------------------------------------------------
local _pageCache  -- forward declaration; initialized below in page-cache section
-- Pool of reusable highlight border frames (accent-colored, fade-in only)
local _searchHighlightPool = {}
local _searchHighlightsActive = {}

local function GetSearchHighlight()
    local hl = table.remove(_searchHighlightPool)
    if not hl then
        hl = CreateFrame("Frame")
        local c = ELLESMERE_GREEN
        local function MkEdge()
            local t = hl:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(c.r, c.g, c.b, 1)
            return t
        end
        hl._top = MkEdge()
        hl._bot = MkEdge()
        hl._lft = MkEdge()
        hl._rgt = MkEdge()
        hl._top:SetHeight(1)
        hl._top:SetPoint("TOPLEFT"); hl._top:SetPoint("TOPRIGHT")
        hl._bot:SetHeight(1)
        hl._bot:SetPoint("BOTTOMLEFT"); hl._bot:SetPoint("BOTTOMRIGHT")
        hl._lft:SetWidth(1)
        hl._lft:SetPoint("TOPLEFT", hl._top, "BOTTOMLEFT")
        hl._lft:SetPoint("BOTTOMLEFT", hl._bot, "TOPLEFT")
        hl._rgt:SetWidth(1)
        hl._rgt:SetPoint("TOPRIGHT", hl._top, "BOTTOMRIGHT")
        hl._rgt:SetPoint("BOTTOMRIGHT", hl._bot, "TOPRIGHT")
    end
    _searchHighlightsActive[#_searchHighlightsActive + 1] = hl
    return hl
end

local function RecycleAllSearchHighlights()
    for i = #_searchHighlightsActive, 1, -1 do
        local hl = _searchHighlightsActive[i]
        hl:Hide()
        hl:SetScript("OnUpdate", nil)
        hl:ClearAllPoints()
        _searchHighlightPool[#_searchHighlightPool + 1] = hl
        _searchHighlightsActive[i] = nil
    end
end

local function PlaySearchHighlight(hl, targetFrame)
    hl:SetParent(targetFrame)
    hl:SetAllPoints(targetFrame)
    hl:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
    hl:SetAlpha(0)
    hl:Show()
    local elapsed = 0
    hl:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.3 then
            self:SetAlpha(0.5)
            self:SetScript("OnUpdate", nil)
            return
        end
        self:SetAlpha(0.5 * (elapsed / 0.3))
    end)
end

-- Collect ALL direct children of a wrapper sorted by original Y position (top to bottom).
-- Groups them into sections: { header=frame, members={frame,...} }
-- Every child belongs to the most recent section header above it.
-- Children before any section header go into a leading orphan list.
-- Split column containers (_leftCol/_rightCol) are treated as single blocks;
-- their internal children are searched but not individually re-anchored.
local function CollectAllChildren(wrapper)
    local children = { wrapper:GetChildren() }
    -- Save original anchor info on first encounter so we can restore later.
    for _, child in ipairs(children) do
        if not child._origAnchor then
            local point, rel, relPoint, x, y = child:GetPoint(1)
            if point then
                child._origAnchor = { point, rel, relPoint, x, y }
            end
        end
        -- For split containers, build a searchable label from all children inside
        if child._leftCol or child._rightCol then
            if not child._splitSearchLabels then
                local labels = {}
                local function GatherLabels(col)
                    if not col then return end
                    local subs = { col:GetChildren() }
                    for _, sub in ipairs(subs) do
                        if sub._sectionName then labels[#labels + 1] = sub._sectionName end
                        if sub._labelText then labels[#labels + 1] = sub._labelText end
                    end
                end
                GatherLabels(child._leftCol)
                GatherLabels(child._rightCol)
                child._splitSearchLabels = table.concat(labels, " ")
            end
        end
    end
    table.sort(children, function(a, b)
        local ay = a._origAnchor and a._origAnchor[5] or 0
        local by = b._origAnchor and b._origAnchor[5] or 0
        return ay > by  -- y offsets are negative, so higher (less negative) = higher on page
    end)

    local sections = {}       -- { { header=frame, members={frame,...} }, ... }
    local orphans  = {}       -- children before any section header
    local current  = nil      -- current section entry

    for _, child in ipairs(children) do
        if child._isSectionHeader then
            current = { header = child, members = {} }
            sections[#sections + 1] = current
        elseif current then
            current.members[#current.members + 1] = child
        else
            orphans[#orphans + 1] = child
        end
    end
    return sections, orphans
end

-- Get a searchable label for any child frame (tagged or not)
local function GetSearchLabel(child)
    if child._labelText then return child._labelText end
    if child._sectionName then return child._sectionName end
    if child._splitSearchLabels then return child._splitSearchLabels end
    return ""
end

-- Resolve the current display text of a dropdown on a region (if any)
local function GetDropdownValueText(region)
    if not region._ddGetValue or not region._ddValues then return nil end
    local key = region._ddGetValue()
    if key == nil then return nil end
    local val = region._ddValues[key]
    if val == nil then return nil end
    if type(val) == "table" then return val.text end
    return tostring(val)
end

function EllesmereUI:ApplyInlineSearch(query, skipHighlights)
    if not activeModule or not activePage then return end
    local cacheKey = activeModule .. "::" .. activePage
    local cached = _pageCache[cacheKey]
    if not cached or not cached.wrapper then return end

    RecycleAllSearchHighlights()

    local sections, orphans = CollectAllChildren(cached.wrapper)

    -- Empty query: restore everything
    if not query or query == "" then
        for _, sec in ipairs(sections) do
            sec.header:Show()
            if sec.header._origAnchor then
                sec.header:ClearAllPoints()
                local a = sec.header._origAnchor
                PanelPP.Point(sec.header, a[1], a[2], a[3], a[4], a[5])
            end
            for _, m in ipairs(sec.members) do
                m:Show()
                if m._origAnchor then
                    m:ClearAllPoints()
                    local a = m._origAnchor
                    PanelPP.Point(m, a[1], a[2], a[3], a[4], a[5])
                end
            end
        end
        for _, o in ipairs(orphans) do
            o:Show()
            if o._origAnchor then
                o:ClearAllPoints()
                local a = o._origAnchor
                PanelPP.Point(o, a[1], a[2], a[3], a[4], a[5])
            end
        end
        -- Restore original scroll height
        contentFrame:SetHeight(cached.totalH + 30)
        if scrollFrame and scrollFrame.SetVerticalScroll then
            scrollTarget = 0
            isSmoothing = false
            if smoothFrame then smoothFrame:Hide() end
            scrollFrame:SetVerticalScroll(0)
            UpdateScrollThumb()
        end
        return
    end

    local queryLower = query:lower()

    -- Determine which sections are visible and which rows/slots match
    local visibleSections = {}
    for _, sec in ipairs(sections) do
        local sectionName = sec.header._sectionName or ""
        local sectionMatch = sectionName:lower():find(queryLower, 1, true)

        local anyMemberMatch = false
        local matchingMembers = {}
        for _, m in ipairs(sec.members) do
            local label = GetSearchLabel(m)
            local matched = label ~= "" and label:lower():find(queryLower, 1, true)
            if not matched then
                -- Also check current dropdown selected values on this row's regions
                for _, rgn in ipairs({ m._leftRegion, m._midRegion, m._rightRegion }) do
                    if rgn then
                        local ddText = GetDropdownValueText(rgn)
                        if ddText and ddText:lower():find(queryLower, 1, true) then
                            matched = true; break
                        end
                    end
                end
            end
            if matched then
                anyMemberMatch = true
                matchingMembers[m] = true
            end
        end

        if sectionMatch or anyMemberMatch then
            visibleSections[#visibleSections + 1] = {
                sec = sec,
                sectionMatch = sectionMatch,
                matchingMembers = matchingMembers,
            }
        else
            sec.header:Hide()
            for _, m in ipairs(sec.members) do m:Hide() end
        end
    end

    -- Hide non-matching orphans
    for _, o in ipairs(orphans) do o:Hide() end

    -- Build per-slot highlight targets and count totals to decide if we suppress
    -- highlights (when every visible slot is highlighted, none should glow).
    local highlightTargets = {}  -- list of { frame = region_or_member }
    local totalSlots = 0
    local highlightedSlots = 0

    for _, vs in ipairs(visibleSections) do
        for _, m in ipairs(vs.sec.members) do
            -- Skip spacer frames — they have no content to highlight
            if m._isSpacer then
                -- still counts as nothing
            else
            -- Collect the slots this member exposes
            local slots = {}
            if m._leftRegion then
                slots[#slots + 1] = { region = m._leftRegion,  label = m._leftRegion._slotLabel  or "" }
            end
            if m._midRegion then
                slots[#slots + 1] = { region = m._midRegion,   label = m._midRegion._slotLabel   or "" }
            end
            if m._rightRegion then
                slots[#slots + 1] = { region = m._rightRegion, label = m._rightRegion._slotLabel or "" }
            end

            if #slots > 0 then
                -- Split row: check each slot individually
                for _, s in ipairs(slots) do
                    if s.label ~= "" then
                        totalSlots = totalSlots + 1
                        local slotMatch = s.label:lower():find(queryLower, 1, true)
                        if not slotMatch then
                            local ddText = GetDropdownValueText(s.region)
                            if ddText then slotMatch = ddText:lower():find(queryLower, 1, true) end
                        end
                        if vs.sectionMatch or slotMatch then
                            highlightedSlots = highlightedSlots + 1
                            highlightTargets[#highlightTargets + 1] = s.region
                        end
                    end
                end
            else
                -- Non-split row: whole member is one slot
                totalSlots = totalSlots + 1
                local label = GetSearchLabel(m)
                local memberMatch = label ~= "" and label:lower():find(queryLower, 1, true)
                if vs.sectionMatch or memberMatch then
                    highlightedSlots = highlightedSlots + 1
                    highlightTargets[#highlightTargets + 1] = m
                end
            end
            end -- _isSpacer else
        end
    end

    -- If every visible slot is highlighted, suppress all highlights
    local suppressHighlights = (highlightedSlots >= totalSlots)

    -- Build a fast lookup for highlight targets
    local hlSet = {}
    if not suppressHighlights then
        for _, target in ipairs(highlightTargets) do
            hlSet[target] = true
        end
    end

    -- Re-anchor visible items sequentially from top
    local startY = -6
    local y = startY
    for _, vs in ipairs(visibleSections) do
        local sec = vs.sec
        local hdrX = sec.header._origAnchor and sec.header._origAnchor[4] or CONTENT_PAD
        sec.header:ClearAllPoints()
        PanelPP.Point(sec.header, "TOPLEFT", cached.wrapper, "TOPLEFT", hdrX, y)
        sec.header:Show()
        y = y - sec.header:GetHeight()

        for _, m in ipairs(sec.members) do
            -- Hide spacers during search — they're just empty gaps
            if m._isSpacer then
                m:Hide()
            else
            local mx = m._origAnchor and m._origAnchor[4] or CONTENT_PAD
            m:ClearAllPoints()
            PanelPP.Point(m, "TOPLEFT", cached.wrapper, "TOPLEFT", mx, y)
            m:Show()

            if not suppressHighlights and not skipHighlights then
                -- Check slot-level highlights for split rows
                if m._leftRegion and hlSet[m._leftRegion] then
                    local hl = GetSearchHighlight()
                    PlaySearchHighlight(hl, m._leftRegion)
                end
                if m._midRegion and hlSet[m._midRegion] then
                    local hl = GetSearchHighlight()
                    PlaySearchHighlight(hl, m._midRegion)
                end
                if m._rightRegion and hlSet[m._rightRegion] then
                    local hl = GetSearchHighlight()
                    PlaySearchHighlight(hl, m._rightRegion)
                end
                -- Non-split row highlight
                if not m._leftRegion and hlSet[m] then
                    local hl = GetSearchHighlight()
                    PlaySearchHighlight(hl, m)
                end
            end

            y = y - m:GetHeight()
            end -- _isSpacer else
        end
    end

    -- Resize content to fit visible items only
    local visibleH = math.abs(y - startY)
    contentFrame:SetHeight(visibleH + 30)

    if scrollFrame and scrollFrame.SetVerticalScroll then
        scrollTarget = 0
        isSmoothing = false
        if smoothFrame then smoothFrame:Hide() end
        scrollFrame:SetVerticalScroll(0)
        UpdateScrollThumb()
    end
end

-------------------------------------------------------------------------------
--  Sidebar highlight  (icon on/off swap)
-------------------------------------------------------------------------------
UpdateSidebarHighlight = function(selectedFolder)
    for folder, btn in pairs(sidebarButtons) do
        btn._hoverGlow:Hide()
        btn._hoverIndicator:Hide()
        if folder == selectedFolder then
            btn._indicator:Show()
            btn._glow:Show()
            btn._glowTop:Show()
            btn._glowBot:Show()
            if btn._loaded then
                btn._label:SetTextColor(NAV_SELECTED_TEXT.r, NAV_SELECTED_TEXT.g, NAV_SELECTED_TEXT.b, NAV_SELECTED_TEXT.a)
                btn._icon:SetTexture(btn._iconOff)
                btn._icon:SetDesaturated(false)
                btn._icon:SetAlpha(NAV_SELECTED_ICON_A)
                btn._iconGlow:Show()
            else
                btn._label:SetTextColor(NAV_SELECTED_TEXT.r, NAV_SELECTED_TEXT.g, NAV_SELECTED_TEXT.b, NAV_SELECTED_TEXT.a)
                btn._icon:SetTexture(btn._iconOff)
                btn._icon:SetDesaturated(false)
                btn._icon:SetAlpha(NAV_SELECTED_ICON_A)
                btn._iconGlow:Show()
            end
        else
            btn._indicator:Hide()
            btn._glow:Hide()
            btn._glowTop:Hide()
            btn._glowBot:Hide()
            btn._iconGlow:Hide()
            if btn._loaded then
                btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
                btn._icon:SetTexture(btn._iconOff)
                btn._icon:SetDesaturated(false)
                btn._icon:SetAlpha(NAV_ENABLED_ICON_A)
            else
                btn._label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
                btn._icon:SetDesaturated(true)
                btn._icon:SetAlpha(NAV_DISABLED_ICON_A)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Content clearing
-------------------------------------------------------------------------------
-- WoW frames are permanent C objects that can never be freed.  Rather than
-- orphaning them with SetParent(nil) (which still leaks the same memory),
-- we just Hide() everything in place.  buildPage creates new frames on top,
-- and the hidden old frames take zero render cost.  The net effect is the
-- same memory use with less churn.
ClearContent = function()
    if not scrollChild then return end
    -- Clear widget refresh registry
    ClearWidgetRefreshList()
    -- Clear content header (non-scrolling region) if active
    if EllesmereUI.ClearContentHeader then
        EllesmereUI:ClearContentHeader()
    end
    -- Reset alternating row counters
    ResetRowCounters()
    -- Clear per-page layout flags so they don't bleed into the next page
    if scrollChild then scrollChild._showRowDivider = nil end
    -- Hide copy popup if visible
    if EllesmereUI._copyPopup then EllesmereUI._copyPopup:Hide() end
    if EllesmereUI._copyBackdrop then EllesmereUI._copyBackdrop:Hide() end
    -- Disconnect all children from the frame tree.
    -- WoW frames can never be freed, but SetParent(nil) removes them from
    -- the render/layout hierarchy so they don't accumulate under scrollChild.
    local children = { scrollChild:GetChildren() }
    for _, child in ipairs(children) do child:Hide(); child:SetParent(nil) end
    local regions = { scrollChild:GetRegions() }
    for _, region in ipairs(regions) do region:Hide(); region:SetParent(nil) end
end

-------------------------------------------------------------------------------
--  SPLIT COLUMN LAYOUT
--  Creates two side-by-side scrollable column frames with a 1px divider.
--  Usage:  local left, right, splitFrame = EllesmereUI:CreateSplitColumns(parent, yOffset)
--  Widgets anchor to left/right using the same TOPLEFT + yOffset pattern.
--  Call splitFrame:SetHeight(maxH) after populating both columns.
-------------------------------------------------------------------------------
function EllesmereUI:CreateSplitColumns(parent, yOffset)
    local PAD = 20        -- space between column edge and divider
    local DIV_W = 1       -- divider width
    local totalW = parent:GetWidth()
    local colW = math.floor((totalW - PAD * 2 - DIV_W) / 2)

    local splitFrame = CreateFrame("Frame", nil, parent)
    splitFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset or 0)
    splitFrame:SetWidth(totalW)
    splitFrame:SetHeight(1)  -- caller sets final height

    local leftCol = CreateFrame("Frame", nil, splitFrame)
    leftCol:SetPoint("TOPLEFT", splitFrame, "TOPLEFT", 0, 0)
    leftCol:SetSize(colW, 1)

    local divider = splitFrame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.08)
    divider:SetWidth(DIV_W)
    divider:SetPoint("TOP", splitFrame, "TOP", 0, 0)
    divider:SetPoint("BOTTOM", splitFrame, "BOTTOM", 0, 0)

    local rightCol = CreateFrame("Frame", nil, splitFrame)
    rightCol:SetPoint("TOPRIGHT", splitFrame, "TOPRIGHT", 0, 0)
    rightCol:SetSize(colW, 1)

    splitFrame._leftCol  = leftCol
    splitFrame._rightCol = rightCol
    splitFrame._divider  = divider
    splitFrame._colW     = colW

    -- Mark columns with split parent so RowBg can extend backgrounds full width
    leftCol._splitParent  = splitFrame
    rightCol._splitParent = splitFrame

    return leftCol, rightCol, splitFrame
end

-------------------------------------------------------------------------------
--  Module Registration
-------------------------------------------------------------------------------
function EllesmereUI:RegisterModule(folderName, config)
    modules[folderName] = config
    -- If UI is already built, update sidebar button immediately
    -- Otherwise, RefreshSidebarStates will handle it when the panel first opens
    local btn = sidebarButtons[folderName]
    if btn then
        btn._loaded = true
        btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        btn._icon:SetDesaturated(false)
        btn._icon:SetAlpha(NAV_ENABLED_ICON_A)
    end
    -- Don't auto-select here; RefreshSidebarStates handles default selection in roster order
end

--- Reset every registered module's settings and the shared EllesmereUIDB.
--- Called by the "Reset ALL EUI Addon Settings" button in Global Settings.
function EllesmereUI:ResetAllModules()
    for _, config in pairs(modules) do
        if config.onReset then
            config.onReset()
        end
    end
    -- Clear unlock mode anchor relationships
    if EllesmereUIDB then
        EllesmereUIDB.unlockAnchors = nil
        -- Wipe profile system data so the user starts fresh
        EllesmereUIDB.profiles = nil
        EllesmereUIDB.profileOrder = nil
        EllesmereUIDB.specProfiles = nil
        EllesmereUIDB.activeProfile = nil
    end
end

-------------------------------------------------------------------------------
--  Page / Module Selection
-------------------------------------------------------------------------------
-- Page cache: maps "moduleName::pageName" -> { wrapper, totalH, headerBuilder }
-- On revisit, we show the cached wrapper and refresh widget values instead of rebuilding.
_pageCache = {}

-- Invalidate all cached pages (called on profile reset, module reload, etc.)
function EllesmereUI:InvalidatePageCache()
    for key, entry in pairs(_pageCache) do
        if entry.wrapper then
            entry.wrapper:Hide()
            entry.wrapper:SetParent(nil)
        end
        _pageCache[key] = nil
    end
    EllesmereUI:InvalidateContentHeaderCache()
end

function EllesmereUI:SelectPage(pageName)
    if not activeModule or not modules[activeModule] then return end

    -- "Unlock Mode" is a fake nav item — fire unlock mode without changing page state.
    -- Capture the current module + page so DoClose can restore them exactly.
    if pageName == "Unlock Mode" then
        if EllesmereUI._openUnlockMode then
            EllesmereUI._unlockReturnModule = activeModule
            EllesmereUI._unlockReturnPage   = activePage
            C_Timer.After(0, EllesmereUI._openUnlockMode)
        end
        return
    end

    -- "Disable Addons" is a fake nav item — close EUI and open the Blizzard addon list.
    if pageName == "Disable Addons" then
        if EllesmereUI._mainFrame then EllesmereUI._mainFrame:Hide() end
        C_Timer.After(0, function()
            if not AddonList then
                C_AddOns.LoadAddOn("Blizzard_AddonList")
            end
            if AddonList then ShowUIPanel(AddonList) end
        end)
        return
    end

    -- Save current page's refresh list before switching
    if activePage then
        local oldKey = activeModule .. "::" .. activePage
        if _pageCache[oldKey] then
            local rl = _pageCache[oldKey].refreshList
            if not rl then rl = {}; _pageCache[oldKey].refreshList = rl end
            -- Wipe and repopulate in-place
            for i = #rl, 1, -1 do rl[i] = nil end
            for i = 1, #_widgetRefreshList do
                rl[i] = _widgetRefreshList[i]
            end
        end
        -- Save current content header to cache before leaving this page
        EllesmereUI:SaveContentHeaderToCache(oldKey)
    end

    activePage = pageName
    _lastPagePerModule[activeModule] = pageName
    UpdateTabHighlight(pageName)

    -- Clear inline search when switching tabs
    if tabBar and tabBar._searchBox and tabBar._searchBox:GetText() ~= "" then
        tabBar._searchBox:SetText("")
    end

    local cacheKey = activeModule .. "::" .. pageName
    local cached = _pageCache[cacheKey]

    if cached and cached.wrapper then
        -- Fast path: re-show cached page
        -- Hide all current scrollChild children AND regions
        -- (regions needed to clean up install page FontStrings/textures)
        HideAllChildren(scrollChild)

        -- Restore content header from cache; fall back to rebuild if not cached
        if not EllesmereUI:RestoreContentHeaderFromCache(cacheKey) then
            if cached.headerBuilder then
                EllesmereUI:SetContentHeader(cached.headerBuilder)
            else
                if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
            end
        end

        -- Show the cached wrapper and set scroll child height
        cached.wrapper:Show()
        contentFrame:SetHeight(cached.totalH + 30)

        -- Restore this page's refresh list
        ClearWidgetRefreshList()
        if cached.refreshList then
            for i = 1, #cached.refreshList do
                _widgetRefreshList[i] = cached.refreshList[i]
            end
        end

        -- Refresh all widget values in-place
        for i = 1, #_widgetRefreshList do _widgetRefreshList[i]() end

        -- Fire module-level refresh hooks (preview update, etc.)
        local config = modules[activeModule]
        if config.onPageCacheRestore then config.onPageCacheRestore(pageName) end
    else
        -- Cold path: build page for the first time
        -- Hide any visible wrappers AND regions from other pages / install page
        HideAllChildren(scrollChild)

        -- Clear content header
        lastHeaderPadded = false
        ClearWidgetRefreshList()
        ResetRowCounters()
        if EllesmereUI._copyPopup then EllesmereUI._copyPopup:Hide() end
        if EllesmereUI._copyBackdrop then EllesmereUI._copyBackdrop:Hide() end
        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end

        -- Create a wrapper frame for this page
        local wrapper = CreateFrame("Frame", nil, scrollChild)
        wrapper:SetAllPoints(scrollChild)

        local config = modules[activeModule]
        local totalH = 0
        if config.buildPage then
            local startY = -6
            totalH = config.buildPage(pageName, wrapper, startY) or 600
            contentFrame:SetHeight(totalH + 30)
        end

        -- Capture the content header builder for this page (if one was set)
        local headerBuilder = nil
        if config.getHeaderBuilder then
            headerBuilder = config.getHeaderBuilder(pageName)
        end

        -- Cache this page's refresh list
        local cachedRefreshList = {}
        for i = 1, #_widgetRefreshList do
            cachedRefreshList[i] = _widgetRefreshList[i]
        end

        _pageCache[cacheKey] = {
            wrapper = wrapper,
            totalH = totalH,
            headerBuilder = headerBuilder,
            refreshList = cachedRefreshList,
        }
    end

    -- Reset scroll to top on tab switch
    if scrollFrame and scrollFrame.SetVerticalScroll then
        scrollTarget = 0
        isSmoothing = false
        if smoothFrame then smoothFrame:Hide() end
        scrollFrame:SetVerticalScroll(0)
        UpdateScrollThumb()
    end
end

-- Rebuild the current page content without resetting scroll position
-- Pass force=true to bypass the fast refresh path (e.g. when widget layout changes).
function EllesmereUI:RefreshPage(force)
    if not activeModule or not activePage then return end
    -- Fast path: if widgets registered refresh callbacks, just re-read
    -- DB values in-place.  No frame teardown, no allocations.
    if not force and #_widgetRefreshList > 0 then
        for i = 1, #_widgetRefreshList do _widgetRefreshList[i]() end
        return
    end
    -- Slow path: full teardown + rebuild
    local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll() or 0
    local savedTarget = scrollTarget

    -- Invalidate the current page's cache entry and destroy ONLY its wrapper.
    -- CRITICAL: Do NOT call ClearContent() here -- it calls SetParent(nil) on
    -- ALL scrollChild children, which orphans other cached pages' wrappers.
    -- Those wrappers are still referenced by _pageCache and will be restored
    -- when the user switches back to that tab.  If they've been orphaned,
    -- Show() makes them appear detached and the layout breaks ("settings fly
    -- all over the screen" bug).
    local cacheKey = activeModule .. "::" .. activePage
    local oldEntry = _pageCache[cacheKey]
    if oldEntry and oldEntry.wrapper then
        oldEntry.wrapper:Hide()
        oldEntry.wrapper:SetParent(nil)
    end
    _pageCache[cacheKey] = nil

    -- Clear widget refresh registry and header (safe -- these are per-page)
    ClearWidgetRefreshList()
    if EllesmereUI.ClearContentHeader then
        EllesmereUI:ClearContentHeader()
    end
    ResetRowCounters()
    if scrollChild then scrollChild._showRowDivider = nil end
    if EllesmereUI._copyPopup then EllesmereUI._copyPopup:Hide() end
    if EllesmereUI._copyBackdrop then EllesmereUI._copyBackdrop:Hide() end

    skipScrollChildReanchor = true
    suppressScrollRangeChanged = true

    -- Create a fresh wrapper for the rebuilt page
    local wrapper = CreateFrame("Frame", nil, scrollChild)
    wrapper:SetAllPoints(scrollChild)

    local config = modules[activeModule]
    local totalH = 0
    if config.buildPage then
        local startY = -6
        totalH = config.buildPage(activePage, wrapper, startY) or 600
        contentFrame:SetHeight(totalH + 30)
    end

    -- Re-cache
    local headerBuilder = nil
    if config.getHeaderBuilder then
        headerBuilder = config.getHeaderBuilder(activePage)
    end
    local cachedRefreshList = {}
    for i = 1, #_widgetRefreshList do
        cachedRefreshList[i] = _widgetRefreshList[i]
    end
    _pageCache[cacheKey] = {
        wrapper = wrapper,
        totalH = totalH,
        headerBuilder = headerBuilder,
        refreshList = cachedRefreshList,
    }

    skipScrollChildReanchor = false
    suppressScrollRangeChanged = false
    isSmoothing = false
    if smoothFrame then smoothFrame:Hide() end
    if scrollFrame then
        local maxScroll = tonumber(scrollFrame:GetVerticalScrollRange()) or 0
        local restored = math.min(savedScroll, maxScroll)
        scrollTarget = math.min(savedTarget, maxScroll)
        scrollFrame:SetVerticalScroll(restored)
        UpdateScrollThumb()
    end
end

function EllesmereUI:GetActiveModule()
    return activeModule
end

function EllesmereUI:SelectModule(folderName)
    if not modules[folderName] then return end

    -- Re-sync pixel perfect mult on every addon switch
    if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end

    -- Save current page's content header under the CORRECT old key
    -- before we overwrite activeModule.
    if activePage and activeModule then
        local oldKey = activeModule .. "::" .. activePage
        if _pageCache[oldKey] then
            local rl = _pageCache[oldKey].refreshList
            if not rl then rl = {}; _pageCache[oldKey].refreshList = rl end
            for i = #rl, 1, -1 do rl[i] = nil end
            for i = 1, #_widgetRefreshList do
                rl[i] = _widgetRefreshList[i]
            end
        end
        EllesmereUI:SaveContentHeaderToCache(oldKey)
    end

    activeModule = folderName
    local config = modules[folderName]
    UpdateSidebarHighlight(folderName)
    headerFrame._title:SetText(config.title or folderName)
    headerFrame._desc:SetText(config.description or "")
    BuildTabs(config.pages, config.disabledPages, config.disabledPageTooltips)
    local savedPage = _lastPagePerModule[folderName]
    -- Validate saved page still exists in this module's page list
    local validPage = nil
    if savedPage and config.pages then
        for _, p in ipairs(config.pages) do
            if p == savedPage then validPage = savedPage; break end
        end
    end
    local targetPage = validPage or (config.pages and config.pages[1])
    if targetPage then
        self:SelectPage(targetPage)
    else
        activePage = nil
        ClearContent()
    end
end

-------------------------------------------------------------------------------
--  Show / Hide / Toggle
-------------------------------------------------------------------------------
local function RefreshSidebarStates()
    -- Refresh global settings button state
    local globalBtn = sidebarButtons["_EUIGlobal"]
    if globalBtn then
        if "_EUIGlobal" == activeModule then
            globalBtn._label:SetTextColor(NAV_SELECTED_TEXT.r, NAV_SELECTED_TEXT.g, NAV_SELECTED_TEXT.b, NAV_SELECTED_TEXT.a)
            globalBtn._icon:SetTexture(globalBtn._iconOff)
            globalBtn._icon:SetDesaturated(false)
            globalBtn._icon:SetAlpha(NAV_SELECTED_ICON_A)
            globalBtn._iconGlow:Show()
        else
            globalBtn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            globalBtn._icon:SetTexture(globalBtn._iconOff)
            globalBtn._icon:SetDesaturated(false)
            globalBtn._icon:SetAlpha(NAV_ENABLED_ICON_A)
            globalBtn._iconGlow:Hide()
        end
    end

    local firstLoaded = nil

    -- Two-pass: enabled addons first (roster order), disabled addons after
    local enabledList = {}
    local disabledList = {}
    for _, info in ipairs(ADDON_ROSTER) do
        local loaded = info.alwaysLoaded or IsAddonLoaded(info.folder)
        if loaded then
            enabledList[#enabledList + 1] = info
        else
            disabledList[#disabledList + 1] = info
        end
    end

    local rowIndex = 0
    for _, info in ipairs(enabledList) do
        rowIndex = rowIndex + 1
        local folder = info.folder
        local btn = sidebarButtons[folder]
        if not btn then break end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, _sidebarAddonNavTop - (rowIndex - 1) * _sidebarNavRowH)
        btn._loaded = true
        btn._notEnabled = false
        btn._dlIcon:Hide()
        if folder == activeModule then
            btn._label:SetTextColor(NAV_SELECTED_TEXT.r, NAV_SELECTED_TEXT.g, NAV_SELECTED_TEXT.b, NAV_SELECTED_TEXT.a)
            btn._icon:SetTexture(btn._iconOff)
            btn._icon:SetDesaturated(false)
            btn._icon:SetAlpha(NAV_SELECTED_ICON_A)
            btn._iconGlow:Show()
        else
            btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            btn._icon:SetTexture(btn._iconOff)
            btn._icon:SetDesaturated(false)
            btn._icon:SetAlpha(NAV_ENABLED_ICON_A)
            btn._iconGlow:Hide()
        end
        if not firstLoaded then firstLoaded = folder end
    end
    for _, info in ipairs(disabledList) do
        rowIndex = rowIndex + 1
        local folder = info.folder
        local btn = sidebarButtons[folder]
        if not btn then break end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, _sidebarAddonNavTop - (rowIndex - 1) * _sidebarNavRowH)
        btn._loaded = false
        btn._notEnabled = true
        btn._dlIcon:Hide()
        btn._label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
        btn._icon:SetTexture(btn._iconOff)
        btn._icon:SetDesaturated(true)
        btn._icon:SetAlpha(NAV_DISABLED_ICON_A)
        btn._iconGlow:Hide()
        btn._indicator:Hide()
        btn._glow:Hide()
        btn._glowTop:Hide()
        btn._glowBot:Hide()
    end
    -- Default to Global Settings if no module is active
    if not activeModule then
        activeModule = nil
        if modules["_EUIGlobal"] then
            EllesmereUI:SelectModule("_EUIGlobal")
        elseif firstLoaded and modules[firstLoaded] then
            EllesmereUI:SelectModule(firstLoaded)
        end
    end
end

-----------------------------------------------------------------------
--  Sidebar Unlock Mode tip  (one-time, shown on first panel open)
-----------------------------------------------------------------------
local _sidebarUnlockTip
local function ShowSidebarUnlockTip()
    if EllesmereUIDB and EllesmereUIDB.sidebarUnlockTipSeen then return end
    if _sidebarUnlockTip and _sidebarUnlockTip:IsShown() then return end
    local anchor = EllesmereUI._unlockSidebarBtn
    if not anchor then return end

    if not _sidebarUnlockTip then
        local TIP_W, TIP_H = 320, 100
        local EG = ELLESMERE_GREEN
        local ar, ag, ab = EG.r, EG.g, EG.b

        local tip = CreateFrame("Frame", nil, mainFrame)
        tip:SetFrameStrata("FULLSCREEN_DIALOG")
        tip:SetFrameLevel(200)
        PanelPP.Size(tip, TIP_W, TIP_H)
        tip:EnableMouse(true)

        -- Center horizontally on the Unlock Mode label text
        local lbl = anchor._label
        if lbl then
            tip:SetPoint("TOP", lbl, "BOTTOM", 0, -12)
        else
            tip:SetPoint("TOP", anchor, "BOTTOM", 60, -12)
        end

        -- Background
        local bg = SolidTex(tip, "BACKGROUND", 0.06, 0.08, 0.10, 1)
        bg:SetAllPoints()

        -- Border (pixel-perfect via PanelPP)
        MakeBorder(tip, ar, ag, ab, 0.25, PanelPP)

        -- Arrow pointing up (clipped diamond)
        local ARROW_SZ = 16
        local arrowClip = CreateFrame("Frame", nil, tip)
        arrowClip:SetFrameStrata("FULLSCREEN_DIALOG")
        arrowClip:SetFrameLevel(tip:GetFrameLevel() + 10)
        arrowClip:SetClipsChildren(true)
        local clipH = ARROW_SZ
        arrowClip:SetSize(ARROW_SZ * 2, clipH)
        arrowClip:SetPoint("BOTTOM", tip, "TOP", 0, -1)

        local arrowFrame = CreateFrame("Frame", nil, arrowClip)
        arrowFrame:SetFrameLevel(arrowClip:GetFrameLevel() + 1)
        arrowFrame:SetSize(ARROW_SZ + 4, ARROW_SZ + 4)
        arrowFrame:SetPoint("CENTER", arrowClip, "BOTTOM", 0, 0)

        local arrowBorder = arrowFrame:CreateTexture(nil, "ARTWORK", nil, 7)
        arrowBorder:SetSize(ARROW_SZ + 2, ARROW_SZ + 2)
        arrowBorder:SetPoint("CENTER")
        arrowBorder:SetColorTexture(ar, ag, ab, 0.18)
        arrowBorder:SetRotation(math.rad(45))
        if arrowBorder.SetSnapToPixelGrid then arrowBorder:SetSnapToPixelGrid(false); arrowBorder:SetTexelSnappingBias(0) end

        local arrowFill = arrowFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        arrowFill:SetSize(ARROW_SZ, ARROW_SZ)
        arrowFill:SetPoint("CENTER")
        arrowFill:SetColorTexture(0.06, 0.08, 0.10, 1)
        arrowFill:SetRotation(math.rad(45))
        if arrowFill.SetSnapToPixelGrid then arrowFill:SetSnapToPixelGrid(false); arrowFill:SetTexelSnappingBias(0) end

        -- Message
        local msg = MakeFont(tip, 12, nil, 1, 1, 1, 0.85)
        msg:SetPoint("TOP", tip, "TOP", 0, -17)
        msg:SetWidth(TIP_W - 30)
        msg:SetJustifyH("CENTER")
        msg:SetSpacing(6)
        msg:SetText("Unlock Mode is where you can adjust\npositioning for all the elements of EllesmereUI")

        -- Okay button
        local okBtn = CreateFrame("Button", nil, tip)
        okBtn:SetSize(86, 26)
        okBtn:SetPoint("BOTTOM", tip, "BOTTOM", 0, 13)
        EllesmereUI.MakeStyledButton(okBtn, "Okay", 11,
            EllesmereUI.RB_COLOURS, function()
                tip:Hide()
                if EllesmereUIDB then EllesmereUIDB.sidebarUnlockTipSeen = true end
            end)

        _sidebarUnlockTip = tip
    end

    _sidebarUnlockTip:SetAlpha(0)
    _sidebarUnlockTip:Show()

    local fadeIn = 0
    _sidebarUnlockTip:SetScript("OnUpdate", function(self, dt)
        fadeIn = fadeIn + dt
        if fadeIn >= 0.3 then
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
            return
        end
        self:SetAlpha(fadeIn / 0.3)
    end)
end

function EllesmereUI:Show()
    self:EnsureLoaded()
    CreateMainFrame()
    RefreshSidebarStates()
    mainFrame:Show()
    ShowSidebarUnlockTip()
end
function EllesmereUI:Hide()   if mainFrame then mainFrame:Hide() end end
function EllesmereUI:Toggle()
    self:EnsureLoaded()
    CreateMainFrame()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        RefreshSidebarStates()
        mainFrame:Show()
        ShowSidebarUnlockTip()
    end
end
function EllesmereUI:IsShown() return mainFrame and mainFrame:IsShown() end
function EllesmereUI:GetScrollFrame() return scrollFrame end
function EllesmereUI:GetActivePage() return activePage end

--- Apply a user-defined panel scale on top of the pixel-perfect base scale.
--- @param userScale number  multiplier (1.0 = default, 0.5–1.5 range)
do
    local scaleAnimFrame = CreateFrame("Frame")
    local scaleFrom, scaleTo, scaleElapsed
    local SCALE_DUR = 0.10
    local isAnimating = false

    local function OnScaleUpdate(self, dt)
        scaleElapsed = scaleElapsed + dt
        local t = math.min(1, scaleElapsed / SCALE_DUR)
        local ease = t * (2 - t)  -- ease-out quad
        local cur = scaleFrom + (scaleTo - scaleFrom) * ease
        if mainFrame then mainFrame:SetScale(cur) end
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            isAnimating = false
            if mainFrame then mainFrame:SetScale(scaleTo) end
            if EllesmereUI._onScaleChanged then
                for _, fn in ipairs(EllesmereUI._onScaleChanged) do fn() end
            end
        end
    end

    function EllesmereUI:SetPanelScale(userScale)
        if not mainFrame then return end
        local physW = (GetPhysicalScreenSize())
        local baseScale = GetScreenWidth() / physW
        local targetScale = baseScale * (userScale or 1.0)
        if EllesmereUIDB then EllesmereUIDB.panelScale = userScale end
        -- Recalculate PanelPP mult for the new scale
        if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end
        if isAnimating then
            -- Already animating: just redirect the target without restarting.
            scaleTo = targetScale
        else
            scaleFrom = mainFrame:GetScale()
            scaleTo = targetScale
            scaleElapsed = 0
            isAnimating = true
            scaleAnimFrame:SetScript("OnUpdate", OnScaleUpdate)
        end
    end
end

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
EllesmereUI.VERSION = "4.3.5"

-- Register this addon's version into a shared global table (taint-free at load time)
if not _G._EUI_AddonVersions then _G._EUI_AddonVersions = {} end
_G._EUI_AddonVersions[EUI_HOST_ADDON] = EllesmereUI.VERSION

-- One-time welcome message (shared across all Ellesmere addons)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if _G._EUI_WelcomePrinted then return end
        _G._EUI_WelcomePrinted = true
        local v = EllesmereUI.VERSION or "1.0"
        print("|cff0cd29fEllesmereUI|r v" .. v .. " loaded. Type |cff0cd29f/eui|r for settings, and |cff0cd29f/unlock|r for Unlock Mode.")

        -- Version mismatch check across all Ellesmere addons
        -- Uses the pre-registered _EUI_AddonVersions table (taint-free)
        if not _G._EUI_VersionChecked then
            _G._EUI_VersionChecked = true
            C_Timer.After(2, function()
                local versions = _G._EUI_AddonVersions
                if not versions then return end
                local loaded = {}
                for name, ver in pairs(versions) do
                    loaded[#loaded + 1] = { name = name, version = ver }
                end
                if #loaded < 2 then return end
                -- Find the newest version
                local newest = loaded[1].version
                for i = 2, #loaded do
                    if loaded[i].version > newest then newest = loaded[i].version end
                end
                -- Collect addons that are behind
                local outdated = {}
                for _, info in ipairs(loaded) do
                    if info.version ~= newest then
                        outdated[#outdated + 1] = info.name
                    end
                end
                if #outdated == 0 then return end
                local msg = "The following EllesmereUI addons are out of date. "
                    .. "Please update so all addons are the same version:\n\n"
                    .. table.concat(outdated, ", ")
                if EllesmereUI.ShowConfirmPopup then
                    EllesmereUI:ShowConfirmPopup({
                        title       = "Out of Date",
                        message     = msg,
                        confirmText = "OK",
                    })
                else
                    print("|cffff6060[EllesmereUI] WARNING:|r " .. msg:gsub("\n", " "))
                end
            end)
        end

    end)
end

--------------------------------------------------------------------------------
--  Global Incompatible Addon Detection
--  Runs once per session. Non-ElvUI conflicts always show. ElvUI is a
--  one-off warning: once dismissed while it is the ONLY conflict, it is
--  suppressed forever. If other conflicts are also present, ElvUI shows too
--  and the one-off flag is not consumed.
--------------------------------------------------------------------------------
if not _G._EUI_ConflictChecked then
    _G._EUI_ConflictChecked = true
    C_Timer.After(2, function()
        local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        if not IsLoaded then return end

        -- conflict list: { addon, label, targets, message }
        -- targets = "all" or a table of Ellesmere folder names
        -- message = optional custom popup message override
        local conflicts = {
            { addon = "ElvUI",                    label = "ElvUI",                      targets = "all",                              message = "Many of ElvUI's modules are incompatible with EllesmereUI. Make sure to disable any conflicting modules." },
            { addon = "Bartender4",               label = "Bartender4",                 targets = { "EllesmereUIActionBars" } },
            { addon = "Dominos",                  label = "Dominos",                    targets = { "EllesmereUIActionBars" } },
            { addon = "UnhaltedUnitFrames",       label = "Unhalted Unit Frames",       targets = { "EllesmereUIUnitFrames" } },
            { addon = "Platynator",               label = "Platynator",                 targets = { "EllesmereUINameplates" } },
            { addon = "Plater",                   label = "Plater Nameplates",          targets = { "EllesmereUINameplates" } },
            { addon = "Kui_Nameplates",            label = "KUI Nameplates",             targets = { "EllesmereUINameplates" } },
            { addon = "SenseiClassResourceBar",   label = "Sensei Class Resource Bar",  targets = { "EllesmereUIResourceBars" } },
            { addon = "FriendGroups",             label = "FriendGroups",               targets = { "EllesmereUIBasics" } },
            { addon = "UltimateMouseCursor",      label = "Ultimate Mouse Cursor",      targets = { "EllesmereUICursor" } },
            { addon = "BetterCooldownManager",    label = "Better Cooldown Manager",    targets = { "EllesmereUICooldownManager" } },
            { addon = "ArcUI",                    label = "ArcUI",                      targets = { "EllesmereUICooldownManager" } },
            { addon = "Ayije_CDM",                label = "Ayije CDM",                  targets = { "EllesmereUICooldownManager" } },
        }

        local exempt = { EllesmereUIPartyMode = true }

        if not EllesmereUIDB then EllesmereUIDB = {} end
        if not EllesmereUIDB.dismissedConflicts then EllesmereUIDB.dismissedConflicts = {} end
        local dismissed = EllesmereUIDB.dismissedConflicts

        -- Collect all active conflicts.
        -- ElvUI is filtered out if it has been permanently dismissed AND it
        -- would be the only conflict showing (i.e. no other conflicts exist).
        local pending = {}
        for _, entry in ipairs(conflicts) do
            if entry.addon ~= EUI_HOST_ADDON and IsLoaded(entry.addon) then
                local affected = {}
                if entry.targets == "all" then
                    local allTargets = {
                        "EllesmereUIActionBars", "EllesmereUIUnitFrames", "EllesmereUINameplates",
                        "EllesmereUIResourceBars", "EllesmereUIAuraBuffReminders", "EllesmereUICooldownManager",
                        "EllesmereUICursor", "EllesmereUIBasics", "EllesmereUIRaidFrames",
                    }
                    for _, name in ipairs(allTargets) do
                        if not exempt[name] and IsLoaded(name) then
                            affected[#affected + 1] = name
                        end
                    end
                else
                    for _, t in ipairs(entry.targets) do
                        if IsLoaded(t) then
                            affected[#affected + 1] = t
                        end
                    end
                end
                if #affected > 0 then
                    pending[#pending + 1] = { entry = entry, affected = affected }
                end
            end
        end

        -- If ElvUI is the ONLY conflict and it has been dismissed, suppress it.
        if #pending == 1 and pending[1].entry.addon == "ElvUI" and dismissed["ElvUI"] then
            return
        end

        -- Show one popup at a time.
        -- Non-ElvUI: never permanently dismissed (always shows next session).
        -- ElvUI: permanently dismissed only when it was the sole conflict.
        local pendingIndex = 0
        local function ShowNextConflict()
            pendingIndex = pendingIndex + 1
            local item = pending[pendingIndex]
            if not item then return end
            local entry, affected = item.entry, item.affected
            local names = {}
            for _, a in ipairs(affected) do
                names[#names + 1] = a:gsub("^EllesmereUI", "")
            end
            local msg = entry.message or (
                entry.label .. " is not compatible with EllesmereUI " .. table.concat(names, ", ")
                .. ". Running both at the same time may cause errors or unexpected behavior."
                .. "\n\nPlease disable one of them."
            )
            local function onDismiss()
                -- Only permanently dismiss ElvUI, and only when it is the sole conflict
                if entry.addon == "ElvUI" and #pending == 1 then
                    dismissed["ElvUI"] = true
                end
                ShowNextConflict()
            end
            if EllesmereUI.ShowConfirmPopup then
                EllesmereUI:ShowConfirmPopup({
                    title       = "Incompatible Addon Detected",
                    message     = msg,
                    confirmText = "Okay",
                    cancelText  = "Don't show again",
                    onConfirm   = onDismiss,
                    onCancel    = onDismiss,
                })
            else
                print("|cffff6060[EllesmereUI]|r " .. msg:gsub("\n", " "))
                ShowNextConflict()
            end
        end
        ShowNextConflict()
    end)
end

SLASH_EUIOPTIONS1 = "/eui"
SLASH_EUIOPTIONS2 = "/ellesmere"
SLASH_EUIOPTIONS3 = "/ellesmereui"
SlashCmdList.EUIOPTIONS = function()
    if InCombatLockdown() then
        print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
        return
    end
    EllesmereUI:Toggle()
end

-- Quick-access: /ee opens global settings
SLASH_EUIQUICK1 = "/ee"
SlashCmdList.EUIQUICK = function()
    if InCombatLockdown() then
        print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
        return
    end
    EllesmereUI:Toggle()
end

-- Quick-access: /epm opens directly to Party Mode settings
SLASH_EUIPARTYMODE1 = "/epm"
SlashCmdList.EUIPARTYMODE = function()
    if InCombatLockdown() then
        print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
        return
    end
    EllesmereUI:ShowModule("EllesmereUIPartyMode")
end

-- Toggle party mode on/off
SLASH_PARTYMODETOGGLE1 = "/partymode"
SlashCmdList.PARTYMODETOGGLE = function()
    if EllesmereUI_TogglePartyMode then
        EllesmereUI_TogglePartyMode()
    else
        print("|cffff6060[EllesmereUI]|r Party Mode addon is not loaded.")
    end
end

-- Debug: reset preview hint dismissed flag
SLASH_EUIRESETHINT1 = "/euiresethint"

-- Quick-access: /unlock opens Unlock Mode directly
SLASH_EUIUNLOCK1 = "/unlock"
SlashCmdList.EUIUNLOCK = function()
    if InCombatLockdown() then
        print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
        return
    end
    EllesmereUI:EnsureLoaded()
    if EllesmereUI._openUnlockMode then
        EllesmereUI._openUnlockMode()
    else
        print("|cffff6060[EllesmereUI]|r Unlock Mode is not available.")
    end
end

SlashCmdList.EUIRESETHINT = function()
    if EllesmereUIDB then
        EllesmereUIDB.previewHintDismissed = nil
        EllesmereUIDB.unlockTipSeen = nil
        EllesmereUIDB.sidebarUnlockTipSeen = nil
    end
    print("|cff00ff00[EllesmereUI]|r All hints reset. /reload to see them again.")
end

-- Debug: wipe saved UI scale so next reload re-snapshots from Blizzard default
SLASH_EUIRESETSCALE1 = "/euiresetscale"
SlashCmdList.EUIRESETSCALE = function()
    if EllesmereUIDB then
        EllesmereUIDB.ppUIScale = nil
        EllesmereUIDB.ppUIScaleAuto = nil
        EllesmereUIDB.blizzUIScale = nil
    end
    print("|cff00ff00[EllesmereUI]|r UI scale reset. /reload to re-snapshot from your Blizzard scale.")
end

-- Open the panel with a specific addon's tab selected
function EllesmereUI:ShowModule(folderName)
    if InCombatLockdown() then
        print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
        return
    end
    self:EnsureLoaded()
    CreateMainFrame()
    RefreshSidebarStates()
    mainFrame:Show()
    ShowSidebarUnlockTip()
    if modules[folderName] then
        self:SelectModule(folderName)
    end
end

-------------------------------------------------------------------------------
--  Streamer Settings: Guild Chat Privacy
-------------------------------------------------------------------------------
do
    local overlay
    local function ShowOverlay()
        if not overlay then return end
        if not (EllesmereUIDB and EllesmereUIDB.guildChatPrivacy) then return end
        local cf = CommunitiesFrame
        if not cf or not cf.Chat or not cf.Chat.MessageFrame then return end
        local mf = cf.Chat.MessageFrame
        overlay:SetParent(mf)
        overlay:SetAllPoints(mf)
        overlay:SetFrameLevel(mf:GetFrameLevel() + 20)
        overlay:Show()
    end

    local function ApplyGuildChatPrivacy()
        local enabled = EllesmereUIDB and EllesmereUIDB.guildChatPrivacy
        if not enabled then
            if overlay then overlay:Hide() end
            return
        end

        if not overlay then
            overlay = CreateFrame("Button", nil, UIParent)
            overlay:SetFrameStrata("DIALOG")
            local bg = overlay:CreateTexture(nil, "BACKGROUND")
            bg:SetPoint("TOPLEFT", -2, 0)
            bg:SetPoint("BOTTOMRIGHT", 2, -4)
            bg:SetColorTexture(0.133, 0.133, 0.133, 1) -- #222, 100%
            local txt = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            txt:SetPoint("CENTER")
            txt:SetText("Click to Show")
            txt:SetTextColor(0.7, 0.7, 0.7, 1)
            overlay:SetScript("OnClick", function(self)
                self:Hide()
            end)
        end

        -- CommunitiesFrame is load-on-demand; hook when it becomes available
        if CommunitiesFrame then
            ShowOverlay()
            if not overlay._hooked then
                CommunitiesFrame:HookScript("OnShow", ShowOverlay)
                overlay._hooked = true
            end
        else
            -- Wait for the addon to load
            local loader = CreateFrame("Frame")
            loader:RegisterEvent("ADDON_LOADED")
            loader:SetScript("OnEvent", function(self, _, addon)
                if addon == "Blizzard_Communities" then
                    self:UnregisterAllEvents()
                    if EllesmereUIDB and EllesmereUIDB.guildChatPrivacy then
                        ShowOverlay()
                        if not overlay._hooked then
                            CommunitiesFrame:HookScript("OnShow", ShowOverlay)
                            overlay._hooked = true
                        end
                    end
                end
            end)
        end
    end
    EllesmereUI._applyGuildChatPrivacy = ApplyGuildChatPrivacy
end

-------------------------------------------------------------------------------
--  Streamer Settings: Secondary Stats Display
-------------------------------------------------------------------------------
do
    local statsFrame, statsText
    local format = string.format

    local function UpdateSecondaryStats()
        if not statsFrame or not statsFrame:IsShown() then return end
        -- Cache class color (used as fallback for both secondary and tertiary)
        if not statsFrame._classHex then
            local _, cls = UnitClass("player")
            local cc = cls and EllesmereUI.GetClassColor(cls)
            if cc then
                statsFrame._classR, statsFrame._classG, statsFrame._classB = cc.r, cc.g, cc.b
                statsFrame._classHex = format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
            else
                statsFrame._classR, statsFrame._classG, statsFrame._classB = 1, 1, 1
                statsFrame._classHex = "ffffff"
            end
        end
        -- Secondary label color (defaults to class color)
        local c = EllesmereUIDB and EllesmereUIDB.secondaryStatsColor
        local cr, cg, cb
        if c then
            cr, cg, cb = c.r, c.g, c.b
        else
            cr, cg, cb = statsFrame._classR, statsFrame._classG, statsFrame._classB
        end
        local labelHex = c and format("%02x%02x%02x", cr * 255, cg * 255, cb * 255) or statsFrame._classHex

        local crit = GetCritChance()
        local haste = GetHaste()
        local mastery = GetMasteryEffect()
        local vers = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
                    + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)

        local txt =
            format("|cff%sCrit:|r  |cffffffff%.2f%%|r", labelHex, crit) .. "\n" ..
            format("|cff%sHaste:|r  |cffffffff%.2f%%|r", labelHex, haste) .. "\n" ..
            format("|cff%sMastery:|r  |cffffffff%.2f%%|r", labelHex, mastery) .. "\n" ..
            format("|cff%sVers:|r  |cffffffff%.2f%%|r", labelHex, vers)

        if EllesmereUIDB and EllesmereUIDB.showTertiaryStats then
            -- Tertiary label color (defaults to class color)
            local tc = EllesmereUIDB.tertiaryStatsColor
            local tr, tg, tb
            if tc then
                tr, tg, tb = tc.r, tc.g, tc.b
            else
                tr, tg, tb = statsFrame._classR, statsFrame._classG, statsFrame._classB
            end
            local tertHex = tc and format("%02x%02x%02x", tr * 255, tg * 255, tb * 255) or statsFrame._classHex

            local leech = GetLifesteal()
            local avoidance = GetAvoidance()
            local speed = GetSpeed()
            txt = txt .. "\n" ..
                format("|cff%sLeech:|r  |cffffffff%.2f%%|r", tertHex, leech) .. "\n" ..
                format("|cff%sAvoidance:|r  |cffffffff%.2f%%|r", tertHex, avoidance) .. "\n" ..
                format("|cff%sSpeed:|r  |cffffffff%.2f%%|r", tertHex, speed)
        end

        statsText:SetText(txt)
    end

    local function ApplySecondaryStats()
        local enabled = EllesmereUIDB and EllesmereUIDB.showSecondaryStats
        if not enabled then
            if statsFrame then
                statsFrame:Hide()
                statsFrame:UnregisterAllEvents()
            end
            return
        end
        if not statsFrame then
            statsFrame = CreateFrame("Frame", "EUI_SecondaryStats", UIParent)
            statsFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -12)
            statsFrame:SetSize(160, 60)
            statsFrame:SetFrameStrata("LOW")
            statsText = statsFrame:CreateFontString(nil, "OVERLAY")
            local font = EllesmereUI.ResolveFontName(EllesmereUI.GetFontsDB().global)
            statsText:SetFont(font, 12, EllesmereUI.GetFontOutlineFlag())
            statsText:SetPoint("TOPLEFT")
            statsText:SetJustifyH("LEFT")
        end
        -- Apply saved position and scale
        local pos = EllesmereUIDB and EllesmereUIDB.secondaryStatsPos
        if pos then
            if pos.scale then pcall(function() statsFrame:SetScale(pos.scale) end) end
            if pos.point then
                statsFrame:ClearAllPoints()
                statsFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
            end
        end
        statsFrame:RegisterUnitEvent("UNIT_STATS", "player")
        statsFrame:RegisterEvent("COMBAT_RATING_UPDATE")
        statsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        statsFrame:SetScript("OnEvent", function()
            UpdateSecondaryStats()
        end)
        statsFrame:Show()
        UpdateSecondaryStats()
    end
    EllesmereUI._applySecondaryStats = ApplySecondaryStats

    -- Expose frame getter for unlock mode
    EllesmereUI._getSecondaryStatsFrame = function()
        if not statsFrame then
            ApplySecondaryStats()
        end
        return statsFrame
    end
end

-------------------------------------------------------------------------------
--  Native Minimap Button (no library dependencies)
-------------------------------------------------------------------------------
do
    local ICON_PATH = "Interface\\AddOns\\EllesmereUI\\media\\eg-logo.tga"
    local BUTTON_SIZE = 32
    local btn
    local currentAngle

    local function GetAngle()
        if currentAngle then return currentAngle end
        currentAngle = (EllesmereUIDB and EllesmereUIDB.minimapButtonAngle) or 220
        return currentAngle
    end

    local function SaveAngle()
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.minimapButtonAngle = currentAngle
    end

    local function UpdatePosition()
        if not btn then return end
        local angle = math.rad(GetAngle())
        local mw, mh = Minimap:GetWidth(), Minimap:GetHeight()
        local radius = (math.max(mw, mh) / 2) + 5
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end

    -- Persistent OnUpdate handler for drag (avoids closure creation per drag)
    local function DragOnUpdate()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        currentAngle = math.deg(math.atan2(cy - my, cx - mx))
        UpdatePosition()
    end

    function EllesmereUI.CreateMinimapButton()
        if btn then return btn end

        btn = CreateFrame("Button", "EllesmereUIMinimapButton", Minimap)
        btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        btn:SetFrameStrata("MEDIUM")
        btn:SetFrameLevel(8)
        btn:SetClampedToScreen(true)
        btn:SetMovable(true)
        btn:RegisterForClicks("anyUp")
        btn:RegisterForDrag("LeftButton")

        -- Background fill (black circle behind the icon)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(25, 25)
        bg:SetPoint("CENTER", 0, 0)
        bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        bg:SetVertexColor(0, 0, 0, 1)

        -- Icon
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(17, 17)
        icon:SetPoint("CENTER", 0, 0)
        icon:SetTexture(ICON_PATH)

        -- Border overlay (standard minimap button look)
        local overlay = btn:CreateTexture(nil, "OVERLAY")
        overlay:SetSize(53, 53)
        overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

        -- Highlight (circular, not square)
        btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

        -- Click handler (only fires when mouse-up without drag)
        local isDragging = false
        btn:SetScript("OnClick", function(_, button)
            if InCombatLockdown() then return end
            if button == "LeftButton" then
                if EllesmereUI then EllesmereUI:Toggle() end
            elseif button == "RightButton" then
                if EllesmereUI then EllesmereUI:EnsureLoaded() end
                if EllesmereUI and EllesmereUI._openUnlockMode then
                    EllesmereUI._openUnlockMode()
                end
            elseif button == "MiddleButton" then
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.showMinimapButton = false
                btn:Hide()
                local rl = EllesmereUI and EllesmereUI._widgetRefreshList
                if rl then for i = 1, #rl do rl[i]() end end
            end
        end)

        -- Drag handlers (left-drag repositions around minimap)
        btn:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            isDragging = true
            self:LockHighlight()
            self:SetScript("OnUpdate", DragOnUpdate)
            GameTooltip:Hide()
        end)

        btn:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            self:UnlockHighlight()
            isDragging = false
            SaveAngle()
            UpdatePosition()
        end)

        -- Tooltip
        btn:SetScript("OnEnter", function(self)
            if isDragging or InCombatLockdown() then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("|cff0cd29fEllesmereUI|r")
            GameTooltip:AddLine("|cff0cd29dLeft-click:|r |cffE0E0E0Toggle EllesmereUI|r")
            GameTooltip:AddLine("|cff0cd29dRight-click:|r |cffE0E0E0Enter Unlock Mode|r")
            GameTooltip:AddLine("|cff0cd29dMiddle-click:|r |cffE0E0E0Hide Minimap Button|r")
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        UpdatePosition()

        -- Respect saved visibility
        if EllesmereUIDB and EllesmereUIDB.showMinimapButton == false then
            btn:Hide()
        else
            btn:Show()
        end

        _EllesmereUI_MinimapRegistered = true
        return btn
    end

    function EllesmereUI.ShowMinimapButton()
        if not btn then EllesmereUI.CreateMinimapButton() end
        if btn then btn:Show() end
    end

    function EllesmereUI.HideMinimapButton()
        if btn then btn:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Init  +  Demo Modules  (temporary placeholder content)
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if mainFrame and mainFrame:IsShown() then
            EllesmereUI:Hide()
            print("|cffff6060[EllesmereUI]|r Options closed -- entering combat.")
        end
        return
    end

    -- PLAYER_LOGIN: register demo modules (UI is built lazily on first open)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Create native minimap button
    EllesmereUI.CreateMinimapButton()

    -- Apply streamer settings
    if EllesmereUI._applyGuildChatPrivacy then EllesmereUI._applyGuildChatPrivacy() end
    if EllesmereUI._applySecondaryStats then EllesmereUI._applySecondaryStats() end

    -- Re-read theme settings from SavedVariables (belt-and-suspenders for persistence)
    if EllesmereUIDB then
        -- Migrate legacy keys to new activeTheme model
        if EllesmereUIDB.activeTheme == nil then
            if EllesmereUIDB.customThemeEnabled then
                if EllesmereUIDB.classColoredTheme then
                    EllesmereUIDB.activeTheme = "Class Colored"
                elseif EllesmereUIDB.accentColor then
                    EllesmereUIDB.activeTheme = "Custom Color"
                else
                    EllesmereUIDB.activeTheme = "EllesmereUI"
                end
            end
            -- Clean up legacy keys
            EllesmereUIDB.customThemeEnabled = nil
            EllesmereUIDB.classColoredTheme  = nil
        end
        local theme = EllesmereUIDB.activeTheme or "EllesmereUI"
        ELLESMERE_GREEN._themeEnabled = true
        local r, g, b = EllesmereUI.ResolveThemeColor(theme)
        ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = r, g, b
    end

    -- Spell ID + Icon ID on Tooltip (developer option)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        -- Register per-type callbacks instead of AllTypes to avoid firing on
        -- every item/unit/currency tooltip in the game (major CPU savings).
        local function SpellIDTooltipHook(tooltip, data)
            if not (EllesmereUIDB and EllesmereUIDB.showSpellID) then return end
            if not data or not data.id then return end
            if not tooltip or not tooltip.GetName then return end
            -- Avoid duplicate lines
            local ok, name = pcall(tooltip.GetName, tooltip)
            if not ok or not name then return end
            if name then
                for i = tooltip:NumLines(), 1, -1 do
                    local fs = _G[name .. "TextLeft" .. i]
                    if fs then
                        local txt = fs:GetText()
                        if txt and (not issecretvalue or not issecretvalue(txt)) and txt:find("SpellID") then return end
                    end
                end
            end
            tooltip:AddDoubleLine("SpellID", tostring(data.id), 1, 1, 1, 1, 1, 1)
            local iconID = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(data.id)
                or (GetSpellTexture and GetSpellTexture(data.id))
            if iconID then
                tooltip:AddDoubleLine("IconID", tostring(iconID), 1, 1, 1, 1, 1, 1)
            end
            tooltip:Show()
        end
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, SpellIDTooltipHook)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, SpellIDTooltipHook)
        if Enum.TooltipDataType.PetAction then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.PetAction, SpellIDTooltipHook)
        end
    end

    -- Consolidated Blizzard AddOns > Options panel (single entry for all Ellesmere addons)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local panel = CreateFrame("Frame")
        panel.name = "EllesmereUI"
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(200, 30)
        btn:SetPoint("CENTER", panel, "CENTER", 0, 0)
        btn:SetText("Open EllesmereUI")
        btn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            -- Close Blizzard settings first, then open ours on next frame to avoid taint
            if SettingsPanel and SettingsPanel:IsShown() then
                HideUIPanel(SettingsPanel)
            end
            C_Timer.After(0, function()
                if EllesmereUI then EllesmereUI:Show() end
            end)
        end)
        local category = Settings.RegisterCanvasLayoutCategory(panel, "EllesmereUI")
        Settings.RegisterAddOnCategory(category)
    end

    local dT, dS, dD = {}, {}, {}
    local demoConfigs = {
        -- Only list addons that do NOT have their own EUI_*_Options.lua yet.
        -- Addons with real options files register via PLAYER_LOGIN and must NOT
        -- appear here — the demo would race and win due to page caching.
        { folder = "EllesmereBeaconReminder",     title = "Beacon Reminders", desc = "Configure alerts for missing Beacon of Light or Faith.",  pages = { "General", "Alerts" } },
        { folder = "EllesmereConsumablesTracker", title = "Consumables",      desc = "Track consumables and raid buffs for instanced content.", pages = { "General", "Tracking" } },
    }

    for _, cfg in ipairs(demoConfigs) do
        if IsAddonLoaded(cfg.folder) and not modules[cfg.folder] then
            local k = cfg.folder
            dT[k] = { opt1 = true, opt2 = false, opt3 = true, opt4 = false, opt5 = true, opt6 = false, opt7 = true }
            dS[k] = { size = 36, font = 14, opacity = 80, spacing = 4, scale = 100, thickness = 2 }
            dD[k] = { effect = "pulse", position = "center", style = "modern" }
            local dC = { showInRaid = true, showInDungeon = true, showInArena = false, showInBG = false, showInWorld = true, showWhileMounted = false }

            EllesmereUI:RegisterModule(cfg.folder, {
                title       = cfg.title,
                description = cfg.desc,
                pages       = cfg.pages,
                buildPage   = function(pageName, parent, yOffset)
                    local W = EllesmereUI.Widgets
                    local y = yOffset
                    local _, h

                    _, h = W:SectionHeader(parent, "APPEARANCE", y);                                     y = y - h
                    _, h = W:Toggle(parent, "Enable Modern Styling", y,
                        function() return dT[k].opt1 end,
                        function(v) dT[k].opt1 = v end);                                                 y = y - h
                    _, h = W:Slider(parent, "Icon Size", y, 16, 64, 1,
                        function() return dS[k].size end,
                        function(v) dS[k].size = v end);                                                 y = y - h
                    _, h = W:Dropdown(parent, "Proc Glow Effect", y,
                        { pulse = "Pulse", flash = "Flash", none = "None" },
                        function() return dD[k].effect end,
                        function(v) dD[k].effect = v end);                                               y = y - h
                    _, h = W:Toggle(parent, "Show Border", y,
                        function() return dT[k].opt3 end,
                        function(v) dT[k].opt3 = v end);                                                 y = y - h
                    _, h = W:Slider(parent, "Border Opacity", y, 0, 100, 5,
                        function() return dS[k].opacity end,
                        function(v) dS[k].opacity = v end);                                              y = y - h
                    _, h = W:Spacer(parent, y, 20);                                                       y = y - h

                    _, h = W:SectionHeader(parent, "KEY BINDING TEXT", y);                                y = y - h
                    _, h = W:Toggle(parent, "Show Keybind Text", y,
                        function() return dT[k].opt2 end,
                        function(v) dT[k].opt2 = v end);                                                 y = y - h
                    _, h = W:Slider(parent, "Font Size", y, 8, 24, 1,
                        function() return dS[k].font end,
                        function(v) dS[k].font = v end);                                                 y = y - h
                    _, h = W:Dropdown(parent, "Text Position", y,
                        { center = "Center", topleft = "Top Left", topright = "Top Right", bottomright = "Bottom Right" },
                        function() return dD[k].position end,
                        function(v) dD[k].position = v end);                                             y = y - h
                    _, h = W:Toggle(parent, "Abbreviate Text", y,
                        function() return dT[k].opt4 end,
                        function(v) dT[k].opt4 = v end);                                                 y = y - h
                    _, h = W:Spacer(parent, y, 20);                                                       y = y - h

                    _, h = W:SectionHeader(parent, "LAYOUT", y);                                          y = y - h
                    _, h = W:Slider(parent, "Button Spacing", y, 0, 12, 1,
                        function() return dS[k].spacing end,
                        function(v) dS[k].spacing = v end);                                              y = y - h
                    _, h = W:Slider(parent, "Global Scale", y, 50, 200, 5,
                        function() return dS[k].scale end,
                        function(v) dS[k].scale = v end);                                                y = y - h
                    _, h = W:Toggle(parent, "Lock Position", y,
                        function() return dT[k].opt5 end,
                        function(v) dT[k].opt5 = v end);                                                 y = y - h
                    _, h = W:Dropdown(parent, "Frame Style", y,
                        { modern = "Modern", classic = "Classic", minimal = "Minimal" },
                        function() return dD[k].style end,
                        function(v) dD[k].style = v end);                                                y = y - h
                    _, h = W:Toggle(parent, "Show in Combat", y,
                        function() return dT[k].opt6 end,
                        function(v) dT[k].opt6 = v end);                                                 y = y - h
                    _, h = W:Spacer(parent, y, 20);                                                       y = y - h

                    _, h = W:SectionHeader(parent, "ADVANCED", y);                                        y = y - h
                    _, h = W:Toggle(parent, "Enable Mouseover Mode", y,
                        function() return dT[k].opt7 end,
                        function(v) dT[k].opt7 = v end);                                                 y = y - h
                    _, h = W:Slider(parent, "Border Thickness", y, 1, 6, 1,
                        function() return dS[k].thickness end,
                        function(v) dS[k].thickness = v end);                                            y = y - h
                    _, h = W:Spacer(parent, y, 20);                                                       y = y - h

                    _, h = W:SectionHeader(parent, "VISIBILITY", y);                                      y = y - h
                    _, h = W:Checkbox(parent, "Show in Raids", y,
                        function() return dC.showInRaid end,
                        function(v) dC.showInRaid = v end);                                               y = y - h
                    _, h = W:Checkbox(parent, "Show in Dungeons", y,
                        function() return dC.showInDungeon end,
                        function(v) dC.showInDungeon = v end);                                            y = y - h
                    _, h = W:Checkbox(parent, "Show in Arena", y,
                        function() return dC.showInArena end,
                        function(v) dC.showInArena = v end);                                              y = y - h
                    _, h = W:Checkbox(parent, "Show in Battlegrounds", y,
                        function() return dC.showInBG end,
                        function(v) dC.showInBG = v end);                                                 y = y - h
                    _, h = W:Checkbox(parent, "Show in Open World", y,
                        function() return dC.showInWorld end,
                        function(v) dC.showInWorld = v end);                                              y = y - h
                    _, h = W:Checkbox(parent, "Show While Mounted", y,
                        function() return dC.showWhileMounted end,
                        function(v) dC.showWhileMounted = v end);                                         y = y - h

                    return math.abs(y)
                end,
                onReset = function()
                    dT[k] = { opt1 = true, opt2 = false, opt3 = true, opt4 = false, opt5 = true, opt6 = false, opt7 = true }
                    dS[k] = { size = 36, font = 14, opacity = 80, spacing = 4, scale = 100, thickness = 2 }
                    dD[k] = { effect = "pulse", position = "center", style = "modern" }
                    EllesmereUI:SelectPage(activePage)
                end,
            })
        end
    end
end)
