-------------------------------------------------------------------------------
--  EllesmereUI.lua  -  Custom Options Panel for EllesmereUI
--  Design-first scaffold: background, sidebar, header, content area, controls
--  Meant to be shared across the entire EllesmereUI addon suite.
-------------------------------------------------------------------------------
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

-- Preload background textures into GPU cache so the panel background
-- renders instantly on first open (avoids 1-frame content-before-bg flash).
-- Uses a hidden 1x1 frame; the textures stay in VRAM once loaded.
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

-- EllesmereUIDB is initialized from SavedVariables at ADDON_LOADED time.
-- Do NOT create it here -- that would overwrite saved data.
-- Save a reference so child addons can detect if their stale saved variables
-- file overwrote EllesmereUIDB (see Bags TOC SavedVariables fix, session 94).
EllesmereUI._parentDBRef = EllesmereUIDB

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
    { folder = "EllesmereUIResourceBars",      display = "Resource & Cast Bars", search_name = "EllesmereUI Resource Bars Cast Bars",      icon_on = ICONS_PATH .. "sidebar\\resourcebars-ig-on-2.png",  icon_off = ICONS_PATH .. "sidebar\\resourcebars-ig-2.png"  },
    { folder = "EllesmereUIAuraBuffReminders", display = "AuraBuff Reminders", search_name = "EllesmereUI AuraBuff Reminders", icon_on = ICONS_PATH .. "sidebar\\beacons-ig-on.png",         icon_off = ICONS_PATH .. "sidebar\\beacons-ig.png" },
    -- Basics is intentionally NOT in the roster: its code has been split into
    -- the per-module addons below. The Basics folder still exists as a shim
    -- addon purely so the v6.6 split-migration can read its enable state.
    { folder = "EllesmereUIQoL",               display = "Quality of Life",    search_name = "EllesmereUI Quality of Life",    icon_on = ICONS_PATH .. "sidebar\\basics-ig-on-2.png",        icon_off = ICONS_PATH .. "sidebar\\basics-ig-2.png"      },
    { folder = "EllesmereUIBlizzardSkin",      display = "Blizz UI Enhanced",  search_name = "EllesmereUI Blizz UI Enhanced",  icon_on = ICONS_PATH .. "sidebar\\blizzard-ig-on.png",        icon_off = ICONS_PATH .. "sidebar\\blizzard-ig.png"      },
    { folder = "EllesmereUIFriends",           display = "Friends List",       search_name = "EllesmereUI Friends List",       icon_on = ICONS_PATH .. "sidebar\\friends-ig-on-2.png",         icon_off = ICONS_PATH .. "sidebar\\friends-ig-2.png"       },
    { folder = "EllesmereUIMythicTimer",       display = "Mythic+ Timer",      search_name = "EllesmereUI Mythic+ Timer",      icon_on = ICONS_PATH .. "sidebar\\mplus-ig-on.png",           icon_off = ICONS_PATH .. "sidebar\\mplus-ig.png"         },
    { folder = "EllesmereUIQuestTracker",      display = "Quest Tracker",      search_name = "EllesmereUI Quest Tracker",      icon_on = ICONS_PATH .. "sidebar\\quests-ig-on-2.png",          icon_off = ICONS_PATH .. "sidebar\\quests-ig-2.png"        },
    { folder = "EllesmereUIMinimap",           display = "Minimap",            search_name = "EllesmereUI Minimap",            icon_on = ICONS_PATH .. "sidebar\\map-ig-on.png",             icon_off = ICONS_PATH .. "sidebar\\map-ig.png"           },
    { folder = "EllesmereUIChat",              display = "Chat",               search_name = "EllesmereUI Chat",               icon_on = ICONS_PATH .. "sidebar\\basics-ig-on-2.png",        icon_off = ICONS_PATH .. "sidebar\\basics-ig-2.png" },
    { folder = "EllesmereUIDamageMeters",      display = "Damage Meters",      search_name = "EllesmereUI Damage Meters",      icon_on = ICONS_PATH .. "sidebar\\basics-ig-on-2.png",        icon_off = ICONS_PATH .. "sidebar\\basics-ig-2.png" },
    { folder = "EllesmereUIBags",              display = "Bags",               search_name = "EllesmereUI Bags",               icon_on = ICONS_PATH .. "sidebar\\basics-ig-on-2.png",        icon_off = ICONS_PATH .. "sidebar\\basics-ig-2.png" },
    { folder = "EllesmereUIPartyMode",         display = "Party Mode",         search_name = "EllesmereUI Party Mode",         icon_on = ICONS_PATH .. "sidebar\\partymode-ig-on.png",       icon_off = ICONS_PATH .. "sidebar\\partymode-ig.png",       alwaysLoaded = true },
}

-------------------------------------------------------------------------------
--  Addon Groups  --  ordered categories that drive the sidebar layout.
--  Each group has its own parent header (icon + label, no power toggle); the
--  listed members render as child rows beneath it (label + power only, no
--  left icon). Member order is authoritative -- coming-soon entries are
--  placed at the end of their group.
-------------------------------------------------------------------------------
-- Stored on EllesmereUI (no file-level local) to stay under Lua 5.1's main-chunk
-- 200-locals and CreateMainFrame's 60-upvalue limits -- EllesmereUI is already
-- captured elsewhere, so every reference here adds no new local or upvalue.
EllesmereUI.ADDON_GROUPS = {
    {
        key     = "core",
        label   = "Core Addons",
        icon_on  = ICONS_PATH .. "sidebar\\actionbars-ig-on.png",
        icon_off = ICONS_PATH .. "sidebar\\actionbars-ig.png",
        members = {
            "EllesmereUIActionBars",
            "EllesmereUINameplates",
            "EllesmereUIUnitFrames",
            "EllesmereUICooldownManager",
            "EllesmereUIResourceBars",
            "EllesmereUIRaidFrames",     -- comingSoon
        },
    },
    {
        key     = "qol",
        label   = "QoL Addons",
        icon_on  = ICONS_PATH .. "sidebar\\basics-ig-on-2.png",
        icon_off = ICONS_PATH .. "sidebar\\basics-ig-2.png",
        members = {
            "EllesmereUIQoL",
            "EllesmereUIAuraBuffReminders",
            "EllesmereUIPartyMode",
        },
    },
    {
        key     = "reskin",
        label   = "UI Reskin Addons",
        icon_on  = ICONS_PATH .. "sidebar\\friends-ig-on-2.png",
        icon_off = ICONS_PATH .. "sidebar\\friends-ig-2.png",
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

-- Flat folder -> roster-info lookup used by the grouped sidebar builder.
-- Stored on EllesmereUI (not a file-level local) to avoid adding a new
-- upvalue to CreateMainFrame, which is up against Lua 5.1's 60-upvalue limit.
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
--  Profile Sync for UI Reskin Addons
--  Synced modules have their settings copied to all profiles on logout.
-------------------------------------------------------------------------------
do
    -- Build reskin module set from ADDON_GROUPS
    local reskinSet = {}
    for _, group in ipairs(EllesmereUI.ADDON_GROUPS) do
        if group.key == "reskin" then
            for _, m in ipairs(group.members) do reskinSet[m] = true end
            break
        end
    end
    EllesmereUI._reskinModules = reskinSet

    -- On first login, if only the Default profile exists (new user),
    -- stamp all reskin modules as synced. This runs once and writes
    -- explicit values so adding profiles later doesn't change them.
    function EllesmereUI._initSyncDefaults()
        if not EllesmereUIDB then return end
        if EllesmereUIDB._syncDefaultsStamped then return end
        EllesmereUIDB._syncDefaultsStamped = true
        local profiles = EllesmereUIDB.profiles
        if not profiles then return end
        local count = 0
        for _ in pairs(profiles) do
            count = count + 1
            if count > 1 then return end
        end
        -- Single profile: default all reskin modules to synced
        if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
        for folder in pairs(reskinSet) do
            if EllesmereUIDB.syncedModules[folder] == nil then
                EllesmereUIDB.syncedModules[folder] = true
            end
        end
    end

    function EllesmereUI.IsModuleSynced(folder)
        if not EllesmereUIDB then return false end
        local sm = EllesmereUIDB.syncedModules
        if sm and sm[folder] then return true end
        return false
    end

    function EllesmereUI.SyncModuleToAllProfiles(folder)
        if not EllesmereUIDB or not EllesmereUIDB.profiles then return end
        local active = EllesmereUIDB.activeProfile or "Default"
        local src = EllesmereUIDB.profiles[active]
        if not src or not src.addons or not src.addons[folder] then return end
        local DeepCopy = EllesmereUI.Lite and EllesmereUI.Lite.DeepCopy
        if not DeepCopy then return end
        local copy = DeepCopy(src.addons[folder])
        for name, prof in pairs(EllesmereUIDB.profiles) do
            if name ~= active and prof.addons then
                prof.addons[folder] = DeepCopy(copy)
            end
        end
    end

    function EllesmereUI.SetModuleSynced(folder, synced)
        if not EllesmereUIDB then return end
        if not EllesmereUIDB.syncedModules then EllesmereUIDB.syncedModules = {} end
        EllesmereUIDB.syncedModules[folder] = synced and true or false
        if synced then
            EllesmereUI.SyncModuleToAllProfiles(folder)
        end
    end

    -- Pre-logout: copy synced module data to all profiles
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        EllesmereUI._initSyncDefaults()
        if EllesmereUI.Lite and EllesmereUI.Lite.RegisterPreLogout then
            EllesmereUI.Lite.RegisterPreLogout(function()
                if not EllesmereUIDB or not EllesmereUIDB.syncedModules then return end
                for folder, synced in pairs(EllesmereUIDB.syncedModules) do
                    if synced then
                        EllesmereUI.SyncModuleToAllProfiles(folder)
                    end
                end
            end)
        end
    end)
end


-------------------------------------------------------------------------------
--  Forward declarations
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI or {}
_G.EllesmereUI = EllesmereUI
EllesmereUI.GLOBAL_KEY = "_EUIGlobal"
EllesmereUI.ADDON_ROSTER = ADDON_ROSTER
EllesmereUI.LOCALE_FONT_FALLBACK = LOCALE_FONT_FALLBACK
EllesmereUI.EXPRESSWAY = LOCALE_FONT_FALLBACK or EXPRESSWAY

-- Taint-safe print. Uses AddMessage instead of the global print(), which
-- routes through Blizzard's C-side handler and taints the chat frame
-- execution context. Silently drops the message inside protected instances
-- (raid combat / active M+ keystone) where any addon message delivery
-- taints FCF_OpenTemporaryWindow's whisper processing chain.
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

local mainFrame, bgFrame, clickArea, sidebar, contentFrame
local headerFrame, tabBar, scrollFrame, scrollChild, footerFrame, contentHeaderFrame
local sidebarButtons = {}
-- sidebarGroupButtons lives on EllesmereUI (not a file-level local) to avoid
-- adding an upvalue inside CreateMainFrame. The field is referenced from
-- CreateMainFrame, RefreshSidebarStates, and _applySidebarSearch.
EllesmereUI._sidebarGroupButtons = {}
local activeModule, activePage
local _lastPagePerModule = {}
local modules = {}
local scrollTarget = 0
local isSmoothing = false
local smoothFrame
local UpdateScrollThumb
local suppressScrollRangeChanged = false
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
    -- Wrapper around PP.CreateBorder that returns the MakeBorder API.
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
-- Blizzard reskin colors (tooltips, context menus, popups)
EllesmereUI.RESKIN = {
    BG_R = 0.067, BG_G = 0.067, BG_B = 0.067,
    TT_ALPHA   = 0.92,   -- tooltip background alpha
    CTX_ALPHA  = 0.95,   -- blizzard context menu background alpha
    QT_ALPHA   = 0.97,   -- quest tracker right-click menu alpha
    BRD_ALPHA  = 0.18,   -- border alpha (white)
}
-- Layout
EllesmereUI.DUAL_ITEM_W  = DUAL_ITEM_W
EllesmereUI.DUAL_GAP     = DUAL_GAP
EllesmereUI.TRIPLE_ITEM_W = TRIPLE_ITEM_W
EllesmereUI.TRIPLE_GAP    = TRIPLE_GAP

-- Table constants
EllesmereUI.CLASS_COLOR_MAP = CLASS_COLOR_MAP
EllesmereUI.CLASS_ART_MAP   = CLASS_ART_MAP

-- Upgrade track color data (shared by BlizzardSkin character/inspect sheets + Bags)
-- Only initialized when a consumer feature is actually enabled.
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

        -- Locale-agnostic track color lookup (all known localized trackString values)
        local map = {
            -- Explorer / Delve (gray)
            Explorer = GR, Expedicionario = GR, Forscher = GR,
            Explorateur = GR, Esploratore = GR, Explorador = GR, Delve = GR,
            -- Adventurer (white)
            Adventurer = W, Aventurero = W, Abenteurer = W,
            Aventurier = W, Avventuriero = W, Aventureiro = W,
            -- Veteran (green)
            Veteran = VE, Veterano = VE, ["V\195\169t\195\169ran"] = VE,
            -- Champion (blue)
            Champion = CH, ["Campe\195\179n"] = CH, Campione = CH,
            ["Campe\195\163o"] = CH,
            -- Hero (purple)
            Hero = HE, ["H\195\169roe"] = HE, Held = HE,
            ["H\195\169ros"] = HE, Eroe = HE, ["Hero\195\173"] = HE,
            -- Myth (orange)
            Myth = MY, Mito = MY, Mythos = MY, Mythe = MY,
            -- ruRU
            ["\208\152\209\129\209\129\208\187\208\181\208\180\208\190\208\178\208\176\209\130\208\181\208\187\209\140"] = GR,
            ["\208\152\209\129\208\186\208\176\209\130\208\181\208\187\209\140 \208\191\209\128\208\184\208\186\208\187\209\142\209\135\208\181\208\189\208\184\208\185"] = W,
            ["\208\146\208\181\209\130\208\181\209\128\208\176\208\189"] = VE,
            ["\208\151\208\176\209\137\208\184\209\130\208\189\208\184\208\186"] = CH,
            ["\208\147\208\181\209\128\208\190\208\185"] = HE,
            ["\208\155\208\181\208\179\208\181\208\189\208\180\208\176"] = MY,
            -- koKR
            ["\237\131\144\237\151\152\234\176\128"] = GR, ["\235\170\168\237\151\152\234\176\128"] = W,
            ["\235\133\184\235\160\168\234\176\128"] = VE, ["\236\177\148\237\148\188\236\150\184"] = CH,
            ["\236\152\129\236\155\133"] = HE, ["\236\139\160\237\153\148"] = MY,
            -- zhCN
            ["\230\142\162\231\180\162\232\128\133"] = GR, ["\229\134\146\233\153\169\232\128\133"] = W,
            ["\232\128\129\229\133\181"] = VE, ["\229\139\135\229\163\171"] = CH,
            ["\232\139\177\233\155\132"] = HE, ["\231\165\158\232\175\157"] = MY,
            -- zhTW
            ["\230\142\162\233\154\170\232\128\133"] = GR, ["\229\134\146\233\154\170\232\128\133"] = W,
            ["\231\178\190\229\133\181"] = VE, ["\231\165\158\232\169\177"] = MY,
        }

        function EllesmereUI.GetUpgradeTrack(itemLink)
            if not itemLink or not (C_Item and C_Item.GetItemUpgradeInfo) then
                return "", W
            end
            local info = C_Item.GetItemUpgradeInfo(itemLink)
            if not info then return "", W end
            local cur, maxL = info.currentLevel, info.maxLevel
            local text = (cur and maxL and maxL > 0) and (cur .. "/" .. maxL) or ""
            local color = map[info.trackString or ""] or W
            return text, color
        end
    end
end

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

    --- Snap a value to the nearest physical pixel at UIParent scale.
    --- Convenience wrapper for save paths that don't have a frame reference.
    function PP.Snap(x)
        if x == 0 then return 0 end
        local m = PP.mult
        local result = math.floor(x / m + 0.5) * m
        -- Clean floating point dust: if result is within 0.001 of an
        -- integer, round to that integer to prevent drift accumulation.
        local rounded = math.floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then result = rounded end
        return result
    end

    --- Convert a coord-space value to its physical pixel count (for display).
    function PP.ToPixels(coord)
        if coord == 0 then return 0 end
        return math.floor(coord / PP.mult + 0.5)
    end

    --- Convert a physical pixel count to a grid-aligned coord value (for storage).
    function PP.FromPixels(px)
        if px == 0 then return 0 end
        return px * PP.mult
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
        local result = physPixels * onePixel
        local rounded = math.floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then result = rounded end
        return result
    end

    ---------------------------------------------------------------------------
    --  SnapCenterForDim(value, dim, effectiveScale)
    --
    --  Snap a CENTER coordinate so that both edges of a frame with the given
    --  dimension land on physical pixel boundaries. For frames with an EVEN
    --  pixel dimension, the center must land on a whole pixel. For frames
    --  with an ODD pixel dimension, the center must land on a half pixel
    --  (integer + 0.5) so that center +/- dim/2 are both whole pixels.
    --
    --  This is the correct snap function for CENTER-anchored frames stored
    --  in CENTER/CENTER coordinate format. Plain SnapForES rounds to whole
    --  pixels, which loses the necessary +0.5 for odd-dimension frames and
    --  causes a 1px drift on save & exit / profile change / spec swap.
    ---------------------------------------------------------------------------
    function PP.SnapCenterForDim(value, dim, es)
        if value == nil then return value end
        es = es or (UIParent and UIParent:GetEffectiveScale() or 1)
        local onePixel = PP.perfect / es
        local valuePx = value / onePixel
        local result
        if dim and dim > 0 then
            local dimPx = math.floor(dim / onePixel + 0.5)
            if dimPx % 2 == 1 then
                -- Odd dimension: snap center to nearest half-pixel grid point
                -- (integer + 0.5) so edges land on whole pixels.
                result = (math.floor(valuePx) + 0.5) * onePixel
                -- Clean floating point dust (half-pixel values)
                local rounded = math.floor(result) + 0.5
                if math.abs(result - rounded) < 0.001 then result = rounded end
                return result
            end
        end
        -- Even dimension (or unknown): snap center to nearest whole pixel.
        result = math.floor(valuePx + 0.5) * onePixel
        local rounded = math.floor(result + 0.5)
        if math.abs(result - rounded) < 0.001 then result = rounded end
        return result
    end

    ---------------------------------------------------------------------------
    --  Convenience wrappers — pixel-snapped frame geometry
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
    --  DisablePixelSnap — prevent WoW's engine from rounding texture
    --  coordinates to the nearest pixel, which causes blurry edges on
    --  sub-pixel-sized elements.
    ---------------------------------------------------------------------------
    -- External weak-keyed set for pixel-snap tracking.
    -- Avoids writing custom keys onto Blizzard's secure widget tables
    -- (which taints them and causes "secret value" errors).
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
           or mk.SetVertexColor or mk.CreateTexture or mk.SetTexCoord or mk.SetTexture then
            if mk.SetSnapToPixelGrid then hooksecurefunc(mk, "SetSnapToPixelGrid", WatchPixelSnap) end
            if mk.SetStatusBarTexture then hooksecurefunc(mk, "SetStatusBarTexture", PP.DisablePixelSnap) end
            if mk.SetColorTexture then hooksecurefunc(mk, "SetColorTexture", PP.DisablePixelSnap) end
            if mk.SetVertexColor then hooksecurefunc(mk, "SetVertexColor", PP.DisablePixelSnap) end
            if mk.CreateTexture then hooksecurefunc(mk, "CreateTexture", PP.DisablePixelSnap) end
            if mk.SetTexCoord then hooksecurefunc(mk, "SetTexCoord", PP.DisablePixelSnap) end
            if mk.SetTexture then hooksecurefunc(mk, "SetTexture", PP.DisablePixelSnap) end
            _hookedMetatables[mk] = true
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
    --  Border data is stored in an external weak-keyed table (_ppBorderData)
    --  instead of directly on the frame, to avoid tainting Blizzard's secure
    --  frame tables. Each entry: { container, borderSize, borderColor }.
    --  The container Frame holds _top, _bottom, _left, _right textures.
    --
    --  API:
    --    PP.CreateBorder(frame, r, g, b, a, borderSize, drawLayer, subLevel)
    --    PP.SetBorderSize(frame, borderSize)
    --    PP.SetBorderColor(frame, r, g, b, a)
    --    PP.UpdateBorder(frame, borderSize, r, g, b, a)
    --    PP.HideBorder(frame)
    --    PP.ShowBorder(frame)
    local _ppBorderData = setmetatable({}, { __mode = "k" })
    ---------------------------------------------------------------------------

    local function SnapBorderTextures(container, frame, borderSize)
        if not container.GetEffectiveScale then return end
        local ok, es = pcall(container.GetEffectiveScale, container)
        if not ok or not es then return end
        local onePixel = es > 0 and (PP.perfect / es) or PP.mult
        local bs = borderSize or 1
        local edgeSize = bs > 0 and math.max(onePixel, math.floor(bs + 0.5) * onePixel) or 0

        local t, b, l, r = container._top, container._bottom, container._left, container._right
        if not t then return end

        if edgeSize == 0 then
            t:Hide(); b:Hide(); l:Hide(); r:Hide()
            return
        end

        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        t:SetHeight(edgeSize); t:Show()
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        b:SetHeight(edgeSize); b:Show()
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -edgeSize)
        l:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, edgeSize)
        l:SetWidth(edgeSize); l:Show()
        r:ClearAllPoints()
        r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -edgeSize)
        r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, edgeSize)
        r:SetWidth(edgeSize); r:Show()

        local bc = container._bdColor
        if bc then
            t:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
            b:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
            l:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
            r:SetVertexColor(bc[1], bc[2], bc[3], bc[4])
        end
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
                local bd = _ppBorderData[f]
                local ok = pcall(SnapBorderTextures, c, f, bd and bd.borderSize or 1)
                if not ok then
                    entry.container = nil
                    entry.frame = nil
                end
            end
        end
    end

    --- Re-snap only borders whose parent frame is a descendant of `root`.
    --- Used by tab switch to avoid resnapping 600+ borders across the
    --- entire addon when only ~30 on the active page need it.
    function PP.ResnapBordersUnder(root)
        if not root then return PP.ResnapAllBorders() end
        local count = 0
        for i = 1, allBordersN do
            local entry = allBorders[i]
            local f = entry.frame
            if f and entry.container then
                -- Walk up the parent chain (max 10 levels to avoid infinite loops)
                local parent = f
                local found = false
                for _ = 1, 10 do
                    parent = parent:GetParent()
                    if not parent then break end
                    if parent == root then found = true; break end
                end
                if found then
                    count = count + 1
                    local bd = _ppBorderData[f]
                    local ok = pcall(SnapBorderTextures, entry.container, f, bd and bd.borderSize or 1)
                    if not ok then
                        entry.container = nil
                        entry.frame = nil
                    end
                end
            end
        end
    end

    function PP.CreateBorder(frame, r, g, b, a, borderSize, drawLayer, subLevel)
        local bd = _ppBorderData[frame]
        if bd then return bd.container end
        r = r or 0; g = g or 0; b = b or 0; a = a or 1
        borderSize = borderSize or 1
        drawLayer = drawLayer or "OVERLAY"
        subLevel = subLevel or 0

        -- 4 texture strips instead of BackdropTemplate: avoids NineSlice corner
        -- sub-frames that render as black boxes on nameplate frames.
        local container = CreateFrame("Frame", nil, frame)
        container:SetAllPoints(frame)
        container:SetFrameLevel(frame:GetFrameLevel() + 1)

        local WHITE = "Interface\\Buttons\\WHITE8X8"
        local function MakeTex()
            local tx = container:CreateTexture(nil, drawLayer, nil, subLevel)
            tx:SetTexture(WHITE)
            return tx
        end
        container._top    = MakeTex()
        container._bottom = MakeTex()
        container._left   = MakeTex()
        container._right  = MakeTex()

        container._bdColor = { r, g, b, a }
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
        bd.borderColor = { r, g, b, a }
        bd.container._bdColor = bd.borderColor
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
    PanelPP.GetBorders    = PP.GetBorders
    PanelPP.SetBorderSize = PP.SetBorderSize
    PanelPP.SetBorderColor = PP.SetBorderColor
    PanelPP.UpdateBorder  = PP.UpdateBorder
    PanelPP.HideBorder    = PP.HideBorder
    PanelPP.ShowBorder    = PP.ShowBorder
end

-- File-level PanelPP reference for panel layout code outside the do block
local PanelPP = EllesmereUI.PanelPP

-------------------------------------------------------------------------------
--  BORDER TEXTURE SYSTEM
--
--  Extends the PP border system with BackdropTemplate-based textured borders.
--  When borderTexture = "solid" (default), the existing PP 4-strip system is
--  used with zero behavior change. When borderTexture is any other key, a
--  BackdropTemplate child frame is created with the resolved edge texture and
--  the PP strips are hidden.
--
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

    -- Per-addon border defaults registry.
    -- Each addon registers a table keyed by texture key. Each texture entry has:
    --   defaultSize: the size key to auto-set when this texture is selected
    --   sizes: table keyed by size key (addon-specific format), each with:
    --     offsetX, offsetY, shiftX, shiftY (all default to 0 if omitted)
    -- Addons register via EllesmereUI.RegisterBorderDefaults(addonKey, table).
    -- Lookup via EllesmereUI.GetBorderDefaults(addonKey, textureKey, sizeKey).
    local _borderDefaults = {}

    function EllesmereUI.RegisterBorderDefaults(addonKey, defaults)
        _borderDefaults[addonKey] = defaults
    end

    --- Get per-addon border defaults for a texture+size combo.
    --- Returns offsetX, offsetY, shiftX, shiftY (all 0 if not registered).
    function EllesmereUI.GetBorderDefaults(addonKey, textureKey, sizeKey)
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
        local addon = _borderDefaults[addonKey]
        if not addon then return nil end
        local tex = addon[textureKey]
        return tex and tex.defaultSize or nil
    end

    -- Built-in border textures (always available, no SharedMedia required)
    -- defaultOffset: how far outward the backdrop frame extends from the content
    -- edge. Each texture has different internal padding, so this is tuned per-texture.
    EllesmereUI._builtinBorderTextures = {
        { key = "solid",   name = "Solid" },
        { key = "glow",    name = "Glow",            path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\glow-border",  defaultOffset = 0, defaultOffsetY = 0, scaleOffset = true, defaultThickness = "normal" },
        { key = "blizz",   name = "Blizzard",        path = "Interface\\AddOns\\EllesmereUI\\media\\borders\\blizz-border", defaultOffset = 3, defaultOffsetY = 2, scaleOffset = true, defaultThickness = "heavy" },
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

    --- Check if a border texture uses scaled offset (edgeSize/2 base).
    function EllesmereUI.BorderTextureUsesScaleOffset(key)
        if not key or key == "" or key == "solid" then return false end
        for _, entry in ipairs(EllesmereUI._builtinBorderTextures) do
            if entry.key == key then return entry.scaleOffset == true end
        end
        return false
    end

    --- Resolve a border texture key to a file path.
    --- Returns nil for "solid" (meaning use PP system).
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
    function EllesmereUI.ApplyBorderStyle(borderFrame, size, r, g, b, a, textureKey, offsetOverride, offsetYOverride, shiftX, shiftY, addonKey, sizeKey)
        local PP = EllesmereUI.PP
        if not PP or not borderFrame then return end
        a = a or 1

        local isSolid = not textureKey or textureKey == "" or textureKey == "solid"

        if isSolid then
            -- Hide BackdropTemplate border if present
            local bdFrame = _bdBorderData[borderFrame]
            if bdFrame then bdFrame:Hide() end
            -- Use PP system (existing behavior, zero change)
            if size > 0 then
                if PP.GetBorders(borderFrame) then
                    PP.UpdateBorder(borderFrame, size, r, g, b, a)
                    PP.ShowBorder(borderFrame)
                    -- Restore alpha in case textured mode zeroed it
                    local ppC = PP.GetBorders(borderFrame)
                    if ppC then
                        if ppC._top then ppC._top:SetAlpha(1) end
                        if ppC._bottom then ppC._bottom:SetAlpha(1) end
                        if ppC._left then ppC._left:SetAlpha(1) end
                        if ppC._right then ppC._right:SetAlpha(1) end
                    end
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
            -- Create or reuse BackdropTemplate frame
            local bdFrame = _bdBorderData[borderFrame]
            if not bdFrame then
                bdFrame = CreateFrame("Frame", nil, borderFrame, "BackdropTemplate")
                bdFrame:EnableMouse(false)
                _bdBorderData[borderFrame] = bdFrame
            end
            bdFrame:SetFrameLevel(borderFrame:GetFrameLevel())
            local EDGE_MAP = { 12, 16, 24, 32 }
            local edgeSize = EDGE_MAP[size] or 12
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
            -- Custom textures (scaleOffset): base = edgeSize/2 so border tracks
            -- the edge at any size, plus a small fine-tune adjustment.
            -- Other textures: absolute offset (no edgeSize base).
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
            bdFrame:SetBackdrop({
                edgeFile = texPath,
                edgeSize = edgeSize,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            bdFrame:SetBackdropBorderColor(r, g, b, a)
            bdFrame:Show()
            borderFrame:Show()
        end
    end

    --- Set border color on whichever system is currently active (PP or backdrop).
    --- Used for hover highlights and other dynamic color changes.
    function EllesmereUI.SetBorderStyleColor(borderFrame, r, g, b, a)
        local PP = EllesmereUI.PP
        if not PP or not borderFrame then return end
        a = a or 1
        -- Check PP first
        local ppContainer = PP.GetBorders(borderFrame)
        if ppContainer and ppContainer:IsShown() then
            PP.SetBorderColor(borderFrame, r, g, b, a)
            return
        end
        -- Check BackdropTemplate
        local bdFrame = _bdBorderData[borderFrame]
        if bdFrame and bdFrame:IsShown() then
            bdFrame:SetBackdropBorderColor(r, g, b, a)
        end
    end
end

-------------------------------------------------------------------------------
--  Global Color System
--  Central source of truth for class, power, and resource colors.
--  Stored in EllesmereUIDB.customColors; falls back to WoW defaults.
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

-- Register our bundled fonts with LibSharedMedia so other addons can use them
-- and so SM's HashTable("font") includes them for our own dropdown lookups.
-- Also populate _smFontPaths so ResolveFontName can resolve SM fonts at runtime.
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
            end
        end)
    end
end

-- Get the fonts DB table (lazy-init)
function EllesmereUI.GetFontsDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.fonts then
        EllesmereUIDB.fonts = {
            global      = "Expressway",
            outlineMode = "shadow",
        }
    end
    local f = EllesmereUIDB.fonts
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
    -- Fallback to Expressway
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
}
EllesmereUI._moduleFontCache = {}
EllesmereUI._moduleFontCacheVer = 0

-- Resolve an addonKey to a moduleFonts entry (or nil for global).
-- Cached per-key for zero-alloc repeated lookups.
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

-- Get the resolved font path for an addon key.
-- Falls back to the global font when no per-module override is configured.
function EllesmereUI.GetFontPath(addonKey)
    local db = EllesmereUI.GetFontsDB()
    local override = EllesmereUI.GetModuleFontEntry(addonKey)
    if override and override.font and override.font ~= "__global" then
        return ResolveFontName(override.font)
    end
    return ResolveFontName(db.global or "Expressway")
end

-- Get the font name (not path) for an addon key.
function EllesmereUI.GetFontName(addonKey)
    local db = EllesmereUI.GetFontsDB()
    local override = EllesmereUI.GetModuleFontEntry(addonKey)
    if override and override.font and override.font ~= "__global" then
        return override.font
    end
    return db.global or "Expressway"
end

-- Get the WoW font flag string for the outline mode.
-- Pass an addonKey to get per-module override; nil returns the global setting.
-- Returns: "OUTLINE", "THICKOUTLINE", or "" (none/shadow)
function EllesmereUI.GetFontOutlineFlag(addonKey)
    local db = EllesmereUI.GetFontsDB()
    local override = EllesmereUI.GetModuleFontEntry(addonKey)
    local mode
    if override and override.outline and override.outline ~= "__global" then
        mode = override.outline
    else
        mode = db.outlineMode or "none"
    end
    if mode == "outline" then return "OUTLINE, SLUG"
    elseif mode == "thick" then return "THICKOUTLINE"
    else return "" end
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

-- Build font dropdown values/order with "EUI Global Font" at the top.
-- Returns values, order tables suitable for W:DualRow dropdown config.
function EllesmereUI.BuildFontDropdownData()
    local values = { ["__global"] = { text = "EUI Global Font" } }
    local order  = { "__global", "---" }
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

-- Get power color (custom or default). Returns nil for unknown keys.
function EllesmereUI.GetPowerColor(powerKey)
    local db = EllesmereUI.GetCustomColorsDB()
    if db.power and db.power[powerKey] then
        return db.power[powerKey]
    end
    local def = EllesmereUI.DEFAULT_POWER_COLORS[powerKey]
    if def then return { r = def.r, g = def.g, b = def.b } end
    return nil
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
        -- In Void Metamorphosis (1217607): stacks come from Silence the
        -- Whispers (1227702) and max is 40. Outside meta: stacks come
        -- from Dark Heart (1225789) and max is 50 (or 35 with Soul
        -- Glutton talent 1247534).
        local inMeta = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(1217607)
        local aura, max
        if inMeta then
            aura = C_UnitAuras.GetPlayerAuraBySpellID(1227702)
            max = 40
        else
            aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(1225789)
            max = (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(1247534)) and 35 or 50
        end
        return (aura and aura.applications or 0), max
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

-- Tip of the Spear and Whirlwind Stacks are now tracked manually via
-- HandleTipOfTheSpear / HandleWhirlwindStacks + UNIT_SPELLCAST_SUCCEEDED.
-- See the manual tracker section above.

EllesmereUI.THEME_PRESETS   = THEME_PRESETS
EllesmereUI.THEME_ORDER     = THEME_ORDER

-- Path strings
EllesmereUI.EXPRESSWAY = EXPRESSWAY
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

    -- M+/raid/PvP instance check -- guards against tainted execution
    local function InProtectedInstance()
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

        -- In protected instances, Shamans always get Astral Recall (no CD queries)
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

        -- Shaman: show Astral Recall if any owned toy is on CD
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

        -- Random owned toy, or fallback to base hearthstone (item 6948)
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
--  MakeUnlockElement  --  shared factory for unlock mode element tables
--
--  Every addon calls this to build a standardized registration table.
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
--    onLiveMove (function(key))  called each frame during drag
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
        noAnchorTarget    = opts.noAnchorTarget,
        noAnchorTo        = opts.noAnchorTo,
    }
end

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
-------------------------------------------------------------------------------

-- Resolve a texture key to a file path. Handles "sm:" prefixed keys by
-- falling back to LSM:Fetch when the key isn't in the local lookup table.
-- This covers the case where a SharedMedia addon loads after our init.
--   texTable  – the addon's local texture lookup (e.g. TBB_TEXTURES)
--   key       – the saved texture key (e.g. "sm:ElvUI Gloss" or "beautiful")
--   fallback  – path to use if nothing resolves (optional)
function EllesmereUI.ResolveTexturePath(texTable, key, fallback)
    if not key then return fallback end
    local path = texTable and texTable[key]
    if path then return path end
    -- If the key has an "sm:" prefix, try LSM directly
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
    -- Filter out icon textures that some SM packs incorrectly register as statusbar
    local SM_TEX_BLACKLIST = {
        play_icon = true, stop_icon = true,
        user_icon = true, users_icon = true,
    }
    for name in pairs(smTextures) do
        local key = "sm:" .. name
        if not textures[key] and not SM_TEX_BLACKLIST[name] then
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
--  Append LibSharedMedia-3.0 sounds into a runtime sound dropdown table.
--  Signature: AppendSharedMediaSounds(paths, names, order)
--    paths   – key → sound file path table
--    names   – key → display name string table
--    order   – ordered array of keys (receives "---" + SM keys appended)
--  Safe to call multiple times; duplicate keys are skipped via the paths
--  table guard.
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
            if popup._modal then
                -- Modal popups swallow Escape so the user must click a button.
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

    -- Pixel-perfect scale (match main frame, including user panel scale)
    -- Popups render at default UI scale — no custom scaling needed.
    -- (Dimmer stays at scale 1 so it covers the full screen.)

    -- Background: stone texture with dark overlay
    local popBgAtlas = popup:CreateTexture(nil, "BACKGROUND")
    popBgAtlas:SetAtlas("housing-basic-panel--stone-background")
    popBgAtlas:SetAllPoints()
    local popBgOverlay = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
    popBgOverlay:SetColorTexture(0, 0, 0, 0.75)
    popBgOverlay:SetAllPoints()

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

    -- Helper: create a styled popup button
    -- Button is sized 2px larger than visual area; bg is inset 1px so the border
    -- texture (which fills the full button) peeks out as a 1px border on all sides.
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

    -- Close on dimmer click (only when clicking outside the popup).
    -- Modal popups ignore dimmer clicks entirely.
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

    popup._title:SetText(opts.title or "Confirm")
    popup._msg:SetText(opts.message or "Are you sure?")
    if opts.disclaimer then
        popup._disclaimer:SetText(opts.disclaimer)
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
        popup._scaleWarnLabel:SetText(opts.scaleWarning)
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
        popup._cbLabel:SetText(opts.checkbox)
        local rowW = 14 + 6 + popup._cbLabel:GetStringWidth()
        popup._cbRow:SetWidth(rowW)
        popup._cbRow:ClearAllPoints()
        popup._cbRow:SetPoint("BOTTOM", popup, "BOTTOM", 0, 13 + 27 + 10)
        popup._cbRow:Show()
        cbH = 28
    else
        popup._cbRow:Hide()
    end

    popup:SetHeight((popup._baseH or 176) + scaleWarnH + cbH)
    popup._cancelBtn._lbl:SetText(opts.cancelText or "Cancel")
    popup._confirmBtn._lbl:SetText(opts.confirmText or "Confirm")
    -- onDismiss: called on escape/click-outside. Falls back to onCancel if not provided.
    popup._onCancel = opts.onDismiss or opts.onCancel or nil
    popup._modal = opts.modal and true or false

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
            if opts.onConfirm then opts.onConfirm(popup._cbChecked) end
        end)
    end

    -- Counter-scale the popup to match the options panel when UIParent
    -- has been rescaled by the pixel-perfect system. The dimmer stays at
    -- scale 1 (covers the full screen), but the popup itself renders at
    -- the same visual size as the main options frame.
    local mf = EllesmereUI._mainFrame
    if mf and mf:GetScale() ~= 1 then
        popup:SetScale(mf:GetScale())
    else
        popup:SetScale(1)
    end


    popup._dimmer:Show()
end

do
-------------------------------------------------------------------------------
--  Reset Gate
--  Bump REQUIRED_RESET_VERSION whenever a breaking SavedVariables purge
--  is released. Users whose stored _resetVersion is below this number get
--  an automatic full wipe at ADDON_LOADED time (before child addons init).
--  Fresh installs are stamped immediately and never see the popup.
-------------------------------------------------------------------------------
local REQUIRED_RESET_VERSION = 9

function EllesmereUI.NeedsBetaReset()
    if not EllesmereUIDB then return false end
    return (EllesmereUIDB._resetVersion or 0) < REQUIRED_RESET_VERSION
end

-- Stamp fresh installs so they never see the reset popup.
-- A fresh install has no _resetVersion at all. By PLAYER_LOGIN, child addons
-- have already populated EllesmereUIDB so key counting is unreliable. Instead,
-- check if _resetVersion has never been set (nil) AND no child addon SVs exist.
function EllesmereUI.StampResetVersion()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if (EllesmereUIDB._resetVersion or 0) >= REQUIRED_RESET_VERSION then return end
    -- If _resetVersion is nil, this is either a fresh install or a very old install.
    -- Fresh installs have no child addon SavedVariables. Old installs that need
    -- the reset will have at least one child DB populated.
    if EllesmereUIDB._resetVersion == nil then
        local hasChildDB = _G.EllesmereUIActionBarsDB
            or _G.EllesmereUIUnitFramesDB
            or _G.EllesmereUINameplatesDB
            or _G.EllesmereUIResourceBarsDB
        if not hasChildDB then
            EllesmereUIDB._resetVersion = REQUIRED_RESET_VERSION
        end
    end
end

-- Perform the full wipe at ADDON_LOADED time, before child addons init.
-- Called from EllesmereUI_Migration.lua (which fires on parent ADDON_LOADED).
function EllesmereUI.PerformResetWipe()
    if not EllesmereUI.NeedsBetaReset() then return false end
    -- Safety: log the wipe to help diagnose unexpected triggers
    local ver = EllesmereUIDB and EllesmereUIDB._resetVersion
    EllesmereUI.Print("|cffff0000[EllesmereUI]|r Reset wipe triggered. _resetVersion=" .. tostring(ver))
    -- Extra guard: if the DB has real user data (profiles, positions, etc.)
    -- but _resetVersion is somehow missing, do NOT wipe. Only wipe if
    -- _resetVersion is genuinely below threshold (old beta data).
    if EllesmereUIDB and EllesmereUIDB.profiles and not EllesmereUIDB._resetVersion then
        -- User has profiles but no reset stamp -- could be a load race.
        -- Stamp and skip rather than wipe their data.
        EllesmereUIDB._resetVersion = 9
        return false
    end
    -- Wipe all child addon SVs
    local svNames = {
        "EllesmereUIActionBarsDB",
        "EllesmereUIAuraBuffRemindersDB",
        "EllesmereUIBasicsDB",
        "EllesmereUICooldownManagerDB",
        "EllesmereUINameplatesDB",
        "EllesmereUIResourceBarsDB",
        "EllesmereUIUnitFramesDB",
    }
    for _, name in ipairs(svNames) do
        if _G[name] then _G[name] = {} end
    end
    -- Wipe the central DB and stamp the new version
    local oldScale = EllesmereUIDB and EllesmereUIDB.ppUIScale
    local oldScaleAuto = EllesmereUIDB and EllesmereUIDB.ppUIScaleAuto
    _G["EllesmereUIDB"] = { _resetVersion = REQUIRED_RESET_VERSION }
    EllesmereUIDB = _G["EllesmereUIDB"]
    -- Preserve UI scale so the popup renders at the right size
    if oldScale then EllesmereUIDB.ppUIScale = oldScale end
    if oldScaleAuto ~= nil then EllesmereUIDB.ppUIScaleAuto = oldScaleAuto end
    -- Flag so the popup shows at PLAYER_LOGIN
    EllesmereUI._showResetPopup = true
    return true
end
end

do
    local welcomePopup, welcomeDimmer

    local function CreateWelcomePopup()
        if welcomePopup then return welcomePopup, welcomeDimmer end

        local POPUP_W = 525
        local POPUP_PAD_TOP = 22
        local POPUP_PAD_BOTTOM = 29
        local BTN_H = 32
        local BTN_GAP = 16

        -- Dimmer
        welcomeDimmer = CreateFrame("Frame", "EUIWelcomeDimmer", UIParent)
        welcomeDimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        welcomeDimmer:SetFrameLevel(100)
        welcomeDimmer:SetAllPoints(UIParent)
        welcomeDimmer:EnableMouse(true)
        welcomeDimmer:EnableMouseWheel(true)
        welcomeDimmer:SetScript("OnMouseWheel", function() end)
        welcomeDimmer:EnableKeyboard(true)
        welcomeDimmer:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
        welcomeDimmer:Hide()

        local dimTex = SolidTex(welcomeDimmer, "BACKGROUND", 0, 0, 0, 0.25)
        dimTex:SetAllPoints()

        -- Popup frame (height set dynamically after text layout)
        welcomePopup = CreateFrame("Frame", "EUIWelcomePopup", welcomeDimmer)
        welcomePopup:SetWidth(POPUP_W)
        welcomePopup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        welcomePopup:SetFrameStrata("FULLSCREEN_DIALOG")
        welcomePopup:SetFrameLevel(welcomeDimmer:GetFrameLevel() + 10)
        welcomePopup:EnableMouse(true)

        local bg = SolidTex(welcomePopup, "BACKGROUND", 0.06, 0.08, 0.10, 0.95)
        bg:SetAllPoints()
        MakeBorder(welcomePopup, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)

        -- Title
        local EG = ELLESMERE_GREEN
        local title = MakeFont(welcomePopup, 22, "", EG.r, EG.g, EG.b)
        title:SetPoint("TOP", welcomePopup, "TOP", 0, -22)
        title:SetText("EllesmereUI Beta Complete")

        -- Message
        local msg = MakeFont(welcomePopup, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        msg:SetPoint("TOP", title, "BOTTOM", 0, -12)
        msg:SetWidth(POPUP_W - 60)
        msg:SetJustifyH("CENTER")
        msg:SetWordWrap(true)
        msg:SetSpacing(4)
        msg:SetText("Thank you for helping test EllesmereUI during beta! During testing, many systemic changes were made to build the foundation for a stable, flexible addon going forward.\n\nTo ensure a clean experience for everyone, all settings have been automatically reset. You will need to reconfigure your UI. We apologize for the inconvenience, and appreciate your patience.\n\nPrevious profile exports are no longer compatible and will need to be re-created.")

        -- Disclaimer
        local disc = welcomePopup:CreateFontString(nil, "OVERLAY")
        disc:SetFont(EXPRESSWAY, 14, "")
        disc:SetTextColor(1, 0.35, 0.35, 0.8)
        disc:SetPoint("TOP", msg, "BOTTOM", 0, -16)
        disc:SetWidth(POPUP_W - 60)
        disc:SetJustifyH("CENTER")
        disc:SetWordWrap(true)
        disc:SetText("All EllesmereUI settings have been reset to defaults.")

        -- Reset & Reload button (accent-colored, centered)
        local closeBtn = CreateFrame("Button", nil, welcomePopup)
        closeBtn:SetSize(180, 32)
        closeBtn:SetFrameLevel(welcomePopup:GetFrameLevel() + 2)
        do
            local eg = ELLESMERE_GREEN
            local cbg = SolidTex(closeBtn, "BACKGROUND", BTN_BG_R, BTN_BG_G, BTN_BG_B, BTN_BG_A)
            cbg:SetAllPoints()
            local cbrd = MakeBorder(closeBtn, eg.r, eg.g, eg.b, 0.8)
            local clbl = MakeFont(closeBtn, 13, nil, eg.r, eg.g, eg.b)
            clbl:SetAlpha(0.8)
            clbl:SetPoint("CENTER")
            clbl:SetText("Reset & Reload")
            closeBtn:SetScript("OnEnter", function()
                clbl:SetAlpha(1)
                cbrd:SetColor(eg.r, eg.g, eg.b, 1)
                cbg:SetColorTexture(BTN_BG_R, BTN_BG_G, BTN_BG_B, BTN_BG_HA)
            end)
            closeBtn:SetScript("OnLeave", function()
                clbl:SetAlpha(0.8)
                cbrd:SetColor(eg.r, eg.g, eg.b, 0.8)
                cbg:SetColorTexture(BTN_BG_R, BTN_BG_G, BTN_BG_B, BTN_BG_A)
            end)
            closeBtn:SetScript("OnClick", function()
                -- Nuclear wipe: nuke ALL child SV globals so WoW saves
                -- clean files to disk during the PLAYER_LOGOUT that
                -- ReloadUI triggers.
                local svNames = {
                    "EllesmereUIActionBarsDB",
                    "EllesmereUIAuraBuffRemindersDB",
                    "EllesmereUIBasicsDB",
                    "EllesmereUICooldownManagerDB",
                    "EllesmereUINameplatesDB",
                    "EllesmereUIResourceBarsDB",
                    "EllesmereUIUnitFramesDB",
                    -- Legacy globals (merged into BasicsDB, clean up stale files)
                    "EllesmereUICursorDB",
                    "EllesmereUIQuestTrackerDB",
                }
                for _, name in ipairs(svNames) do
                    _G[name] = {}
                end
                -- Re-wipe central store (preserving reset stamp + scale)
                local oldScale = EllesmereUIDB and EllesmereUIDB.ppUIScale
                local oldScaleAuto = EllesmereUIDB and EllesmereUIDB.ppUIScaleAuto
                local resetVer = EllesmereUIDB and EllesmereUIDB._resetVersion
                _G["EllesmereUIDB"] = { _resetVersion = resetVer }
                EllesmereUIDB = _G["EllesmereUIDB"]
                if oldScale then EllesmereUIDB.ppUIScale = oldScale end
                if oldScaleAuto ~= nil then EllesmereUIDB.ppUIScaleAuto = oldScaleAuto end
                ReloadUI()
            end)
        end
        closeBtn:SetPoint("BOTTOM", welcomePopup, "BOTTOM", 0, POPUP_PAD_BOTTOM)

        -- Calculate dynamic height: title + gap + msg + gap + disc + gap + btn + padding
        local titleH = title:GetStringHeight()
        local msgH = msg:GetStringHeight()
        local discH = disc:GetStringHeight()
        local totalH = POPUP_PAD_TOP + titleH + 12 + msgH + 16 + discH + BTN_GAP + BTN_H + POPUP_PAD_BOTTOM
        welcomePopup:SetHeight(totalH)

        return welcomePopup, welcomeDimmer
    end

    function EllesmereUI:ShowWelcomePopup()
        local popup, dimmer = CreateWelcomePopup()
        dimmer:Show()
    end
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

        local popBgAtlas = popup:CreateTexture(nil, "BACKGROUND")
        popBgAtlas:SetAtlas("housing-basic-panel--stone-background")
        popBgAtlas:SetAllPoints()
        local popBgOverlay = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
        popBgOverlay:SetColorTexture(0, 0, 0, 0.75)
        popBgOverlay:SetAllPoints()

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
        popup._scaleWarnLabel:SetText(opts.scaleWarning)
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
        -- Recalculate pixel-perfect base scale every time the panel opens
        -- so resolution or UIParent scale changes are picked up immediately
        local physW2 = (GetPhysicalScreenSize())
        local baseScale2 = GetScreenWidth() / physW2
        local userScale2 = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
        mainFrame:SetScale(baseScale2 * userScale2)
        -- Re-sync PanelPP mult for the (possibly new) scale
        if EllesmereUI.PanelPP then EllesmereUI.PanelPP.UpdateMult() end
        -- Panel borders are resnapped by the tab-switch ResnapBordersUnder
        -- call (scoped to the active page, ~2ms). The global ResnapAllBorders
        -- was iterating every border in the addon (~74ms) which is unnecessary
        -- since non-panel borders have their own scale and resnap triggers.
        for _, fn in ipairs(_onShowCallbacks) do fn() end
    end)
    mainFrame:SetScript("OnHide", function()
        if _onHideCallbacks then
            for _, fn in ipairs(_onHideCallbacks) do fn() end
        end
        -- Release cached pages for non-active tabs to free memory.
        -- Keep the active page so reopening shows the same content.
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
    local NAV_ROW_H   = 50    -- height per nav row (Unlock / Global Settings)
    local NAV_ICON_W  = 52    -- exact pixel width
    local NAV_ICON_H  = 37    -- exact pixel height
    local NAV_LEFT    = 20    -- left padding for icon
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

    -- Helper: create a horizontal gradient glow texture on a sidebar button.
    -- Anchors top+bottom to the button so the texture scales with whatever
    -- height the row was sized to (group headers and child rows use different
    -- heights now).
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
    local ORIG_ADDON_NAV_TOP = NAV_TOP - NAV_ROW_H * 2

    -----------------------------------------------------------------------
    --  Sidebar search bar (filters addon list by display name or page name)
    -----------------------------------------------------------------------
    local SB_TOP_PAD     = 18   -- gap between Global Settings and the search bar
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
    sbPlaceholder:SetText("Search Features...")

    local sbClearBtn = CreateFrame("Button", nil, sidebarSearchFrame)
    sbClearBtn:SetSize(20, 20)
    sbClearBtn:SetPoint("RIGHT", sidebarSearchFrame, "RIGHT", -4, 0)
    sbClearBtn:SetFrameLevel(sbEdit:GetFrameLevel() + 2)
    sbClearBtn:Hide()
    local sbClearLabel = MakeFont(sbClearBtn, 20, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.35)
    sbClearLabel:SetPoint("CENTER")
    sbClearLabel:SetText("×")
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
        if EllesmereUI._applySidebarSearch then
            EllesmereUI._applySidebarSearch(text)
        end
    end)

    -- Addon scroll area sits below the search bar
    local ADDON_NAV_TOP = ORIG_ADDON_NAV_TOP - SB_TOTAL

    -----------------------------------------------------------------------
    --  Scrollable addon nav container
    --  The roster has grown past the space between ADDON_NAV_TOP and the
    --  class art, so addon buttons live inside a ScrollFrame with smooth
    --  mouse-wheel scrolling and a thin thumb on the right edge.
    -----------------------------------------------------------------------
    local ADDON_VISIBLE_ROWS    = 10.5
    -- +30 = 20px viewport bonus plus 10px offsetting the SB_TOP_PAD bump above,
    -- so growing the search-bar padding doesn't silently shrink the viewport.
    local ADDON_SCROLL_H        = ADDON_VISIBLE_ROWS * NAV_ROW_H - SB_TOTAL + 30
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
    -- Initial height bound (final value set in the button-build loop below using
    -- cumulative GROUP_ROW_H / CHILD_ROW_H offsets). Starts at the scroll area
    -- height so it's non-zero before the loop runs.
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

    local function UpdateAddonThumb()
        local maxScroll = EllesmereUI.SafeScrollRange and EllesmereUI.SafeScrollRange(addonScrollFrame) or 0
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
    -- Pixel-snap scroll offset in EFFECTIVE-PIXEL space (not raw WoW units),
    -- matching the main content-scroll pattern. Rounding in the direction of
    -- travel keeps the lerp monotonic so it doesn't bounce/overshoot on
    -- settlement. Fractional scroll offsets leave font glyphs on sub-pixel
    -- positions, and the rasterizer picks different pixels per frame -- this
    -- is the root cause of the visible 1px horizontal jitter on scroll.
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
        -- Snap the resting target to a pixel boundary so settlement lands on
        -- an integer-pixel row offset (same as the main content scroll does).
        target = math.floor(target * scale + 0.5) / scale
        addonScrollTarget = math.min(target, maxScroll)
        if not addonIsSmoothing then
            addonIsSmoothing = true
            addonSmoothFrame:Show()
        end
    end)
    addonScrollFrame:SetScript("OnScrollRangeChanged", UpdateAddonThumb)
    addonScrollFrame:HookScript("OnSizeChanged", UpdateAddonThumb)

    -- Click / drag on the scrollbar track. Clicking anywhere on the track
    -- jumps the scroll to that position; holding the button drags.
    -- The visible track is 3px wide so we add a wider invisible hit frame.
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

    -- Condensed grouped-sidebar row heights. Groups are text-only headers;
    -- children are indented rows with label + power. Goal: fit all addons
    -- without scrolling. Stored on EllesmereUI so RefreshSidebarStates /
    -- _applySidebarSearch can read the same values.
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
        label:SetText(group.label)
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

        -- Power toggle button (hidden for comingSoon, maintenance, or alwaysLoaded entries)
        if not info.comingSoon and not info.maintenance and not info.alwaysLoaded then
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
                self._tex:SetVertexColor(1, 1, 1, 1)
                if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
            end)
            pwrBtn:SetScript("OnClick", function(self)
                local enabled = IsAddonLoaded(self._folder)
                local action = enabled and "disable" or "enable"
                local folder = self._folder
                EllesmereUI:ShowConfirmPopup({
                    title       = (enabled and "Disable" or "Enable") .. " Module",
                    message     = "Are you sure you want to " .. action .. " " .. self._display .. "?",
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
            if self._notEnabled then return end
            if self._loaded and modules[self._folder] then
                EllesmereUI:SelectModule(self._folder)
            end
        end)

        return btn
    end

    -- Build the sidebar in group order. Positions are assigned once here and
    -- re-stacked by RefreshSidebarStates / _applySidebarSearch as needed.
    -- All group/roster references go through EllesmereUI fields to avoid adding
    -- upvalues inside CreateMainFrame (Lua 5.1 cap: 60). Cumulative `_y` walks
    -- each row so group and child heights can differ.
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
    footerFrame._resetBtn = resetBtn

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
        editBox:SetFont(EXPRESSWAY, 13, "")
        editBox:SetTextColor(TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B, 1)
        editBox:SetTextInsets(10, 24, 0, 0)
        editBox:SetMaxLetters(40)

        local placeholder = MakeFont(searchFrame, 12, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, 0.3)
        placeholder:SetPoint("LEFT", searchFrame, "LEFT", 10, 0)
        placeholder:SetText("Search Module Settings...")

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

EllesmereUI.PlaySearchHighlight = PlaySearchHighlight
EllesmereUI.GetSearchHighlight = GetSearchHighlight

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

function EllesmereUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
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
                -- Find the specific row to highlight and scroll to
                local target = sec.header
                if highlightText then
                    for _, m in ipairs(sec.members) do
                        if m._labelText and m._labelText:find(highlightText, 1, true) then
                            target = m
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
                        PlaySearchHighlight(hl, target)
                    end)
                end
                return
            end
        end
    end)
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
    -- Only allow registration from EllesmereUI addon files.
    -- Extract the addon folder name from the caller's file path.
    local caller = debugstack(2, 1, 0) or ""
    local callerFolder = caller:match("AddOns/([^/]+)/")
    if callerFolder then
        local ALLOWED = {
            EllesmereUI = true,
            EllesmereUIActionBars = true,
            EllesmereUIAuraBuffReminders = true,
            EllesmereUIBasics = true,
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
        }
        if not ALLOWED[callerFolder] then return end
    end
    modules[folderName] = config
    -- If UI is already built, update sidebar button immediately
    -- Otherwise, RefreshSidebarStates will handle it when the panel first opens
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

function EllesmereUI:SelectPage(pageName)
    if not activeModule or not modules[activeModule] then return end
    if pageName == activePage then return end

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
        _activePageWrapper = cached.wrapper
        contentFrame:SetHeight(cached.totalH + 30)

        -- Restore any elements hidden by a previous inline search.
        -- Skip if the search box is already empty -- ApplyInlineSearch("")
        -- calls CollectAllChildren which sorts + re-anchors every widget.
        local searchText = tabBar and tabBar._searchBox and tabBar._searchBox:GetText() or ""
        if searchText ~= "" then
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

            -- Inject Sync Profile Settings button for UI Reskin modules
            if EllesmereUI._reskinModules and EllesmereUI._reskinModules[activeModule] then
                local W = EllesmereUI.Widgets
                if W and W.WideButton then
                    startY = startY - 5
                    local synced = EllesmereUI.IsModuleSynced(activeModule)
                    local syncLabel = synced and "Settings are Cross-Profile. Click to Desync" or "Settings are Per-Profile. Click to Sync"
                    local syncFolder = activeModule
                    local syncBtnFrame, syncH
                    local syncBtnLbl
                    local syncBtnObj
                    local syncLocked = false
                    syncBtnFrame, syncH = W:WideButton(wrapper, syncLabel, startY, function()
                        if syncLocked then return end
                        local nowSynced = EllesmereUI.IsModuleSynced(syncFolder)
                        EllesmereUI.SetModuleSynced(syncFolder, not nowSynced)
                        if not nowSynced and syncBtnLbl then
                            -- Was off, now synced: show "Synced" confirmation
                            syncLocked = true
                            if syncBtnObj then syncBtnObj:Disable() end
                            local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
                            syncBtnLbl:SetText("Synced")
                            syncBtnLbl:SetTextColor(eg.r, eg.g, eg.b, 1)
                            C_Timer.After(1.2, function()
                                if syncBtnLbl then
                                    syncBtnLbl:SetText("Settings are Cross-Profile. Click to Desync")
                                    syncBtnLbl:SetTextColor(1, 1, 1, 1)
                                end
                                syncLocked = false
                                if syncBtnObj then
                                    syncBtnObj:Enable()
                                    syncBtnObj:SetAlpha(0.5)
                                end
                            end)
                        elseif syncBtnLbl then
                            -- Was on, now desynced: show "Desynced" confirmation
                            syncLocked = true
                            if syncBtnObj then syncBtnObj:Disable() end
                            syncBtnLbl:SetText("Desynced")
                            syncBtnLbl:SetTextColor(1, 0.4, 0.4, 1)
                            C_Timer.After(1.2, function()
                                if syncBtnLbl then
                                    syncBtnLbl:SetText("Settings are Per-Profile. Click to Sync")
                                    syncBtnLbl:SetTextColor(1, 1, 1, 1)
                                end
                                syncLocked = false
                                if syncBtnObj then
                                    syncBtnObj:Enable()
                                    syncBtnObj:SetAlpha(1)
                                end
                            end)
                        end
                    end)
                    do
                        local btn = select(1, syncBtnFrame:GetChildren())
                        if btn then
                            syncBtnObj = btn
                            for i = 1, btn:GetNumRegions() do
                                local rgn = select(i, btn:GetRegions())
                                if rgn and rgn.GetText and rgn:GetText() then
                                    syncBtnLbl = rgn; break
                                end
                            end
                            -- Tooltip explaining both states
                            btn:HookScript("OnEnter", function(self)
                                local eg = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.61 }
                                local hex = string.format("|cff%02x%02x%02x", eg.r * 255, eg.g * 255, eg.b * 255)
                                if EllesmereUI.IsModuleSynced(syncFolder) then
                                    self:SetAlpha(0.75)
                                    EllesmereUI.ShowWidgetTooltip(self, hex .. "Settings are Cross-Profile:|r Changes to this module apply to all profiles. Click to desync and use separate settings per profile.")
                                else
                                    EllesmereUI.ShowWidgetTooltip(self, hex .. "Settings are Per-Profile:|r Each profile has its own settings for this module. Click to sync and copy the current settings to all profiles.")
                                end
                            end)
                            btn:HookScript("OnLeave", function(self)
                                if EllesmereUI.IsModuleSynced(syncFolder) then
                                    self:SetAlpha(0.5)
                                end
                                EllesmereUI.HideWidgetTooltip()
                            end)
                            -- Desync state: dimmed at 50%
                            if synced then
                                btn:SetAlpha(0.5)
                            end
                        end
                    end
                    syncBtnFrame:SetScale(0.9)
                    -- Re-center: scale shrinks from TOPLEFT, shift right to compensate
                    local frameW = syncBtnFrame:GetWidth()
                    if frameW and frameW > 0 then
                        local offset = frameW * (1 - 0.9) / 2
                        local pt, rel, relPt, px, py = syncBtnFrame:GetPoint(1)
                        if pt then
                            syncBtnFrame:SetPoint(pt, rel, relPt, (px or 0) + offset, py or 0)
                        end
                    end
                    startY = startY - syncH * 0.9 + 5
                end
            end

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

    -- Re-snap all PP borders after tab switch. Cached frames are re-shown
    -- without going through CreateBorder's built-in 2-frame re-snap, so
    -- borders can end up misaligned until the panel is closed and reopened.
    -- Waiting 1 frame ensures the frame hierarchy has finished layout before
    -- we recalculate effective scales.
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
        local maxScroll = EllesmereUI.SafeScrollRange(scrollFrame)
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
    if folderName == activeModule then return end

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
    local rb = footerFrame and footerFrame._resetBtn
    if rb and rb._label then
        local displayName = config.title or folderName
        for _, entry in ipairs(ADDON_ROSTER) do
            if entry.folder == folderName then displayName = entry.display; break end
        end
        rb._label:SetText("Reset " .. displayName)
        rb._label:SetWidth(rb:GetWidth() * 0.85)
        rb._label:SetWordWrap(false)
        rb._label:SetMaxLines(1)
    end
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
--  Sidebar search filter
--  Iterates the last order captured by RefreshSidebarStates, hides any button
--  whose addon display name and registered page names don't contain the query,
--  and re-stacks the remaining ones at the top of the scroll area.
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

    local function childMatches(info)
        if #queryWords == 0 then return true end
        local parts = { (info.display or ""):lower() }
        local mod = modules[info.folder]
        if mod and mod.pages then
            for _, p in ipairs(mod.pages) do
                parts[#parts + 1] = tostring(p):lower()
            end
        end
        if mod and mod.searchTerms then
            if type(mod.searchTerms) == "table" then
                for _, t in ipairs(mod.searchTerms) do
                    parts[#parts + 1] = tostring(t):lower()
                end
            else
                parts[#parts + 1] = tostring(mod.searchTerms):lower()
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

    -- Re-apply the active sidebar search filter so it survives refreshes.
    local sbText = EllesmereUI._sidebarSearchText
    if sbText and sbText ~= "" and EllesmereUI._applySidebarSearch then
        EllesmereUI._applySidebarSearch(sbText)
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
    if self.NeedsBetaReset() then self:ShowWelcomePopup(); return end
    self:EnsureLoaded()
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
EllesmereUI.VERSION = "7.7.5"

-- Register this addon's version into a shared global table (taint-free at load time)
if not _G._EUI_AddonVersions then _G._EUI_AddonVersions = {} end
_G._EUI_AddonVersions[EUI_HOST_ADDON] = EllesmereUI.VERSION

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

-- Combat reload warning: if the UI was reloaded while in combat, show a
-- red warning in the center of the screen. Fades after 5s or on combat drop.
do
    local cf = CreateFrame("Frame")
    cf:RegisterEvent("PLAYER_ENTERING_WORLD")
    cf:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" then
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
            local function HasAnchoredActionBars()
                local adb = EllesmereUIDB and EllesmereUIDB.unlockAnchors
                if not adb then return false end
                for key, info in pairs(adb) do
                    if info.target then
                        -- Check if an action bar itself is anchored to something
                        local isBar = (key == "MainBar" or key == "StanceBar" or key == "PetBar"
                            or key == "MicroBar" or key == "BagBar" or key == "XPBar" or key == "RepBar"
                            or (key:sub(1, 3) == "Bar" and tonumber(key:sub(4))))
                        if isBar then return true end
                    end
                end
                return false
            end
            local function ShowWarning()
                if self._warn then return end
                if not HasAnchoredActionBars() then return end
                local warn = UIParent:CreateFontString(nil, "OVERLAY")
                warn:SetFont("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF", 24, "")
                warn:SetShadowOffset(1, -1)
                warn:SetShadowColor(0, 0, 0, 0.8)
                warn:SetTextColor(0.878, 0.247, 0.247, 1)
                warn:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
                warn:SetJustifyH("CENTER")
                warn:SetText("EUI: Combat Reload UI Warning:\nDrop combat to fix any layout issues")
                warn:Show()
                self:RegisterEvent("PLAYER_REGEN_ENABLED")
                self._warn = warn
                local elapsed = 0
                local fadeFrame = CreateFrame("Frame")
                fadeFrame:SetScript("OnUpdate", function(ff, dt)
                    elapsed = elapsed + dt
                    if elapsed >= 10 then
                        warn:Hide()
                        ff:SetScript("OnUpdate", nil)
                    elseif elapsed >= 9 then
                        warn:SetAlpha(1 - (elapsed - 9))
                    end
                end)
                self._fadeFrame = fadeFrame
            end
            if InCombatLockdown() then
                ShowWarning()
            else
                -- Brief delay: combat state may not be set yet at PEW
                C_Timer.After(0.5, function()
                    if InCombatLockdown() and not self._warn then
                        ShowWarning()
                    end
                end)
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if self._warn then
                self._warn:Hide()
                self._warn = nil
            end
            if self._fadeFrame then
                self._fadeFrame:SetScript("OnUpdate", nil)
                self._fadeFrame = nil
            end
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
-- Conflict check is wrapped in a function so the first-install popup
-- (EllesmereUI_FirstInstall.lua) can defer it until after the user picks
-- their initial addon list. The inline scheduler at the bottom of this
-- block only runs it automatically if the first-install popup has already
-- been shown in a prior session.
EllesmereUI._RunConflictCheck = function()
    if _G._EUI_ConflictCheckRan then return end
    _G._EUI_ConflictCheckRan = true
    do
        local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
        if not IsLoaded then return end

        -- conflict list: { addon, label, targets, message, moduleCheck }
        -- targets = "all" or a table of Ellesmere folder names
        -- message = optional custom popup message override
        -- moduleCheck = optional function returning true if the specific sub-module is active
        --              (used for Basics sub-modules: minimap, friends, chat, etc.)
        -- Per-addon enable check. Each EUI addon owns its own DB global;
        -- `key` is the profile sub-table name used inside that DB.
        -- Minimap, Friends, and QuestTracker no longer have a module-level
        -- enable toggle (loaded == enabled); their conflict entries rely
        -- on IsLoaded alone.
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
        -- Blizzard UI Enhanced has sub-features stored as flags on
        -- EllesmereUIDB. Conflicts against a specific sub-feature only
        -- fire when that feature is actually enabled.
        local function BlizzardSkinSubEnabled(key)
            if not EllesmereUIDB then return true end
            return EllesmereUIDB[key] ~= false
        end
        local conflicts = {
            { addon = "ElvUI",                    label = "ElvUI",                      targets = "all",                              message = "Many of ElvUI's modules are incompatible with EllesmereUI. Make sure to disable any conflicting modules." },
            { addon = "TellMeWhen",               label = "TellMeWhen",                 targets = "all",                              message = "TellMeWhen overlaps with EllesmereUI's core positional architecture. If you ONLY use for sound alerts it should be okay but may still cause issues." },
            { addon = "Bartender4",               label = "Bartender4",                 targets = { "EllesmereUIActionBars" } },
            { addon = "Dominos",                  label = "Dominos",                    targets = { "EllesmereUIActionBars" } },
            { addon = "UnhaltedUnitFrames",       label = "Unhalted Unit Frames",       targets = { "EllesmereUIUnitFrames" } },
            { addon = "Platynator",               label = "Platynator",                 targets = { "EllesmereUINameplates" } },
            { addon = "Plater",                   label = "Plater Nameplates",          targets = { "EllesmereUINameplates" } },
            { addon = "Kui_Nameplates",            label = "KUI Nameplates",             targets = { "EllesmereUINameplates" } },
            { addon = "TidyPlates",               label = "TidyPlates",                 targets = { "EllesmereUINameplates" } },
            { addon = "TidyPlates_ThreatPlates",  label = "TidyPlates ThreatPlates",    targets = { "EllesmereUINameplates" } },
            { addon = "Healers-Have-To-Die",      label = "Healers Have To Die",        targets = { "EllesmereUINameplates" } },
            { addon = "Aloft",                    label = "Aloft",                      targets = { "EllesmereUINameplates" } },
            { addon = "SenseiClassResourceBar",   label = "Sensei Class Resource Bar",  targets = { "EllesmereUIResourceBars" } },
            { addon = "FriendGroups",             label = "FriendGroups",               targets = { "EllesmereUIFriends" }, },
            { addon = "AccWideUILayoutSelection", label = "Account Wide Interface Settings", targets = { "EllesmereUIQuestTracker" }, },
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
            { addon = "EllesmereBarGlows",        label = "Ellesmere's CDM Bar Glows",  targets = "all" },
            { addon = "EllesmereNameplates",        label = "Ellesmere's Nameplates",  targets = "all" },
            { addon = "EllesmereActionBars",        label = "Ellesmere's Action Bars",  targets = "all" },
            { addon = "EllesmereUnitFrames",        label = "Ellesmere's Unit Frames",  targets = "all" },
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
            local moduleActive = not entry.moduleCheck or entry.moduleCheck()
            -- Suppress Ayije_CDM here if the CDM module's crash-prevention
            -- early-bail already fired -- its own popup supersedes this one.
            local suppressedBySpecific =
                (entry.addon == "Ayije_CDM" and _G._EUI_ECME_HandledAyijeCDM)
            if entry.addon ~= EUI_HOST_ADDON and IsLoaded(entry.addon)
               and moduleActive and not suppressedBySpecific then
                local affected = {}
                if entry.targets == "all" then
                    local allTargets = {
                        "EllesmereUIActionBars", "EllesmereUIUnitFrames", "EllesmereUINameplates",
                        "EllesmereUIResourceBars", "EllesmereUIAuraBuffReminders", "EllesmereUICooldownManager",
                        "EllesmereUIBasics", "EllesmereUIRaidFrames",
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
                -- Prefer the module's registered display title; fall back
                -- to stripping the EllesmereUI prefix from the folder name.
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

-- Auto-run the conflict check only if first-install has already been shown.
-- On first install, the first-install popup will call RunConflictCheck when
-- the user closes it (with no reload needed).
C_Timer.After(2, function()
    if EllesmereUIDB and EllesmereUIDB.firstInstallPopupShown then
        if EllesmereUI._RunConflictCheck then EllesmereUI._RunConflictCheck() end
    end
end)

SLASH_EUIOPTIONS1 = "/eui"
SLASH_EUIOPTIONS2 = "/ellesmere"
SLASH_EUIOPTIONS3 = "/ellesmereui"
-- Defer slash command actions by one frame to avoid tainting
-- Blizzard's ParseText -> ClearChat -> UpdateHeader chain when
-- typed in a BN_WHISPER edit box (secret tellTarget value).
SlashCmdList.EUIOPTIONS = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
            return
        end
        EllesmereUI:Toggle()
    end)
end

-- Debug: /euimem toggles per-second memory delta readout
SLASH_EUIMEM1 = "/euimem"
SlashCmdList.EUIMEM = function()
    if EllesmereUI._memTicker then
        EllesmereUI._memTicker:Cancel()
        EllesmereUI._memTicker = nil
        EllesmereUI.Print("|cff00ff00[EUI Memory Tracker]|r Stopped.")
        return
    end
    local addons = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name:find("^Ellesmere") and C_AddOns.IsAddOnLoaded(i) then
            addons[#addons + 1] = name
        end
    end
    UpdateAddOnMemoryUsage()
    local lastMem = {}
    for _, name in ipairs(addons) do
        lastMem[name] = GetAddOnMemoryUsage(name)
    end
    EllesmereUI.Print("|cff00ff00[EUI Memory Tracker]|r Tracking " .. #addons .. " addons. /euimem to stop.")
    local MEM_INTERVAL = 10
    local sampleCount = 0
    local accumMem = {}
    for _, name in ipairs(addons) do accumMem[name] = 0 end
    EllesmereUI._memTicker = C_Timer.NewTicker(1, function()
        UpdateAddOnMemoryUsage()
        sampleCount = sampleCount + 1
        for _, name in ipairs(addons) do
            local cur = GetAddOnMemoryUsage(name)
            local delta = cur - (lastMem[name] or cur)
            lastMem[name] = cur
            accumMem[name] = accumMem[name] + delta
        end
        if sampleCount < MEM_INTERVAL then return end
        -- Print averages (skip GC frames where total is negative)
        local totalAvg = 0
        for _, name in ipairs(addons) do
            totalAvg = totalAvg + accumMem[name] / MEM_INTERVAL
        end
        if totalAvg < 0 then
            for _, name in ipairs(addons) do accumMem[name] = 0 end
            sampleCount = 0
            return
        end
        totalAvg = 0
        local lines = {}
        for _, name in ipairs(addons) do
            local avg = accumMem[name] / MEM_INTERVAL
            totalAvg = totalAvg + avg
            if true then
                local short = name:gsub("^EllesmereUI", "")
                if short == "" then short = "Core" end
                local c = math.abs(avg) > 10 and "ffff6060" or math.abs(avg) > 5 and "ffffff60" or "ff60ff60"
                lines[#lines + 1] = string.format("  |c%s%s|r %+.1f kb/s", c, short, avg)
            end
            accumMem[name] = 0
        end
        sampleCount = 0
        local totalColor = math.abs(totalAvg) > 40 and "ffff6060" or math.abs(totalAvg) > 25 and "ffffff60" or "ff60ff60"
        EllesmereUI.Print(string.format("|c%s[EUI Memory Tracker]|r %+.1f kb/s avg", totalColor, totalAvg))
        for _, line in ipairs(lines) do EllesmereUI.Print(line) end
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

-- Debug: reset preview hint dismissed flag
SLASH_EUIRESETHINT1 = "/euiresethint"

-- Quick-access: /unlock opens Unlock Mode directly
SLASH_EUIUNLOCK1 = "/unlock"
SlashCmdList.EUIUNLOCK = function()
    C_Timer.After(0, function()
        if InCombatLockdown() then
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
            return
        end
        if EllesmereUI.NeedsBetaReset() then EllesmereUI:ShowWelcomePopup(); return end
        EllesmereUI:EnsureLoaded()
        if EllesmereUI._openUnlockMode then
            EllesmereUI._openUnlockMode()
        else
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Unlock Mode is not available.")
        end
    end)
end

-- Test: /euipopup shows the welcome popup without wiping anything
SLASH_EUIPOPUP1 = "/euipopup"
SlashCmdList.EUIPOPUP = function()
    C_Timer.After(0, function() EllesmereUI:ShowWelcomePopup() end)
end

SlashCmdList.EUIRESETHINT = function()
    C_Timer.After(0, function()
        if EllesmereUIDB then
            EllesmereUIDB.previewHintDismissed = nil
            EllesmereUIDB.unlockTipSeen = nil
            EllesmereUIDB.sidebarUnlockTipSeen = nil
        end
        EllesmereUI.Print("|cff00ff00[EllesmereUI]|r All hints reset. /reload to see them again.")
    end)
end

-- Debug: wipe saved UI scale so next reload re-snapshots from Blizzard default
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

-- Open the panel with a specific addon's tab selected
function EllesmereUI:ShowModule(folderName)
    if InCombatLockdown() then
        EllesmereUI.Print("|cffff6060[EllesmereUI]|r Cannot open options during combat.")
        return
    end
    if self.NeedsBetaReset() then self:ShowWelcomePopup(); return end
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
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -2, 0)
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
            EllesmereUI.Print("|cffff6060[EllesmereUI]|r Options closed -- entering combat.")
        end
        return
    end

    -- PLAYER_LOGIN: register demo modules (UI is built lazily on first open)
    self:UnregisterEvent("PLAYER_LOGIN")


    -- Stamp fresh installs so they never see the reset popup
    EllesmereUI.StampResetVersion()

    -- Show reset notification if the wipe just happened
    if EllesmereUI._showResetPopup then
        EllesmereUI._showResetPopup = nil
        C_Timer.After(1.5, function() EllesmereUI:ShowWelcomePopup() end)
    end

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

    -- Add EllesmereUI + Unlock Mode buttons to the Game Menu (pause menu).
    -- Both share a single Layout hook to avoid double-push conflicts.
    if GameMenuFrame and not EllesmereUI._GetFFD(GameMenuFrame).euiBtn then
        -- Game menu frame+button skinning lives in EllesmereUIBlizzardSkin.lua
        -- so it only applies when that addon is enabled. Detect whether the
        -- skin is active so EUI's own buttons match the skinned menu style.
        local _blizzSkinLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin")
        local _reskinMenu = _blizzSkinLoaded and EllesmereUIDB and EllesmereUIDB.reskinGameMenu
        if _reskinMenu == nil and _blizzSkinLoaded then _reskinMenu = (not EllesmereUIDB or (EllesmereUIDB.customTooltips ~= false and EllesmereUIDB.reskinQueuePopup ~= false)) end

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
            local RS = EllesmereUI.RESKIN
            local PP = EllesmereUI.PP
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
                cBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
                if PP and PP.CreateBorder then
                    PP.CreateBorder(inset, 1, 1, 1, RS.BRD_ALPHA, 1, "OVERLAY", 7)
                end
                local hl = customBtn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(inset)
                hl:SetColorTexture(1, 1, 1, 0.1)
                local cfs = customBtn:GetFontString()
                if cfs then
                    local euiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or nil
                    local _, size, flags = cfs:GetFont()
                    cfs:SetFont(euiFont or "Fonts\\FRIZQT__.TTF", (size or 14) - 2, flags or "")
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
                        local EG = ELLESMERE_GREEN
                        headerText:SetTextColor(EG.r, EG.g, EG.b, 1)
                    end
                end
            end

            -- Determine which buttons are visible
            local showEUI = not (EllesmereUIDB and EllesmereUIDB.hideGameMenuButton)
            local showUnlock = EllesmereUIDB and EllesmereUIDB.hideUnlockMenuButton == false

            if not showEUI then btn:Hide() end
            if not showUnlock then unlockBtn:Hide() end
            if not showEUI and not showUnlock then return end

            local eg = ELLESMERE_GREEN
            local hex = string.format("|cff%02x%02x%02x", (eg.r or 0.05) * 255, (eg.g or 0.82) * 255, (eg.b or 0.62) * 255)

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

            if showEUI then
                btn:Show()
                btn:SetText(hex .. "Ellesmere|r|cffffffff" .. "UI|r")
                if _reskinMenu then
                    local fs = btn:GetFontString()
                    if fs then fs:SetFont(euiFont, btnFontSize, "") end
                end
                btn:ClearAllPoints()
                btn:SetPoint("TOP", lastBtn, "BOTTOM", 0, -12)
                lastBtn = btn
                extraH = extraH + 40
            end
            if showUnlock then
                unlockBtn:Show()
                unlockBtn:SetText(hex .. "EUI|r |cffffffffUnlock Mode|r")
                if _reskinMenu then
                    local fs2 = unlockBtn:GetFontString()
                    if fs2 then fs2:SetFont(euiFont, btnFontSize, "") end
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
        -- Apply theme color to window background only
        if EllesmereUI._applyBgTint then
            EllesmereUI._applyBgTint(themeR, themeG, themeB)
        end
        -- Accent color priority: class color (if enabled) > custom override > theme
        if EllesmereUIDB.useClassAccentColor and EllesmereUI.GetPlayerClassColor then
            local cr, cg, cb = EllesmereUI.GetPlayerClassColor()
            ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = cr, cg, cb
        else
            local ca = EllesmereUIDB.customAccentColor
            if ca then
                ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = ca.r or themeR, ca.g or themeG, ca.b or themeB
            else
                ELLESMERE_GREEN.r, ELLESMERE_GREEN.g, ELLESMERE_GREEN.b = themeR, themeG, themeB
            end
        end
    end

    -- Spell ID / Item ID + Icon ID on Tooltip (developer option)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        -- Register per-type callbacks instead of AllTypes to avoid firing on
        -- every unit/currency tooltip in the game (major CPU savings).
        local _isSecret = issecretvalue  -- cache global once

        -- Shared dedup check: only scan last 4 lines (we add at most 2)
        local function hasDupLine(tooltip, name, tag)
            local n = tooltip:NumLines()
            local start = n - 3
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

        local function SpellIDTooltipHook(tooltip, data)
            if not (EllesmereUIDB and EllesmereUIDB.showSpellID) then return end
            if not data or not data.id then return end
            if _isSecret and _isSecret(data.id) then return end
            if not tooltip or not tooltip.GetName then return end
            local ok, name = pcall(tooltip.GetName, tooltip)
            if not ok or not name then return end
            if hasDupLine(tooltip, name, "SpellID") then return end
            tooltip:AddDoubleLine("SpellID", tostring(data.id), 1, 1, 1, 1, 1, 1)
            local iconID = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(data.id)
                or (GetSpellTexture and GetSpellTexture(data.id))
            if iconID then
                tooltip:AddDoubleLine("IconID", tostring(iconID), 1, 1, 1, 1, 1, 1)
            end
            tooltip:Show()
        end

        local function ItemIDTooltipHook(tooltip, data)
            if not (EllesmereUIDB and EllesmereUIDB.showSpellID) then return end
            if not data or not data.id then return end
            if _isSecret and _isSecret(data.id) then return end
            if not tooltip or not tooltip.GetName then return end
            local ok, name = pcall(tooltip.GetName, tooltip)
            if not ok or not name then return end
            if hasDupLine(tooltip, name, "ItemID") then return end
            tooltip:AddDoubleLine("ItemID", tostring(data.id), 1, 1, 1, 1, 1, 1)
            local iconID = C_Item.GetItemIconByID and C_Item.GetItemIconByID(data.id)
                or (GetItemIcon and GetItemIcon(data.id))
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
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ItemIDTooltipHook)
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

-------------------------------------------------------------------------------
--  Shared Visibility System
--  Unified visibility dropdown values, checkbox dropdown items, and runtime
--  checks used by CDM, Action Bars, Resource Bars, and Unit Frames.
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

-- Checkbox dropdown 2: Visibility Options (keys match DB fields)
EllesmereUI.VIS_OPT_ITEMS = {
    { key = "visOnlyInstances",    label = "Only Show in Instances" },
    { key = "visHideHousing",      label = "Hide in Housing" },
    { key = "visHideMounted",      label = "Hide when Mounted" },
    { key = "visHideNoTarget",     label = "Hide without Target",
      tooltip = "This bar will only show if you have a target" },
    { key = "visHideNoEnemy",      label = "Hide without Enemy Target",
      tooltip = "This bar will only show if you have an enemy targeted" },
}

-- Cache player class once at load time (never changes).
local _, _playerClass = UnitClass("player")

-- Druid mount-like form spell IDs. Travel Form applies a player aura with
-- spell ID 783 regardless of the active ground/swim/fly subform, so an
-- aura lookup is the most reliable cross-patch detection.
local DRUID_MOUNT_FORM_SPELLS = {
    783,    -- Travel Form
    1066,   -- Aquatic Form
    33943,  -- Flight Form
    40120,  -- Swift Flight Form
    165962, -- Flight Form (variant)
    210053, -- Mount Form (variant)
}

-- Runtime check: returns true if the element should be HIDDEN by visibility options.
-- `opts` is the settings table containing the vis option booleans.
function EllesmereUI.IsPlayerMountedLike()
    -- Fast path for regular mounts.
    if IsMounted and IsMounted() then return true end

    -- Only druids have mount-like shapeshift forms.
    if _playerClass ~= "DRUID" then return false end

    -- Aura check: the Travel Form buff is present on the player whenever
    -- the druid is shifted, regardless of ground/swim/fly subform.
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for i = 1, #DRUID_MOUNT_FORM_SPELLS do
            if C_UnitAuras.GetPlayerAuraBySpellID(DRUID_MOUNT_FORM_SPELLS[i]) then
                return true
            end
        end
    end

    return false
end

-- Non-macro visibility subset: the options that CAN'T be expressed in a
-- secure [macro] condition and must be evaluated in Lua. Used by secure
-- action bar frames that delegate the macro-expressible options
-- (target/combat/group) to their state-visibility driver and only need
-- Lua handling for these three.
function EllesmereUI.CheckVisibilityOptionsNonMacro(opts)
    if not opts then return false end

    -- Only Show in Instances
    if opts.visOnlyInstances then
        local _, iType, diffID = GetInstanceInfo()
        diffID = tonumber(diffID) or 0
        local inInstance = false
        if diffID > 0 then
            if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
                inInstance = false
            elseif iType == "party" or iType == "raid" or iType == "scenario" or iType == "arena" or iType == "pvp" then
                inInstance = true
            end
        end
        if not inInstance then return true end
    end

    -- Hide in Housing
    if opts.visHideHousing then
        if C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then
            return true
        end
    end

    -- Hide when Mounted (includes druid travel/flight/aquatic forms)
    if opts.visHideMounted then
        if EllesmereUI.IsPlayerMountedLike and EllesmereUI.IsPlayerMountedLike() then return true end
    end

    return false
end

function EllesmereUI.CheckVisibilityOptions(opts)
    if not opts then return false end

    -- Instances / housing / mounted (shared with secure-frame fast path).
    if EllesmereUI.CheckVisibilityOptionsNonMacro(opts) then return true end

    -- Hide without Target
    if opts.visHideNoTarget then
        if not UnitExists("target") then return true end
    end

    -- Hide without Enemy Target
    if opts.visHideNoEnemy then
        if not (UnitExists("target") and UnitCanAttack("player", "target")) then return true end
    end

    return false
end

-- Runtime check: returns true if the element should be SHOWN based on the
-- visibility mode dropdown value. Caller provides combat/group state.
-- `mode` is the string from the visibility dropdown.
-- `state` is a table: { inCombat, inRaid, inParty }
function EllesmereUI.CheckVisibilityMode(mode, state)
    if mode == "disabled" then return false end
    if mode == "never" then return false end
    if mode == "in_combat" then return state.inCombat end
    if mode == "out_of_combat" then return not state.inCombat end
    if mode == "in_raid" then return state.inRaid end
    if mode == "in_party" then return state.inParty or state.inRaid end
    if mode == "solo" then return not state.inRaid and not state.inParty end
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
--  Shared Player Cast Bar Suppression
--  Multiple EUI modules can temporarily suppress Blizzard's player cast bar
--  while they render their own. We centralize that ownership here so modules
--  cooperate with each other and leave third-party visibility control alone
--  once no EUI module is actively using a replacement bar.
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

        if blizzBar:GetParent() ~= hiddenParent then
            blizzBar:SetParent(hiddenParent)
        end

        -- Edit Mode tries to re-anchor the cast bar during layout changes.
        -- Keep re-applying our hidden parent while any EUI owner suppresses it.
        if not EllesmereUI._GetFFD(blizzBar).setParentHooked then
            EllesmereUI._GetFFD(blizzBar).setParentHooked = true
            hooksecurefunc(blizzBar, "SetParent", function(self, newParent)
                if EllesmereUI._GetFFD(self).castBarSuppressed and newParent ~= EllesmereUI._playerCastBarHiddenParent then
                    C_Timer.After(0, function()
                        if EllesmereUI._GetFFD(self).castBarSuppressed
                           and not InCombatLockdown()
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
                    if PlayerCastingBarFrame and EllesmereUI._GetFFD(PlayerCastingBarFrame).castBarSuppressed then
                        self:SetAlpha(0)
                        self:EnableMouse(false)
                    end
                end)
            end
        end

        return
    end

    EllesmereUI._GetFFD(blizzBar).castBarSuppressed = false

    if hiddenParent and blizzBar:GetParent() == hiddenParent and EllesmereUI._GetFFD(blizzBar).origParent then
        blizzBar:SetParent(EllesmereUI._GetFFD(blizzBar).origParent)
    end

    local selection = blizzBar.Selection
    if selection then
        EllesmereUI._GetFFD(selection).suppressed = false
        selection:SetAlpha(EllesmereUI._GetFFD(selection).restoreAlpha or 1)
        selection:EnableMouse(EllesmereUI._GetFFD(selection).restoreMouse or false)
    end

    -- Let Blizzard rebuild its normal event wiring and pick up any active cast
    -- without forcing visibility back on. This keeps profile switches and
    -- UnitFrames/oUF teardown compatible with Blizzard's own cast bar logic.
    if blizzBar.SetUnit then
        blizzBar:SetUnit("player")
    end
end


