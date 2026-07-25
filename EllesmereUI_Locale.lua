--------------------------------------------------------------------------------
--  EllesmereUI_Locale.lua
--  Central multi-language engine for the EllesmereUI options panel, unlock mode,
--  and custom popups/tooltips. Short in-game STATUS text is also in scope where a
--  locale provides it (raid frame DEAD/OFFLINE/AFK, nameplate "Interrupted",
--  auto-repair chat feedback) -- untranslated keys fall back to English silently.
--
--  Design: "translate the pixels, never the data." Translation is applied at the
--  render boundary (the :SetText call) inside the shared widget builders, so the
--  English identity fields used for search, page dispatch, and unlock-mode routing
--  keep byte-matching English for free. This file owns only the primitives.
--
--  TIMING: SavedVariables (EllesmereUIDB, which holds the manual language override)
--  are NOT available at file-scope -- they load at ADDON_LOADED. So locale files
--  populate their data unconditionally at load, and the engine resolves the
--  EFFECTIVE locale (client locale + override) and activates the matching catalog
--  at ADDON_LOADED. The options panel renders much later, so this is always in time.
--
--  Zero rendering impact on English: when the effective locale is enUS/enGB,
--  the active catalog is nil and L/Lf/EnKey return the input unchanged, so every
--  :SetText receives byte-identical text. (Locale tables still load into memory,
--  but they are never read on an English client.)
--------------------------------------------------------------------------------
local ADDON_NAME = ...

EllesmereUI = EllesmereUI or {}
local EllesmereUI = EllesmereUI

local type, tonumber, pairs, select = type, tonumber, pairs, select
local GetLocale = GetLocale
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame

local SUPPORTED = {
    enUS = true, deDE = true, esES = true, esMX = true, frFR = true,
    itIT = true, ptBR = true, ruRU = true, koKR = true, zhCN = true, zhTW = true,
}

-- Per-locale translation tables, keyed by locale code. Filled at load by the
-- Locales/<code>.lua files via RegisterLocale(). The active one is selected later.
local localeData = {}

-- The currently active translation table (nil = English / identity), and the
-- reverse (translation -> English) map used by EnKey. Both are (re)assigned by
-- Activate(); L/EnKey close over these upvalues so they always see the latest.
local activeCatalog = nil
local reverse = {}

--------------------------------------------------------------------------------
--  Translation API
--------------------------------------------------------------------------------

-- The translator. Identity when no catalog is active (English, or before the
-- catalog is resolved). Otherwise looks up the English key; guards short-circuit
-- anything that must never be translated (non-strings, empty, secret combat
-- values, pure numbers, letterless strings like hex/coords) before the lookup.
local function L(s)
    local cat = activeCatalog
    if not cat then return s end
    if type(s) ~= "string" or s == "" then return s end
    if issecretvalue and issecretvalue(s) then return s end
    if tonumber(s) ~= nil then return s end
    if not s:find("%a") then return s end
    local v = cat[s]
    if type(v) == "string" then return v end
    return s   -- untranslated key -> silent English fallback
end
EllesmereUI.L = L

-- Format helper for the hard-case long tail. Uses WoW positional %1$s / %2$d
-- specifiers so translators can reorder placeholders for other word orders.
EllesmereUI.Lf = function(s, ...)
    local t = L(s)
    if type(t) ~= "string" or select("#", ...) == 0 then return t end
    return t:format(...)
end

-- Reverse-map identity primitive. Where code reads a rendered FontString back
-- and compares it to an English literal, EnKey maps the on-screen translation
-- back to English so the comparison still matches. Identity on English.
EllesmereUI.EnKey = function(s)
    if type(s) ~= "string" then return s end
    return reverse[s] or s
end

-- Entry point every Locales/<code>.lua file calls. Returns the per-locale table
-- to populate. Files load before the override is known, so EVERY locale file
-- populates its own table; the engine selects the active one at ADDON_LOADED.
EllesmereUI.RegisterLocale = function(code)
    local t = localeData[code]
    if not t then t = {}; localeData[code] = t end
    return t
end

--------------------------------------------------------------------------------
--  Resolve + activate the effective locale
--------------------------------------------------------------------------------
local function GlyphFont(locale)
    -- Simplified Chinese and Traditional Chinese use different system fonts:
    -- zhCN renders with the Simplified glyph set (ARKai_T), zhTW with the
    -- Traditional glyph set (bLEI00D). Routing zhTW to ARKai_T would show
    -- Simplified glyph forms to a Traditional reader, so keep them separate.
    if locale == "zhCN" then return "Fonts\\ARKai_T.ttf"
    elseif locale == "zhTW" then return "Fonts\\bLEI00D.ttf"
    elseif locale == "koKR" then return "Fonts\\2002.TTF"
    elseif locale == "ruRU" then return "Fonts\\FRIZQT___CYR.TTF" end
    return nil
end

local function Activate()
    local client = GetLocale()
    if client == "enGB" then client = "enUS" end
    if not SUPPORTED[client] then client = "enUS" end

    -- Manual override (global saved var; nil/unavailable falls back to client).
    local override = EllesmereUIDB and EllesmereUIDB.displayLocale
    if override == "auto" or not SUPPORTED[override or ""] then override = nil end

    local locale = override or client
    EllesmereUI.LOCALE     = locale
    EllesmereUI.IS_ENGLISH = (locale == "enUS")
    EllesmereUI._localeFont = GlyphFont(locale)

    reverse = {}
    if locale == "enUS" then
        activeCatalog = nil
    else
        local src = localeData[locale]
        if src then
            -- Resolve the "= true" keep-English sentinel and build the reverse map.
            for k, v in pairs(src) do
                if v == true then src[k] = k; v = k end
                if type(v) == "string" then reverse[v] = k end
            end
        end
        activeCatalog = src   -- nil if no locale file shipped for this code
    end
end

-- Preliminary pass at file-load: SavedVariables are not loaded yet, so this
-- resolves the CLIENT locale only and sets the glyph font for EllesmereUI.lua
-- (which reads EllesmereUI._localeFont at its own file-load). The active catalog
-- is filled at ADDON_LOADED below, once the locale files have populated and the
-- override is readable.
Activate()

-- Re-resolve once SavedVariables (the override) are available and every locale
-- file has populated. Nothing renders before this point.
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, loaded)
    if loaded == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        Activate()
    end
end)
