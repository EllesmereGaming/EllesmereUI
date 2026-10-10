if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Fonts.lua
--  Font tables and LSM registration, font resolution cache and per-module
--  getters, outline/slug/shadow helpers, game-text font. Loads after EllesmereUI_Colors.lua.
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
