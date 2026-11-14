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
--  Number Format (per profile): a global Unit Style and Letter Case, plus a
--  Precision and an abbreviation threshold per value type (health, max health,
--  absorb, boss health, meter). Precision "standard" is each consumer's own
--  pre-existing table, so an untouched profile reads exactly as before.
--  Everything here is a breakpoint table handed to the C function, never Lua
--  math on the value, so secret health and meter values stay secret-safe.
--
--  WoW Forever's numbers are small, so nothing below 10,000 abbreviates there by
--  default (9999 stays "9999", 10123 reads "10.1K"). TrimTiers does that cut,
--  and EllesmereUI.ForeverAbbreviateNumbers hands the same trimmed tiers to
--  modules that call the client function directly.
--
--  AbbreviateNumber() runs on every combat-meter refresh, often many
--  times a second across a raid frame's worth of bars, so it's written as a hot
--  path: client API localized to upvalues, and each value type's resolved config
--  cached until RefreshNumberFormat() (settings change, profile switch).
--  eui-style: allow comment-budget (file header below the client gate)
--------------------------------------------------------------------------------
EllesmereUI = EllesmereUI or {}
local EllesmereUI = EllesmereUI

local tonumber = tonumber
local wipe = wipe
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
-- session, since the resolved config is cached below. It shapes Precision
-- "standard" only; the other precisions build from CJK_GLYPHS or K/M/B.
function EllesmereUI.RegisterNumberAbbreviation(localeCode, builderFn)
    localeBuilders[localeCode] = builderFn
end

-- EllesmereUI.LocaleHasNumberAbbreviation(localeCode) -> boolean
--   True when localeCode (default: the current effective locale) has its own
--   algorithm -- i.e. a "Western K/M/B" Unit Style would actually change
--   something for it. Lets callers (options pages) gate that choice without
--   hardcoding which locales happen to have one.
function EllesmereUI.LocaleHasNumberAbbreviation(localeCode)
    localeCode = localeCode or EllesmereUI.LOCALE
    return localeBuilders[localeCode] ~= nil
end

-- rows (largest first) -> a new list without the tiers below threshold, bar the
-- plain one (breakpoint 1 or 0). When nothing then starts AT threshold, the
-- largest dropped tier moves up to start there, keeping its divisors: at 10,000
-- the English K tier still reads 12345 as "12.3K", while the CJK thousands tier
-- just goes (the wan tier already starts at 10,000). A moved row is edited in
-- place, so pass freshly built rows.
local function TrimTiers(rows, threshold)
    local out = {}
    for i = 1, #rows do
        local row = rows[i]
        local bp = row.breakpoint
        if bp >= threshold or bp <= 1 then
            out[#out + 1] = row
        elseif not out[1] or out[#out].breakpoint > threshold then
            row.breakpoint = threshold
            out[#out + 1] = row
        end
    end
    return out
end

-- Precision "standard" on WoW Forever keeps its 10,000 cut; nil elsewhere.
local STANDARD_THRESHOLD = EllesmereUI.IS_FOREVER and 10000 or nil
local DEFAULT_THRESHOLD = EllesmereUI.IS_FOREVER and 10000 or 1000

local function NewConfig(rows, threshold)
    if threshold then rows = TrimTiers(rows, threshold) end
    return { config = CreateAbbreviateConfig(rows) }
end

-- Precision "standard" configs, built at most once per session -- plain
-- upvalues rather than a table keyed by locale, so a warm call is a truthiness
-- check away from returning instead of a hash lookup.
local cfgLocalized, cfgEnglish

local function BuildConfig(forceEnglish)
    if forceEnglish then
        cfgEnglish = cfgEnglish or NewConfig(EnglishBreakpoints(), STANDARD_THRESHOLD)
        return cfgEnglish
    end
    if not cfgLocalized then
        local builder = localeBuilders[EllesmereUI.LOCALE]
        local opts = builder and builder() or EnglishBreakpoints()
        cfgLocalized = NewConfig(opts, STANDARD_THRESHOLD)
    end
    return cfgLocalized
end

--------------------------------------------------------------------------------
--  Number Format settings
--------------------------------------------------------------------------------
-- Value types, in options-page order. "bossHealth" covers current and max
-- health on Unit Frames' boss frames; "meter" covers Damage Meters and the
-- Mythic+ run summary.
EllesmereUI.NUMBER_FORMAT_TYPES = { "health", "maxHealth", "absorb", "bossHealth", "meter" }

local VALID_PRECISION = { standard = true, smart = true, [0] = true, [1] = true, [2] = true }
local VALID_THRESHOLD = { [1000] = true, [10000] = true, [100000] = true }

-- The active profile table, read only; nil until the saved variables and the
-- active profile exist.
local function ActiveProfile()
    local db = EllesmereUIDB
    local profiles = db and db.profiles
    return profiles and profiles[db.activeProfile or "Default"]
end

-- EllesmereUI.GetNumberFormatDB(create) -> table | nil
--   The active profile's number-format table, possibly sparse (missing fields
--   mean the defaults). Readers pass nothing and get nil while it is unset;
--   writers pass create = true. nil until the active profile exists either way,
--   so an early call never seeds a throwaway DB.
--   Shape: { units = "auto"|"western", case = "upper"|"lower",
--            types = { [valueType] = { precision = "standard"|"smart"|0|1|2,
--                                      threshold = 1000|10000|100000 } } }
function EllesmereUI.GetNumberFormatDB(create)
    local active = ActiveProfile()
    if not active then return nil end
    if create and not active.numberFormat then active.numberFormat = {} end
    return active.numberFormat
end

-- nf -> glyphs (CJK units in use) | nil (K/M/B), western
local function ActiveUnits(nf)
    -- Western only means something on a locale with its own algorithm.
    local western = nf ~= nil and nf.units == "western" and localeBuilders[EllesmereUI.LOCALE] ~= nil
    return (not western and CJK_GLYPHS[EllesmereUI.LOCALE]) or nil, western
end

-- EllesmereUI.NumberFormatUsesGlyphs() -> boolean
--   True when the active profile shows CJK units, which have no letter case.
function EllesmereUI.NumberFormatUsesGlyphs()
    local active = ActiveProfile()
    return ActiveUnits(active and active.numberFormat) ~= nil
end

-- nf, valueType -> precision, threshold (stored values validated, else the defaults)
local function TypeSettings(nf, valueType)
    local t = nf and nf.types and nf.types[valueType]
    local precision = t and t.precision
    if not VALID_PRECISION[precision] then precision = "standard" end
    local threshold = t and t.threshold
    if not VALID_THRESHOLD[threshold] then threshold = DEFAULT_THRESHOLD end
    return precision, threshold
end

-- EllesmereUI.NumberFormatTypeSettings(valueType) -> precision, threshold
--   What the engine applies for valueType under the active profile.
function EllesmereUI.NumberFormatTypeSettings(valueType)
    local active = ActiveProfile()
    return TypeSettings(active and active.numberFormat, valueType)
end

-- Unit bases, largest first: { base, upper, lower }.
local WESTERN_UNITS = {
    { 1000000000, "B", "b" },
    { 1000000,    "M", "m" },
    { 1000,       "K", "k" },
}

-- precision "smart" | 0 | 1 | 2, glyphs (CJK) or nil (K/M/B) -> rows, largest first.
-- "smart" keeps three significant digits with one row per digit count inside
-- each unit (1.23M / 12.3M / 123M); a unit's rows stop below the next unit up.
local function BuildRows(precision, glyphs, lower)
    local units
    if glyphs then
        units = { { 100000000, glyphs[3] }, { 10000, glyphs[2] }, { 1000, glyphs[1] } }
    else
        units = WESTERN_UNITS
    end
    local rows = {}
    for i = 1, #units do
        local base = units[i][1]
        local abbr = (lower and units[i][3]) or units[i][2]
        local cap = i > 1 and units[i - 1][1] or nil
        if precision == "smart" then
            for k = 2, 0, -1 do
                local bp = base * 10 ^ k
                if not cap or bp < cap then
                    local d = 10 ^ (2 - k)
                    rows[#rows + 1] = { breakpoint = bp, abbreviation = abbr, significandDivisor = base / d, fractionDivisor = d, abbreviationIsGlobal = false }
                end
            end
        else
            local d = 10 ^ precision
            rows[#rows + 1] = { breakpoint = base, abbreviation = abbr, significandDivisor = base / d, fractionDivisor = d, abbreviationIsGlobal = false }
        end
    end
    rows[#rows + 1] = { breakpoint = 1, abbreviation = "", significandDivisor = 1, fractionDivisor = 1, abbreviationIsGlobal = false }
    return rows
end

-- The effective settings as one string, so a profile switch that keeps the same
-- format skips the module repaints (the switch repaints them anyway). The first
-- value drawn records the format it was drawn in (NumberFormatOptions).
local TYPES = EllesmereUI.NUMBER_FORMAT_TYPES
local lastSignature
local function Signature()
    local active = ActiveProfile()
    local nf = active and active.numberFormat
    local _, western = ActiveUnits(nf)
    local parts = { western and "w" or "a", (nf and nf.case == "lower") and "l" or "u" }
    for i = 1, #TYPES do
        local precision, threshold = TypeSettings(nf, TYPES[i])
        parts[#parts + 1] = precision .. "," .. threshold
    end
    return table.concat(parts, ";")
end

-- Resolved opts per value type (false = "use the caller's own default"), wiped
-- by RefreshNumberFormat; optsByTypeW holds the forceWestern variants.
-- cfgBySpec shares one config between identical specs; the locale is fixed per
-- session, so it never needs wiping.
local optsByType = {}
local optsByTypeW = {}
local cfgBySpec = {}

-- valueType, forceWestern -> opts | false, cacheable (false before the active
-- profile exists). forceWestern: a module's own K/M/B override (Damage Meters'
-- Force English Units) over the Unit Style; Precision and threshold stay, the
-- case only where the Unit Style lets the user set it (else upper, as on CJK).
local function ResolveOptions(valueType, forceWestern)
    local active = ActiveProfile()
    local nf = active and active.numberFormat
    local precision, threshold = TypeSettings(nf, valueType)
    local glyphs, western = ActiveUnits(nf)
    local lower = nf ~= nil and nf.case == "lower" and not glyphs
    if forceWestern then glyphs, western = nil, true end

    if precision == "standard" then
        if western then return BuildConfig(true), active ~= nil end
        if valueType == "meter" then return BuildConfig(false), active ~= nil end
        return false, active ~= nil
    end

    local key = (glyphs and EllesmereUI.LOCALE or "en") .. ":" .. precision .. ":" .. threshold .. (lower and ":l" or ":u")
    local cfg = cfgBySpec[key]
    if not cfg then
        cfg = NewConfig(BuildRows(precision, glyphs, lower), threshold)
        cfgBySpec[key] = cfg
    end
    return cfg, true
end

-- The "meter" opts again as plain upvalues: AbbreviateNumber's warm path.
local meterOpts, meterOptsW

-- EllesmereUI.NumberFormatOptions(valueType, forceWestern) -> opts | nil
--   The AbbreviateNumbers options for valueType under the active profile's
--   Number Format. nil means Precision "standard" on a type whose consumer keeps
--   its own default call (plain AbbreviateNumbers, or ForeverAbbreviateNumbers);
--   "meter" always returns a config. forceWestern: K/M/B whatever the Unit Style.
function EllesmereUI.NumberFormatOptions(valueType, forceWestern)
    local cache = forceWestern and optsByTypeW or optsByType
    local o = cache[valueType]
    if o == nil then
        local cacheable
        o, cacheable = ResolveOptions(valueType, forceWestern)
        if not lastSignature then lastSignature = Signature() end
        if cacheable then
            cache[valueType] = o
            if valueType == "meter" then
                if forceWestern then meterOptsW = o else meterOpts = o end
            end
        end
    end
    return o or nil
end
local NumberFormatOptions = EllesmereUI.NumberFormatOptions

-- EllesmereUI.RegisterNumberFormatCallback(fn)
--   fn() runs after every RefreshNumberFormat, for modules to redraw their text.
local refreshCallbacks = {}
function EllesmereUI.RegisterNumberFormatCallback(fn)
    refreshCallbacks[#refreshCallbacks + 1] = fn
end

-- EllesmereUI.RefreshNumberFormat()
--   Drops the resolved per-type options (after a settings change or a profile
--   switch) and, when the effective format changed, notifies the registered
--   modules. Before any value is drawn there is nothing to redraw (the
--   spec-assigned profile is switched in before the modules enable). It runs
--   inside the profile switch, so one failing callback is reported without
--   stopping the rest.
function EllesmereUI.RefreshNumberFormat()
    wipe(optsByType)
    wipe(optsByTypeW)
    meterOpts, meterOptsW = nil, nil
    local signature = Signature()
    if signature == lastSignature then return end
    local drawn = lastSignature ~= nil
    lastSignature = signature
    if not drawn then return end
    local handler = geterrorhandler()
    for i = 1, #refreshCallbacks do xpcall(refreshCallbacks[i], handler) end
end

-- EllesmereUI.ResetNumberFormat()
--   The active profile back to the default Number Format, then redrawn.
function EllesmereUI.ResetNumberFormat()
    local active = ActiveProfile()
    if active then active.numberFormat = nil end
    EllesmereUI.RefreshNumberFormat()
end

-- EllesmereUI.AbbreviateNumber(n, forceWestern) -> string
--   Formats n as the "meter" value type (Damage Meters, Mythic+ summary).
--   forceWestern: K/M/B whatever the Unit Style (Damage Meters' Force English
--   Units); with Precision "standard" that is the old fixed English table.
function EllesmereUI.AbbreviateNumber(n, forceWestern)
    if forceWestern then
        return AbbreviateNumbers(tonumber(n) or 0, meterOptsW or NumberFormatOptions("meter", true))
    end
    return AbbreviateNumbers(tonumber(n) or 0, meterOpts or NumberFormatOptions("meter"))
end

-- EllesmereUI.AbbreviateValue(v, valueType) -> string
--   v as valueType under the Number Format (health, max health, absorb and boss
--   health text). Precision "standard" keeps the default call: the client's own
--   format, on WoW Forever this file's table with its 10,000 cut. v goes straight
--   to the C function, so a secret value stays secret-safe.
local IS_FOREVER = EllesmereUI.IS_FOREVER
function EllesmereUI.AbbreviateValue(v, valueType)
    local opts = NumberFormatOptions(valueType)
    if opts then return AbbreviateNumbers(v, opts) end
    if IS_FOREVER then return AbbreviateNumbers(v, BuildConfig(false)) end
    return AbbreviateNumbers(v)
end

-- EllesmereUI.IsZeroValue(v) -> bool
--   True for a whole-number amount of 0, secret ones too: a probe FontString's
--   GetText is nil after TruncateWhenZero (as ns.FormatHealAbsorbInto, Raid Frames).
--   For a secret amount that text is a secret string, so it is only tested for
--   truth, never compared with a value (that raises).
--   The probe sits on its own hidden, parentless frame, outside Blizzard's tree.
do
    local probe
    function EllesmereUI.IsZeroValue(v)
        if not issecretvalue(v) then return v == 0 end
        if not probe then
            local holder = CreateFrame("Frame")
            holder:Hide()
            probe = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        probe:SetText(C_StringUtil.TruncateWhenZero(v))
        return not probe:GetText()
    end
end

-- EllesmereUI.AbbreviateNumberFixed(n, forceEnglish) -> string
--   The fixed Precision "standard" table, outside the Number Format (gold
--   blocks, which keep their own K/M/B toggle). forceEnglish: true always
--   uses K/M/B, else the client's own units.
function EllesmereUI.AbbreviateNumberFixed(n, forceEnglish)
    return AbbreviateNumbers(tonumber(n) or 0, BuildConfig(forceEnglish))
end

--------------------------------------------------------------------------------
--  WoW Forever only: helpers for modules that call the client function directly.
--------------------------------------------------------------------------------
if EllesmereUI.IS_FOREVER then
    -- For a module's own breakpoint table (Unit Frames' decimal bands).
    EllesmereUI.ForeverAbbrevTiers = function(rows)
        return TrimTiers(rows, 10000)
    end

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
