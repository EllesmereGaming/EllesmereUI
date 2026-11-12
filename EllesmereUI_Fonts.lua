if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Fonts.lua
--  Font tables and LSM registration, font resolution cache and per-module
--  getters, outline/slug/shadow helpers, font families, game-text font. Loads after
--  EllesmereUI_Colors.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI

local MEDIA_PATH = EllesmereUI.MEDIA_PATH

-------------------------------------------------------------------------------
--  Global Font System
-------------------------------------------------------------------------------
-- Canonical font name -> filename mapping (shared across all addons)
EllesmereUI.FONT_FILES = {
    ["Expressway"]          = "Expressway.TTF",
    ["Expressway Bold"]     = "Expressway Bold.ttf",
    ["Expressway CAPS"]     = "Expressway CAPS.ttf",
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
    ["HWT Artz"]            = "HWT Artz.ttf",
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
-- Future X Black, Homespun, HWT Artz, KMT Ninja Naruto, Barlow Condensed) has ZERO Cyrillic
-- and would render boxes. Re-check coverage before adding a face; a wrong entry ships
-- unreadable text. Expressway CAPS: cmap checked, 66/66 Russian letters (Yo pair included).
-- Deliberately NOT extended to FONT_BLIZZARD: the Cyrillic-capable Blizzard face is
-- FRIZQT___CYR (already the fallback), and the plain ones vary by installed client locale.
EllesmereUI.FONT_CYRILLIC = {
    ["Expressway"]       = true,
    ["Expressway Bold"]  = true,
    ["Expressway CAPS"]  = true,
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
    "Expressway", "Expressway Bold", "Expressway CAPS", "Avant Garde", "Arial Bold", "Poppins",
    "Fira Sans Medium",
    "---",
    "Arial Narrow", "Changa", "Cinzel Decorative", "Exo",
    "Fira Sans Bold", "Fira Sans Light", "Future X Black",
    "Gotham Narrow Ultra", "Gotham Narrow", "Russo One", "Ubuntu", "Homespun", "HWT Artz",
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
-- The client's standard UI font, read when used (another addon may set the global
-- after this file loads). "Apply to All Game Text" overwrites STANDARD_TEXT_FONT,
-- so the value it replaced is kept (_clientFontPath, ApplyGlobalFontToGameText) and wins.
function EllesmereUI.GetBlizzardFontPath()
    return EllesmereUI._clientFontPath or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

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
        return EllesmereUI.GetBlizzardFontPath()
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
    if EllesmereUI.LOCALE_FONT_FALLBACK then
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
        return EllesmereUI.LOCALE_FONT_FALLBACK
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

-- Floating combat text is in the client's language, not EUI's display language. On a
-- glyph-restricted client, a Combat Text Font key counts only if it can draw that script:
-- a SharedMedia font or a Blizzard file LSM registers (LSM keeps just the ones flagged
-- for the client), or a FONT_CYRILLIC face on ruRU.
function EllesmereUI.CombatTextFontCoversLocale(key)
    local locale = GetLocale()
    if not EllesmereUI.LocaleGlyphFont(locale) or key:match("^smf:") then return true end
    if locale == "ruRU" then
        for name, file in pairs(EllesmereUI.FONT_FILES) do
            if EllesmereUI.FONT_CYRILLIC[name] and key == MEDIA_PATH .. "fonts\\" .. file then return true end
        end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    for _, path in pairs(LSM and LSM:HashTable("font") or {}) do
        if path == key then return true end
    end
    return false
end

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
    essentials   = "EllesmereUIForeverEssentials",
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
    lootCouncil  = "EllesmereUISimpleLootCouncil",
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
    local flag = EllesmereUI.OutlineFlagForMode(mode)
    c[k] = flag
    return flag
end

-- The WoW font flag for one outline mode ("outline", "thick"; anything else is
-- none/shadow), slug-gated. For a feature with its own outline choice; resolve
-- "__global" through GetFontOutlineFlag first.
function EllesmereUI.OutlineFlagForMode(mode)
    local flag
    if mode == "outline" then flag = "OUTLINE, SLUG"
    elseif mode == "thick" then flag = "THICKOUTLINE, SLUG"
    else flag = "" end
    return EllesmereUI.SlugFlag(flag)
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

-------------------------------------------------------------------------------
--  Font families. A text that can show other players' writing (unit names,
--  guild names, Battle.net names and notes, chat bubbles, meter rows, tooltip
--  lines) takes a FONT FAMILY instead of one font file. The engine draws a whole
--  string with ONE member, chosen by its content: any Cyrillic letter takes the
--  russian member (Latin letters in that string included), Latin-only text the
--  roman one. The chosen font is the roman member, the russian member when it
--  carries Cyrillic and the client's own CJK alphabet's member; Blizzard's own
--  Cyrillic, Korean and Chinese faces draw the scripts it lacks. Every member has
--  the same size and flags, so Latin text draws exactly as with a plain SetFont.
--  A family carries face, size, flags and its shadow (a drop shadow renders only
--  from a font object), never a text colour or justification: SetFontObject
--  pushes only what the object defines, so a string keeps its own.
--  A plain fs:SetFont pins that string's face for good (a later SetFontObject no
--  longer changes it), so a string takes its family from its FIRST font write
--  and every later write to it goes through SetFontFamily, never SetFont,
--  ApplyModuleFont, ApplyIconTextFont or PrimeFontShadow.
--  Blizzard's own font OBJECTS (families or plain) change member by member
--  through SetFontObjectFace. A family object's own SetFont changes only its own
--  font, the one GetFont() reads and copies take (Blizzard's guild chat copies the
--  main chat window's), never a member; SetFontObjectFace sets it too, where the
--  client's own alphabet takes the face.
--  Built once per path / size / flags / shadow; a hit reads four table fields and
--  builds nothing. Table fields, not file-scope locals (200-local limit).
-------------------------------------------------------------------------------
EllesmereUI._FONT_ALPHABETS = { "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }
-- The client language whose stock face draws each CJK alphabet.
EllesmereUI._FONT_CJK_LOCALE = { korean = "koKR", simplifiedchinese = "zhCN", traditionalchinese = "zhTW" }
-- The client's own CJK alphabet (nil on other clients) keeps the chosen font, as
-- every text in the client's language draws with it.
EllesmereUI._FONT_CLIENT_ALPHABET = ({ koKR = "korean", zhCN = "simplifiedchinese",
    zhTW = "traditionalchinese" })[GetLocale()]
-- On a Russian client the russian member keeps the path, as every text in Russian draws with it.
EllesmereUI._FONT_CLIENT_RU = (GetLocale() == "ruRU")
-- The alphabet the client's own language draws with.
EllesmereUI._FONT_CLIENT_OWN = EllesmereUI._FONT_CLIENT_ALPHABET
    or (EllesmereUI._FONT_CLIENT_RU and "russian") or "roman"
EllesmereUI._FONT_CYR_FILE = "Fonts\\FRIZQT___CYR.TTF"
-- path -> size -> flags ("" for none) -> shadow (true / false) -> family, or false
-- when the client has no families or the creation failed (never retried).
EllesmereUI._fontFamilies = {}
EllesmereUI._fontFamilyCount = 0
-- Our families and their member objects: the game text passes skip them.
EllesmereUI._fontFamilySet = setmetatable({}, { __mode = "k" })
EllesmereUI._fontPathCyr = {}   -- path -> it draws the Russian alphabet
EllesmereUI._fontPathOK = {}    -- path -> the client loads it
EllesmereUI._fontObjIsFamily = setmetatable({}, { __mode = "k" })  -- font object -> is a family
EllesmereUI._fontFaceDone = {}  -- the members one SetFontObjectFace call has set (reused)

-- True when `path` draws the full Russian alphabet: a FONT_CYRILLIC face's file,
-- Blizzard's Cyrillic Friz, or any path on a Russian client. Cached per path.
function EllesmereUI._FontPathCyrillic(path)
    if type(path) ~= "string" then return false end
    local c = EllesmereUI._fontPathCyr
    local hit = c[path]
    if hit ~= nil then return hit end
    local yes = EllesmereUI._FONT_CLIENT_RU
    if not yes then
        local low = path:lower():gsub("/", "\\")
        yes = (low == EllesmereUI._FONT_CYR_FILE:lower())
        if not yes then
            local dir = (MEDIA_PATH .. "fonts\\"):lower()
            for name in pairs(EllesmereUI.FONT_CYRILLIC) do
                local file = EllesmereUI.FONT_FILES[name]
                if file and low == dir .. file:lower() then
                    yes = true
                    break
                end
            end
        end
    end
    c[path] = yes
    return yes
end

-- Whether a member of `alphabet` takes the face `path` (else it keeps a stock face):
-- roman always, russian when the path draws Russian, the client's own CJK alphabet.
function EllesmereUI._FontMemberTakesPath(alphabet, path)
    if alphabet == "roman" or alphabet == EllesmereUI._FONT_CLIENT_ALPHABET then return true end
    if alphabet == "russian" then return EllesmereUI._FontPathCyrillic(path) end
    return false
end

-- Whether the client loads the font file at `path`: a hidden scratch string's
-- SetFont returns false for a file it cannot load. Tested once per path, except
-- that failures are retested until the loading screen after the first one ends
-- (see below).
function EllesmereUI._FontPathLoads(path)
    local c = EllesmereUI._fontPathOK
    local hit = c[path]
    if hit ~= nil then return hit end
    local probe = EllesmereUI._fontProbe
    if not probe then
        local holder = CreateFrame("Frame")
        holder:Hide()
        probe = holder:CreateFontString()
        EllesmereUI._fontProbe = probe
    end
    local ok, loaded = pcall(probe.SetFont, probe, path, 12, "")
    hit = ok and loaded ~= false
    -- On a fresh game start a file can fail before it is read: retested at login (see below).
    if hit or EllesmereUI._fontRetryDone then c[path] = hit else EllesmereUI._FontRetryArm(path) end
    return hit
end

-- Paths that failed before login finished, and the families built without them.
EllesmereUI._fontPathPending = {}
EllesmereUI._fontFamPending = {}
-- Retests each pending path at the login stages; a path that loads goes into the
-- families that fell back, member by member, so their texts update in place.
function EllesmereUI._FontRetryArm(path)
    EllesmereUI._fontPathPending[path] = true
    local f = EllesmereUI._fontRetryFrame
    if f then return end
    f = CreateFrame("Frame")
    EllesmereUI._fontRetryFrame = f
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("LOADING_SCREEN_DISABLED")
    f:SetScript("OnEvent", function(self, event)
        local pending, c = EllesmereUI._fontPathPending, EllesmereUI._fontPathOK
        local final = event == "LOADING_SCREEN_DISABLED"
        for p in pairs(pending) do
            local ok, loaded = pcall(EllesmereUI._fontProbe.SetFont, EllesmereUI._fontProbe, p, 12, "")
            if ok and loaded ~= false then
                c[p], pending[p] = true, nil
                EllesmereUI._FontFamiliesTakePath(p)
            elseif final then
                c[p], pending[p] = false, nil
            end
        end
        if final or not next(pending) then
            EllesmereUI._fontRetryDone = final or nil
            if final then
                self:UnregisterAllEvents()
                wipe(EllesmereUI._fontFamPending)
            end
        end
    end)
end

-- The families built while `path` failed get it now, on the members that take it,
-- and as their own font (a family built with the path has its roman member's).
function EllesmereUI._FontFamiliesTakePath(path)
    local list = EllesmereUI._fontFamPending
    local alphabets = EllesmereUI._FONT_ALPHABETS
    for i = #list, 1, -1 do
        local e = list[i]
        if e.path == path then
            for a = 1, #alphabets do
                local member = EllesmereUI._FontMemberTakesPath(alphabets[a], path)
                    and e.fam:GetFontObjectForAlphabet(alphabets[a])
                if member then pcall(member.SetFont, member, path, e.size, e.flags) end
            end
            pcall(e.fam.SetFont, e.fam, path, e.size, e.flags)
            table.remove(list, i)
        end
    end
end

-- The shadow on the family and on each member (PrimeFontShadow's values), and the
-- family and its members into the set the game text passes skip. Once, at creation.
function EllesmereUI._DressFontFamily(fam, shadow)
    local set = EllesmereUI._fontFamilySet
    set[fam] = true
    local a, x, y = 0, 0, 0
    if shadow then a, x, y = 1, 1, -1 end
    fam:SetShadowColor(0, 0, 0, a)
    fam:SetShadowOffset(x, y)
    local alphabets = EllesmereUI._FONT_ALPHABETS
    for i = 1, #alphabets do
        local member = fam:GetFontObjectForAlphabet(alphabets[i])
        if member then
            set[member] = true
            member:SetShadowColor(0, 0, 0, a)
            member:SetShadowOffset(x, y)
        end
    end
end

-- Builds and caches the family for one key. A path the client cannot load takes the
-- client's standard font.
function EllesmereUI._BuildFontFamily(path, size, flags, shadow)
    if type(path) ~= "string" or type(size) ~= "number" or not (size > 0) then return nil end
    local cache = EllesmereUI._fontFamilies
    local bySize = cache[path]
    if not bySize then bySize = {}; cache[path] = bySize end
    local byFlags = bySize[size]
    if not byFlags then byFlags = {}; bySize[size] = byFlags end
    local byShadow = byFlags[flags]
    if not byShadow then byShadow = {}; byFlags[flags] = byShadow end
    local create = CreateFontFamily
    if type(create) ~= "function" then
        byShadow[shadow] = false
        return nil
    end
    local face = path
    if not EllesmereUI._FontPathLoads(path) then face = EllesmereUI.GetBlizzardFontPath() end
    local alphabets = EllesmereUI._FONT_ALPHABETS
    local members = {}
    for i = 1, #alphabets do
        local alphabet = alphabets[i]
        local file = face
        if not EllesmereUI._FontMemberTakesPath(alphabet, face) then
            if alphabet == "russian" then
                file = EllesmereUI._FONT_CYR_FILE
            else
                file = EllesmereUI.LocaleGlyphFont(EllesmereUI._FONT_CJK_LOCALE[alphabet])
            end
        end
        members[i] = { alphabet = alphabet, file = file, height = size, flags = flags }
    end
    EllesmereUI._fontFamilyCount = EllesmereUI._fontFamilyCount + 1
    local ok, fam = pcall(create, "EUIFontFamily" .. EllesmereUI._fontFamilyCount, members)
    if ok and fam then ok = pcall(EllesmereUI._DressFontFamily, fam, shadow) end
    if not (ok and fam) then
        byShadow[shadow] = false
        return nil
    end
    byShadow[shadow] = fam
    if face ~= path and EllesmereUI._fontPathPending[path] then
        local list = EllesmereUI._fontFamPending
        list[#list + 1] = { fam = fam, path = path, size = size, flags = flags }
    end
    return fam
end

-- The family font object for a face, size, outline flags and shadow, or nil when the
-- client has no font families (or this one could not be made): the caller then sets
-- the font the plain way. One family per key for the session.
function EllesmereUI.GetFontFamily(path, size, flags, shadow)
    flags = flags or ""
    shadow = shadow and true or false
    -- Scaled texts (raid and party auto-resize, size offsets) hand fractional sizes:
    -- families are kept per quarter point, so a slider drag reuses a few of them (a
    -- font object is never freed), at most an eighth of a point off.
    if type(size) == "number" then size = math.floor(size * 4 + 0.5) / 4 end
    local t = EllesmereUI._fontFamilies[path]
    t = t and t[size]
    t = t and t[flags]
    local fam = t and t[shadow]
    if fam then return fam end
    if fam == false then return nil end
    return EllesmereUI._BuildFontFamily(path, size, flags, shadow)
end

-- Sets a font string's font as a family (see the block above). A string already on
-- that family is not touched. Its first switch from a font object that is not one
-- of ours keeps the string's justification and text colour, which a template object
-- may have given it. With no family: PrimeFontShadow, then a plain SetFont.
function EllesmereUI.SetFontFamily(fs, path, size, flags, shadow)
    if not (fs and fs.SetFontObject) then return end
    local fam = EllesmereUI.GetFontFamily(path, size, flags, shadow)
    if not fam then
        EllesmereUI.PrimeFontShadow(fs, shadow)
        fs:SetFont(path, size, flags)
        return
    end
    local cur = fs:GetFontObject()
    if cur == fam then return end
    if cur and EllesmereUI._fontFamilySet[cur] then
        fs:SetFontObject(fam)
        return
    end
    -- The getters may hand back secret values (a text colour set from secret
    -- data), so they are tested with type() only and passed straight back.
    local justifyH, justifyV = fs:GetJustifyH(), fs:GetJustifyV()
    local r, g, b, a = fs:GetTextColor()
    fs:SetFontObject(fam)
    if type(justifyH) == "string" then fs:SetJustifyH(justifyH) end
    if type(justifyV) == "string" then fs:SetJustifyV(justifyV) end
    if type(r) == "number" then fs:SetTextColor(r, g, b, a) end
end

-- True when a font object is a family: its roman and russian alphabets have
-- members of their own. Read once per object.
function EllesmereUI._FontObjectIsFamily(obj)
    local c = EllesmereUI._fontObjIsFamily
    local hit = c[obj]
    if hit ~= nil then return hit end
    local yes = false
    if obj.GetFontObjectForAlphabet then
        local okR, roman = pcall(obj.GetFontObjectForAlphabet, obj, "roman")
        local okC, russian = pcall(obj.GetFontObjectForAlphabet, obj, "russian")
        yes = (okR and okC and roman ~= nil and russian ~= nil and roman ~= russian) and true or false
    end
    c[obj] = yes
    return yes
end

-- One member (or plain object): the face `path` when given, else its own; `size`
-- when given, else its own size times `scale`; `flags` when given, else its own.
-- A member already in `done` is skipped, so a member several alphabets or objects
-- share changes once (a scale never compounds).
function EllesmereUI._SetFontMemberFace(member, path, size, flags, scale, done)
    if done[member] then return end
    done[member] = true
    local face, msize, mflags = member:GetFont()
    if not msize or msize <= 0 then return end
    face = path or face
    if not face then return end
    pcall(member.SetFont, member, face, size or msize * (scale or 1), flags or mflags or "")
end

-- SetFontObjectFace's body with the caller's `done` set (a game text pass shares one
-- set across every object it changes).
function EllesmereUI._FontObjectFaceInto(obj, path, size, flags, scale, done)
    if EllesmereUI._FontObjectIsFamily(obj) then
        local alphabets = EllesmereUI._FONT_ALPHABETS
        for i = 1, #alphabets do
            local alphabet = alphabets[i]
            local ok, member = pcall(obj.GetFontObjectForAlphabet, obj, alphabet)
            if ok and member then
                local face = path
                if face and not EllesmereUI._FontMemberTakesPath(alphabet, face) then face = nil end
                EllesmereUI._SetFontMemberFace(member, face, size, flags, scale, done)
            end
        end
        -- The family's own font as well (it changes no member): GetFont() reads it and
        -- copies take it (the guild chat copies the main chat window's font). Only
        -- where the client's own alphabet takes the face.
        if not path or EllesmereUI._FontMemberTakesPath(EllesmereUI._FONT_CLIENT_OWN, path) then
            EllesmereUI._SetFontMemberFace(obj, path, size, flags, scale, done)
        end
    else
        EllesmereUI._SetFontMemberFace(obj, path, size, flags, scale, done)
    end
end

-- Changes a Blizzard font OBJECT, family or plain. A family changes member by member:
-- `path` (nil keeps every face) goes to the members that take it under the family
-- rules (roman; russian when the path draws Russian; the client's own CJK alphabet),
-- the others keep their own faces; `size` (nil: each member's own size times `scale`,
-- default 1) and `flags` (nil: each member's own) go to every member. A plain object
-- takes the same on itself.
function EllesmereUI.SetFontObjectFace(obj, path, size, flags, scale)
    if not (obj and type(obj) == "table" and obj.GetFont and obj.SetFont) then return end
    local done = EllesmereUI._fontFaceDone
    wipe(done)
    EllesmereUI._FontObjectFaceInto(obj, path, size, flags, scale, done)
end

-- Each member's (or a plain object's) face, size and flags, and a family's own
-- font, for RestoreFontObject.
function EllesmereUI.SnapshotFontObject(obj)
    if not (obj and type(obj) == "table" and obj.GetFont) then return nil end
    local snap = {}
    if EllesmereUI._FontObjectIsFamily(obj) then
        local ownFace, ownSize, ownFlags = obj:GetFont()
        snap.own = { face = ownFace, size = ownSize, flags = ownFlags }
        local alphabets = EllesmereUI._FONT_ALPHABETS
        for i = 1, #alphabets do
            local ok, member = pcall(obj.GetFontObjectForAlphabet, obj, alphabets[i])
            if ok and member then
                local face, size, flags = member:GetFont()
                snap[alphabets[i]] = { face = face, size = size, flags = flags }
            end
        end
    else
        local face, size, flags = obj:GetFont()
        snap.plain = { face = face, size = size, flags = flags }
    end
    return snap
end

function EllesmereUI._RestoreFontMember(member, s)
    if s and s.face and s.size and s.size > 0 then
        pcall(member.SetFont, member, s.face, s.size, s.flags or "")
    end
end

-- Puts back what SnapshotFontObject read.
function EllesmereUI.RestoreFontObject(obj, snap)
    if not (obj and type(obj) == "table" and obj.SetFont and snap) then return end
    if snap.plain then
        EllesmereUI._RestoreFontMember(obj, snap.plain)
        return
    end
    EllesmereUI._RestoreFontMember(obj, snap.own)
    local alphabets = EllesmereUI._FONT_ALPHABETS
    for i = 1, #alphabets do
        local s = snap[alphabets[i]]
        if s then
            local ok, member = pcall(obj.GetFontObjectForAlphabet, obj, alphabets[i])
            if ok and member then EllesmereUI._RestoreFontMember(member, s) end
        end
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
-- The font objects the pass leaves alone: the floating combat text's, which the
-- Combat Text Font setting owns.
EllesmereUI._GAME_TEXT_KEEP = { "CombatTextFont", "SystemFont_World" }
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
        -- The client's own font, before the first swap replaces it (Blizzard Default).
        EllesmereUI._clientFontPath = EllesmereUI._clientFontPath or _G.STANDARD_TEXT_FONT
        -- Universal fallback consumed by newly-created Blizzard/addon text.
        _G.STANDARD_TEXT_FONT = path
    end

    -- Enumerate every registered font object via the game's own font list (no
    -- hardcoded list to go stale); covers Blizzard + other addons in one pass.
    -- A family changes member by member (SetFontObjectFace): a member whose script
    -- the chosen face lacks keeps its own face, so Russian, Korean and Chinese text
    -- keeps drawing. One `done` set for the whole pass, so a member several objects
    -- share scales once. Our own families are skipped.
    local fonts = (GetFonts and GetFonts()) or {}
    local ours = EllesmereUI._fontFamilySet
    local done = {}
    -- The floating combat text over the player draws with CombatTextFont (on the
    -- SystemFont_World family), the numbers over enemies with DAMAGE_TEXT_FONT. Both
    -- follow the Combat Text Font setting alone, so the pass marks those two objects,
    -- their own fonts and every member as done and leaves them as they are.
    local keep = EllesmereUI._GAME_TEXT_KEEP
    local alphabets = EllesmereUI._FONT_ALPHABETS
    for k = 1, #keep do
        local obj = _G[keep[k]]
        if obj and type(obj) == "table" then
            done[obj] = true
            if obj.GetFontObjectForAlphabet then
                for a = 1, #alphabets do
                    local ok, member = pcall(obj.GetFontObjectForAlphabet, obj, alphabets[a])
                    if ok and member then done[member] = true end
                end
            end
        end
    end
    for i = 1, #fonts do
        local obj = _G[fonts[i]]
        -- Guard each: GetFonts may list entries that are not usable font objects.
        if obj and type(obj) == "table" and not ours[obj] and obj.GetFont and obj.SetFont then
            EllesmereUI._FontObjectFaceInto(obj, swap and path or nil, nil, nil, scale, done)
        end
    end
    -- Premade Groups' category labels are copies of GameFontNormal taken as each button
    -- is built, with no font object to follow, so one built before this pass (the first:
    -- Blizzard's XML declares it) keeps the client's face. A label still on that face
    -- takes the global one at its own size. Nothing to do under Blizzard Default (the
    -- same face) or on WoW Forever (no such window, so the wait would never end).
    local old = EllesmereUI._clientFontPath
    if swap and path ~= old and not EllesmereUI.IS_FOREVER and EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_GroupFinder", function()
            if not LFGListCategorySelection_AddButton then return end
            hooksecurefunc("LFGListCategorySelection_AddButton", function(cs, i)
                local b = cs and type(cs.CategoryButtons) == "table" and cs.CategoryButtons[i]
                local label = b and b.Label
                if not (label and label.GetFont) then return end
                local face, size, flags = label:GetFont()  -- not in an and-chain, that keeps only face
                if face == old and size then label:SetFont(path, size, flags or "") end
            end)
        end)
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
    -- A family changes member by member (SetFontObjectFace): the members whose script the
    -- face lacks keep their own faces. Our own families are skipped.
    local function swap(obj, path, outline)
        if not obj or type(obj) ~= "table" or EllesmereUI._fontFamilySet[obj] then return end
        EllesmereUI.SetFontObjectFace(obj, path or _G.STANDARD_TEXT_FONT, nil, outline, nil)
    end

    -- Chat: the module fonts the frames + edit boxes directly; ChatFontNormal backstops the rest (menus, copy/URL windows, channel buttons, etc.).
    if IsLoaded("EllesmereUIChat") then
        swap(_G.ChatFontNormal, GetPath("chat"), GetOutline and GetOutline("chat"))
    end

    -- Quest Tracker: the skin region-walks live blocks; these shared objects catch fontstrings
    -- Blizzard re-templates after the walk. ONLY ObjectiveTracker*-prefixed objects, so the world-map quest log (QuestFont*) stays untouched.
    -- Skipped under the module's stock styles, which keep Blizzard's own tracker text.
    local qtNS = EllesmereUI._ModuleNS and EllesmereUI._ModuleNS.EllesmereUIQuestTracker
    local qtStock = qtNS and qtNS.QT_Style and qtNS.QT_Style() ~= "eui"
    if IsLoaded("EllesmereUIQuestTracker") and not qtStock then
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
        flag = (EllesmereUI.GetFontOutlineFlag(moduleKey)) or ""
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

-- Body text in a module's font: fontPath/flags default to the module's (nil key = global)
-- font and outline; a "" flag (Drop Shadow/None) gets the drop shadow.
function EllesmereUI.ApplyModuleFont(fs, fontPath, size, moduleKey, flags)
    if not (fs and fs.SetFont) then return end
    flags = flags or EllesmereUI.GetFontOutlineFlag(moduleKey)
    EllesmereUI.PrimeFontShadow(fs, flags == "")
    fs:SetFont(fontPath or EllesmereUI.GetFontPath(moduleKey), size, flags)
end

-- ApplyModuleFont for a text that can show other players' writing: the same defaults
-- (the module's font and outline; a "" flag gets the drop shadow) as a font family
-- (SetFontFamily). Once a string has a family, no ApplyModuleFont may reach it.
function EllesmereUI.ApplyModuleFontFamily(fs, fontPath, size, moduleKey, flags)
    if not (fs and fs.SetFont) then return end
    flags = flags or EllesmereUI.GetFontOutlineFlag(moduleKey)
    EllesmereUI.SetFontFamily(fs, fontPath or EllesmereUI.GetFontPath(moduleKey), size, flags, flags == "")
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
                         font = EllesmereUI.GetBlizzardFontPath() } }
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
