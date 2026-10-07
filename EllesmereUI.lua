if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI.lua  -  Custom Options Panel, shared across the whole EUI suite.
--  Scaffold: background, sidebar, header, content area, controls.
-------------------------------------------------------------------------------
-- EUI_NS is this addon's private namespace (the TOC vararg): shared by the core
-- files, unreachable from any other addon. Navigation state that must not be
-- writable by third-party code (module registry, sidebar model, page cache)
-- lives here instead of on the global EllesmereUI table.
local EUI_HOST_ADDON, EUI_NS = ...
-- Build renames "EllesmereUI" -> "EUICoreStandalone<Module>" but never the word
-- "Standalone", so host name contains it iff standalone; false in the suite (branches inert).
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
-- A standalone build is ONE addon: its module files share this vararg table
-- and publish it through _ModuleNS. So there the core's private state lives in
-- a table of its own, handed to the later core files through __euiCoreNS until
-- the first module publish removes that slot (see _ModuleNS).
if IS_STANDALONE then
    local shared = EUI_NS
    EUI_NS = {}
    shared.__euiCoreNS = EUI_NS
end
-------------------------------------------------------------------------------
--  Constants & Colours (BURNE STAY AWAY FROM THIS SECTION)
-------------------------------------------------------------------------------
--  Visual Settings  (edit these to adjust the look -- values only, no tables)
-------------------------------------------------------------------------------
-- Accent colour -- canonical default: #0CD29D teal. The Forever client opens
-- on #DCA77F (soft bronze) instead; a chosen accent always wins over this.
local DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B = 12/255, 210/255, 157/255
if EUI_CLIENT_FOREVER == true then
    DEFAULT_ACCENT_R, DEFAULT_ACCENT_G, DEFAULT_ACCENT_B = 220/255, 167/255, 127/255
end

-- Theme presets: { accentR, accentG, accentB, bgFile }
-- bgFile is relative to MEDIA_PATH (resolved later after MEDIA_PATH is defined)
local THEME_PRESETS = {
    ["EllesmereUI"]    = { r = 12/255,  g = 210/255, b = 157/255 },  -- #0CD29D
    ["EllesmereUI Original"] = { r = 12/255, g = 210/255, b = 157/255 },  -- #0CD29D
    ["EllesmereUI Forever"] = { r = 220/255, g = 167/255, b = 127/255 },  -- #DCA77F soft bronze
    ["Horde"]          = { r = 255/255, g = 90/255,  b = 31/255  },  -- #FF5A1F
    ["Alliance"]       = { r = 63/255,  g = 167/255, b = 255/255 },  -- #3FA7FF
    ["Faction (Auto)"] = nil,  -- resolved at runtime to Horde or Alliance
    ["Midnight"]       = { r = 120/255, g = 65/255,  b = 200/255 },  -- #7841C8  deep purple void
    ["Dark"]           = { r = 1,       g = 1,       b = 1       },  -- white accent
    ["Pixels"]         = { r = 1,       g = 1,       b = 1       },  -- white accent
    ["Class Colored"]  = nil,  -- resolved at runtime from player class
    ["Custom Color"]   = nil,  -- user-chosen via color picker
}
local THEME_ORDER = { "EllesmereUI", "EllesmereUI Original", "EllesmereUI Forever", "Horde", "Alliance", "Faction (Auto)", "Midnight", "Dark", "Pixels", "Class Colored", "Custom Color" }
-- The theme in force when none was chosen: the Forever client opens on its own
-- backdrop, every other client on the house one. A chosen theme always wins.
EllesmereUI.DEFAULT_THEME = (EUI_CLIENT_FOREVER == true) and "EllesmereUI Forever" or "EllesmereUI"
-- Background file paths per theme (relative to MEDIA_PATH, in backgrounds/ subfolder)
local THEME_BG_FILES = {
    ["EllesmereUI"]   = "backgrounds\\eui-bg-new.png",
    ["EllesmereUI Original"] = "backgrounds\\eui-bg-old.png",
    ["EllesmereUI Forever"] = "backgrounds\\eui-bg-forever-compressed.png",
    ["Horde"]         = "backgrounds\\eui-bg-horde-compressed.png",
    ["Alliance"]      = "backgrounds\\eui-bg-alliance-compressed.png",
    ["Midnight"]      = "backgrounds\\eui-bg-midnight-compressed.png",
    ["Dark"]          = "backgrounds\\eui-bg-dark-compressed.png",
    ["Pixels"]        = "backgrounds\\eui-bg-pixels-compressed.png",
    ["Class Colored"] = "backgrounds\\eui-bg-old.png",
    ["Custom Color"]  = "backgrounds\\eui-bg-old.png",
}
-- Theme art kept out of the file-load VRAM preload below (fields: the main chunk
-- sits at its local cap). It loads on its first pick (the crossfade starts the new
-- layer at alpha 0, so nothing flashes), or at PLAYER_LOGIN for the player whose
-- saved theme it is (EllesmereUI._PreloadLazyThemeBG).
EllesmereUI._THEME_BG_LAZY = { ["Pixels"] = true }
-- Accent overlay per theme: its accent-coloured pieces (logo mark, rules, close X)
-- as white art, cropped to their band of the 1500x1154 canvas (x, y = top-left
-- offset; w, h = size, all in canvas units). Drawn above the theme art and tinted
-- with the live UI accent; built on the theme's first apply (CreateMainFrame).
EllesmereUI.THEME_ACCENT_OVERLAYS = {
    ["Pixels"] = { file = "backgrounds\\eui-bg-pixels-accent.png", x = 102, y = 127, w = 1295, h = 110 },
}
-- The close box painted into each theme art file, in canvas units: x, y, w, h =
-- tight rect around its border; bx, by, bw, bh = outer rect of the border line
-- itself and bd = its depth (the hover glow lights only that ring); gx, gy =
-- centre of its X; gs = glyph size drawn over a copy (16 when absent); r, g, b =
-- the X colour; sh = alpha of the dark rim under a glyph; acc = alpha of a
-- live-accent glyph stacked on top (art whose X comes from its accent overlay);
-- ex, ey = top-left of the 76 unit square around the painted logo emblem; rr, rg,
-- rb = the logo badge ring colour. The collapse button and the collapsed mini
-- window rebuild their boxes and badge from these rects of the art on screen.
EllesmereUI.THEME_CLOSE_BOX = {
    ["backgrounds\\eui-bg-new.png"] = { x = 1346, y = 114, w = 43, h = 41, gx = 1368, gy = 134,
        bx = 1348, by = 116, bw = 40, bh = 38, bd = 3,
        r = 0.894, g = 0.788, b = 0.617, sh = 0.5, ex = 119, ey = 110, rr = 0.417, rg = 0.311, rb = 0.231 },
    ["backgrounds\\eui-bg-forever-compressed.png"] = { x = 1346, y = 114, w = 43, h = 41, gx = 1368, gy = 134,
        bx = 1348, by = 116, bw = 40, bh = 38, bd = 3,
        r = 0.894, g = 0.788, b = 0.617, sh = 0.5, ex = 122, ey = 109, rr = 0.417, rg = 0.311, rb = 0.231 },
    ["backgrounds\\eui-bg-old.png"] = { x = 1347, y = 117, w = 40, h = 39, gx = 1367, gy = 136,
        bx = 1348, by = 118, bw = 38, bh = 37, bd = 2,
        r = 0.685, g = 0.719, b = 0.715, sh = 0.5, ex = 118, ey = 110, rr = 0.324, rg = 0.345, rb = 0.363 },
    ["backgrounds\\eui-bg-midnight-compressed.png"] = { x = 1347, y = 117, w = 40, h = 39, gx = 1367, gy = 136,
        bx = 1348, by = 118, bw = 38, bh = 37, bd = 2,
        r = 0.738, g = 0.617, b = 0.834, sh = 0.5, ex = 118, ey = 110, rr = 0.335, rg = 0.296, rb = 0.440 },
    ["backgrounds\\eui-bg-dark-compressed.png"] = { x = 1347, y = 117, w = 40, h = 39, gx = 1367, gy = 136,
        bx = 1348, by = 118, bw = 38, bh = 37, bd = 2,
        r = 0.502, g = 0.502, b = 0.502, sh = 0.5, ex = 118, ey = 110, rr = 0.258, rg = 0.258, rb = 0.258 },
    ["backgrounds\\eui-bg-horde-compressed.png"] = { x = 1348, y = 116, w = 39, h = 40, gx = 1367, gy = 135,
        bx = 1349, by = 117, bw = 37, bh = 38, bd = 2, gs = 20,
        r = 0.467, g = 0.357, b = 0.323, sh = 0, ex = 118, ey = 110, rr = 0.354, rg = 0.225, rb = 0.182 },
    ["backgrounds\\eui-bg-alliance-compressed.png"] = { x = 1345, y = 115, w = 43, h = 43, gx = 1367, gy = 136,
        bx = 1347, by = 117, bw = 39, bh = 39, bd = 2, gs = 18,
        r = 1, g = 1, b = 1, sh = 0.5, ex = 118, ey = 110, rr = 0.323, rg = 0.377, rb = 0.483 },
    ["backgrounds\\eui-bg-pixels-compressed.png"] = { x = 1344, y = 115, w = 43, h = 42, gx = 1366, gy = 136,
        bx = 1346, by = 117, bw = 39, bh = 38, bd = 3, gs = 18,
        r = 0.604, g = 0.608, b = 0.604, sh = 0.9, acc = 0.70, ex = 105, ey = 110, rr = 0.371, rg = 0.363, rb = 0.374 },
}

--- Resolve "Faction (Auto)" to Horde/Alliance by player faction; other themes unchanged.
local function ResolveFactionTheme(theme)
    if theme == "Faction (Auto)" then
        local faction = UnitFactionGroup("player")
        return (faction == "Horde") and "Horde" or "Alliance"
    end
    return theme
end

-- Hidden 1x1 frame preloads bg textures into VRAM: no 1-frame bg flash on first open.
do
    local mp = "Interface\\AddOns\\EllesmereUI\\media\\"
    local preload = CreateFrame("Frame")
    preload:SetSize(1, 1)
    preload:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
    preload:Show()
    local lazy = EllesmereUI._THEME_BG_LAZY
    for theme, file in pairs(THEME_BG_FILES) do
        if not lazy[theme] then
            local tex = preload:CreateTexture()
            tex:SetTexture(mp .. file)
            tex:SetAllPoints()
        end
    end
    local baseTex = preload:CreateTexture()
    baseTex:SetTexture(mp .. "backgrounds\\eui-bg.png")
    baseTex:SetAllPoints()
    -- The saved theme is known only once SavedVariables load, so the PLAYER_LOGIN
    -- theme block calls this (once): a lazy theme's own player then opens the
    -- panel with its art, and its accent overlay, already resident.
    function EllesmereUI._PreloadLazyThemeBG(theme)
        if not lazy[theme] then return end
        local tex = preload:CreateTexture()
        tex:SetTexture(mp .. THEME_BG_FILES[theme])
        tex:SetAllPoints()
        local ov = EllesmereUI.THEME_ACCENT_OVERLAYS[theme]
        if ov then
            local ovTex = preload:CreateTexture()
            ovTex:SetTexture(mp .. ov.file)
            ovTex:SetAllPoints()
        end
    end
end

-- EllesmereUIDB arrives from SavedVariables at ADDON_LOADED. Do NOT create it here --
-- that overwrites saved data. (Stale child SV copy guard lives in EllesmereUI_Lite.lua.)

-- Widget style constants, one table instead of ~75 file-scope locals, which
-- would push this main chunk past Lua 5.1's 200-active-locals limit. Read them
-- as STYLE.X here; other files get them through the EllesmereUI.X exports below.
local STYLE = {
    -- The dark surfaces below (and the options' popups) share one faint warm
    -- tint, that of #100d0a, each at its own lightness.

    -- Panel background
    PANEL_BG_R = 0.069, PANEL_BG_G = 0.058, PANEL_BG_B = 0.047,

    -- Global border  (white + alpha -- adapts to any background tint)
    BORDER_R = 1, BORDER_G = 1, BORDER_B = 1,
    BORDER_A = 0.05,

    -- Text  (white + alpha -- adapts to any background tint)
    TEXT_WHITE_R = 1, TEXT_WHITE_G = 1, TEXT_WHITE_B = 1,
    TEXT_DIM_R = 1, TEXT_DIM_G = 1, TEXT_DIM_B = 1,
    TEXT_DIM_A = 0.53,
    TEXT_SECTION_R = 1, TEXT_SECTION_G = 1, TEXT_SECTION_B = 1,
    TEXT_SECTION_A = 0.41,

    -- Row alternating background alpha  (black overlay on option rows)
    ROW_BG_ODD = 0.1,
    ROW_BG_EVEN = 0.2,

    -- Slider  (white + alpha for track -- adapts to any background tint)
    SL_TRACK_R = 1, SL_TRACK_G = 1, SL_TRACK_B = 1,        -- track bg (white + alpha)
    SL_TRACK_A = 0.16,                                     -- track bg alpha
    SL_FILL_A = 0.75,                                      -- filled portion alpha (colour = accent)
    SL_INPUT_R = 0.030, SL_INPUT_G = 0.023, SL_INPUT_B = 0.018, -- input box background (darker than bg, stays as-is)
    SL_INPUT_A = 0.25,                                     -- input box alpha (all sliders)
    SL_INPUT_BRD_A = 0.02,                                 -- input box border alpha (white)

    -- Multi-widget slider overrides  (applied additively in BuildSliderCore)
    MW_INPUT_ALPHA_BOOST = 0.15,                           -- additive alpha boost for multi-widget input fields
    MW_TRACK_ALPHA_BOOST = 0.06,                           -- additive alpha boost for multi-widget slider track

    -- Toggle  (white + alpha for off states -- adapts to any background tint)
    TG_OFF_R = 0.267, TG_OFF_G = 0.267, TG_OFF_B = 0.267,  -- track when OFF (#444)
    TG_OFF_A = 0.65,                                       -- track OFF alpha
    TG_ON_A = 0.75,                                        -- track alpha at full ON (colour = accent)
    TG_KNOB_OFF_R = 1, TG_KNOB_OFF_G = 1, TG_KNOB_OFF_B = 1, -- knob when OFF (white + alpha)
    TG_KNOB_OFF_A = 0.5,                                   -- knob OFF alpha
    TG_KNOB_ON_R = 1, TG_KNOB_ON_G = 1, TG_KNOB_ON_B = 1,  -- knob when ON
    TG_KNOB_ON_A = 1,                                      -- knob ON alpha

    -- Checkbox
    CB_BOX_R = 0.112, CB_BOX_G = 0.105, CB_BOX_B = 0.098,  -- box background
    CB_BRD_A = 0.05, CB_ACT_BRD_A = 0.15,                  -- box border alpha / checked border alpha

    -- Button / WideButton
    BTN_BG_R = 0.089, BTN_BG_G = 0.080, BTN_BG_B = 0.072,  -- background
    BTN_BG_A = 0.6,
    BTN_BG_HA = 0.65,                                      -- background alpha hovered
    BTN_BRD_A = 0.3,                                       -- border alpha (colour = white)
    BTN_BRD_HA = 0.45,                                     -- border alpha hovered
    BTN_TXT_A = 0.55,                                      -- text alpha (colour = white)
    BTN_TXT_HA = 0.70,                                     -- text alpha hovered

    -- Dropdown
    DD_BG_R = 0.103, DD_BG_G = 0.095, DD_BG_B = 0.088,     -- background
    DD_BG_A = 0.9,
    DD_BG_HA = 0.98,                                       -- background alpha hovered
    DD_BRD_A = 0.20,                                       -- border alpha (colour = white)
    DD_BRD_HA = 0.30,                                      -- border alpha hovered
    DD_TXT_A = 0.50,                                       -- selected value text alpha (colour = white)
    DD_TXT_HA = 0.60,                                      -- selected value text alpha hovered
    DD_ITEM_HL_A = 0.08,                                   -- menu item highlight alpha (hover)
    DD_ITEM_SEL_A = 0.04,                                  -- menu item highlight alpha (active selection)

    -- Multi-widget layout  (dual = 2-up, triple = 3-up -- shared by all widget types)
    DUAL_ITEM_W = 350,                                     -- width of each item in a 2-up row
    DUAL_GAP = 42,                                         -- gap between 2-up items
    TRIPLE_ITEM_W = 180,                                   -- width of each item in a 3-up row
    TRIPLE_GAP = 50,                                       -- gap between 3-up items
}

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
    -- CLASS_COLOR_MAP is defined below: parse time resolves presets only; Class/Custom resolve at PLAYER_LOGIN.
    local db = EllesmereUIDB or {}
    local theme = ResolveFactionTheme(db.activeTheme or EllesmereUI.DEFAULT_THEME)
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

-- Registry of accent-colored elements (sidebar indicators, glows, tab underlines,
-- footer buttons, popup confirm). Entry = { type="solid"|"gradient"|"font"|"callback", obj=... }
local _accentElements = { _idx = {} }  -- _idx: obj -> index, prevents duplicates
local function RegAccent(entry)
    local key = entry.obj or entry.fn
    if key and _accentElements._idx[key] then
        _accentElements[_accentElements._idx[key]] = entry
    else
        _accentElements[#_accentElements + 1] = entry
        if key then _accentElements._idx[key] = #_accentElements end
    end
end
local DARK_BG         = { r = STYLE.PANEL_BG_R, g = STYLE.PANEL_BG_G, b = STYLE.PANEL_BG_B }
local BORDER_COLOR    = { r = STYLE.BORDER_R, g = STYLE.BORDER_G, b = STYLE.BORDER_B, a = STYLE.BORDER_A }
local TEXT_WHITE      = { r = STYLE.TEXT_WHITE_R, g = STYLE.TEXT_WHITE_G, b = STYLE.TEXT_WHITE_B }
local TEXT_DIM        = { r = STYLE.TEXT_DIM_R, g = STYLE.TEXT_DIM_G, b = STYLE.TEXT_DIM_B, a = STYLE.TEXT_DIM_A }
local TEXT_SECTION    = { r = STYLE.TEXT_SECTION_R, g = STYLE.TEXT_SECTION_G, b = STYLE.TEXT_SECTION_B, a = STYLE.TEXT_SECTION_A }

-- Dropdown widget colours: widgets reference DD_BG_*, DD_BRD_*, DD_TXT_* directly

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

-- Class icon sprite-sheet UV grid (4-column sheet; left/right/top/bottom). Shared by
-- every module's class-icon rendering; TEXTURE path stays per consumer. Read-only.
EllesmereUI.CLASS_ICON_SPRITE_COORDS = {
    WARRIOR     = { 0,     0.125, 0,     0.125 },
    MAGE        = { 0.125, 0.25,  0,     0.125 },
    ROGUE       = { 0.25,  0.375, 0,     0.125 },
    DRUID       = { 0.375, 0.5,   0,     0.125 },
    EVOKER      = { 0.5,   0.625, 0,     0.125 },
    HUNTER      = { 0,     0.125, 0.125, 0.25  },
    SHAMAN      = { 0.125, 0.25,  0.125, 0.25  },
    PRIEST      = { 0.25,  0.375, 0.125, 0.25  },
    WARLOCK     = { 0.375, 0.5,   0.125, 0.25  },
    PALADIN     = { 0,     0.125, 0.25,  0.375 },
    DEATHKNIGHT = { 0.125, 0.25,  0.25,  0.375 },
    MONK        = { 0.25,  0.375, 0.25,  0.375 },
    DEMONHUNTER = { 0.375, 0.5,   0.25,  0.375 },
}

-- Font (Expressway lives in EllesmereUI/media)
local EXPRESSWAY = MEDIA_PATH .. "fonts\\Expressway.ttf"

-- Locale system-font fallback for glyphs our fonts lack (CJK, Cyrillic). Resolved by
-- EllesmereUI_Locale.lua from the EFFECTIVE locale (client or override); nil = Expressway.
local LOCALE_FONT_FALLBACK = _G.EllesmereUI and _G.EllesmereUI._localeFont or nil
-------------------------------------------------------------------------------
--  Addon Roster  --  per-addon display name + search alias from EllesmereUI/media
-------------------------------------------------------------------------------
local ICONS_PATH    = MEDIA_PATH .. "icons\\"

-------------------------------------------------------------------------------
--  Season M+ Portals -- single source of truth for every portal/teleport list in
--  the suite (Chat flyout, Minimap flyout, QoL /keys resolver, DataBars tooltip).
--  Update ONCE here each season. Order = flyout grid order (top-left to bottom-right).
--    spellID     - primary teleport spell id
--    short       - abbreviated label used by the flyout buttons
--    dungeonID   - LFG dungeonID (GetLFGDungeonInfo name lookup)
--    names       - lowercase dungeon names + localized aliases (name -> spell)
--    altSpellIDs - optional variant teleport spell ids
-------------------------------------------------------------------------------
EllesmereUI.SEASON_PORTALS = {
    { spellID = 1286801, short = "BV",  dungeonID = 3102, names = { "the blinding vale", "blinding vale", "слепящая долина" } },
    { spellID = 1286804, short = "VA",  dungeonID = 3106, names = { "voidscar arena", "арена шрама бездны" } },
    { spellID = 1286807, short = "DoN", dungeonID = 3051, names = { "den of nalorakk", "den of nalorak", "берлога налоракка" } },
    { spellID = 1286809, short = "MR",  dungeonID = 3090, names = { "murder row", "закоулок душегубов" } },
    { spellID = 1286812, short = "AoF", dungeonID = 3191, names = { "altar of fangs", "алтарь клыков" } },
    { spellID = 393256,  short = "RLP", dungeonID = 2361, names = { "ruby life pools", "рубиновые омуты жизни" } },
    { spellID = 1286828, short = "ToS", dungeonID = 1694, names = { "temple of sethraliss", "храм сетралисс" } },
    { spellID = 1286831, short = "KR",  dungeonID = 1785, names = { "kings' rest", "king's rest", "гробница королей" } },
}

-- Great Vault shortcut (Minimap button, Data Bars block, character sheet
-- season panel): loads Blizzard's vault on first use and toggles it directly,
-- so opening it closes no other panel (the UIPanel fit check would close the
-- character sheet). Escape still closes it (RegisterEscapeClose, notOwned).
function EllesmereUI.ToggleGreatVault()
    if not C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards") then
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
    end
    local vault = _G.WeeklyRewardsFrame
    if vault then vault:SetShown(not vault:IsShown()) end
end

-- Portal flyout (Chat sidebar and Minimap): SEASON_PORTALS spell buttons plus a
-- hearthstone column, all secure. Build lazily, never in combat; the caller
-- caches the frame and owns anchoring. opts: name (frame name prefix), bg
-- ({r,g,b}), labelFont, labelFlags, clamp (clamp to screen), unitEvents
-- (register the cast events for "player" only).
function EllesmereUI.CreatePortalFlyout(opts)
    if InCombatLockdown() then return nil end
    local floor = math.floor
    local PP = EllesmereUI.PP

    local BTN_SIZE = 32
    local SPACING = 1
    local PADDING = 2
    local COLS = 4
    local ROWS = math.ceil(#EllesmereUI.SEASON_PORTALS / COLS)

    local flyH = PADDING * 2 + BTN_SIZE * ROWS + SPACING * (ROWS - 1)
    local HS_COUNT = 3
    local HS_H = floor((flyH - PADDING * 2 - SPACING * (HS_COUNT - 1)) / HS_COUNT)
    local hsX = PADDING + COLS * BTN_SIZE + (COLS - 1) * SPACING + SPACING
    local flyW = hsX + HS_H + PADDING

    local flyout = CreateFrame("Frame", opts.name .. "PortalFlyout", UIParent)
    flyout:SetSize(flyW, flyH)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetFrameLevel(100)
    if opts.clamp then flyout:SetClampedToScreen(true) end
    flyout:Hide()

    local bg = flyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(opts.bg[1], opts.bg[2], opts.bg[3], 0.95)

    if PP and PP.CreateBorder then
        PP.CreateBorder(flyout, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
    end

    -- Close in combat
    local guard = CreateFrame("Frame")
    guard:RegisterEvent("PLAYER_REGEN_DISABLED")
    guard:SetScript("OnEvent", function() flyout:Hide() end)

    local function NewButton(name, size)
        local btn = CreateFrame("Button", name, flyout, "SecureActionButtonTemplate")
        btn:SetSize(size, size)
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
        btn.icon = icon
        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end
        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(true)
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        btn.cooldown = cd
        return btn, cd
    end

    local function AddHighlights(btn)
        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.20)
        -- Casting highlight overlay
        local castHL = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        castHL:SetAllPoints()
        castHL:SetColorTexture(1, 1, 1, 0.4)
        castHL:Hide()
        btn._castHL = castHL
    end

    local portalBtns = {}
    for i, e in ipairs(EllesmereUI.SEASON_PORTALS) do
        local spellID = e.spellID
        local col = (i - 1) % COLS
        local row = floor((i - 1) / COLS)
        local btn, cd = NewButton(opts.name .. "Portal" .. i, BTN_SIZE)
        btn:SetPoint("TOPLEFT", flyout, "TOPLEFT",
            PADDING + col * (BTN_SIZE + SPACING),
            -(PADDING + row * (BTN_SIZE + SPACING)))
        btn.spellID = spellID
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo then btn.icon:SetTexture(spellInfo.iconID) end

        local short = e.short
        if short then
            local labelFrame = CreateFrame("Frame", nil, btn)
            labelFrame:SetAllPoints()
            labelFrame:SetFrameLevel(cd:GetFrameLevel() + 2)
            local label = labelFrame:CreateFontString(nil, "OVERLAY", nil)
            if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(label, true) end
            label:SetFont(opts.labelFont, 8, opts.labelFlags)
            label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
            label:SetTextColor(1, 1, 1, 0.9)
            label:SetText((EllesmereUI.L(short)) or short)
        end

        AddHighlights(btn)
        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spellID)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        portalBtns[i] = btn
    end

    -- Hearthstone column: 3 icons stacked vertically as a 5th column
    local hearthBtns = {}
    for i = 1, HS_COUNT do
        local btn = NewButton(opts.name .. "Hearth" .. i, HS_H)
        btn:SetPoint("TOPLEFT", flyout, "TOPLEFT",
            hsX,
            -(PADDING + (i - 1) * (HS_H + SPACING)))
        AddHighlights(btn)
        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._hsType == "spell" then
                GameTooltip:SetSpellByID(self._hsID)
            elseif self._hsType == "item" then
                if self._hsID ~= 6948 and PlayerHasToy and PlayerHasToy(self._hsID) then
                    GameTooltip:SetToyByItemID(self._hsID)
                else
                    GameTooltip:SetItemByID(self._hsID)
                end
            elseif self._hsType == "housing" then
                GameTooltip:AddLine(EllesmereUI.L("Housing Dashboard"))
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:HookScript("PostClick", function(self)
            if self._hsType == "housing" then
                if HousingFramesUtil and HousingFramesUtil.ToggleHousingDashboard then
                    HousingFramesUtil.ToggleHousingDashboard()
                end
                flyout:Hide()
            else
                self._castHL:Show()
            end
        end)
        hearthBtns[i] = btn
    end

    local function RefreshPortalButtons()
        for _, btn in ipairs(portalBtns) do
            local spellID = btn.spellID
            local known = IsPlayerSpell(spellID)
            if btn._lastKnown ~= known then
                btn._lastKnown = known
                btn.icon:SetDesaturated(not known)
                btn.icon:SetAlpha(known and 1 or 0.4)
            end
            if known then
                local cdInfo = C_Spell.GetSpellCooldown(spellID)
                if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                    btn.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
                else
                    btn.cooldown:Clear()
                end
            else
                btn.cooldown:Clear()
            end
        end
    end

    -- Swipe-only refresh (SPELL_UPDATE_COOLDOWN); never re-resolves toys.
    local function RefreshHearthCooldowns()
        for _, btn in ipairs(hearthBtns) do
            local aType, id = btn._hsType, btn._hsID
            if aType == "spell" and C_Spell and C_Spell.GetSpellCooldown then
                local cdInfo = C_Spell.GetSpellCooldown(id)
                if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                    btn.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
                else
                    btn.cooldown:Clear()
                end
            -- The namespaced call (as IsHearthOnCD uses): the global only exists
            -- behind Blizzard's deprecation fallbacks, and never on Forever.
            elseif aType == "item" and C_Container and C_Container.GetItemCooldown then
                local ok, start, dur = pcall(C_Container.GetItemCooldown, id)
                if ok and start and dur and dur > 0 then
                    btn.cooldown:SetCooldown(start, dur)
                else
                    btn.cooldown:Clear()
                end
            else
                btn.cooldown:Clear()
            end
        end
    end

    -- Full resolve (random toy, icon/macro/attributes). Show only, never on
    -- cooldown events; attribute writes are combat-illegal, hence the gate.
    local function ResolveHearthButtons()
        if InCombatLockdown() then return end
        local resolvers = {
            EllesmereUI.ResolveHearthSlot,
            EllesmereUI.ResolveDalaranSlot,
            EllesmereUI.ResolveHousingSlot,
        }
        for i, btn in ipairs(hearthBtns) do
            local aType, id, iconTex = resolvers[i]()
            btn._hsType = aType
            btn._hsID = id
            btn.icon:SetTexture(iconTex)
            btn.icon:SetTexCoord(aType == "housing" and 0 or 6/64,
                                 aType == "housing" and 1 or 58/64,
                                 aType == "housing" and 0 or 6/64,
                                 aType == "housing" and 1 or 58/64)
            if aType == "housing" then
                btn:SetAttribute("type", nil)
                btn:SetAttribute("macrotext", nil)
            elseif aType == "spell" then
                btn:SetAttribute("type", "macro")
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                local name = info and info.name or ""
                btn:SetAttribute("macrotext", "/cast " .. name)
            else
                btn:SetAttribute("type", "macro")
                if id == 6948 then
                    btn:SetAttribute("macrotext", "/use item:" .. id)
                else
                    local toyName
                    if C_ToyBox and C_ToyBox.GetToyInfo then
                        local _, tn = C_ToyBox.GetToyInfo(id)
                        toyName = tn
                    end
                    btn:SetAttribute("macrotext", toyName and ("/use " .. toyName) or ("/use item:" .. id))
                end
            end
        end
        RefreshHearthCooldowns()
    end

    -- Events live only while shown: cooldown + cast highlight refresh.
    local CAST_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
                          "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }
    flyout:SetScript("OnShow", function(self)
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        for _, ev in ipairs(CAST_EVENTS) do
            if opts.unitEvents then self:RegisterUnitEvent(ev, "player") else self:RegisterEvent(ev) end
        end
        RefreshPortalButtons()
        ResolveHearthButtons()
        -- Controller cursor: a window the player opened brings the gamepad pointer up.
        if EllesmereUI.PadNative() then EllesmereUI.RaiseGamePadCursor() end
    end)
    flyout:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        for _, btn in ipairs(portalBtns) do
            if btn._castHL then btn._castHL:Hide() end
        end
        for _, btn in ipairs(hearthBtns) do
            if btn._castHL then btn._castHL:Hide() end
        end
    end)
    flyout:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
        if event == "SPELL_UPDATE_COOLDOWN" then
            RefreshPortalButtons()
            RefreshHearthCooldowns()
        elseif unit == "player" then
            local casting = (event == "UNIT_SPELLCAST_START") and spellID or nil
            for _, btn in ipairs(portalBtns) do
                if btn._castHL then
                    btn._castHL:SetShown(casting and casting == btn.spellID)
                end
            end
            -- Cast end clears hearthstone highlights
            if not casting then
                for _, btn in ipairs(hearthBtns) do
                    if btn._castHL then btn._castHL:Hide() end
                end
            end
        end
    end)

    -- Escape to close
    EllesmereUI.RegisterEscapeClose(flyout)
    return flyout
end

local ADDON_ROSTER = {
    { folder = "EllesmereUIActionBars",        display = "Action Bars",          search_name = "EllesmereUI Action Bars"             },
    { folder = "EllesmereUINameplates",        display = "Nameplates",           search_name = "EllesmereUI Nameplates"              },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",          search_name = "EllesmereUI Unit Frames"             },
    { folder = "EllesmereUIRaidFrames",        display = "Raid Frames",          search_name = "EllesmereUI Raid Frames"             },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",     search_name = "EllesmereUI Cooldown Manager"        },
    { folder = "EllesmereUIResourceBars",      display = "Resource & Cast Bars", search_name = "EllesmereUI Resource Bars Cast Bars" },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders",   search_name = "EllesmereUI AuraBuff Reminders"      },
    { folder = "EllesmereUIQoL",               display = "Quality of Life",      search_name = "EllesmereUI Quality of Life"         },
    { folder = "EllesmereUIForeverEssentials", display = "Forever Essentials",   search_name = "EllesmereUI Forever Essentials"      },
    { folder = "EllesmereUIBlizzardSkin",      display = "Blizzard Skins+",      search_name = "EllesmereUI Blizzard Skins+",      syncFolder = "EllesmereUIDragonRiding", syncDisplay = "Dragon Riding" },
    { folder = "EllesmereUIFriends",           display = "Friends List",         search_name = "EllesmereUI Friends List"            },
    { folder = "EllesmereUIMythicTimer",       display = "Mythic+ Tools",        search_name = "EllesmereUI Mythic+ Tools Timer"     },
    { folder = "EllesmereUIQuestTracker",      display = "Quest Tracker",        search_name = "EllesmereUI Quest Tracker"           },
    { folder = "EllesmereUIMinimap",           display = "Minimap",              search_name = "EllesmereUI Minimap"                 },
    { folder = "EllesmereUIChat",              display = "Chat",                 search_name = "EllesmereUI Chat"                    },
    { folder = "EllesmereUIDamageMeters",      display = "Damage Meters",        search_name = "EllesmereUI Damage Meters"           },
    { folder = "EllesmereUIBags",              display = "Bags",                 search_name = "EllesmereUI Bags"                    },
    { folder = "EllesmereUIDataBars",          display = "DataBars",             search_name = "EllesmereUI DataBars"                },
    { folder = "EllesmereUIQuickdraw",         display = "Quickdraw",            search_name = "EllesmereUI Quickdraw"               },
    { folder = "EllesmereUIPartyMode",         display = "Party Mode",           search_name = "EllesmereUI Party Mode",             alwaysLoaded = true },
}

-------------------------------------------------------------------------------
--  Addon Groups -- ordered sidebar categories (group = text header, no toggle; members
--  = child rows, order authoritative, coming-soon last). On EllesmereUI, not a file
--  local, to stay under the 200-local / CreateMainFrame 60-upvalue caps.
-------------------------------------------------------------------------------
EllesmereUI.ADDON_GROUPS = {
    {
        key     = "core",
        label   = "Core Addons",
        members = {
            "EllesmereUIActionBars",
            "EllesmereUINameplates",
            "EllesmereUIUnitFrames",
            "EllesmereUICooldownManager",
            "EllesmereUIResourceBars",
            "EllesmereUIRaidFrames",
        },
    },
    {
        key     = "qol",
        label   = "QoL Addons",
        members = {
            "EllesmereUIQoL",
            "EllesmereUIForeverEssentials",
            "EllesmereUIAuraBuffReminders",
            "EllesmereUIDataBars",
            "EllesmereUIQuickdraw",
            "EllesmereUIPartyMode",
        },
    },
    {
        key     = "reskin",
        label   = "UI Reskin Addons",
        members = {
            "EllesmereUIBlizzardSkin",
            "EllesmereUIDamageMeters",
            "EllesmereUIMythicTimer",
            "EllesmereUIQuestTracker",
            "EllesmereUIFriends",
            "EllesmereUIMinimap",
            "EllesmereUIChat",
            "EllesmereUIBags",
        },
    },
}

-- STANDALONE: the bundled module is the only roster entry containing "Standalone"
-- (rename yields "EUICoreStandalone<X>" refs; installed folder is "EUIStandalone<X>").
-- Keep the full sidebar, prepend a "Standalone" category with this module, and remove
-- it from its normal category so it is not listed twice. Inert in the suite.
if IS_STANDALONE then
    local selfFolder
    for _, info in ipairs(ADDON_ROSTER) do
        -- Exclude "Core": the renamed core token is "EUICoreStandalone<X>".
        if info.folder:find("Standalone") and not info.folder:find("Core") then
            selfFolder = info.folder
            break
        end
    end
    if selfFolder then
        for _, group in ipairs(EllesmereUI.ADDON_GROUPS) do
            for mi = #group.members, 1, -1 do
                if group.members[mi] == selfFolder then
                    table.remove(group.members, mi)
                end
            end
        end
        table.insert(EllesmereUI.ADDON_GROUPS, 1, {
            key     = "standalone",
            label   = "Standalone",
            members = { selfFolder },
        })
    end
end

-- WoW Forever: addons switched off for the whole client (TOC
-- "## AllowLoadGameType: standard") leave every list built from the roster
-- and the groups -- sidebar, install picker, font and texture cards -- rather
-- than sit in them disabled. Extend the set whenever a TOC gets that line.
EllesmereUI.FOREVER_HIDDEN_ADDONS = {
    EllesmereUIMythicTimer = true, EllesmereUIFriends = true,
    -- Not an addon: the Dragon Riding profile pseudo-folder (its file returns at
    -- load on Forever), listed so the profile import/export checklists drop it.
    EllesmereUIDragonRiding = true,
}
-- The mirror: addons that load on WoW Forever alone (TOC
-- "## AllowLoadGameType: camelot") leave the same lists on every other client.
EllesmereUI.FOREVER_ONLY_ADDONS = {
    EllesmereUIForeverEssentials = true,
}
-- The set the running client leaves out.
EllesmereUI._CLIENT_HIDDEN_ADDONS = (EUI_CLIENT_FOREVER == true)
    and EllesmereUI.FOREVER_HIDDEN_ADDONS or EllesmereUI.FOREVER_ONLY_ADDONS
-- The profile import/export checklists read the profile data map, which stays
-- complete (it drives the data itself); they list through this view instead.
function EllesmereUI.VisibleProfileAddons(map)
    if type(map) ~= "table" then return map end
    local hidden = EllesmereUI._CLIENT_HIDDEN_ADDONS
    local out = {}
    for _, entry in ipairs(map) do
        if not hidden[entry.folder] then out[#out + 1] = entry end
    end
    return out
end
do
    local hidden = EllesmereUI._CLIENT_HIDDEN_ADDONS
    for i = #ADDON_ROSTER, 1, -1 do
        if hidden[ADDON_ROSTER[i].folder] then table.remove(ADDON_ROSTER, i) end
    end
    for _, group in ipairs(EllesmereUI.ADDON_GROUPS) do
        for mi = #group.members, 1, -1 do
            if hidden[group.members[mi]] then table.remove(group.members, mi) end
        end
    end
end

-- Icon file ids the Forever client does not ship (its art set predates them),
-- each with the vanilla-era icon that stands in for it there. Resolved where
-- an icon is painted (a stored custom icon gets the same treatment), never in
-- the default tables; every other client gets the id back as it is. Extend
-- the map whenever a tester reports a green square.
EllesmereUI._FOREVER_ICON = {
    [7548911] = 133975,   -- Bags "Consumables" default: an apple
    [7549094] = 136249,   -- Bags "Gear Enhancements": classic enchantment icon
    [7548925] = 134332,   -- Bags "Professions": classic trade-skill icon
}
function EllesmereUI.ClientIcon(icon)
    if EUI_CLIENT_FOREVER ~= true then return icon end
    return EllesmereUI._FOREVER_ICON[icon] or icon
end

-- The trash can on a delete button: Blizzard's atlas where the client has it,
-- else the bundled glyph (the Forever client has no common-icon-delete).
function EllesmereUI.SetDeleteIcon(tex)
    local ok = EllesmereUI._deleteAtlasOK
    if ok == nil then
        ok = C_Texture.GetAtlasInfo("common-icon-delete") ~= nil
        EllesmereUI._deleteAtlasOK = ok
    end
    if ok then
        tex:SetAtlas("common-icon-delete")
    else
        tex:SetTexture(EllesmereUI.ICONS_PATH .. "common-icon-delete.png")
    end
end

-- Flat folder -> roster-info lookup for the grouped sidebar builder. On EllesmereUI
-- (not a local): CreateMainFrame is up against the Lua 5.1 60-upvalue limit.
EllesmereUI._addonInfoByFolder = {}
for _, info in ipairs(ADDON_ROSTER) do
    EllesmereUI._addonInfoByFolder[info.folder] = info
end

-------------------------------------------------------------------------------
--  Private navigation model
--  The sidebar is built ONLY from these copies, taken once the roster and groups
--  above are final. ADDON_ROSTER / ADDON_GROUPS / _addonInfoByFolder stay public
--  as read-only data for other files, but writes to them no longer reach the
--  sidebar: third-party code cannot add rows to the suite's sections, reorder
--  them, or relabel them. Plugin sections (see the Plugin API section) are held
--  in separate lists and can only sit above or below the whole suite block.
-------------------------------------------------------------------------------
do
    local navInfo = {}
    for _, info in ipairs(ADDON_ROSTER) do
        local copy = {}
        for k, v in pairs(info) do copy[k] = v end
        navInfo[info.folder] = copy
    end
    local coreGroups = {}
    for _, group in ipairs(EllesmereUI.ADDON_GROUPS) do
        local members = {}
        for i, folder in ipairs(group.members) do members[i] = folder end
        coreGroups[#coreGroups + 1] = { key = group.key, label = group.label, members = members }
    end
    EUI_NS.navInfo            = navInfo
    EUI_NS.coreGroups         = coreGroups
    EUI_NS.pluginGroupsTop    = {}
    EUI_NS.pluginGroupsBottom = {}
    EUI_NS.navGroups          = {}
    -- Sidebar group header frames, keyed by group key.
    EUI_NS.sidebarGroupButtons = {}

    -- Final sidebar order: top plugin sections, the suite's own groups as one
    -- contiguous block, then bottom plugin sections.
    function EUI_NS.RebuildNavGroups()
        local out = EUI_NS.navGroups
        for i = #out, 1, -1 do out[i] = nil end
        for _, g in ipairs(EUI_NS.pluginGroupsTop)    do out[#out + 1] = g end
        for _, g in ipairs(coreGroups)                do out[#out + 1] = g end
        for _, g in ipairs(EUI_NS.pluginGroupsBottom) do out[#out + 1] = g end
    end
    EUI_NS.RebuildNavGroups()

    -- Module keys starting with this prefix belong to the plugin registry.
    local PLUGIN_PREFIX = "plugin:"
    EUI_NS.PLUGIN_PREFIX = PLUGIN_PREFIX
    function EUI_NS.IsPluginKey(key)
        return type(key) == "string" and key:sub(1, #PLUGIN_PREFIX) == PLUGIN_PREFIX
    end

    -- Suite registration window (see RegisterModule). Open while the options
    -- addon loads (whoever loads it: its files register as they run), while the
    -- core drains its deferred inits, and from a pre-login load of the options
    -- addon until just after PLAYER_LOGIN (its files register from their
    -- PLAYER_LOGIN handlers in that case).
    local regDepth, loginWindow = 0, false
    local IsAddOnLoaded = C_AddOns.IsAddOnLoaded
    function EUI_NS.CoreRegistrationOpen()
        if regDepth > 0 or loginWindow then return true end
        local loadedOrLoading, loaded = IsAddOnLoaded("EllesmereUIOptions")
        return loadedOrLoading and not loaded
    end
    -- The suite's pages always register through the real RegisterModule. An
    -- addon that replaced or hooked the public one (to slip pages into the
    -- suite's modules) is taken out of the path first, so it can never stop
    -- them registering, and is named in the panel's update notice.
    local rawget, rawset = rawget, rawset
    local function ReclaimRegisterModule()
        local real = EUI_NS.CoreRegisterModule
        if not real or rawget(EllesmereUI, "RegisterModule") == real then return end
        local by = EUI_NS.WriterOf(EllesmereUI, "RegisterModule")
        rawset(EllesmereUI, "RegisterModule", real)
        if by then EUI_NS.RecordLegacyOffender(by) end
    end
    -- Errors are reported through the error handler (keeping their traceback)
    -- rather than rethrown, so a failing callee can never leave the window open.
    local function ReportError(err) return geterrorhandler()(err) end
    EUI_NS.ReportError = ReportError  -- shared with the plugin registry (EllesmereUI_Panel.lua)
    function EUI_NS.RunCoreRegistration(fn, ...)
        ReclaimRegisterModule()
        regDepth = regDepth + 1
        local ok, a, b = xpcall(fn, ReportError, ...)
        regDepth = regDepth - 1
        if ok then return a, b end
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self, event, name)
        if event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            -- Before the options files' own PLAYER_LOGIN registrations (a
            -- pre-login options load, standalone builds).
            ReclaimRegisterModule()
            if loginWindow then
                C_Timer.After(0, function() loginWindow = false end)
            end
        elseif name == "EllesmereUIOptions" then
            self:UnregisterEvent("ADDON_LOADED")
            -- Loaded before login: its files register from their PLAYER_LOGIN handlers.
            if not IsLoggedIn() then loginWindow = true end
        end
    end)
end

local IsAddonLoaded = C_AddOns.IsAddOnLoaded

-------------------------------------------------------------------------------
--  Forward declarations
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI or {}
_G.EllesmereUI = EllesmereUI
EllesmereUI.GLOBAL_KEY = "_EUIGlobal"
EllesmereUI.ADDON_ROSTER = ADDON_ROSTER
EllesmereUI.LOCALE_FONT_FALLBACK = LOCALE_FONT_FALLBACK
-- Script the fallback stands in for: "cyrillic" | "cjk" | nil. Table field, not a
-- file-scope local: this file sits on the Lua 5.1 200-local cap.
EllesmereUI.LOCALE_SCRIPT = EllesmereUI._localeScript
EllesmereUI.EXPRESSWAY = LOCALE_FONT_FALLBACK or EXPRESSWAY

-- Re-sync once the override-aware effective locale is known (the values above
-- are captured before EllesmereUIDB's displayLocale override is readable).
function EllesmereUI.RefreshLocaleFontFallback()
    LOCALE_FONT_FALLBACK = EllesmereUI._localeFont
    EllesmereUI.LOCALE_FONT_FALLBACK = LOCALE_FONT_FALLBACK
    EllesmereUI.LOCALE_SCRIPT = EllesmereUI._localeScript
    EllesmereUI.EXPRESSWAY = LOCALE_FONT_FALLBACK or EXPRESSWAY
    EllesmereUI.InvalidateFontCache()
end

-- Taint-safe print: AddMessage, never global print() (its C-side handler taints the chat
-- frame). Drops silently in protected instances (raid combat, active M+) to avoid tainting FCF_OpenTemporaryWindow's whisper chain.
function EllesmereUI.Print(...)
    local f = DEFAULT_CHAT_FRAME
    if not f then return end
    local _, instanceType = IsInInstance()
    if instanceType == "raid" and InCombatLockdown() then return end
    if instanceType == "party" and C_ChallengeMode
       and C_ChallengeMode.IsChallengeModeActive
       and C_ChallengeMode.IsChallengeModeActive() then return end
    if (instanceType == "pvp" or instanceType == "arena") and InCombatLockdown() then return end
    f:AddMessage(strjoin(" ", tostringall(...)))
end

-- Budgeted step runner -- the 12.1 script-watchdog defense for any pass whose
-- cost scales with data size (frames x settings x profile keys). Runs `steps`
-- (an array of functions) strictly in order, spending at most `msBudget`
-- (default 8) milliseconds of CPU per execution; when the budget is spent the
-- remainder re-queues via C_Timer.After(0), so every continuation gets a
-- fresh watchdog budget. By construction no single execution here can
-- approach the watchdog limit, on any machine, at any step count.
--
-- NOTHING runs in the caller's execution: the first slice is deferred too,
-- so a caller that already spent real budget (a profile apply, an options
-- click) never gets this work stacked on top. Timers do not fire during
-- loading screens, so from a login-window caller the first slice lands on
-- the first frame after the screen drops.
--
-- Each step runs under pcall with errors routed to the standard error
-- handler and the chain CONTINUING: an async chain that died mid-way would
-- silently strand `onDone` (completion/cleanup) and every later step, which
-- is worse than one step's failure. Steps must tolerate a failed
-- predecessor; a sequence that cannot should stay synchronous instead.
-- `onDone` (optional) runs after the last step, in that final execution.
-- No file-scope locals here on purpose: this file sits on the 200-local cap.
function EllesmereUI.RunBudgeted(steps, msBudget, onDone)
    local idx, n = 1, #steps
    local budget = msBudget or 8
    local function drain()
        local deadline = debugprofilestop() + budget
        while idx <= n do
            local ok, err = pcall(steps[idx])
            idx = idx + 1
            if not ok and err then geterrorhandler()(err) end
            if idx <= n and debugprofilestop() > deadline then
                C_Timer.After(0, drain)
                return
            end
        end
        if onDone then onDone() end
    end
    C_Timer.After(0, drain)
end

local modules = {}
-- Private alias so other core files (the panel, global search) can reach the
-- registered modules. Never published on EllesmereUI: a reference to a
-- module's config table would let any addon rewrite that module's pages.
EUI_NS.modules = modules

-- Widget refresh registry: a Refresh callback per widget so RefreshPage updates values in-place without rebuilding frames.
local _widgetRefreshList = {}
local function RegisterWidgetRefresh(fn)
    _widgetRefreshList[#_widgetRefreshList + 1] = fn
end
EllesmereUI.RegisterWidgetRefresh = RegisterWidgetRefresh

-- Collapse callbacks -- fn(true) when the panel folds to its mini window, fn(false)
-- when it unfolds back on screen. The options session stays open across both, so
-- neither the OnShow nor the OnHide callbacks run; a close from the mini window
-- runs the OnHide callbacks instead of fn(false). For panel-owned surfaces that
-- live outside the panel body (UIParent-parented popouts) or panel-only work.
EllesmereUI._onCollapseCallbacks = {}
function EllesmereUI:RegisterOnCollapse(fn)
    local list = self._onCollapseCallbacks
    list[#list + 1] = fn
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

-- PP and PanelPP come from EllesmereUI_PixelPerfect.lua, which loads before this file
local PP = EllesmereUI.PP

-- Disable WoW pixel snapping on a texture/frame so 1px elements never round to 0.
local function DisablePixelSnap(obj)
    if obj.SetSnapToPixelGrid then
        obj:SetSnapToPixelGrid(false)
        obj:SetTexelSnappingBias(0)
    end
end

-- Dropdown arrow: square canvas, arrow centered, two-point anchored so it inherits the parent's pixel-aligned bounds.
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
    -- PP.CreateBorder wrapper returning the MakeBorder API. ppOverride: PanelPP for panel context, else real PP (game context).
    local pp = ppOverride or PP
    local alpha = a or 1
    r = r or 0; g = g or 0; b = b or 0
    local bf = CreateFrame("Frame", nil, parent)
    bf:SetAllPoints(parent)
    bf:SetFrameLevel(parent:GetFrameLevel() + 1)
    bf:EnableMouse(false)

    -- PP.CreateBorder's four strips. A border inside the options panel re-snaps with
    -- the rest of it in SetPanelScale's settle pass, never through a hook of its own.
    local brd = PP.CreateBorder(bf, r, g, b, alpha, 1, "BORDER", 7)

    return {
        _frame = bf,
        edges = brd,
        SetColor = function(self, cr, cg, cb, ca)
            PP.SetBorderColor(bf, cr, cg, cb, ca or 1)
        end,
    }
end

-- Alternating row backgrounds, counted per parent so each section resets independently. In
-- a split column (parent._splitParent) the bg lives on splitParent so it spans full width, anchored to the widget frame's top/bottom edges.
local rowCounters = {}
local function RowBg(frame, parent)
    if not rowCounters[parent] then rowCounters[parent] = 0 end
    rowCounters[parent] = rowCounters[parent] + 1
    local alpha = (rowCounters[parent] % 2 == 0) and STYLE.ROW_BG_EVEN or STYLE.ROW_BG_ODD
    local splitParent = parent._splitParent
    local bgParent = splitParent or frame
    local bg = bgParent:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, alpha)
    -- Always panel context: PanelPP (EllesmereUI_PixelPerfect.lua, loaded before this file)
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
    -- Center divider (1px vertical at row midpoint); only when parent._showRowDivider is set
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

-- "Name-Realm" whisper/invite target. With realmName it builds (realm wins,
-- spaces stripped); with a finished name alone it only collapses a stacked realm.
function EllesmereUI.BuildFullName(charName, realmName)
    -- type()/issecretvalue() before any comparison: `== ""` on a secret throws.
    if type(charName) ~= "string" then return nil end
    if issecretvalue and issecretvalue(charName) then return charName end
    if charName == "" then return nil end

    -- Character names hold no hyphen, so the first one splits name from realm.
    local base, suffix = charName:match("^([^%-]+)%-(.+)$")
    base = base or charName

    if type(realmName) == "string" and not (issecretvalue and issecretvalue(realmName)) then
        local realm = (realmName:gsub("%s+", ""))
        if realm ~= "" then return base .. "-" .. realm end
    end
    if not suffix then return base end

    -- Collapse proven repetition only -- a realm may hold a hyphen ("Azjol-Nerub").
    local segs = {}
    for seg in suffix:gmatch("[^%-]+") do
        if segs[#segs] ~= seg then segs[#segs + 1] = seg end
    end
    suffix = table.concat(segs, "-")
    -- A doubled multi-word realm has no adjacent repeats; a half-split catches it.
    local half = (#suffix - 1) / 2
    if half > 0 and half == math.floor(half)
        and suffix:sub(half + 1, half + 1) == "-"
        and suffix:sub(1, half) == suffix:sub(half + 2) then
        suffix = suffix:sub(1, half)
    end
    return base .. "-" .. suffix
end

-- A friend or guild note for display. Old Friends builds wrote a "||EUI:Group||" tag
-- into friend notes that was never removed: the text before it is kept, trailing
-- space trimmed. nil for a non-string, secret or empty note.
function EllesmereUI.StripFriendNoteTag(note)
    if type(note) ~= "string" or issecretvalue(note) or note == "" then return nil end
    local s = note:find("||EUI:", 1, true)
    if s and note:find("||", s + 6, true) then
        note = note:sub(1, s - 1):match("^(.-)%s*$")
        if note == "" then return nil end
    end
    return note
end

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
EllesmereUI.EYE_VISIBLE_ICON   = MEDIA_PATH .. "icons\\eui-visible.png"
EllesmereUI.EYE_INVISIBLE_ICON = MEDIA_PATH .. "icons\\eui-invisible.png"

-- Shared chat/tooltip colour escapes. Leave codes inside L()/Lf() literals alone:
-- that text is the translation key.
EllesmereUI.COLOR_CODES = {
    WHITE = "|cffffffff",
    DIM   = "|cff888888",
    BAD   = "|cffff5959",
    ERROR = "|cffff6060",
    BRAND = "|cff0cd29d",  -- ADDON_COLORS["EllesmereUI"]
}

-- 0-1 r, g, b -> "|cffRRGGBB" (each channel rounded).
function EllesmereUI.HexColor(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Red "[EllesmereUI]" chat line through Print (same combat/instance muting).
function EllesmereUI.PrintError(msg)
    EllesmereUI.Print(EllesmereUI.COLOR_CODES.ERROR .. "[EllesmereUI]|r " .. msg)
end

-- Shared options-dropdown data, read-only. The menu renders ONLY the keys its order array
-- lists, so a subset-order site may share the full labels dict. Never mutate these or feed
-- them to the SharedMedia appenders (which mutate args in place); sites with a different sequence (none-first, bottomright-first, "same"-prefixed) keep local orders.
EllesmereUI.POSITION_GRID_VALUES = {
    ["topleft"]    = "Top Left",
    ["top"]        = "Top",
    ["topright"]   = "Top Right",
    ["left"]       = "Left",
    ["center"]     = "Center",
    ["right"]      = "Right",
    ["bottomleft"] = "Bottom Left",
    ["bottom"]     = "Bottom",
    ["bottomright"] = "Bottom Right",
}
EllesmereUI.POSITION_GRID_VALUES_NONE = {
    ["topleft"]    = "Top Left",
    ["top"]        = "Top",
    ["topright"]   = "Top Right",
    ["left"]       = "Left",
    ["center"]     = "Center",
    ["right"]      = "Right",
    ["bottomleft"] = "Bottom Left",
    ["bottom"]     = "Bottom",
    ["bottomright"] = "Bottom Right",
    ["none"]       = "None",
}
EllesmereUI.POSITION_GRID_ORDER = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
EllesmereUI.FRAME_STRATA_LABELS = {
    BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium",
    HIGH = "High", DIALOG = "Dialog", FULLSCREEN = "Fullscreen",
    FULLSCREEN_DIALOG = "Fullscreen Dialog", TOOLTIP = "Tooltip",
}
EllesmereUI.FRAME_STRATA_ORDER_BASE = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }
EllesmereUI.FRAME_STRATA_ORDER_FULL = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
EllesmereUI.GROW_DIR_VALUES_FULL = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down", CENTER = "Center" }
EllesmereUI.GROW_DIR_ORDER_FULL  = { "RIGHT", "LEFT", "UP", "DOWN", "CENTER" }
EllesmereUI.GROW_DIR_VALUES_BASE = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
EllesmereUI.GROW_DIR_ORDER_BASE  = { "RIGHT", "LEFT", "UP", "DOWN" }

-- Alert sound catalogue: shared LITERAL data only. Every consumer takes its OWN tables from
-- BuildAlertSoundTables() -- SM appenders mutate in place and cache by table identity, so a shared table collapses two dropdowns into one and loses SM entries.
EllesmereUI.ALERT_SOUND_FILES = {
    airhorn = "AirHorn.ogg", banana = "BananaPeelSlip.ogg", bikehorn = "BikeHorn.ogg",
    bite = "Bite.ogg", boxing = "BoxingArenaSound.ogg", catmeow = "CatMeow.ogg",
    catmeow2 = "CatMeow2.ogg", gunshot = "FrontalsGunshot.wav", glass = "Glass.mp3",
    kaching = "Kaching.ogg", phone = "Phone.ogg", robotblip = "RobotBlip.ogg",
    sonar = "Sonar.ogg", siren = "WarningSiren.ogg", water = "WaterDrop.ogg",
    wilhelm = "Wilhelm.ogg",
}
EllesmereUI.ALERT_SOUND_NAMES = {
    none = "None", airhorn = "Air Horn", banana = "Banana Peel Slip",
    bikehorn = "Bike Horn", bite = "Bite", boxing = "Boxing Arena",
    catmeow = "Cat Meow", catmeow2 = "Cat Meow 2", gunshot = "Frontals Gunshot",
    glass = "Glass", kaching = "Kaching", phone = "Phone", robotblip = "Robot Blip",
    sonar = "Sonar", siren = "Warning Siren", water = "Water Drop", wilhelm = "Wilhelm",
}
EllesmereUI.ALERT_SOUND_ORDER = {
    "none", "airhorn", "banana", "bikehorn", "bite", "boxing", "catmeow",
    "catmeow2", "gunshot", "glass", "kaching", "phone", "robotblip", "sonar",
    "siren", "water", "wilhelm",
}
-- FRESH paths/names/order tables from the catalogue ("none" = name-only, no path). Safe for the SM appenders.
function EllesmereUI.BuildAlertSoundTables()
    local dir = MEDIA_PATH .. "sounds\\"
    local paths, names, order = {}, {}, {}
    for i, k in ipairs(EllesmereUI.ALERT_SOUND_ORDER) do
        order[i] = k
        names[k] = EllesmereUI.ALERT_SOUND_NAMES[k]
        local f = EllesmereUI.ALERT_SOUND_FILES[k]
        if f then paths[k] = dir .. f end
    end
    return paths, names, order
end

-- Statusbar texture catalogue: same contract as the sound catalogue above.
EllesmereUI.BAR_TEXTURE_FILES = {
    melli = "melli.tga", beautiful = "beautiful.tga", plating = "plating.tga",
    atrocity = "atrocity.tga", divide = "divide.tga", glass = "glass.tga",
    ["fade-right"] = "fade-right.tga", ["thin-line-top"] = "thin-line-top.tga",
    ["thin-line-bottom"] = "thin-line-bottom.tga", fade = "fade.tga",
    ["gradient-lr"] = "gradient-lr.tga", ["gradient-rl"] = "gradient-rl.tga",
    ["gradient-bt"] = "gradient-bt.tga", ["gradient-tb"] = "gradient-tb.tga",
    matte = "matte.tga", sheer = "sheer.tga",
    ["pixels-fill"] = "pixels-fill.tga", ["pixels-dark"] = "pixels-dark.tga",
    ["pixels-bg"] = "pixels-bg.tga",
    ["blinkii-diamonds"] = "blinkii-diamonds.tga",
    ["kringel-window"] = "kringel-window.tga",
}
EllesmereUI.BAR_TEXTURE_NAMES = {
    none = "None", melli = "Melli (ElvUI)", beautiful = "Beautiful",
    plating = "Plating", atrocity = "Atrocity", divide = "Divide",
    glass = "Glass", ["fade-right"] = "Fade Right",
    ["thin-line-top"] = "Thin Line Top", ["thin-line-bottom"] = "Thin Line Bottom",
    fade = "Fade", ["gradient-lr"] = "Gradient Right",
    ["gradient-rl"] = "Gradient Left", ["gradient-bt"] = "Gradient Up",
    ["gradient-tb"] = "Gradient Down", matte = "Matte", sheer = "Sheer",
    ["pixels-fill"] = "Pixels Fill", ["pixels-dark"] = "Pixels Dark",
    ["pixels-bg"] = "Pixels Background",
    ["blinkii-diamonds"] = "Blinkii Diamonds", ["kringel-window"] = "Kringel Window",
}
EllesmereUI.BAR_TEXTURE_ORDER = {
    "none", "melli", "atrocity",
    "fade", "fade-right",
    "thin-line-top", "thin-line-bottom",
    "beautiful", "plating",
    "divide", "glass",
    "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
    "matte", "sheer",
    "pixels-fill", "pixels-dark", "pixels-bg",
    "blinkii-diamonds", "kringel-window",
}
-- FRESH textures/names/order tables. includeExtras=true = full 22-key set; else core set
-- without the pattern textures (blinkii-diamonds, kringel-window). "none" is name-only.
function EllesmereUI.BuildBarTextureTables(includeExtras)
    local dir = MEDIA_PATH .. "textures\\"
    local tex, names, order = {}, {}, {}
    for _, k in ipairs(EllesmereUI.BAR_TEXTURE_ORDER) do
        if includeExtras or (k ~= "blinkii-diamonds" and k ~= "kringel-window") then
            order[#order + 1] = k
            names[k] = EllesmereUI.BAR_TEXTURE_NAMES[k]
            local f = EllesmereUI.BAR_TEXTURE_FILES[k]
            if f then tex[k] = dir .. f end
        end
    end
    return tex, names, order
end

-- Absorb bar style catalogue (Unit Frames absorbs, the Resource Bars health bar
-- overlays): key -> file, the styles drawn as repeating tiles (every other style
-- stretches; striped3 is a stretch texture, never add "striped"), the dropdown
-- names and the shield / heal absorb orders. Readers copy the names and orders
-- before appending the SharedMedia tail; never mutate these.
EllesmereUI.ABSORB_STYLE_TEX = {
    striped         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped3.tga",
    stripedReversed = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-5-reversed.png",
    stripedThick    = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-thick.png",
    stripedThickR   = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\striped-thick-r.png",
    clean           = "Interface\\Buttons\\WHITE8X8",
    blizzard        = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\blizzard.tga",
    largeOutlinedStripes  = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-habsorb-left.png",
    largeOutlinedStripesR = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-habsorb-right.png",
    largeStripes          = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-absorb-left.png",
    largeStripesR         = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\large-absorb-right.png",
    pixelsShield          = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\pixels-shield.tga",
    pixelsShieldEdge      = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\pixels-shield-edge.tga",
    pixelsShieldFill      = "Interface\\AddOns\\EllesmereUI\\media\\textures\\shields\\pixels-shield-fill.tga",
}
EllesmereUI.ABSORB_TILED_STYLES = {
    stripedReversed = true, stripedThick = true, stripedThickR = true,
    largeStripes = true, largeStripesR = true,
    largeOutlinedStripes = true, largeOutlinedStripesR = true,
    pixelsShieldFill = true,
}
EllesmereUI.ABSORB_STYLE_NAMES = {
    none            = "None",
    striped         = "Striped",
    stripedReversed = "Striped Reversed",
    stripedThick    = "Striped Thick",
    stripedThickR   = "Striped Thick Reversed",
    clean           = "Clean (Flat)",
    blizzard        = "Blizzard",
    largeOutlinedStripes  = "Large Outlined Stripes",    -- heal absorb only
    largeOutlinedStripesR = "Large Outlined Stripes R",  -- heal absorb only
    largeStripes          = "Large Stripes",
    largeStripesR         = "Large Stripes R",
    pixelsShield          = "Pixels Shield",
    pixelsShieldEdge      = "Pixels Shield Edge",        -- shield only
    pixelsShieldFill      = "Pixels Shield Fill",        -- shield only
}
EllesmereUI.ABSORB_STYLE_ORDER = { "none", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "largeStripes", "largeStripesR", "pixelsShield", "pixelsShieldEdge", "pixelsShieldFill" }
EllesmereUI.HEAL_ABSORB_STYLE_ORDER = { "none", "striped", "stripedReversed", "stripedThick", "stripedThickR", "clean", "blizzard", "largeOutlinedStripes", "largeOutlinedStripesR", "largeStripes", "largeStripesR", "pixelsShield" }

-- Numeric constants
EllesmereUI.TEXT_WHITE_R = STYLE.TEXT_WHITE_R
EllesmereUI.TEXT_WHITE_G = STYLE.TEXT_WHITE_G
EllesmereUI.TEXT_WHITE_B = STYLE.TEXT_WHITE_B
EllesmereUI.TEXT_DIM_R = STYLE.TEXT_DIM_R
EllesmereUI.TEXT_DIM_G = STYLE.TEXT_DIM_G
EllesmereUI.TEXT_DIM_B = STYLE.TEXT_DIM_B
EllesmereUI.TEXT_DIM_A = STYLE.TEXT_DIM_A
EllesmereUI.TEXT_SECTION_R = STYLE.TEXT_SECTION_R
EllesmereUI.TEXT_SECTION_G = STYLE.TEXT_SECTION_G
EllesmereUI.TEXT_SECTION_B = STYLE.TEXT_SECTION_B
EllesmereUI.TEXT_SECTION_A = STYLE.TEXT_SECTION_A
EllesmereUI.ROW_BG_ODD  = STYLE.ROW_BG_ODD
EllesmereUI.ROW_BG_EVEN = STYLE.ROW_BG_EVEN
EllesmereUI.BORDER_R = STYLE.BORDER_R
EllesmereUI.BORDER_G = STYLE.BORDER_G
EllesmereUI.BORDER_B = STYLE.BORDER_B
EllesmereUI.CONTENT_PAD = CONTENT_PAD
-- Slider
EllesmereUI.SL_TRACK_R = STYLE.SL_TRACK_R
EllesmereUI.SL_TRACK_G = STYLE.SL_TRACK_G
EllesmereUI.SL_TRACK_B = STYLE.SL_TRACK_B
EllesmereUI.SL_TRACK_A = STYLE.SL_TRACK_A
EllesmereUI.SL_FILL_A  = STYLE.SL_FILL_A
EllesmereUI.SL_INPUT_R = STYLE.SL_INPUT_R
EllesmereUI.SL_INPUT_G = STYLE.SL_INPUT_G
EllesmereUI.SL_INPUT_B = STYLE.SL_INPUT_B
EllesmereUI.SL_INPUT_A = STYLE.SL_INPUT_A
EllesmereUI.SL_INPUT_BRD_A = STYLE.SL_INPUT_BRD_A
EllesmereUI.MW_INPUT_ALPHA_BOOST = STYLE.MW_INPUT_ALPHA_BOOST
EllesmereUI.MW_TRACK_ALPHA_BOOST = STYLE.MW_TRACK_ALPHA_BOOST
-- Toggle
EllesmereUI.TG_OFF_R = STYLE.TG_OFF_R
EllesmereUI.TG_OFF_G = STYLE.TG_OFF_G
EllesmereUI.TG_OFF_B = STYLE.TG_OFF_B
EllesmereUI.TG_OFF_A = STYLE.TG_OFF_A
EllesmereUI.TG_ON_A  = STYLE.TG_ON_A
EllesmereUI.TG_KNOB_OFF_R = STYLE.TG_KNOB_OFF_R
EllesmereUI.TG_KNOB_OFF_G = STYLE.TG_KNOB_OFF_G
EllesmereUI.TG_KNOB_OFF_B = STYLE.TG_KNOB_OFF_B
EllesmereUI.TG_KNOB_OFF_A = STYLE.TG_KNOB_OFF_A
EllesmereUI.TG_KNOB_ON_R  = STYLE.TG_KNOB_ON_R
EllesmereUI.TG_KNOB_ON_G  = STYLE.TG_KNOB_ON_G
EllesmereUI.TG_KNOB_ON_B  = STYLE.TG_KNOB_ON_B
EllesmereUI.TG_KNOB_ON_A  = STYLE.TG_KNOB_ON_A
-- Checkbox
EllesmereUI.CB_BOX_R = STYLE.CB_BOX_R
EllesmereUI.CB_BOX_G = STYLE.CB_BOX_G
EllesmereUI.CB_BOX_B = STYLE.CB_BOX_B
EllesmereUI.CB_BRD_A     = STYLE.CB_BRD_A
EllesmereUI.CB_ACT_BRD_A = STYLE.CB_ACT_BRD_A
-- Button
EllesmereUI.BTN_BG_R  = STYLE.BTN_BG_R
EllesmereUI.BTN_BG_G  = STYLE.BTN_BG_G
EllesmereUI.BTN_BG_B  = STYLE.BTN_BG_B
EllesmereUI.BTN_BG_A  = STYLE.BTN_BG_A
EllesmereUI.BTN_BG_HA = STYLE.BTN_BG_HA
EllesmereUI.BTN_BRD_A  = STYLE.BTN_BRD_A
EllesmereUI.BTN_BRD_HA = STYLE.BTN_BRD_HA
EllesmereUI.BTN_TXT_A  = STYLE.BTN_TXT_A
EllesmereUI.BTN_TXT_HA = STYLE.BTN_TXT_HA
-- Dropdown
EllesmereUI.DD_BG_R  = STYLE.DD_BG_R
EllesmereUI.DD_BG_G  = STYLE.DD_BG_G
EllesmereUI.DD_BG_B  = STYLE.DD_BG_B
EllesmereUI.DD_BG_A  = STYLE.DD_BG_A
EllesmereUI.DD_BG_HA = STYLE.DD_BG_HA
EllesmereUI.DD_BRD_A  = STYLE.DD_BRD_A
EllesmereUI.DD_BRD_HA = STYLE.DD_BRD_HA
EllesmereUI.DD_TXT_A  = STYLE.DD_TXT_A
EllesmereUI.DD_TXT_HA = STYLE.DD_TXT_HA
EllesmereUI.DD_ITEM_HL_A  = STYLE.DD_ITEM_HL_A
EllesmereUI.DD_ITEM_SEL_A = STYLE.DD_ITEM_SEL_A
-- Blizzard reskin colors (tooltips, context menus, popups)
EllesmereUI.RESKIN = {
    BG_R = 0.067, BG_G = 0.067, BG_B = 0.067,
    TT_ALPHA   = 0.92,   -- tooltip background alpha
    CTX_ALPHA  = 0.95,   -- blizzard context menu background alpha
    QT_ALPHA   = 0.97,   -- quest tracker right-click menu alpha
    BRD_ALPHA  = 0.18,   -- border alpha (white)
}

-- LFG queue accept countdown defaults (shared by the skin and its options)
EllesmereUI.QUEUE_TIMER = {
    TEXT_R = 1, TEXT_G = 0.831, TEXT_B = 0,   -- #ffd400
    TEXT_SIZE = 9, BAR_HEIGHT = 11, TEXT_OFFSET_Y = 0,
}

-- Unified tooltip background for BOTH the Blizzard tooltip reskin and EUI widget tooltips.
-- Customizable via Blizz UI Enhanced > Blizzard Tooltip (tooltipBgColor/tooltipBgOpacity in
-- EllesmereUIDB); unset = RESKIN palette. Returns r,g,b,a (0 is valid: Lua 0 is truthy, so `or` fallback fires on nil only).
function EllesmereUI.GetTooltipBg()
    local db = EllesmereUIDB
    local c = db and db.tooltipBgColor
    local R = EllesmereUI.RESKIN
    local r = (c and c.r) or R.BG_R
    local g = (c and c.g) or R.BG_G
    local b = (c and c.b) or R.BG_B
    local a = (db and db.tooltipBgOpacity) or R.TT_ALPHA
    return r, g, b, a
end
-- Tooltip border for the Blizzard tooltip reskin (Blizz UI Enhanced > Blizzard Tooltip >
-- Border); unset = white @ BRD_ALPHA, 1px. Returns r,g,b,a,size (0 is valid).
function EllesmereUI.GetTooltipBorder()
    local db = EllesmereUIDB
    local c = db and db.tooltipBorderColor
    local r = (c and c.r) or 1
    local g = (c and c.g) or 1
    local b = (c and c.b) or 1
    local a = (db and db.tooltipBorderOpacity) or EllesmereUI.RESKIN.BRD_ALPHA
    local size = (db and db.tooltipBorderSize) or 1
    return r, g, b, a, size
end
-- Layout
EllesmereUI.DUAL_ITEM_W  = STYLE.DUAL_ITEM_W
EllesmereUI.DUAL_GAP     = STYLE.DUAL_GAP
EllesmereUI.TRIPLE_ITEM_W = STYLE.TRIPLE_ITEM_W
EllesmereUI.TRIPLE_GAP    = STYLE.TRIPLE_GAP

-- Table constants
EllesmereUI.CLASS_COLOR_MAP = CLASS_COLOR_MAP
EllesmereUI.CLASS_ART_MAP   = CLASS_ART_MAP

-- Upgrade track identification (locale-agnostic). Deliberately NOT feature-gated: the QoL
-- upgrade calculator needs it with skin/bag modules disabled. Tiny table, built once.
do
    -- Localized C_Item.GetItemUpgradeInfo().trackString -> canonical English key (the upgrade calculator's season tables key on these).
    local KEYS = {
        -- Explorer / Delve
        Explorer = "Explorer", Expedicionario = "Explorer", Forscher = "Explorer",
        Explorateur = "Explorer", Esploratore = "Explorer", Explorador = "Explorer",
        Delve = "Explorer",
        -- Adventurer
        Adventurer = "Adventurer", Aventurero = "Adventurer", Abenteurer = "Adventurer",
        Aventurier = "Adventurer", Avventuriero = "Adventurer", Aventureiro = "Adventurer",
        -- Veteran
        Veteran = "Veteran", Veterano = "Veteran", ["V\195\169t\195\169ran"] = "Veteran",
        -- Champion
        Champion = "Champion", ["Campe\195\179n"] = "Champion", Campione = "Champion",
        ["Campe\195\163o"] = "Champion",
        -- Hero
        Hero = "Hero", ["H\195\169roe"] = "Hero", Held = "Hero",
        ["H\195\169ros"] = "Hero", Eroe = "Hero", ["Hero\195\173"] = "Hero",
        -- Myth
        Myth = "Myth", Mito = "Myth", Mythos = "Myth", Mythe = "Myth",
        -- ruRU
        ["\208\152\209\129\209\129\208\187\208\181\208\180\208\190\208\178\208\176\209\130\208\181\208\187\209\140"] = "Explorer",
        ["\208\152\209\129\208\186\208\176\209\130\208\181\208\187\209\140 \208\191\209\128\208\184\208\186\208\187\209\142\209\135\208\181\208\189\208\184\208\185"] = "Adventurer",
        ["\208\146\208\181\209\130\208\181\209\128\208\176\208\189"] = "Veteran",
        ["\208\151\208\176\209\137\208\184\209\130\208\189\208\184\208\186"] = "Champion",
        ["\208\147\208\181\209\128\208\190\208\185"] = "Hero",
        ["\208\155\208\181\208\179\208\181\208\189\208\180\208\176"] = "Myth",
        -- koKR
        ["\237\131\144\237\151\152\234\176\128"] = "Explorer", ["\235\170\168\237\151\152\234\176\128"] = "Adventurer",
        ["\235\133\184\235\160\168\234\176\128"] = "Veteran", ["\236\177\148\237\148\188\236\150\184"] = "Champion",
        ["\236\152\129\236\155\133"] = "Hero", ["\236\139\160\237\153\148"] = "Myth",
        -- zhCN
        ["\230\142\162\231\180\162\232\128\133"] = "Explorer", ["\229\134\146\233\153\169\232\128\133"] = "Adventurer",
        ["\232\128\129\229\133\181"] = "Veteran", ["\229\139\135\229\163\171"] = "Champion",
        ["\232\139\177\233\155\132"] = "Hero", ["\231\165\158\232\175\157"] = "Myth",
        -- zhTW
        ["\230\142\162\233\154\170\232\128\133"] = "Explorer", ["\229\134\146\233\154\170\232\128\133"] = "Adventurer",
        ["\231\178\190\229\133\181"] = "Veteran", ["\231\165\158\232\169\177"] = "Myth",
    }

    EllesmereUI.UPGRADE_TRACK_KEYS = KEYS

    -- Returns trackKey (canonical English) | nil, currentLevel, maxLevel; nil trackKey means
    -- a no-track item (crafted, older) or an untranslated trackString.
    function EllesmereUI.GetUpgradeTrackKey(itemLink)
        if not itemLink or not (C_Item and C_Item.GetItemUpgradeInfo) then return nil end
        local info = C_Item.GetItemUpgradeInfo(itemLink)
        if not info then return nil end
        return KEYS[info.trackString or ""], info.currentLevel, info.maxLevel
    end
end

-- Upgrade track color data (shared by BlizzardSkin character/inspect sheets + Bags); only
-- initialized when a consumer feature is enabled.
do
    local en = C_AddOns and C_AddOns.GetAddOnEnableState
    local need = en and (
        (en("EllesmereUIBags") or 0) > 0
        or ((en("EllesmereUIBlizzardSkin") or 0) > 0
            and (not EllesmereUIDB
                 or EllesmereUIDB.themedCharacterSheet ~= false
                 or EllesmereUIDB.themedInspectSheet ~= false))
    )
    if need then
        local W  = { r = 1.00, g = 1.00, b = 1.00 }
        local CH = { r = 0.00, g = 0.44, b = 0.87 }
        local MY = { r = 1.00, g = 0.50, b = 0.00 }
        local HE = { r = 1.00, g = 0.30, b = 1.00 }
        local VE = { r = 0.12, g = 1.00, b = 0.00 }
        local GR = { r = 0.62, g = 0.62, b = 0.62 }

        EllesmereUI._TRACK_WHITE = W
        EllesmereUI._TRACK_RANK = { [GR] = 1, [W] = 2, [VE] = 3, [CH] = 4, [HE] = 5, [MY] = 6 }

        -- Canonical track key -> hue (localized translation lives ONLY in UPGRADE_TRACK_KEYS).
        local map = {
            Explorer   = GR,
            Adventurer = W,
            Veteran    = VE,
            Champion   = CH,
            Hero       = HE,
            Myth       = MY,
        }

        function EllesmereUI.GetUpgradeTrack(itemLink)
            local key, cur, maxL = EllesmereUI.GetUpgradeTrackKey(itemLink)
            local text = (cur and maxL and maxL > 0) and (cur .. "/" .. maxL) or ""
            return text, map[key or ""] or W
        end

        -- Crest bonuses identify the crafting tier independently of quality and
        -- overlapping item levels. Midnight S2 Hero/Myth: 13835/13836.
        -- Source: https://www.raidbots.com/static/data/live/bonuses.json
        local craftedColors = { [13835] = HE, [13836] = MY }
        local function ParseCraftedTrackColor(itemLink)
            local payload = itemLink:match("item:([^|]+)")
            if not payload then return nil end
            local index, lastBonus = 0, 13
            for field in (payload .. ":"):gmatch("([^:]*):") do
                index = index + 1
                if index == 13 then
                    lastBonus = 13 + (tonumber(field) or 0)
                elseif index > 13 then
                    if index > lastBonus then break end
                    local color = craftedColors[tonumber(field)]
                    if color then return color end
                end
            end
            return nil
        end
        -- Memoized per link: the Bags inventory/bank refresh asks for every
        -- untracked gear item on every pass (bag-update bursts), and the parse
        -- above concatenates and splits the link each time. Links are
        -- per-instance, so the memo is bounded and wiped like Bags' sort cache;
        -- `false` records a miss so the parse never repeats for one link.
        local craftedCache, craftedCacheN = {}, 0
        function EllesmereUI.GetCraftedTrackColor(itemLink)
            if type(itemLink) ~= "string" then return nil end
            local hit = craftedCache[itemLink]
            if hit ~= nil then return hit or nil end
            local color = ParseCraftedTrackColor(itemLink)
            if craftedCacheN >= 4000 then wipe(craftedCache); craftedCacheN = 0 end
            craftedCache[itemLink] = color or false
            craftedCacheN = craftedCacheN + 1
            return color
        end

        -- Item-level text color: custom override > upgrade-track hue > crafted-crest hue >
        -- item rarity > white. Shared by character sheet, inspect sheet, equipment flyout and
        -- merchant. upgradeText/upgradeColor: a GetUpgradeTrack result the caller already has.
        function EllesmereUI.GetItemLevelColor(itemLink, itemQuality, upgradeText, upgradeColor)
            if EllesmereUIDB and EllesmereUIDB.charSheetItemLevelUseColor
                and EllesmereUIDB.charSheetItemLevelColor then
                return EllesmereUIDB.charSheetItemLevelColor
            end
            if upgradeText == nil then
                upgradeText, upgradeColor = EllesmereUI.GetUpgradeTrack(itemLink)
            end
            if upgradeText and upgradeText ~= "" and upgradeColor then
                return upgradeColor
            end
            local crafted = EllesmereUI.GetCraftedTrackColor(itemLink)
            if crafted then return crafted end
            if (not EllesmereUIDB or EllesmereUIDB.charSheetColorItemLevel ~= false) and itemQuality then
                local r, g, b = C_Item.GetItemQualityColor(itemQuality)
                return { r = r, g = g, b = b }
            end
            return { r = 1, g = 1, b = 1 }
        end
    end
end

-- File-level PanelPP reference for panel layout code below
local PanelPP = EllesmereUI.PanelPP

-- Critical Strike and Haste as Blizzard's character pane shows them. WoW Forever
-- keeps melee, ranged and spell crit and haste apart and shows the highest with
-- its matching rating. Retail crit makes the same pick between the lowest spell
-- crit across the magic schools (2 = Holy up to MAX_SPELL_SCHOOLS), ranged and
-- melee; retail haste is one figure. The getters go secret while unit stats are
-- restricted, so the source picked on the last readable update is reused until
-- the next one; before any readable update retail gets spell (Blizzard's tie
-- winner), and on Forever casters get spell, hunters ranged (haste only once a
-- ranged total has been read) and everyone else melee.
do
    local FOREVER_CASTER = { MAGE = true, PRIEST = true, WARLOCK = true }
    local statPick = {}
    local foreverRangedHaste

    local function ForeverFallbackPick(kind)
        if statPick[kind] then return statPick[kind] end
        local _, cls = UnitClass("player")
        if not issecretvalue(cls) then
            if FOREVER_CASTER[cls] then return "spell" end
            if cls == "HUNTER" and (kind == "crit" or foreverRangedHaste) then return "ranged" end
        end
        return "melee"
    end

    local function HighestPick(spell, ranged, melee)
        if spell >= ranged and spell >= melee then return "spell" end
        if ranged >= melee then return "ranged" end
        return "melee"
    end

    function EllesmereUI.ForeverCritChance()
        local spell, ranged, melee = GetSpellCritChance(), GetRangedCritChance(), GetCritChance()
        local pick
        if issecretvalue(spell) or issecretvalue(ranged) or issecretvalue(melee) then
            pick = ForeverFallbackPick("crit")
        else
            pick = HighestPick(spell, ranged, melee)
            statPick.crit = pick
        end
        if pick == "spell" then return spell, CR_CRIT_SPELL end
        if pick == "ranged" then return ranged, CR_CRIT_RANGED end
        return melee, CR_CRIT_MELEE
    end

    function EllesmereUI.ForeverHaste()
        local spell, melee = UnitSpellHaste("player"), GetMeleeHaste()
        local rangedBase, quiver = GetRangedHaste()
        local ranged, pick
        if issecretvalue(spell) or issecretvalue(melee) or issecretvalue(rangedBase) or issecretvalue(quiver) then
            pick = ForeverFallbackPick("haste")
            -- The quiver bonus cannot be added to a secret; ranged shows the last readable total.
            ranged = foreverRangedHaste
        else
            ranged = rangedBase + (quiver or 0)
            foreverRangedHaste = ranged
            pick = HighestPick(spell, ranged, melee)
            statPick.haste = pick
        end
        if pick == "spell" then return spell, CR_HASTE_SPELL end
        if pick == "ranged" then return ranged, CR_HASTE_RANGED end
        return melee, CR_HASTE_MELEE
    end

    -- Crit for the running client: the Forever pick there, the retail rule here.
    -- Returns percent, rating index.
    function EllesmereUI.PlayerCritChance()
        if EllesmereUI.IS_FOREVER then return EllesmereUI.ForeverCritChance() end
        local ranged, melee = GetRangedCritChance(), GetCritChance()
        local spell, school = GetSpellCritChance(2), 2
        local secret = issecretvalue(ranged) or issecretvalue(melee) or issecretvalue(spell)
        if not secret then
            for i = 3, MAX_SPELL_SCHOOLS or 7 do
                local s = GetSpellCritChance(i)
                if issecretvalue(s) then secret = true; break end
                if s < spell then spell, school = s, i end
            end
        end
        local pick
        if secret then
            pick = statPick.crit or "spell"
            if pick == "spell" then spell = GetSpellCritChance(statPick.critSchool or 2) end
        else
            pick = HighestPick(spell, ranged, melee)
            statPick.crit, statPick.critSchool = pick, school
        end
        if pick == "spell" then return spell, CR_CRIT_SPELL end
        if pick == "ranged" then return ranged, CR_CRIT_RANGED end
        return melee, CR_CRIT_MELEE
    end
end

-- Group role with the local player's spec as the authority. The role picked
-- when listing a premade group sticks server-side through spec swaps (list a
-- key as tank, swap to dps: UnitGroupRolesAssigned still answers TANK for the
-- life of the group, surviving /reload and a manual role set), so for the
-- player the spec-derived role wins whenever spec data is readable. Other
-- units have no readable spec, so they keep the assigned role; call sites
-- keep their own secret guards on that value (the player's spec role is
-- never secret).
function EllesmereUI.UnitEffectiveRole(unit)
    if UnitIsUnit(unit, "player") then
        local spec = GetSpecialization and GetSpecialization()
        local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
        if role then return role end
    end
    return UnitGroupRolesAssigned(unit)
end

-------------------------------------------------------------------------------
--  Resource trackers (secret-value safe)
--  Maelstrom Weapon (344179), Tip of the Spear (260286) and Devourer soul
--  fragment auras (1225789, 1227702) are Blizzard-whitelisted and stay readable.
-------------------------------------------------------------------------------

-- Tip of the Spear stacks (Survival Hunter). Buff 260286 is WHITELISTED, safe to read
-- in combat. Max 3 stacks.
function EllesmereUI.GetTipOfTheSpear()
    local aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(260286)
    return (aura and aura.applications or 0), 3
end

-- DH Soul Fragment count (current, max). Vengeance: C_Spell.GetSpellCastCount(228477)
-- returns a SECRET value the caller must handle (StatusBar or similar). Devourer (hero
-- spec 1480): auras 1225789/1227702 are WHITELISTED, safe to read.
-- Cached spec ID: GetSoulFragments is polled EVERY FRAME and GetSpecialization +
-- GetSpecializationInfo allocate fresh strings per call (~1.9 kb garbage/call, the
-- dominant memory churn). Spec changes only on swap: cache it, refresh on spec events.
EllesmereUI._RefreshSpecID = function()
    local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    EllesmereUI._specID = (spec and C_SpecializationInfo.GetSpecializationInfo(spec)) or 0
end
EllesmereUI._specWatcher = EllesmereUI._specWatcher or CreateFrame("Frame")
EllesmereUI._specWatcher:RegisterEvent("PLAYER_LOGIN")
EllesmereUI._specWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
EllesmereUI._specWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
EllesmereUI._specWatcher:SetScript("OnEvent", EllesmereUI._RefreshSpecID)

function EllesmereUI.GetSoulFragments()
    local specID = EllesmereUI._specID
    if not specID then           -- pre-login / not resolved yet: resolve once
        EllesmereUI._RefreshSpecID()
        specID = EllesmereUI._specID
    end
    if specID == 581 then -- Vengeance
        local cur = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
        return cur, 6
    elseif specID == 1480 then -- Devourer (hero spec)
        -- In Void Metamorphosis (1217607): stacks from Silence the Whispers (1227702),
        -- max 40. Outside: Dark Heart (1225789), max 50 (35 with Soul Glutton 1247534).
        -- Surrender to the Void (PvP talent 1261423) adds 50 to whichever value applies.
        local inMeta = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(1217607)
        local aura, max
        if inMeta then
            aura = C_UnitAuras.GetPlayerAuraBySpellID(1227702)
            max = 40
        else
            aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(1225789)
            max = (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(1247534)) and 35 or 50
            if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(1261423) then
                max = max + 50
            end
        end
        return (aura and aura.applications or 0), max
    end
    -- Havoc or unknown spec: no soul fragments
    return 0, 0
end

-- Enhancement Shaman Maelstrom Weapon stacks (current, max). Buff 344179 is WHITELISTED,
-- safe to read in combat. Base max 5 (10 with Raging Maelstrom talent 384143).
function EllesmereUI.GetMaelstromWeapon()
    local aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(344179)
    local max = 5
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(384143) then
        max = 10
    end
    return (aura and aura.applications or 0), max
end

EllesmereUI.RESOURCE_BAR_ANCHOR_KEYS = {
    none = true,
    mouse = true,
    partyframe = true,
    playerframe = true,
    erb_classresource = true,
    erb_powerbar = true,
    erb_health = true,
    erb_castbar = true,
    erb_cdm = true,
}

do
local PARTY_FRAME_SOURCES = {
    { addon = "ElvUI",  prefix = "ElvUF_PartyGroup1UnitButton", count = 5 },
    { addon = "Cell",   prefix = "CellPartyFrameMember",        count = 5 },
    { addon = nil,      prefix = "CompactPartyFrameMember",     count = 5 },
    { addon = nil,      prefix = "CompactRaidFrame",            count = 40 },
}

local PLAYER_FRAME_SOURCES = {
    { addon = "EllesmereUIUnitFrames", global = "EllesmereUIUnitFrames_Player" },
    { addon = "ElvUI",                 global = "ElvUF_Player" },
}

local _cachedPartyFrame   = nil
local _cachedPlayerFrame  = nil
local _cachedRosterToken  = -1

local function RosterToken()
    return GetNumGroupMembers()
end

local function CacheValid()
    return _cachedRosterToken == RosterToken()
end

-- Invalidate both caches. Called by CDM and ResourceBars on GROUP_ROSTER_UPDATE
-- and PLAYER_SPECIALIZATION_CHANGED so the next lookup rescans.
function EllesmereUI.InvalidateFrameCache()
    _cachedPartyFrame  = nil
    _cachedPlayerFrame = nil
    _cachedRosterToken = -1
end

function EllesmereUI.FindPlayerPartyFrame()
    if _cachedPartyFrame and CacheValid() and _cachedPartyFrame:IsVisible() then
        return _cachedPartyFrame
    end
    _cachedPartyFrame  = nil
    _cachedRosterToken = RosterToken()

    for _, src in ipairs(PARTY_FRAME_SOURCES) do
        if not src.addon or C_AddOns.IsAddOnLoaded(src.addon) then
            for i = 1, src.count do
                local frame = _G[src.prefix .. i]
                if frame and frame.GetAttribute and frame:GetAttribute("unit") == "player"
                   and frame.IsVisible and frame:IsVisible() then
                    _cachedPartyFrame = frame
                    return frame
                end
            end
        end
    end

    if C_AddOns.IsAddOnLoaded("DandersFrames") then
        local container = _G["DandersPartyContainer"]
        if container and container.IsVisible and container:IsVisible() then
            _cachedPartyFrame = container
            return container
        end
    end

    return nil
end

function EllesmereUI.FindPlayerUnitFrame()
    if _cachedPlayerFrame and CacheValid() and _cachedPlayerFrame:IsVisible() then
        local u = _cachedPlayerFrame.GetAttribute and _cachedPlayerFrame:GetAttribute("unit")
        if not u or UnitIsUnit(u, "player") then
            return _cachedPlayerFrame
        end
    end
    _cachedPlayerFrame = nil
    _cachedRosterToken = RosterToken()

    for _, src in ipairs(PLAYER_FRAME_SOURCES) do
        if C_AddOns.IsAddOnLoaded(src.addon) then
            local frame = _G[src.global]
            if frame and frame.IsVisible and frame:IsVisible() then
                _cachedPlayerFrame = frame
                return frame
            end
        end
    end

    if C_AddOns.IsAddOnLoaded("DandersFrames") then
        local header = _G["DandersPartyHeader"]
        if header then
            for i = 1, 5 do
                local child = header:GetAttribute("child" .. i)
                if child and child.GetAttribute and child:GetAttribute("unit") == "player"
                   and child.IsVisible and child:IsVisible() then
                    _cachedPlayerFrame = child
                    return child
                end
            end
        end
    end

    local blizz = _G["PlayerFrame"]
    if blizz and blizz.IsVisible and blizz:IsVisible() then
        _cachedPlayerFrame = blizz
        return blizz
    end

    return nil
end
end

-- Tip of the Spear / Whirlwind Stacks: tracked manually above via UNIT_SPELLCAST_SUCCEEDED.

EllesmereUI.THEME_PRESETS   = THEME_PRESETS
EllesmereUI.THEME_ORDER     = THEME_ORDER

-- Path strings Keep the locale glyph-font fallback: plain EXPRESSWAY here would drop it
-- and render CJK/Cyrillic clients as boxes for every later consumer.
EllesmereUI.EXPRESSWAY = LOCALE_FONT_FALLBACK or EXPRESSWAY
EllesmereUI.MEDIA_PATH = MEDIA_PATH
EllesmereUI.ICONS_PATH = ICONS_PATH

-------------------------------------------------------------------------------
--  Portal flyout hearthstone row: shared resolution logic.
--  Called lazily from chat + minimap portal flyouts on Show only.
-------------------------------------------------------------------------------
do
    local HEARTH_TOYS = {
        54452,  -- Ethereal Portal
        64488,  -- The Innkeeper's Daughter
        93672,  -- Dark Portal
        28585,  -- Ruby Slippers
        142542, -- Tome of Town Portal
        163045, -- Headless Horseman's Hearthstone
        162973, -- Greatfather Winter's Hearthstone
        165669, -- Lunar Elder's Hearthstone
        165670, -- Peddlefeet's Lovely Hearthstone
        165802, -- Noble Gardener's Hearthstone
        166746, -- Fire Eater's Hearthstone
        166747, -- Brewfest Reveler's Hearthstone
        168907, -- Holographic Digitalization Hearthstone
        172179, -- Eternal Traveler's Hearthstone
        184353, -- Kyrian Hearthstone
        180290, -- Night Fae Hearthstone
        182773, -- Necrolord Hearthstone
        183716, -- Venthyr Sinstone
        188952, -- Dominated Hearthstone
        190237, -- Broker Translocation Matrix
        190196, -- Enlightened Hearthstone
        193588, -- Timewalker's Hearthstone
        200630, -- Ohn'ir Windsage's Hearthstone
        206195, -- Path of the Naaru
        209035, -- Hearthstone of the Flame
        210455, -- Draenic Hologem
        208704, -- Deepdweller's Earthen Hearthstone
        212337, -- Stone of the Hearth
        228940, -- Notorious Thread's Hearthstone
        235016, -- Redeployment Module
        236687, -- Explosive Hearthstone
        245970, -- P.O.S.T. Master's Express Hearthstone
        246565, -- Cosmic Hearthstone
        250411, -- Timerunner's Hearthstone
        257736, -- Lightcalled Hearthstone
        263489, -- Naaru's Enfold
        263933, -- Preyseeker's Hearthstone
        265100, -- Corewarden's Hearthstone
        142298, -- Astonishingly Scarlet Slippers
        264367, -- Mushroom
    }
    local SHAMAN_ASTRAL_RECALL = 556
    local DALARAN_HS = 253629
    local DALARAN_HS_FALLBACK = 140192
    local HOUSING_ICON = MEDIA_PATH .. "icons\\housing-teleport.png"

    -- Get the correct icon for a toy (not the base "learn" item icon)
    local function ToyIcon(id)
        if C_ToyBox and C_ToyBox.GetToyInfo then
            local _, _, icon = C_ToyBox.GetToyInfo(id)
            if icon then return icon end
        end
        return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or 134414
    end

    -- M+/raid/PvP instance check -- guards against tainted execution.
    -- Dev mode counts as protected: /euidev forces the addon*RestrictionsForced
    -- CVars, which create the same restricted/secret-value environment anywhere.
    local function InProtectedInstance()
        if EllesmereUI.IsDevModeActive and EllesmereUI.IsDevModeActive() then return true end
        local _, instanceType = IsInInstance()
        if instanceType == "raid" and InCombatLockdown() then return true end
        if instanceType == "party" and C_ChallengeMode
            and C_ChallengeMode.IsChallengeModeActive
            and C_ChallengeMode.IsChallengeModeActive() then
            return true
        end
        if (instanceType == "pvp" or instanceType == "arena") and InCombatLockdown() then return true end
        return false
    end
    EllesmereUI.InProtectedInstance = InProtectedInstance

    -- Check if a toy/item hearthstone is on cooldown.
    -- Skips in M+/raid combat to avoid secret value errors.
    local function IsHearthOnCD(id)
        if InProtectedInstance() then return true end
        if C_Container and C_Container.GetItemCooldown then
            local ok, start, dur = pcall(C_Container.GetItemCooldown, id)
            if ok and start and dur and dur > 1.5 then return true end
        end
        return false
    end

    -- Resolve slot 1: For Shamans with Astral Recall known:
    --   In M+/raid combat -> always Astral Recall (no CD checks, no secret values)
    --   If any owned toy is on CD -> Astral Recall (shorter CD)
    --   Otherwise -> random owned toy (variety)
    -- For non-Shamans: random owned toy HS, fallback to item 6948
    function EllesmereUI.ResolveHearthSlot()
        local _, cls = UnitClass("player")
        local isShaman = cls == "SHAMAN" and IsPlayerSpell(SHAMAN_ASTRAL_RECALL)

        if isShaman and InProtectedInstance() then
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(SHAMAN_ASTRAL_RECALL)
            return "spell", SHAMAN_ASTRAL_RECALL, info and info.iconID or 136010
        end

        -- Collect owned hearthstone toys (6948 is always in bags, not a toy)
        local owned = {}
        for _, id in ipairs(HEARTH_TOYS) do
            local hasToy = PlayerHasToy and PlayerHasToy(id)
            if hasToy then
                owned[#owned + 1] = id
            end
        end

        if isShaman and #owned > 0 then
            local anyOnCD = false
            for _, id in ipairs(owned) do
                if IsHearthOnCD(id) then anyOnCD = true; break end
            end
            if anyOnCD then
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(SHAMAN_ASTRAL_RECALL)
                return "spell", SHAMAN_ASTRAL_RECALL, info and info.iconID or 136010
            end
        end

        if #owned == 0 then
            local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(6948) or 134414
            return "item", 6948, icon
        end
        local pick = owned[math.random(#owned)]
        return "item", pick, ToyIcon(pick)
    end

    -- Resolve slot 2: Dalaran HS 253629 > fallback 140192
    function EllesmereUI.ResolveDalaranSlot()
        local hasPrimary = PlayerHasToy and PlayerHasToy(DALARAN_HS)
        local id = hasPrimary and DALARAN_HS or DALARAN_HS_FALLBACK
        return "item", id, ToyIcon(id)
    end

    -- Resolve slot 3: Housing dashboard (click handler, not a spell)
    function EllesmereUI.ResolveHousingSlot()
        return "housing", 0, HOUSING_ICON
    end
end

-- Safe scroll range helper (avoids tainted secret number values)
function EllesmereUI.SafeScrollRange(sf)
    local ok, val = pcall(sf.GetVerticalScrollRange, sf)
    if ok and val then
        local ok2, n = pcall(tonumber, val)
        if ok2 and n then
            local ok3, gt = pcall(function() return n > 0 end)
            if ok3 and gt then return n end
        end
    end
    return 0
end

-- Smooth wheel scroll + thin draggable scrollbar (shown only on overflow) for a ScrollFrame.
-- opts: step (45), thumbMin (30), width (4), rightInset (2), topInset (4), bottomInset (topInset),
-- trackParent (sf), level (2, above trackParent), trackAlpha (0.02), thumbAlpha (0.27),
-- child (range = child height - sf height, else SafeScrollRange), onScroll(v), thumb (false = wheel only),
-- panelWheel (true: a surface inside the options panel, where Shift + wheel scales the panel instead).
-- Returns UpdateThumb, ScrollTo(v) (immediate: stops the lerp, clamps, syncs the thumb).
-- While a controller is in use the bar also carries step arrows and a page strip.
function EllesmereUI.AttachSmoothScrollbar(sf, opts)
    opts = opts or {}
    local step, child, onScroll = opts.step or 45, opts.child, opts.onScroll
    local function MaxScroll()
        if child then return math.max(0, child:GetHeight() - sf:GetHeight()) end
        return EllesmereUI.SafeScrollRange(sf)
    end
    local UpdateThumb = function() end
    local track, thumb
    if opts.thumb ~= false then
        local w, thumbMin, tp = opts.width or 4, opts.thumbMin or 30, opts.trackParent or sf
        local top = opts.topInset or 4
        track = CreateFrame("Frame", nil, tp)
        track:SetWidth(w)
        track:SetPoint("TOPRIGHT", tp, "TOPRIGHT", -(opts.rightInset or 2), -top)
        track:SetPoint("BOTTOMRIGHT", tp, "BOTTOMRIGHT", -(opts.rightInset or 2), opts.bottomInset or top)
        track:SetFrameLevel(tp:GetFrameLevel() + (opts.level or 2))
        track:Hide()
        SolidTex(track, "BACKGROUND", 1, 1, 1, opts.trackAlpha or 0.02):SetAllPoints()
        thumb = CreateFrame("Button", nil, track)
        thumb:SetWidth(w)
        thumb:SetFrameLevel(track:GetFrameLevel() + 1)
        thumb:EnableMouse(true)
        thumb:RegisterForDrag("LeftButton")
        thumb:SetScript("OnDragStart", function() end)
        thumb:SetScript("OnDragStop", function() end)
        SolidTex(thumb, "ARTWORK", 1, 1, 1, opts.thumbAlpha or 0.27):SetAllPoints()
        -- Controller cursor: a drag-only control, never a stop.
        EllesmereUI.PadHint(thumb, "nodeignore")
        UpdateThumb = function()
            local maxScroll = MaxScroll()
            if maxScroll <= 0 then track:Hide(); return end
            track:Show()
            local trackH = track:GetHeight()
            local visH = sf:GetHeight()
            local thumbH = math.max(thumbMin, trackH * (visH / (visH + maxScroll)))
            thumb:SetHeight(thumbH)
            -- Guarded read: the preview scroll frames can return a secret value.
            local cur = 0
            local ok, val = pcall(sf.GetVerticalScroll, sf)
            if ok and val then
                local ok2, n = pcall(tonumber, val)
                if ok2 and n then cur = n end
            end
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -(cur / maxScroll * (trackH - thumbH)))
        end
    end

    local target, smoothing = 0, false
    local smoothFrame = CreateFrame("Frame", nil, sf)
    smoothFrame:Hide()
    local function Stop() smoothing = false; smoothFrame:Hide() end
    local function Set(v)
        sf:SetVerticalScroll(v)
        UpdateThumb()
        if onScroll then onScroll(v) end
    end
    smoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = sf:GetVerticalScroll()
        local maxScroll = MaxScroll()
        target = math.max(0, math.min(maxScroll, target))
        local diff = target - cur
        if math.abs(diff) < 0.3 then
            Stop(); Set(target)
            return
        end
        Set(math.max(0, math.min(maxScroll, cur + diff * math.min(1, 12 * elapsed))))
    end)
    sf:EnableMouseWheel(true)
    local panelWheel = opts.panelWheel
    sf:SetScript("OnMouseWheel", function(self, delta)
        if panelWheel and EllesmereUI._ShiftWheelScale(delta) then return end
        local maxScroll = MaxScroll()
        if maxScroll <= 0 then return end
        local base = smoothing and target or self:GetVerticalScroll()
        target = math.max(0, math.min(maxScroll, base - delta * step))
        if not smoothing then smoothing = true; smoothFrame:Show() end
    end)

    local function ScrollTo(v)
        Stop()
        target = math.max(0, math.min(MaxScroll(), v))
        Set(target)
    end
    if not thumb then return UpdateThumb, ScrollTo end
    sf:SetScript("OnScrollRangeChanged", function() UpdateThumb() end)

    -- Controller cursor: it scrolls the frame itself to reach a control, so the
    -- thumb follows (the lerp and a thumb drag already paint their own frames).
    if EllesmereUI.PadCP() then
        sf:HookScript("OnVerticalScroll", function()
            if not smoothing and not thumb:GetScript("OnUpdate") then UpdateThumb() end
        end)
    end

    -- Controller (no mouse wheel): step arrows and a page strip on the bar, built
    -- and shown only when a controller is in use as the bar appears.
    local padSteps
    local function PadScrollBy(delta)
        local maxScroll = MaxScroll()
        if maxScroll <= 0 then return end
        local base = smoothing and target or sf:GetVerticalScroll()
        target = math.max(0, math.min(maxScroll, base + delta))
        if not smoothing then smoothing = true; smoothFrame:Show() end
    end
    local function PadArrow(point, icon, delta)
        local b = CreateFrame("Button", nil, padSteps)
        b:SetSize(track:GetWidth() + 10, 14)
        b:SetPoint(point, track, point, 0, 0)
        b:SetFrameLevel(track:GetFrameLevel() + 1)
        SolidTex(b, "BACKGROUND", 0, 0, 0, 0.6):SetAllPoints()
        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetTexture(ICONS_PATH .. icon)
        tex:SetSize(14, 14)
        tex:SetPoint("CENTER")
        tex:SetAlpha(0.6)
        b:SetScript("OnEnter", function() tex:SetAlpha(1) end)
        b:SetScript("OnLeave", function() tex:SetAlpha(0.6) end)
        b:SetScript("OnClick", function() PadScrollBy(delta) end)
    end
    track:HookScript("OnShow", function()
        if not EllesmereUI.PadInUse() then
            if padSteps then padSteps:Hide() end
            return
        end
        if not padSteps then
            padSteps = CreateFrame("Frame", nil, track)
            padSteps:SetAllPoints(track)
            padSteps:SetFrameLevel(track:GetFrameLevel())
            -- Page strip under the thumb: a click pages toward the pointer.
            local strip = CreateFrame("Button", nil, padSteps)
            strip:SetPoint("TOPLEFT", track, "TOPLEFT", -5, 0)
            strip:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 5, 0)
            strip:SetFrameLevel(track:GetFrameLevel())
            strip:SetScript("OnClick", function()
                local _, ty = thumb:GetCenter()
                if not ty then return end
                local _, cy = GetCursorPosition()
                local amount = sf:GetHeight() * 0.9
                PadScrollBy((cy / thumb:GetEffectiveScale() > ty) and -amount or amount)
            end)
            -- The controller cursor cannot aim a page click: its stops are the arrows.
            EllesmereUI.PadHint(strip, "nodeignore")
            PadArrow("TOP", "eui-arrow-up3.png", -step)
            PadArrow("BOTTOM", "eui-arrow-down3.png", step)
            -- The thumb stays grabbable over the arrows; at either end it only
            -- covers the arrow that cannot scroll further.
            thumb:SetFrameLevel(track:GetFrameLevel() + 2)
        end
        padSteps:Show()
    end)

    thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        Stop()
        local _, cy = GetCursorPosition()
        local startY = cy / self:GetEffectiveScale()
        local startScroll = sf:GetVerticalScroll()
        self:SetScript("OnUpdate", function(self2)
            if not IsMouseButtonDown("LeftButton") then self2:SetScript("OnUpdate", nil); return end
            Stop()
            local _, cy2 = GetCursorPosition()
            local maxTravel = track:GetHeight() - self2:GetHeight()
            if maxTravel <= 0 then return end
            local maxScroll = MaxScroll()
            target = math.max(0, math.min(maxScroll,
                startScroll + ((startY - cy2 / self2:GetEffectiveScale()) / maxTravel) * maxScroll))
            Set(target)
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then self:SetScript("OnUpdate", nil) end
    end)
    return UpdateThumb, ScrollTo
end

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
EllesmereUI._STYLE          = STYLE
EllesmereUI._THEME_BG_FILES = THEME_BG_FILES
EllesmereUI._IS_STANDALONE  = IS_STANDALONE

-------------------------------------------------------------------------------
--  MakeUnlockElement  --  shared factory for unlock mode element tables.
--  Required fields in opts:
--    key        (string)   unique element key, e.g. "MainBar", "ERB_Health"
--    label      (string)   human-readable name shown on the mover
--    group      (string)   grouping label in menus, e.g. "Action Bars"
--    order      (number)   sort order (lower = earlier)
--    getFrame   (function) -> frame  returns the movable frame
--    getSize    (function) -> w, h   returns authoritative width, height
--    savePos    (function(key, point, relPoint, x, y))  persist + apply
--    loadPos    (function(key)) -> { point, relPoint, x, y } or nil
--    clearPos   (function(key))  remove saved position
--    applyPos   (function(key))  apply saved position to the live frame
--
--  Optional fields:
--    setWidth   (function(key, w))  set element width and rebuild
--    setHeight  (function(key, h))  set element height and rebuild
--    isHidden   (function(key)) -> bool  true if element is disabled/hidden
--    isAnchored (function(key)) -> bool  true if anchored to another element
--    onLiveMove (function(key))  called after every mover-driven placement of
--               the frame: drag start, each drag frame, drag stop, arrow/cog
--               nudge. Runs before the anchor chain reads the frame's rect.
--    ownsPosition (boolean) the module alone places the frame from its saved
--               position (main chat, whose spot Blizzard's Edit Mode also
--               applies): anchor links never move it and it offers no link or
--               screen-edge menu, so no link becomes a third owner of the frame.
--               Mover drags and nudges still move it and save through savePos
--    linkedKeys (table)  list of element keys that move with this one
--    noResize   (boolean) true for Blizzard elements that cannot be resized
--    sizeFixedByLook (boolean) the current look fixes the element's size
--               (Blizzard Style unit frames): getSize reports that look's size,
--               not the element's own setting. Stored width/height matches to
--               and from it are kept, and spec layouts never bank that size
--    getSettingSize (function(key) -> w, h)  the size the element's own
--               settings give, whatever the look (read with sizeFixedByLook)
--    getBottomExtra (function(key) -> height)  extra height, in the frame's
--               units, the mover extends BELOW the frame (a boss cast bar,
--               the Blizzard Style cast bar text box)
--    getInsets  (function(key) -> l, r, t, b)  visual insets from the frame's
--               box to the rect the mover outlines (Blizzard Style unit frames)
--    detachedMover (boolean) the frame refuses dependents (it carries a
--               forbidden layout aspect), so the mover takes its screen spot by
--               absolute anchor instead of anchoring to it
--    loadRawPos (function(key)) -> the STORED position table, for an element
--               whose stored form is not the one loadPos reports
--    saveRawPos (function(key, p))  store a table loadRawPos returned. Spec
--               override unlock layers bank and restore positions through this
--               pair when an element gives both (loadPos/savePos otherwise)
--  This table is a WHITELIST: a field left out here never reaches the unlock
--  module, silently.
-------------------------------------------------------------------------------
function EllesmereUI.MakeUnlockElement(opts)
    return {
        key           = opts.key,
        label         = opts.label,
        group         = opts.group,
        order         = opts.order,
        getFrame      = opts.getFrame,
        getSize       = opts.getSize,
        savePosition  = opts.savePos,
        loadPosition  = opts.loadPos,
        clearPosition = opts.clearPos,
        applyPosition = opts.applyPos,
        setWidth      = opts.setWidth,
        setHeight     = opts.setHeight,
        isHidden      = opts.isHidden,
        isAnchored    = opts.isAnchored,
        onLiveMove    = opts.onLiveMove,
        ownsPosition  = opts.ownsPosition,
        linkedKeys    = opts.linkedKeys,
        noResize          = opts.noResize,
        linkedDimensions  = opts.linkedDimensions,
        -- noInitHook: self-positioning element; ApplySavedPositions /
        -- NotifyElementResized (EUI_UnlockMode) must not re-apply its stored position.
        noInitHook        = opts.noInitHook,
        loadRawPosition   = opts.loadRawPos,
        saveRawPosition   = opts.saveRawPos,
        noAnchorTarget    = opts.noAnchorTarget,
        noAnchorTo        = opts.noAnchorTo,
        -- allowMatchSource: show the width/height MATCH buttons even when resize is
        -- disabled (noResize), so the element can size-match TO another element.
        -- noSizeMatchTarget: other elements may NOT size-match TO this one.
        allowMatchSource  = opts.allowMatchSource,
        noSizeMatchTarget = opts.noSizeMatchTarget,
        sizeFixedByLook   = opts.sizeFixedByLook,
        getSettingSize    = opts.getSettingSize,
        -- matchUnavailable: function(key) -> reason string when a NEW width/height match
        -- is impossible (action bars in Blizzard Style, where EUI does not control
        -- sizing). Clearing an existing match stays allowed.
        matchUnavailable  = opts.matchUnavailable,
        -- keepMoverWhenAnchored: isAnchored() reflecting a module option (ERB "Anchor
        -- To") still gets a mover -- position-locked (no drag/nudge/anchor link), but
        -- resize and width/height matching stay available.
        keepMoverWhenAnchored = opts.keepMoverWhenAnchored,
        -- moverBg: optional {r,g,b} tint for the mover background (default: dark overlay).
        -- moverTooltip: optional hover tooltip (string or function) on the mover
        -- (first use: CDM's Additional Bar Offset marker).
        -- subtitle: optional dimmed helper line under the mover label.
        moverBg           = opts.moverBg,
        moverTooltip      = opts.moverTooltip,
        subtitle          = opts.subtitle,
        getBottomExtra    = opts.getBottomExtra,
        getInsets         = opts.getInsets,
        -- getMatchPad: function(key) -> padW, padH the element draws OUTSIDE its
        -- own rect (chrome such as a classic resource bar's frame); width/height
        -- matching adds it on the target side and takes it off the source side so
        -- matches line up with what is on screen. nil = nothing outside the rect.
        getMatchPad       = opts.getMatchPad,
        detachedMover     = opts.detachedMover,
    }
end

-------------------------------------------------------------------------------
--  Lazy-load stub: ResolveThemeColor -- minimal version for PLAYER_LOGIN, before the
--  Widgets file initializes and replaces it with the full (animated) version.
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
--  Load-order stub: GetActiveTheme -- the real one lives in EllesmereUI_UICore.lua
--  (loads right after this file); covers callers in the rest of THIS file's scope. Identical body, harmlessly replaced.
-------------------------------------------------------------------------------
if not EllesmereUI.GetActiveTheme then
    EllesmereUI.GetActiveTheme = function()
        return EllesmereUIDB and EllesmereUIDB.activeTheme or EllesmereUI.DEFAULT_THEME
    end
end

-------------------------------------------------------------------------------
--  Load-order stub: ResolveActiveAccent -- the real one (and its ResolveProfileAccent /
--  GetActiveProfileData helpers) lives in EllesmereUI_UICore.lua, which loads right after
--  this file; mirrors ResolveProfileAccent's resolution order so the accent matches.
-------------------------------------------------------------------------------
if not EllesmereUI.ResolveActiveAccent then
    EllesmereUI.ResolveActiveAccent = function()
        local theme = (EllesmereUIDB and EllesmereUIDB.activeTheme) or EllesmereUI.DEFAULT_THEME
        local themeR, themeG, themeB = EllesmereUI.ResolveThemeColor(theme)
        local db = EllesmereUIDB
        local p = db and db.profiles and db.profiles[db.activeProfile or "Default"]
        local acc = p and p.euiAccent
        -- 1) per-profile euiAccent
        if acc and acc.useClass then
            local c = CLASS_COLOR_MAP[playerClass]
            if c then return c.r, c.g, c.b end
        end
        if acc and acc.custom then
            local ca = acc.custom
            return ca.r or themeR, ca.g or themeG, ca.b or themeB
        end
        -- 2) frozen global root (only when no explicit per-profile euiAccent)
        if (not acc) and db and db.useClassAccentColor then
            local c = CLASS_COLOR_MAP[playerClass]
            if c then return c.r, c.g, c.b end
        end
        local gca = db and db.customAccentColor
        if gca then return gca.r or themeR, gca.g or themeG, gca.b or themeB end
        -- 3) theme color
        return themeR, themeG, themeB
    end
end

-------------------------------------------------------------------------------
--  SharedMedia helpers
-------------------------------------------------------------------------------

-- Resolve a texture key to a file path; "sm:" keys fall back to LSM:Fetch when missing
-- from the local table (covers a SharedMedia addon loading after our init).
--   texTable  - the addon's local texture lookup (e.g. TBB_TEXTURES)
--   key       - the saved texture key ("sm:Some Pack" or "beautiful")
--   fallback  - path to use if nothing resolves (optional)
function EllesmereUI.ResolveTexturePath(texTable, key, fallback)
    if not key then return fallback end
    local path = texTable and texTable[key]
    if path then return path end
    -- A non-string key is legacy data, not a lookup miss: some settings were boolean toggles
    -- before becoming style dropdowns (showPlayerAbsorb). Callers gate on truthiness, so a
    -- stored `true` reaches the :match below and raises inside unit frame init, aborting the
    -- whole build (white player frame, unopenable tab); treat it as unset. Deliberately AFTER
    -- the direct lookup: the raise is in the :match, so this stays a pure crash fix and can never turn a table hit into a fallback.
    if type(key) ~= "string" then return fallback end
    local smName = key:match("^sm:(.+)")
    if smName then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local fetched = LSM:Fetch("statusbar", smName)
            if fetched then
                -- Cache it back into the table so future lookups are instant
                if texTable then texTable[key] = fetched end
                return fetched
            end
        end
    end
    return fallback
end

-------------------------------------------------------------------------------
--  Append LibSharedMedia-3.0 statusbar textures into a runtime texture table.
--  Signature: AppendSharedMediaTextures(names, order, castBarNames, textures)
--    names        - key -> display-name string table
--    order        - ordered array of keys (receives "---" + SM keys appended)
--    castBarNames - optional secondary names table (may be nil)
--    textures     - key -> texture-path table
--  Safe to call repeatedly; duplicate keys are skipped via the textures guard. Registered
--  tables stay current for the session: one LibSharedMedia_Registered callback appends
--  LATE-registered textures (addons register at varying times) into every consumer's tables, so dropdowns always list ALL SharedMedia.
-------------------------------------------------------------------------------
-- Consumers keyed by their `textures` table identity (dedups repeat calls).
-- On EllesmereUI (not new file-scope locals): this file is at the local/upvalue cap.
EllesmereUI._smTexConsumers = EllesmereUI._smTexConsumers or {}

function EllesmereUI.AppendSharedMediaTextures(names, order, castBarNames, textures)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end

    -- Icon textures some SM packs wrongly register as statusbar (cached once).
    local blacklist = EllesmereUI._smTexBlacklist
    if not blacklist then
        blacklist = { play_icon = true, stop_icon = true, user_icon = true, users_icon = true }
        EllesmereUI._smTexBlacklist = blacklist
    end

    -- Append one SM texture (by LSM name) into a consumer's tables if absent; the "---"
    -- separator is added once, lazily, before the first SM key. Defined here (not file scope) and captured as an upvalue by the once-installed registration callback.
    local function AppendOne(c, name, path)
        if not path then return end
        local key = "sm:" .. name
        if c.textures[key] or blacklist[name] then return end
        -- Drop only an exact duplicate: a native entry with the SAME display
        -- name AND the same file would otherwise list that texture twice,
        -- once in the module's own section and once in the SharedMedia tail.
        local nativePath = c.nativeNames and c.nativeNames[string.lower(name)]
        if nativePath and nativePath == path then return end
        if not c.sepAdded then
            c.order[#c.order + 1] = "---"
            c.sepAdded = true
        end
        c.textures[key]       = path
        c.names[key]          = name
        c.order[#c.order + 1] = key
        if c.castBarNames then c.castBarNames[key] = name end
    end

    -- Register this consumer (dedup by textures-table identity); sepAdded stays false so the first SM key adds exactly one "---" (the dedup guard prevents a second).
    local c = EllesmereUI._smTexConsumers[textures]
    if not c then
        -- The consumer's own display-name -> file pairs at registration (its
        -- module-side list is complete by then; SM keys are not in it yet),
        -- for the exact-duplicate test above. Keyed by NAME, not by file
        -- alone: several modules point an entry of their own at a file the
        -- library also ships under a different name -- Raid Frames calls the
        -- blank texture "None" where the library calls it "Solid" -- and
        -- matching on the file alone would swallow the library's entry and
        -- leave the user unable to find that texture by name.
        local native = {}
        for k, path in pairs(textures) do
            local nm = names and names[k]
            if nm then native[string.lower(nm)] = path end
        end
        c = { names = names, order = order, castBarNames = castBarNames, textures = textures, nativeNames = native }
        EllesmereUI._smTexConsumers[textures] = c
    end

    -- Sync all currently-registered SM textures (sorted alphabetically; late ones arriving via the callback append after, in registration order).
    local smTextures = LSM:HashTable("statusbar")
    if smTextures then
        local sorted = {}
        for name in pairs(smTextures) do
            local key = "sm:" .. name
            if not textures[key] and not blacklist[name] then
                sorted[#sorted + 1] = name
            end
        end
        if #sorted > 0 then
            table.sort(sorted)
            for _, name in ipairs(sorted) do
                AppendOne(c, name, smTextures[name])
            end
        end
    end

    -- Install the late-registration callback once, with a DEDICATED owner: same owner + event would replace the font LibSharedMedia_Registered callback in CallbackHandler.
    if not EllesmereUI._smTexCallbackInstalled then
        EllesmereUI._smTexCallbackInstalled = true
        EllesmereUI._smTexCBOwner = EllesmereUI._smTexCBOwner or {}
        LSM.RegisterCallback(EllesmereUI._smTexCBOwner, "LibSharedMedia_Registered", function(_, mediatype, key)
            if mediatype ~= "statusbar" then return end
            local path = LSM:Fetch("statusbar", key)
            if not path then return end
            for _, cc in pairs(EllesmereUI._smTexConsumers) do
                AppendOne(cc, key, path)
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Append LibSharedMedia-3.0 sounds into a runtime sound dropdown table.
--  Signature: AppendSharedMediaSounds(paths, names, order)
--    paths   - key -> sound file path table
--    names   - key -> display name string table
--    order   - ordered array of keys (receives "---" + SM keys appended)
--  Safe to call repeatedly; duplicate keys are skipped via the paths guard.
-------------------------------------------------------------------------------
function EllesmereUI.AppendSharedMediaSounds(paths, names, order)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local smSounds = LSM:HashTable("sound")
    if not smSounds then return end

    local sorted = {}
    for name in pairs(smSounds) do
        local key = "sm:" .. name
        if not paths[key] then
            sorted[#sorted + 1] = name
        end
    end
    if #sorted == 0 then return end
    table.sort(sorted)

    order[#order + 1] = "---"
    for _, name in ipairs(sorted) do
        local key = "sm:" .. name
        paths[key] = smSounds[name]
        names[key] = name
        order[#order + 1] = key
    end
end

-------------------------------------------------------------------------------
--  Append LibSharedMedia-3.0 fonts into a runtime font dropdown table.
--  Signature: AppendSharedMediaFonts(values, order, opts)
--    values  - key -> { text, font } table (or key -> path when keyByName=true)
--    order   - ordered array of keys
--    opts    - optional { keyByName = true } -- use display name as key
--  Safe to call multiple times; duplicate keys are skipped.
-------------------------------------------------------------------------------
function EllesmereUI.AppendSharedMediaFonts(values, order, opts)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local smFonts = LSM:HashTable("font")
    if not smFonts then return end

    -- Build the SM font path lookup so ResolveFontName can find SM fonts
    if not EllesmereUI._smFontPaths then EllesmereUI._smFontPaths = {} end
    for name, path in pairs(smFonts) do
        EllesmereUI._smFontPaths[name] = path
    end

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

-- Append only EXTERNAL SharedMedia fonts (not bundled with EllesmereUI) to a dropdown
-- values/order pair, for glyph-restricted locales where bundled Latin fonts cannot render the
-- script: only user-installed SM fonts are offered, alongside System Default (bundled names are skipped -- LSM-registered too, but they would just show boxes).
function EllesmereUI.AppendExternalSharedMediaFonts(values, order)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end
    local smFonts = LSM:HashTable("font")
    if not smFonts then return end
    if not EllesmereUI._smFontPaths then EllesmereUI._smFontPaths = {} end
    local sorted = {}
    for name, path in pairs(smFonts) do
        EllesmereUI._smFontPaths[name] = path
        if not EllesmereUI.FONT_FILES[name] and not EllesmereUI.FONT_BLIZZARD[name]
           and not values[name] then
            sorted[#sorted + 1] = name
        end
    end
    if #sorted == 0 then return end
    table.sort(sorted)
    order[#order + 1] = "---"
    for _, name in ipairs(sorted) do
        values[name] = { text = name, font = smFonts[name] }
        order[#order + 1] = name
    end
end

-------------------------------------------------------------------------------
--  Deferred file initialization -- Heavy UI files (Widgets, UnlockMode, Options)
--  register init functions here at load but do not execute until the panel opens.
--  The options surface itself (Widgets + every *_Options.lua) lives in the
--  LoadOnDemand EllesmereUIOptions addon: nothing of it is even PARSED until
--  EnsureLoaded loads the addon on first panel open.
-------------------------------------------------------------------------------
EllesmereUI._deferredInits = {}
EllesmereUI._deferredLoaded = false

-- Module-namespace registry: every child addon publishes its private ns here at
-- load. The LOD options files (which get EllesmereUIOptions' own useless vararg
-- ns) resolve their module's real ns from this table, and early-return when the
-- module is absent/disabled -- reproducing the old "disabled child = no options
-- page" behavior exactly.
EllesmereUI._ModuleNS = {}
if IS_STANDALONE then
    -- Every core file has loaded by the first module publish: remove the
    -- hand-off slot before the shared table is published (see the top).
    local shared = select(2, ...)
    setmetatable(EllesmereUI._ModuleNS, { __newindex = function(t, k, v)
        shared.__euiCoreNS = nil
        setmetatable(t, nil)
        rawset(t, k, v)
    end })
end

-- Login-critical deferred body: UnlockMode's position/anchor engine
-- (_applySavedPositions, width/height matches, anchor propagation). It must run
-- at PLAYER_LOGIN / CDM setup WITHOUT loading the options addon, or the
-- LoadOnDemand split's login win evaporates -- so it lives in its own slot, not
-- _deferredInits. One-shot; EnsureLoaded also drains it (panel paths need it too).
EllesmereUI._unlockCoreInit = nil

function EllesmereUI:EnsureUnlockCore()
    local fn = self._unlockCoreInit
    if fn then
        self._unlockCoreInit = nil
        fn()
    end
end

-- Loads the LoadOnDemand options surface. False (with a user-facing message)
-- only when the EllesmereUIOptions addon is missing or disabled in the AddOn List.
function EllesmereUI.EnsureOptionsLoaded()
    -- Standalone builds bundle the options files FLAT into the one addon --
    -- they are resident from startup, and the LoadOnDemand addon named below
    -- does not exist there under any name (the rename would point this at a
    -- nonexistent "<coreToken>Options", printing MISSING and dead-ending every
    -- options open). Loaded is simply true; EnsureLoaded's deferred-init drain
    -- does the rest, exactly like the pre-split resident options.
    if IS_STANDALONE then return true end
    if C_AddOns.IsAddOnLoaded("EllesmereUIOptions") then return true end
    -- Inside the suite registration window: the options files register the
    -- suite's module pages while they load (see RegisterModule).
    local ok, reason = EUI_NS.RunCoreRegistration(C_AddOns.LoadAddOn, "EllesmereUIOptions")
    if not ok then
        EllesmereUI.PrintError("Options could not load (" .. tostring(reason) .. "). Enable the \"EllesmereUI Options\" addon in the AddOn List.")
    end
    return ok and true or false
end

-- The options LOD split moved the child modules' slash registrations into
-- EllesmereUIOptions, where they cannot exist until the panel first loads.
-- Register a self-replacing bootstrap for each at login: it refuses in
-- combat (matching the real handlers, and keeping LoadAddOn out of combat),
-- loads the options addon -- whose re-fired init installs the REAL handler
-- over this one -- then re-dispatches, so subcommands like "/erf reset"
-- behave exactly as before the split. A real handler that never installs
-- (child module disabled) leaves the command a silent no-op, matching the
-- pre-split not-loaded behavior.
do
    local LOD_SLASH = {
        { key = "EABR",                "/eabr", "/ebr" },
        { key = "EBSK",                "/ebsk" },
        { key = "ECMEOPT",             "/ecmeopt" },
        { key = "EFR",                 "/efr" },
        { key = "EMM",                 "/emm" },
        { key = "ELLESMERENAMEPLATES", "/enp" },
        { key = "EQOL",                "/qol" },
        { key = "EQTOPTS",             "/eqtopts" },
        { key = "EUIQUICKDRAW",        "/eqd", "/quickdraw" },
        { key = "ELLESMERERAIDFRAMES", "/erf" },
        { key = "ERBOPT",              "/erbopt" },
        { key = "ELLESMEREUNITFRAMES", "/euf" },
        { key = "ELLESMEREDATABARS",   "/edb" },
    }
    for _, e in ipairs(LOD_SLASH) do
        local key = e.key
        for i = 1, #e do
            _G["SLASH_" .. key .. i] = e[i]
        end
        local function bootstrap(msg)
            if InCombatLockdown() then
                print("Cannot open options in combat")
                return
            end
            -- Deferred one tick: slash dispatch runs inside the chat edit
            -- box's script execution, and first-open work (options addon
            -- load + full panel build) can exceed that execution's watchdog
            -- budget ("script ran too long"). A fresh timer execution owns
            -- its own budget.
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                if not EllesmereUI.EnsureOptionsLoaded() then return end
                local real = SlashCmdList[key]
                if real and real ~= bootstrap then real(msg) end
            end)
        end
        SlashCmdList[key] = bootstrap
    end
end

function EllesmereUI:EnsureLoaded()
    if self._deferredLoaded then return end
    -- Unlock core first (position/anchor engine), matching the pre-split order
    -- where UnlockMode's deferred body ran before Widgets'.
    self:EnsureUnlockCore()
    -- Load the options addon: its files append their deferred inits, which the
    -- loop below then runs. On failure keep _deferredLoaded false so a later
    -- open retries after the user re-enables the addon.
    if not EllesmereUI.EnsureOptionsLoaded() then return end
    self._deferredLoaded = true
    -- Deferred inits run inside the suite registration window: some options
    -- files register their module page from here (e.g. Party Mode).
    for i, fn in ipairs(self._deferredInits) do
        EUI_NS.RunCoreRegistration(fn)
        self._deferredInits[i] = nil
    end
end

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
EllesmereUI.VERSION = "9.4"

-- Register this addon's version into a shared global table (taint-free at load time)
if not _G._EUI_AddonVersions then _G._EUI_AddonVersions = {} end
_G._EUI_AddonVersions[EUI_HOST_ADDON] = EllesmereUI.VERSION

-- Version-increase detection: stamp the account's last-seen version at login
-- and raise the Patch Notes reminder dot when it changed. The dot clears
-- when the Patch Notes row is clicked and stays cleared until the NEXT
-- version change. First-ever login (no prior stamp) never raises it.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if not EllesmereUIDB then EllesmereUIDB = {} end
        local prev = EllesmereUIDB.lastLoginVersion
        if prev and prev ~= EllesmereUI.VERSION then
            EllesmereUIDB.patchDotPending = true
        end
        EllesmereUIDB.lastLoginVersion = EllesmereUI.VERSION
        if EllesmereUI._UpdatePatchDot then EllesmereUI._UpdatePatchDot() end
    end)
end

-- Version mismatch check (shared across all Ellesmere addons)
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        if _G._EUI_VersionChecked then return end
        _G._EUI_VersionChecked = true
        C_Timer.After(2, function()
            local versions = _G._EUI_AddonVersions
            if not versions then return end
            local loaded = {}
            for name, ver in pairs(versions) do
                loaded[#loaded + 1] = { name = name, version = ver }
            end
            if #loaded < 2 then return end
            local newest = loaded[1].version
            for i = 2, #loaded do
                if loaded[i].version > newest then newest = loaded[i].version end
            end
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
            EllesmereUI:ShowConfirmPopup({
                title       = "Out of Date",
                message     = msg,
                confirmText = "OK",
            })
        end)
    end)
end

--------------------------------------------------------------------------------
--  Global Incompatible Addon Detection -- runs once per session. Non-ElvUI conflicts always
--  show. ElvUI is a one-off warning: once dismissed while it is the ONLY conflict, it is
--  suppressed forever; if other conflicts are also present, ElvUI shows too and the one-off flag is not consumed.
--------------------------------------------------------------------------------
-- Conflict check is wrapped in a function so the first-install popup (EllesmereUI_FirstInstall.lua)
-- can defer it until after the user picks their initial addon list. The inline scheduler at the
-- bottom of this block only runs it automatically if the first-install popup has already been shown in a prior session.
EllesmereUI._RunConflictCheck = function()
    if _G._EUI_ConflictCheckRan then return end
    _G._EUI_ConflictCheckRan = true
    do
        local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        if not IsLoaded then return end

        -- conflict list: { addon, label, targets, message, moduleCheck }
        --   targets = "all" or a table of Ellesmere folder names
        --   message = optional custom popup message override
        --   moduleCheck = optional function returning true if the specific sub-module is active
        --     (used for per-module conflicts: minimap, friends, chat, etc.)
        -- Blizzard UI Enhanced has sub-features stored as flags on EllesmereUIDB; conflicts against a specific sub-feature only fire when that feature is actually enabled.
        local function BlizzardSkinSubEnabled(key)
            if not EllesmereUIDB then return true end
            return EllesmereUIDB[key] ~= false
        end
        local conflicts = {
            { addon = "ElvUI",                    label = "ElvUI",                      targets = "all",                              message = "Many of ElvUI's modules are incompatible with EllesmereUI. Make sure to disable any conflicting modules." },
            { addon = "DandersFrames",            label = "Danders Frames",             targets = { "EllesmereUIRaidFrames" } },
            { addon = "HarreksAdvancedRaidFrames", label = "Harreks Advanced Raid Frames", targets = { "EllesmereUIRaidFrames" } },
            { addon = "Grid2",                    label = "Grid2",                      targets = { "EllesmereUIRaidFrames" } },
            -- Clique is special: it only conflicts when Raid Frames is enabled AND
            -- HoverCast (click-casting) is turned on -- with HoverCast off, Clique
            -- coexists fine (it owns the frames). targets handles the RF-enabled
            -- check; moduleCheck adds the HoverCast-enabled check.
            { addon = "Clique",                   label = "Clique",                     targets = { "EllesmereUIRaidFrames" },
              moduleCheck = function() return _G._ERF_IsHoverCastEnabled and _G._ERF_IsHoverCastEnabled() end,
              message = "Clique controls click-casting on the same Raid Frames as EllesmereUI's HoverCast, so they conflict. Disable the Clique addon to use HoverCast." },
            { addon = "TellMeWhen",               label = "TellMeWhen",                 targets = "all",                              message = "TellMeWhen overlaps with EllesmereUI's core positional architecture. If you ONLY use for sound alerts it should be okay but may still cause issues." },
            { addon = "Bartender4",               label = "Bartender4",                 targets = { "EllesmereUIActionBars" } },
            { addon = "Dominos",                  label = "Dominos",                    targets = { "EllesmereUIActionBars" } },
            { addon = "ImprovedTalentLoadouts",   label = "Improved Talent Loadouts",   targets = { "EllesmereUIActionBars" } },
            { addon = "UnhaltedUnitFrames",       label = "Unhalted Unit Frames",       targets = { "EllesmereUIUnitFrames" } },
            { addon = "Platynator",               label = "Platynator",                 targets = { "EllesmereUINameplates" } },
            { addon = "Plater",                   label = "Plater Nameplates",          targets = { "EllesmereUINameplates" } },
            { addon = "Kui_Nameplates",            label = "KUI Nameplates",             targets = { "EllesmereUINameplates" } },
            { addon = "TidyPlates",               label = "TidyPlates",                 targets = { "EllesmereUINameplates" } },
            { addon = "TidyPlates_ThreatPlates",  label = "TidyPlates ThreatPlates",    targets = { "EllesmereUINameplates" } },
            { addon = "Healers-Have-To-Die",      label = "Healers Have To Die",        targets = { "EllesmereUINameplates" } },
            { addon = "Aloft",                    label = "Aloft",                      targets = { "EllesmereUINameplates" } },
            { addon = "SenseiClassResourceBar",   label = "Sensei Class Resource Bar",  targets = { "EllesmereUIResourceBars" } },
            { addon = "EditModeExpanded",     label = "Edit Mode Expanded",         targets = { "EllesmereUIQuestTracker", "EllesmereUIChat" } },
            { addon = "SexyMap",                  label = "SexyMap",                    targets = { "EllesmereUIMinimap" }, },
            { addon = "MinimapButtonButton",      label = "MinimapButtonButton",        targets = { "EllesmereUIMinimap" }, },
            { addon = "Leatrix_Plus",              label = "Leatrix",                    targets = { "EllesmereUIChat", "EllesmereUIMinimap" },
              message = "Leatrix Plus has chat and minimap features that conflict with EllesmereUI. Disable any chat or minimap related options within Leatrix Plus to stay compatible." },
            { addon = "Prat-3.0",                 label = "Prat",                       targets = { "EllesmereUIChat" } },
            { addon = "Chatter",                  label = "Chatter",                    targets = { "EllesmereUIChat" } },
            { addon = "Chattynator",              label = "Chattynator",                targets = { "EllesmereUIChat" } },
            { addon = "Glass",                    label = "Glass",                      targets = { "EllesmereUIChat" } },
            { addon = "AdiBags",                  label = "AdiBags",                    targets = { "EllesmereUIBags" } },
            { addon = "ArkInventory",             label = "ArkInventory",               targets = { "EllesmereUIBags" } },
            { addon = "Baganator",                label = "Baganator",                  targets = { "EllesmereUIBags" } },
            { addon = "Bagnon",                   label = "Bagnon",                     targets = { "EllesmereUIBags" } },
            { addon = "BetterBags",               label = "BetterBags",                 targets = { "EllesmereUIBags" } },
            { addon = "Sorted",                   label = "Sorted",                     targets = { "EllesmereUIBags" } },
            { addon = "UltimateMouseCursor",      label = "Ultimate Mouse Cursor",      targets = { "EllesmereUIQoL" } },
            { addon = "BetterCooldownManager",    label = "Better Cooldown Manager",    targets = { "EllesmereUICooldownManager", "EllesmereUIResourceBars" } },
            { addon = "CooldownManagerCentered",    label = "Cooldown Manager Centered",    targets = { "EllesmereUICooldownManager" } },
            { addon = "SkironCooldownManager",    label = "Skiron Cooldown Manager",    targets = { "EllesmereUICooldownManager" } },
            { addon = "ArcUI",                    label = "ArcUI",                      targets = { "EllesmereUICooldownManager", } },
            { addon = "Ayije_CDM",                label = "Ayije CDM",                  targets = { "EllesmereUICooldownManager", "EllesmereUIResourceBars" } },
            { addon = "MythicPlusTimer",          label = "Mythic Plus Timer",          targets = { "EllesmereUIMythicTimer" } },
            { addon = "WarpDeplete",              label = "WarpDeplete",                targets = { "EllesmereUIMythicTimer" } },
            { addon = "MPlusTimer",               label = "MPlusTimer",                 targets = { "EllesmereUIMythicTimer" } },
            { addon = "ChonkyCharacterSheet",     label = "Chonky Character Sheet",     targets = { "EllesmereUIBlizzardSkin" },
              moduleCheck = function() return BlizzardSkinSubEnabled("themedCharacterSheet") end,
              message = "Chonky Character Sheet conflicts with the EllesmereUI's Character Sheet. Disable either Chonky or the Character Sheet skin in Blizzard UI Enhanced settings." },
            { addon = "DejaCharacterStats",       label = "Deja Character Stats",       targets = { "EllesmereUIBlizzardSkin" },
              moduleCheck = function() return BlizzardSkinSubEnabled("themedCharacterSheet") end,
              message = "Deja Character Stats conflicts with the EllesmereUI's Character Sheet. Disable either Deja or the Character Sheet skin in Blizzard UI Enhanced settings." },
            { addon = "BetterCharacterPanel",     label = "Better Character Panel",     targets = { "EllesmereUIBlizzardSkin" },
              moduleCheck = function() return BlizzardSkinSubEnabled("themedCharacterSheet") end,
              message = "Better Character Panel conflicts with the EllesmereUI's Character Sheet. Disable either Better Character Panel or the Character Sheet skin in Blizzard UI Enhanced settings." },
            { addon = "idTip",                    label = "idTip",                      targets = "all",
              message = "idTip conflicts with EllesmereUI's tooltip systems. Disable the idTip addon to stay compatible." },
            -- Old name of EllesmereUIDataBars: a leftover copy of the addon from before the rename duplicates the entire bar.
            { addon = "EllesmereUIWonderBar",     label = "EllesmereUI WonderBar",      targets = { "EllesmereUIDataBars" },
              message = "EllesmereUI WonderBar was renamed to EllesmereUI DataBars. The old WonderBar addon is still installed and both create the same bar. Please disable or delete the EllesmereUIWonderBar addon." },
            { addon = "EllesmereBarGlows",        label = "Ellesmere's CDM Bar Glows",  targets = "all" },
            { addon = "EllesmereNameplates",        label = "Ellesmere's Nameplates",  targets = "all" },
            { addon = "EllesmereActionBars",        label = "Ellesmere's Action Bars",  targets = "all" },
            { addon = "EllesmereUnitFrames",        label = "Ellesmere's Unit Frames",  targets = "all" },
        }

        local exempt = { EllesmereUIPartyMode = true }

        if not EllesmereUIDB then EllesmereUIDB = {} end
        if not EllesmereUIDB.dismissedConflicts then EllesmereUIDB.dismissedConflicts = {} end
        local dismissed = EllesmereUIDB.dismissedConflicts

        -- Collect all active conflicts. ElvUI is filtered out if it has been permanently dismissed AND it would be the only conflict showing (i.e. no other conflicts exist).
        local pending = {}
        for _, entry in ipairs(conflicts) do
            local moduleActive = not entry.moduleCheck or entry.moduleCheck()
            if entry.addon ~= EUI_HOST_ADDON and IsLoaded(entry.addon) and moduleActive then
                local affected = {}
                if entry.targets == "all" then
                    local allTargets = {
                        "EllesmereUIActionBars", "EllesmereUIUnitFrames", "EllesmereUINameplates",
                        "EllesmereUIResourceBars", "EllesmereUIAuraBuffReminders", "EllesmereUICooldownManager",
                        "EllesmereUIRaidFrames",
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
        -- "Okay"             -> dismiss this session only; re-shows next login.
        -- "Don't show again" -> permanently dismiss this specific addon.
        local pendingIndex = 0
        local function ShowNextConflict()
            pendingIndex = pendingIndex + 1
            local item = pending[pendingIndex]
            if not item then return end
            local entry, affected = item.entry, item.affected
            -- Skip any conflict the user permanently dismissed previously.
            if dismissed[entry.addon] then
                ShowNextConflict()
                return
            end
            local names = {}
            for _, a in ipairs(affected) do
                -- Prefer the module's registered display title; fall back to stripping the EllesmereUI prefix from the folder name.
                local displayName = (modules[a] and modules[a].title)
                    or a:gsub("^EllesmereUI", "")
                names[#names + 1] = displayName
            end
            local msg = entry.message or (
                entry.label .. " is not compatible with EllesmereUI's " .. table.concat(names, ", ")
                .. ". Running both at the same time may cause errors or unexpected behavior."
                .. "\n\nPlease disable one of them."
            )
            if EllesmereUI.ShowConfirmPopup then
                EllesmereUI:ShowConfirmPopup({
                    title       = "Incompatible Addon Detected",
                    message     = msg,
                    confirmText = "Okay",
                    cancelText  = "Don't show again",
                    onConfirm   = function() ShowNextConflict() end,
                    onCancel    = function()
                        dismissed[entry.addon] = true
                        ShowNextConflict()
                    end,
                    modal       = true,
                })
            else
                EllesmereUI.PrintError(msg:gsub("\n", " "))
                ShowNextConflict()
            end
        end
        ShowNextConflict()
    end
end

-- Auto-run the conflict check only if first-install has already been shown. On first install,
-- the first-install popup will call RunConflictCheck when the user closes it (no reload needed).
C_Timer.After(2, function()
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown then
        -- Defer while any intro popup is still pending/open; each runs the conflict check itself
        -- when dismissed (RaidFrames / PatchNotes / WindowSkins / SpecOverrides / PTRManagers
        -- popup files, plus the 12.1 launch video announcement in EllesmereUI_VideoGuides.lua).
        if EllesmereUI._raidFramesIntroPending or EllesmereUI._patchNotesIntroPending
           or EllesmereUI._windowSkinsIntroPending or EllesmereUI._specOvIntroPending
           or EllesmereUI._ptrManagersIntroPending or EllesmereUI._launchVideoIntroPending
           or EllesmereUI._styleLaunchIntroPending or EllesmereUI._styleChoicePending then return end
        EllesmereUI._RunConflictCheck()
    end
end)

SLASH_EUIOPTIONS1 = "/eui"
SLASH_EUIOPTIONS2 = "/ellesmere"
SLASH_EUIOPTIONS3 = "/ellesmereui"
-- Deferred one frame: keeps the panel build out of the chat edit box's
-- execution (its watchdog budget). Blizzard's own Enter handling still runs
-- tainted after any addon slash command; on a whisper to a secret-named
-- target its header math then errors (ChatFrameEditBox UpdateHeader), which
-- no handler-side change can prevent.
SlashCmdList.EUIOPTIONS = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            EllesmereUI.PrintError("Cannot open options during combat.")
            return
        end
        EllesmereUI:Toggle()
    end)
end

-- Quick-access: /ee opens global settings
SLASH_EUIQUICK1 = "/ee"
SlashCmdList.EUIQUICK = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            EllesmereUI.PrintError("Cannot open options during combat.")
            return
        end
        EllesmereUI:Toggle()
    end)
end

-- Quick-access: /epm opens directly to Party Mode settings
SLASH_EUIPARTYMODE1 = "/epm"
SlashCmdList.EUIPARTYMODE = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            EllesmereUI.PrintError("Cannot open options during combat.")
            return
        end
        EllesmereUI:ShowModule("EllesmereUIPartyMode")
    end)
end

-- Toggle party mode on/off
SLASH_PARTYMODETOGGLE1 = "/partymode"
SlashCmdList.PARTYMODETOGGLE = function()
    C_Timer.After(0, function()
        if EllesmereUI_TogglePartyMode then
            EllesmereUI_TogglePartyMode()
        else
            EllesmereUI.PrintError("Party Mode addon is not loaded.")
        end
    end)
end

-- Quick-access: /unlock opens Unlock Mode directly
SLASH_EUIUNLOCK1 = "/unlock"
SlashCmdList.EUIUNLOCK = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            EllesmereUI.PrintError("Cannot open options during combat.")
            return
        end
        EllesmereUI:EnsureUnlockCore()
        if EllesmereUI._openUnlockMode then
            EllesmereUI._openUnlockMode()
        else
            EllesmereUI.PrintError("Unlock Mode is not available.")
        end
    end)
end

-- Support: reset all one-time hint flags so they show again
SLASH_EUIRESETHINT1 = "/euiresethint"
SlashCmdList.EUIRESETHINT = function()
    C_Timer.After(0, function()
        if EllesmereUIDB then
            EllesmereUIDB.previewHintDismissed = nil
            EllesmereUIDB.unlockTipSeen = nil
            EllesmereUIDB.sidebarUnlockTipSeen = nil
            EllesmereUIDB.rfEyeHintSeen = nil
            EllesmereUIDB.bmIconHintDismissed = nil
            EllesmereUIDB.cdmButtonTipSeen = nil
            EllesmereUIDB.bagCategoryTipSeen = nil
        end
        EllesmereUI.Print("|cff00ff00[EllesmereUI]|r All hints reset. /reload to see them again.")
    end)
end

-- Support: wipe saved UI scale so next reload re-snapshots from Blizzard default
SLASH_EUIRESETSCALE1 = "/euiresetscale"
SlashCmdList.EUIRESETSCALE = function()
    C_Timer.After(0, function()
        if EllesmereUIDB then
            EllesmereUIDB.ppUIScale = nil
            EllesmereUIDB.ppUIScaleAuto = nil
        end
        EllesmereUI.Print("|cff00ff00[EllesmereUI]|r UI scale reset. /reload to re-snapshot from your Blizzard scale.")
    end)
end

SLASH_EUIDEV1 = "/euidev"
SlashCmdList.EUIDEV = function()
    local cvars = {
        "addonChallengeModeRestrictionsForced",
        "addonChatRestrictionsForced",
        "addonCombatRestrictionsForced",
        "addonEncounterRestrictionsForced",
        "addonMapRestrictionsForced",
        "addonPvPMatchRestrictionsForced",
    }
    local current = GetCVar(cvars[1])
    local newVal = (current == "1") and "0" or "1"
    for _, cv in ipairs(cvars) do
        EllesmereUI.SetCVar(cv, newVal)
    end
    local state = newVal == "1" and "ON" or "OFF"
    EllesmereUI.Print("|cff00ff00[EllesmereUI]|r Dev mode: all addon restriction CVars " .. state .. ".")
    if EllesmereUI.UpdateDevModeIndicator then EllesmereUI.UpdateDevModeIndicator() end
end

-------------------------------------------------------------------------------
--  Dev Mode badge: a small top-left indicator shown while /euidev is active (the addon-
--  restriction-forced CVars are on, forcing the restricted / secret-value environment for
--  testing). Toggled by /euidev and re-checked on login, since the CVars persist across sessions.
-------------------------------------------------------------------------------
do
    local DEV_CVAR = "addonChallengeModeRestrictionsForced"

    function EllesmereUI.IsDevModeActive()
        return GetCVar(DEV_CVAR) == "1"
    end

    local badge

    local function CreateDevBadge()
        if badge then return badge end
        local PP = EllesmereUI.PP
        local accent = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }

        local f = CreateFrame("Frame", "EllesmereUIDevModeBadge", UIParent)
        f:SetFrameStrata("HIGH")
        f:SetHeight(26)
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -41)
        f:EnableMouse(false)
        f:Hide()

        -- Dark base + faint accent wash for an on-brand tint
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.02, 0.02, 0.03, 0.62)
        local wash = f:CreateTexture(nil, "BORDER")
        wash:SetAllPoints()
        wash:SetColorTexture(accent.r, accent.g, accent.b, 0.06)

        -- Accent 1px border (our own frame, safe)
        if PP and PP.CreateBorder then
            PP.CreateBorder(f, accent.r, accent.g, accent.b, 0.9, 1, "OVERLAY", 7)
        end

        -- Pulsing accent "LED" dot (recording-indicator vibe)
        local dot = f:CreateTexture(nil, "ARTWORK")
        dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        dot:SetVertexColor(accent.r, accent.g, accent.b, 1)
        dot:SetSize(7, 7)
        dot:SetPoint("LEFT", f, "LEFT", 9, 0)
        if dot.SetSnapToPixelGrid then dot:SetSnapToPixelGrid(false); dot:SetTexelSnappingBias(0) end
        local ag = dot:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local pulse = ag:CreateAnimation("Alpha")
        pulse:SetFromAlpha(1); pulse:SetToAlpha(0.1)
        pulse:SetDuration(0.7); pulse:SetSmoothing("IN_OUT")
        f._pulse = ag

        -- Label
        local label = f:CreateFontString(nil, "OVERLAY")
        label:SetFont(EllesmereUI.EXPRESSWAY, 11,
            (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE")
        label:SetText("DEV MODE ACTIVE")
        label:SetTextColor(accent.r, accent.g, accent.b, 1)
        label:SetPoint("LEFT", dot, "RIGHT", 8, 0)

        -- Size to content: dotPad(9) + dot(7) + gap(8) + text + rightPad(12)
        f:SetWidth(9 + 7 + 8 + label:GetStringWidth() + 12)

        badge = f
        return f
    end

    function EllesmereUI.UpdateDevModeIndicator()
        if not EllesmereUI.IsDevModeActive() then
            if badge then
                if badge._pulse then badge._pulse:Stop() end
                badge:Hide()
            end
            return
        end
        local f = CreateDevBadge()
        f:Show()
        if f._pulse then f._pulse:Play() end
    end

    -- CVars persist across sessions: check on login (deferred so the theme accent is fully resolved). PLAYER_LOGIN re-fires on /reload, so this covers both.
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(2, function()
            EllesmereUI.UpdateDevModeIndicator()
        end)
    end)
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
                if EllesmereUI then EllesmereUI:EnsureUnlockCore() end
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
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -2, 0)
            GameTooltip:AddLine("|cff0cd29fEllesmereUI|r")
            GameTooltip:AddLine(EllesmereUI.L("|cff0cd29dLeft-click:|r |cffE0E0E0Toggle EllesmereUI|r"))
            GameTooltip:AddLine(EllesmereUI.L("|cff0cd29dRight-click:|r |cffE0E0E0Enter Unlock Mode|r"))
            GameTooltip:AddLine(EllesmereUI.L("|cff0cd29dMiddle-click:|r |cffE0E0E0Hide Minimap Button|r"))
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

-- Spell ID on Tooltip (Blizzard Skins+ > Tooltips & Menus, Global Settings >
-- Developer): on unless turned off. Accounts from before that default keep it
-- off through the spellid_default_on_v1 migration (EllesmereUI_Migration.lua).
function EllesmereUI.SpellIDOn()
    local db = EllesmereUIDB
    return db ~= nil and db.showSpellID ~= false
end

-------------------------------------------------------------------------------
--  Init  +  Demo Modules  (temporary placeholder content)
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
            EllesmereUI:Hide()
            EllesmereUI.PrintError("Options closed -- entering combat.")
        end
        return
    end

    -- PLAYER_LOGIN: register demo modules (UI is built lazily on first open)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Apply the global font to Blizzard's default game text (opt-in, reload-gated).
    -- Done here at login, out of combat, so it runs once before the UI renders.
    EllesmereUI.ApplyGlobalFontToGameText()
    -- Always-on failsafe: swap the shared font objects behind Chat, the Quest Tracker, and
    -- Blizzard-UI-Enhanced tooltips to each module's font, so the sub-elements our per-frame
    -- styling misses pick up the right face. Runs after the global pass so the per-module face wins in those three areas.
    EllesmereUI.ApplyModuleFontFailsafe()

    ---------------------------------------------------------------------------
    --  Escape proxy: single UISpecialFrames entry for all EUI frames.
    --  Child addons call EllesmereUI.RegisterEscapeClose(frame[, opts]) to opt
    --  in (defined here, at PLAYER_LOGIN). Every opt is optional; a frame
    --  registered without opts closes one per Escape press, newest registration
    --  first, exactly as before:
    --    cursor    raise the gamepad pointer on each show (user-opened windows)
    --    onEscape  fn(frame) runs instead of frame:Hide() when Escape/Back closes it
    --    modal     true or fn(frame): never closed by Escape/Back, never keeps the
    --              proxy shown by itself, and while shown swallows Escape/Back for
    --              the windows under it (as a modal popup's own key handler does)
    --    notOwned  no controller-cursor registration: a frame we do not own, or
    --              one that must never be a controller-cursor root (Unlock Mode)
    --    padOnly   counts only when a controller was in use at its show (popups,
    --              dimmers, Unlock Mode); otherwise it never touches the proxy
    --  Controller Back while the gamepad pointer is in control closes every open
    --  window in one pass: Blizzard turns the pointer off after that press.
    ---------------------------------------------------------------------------
    do
        local escFrames = {}
        local escOpts = {}      -- [frame] = its opts (a shared empty table when none)
        local escModal = {}     -- registered non-padOnly frames with a modal opt
        local padOpen = {}      -- padOnly frames that count, in show order
        local closeList = {}    -- reused by the controller close-all pass
        local closing = false
        local NO_OPTS = {}
        local PadNative, PadInUse = EllesmereUI.PadNative, EllesmereUI.PadInUse
        local proxy = CreateFrame("Frame", "EllesmereUI_EscapeProxy", UIParent)
        proxy:Hide()
        tinsert(UISpecialFrames, "EllesmereUI_EscapeProxy")

        local function IsModal(f)
            local m = escOpts[f].modal
            if not m then return false end
            if m == true then return true end
            return m(f) and true or false
        end

        local function AnyOpen()
            for i = 1, #escFrames do
                local f = escFrames[i]
                if f:IsShown() and not IsModal(f) then return true end
            end
            for i = 1, #padOpen do
                local f = padOpen[i]
                if f:IsShown() and not IsModal(f) then return true end
            end
            return false
        end

        local function ModalOpen()
            for i = 1, #escModal do
                local f = escModal[i]
                if f:IsShown() and IsModal(f) then return true end
            end
            for i = 1, #padOpen do
                local f = padOpen[i]
                if f:IsShown() and IsModal(f) then return true end
            end
            return false
        end

        local function RefreshProxy()
            if closing then return end
            if AnyOpen() then proxy:Show() else proxy:Hide() end
        end

        local function CloseOne(f)
            local onEscape = escOpts[f].onEscape
            if onEscape then onEscape(f) else f:Hide() end
        end

        -- Controller close-all pass over the snapshot in closeList.
        local function CloseListed(n)
            for i = 1, n do
                local f = closeList[i]
                if f:IsShown() then CloseOne(f) end
            end
        end

        proxy:SetScript("OnHide", function(self)
            if closing then return end
            if ModalOpen() then RefreshProxy(); return end
            -- Controller Back (a real Hide, the gamepad pointer in control):
            -- close everything now, newest controller-counted window first.
            if not self:IsShown() and PadNative() and CanAutoSetGamePadCursorControl(false) then
                local n = 0
                for i = #padOpen, 1, -1 do
                    local f = padOpen[i]
                    if f:IsShown() and not IsModal(f) then n = n + 1; closeList[n] = f end
                end
                for i = #escFrames, 1, -1 do
                    local f = escFrames[i]
                    if f:IsShown() and not IsModal(f) then n = n + 1; closeList[n] = f end
                end
                -- A failing onEscape must not leave the proxy stuck in `closing`.
                closing = true
                local ok, err = pcall(CloseListed, n)
                closing = false
                wipe(closeList)
                RefreshProxy()
                if not ok then geterrorhandler()(err) end
                return
            end
            -- One window per press: a controller-counted window first (only
            -- ever present while a controller is in use), then the registry.
            for i = #padOpen, 1, -1 do
                local f = padOpen[i]
                if f:IsShown() and not IsModal(f) then
                    CloseOne(f)
                    if AnyOpen() then self:Show() end
                    return
                end
            end
            for i = #escFrames, 1, -1 do
                local f = escFrames[i]
                if f:IsShown() and not IsModal(f) then
                    CloseOne(f)
                    if AnyOpen() then self:Show() end
                    return
                end
            end
        end)

        -- padOnly: one controller check at the show edge; the hide edge only
        -- walks the counted list, which stays empty for mouse/keyboard players.
        local function PadOnlyShown(f)
            if not PadInUse() then return end
            for i = #padOpen, 1, -1 do
                if padOpen[i] == f then table.remove(padOpen, i) end
            end
            padOpen[#padOpen + 1] = f
            RefreshProxy()
        end

        local function PadOnlyHidden(f)
            for i = #padOpen, 1, -1 do
                if padOpen[i] == f then
                    table.remove(padOpen, i)
                    RefreshProxy()
                    return
                end
            end
        end

        function EllesmereUI.RegisterEscapeClose(frame, opts)
            if escOpts[frame] then return end
            opts = opts or NO_OPTS
            escOpts[frame] = opts
            if not opts.notOwned then EllesmereUI.RegisterPadFrame(frame) end
            if opts.cursor then frame:HookScript("OnShow", EllesmereUI.RaiseGamePadCursor) end
            if opts.padOnly then
                frame:HookScript("OnShow", PadOnlyShown)
                frame:HookScript("OnHide", PadOnlyHidden)
                return
            end
            if opts.modal then escModal[#escModal + 1] = frame end
            escFrames[#escFrames + 1] = frame
            frame:HookScript("OnShow", RefreshProxy)
            frame:HookScript("OnHide", RefreshProxy)
        end

        -- Register the Vault once, regardless of which shortcut opens it.
        -- Blizzard's frame: never handed to the controller cursor.
        local function RegisterVaultEscapeClose()
            if not WeeklyRewardsFrame then return false end
            EllesmereUI.RegisterEscapeClose(WeeklyRewardsFrame, { notOwned = true })
            RefreshProxy()
            return true
        end

        if not RegisterVaultEscapeClose() then
            local vaultLoader = CreateFrame("Frame")
            vaultLoader:RegisterEvent("ADDON_LOADED")
            vaultLoader:SetScript("OnEvent", function(self, event, addonName)
                if addonName == "Blizzard_WeeklyRewards" and RegisterVaultEscapeClose() then
                    self:UnregisterEvent("ADDON_LOADED")
                end
            end)
        end
    end

    -- Create native minimap button
    EllesmereUI.CreateMinimapButton()

    -- Add EllesmereUI + Unlock Mode buttons to the Game Menu (pause menu); both share a single Layout hook to avoid double-push conflicts.
    if GameMenuFrame and not EllesmereUI._GetFFD(GameMenuFrame).euiBtn then
        -- Game menu frame+button skinning lives in EllesmereUIBlizzardSkin.lua so it only
        -- applies when that addon is enabled; detect whether the skin is active so EUI's own buttons match the skinned menu style.
        local _blizzSkinLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin")
        -- "Reskin Pause Menu" is an independent toggle (default on); the migration blizzskin_reskin_master_split_v1 seeds reskinGameMenu for existing users.
        local _reskinMenu = _blizzSkinLoaded and (not EllesmereUIDB or EllesmereUIDB.reskinGameMenu ~= false)

        local btn = CreateFrame("Button", "EllesmereUI_GameMenuButton", GameMenuFrame, "MainMenuFrameButtonTemplate")
        btn:SetSize(200, 35)
        btn:SetScript("OnClick", function()
            if InCombatLockdown() then
                EllesmereUI.PrintError("Cannot open options during combat.")
                return
            end
            HideUIPanel(GameMenuFrame)
            EllesmereUI:Toggle()
            -- Controller cursor: the pause menu turned the gamepad pointer off as it
            -- hid; unfolding the mini window fires no OnShow, so raise it here too.
            if EllesmereUI.PadNative() and EllesmereUI:IsShown() then
                EllesmereUI.RaiseGamePadCursor()
            end
        end)
        EllesmereUI._GetFFD(GameMenuFrame).euiBtn = btn

        local unlockBtn = CreateFrame("Button", "EllesmereUI_UnlockMenuButton", GameMenuFrame, "MainMenuFrameButtonTemplate")
        unlockBtn:SetSize(200, 35)
        unlockBtn:SetScript("OnClick", function()
            if InCombatLockdown() then
                EllesmereUI.PrintError("Cannot toggle Unlock Mode during combat.")
                return
            end
            HideUIPanel(GameMenuFrame)
            if EllesmereUI.ToggleUnlockMode then
                EllesmereUI:ToggleUnlockMode()
            end
            -- Controller cursor: the pause menu turned the gamepad pointer off as it hid.
            if EllesmereUI.PadNative() and EllesmereUI._unlockActive then
                EllesmereUI.RaiseGamePadCursor()
            end
        end)
        EllesmereUI._GetFFD(GameMenuFrame).unlockBtn = unlockBtn

        -- Skin our custom buttons the same way as pooled Blizzard buttons
        if _reskinMenu then
            for _, customBtn in ipairs({ btn, unlockBtn }) do
                local regions = { customBtn:GetRegions() }
                for j = 1, #regions do
                    local r = regions[j]
                    if r and r:IsObjectType("Texture") and r ~= customBtn:GetFontString() then
                        r:SetAlpha(0)
                    end
                end
                if customBtn.Left then customBtn.Left:SetAlpha(0) end
                if customBtn.Middle then customBtn.Middle:SetAlpha(0) end
                if customBtn.Right then customBtn.Right:SetAlpha(0) end
                for _, texKey in ipairs({ "Left", "Middle", "Right" }) do
                    local tex = customBtn[texKey]
                    if tex and tex.SetAlpha then
                        hooksecurefunc(tex, "SetAlpha", function(self, a)
                            if a > 0 then self:SetAlpha(0) end
                        end)
                    end
                end
                local inset = CreateFrame("Frame", nil, customBtn)
                inset:SetPoint("TOPLEFT", 2, -2)
                inset:SetPoint("BOTTOMRIGHT", -2, 2)
                inset:SetFrameLevel(customBtn:GetFrameLevel())
                local cBg = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
                cBg:SetAllPoints()
                local c=EllesmereUIDB and EllesmereUIDB.popupMenuButtonBackgroundColor or {r=.1,g=.1,b=.1,a=.8}
                cBg:SetColorTexture(c.r,c.g,c.b,c.a == nil and .8 or c.a)
                EllesmereUI._GetFFD(customBtn).gameMenuInset=inset
                EllesmereUI._GetFFD(customBtn).gameMenuButtonBg=cBg
                if EllesmereUI._applyBlizzardConfiguredBorder then EllesmereUI._applyBlizzardConfiguredBorder(inset,"popupMenuButton",1) end
                local hl = customBtn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(inset)
                hl:SetColorTexture(1, 1, 1, 0.1)
                local cfs = customBtn:GetFontString()
                if cfs then
                    local euiFont = EllesmereUI.GetFontPath() or nil
                    local _, size, flags = cfs:GetFont()
                    cfs:SetFont(euiFont or "Fonts\\FRIZQT__.TTF", (size or 14) - 2, flags or "")
                    -- Native mode keeps the branded inline-code labels set by
                    -- the Layout hook; only explicit modes flat-recolor.
                    if EllesmereUI._getPopupMenuElementMode
                       and EllesmereUI._getPopupMenuElementMode() ~= "native"
                       and EllesmereUI._getPopupMenuButtonTextColor then
                        local r,g,b=EllesmereUI._getPopupMenuButtonTextColor()
                        cfs:SetTextColor(r,g,b,1)
                    end
                end
            end
        end

        local _gameMenuBaseHeight = nil
        hooksecurefunc(GameMenuFrame, "Layout", function()
            if InCombatLockdown() then
                btn:Hide()
                unlockBtn:Hide()
                return
            end

            -- Re-apply accent color to header text on every open (only when skinned)
            if _reskinMenu then
                local header = GameMenuFrame.Header
                if header then
                    local headerText = header.Text
                    if headerText and headerText.SetTextColor then
                        if EllesmereUI._getPopupMenuButtonTextColor then
                            local r,g,b=EllesmereUI._getPopupMenuButtonTextColor()
                            headerText:SetTextColor(r,g,b,1)
                        end
                    end
                end
            end

            -- Determine which buttons are visible
            local showEUI = not (EllesmereUIDB and EllesmereUIDB.hideGameMenuButton)
            local showUnlock = EllesmereUIDB and EllesmereUIDB.hideUnlockMenuButton == false

            if not showEUI then btn:Hide() end
            if not showUnlock then unlockBtn:Hide() end
            if not showEUI and not showUnlock then return end

            -- Find the Shop button to anchor below (fall back to Options)
            local anchorBtn
            for menuBtn in GameMenuFrame.buttonPool:EnumerateActive() do
                local text = menuBtn:GetText()
                if text == BLIZZARD_STORE then
                    anchorBtn = menuBtn
                    break
                elseif text == GAMEMENU_OPTIONS then
                    anchorBtn = menuBtn
                end
            end
            if not anchorBtn then return end

            -- Match our buttons to the Blizzard button size
            local anchorW, anchorH = anchorBtn:GetWidth(), anchorBtn:GetHeight()
            if anchorW and anchorW > 0 then
                btn:SetSize(anchorW, anchorH or 35)
                unlockBtn:SetSize(anchorW, anchorH or 35)
            end

            -- Position our buttons in a chain below the anchor
            local extraH = 0
            local lastBtn = anchorBtn
            local euiFont = EllesmereUI.GetFontPath() or "Fonts\\FRIZQT__.TTF"
            local btnFontSize = 13
            -- Branded two-tone labels are the default (native mode, or when BlizzardSkin is not
            -- loaded) -- applied via inline color codes in SetText, which works with the
            -- pause-menu reskin off too. Only an explicitly chosen Element & Text Color mode switches to a plain label + whole-string recolor (inline codes would override SetTextColor otherwise).
            local elemMode = EllesmereUI._getPopupMenuElementMode
                and EllesmereUI._getPopupMenuElementMode() or "native"
            local brandHex
            if elemMode == "native" then
                local EG = EllesmereUI.ELLESMERE_GREEN or { r = .27, g = .86, b = .49 }
                brandHex = EllesmereUI.HexColor(EG.r, EG.g, EG.b)
            end

            if showEUI then
                btn:Show()
                if brandHex then
                    btn:SetText(brandHex .. "Ellesmere|r|cffffffffUI|r")
                else
                    btn:SetText("EllesmereUI")
                end
                if _reskinMenu then
                    local fs = btn:GetFontString()
                    if fs then fs:SetFont(euiFont, btnFontSize, ""); if not brandHex and EllesmereUI._getPopupMenuButtonTextColor then local r,g,b=EllesmereUI._getPopupMenuButtonTextColor(); fs:SetTextColor(r,g,b,1) end end
                end
                btn:ClearAllPoints()
                btn:SetPoint("TOP", lastBtn, "BOTTOM", 0, -12)
                lastBtn = btn
                extraH = extraH + 40
            end
            if showUnlock then
                unlockBtn:Show()
                if brandHex then
                    unlockBtn:SetText(brandHex .. "EUI|r |cffffffffUnlock Mode|r")
                else
                    unlockBtn:SetText("EUI Unlock Mode")
                end
                if _reskinMenu then
                    local fs2 = unlockBtn:GetFontString()
                    if fs2 then fs2:SetFont(euiFont, btnFontSize, ""); if not brandHex and EllesmereUI._getPopupMenuButtonTextColor then local r,g,b=EllesmereUI._getPopupMenuButtonTextColor(); fs2:SetTextColor(r,g,b,1) end end
                end
                unlockBtn:ClearAllPoints()
                unlockBtn:SetPoint("TOP", lastBtn, "BOTTOM", 0, showEUI and -4 or -12)
                extraH = extraH + (showEUI and 40 or 40)
            end

            -- Push all Blizzard buttons below the anchor down
            local anchorBottom = anchorBtn:GetBottom()
            if anchorBottom then
                for menuBtn in GameMenuFrame.buttonPool:EnumerateActive() do
                    local top = menuBtn:GetTop()
                    if top and top < anchorBottom + 2 then
                        local p, rel, rp, x, y = menuBtn:GetPoint(1)
                        if p then
                            menuBtn:ClearAllPoints()
                            menuBtn:SetPoint(p, rel, rp, x, (y or 0) - extraH)
                        end
                    end
                end
            end

            if not _gameMenuBaseHeight then
                _gameMenuBaseHeight = GameMenuFrame:GetHeight()
            end
            GameMenuFrame:SetHeight(_gameMenuBaseHeight + extraH)
        end)
    end

    -- Apply theme settings from SavedVariables
    if EllesmereUIDB then
        local theme = EllesmereUIDB.activeTheme or EllesmereUI.DEFAULT_THEME
        ELLESMERE_GREEN._themeEnabled = true
        local themeR, themeG, themeB = EllesmereUI.ResolveThemeColor(theme)
        -- Apply theme color to the window background only. The EUI Options Theme
        -- is a SEPARATE, global control from the UI accent color (per-profile).
        if EllesmereUI._applyBgTint then
            EllesmereUI._applyBgTint(themeR, themeG, themeB)
        end
        -- Art left out of the file-load preload is preloaded for its own player only.
        EllesmereUI._PreloadLazyThemeBG(theme)
        -- UI accent: authoritative login resolution for the active profile
        -- (per-profile euiAccent -> frozen global root -> theme color). When a
        -- profile has no per-profile accent this reproduces the legacy behavior
        -- exactly, so existing users see zero change.
        --
        -- Routed through the live-apply path rather than assigning the three
        -- fields directly: Lite is TOC-ordered ahead of this file, so its
        -- PLAYER_LOGIN fires first and every module's OnEnable has already
        -- painted against the parse-time fallback. Notifying repaints them.
        local accentR, accentG, accentB = EllesmereUI.ResolveActiveAccent()
        if EllesmereUI.ApplyAccentColorLive then
            EllesmereUI.ApplyAccentColorLive(accentR, accentG, accentB)
        else
            ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = accentR, accentG, accentB
        end
    end

    -- Spell ID / Item ID + Icon ID / Max Item Stack on Tooltip (developer option)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        -- Register per-type callbacks instead of AllTypes to avoid firing on every unit/currency tooltip in the game (major CPU savings).
        local _isSecret = issecretvalue  -- cache global once

        -- The spell/item/icon ID lines can be gated behind a held modifier (the "Use Modifier"
        -- cog: none | shift | control | alt, default none). "none" shows them whenever Show
        -- Spell ID is on (the original behavior); the others only surface the lines while that key is held.
        local function IsSpellIDModifierHeld()
            local mod = (EllesmereUIDB and EllesmereUIDB.spellIDModifier) or "none"
            if mod == "none" then return true end
            if mod == "control" then return IsControlKeyDown() end
            if mod == "alt" then return IsAltKeyDown() end
            return IsShiftKeyDown()
        end

        -- The Max Item Stack lines can be gated behind a held modifier (the "Use Modifier" cog:
        -- none | shift | control | alt, default none). "none" shows them whenever Show Max Stack
        -- for items is on (the original behavior); the others only surface the lines while that key is held.
        local function IsItemStackModifierHeld()
            local mod = (EllesmereUIDB and EllesmereUIDB.itemStackModifier) or "none"
            if mod == "none" then return true end
            if mod == "control" then return IsControlKeyDown() end
            if mod == "alt" then return IsAltKeyDown() end
            return IsShiftKeyDown()
        end

        -- Shared dedup check: only scan last 5 lines (we add at most 3)
        local function hasDupLine(tooltip, name, tag)
            local n = tooltip:NumLines()
            local start = n - 4
            if start < 1 then start = 1 end
            for i = n, start, -1 do
                local fs = _G[name .. "TextLeft" .. i]
                if fs then
                    local txt = fs:GetText()
                    if txt then
                        if _isSecret and _isSecret(txt) then return true end
                        if txt:find(tag) then return true end
                    end
                end
            end
            return false
        end

        -- 12.1 ONLY: aura spell IDs during combat. The Lua hooks below can never render them
        -- there -- under aura restrictions the tooltip's id is a SECRET value -- but the
        -- engine-side tooltipShowAuraSpellIDs CVar (68824+) formats the ID itself and works under
        -- full secrecy, including the forbidden container tooltips. The CVar is session-only, so
        -- it re-asserts every login and on toggle edits. Modifier-gated configs skip it: the engine renders always-on, which would override the user's hold-a-modifier preference (their combat aura IDs stay unavailable -- inherent trade).
        function EllesmereUI.SyncAuraSpellIDCVar()
            local db = EllesmereUIDB
            local on = EllesmereUI.SpellIDOn()
                and (db.spellIDModifier or "none") == "none"
            pcall(EllesmereUI.SetCVar, "tooltipShowAuraSpellIDs", on and "1" or "0")
        end
        do
            -- PLAYER_ENTERING_WORLD, not PLAYER_LOGIN: the engine settles its
            -- session CVars after login and clobbered the early write -- aura
            -- IDs stayed off until the user re-toggled the option (field-
            -- reported). Kept registered: a re-assert per zone-in is one
            -- pcall'd SetCVar and survives any later engine reset.
            local cvarBoot = CreateFrame("Frame")
            cvarBoot:RegisterEvent("PLAYER_ENTERING_WORLD")
            -- Instance zone-ins also remind once per session about the two
            -- debug CVars that quietly tax combat performance (taintLog is
            -- often left on after a bug-report capture; scriptProfile adds
            -- per-call overhead to every addon and only changes effect on
            -- reload). Ignore or Esc keeps it quiet until the next reload;
            -- the flag is set on SHOW, so nothing re-fires on later zones.
            local perfPromptShown = false
            cvarBoot:SetScript("OnEvent", function()
                EllesmereUI.SyncAuraSpellIDCVar()
                if perfPromptShown or not IsInInstance() then return end
                local taintOn = (tonumber(GetCVar("taintLog") or 0) or 0) > 0
                local profOn  = (tonumber(GetCVar("scriptProfile") or 0) or 0) > 0
                if not (taintOn or profOn) then return end
                perfPromptShown = true
                local which
                if taintOn and profOn then
                    which = EllesmereUI.L("The taintLog and scriptProfile CVars are enabled.")
                elseif taintOn then
                    which = EllesmereUI.L("The taintLog CVar is enabled.")
                else
                    which = EllesmereUI.L("The scriptProfile CVar is enabled.")
                end
                EllesmereUI:ShowConfirmPopup({
                    title       = EllesmereUI.L("Performance Reminder"),
                    message     = which .. " " .. EllesmereUI.L("It reduces performance and should be off unless you are capturing a bug report."),
                    confirmText = EllesmereUI.L("Disable and Reload"),
                    cancelText  = EllesmereUI.L("Ignore"),
                    reload      = true,
                    onConfirm   = function()
                        -- The player's own fix, which Uninstall EUI must not
                        -- undo: plain SetCVar, not EllesmereUI.SetCVar.
                        pcall(C_CVar.SetCVar, "taintLog", "0")
                        pcall(C_CVar.SetCVar, "scriptProfile", "0")
                    end,
                })
            end)
        end

        local function SpellIDTooltipHook(tooltip, data)
            if not EllesmereUI.SpellIDOn() then return end
            if not IsSpellIDModifierHeld() then return end
            if not data or not data.id then return end
            if _isSecret and _isSecret(data.id) then return end
            -- 12.1 no-modifier configs render aura IDs engine-side via the tooltipShowAuraSpellIDs
            -- CVar (see SyncAuraSpellIDCVar); adding the Lua line too would show the ID twice on aura tooltips.
            if Enum.TooltipDataType
                and data.type == Enum.TooltipDataType.UnitAura
                and (EllesmereUIDB.spellIDModifier or "none") == "none" then
                return
            end
            if not tooltip or not tooltip.GetName then return end
            local ok, name = pcall(tooltip.GetName, tooltip)
            if not ok or not name then return end
            if hasDupLine(tooltip, name, "SpellID") then return end
            tooltip:AddDoubleLine("SpellID", tostring(data.id), 1, 1, 1, 1, 1, 1)
            if EllesmereUIDB.showIconID ~= false then
                local iconID = C_Spell.GetSpellTexture(data.id)
                if iconID then
                    tooltip:AddDoubleLine("IconID", tostring(iconID), 1, 1, 1, 1, 1, 1)
                end
            end
            tooltip:Show()
        end

        local function ItemIDTooltipHook(tooltip, data)
            if not EllesmereUI.SpellIDOn() then return end
            if not IsSpellIDModifierHeld() then return end
            if not data or not data.id then return end
            if _isSecret and _isSecret(data.id) then return end
            if not tooltip or not tooltip.GetName then return end
            local ok, name = pcall(tooltip.GetName, tooltip)
            if not ok or not name then return end
            -- The gem-socketing window's item text is a tooltip-data frame; ID lines do not belong inside that window.
            if name == "ItemSocketingDescription" then return end
            if hasDupLine(tooltip, name, "ItemID") then return end
            local showItem = EllesmereUIDB.showItemID ~= false
            local showIcon = EllesmereUIDB.showIconID ~= false
            if not showItem and not showIcon then return end
            if showItem then
                tooltip:AddDoubleLine("ItemID", tostring(data.id), 1, 1, 1, 1, 1, 1)
            end
            if showIcon then
                local iconID = C_Item.GetItemIconByID and C_Item.GetItemIconByID(data.id)
                    or (GetItemIcon and GetItemIcon(data.id))
                if iconID then
                    tooltip:AddDoubleLine("IconID", tostring(iconID), 1, 1, 1, 1, 1, 1)
                end
            end
            tooltip:Show()
        end

        local function ItemIdMaxStackHook(tooltip, data)
            if not (EllesmereUIDB and EllesmereUIDB.showItemMaxStacks) then return end
            if not IsItemStackModifierHeld() then return end
            if not data or not data.id then return end
            if _isSecret and _isSecret(data.id) then return end
            if not tooltip or not tooltip.GetName then return end
            local ok, name = pcall(tooltip.GetName, tooltip)
            if not ok or not name then return end
            if name == "ItemSocketingDescription" then return end
            if hasDupLine(tooltip, name, "Max Stack") then return end

            -- 8th return of GetItemInfo is the native max stack size; nil while the item is uncached (the line then appears on the next hover).
            local _, _, _, _, _, _, _, maxStack = C_Item.GetItemInfo(data.id)
            if maxStack and maxStack > 1 then
                tooltip:AddDoubleLine("Max Stack", tostring(maxStack), 1, 1, 1, 1, 1, 1)
                tooltip:Show()
            end
        end

        -- Macros surface as their own tooltip type, so the Spell hook above never fires for
        -- them (GetSpell() also returns nil on a macro tooltip). The spell #showtooltip resolved
        -- to (honoring conditionals) is exposed as the FIRST tooltip line's tooltipID, read from the tooltip data.
        local function MacroSpellIDTooltipHook(tooltip, _data)
            if not EllesmereUI.SpellIDOn() then return end
            if not IsSpellIDModifierHeld() then return end
            if not tooltip or not tooltip.GetName or not tooltip.GetTooltipData then return end
            local ok, info = pcall(tooltip.GetTooltipData, tooltip)
            if not ok or type(info) ~= "table" or not info.lines then return end
            local line = info.lines[1]
            local spellID = line and line.tooltipID
            if not spellID then return end  -- item-only macro / nothing castable
            if _isSecret and _isSecret(spellID) then return end
            local okN, name = pcall(tooltip.GetName, tooltip)
            if not okN or not name then return end
            if hasDupLine(tooltip, name, "SpellID") then return end
            tooltip:AddDoubleLine("SpellID", tostring(spellID), 1, 1, 1, 1, 1, 1)
            if EllesmereUIDB.showIconID ~= false then
                local iconID = C_Spell.GetSpellTexture(spellID)
                if iconID then
                    tooltip:AddDoubleLine("IconID", tostring(iconID), 1, 1, 1, 1, 1, 1)
                end
            end
            tooltip:Show()
        end

        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, SpellIDTooltipHook)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, SpellIDTooltipHook)
        if Enum.TooltipDataType.PetAction then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.PetAction, SpellIDTooltipHook)
        end
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ItemIDTooltipHook)
        if Enum.TooltipDataType.Macro then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, MacroSpellIDTooltipHook)
        end
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ItemIdMaxStackHook)

        -- Live toggle: when a selected modifier is pressed/released while a tooltip is hovered,
        -- re-process the shown GameTooltip so the ID and Max Stack lines appear/disappear without
        -- re-hovering. RefreshData re-runs the post-calls above (which then add or skip their
        -- lines per their own modifier checks). Only fires when a feature is on and its chosen modifier actually changed.
        local function KeyMatchesModifier(key, mod)
            return (mod == "shift"   and (key == "LSHIFT" or key == "RSHIFT"))
                or (mod == "control" and (key == "LCTRL"  or key == "RCTRL"))
                or (mod == "alt"     and (key == "LALT"   or key == "RALT"))
        end
        local modWatcher = CreateFrame("Frame")
        modWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
        modWatcher:SetScript("OnEvent", function(_, key)
            local db = EllesmereUIDB
            if not db then return end
            local relevant =
                (EllesmereUI.SpellIDOn() and KeyMatchesModifier(key, db.spellIDModifier or "none"))
                or (db.showItemMaxStacks and KeyMatchesModifier(key, db.itemStackModifier or "none"))
            if not relevant then return end
            if GameTooltip and GameTooltip:IsShown() and GameTooltip.RefreshData then
                GameTooltip:RefreshData()
            end
        end)
    end

    -- Consolidated Blizzard AddOns > Options panel (single entry for all Ellesmere addons)
    local panel = CreateFrame("Frame")
    panel.name = "EllesmereUI"
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(200, 30)
    btn:SetPoint("CENTER", panel, "CENTER", 0, 0)
    btn:SetText("Open EllesmereUI")
    btn:SetScript("OnClick", function()
        if InCombatLockdown() then
            EllesmereUI.PrintError("Cannot open options during combat.")
            return
        end
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

    local dT, dS, dD = {}, {}, {}
    local demoConfigs = {
        -- Only list addons that do NOT have their own EUI_*_Options.lua yet. Addons with real
        -- options files register via PLAYER_LOGIN and must NOT appear here -- the demo would race and win due to page caching.
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

            EUI_NS.RegisterCoreModule(cfg.folder, {
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
                        function(v) dS[k].spacing = v end, nil, true);                                   y = y - h
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
                    EllesmereUI:SelectPage(EllesmereUI:GetActivePage())
                end,
            }, false)
        end
    end
end)
