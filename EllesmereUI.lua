if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI.lua  -  Custom Options Panel, shared across the whole EUI suite.
--  Scaffold: background, sidebar, header, content area, controls.
-------------------------------------------------------------------------------
local EUI_HOST_ADDON = ...
-- Build renames "EllesmereUI" -> "EUICoreStandalone<Module>" but never the word
-- "Standalone", so host name contains it iff standalone; false in the suite (branches inert).
local IS_STANDALONE = type(EUI_HOST_ADDON) == "string" and EUI_HOST_ADDON:find("Standalone") ~= nil
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
    for _, file in pairs(THEME_BG_FILES) do
        local tex = preload:CreateTexture()
        tex:SetTexture(mp .. file)
        tex:SetAllPoints()
    end
    local baseTex = preload:CreateTexture()
    baseTex:SetTexture(mp .. "backgrounds\\eui-bg.png")
    baseTex:SetAllPoints()
end

-- EllesmereUIDB arrives from SavedVariables at ADDON_LOADED. Do NOT create it here --
-- that overwrites saved data. (Stale child SV copy guard lives in EllesmereUI_Lite.lua.)

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

-- Sidebar nav values inlined into NAV_* locals below to avoid an extra file-scope local

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
    -- CLASS_COLOR_MAP is defined below: parse time resolves presets only; Class/Custom resolve at PLAYER_LOGIN.
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

local ADDON_ROSTER = {
    { folder = "EllesmereUIActionBars",        display = "Action Bars",          search_name = "EllesmereUI Action Bars"             },
    { folder = "EllesmereUINameplates",        display = "Nameplates",           search_name = "EllesmereUI Nameplates"              },
    { folder = "EllesmereUIUnitFrames",        display = "Unit Frames",          search_name = "EllesmereUI Unit Frames"             },
    { folder = "EllesmereUIRaidFrames",        display = "Raid Frames",          search_name = "EllesmereUI Raid Frames"             },
    { folder = "EllesmereUICooldownManager",   display = "Cooldown Manager",     search_name = "EllesmereUI Cooldown Manager"        },
    { folder = "EllesmereUIResourceBars",      display = "Resource & Cast Bars", search_name = "EllesmereUI Resource Bars Cast Bars" },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders",   search_name = "EllesmereUI AuraBuff Reminders"      },
    { folder = "EllesmereUIQoL",               display = "Quality of Life",      search_name = "EllesmereUI Quality of Life"         },
    { folder = "EllesmereUIBlizzardSkin",      display = "Blizz UI Enhanced",    search_name = "EllesmereUI Blizz UI Enhanced",      syncFolder = "EllesmereUIDragonRiding", syncDisplay = "Dragon Riding" },
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

-- Flat folder -> roster-info lookup for the grouped sidebar builder. On EllesmereUI
-- (not a local): CreateMainFrame is up against the Lua 5.1 60-upvalue limit.
EllesmereUI._addonInfoByFolder = {}
for _, info in ipairs(ADDON_ROSTER) do
    EllesmereUI._addonInfoByFolder[info.folder] = info
end

local function IsAddonLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name)
    elseif IsAddOnLoaded then return IsAddOnLoaded(name) end
    return false
end

-------------------------------------------------------------------------------
--  Profile Sync System (mirror groups)
--  A module's sync set is a MEMBERSHIP group (popup adds the configuring profile too).
--  Two-way: active member pushes a selective copy to others on sync click, logout, and
--  profile switch; outside profiles never push in. Storage: EllesmereUIDB.syncedModules
--  = { [folder] = { [profileName] = true } }. Exclusions: EllesmereUI._syncExclusions
--  [folder] = { key = true }; dot-wildcard "bars.*.growDirection" skips that key in any sub-table of bars.
-------------------------------------------------------------------------------
do
    -- Modules that should NOT get a sync icon (no per-profile settings)
    local SYNC_EXEMPT = { EllesmereUIPartyMode = true }
    EllesmereUI._syncExempt = SYNC_EXEMPT

    -- Modules with a sync icon but no per-profile data (always "synced"). BlizzardSkin hosts
    -- Dragon Riding's per-profile DB; its sync icon routes to EllesmereUIDragonRiding via syncFolder.
    local SYNC_GLOBAL_ONLY = {}
    EllesmereUI._syncGlobalOnly = SYNC_GLOBAL_ONLY

    -- Exclusion registry: keys NOT copied during sync (flat or dot-wildcard, see banner)
    local syncExclusions = {}
    EllesmereUI._syncExclusions = syncExclusions

    function EllesmereUI.RegisterSyncExclusions(folder, keys)
        if not syncExclusions[folder] then syncExclusions[folder] = {} end
        local ex = syncExclusions[folder]
        for _, k in ipairs(keys) do
            ex[k] = true
        end
    end

    -- Merged exclusions for ONE src->dst copy: static registry plus every setting EITHER
    -- profile holds a spec/conditional OVERRIDE entry for (override-owned keys never sync --
    -- the override system owns them; a pushed blob would drift from the dest's recorded values).
    -- PURE READ of profile tables only (no override store creation/harvest/apply/capture).
    -- Returns staticEx unchanged (zero alloc) when neither profile has override data, else a
    -- fresh table (shared registry never mutated); callers pcall and fall back to staticEx on error.
    -- fkey = folder.."\31"..path, segments joined by "\30" (mirrors SplitFKey in
    -- EllesmereUI_SpecOverrides.lua); matcher walks the tree dot-joined so gsub("\30",".") is exact.
    EllesmereUI._SyncExclusionsWithOverrides = function(folder, staticEx, srcProf, dstProf)
        local merged
        local function ensure()
            if not merged then
                merged = {}
                if staticEx then for k in pairs(staticEx) do merged[k] = true end end
            end
        end
        local function addStore(store)
            if type(store) ~= "table" then return end
            for _, entry in ipairs(store) do
                local vals = type(entry) == "table" and entry.values
                if type(vals) == "table" then
                    for _, m in pairs(vals) do  -- default map + every spec/gid map
                        if type(m) == "table" then
                            for fkey in pairs(m) do
                                if type(fkey) == "string" then
                                    local f, path = fkey:match("^([^\31]+)\31(.*)$")
                                    if f == folder and path and path ~= "" then
                                        ensure()
                                        merged[path:gsub("\30", ".")] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        local function addProf(prof)
            if type(prof) ~= "table" then return end
            addStore(prof.specOverrides)
            addStore(prof.condOverrides)
            if folder == "EllesmereUIRaidFrames" then
                -- BM forks are layer-shaped, not fkey-shaped: the fork system writes
                -- bmIndicators/bmSimple/bmDisplayMode/bmIconZoom straight into the live RF blob,
                -- so if EITHER profile carries ANY BM layer, those keys are fork territory and
                -- must not sync (emptiness check mirrors the BM harvest's zero-cost gate).
                local s, c = prof.specBmOverrides, prof.condBmOverrides
                if (type(s) == "table" and (s.active or s.baselineLayout
                        or (type(s.layouts) == "table" and next(s.layouts))))
                   or (type(c) == "table" and type(c.layouts) == "table"
                        and next(c.layouts)) then
                    ensure()
                    merged.bmIndicators  = true
                    merged.bmSimple      = true
                    merged.bmDisplayMode = true
                    merged.bmIconZoom    = true
                    merged.bm2           = true   -- v2 payload rides BM layers
                end
                -- Debuff Manager forks own the dmDebuff subtree the same way.
                local ds, dc = prof.specDmOverrides, prof.condDmOverrides
                if (type(ds) == "table" and (ds.active or ds.baselineLayout
                        or (type(ds.layouts) == "table" and next(ds.layouts))))
                   or (type(dc) == "table" and type(dc.layouts) == "table"
                        and next(dc.layouts)) then
                    ensure()
                    merged.dmDebuff = true
                end
            end
        end
        addProf(srcProf)
        addProf(dstProf)
        return merged or staticEx
    end

    -- Selective deep-copy: src minus excluded keys (flat "barPositions" or wildcard
    -- "bars.*.growDirection" = skip that key in any sub-table of "bars").
    local function SelectiveCopy(src, exclusions, parentPath)
        if type(src) ~= "table" then return src end
        local copy = {}
        for k, v in pairs(src) do
            local keyStr = tostring(k)
            local fullKey = parentPath and (parentPath .. "." .. keyStr) or keyStr
            if not exclusions[fullKey] then
                if type(v) == "table" then
                    -- Wildcard parent check (e.g. "bars" in "bars.*.X")
                    local isWildcardParent = false
                    local childExclusions = nil
                    for exKey in pairs(exclusions) do
                        local prefix, childKey = exKey:match("^(.-)%.%*%.(.+)$")
                        -- Full-path match only (a bare-name collision is not a wildcard parent)
                        if prefix and fullKey == prefix then
                            isWildcardParent = true
                            if not childExclusions then childExclusions = {} end
                            childExclusions[childKey] = true
                        end
                    end
                    if isWildcardParent and childExclusions then
                        -- Copy the container but apply child exclusions to each sub-table
                        local containerCopy = {}
                        for ck, cv in pairs(v) do
                            if type(cv) == "table" then
                                local subCopy = {}
                                for sk, sv in pairs(cv) do
                                    if not childExclusions[tostring(sk)] then
                                        if type(sv) == "table" then
                                            subCopy[sk] = SelectiveCopy(sv, {})
                                        else
                                            subCopy[sk] = sv
                                        end
                                    end
                                end
                                containerCopy[ck] = subCopy
                            else
                                containerCopy[ck] = cv
                            end
                        end
                        copy[k] = containerCopy
                    else
                        copy[k] = SelectiveCopy(v, exclusions, fullKey)
                    end
                else
                    copy[k] = v
                end
            end
        end
        return copy
    end
    EllesmereUI._SelectiveCopy = SelectiveCopy

    -- Exclusion-aware deep overlay for destinations with existing data: writes src into dst
    -- leaf-by-leaf wherever an exclusion path (flat/dotted/wildcard) touches the subtree, so
    -- excluded keys keep dest values (replacing a parent whole would delete them).
    function EllesmereUI._SelectiveOverlay(src, dst, exclusions, deepCopy, parentPath)
        for k, v in pairs(src) do
            local keyStr = tostring(k)
            local fullKey = parentPath and (parentPath .. "." .. keyStr) or keyStr
            if not exclusions[fullKey] then
                if type(v) == "table" then
                    -- Wildcard parent and/or dotted exclusions deeper in this subtree
                    local childExclusions = nil
                    local hasNested = false
                    for exKey in pairs(exclusions) do
                        local prefix, childKey = exKey:match("^(.-)%.%*%.(.+)$")
                        -- Full-path match only (same rule as SelectiveCopy)
                        if prefix and fullKey == prefix then
                            if not childExclusions then childExclusions = {} end
                            childExclusions[childKey] = true
                        elseif exKey:sub(1, #fullKey + 1) == (fullKey .. ".") then
                            hasNested = true
                        end
                    end
                    if childExclusions then
                        -- Merge each sub-table, preserving excluded child keys
                        if type(dst[k]) ~= "table" then dst[k] = {} end
                        local dstContainer = dst[k]
                        for ck, cv in pairs(v) do
                            if type(cv) == "table" then
                                if type(dstContainer[ck]) ~= "table" then dstContainer[ck] = {} end
                                local dstSub = dstContainer[ck]
                                for sk, sv in pairs(cv) do
                                    if not childExclusions[tostring(sk)] then
                                        dstSub[sk] = type(sv) == "table" and deepCopy(sv) or sv
                                    end
                                end
                            else
                                dstContainer[ck] = cv
                            end
                        end
                    elseif hasNested then
                        if type(dst[k]) ~= "table" then dst[k] = {} end
                        EllesmereUI._SelectiveOverlay(v, dst[k], exclusions, deepCopy, fullKey)
                    else
                        dst[k] = deepCopy(v)
                    end
                else
                    dst[k] = v
                end
            end
        end
    end

    function EllesmereUI.IsProfileSynced(folder, profileName)
        if not EllesmereUIDB then return false end
        local sm = EllesmereUIDB.syncedModules
        if not sm or not sm[folder] then return false end
        local targets = sm[folder]
        return type(targets) == "table" and targets[profileName] == true
    end

    function EllesmereUI.GetSyncedProfiles(folder)
        if not EllesmereUIDB or not EllesmereUIDB.syncedModules then return {} end
        local targets = EllesmereUIDB.syncedModules[folder]
        if type(targets) == "table" then return targets end
        return {}
    end

    -- Fully synced = EVERY profile is a group member. Never keyed off activeProfile
    -- (resolves per character/spec) so the icon reads the same on every character.
    function EllesmereUI.IsModuleFullySynced(folder)
        if not EllesmereUIDB or not EllesmereUIDB.syncedModules or not EllesmereUIDB.profiles then return false end
        local targets = EllesmereUIDB.syncedModules[folder]
        if type(targets) ~= "table" then return false end
        local total = 0
        for name in pairs(EllesmereUIDB.profiles) do
            total = total + 1
            if not targets[name] then return false end
        end
        return total > 1
    end

    -- Check if ANY profile is synced for a module (for icon state)
    function EllesmereUI.IsModuleSynced(folder)
        if not EllesmereUIDB or not EllesmereUIDB.syncedModules then return false end
        local targets = EllesmereUIDB.syncedModules[folder]
        if type(targets) ~= "table" then return false end
        for _, v in pairs(targets) do if v then return true end end
        return false
    end

    -- Sync one module from active profile to specific target profiles
    function EllesmereUI.SyncModuleToProfiles(folder, targetProfiles)
        if not EllesmereUIDB or not EllesmereUIDB.profiles then return end
        local active = EllesmereUIDB.activeProfile or "Default"
        local src = EllesmereUIDB.profiles[active]
        if not src or not src.addons or not src.addons[folder] then return end
        local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy
        if not DeepCopy then return end

        local staticEx = syncExclusions[folder]
        local exFn = EllesmereUI._SyncExclusionsWithOverrides
        for profName in pairs(targetProfiles) do
            if profName ~= active then
                local prof = EllesmereUIDB.profiles[profName]
                if prof then
                    if not prof.addons then prof.addons = {} end
                    -- Merge both profiles' override-entry paths into the static set
                    -- (fail-open: any derive error keeps static-only behavior).
                    local exclusions = staticEx
                    if exFn then
                        local ok, m = pcall(exFn, folder, staticEx, src, prof)
                        if ok and m then exclusions = m end
                    end
                    if exclusions and next(exclusions) then
                        local dst = prof.addons[folder]
                        if not dst then
                            -- First sync to this profile: no dest values to preserve
                            prof.addons[folder] = SelectiveCopy(src.addons[folder], exclusions)
                        else
                            -- Overlay leaf-by-leaf so excluded keys keep dest values
                            EllesmereUI._SelectiveOverlay(src.addons[folder], dst, exclusions, DeepCopy)
                        end
                    else
                        -- Full blob copy (no exclusions)
                        prof.addons[folder] = DeepCopy(src.addons[folder])
                    end
                end
            end
        end
    end

    -- Set the sync group for a module and execute an initial push
    function EllesmereUI.SetModuleSyncTargets(folder, targetProfiles)
        if not EllesmereUIDB then return end
        if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
        EllesmereUIDB.syncedModules[folder] = targetProfiles
        EllesmereUI.SyncModuleToProfiles(folder, targetProfiles)
    end

    -- Equalize a module across group members from an explicit source ("seed"). Non-active dests
    -- get a selective copy; an ACTIVE dest is written IN PLACE (live db.profile refs stay valid),
    -- defaults re-merged (stored blobs are sparse), then UI refreshed. Excluded (layout) keys keep each dest's values.
    function EllesmereUI.SyncModuleFromProfile(folder, srcName, targets)
        if not EllesmereUIDB or not EllesmereUIDB.profiles then return end
        local active = EllesmereUIDB.activeProfile or "Default"
        if srcName == active then
            EllesmereUI.SyncModuleToProfiles(folder, targets)
            return
        end
        local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy
        if not DeepCopy then return end
        local srcProf = EllesmereUIDB.profiles[srcName]
        local srcData = srcProf and srcProf.addons and srcProf.addons[folder]
        if not srcData then return end

        local staticEx = syncExclusions[folder]
        local exFn = EllesmereUI._SyncExclusionsWithOverrides
        for profName in pairs(targets) do
            if profName ~= srcName then
                local prof = EllesmereUIDB.profiles[profName]
                if prof then
                    if not prof.addons then prof.addons = {} end
                    -- Same override-ownership exclusions as SyncModuleToProfiles.
                    local exclusions = staticEx
                    if exFn then
                        local ok, m = pcall(exFn, folder, staticEx, srcProf, prof)
                        if ok and m then exclusions = m end
                    end
                    local dst = prof.addons[folder]
                    if profName == active then
                        -- Live profile: adopt in place, never replace the table
                        if type(dst) ~= "table" then
                            dst = {}
                            prof.addons[folder] = dst
                        end
                        if exclusions and next(exclusions) then
                            EllesmereUI._SelectiveOverlay(srcData, dst, exclusions, DeepCopy)
                        else
                            wipe(dst)
                            for k, v in pairs(srcData) do
                                dst[k] = type(v) == "table" and DeepCopy(v) or v
                            end
                        end
                    elseif not (exclusions and next(exclusions)) then
                        prof.addons[folder] = DeepCopy(srcData)
                    elseif type(dst) == "table" then
                        EllesmereUI._SelectiveOverlay(srcData, dst, exclusions, DeepCopy)
                    else
                        prof.addons[folder] = SelectiveCopy(srcData, exclusions)
                    end
                end
            end
        end

        if targets[active] then
            -- Re-merge defaults into the adopted live table, then refresh addons and any open options page
            local reg = EllesmereUI.Lite._dbRegistry
            if reg then
                for _, rdb in ipairs(reg) do
                    if rdb.folder == folder then
                        if rdb._profileDefaults and rdb.profile then
                            EllesmereUI.Lite.DeepMergeDefaults(rdb.profile, rdb._profileDefaults)
                        end
                        break
                    end
                end
            end
            if EllesmereUI.RefreshAllAddons then
                EllesmereUI.RefreshAllAddons()
            end
            if EllesmereUI.RefreshPage then
                EllesmereUI:RefreshPage()
            end
        end
    end

    -- Pre-logout push to other group members. Only a MEMBER pushes; an outside
    -- profile must never overwrite member data regardless of what is active.
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if EllesmereUI.Lite and EllesmereUI.Lite.RegisterPreLogout then
            EllesmereUI.Lite.RegisterPreLogout(function()
                if not EllesmereUIDB or not EllesmereUIDB.syncedModules then return end
                local active = EllesmereUIDB.activeProfile or "Default"
                for folder, targets in pairs(EllesmereUIDB.syncedModules) do
                    if type(targets) == "table" and targets[active] then
                        EllesmereUI.SyncModuleToProfiles(folder, targets)
                    end
                end
            end)
        end
    end)
end


-------------------------------------------------------------------------------
--  Sync Exclusions per Module -- keys listed here are NOT copied when syncing between profiles.
-------------------------------------------------------------------------------
EllesmereUI.RegisterSyncExclusions("EllesmereUIActionBars", {
    "barPositions",
    "bars.*.growDirection",
    "bars.*.orientation",
    "bars.*.buttonWidth",
    "bars.*.buttonHeight",
    "bars.*.targetWidth",
    "bars.*.targetHeight",
    "bars.*.width",
    "bars.*.height",
    "bars.*.overrideNumIcons",
    "bars.*.overrideNumRows",
    "bars.*.numIcons",
    "bars.*.numRows",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUIUnitFrames", {
    "positions",
    "player.frameWidth", "player.healthHeight",
    "target.frameWidth", "target.healthHeight",
    "playerTarget.frameWidth", "playerTarget.healthHeight",
    "targettarget.frameWidth", "targettarget.healthHeight",
    "focustarget.frameWidth", "focustarget.healthHeight",
    "pet.frameWidth", "pet.healthHeight",
    "focus.frameWidth", "focus.healthHeight",
    "boss.frameWidth", "boss.healthHeight",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUICooldownManager", {
    "cdmBarPositions",
    "cdmBars.bars.*.iconSize",
    "cdmBars.bars.*.numRows",
    "cdmBars.bars.*.anchorFirstRow",
    "cdmBars.bars.*.rowGrowDirection",
    "cdmBars.bars.*.spacing",
    "cdmBars.bars.*.verticalOrientation",
    "cdmBars.bars.*.anchorTo",
    "cdmBars.bars.*.anchorPosition",
    "cdmBars.bars.*.anchorOffsetX",
    "cdmBars.bars.*.anchorOffsetY",
    "cdmBars.bars.*.keybindOffsetX",
    "cdmBars.bars.*.keybindOffsetY",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUIResourceBars", {
    "health.width", "health.height", "health.offsetX", "health.offsetY", "health.orientation",
    "primary.width", "primary.height", "primary.offsetX", "primary.offsetY", "primary.orientation",
    "secondary.pipWidth", "secondary.pipHeight", "secondary.pipSpacing", "secondary.pipOrientation",
    "secondary.offsetX", "secondary.offsetY",
    "castBar.width", "castBar.height", "castBar.anchorX", "castBar.anchorY", "castBar.unlockPos",
    "totemBar.iconSize", "totemBar.spacing", "totemBar.unlockPos",
    "general.anchorX", "general.anchorY", "general.orientation",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUIAuraBuffReminders", {
    "unlockPos",
    "display.xOffset", "display.yOffset",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUIRaidFrames", {
    "unlockPos",
})

EllesmereUI.RegisterSyncExclusions("EllesmereUIMythicTimer", {
    "standalonePos",
    "scale",
    "frameWidth",
})

-- Dragon Riding HUD position (unlockPos) stays per-profile on sync, like every module.
EllesmereUI.RegisterSyncExclusions("EllesmereUIDragonRiding", {
    "unlockPos",
})

-- QoL Secondary Stats/FPS positions and the cursor slice (GCD ring, cast circle, at
-- profile.cursor) stay per-profile on sync: exported intact, never push-overwritten.
EllesmereUI.RegisterSyncExclusions("EllesmereUIQoL", {
    "secondaryStatsPos",
    "fpsPos",
    "cursor.gcd.pos",
    "cursor.castCircle.pos",
})

-- Minimap settings nest under profile.minimap.
EllesmereUI.RegisterSyncExclusions("EllesmereUIMinimap", {
    "minimap.position",      -- unlock-element drag position
    "minimap.btnPositions",  -- per-button shift-drag offsets
})

-- Chat settings nest under profile.chat.
EllesmereUI.RegisterSyncExclusions("EllesmereUIChat", {
    "chat.chatPosition",   -- unlock drag position
    "chat.chatWidth",      -- unlock resize-handle width
    "chat.chatHeight",     -- unlock resize-handle height
    "chat.toastPosition",  -- BNet toast unlock position
    "chat.iconPositions",  -- per-sidebar-icon shift-drag offsets
})

-- Damage Meters settings nest under profile.dm.
EllesmereUI.RegisterSyncExclusions("EllesmereUIDamageMeters", {
    "dm.standaloneTimerPos",  -- drag-written standalone timer position
    "dm.windows.*.position",  -- per-window drag position
    "dm.windows.*.width",     -- per-window drag-resize width
    "dm.windows.*.height",    -- per-window drag-resize height
})

-- DataBars per-bar geometry lives in the top-level bars array (wildcard shape as ActionBars).
EllesmereUI.RegisterSyncExclusions("EllesmereUIDataBars", {
    "bars.*.savedPos",   -- unlock drag position
    "bars.*.length",     -- unlock resize owned
    "bars.*.thickness",  -- unlock resize owned
    "bars.*.snapEdge",   -- mutated by the drag save itself
})

-- Bags is the one auto-synced module: without this the bank position mirrors across profiles.
EllesmereUI.RegisterSyncExclusions("EllesmereUIBags", {
    "bankPosition",  -- bank window shift-drag position
})

-------------------------------------------------------------------------------
--  Sync Popup -- anchored flush to sidebar's right edge, centered on clicked sync icon,
--  clamped to the EUI window bottom.
-------------------------------------------------------------------------------
do
    local _syncPopup = nil

    function EllesmereUI.CloseSyncPopup()
        if _syncPopup then _syncPopup:Hide() end
        if EllesmereUI._syncConfirmFrame then EllesmereUI._syncConfirmFrame:Hide() end
    end

    -- Seed-picker confirm for create/update: user picks which member's settings the
    -- group starts from; after that first equalization the group is a mirror.
    function EllesmereUI._ShowSyncSeedConfirm(opts)
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local PP = EllesmereUI.PanelPP or EllesmereUI.PP
        local W, PAD = 360, 18

        if not EllesmereUI._syncConfirmFrame then
            local nf = CreateFrame("Frame", nil, UIParent)
            nf:SetFrameStrata("FULLSCREEN_DIALOG")
            -- Below 200: the shared dropdown menu (hardcoded level 200) must render above
            nf:SetFrameLevel(150)
            nf:EnableMouse(true)
            local bg = nf:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(15/255, 17/255, 22/255, 1)
            nf._bg = bg
            -- Fullscreen dimmer: darkens and click-blocks everything behind
            local dim = CreateFrame("Frame", nil, UIParent)
            dim:SetFrameStrata("FULLSCREEN_DIALOG")
            dim:SetFrameLevel(140)
            dim:SetAllPoints(UIParent)
            dim:EnableMouse(true)
            dim:Hide()
            local dimTex = dim:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.55)
            nf._dimmer = dim
            nf:SetScript("OnHide", function(self) self._dimmer:Hide() end)
            EllesmereUI._syncConfirmFrame = nf
        end
        local f = EllesmereUI._syncConfirmFrame

        -- Clean old children/regions (recycled frame)
        for _, c in ipairs({f:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        for _, r in ipairs({f:GetRegions()}) do
            if r ~= f._bg then r:Hide(); r:SetParent(nil) end
        end

        local function MakeFont(parent, size, r, g, b, a)
            local fs = parent:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, true) end
            fs:SetFont(fontPath, size, "")
            fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            return fs
        end

        if PP then EllesmereUI.MakeBorder(f, 1, 1, 1, 0.15, PP) end
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)

        local cy = -PAD

        local title = MakeFont(f, 14, 1, 1, 1, 0.9)
        title:SetPoint("TOP", f, "TOP", 0, cy)
        title:SetText(EllesmereUI.L(opts.hadGroup and "Update Sync Group" or "Create Sync Group"))
        cy = cy - 22 - 8

        local msg = MakeFont(f, 11, 1, 1, 1, 0.6)
        msg:SetPoint("TOP", f, "TOP", 0, cy)
        msg:SetWidth(W - PAD * 2)
        msg:SetJustifyH("CENTER")
        msg:SetText(EllesmereUI.Lf("All selected profiles will keep their %1$s settings in sync: changes made on any of them carry over to the others. Choose which profile's settings the group starts from.", EllesmereUI.L(opts.displayName)))
        cy = cy - (msg:GetStringHeight() or 42) - 14

        local ddLabel = MakeFont(f, 11, 1, 1, 1, 0.5)
        ddLabel:SetPoint("TOP", f, "TOP", 0, cy)
        ddLabel:SetText(EllesmereUI.L("Sync settings from:"))
        cy = cy - 16 - 6

        local seedChoice = opts.defaultSeed
        local ddValues = { _noLoc = true }  -- profile names: never translate
        for _, name in ipairs(opts.memberOrder) do ddValues[name] = name end
        local DD_W = 190
        local DD_SCALE = 0.85
        local ddVisW = math.floor(DD_W * DD_SCALE + 0.5)
        local ddVisH = math.floor(30 * DD_SCALE + 0.5)
        local ddHolder = CreateFrame("Frame", nil, f)
        ddHolder:SetSize(ddVisW, ddVisH)
        ddHolder:SetPoint("TOP", f, "TOP", 0, cy)
        ddHolder:SetFrameLevel(f:GetFrameLevel() + 1)
        local ddBtn = EllesmereUI.BuildDropdownControl(ddHolder, DD_W, ddHolder:GetFrameLevel() + 1,
            ddValues, opts.memberOrder,
            function() return seedChoice end,
            function(v) seedChoice = v end)
        ddBtn:SetScale(DD_SCALE)
        ddBtn:SetPoint("TOPLEFT", ddHolder, "TOPLEFT", 0, 0)
        -- Menu is created lazily at UIParent scale; match it to the scaled button once it exists
        ddBtn:HookScript("OnClick", function(self)
            if self._ddMenu and self._ddMenu:GetScale() ~= DD_SCALE then
                self._ddMenu:SetScale(DD_SCALE)
            end
        end)
        cy = cy - ddVisH - 14

        if opts.hasWarning then
            local warn = MakeFont(f, 10, 0.92, 0.3, 0.3, 1)
            warn:SetPoint("TOP", f, "TOP", 0, cy)
            warn:SetWidth(W - PAD * 2)
            warn:SetJustifyH("CENTER")
            warn:SetText(EllesmereUI.L("Position and size settings are not synced and keep each profile's own values."))
            cy = cy - (warn:GetStringHeight() or 26) - 14
        end

        local function MakeBtn(label, r, g, b, a, hr, hg, hb)
            local btn = CreateFrame("Button", nil, f)
            btn:SetSize(120, 26)
            btn:SetFrameLevel(f:GetFrameLevel() + 1)
            local bgT = btn:CreateTexture(nil, "BACKGROUND")
            bgT:SetAllPoints(); bgT:SetColorTexture(r, g, b, a)
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, false) end
            lbl:SetFont(fontPath, 10, "")
            lbl:SetTextColor(1, 1, 1, 1); lbl:SetPoint("CENTER"); lbl:SetText(label)
            btn:SetScript("OnEnter", function() bgT:SetColorTexture(hr, hg, hb, 1) end)
            btn:SetScript("OnLeave", function() bgT:SetColorTexture(r, g, b, a) end)
            return btn
        end

        local cancelBtn = MakeBtn(EllesmereUI.L("Cancel"), 0.18, 0.19, 0.22, 0.9, 0.25, 0.26, 0.3)
        cancelBtn:SetPoint("TOPRIGHT", f, "TOP", -6, cy)
        local confirmBtn = MakeBtn(EllesmereUI.L("Sync"), 0.05, 0.52, 0.39, 0.8, 0.07, 0.62, 0.49)
        confirmBtn:SetPoint("TOPLEFT", f, "TOP", 6, cy)
        cy = cy - 26

        f:SetSize(W, -cy + PAD)

        confirmBtn:SetScript("OnClick", function()
            f:Hide()
            if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
            EllesmereUIDB.syncedModules[opts.folder] = opts.targets
            if seedChoice then
                EllesmereUI.SyncModuleFromProfile(opts.folder, seedChoice, opts.targets)
            end
            if opts.onDone then opts.onDone() end
        end)
        cancelBtn:SetScript("OnClick", function()
            f:Hide()
            if opts.onCancel then opts.onCancel() end
        end)

        f._dimmer:Show()
        f:Show()
    end

    function EllesmereUI.OpenSyncPopup(folder, displayName, anchorBtn)
        if EllesmereUI._syncConfirmFrame then EllesmereUI._syncConfirmFrame:Hide() end
        -- Toggle off if already open for this module
        if _syncPopup and _syncPopup:IsShown() and _syncPopup._folder == folder then
            _syncPopup:Hide()
            return
        end

        if not EllesmereUIDB or not EllesmereUIDB.profiles then return end
        local active = EllesmereUIDB.activeProfile or "Default"
        local profileOrder = EllesmereUIDB.profileOrder or {}

        -- Full profile list, profileOrder first then stragglers (active included: groups are explicit membership)
        local allProfiles = {}
        for _, name in ipairs(profileOrder) do
            if EllesmereUIDB.profiles[name] then
                allProfiles[#allProfiles + 1] = name
            end
        end
        for name in pairs(EllesmereUIDB.profiles) do
            local found = false
            for _, n in ipairs(allProfiles) do if n == name then found = true; break end end
            if not found then allProfiles[#allProfiles + 1] = name end
        end

        if #allProfiles <= 1 then
            if EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(anchorBtn, "No other profiles to sync to")
                C_Timer.After(1.5, function() EllesmereUI.HideWidgetTooltip() end)
            end
            return
        end

        local MEDIA_PATH = "Interface\\AddOns\\EllesmereUI\\media\\"
        local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local accentColor = EllesmereUI.ACCENT_COLOR or EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        local PP = EllesmereUI.PanelPP or EllesmereUI.PP

        local POPUP_W = 300
        local PAD = 16
        local ROW_H = 30
        local ROW_GAP = 2
        local HEADER_H = 26
        local WARN_MODULES = {
            EllesmereUIActionBars = true,
            EllesmereUIUnitFrames = true,
            EllesmereUICooldownManager = true,
            EllesmereUIResourceBars = true,
            EllesmereUIMythicTimer = true,
            EllesmereUIRaidFrames = true,
        }
        local hasWarning = WARN_MODULES[folder]
        local SUBTITLE_H = 30
        local popupH = PAD + HEADER_H + 7 + SUBTITLE_H + 14
            + #allProfiles * (ROW_H + ROW_GAP) - ROW_GAP + 16 + 30 + PAD

        if not _syncPopup then
            _syncPopup = CreateFrame("Frame", nil, UIParent)
            _syncPopup:SetFrameStrata("FULLSCREEN_DIALOG")
            _syncPopup:SetFrameLevel(200)
            _syncPopup:EnableMouse(true)
            local bg = _syncPopup:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(); bg:SetColorTexture(15/255, 17/255, 22/255, 1)
            _syncPopup._bg = bg
        end
        local popup = _syncPopup
        popup._folder = folder
        popup:SetFrameLevel(200)

        -- Clean old children
        for _, c in ipairs({popup:GetChildren()}) do c:Hide(); c:SetParent(nil) end
        for _, r in ipairs({popup:GetRegions()}) do
            if r ~= popup._bg then r:Hide(); r:SetParent(nil) end
        end

        popup:SetSize(POPUP_W, popupH)
        if PP then
            EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, PP)
        end

        -- Position: flush right of sidebar, centered on the sync icon, clamped
        local sidebar = EllesmereUI._sidebar
        local root = EllesmereUI._mainFrame
        if sidebar and anchorBtn then
            local btnMidY = select(2, anchorBtn:GetCenter()) or 0
            local sidebarMidY = select(2, sidebar:GetCenter()) or 0
            local offsetY = btnMidY - sidebarMidY
            -- Clamp to EUI window bottom
            if root then
                local rootBot = root:GetBottom() or 0
                local popupBot = btnMidY - popupH / 2
                if popupBot < rootBot then offsetY = offsetY + (rootBot - popupBot) end
            end
            popup:ClearAllPoints()
            popup:SetPoint("LEFT", sidebar, "RIGHT", 0, offsetY)
        else
            popup:ClearAllPoints()
            popup:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end

        local function MakeFont(parent, size, r, g, b, a)
            local fs = parent:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, true) end
            fs:SetFont(fontPath, size, "")
            fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            return fs
        end

        local cy = -PAD

        -- Header: sync icon (left), title (centered), close X (right)
        local iconTex = popup:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(19, 19)
        iconTex:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD - 1, cy + 1)
        iconTex:SetTexture(MEDIA_PATH .. "icons\\linked.png")
        -- Accent when this module has an active sync group, gray otherwise
        if EllesmereUI.IsModuleSynced(folder) then
            iconTex:SetVertexColor(accentColor.r, accentColor.g, accentColor.b, 1)
        else
            iconTex:SetVertexColor(0.55, 0.55, 0.55, 1)
        end

        local title = MakeFont(popup, 14, 1, 1, 1, 0.9)
        title:SetPoint("TOP", popup, "TOP", 0, cy - 1)
        title:SetText(EllesmereUI.Lf("%1$s Sync", EllesmereUI.L(displayName)))
        cy = cy - HEADER_H - 7

        local subtitle = MakeFont(popup, 10, 1, 1, 1, 0.45)
        subtitle:SetPoint("TOP", popup, "TOP", 0, cy)
        subtitle:SetWidth(POPUP_W - PAD * 2)
        subtitle:SetJustifyH("CENTER")
        subtitle:SetText(EllesmereUI.L("Syncing allows you to auto update all profiles whenever you change settings. This can be enabled per module."))
        cy = cy - SUBTITLE_H - 14

        -- Toggle rows for every profile (the active one included)
        local currentSynced = EllesmereUI.GetSyncedProfiles(folder)
        local toggleState = {}
        local hadGroup = next(currentSynced) ~= nil
        local refreshSyncBtnLabel  -- defined with the button below

        local accentHex = string.format("%02x%02x%02x",
            math.floor(accentColor.r * 255 + 0.5),
            math.floor(accentColor.g * 255 + 0.5),
            math.floor(accentColor.b * 255 + 0.5))

        local BuildToggleControl = EllesmereUI.BuildToggleControl
        for _, profName in ipairs(allProfiles) do
            -- Card-style row: label left, toggle right, whole row clickable
            local row = CreateFrame("Button", nil, popup)
            row:SetSize(POPUP_W - PAD * 2, ROW_H)
            row:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, cy)
            row:SetFrameLevel(popup:GetFrameLevel() + 1)
            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetColorTexture(1, 1, 1, 0.05)

            local isSynced = currentSynced[profName] == true
            toggleState[profName] = isSynced

            local tg, _, tgSnap = BuildToggleControl(row, row:GetFrameLevel() + 1,
                function() return toggleState[profName] end,
                function(v)
                    toggleState[profName] = v
                    if refreshSyncBtnLabel then refreshSyncBtnLabel() end
                end,
                { sizeRatio = 0.75 })
            tg:SetPoint("RIGHT", row, "RIGHT", -10, 0)

            row:SetScript("OnClick", function()
                toggleState[profName] = not toggleState[profName]
                tgSnap(toggleState[profName])
                if refreshSyncBtnLabel then refreshSyncBtnLabel() end
            end)
            row:SetScript("OnEnter", function() rowBg:SetColorTexture(1, 1, 1, 0.08) end)
            row:SetScript("OnLeave", function() rowBg:SetColorTexture(1, 1, 1, 0.05) end)
            -- Toggle hover fires the row's OnLeave (child frame); keep the card lit
            tg:HookScript("OnEnter", function() rowBg:SetColorTexture(1, 1, 1, 0.08) end)
            tg:HookScript("OnLeave", function() rowBg:SetColorTexture(1, 1, 1, 0.05) end)

            local lblText = MakeFont(row, 12, 1, 1, 1, 0.85)
            lblText:SetPoint("LEFT", row, "LEFT", 10, 0)
            if profName == active then
                lblText:SetText(profName .. " |cff" .. accentHex .. "(active)|r")
            else
                lblText:SetText(profName)
            end

            cy = cy - ROW_H - ROW_GAP
        end

        cy = cy - (16 - ROW_GAP)

        -- Action button: full-width accent outline; label tracks the toggle state
        local syncBtn = CreateFrame("Button", nil, popup)
        syncBtn:SetSize(POPUP_W - PAD * 2, 30)
        syncBtn:SetPoint("TOP", popup, "TOP", 0, cy)
        syncBtn:SetFrameLevel(popup:GetFrameLevel() + 1)
        local sBg = syncBtn:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        local sBrd
        if PP then
            sBrd = EllesmereUI.MakeBorder(syncBtn, accentColor.r, accentColor.g, accentColor.b, 0.7, PP)
        end
        local sLbl = syncBtn:CreateFontString(nil, "OVERLAY")
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(sLbl, false) end
        sLbl:SetFont(fontPath, 11, "")
        sLbl:SetPoint("CENTER")

        -- Grayed out until the toggles actually differ from the saved group
        local function ApplyBtnState(dirty)
            syncBtn._dirty = dirty
            if dirty then
                sBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.08)
                if sBrd then sBrd:SetColor(accentColor.r, accentColor.g, accentColor.b, 0.7) end
                sLbl:SetTextColor(accentColor.r, accentColor.g, accentColor.b, 1)
            else
                sBg:SetColorTexture(1, 1, 1, 0.03)
                if sBrd then sBrd:SetColor(1, 1, 1, 0.15) end
                sLbl:SetTextColor(1, 1, 1, 0.35)
            end
        end
        syncBtn:SetScript("OnEnter", function()
            if not syncBtn._dirty then return end
            sBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.18)
        end)
        syncBtn:SetScript("OnLeave", function()
            ApplyBtnState(syncBtn._dirty)
        end)

        refreshSyncBtnLabel = function()
            local count = 0
            local dirty = false
            for profName, v in pairs(toggleState) do
                if v then count = count + 1 end
                if v ~= (currentSynced[profName] == true) then dirty = true end
            end
            if hadGroup and count == 0 then
                sLbl:SetText(EllesmereUI.L("Disband Sync Group"))
            elseif hadGroup then
                sLbl:SetText(EllesmereUI.L("Update Sync Group"))
            else
                sLbl:SetText(EllesmereUI.L("Create Sync Group"))
            end
            ApplyBtnState(dirty)
        end
        refreshSyncBtnLabel()

        local function RefreshSidebarSyncIcon()
            local sidebarBtns = EllesmereUI._sidebarButtons
            if sidebarBtns and sidebarBtns[folder] and sidebarBtns[folder]._syncBtn then
                local sb = sidebarBtns[folder]._syncBtn
                if sb._refreshAlpha then sb._refreshAlpha() end
            end
        end

        syncBtn:SetScript("OnClick", function()
            if not syncBtn._dirty then return end
            -- The group is exactly the toggled-on profiles
            local targets = {}
            local count = 0
            local anyNew = false
            for profName, checked in pairs(toggleState) do
                if checked then
                    targets[profName] = true
                    count = count + 1
                    if not currentSynced[profName] then anyNew = true end
                end
            end

            if count == 0 then
                -- Disband (or nothing was ever configured)
                if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
                EllesmereUIDB.syncedModules[folder] = {}
                popup:Hide()
                RefreshSidebarSyncIcon()
                return
            end

            if count == 1 then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(syncBtn, "A sync group needs at least two profiles")
                    C_Timer.After(1.5, function() EllesmereUI.HideWidgetTooltip() end)
                end
                return
            end

            if not anyNew then
                -- Pure removal / no change: nothing overwritten, save without confirmation
                if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
                EllesmereUIDB.syncedModules[folder] = targets
                popup:Hide()
                RefreshSidebarSyncIcon()
                return
            end

            -- New members joining: confirm with a seed picker; default = an existing member
            -- on update (newcomers adopt group settings), active on create.
            local memberOrder = {}
            for _, name in ipairs(allProfiles) do
                if targets[name] then memberOrder[#memberOrder + 1] = name end
            end
            local defaultSeed
            if hadGroup then
                for _, name in ipairs(memberOrder) do
                    if currentSynced[name] then defaultSeed = name; break end
                end
            end
            if not defaultSeed then
                defaultSeed = targets[active] and active or memberOrder[1]
            end

            popup:SetFrameLevel(90)
            popup:SetScript("OnUpdate", nil)
            EllesmereUI._ShowSyncSeedConfirm({
                folder = folder,
                displayName = displayName,
                targets = targets,
                memberOrder = memberOrder,
                defaultSeed = defaultSeed,
                hadGroup = hadGroup,
                hasWarning = hasWarning,
                active = active,
                onDone = function()
                    popup:Hide()
                    RefreshSidebarSyncIcon()
                end,
                onCancel = function()
                    popup:Hide()
                end,
            })
        end)

        -- Click-off to close (OnUpdate poll like CC popups)
        popup:SetScript("OnShow", function(self)
            self:SetScript("OnUpdate", function(self2)
                if IsMouseButtonDown("LeftButton") then
                    if not self2:IsMouseOver() and not (anchorBtn and anchorBtn:IsMouseOver()) then
                        self2:Hide()
                    end
                end
            end)
        end)
        popup:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        popup:Show()
    end
end

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

local mainFrame, bgFrame, clickArea, sidebar, contentFrame
local headerFrame, tabBar, scrollFrame, scrollChild, footerFrame, contentHeaderFrame
local sidebarButtons = {}
-- On EllesmereUI (not a local) to save a CreateMainFrame upvalue; used by CreateMainFrame, RefreshSidebarStates, _applySidebarSearch.
EllesmereUI._sidebarGroupButtons = {}
local activeModule, activePage
local _lastPagePerModule = {}
local modules = {}
EllesmereUI._modules = modules -- read-only alias so other files (e.g. global search) can iterate registered modules
local scrollTarget = 0
local isSmoothing = false
local smoothFrame
local UpdateScrollThumb
local suppressScrollRangeChanged = false
local lastHeaderPadded = false
local skipScrollChildReanchor = false

-- Widget refresh registry: a Refresh callback per widget so RefreshPage updates values in-place without rebuilding frames.
local _widgetRefreshList = {}
local function RegisterWidgetRefresh(fn)
    _widgetRefreshList[#_widgetRefreshList + 1] = fn
end
EllesmereUI.RegisterWidgetRefresh = RegisterWidgetRefresh
local function ClearWidgetRefreshList()
    for i = 1, #_widgetRefreshList do _widgetRefreshList[i] = nil end
end

-- Snapshot/restore the refresh registry around off-screen widget builds (search-index
-- pre-build) so an unviewed page never leaks refresh closures into the displayed list.
function EllesmereUI._SnapshotAndClearWidgetRefreshList()
    local snap = {}
    for i = 1, #_widgetRefreshList do snap[i] = _widgetRefreshList[i] end
    ClearWidgetRefreshList()
    return snap
end
function EllesmereUI._RestoreWidgetRefreshList(snap)
    ClearWidgetRefreshList()
    for i = 1, #snap do _widgetRefreshList[i] = snap[i] end
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
        n = _packIntoScratch(parent:GetRegions())
        for i = 1, n do
            if not (keepSet and keepSet[_hideAllScratch[i]]) then _hideAllScratch[i]:Hide() end
            _hideAllScratch[i] = nil
        end
        -- Also hide custom root frames parented to scrollFrame (bypass scroll child)
        if EllesmereUI._hideScrollFrameRoots then
            EllesmereUI._hideScrollFrameRoots()
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

    -- Unified border system (single BackdropTemplate frame)
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

-- Alternating row backgrounds, counted per parent so each section resets independently. In
-- a split column (parent._splitParent) the bg lives on splitParent so it spans full width, anchored to the widget frame's top/bottom edges.
local rowCounters = {}
local function RowBg(frame, parent)
    if not rowCounters[parent] then rowCounters[parent] = 0 end
    rowCounters[parent] = rowCounters[parent] + 1
    local alpha = (rowCounters[parent] % 2 == 0) and ROW_BG_EVEN or ROW_BG_ODD
    local splitParent = parent._splitParent
    local bgParent = splitParent or frame
    local bg = bgParent:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, alpha)
    -- Always panel context: PanelPP, resolved lazily (it is defined later in the file)
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
    "blinkii-diamonds", "kringel-window",
}
-- FRESH textures/names/order tables. includeExtras=true = full 19-key set; else core set
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
-- Blizzard reskin colors (tooltips, context menus, popups)
EllesmereUI.RESKIN = {
    BG_R = 0.067, BG_G = 0.067, BG_B = 0.067,
    TT_ALPHA   = 0.92,   -- tooltip background alpha
    CTX_ALPHA  = 0.95,   -- blizzard context menu background alpha
    QT_ALPHA   = 0.97,   -- quest tracker right-click menu alpha
    BRD_ALPHA  = 0.18,   -- border alpha (white)
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
EllesmereUI.DUAL_ITEM_W  = DUAL_ITEM_W
EllesmereUI.DUAL_GAP     = DUAL_GAP
EllesmereUI.TRIPLE_ITEM_W = TRIPLE_ITEM_W
EllesmereUI.TRIPLE_GAP    = TRIPLE_GAP

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

        -- Item-level text color: custom override > upgrade-track hue > item rarity >
        -- white. Shared by character sheet, inspect sheet and equipment flyout.
        function EllesmereUI.GetItemLevelColor(itemLink, itemQuality)
            if EllesmereUIDB and EllesmereUIDB.charSheetItemLevelUseColor
                and EllesmereUIDB.charSheetItemLevelColor then
                return EllesmereUIDB.charSheetItemLevelColor
            end
            local upgradeText, upgradeColor = EllesmereUI.GetUpgradeTrack(itemLink)
            if upgradeText and upgradeText ~= "" and upgradeColor then
                return upgradeColor
            end
            if (not EllesmereUIDB or EllesmereUIDB.charSheetColorItemLevel ~= false) and itemQuality then
                local r, g, b = GetItemQualityColor(itemQuality)
                return { r = r, g = g, b = b }
            end
            return { r = 1, g = 1, b = 1 }
        end
    end
end

-------------------------------------------------------------------------------
--  Pixel Perfect System
--  Snaps UI elements to exact physical pixel boundaries regardless of UI scale, resolution, or element scale.
--    perfect = 768 / physicalScreenHeight   (1 pixel in WoW's 768-based coord)
--    mult    = perfect / UIParent:GetScale() (1 physical pixel at current scale)
--    Scale(x) snaps any value to the nearest mult boundary.
--  Usage: local PP = EllesmereUI.PP
--    PP.Size/Width/Height/Point, PP.SetInside/SetOutside(obj, anchor, x, y),
--    PP.DisablePixelSnap(texture), PP.Scale(x) -> snapped value
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
    -- perfect = 1 physical pixel in WoW's 768-based coords at scale 1.0. Keep the last known-
    -- good height when GetPhysicalScreenSize() reports 0/nil mid display-mode change (768/0 is infinite, and perfect divides every pixel snap -> NaN sizes suite-wide).
    function PP.RefreshPhysical()
        local pw, ph = GetPhysicalScreenSize()
        if ph and ph > 0 then
            PP.physicalWidth, PP.physicalHeight = pw, ph
        elseif not PP.physicalHeight then
            PP.physicalWidth, PP.physicalHeight = 1920, 1080
        end
        PP.perfect = 768 / PP.physicalHeight
    end
    PP.RefreshPhysical()

    -- mult = 1 physical pixel at current UIParent scale. When UIParent scale ==
    -- perfect, mult == 1 and every integer is pixel-perfect with no snapping.
    PP.mult = PP.perfect / (UIParent and UIParent:GetScale() or 1)

    --- Returns the ideal pixel-perfect scale, clamped to WoW's valid range.
    function PP.PixelBestSize()
        return max(0.4, min(PP.perfect, 1.15))
    end

    --- Recalculate mult after a scale or resolution change.
    function PP.UpdateMult()
        PP.RefreshPhysical()
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
        local currentScale = UIParent and UIParent:GetScale() or 1
        local scaleChanged = math.abs(currentScale - newScale) > 0.0001
        EllesmereUIDB.ppUIScale = newScale
        UIParent:SetScale(newScale)
        PP.UpdateMult()
        if scaleChanged then
            -- Re-snap all stored values to the new pixel grid
            if EllesmereUI.SnapProfilePositions then
                local activeName = EllesmereUIDB.activeProfile or "Default"
                local profData = EllesmereUIDB.profiles and EllesmereUIDB.profiles[activeName]
                if profData then EllesmereUI.SnapProfilePositions(profData) end
            end
            if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
            if _G._ERB_Apply then _G._ERB_Apply() end
            if _G._EAB_Apply then _G._EAB_Apply() end
            if _G._ECME_Apply then _G._ECME_Apply() end
            -- Re-sync width/height matches against the new grid. UIParent:SetScale()
            -- does NOT fire UI_SCALE_CHANGED (that event is CVar-tied), so no listener
            -- catches this path. Debounced: the Options slider calls this repeatedly
            -- while dragged and re-matching on every call never converges.
            if EllesmereUI.ApplyAllWidthHeightMatches then
                if PP._scaleMatchDebounce then PP._scaleMatchDebounce:Cancel() end
                PP._scaleMatchDebounce = C_Timer.NewTimer(0.3, function()
                    PP._scaleMatchDebounce = nil
                    EllesmereUI.ApplyAllWidthHeightMatches()
                end)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Scale(x) -- snap to the nearest physical-pixel boundary (sizes, positions, offsets).
    --  Divides x into whole-pixel chunks of `mult`, truncating toward zero (positive floors, negative ceils).
    ---------------------------------------------------------------------------
    function PP.Scale(x)
        if x == 0 then return 0 end
        local m = PP.mult
        if m == 1 then return x end
        local pixels = x / m
        -- Epsilon-guarded truncation: pixel-unit slider values sit exactly ON a grid boundary
        -- (px*mult); float dust can land a hair below, dropping a whole pixel at floor. 0.001 px is below any legitimate distance.
        pixels = x > 0 and math.floor(pixels + 0.001) or math.ceil(pixels - 0.001)
        return pixels * m
    end

    --- Snap a value to the nearest physical pixel at UIParent scale.
    --- Convenience wrapper for save paths that don't have a frame reference.
    function PP.Snap(x)
        if x == 0 then return 0 end
        local m = PP.mult
        local result = math.floor(x / m + 0.5) * m
        -- Clean float dust: within 0.001 of an integer, round to it (prevents drift)
        local rounded = math.floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then result = rounded end
        return result
    end

    --- Coord-space value -> physical pixel count (for display). Epsilon-guarded round (ties up):
    --- a value a hair off a half-pixel boundary (uiScale CVar != 768/screenHeight) must round the same every call/reload or coords flip by 1.
    function PP.ToPixels(coord)
        if coord == 0 then return 0 end
        return math.floor(coord / PP.mult + 0.5 + 0.001)
    end

    --- Convert a physical pixel count to a grid-aligned coord value (for storage).
    function PP.FromPixels(px)
        if px == 0 then return 0 end
        return px * PP.mult
    end

    ---------------------------------------------------------------------------
    --  SnapForES(x, effectiveScale) -- snap to a whole number of physical pixels at the
    --  given effective scale (border-system approach): onePixel = perfect / es; result =
    --  round(x / onePixel) * onePixel. Guarantees exactly N physical pixels, no sub-pixel drift between siblings.
    ---------------------------------------------------------------------------
    function PP.SnapForES(x, es)
        if x == 0 then return 0 end
        local onePixel = PP.perfect / es
        -- Epsilon-guarded round (ties up): inputs a hair below a half-pixel boundary
        -- (imperfect uiScale CVars) must snap the same way or frames shift 1px per reload.
        local physPixels = math.floor(x / onePixel + 0.5 + 0.001)
        local result = physPixels * onePixel
        local rounded = math.floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then result = rounded end
        return result
    end

    ---------------------------------------------------------------------------
    --  SnapCenterForDim(value, dim, effectiveScale) -- snap a CENTER coord so both edges land
    --  on physical pixels: EVEN dim -> whole-pixel center; ODD -> half-pixel center (integer +
    --  0.5) so center +/- dim/2 are both whole. THE snap for CENTER/CENTER-stored frames --
    --  plain SnapForES loses the +0.5 for odd dims and drifts 1px on save/exit, profile change, spec swap.
    ---------------------------------------------------------------------------
    function PP.SnapCenterForDim(value, dim, es)
        if value == nil then return value end
        es = es or (UIParent and UIParent:GetEffectiveScale() or 1)
        local onePixel = PP.perfect / es
        local valuePx = value / onePixel
        -- Clean float dust BEFORE any floor: N +/- 1e-9 must not flip which half/whole pixel it
        -- lands on between reloads (visible 1px jump); cleaned, an exact integer takes the +0.5 odd-branch side.
        local vClean = math.floor(valuePx + 0.5)
        if math.abs(valuePx - vClean) < 0.001 then valuePx = vClean end
        local result
        if dim and dim > 0 then
            local dimPx = math.floor(dim / onePixel + 0.5 + 0.001)
            if dimPx % 2 == 1 then
                -- Odd dim: snap center to nearest half-pixel (integer + 0.5)
                result = (math.floor(valuePx) + 0.5) * onePixel
                -- Clean floating point dust (half-pixel values)
                local rounded = math.floor(result) + 0.5
                if math.abs(result - rounded) < 0.001 then result = rounded end
                return result
            end
        end
        -- Even dimension (or unknown): snap center to nearest whole pixel.
        result = math.floor(valuePx + 0.5 + 0.001) * onePixel
        local rounded = math.floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then result = rounded end
        return result
    end

    ---------------------------------------------------------------------------
    --  CenterToPixels(center, dim, effectiveScale) -- inverse of SnapCenterForDim for LIVE-
    --  geometry readouts/deltas: live CENTER coord (UIParent units) -> stored-convention pixel
    --  value. Odd-dim centers rest on a half pixel (stored N means N+0.5), so subtract it before
    --  rounding, or ToPixels' tie-up maps N+0.5 to N+1 and the delta overshoots a whole pixel (even dims behave like ToPixels).
    ---------------------------------------------------------------------------
    function PP.CenterToPixels(center, dim, es)
        if center == nil then return nil end
        local v = center / PP.mult
        if dim and dim > 0 then
            es = es or (UIParent and UIParent:GetEffectiveScale() or 1)
            local onePixel = PP.perfect / es
            local dimPx = math.floor(dim / onePixel + 0.5 + 0.001)
            if dimPx % 2 == 1 then v = v - 0.5 end
        end
        return math.floor(v + 0.5 + 0.001)
    end

    ---------------------------------------------------------------------------
    --  Convenience wrappers -- pixel-snapped frame geometry
    ---------------------------------------------------------------------------
    function PP.Size(frame, w, h)
        frame:SetSize(PP.Scale(w), h and PP.Scale(h) or PP.Scale(w))
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
    --  DisablePixelSnap -- stop WoW rounding texture coords to the nearest pixel (blurs sub-pixel-sized elements).
    ---------------------------------------------------------------------------
    -- External weak-keyed set: NEVER write custom keys onto Blizzard's secure widget
    -- tables (taints them -> "secret value" errors).
    local _pixelSnapDisabled = setmetatable({}, { __mode = "k" })

    function PP.DisablePixelSnap(obj)
        if not obj then return end
        if issecretvalue and issecretvalue(obj) then return end
        if issecrettable and issecrettable(obj) then return end
        if _pixelSnapDisabled[obj] then return end
        if obj.IsForbidden and obj:IsForbidden() then return end

        -- Textures and FontStrings expose SetSnapToPixelGrid directly
        local target = obj
        if not obj.SetSnapToPixelGrid and obj.GetStatusBarTexture then
            -- StatusBars need their inner texture unsnapped instead
            target = obj:GetStatusBarTexture()
            if type(target) ~= "table" or not target.SetSnapToPixelGrid then
                _pixelSnapDisabled[obj] = true
                return
            end
        end

        if target.SetSnapToPixelGrid then
            target:SetSnapToPixelGrid(false)
            target:SetTexelSnappingBias(0)
        end
        _pixelSnapDisabled[obj] = true
    end

    ---------------------------------------------------------------------------
    --  Global Pixel Snap Prevention -- pixel-snap is a persistent property of each
    --  texture OBJECT: defaults ON at creation, when SetStatusBarTexture mints a new
    --  inner texture, or when foreign code calls SetSnapToPixelGrid(true). Image setters
    --  (SetTexture/SetColorTexture/SetAtlas) do NOT reset snap; tint/UV changes never do.
    --  So hook only: image setters (one-time first-touch disable), SetStatusBarTexture
    --  (fill swaps), and SetSnapToPixelGrid via WatchPixelSnap (re-catch Blizzard
    --  re-enabling). NOT hooked: SetVertexColor/SetTexCoord -- fire constantly (nameplate
    --  recolor churn) yet never blur a texture, so skipping them is the CPU win.
    --  PP.DisablePixelSnap caches into _pixelSnapDisabled (snap C-calls run once each).
    --  INVARIANT: cache keys on the StatusBar OBJECT, so re-calling SetStatusBarTexture
    --  on a cached bar does NOT re-disable snap on the new inner texture -- runtime
    --  bar-fill swaps MUST call PP.DisablePixelSnap on the new GetStatusBarTexture() themselves.
    ---------------------------------------------------------------------------
    local function WatchPixelSnap(frame, snap)
        if issecrettable and issecrettable(frame) then return end
        if (frame and not frame:IsForbidden()) and _pixelSnapDisabled[frame] and snap then
            _pixelSnapDisabled[frame] = nil
        end
    end

    local _hookedMetatables = {}
    local function HookPixelSnap(object)
        local mk = getmetatable(object)
        if not mk then return end
        mk = mk.__index
        if not mk or _hookedMetatables[mk] then return end

        if mk.SetSnapToPixelGrid or mk.SetStatusBarTexture or mk.SetColorTexture
           or mk.SetAtlas or mk.SetTexture then
            -- Rationale in the banner. CreateTexture is NOT hooked: hooksecurefunc
            -- passes the parent frame, not the new texture, so it would be a no-op.
            if mk.SetSnapToPixelGrid then hooksecurefunc(mk, "SetSnapToPixelGrid", WatchPixelSnap) end
            if mk.SetStatusBarTexture then hooksecurefunc(mk, "SetStatusBarTexture", PP.DisablePixelSnap) end
            if mk.SetColorTexture then hooksecurefunc(mk, "SetColorTexture", PP.DisablePixelSnap) end
            if mk.SetAtlas then hooksecurefunc(mk, "SetAtlas", PP.DisablePixelSnap) end
            if mk.SetTexture then hooksecurefunc(mk, "SetTexture", PP.DisablePixelSnap) end
            _hookedMetatables[mk] = true
        end
    end

    -- Hook all known widget types by creating one of each and hooking its metatable
    local hookFrame = CreateFrame("Frame")
    do
        -- Raw ORIGINAL image setters captured BEFORE HookPixelSnap wraps the Texture
        -- metatable. Pooled hot-path textures (nameplate aura slots) snap once at
        -- creation then use these to skip wrapper + guard + cache lookup per swap.
        -- Only legal when the texture had PP.DisablePixelSnap applied once and nothing
        -- can re-enable snap on it afterwards (our own pooled textures qualify).
        local mt = getmetatable(hookFrame:CreateTexture())
        if mt and mt.__index then
            PP.RawSetTexture = mt.__index.SetTexture
            PP.RawSetColorTexture = mt.__index.SetColorTexture
        end
    end
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
    --  UNIFIED BORDER SYSTEM -- the single border API for every EllesmereUI addon. 4 manual
    --  texture strips, each exactly borderSize*mult UI units thick (= borderSize physical
    --  pixels); no BackdropTemplate, no sub-pixel interp. Border data lives in the external
    --  weak-keyed _ppBorderData, NEVER on the frame (taints Blizzard's secure frame tables);
    --  entry = { container, borderSize, borderColor }, container holds _top/_bottom/_left/_right textures.
    --  API:
    --    PP.CreateBorder(frame, r, g, b, a, borderSize, drawLayer, subLevel)
    --    PP.SetBorderSize(frame, borderSize)   PP.SetBorderColor(frame, r, g, b, a)
    --    PP.UpdateBorder(frame, borderSize, r, g, b, a)
    --    PP.HideBorder(frame)   PP.ShowBorder(frame)
    local _ppBorderData = setmetatable({}, { __mode = "k" })
    ---------------------------------------------------------------------------

    local function SnapBorderTextures(container, frame, borderSize)
        if not container.GetEffectiveScale then return end
        local ok, es = pcall(container.GetEffectiveScale, container)
        if not ok or not es then return end
        -- Degenerate PARENT-scale guard, OPT-IN via container._scaleGuard (nameplates, see
        -- PP.CreateBorder): those containers are scale-DECOUPLED so their own es pins to 1
        -- and onePixel cannot explode, but the plate they anchor to hits near-zero scale during
        -- recycle/hide/PEW (SetScale(0.001)) -- snapping against that rect is churn, skip it (the skipped state is re-asserted via ArmPendingSnap below -- do NOT assume some later pass comes on its own, pooled plates get none); UIParent-based borders leave the flag unset.
        if container._scaleGuard then
            local pok, pes = pcall(frame.GetEffectiveScale, frame)
            if pok and pes and pes < 0.1 then
                -- Skipping the snap is right (the rect is collapsed, snapping against it is
                -- churn), but the CALLER'S INTENT MUST NOT BE LOST. A state change that lands
                -- in this window is otherwise dropped for good: the nameplate cast-bar wrap
                -- clears its hidden-bottom seam when the cast ends, which for a dying/despawning
                -- unit happens exactly while the plate is collapsed -- and since plates are
                -- POOLED and the paths that would re-snap on re-use are appearance-generation
                -- cached, the bottom strip then stays hidden for every unit that plate is
                -- recycled onto. Drop the geometry key so the next pass cannot match it as
                -- identical and skip, and arm a one-shot re-snap for when the container is
                -- visible again.
                container._snapEdge = nil
                PP.ArmPendingSnap(container, frame)
                return
            end
        end
        local onePixel = es > 0 and (PP.perfect / es) or PP.mult
        local bs = borderSize or 1
        local edgeSize = bs > 0 and math.max(onePixel, math.floor(bs + 0.5) * onePixel) or 0

        local t, b, l, r = container._top, container._bottom, container._left, container._right
        if not t then return end

        if edgeSize == 0 then
            t:Hide(); b:Hide(); l:Hide(); r:Hide()
            -- Clear the geometry key so the next non-zero pass cannot match a stale one and skip the Show().
            container._snapEdge = nil
            return
        end

        -- Edge suppression for joined bars: flags live on the container so they survive
        -- re-snaps (a one-shot :Hide() is clobbered by the next snap). Hidden top/bottom
        -- edges also drop the matching side-strip inset so stacked borders fuse with no
        -- corner notch.
        local topInset, botInset = -edgeSize, edgeSize
        if container._hideTop then topInset = 0 end
        if container._hideBottom then botInset = 0 end

        -- Geometry is idempotent (~30 frame API calls per invocation, per-aura-per-refresh):
        -- skip when the layout is identical. Compare POST-transform values (edgeSize + both
        -- insets), NEVER borderSize input -- an input-vs-applied guard can't match a non-trivial
        -- transform and re-fires forever. Scale flows through (es -> onePixel -> edgeSize), so an
        -- equal-edgeSize skip is correct (every SetPoint here is anchor-relative, insets-only).
        -- The colour block stays OUTSIDE this guard (textured path zeroes strip alpha; SetVertexColor
        -- restores it); side-strip hidden flags need their own key slots since a left/right-only
        -- flip at unchanged geometry moves no inset and would otherwise be skipped.
        local hideL = container._hideLeft or false
        local hideR = container._hideRight or false
        local geomSame = container._snapEdge == edgeSize
            and container._snapTop == topInset
            and container._snapBot == botInset
            and container._snapHideL == hideL
            and container._snapHideR == hideR
            and container._snapFrame == frame
        if not geomSame then
            container._snapEdge, container._snapTop = edgeSize, topInset
            container._snapBot, container._snapFrame = botInset, frame
            container._snapHideL, container._snapHideR = hideL, hideR

            if container._hideTop then
                t:Hide()
            else
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
                t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                t:SetHeight(edgeSize); t:Show()
            end
            if container._hideBottom then
                b:Hide()
            else
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
                b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                b:SetHeight(edgeSize); b:Show()
            end
            if container._hideLeft then
                l:Hide()
            else
                l:ClearAllPoints()
                l:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, topInset)
                l:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, botInset)
                l:SetWidth(edgeSize); l:Show()
            end
            if container._hideRight then
                r:Hide()
            else
                r:ClearAllPoints()
                r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, topInset)
                r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, botInset)
                r:SetWidth(edgeSize); r:Show()
            end
        end

        local bc = container._bdColor
        if bc then
            t:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
            b:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
            l:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
            r:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
        end
    end

    --  Deferred re-snap for a guarded container whose snap was swallowed at degenerate parent
    --  scale (rationale at the guard in SnapBorderTextures). OnShow is the trigger because it is
    --  exactly the moment the plate un-collapses, costs nothing while idle, and needs no ticker.
    --  Nothing else scripts OnShow on a border container, so SetScript is safe here; the handler
    --  is shared, NOT a per-container closure (these arm on pooled nameplate borders).
    --  Two further nets catch a container whose OnShow never fires: the cleared _snapEdge means
    --  no later snap can skip it as unchanged, and PP.ResnapAllBorders re-snaps it wholesale.
    function PP._pendingSnapOnShow(container)
        local frame = container._pendingSnap
        if not frame then
            container:SetScript("OnShow", nil)
            return
        end
        local pok, pes = pcall(frame.GetEffectiveScale, frame)
        -- Still collapsed (shown inside a hidden/zero-scale ancestor): stay armed for the next show.
        if not pok or not pes or pes < 0.1 then return end
        container._pendingSnap = nil
        container:SetScript("OnShow", nil)
        local bd = _ppBorderData[frame]
        SnapBorderTextures(container, frame, bd and bd.borderSize or 1)
    end

    function PP.ArmPendingSnap(container, frame)
        if container._pendingSnap then return end
        container._pendingSnap = frame
        container:SetScript("OnShow", PP._pendingSnapOnShow)
    end

    ---------------------------------------------------------------------------
    --  Border registry -- tracks all border containers for centralized re-snap
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
                local bd = _ppBorderData[f]
                local ok = pcall(SnapBorderTextures, c, f, bd and bd.borderSize or 1)
                if not ok then
                    -- Evict only on real failure (dead frame): while auras are secret,
                    -- rect reads in engine aura subtrees are denied but transient.
                    local AKR = EllesmereUI and EllesmereUI.AuraKit
                    if not (AKR and AKR.AurasRestricted and AKR.AurasRestricted()) then
                        entry.container = nil
                        entry.frame = nil
                    end
                end
            end
        end
    end

    --- Re-snap only borders whose parent frame descends from `root`. Tab switch uses
    --- this instead of resnapping 600+ borders when only ~30 on the page need it.
    function PP.ResnapBordersUnder(root)
        if not root then return PP.ResnapAllBorders() end
        local count = 0
        -- Shared method ref for the climb: engine aura buttons deny addon access while
        -- auras are secret. Under pcall a denied step is a chain dead-end = not under
        -- root, which is correct (aura subtrees are never inside the options panel).
        local GetParentFn = root.GetParent
        for i = 1, allBordersN do
            local entry = allBorders[i]
            local f = entry.frame
            if f and entry.container then
                -- Walk up the parent chain (max 10 levels to avoid infinite loops)
                local parent = f
                local found = false
                for _ = 1, 10 do
                    local ok, p = pcall(GetParentFn, parent)
                    if not ok or not p then break end
                    parent = p
                    if parent == root then found = true; break end
                end
                if found then
                    count = count + 1
                    local bd = _ppBorderData[f]
                    local ok = pcall(SnapBorderTextures, entry.container, f, bd and bd.borderSize or 1)
                    if not ok then
                        -- Same transient-vs-dead distinction as ResnapAllBorders.
                        local AKR = EllesmereUI and EllesmereUI.AuraKit
                        if not (AKR and AKR.AurasRestricted and AKR.AurasRestricted()) then
                            entry.container = nil
                            entry.frame = nil
                        end
                    end
                end
            end
        end
    end

    -- scaleGuard (opt-in, nameplate borders): marks a border whose PARENT has a DYNAMIC
    -- effective scale (Scale Target/Casting Nameplate ease plate:SetScale live, recycled
    -- plates snap back to 1, Blizzard rescales base plates). Two effects, flagged borders only:
    --  1. Container is scale-DECOUPLED (SetIgnoreParentScale(true) + SetScale 1): strips render
    --     in fixed scale-1 space while anchors track the plate's live rect, so thickness stays
    --     EXACTLY round(borderSize) physical pixels however the plate scales AFTER the snap.
    --     Otherwise thickness bakes in at snap-time scale and a later DOWN-scale (target lost,
    --     cast ended, mid-ease, recycled from an enlarged unit) leaves sub-1px strips that cover
    --     no pixel center at many sub-pixel positions -- border sides VANISH as the plate slides
    --     with the camera (DisablePixelSnap cannot fix this: it removes snap-to-0, not exact-geometry raster).
    --  2. SnapBorderTextures skips work while the PARENT's effective scale is degenerate (< 0.1,
    --     the SetScale(0.001) hide path). Every other caller leaves scaleGuard nil, unaffected.
    local function DecoupleBorderScale(container)
        if container._scaleDecoupled then return end
        if not container.SetIgnoreParentScale then return end
        container._scaleDecoupled = true
        container:SetIgnoreParentScale(true)
        container:SetScale(1)
    end

    function PP.CreateBorder(frame, r, g, b, a, borderSize, drawLayer, subLevel, scaleGuard)
        local bd = _ppBorderData[frame]
        if bd then
            -- A later call can opt an existing border into the guard. Decoupling changes
            -- the container's coord space, so re-snap now (stored sizes used the old one).
            if scaleGuard and not bd.container._scaleGuard then
                bd.container._scaleGuard = true
                DecoupleBorderScale(bd.container)
                SnapBorderTextures(bd.container, frame, bd.borderSize or 1)
            end
            return bd.container
        end
        r = r or 0; g = g or 0; b = b or 0; a = a or 1
        borderSize = borderSize or 1
        drawLayer = drawLayer or "OVERLAY"
        subLevel = subLevel or 0

        -- 4 strips instead of BackdropTemplate: NineSlice corner sub-frames render as black boxes on nameplates.
        local container = CreateFrame("Frame", nil, frame)
        container:SetAllPoints(frame)
        container:SetFrameLevel(frame:GetFrameLevel() + 1)

        local WHITE = "Interface\\Buttons\\WHITE8X8"
        local function MakeTex()
            local tx = container:CreateTexture(nil, drawLayer, nil, subLevel)
            tx:SetTexture(WHITE)
            -- No pixel-grid snapping: a 1px edge strip must never round to 0 and
            -- VANISH per-side at fractional scales/positions. Our textures, taint-safe.
            PP.DisablePixelSnap(tx)
            return tx
        end
        container._top    = MakeTex()
        container._bottom = MakeTex()
        container._left   = MakeTex()
        container._right  = MakeTex()

        container._bdColor = { r, g, b, a }
        container._scaleGuard = scaleGuard or nil
        if scaleGuard then DecoupleBorderScale(container) end
        bd = { container = container, borderSize = borderSize, borderColor = { r, g, b, a } }
        _ppBorderData[frame] = bd

        SnapBorderTextures(container, frame, borderSize)

        -- Re-snap for 2 frames to catch final effective scale after layout.
        local ticks = 0
        container:SetScript("OnUpdate", function(self)
            ticks = ticks + 1
            SnapBorderTextures(self, frame, bd.borderSize or 1)
            if ticks >= 2 then self:SetScript("OnUpdate", nil) end
        end)

        RegisterBorder(container, frame)

        return container
    end

    function PP.GetBorders(frame)
        local bd = _ppBorderData[frame]
        return bd and bd.container
    end

    function PP.SetBorderSize(frame, borderSize)
        local bd = _ppBorderData[frame]
        if not bd then return end
        borderSize = borderSize or 1
        SnapBorderTextures(bd.container, frame, borderSize)
        bd.borderSize = borderSize
    end

    function PP.SetBorderColor(frame, r, g, b, a)
        local bd = _ppBorderData[frame]
        if not bd then return end
        a = a or 1

        -- Mutated in place, never replaced: called per-aura-per-refresh, and a fresh {r,g,b,a}
        -- table per call was the addon's largest garbage source (1.2 MB/min). container._bdColor
        -- aliases this table, so writes keep both views in sync. SECRET color components
        -- (RaidFrames dispel colors in combat) can be WRITTEN to textures but never compared or
        -- cached (the compare errors on a secret, and caching one breaks the NEXT clean call's
        -- compare too); secrets skip the guard, leave the cache on the last CLEAN color, and mark dirty so the next clean color repaints.
        local col = bd.borderColor
        local secret = issecretvalue
            and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b) or issecretvalue(a))
        if secret then
            bd.colDirty = true
        elseif col then
            if not bd.colDirty
               and col[1] == r and col[2] == g and col[3] == b and col[4] == a then
                return   -- unchanged; the four texture writes below are redundant
            end
            bd.colDirty = nil
            col[1], col[2], col[3], col[4] = r, g, b, a
        else
            col = { r, g, b, a }
            bd.borderColor = col
        end
        if col then bd.container._bdColor = col end

        local c = bd.container
        if c._top then c._top:SetVertexColor(r, g, b, a) end
        if c._bottom then c._bottom:SetVertexColor(r, g, b, a) end
        if c._left then c._left:SetVertexColor(r, g, b, a) end
        if c._right then c._right:SetVertexColor(r, g, b, a) end
    end

    function PP.UpdateBorder(frame, borderSize, r, g, b, a)
        if r then PP.SetBorderColor(frame, r, g, b, a) end
        PP.SetBorderSize(frame, borderSize)
    end

    function PP.HideBorder(frame)
        local bd = _ppBorderData[frame]
        if bd then bd.container:Hide() end
    end

    function PP.ShowBorder(frame)
        local bd = _ppBorderData[frame]
        if bd then bd.container:Show() end
    end

    -- Variable-thickness border ring drawn from a single pre-shaped texture (natively
    -- 7px thick), scaled by (7 - rawBorderSize) and clipped by `mask`. Called with `:`
    -- so self.Point resolves to whichever PP module owns host's frame hierarchy
    -- (world PP vs PanelPP) -- calling with `.` shifts every argument left by one.
    function PP:ApplyMaskedShapeBorder(host, mask, texPath, rawBorderSize, r, g, b, a)
        if not host then return end
        rawBorderSize = rawBorderSize or 0
        if rawBorderSize <= 0 or not texPath then
            if host._shapeBorderShown then
                host._shapeBorderTex:Hide()
                host._shapeBorderShown = nil
            end
            return
        end
        r, g, b, a = r or 0, g or 0, b or 0, a or 1
        -- Every field guarded: callers invoke this on every restyle pass regardless
        -- of whether the border changed, and Remove/AddMaskTexture aren't cheap.
        if host._shapeBorderShown and host._sbTex == texPath and host._sbSize == rawBorderSize
            and host._sbMask == mask and host._sbR == r and host._sbG == g
            and host._sbB == b and host._sbA == a then
            return
        end
        if not host._shapeBorderTex then
            host._shapeBorderTex = host:CreateTexture(nil, "OVERLAY")
            local t = host._shapeBorderTex
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        end
        local tex = host._shapeBorderTex
        local bExp = 7 - math.min(rawBorderSize, 7)
        tex:ClearAllPoints()
        self.Point(tex, "TOPLEFT", host, "TOPLEFT", -bExp, bExp)
        self.Point(tex, "BOTTOMRIGHT", host, "BOTTOMRIGHT", bExp, -bExp)
        if mask then
            pcall(tex.RemoveMaskTexture, tex, mask)
            pcall(tex.AddMaskTexture, tex, mask)
        end
        tex:SetTexture(texPath)
        tex:SetVertexColor(r, g, b, a)
        tex:Show()
        host._sbTex, host._sbSize, host._sbMask, host._sbR, host._sbG, host._sbB, host._sbA =
            texPath, rawBorderSize, mask, r, g, b, a
        host._shapeBorderShown = true
    end

    -- Callers switching away from a shaped border (to the plain-line border, or off
    -- entirely) must hide _shapeBorderTex through this, not a raw :Hide() -- the guard
    -- above trusts _shapeBorderShown, so an external hide it doesn't know about leaves
    -- a later ApplyMaskedShapeBorder call with the exact same args wrongly skipping
    -- its own Show().
    function PP:HideMaskedShapeBorder(host)
        if host and host._shapeBorderShown then
            host._shapeBorderTex:Hide()
            host._shapeBorderShown = nil
        end
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
            -- Resolution changed -- recalculate perfect and re-apply scale
            PP.RefreshPhysical()
            -- Only auto-update if user explicitly opted into auto scale
            if EllesmereUIDB and EllesmereUIDB.ppUIScaleAuto == true then
                PP.SetUIScale(PP.PixelBestSize())
            else
                PP.UpdateMult()
            end
        else
            PP.UpdateMult()
        end
        PP.ResnapAllBorders()
        -- Re-sync panel scale after loading screens / resolution / UI scale changes
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
--  Panel Pixel Perfect (PanelPP) -- the options panel runs at effective scale = baseScale *
--  userScale. At userScale 1.0, 1 unit = 1 physical pixel (integer rounding suffices); otherwise PanelPP computes its own mult (1 physical pixel in panel units) and snaps to that grid.
-------------------------------------------------------------------------------
do
    local PanelPP = {}
    EllesmereUI.PanelPP = PanelPP

    local floor, type = math.floor, type

    -- mult = 1 physical pixel in panel units (1.0 at userScale 1.0, ~0.9901 at
    -- 1.01); recalculated by UpdateMult() when the panel scale changes.
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

    -- DisablePixelSnap is scale-independent -- just reuse PP's version
    PanelPP.DisablePixelSnap = PP.DisablePixelSnap

    -- Panel borders delegate to the unified PP border system
    PanelPP.CreateBorder  = PP.CreateBorder
    PanelPP.GetBorders    = PP.GetBorders
    PanelPP.SetBorderSize = PP.SetBorderSize
    PanelPP.SetBorderColor = PP.SetBorderColor
    PanelPP.UpdateBorder  = PP.UpdateBorder
    PanelPP.HideBorder    = PP.HideBorder
    PanelPP.ShowBorder    = PP.ShowBorder
    PanelPP.ApplyMaskedShapeBorder = PP.ApplyMaskedShapeBorder
    PanelPP.HideMaskedShapeBorder = PP.HideMaskedShapeBorder
end

-- File-level PanelPP reference for panel layout code outside the do block
local PanelPP = EllesmereUI.PanelPP

-------------------------------------------------------------------------------
--  BORDER TEXTURE SYSTEM -- extends PP borders with BackdropTemplate textured borders.
--  borderTexture = "solid" (default) uses the PP 4-strip system unchanged; any other
--  key creates a BackdropTemplate child with the resolved edge texture, hiding the strips.
--  API:
--    EllesmereUI.GetBorderTextureList()       -- sorted {key,name} array
--    EllesmereUI.GetBorderTextureDropdown()    -- values + order for W:DualRow
--    EllesmereUI.ResolveBorderTexture(key)     -- key -> edgeFile path (nil for solid)
--    EllesmereUI.ApplyBorderStyle(frame, sz, r,g,b,a, textureKey)
--    EllesmereUI.SetBorderStyleColor(frame, r,g,b,a)
-------------------------------------------------------------------------------
do
    local _bdBorderData = setmetatable({}, { __mode = "k" })
    EllesmereUI._bdBorderData = _bdBorderData

    --- Returns usable, width, height.
    --- usable = false means EVERY widget call on this frame raises from our (always tainted)
    --- code: Enum.ForbiddenAspect.UntrustedLayoutScriptExecution propagates to a forbidden
    --- frame's children AND to anything ANCHORED to it, so a border we hung off a Blizzard
    --- frame inherits it the moment that frame anchors to a forbidden one (Blizzard UI
    --- widgets do exactly that to the tooltip they own, on hover). The size READ raises
    --- too, so pcall is the only way to ask.
    --- usable with no width = the size is SECRET: the frame is fine to touch, only the
    --- backdrop's texcoord arithmetic is not (map-pin tooltips, menus with secret text, and
    --- every frame anchored to secret aura geometry, which uses the solid path on purpose).
    local function ReadBorderSize(frame)
        local ok, w, h = pcall(frame.GetSize, frame)
        if not ok then return false end
        if issecretvalue and (issecretvalue(w) or issecretvalue(h)) then return true end
        return true, w, h
    end

    -- Per-addon border defaults registry, keyed by texture key. Each texture entry:
    --   defaultSize: size key auto-set when this texture is selected
    --   sizes: keyed by size key (addon-specific), each with offsetX, offsetY,
    --     shiftX, shiftY (all default to 0 if omitted)
    -- Register: EllesmereUI.RegisterBorderDefaults(addonKey, table);
    -- read: EllesmereUI.GetBorderDefaults(addonKey, textureKey, sizeKey).
    local _borderDefaults = {}

    function EllesmereUI.RegisterBorderDefaults(addonKey, defaults)
        _borderDefaults[addonKey] = defaults
    end

    --- Get per-addon border defaults for a texture+size combo.
    --- Returns offsetX, offsetY, shiftX, shiftY (all 0 if not registered).
    function EllesmereUI.GetBorderDefaults(addonKey, textureKey, sizeKey)
        if textureKey == "shadow" then textureKey = "glow" end  -- Shadow shares Glow's defaults
        local addon = _borderDefaults[addonKey]
        if not addon then return 0, 0, 0, 0 end
        local tex = addon[textureKey]
        if not tex or not tex.sizes then return 0, 0, 0, 0 end
        local s = tex.sizes[sizeKey]
        if not s then return 0, 0, 0, 0 end
        return s.offsetX or 0, s.offsetY or 0, s.shiftX or 0, s.shiftY or 0
    end

    --- Get the default size key for a texture in a specific addon.
    --- Returns nil if not registered (caller keeps current size).
    function EllesmereUI.GetBorderDefaultSize(addonKey, textureKey)
        if textureKey == "shadow" then textureKey = "glow" end  -- Shadow shares Glow's defaults
        local addon = _borderDefaults[addonKey]
        local tex = addon and addon[textureKey]
        if tex and tex.defaultSize then return tex.defaultSize end
        -- Any SharedMedia border ("sm:<name>") defaults to size 1 unless registered above
        -- (shared, applies to every consumer). Called only from a dropdown setValue, never load/apply, so stored sizes stay untouched until picked.
        if type(textureKey) == "string" and textureKey:sub(1, 3) == "sm:" then return 1 end
        return nil
    end

    -- Built-in border textures (always available, no SharedMedia). defaultOffset = outward extension from the content edge, tuned per-texture (internal padding differs).
    EllesmereUI._builtinBorderTextures = {
        { key = "solid",   name = "Solid" },
        { key = "glow",    name = "Glow",            path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\glow-border",  defaultOffset = 0, defaultOffsetY = 0, scaleOffset = true, defaultThickness = "normal" },
        -- Shadow = the Glow texture drawn behind the frame in black; aliases to glow in default lookups, "behind + black" applied by GetBorderStyleSelectDefaults.
        { key = "shadow",  name = "Shadow",          path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\glow-border",  defaultOffset = 0, defaultOffsetY = 0, scaleOffset = true, defaultThickness = "normal" },
        { key = "blizz",   name = "Blizzard",        path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\blizz-border", defaultOffset = 3, defaultOffsetY = 2, scaleOffset = true, defaultThickness = "heavy" },
        { key = "lightspark", name = "Lightspark Border", path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\lightspark-border", defaultOffset = 0, defaultOffsetY = 0, scaleOffset = true, defaultThickness = "normal" },
        { key = "dialog",  name = "Blizzard Dialog",  path = "Interface\\DialogFrame\\UI-DialogBox-Border",                 defaultOffset = 4, defaultOffsetY = 4, defaultThickness = "normal" },
    }
    local DEFAULT_LSM_OFFSET = 0

    --- Build a sorted list of border texture entries for dropdown widgets.
    function EllesmereUI.GetBorderTextureList()
        local list = {}
        local seen = {}
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            list[#list + 1] = { key = entry.key, name = entry.name }
            seen[entry.name] = true
        end
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local smBorders = LSM:HashTable("border")
            if smBorders then
                local LSM_BLACKLIST = {
                    ["Blizzard Tooltip"] = true,
                    ["Blizzard Chat Bubble"] = true,
                    ["Blizzard Dialog Gold"] = true,
                    ["Blizzard Party"] = true,
                    ["None"] = true,
                }
                local sorted = {}
                for name in pairs(smBorders) do
                    if not seen[name] and not LSM_BLACKLIST[name] then
                        sorted[#sorted + 1] = name
                    end
                end
                table.sort(sorted)
                local LSM_RENAME = {
                    ["Blizzard Achievement Wood"] = "Blizzard Wood",
                }
                for _, name in ipairs(sorted) do
                    list[#list + 1] = { key = "sm:" .. name, name = LSM_RENAME[name] or name }
                end
            end
        end
        return list
    end

    --- Build dropdown values/order tables from the texture list.
    function EllesmereUI.GetBorderTextureDropdown()
        local texList = EllesmereUI.GetBorderTextureList()
        local values, order = {}, {}
        for _, entry in ipairs(texList) do
            values[entry.key] = entry.name
            order[#order + 1] = entry.key
        end
        return values, order
    end

    -- Per-LSM-texture defaults (keyed by original LSM name)
    local LSM_DEFAULT_OFFSETS = {
        ["Blizzard Achievement Wood"] = { x = 1, y = 1, thickness = "thin" },
    }

    --- Get the default border thickness for a texture key.
    function EllesmereUI.GetBorderTextureDefaultThickness(key)
        if not key or key == "" or key == "solid" then return nil end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.defaultThickness end
        end
        local smName = key:match("^sm:(.+)")
        if smName and LSM_DEFAULT_OFFSETS[smName] then return LSM_DEFAULT_OFFSETS[smName].thickness end
        return nil
    end

    --- Get the default X offset for a border texture key.
    function EllesmereUI.GetBorderTextureDefaultOffset(key)
        if not key or key == "" or key == "solid" then return 0 end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.defaultOffset or DEFAULT_LSM_OFFSET end
        end
        local smName = key:match("^sm:(.+)")
        if smName and LSM_DEFAULT_OFFSETS[smName] then return LSM_DEFAULT_OFFSETS[smName].x end
        return DEFAULT_LSM_OFFSET
    end

    --- Get the default Y offset for a border texture key.
    function EllesmereUI.GetBorderTextureDefaultOffsetY(key)
        if not key or key == "" or key == "solid" then return 0 end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.defaultOffsetY or entry.defaultOffset or DEFAULT_LSM_OFFSET end
        end
        local smName = key:match("^sm:(.+)")
        if smName and LSM_DEFAULT_OFFSETS[smName] then return LSM_DEFAULT_OFFSETS[smName].y end
        return DEFAULT_LSM_OFFSET
    end

    -- Textured border edgeSize per size step (1-4).
    local EDGE_MAP = { 12, 16, 24, 32 }

    --- Check if a border texture uses scaled offset (edgeSize/2 base).
    function EllesmereUI.BorderTextureUsesScaleOffset(key)
        if not key or key == "" or key == "solid" then return false end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.scaleOffset == true end
        end
        return false
    end

    --- Border color + layer defaults to apply when a border style is selected (Shadow is the
    --- only style rendered behind both its icon and Unit Frame). Returns (colorTable, behindBool, behindUnitFrameBool).
    function EllesmereUI.GetBorderStyleSelectDefaults(textureKey)
        if textureKey == "shadow" then return { r = 0, g = 0, b = 0 }, true, true end
        if not textureKey or textureKey == "" or textureKey == "solid" then
            return { r = 0, g = 0, b = 0 }, false, false
        end
        return { r = 1, g = 1, b = 1 }, false, false
    end

    --- Resolve a border texture key to a file path; nil for "solid" (use PP system).
    function EllesmereUI.ResolveBorderTexture(key)
        if not key or key == "" or key == "solid" then return nil end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.path end
        end
        local smName = key:match("^sm:(.+)")
        if smName then
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM then
                local path = LSM:Fetch("border", smName)
                if path and path ~= "" then return path end
            end
        end
        if key:find("\\") or key:find("/") then return key end
        return nil
    end

    --- Apply border style to a border frame, managing PP vs BackdropTemplate.
    --- borderFrame must be a frame we own (not a Blizzard frame).
    --- size: border thickness in PP pixels (solid) or mapped to edgeSize (textured).
    --- textureKey: "solid"/nil for PP, anything else for BackdropTemplate.
    --- offsetOverride/offsetYOverride: optional user override (nil = use per-addon or global default).
    --- shiftX/shiftY: optional user override (nil = use per-addon default or 0).
    --- addonKey/sizeKey: optional per-addon registry lookup key pair for defaults.
    --- normalizeScale: opt-in, textured only. Cancels the frame's scale chain below UIParent
    ---   so the border matches an unscaled frame's. Pass ONLY where that scale is an
    ---   implementation detail the caller already cancels elsewhere (CDM cancels Blizzard's
    ---   per-icon scale for icon size, iS = 1/iconScale, but not its border). NEVER where the
    ---   scale is user intent (nameplate target/cast scale, buff-bar position scale): those
    ---   borders scale with the frame, and ratio is sampled once at style time so a later change would bake in a transient value.
    function EllesmereUI.ApplyBorderStyle(borderFrame, size, r, g, b, a, textureKey, offsetOverride, offsetYOverride, shiftX, shiftY, addonKey, sizeKey, normalizeScale)
        local PP = EllesmereUI.PP
        if not PP or not borderFrame then return end
        a = a or 1
        -- Probe before the first widget call: a restyle can land while the owner is anchored
        -- to a forbidden frame (tooltips on UI-widget hover), and then anchoring, frame level
        -- and color would each raise in turn. Skipping leaves the last-good border; the next apply, off that anchor, restyles normally.
        if not ReadBorderSize(borderFrame) then return end

        local isSolid = not textureKey or textureKey == "" or textureKey == "solid"

        if isSolid then
            local bdFrame = _bdBorderData[borderFrame]
            if bdFrame then bdFrame:Hide() end
            -- PP system
            if size > 0 then
                if PP.GetBorders(borderFrame) then
                    PP.UpdateBorder(borderFrame, size, r, g, b, a)
                    PP.ShowBorder(borderFrame)
                    -- No SetAlpha "restore" after textured-mode zeroing: on Textures SetAlpha
                    -- writes the SAME state as SetVertexColor's 4th arg, so the color write above
                    -- restores it; a hardcoded SetAlpha(1) would stomp every fractional border alpha on re-apply.
                else
                    PP.CreateBorder(borderFrame, r, g, b, a, size, "OVERLAY", 7)
                end
                borderFrame:Show()
            else
                if PP.GetBorders(borderFrame) then PP.HideBorder(borderFrame) end
                borderFrame:Hide()
            end
        else
            -- Textured border via BackdropTemplate
            local texPath = EllesmereUI.ResolveBorderTexture(textureKey)
            if not texPath or size <= 0 then
                local bdFrame = _bdBorderData[borderFrame]
                if bdFrame then bdFrame:Hide() end
                if PP.GetBorders(borderFrame) then PP.HideBorder(borderFrame) end
                if size <= 0 then borderFrame:Hide() end
                return
            end
            -- Hide PP borders and zero their alpha so they can't flash
            if PP.GetBorders(borderFrame) then
                PP.HideBorder(borderFrame)
                local ppC = PP.GetBorders(borderFrame)
                if ppC then
                    if ppC._top then ppC._top:SetAlpha(0) end
                    if ppC._bottom then ppC._bottom:SetAlpha(0) end
                    if ppC._left then ppC._left:SetAlpha(0) end
                    if ppC._right then ppC._right:SetAlpha(0) end
                end
            end
            local bdFrame = _bdBorderData[borderFrame]
            if not bdFrame then
                bdFrame = CreateFrame("Frame", nil, borderFrame, "BackdropTemplate")
                bdFrame:EnableMouse(false)
                -- Addon-born frame: its scripts always run tainted. When the owner rides a
                -- Blizzard frame sized from secret content (map-pin tooltips, menus with secret
                -- text), GetWidth() hands the template's resize recompute a SECRET number and its
                -- texcoord math throws; a forbidden layout aspect inherited from the owner's
                -- anchor makes the read itself throw (see ReadBorderSize). Skip the recompute
                -- either way (edges keep last-good texcoords and stretch, same as the throwing path left them, minus the per-resize error).
                bdFrame:SetScript("OnSizeChanged", function(self)
                    local usable, w = ReadBorderSize(self)
                    if not usable or not w then return end
                    self:OnBackdropSizeChanged()
                end)
                _bdBorderData[borderFrame] = bdFrame
            end
            bdFrame:SetFrameLevel(borderFrame:GetFrameLevel())
            -- edgeSize is in local units: SetBackdrop renders edgeSize x effectiveScale, so a
            -- scaled frame draws a proportionally scaled border (correct by default, hence
            -- opt-in). uiES/es = 1/(scale chain below UIParent), so ratio is 1 for an unscaled
            -- frame at any resolution or UI scale; the 0.01 floor keeps a degenerate scale from exploding it.
            local ratio = 1
            if normalizeScale then
                local eok, es = pcall(bdFrame.GetEffectiveScale, bdFrame)
                local uiES = UIParent and UIParent:GetEffectiveScale() or 1
                if eok and es and es > 0.01 and uiES > 0 then ratio = uiES / es end
            end
            local edgeSize = (EDGE_MAP[size] or EDGE_MAP[1]) * ratio
            -- Resolve offset/shift defaults: per-addon registry first, then global fallback.
            local adjX, adjY, sx, sy
            if addonKey and sizeKey then
                local dox, doy, dsx, dsy = EllesmereUI.GetBorderDefaults(addonKey, textureKey, sizeKey)
                adjX = offsetOverride or dox
                adjY = offsetYOverride or doy
                sx   = shiftX or dsx
                sy   = shiftY or dsy
            else
                adjX = offsetOverride or EllesmereUI.GetBorderTextureDefaultOffset(textureKey)
                adjY = offsetYOverride or EllesmereUI.GetBorderTextureDefaultOffsetY(textureKey)
                sx   = shiftX or 0
                sy   = shiftY or 0
            end
            -- Same factor as edgeSize, or a normalized edge would be positioned by offsets still in the frame's scaled units.
            adjX, adjY = adjX * ratio, adjY * ratio
            sx, sy = sx * ratio, sy * ratio
            -- scaleOffset textures: base = edgeSize/2 (border tracks the edge at any size) plus fine-tune adj; other textures: absolute offset, no base.
            local offsetX, offsetY
            if EllesmereUI.BorderTextureUsesScaleOffset(textureKey) then
                offsetX = (edgeSize / 2) + adjX
                offsetY = (edgeSize / 2) + adjY
            else
                offsetX = adjX
                offsetY = adjY
            end
            bdFrame:ClearAllPoints()
            bdFrame:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", -offsetX + sx, offsetY + sy)
            bdFrame:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", offsetX + sx, -offsetY + sy)
            -- SetBackdrop re-runs the nine-slice texcoord math, dividing by THIS frame's current
            -- width/height, and owners' sizes can be secret (map-pin tooltips); the upstream
            -- owner-width guard can pass while this anchored rect resolves secret, so the guard
            -- must sit here. Unchanged style (tooltips re-skin every Show) skips the template; a
            -- real style change under a secret size keeps the last-good backdrop and retries next apply (the color write below is vertex-only and always safe).
            local bdKey = texPath .. "@" .. edgeSize
            if bdFrame._euiBdKey ~= bdKey then
                local bdUsable, bdW = ReadBorderSize(bdFrame)
                if not bdUsable or not bdW then
                    bdFrame._euiBdKey = nil
                else
                    bdFrame:SetBackdrop({
                        edgeFile = texPath,
                        edgeSize = edgeSize,
                        insets = { left = 0, right = 0, top = 0, bottom = 0 },
                    })
                    bdFrame._euiBdKey = bdKey
                end
            end
            bdFrame:SetBackdropBorderColor(r, g, b, a)
            bdFrame:Show()
            borderFrame:Show()
        end
    end

    -- BackdropTemplate does arithmetic on its owner's width/height, so it is unusable for
    -- frames anchored to secret aura geometry. This variant draws the same eight edge-file
    -- slices manually, keeping the PP path for Solid; `state` is any caller-owned table caching the eight textures (FFD, AuraKit button data).
    local SECRET_BORDER_UV = {
        topLeft     = { 0.5078125, 0.0625, 0.5078125, 0.9375, 0.6171875, 0.0625, 0.6171875, 0.9375 },
        topRight    = { 0.6328125, 0.0625, 0.6328125, 0.9375, 0.7421875, 0.0625, 0.7421875, 0.9375 },
        bottomLeft  = { 0.7578125, 0.0625, 0.7578125, 0.9375, 0.8671875, 0.0625, 0.8671875, 0.9375 },
        bottomRight = { 0.8828125, 0.0625, 0.8828125, 0.9375, 0.9921875, 0.0625, 0.9921875, 0.9375 },
        top         = { 0.2578125, 0.9375, 0.3671875, 0.9375, 0.2578125, 0.0625, 0.3671875, 0.0625 },
        bottom      = { 0.3828125, 0.9375, 0.4921875, 0.9375, 0.3828125, 0.0625, 0.4921875, 0.0625 },
        left        = { 0.0078125, 0.0625, 0.0078125, 0.9375, 0.1171875, 0.0625, 0.1171875, 0.9375 },
        right       = { 0.1328125, 0.0625, 0.1328125, 0.9375, 0.2421875, 0.0625, 0.2421875, 0.9375 },
    }

    function EllesmereUI.ApplySecretSafeBorderStyle(borderFrame, state, size, r, g, b, a,
        textureKey, offsetX, offsetY, shiftX, shiftY, addonKey, sizeKey)
        if not borderFrame or not state then return end
        size, textureKey = size or 0, textureKey or "solid"
        local edges = state._secretBorderEdges
        -- Inlined, not a local closure: runs per-aura-per-refresh, and a closure built on entry (before the early-outs below) is pure garbage on the common path.
        if textureKey == "" or textureKey == "solid" or size <= 0 then
            if edges then for _, tex in pairs(edges) do tex:Hide() end end
            EllesmereUI.ApplyBorderStyle(borderFrame, size, r, g, b, a, "solid")
            return
        end
        local path = EllesmereUI.ResolveBorderTexture(textureKey)
        if not path then
            if edges then for _, tex in pairs(edges) do tex:Hide() end end
            EllesmereUI.ApplyBorderStyle(borderFrame, 0, 0, 0, 0, 0, "solid")
            return
        end
        -- Also hides any BackdropTemplate child already on this frame.
        EllesmereUI.ApplyBorderStyle(borderFrame, 0, 0, 0, 0, 0, "solid")
        borderFrame:Show()
        if not edges then
            edges = {}
            for key, uv in pairs(SECRET_BORDER_UV) do
                local tex = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                tex:SetTexCoord(unpack(uv)); edges[key] = tex
            end
            state._secretBorderEdges = edges
        end
        local edgeSize = EDGE_MAP[size] or EDGE_MAP[1]
        local ox, oy, sx, sy = EllesmereUI.GetBorderDefaults(addonKey, textureKey, sizeKey)
        ox = offsetX ~= nil and offsetX or ox; oy = offsetY ~= nil and offsetY or oy
        sx = shiftX ~= nil and shiftX or sx; sy = shiftY ~= nil and shiftY or sy
        if EllesmereUI.BorderTextureUsesScaleOffset(textureKey) then
            ox, oy = edgeSize / 2 + ox, edgeSize / 2 + oy
        end
        for _, tex in pairs(edges) do
            tex:SetTexture(path, true, true); tex:SetVertexColor(r, g, b, a or 1)
            tex:ClearAllPoints(); tex:Show()
        end
        edges.topLeft:SetSize(edgeSize, edgeSize); edges.topLeft:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", -ox + sx, oy + sy)
        edges.topRight:SetSize(edgeSize, edgeSize); edges.topRight:SetPoint("TOPRIGHT", borderFrame, "TOPRIGHT", ox + sx, oy + sy)
        edges.bottomLeft:SetSize(edgeSize, edgeSize); edges.bottomLeft:SetPoint("BOTTOMLEFT", borderFrame, "BOTTOMLEFT", -ox + sx, -oy + sy)
        edges.bottomRight:SetSize(edgeSize, edgeSize); edges.bottomRight:SetPoint("BOTTOMRIGHT", borderFrame, "BOTTOMRIGHT", ox + sx, -oy + sy)
        edges.top:SetHeight(edgeSize); edges.top:SetPoint("TOPLEFT", edges.topLeft, "TOPRIGHT"); edges.top:SetPoint("TOPRIGHT", edges.topRight, "TOPLEFT")
        edges.bottom:SetHeight(edgeSize); edges.bottom:SetPoint("BOTTOMLEFT", edges.bottomLeft, "BOTTOMRIGHT"); edges.bottom:SetPoint("BOTTOMRIGHT", edges.bottomRight, "BOTTOMLEFT")
        edges.left:SetWidth(edgeSize); edges.left:SetPoint("TOPLEFT", edges.topLeft, "BOTTOMLEFT"); edges.left:SetPoint("BOTTOMLEFT", edges.bottomLeft, "TOPLEFT")
        edges.right:SetWidth(edgeSize); edges.right:SetPoint("TOPRIGHT", edges.topRight, "BOTTOMRIGHT"); edges.right:SetPoint("BOTTOMRIGHT", edges.bottomRight, "TOPRIGHT")
    end

    --- Set border color on whichever system is active (PP or backdrop); used for hover highlights and other dynamic color changes.
    function EllesmereUI.SetBorderStyleColor(borderFrame, r, g, b, a)
        local PP = EllesmereUI.PP
        if not PP or not borderFrame then return end
        a = a or 1
        local ppContainer = PP.GetBorders(borderFrame)
        if ppContainer and ppContainer:IsShown() then
            PP.SetBorderColor(borderFrame, r, g, b, a)
            return
        end
        local bdFrame = _bdBorderData[borderFrame]
        if bdFrame and bdFrame:IsShown() then
            bdFrame:SetBackdropBorderColor(r, g, b, a)
        end
    end

    --- Hide whichever ApplyBorderStyle system is drawn on borderFrame (PP pixel border or
    --- BackdropTemplate texture) WITHOUT hiding borderFrame itself, for when another renderer (the dashed ants border) takes over the same frame.
    function EllesmereUI.HideBorderStyle(borderFrame)
        if not borderFrame then return end
        local PP = EllesmereUI.PP
        if PP and PP.GetBorders and PP.GetBorders(borderFrame) then PP.HideBorder(borderFrame) end
        local bdFrame = _bdBorderData[borderFrame]
        if bdFrame then bdFrame:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Global Color System -- central source of truth for class, power, and resource colors;
--  stored in EllesmereUIDB.customColors, falls back to WoW defaults.
-------------------------------------------------------------------------------

-- Default power colors (from WoW's PowerBarColor)
EllesmereUI.DEFAULT_POWER_COLORS = {
    -- Standard power types
    MANA         = { r = 0.000, g = 0.550, b = 1.000 },
    RAGE         = { r = 0.900, g = 0.150, b = 0.150 },
    FOCUS        = { r = 0xDD/255, g = 0x92/255, b = 0x37/255 },
    ENERGY       = { r = 1.000, g = 0.960, b = 0.410 },
    RUNIC_POWER  = { r = 0xC4/255, g = 0x1F/255, b = 0x3B/255 },
    LUNAR_POWER  = { r = 0xFF/255, g = 0x7D/255, b = 0x0A/255 },
    INSANITY     = { r = 0.400, g = 0.000, b = 0.800 },
    MAELSTROM    = { r = 0x00/255, g = 0x70/255, b = 0xDE/255 },
    FURY         = { r = 0xA3/255, g = 0x30/255, b = 0xC9/255 },
    PAIN         = { r = 1.000, g = 0.612, b = 0.000 },
    EBON_MIGHT   = { r = 0xE6/255, g = 0x8C/255, b = 0x4D/255 },
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

-- Default class-resource colors keyed by the RESOURCE, not the class (classes with multiple resources get distinct colors); customized via customColors.classResource.
EllesmereUI.DEFAULT_CLASS_RESOURCE_COLORS = {
    ComboPoints     = { r = 1.0,    g = 0.9608, b = 0.4118 },
    Runes           = { r = 0.0,    g = 0.8196, b = 1.0    },
    SoulShards      = { r = 0.5059, g = 0.3412, b = 0.8431 },
    HolyPower       = { r = 0.949,  g = 0.902,  b = 0.6    },
    ArcaneCharges   = { r = 0.7176, g = 0.4902, b = 0.8118 },
    Icicles         = { r = 0.7098, g = 1.0,    b = 0.9216 },
    Chi             = { r = 0.0,    g = 1.0,    b = 0.6    },
    Essence         = { r = 0.2,    g = 0.58,   b = 0.502  },
    SoulFragments   = { r = 0.6,    g = 0.8,    b = 0.2    },
    MaelstromWeapon = { r = 0.0,    g = 0.4392, b = 0.8706 },
    TipOfTheSpear   = { r = 0.6667, g = 0.8275, b = 0.4471 },
    WhirlwindStacks = { r = 0.7765, g = 0.6078, b = 0.4275 },
    SweepingStrikes = { r = 0.8510, g = 0.4157, b = 0.3373 },
}

-- Get a class-resource color (custom override or default), keyed by resource.
function EllesmereUI.GetClassResourceColor(key)
    if not key then return nil end
    if EllesmereUI._colorCacheDirty then EllesmereUI._RebuildColorCache() end
    return EllesmereUI._colorCache.classResource[key]
end

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

-- Canonical 13-class token sequence (role order) for class pickers/grids, read-only; sites needing a DIFFERENT order (e.g. alphabetical) keep local lists.
EllesmereUI.CLASS_TOKEN_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
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

-- Effective in-game custom colours for all rendering consumers (lazy-init). Stored PER
-- PROFILE (db.profiles[name].customColors); the account-wide toggle
-- EllesmereUIDB.colorsApplyToAllProfiles (default ON, nil = on) picks which palette:
--   ON  (global, default): ONE chosen profile's palette (EllesmereUIDB.colorsPullFrom,
--        default the first profile) shared across EVERY profile.
--   OFF (per-profile): the ACTIVE profile's own palette.
-- Nothing is wiped/restored on a profile switch (the getter just resolves a different
-- table), so a spec-switch colour wipe cannot happen. Missing tables -> defaults.
function EllesmereUI.GetCustomColorsDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.customColors then EllesmereUIDB.customColors = {} end
    if EllesmereUI.GetProfilesDB then
        local pdb = EllesmereUI.GetProfilesDB()
        if EllesmereUIDB.colorsApplyToAllProfiles == false then
            -- Per-profile: the active profile's own palette.
            local active = pdb.profiles and pdb.profiles[pdb.activeProfile or "Default"]
            if active then active.customColors = active.customColors or {}; return active.customColors end
        else
            -- Global (default): the chosen source profile's palette, used everywhere.
            -- Heal a dangling source pointer first (profile removed by a path that
            -- missed the DeleteProfile/RenameProfile cleanup, or a DB saved before
            -- that cleanup existed): treat it as unset so the first profile takes
            -- over, instead of silently falling through to the legacy account table.
            local pull = EllesmereUIDB.colorsPullFrom
            if pull and not (pdb.profiles and pdb.profiles[pull]) then
                EllesmereUIDB.colorsPullFrom = nil
            end
            local srcName = EllesmereUIDB.colorsPullFrom or (pdb.profileOrder and pdb.profileOrder[1])
            local src = srcName and pdb.profiles and pdb.profiles[srcName]
            if src then src.customColors = src.customColors or {}; return src.customColors end
        end
    end
    return EllesmereUIDB.customColors
end

-- Colour editing locks ONLY in global mode while viewing a profile other than the
-- palette source (editing a dormant palette would mislead). Per-profile mode is always
-- editable; global mode is editable on the source profile.
function EllesmereUI.IsColorEditingLocked()
    if not EllesmereUIDB then return false end
    if EllesmereUIDB.colorsApplyToAllProfiles == false then return false end
    if not EllesmereUI.GetProfilesDB then return false end
    local pdb = EllesmereUI.GetProfilesDB()
    local activeName = pdb.activeProfile or "Default"
    local srcName = EllesmereUIDB.colorsPullFrom or (pdb.profileOrder and pdb.profileOrder[1])
    return srcName ~= nil and srcName ~= activeName
end

-------------------------------------------------------------------------------
--  Dark Mode (per-profile)
--  One shared palette feeds the Dark Mode look of Unit Frames, Raid Frames and
--  Resource Bars, plus "darken" amounts that blacken class/power/class-resource
--  colours inside the colour getters below (every consumer gets adjusted values,
--  no per-module logic). Stored at EllesmereUIDB.profiles[name].darkMode (sibling
--  of customColors) and ALWAYS the ACTIVE profile's own table -- no "Apply to All
--  Profiles" redirect. Defaults: #111111 fill @ 90%, #4f4f4f bg @ 100%, zero darken.
-------------------------------------------------------------------------------
EllesmereUI.DEFAULT_DARK_MODE = {
    fillR = 0x11/255, fillG = 0x11/255, fillB = 0x11/255, fillA = 0.90,
    bgR   = 0x4f/255, bgG   = 0x4f/255, bgB   = 0x4f/255, bgA   = 1.0,
    classDarken = 0, powerDarken = 0, resourceDarken = 0, powerBgDarken = 0,
}

-- The active profile's dark-mode table (lazily created, may be sparse -- callers
-- fall back to DEFAULT_DARK_MODE per field). Never returns nil.
function EllesmereUI.GetDarkModeDB()
    if EllesmereUI.GetProfilesDB then
        local pdb = EllesmereUI.GetProfilesDB()
        if pdb and pdb.profiles then
            local active = pdb.profiles[pdb.activeProfile or "Default"]
            if active then
                active.darkMode = active.darkMode or {}
                return active.darkMode
            end
        end
    end
    if not EllesmereUIDB then EllesmereUIDB = {} end
    EllesmereUIDB.darkMode = EllesmereUIDB.darkMode or {}
    return EllesmereUIDB.darkMode
end

-- Dark Mode fill colour (r, g, b, a). Opacity is honoured by Unit Frames and
-- Raid Frames; Resource Bars ignore the alpha and keep their own.
function EllesmereUI.GetDarkModeFill()
    local d = EllesmereUI.GetDarkModeDB()
    local def = EllesmereUI.DEFAULT_DARK_MODE
    return d.fillR or def.fillR, d.fillG or def.fillG, d.fillB or def.fillB, d.fillA or def.fillA
end

-- Dark Mode background colour (r, g, b, a). Same opacity rules as the fill.
function EllesmereUI.GetDarkModeBg()
    local d = EllesmereUI.GetDarkModeDB()
    local def = EllesmereUI.DEFAULT_DARK_MODE
    return d.bgR or def.bgR, d.bgG or def.bgG, d.bgB or def.bgB, d.bgA or def.bgA
end

-- Effective-colour cache. Class/power/resource getters run in hot render paths, so the FINAL
-- colours (palette + darken) are precomputed once and served as cached {r,g,b} tables: rebuilt
-- lazily on first read after invalidation, reads are one lookup with zero allocation.
-- Invalidation inputs: ApplyColorsToOUF (the universal "colours changed" chokepoint -- swatch
-- edits, resets, mode toggles, profile switches) and RefreshDarkMode. READ-ONLY derived cache: worst failure is a stale colour.
EllesmereUI._colorCache = { class = {}, power = {}, classResource = {}, resource = {}, classCustomized = {} }
EllesmereUI._colorCacheDirty = true
EllesmereUI._COLOR_WHITE = { r = 1, g = 1, b = 1 }
EllesmereUI._powerBgDarkenFactor = 1

function EllesmereUI.InvalidateColorCache()
    EllesmereUI._colorCacheDirty = true
end

-- Fill `out` with {r,g,b} per key: defaults overlaid by custom, blackened by darkenPct (0-100); sub-tables are recreated each rebuild (rare) so hot-path reads never allocate.
function EllesmereUI._BuildColorPalette(out, defaults, custom, darkenPct)
    wipe(out)
    if defaults then
        for k, def in pairs(defaults) do out[k] = { r = def.r, g = def.g, b = def.b } end
    end
    if custom then
        for k, c in pairs(custom) do out[k] = { r = c.r, g = c.g, b = c.b } end
    end
    if darkenPct and darkenPct > 0 then
        local f = 1 - darkenPct / 100
        if f < 0 then f = 0 end
        for _, col in pairs(out) do
            col.r = col.r * f; col.g = col.g * f; col.b = col.b * f
        end
    end
end

function EllesmereUI._RebuildColorCache()
    local cc = EllesmereUI.GetCustomColorsDB()
    local dm = EllesmereUI.GetDarkModeDB()
    local cache = EllesmereUI._colorCache
    EllesmereUI._BuildColorPalette(cache.class,          EllesmereUI.CLASS_COLOR_MAP,               cc and cc.class,          dm and dm.classDarken)
    EllesmereUI._BuildColorPalette(cache.power,          EllesmereUI.DEFAULT_POWER_COLORS,          cc and cc.power,          dm and dm.powerDarken)
    EllesmereUI._BuildColorPalette(cache.classResource,  EllesmereUI.DEFAULT_CLASS_RESOURCE_COLORS, cc and cc.classResource,  dm and dm.resourceDarken)
    EllesmereUI._BuildColorPalette(cache.resource,       EllesmereUI.DEFAULT_RESOURCE_COLORS,       cc and cc.resource,       dm and dm.resourceDarken)
    -- BG Power Color Darken: extra blacken for power-COLORED bar backgrounds, kept as a multiplier (not a palette) so it stacks on whatever power color a consumer resolved.
    local bgd = (dm and dm.powerBgDarken) or 0
    EllesmereUI._powerBgDarkenFactor = bgd > 0 and math.max(0, 1 - bgd / 100) or 1
    -- Classes whose effective colour no longer matches Blizzard's default (a swatch edit, or any
    -- nonzero class darken). Only these need the restricted-unit recovery below; an untouched
    -- palette leaves the table empty, so that path costs one next() and stops.
    local customized = cache.classCustomized
    wipe(customized)
    for token, def in pairs(EllesmereUI.CLASS_COLOR_MAP) do
        local col = cache.class[token]
        if col and (math.abs(col.r - def.r) > 0.004 or math.abs(col.g - def.g) > 0.004
                or math.abs(col.b - def.b) > 0.004) then
            customized[token] = col
        end
    end
    EllesmereUI._restrictedCandidatesDirty = true
    EllesmereUI._colorCacheDirty = false
end

-- Modules register a callback re-reading the dark palette and repainting their frames; RefreshDarkMode() runs them all and re-pushes class/power colours via ApplyColorsToOUF.
EllesmereUI._darkModeRefreshers = EllesmereUI._darkModeRefreshers or {}
function EllesmereUI.RegisterDarkModeRefresh(fn)
    if type(fn) == "function" then
        EllesmereUI._darkModeRefreshers[#EllesmereUI._darkModeRefreshers + 1] = fn
    end
end
function EllesmereUI.RefreshDarkMode()
    -- Darken amounts feed the colour cache; drop it so refreshers + the OUF push below resolve freshly darkened colours.
    EllesmereUI.InvalidateColorCache()
    for _, fn in ipairs(EllesmereUI._darkModeRefreshers) do pcall(fn) end
    if EllesmereUI.ApplyColorsToOUF then EllesmereUI.ApplyColorsToOUF() end
end

-- Global Dark Mode master toggle. Each module stores its own flag in its own DB shape (UF
-- darkTheme; RB secondary.darkTheme; RF healthColorMode == "dark"), so each registers a
-- provider that reads/flips its flag AND repaints its frames. The master toggle is a pure view
-- (reads "all on", writes "set all"): no stored key, so it can never desync from the per-module toggles.
EllesmereUI._darkModeToggles = EllesmereUI._darkModeToggles or {}
function EllesmereUI.RegisterDarkModeToggle(provider)
    if type(provider) == "table" and type(provider.isOn) == "function"
        and type(provider.setOn) == "function" then
        EllesmereUI._darkModeToggles[#EllesmereUI._darkModeToggles + 1] = provider
    end
end

-- True only when every registered module has Dark Mode on (and at least one is registered).
-- Optional `filter(provider) -> boolean` narrows which providers count, so one checkbox can view a single group and read "on" only when that group is all dark.
function EllesmereUI.IsDarkModeAllOn(filter)
    local matched = false
    for _, p in ipairs(EllesmereUI._darkModeToggles) do
        if not filter or filter(p) then
            matched = true
            local ok, on = pcall(p.isOn)
            if not ok or not on then return false end
        end
    end
    return matched
end

-- Flip every module's Dark Mode to `on`, then refresh the shared palette so palette-listening modules repaint too. `filter` narrows as in IsDarkModeAllOn.
function EllesmereUI.SetDarkModeAll(on, filter)
    on = on and true or false
    for _, p in ipairs(EllesmereUI._darkModeToggles) do
        if not filter or filter(p) then
            pcall(p.setOn, on)
        end
    end
    EllesmereUI.RefreshDarkMode()
    -- Dark Mode feeds the conditional-override "darkmode" condition. Deliberately here, NOT in
    -- RefreshDarkMode: SetDarkModeAll is only called by the Fonts & Colors master checkboxes
    -- (pure user action), while RefreshDarkMode is also reached from the profile-apply pipeline
    -- where an extra recheck could interleave with the conditions establish choreography (cheap no-op with no darkmode group; self-defers in combat).
    if EllesmereUI.Conditions_Recheck then EllesmereUI.Conditions_Recheck() end
end

-------------------------------------------------------------------------------
--  Global Font System
-------------------------------------------------------------------------------
-- Canonical font name -> filename mapping (shared across all addons)
EllesmereUI.FONT_FILES = {
    ["Expressway"]          = "Expressway.TTF",
    ["Expressway Bold"]     = "Expressway Bold.ttf",
    ["Avant Garde"]         = "Avant Garde Naowh.ttf",
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
    ["KMT Kimberley"]       = "KMT Kimberley.otf",
    ["KMT Ninja Naruto"]    = "KMT Ninja Naruto.ttf",
    ["Friz Quadrata"]       = nil,  -- Blizzard font
    ["Arial"]               = nil,  -- Blizzard font
    ["Morpheus"]            = nil,  -- Blizzard font
    ["Skurri"]              = nil,  -- Blizzard font
}
-- Bundled faces whose cmap covers the FULL Russian alphabet (U+0410-U+044F plus U+0401
-- and U+0451, i.e. the Yo pair): these stay
-- usable in ruRU instead of being swapped for the system glyph font. Verified per file
-- against its cmap table -- everything omitted here (Poppins, Exo, Gotham, Changa, Cinzel,
-- Future X Black, Homespun, KMT Ninja Naruto, Barlow Condensed) has ZERO Cyrillic and would
-- render boxes. Re-check coverage before adding a face; a wrong entry ships unreadable text.
-- Deliberately NOT extended to FONT_BLIZZARD: the Cyrillic-capable Blizzard face is
-- FRIZQT___CYR (already the fallback), and the plain ones vary by installed client locale.
EllesmereUI.FONT_CYRILLIC = {
    ["Expressway"]       = true,
    ["Expressway Bold"]  = true,
    ["Avant Garde"]      = true,
    ["Arial Bold"]       = true,
    ["Arial Narrow"]     = true,
    ["Fira Sans Medium"] = true,
    ["Fira Sans Bold"]   = true,
    ["Fira Sans Light"]  = true,
    ["KMT Kimberley"]    = true,
    ["Russo One"]        = true,
    ["Ubuntu"]           = true,
}

-- Blizzard built-in font paths (not in our media folder)
EllesmereUI.FONT_BLIZZARD = {
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial"]         = "Fonts\\ARIALN.TTF",
    ["Morpheus"]      = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]        = "Fonts\\skurri.ttf",
}
EllesmereUI.FONT_ORDER = {
    "Expressway", "Expressway Bold", "Avant Garde", "Arial Bold", "Poppins", "Fira Sans Medium",
    "---",
    "Arial Narrow", "Changa", "Cinzel Decorative", "Exo",
    "Fira Sans Bold", "Fira Sans Light", "Future X Black",
    "Gotham Narrow Ultra", "Gotham Narrow", "Russo One", "Ubuntu", "Homespun",
    "KMT Kimberley", "KMT Ninja Naruto",
    "Friz Quadrata", "Arial", "Morpheus", "Skurri",
}
-- Display name overrides for the font dropdown (key = FONT_ORDER name)
EllesmereUI.FONT_DISPLAY_NAMES = {
}

-- Sentinel key = "use the locale system font", offered in the picker for glyph-restricted
-- locales (CJK, Cyrillic). Resolves to LOCALE_FONT_FALLBACK in ResolveFontName.
EllesmereUI.SYSTEM_FONT_KEY = "__system"

-- Sentinel forcing bundled Expressway in glyph-restricted locales. Distinct from the
-- stored name "Expressway" ON PURPOSE: untouched defaults keep mapping to the system
-- font, and only an explicit pick takes the Latin face (non-Latin renders unglyphed).
EllesmereUI.EXPRESSWAY_FORCED_KEY = "__expressway"

-- Register bundled fonts with LSM (other addons get them; SM's HashTable("font")
-- includes them for our dropdowns) and populate _smFontPaths for ResolveFontName.
do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for name, file in pairs(EllesmereUI.FONT_FILES) do
            if file then
                LSM:Register(LSM.MediaType.FONT, name, MEDIA_PATH .. "fonts\\" .. file)
            end
        end
        -- Snapshot all currently registered SM fonts into the path lookup
        local smFonts = LSM:HashTable("font")
        if smFonts then
            EllesmereUI._smFontPaths = {}
            for name, path in pairs(smFonts) do
                EllesmereUI._smFontPaths[name] = path
            end
        end
        -- Listen for late-registered fonts from other addons
        LSM.RegisterCallback(EllesmereUI, "LibSharedMedia_Registered", function(_, mediatype, key)
            if mediatype == "font" then
                if not EllesmereUI._smFontPaths then EllesmereUI._smFontPaths = {} end
                local path = LSM:Fetch("font", key)
                if path then EllesmereUI._smFontPaths[key] = path end
                EllesmereUI.InvalidateFontCache()
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Font resolution cache -- GetFontPath / GetFontName / GetFontOutlineFlag /
--  GetIconTextOutlineFlag all walk the same chain (GetFontsDB -> GetModuleFontEntry ->
--  ResolveFontName -> SlugFlag -> IsSlugDisabled); recomputing it per text update was
--  ~44% of this addon's CPU. Results depend on the fonts DB, the addon key, AND
--  _smFontPaths (read by ResolveFontName), so they are memoized per key.
--  Invalidation is explicit and deliberately coarse (drop everything):
--    * every font setting funnels through the options page's FontReload()
--    * applying or importing a profile rewrites the fonts DB in place
--    * the fonts reset nils the table outright
--    * a late LibSharedMedia_Registered font updates _smFontPaths
--  Anything else writing the fonts DB OR _smFontPaths MUST call InvalidateFontCache():
--  omitting it cached the Expressway fallback for the session when an SM font registered
--  late. Memoizing in front of ResolveFontName DISABLES its own late-load LSM re-fetch (a
--  cache hit never reaches it), so this cache is the only recovery path. Table fields, not
--  file-scope locals: this file sits on the 200-local limit.
-------------------------------------------------------------------------------
EllesmereUI._fontCache = { path = {}, name = {}, outline = {}, icon = {} }
EllesmereUI._fontCacheDirty = true
-- Stand-in key for a nil addonKey (the global font), which cannot index a table.
EllesmereUI._FONT_KEY_GLOBAL = "\1global"
-- Dropdown sentinel for "Blizzard Default": resolves to the client's own
-- standard UI font (STANDARD_TEXT_FONT, locale-aware) in ResolveFontName.
EllesmereUI.BLIZZARD_FONT_KEY = "__blizzard"

function EllesmereUI.InvalidateFontCache()
    EllesmereUI._fontCacheDirty = true
end

--- Returns the cache, cleared first if a font setting changed since last use.
function EllesmereUI._FontCacheReady()
    local c = EllesmereUI._fontCache
    if EllesmereUI._fontCacheDirty then
        wipe(c.path); wipe(c.name); wipe(c.outline); wipe(c.icon)
        c.slug = nil
        EllesmereUI._fontCacheDirty = false
    end
    return c
end

-- Get the fonts DB table (lazy-init)
function EllesmereUI.GetFontsDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.fonts then
        EllesmereUIDB.fonts = {
            -- Cyrillic locales seed the system glyph font, not Expressway: the FONT_CYRILLIC
            -- faces do render ruRU correctly, but they stay an explicit opt-in so a fresh
            -- install looks exactly like every prior version. Existing installs are pinned
            -- by the ru_cyrillic_font_optin_v1 migration.
            global      = (EllesmereUI.LOCALE_SCRIPT == "cyrillic")
                          and EllesmereUI.SYSTEM_FONT_KEY or "Expressway",
            outlineMode = "shadow",
        }
    end
    local f = EllesmereUIDB.fonts
    return f
end

-- Resolve a font name to a full file path
local function ResolveFontName(fontName)
    -- Blizzard Default: the client's own standard UI font. Handled before the
    -- glyph-restriction branch because STANDARD_TEXT_FONT is already
    -- locale-aware (the engine picks the right face per client language).
    if fontName == EllesmereUI.BLIZZARD_FONT_KEY then
        return _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    end
    -- Explicit Expressway override: bypasses the glyph-restriction mapping below.
    if fontName == EllesmereUI.EXPRESSWAY_FORCED_KEY then
        return MEDIA_PATH .. "fonts\\Expressway.TTF"
    end
    -- Glyph-restricted locales (CJK, Cyrillic): bundled fonts without coverage for the
    -- script, and the System Default sentinel, map to the system glyph font. Only an
    -- external SharedMedia font (or a FONT_CYRILLIC face in ruRU, handled first) may
    -- override. Bundled names are excluded below because they are LSM-registered too and
    -- would otherwise resolve to their Latin file.
    if LOCALE_FONT_FALLBACK then
        -- Cyrillic locales: a bundled face with verified Cyrillic coverage renders ruRU
        -- text correctly, so honour the pick instead of forcing the system glyph font.
        -- Gated on LOCALE_SCRIPT, not on the fallback alone: CJK has no bundled coverage.
        if EllesmereUI.LOCALE_SCRIPT == "cyrillic" and fontName
           and EllesmereUI.FONT_CYRILLIC[fontName] then
            local cyrFile = EllesmereUI.FONT_FILES[fontName]
            if cyrFile then return MEDIA_PATH .. "fonts\\" .. cyrFile end
        end
        if fontName
           and not EllesmereUI.FONT_FILES[fontName]
           and not EllesmereUI.FONT_BLIZZARD[fontName] then
            local smPath = EllesmereUI._smFontPaths and EllesmereUI._smFontPaths[fontName]
            if smPath then return smPath end
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM and LSM:IsValid("font", fontName) then
                local fetched = LSM:Fetch("font", fontName)
                if fetched then
                    if not EllesmereUI._smFontPaths then EllesmereUI._smFontPaths = {} end
                    EllesmereUI._smFontPaths[fontName] = fetched
                    return fetched
                end
            end
        end
        return LOCALE_FONT_FALLBACK
    end
    local bliz = EllesmereUI.FONT_BLIZZARD[fontName]
    if bliz then return bliz end
    local file = EllesmereUI.FONT_FILES[fontName]
    if file then
        return MEDIA_PATH .. "fonts\\" .. file
    end
    -- SharedMedia fonts: path from _smFontPaths (populated at init)
    local smPath = EllesmereUI._smFontPaths and EllesmereUI._smFontPaths[fontName]
    if smPath then return smPath end
    -- LSM fallback for late-loading SM addons not yet in _smFontPaths
    if fontName then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local fetched = LSM:Fetch("font", fontName)
            if fetched then
                if not EllesmereUI._smFontPaths then EllesmereUI._smFontPaths = {} end
                EllesmereUI._smFontPaths[fontName] = fetched
                return fetched
            end
        end
    end
    return MEDIA_PATH .. "fonts\\Expressway.TTF"
end
EllesmereUI.ResolveFontName = ResolveFontName

-- Per-module font overrides: all state stored on the EllesmereUI table
-- to stay under the 200-local / 60-upvalue Lua 5.1 caps.
EllesmereUI._addonKeyToFolder = {
    actionBars   = "EllesmereUIActionBars",
    nameplates   = "EllesmereUINameplates",
    unitFrames   = "EllesmereUIUnitFrames",
    cdm          = "EllesmereUICooldownManager",
    resourceBars = "EllesmereUIResourceBars",
    auraBuff     = "EllesmereUIAuraBuffReminders",
    extras       = "EllesmereUIQoL",
    friends      = "EllesmereUIFriends",
    minimap      = "EllesmereUIMinimap",
    chat         = "EllesmereUIChat",
    questTracker = "EllesmereUIQuestTracker",
    mythicTimer  = "EllesmereUIMythicTimer",
    blizzardSkin = "EllesmereUIBlizzardSkin",
    damageMeters = "EllesmereUIDamageMeters",
    dataBars     = "EllesmereUIDataBars",
    raidFrames   = "EllesmereUIRaidFrames",
    bags         = "EllesmereUIBags",
    quickdraw    = "EllesmereUIQuickdraw",
}
EllesmereUI._moduleFontCache = {}
EllesmereUI._moduleFontCacheVer = 0

-- Resolve an addonKey to a moduleFonts entry (nil = global). Cached per-key, zero-alloc.
function EllesmereUI.GetModuleFontEntry(addonKey)
    if not addonKey then return nil end
    local db = EllesmereUI.GetFontsDB()
    local mfList = db.moduleFonts
    if not mfList or #mfList == 0 then return nil end

    local cache = EllesmereUI._moduleFontCache
    local ver = #mfList
    if ver ~= EllesmereUI._moduleFontCacheVer then
        wipe(cache)
        EllesmereUI._moduleFontCacheVer = ver
    end

    local cached = cache[addonKey]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local folder = EllesmereUI._addonKeyToFolder[addonKey] or addonKey

    for _, entry in ipairs(mfList) do
        if entry.folder == folder then
            cache[addonKey] = entry
            return entry
        end
    end
    cache[addonKey] = false
    return nil
end

-- Resolved font path for an addon key; falls back to the global font with no override.
function EllesmereUI.GetFontPath(addonKey)
    local c = EllesmereUI._FontCacheReady().path
    local k = addonKey or EllesmereUI._FONT_KEY_GLOBAL
    local hit = c[k]
    if hit then return hit end

    local db = EllesmereUI.GetFontsDB()
    local override = EllesmereUI.GetModuleFontEntry(addonKey)
    local path
    if override and override.font and override.font ~= "__global" then
        path = ResolveFontName(override.font)
    else
        path = ResolveFontName(db.global or "Expressway")
    end
    c[k] = path
    return path
end

-- Get the font name (not path) for an addon key.
function EllesmereUI.GetFontName(addonKey)
    local c = EllesmereUI._FontCacheReady().name
    local k = addonKey or EllesmereUI._FONT_KEY_GLOBAL
    local hit = c[k]
    if hit then return hit end

    local db = EllesmereUI.GetFontsDB()
    local override = EllesmereUI.GetModuleFontEntry(addonKey)
    local name
    if override and override.font and override.font ~= "__global" then
        name = override.font
    else
        name = db.global or "Expressway"
    end
    c[k] = name
    return name
end

-- Get the WoW font flag string for the outline mode.
-- Pass an addonKey to get per-module override; nil returns the global setting.
-- Returns: "OUTLINE, SLUG", "THICKOUTLINE, SLUG", or "" (none/shadow)
function EllesmereUI.GetFontOutlineFlag(addonKey)
    local c = EllesmereUI._FontCacheReady().outline
    local k = addonKey or EllesmereUI._FONT_KEY_GLOBAL
    -- "" (no outline) is a legitimate result and truthy in Lua, so a presence test is a correct cache hit.
    local hit = c[k]
    if hit then return hit end

    local db = EllesmereUI.GetFontsDB()
    local override = EllesmereUI.GetModuleFontEntry(addonKey)
    local mode
    if override and override.outline and override.outline ~= "__global" then
        mode = override.outline
    else
        mode = db.outlineMode or "none"
    end
    local flag
    if mode == "outline" then flag = "OUTLINE, SLUG"
    elseif mode == "thick" then flag = "THICKOUTLINE, SLUG"
    else flag = "" end
    flag = EllesmereUI.SlugFlag(flag)
    c[k] = flag
    return flag
end

-- Per-profile "Never Show Slug": ON strips the SLUG token from every outline flag the
-- UI produces (body + icon/aura text across all modules, plus the global Outline Mode).
-- Lives in the per-profile fonts DB so it rides profile export/import, falling back to
-- the account-global EllesmereUIDB.neverShowSlug. OFF by default.
function EllesmereUI.IsSlugDisabled()
    local c = EllesmereUI._FontCacheReady()
    -- Cached value is a boolean, so nil is the only safe "not yet computed".
    if c.slug ~= nil then return c.slug end

    local f = EllesmereUI.GetFontsDB()
    local v = f and f.neverShowSlug
    if v == nil then v = EllesmereUIDB and EllesmereUIDB.neverShowSlug end
    v = (v == true)
    c.slug = v
    return v
end

-- Strip the SLUG token from a font outline flag:
-- "OUTLINE, SLUG" -> "OUTLINE", "THICKOUTLINE, SLUG" -> "THICKOUTLINE", "" -> "".
function EllesmereUI.StripSlugFlag(flag)
    if not flag or flag == "" then return flag or "" end
    return (flag:gsub("%s*,%s*SLUG", ""))
end

-- Central gate: strips SLUG from `flag` when "Never Show Slug" is on. Use at EVERY point
-- a slug outline flag is produced (outline helpers, hardcoded icon-text literals).
function EllesmereUI.SlugFlag(flag)
    if EllesmereUI.IsSlugDisabled() then return EllesmereUI.StripSlugFlag(flag) end
    return flag
end

-- Returns true when the outline mode uses drop shadow instead of outline.
-- Pass an addonKey to get per-module override; nil returns the global setting.
function EllesmereUI.GetFontUseShadow(addonKey)
    local db = EllesmereUI.GetFontsDB()
    local override = EllesmereUI.GetModuleFontEntry(addonKey)
    local mode
    if override and override.outline and override.outline ~= "__global" then
        mode = override.outline
    else
        mode = db.outlineMode or "none"
    end
    return mode == "none" or mode == "shadow"
end

-- Runtime FontString:SetShadowOffset/SetShadowColor does NOT render a drop shadow;
-- shadows only render when carried by a FontObject. Prime each string with a shared
-- shadow (or no-shadow) FontObject via SetFontObject, THEN SetFont for the typeface:
-- the inherited shadow survives SetFont and instance text color is preserved.
do
    local shadowObj = CreateFont("EllesmereUIShadowFont")
    shadowObj:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    shadowObj:SetShadowColor(0, 0, 0, 1)
    shadowObj:SetShadowOffset(1, -1)
    local noShadowObj = CreateFont("EllesmereUINoShadowFont")
    noShadowObj:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    noShadowObj:SetShadowColor(0, 0, 0, 0)
    noShadowObj:SetShadowOffset(0, 0)
    -- Prime a FontString so its drop shadow renders. Call BEFORE SetFont.
    function EllesmereUI.PrimeFontShadow(fs, useShadow)
        if not (fs and fs.SetFontObject) then return end
        fs:SetFontObject(useShadow and shadowObj or noShadowObj)
    end
end

-- "Apply to All Game Text" + "Game Text Scale": swaps Blizzard's default game fonts to
-- the user's global face and/or scales their sizes. Taint-safe: runs once at PLAYER_LOGIN
-- (out of combat), sets STANDARD_TEXT_FONT, and SetFonts Blizzard's named font OBJECTS
-- (not secure frames, no keys written onto Blizzard frame tables). Outline preserved;
-- sizes multiply from each object's NATIVE size (single once-per-session pass, so the
-- scale can never compound); either setting requires a reload (no undo path: off/100% =
-- that half skipped, defaults kept). Scale works without the face swap too -- each
-- object keeps its own face at the scaled size.
function EllesmereUI.ApplyGlobalFontToGameText()
    local db = EllesmereUI.GetFontsDB()
    -- Zero cost while fully off: both settings absent (scale 100 stores nil)
    -- means two table reads and out -- nothing computed, nothing enumerated.
    if not db.applyToAllGameText and not db.gameTextScale then return end
    local scale = tonumber(db.gameTextScale) or 100
    if scale < 75 then scale = 75 elseif scale > 125 then scale = 125 end
    scale = scale / 100
    local swap = db.applyToAllGameText and true or false
    local path
    if swap then
        path = ResolveFontName(db.global or "Expressway")
        if not path then swap = false end
    end
    if not swap and scale == 1 then return end

    if swap then
        -- Universal fallback consumed by newly-created Blizzard/addon text.
        _G.STANDARD_TEXT_FONT = path
    end

    -- Enumerate every registered font object via the game's own font list (no
    -- hardcoded list to go stale); covers Blizzard + other addons in one pass.
    local fonts = (GetFonts and GetFonts()) or {}
    for i = 1, #fonts do
        local obj = _G[fonts[i]]
        -- Guard each: GetFonts may list entries that are not usable font objects.
        if obj and type(obj) == "table" and obj.GetFont and obj.SetFont then
            local face, size, flags = obj:GetFont()
            if size and size > 0 then
                obj:SetFont(swap and path or face, size * scale, flags)
            end
        end
    end
end

-- Module-scoped font failsafe (always on, independent of "Apply to All Game Text"). Chat,
-- Quest Tracker and the Blizz-UI-Enhanced tooltips style text per-frame, but some sub-elements
-- draw from Blizzard's SHARED font OBJECTS, leaving stragglers on the default face; swapping
-- those objects at login catches them. Each area is gated on its module being loaded/enabled
-- and uses that module's font key (per-module override, else global). Typeface + outline only,
-- native size preserved (tooltips keep their font-scale). Taint-safe like ApplyGlobalFontToGameText: SetFont on font objects only, never a write onto a Blizzard frame table; runs after the global pass so module wins.
function EllesmereUI.ApplyModuleFontFailsafe()
    local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    local GetPath = EllesmereUI.GetFontPath
    local GetOutline = EllesmereUI.GetFontOutlineFlag
    if not IsLoaded or not GetPath then return end

    -- Face + outline swap preserving each object's native SIZE (per-frame styling owns size).
    -- The outline matches what each area's per-frame styling applies (chat, questTracker,
    -- blizzardSkin) so stragglers stop looking un-styled. Safe for the chat input box:
    -- SkinEditBox sets its own font, so it never inherits ChatFontNormal. `outline` may be ""
    -- (Drop Shadow/None), which correctly CLEARS a native outline; pass nil to keep native flags. Guards nil/non-object, missing size and a rejecting SetFont, so an absent or renamed object is a no-op.
    local function swap(obj, path, outline)
        if not obj or type(obj) ~= "table" or not obj.GetFont or not obj.SetFont then return end
        local _, size, flags = obj:GetFont()
        if not size or size <= 0 then return end
        if outline ~= nil then flags = outline end
        pcall(obj.SetFont, obj, path or _G.STANDARD_TEXT_FONT, size, flags)
    end

    -- Chat: the module fonts the frames + edit boxes directly; ChatFontNormal backstops the rest (menus, copy/URL windows, channel buttons, etc.).
    if IsLoaded("EllesmereUIChat") then
        swap(_G.ChatFontNormal, GetPath("chat"), GetOutline and GetOutline("chat"))
    end

    -- Quest Tracker: the skin region-walks live blocks; these shared objects catch fontstrings
    -- Blizzard re-templates after the walk. ONLY ObjectiveTracker*-prefixed objects, so the world-map quest log (QuestFont*) stays untouched.
    if IsLoaded("EllesmereUIQuestTracker") then
        local p = GetPath("questTracker")
        local po = GetOutline and GetOutline("questTracker")
        swap(_G.ObjectiveTrackerHeaderFont, p, po)
        swap(_G.ObjectiveTrackerLineFont, p, po)
        for i = 12, 22 do
            swap(_G["ObjectiveTrackerFont" .. i], p, po)
        end
    end

    -- Tooltips (Blizz UI Enhanced): only when customTooltips is on. _ttFonts styles each visible line (size + outline + scale) on show; these only backstop what it misses.
    if IsLoaded("EllesmereUIBlizzardSkin") and (not EllesmereUIDB or EllesmereUIDB.customTooltips ~= false) then
        local p = GetPath("blizzardSkin")
        local po = GetOutline and GetOutline("blizzardSkin")
        swap(_G.GameTooltipText, p, po)
        swap(_G.GameTooltipHeaderText, p, po)
        swap(_G.GameTooltipTextSmall, p, po)
    end
end

-- Outline flag for icon-overlay text (stack counts, durations, keybinds) on action buttons,
-- unit/raid auras, CDM icons and bags. Checked "Outline Icon Text" (default) forces crisp
-- "OUTLINE, SLUG"; unchecked follows the global/per-module outline choice (each of the five modules has its own font key in _addonKeyToFolder).
function EllesmereUI.GetIconTextOutlineFlag(moduleKey)
    local c = EllesmereUI._FontCacheReady().icon
    local k = moduleKey or EllesmereUI._FONT_KEY_GLOBAL
    local hit = c[k]
    if hit then return hit end

    -- Per-profile (rides profile export); the account-global table is the read-time fallback.
    local f = EllesmereUI.GetFontsDB()
    local t = (f and f.outlineIconText) or (EllesmereUIDB and EllesmereUIDB.outlineIconText)
    local flag
    if t and t[moduleKey] == false then
        -- Follows the outline mode, which is already slug-gated at the source.
        flag = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag(moduleKey)) or ""
    else
        -- Forced crisp outline; "Never Show Slug" still drops the slug token.
        flag = EllesmereUI.SlugFlag("OUTLINE, SLUG")
    end
    c[k] = flag
    return flag
end

-- Applies the icon-text outline flag AND the matching shadow in one call. Checked -> "OUTLINE,
-- SLUG", no shadow; unchecked -> the user's outline choice, and when that resolves to "" (Drop Shadow/None) a drop shadow is applied for legibility.
function EllesmereUI.ApplyIconTextFont(fs, fontPath, size, moduleKey)
    if not (fs and fs.SetFont) then return end
    local flag = EllesmereUI.GetIconTextOutlineFlag(moduleKey)
    -- Prime the shadow FontObject before SetFont (see PrimeFontShadow).
    EllesmereUI.PrimeFontShadow(fs, flag == "")
    fs:SetFont(fontPath, size, flag)
end

-- Build font dropdown values/order ("EUI Global Font" first) for W:DualRow configs.
function EllesmereUI.BuildFontDropdownData()
    -- Glyph-restricted locales: bundled Latin fonts cannot render the script (and resolve to the
    -- system font anyway), so pickers offer only "EUI Global Font", "System Default" and external SharedMedia, matching the global font picker.
    if EllesmereUI.LOCALE_FONT_FALLBACK then
        local values = { ["__global"] = { text = "EUI Global Font" },
                         [EllesmereUI.SYSTEM_FONT_KEY] = { text = "System Default", font = EllesmereUI.LOCALE_FONT_FALLBACK },
                         [EllesmereUI.EXPRESSWAY_FORCED_KEY] = { text = "Expressway (Latin only)",
                             font = EllesmereUI.MEDIA_PATH .. "fonts\\Expressway.TTF" } }
        local order  = { "__global", EllesmereUI.SYSTEM_FONT_KEY, EllesmereUI.EXPRESSWAY_FORCED_KEY }
        if EllesmereUI.AppendExternalSharedMediaFonts then
            EllesmereUI.AppendExternalSharedMediaFonts(values, order)
        end
        return values, order
    end
    -- "Blizzard Default" sits right under the inherit entry on unrestricted
    -- locales. Glyph-restricted pickers (branch above) skip it: their "System
    -- Default" entry already IS the client's own font.
    local values = { ["__global"] = { text = "EUI Global Font" },
                     [EllesmereUI.BLIZZARD_FONT_KEY] = { text = "Blizzard Default",
                         font = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" } }
    local order  = { "__global", EllesmereUI.BLIZZARD_FONT_KEY, "---" }
    local FONT_DIR = EllesmereUI.MEDIA_PATH .. "fonts\\"
    for _, name in ipairs(EllesmereUI.FONT_ORDER) do
        if name == "---" then
            order[#order + 1] = "---"
        else
            local path = EllesmereUI.FONT_BLIZZARD[name]
                or (FONT_DIR .. (EllesmereUI.FONT_FILES[name] or "Expressway.TTF"))
            local displayName = (EllesmereUI.FONT_DISPLAY_NAMES and EllesmereUI.FONT_DISPLAY_NAMES[name]) or name
            values[name] = { text = displayName, font = path }
            order[#order + 1] = name
        end
    end
    if EllesmereUI.AppendSharedMediaFonts then
        EllesmereUI.AppendSharedMediaFonts(values, order, { keyByName = true })
    end
    return values, order
end

-- Class color (custom or default) with Class Color Darken baked in by the cache, so every consumer gets the adjusted colour with no per-module logic. Unknown -> white.
function EllesmereUI.GetClassColor(classToken)
    if EllesmereUI._colorCacheDirty then EllesmereUI._RebuildColorCache() end
    return EllesmereUI._colorCache.class[classToken] or EllesmereUI._COLOR_WHITE
end

-- Custom class colour for a unit whose identity is RESTRICTED (target-of-target, focus-target):
-- UnitClass hands back a SECRET token there, and a secret cannot be a table key, so the palette
-- above is unreachable and callers fall back to C_ClassColor.GetClassColor(secretToken) -- right
-- class, but Blizzard's default shade instead of the user's.
-- Such a unit is nearly always someone in the group, whose own token IS readable, so the class
-- can be recovered without ever naming the unit: UnitIsUnit does the identity compare in C (its
-- answer is itself secret when the comparison is restricted) and C_CurveUtil picks between two
-- colour components from that secret boolean, also in C. Lua only ever handles opaque values.
-- Returns ok, r, g, b -- ok is a PLAIN boolean, r/g/b may be SECRET numbers: feed them straight
-- to a setter, never inspect or do arithmetic on them.
--
-- SCOPE, measured in a 12.1 dungeon: under an identity restriction the client will answer "is
-- this unit me?" (CanCompareUnitTokens true, UnitIsUnit a SECRET boolean) and REFUSES every
-- other pairing (CanCompareUnitTokens false, UnitIsUnit returns nil, both argument orders).
-- Refuses by returning nothing, not by erroring, which is why the loop below type-checks the
-- answer instead of trusting it. So in practice this recovers the colour when the restricted
-- unit is the player, and other group members keep Blizzard's shade -- knowing WHICH other
-- player an enemy is on is the exact fact the restriction exists to hide. The roster loop is
-- kept general rather than hardcoded to "player" so it starts working if that ever relaxes.
--
-- Which group members are worth comparing against only changes on a roster or palette edit, so
-- the list is cached as a flat unit/colour array (no per-call allocation, no per-call UnitClass
-- or token concat). Only the compares themselves have to run live.
EllesmereUI._restrictedCandidates = {}
EllesmereUI._restrictedCandidatesDirty = true

-- Namespaced, not file-locals: this chunk sits at Lua's 200-local ceiling.
function EllesmereUI._RebuildRestrictedCandidates()
    local out = EllesmereUI._restrictedCandidates
    wipe(out)
    local customized = EllesmereUI._colorCache.classCustomized
    if next(customized) then
        local inRaid = IsInRaid()
        local members = GetNumGroupMembers() or 0
        -- Raid rosters run raid1..raidN (player included); party rosters are player + party1..N-1.
        local first = inRaid and 1 or 0
        local last  = inRaid and members or (members > 0 and members - 1 or 0)
        for i = first, last do
            local u = (i == 0) and "player" or ((inRaid and "raid" or "party") .. i)
            local _, token = UnitClass(u)
            local col = (type(token) == "string" and not issecretvalue(token)) and customized[token]
            if col then
                out[#out + 1] = u
                out[#out + 1] = col
            end
        end
    end
    EllesmereUI._restrictedCandidatesDirty = false
end

-- Created on the first restricted lookup, so a profile that never needs one never registers it.
function EllesmereUI._EnsureRestrictedRosterWatcher()
    if EllesmereUI._restrictedRosterWatcher then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function() EllesmereUI._restrictedCandidatesDirty = true end)
    EllesmereUI._restrictedRosterWatcher = f
end

function EllesmereUI.GetClassColorForRestrictedUnit(unit, secretClassToken)
    if EllesmereUI._colorCacheDirty then EllesmereUI._RebuildColorCache() end
    if not next(EllesmereUI._colorCache.classCustomized) then return false end
    local pick = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if not (pick and C_ClassColor and C_ClassColor.GetClassColor) then return false end
    EllesmereUI._EnsureRestrictedRosterWatcher()
    if EllesmereUI._restrictedCandidatesDirty then EllesmereUI._RebuildRestrictedCandidates() end
    local candidates = EllesmereUI._restrictedCandidates
    local count = #candidates
    -- Nobody around wears a customised colour: let the caller take Blizzard's shade unchanged.
    if count == 0 then return false end
    local base = C_ClassColor.GetClassColor(secretClassToken)
    if not base then return false end
    local r, g, b = base.r, base.g, base.b
    local canCompare = C_Secrets and C_Secrets.CanCompareUnitTokens
    for i = 1, count, 2 do
        local u = candidates[i]
        -- CanCompareUnitTokens false means UnitIsUnit answers nothing, not that it goes secret.
        if (not canCompare) or canCompare(unit, u) then
            local isSameUnit = UnitIsUnit(unit, u)
            -- Belt and braces: the predicate above should have caught a refusal, and a nil
            -- reaching pick() would throw. type() reports a secret's underlying type, so a
            -- secret boolean -- the whole point of this fold -- passes here.
            if type(isSameUnit) == "boolean" then
                local col = candidates[i + 1]
                r = pick(isSameUnit, col.r, r)
                g = pick(isSameUnit, col.g, g)
                b = pick(isSameUnit, col.b, b)
            end
        end
    end
    return true, r, g, b
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

-- Get power color (cached, darken baked in). Returns nil for unknown keys.
function EllesmereUI.GetPowerColor(powerKey)
    if EllesmereUI._colorCacheDirty then EllesmereUI._RebuildColorCache() end
    return EllesmereUI._colorCache.power[powerKey]
end

-- Multiplier (0-1) for power-COLORED bar backgrounds (Dark Mode "BG Power Color
-- Darken"); stacks on the consumer's resolved power color. 1 = identity (slider at 0).
function EllesmereUI.GetPowerBgDarkenFactor()
    if EllesmereUI._colorCacheDirty then EllesmereUI._RebuildColorCache() end
    return EllesmereUI._powerBgDarkenFactor
end

-- Get resource color (cached, darken baked in). Returns nil for unknown keys.
-- Shares Resource Color Darken with GetClassResourceColor.
function EllesmereUI.GetResourceColor(classToken)
    if EllesmereUI._colorCacheDirty then EllesmereUI._RebuildColorCache() end
    return EllesmereUI._colorCache.resource[classToken]
end

-- Reset colors for a specific class (class color + resource color + power stays)
function EllesmereUI.ResetClassColors(classToken)
    local db = EllesmereUI.GetCustomColorsDB()
    if db.class then db.class[classToken] = nil end
    if db.resource then db.resource[classToken] = nil end
    EllesmereUI.InvalidateColorCache()
end

-- Reset a specific power color
function EllesmereUI.ResetPowerColor(powerKey)
    local db = EllesmereUI.GetCustomColorsDB()
    if db.power then db.power[powerKey] = nil end
    EllesmereUI.InvalidateColorCache()
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

-- Integer power-type -> string key (reverse of POWER_KEY_TO_ENUM). UnitPowerType's 1st return
-- is readable on EVERY unit, so it recovers a color key when the string token (2nd return) is unreadable, as on non-player units (boss/target/focus).
EllesmereUI.POWER_ENUM_TO_KEY = {}
for k, v in pairs(EllesmereUI.POWER_KEY_TO_ENUM) do
    EllesmereUI.POWER_ENUM_TO_KEY[v] = k
end

-- EUI power color (r,g,b or nil) for a unit's CURRENT power. Mirrors oUF's bar ladder so
-- unit-frame TEXT matches the bar on EVERY unit, including non-player:
--   1) Named token -> custom/default color (all standard types; the player lands here).
--   2) NON-STANDARD types (creatures/NPCs) report an unmapped token but an integer type
--      colliding with a standard slot (cosmic energy -> 3 = Energy); the engine returns
--      the REAL color in altR/altG/altB (what oUF paints the bar with), so use it.
--   3) Token unmatched, no alt color, standard integer type -> custom color (safety net).
function EllesmereUI.ResolveUnitPowerColor(unit)
    -- Player: the forced display power type (UF Power Type dropdown) wins over
    -- the real one, resolved live so it never lags a setting or spec change.
    if unit == "player" and EllesmereUI.GetPlayerPowerOverride then
        local override = EllesmereUI.GetPlayerPowerOverride()
        if override ~= nil then
            local overrideKey = EllesmereUI.POWER_ENUM_TO_KEY[override]
            local overrideInfo = overrideKey and EllesmereUI.GetPowerColor(overrideKey)
            if overrideInfo then return overrideInfo.r, overrideInfo.g, overrideInfo.b end
        end
    end
    local pType, pToken, altR, altG, altB = UnitPowerType(unit)
    local info = EllesmereUI.GetPowerColor(pToken)
    if info then return info.r, info.g, info.b end
    if altR then
        -- UnitPowerType may hand back 0-255 or 0-1 ranges; normalize (per oUF).
        if altR > 1 or altG > 1 or altB > 1 then
            return altR / 255, altG / 255, altB / 255
        end
        return altR, altG, altB
    end
    local key = EllesmereUI.POWER_ENUM_TO_KEY[pType]
    info = key and EllesmereUI.GetPowerColor(key)
    if info then return info.r, info.g, info.b end
    return nil
end

-- Apply custom class colors to oUF (call after settings change)
function EllesmereUI.ApplyColorsToOUF()
    -- Universal "colours changed" entry point (swatch edits, resets, global-mode toggle,
    -- Pull Colors From, profile switches), so drop the effective-colour cache here; the
    -- GetClassColor/GetPowerColor reads below rebuild it from the new palette + darken.
    EllesmereUI.InvalidateColorCache()
    -- 1. Update the unit-frame engine's shared color objects. NEVER modify
    -- _G.RAID_CLASS_COLORS: taint.
    local colors = EllesmereUI._UFColors
    if colors then
        if colors.class then
            for classToken, _ in pairs(CLASS_COLOR_MAP) do
                local cc = EllesmereUI.GetClassColor(classToken)
                local entry = colors.class[classToken]
                if entry and entry.SetRGBA then
                    entry:SetRGBA(cc.r, cc.g, cc.b, 1)
                else
                    colors.class[classToken] = CreateColor(cc.r, cc.g, cc.b, 1)
                end
            end
        end
        if colors.power then
            for powerKey, enumVal in pairs(EllesmereUI.POWER_KEY_TO_ENUM) do
                local pc = EllesmereUI.GetPowerColor(powerKey)
                local entry = colors.power[enumVal]
                if entry and entry.SetRGBA then
                    entry:SetRGBA(pc.r, pc.g, pc.b, 1)
                else
                    colors.power[enumVal] = CreateColor(pc.r, pc.g, pc.b, 1)
                end
            end
        end
        if EllesmereUI._UFEngineForceAll then
            EllesmereUI._UFEngineForceAll("ForceUpdate")
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
    -- 6. Refresh damage meters (bars/text class colors)
    if EllesmereUI._DM_RefreshColors then
        EllesmereUI._DM_RefreshColors()
    end
end

-------------------------------------------------------------------------------
--  Manual resource trackers (secret-value safe)
--  Track stacks via UNIT_SPELLCAST_SUCCEEDED instead of reading aura data, which
--  returns secret values in combat. Maelstrom Weapon (344179) and Devourer soul
--  fragment auras (1225789, 1227702) are Blizzard-whitelisted and stay readable.
-------------------------------------------------------------------------------

-- Tip of the Spear tracker (Survival Hunter), talent 260285. Kill Command (259489)
-- grants 1 stack (2 with Primal Surge 1272154). Takedown (1250646) grants 3 when Twin
-- Fangs (1272139) is known and spends one on its impact (1253859), netting 2. Spender
-- abilities consume 1 each. Buff: 10s duration, max 3 stacks.
do
    local stacks, expiresAt = 0, nil
    local MAX = 3
    local DURATION = 10
    local TALENT     = 260285
    local KILL_CMD   = 259489
    local PRIMAL     = 1272154
    local TAKEDOWN     = 1250646
    local TAKEDOWN_HIT = 1253859
    local TWIN_FANG    = 1272139
    local TWIN_FANG_GAIN = 3

    local SPENDERS = {
        [186270]  = true,  -- Raptor Strike
        [265189]  = true,  -- Raptor Strike (ranged)
        [1262293] = true,  -- Raptor Swipe
        [1262343] = true,  -- Raptor Swipe (ranged)
        [259495]  = true,  -- Wildfire Bomb
        [193265]  = true,  -- Hatchet Toss
        [1264949] = true,  -- Chakram
        [1261193] = true,  -- Boomstick
        [TAKEDOWN_HIT] = true,  -- Takedown's impact (only spends without Twin Fangs)
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
            -- Twin Fangs grants 3 and the impact spends one: the cast nets 2 from any
            -- starting count (the grant alone always caps). Both halves resolve here
            -- instead of on the impact event: at melee range both arrive the same frame
            -- and an impact handled first is swallowed by an empty tracker, leaving the
            -- bar a stack high for the buff's full duration.
            stacks = min(MAX, stacks + TWIN_FANG_GAIN) - 1
            expiresAt = GetTime() + DURATION
        elseif SPENDERS[spellID] and stacks > 0 then
            -- With Twin Fangs the cast above already spent for this impact.
            if spellID == TAKEDOWN_HIT and C_SpellBook.IsSpellKnown(TWIN_FANG) then
                return
            end
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

-- Improved Whirlwind tracker (Fury Warrior), required talent 12950. Whirlwind (190411)
-- sets stacks to max; Thunder Clap (6343) / Thunder Blast (435222) also do when Crashing
-- Thunder (436707) is known. Single-target spenders consume 1 each. Buff: 20s, max 4.
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

    -- Bloodthirst/Bloodbath do not consume stacks during Bladestorm with Unhinged
    -- (386628). Tracked via UNIT_SPELLCAST_SUCCEEDED: IsSpellUsable can return secrets.
    local UNHINGED_EXEMPT = { [23881] = true, [335096] = true }
    local bladestormEndsAt = 0

    -- Deduplicate cast events via GUID
    local seenGUID = {}
    local guidCount = 0

    local CRACKLING = 203201  -- Crackling Thunder: widens Thunder Clap / Thunder Blast

    -- Cached IsSpellKnown flags: GetWhirlwindStacks is polled every 0.1s and
    -- HandleWhirlwindStacks runs on every player cast for every class; IsSpellKnown is a
    -- C call and talents cannot change in combat, so resolve once per login/spec/talent
    -- event. Non-warriors never register the watcher: flags stay false and both entry
    -- points early-out on a plain upvalue read.
    local requiredKnown, crashingKnown, unhingedKnown, cracklingKnown = false, false, false, false
    do
        local _, cls = UnitClass("player")
        if cls == "WARRIOR" then
            local function RefreshKnown()
                local sb = C_SpellBook
                requiredKnown  = (sb and sb.IsSpellKnown(REQUIRED)) or false
                crashingKnown  = (sb and sb.IsSpellKnown(CRASHING)) or false
                unhingedKnown  = (sb and sb.IsSpellKnown(UNHINGED)) or false
                cracklingKnown = (sb and sb.IsSpellKnown(CRACKLING)) or false
            end
            local watcher = CreateFrame("Frame")
            watcher:RegisterEvent("PLAYER_LOGIN")
            watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
            watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
            watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
            watcher:SetScript("OnEvent", RefreshKnown)
        end
    end

    -- Improved Whirlwind grants stacks only when the swing connects, but
    -- UNIT_SPELLCAST_SUCCEEDED fires on a whiff too: gate the award on an attackable
    -- living enemy inside the strike radius. Whirlwind is a ~8 yd self-AoE; the index-2
    -- probe (~11 yd) is slightly generous and resolves on hostile nameplates; Thunder
    -- Clap/Blast reach farther with Crackling Thunder. Resolved synchronously at cast
    -- time so a combat-ending kill still counts; with no hostile target it relies on
    -- enemy nameplates showing. InReach is block-scoped (no upvalues) so
    -- EnemyInStrikeRange allocates no closure per cast.
    local function InReach(u, wide)
        if not (UnitExists(u) and UnitCanAttack("player", u) and not UnitIsDead(u)) then
            return false
        end
        return CheckInteractDistance(u, 2) or (wide and CheckInteractDistance(u, 1)) or false
    end
    local function EnemyInStrikeRange(spellID)
        local wide = (spellID == 6343 or spellID == 435222) and cracklingKnown
        if InReach("target", wide) then return true end
        for i = 1, 40 do
            if InReach("nameplate" .. i, wide) then return true end
        end
        return false
    end

    -- Deferred award for casts the probe rejected while MOVING: Whirlwind pressed during
    -- Charge probes while still yards away, but the server resolves the swing at landing
    -- and grants the real buff (unreadable: 85739 is non-whitelisted, so
    -- GetPlayerAuraBySpellID returns nil). The landing IS the event edge: re-run the same
    -- probe once on PLAYER_STOPPED_MOVING inside a short validity window. Registered only
    -- while an award is pending, so the frame is idle everywhere else.
    do
        local _, cls = UnitClass("player")
        if cls == "WARRIOR" then
            local pf = CreateFrame("Frame")
            EllesmereUI._wwPendFrame = pf
            -- Shared resolver, also driven from the cast handler: a strafing melee can
            -- go a whole fight without firing PLAYER_STOPPED_MOVING, so the next GCD cast
            -- is the edge that always exists in combat. A FAILED probe keeps the pending
            -- award armed until the window closes (burning it on one bad probe lost the
            -- refresh, and the stale expiry then cleared live stacks).
            EllesmereUI._wwResolvePend = function()
                local sid = EllesmereUI._wwPendSid
                if not sid then return end
                if GetTime() > (EllesmereUI._wwPendUntil or 0) then
                    EllesmereUI._wwPendSid = nil
                    pf:UnregisterEvent("PLAYER_STOPPED_MOVING")
                    return
                end
                if EnemyInStrikeRange(sid) then
                    EllesmereUI._wwPendSid = nil
                    pf:UnregisterEvent("PLAYER_STOPPED_MOVING")
                    stacks = MAX
                    expiresAt = GetTime() + DURATION
                end
                -- Probe still false inside the window: stay armed.
            end
            pf:SetScript("OnEvent", EllesmereUI._wwResolvePend)
        end
    end

    function EllesmereUI.HandleWhirlwindStacks(event, unit, castGUID, spellID)
        if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
            stacks, expiresAt = 0, nil
            bladestormEndsAt = 0
            wipe(seenGUID)
            guidCount = 0
            if EllesmereUI._wwPendFrame then
                EllesmereUI._wwPendFrame:UnregisterEvent("PLAYER_STOPPED_MOVING")
                EllesmereUI._wwPendSid = nil
            end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            -- Clean up GUID cache on combat end to prevent unbounded growth
            wipe(seenGUID)
            guidCount = 0
            return
        end
        if event ~= "UNIT_SPELLCAST_SUCCEEDED" or unit ~= "player" then return end
        if not requiredKnown then return end

        -- Resolve any pending landing award BEFORE this cast: by the next GCD press the
        -- player is at the target so the re-probe sees what the whiffed-looking generator
        -- hit. Order matters: the pending WW landed first, so a spender drains a fresh 4.
        if EllesmereUI._wwResolvePend then EllesmereUI._wwResolvePend() end

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
            if (spellID == 6343 or spellID == 435222) and not crashingKnown then
                return
            end
            -- Award only if the swing had an enemy to land on; a false probe arms the
            -- landing re-probe instead of dropping the cast (the mid-Charge case).
            if not EnemyInStrikeRange(spellID) then
                local pf = EllesmereUI._wwPendFrame
                if pf then
                    EllesmereUI._wwPendSid = spellID
                    EllesmereUI._wwPendUntil = GetTime() + 1.5
                    pf:RegisterEvent("PLAYER_STOPPED_MOVING")
                end
                return
            end
            local pf = EllesmereUI._wwPendFrame
            if pf then
                pf:UnregisterEvent("PLAYER_STOPPED_MOVING")
                EllesmereUI._wwPendSid = nil
            end
            stacks = MAX
            expiresAt = GetTime() + DURATION
        elseif SPENDERS[spellID] and stacks > 0 then
            -- Unhinged: Bloodthirst/Bloodbath don't consume during Bladestorm
            if UNHINGED_EXEMPT[spellID] and unhingedKnown
               and GetTime() < bladestormEndsAt then
                return
            end
            stacks = max(0, stacks - 1)
            if stacks == 0 then expiresAt = nil end
        end
    end

    -- NO aura validation, same doctrine as Sweeping Strikes below: stack buff 85739 is
    -- non-whitelisted, so GetPlayerAuraBySpellID returns nil even while it is visibly
    -- active. Prediction + the duration timer IS the tracker.
    function EllesmereUI.GetWhirlwindStacks()
        if not requiredKnown then return 0, 0 end
        if expiresAt and GetTime() >= expiresAt then
            stacks, expiresAt = 0, nil
        end
        return stacks, MAX
    end
end

-- Sweeping Strikes tracker (Arms Warrior). 260708 grants 12 charges; single-target
-- damaging abilities spend a charge to strike an extra enemy within ~8 yd, and only when
-- a sweep partner is actually in range. Broad Strokes (1261049): Colossus Smash /
-- Warbreaker grant 6 charges. Buff 30s, cooldown 30s. 12.1: Improved Sweeping Strikes
-- (383155) was REMOVED, so the cap is a flat 18 for everyone; charges from the ability
-- and from Broad Strokes stack normally in any order, so both sources ADD (12 + 6 = the
-- cap) instead of refreshing to max, and either application refreshes the 30s duration.
-- The buff also displays its charge count now, which is what CdmSweepSync reads.
-- Fervor of Battle (202316): Cleave/Whirlwind on 3+ targets also Slams the primary
-- target, and that Slam sweeps and spends a charge.
do
    local stacks, expiresAt = 0, nil
    local MAX_STACKS  = 18    -- 12.1 cap: 12 from the ability + 6 from Broad Strokes
    local SWEEP_GRANT = 12
    local BROAD_GRANT = 6
    local DURATION = 30
    local SWEEP    = 260708
    local BROAD    = 1261049  -- Broad Strokes: Colossus Smash grants 6 charges
    local FERVOR   = 202316   -- Fervor of Battle: Cleave/WW on 3+ targets Slams
    -- Bladestorm: Slayer's Unhinged auto-casts Mortal Strike during it, but those do NOT
    -- consume charges. No CHANNEL events and no 227847: pressing Bladestorm fires
    -- SUCCEEDED 446035 once, then SUCCEEDED 50622 pulses ~every 0.7s with the Unhinged
    -- 12294 casts between pulses. Each pulse extends the suppression window, which only
    -- needs to outlive the pulse gap (plus the trailing Unhinged cast) without eating a
    -- real post-storm Mortal Strike (>= a GCD away).
    local BLADESTORM_IDS = {
        [446035] = true,  -- cast on press
        [50622]  = true,  -- per-pulse tick
        [227847] = true,  -- talent/base cast id, kept in case a variant reports it
    }
    local BLADESTORM_PULSE_GAP = 1.0

    -- Cached IsSpellKnown flags: GetSweepingStrikes is polled every 0.1s and
    -- HandleSweepingStrikes runs on every player cast for every class; IsSpellKnown is a
    -- C call and talents cannot change in combat, so resolve once per login/spec/talent
    -- event. Non-warriors never register the watcher: flags stay false, callers early-out.
    local sweepKnown, broadKnown, fervorKnown = false, false, false
    do
        local _, cls = UnitClass("player")
        if cls == "WARRIOR" then
            local function RefreshKnown()
                local sb = C_SpellBook
                sweepKnown  = (sb and sb.IsSpellKnown(SWEEP)) or false
                broadKnown  = (sb and sb.IsSpellKnown(BROAD)) or false
                fervorKnown = (sb and sb.IsSpellKnown(FERVOR)) or false
            end
            local watcher = CreateFrame("Frame")
            watcher:RegisterEvent("PLAYER_LOGIN")
            watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
            watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
            watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
            watcher:SetScript("OnEvent", RefreshKnown)
        end
    end

    -- Broad Strokes generators (only count with the talent known)
    local CS_GENERATORS = {
        [167105] = true,  -- Colossus Smash
        [262161] = true,  -- Warbreaker (replaces Colossus Smash)
    }

    -- Single-target damaging cast IDs in the Sweeping Strikes affected-spells list,
    -- mapped to charges consumed. Storm Bolt does NOT sweep: deliberately absent.
    local SPENDERS = {
        [12294]   = 1,  -- Mortal Strike
        [7384]    = 1,  -- Overpower
        [1464]    = 1,  -- Slam
        -- Execute: one Arms press fires TWO SUCCEEDED events (260798 + 281000), not
        -- 163201/5308. All four are listed and share the echo guard below so one press
        -- only ever consumes one charge.
        [260798]  = 1,  -- Execute (Arms, real SUCCEEDED id)
        [281000]  = 1,  -- Execute (Arms, paired SUCCEEDED id)
        [163201]  = 1,  -- Execute (Arms, legacy id kept as a fallback)
        [5308]    = 1,  -- Execute (base, kept as a fallback)
        [260643]  = 1,  -- Skullsplitter
        [34428]   = 1,  -- Victory Rush
        [202168]  = 1,  -- Impending Victory
        [1715]    = 1,  -- Hamstring
        [1269383] = 1,  -- Heroic Strike (replaces Slam via Master of Warfare)
        [772]     = 1,  -- Rend: single-target since 12.1, and in 260708's jump-target list
        [436358]  = 2,  -- Demolish: the channel sweeps twice (damage IDs
                        -- 440884/440886) -- confirmed in-game, 2 per cast
    }

    -- Fervor of Battle: the triggered Slam happens on Cleave/Whirlwind casts
    local FOB_TRIGGERS = {
        [1680] = true,  -- Whirlwind (Arms)
        [845]  = true,  -- Cleave
    }
    local fobWindow = 0  -- suppress a possibly-echoed Slam cast event
    -- Execute fires a pair of SUCCEEDED ids per press; the first to spend opens
    -- EllesmereUI._ssExecWindow so the second is skipped (one charge). A field, not a
    -- local: this chunk sits at Lua's 200-local cap.
    local bladestormUntil = 0  -- suppress Sweeping Strikes spends until this time

    -- Deduplicate cast events via GUID
    local seenGUID = {}
    local guidCount = 0

    -- A charge is only consumed when the strike can sweep onto a second enemy. `need` =
    -- enemies required in reach (2 for a sweep partner, 3 for a Fervor of Battle
    -- trigger); relies on enemy nameplates showing for off-target enemies. InReach is
    -- block-scoped (no upvalues) so EnemiesInReach allocates nothing on every spender.
    -- Range gauge: the cleave is player-anchored at ~6 yd (melee), NOT the ~11 yd the
    -- interact probe measures, so an index-2 probe falsely depleted in the 6-11 yd band.
    -- C_Spell.IsSpellInRange on Mortal Strike is a ~5 yd nameplate check that tracks the
    -- cleave (true at 4-5 yd, false past ~6 yd) and is the TIGHTEST primitive resolving
    -- on nameplate units: IsItemInRange does NOT work on nameplates (always false), so
    -- 6/7 yd harm-item checks are unavailable, and CheckInteractDistance bottoms out at
    -- ~9.9 yd. The residual ~1 yd gap is an UNDER-count, the safe direction: the bar
    -- reads slightly full, never empty, and self-heals via CdmSweepSync at the next lull.
    -- IsSpellInRange can answer nil, or a secret value inside instanced content. idx
    -- defaults to the index-2 trade probe.
    local function InReach(u, idx)
        if not (UnitExists(u) and UnitCanAttack("player", u) and not UnitIsDead(u)) then
            return false
        end
        -- The rule (field-measured): a charge is consumed when at least TWO enemies
        -- stand within 8 yd of the PLAYER; the current target is irrelevant. NO legal
        -- probe measures 8 on non-target units: Charge's 8 yd min range evaluates ONLY
        -- against the target token (plate units always read "in min range");
        -- UnitPosition dies in instances (context-dependent fidelity, rejected); the
        -- duel interact probe reaches ~9.9 and falsely drained charges on 8-9.9 bodies
        -- the game refused to cleave. So the gauge is the melee-spell probe ALONE:
        -- hitbox-scaled (~5 yd + combat reach, wider on real mobs than dummies), uniform
        -- in every secret context, and its only error is UNDER-counting partners between
        -- melee reach and 8 yd -- it never fabricates a spend.
        local isr = C_Spell and C_Spell.IsSpellInRange
        if isr then
            -- Resolve the live override id (a talent-replaced base id returns nil).
            local ms = (C_SpellBook and C_SpellBook.FindSpellOverrideByID
                and C_SpellBook.FindSpellOverrideByID(12294)) or 12294
            local r = isr(ms, u)
            if not (issecretvalue and issecretvalue(r)) then
                return r == true
            end
        end
        return false
    end
    local function EnemiesInReach(need, idx)
        local count, targetPlated = 0, false
        for i = 1, 40 do
            local u = "nameplate" .. i
            if InReach(u, idx) then
                count = count + 1
                if UnitIsUnit(u, "target") then targetPlated = true end
                if count >= need then return true end
            end
        end
        -- Target without a visible nameplate still counts as one body
        if not targetPlated and InReach("target", idx) then count = count + 1 end
        return count >= need
    end

    -- CDM child sync state (see CdmSweepSync). cdmSeenActive gates the zero-on-inactive
    -- path and must be re-earned after every activation, so a present-but-never-active
    -- child (buff removed from the tracked set, TBB quirks) can NEVER wipe live stacks.
    local cdmChild, cdmChildCdID, cdmNextScan = nil, nil, 0
    local cdmSeenActive, cdmInactiveSince = false, nil
    local cdmSigDbg, cdmAppsDbg = nil, nil
    local function dbg(...)
        if EllesmereUI._SSDEBUG then print("|cff33ff99[SS]|r", ...) end
    end

    function EllesmereUI.HandleSweepingStrikes(event, unit, castGUID, spellID)
        if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
            stacks, expiresAt = 0, nil
            fobWindow = 0
            bladestormUntil = 0
            cdmSeenActive, cdmInactiveSince = false, nil
            wipe(seenGUID)
            guidCount = 0
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            -- Clean up GUID cache on combat end to prevent unbounded growth
            bladestormUntil = 0  -- safety: Bladestorm can't outlive combat
            wipe(seenGUID)
            guidCount = 0
            return
        end
        if event ~= "UNIT_SPELLCAST_SUCCEEDED" or unit ~= "player" then return end
        if not sweepKnown then return end

        -- Before GUID dedup: every Bladestorm pulse must extend the window,
        -- even if the game reuses a castGUID across pulses.
        if BLADESTORM_IDS[spellID] then
            bladestormUntil = GetTime() + BLADESTORM_PULSE_GAP
            return
        end

        if castGUID and seenGUID[castGUID] then return end
        if castGUID then
            seenGUID[castGUID] = true
            guidCount = guidCount + 1
            -- Safety: flush if table grows too large (shouldn't happen normally)
            if guidCount > 200 then wipe(seenGUID); guidCount = 0 end
        end

        -- Diagnostic-only (_SSDEBUG) trace of the live reach gauge, regardless of stacks.
        if EllesmereUI._SSDEBUG then
            local nm = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or "?"
            local cls = (spellID == SWEEP or (CS_GENERATORS[spellID] and broadKnown)) and "ACTIVATE"
                or (SPENDERS[spellID] and "SPENDER")
                or (FOB_TRIGGERS[spellID] and "FoB")
                or "ignored"
            dbg(("cast %d %s [%s] stacks=%d reach=%s"):format(
                spellID, nm, cls, stacks, tostring(EnemiesInReach(2))))
        end

        if spellID == SWEEP
           or (CS_GENERATORS[spellID] and broadKnown) then
            -- 12.1: both sources stack in any order, so add and clamp at the cap instead
            -- of snapping to max. Casting at 12+ overcaps in-game too and reads as 18.
            local grant = (spellID == SWEEP) and SWEEP_GRANT or BROAD_GRANT
            stacks = min(MAX_STACKS, stacks + grant)
            expiresAt = GetTime() + DURATION
            cdmSeenActive, cdmInactiveSince = false, nil
            dbg("activated: +" .. grant, "->", stacks, "stacks (cast", spellID .. ")")
        elseif FOB_TRIGGERS[spellID] and stacks > 0 and fervorKnown then
            -- Fervor of Battle's triggered Slam is not a player cast event, so it is
            -- counted off the Cleave/WW cast, gated on 3 enemies in reach (with 3+ up a
            -- sweep partner necessarily exists).
            if GetTime() < bladestormUntil then return end
            if not EnemiesInReach(3) then return end
            fobWindow = GetTime() + 0.3
            stacks = max(0, stacks - 1)
            if stacks == 0 then expiresAt = nil end
            dbg("FoB spend (cast", spellID .. "):", stacks, "stacks left")
        elseif SPENDERS[spellID] and stacks > 0 then
            -- Bladestorm window: Unhinged auto-casts Mortal Strike (12294) but the game
            -- consumes no charge, so skip all spends until the window closes.
            if GetTime() < bladestormUntil then return end
            -- Skip an echoed Fervor-of-Battle Slam: the charge was counted above, and a
            -- player-pressed Slam cannot land inside the 0.3s window (GCD). 1269383:
            -- Master of Warfare replaces Slam with Heroic Strike, so the echo uses it.
            if (spellID == 1464 or spellID == 1269383) and GetTime() < fobWindow then return end
            -- Execute's paired second id lands the same frame; skip it so one press = one charge.
            local isExec = spellID == 260798 or spellID == 281000
                or spellID == 163201 or spellID == 5308
            if isExec and GetTime() < (EllesmereUI._ssExecWindow or 0) then return end
            -- No sweep partner in melee range: the game does not cleave, no charge spent.
            if not EnemiesInReach(2) then
                dbg("spend BLOCKED (no reach):", spellID)
                return
            end
            stacks = max(0, stacks - SPENDERS[spellID])
            if stacks == 0 then expiresAt = nil end
            if isExec then EllesmereUI._ssExecWindow = GetTime() + 0.3 end
            dbg("spend APPLIED:", spellID, "->", stacks, "stacks left")
        end
    end

    -- Blizzard's CooldownViewer tracked-buff child for 260708 caches aura state in plain
    -- frame fields even though C_UnitAuras refuses this aura: presence via
    -- wasSetFromAura/auraInstanceID/IsShown, count via auraDataCached.applications
    -- (plain out of restricted combat, secret inside it). It feeds two fail-open
    -- corrections prediction cannot make: zero on a confirmed early drop (/cancelaura),
    -- and drift resync whenever the count reads plain. CDM disabled or buff untracked ->
    -- no child is ever found and prediction is unchanged.

    local function CdmInfoMatches(info)
        if not info then return false end
        if info.spellID == SWEEP or info.overrideSpellID == SWEEP then return true end
        local linked = info.linkedSpellIDs
        if linked then
            for i = 1, #linked do
                if linked[i] == SWEEP then return true end
            end
        end
        return false
    end
    local function FindCdmChild()
        local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
        if not gci then return nil end
        local function ScanViewer(viewer)
            local pool = viewer and viewer.itemFramePool
            if not pool then return nil end
            for frame in pool:EnumerateActive() do
                local cdID = frame.cooldownID
                if cdID and CdmInfoMatches(gci(cdID)) then return frame end
            end
        end
        return ScanViewer(_G.BuffIconCooldownViewer) or ScanViewer(_G.BuffBarCooldownViewer)
    end

    local function CdmSweepSync(now)
        local child = cdmChild
        -- Pooled frames get re-acquired for other spells; a moved cooldownID invalidates the cache.
        if child and child.cooldownID ~= cdmChildCdID then
            child, cdmChild = nil, nil
        end
        if not child then
            if now < cdmNextScan then return end
            cdmNextScan = now + 1
            child = FindCdmChild()
            if not child then return end
            cdmChild, cdmChildCdID = child, child.cooldownID
            dbg("CDM child found:", child:GetName() or tostring(child),
                "cdID", cdmChildCdID)
        end

        -- OR of every presence signal on purpose: a stuck-true signal only makes the
        -- inactive branch unreachable, while trusting one that clears early wipes stacks.
        local shown = child:IsShown()
        local wsfa = child.wasSetFromAura == true
        local iid = child.auraInstanceID ~= nil
        if EllesmereUI._SSDEBUG then
            local sig = (shown and "S" or "-") .. (wsfa and "W" or "-")
                .. (iid and "I" or "-")
            if sig ~= cdmSigDbg then
                cdmSigDbg = sig
                dbg("signals:", sig, "(S=shown W=wasSetFromAura I=auraInstanceID)")
            end
        end
        local active = shown or wsfa or iid
        if active then
            cdmInactiveSince = nil
            if not cdmSeenActive then
                cdmSeenActive = true
                dbg("CDM child active: shown=" .. tostring(shown)
                    .. " wsfa=" .. tostring(child.wasSetFromAura)
                    .. " iid=" .. tostring(child.auraInstanceID ~= nil))
            end
            local ad = child.auraDataCached
            local apps = ad and ad.applications
            if EllesmereUI._SSDEBUG then
                local state
                if not ad then state = "no-cache"
                elseif apps == nil then state = "no-apps"
                elseif issecretvalue(apps) then state = "secret"
                else state = tostring(apps) end
                if state ~= cdmAppsDbg then
                    cdmAppsDbg = state
                    dbg("apps:", state, "(predicted " .. stacks .. ")")
                end
            end
            if apps and not issecretvalue(apps) and type(apps) == "number"
               and apps ~= stacks then
                dbg("snap:", stacks, "->", apps)
                stacks = apps
                local exp = ad.expirationTime
                if exp and not issecretvalue(exp) and type(exp) == "number"
                   and exp > now then
                    expiresAt = exp
                elseif not expiresAt then
                    expiresAt = now + DURATION
                end
            end
        elseif cdmSeenActive and stacks > 0 then
            -- Debounce: aura refreshes blink the child inactive for a frame during re-acquire.
            if not cdmInactiveSince then
                cdmInactiveSince = now
            elseif now - cdmInactiveSince > 0.3 then
                dbg("CDM child inactive -> buff gone, clearing", stacks, "stacks")
                stacks, expiresAt = 0, nil
                cdmSeenActive, cdmInactiveSince = false, nil
            end
        end
    end

    -- NO aura validation here, on purpose. Validating drift against the real buff (by
    -- name or C_UnitAuras.GetPlayerAuraBySpellID) treats a missing aura as "buff gone"
    -- and wipes the stacks, but 260708 is NOT whitelisted and non-whitelisted player
    -- buffs are invisible to the aura read surface (with the buff visibly active,
    -- GetPlayerAuraBySpellID(260708) returns nil and a GetAuraDataByIndex("player", i,
    -- "HELPFUL") sweep enumerates zero auras), so any validation zeroes the bar (wiped
    -- in combat, pinned at 0 in M+). Whitelisted buffs ARE readable: see
    -- GetMaelstromWeapon / GetSoulFragments below and the NON_SECRET_SPELL_IDS catalogue
    -- + C_Secrets.ShouldSpellAuraBeSecret probe in EllesmereUIAuraBuffReminders. Until
    -- Blizzard whitelists 260708, cast prediction + the duration timer IS the tracker.
    -- CdmSweepSync is NOT that validation: it reads Blizzard's own widget, corrects only
    -- on positive evidence, and degrades to pure prediction when the widget is absent.
    function EllesmereUI.GetSweepingStrikes()
        if not sweepKnown then return 0, 0 end
        local now = GetTime()
        CdmSweepSync(now)
        if expiresAt and now >= expiresAt then
            stacks, expiresAt = 0, nil
        end
        -- Clamp: the cap is a flat 18 since 12.1, but a CDM snap reads Blizzard's own
        -- count, so keep the readout inside the bar's pip count either way.
        if stacks > MAX_STACKS then stacks = MAX_STACKS end
        return stacks, MAX_STACKS
    end
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
--    linkedKeys (table)  list of element keys that move with this one
--    noResize   (boolean) true for Blizzard elements that cannot be resized
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
        linkedKeys    = opts.linkedKeys,
        noResize          = opts.noResize,
        linkedDimensions  = opts.linkedDimensions,
        -- noInitHook: self-positioning element; ApplySavedPositions /
        -- NotifyElementResized (EUI_UnlockMode) must not re-apply its stored position.
        noInitHook        = opts.noInitHook,
        noAnchorTarget    = opts.noAnchorTarget,
        noAnchorTo        = opts.noAnchorTo,
        -- allowMatchSource: show the width/height MATCH buttons even when resize is
        -- disabled (noResize), so the element can size-match TO another element.
        -- noSizeMatchTarget: other elements may NOT size-match TO this one.
        allowMatchSource  = opts.allowMatchSource,
        noSizeMatchTarget = opts.noSizeMatchTarget,
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
        return EllesmereUIDB and EllesmereUIDB.activeTheme or "EllesmereUI"
    end
end

-------------------------------------------------------------------------------
--  Load-order stub: ResolveActiveAccent -- the real one (and its ResolveProfileAccent /
--  GetActiveProfileData helpers) lives in EllesmereUI_UICore.lua, which loads right after
--  this file; mirrors ResolveProfileAccent's resolution order so the accent matches.
-------------------------------------------------------------------------------
if not EllesmereUI.ResolveActiveAccent then
    EllesmereUI.ResolveActiveAccent = function()
        local theme = (EllesmereUIDB and EllesmereUIDB.activeTheme) or "EllesmereUI"
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
        c = { names = names, order = order, castBarNames = castBarNames, textures = textures }
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
    local ok, reason = C_AddOns.LoadAddOn("EllesmereUIOptions")
    if not ok then
        EllesmereUI.Print("|cffff6060[EllesmereUI]|r Options could not load (" .. tostring(reason) .. "). Enable the \"EllesmereUI Options\" addon in the AddOn List.")
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
    for i, fn in ipairs(self._deferredInits) do
        fn()
        self._deferredInits[i] = nil
    end
end

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
-- moves INVERSELY with UI scale, nor grows QUADRATICALLY with the panel-scale dropdown; px/unit
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
local function WirePopupEscape(popup, dimmer)
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
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

    -- Popups render at default UI scale (dimmer stays at 1 to cover the full screen).

    -- Background: flat dark default, optional stone atlas for modern style
    local popBgFlat = SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 1)
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
    local BTN_W, BTN_H = 125, 27
    local BTN_GAP = 16
    local BTN_Y = 13
    local FADE_DUR = 0.1

    -- Styled popup button: sized 2px larger than the visual area, bg inset 1px so the full-button border texture peeks out as a 1px border on all sides.
    local function MakePopupButton(parent, anchorPoint, anchorTo, anchorRef, xOff, yOff, defR, defG, defB, defA, hovR, hovG, hovB, hovA, bDefR, bDefG, bDefB, bDefA, bHovR, bHovG, bHovB, bHovA)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(BTN_W, BTN_H)
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

    -- Optional checkbox (above buttons, centered)
    local cbRow = CreateFrame("Button", nil, popup)
    cbRow:SetSize(POPUP_W - 60, 18)
    cbRow:SetPoint("BOTTOM", popup, "BOTTOM", 0, BTN_Y + BTN_H + 10)
    cbRow:SetFrameLevel(popup:GetFrameLevel() + 2)

    local cbBox = CreateFrame("Frame", nil, cbRow)
    cbBox:SetSize(14, 14)
    cbBox:SetPoint("LEFT", cbRow, "LEFT", 0, 0)
    cbBox:SetFrameLevel(cbRow:GetFrameLevel() + 1)
    local cbBoxBg = SolidTex(cbBox, "BACKGROUND", 0.075, 0.113, 0.141, 1)
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

    -- Optional type-to-confirm gate (lazy, like the macro overlay): the user must type the given
    -- word (case-insensitive) before confirm accepts clicks. NOT supported with confirmMacro (secure overlay clicks cannot be gated).
    local typeH = 0
    popup._typeGateOn = nil
    if opts.typeToConfirm then
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
                self:ClearFocus()
                if popup._typeGateOk then
                    local click = popup._confirmBtn:GetScript("OnClick")
                    if click then click(popup._confirmBtn) end
                end
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
        -- The base height affords roughly three message lines; gated popups carry long warnings, so grow by the measured overflow too.
        local extra = popup._msg:GetStringHeight() or 0
        if opts.disclaimer then
            extra = extra + (popup._disclaimer:GetStringHeight() or 0) + 8
        end
        typeH = 36 + math.max(0, extra - 44)
    elseif popup._typeRow then
        popup._typeRow._box:ClearFocus()
        popup._typeRow:Hide()
    end

    popup:SetHeight((popup._baseH or 176) + scaleWarnH + cbH + typeH)
    popup._cancelBtn._lbl:SetText(EllesmereUI.L(opts.cancelText or "Cancel"))
    popup._confirmBtn._lbl:SetText(EllesmereUI.L(opts.confirmText or "Confirm"))
    -- onDismiss: called on escape/click-outside. Falls back to onCancel if not provided.
    popup._onCancel = opts.onDismiss or opts.onCancel or nil
    popup._modal = opts.modal and true or false

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

    -- Reset hover states
    popup._cancelBtn._resetAnim()
    popup._confirmBtn._resetAnim()
    popup._confirmBtn:SetAlpha(popup._typeGateOn and 0.3 or 1)

    popup._cancelBtn:SetScript("OnClick", function()
        popup._dimmer:Hide()
        if opts.onCancel then opts.onCancel() end
    end)

    -- Macro overlay: protected actions (/logout) need a hardware event routed through InsecureActionButtonTemplate.
    if opts.confirmMacro then
        if not popup._macroOverlay then
            local ov = CreateFrame("Button", "EUIConfirmMacroOverlay", popup._confirmBtn, "InsecureActionButtonTemplate")
            ov:SetAllPoints(popup._confirmBtn)
            ov:SetFrameLevel(popup._confirmBtn:GetFrameLevel() + 5)
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
        if popup._macroOverlay then popup._macroOverlay:Hide() end
        popup._confirmBtn:SetScript("OnClick", function()
            if popup._typeGateOn and not popup._typeGateOk then return end
            popup._dimmer:Hide()
            if opts.onConfirm then opts.onConfirm(popup._cbChecked) end
        end)
    end

    -- Counter-scale the popup to the options panel when the pixel-perfect system has rescaled UIParent; the dimmer stays at 1 so it still covers the full screen.
    local mf = EllesmereUI._mainFrame
    if mf and mf:GetScale() ~= 1 then
        popup:SetScale(mf:GetScale())
    else
        popup:SetScale(1)
    end


    popup._dimmer:Show()
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
    contentFS:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
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
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
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
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
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
        local maxScroll = EllesmereUI.SafeScrollRange(sf)
        scrollTarget = math.max(0, math.min(maxScroll, target))
        if not isSmoothing then
            isSmoothing = true
            smoothFrame:Show()
        end
    end

    sf:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = EllesmereUI.SafeScrollRange(self)
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
            local maxScroll = EllesmereUI.SafeScrollRange(sf)
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

    popup._title:SetText(EllesmereUI.L(opts.title or "Information"))
    popup._contentFS:SetText(EllesmereUI.L(opts.content) or "")

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

        local popBgFlat = SolidTex(popup, "BACKGROUND", 0.06, 0.08, 0.10, 1)
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

        local BTN_W, BTN_H = 125, 27
        local BTN_GAP = 16
        local BTN_Y = 18
        local FADE_DUR = 0.1

        local function MakePopupButton(parent, anchorPoint, anchorTo, anchorRef, xOff, yOff, defR, defG, defB, defA, hovR, hovG, hovB, hovA, bDefR, bDefG, bDefB, bDefA, bHovR, bHovG, bHovB, bHovA)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(BTN_W, BTN_H)
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

    popup:SetHeight(194 + extraH + warnH + scaleWarnH)

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
        -- Recalculate pixel-perfect base scale on every open so resolution / UIParent scale changes apply
        local physW2 = (GetPhysicalScreenSize())
        local baseScale2 = GetScreenWidth() / physW2
        local userScale2 = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
        mainFrame:SetScale(baseScale2 * userScale2)
        -- Re-sync PanelPP mult for the (possibly new) scale
        if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end
        -- Panel borders are resnapped by the tab-switch ResnapBordersUnder (active page only, ~2ms);
        -- a global ResnapAllBorders here costs ~74ms and is unnecessary, since non-panel borders have their own scale and resnap triggers.
        for _, fn in ipairs(_onShowCallbacks) do fn() end
    end)
    mainFrame:SetScript("OnHide", function()
        -- Close the sidebar sync popup so it never lingers after the window is dismissed.
        if EllesmereUI.CloseSyncPopup then EllesmereUI.CloseSyncPopup() end
        if _onHideCallbacks then
            for _, fn in ipairs(_onHideCallbacks) do fn() end
        end
        -- Free cached pages for non-active tabs; keep the active one so reopening matches.
        if _pageCache then
            local activeKey = activeModule and activePage and (activeModule .. "::" .. activePage)
            for key, entry in pairs(_pageCache) do
                if key ~= activeKey then
                    if entry.wrapper then
                        entry.wrapper:Hide()
                        entry.wrapper:SetParent(nil)
                    end
                    _pageCache[key] = nil
                end
            end
        end
        _activePageWrapper = nil
    end)

    -- Pixel-perfect scale: make 1 WoW unit = 1 screen pixel
    local physW = (GetPhysicalScreenSize())
    local baseScale = GetScreenWidth() / physW
    local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
    mainFrame:SetScale(baseScale * userScale)
    -- Initialize PanelPP mult for the saved user scale
    if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end

    EllesmereUI.RegisterEscapeClose(mainFrame)

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

    -- Two crossfade layers (A = current, B = incoming). Only the active layer holds a
    -- texture; the idle one is cleared after each transition to free GPU memory.
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

    -- Accent hue via desaturate + vertex tint: base images are teal, so desaturating
    -- removes the hue and vertex color re-tints to the chosen accent. Horde/Alliance
    -- have dedicated background images and are used as-is (never desaturated/tinted).
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

    -- Background crossfade ticker: old stays solid, new fades in on top with the same
    -- ease-in-out curve as the accent transition, so both animations track visually.
    local bgFadeTicker = CreateFrame("Frame", nil, bgFrame)
    bgFadeTicker:Hide()
    bgFadeTicker:SetScript("OnUpdate", function(self, elapsed)
        bgFadeProgress = bgFadeProgress + elapsed / BG_FADE_DURATION
        if bgFadeProgress >= 1 then
            bgFadeProgress = 1
            bgFront:SetAlpha(1)
            -- bgBack stays solid behind bgFront (occluded, zero cost). NEVER clear it
            -- here (single-frame flash); the next ApplyThemeBG replaces its texture.
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

        -- New front layer gets the target texture + tint on top; this SetTexture is also
        -- the lazy cleanup of the previous transition's idle layer.
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
    -- Resolve theme color directly -- ELLESMERE_GREEN is the UI accent which may differ
    local _initTheme = ResolveFactionTheme((EllesmereUIDB or {}).activeTheme or "EllesmereUI")
    local _initFile = THEME_BG_FILES[_initTheme] or THEME_BG_FILES["EllesmereUI"]
    local _initR, _initG, _initB = EllesmereUI.ResolveThemeColor(_initTheme)
    bgA:SetTexture(MEDIA_PATH .. _initFile)
    ApplyBgTintToLayer(bgA, _initTheme, _initR, _initG, _initB)
    EllesmereUI._bgTexture = bgA
    EllesmereUI._applyBgTint = ApplyBgTint
    EllesmereUI._applyThemeBG = ApplyThemeBG

    -----------------------------------------------------------------------
    --  Click area  (1300x946, centred)
    -----------------------------------------------------------------------
    clickArea = CreateFrame("Frame", "EllesmereUIClickArea", mainFrame)
    EllesmereUI._clickArea = clickArea
    clickArea:SetSize(CLICK_W, CLICK_H)
    clickArea:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
    clickArea:SetFrameLevel(mainFrame:GetFrameLevel() + 1)
    clickArea:EnableMouse(true)
    clickArea:SetMovable(true)
    clickArea:RegisterForDrag("LeftButton")
    -- No SetClampedToScreen: the whole window moves as one and drags freely off any edge.
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
    EllesmereUI._sidebar = sidebar

    -- Nav buttons -- start below the logo area with proper spacing
    local NAV_TOP     = -114   -- distance from sidebar top to first nav item
    local NAV_ROW_H   = 40    -- height per nav row (Unlock / Global / Patch Notes / Profiles)
    local NAV_ICON_W  = 46    -- exact pixel width
    local NAV_ICON_H  = 31    -- exact pixel height
    local NAV_LEFT    = 20    -- left padding for icon
    local NAV_TXT_GAP = 10    -- gap between icon and label

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

    -- Horizontal gradient glow on a sidebar button, anchored top+bottom so it scales
    -- with the row height (group headers and child rows differ).
    local function MakeNavGradient(btn, r, g, b, startA)
        local tex = btn:CreateTexture(nil, "BACKGROUND")
        tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
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
        btn._indicator:SetWidth(3)
        btn._indicator:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 0)
        btn._indicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -1, 0)
        btn._indicator:Hide()
        RegAccent({ type="solid", obj=btn._indicator, a=1 })

        btn._glow    = MakeNavGradient(btn, EG.r, EG.g, EG.b, 0.15)
        RegAccent({ type="gradient", obj=btn._glow, startA=0.15 })
        btn._glowTop = MakeNavEdgeLine(btn, "TOP")
        btn._glowBot = MakeNavEdgeLine(btn, "BOTTOM")

        local hR, hG, hB = 0.85, 0.95, 0.90
        btn._hoverGlow = MakeNavGradient(btn, hR, hG, hB, 0.03)
        btn._hoverIndicator = SolidTex(btn, "ARTWORK", hR, hG, hB, 0.25)
        btn._hoverIndicator:SetWidth(3)
        btn._hoverIndicator:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 0)
        btn._hoverIndicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -1, 0)
        btn._hoverIndicator:Hide()
    end

    -------------------------------------------------------------------
    --  Unlock Mode button  (always top, not a module -- just triggers unlock)
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

        local label = MakeFont(btn, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText(EllesmereUI.L("Unlock Mode"))
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

        -- One-time tutorial tip: play badge opening the Unlock Mode video guide, retired
        -- once clicked. VideoGuides owns all gating (per-account seen map + the Enable
        -- Tutorial Tips setting); nil-guarded for standalone builds.
        if EllesmereUI.VideoGuides and EllesmereUI.VideoGuides.AttachTip then
            EllesmereUI.VideoGuides.AttachTip(btn, "unlock_mode", {
                tooltip = "Video Guide: Unlock Mode",
                x = -12,
            })
        end
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

        local label = MakeFont(btn, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText(EllesmereUI.L("Global Settings"))
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
            if self._ovLocked then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "This module can't be overridden. Exit the override editing session to open it.")
                end
                return
            end
            hlTex:SetAlpha(0.06)
            if activeModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            if self._ovLocked then return end
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if activeModule ~= self._folder then
                self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnClick", function(self)
            if self._ovLocked then return end
            if modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        sidebarButtons[GLOBAL_KEY] = btn
    end

    -------------------------------------------------------------------
    --  Patch Notes button  (own page -- selects the _EUIPatchNotes module)
    -------------------------------------------------------------------
    do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, NAV_ROW_H)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, NAV_TOP - NAV_ROW_H * 2)
        btn:SetFrameLevel(sidebar:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        -- Glow layer (behind icon): tinted version of the -on texture
        local iconGlow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        iconGlow:SetTexture(ICONS_PATH .. "sidebar\\notes-on.png")
        iconGlow:SetSize(NAV_ICON_W, NAV_ICON_H)
        iconGlow:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        iconGlow:SetDesaturated(true)
        iconGlow:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
        iconGlow:Hide()
        btn._iconGlow = iconGlow
        RegAccent({ type="vertex", obj=iconGlow })

        -- Icon layer (on top of glow): always the white off texture
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(ICONS_PATH .. "sidebar\\notes-off.png")
        icon:SetSize(NAV_ICON_W, NAV_ICON_H)
        icon:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        btn._icon    = icon
        btn._iconOn  = ICONS_PATH .. "sidebar\\notes-on.png"
        btn._iconOff = ICONS_PATH .. "sidebar\\notes-off.png"

        local label = MakeFont(btn, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText(EllesmereUI.L("Patch Notes"))
        btn._label = label

        label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        icon:SetDesaturated(false)
        icon:SetAlpha(NAV_ENABLED_ICON_A)

        btn._folder = "_EUIPatchNotes"
        btn._loaded = true

        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            if self._ovLocked then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "This module can't be overridden. Exit the override editing session to open it.")
                end
                return
            end
            hlTex:SetAlpha(0.06)
            if activeModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            if self._ovLocked then return end
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if activeModule ~= self._folder then
                self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnClick", function(self)
            if self._ovLocked then return end
            -- Opening Patch Notes consumes the new-patch reminder dot; it
            -- re-arms only on the next version increase.
            if EllesmereUIDB and EllesmereUIDB.patchDotPending then
                EllesmereUIDB.patchDotPending = nil
                if EllesmereUI._UpdatePatchDot then EllesmereUI._UpdatePatchDot() end
            end
            if modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        -- Pulsing "new patch" dot: shown while patchDotPending is raised (version-increase
        -- stamp near EllesmereUI.VERSION) and patchDotDisabled is unset. Built lazily.
        local dot
        EllesmereUI._UpdatePatchDot = function()
            local show = EllesmereUIDB and EllesmereUIDB.patchDotPending
                and not EllesmereUIDB.patchDotDisabled and true or false
            if not dot then
                if not show then return end
                dot = CreateFrame("Frame", nil, btn)
                dot:SetFrameLevel(btn:GetFrameLevel() + 5)
                dot:SetSize(9, 9)
                dot:SetPoint("RIGHT", btn, "RIGHT", -14, 0)
                local t = dot:CreateTexture(nil, "OVERLAY")
                t:SetAllPoints()
                t:SetColorTexture(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
                -- Round: run the solid color through the portrait circle mask.
                local mask = dot:CreateMaskTexture()
                mask:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga",
                    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(t)
                t:AddMaskTexture(mask)
                local ag = dot:CreateAnimationGroup()
                ag:SetLooping("REPEAT")
                local a1 = ag:CreateAnimation("Alpha")
                a1:SetFromAlpha(1); a1:SetToAlpha(0.35)
                a1:SetDuration(0.7); a1:SetOrder(1); a1:SetSmoothing("IN_OUT")
                local a2 = ag:CreateAnimation("Alpha")
                a2:SetFromAlpha(0.35); a2:SetToAlpha(1)
                a2:SetDuration(0.7); a2:SetOrder(2); a2:SetSmoothing("IN_OUT")
                dot._ag = ag
            end
            dot:SetShown(show)
            if show then dot._ag:Play() else dot._ag:Stop() end
        end
        EllesmereUI._UpdatePatchDot()

        sidebarButtons["_EUIPatchNotes"] = btn
        EllesmereUI._patchNotesSidebarBtn = btn
    end

    -------------------------------------------------------------------
    --  Profiles & Presets button  (own page -- selects the _EUIProfiles module)
    -------------------------------------------------------------------
    do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, NAV_ROW_H)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, NAV_TOP - NAV_ROW_H * 3)
        btn:SetFrameLevel(sidebar:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        -- Glow layer (behind icon): tinted version of the -on texture
        local iconGlow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
        iconGlow:SetTexture(ICONS_PATH .. "sidebar\\profiles-on.png")
        iconGlow:SetSize(NAV_ICON_W, NAV_ICON_H)
        iconGlow:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        iconGlow:SetDesaturated(true)
        iconGlow:SetVertexColor(ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 1)
        iconGlow:Hide()
        btn._iconGlow = iconGlow
        RegAccent({ type="vertex", obj=iconGlow })

        -- Icon layer (on top of glow): always the white off texture
        local icon = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(ICONS_PATH .. "sidebar\\profiles-off.png")
        icon:SetSize(NAV_ICON_W, NAV_ICON_H)
        icon:SetPoint("LEFT", btn, "LEFT", NAV_LEFT, 0)
        btn._icon    = icon
        btn._iconOn  = ICONS_PATH .. "sidebar\\profiles-on.png"
        btn._iconOff = ICONS_PATH .. "sidebar\\profiles-off.png"

        local label = MakeFont(btn, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", icon, "RIGHT", NAV_TXT_GAP, 0)
        label:SetText(EllesmereUI.L("Profiles & Presets"))
        btn._label = label

        label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        icon:SetDesaturated(false)
        icon:SetAlpha(NAV_ENABLED_ICON_A)

        btn._folder = "_EUIProfiles"
        btn._loaded = true

        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            if self._ovLocked then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "This module can't be overridden. Exit the override editing session to open it.")
                end
                return
            end
            hlTex:SetAlpha(0.06)
            if activeModule ~= self._folder then
                self._hoverGlow:Show()
                self._hoverIndicator:Show()
                self._label:SetTextColor(NAV_HOVER_ENABLED_TEXT.r, NAV_HOVER_ENABLED_TEXT.g, NAV_HOVER_ENABLED_TEXT.b, NAV_HOVER_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            if self._ovLocked then return end
            hlTex:SetAlpha(0)
            self._hoverGlow:Hide()
            self._hoverIndicator:Hide()
            if activeModule ~= self._folder then
                self._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
            end
        end)
        btn:SetScript("OnClick", function(self)
            if self._ovLocked then return end
            if modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        sidebarButtons["_EUIProfiles"] = btn
        EllesmereUI._profilesSidebarBtn = btn
    end

    -- First addon starts four rows down (Unlock, Global, Patch Notes, Profiles & Presets)
    local ORIG_ADDON_NAV_TOP = NAV_TOP - NAV_ROW_H * 4

    -----------------------------------------------------------------------
    --  Sidebar search bar (filters addon list by display name or page name)
    -----------------------------------------------------------------------
    local SB_TOP_PAD     = 13   -- gap between Profiles & Presets and the search bar
    local SB_H           = 28
    local SB_BOT_PAD     = 6
    local SB_SIDE_INSET  = 20
    local SB_TOTAL       = SB_TOP_PAD + SB_H + SB_BOT_PAD

    local sidebarSearchFrame = CreateFrame("Frame", nil, sidebar)
    sidebarSearchFrame:SetSize(SIDEBAR_W - SB_SIDE_INSET * 2, SB_H)
    sidebarSearchFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", SB_SIDE_INSET + 2, ORIG_ADDON_NAV_TOP - SB_TOP_PAD)
    sidebarSearchFrame:SetFrameLevel(sidebar:GetFrameLevel() + 3)

    local sbBg = SolidTex(sidebarSearchFrame, "BACKGROUND",
        EllesmereUI.SL_INPUT_R, EllesmereUI.SL_INPUT_G, EllesmereUI.SL_INPUT_B, EllesmereUI.SL_INPUT_A + 0.10)
    sbBg:SetAllPoints()
    local sbBrd = MakeBorder(sidebarSearchFrame,
        EllesmereUI.BORDER_R, EllesmereUI.BORDER_G, EllesmereUI.BORDER_B, 0.10)

    local sbEdit = CreateFrame("EditBox", nil, sidebarSearchFrame)
    sbEdit:SetAllPoints()
    sbEdit:SetAutoFocus(false)
    sbEdit:SetFont(EllesmereUI.EXPRESSWAY, 13, "")
    sbEdit:SetTextColor(1, 1, 1, 1)
    sbEdit:SetTextInsets(10, 24, 0, 0)
    sbEdit:SetMaxLetters(40)

    local sbPlaceholder = MakeFont(sidebarSearchFrame, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.3)
    sbPlaceholder:SetPoint("LEFT", sidebarSearchFrame, "LEFT", 10, 0)
    sbPlaceholder:SetText(EllesmereUI.L("Search Features..."))

    local sbClearBtn = CreateFrame("Button", nil, sidebarSearchFrame)
    sbClearBtn:SetSize(20, 20)
    sbClearBtn:SetPoint("RIGHT", sidebarSearchFrame, "RIGHT", -4, 0)
    sbClearBtn:SetFrameLevel(sbEdit:GetFrameLevel() + 2)
    sbClearBtn:Hide()
    local sbClearLabel = MakeFont(sbClearBtn, 15, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.35)
    sbClearLabel:SetPoint("CENTER")
    sbClearLabel:SetText("x")
    sbClearBtn:SetScript("OnEnter", function() sbClearLabel:SetTextColor(1, 1, 1, 1) end)
    sbClearBtn:SetScript("OnLeave", function() sbClearLabel:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.35) end)
    sbClearBtn:SetScript("OnClick", function()
        sbEdit:SetText("")
        sbEdit:ClearFocus()
    end)

    local function _sbBorderHover(a) sbBrd:SetColor(EllesmereUI.BORDER_R, EllesmereUI.BORDER_G, EllesmereUI.BORDER_B, a) end
    sidebarSearchFrame:SetScript("OnEnter", function() _sbBorderHover(0.15) end)
    sidebarSearchFrame:SetScript("OnLeave", function() _sbBorderHover(0.10) end)
    sbEdit:SetScript("OnEditFocusGained", function() _sbBorderHover(0.15) end)
    sbEdit:SetScript("OnEditFocusLost", function() _sbBorderHover(0.10) end)
    sbEdit:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    sbEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    EllesmereUI._sidebarSearchBox = sbEdit
    EllesmereUI._sidebarSearchText = ""

    sbEdit:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text == "" then
            sbPlaceholder:Show()
            sbClearBtn:Hide()
        else
            sbPlaceholder:Hide()
            sbClearBtn:Show()
        end
        EllesmereUI._sidebarSearchText = text
        -- Deliberately NO sidebar filtering here: the global search results popup
        -- (EllesmereUI_GlobalSearch.lua) lists matches without reshuffling the nav.
    end)

    -- Addon scroll area sits below the search bar
    local ADDON_NAV_TOP = ORIG_ADDON_NAV_TOP - SB_TOTAL

    -----------------------------------------------------------------------
    --  Scrollable addon nav container
    --  The roster exceeds the space between ADDON_NAV_TOP and the class art, so addon
    --  buttons live in a ScrollFrame with smooth wheel scrolling and a thin right thumb.
    -----------------------------------------------------------------------
    local ADDON_VISIBLE_ROWS    = 12   -- nav rows shrank to 40px; bump count so the addon viewport still fills to the bottom
    -- +30 = 20px viewport bonus plus 10px offsetting the SB_TOP_PAD bump, so growing the
    -- search-bar padding cannot shrink the viewport. ARROW_RESERVE = strip for the arrow.
    local ADDON_ARROW_RESERVE   = 24
    local ADDON_SCROLL_H        = ADDON_VISIBLE_ROWS * NAV_ROW_H - SB_TOTAL + 30 - ADDON_ARROW_RESERVE
    local ADDON_SCROLL_STEP     = 60   -- match the main content scroll
    local ADDON_SMOOTH_SPEED    = 12   -- match the main content scroll

    local addonScrollFrame = CreateFrame("ScrollFrame", nil, sidebar)
    addonScrollFrame:SetWidth(SIDEBAR_W)
    addonScrollFrame:SetHeight(ADDON_SCROLL_H)
    addonScrollFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, ADDON_NAV_TOP)
    addonScrollFrame:SetFrameLevel(sidebar:GetFrameLevel() + 1)
    addonScrollFrame:EnableMouseWheel(true)
    addonScrollFrame:SetClipsChildren(true)

    local addonScrollChild = CreateFrame("Frame", nil, addonScrollFrame)
    addonScrollChild:SetWidth(SIDEBAR_W)
    -- Placeholder height; the button-build loop below sets the real value from
    -- cumulative GROUP_ROW_H / CHILD_ROW_H offsets.
    addonScrollChild:SetHeight(1)
    addonScrollFrame:SetScrollChild(addonScrollChild)

    EllesmereUI._addonScrollFrame = addonScrollFrame
    EllesmereUI._addonScrollChild = addonScrollChild

    -- Thin scrollbar thumb on the right edge of the scroll area
    local addonTrack = CreateFrame("Frame", nil, addonScrollFrame)
    addonTrack:SetWidth(3)
    addonTrack:SetPoint("TOPRIGHT", addonScrollFrame, "TOPRIGHT", -2, -2)
    addonTrack:SetPoint("BOTTOMRIGHT", addonScrollFrame, "BOTTOMRIGHT", -2, 2)
    addonTrack:SetFrameLevel(addonScrollFrame:GetFrameLevel() + 3)
    local addonTrackBg = SolidTex(addonTrack, "BACKGROUND", 1, 1, 1, 0.03)
    addonTrackBg:SetAllPoints()

    local addonThumb = SolidTex(addonTrack, "ARTWORK", 1, 1, 1, 0.25)
    addonThumb:SetPoint("TOP", addonTrack, "TOP", 0, 0)
    addonThumb:SetWidth(3)
    addonThumb:SetHeight(40)

    -- Scroll-to-bottom arrow below the viewport: dims at the bottom (or when the list
    -- does not scroll), click animates down. OnClick is wired below, once the
    -- smooth-scroll state locals exist. Alpha tiers live on the frame (ours to write).
    local arrowBtn = CreateFrame("Button", nil, sidebar)
    arrowBtn:SetSize(22, 19)
    arrowBtn:SetPoint("TOP", addonScrollFrame, "BOTTOM", 0, -5)
    arrowBtn:SetFrameLevel(sidebar:GetFrameLevel() + 5)
    arrowBtn:SetHitRectInsets(-12, -12, -6, -8)
    arrowBtn._aEnabled, arrowBtn._aDisabled, arrowBtn._aHover = 0.7, 0.2, 1.0
    arrowBtn._atBottom = false
    do
        local t = arrowBtn:CreateTexture(nil, "ARTWORK")
        t:SetTexture(ICONS_PATH .. "eui-arrow-down3.png")
        t:SetAllPoints()
    end
    arrowBtn:SetAlpha(arrowBtn._aEnabled)
    arrowBtn:SetScript("OnEnter", function(self)
        if not self._atBottom then self:SetAlpha(self._aHover) end
    end)
    arrowBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(self._atBottom and self._aDisabled or self._aEnabled)
    end)
    EllesmereUI._addonScrollArrow = arrowBtn

    local function UpdateAddonThumb()
        local maxScroll = EllesmereUI.SafeScrollRange and EllesmereUI.SafeScrollRange(addonScrollFrame) or 0
        -- Arrow state: dimmed when nothing is below. Runs before the no-scroll return.
        do
            local cur = tonumber(addonScrollFrame:GetVerticalScroll()) or 0
            local atBottom = (maxScroll <= 0.5) or (cur >= maxScroll - 0.5)
            arrowBtn._atBottom = atBottom
            if atBottom then
                arrowBtn:SetAlpha(arrowBtn._aDisabled)
            elseif arrowBtn:IsMouseOver() then
                arrowBtn:SetAlpha(arrowBtn._aHover)
            else
                arrowBtn:SetAlpha(arrowBtn._aEnabled)
            end
        end
        if maxScroll <= 0 then
            addonTrack:Hide()
            return
        end
        addonTrack:Show()
        local trackH = addonTrack:GetHeight()
        local visH = addonScrollFrame:GetHeight()
        local ratio = visH / (visH + maxScroll)
        local thumbH = math.max(30, trackH * ratio)
        addonThumb:SetHeight(thumbH)
        local scrollRatio = (tonumber(addonScrollFrame:GetVerticalScroll()) or 0) / maxScroll
        addonThumb:ClearAllPoints()
        addonThumb:SetPoint("TOP", addonTrack, "TOP", 0, -(scrollRatio * (trackH - thumbH)))
    end

    -- Smooth mouse-wheel scroll (lerp towards target)
    local addonScrollTarget = 0
    local addonIsSmoothing  = false
    local addonSmoothFrame  = CreateFrame("Frame")
    addonSmoothFrame:Hide()
    -- Pixel-snap the scroll offset in EFFECTIVE-PIXEL space (not raw WoW units), like the
    -- main content scroll. Rounding in the direction of travel keeps the lerp monotonic
    -- so it never bounces at settlement. Fractional offsets leave glyphs on sub-pixel
    -- positions and the rasterizer picks different pixels per frame: 1px scroll jitter.
    addonSmoothFrame:SetScript("OnUpdate", function(_, elapsed)
        local cur = addonScrollFrame:GetVerticalScroll()
        local maxScroll = EllesmereUI.SafeScrollRange and EllesmereUI.SafeScrollRange(addonScrollFrame) or 0
        local scale = addonScrollFrame:GetEffectiveScale()
        -- Snap max down to a pixel boundary so target can't exceed it.
        maxScroll = math.floor(maxScroll * scale) / scale
        addonScrollTarget = math.max(0, math.min(maxScroll, addonScrollTarget))
        local diff = addonScrollTarget - cur
        if math.abs(diff) < 0.3 then
            addonScrollFrame:SetVerticalScroll(addonScrollTarget)
            UpdateAddonThumb()
            addonIsSmoothing = false
            addonSmoothFrame:Hide()
            return
        end
        local newScroll = cur + diff * math.min(1, ADDON_SMOOTH_SPEED * elapsed)
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        if diff > 0 then
            newScroll = math.ceil(newScroll * scale) / scale
        else
            newScroll = math.floor(newScroll * scale) / scale
        end
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        addonScrollFrame:SetVerticalScroll(newScroll)
        UpdateAddonThumb()
    end)

    addonScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = EllesmereUI.SafeScrollRange and EllesmereUI.SafeScrollRange(self) or 0
        if maxScroll <= 0 then return end
        local scale = self:GetEffectiveScale()
        maxScroll = math.floor(maxScroll * scale) / scale
        local base = addonIsSmoothing and addonScrollTarget or self:GetVerticalScroll()
        local target = math.max(0, math.min(maxScroll, base - delta * ADDON_SCROLL_STEP))
        -- Snap the resting target to a pixel boundary so settlement lands on an integer row offset.
        target = math.floor(target * scale + 0.5) / scale
        addonScrollTarget = math.min(target, maxScroll)
        if not addonIsSmoothing then
            addonIsSmoothing = true
            addonSmoothFrame:Show()
        end
    end)
    addonScrollFrame:SetScript("OnScrollRangeChanged", UpdateAddonThumb)
    addonScrollFrame:HookScript("OnSizeChanged", UpdateAddonThumb)

    -- Arrow click: smooth-animate to the bottom, reusing the wheel's scroll state.
    arrowBtn:SetScript("OnClick", function()
        local maxScroll = EllesmereUI.SafeScrollRange and EllesmereUI.SafeScrollRange(addonScrollFrame) or 0
        if maxScroll <= 0 then return end
        local scale = addonScrollFrame:GetEffectiveScale()
        maxScroll = math.floor(maxScroll * scale) / scale
        addonScrollTarget = maxScroll
        if not addonIsSmoothing then
            addonIsSmoothing = true
            addonSmoothFrame:Show()
        end
    end)

    -- Click/drag the scrollbar track: a click jumps to that position, holding drags.
    -- The visible track is 3px, so a wider invisible hit rect is added.
    addonTrack:EnableMouse(true)
    addonTrack:SetHitRectInsets(-8, -2, 0, 0)
    local function _scrollToCursor()
        local maxScroll = EllesmereUI.SafeScrollRange and EllesmereUI.SafeScrollRange(addonScrollFrame) or 0
        if maxScroll <= 0 then return end
        local trackH = addonTrack:GetHeight()
        local thumbH = addonThumb:GetHeight()
        local travel = math.max(1, trackH - thumbH)
        local _, cy = GetCursorPosition()
        local scale = addonTrack:GetEffectiveScale()
        local trackTop = addonTrack:GetTop() or 0
        -- Center the thumb on the cursor, then clamp to travel range.
        local offset = (trackTop - cy / scale) - thumbH / 2
        offset = math.max(0, math.min(travel, offset))
        local rawScroll = (offset / travel) * maxScroll
        -- Snap to an effective-pixel boundary so labels land on exact pixels.
        local s = addonScrollFrame:GetEffectiveScale()
        local newScroll = math.floor(rawScroll * s + 0.5) / s
        newScroll = math.max(0, math.min(maxScroll, newScroll))
        addonScrollTarget = newScroll
        addonScrollFrame:SetVerticalScroll(newScroll)
        UpdateAddonThumb()
    end
    addonTrack:SetScript("OnMouseDown", function(self)
        _scrollToCursor()
        addonIsSmoothing = false
        addonSmoothFrame:Hide()
        self:SetScript("OnUpdate", _scrollToCursor)
    end)
    addonTrack:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    addonTrack:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- Grouped-sidebar row heights (groups = text-only headers, children = indented rows
    -- with label + power), sized to fit all addons without scrolling. On EllesmereUI so
    -- RefreshSidebarStates / _applySidebarSearch read the same values.
    EllesmereUI.SIDEBAR_GROUP_ROW_H = 28
    EllesmereUI.SIDEBAR_CHILD_ROW_H = 28   -- includes 6px air gap between addons
    EllesmereUI.SIDEBAR_GROUP_GAP   = 10   -- extra vertical space between groups
    local GROUP_ROW_H    = EllesmereUI.SIDEBAR_GROUP_ROW_H
    local CHILD_ROW_H    = EllesmereUI.SIDEBAR_CHILD_ROW_H
    local CHILD_INDENT_X = NAV_LEFT + 16   -- label indent past the group label

    -- Register the addon-enable helper once (on EllesmereUI to avoid new upvalues).
    if not EllesmereUI._addonToggleInit then
        EllesmereUI._addonToggleInit = true
        EllesmereUI.IsAddonEnabled = function(name)
            if C_AddOns and C_AddOns.GetAddOnEnableState then
                return C_AddOns.GetAddOnEnableState(name) > 0
            end
            return true
        end
    end

    -- Create a group header row (accent-colored label only, no icon, no power,
    -- not clickable). Acts as a visual category divider above its children.
    local function CreateGroupHeader(group)
        local row = CreateFrame("Frame", nil, addonScrollChild)
        row:SetSize(SIDEBAR_W, GROUP_ROW_H)
        row:SetFrameLevel(addonScrollChild:GetFrameLevel() + 1)

        local EG = ELLESMERE_GREEN
        local label = MakeFont(row, 15, nil, EG.r, EG.g, EG.b, 1)
        label:SetPoint("LEFT", row, "LEFT", NAV_LEFT, 0)
        label:SetText(EllesmereUI.L(group.label))
        RegAccent({ type="callback", fn = function(r, g, b)
            label:SetTextColor(r, g, b, 1)
        end })

        row._isGroup = true
        row._group   = group
        row._label   = label
        return row
    end

    -- Create a child (addon) row: indented label + power on the right, no left icon.
    local function CreateAddonChildRow(info)
        local btn = CreateFrame("Button", nil, addonScrollChild)
        btn:SetSize(SIDEBAR_W, CHILD_ROW_H)
        btn:SetFrameLevel(addonScrollChild:GetFrameLevel() + 1)

        DecorateSidebarButton(btn)

        local label = MakeFont(btn, 14, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("LEFT", btn, "LEFT", CHILD_INDENT_X, 0)
        label:SetText(EllesmereUI.L(info.display))
        btn._label = label

        -- One-time tutorial tip on the Cooldown Manager row: play badge in the indent
        -- gutter opening the CDM video guide, retired once clicked. VideoGuides owns all
        -- gating (seen map + Enable Tutorial Tips); nil-guarded for standalone builds.
        if info.folder == "EllesmereUICooldownManager"
            and EllesmereUI.VideoGuides and EllesmereUI.VideoGuides.AttachTip then
            EllesmereUI.VideoGuides.AttachTip(btn, "cooldown_manager", {
                tooltip = "Video Guide: Cooldown Manager",
                point = "RIGHT", relPoint = "LEFT",
                x = CHILD_INDENT_X - 6,
            })
        end

        -- Download icon (shown for uninstalled addons)
        local dlIcon = btn:CreateTexture(nil, "ARTWORK")
        dlIcon:SetSize(18, 18)
        dlIcon:SetPoint("RIGHT", btn, "RIGHT", -14, 0)
        dlIcon:SetTexture(ICONS_PATH .. "eui-download.png")
        dlIcon:SetDesaturated(true)
        dlIcon:SetAlpha(0.6)
        dlIcon:Hide()
        btn._dlIcon = dlIcon

        -- Power toggle (hidden for comingSoon/maintenance/alwaysLoaded, and entirely in
        -- standalone builds: one module, which cannot toggle itself off).
        if not IS_STANDALONE and not info.comingSoon and not info.maintenance and not info.alwaysLoaded then
            local pwrBtn = CreateFrame("Button", nil, btn)
            pwrBtn:SetSize(13, 13)
            pwrBtn:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
            pwrBtn:SetFrameLevel(btn:GetFrameLevel() + 5)
            local pwrTex = pwrBtn:CreateTexture(nil, "ARTWORK")
            pwrTex:SetAllPoints()
            pwrTex:SetTexture(ICONS_PATH .. "power.png")
            pwrTex:SetAlpha(0.75)
            pwrBtn._tex = pwrTex
            pwrBtn._folder = info.folder
            pwrBtn._display = info.display
            pwrBtn:SetScript("OnEnter", function(self)
                local enabled = IsAddonLoaded(self._folder)
                if enabled then
                    self._tex:SetVertexColor(0.824, 0.212, 0.212, 1)
                else
                    self._tex:SetVertexColor(0.212, 0.824, 0.325, 1)
                end
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, enabled and "Disable " .. self._display or "Enable " .. self._display)
                end
            end)
            pwrBtn:SetScript("OnLeave", function(self)
                local enabled = IsAddonLoaded(self._folder)
                self._tex:SetVertexColor(1, 1, 1, enabled and 1 or 0.5)
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            pwrBtn:SetScript("OnClick", function(self)
                local enabled = IsAddonLoaded(self._folder)
                local action = enabled and "disable" or "enable"
                local folder = self._folder
                EllesmereUI:ShowConfirmPopup({
                    title       = EllesmereUI.Lf("%1$s Module", enabled and EllesmereUI.L("Disable") or EllesmereUI.L("Enable")),
                    message     = EllesmereUI.Lf("Are you sure you want to %1$s %2$s?", EllesmereUI.L(action), EllesmereUI.L(self._display)),
                    confirmText = enabled and "Disable & Reload" or "Enable & Reload",
                    cancelText  = "Cancel",
                    onConfirm   = function()
                        if folder == "EllesmereUIBags" and EllesmereUIDB then
                            EllesmereUIDB.bagsUserChosen = true
                        end
                        if enabled then
                            C_AddOns.DisableAddOn(folder)
                        else
                            C_AddOns.EnableAddOn(folder)
                        end
                        ReloadUI()
                    end,
                })
            end)
            btn._pwrBtn = pwrBtn
        end

        -- Sync icon (to the left of power button, hidden for exempt/single-profile).
        -- Also hidden entirely in standalone builds (no cross-module sync surface).
        if not IS_STANDALONE and not info.comingSoon and not info.maintenance and not EllesmereUI._syncExempt[info.folder] then
            local syncBtn = CreateFrame("Button", nil, btn)
            syncBtn:SetSize(15, 15)
            if btn._pwrBtn then
                syncBtn:SetPoint("RIGHT", btn._pwrBtn, "LEFT", -8, 0)
            else
                syncBtn:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
            end
            syncBtn:SetFrameLevel(btn:GetFrameLevel() + 5)
            local syncTex = syncBtn:CreateTexture(nil, "ARTWORK")
            syncTex:SetAllPoints()
            syncTex:SetTexture(EllesmereUI.SYNC_ICON)
            syncTex:SetVertexColor(1, 1, 1, 1)
            syncBtn._tex = syncTex
            -- syncFolder/syncDisplay let an entry drive the sync of a DIFFERENT profile
            -- folder (Dragon Riding lives in the BlizzardSkin entry); the loaded check
            -- still uses info.folder, only the sync state/group target is redirected.
            local syncFolder = info.syncFolder or info.folder
            syncBtn._folder = syncFolder
            syncBtn._display = info.syncDisplay or info.display
            local SYNC_ON_R, SYNC_ON_G, SYNC_ON_B = 0x32/255, 0xbc/255, 0x53/255
            local SYNC_HOVER_R = math.min(1, SYNC_ON_R * 1.25)
            local SYNC_HOVER_G = math.min(1, SYNC_ON_G * 1.25)
            local SYNC_HOVER_B = math.min(1, SYNC_ON_B * 1.25)
            local isGlobalOnly = EllesmereUI._syncGlobalOnly and EllesmereUI._syncGlobalOnly[info.folder]
            local function RefreshSyncState()
                -- Hide the sync icon for disabled modules (no live settings to sync);
                -- same loaded check as the power button so the two stay consistent.
                if not IsAddonLoaded(info.folder) then syncBtn:Hide(); return end
                -- Hide if only one profile exists
                local profCount = 0
                if EllesmereUIDB and EllesmereUIDB.profiles then
                    for _ in pairs(EllesmereUIDB.profiles) do
                        profCount = profCount + 1
                        if profCount > 1 then break end
                    end
                end
                if profCount <= 1 then syncBtn:Hide(); return end
                -- Green when the ACTIVE profile is a member of this module's sync group;
                -- dim white otherwise, including when a group exists without it.
                local activeProf = EllesmereUIDB and EllesmereUIDB.activeProfile or "Default"
                local activeSynced = isGlobalOnly or EllesmereUI.IsProfileSynced(syncFolder, activeProf)
                -- Check global hide settings
                if EllesmereUIDB then
                    if EllesmereUIDB.hideSyncIcons then
                        if EllesmereUIDB.hideSyncIconsOnlyFull then
                            if activeSynced then syncBtn:Hide(); return end
                        else
                            syncBtn:Hide(); return
                        end
                    end
                end
                syncBtn:Show()
                if activeSynced then
                    syncTex:SetVertexColor(SYNC_ON_R, SYNC_ON_G, SYNC_ON_B, 1)
                else
                    syncTex:SetVertexColor(1, 1, 1, 0.5)
                end
            end
            RefreshSyncState()
            syncBtn._refreshAlpha = RefreshSyncState
            -- Bulk-refresh registry (e.g. after profile deletion), keyed by folder so a
            -- sidebar rebuild overwrites the old closure instead of accumulating stale ones.
            if not EllesmereUI._syncRefreshFns then EllesmereUI._syncRefreshFns = {} end
            EllesmereUI._syncRefreshFns[info.folder] = RefreshSyncState
            syncBtn:SetScript("OnEnter", function(self)
                if isGlobalOnly then
                    self._tex:SetVertexColor(SYNC_HOVER_R, SYNC_HOVER_G, SYNC_HOVER_B, 1)
                    if EllesmereUI.ShowWidgetTooltip then
                        EllesmereUI.ShowWidgetTooltip(self, "No Profile Level Customizations")
                    end
                    return
                end
                local activeProf = EllesmereUIDB and EllesmereUIDB.activeProfile or "Default"
                local activeSynced = EllesmereUI.IsProfileSynced(self._folder, activeProf)
                if activeSynced then
                    self._tex:SetVertexColor(SYNC_HOVER_R, SYNC_HOVER_G, SYNC_HOVER_B, 1)
                else
                    self._tex:SetVertexColor(1, 1, 1, 1)
                end
                if EllesmereUI.ShowWidgetTooltip then
                    local tip = activeSynced and "Profile Synced" or "Sync " .. self._display
                    EllesmereUI.ShowWidgetTooltip(self, tip)
                end
            end)
            syncBtn:SetScript("OnLeave", function(self)
                RefreshSyncState()
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            syncBtn:SetScript("OnClick", function(self)
                if isGlobalOnly then return end
                if EllesmereUI.OpenSyncPopup then
                    EllesmereUI.OpenSyncPopup(self._folder, self._display, self)
                end
            end)
            btn._syncBtn = syncBtn
        end

        -- Bound the label to the leftmost right-side icon so long translated names
        -- ellipsize instead of overlapping the sync/power icons. The download icon always
        -- exists, so there is always a right anchor reserving the cluster's space.
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetMaxLines(1)
        local rightEdge = btn._syncBtn or btn._pwrBtn or btn._dlIcon
        if rightEdge then
            label:SetPoint("RIGHT", rightEdge, "LEFT", -6, 0)
        end

        -- Default to unloaded appearance (refreshed each time panel opens)
        label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
        btn._folder = info.folder
        btn._loaded = false
        btn._alwaysLoaded = info.alwaysLoaded or false
        btn._comingSoon = info.comingSoon or false
        btn._maintenance = info.maintenance or false

        local hlTex = SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0)
        hlTex:SetAllPoints()
        btn:SetScript("OnEnter", function(self)
            if self._comingSoon then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "Coming soon")
                end
                return
            end
            if self._maintenance then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "In Maintenance")
                end
                return
            end
            if self._ovLocked then
                if EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, "This module can't be overridden. Exit the override editing session to open it.")
                end
                return
            end
            if self._notEnabled then return end
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
            if self._maintenance then return end
            if self._ovLocked then return end
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
            if self._maintenance then return end
            if self._ovLocked then return end
            if self._notEnabled then return end
            if self._loaded and modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        return btn
    end

    -- Build the sidebar in group order; positions are assigned once and re-stacked by
    -- RefreshSidebarStates / _applySidebarSearch. Group/roster references go through
    -- EllesmereUI fields to avoid upvalues in CreateMainFrame (60-upvalue cap); cumulative `_y` walks each row so group and child heights can differ.
    local _y = 0
    local _groupHeaders = EllesmereUI._sidebarGroupButtons
    local _infoByFolder = EllesmereUI._addonInfoByFolder
    local GROUP_GAP = EllesmereUI.SIDEBAR_GROUP_GAP
    for i, group in ipairs(EllesmereUI.ADDON_GROUPS) do
        if i > 1 then _y = _y + GROUP_GAP end
        local header = CreateGroupHeader(group)
        header:SetPoint("TOPLEFT", addonScrollChild, "TOPLEFT", 0, -_y)
        _groupHeaders[group.key] = header
        _y = _y + GROUP_ROW_H
        for _, folder in ipairs(group.members) do
            local info = _infoByFolder[folder]
            if info then
                local btn = CreateAddonChildRow(info)
                btn:SetPoint("TOPLEFT", addonScrollChild, "TOPLEFT", 0, -_y)
                sidebarButtons[info.folder] = btn
                _y = _y + CHILD_ROW_H
            end
        end
    end
    EllesmereUI._sidebarButtons = sidebarButtons
    -- Lock/unlock excluded modules during an override editing session: their settings cannot be
    -- captured, so the row grays out and blocks clicks. Called from the session enter/exit paths in EllesmereUI_SpecOverrides.
    EllesmereUI.RefreshSidebarOverrideLocks = function()
        local active = EllesmereUI.SpecOverrides_EditSessionActive
            and EllesmereUI.SpecOverrides_EditSessionActive() or false
        for folder, btn in pairs(sidebarButtons) do
            local lock = (active and EllesmereUI.SpecOverrides_ModuleExcluded
                and EllesmereUI.SpecOverrides_ModuleExcluded(folder)) or false
            if lock then
                -- Re-assert UNCONDITIONALLY: RefreshSidebarStates recolors every row by
                -- loaded state on module switches and would otherwise wash the lock out.
                btn._ovLocked = true
                btn._label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
                if btn._icon then
                    btn._icon:SetDesaturated(true)
                    btn._icon:SetAlpha(0.35)
                end
            elseif btn._ovLocked then
                btn._ovLocked = nil
                if btn._loaded then
                    btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
                    if btn._icon then
                        btn._icon:SetDesaturated(false)
                        btn._icon:SetAlpha(NAV_ENABLED_ICON_A)
                    end
                end
            end
        end
    end
    -- Refresh all sync icons (called from global settings toggle)
    EllesmereUI._refreshAllSyncIcons = function()
        for _, btn in pairs(sidebarButtons) do
            if btn._syncBtn and btn._syncBtn._refreshAlpha then
                btn._syncBtn._refreshAlpha()
            end
        end
    end
    addonScrollChild:SetHeight(_y)

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

    -- Resource usage tracker (CPU for all EUI addons). Only ticks while the panel is
    -- visible: parented to sidebar, a descendant of mainFrame (hidden frames never tick).

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
    EllesmereUI._tabBar = tabBar

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
    contentHeaderFrame:SetClipsChildren(true)
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
        -- Anchor bottom to footer top so WoW resolves height from both edges, avoiding
        -- the PanelPP.Point vs PanelPP.Height rounding mismatch (1px flicker at the
        -- scroll area's bottom edge when the content header height changes).
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
    -- Clip children to the viewport so off-screen widgets are skipped; without it every
    -- widget on the page renders each frame regardless of scroll position.
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
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
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
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
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
        -- Round toward the target so the last frames approach monotonically, never bouncing
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
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
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

    -- Current content scroll offset: the in-flight target while animating, else the
    -- settled position. Lets callers capture and restore scroll across a page rebuild.
    function EllesmereUI.GetContentScroll()
        if isSmoothing then return scrollTarget or 0 end
        return (scrollFrame and tonumber(scrollFrame:GetVerticalScroll())) or 0
    end

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
        local maxScroll = EllesmereUI.SafeScrollRange(self)
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
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
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
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
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

    -- Cache the content header's children/regions, reparented to a hidden stash so
    -- ClearContentHeaderInner cannot destroy them while clearing for other pages.
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
        -- Use the ACTUAL height change after PixelUtil snapping, not the requested
        -- delta: rounding to physical pixels at the frame's effective scale makes the
        -- real change differ from h-oldH by a sub-pixel amount (1px content shift).
        local newActualH = contentHeaderFrame:GetHeight()
        local delta = newActualH - oldActualH
        ApplyContentLayout()
        -- The scroll frame moved by |delta| px; scroll content the same to hold the viewport.
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

    -- Silent variant: resizes the header with no scroll compensation, for cosmetic
    -- height changes (buff icons toggled) that must not jump the scroll.
    function EllesmereUI:SetContentHeaderHeightSilent(h)
        if not contentHeaderFrame:IsShown() then return end
        contentHeaderH = h
        PanelPP.Height(contentHeaderFrame, h)
        ApplyContentLayout()
    end

    function EllesmereUI:ClearContentHeader()
        ClearContentHeaderInner()
    end

    -- Lightweight hide (no orphaning), for when the header is already cached.
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
        lbl:SetAlpha(textA); lbl:SetPoint("CENTER"); lbl:SetText(EllesmereUI.L(label))
        btn._label = lbl
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

    local FOOTER_BTN_W, FOOTER_BTN_H = 180, 36
    local FOOTER_BTN_GAP = 20   -- gap between Reset and Reload
    local DONE_BTN_W = 160      -- Done button width
    local FOOTER_PAD = 24       -- symmetric inset from left/right edges
    local FOOTER_Y   = 24       -- vertical offset from bottom

    -- Reset button  (left side, FOOTER_PAD from left edge)
    local resetBtn = MakeFooterBtn(footerFrame, FOOTER_BTN_W, FOOTER_BTN_H,
        "BOTTOMLEFT", footerFrame, "BOTTOMLEFT", FOOTER_PAD, FOOTER_Y,
        RS_TEXT_R, RS_TEXT_G, RS_TEXT_B, RS_TEXT_A, RS_TEXT_HR, RS_TEXT_HG, RS_TEXT_HB, RS_TEXT_HA,
        RS_BRD_R, RS_BRD_G, RS_BRD_B, RS_BRD_A, RS_BRD_HR, RS_BRD_HG, RS_BRD_HB, RS_BRD_HA,
        "Reset", function()
            if not activeModule or not modules[activeModule] or not modules[activeModule].onReset then return end
            local config = modules[activeModule]
            local addonTitle = config.title or activeModule
            local msg = EllesmereUI.Lf("Are you sure you want to reset all %1$s settings to their defaults? This will reload your UI.", EllesmereUI.L(addonTitle))
            local disclaimer
            if activeModule == (EllesmereUI.GLOBAL_KEY or "_EUIGlobal") then
                disclaimer = "This will not reset addon-specific Quick Setup."
            end
            EllesmereUI:ShowConfirmPopup({
                title       = EllesmereUI.Lf("Reset %1$s", EllesmereUI.L(addonTitle)),
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
    footerFrame._resetBtn = resetBtn

    -- Reload UI  (next to Reset, 40px gap, same white/muted style)
    local reloadBtn = MakeFooterBtn(footerFrame, FOOTER_BTN_W, FOOTER_BTN_H,
        "BOTTOMLEFT", resetBtn, "BOTTOMRIGHT", FOOTER_BTN_GAP, 0,
        RS_TEXT_R, RS_TEXT_G, RS_TEXT_B, RS_TEXT_A, RS_TEXT_HR, RS_TEXT_HG, RS_TEXT_HB, RS_TEXT_HA,
        RS_BRD_R, RS_BRD_G, RS_BRD_B, RS_BRD_A, RS_BRD_HR, RS_BRD_HG, RS_BRD_HB, RS_BRD_HA,
        "Reload UI", function() ReloadUI() end)
    footerFrame._reloadBtn = reloadBtn

    -- Per-module Reset visibility: modules with no onReset (Patch Notes, Profiles) hide
    -- Reset and slide Reload UI left into its slot. Called from SelectModule.
    EllesmereUI._UpdateResetButtonVisible = function(hasReset)
        local rb, rl = footerFrame._resetBtn, footerFrame._reloadBtn
        if not rb or not rl then return end
        rl:ClearAllPoints()
        if hasReset then
            rb:Show()
            rl:SetPoint("BOTTOMLEFT", rb, "BOTTOMRIGHT", FOOTER_BTN_GAP, 0)
        else
            rb:Hide()
            rl:SetPoint("BOTTOMLEFT", footerFrame, "BOTTOMLEFT", FOOTER_PAD, FOOTER_Y)
        end
    end

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
            { icon = ICONS_PATH .. "twitch-2.png",  url = "https://www.twitch.tv/ellesmere_gaming", tooltip = "Twitch" },
            { icon = ICONS_PATH .. "discord-2.png", url = "https://discord.gg/FtCsUSC",             tooltip = "Discord" },
            { icon = ICONS_PATH .. "donate-3.png",  url = "https://www.patreon.com/ellesmere",       tooltip = "Patreon" },
            { icon = ICONS_PATH .. "paypal.png",    url = "https://www.paypal.biz/ellesmeregaming",  tooltip = "PayPal" },
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
            btn:SetScript("OnEnter", function(self)
                target = 1; self:SetScript("OnUpdate", OnUpdate)
                if def.tooltip and EllesmereUI.ShowWidgetTooltip then
                    EllesmereUI.ShowWidgetTooltip(self, def.tooltip)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                target = 0; self:SetScript("OnUpdate", OnUpdate)
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            btn:SetScript("OnClick", function() ShowLinkPopup(def.url, btn) end)
        end
    end

    -- Close  (right side, FOOTER_PAD from right edge, green, closes window)
    do
        local btn = CreateFrame("Button", nil, footerFrame)
        PanelPP.Size(btn, DONE_BTN_W, FOOTER_BTN_H)
        PanelPP.Point(btn, "BOTTOMRIGHT", footerFrame, "BOTTOMRIGHT", -FOOTER_PAD, FOOTER_Y)
        btn:SetFrameLevel(footerFrame:GetFrameLevel() + 1)
        local brd = MakeBorder(btn, ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b, 0.7, PanelPP)
        local bg = SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, .92)
        bg:SetAllPoints()
        local lbl = MakeFont(btn, 13, nil, ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b)
        lbl:SetAlpha(0.7); lbl:SetPoint("CENTER"); lbl:SetText(EllesmereUI.L("Close"))
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
-- Display-only tab label overrides ([page identity] = shown label), registered by module options
-- files. Page IDENTITY stays the original string everywhere else (SelectPage, nav targets, unlock elements, spec overrides, saved state); only the tab text changes.
EllesmereUI.TAB_LABEL_OVERRIDES = EllesmereUI.TAB_LABEL_OVERRIDES or {}

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
    label:SetText(EllesmereUI.L(EllesmereUI.TAB_LABEL_OVERRIDES[name] or name))
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
        local SEARCH_W, SEARCH_H = 210, 28
        local searchFrame = CreateFrame("Frame", nil, tabBar)
        searchFrame:SetSize(SEARCH_W, SEARCH_H)
        searchFrame:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", -10, (TAB_BAR_H - SEARCH_H) / 2 + 2)
        searchFrame:SetFrameLevel(tabBar:GetFrameLevel() + 2)

        local searchBg = SolidTex(searchFrame, "BACKGROUND", SL_INPUT_R, SL_INPUT_G, SL_INPUT_B, SL_INPUT_A + 0.10)
        searchBg:SetAllPoints()
        local searchBrd = MakeBorder(searchFrame, BORDER_R, BORDER_G, BORDER_B, 0.10)

        local editBox = CreateFrame("EditBox", nil, searchFrame)
        editBox:SetAllPoints()
        editBox:SetAutoFocus(false)
        editBox:SetFont(EllesmereUI.EXPRESSWAY, 13, "")
        editBox:SetTextColor(TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B, 1)
        editBox:SetTextInsets(10, 24, 0, 0)
        editBox:SetMaxLetters(40)

        local placeholder = MakeFont(searchFrame, 12, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, 0.3)
        placeholder:SetPoint("LEFT", searchFrame, "LEFT", 10, 0)
        placeholder:SetText(EllesmereUI.L("Search Module Settings..."))

        -- Clear button (X) on right side -- frame level above editBox so clicks register
        local clearBtn = CreateFrame("Button", nil, searchFrame)
        clearBtn:SetSize(20, 20)
        clearBtn:SetPoint("RIGHT", searchFrame, "RIGHT", -4, 0)
        clearBtn:SetFrameLevel(editBox:GetFrameLevel() + 2)
        clearBtn:Hide()
        local clearLabel = MakeFont(clearBtn, 15, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, 0.35)
        clearLabel:SetPoint("CENTER")
        clearLabel:SetText("x")
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

        -- Spec Override capture toggle (left of the search box). All look
        -- and behavior live in EllesmereUI_SpecOverrides.lua.
        if EllesmereUI.SpecOverrides_SetupButton then
            local soBtn = CreateFrame("Button", nil, tabBar)
            soBtn:SetSize(26, 26)
            soBtn:SetPoint("RIGHT", searchFrame, "LEFT", -10, 0)
            soBtn:SetFrameLevel(tabBar:GetFrameLevel() + 2)
            EllesmereUI.SpecOverrides_SetupButton(soBtn)
            tabBar._specOvBtn = soBtn
        end
        -- Conditional Overrides has no toolbar button: its cards render as a second section in the spec popup.
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

EllesmereUI.PlaySearchHighlight = PlaySearchHighlight
EllesmereUI.GetSearchHighlight = GetSearchHighlight

-- Collect a wrapper's direct children sorted by original Y (top to bottom) into sections
-- { header=frame, members={frame,...} }: each child belongs to the nearest section header above
-- it, children before any header become leading orphans. Split column containers (_leftCol/_rightCol) are single blocks -- searched inside, never re-anchored per child.
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
                local labelsLoc = {}
                local function GatherLabels(col)
                    if not col then return end
                    local subs = { col:GetChildren() }
                    for _, sub in ipairs(subs) do
                        if sub._sectionName then labels[#labels + 1] = sub._sectionName; labelsLoc[#labelsLoc + 1] = sub._sectionNameLoc or sub._sectionName end
                        if sub._labelText then labels[#labels + 1] = sub._labelText; labelsLoc[#labelsLoc + 1] = sub._labelTextLoc or sub._labelText end
                    end
                end
                GatherLabels(child._leftCol)
                GatherLabels(child._rightCol)
                child._splitSearchLabels = table.concat(labels, " ")
                -- Bilingual search: localized variant, only stored when it differs (nil on English).
                local _loc = table.concat(labelsLoc, " ")
                if _loc ~= child._splitSearchLabels then child._splitSearchLabelsLoc = _loc end
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
        if child._searchIgnore then
            -- Managed outside the inline search (e.g. party sync overlays); never
            -- collect it so the search can't re-anchor or hide/show it.
        elseif child._isSectionHeader then
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

function EllesmereUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
    -- For split rows (DualRow etc.), narrow a deep-link highlight to the half/slot whose own
    -- label matches instead of pulsing the whole row; returns that child region, or nil to fall
    -- back to the full row. Inline, not a file-scope local: the main chunk is at the 200-local cap.
    local function ResolveHighlightSlot(row, text)
        if not text or not row.GetChildren then return nil end
        local locText = EllesmereUI.L and EllesmereUI.L(text) or text
        for _, region in ipairs({ row:GetChildren() }) do
            local lbl = region._label
            if lbl and lbl.GetText then
                local t = lbl:GetText()
                if t and t ~= "" and (t:find(text, 1, true) or (locText ~= text and t:find(locText, 1, true))) then
                    return region
                end
            end
        end
        return nil
    end

    -- First-open split (see _SplitFirstOpen): Show() below returns without
    -- building the panel on the session's first open, so run the whole deep
    -- link next frame rather than navigating a panel that does not exist yet.
    if self:_SplitFirstOpen(function()
        EllesmereUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
    end) then return end

    self:Show()
    self:SelectModule(moduleName)
    self:SelectPage(pageName)

    -- Switch dropdown AFTER the page is loaded, then force a full rebuild.
    -- This mirrors exactly what the dropdown's own onChange handler does.
    if preSelectFn then
        preSelectFn()
        self:InvalidateContentHeaderCache()
        local config = modules[moduleName]
        if config and config.getHeaderBuilder then
            local hb = config.getHeaderBuilder(pageName)
            if hb then self:SetContentHeader(hb) end
        end
        self:RefreshPage(true)
    end

    C_Timer.After(0.05, function()
        local cacheKey = moduleName .. "::" .. pageName
        local cached = _pageCache[cacheKey]
        if not cached or not cached.wrapper then return end

        local sections = CollectAllChildren(cached.wrapper)
        for _, sec in ipairs(sections) do
            if sec.header._sectionName == sectionName then
                -- Find the row to scroll to; narrow the highlight to the matching
                -- slot (DualRow half) when possible, otherwise pulse the whole row.
                local target = sec.header
                local hlTarget = sec.header
                if highlightText then
                    for _, m in ipairs(sec.members) do
                        if (m._labelText and m._labelText:find(highlightText, 1, true))
                           or (m._labelTextLoc and m._labelTextLoc:find(highlightText, 1, true)) then
                            target = m
                            hlTarget = ResolveHighlightSlot(m, highlightText) or m
                            break
                        end
                    end
                end

                local a = target._origAnchor
                if a then
                    local scrollPos = math.abs(a[5]) - 40
                    EllesmereUI.SmoothScrollTo(scrollPos)
                    C_Timer.After(0.15, function()
                        local hl = GetSearchHighlight()
                        PlaySearchHighlight(hl, hlTarget)
                    end)
                end
                return
            end
        end
    end)
end

-- Searchable label for any child frame. On translated clients the localized variant is
-- appended so search matches either language; on English the *Loc fields are nil.
local function GetSearchLabel(child)
    local en = child._labelText or child._sectionName or child._splitSearchLabels
    if not en then return "" end
    local loc = child._labelTextLoc or child._sectionNameLoc or child._splitSearchLabelsLoc
    if loc then return en .. " " .. loc end
    return en
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
    -- Active search force-expands every "Show Less Common" section (links hidden);
    -- clearing collapses back to session state. MUST run before the cache lookup below:
    -- a state transition rebuilds and replaces this page's cache entry.
    if EllesmereUI.SetLessCommonSearchActive then
        EllesmereUI.SetLessCommonSearchActive(query ~= nil and query ~= "")
    end
    local cacheKey = activeModule .. "::" .. activePage
    local cached = _pageCache[cacheKey]
    if not cached or not cached.wrapper then return end

    -- Per-page search-state hook (e.g. the party tab hides its sync overlays
    -- while a search is active). Fires for both filtering and restore.
    if EllesmereUI._onInlineSearch then EllesmereUI._onInlineSearch(query or "") end

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
        cached._searchFiltered = nil
        return
    end

    local queryLower = query:lower()

    -- Determine which sections are visible and which rows/slots match
    local visibleSections = {}
    for _, sec in ipairs(sections) do
        local sectionName = sec.header._sectionName or ""
        local sectionMatch = sectionName:lower():find(queryLower, 1, true)
        -- Bilingual: also match the localized section name on translated clients.
        if not sectionMatch and sec.header._sectionNameLoc then
            sectionMatch = sec.header._sectionNameLoc:lower():find(queryLower, 1, true)
        end
        -- Per-page section exclusion hook (e.g. the party tab hides sections that
        -- are synced with raid settings). Only consulted during a live search.
        local excluded = EllesmereUI._searchExcludeSection
            and EllesmereUI._searchExcludeSection(sectionName)

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

        if (sectionMatch or anyMemberMatch) and not excluded then
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

    -- Orphans are by construction the LEADING widgets on a page: created before its first
    -- SectionHeader call, so _currentSection is nil when TagOptionRow tags them. Match them like
    -- section members instead of hiding them unconditionally, or a query matching only an orphan (a lead "Activate X" button) leaves the page empty.
    local visibleOrphans = {}
    for _, o in ipairs(orphans) do
        local label = GetSearchLabel(o)
        local matched = label ~= "" and label:lower():find(queryLower, 1, true)
        if not matched then
            for _, rgn in ipairs({ o._leftRegion, o._midRegion, o._rightRegion }) do
                if rgn then
                    local ddText = GetDropdownValueText(rgn)
                    if ddText and ddText:lower():find(queryLower, 1, true) then
                        matched = true; break
                    end
                end
            end
        end
        if matched then
            visibleOrphans[#visibleOrphans + 1] = o
        else
            o:Hide()
        end
    end

    -- Build per-slot highlight targets and count totals to decide if we suppress
    -- highlights (when every visible slot is highlighted, none should glow).
    local highlightTargets = {}  -- list of { frame = region_or_member }
    local totalSlots = 0
    local highlightedSlots = 0

    for _, vs in ipairs(visibleSections) do
        for _, m in ipairs(vs.sec.members) do
            -- Skip spacer frames -- they have no content to highlight
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

    -- Same slot/highlight accounting for visible orphans: they already passed the match check, so unlike section members there is no "section matched" bypass to OR in.
    for _, o in ipairs(visibleOrphans) do
        if not o._isSpacer then
            local slots = {}
            if o._leftRegion then slots[#slots + 1] = { region = o._leftRegion,  label = o._leftRegion._slotLabel  or "" } end
            if o._midRegion  then slots[#slots + 1] = { region = o._midRegion,   label = o._midRegion._slotLabel   or "" } end
            if o._rightRegion then slots[#slots + 1] = { region = o._rightRegion, label = o._rightRegion._slotLabel or "" } end

            if #slots > 0 then
                for _, s in ipairs(slots) do
                    if s.label ~= "" then
                        totalSlots = totalSlots + 1
                        local slotMatch = s.label:lower():find(queryLower, 1, true)
                        if not slotMatch then
                            local ddText = GetDropdownValueText(s.region)
                            if ddText then slotMatch = ddText:lower():find(queryLower, 1, true) end
                        end
                        if slotMatch then
                            highlightedSlots = highlightedSlots + 1
                            highlightTargets[#highlightTargets + 1] = s.region
                        end
                    end
                end
            else
                totalSlots = totalSlots + 1
                highlightedSlots = highlightedSlots + 1
                highlightTargets[#highlightTargets + 1] = o
            end
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

    -- Matching orphans lead the page (always before the first section in the source
    -- layout), so place and highlight them first; the sections loop continues from y.
    for _, o in ipairs(visibleOrphans) do
        if o._isSpacer then
            o:Hide()
        else
            local ox = o._origAnchor and o._origAnchor[4] or CONTENT_PAD
            o:ClearAllPoints()
            PanelPP.Point(o, "TOPLEFT", cached.wrapper, "TOPLEFT", ox, y)
            o:Show()

            if not suppressHighlights and not skipHighlights then
                if o._leftRegion and hlSet[o._leftRegion] then
                    local hl = GetSearchHighlight(); PlaySearchHighlight(hl, o._leftRegion)
                end
                if o._midRegion and hlSet[o._midRegion] then
                    local hl = GetSearchHighlight(); PlaySearchHighlight(hl, o._midRegion)
                end
                if o._rightRegion and hlSet[o._rightRegion] then
                    local hl = GetSearchHighlight(); PlaySearchHighlight(hl, o._rightRegion)
                end
                if not o._leftRegion and hlSet[o] then
                    local hl = GetSearchHighlight(); PlaySearchHighlight(hl, o)
                end
            end

            y = y - o:GetHeight()
        end
    end

    for _, vs in ipairs(visibleSections) do
        local sec = vs.sec
        local hdrX = sec.header._origAnchor and sec.header._origAnchor[4] or CONTENT_PAD
        sec.header:ClearAllPoints()
        PanelPP.Point(sec.header, "TOPLEFT", cached.wrapper, "TOPLEFT", hdrX, y)
        sec.header:Show()
        y = y - sec.header:GetHeight()

        for _, m in ipairs(sec.members) do
            -- Hide spacers during search -- they're just empty gaps
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
    -- Mark this page as currently search-filtered so it is reliably restored when
    -- shown again, even if the search box was cleared on a tab/module switch.
    cached._searchFiltered = true
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
            btn._label:SetTextColor(NAV_SELECTED_TEXT.r, NAV_SELECTED_TEXT.g, NAV_SELECTED_TEXT.b, NAV_SELECTED_TEXT.a)
            if btn._icon then
                btn._icon:SetTexture(btn._iconOff)
                btn._icon:SetDesaturated(false)
                btn._icon:SetAlpha(NAV_SELECTED_ICON_A)
            end
            if btn._iconGlow then btn._iconGlow:Show() end
        else
            btn._indicator:Hide()
            btn._glow:Hide()
            btn._glowTop:Hide()
            btn._glowBot:Hide()
            if btn._iconGlow then btn._iconGlow:Hide() end
            if btn._loaded then
                btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
                if btn._icon then
                    btn._icon:SetTexture(btn._iconOff)
                    btn._icon:SetDesaturated(false)
                    btn._icon:SetAlpha(NAV_ENABLED_ICON_A)
                end
            else
                btn._label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
                if btn._icon then
                    btn._icon:SetDesaturated(true)
                    btn._icon:SetAlpha(NAV_DISABLED_ICON_A)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Content clearing
-------------------------------------------------------------------------------
-- WoW frames are permanent C objects that can never be freed, so orphaning with
-- SetParent(nil) leaks the same memory: Hide() everything in place instead. buildPage
-- creates new frames on top and hidden ones cost nothing to render.
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
    -- Disconnect children: frames can never be freed, but SetParent(nil) removes them
    -- from the render/layout hierarchy so they stop accumulating under scrollChild.
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
    -- Only allow registration from EllesmereUI addon files.
    -- Extract the addon folder name from the caller's file path.
    local caller = debugstack(2, 1, 0) or ""
    local callerFolder = caller:match("AddOns/([^/]+)/")
    local ALLOWED = {
        EllesmereUI = true,
        EllesmereUIOptions = true,  -- the LoadOnDemand options surface: every module's options file registers from here
        EllesmereUIActionBars = true,
        EllesmereUIAuraBuffReminders = true,
        EllesmereUICooldownManager = true,
        EllesmereUINameplates = true,
        EllesmereUIPartyMode = true,
        EllesmereUIRaidFrames = true,
        EllesmereUIResourceBars = true,
        EllesmereUIUnitFrames = true,
        EllesmereUIMythicTimer = true,
        -- v6.6 split
        EllesmereUIQoL = true,
        EllesmereUIBlizzardSkin = true,
        EllesmereUIQuestTracker = true,
        EllesmereUIMinimap = true,
        EllesmereUIFriends = true,
        EllesmereUIChat = true,
        EllesmereUIDamageMeters = true,
        EllesmereUIBags = true,
        EllesmereUIDataBars = true,
        EllesmereUIQuickdraw = true,
    }
    if callerFolder and not ALLOWED[callerFolder] then return end
    -- Suite-core marker (module key is a suite folder), gating the toolbar whitelists:
    -- the overrides icon renders for core modules only, the inline search for core
    -- modules + Global Settings. Companion/external pages keep their own folder keys and
    -- stay unmarked, so neither control renders for them (see SelectModule).
    config._euiCore = ALLOWED[folderName] == true
    modules[folderName] = config
    -- If the UI is built, update the sidebar button now; else RefreshSidebarStates does it on first open
    local btn = sidebarButtons[folderName]
    if btn then
        btn._loaded = true
        btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
        if btn._icon then
            btn._icon:SetDesaturated(false)
            btn._icon:SetAlpha(NAV_ENABLED_ICON_A)
        end
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
EllesmereUI._pageCache = _pageCache
local _activePageWrapper  -- the currently-visible wrapper frame

-- Invalidate all cached pages (called on profile reset, module reload, etc.)
function EllesmereUI:InvalidatePageCache()
    for key, entry in pairs(_pageCache) do
        if entry.wrapper then
            entry.wrapper:Hide()
            entry.wrapper:SetParent(nil)
        end
        _pageCache[key] = nil
    end
    _activePageWrapper = nil
    if EllesmereUI.InvalidateContentHeaderCache then
        EllesmereUI:InvalidateContentHeaderCache()
    end
end

-- Invalidate cached pages for a SINGLE module (key prefix "Module::"), e.g. on spec change
-- where only the per-spec module's pages go stale. Panel OPEN: the shown page's wrapper is kept
-- so the screen is not blanked (the caller rebuilds it in place via RefreshPage(true)). Panel
-- CLOSED: every cached page is dropped for a fresh build. Teardown matches RefreshPage: Hide + SetParent(nil) the wrapper, then drop the entry.
function EllesmereUI:InvalidateModulePageCache(moduleName)
    if not moduleName then return end
    local prefix = moduleName .. "::"
    local keepKey
    if self.IsShown and self:IsShown() and activeModule and activePage then
        keepKey = activeModule .. "::" .. activePage
    end
    for key, entry in pairs(_pageCache) do
        if key:sub(1, #prefix) == prefix and key ~= keepKey then
            if entry.wrapper then
                entry.wrapper:Hide()
                entry.wrapper:SetParent(nil)
            end
            _pageCache[key] = nil
        end
    end
end

function EllesmereUI:SelectPage(pageName)
    -- Excluded pages (CDM Bar Glows / Tracking Bars) lock during an override editing
    -- session: their systems keep their own per-spec storage, outside the capture.
    if EllesmereUI.SpecOverrides_EditSessionActive
       and EllesmereUI.SpecOverrides_EditSessionActive()
       and EllesmereUI.SpecOverrides_PageExcluded
       and EllesmereUI.SpecOverrides_PageExcluded(activeModule, pageName) then
        return
    end
    if not activeModule or not modules[activeModule] then return end
    if pageName == activePage then return end

    -- "Unlock Mode" is a fake nav item -- fire unlock mode without changing page state.
    -- Capture the current module + page so DoClose can restore them exactly.
    if pageName == "Unlock Mode" then
        if EllesmereUI._openUnlockMode then
            EllesmereUI._unlockReturnModule = activeModule
            EllesmereUI._unlockReturnPage   = activePage
            C_Timer.After(0, EllesmereUI._openUnlockMode)
        end
        return
    end

    -- "Disable Addons" is a fake nav item -- close EUI and open the Blizzard addon list.
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

    -- Restore the page's inline-search filter and clear the box BEFORE switching activePage:
    -- SetText("") fires ApplyInlineSearch("") via OnTextChanged, which keys off activePage, so it
    -- must still point at the filtered page or it stays stuck in its filtered layout (looks "searched" with an empty box) until re-search.
    if tabBar and tabBar._searchBox and tabBar._searchBox:GetText() ~= "" then
        tabBar._searchBox:SetText("")
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

    local cacheKey = activeModule .. "::" .. pageName
    local cached = _pageCache[cacheKey]

    -- Reconcile the two independent caches before the fast path. The page wrapper (_pageCache)
    -- and the content-header PREVIEW (_contentHeaderCache) cache separately, but the preview's
    -- interactive hit overlays are created ONLY by buildPage. If InvalidateContentHeaderCache ran
    -- while this page's wrapper stayed cached, a header-only SetContentHeader rebuild recreates
    -- the preview with NO overlays -- visible but dead to hover/click until /reload. So a page
    -- that HAS a preview but misses its header cache discards the stale wrapper (RefreshPage teardown) and falls through to a cold rebuild; pages without a headerBuilder stay on the fast path.
    if cached and cached.wrapper then
        HideAllChildren(scrollChild)
        if not EllesmereUI:RestoreContentHeaderFromCache(cacheKey) then
            if cached.headerBuilder then
                cached.wrapper:Hide()
                cached.wrapper:SetParent(nil)
                _pageCache[cacheKey] = nil
                cached = nil
            elseif EllesmereUI.ClearContentHeader then
                EllesmereUI:ClearContentHeader()
            end
        end
    end

    if cached and cached.wrapper then
        -- Fast path (both caches in sync): show the cached wrapper, set child height
        cached.wrapper:Show()
        _activePageWrapper = cached.wrapper
        contentFrame:SetHeight(cached.totalH + 30)

        -- Restore elements hidden by a previous inline search, keyed off the page's own filtered
        -- flag and NOT the search box: clearing the box on a tab/module switch does not reliably
        -- restore the page being left, so a cached page can stay filtered while the box reads empty. The flag tracks the real state.
        if cached._searchFiltered then
            EllesmereUI:ApplyInlineSearch("")
        end

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
        _activePageWrapper = wrapper

        local config = modules[activeModule]
        local totalH = 0
        if config.buildPage then
            local startY = -6

            EllesmereUI._buildingModule = activeModule
            EllesmereUI._buildingPage = pageName
            totalH = config.buildPage(pageName, wrapper, startY) or 600
            EllesmereUI._buildingModule = nil
            EllesmereUI._buildingPage = nil
            EllesmereUI._buildingSelector = nil
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

    -- Re-snap PP borders after a tab switch: cached frames re-show without
    -- CreateBorder's built-in 2-frame re-snap, so borders misalign until reopen. Wait
    -- 1 frame so the hierarchy has finished layout before recalculating effective scales.
    C_Timer.After(0, function()
        if PP and PP.ResnapBordersUnder and _activePageWrapper then
            PP.ResnapBordersUnder(_activePageWrapper)
        elseif PP and PP.ResnapAllBorders then
            PP.ResnapAllBorders()
        end
    end)
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
    -- Panel hidden: a rebuild here would run buildPage with nothing on screen, firing page-open
    -- side effects (preview flags, placeholder shows) AFTER the OnHide cleanup already cleared
    -- them -- they then stick until the next open (e.g. CDM buff previews staying visible when
    -- an override edit session tears down on panel close). Defer the rebuild to the next show instead; the on-show callback below consumes the flag before module OnShow handlers run.
    if not (mainFrame and mainFrame:IsShown()) then
        EllesmereUI._pendingForceRefresh = true
        return
    end
    -- Slow path: full teardown + rebuild
    local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll() or 0
    local savedTarget = scrollTarget

    -- Invalidate the current page's cache entry and destroy ONLY its wrapper. CRITICAL: do NOT
    -- call ClearContent() here -- it calls SetParent(nil) on ALL scrollChild children, which
    -- orphans other cached pages' wrappers. Those wrappers are still referenced by _pageCache and
    -- will be restored when the user switches back to that tab; if orphaned, Show() makes them appear detached and the layout breaks ("settings fly all over the screen" bug).
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
        EllesmereUI._buildingModule = activeModule
        EllesmereUI._buildingPage = activePage
        totalH = config.buildPage(activePage, wrapper, startY) or 600
        EllesmereUI._buildingModule = nil
        EllesmereUI._buildingPage = nil
        EllesmereUI._buildingSelector = nil
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
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
        local restored = math.min(savedScroll, maxScroll)
        scrollTarget = math.min(savedTarget, maxScroll)
        scrollFrame:SetVerticalScroll(restored)
        UpdateScrollThumb()
    end
end

-- Consume a rebuild that was requested while the panel was hidden (see the deferral
-- inside RefreshPage). Registered here, before any module files load, so it runs ahead
-- of module OnShow callbacks -- they then observe the freshly rebuilt page.
EllesmereUI:RegisterOnShow(function()
    if EllesmereUI._pendingForceRefresh then
        EllesmereUI._pendingForceRefresh = nil
        EllesmereUI:RefreshPage(true)
    end
end)

-- Public: snap the settings scroll back to the top (e.g. in resource bars clicking on a
-- simple section to the Advanced page)
function EllesmereUI:ScrollToTop()
    if scrollFrame and scrollFrame.SetVerticalScroll then
        scrollTarget = 0
        isSmoothing = false
        if smoothFrame then smoothFrame:Hide() end
        scrollFrame:SetVerticalScroll(0)
        UpdateScrollThumb()
    end
end

function EllesmereUI:GetActiveModule()
    return activeModule
end

function EllesmereUI:GetModuleTitle(folderName)
    local m = folderName and modules[folderName]
    return m and m.title
end

function EllesmereUI:SelectModule(folderName)
    if not modules[folderName] then return end
    -- The panel is not always built when we get here: on the session's first
    -- open the first-open split (see _SplitFirstOpen) makes Show()/Toggle()
    -- return BEFORE CreateMainFrame, so a caller that opens the panel and
    -- selects a module in the same execution arrives with headerFrame nil.
    -- Bail before activeModule is written -- a half-applied selection also
    -- suppresses CreateMainFrame's default-module pick, leaving a blank panel.
    if not headerFrame then return end
    if folderName == activeModule then return end
    -- Excluded modules are locked while an override editing session is
    -- active; blocking at the choke point covers every navigation path
    -- (sidebar, list rows, links), not just the grayed buttons.
    if EllesmereUI.SpecOverrides_EditSessionActive
       and EllesmereUI.SpecOverrides_EditSessionActive()
       and EllesmereUI.SpecOverrides_ModuleExcluded
       and EllesmereUI.SpecOverrides_ModuleExcluded(folderName) then
        return
    end

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

    -- Restore the old module page's inline-search filter and clear the search box BEFORE
    -- switching modules, while activeModule/activePage still point to the filtered page.
    -- SetText("") fires ApplyInlineSearch("") via OnTextChanged; doing this after the switch would target the new module and leave the old page stuck in its filtered layout.
    if tabBar and tabBar._searchBox and tabBar._searchBox:GetText() ~= "" then
        tabBar._searchBox:SetText("")
    end

    activeModule = folderName
    local config = modules[folderName]
    UpdateSidebarHighlight(folderName)
    headerFrame._title:SetText(EllesmereUI.L(config.title or folderName))
    local rb = footerFrame and footerFrame._resetBtn
    if rb and rb._label then
        local displayName = config.title or folderName
        for _, entry in ipairs(ADDON_ROSTER) do
            if entry.folder == folderName then displayName = entry.display; break end
        end
        rb._label:SetText(EllesmereUI.Lf("Reset %1$s", EllesmereUI.L(displayName)))
        rb._label:SetWidth(rb:GetWidth() * 0.85)
        rb._label:SetWordWrap(false)
        rb._label:SetMaxLines(1)
    end
    if EllesmereUI._UpdateResetButtonVisible then
        EllesmereUI._UpdateResetButtonVisible(config.onReset ~= nil)
    end
    headerFrame._desc:SetText(EllesmereUI.L(config.description or ""))
    BuildTabs(config.pages, config.disabledPages, config.disabledPageTooltips)
    -- Toolbar whitelists: the overrides icon and the inline search operate on suite data only
    -- (override capture, search index), so they render solely for whitelisted pages -- overrides:
    -- core modules; search: core modules + Global Settings. Foreign/companion pages get neither. (BuildTabs unconditionally shows the search frame; gate it here.)
    if tabBar then
        local core = config._euiCore == true
        if tabBar._searchFrame then
            tabBar._searchFrame:SetShown(core or folderName == EllesmereUI.GLOBAL_KEY)
        end
        if tabBar._specOvBtn then
            tabBar._specOvBtn:SetShown(core)
        end
    end
    local savedPage = _lastPagePerModule[folderName]
    -- Validate saved page still exists in this module's page list
    local validPage = nil
    if savedPage and config.pages then
        for _, p in ipairs(config.pages) do
            if p == savedPage then validPage = savedPage; break end
        end
    end
    local targetPage = validPage or (config.pages and config.pages[1])
    -- Clear activePage so SelectPage doesn't bail when the target page
    -- has the same name as the previous module's page (e.g. both have "General").
    activePage = nil
    if targetPage then
        self:SelectPage(targetPage)
    else
        activePage = nil
        ClearContent()
    end
end

-------------------------------------------------------------------------------
--  Sidebar search filter -- iterates the last order captured by RefreshSidebarStates, hides
--  any button whose addon display name and registered page names don't contain the query, and re-stacks the remaining ones at the top of the scroll area.
-------------------------------------------------------------------------------
function EllesmereUI._applySidebarSearch(text)
    text = text and text:lower() or ""
    local scrollChild = EllesmereUI._addonScrollChild
    if not scrollChild then return end

    -- Split the query into whitespace-delimited words. An entry matches only
    -- if EVERY word is found somewhere in its combined searchable text
    -- (display name + registered page names + module searchTerms).
    local queryWords = {}
    if text ~= "" then
        for word in text:gmatch("%S+") do
            queryWords[#queryWords + 1] = word
        end
    end

    -- Bilingual: index the localized form too, only when it differs from the
    -- original, so the English haystack stays byte-identical on English clients.
    local function addLocalized(parts, s)
        s = tostring(s)
        parts[#parts + 1] = s:lower()
        local loc = tostring(EllesmereUI.L(s))
        if loc ~= s then parts[#parts + 1] = loc:lower() end
    end

    local function childMatches(info)
        if #queryWords == 0 then return true end
        local parts = {}
        addLocalized(parts, info.display or "")
        local mod = modules[info.folder]
        if mod and mod.pages then
            for _, p in ipairs(mod.pages) do
                addLocalized(parts, p)
            end
        end
        if mod and mod.searchTerms then
            if type(mod.searchTerms) == "table" then
                for _, t in ipairs(mod.searchTerms) do
                    addLocalized(parts, t)
                end
            else
                addLocalized(parts, mod.searchTerms)
            end
        end
        local haystack = table.concat(parts, " ")
        for _, word in ipairs(queryWords) do
            if not haystack:find(word, 1, true) then return false end
        end
        return true
    end

    local y = 0
    local groupHeaders = EllesmereUI._sidebarGroupButtons
    local infoByFolder = EllesmereUI._addonInfoByFolder
    local GROUP_H  = EllesmereUI.SIDEBAR_GROUP_ROW_H
    local CHILD_H  = EllesmereUI.SIDEBAR_CHILD_ROW_H
    local GROUP_GAP = EllesmereUI.SIDEBAR_GROUP_GAP
    local firstVisibleGroup = true
    for _, group in ipairs(EllesmereUI.ADDON_GROUPS) do
        local header = groupHeaders[group.key]
        local visibleChildren = {}
        for _, folder in ipairs(group.members) do
            local info = infoByFolder[folder]
            local btn = info and sidebarButtons[folder]
            if btn and info then
                if childMatches(info) then
                    visibleChildren[#visibleChildren + 1] = btn
                else
                    btn:Hide()
                end
            end
        end
        if header then
            if #visibleChildren == 0 then
                header:Hide()
            else
                if not firstVisibleGroup then y = y + GROUP_GAP end
                firstVisibleGroup = false
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                header:Show()
                y = y + GROUP_H
            end
        end
        for _, btn in ipairs(visibleChildren) do
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            btn:Show()
            y = y + CHILD_H
        end
    end

    scrollChild:SetHeight(math.max(CHILD_H, y))
    if text ~= "" and EllesmereUI._addonScrollFrame then
        EllesmereUI._addonScrollFrame:SetVerticalScroll(0)
    end
end

-------------------------------------------------------------------------------
--  Show / Hide / Toggle
-------------------------------------------------------------------------------
local function RefreshSidebarStates()
    -- Refresh global settings button state (unchanged -- still a dedicated
    -- always-visible row above the grouped scroll area).
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

    local scrollChild = EllesmereUI._addonScrollChild
    if not scrollChild then return end

    local firstLoaded = nil
    local groupHeaders = EllesmereUI._sidebarGroupButtons
    local infoByFolder = EllesmereUI._addonInfoByFolder

    local GROUP_H   = EllesmereUI.SIDEBAR_GROUP_ROW_H
    local CHILD_H   = EllesmereUI.SIDEBAR_CHILD_ROW_H
    local GROUP_GAP = EllesmereUI.SIDEBAR_GROUP_GAP
    local y = 0
    for i, group in ipairs(EllesmereUI.ADDON_GROUPS) do
        if i > 1 then y = y + GROUP_GAP end
        local header = groupHeaders[group.key]
        if header then
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            header:Show()
            y = y + GROUP_H
        end
        for _, folder in ipairs(group.members) do
            local info = infoByFolder[folder]
            local btn = info and sidebarButtons[folder]
            if btn then
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                btn:Show()
                y = y + CHILD_H

                local loaded = info.alwaysLoaded or IsAddonLoaded(info.folder)
                local isSpecial = info.comingSoon or info.maintenance
                -- Coming-soon / maintenance rows render as disabled regardless
                -- of whether their placeholder folder happens to be loaded.
                local effectiveLoaded = loaded and not isSpecial
                btn._loaded = effectiveLoaded
                btn._notEnabled = (not loaded) and (not isSpecial)
                btn._dlIcon:Hide()

                -- Refresh sync icon state
                if btn._syncBtn and btn._syncBtn._refreshAlpha then
                    btn._syncBtn._refreshAlpha()
                end

                if effectiveLoaded and folder == activeModule then
                    btn._label:SetTextColor(NAV_SELECTED_TEXT.r, NAV_SELECTED_TEXT.g, NAV_SELECTED_TEXT.b, NAV_SELECTED_TEXT.a)
                    if btn._pwrBtn then btn._pwrBtn._tex:SetAlpha(1) end
                elseif effectiveLoaded then
                    btn._label:SetTextColor(NAV_ENABLED_TEXT.r, NAV_ENABLED_TEXT.g, NAV_ENABLED_TEXT.b, NAV_ENABLED_TEXT.a)
                    if btn._pwrBtn then btn._pwrBtn._tex:SetAlpha(1) end
                    if not firstLoaded then firstLoaded = folder end
                else
                    btn._label:SetTextColor(NAV_DISABLED_TEXT.r, NAV_DISABLED_TEXT.g, NAV_DISABLED_TEXT.b, NAV_DISABLED_TEXT.a)
                    if btn._pwrBtn then btn._pwrBtn._tex:SetAlpha(0.5) end
                    btn._indicator:Hide()
                    btn._glow:Hide()
                    btn._glowTop:Hide()
                    btn._glowBot:Hide()
                end
            end
        end
    end

    if scrollChild.SetHeight then
        scrollChild:SetHeight(math.max(CHILD_H, y))
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

    -- (Sidebar search no longer filters the addon rows -- the global search
    -- results popup replaced that behavior -- so there is no filter state to
    -- re-apply across refreshes anymore.)

    -- Re-assert override-session locks LAST: the recolor loop above paints by loaded
    -- state and would otherwise wash out locked rows on every module/page switch.
    if EllesmereUI.RefreshSidebarOverrideLocks then
        EllesmereUI.RefreshSidebarOverrideLocks()
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
        msg:SetText(EllesmereUI.L("Unlock Mode is where you can adjust\npositioning for all the elements of EllesmereUI"))

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

-- FIRST-OPEN SPLIT: the session's first open pays two heavy bills --
-- EnsureLoaded (LoadAddOn parsing the whole LoD options addon + every deferred
-- init) and the full panel build -- and the per-execution watchdog meters them
-- TOGETHER when both run in one hardware-event handler (field: "script ran too
-- long" aborting mid-sidebar on the very first open). Split them: the
-- triggering execution only LOADS; afterFn (the caller re-invoking itself)
-- runs next frame with its own fresh budget. Later opens (already loaded) stay
-- fully synchronous -- returns false and the caller proceeds as before.
-- EnsureLoaded itself stays synchronous: direct callers (DataBars' block
-- settings path) use the deferred inits' results in the same execution. A
-- failed load (options addon disabled) also returns false so the caller runs
-- the exact legacy failure path; _openPending swallows re-clicks during the
-- one-frame gap so a Toggle can't double-fire.
function EllesmereUI:_SplitFirstOpen(afterFn)
    if self._deferredLoaded then return false end
    self:EnsureLoaded()
    if not self._deferredLoaded then return false end
    self._openPending = true
    C_Timer.After(0, function()
        EllesmereUI._openPending = nil
        afterFn()
    end)
    return true
end

function EllesmereUI:Show()
    if self._openPending then return end
    if self:_SplitFirstOpen(function() EllesmereUI:Show() end) then return end
    CreateMainFrame()
    RefreshSidebarStates()
    mainFrame:Show()
    ShowSidebarUnlockTip()
end
function EllesmereUI:Hide()   if mainFrame then mainFrame:Hide() end end
function EllesmereUI:Toggle()
    if self._openPending then return end
    if self:_SplitFirstOpen(function() EllesmereUI:Toggle() end) then return end
    CreateMainFrame()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        RefreshSidebarStates()
        mainFrame:Show()
        ShowSidebarUnlockTip()
        -- Refresh widget disabled states (e.g. width-match may have
        -- changed in unlock mode since the page was last shown).
        if self.RefreshPage then self:RefreshPage() end
    end
end
function EllesmereUI:IsShown() return mainFrame and mainFrame:IsShown() end
function EllesmereUI:GetScrollFrame() return scrollFrame end
-- The main settings window frame. Used e.g. to scope popup click-catchers to the
-- panel instead of UIParent, so an open popup doesn't block world mouse/mouselook.
function EllesmereUI:GetMainFrame() return mainFrame end
function EllesmereUI:GetActivePage() return activePage end

--- Apply a user-defined panel scale on top of the pixel-perfect base scale.
--- @param userScale number  multiplier (1.0 = default, 0.5-1.5 range)
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
EllesmereUI.VERSION = "9.0.8"

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
            if EllesmereUI.ShowConfirmPopup then
                EllesmereUI:ShowConfirmPopup({
                    title       = "Out of Date",
                    message     = msg,
                    confirmText = "OK",
                })
            end
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
        -- Per-addon enable check: each EUI addon owns its own DB global; `key` is the profile
        -- sub-table name used inside that DB. Minimap, Friends, and QuestTracker no longer have
        -- a module-level enable toggle (loaded == enabled); their conflict entries rely on IsLoaded alone.
        local function AddonEnabled(key)
            local dbMap = {
                cursor = _G._ECL_AceDB,
            }
            local db = dbMap[key]
            if db and db.profile and db.profile[key] then
                return db.profile[key].enabled ~= false
            end
            return true -- assume enabled if DB not yet available
        end
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
            -- Suppress Ayije_CDM here if the CDM module's crash-prevention early-bail already fired -- its own popup supersedes this one.
            local suppressedBySpecific =
                (entry.addon == "Ayije_CDM" and _G._EUI_ECME_HandledAyijeCDM)
            if entry.addon ~= EUI_HOST_ADDON and IsLoaded(entry.addon)
               and moduleActive and not suppressedBySpecific then
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
                EllesmereUI.Print("|cffff6060[EllesmereUI]|r " .. msg:gsub("\n", " "))
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
           or EllesmereUI._ptrManagersIntroPending or EllesmereUI._launchVideoIntroPending then return end
        if EllesmereUI._RunConflictCheck then EllesmereUI._RunConflictCheck() end
    end
end)

SLASH_EUIOPTIONS1 = "/eui"
SLASH_EUIOPTIONS2 = "/ellesmere"
SLASH_EUIOPTIONS3 = "/ellesmereui"
-- Defer slash command actions by one frame to avoid tainting Blizzard's ParseText -> ClearChat -> UpdateHeader chain when typed in a BN_WHISPER edit box (secret tellTarget value).
SlashCmdList.EUIOPTIONS = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
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
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
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
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
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
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Party Mode addon is not loaded.")
        end
    end)
end

-- Support: reset all one-time hint flags so they show again
SLASH_EUIRESETHINT1 = "/euiresethint"

-- Quick-access: /unlock opens Unlock Mode directly
SLASH_EUIUNLOCK1 = "/unlock"
SlashCmdList.EUIUNLOCK = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
            return
        end
        EllesmereUI:EnsureUnlockCore()
        if EllesmereUI._openUnlockMode then
            EllesmereUI._openUnlockMode()
        else
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Unlock Mode is not available.")
        end
    end)
end

SlashCmdList.EUIRESETHINT = function()
    C_Timer.After(0, function()
        if EllesmereUIDB then
            EllesmereUIDB.previewHintDismissed = nil
            EllesmereUIDB.unlockTipSeen = nil
            EllesmereUIDB.sidebarUnlockTipSeen = nil
            EllesmereUIDB.rfEyeHintSeen = nil
            EllesmereUIDB.bmIconHintDismissed = nil
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
        SetCVar(cv, newVal)
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
            (EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE")
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
            if EllesmereUI.UpdateDevModeIndicator then EllesmereUI.UpdateDevModeIndicator() end
        end)
    end)
end

-- Open the panel with a specific addon's tab selected
function EllesmereUI:ShowModule(folderName)
    if InCombatLockdown() then
        EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
        return
    end
    if self._openPending then return end
    -- First-open split (see _SplitFirstOpen): the combat check above stays in
    -- the click execution; the deferred re-invoke re-checks it harmlessly.
    if self:_SplitFirstOpen(function() EllesmereUI:ShowModule(folderName) end) then return end
    CreateMainFrame()
    RefreshSidebarStates()
    mainFrame:Show()
    ShowSidebarUnlockTip()
    if modules[folderName] then
        self:SelectModule(folderName)
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
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Options closed -- entering combat.")
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
    --  Child addons call EllesmereUI.RegisterEscapeClose(frame) to opt in.
    ---------------------------------------------------------------------------
    do
        local escFrames = {}
        local proxy = CreateFrame("Frame", "EllesmereUI_EscapeProxy", UIParent)
        proxy:Hide()
        tinsert(UISpecialFrames, "EllesmereUI_EscapeProxy")

        proxy:SetScript("OnHide", function(self)
            for i = #escFrames, 1, -1 do
                if escFrames[i]:IsShown() then
                    escFrames[i]:Hide()
                    for j = 1, #escFrames do
                        if escFrames[j]:IsShown() then self:Show(); return end
                    end
                    return
                end
            end
        end)

        local function RefreshProxy()
            for i = 1, #escFrames do
                if escFrames[i]:IsShown() then proxy:Show(); return end
            end
            proxy:Hide()
        end

        function EllesmereUI.RegisterEscapeClose(frame)
            escFrames[#escFrames + 1] = frame
            frame:HookScript("OnShow", RefreshProxy)
            frame:HookScript("OnHide", RefreshProxy)
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
                EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
                return
            end
            HideUIPanel(GameMenuFrame)
            EllesmereUI:Toggle()
        end)
        EllesmereUI._GetFFD(GameMenuFrame).euiBtn = btn

        local unlockBtn = CreateFrame("Button", "EllesmereUI_UnlockMenuButton", GameMenuFrame, "MainMenuFrameButtonTemplate")
        unlockBtn:SetSize(200, 35)
        unlockBtn:SetScript("OnClick", function()
            if InCombatLockdown() then
                EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot toggle Unlock Mode during combat.")
                return
            end
            HideUIPanel(GameMenuFrame)
            if EllesmereUI.ToggleUnlockMode then
                EllesmereUI:ToggleUnlockMode()
            end
        end)
        EllesmereUI._GetFFD(GameMenuFrame).unlockBtn = unlockBtn

        -- Skin our custom buttons the same way as pooled Blizzard buttons
        if _reskinMenu then
            for _, customBtn in ipairs({ btn, unlockBtn }) do
                for j = 1, select("#", customBtn:GetRegions()) do
                    local r = select(j, customBtn:GetRegions())
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
                    local euiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or nil
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
            local euiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or "Fonts\\FRIZQT__.TTF"
            local btnFontSize = 13
            -- Branded two-tone labels are the default (native mode, or when BlizzardSkin is not
            -- loaded) -- applied via inline color codes in SetText, which works with the
            -- pause-menu reskin off too. Only an explicitly chosen Element & Text Color mode switches to a plain label + whole-string recolor (inline codes would override SetTextColor otherwise).
            local elemMode = EllesmereUI._getPopupMenuElementMode
                and EllesmereUI._getPopupMenuElementMode() or "native"
            local brandHex
            if elemMode == "native" then
                local EG = EllesmereUI.ELLESMERE_GREEN or { r = .27, g = .86, b = .49 }
                brandHex = string.format("|cff%02x%02x%02x",
                    math.floor(EG.r * 255 + 0.5), math.floor(EG.g * 255 + 0.5),
                    math.floor(EG.b * 255 + 0.5))
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
        local theme = EllesmereUIDB.activeTheme or "EllesmereUI"
        ELLESMERE_GREEN._themeEnabled = true
        local themeR, themeG, themeB = EllesmereUI.ResolveThemeColor(theme)
        -- Apply theme color to the window background only. The EUI Options Theme
        -- is a SEPARATE, global control from the UI accent color (per-profile).
        if EllesmereUI._applyBgTint then
            EllesmereUI._applyBgTint(themeR, themeG, themeB)
        end
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
            local on = db and db.showSpellID
                and (db.spellIDModifier or "none") == "none"
            pcall(C_CVar.SetCVar, "tooltipShowAuraSpellIDs", on and "1" or "0")
        end
        do
            -- PLAYER_ENTERING_WORLD, not PLAYER_LOGIN: the engine settles its
            -- session CVars after login and clobbered the early write -- aura
            -- IDs stayed off until the user re-toggled the option (field-
            -- reported). Kept registered: a re-assert per zone-in is one
            -- pcall'd SetCVar and survives any later engine reset.
            local cvarBoot = CreateFrame("Frame")
            cvarBoot:RegisterEvent("PLAYER_ENTERING_WORLD")
            cvarBoot:SetScript("OnEvent", function()
                EllesmereUI.SyncAuraSpellIDCVar()
            end)
        end

        local function SpellIDTooltipHook(tooltip, data)
            if not (EllesmereUIDB and EllesmereUIDB.showSpellID) then return end
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
                local iconID = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(data.id)
                    or (GetSpellTexture and GetSpellTexture(data.id))
                if iconID then
                    tooltip:AddDoubleLine("IconID", tostring(iconID), 1, 1, 1, 1, 1, 1)
                end
            end
            tooltip:Show()
        end

        local function ItemIDTooltipHook(tooltip, data)
            if not (EllesmereUIDB and EllesmereUIDB.showSpellID) then return end
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
            if not (EllesmereUIDB and EllesmereUIDB.showSpellID) then return end
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
                local iconID = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
                    or (GetSpellTexture and GetSpellTexture(spellID))
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
                (db.showSpellID and KeyMatchesModifier(key, db.spellIDModifier or "none"))
                or (db.showItemMaxStacks and KeyMatchesModifier(key, db.itemStackModifier or "none"))
            if not relevant then return end
            if GameTooltip and GameTooltip:IsShown() and GameTooltip.RefreshData then
                GameTooltip:RefreshData()
            end
        end)
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
            if InCombatLockdown() then
                EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
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
    end

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
                    EllesmereUI:SelectPage(activePage)
                end,
            })
        end
    end
end)

-------------------------------------------------------------------------------
--  Shared Visibility System -- unified visibility dropdown values, checkbox dropdown items, and runtime checks used by CDM, Action Bars, Resource Bars, and Unit Frames.
-------------------------------------------------------------------------------

-- Dropdown 1: Visibility mode
EllesmereUI.VIS_VALUES = {
    never      = "Never",
    always     = "Always",
    mouseover  = "Mouseover",
    in_combat      = "In Combat",
    out_of_combat  = "Out of Combat",
    in_raid        = "In Raid Group",
    in_party   = "In Party",
    solo       = "Solo",
}
EllesmereUI.VIS_ORDER = { "never", "always", "mouseover", "in_combat", "out_of_combat", "---", "in_raid", "in_party", "solo" }

-- Action Bars variant: adds "When Dragonriding". The secure action bars (1-8, stance, pet)
-- express it as [advflyable,flying] in their state driver, which re-evaluates the flying
-- transition in real time. Lua-side modules catch the same transition via the gliding edge events registered in EllesmereUI_Visibility.lua (gated on EllesmereUI._hasGlidingEvent).
EllesmereUI.VIS_VALUES_AB = {
    never      = "Never",
    always     = "Always",
    mouseover  = "Mouseover",
    in_combat      = "In Combat",
    out_of_combat  = "Out of Combat",
    show_dragonriding = "When Dragonriding",
    show_not_dragonriding = "When Not Dragonriding",
    in_raid        = "In Raid Group",
    in_party   = "In Party",
    solo       = "Solo",
}
EllesmereUI.VIS_ORDER_AB = { "never", "always", "mouseover", "in_combat", "out_of_combat", "show_dragonriding", "show_not_dragonriding", "---", "in_raid", "in_party", "solo" }

-- CDM variant (no mouseover -- CDM bars don't support mouseover visibility)
EllesmereUI.VIS_VALUES_CDM = {
    never          = "Never",
    always         = "Always",
    in_combat      = "In Combat",
    out_of_combat  = "Out of Combat",
    in_raid        = "In Raid Group",
    in_party       = "In Party",
    solo           = "Solo",
}
EllesmereUI.VIS_ORDER_CDM = { "never", "always", "in_combat", "out_of_combat", "---", "in_raid", "in_party", "solo" }

-- Checkbox dropdown 2: Visibility Options (keys match DB fields). Every entry is
-- evaluated by CheckVisibilityOptions below, so any module using that evaluator
-- may offer the whole list; the skyriding edge (PLAYER_CAN_GLIDE_CHANGED /
-- PLAYER_IS_GLIDING_CHANGED) is registered by the dispatcher and by every
-- self-evaluating module already.
EllesmereUI.VIS_OPT_ITEMS = {
    { key = "visOnlyInstances",    label = "Only Show in Instances" },
    { key = "visHideHousing",      label = "Hide in Housing" },
    { key = "visOnlyHousing",      label = "Only Show in Housing",
      tooltip = "This element will only show while you are inside a house or plot" },
    { key = "visHideMounted",      label = "Hide when Mounted" },
    { key = "visHideDragonriding", label = "Hide when Skyriding Mounted",
      tooltip = "Hides this element while you are on a skyriding (glide-capable) mount, where Blizzard shows its vigor HUD." },
    { key = "visOnlyMounted",      label = "Only Show when Mounted",
      tooltip = "This element will only show while you are mounted" },
    { key = "visHideNoTarget",     label = "Hide without Target",
      tooltip = "*Blizzard's auto targeting (soft target) setting can cause brief flickering when your actual target dies but a soft-target is still active." },
    { key = "visHideNoEnemy",      label = "Hide without Enemy Target",
      tooltip = "This bar will only show if you have an enemy targeted" },
}

-- Every visibility-option DB field, including the four counter-lane keys that have
-- no row in the legacy VIS_OPT_ITEMS list above (they exist only as Hide/Show lanes
-- in the unified Visibility row, EllesmereUI.VIS_ROW_ITEMS). Sync copies and equality
-- checks iterate THIS list so a lane set through the unified row is never dropped by
-- a module still building the legacy pair of dropdowns.
EllesmereUI.VIS_OPT_KEYS = {
    "visOnlyInstances", "visHideInstances",
    "visHideHousing", "visOnlyHousing",
    "visHideMounted", "visOnlyMounted",
    "visHideDragonriding", "visOnlySkyriding",
    "visHideNoTarget", "visHideWithTarget",
    "visHideNoEnemy", "visHideWithEnemy",
}

-- Cache player class once at load time (never changes).
local _, _playerClass = UnitClass("player")

-- Druid mount-like form spell IDs. Travel Form applies a player aura with spell ID 783
-- regardless of the active ground/swim/fly subform, so an aura lookup is the most reliable cross-patch detection.
local DRUID_MOUNT_FORM_SPELLS = {
    783,    -- Travel Form
    1066,   -- Aquatic Form
    33943,  -- Flight Form
    40120,  -- Swift Flight Form
    165962, -- Flight Form (variant)
    210053, -- Mount Form (variant)
}

-- Instanced-content probe shared by the Instances axis' veto chain and its per-axis
-- "any" match verdict. A garrison reports a difficulty but is not instanced content
-- for this axis, which is why the difficulty test alone is not enough.
function EllesmereUI.IsInInstancedContent()
    local _, iType, diffID = GetInstanceInfo()
    diffID = tonumber(diffID) or 0
    if diffID <= 0 then return false end
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
        return false
    end
    return iType == "party" or iType == "raid" or iType == "scenario"
        or iType == "arena" or iType == "pvp"
end

-- Runtime check: returns true if the element should be HIDDEN by visibility options.
-- `opts` is the settings table containing the vis option booleans.
function EllesmereUI.IsPlayerMountedLike()
    -- Fast path for regular mounts.
    if IsMounted and IsMounted() then return true end

    -- Only druids have mount-like shapeshift forms.
    if _playerClass ~= "DRUID" then return false end

    -- Engine form category first: ground Travel and Mount Form report 3, Aquatic 4, Flight 27.
    -- Spell-agnostic, so it keeps working when the form aura's spell ID drifts across patches
    -- (Flight Form stopped matching the aura list below); no collision with combat forms (Cat 1, Bear 5, Moonkin 31).
    if GetShapeshiftFormID then
        local formID = GetShapeshiftFormID()
        if formID == 3 or formID == 4 or formID == 27 then
            return true
        end
    end

    -- Aura fallback: the Travel Form buff is present on the player
    -- whenever the druid is shifted, regardless of ground/swim/fly subform.
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for i = 1, #DRUID_MOUNT_FORM_SPELLS do
            if C_UnitAuras.GetPlayerAuraBySpellID(DRUID_MOUNT_FORM_SPELLS[i]) then
                return true
            end
        end
    end

    return false
end

-- canGlide is already scoped to being on a glide-capable mount or form, so it
-- needs no mount-shaped prefilter. IsPlayerMountedLike used to gate this and
-- hard-returns false off DRUID, which silently excluded the non-druid flight
-- forms (Dracthyr Soar, Haranir) from "Hide when Skyriding Mounted". Deliberately
-- no IsFlying() term: unlike the show/hide visibility MODES, this option fires
-- on the ground too, as soon as the skyriding bar is available.
function EllesmereUI.IsPlayerSkyriding()
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local _, canGlide = C_PlayerInfo.GetGlidingInfo()
        return canGlide == true
    end
    return false
end

-- Non-macro visibility subset: the options that CAN'T be expressed in a secure [macro] condition
-- and must be evaluated in Lua. Used by secure action bar frames that delegate the macro-expressible options (target/combat/group) to their state-visibility driver and only need Lua handling for these three.
-- skipMountAxis: the caller's secure state driver already carries [mounted]/[nomounted]
-- clauses that self-update inside combat. Evaluating the mount axis here too would let
-- Lua clobber the driver with a literal "hide" that cannot re-evaluate until combat ends
-- (see BuildVisibilityString in EllesmereUIActionBars.lua). Such callers pass true and
-- keep their own narrower mount check for the shapeshift forms [mounted] cannot see.
function EllesmereUI.CheckVisibilityOptionsNonMacro(opts, skipMountAxis)
    if not opts then return false end

    -- Any match: the lanes are disjuncts, not vetoes; EvalVisibilityExtended (or the
    -- secure driver build path) owns the combined verdict.
    if opts.visibilityMatch == "any" then return false end

    -- Instances axis: Only Show in Instances / Hide in Instances share one probe.
    if opts.visOnlyInstances or opts.visHideInstances then
        local inInstance = EllesmereUI.IsInInstancedContent()
        if opts.visOnlyInstances and not inInstance then return true end
        if opts.visHideInstances and inInstance then return true end
    end

    -- Hide in Housing
    if opts.visHideHousing then
        if C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then
            return true
        end
    end

    -- Only Show in Housing (inverse of the above; same probe, same edges)
    if opts.visOnlyHousing then
        if not (C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot()) then
            return true
        end
    end

    if not skipMountAxis then
        -- Hide when Mounted (includes druid travel/flight/aquatic forms)
        if opts.visHideMounted then
            if EllesmereUI.IsPlayerMountedLike and EllesmereUI.IsPlayerMountedLike() then return true end
        end

        -- Only Show when Mounted (inverse; druid mount-like forms count as mounted
        -- here too -- secure action bars carry a [nomounted] clause instead, which
        -- cannot see forms, see BuildVisibilityString)
        if opts.visOnlyMounted then
            if not (EllesmereUI.IsPlayerMountedLike and EllesmereUI.IsPlayerMountedLike()) then return true end
        end
    end

    -- Skyriding-mount axis (glide capability, ground included -- NOT the airborne
    -- show_dragonriding / show_not_dragonriding mode pair, which additionally
    -- requires IsFlying; see EllesmereUI.IsAirborneSkyriding). No secure macro token
    -- expresses "ground included", so this stays Lua-only for every caller; it returns
    -- the truthy marker "mountaxis" so a secure-driver caller can bake a combat escape
    -- hatch into what it writes (a bare "hide" cannot re-evaluate once combat starts).
    if opts.visHideDragonriding then
        if EllesmereUI.IsPlayerSkyriding and EllesmereUI.IsPlayerSkyriding() then return "mountaxis" end
    end

    if opts.visOnlySkyriding then
        if not (EllesmereUI.IsPlayerSkyriding and EllesmereUI.IsPlayerSkyriding()) then return "mountaxis" end
    end

    return false
end

function EllesmereUI.CheckVisibilityOptions(opts)
    if not opts then return false end

    -- Any match: the lanes are disjuncts, not vetoes; EvalVisibilityExtended (or the
    -- secure driver build path) owns the combined verdict.
    if opts.visibilityMatch == "any" then return false end

    -- Instances / housing / mounted (shared with secure-frame fast path).
    if EllesmereUI.CheckVisibilityOptionsNonMacro(opts) then return true end

    -- Target axis
    if opts.visHideNoTarget then
        if not UnitExists("target") then return true end
    end
    if opts.visHideWithTarget then
        if UnitExists("target") then return true end
    end

    -- Enemy-target axis
    if opts.visHideNoEnemy then
        if not (UnitExists("target") and UnitCanAttack("player", "target")) then return true end
    end
    if opts.visHideWithEnemy then
        if UnitExists("target") and UnitCanAttack("player", "target") then return true end
    end

    return false
end

-- Option-lane axes: one axis per condition (Show lane, Hide lane, probe() = holds now),
-- read by the "any" match for per-axis verdicts; the "all" veto chain above is untouched.
-- luaOnly = no macro conditional exists, so the secure driver resolves the axis in Lua.
EllesmereUI.VIS_OPT_AXES = {
    { show = "visOnlyInstances", hide = "visHideInstances", luaOnly = true,
      probe = function() return EllesmereUI.IsInInstancedContent() end },
    { show = "visOnlyHousing", hide = "visHideHousing", luaOnly = true,
      probe = function()
          return (C_Housing and C_Housing.IsInsideHouseOrPlot
              and C_Housing.IsInsideHouseOrPlot()) and true or false
      end },
    { show = "visOnlyMounted", hide = "visHideMounted",
      probe = function() return EllesmereUI.IsPlayerMountedLike() end },
    { show = "visOnlySkyriding", hide = "visHideDragonriding", luaOnly = true,
      probe = function() return EllesmereUI.IsPlayerSkyriding() end },
    -- needsEdge: [exists]/[harm] re-evaluate on soft-target changes that
    -- UnitExists("target") ignores; a consumer without those edges resolves the axis in Lua.
    { show = "visHideNoTarget", hide = "visHideWithTarget", needsEdge = "softTarget",
      probe = function() return UnitExists("target") and true or false end },
    { show = "visHideNoEnemy", hide = "visHideWithEnemy", needsEdge = "softTarget",
      probe = function()
          return (UnitExists("target") and UnitCanAttack("player", "target")) and true or false
      end },
}

-- Whether this axis has to be resolved in Lua for a consumer with these edges.
-- `edges` is the set of event edges the consumer actually watches, e.g.
-- { softTarget = true } for Action Bars, which owns that machinery.
function EllesmereUI.VisAxisIsLuaOnly(ax, edges)
    if ax.luaOnly then return true end
    return ax.needsEdge ~= nil and not (edges and edges[ax.needsEdge])
end

-- Per-axis tally for the "any" match. filter: nil counts every axis, "luaOnly" only
-- the ones this consumer must resolve in Lua, "driver" only the ones it can compile.
-- Returns how many axes are constrained and how many of those currently match.
function EllesmereUI.TallyVisibilityOptionAxes(opts, filter, edges)
    local constrained, passed = 0, 0
    if not opts then return constrained, passed end
    local axes = EllesmereUI.VIS_OPT_AXES
    for i = 1, #axes do
        local ax = axes[i]
        local luaOnly = EllesmereUI.VisAxisIsLuaOnly(ax, edges)
        local skip = (filter == "luaOnly" and not luaOnly)
                  or (filter == "driver" and luaOnly)
        if not skip then
            local wantShow, wantHide = opts[ax.show], opts[ax.hide]
            -- Both lanes at once is the contradiction the row already prevents on
            -- click; count it as unconstrained rather than as an axis that can never
            -- match, so a hand-edited store cannot lock an Any selection to hidden.
            if wantShow and not wantHide then
                constrained = constrained + 1
                if ax.probe() then passed = passed + 1 end
            elseif wantHide and not wantShow then
                constrained = constrained + 1
                if not ax.probe() then passed = passed + 1 end
            end
        end
    end
    return constrained, passed
end

-- Runtime check: returns true if the element should be SHOWN based on the visibility mode
-- dropdown value. `mode` is the dropdown string; `state` is a table: { inCombat, inRaid, inParty }.
function EllesmereUI.CheckVisibilityMode(mode, state)
    if mode == "disabled" then return false end
    if mode == "never" then return false end
    if mode == "in_combat" then return state.inCombat end
    if mode == "out_of_combat" then return not state.inCombat end
    if mode == "in_raid" then return state.inRaid end
    if mode == "in_party" then return state.inParty end
    if mode == "solo" then return not state.inRaid and not state.inParty end
    if mode == "show_dragonriding" then
        -- Mirrors the secure-macro [advflyable,flying] driver: show only while airborne and
        -- glide-capable (skyriding mounts and flight forms alike). The shared predicate lives in
        -- EllesmereUI_Visibility.lua and is also used by the multi-select visibility engine.
        return (EllesmereUI.IsAirborneSkyriding and EllesmereUI.IsAirborneSkyriding()) or false
    end
    if mode == "show_not_dragonriding" then
        -- Exact inverse of show_dragonriding: show whenever NOT airborne and
        -- glide-capable (skyriding mounts and flight forms alike).
        return not (EllesmereUI.IsAirborneSkyriding and EllesmereUI.IsAirborneSkyriding())
    end
    -- "always" and "mouseover" both return true (mouseover handled separately)
    return true
end

-------------------------------------------------------------------------------
--  External weak-keyed lookup table for frame state (prevents tainting Blizzard
--  frames). Stored on EllesmereUI to avoid the 200-local cap in this file.
-------------------------------------------------------------------------------
EllesmereUI._FFD = EllesmereUI._FFD or setmetatable({}, { __mode = "k" })
function EllesmereUI._GetFFD(frame)
    local d = EllesmereUI._FFD[frame]
    if not d then d = {}; EllesmereUI._FFD[frame] = d end
    return d
end

-------------------------------------------------------------------------------
--  Third-Party Skin Registration (public API) -- other addons call
--  EllesmereUI.RegisterSkin("TheirAddon", function(S) ... end) to have their frames painted in
--  the EUI house style. This stub only queues: the Blizz UI Enhanced child addon drains the
--  queue at PLAYER_LOGIN (or immediately for late/LoD registrations) and passes the skinning
--  facade S. Queuing keeps registration order-independent -- third-party addons may load before
--  or after the child -- and the API stays callable (a silent no-op) when the child addon is
--  disabled. Developer guide: SKINNING_API.md. Stored on EllesmereUI to avoid the 200-local cap.
-------------------------------------------------------------------------------
EllesmereUI._skinRegistry = EllesmereUI._skinRegistry or {}
function EllesmereUI.RegisterSkin(name, applyFn)
    if type(name) ~= "string" or name == "" or type(applyFn) ~= "function" then return end
    local reg = EllesmereUI._skinRegistry
    for i = 1, #reg do
        if reg[i].name == name then return end
    end
    local entry = { name = name, apply = applyFn }
    reg[#reg + 1] = entry
    if EllesmereUI._DispatchSkinRegistration then
        EllesmereUI._DispatchSkinRegistration(entry)
    end
    return true
end

-------------------------------------------------------------------------------
--  Alpha-Zero Visibility Helper
--  For anchor-participating container frames: use alpha 0 + EnableMouse(false)
--  instead of :Hide() so the frame stays in the layout engine with valid bounds.
--  Sub-widgets (icons, text, glows) inside these frames still use :Hide()/:Show().
-------------------------------------------------------------------------------
function EllesmereUI.SetElementVisibility(frame, visible)
    if not frame then return end
    if visible then
        frame:SetAlpha(EllesmereUI._GetFFD(frame).restoreAlpha or 1)
        frame:EnableMouse(EllesmereUI._GetFFD(frame).restoreMouse or false)
    else
        if frame:GetAlpha() > 0 then
            EllesmereUI._GetFFD(frame).restoreAlpha = frame:GetAlpha()
        end
        EllesmereUI._GetFFD(frame).restoreMouse = frame:IsMouseEnabled()
        frame:SetAlpha(0)
        frame:EnableMouse(false)
    end
end

-------------------------------------------------------------------------------
--  Blizzard Cast Bar Event Ownership -- standalone cast bar addons claim Blizzard's
--  player/pet cast bars by unregistering their events. oUF's Castbar element writes the same
--  state -- it silences those frames when it enables on the player frame and re-arms them when
--  it disables -- so EUI can hand a user's cast bar back to Blizzard on top of the addon they
--  replaced it with. EUI hides Blizzard's bar by re-parenting it (see SetPlayerCastBarSuppressed),
--  so it never needs the event state changed: wrap anything that flips it in Capture/Restore and only ever undo EUI's own writes.
-------------------------------------------------------------------------------
function EllesmereUI._BlizzCastBars()
    local bars = EllesmereUI._blizzCastBarList
    if bars then return bars end

    bars = {}
    if PlayerCastingBarFrame then bars[#bars + 1] = { frame = PlayerCastingBarFrame, unit = "player" } end
    if PetCastingBarFrame then bars[#bars + 1] = { frame = PetCastingBarFrame, unit = "pet" } end
    EllesmereUI._blizzCastBarList = bars

    for i = 1, #bars do
        local bar = bars[i]
        -- An UnregisterAllEvents outside one of our own Capture/Restore windows is another
        -- addon claiming the frame: EUI drops its claim and records the claim as foreign.
        -- "Foreign" is tracked separately from "not ours" because those are very different states -- see RestoreBlizzCastBarEvents.
        hooksecurefunc(bar.frame, "UnregisterAllEvents", function()
            if not EllesmereUI._blizzCastBarSnapshot then
                bar.owned = false
                bar.foreign = true
            end
        end)
    end
    return bars
end

function EllesmereUI.CaptureBlizzCastBarEvents()
    local bars = EllesmereUI._BlizzCastBars()
    local snapshot = {}
    for i = 1, #bars do
        snapshot[i] = bars[i].frame:IsEventRegistered("UNIT_SPELLCAST_START") and true or false
    end
    EllesmereUI._blizzCastBarSnapshot = snapshot
end

function EllesmereUI.RestoreBlizzCastBarEvents()
    local snapshot = EllesmereUI._blizzCastBarSnapshot
    if not snapshot then return end
    EllesmereUI._blizzCastBarSnapshot = nil

    local bars = EllesmereUI._blizzCastBarList
    for i = 1, #bars do
        local bar = bars[i]
        local live = bar.frame:IsEventRegistered("UNIT_SPELLCAST_START") and true or false
        if live ~= snapshot[i] then
            if not live then
                bar.owned = true
            elseif bar.owned then
                bar.owned = false
            elseif bar.foreign then
                -- Another addon silenced this frame and we just re-registered it
                -- on the way past; put it back the way we found it instead of
                -- resurrecting Blizzard's cast bar next to theirs.
                bar.frame:UnregisterAllEvents()
                bar.frame:Hide()
            else
                -- Registered inside our own window with nobody claiming it.
                -- That is EUI's own bookkeeping having lost track (a silence
                -- that produced no transition to observe), NOT another addon,
                -- so re-silencing here would kill Blizzard's cast bar for the
                -- session with no way back short of a reload. Leave it armed:
                -- a visible Blizzard bar is something the user can turn off, a
                -- dead one is not.
            end
        end
    end
end

-- The cast events Blizzard's bars listen on, registered per unit. Mirrors the set oUF's
-- Castbar element restores when it disables, which is the only path that has ever successfully re-armed these frames.
--
-- SetUnit is deliberately NOT used to re-arm: its body is guarded on `self.unit ~= unit`, and
-- the frame still holds the unit Blizzard assigned at load, so passing that same unit registers
-- nothing at all. Forcing the guard open is worse -- SetUnit runs StopAnims -> StopFinishAnims,
-- which iterates a table that cannot be accessed while tainted, so from addon execution it throws
-- outright ("attempted to iterate a table that cannot be accessed while tainted") and takes down
-- whatever called it. Registering the events directly is what oUF does, is taint-clean, and touches no Blizzard code at all.
local BLIZZ_CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

-- Give Blizzard's cast bars their event wiring back, unless another addon has claimed them.
-- Covers the pet bar too: oUF silences both and only re-arms them from its Castbar element's
-- Disable, so any release path that does not run that (the element was never enabled to begin with) leaves both dead.
function EllesmereUI.RearmBlizzCastBars()
    local bars = EllesmereUI._blizzCastBarList
    if not bars then return end
    for i = 1, #bars do
        local bar = bars[i]
        if not bar.foreign and not bar.frame:IsEventRegistered("UNIT_SPELLCAST_START") then
            bar.owned = false
            for j = 1, #BLIZZ_CAST_EVENTS do
                bar.frame:RegisterUnitEvent(BLIZZ_CAST_EVENTS[j], bar.unit)
            end
            bar.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
            if bar.unit == "pet" then bar.frame:RegisterEvent("UNIT_PET") end
        end
    end
end

-- Arm the ownership hooks at load rather than on first capture. Rearm's only shield against
-- resurrecting a bar a standalone cast bar addon silenced is the foreign flag, and that flag can
-- only be set once the UnregisterAllEvents hooks exist -- a lazy first capture at PLAYER_LOGIN
-- leaves every earlier silence unattributed. File scope runs during the ADDON_LOADED sequence,
-- before any addon's PLAYER_LOGIN handler, so this closes the window to everything except
-- file-scope silences in addons that load before EUI. Guarded on BOTH frames: the list is cached on first build, so building it while either frame is missing would drop that bar for the whole session.
if PlayerCastingBarFrame and PetCastingBarFrame then
    EllesmereUI._BlizzCastBars()
end

-------------------------------------------------------------------------------
--  Shared Player Cast Bar Suppression -- multiple EUI modules can temporarily suppress
--  Blizzard's player cast bar while they render their own. Centralized here so modules cooperate
--  with each other and leave third-party visibility control alone once no EUI module is actively using a replacement bar.
-------------------------------------------------------------------------------
function EllesmereUI.SetPlayerCastBarSuppressed(owner, suppressed)
    if not owner or owner == "" then return end

    local owners = EllesmereUI._playerCastBarSuppressors
    if not owners then
        owners = {}
        EllesmereUI._playerCastBarSuppressors = owners
    end

    if suppressed then
        owners[owner] = true
    else
        owners[owner] = nil
    end

    local blizzBar = PlayerCastingBarFrame
    if not blizzBar then return end

    local shouldSuppress = next(owners) ~= nil
    local hiddenParent = EllesmereUI._playerCastBarHiddenParent

    if shouldSuppress then
        if not hiddenParent then
            hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
            EllesmereUI._playerCastBarHiddenParent = hiddenParent
        end

        if blizzBar:GetParent() ~= hiddenParent then
            EllesmereUI._GetFFD(blizzBar).origParent = blizzBar:GetParent()
        end
        EllesmereUI._GetFFD(blizzBar).castBarSuppressed = true

        -- Skip the re-parent while Edit Mode is open: SetParent fires Blizzard's synchronous
        -- layout handlers in this execution, and the UnitFrames Edit-Mode-close hook re-applies this state afterwards.
        if blizzBar:GetParent() ~= hiddenParent
            and not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
            blizzBar:SetParent(hiddenParent)
        end

        -- Edit Mode tries to re-anchor the cast bar during layout changes; keep re-applying our hidden parent while any EUI owner suppresses it.
        if not EllesmereUI._GetFFD(blizzBar).setParentHooked then
            EllesmereUI._GetFFD(blizzBar).setParentHooked = true
            hooksecurefunc(blizzBar, "SetParent", function(self, newParent)
                if EllesmereUI._GetFFD(self).castBarSuppressed and newParent ~= EllesmereUI._playerCastBarHiddenParent then
                    C_Timer.After(0, function()
                        -- Never re-parent while Edit Mode is open, even from a timer: SetParent
                        -- fires Blizzard's synchronous layout handlers under addon taint and poisons the manager's state for its next pass (the Edit Mode close hook in UnitFrames re-applies suppression).
                        if EllesmereUI._GetFFD(self).castBarSuppressed
                           and not InCombatLockdown()
                           and not (EditModeManagerFrame and EditModeManagerFrame:IsShown())
                           and self:GetParent() ~= EllesmereUI._playerCastBarHiddenParent
                        then
                            self:SetParent(EllesmereUI._playerCastBarHiddenParent)
                        end
                    end)
                end
            end)
        end

        local selection = blizzBar.Selection
        if selection then
            if not EllesmereUI._GetFFD(selection).suppressed then
                EllesmereUI._GetFFD(selection).restoreAlpha = selection:GetAlpha()
                EllesmereUI._GetFFD(selection).restoreMouse = selection:IsMouseEnabled()
            end
            EllesmereUI._GetFFD(selection).suppressed = true
            selection:SetAlpha(0)
            selection:EnableMouse(false)

            if not EllesmereUI._GetFFD(selection).showHooked then
                EllesmereUI._GetFFD(selection).showHooked = true
                hooksecurefunc(selection, "Show", function(self)
                    -- Deferred: Show fires inside Edit Mode's secure ShowSystemSelections pass; write nothing there.
                    C_Timer.After(0, function()
                        if PlayerCastingBarFrame and EllesmereUI._GetFFD(PlayerCastingBarFrame).castBarSuppressed then
                            self:SetAlpha(0)
                            self:EnableMouse(false)
                        end
                    end)
                end)
            end
        end

        return
    end

    EllesmereUI._GetFFD(blizzBar).castBarSuppressed = false

    -- Hand the bar back to the parent EUI took it from -- but never to one that is itself hidden.
    -- Blizzard parents this bar under PlayerFrame, and Edit Mode re-parents it into a layout frame
    -- that gets hidden on exit, while EUI hides PlayerFrame whenever it renders its own player
    -- frame. Restoring there leaves Blizzard's cast bar fully armed but permanently invisible,
    -- which reads exactly like the suppression never lifted. UIParent is where Edit Mode positions the bar from anyway, and SetParent keeps the existing anchors, so the bar still lands where the user had it.
    local origParent = EllesmereUI._GetFFD(blizzBar).origParent
    local currentParent = blizzBar:GetParent()
    local restoreParent = origParent
    if not restoreParent or not restoreParent.IsVisible or not restoreParent:IsVisible() then
        restoreParent = UIParent
    end

    -- Only ever un-park a bar EUI itself parked: either it is still sitting in our hidden parent,
    -- or an earlier release handed it back to the captured parent and that parent is itself
    -- hidden. Matching the captured parent exactly is what separates "Blizzard's own parent
    -- happens to be hidden" from "another addon parked this bar under its own hidden frame" -- the latter is left alone, since resurrecting it is the bug this whole ownership dance exists to prevent.
    local parkedByUs = (hiddenParent and currentParent == hiddenParent)
        or (origParent and currentParent == origParent
            and currentParent.IsVisible and not currentParent:IsVisible())

    -- The Edit Mode gate can skip this; ApplyBlizzCastbarState re-runs the release on
    -- PLAYER_ENTERING_WORLD and on Edit Mode close, so a bar left parked by a skipped pass is healed as soon as re-parenting is legal.
    if parkedByUs and currentParent ~= restoreParent
        and not (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
        blizzBar:SetParent(restoreParent)
    end

    local selection = blizzBar.Selection
    if selection and EllesmereUI._GetFFD(selection).suppressed then
        EllesmereUI._GetFFD(selection).suppressed = false
        selection:SetAlpha(EllesmereUI._GetFFD(selection).restoreAlpha or 1)
        selection:EnableMouse(EllesmereUI._GetFFD(selection).restoreMouse or false)
    end

    -- Let Blizzard rebuild its normal event wiring without forcing visibility back on, so profile
    -- switches and UnitFrames/oUF teardown stay compatible with Blizzard's own cast bar logic.
    -- Only when EUI silenced the frame in the first place: a standalone cast bar addon silences
    -- the same frame, and re-registering its events is what pops Blizzard's cast bar back on screen next to theirs once EUI's own cast bar is switched off.
    EllesmereUI.RearmBlizzCastBars()
end

-------------------------------------------------------------------------------
--  Swiftmend Brightness Fix (shared hook utility) -- Blizzard dims Swiftmend based on
--  Efflorescence state (secret value in Midnight). Child addons call this on icon textures they identify as Swiftmend; the hook prevents vertex-color dimming and desaturation.
-------------------------------------------------------------------------------
do
    local hooked = {}
    local function isEnabled()
        return not EllesmereUIDB or EllesmereUIDB.brightenSwiftmend ~= false
    end
    function EllesmereUI._HookSwiftmendIcon(tex)
        if not tex or hooked[tex] then
            -- Already hooked; just force bright if re-enabling
            if tex and hooked[tex] and isEnabled() then
                tex:SetVertexColor(1, 1, 1)
            end
            return
        end
        hooked[tex] = true
        local vcGuard = false
        hooksecurefunc(tex, "SetVertexColor", function(_, r, g, b)
            if not vcGuard and isEnabled() and not (r == 1 and g == 1 and b == 1) then
                vcGuard = true
                tex:SetVertexColor(1, 1, 1)
                vcGuard = false
            end
        end)
        -- Force bright immediately (icon may already be dimmed before hook)
        if isEnabled() then tex:SetVertexColor(1, 1, 1) end
    end
    EllesmereUI._SWIFTMEND_SPELL = 18562
    EllesmereUI._SWIFTMEND_ICON  = 134914
end
