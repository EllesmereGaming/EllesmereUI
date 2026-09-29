if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_NumberFormat.lua
--  Central "abbreviate a big number to K/M/B/etc." engine, shared by every module
--  that squeezes a large number into a small space (Gold in EllesmereUIDataBars,
--  damage/healing in EllesmereUIDamageMeters, ...). Delegates to the client's own
--  AbbreviateNumbers/CreateAbbreviateConfig -- present on every client build this
--  addon supports (EUI_CLIENT_BLOCKED gates out anything older); this file only
--  supplies the breakpoint tables.
--
--  The CJK grouping tables (ten-thousands / hundred-millions instead of K/M/B,
--  with a thousands tier below) live HERE, keyed by locale, rather than inside
--  the EllesmereUILocales files: the standalone builds ship no locale files at
--  all, and a CJK client on one of those must keep the same grouping as the
--  suite. RegisterNumberAbbreviation stays the public hook for a locale to add
--  or override its algorithm.
--
--  WoW Forever's numbers are small, so nothing below 10,000 abbreviates there
--  (9999 stays "9999", 10123 reads "10.1K"). The block at the end of this file
--  trims every table here, and EllesmereUI.ForeverAbbreviateNumbers hands the
--  same trimmed tiers to modules that call the client function directly.
--
--  AbbreviateNumber() runs on every combat-meter and gold-bar refresh, often many
--  times a second across a raid frame's worth of bars, so it's written as a hot
--  path: client API localized to upvalues, and the resolved AbbreviateConfig built
--  at most once per session (EllesmereUI.LOCALE cannot change without a UI reload,
--  per EUI__General_Options.lua's language picker, so there is nothing to
--  invalidate).
--------------------------------------------------------------------------------
EllesmereUI = EllesmereUI or {}
local EllesmereUI = EllesmereUI

local tonumber = tonumber
local AbbreviateNumbers = AbbreviateNumbers
local CreateAbbreviateConfig = CreateAbbreviateConfig

-- English/default breakpoint table -- there's no locale-agnostic "generic"
-- abbreviation, K/M/B is just what English (and every locale without its own
-- entry below) uses. One table fits every caller: an unreached breakpoint
-- (e.g. the B tier on gold, capped at 99,999,999) simply never matches, so
-- there's no need for a caller-specific variant.
local function EnglishBreakpoints()
    return {
        { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1000000,    abbreviation = "M", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1000,       abbreviation = "K", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
        { breakpoint = 1,          abbreviation = "",  significandDivisor = 1,        fractionDivisor = 1,   abbreviationIsGlobal = false },
    }
end

-- East Asian clients group large numbers by ten-thousands (wan) and
-- hundred-millions (yi), with a thousands tier below. Simplified and Traditional
-- Chinese share the math, only the glyphs differ. Glyph order per locale:
-- thousand, wan, yi.
local CJK_GLYPHS = {
    zhCN = { "千", "万", "亿" },
    zhTW = { "千", "萬", "億" },
    koKR = { "천", "만", "억" },
}

local function CJKBreakpoints(g)
    return {
        { breakpoint = 100000000, abbreviation = g[3], significandDivisor = 1000000, fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 10000,     abbreviation = g[2], significandDivisor = 100,     fractionDivisor = 100, abbreviationIsGlobal = false },
        { breakpoint = 1000,      abbreviation = g[1], significandDivisor = 100,     fractionDivisor = 10,  abbreviationIsGlobal = false },
        { breakpoint = 1,         abbreviation = "",   significandDivisor = 1,       fractionDivisor = 1,   abbreviationIsGlobal = false },
    }
end

-- EllesmereUI.NumberAbbrevGlyphs(localeCode) -> { thousand, wan, yi } | nil
--   The ten-thousand-grouping glyphs for localeCode (default: the current effective
--   locale), nil for K/M/B locales. For modules that build their own breakpoint
--   table (a fixed decimal count, say) but must show the same units as this engine.
function EllesmereUI.NumberAbbrevGlyphs(localeCode)
    return CJK_GLYPHS[localeCode or EllesmereUI.LOCALE]
end

-- Locale-specific algorithms: [localeCode] -> breakpoint-table builder.
local localeBuilders = {
    zhCN = function() return CJKBreakpoints(CJK_GLYPHS.zhCN) end,
    zhTW = function() return CJKBreakpoints(CJK_GLYPHS.zhTW) end,
    koKR = function() return CJKBreakpoints(CJK_GLYPHS.koKR) end,
}

-- A locale may add or replace its algorithm (e.g. from its EllesmereUILocales
-- file). Only takes effect before the first AbbreviateNumber() call of the
-- session, since the resolved config is cached below.
function EllesmereUI.RegisterNumberAbbreviation(localeCode, builderFn)
    localeBuilders[localeCode] = builderFn
end

-- EllesmereUI.LocaleHasNumberAbbreviation(localeCode) -> boolean
--   True when localeCode (default: the current effective locale) has its own
--   algorithm -- i.e. a "Force English Units" toggle would actually change
--   something for it. Lets callers (options pages) gate that toggle without
--   hardcoding which locales happen to have one.
function EllesmereUI.LocaleHasNumberAbbreviation(localeCode)
    localeCode = localeCode or EllesmereUI.LOCALE
    return localeBuilders[localeCode] ~= nil
end

-- Resolved AbbreviateConfig objects, built at most once and reused for the rest
-- of the session -- plain upvalues rather than a table keyed by locale, so a
-- warm call is a truthiness check away from returning instead of a hash lookup.
local cfgLocalized, cfgEnglish

-- WoW Forever's tier trim, set by the block at the end of this file (nil on
-- every other client, whose tables reach the client untouched).
local ForeverTiers

local function NewConfig(rows)
    if ForeverTiers then rows = ForeverTiers(rows) end
    return { config = CreateAbbreviateConfig(rows) }
end

local function BuildConfig(forceEnglish)
    if forceEnglish then
        cfgEnglish = cfgEnglish or NewConfig(EnglishBreakpoints())
        return cfgEnglish
    end
    if not cfgLocalized then
        local builder = localeBuilders[EllesmereUI.LOCALE]
        local opts = builder and builder() or EnglishBreakpoints()
        cfgLocalized = NewConfig(opts)
    end
    return cfgLocalized
end

-- EllesmereUI.AbbreviateNumber(n, forceEnglish) -> string
--   forceEnglish: true skips any locale-specific algorithm and always uses
--   K/M/B (e.g. DamageMeters' "force English units" setting).
function EllesmereUI.AbbreviateNumber(n, forceEnglish)
    return AbbreviateNumbers(tonumber(n) or 0, BuildConfig(forceEnglish))
end

--------------------------------------------------------------------------------
--  WoW Forever only: no tier below 10,000.
--------------------------------------------------------------------------------
if EllesmereUI.IS_FOREVER then
    -- rows (largest first) -> a new list without the tiers below 10,000, bar the
    -- plain one (breakpoint 1 or 0). When nothing then starts AT 10,000, the
    -- largest dropped tier moves up to start there, keeping its divisors: the
    -- English K tier still reads 12345 as "12.3K", while the CJK thousands tier
    -- just goes (the wan tier already starts at 10,000). A moved row is edited
    -- in place, so pass freshly built rows.
    ForeverTiers = function(rows)
        local out = {}
        for i = 1, #rows do
            local row = rows[i]
            local bp = row.breakpoint
            if bp >= 10000 or bp <= 1 then
                out[#out + 1] = row
            elseif not out[1] or out[#out].breakpoint > 10000 then
                row.breakpoint = 10000
                out[#out + 1] = row
            end
        end
        return out
    end
    -- For a module's own breakpoint table (Unit Frames' decimal bands).
    EllesmereUI.ForeverAbbrevTiers = ForeverTiers

    -- EllesmereUI.ForeverAbbreviateNumbers(n, opts) / ForeverAbbreviateLargeNumbers(n, opts)
    --   The client's AbbreviateNumbers / AbbreviateLargeNumbers for modules that
    --   call it directly (health, power, absorb and XP text), on this file's own
    --   trimmed tiers so every Forever number reads alike (9999, then 10.1K); a
    --   caller's own opts pass through as they are. n goes straight to the C
    --   function, so a secret value stays secret-safe.
    local AbbreviateLargeNumbers = AbbreviateLargeNumbers

    function EllesmereUI.ForeverAbbreviateNumbers(n, opts)
        return AbbreviateNumbers(n, opts or BuildConfig(false))
    end

    function EllesmereUI.ForeverAbbreviateLargeNumbers(n, opts)
        return AbbreviateLargeNumbers(n, opts or BuildConfig(false))
    end
end
