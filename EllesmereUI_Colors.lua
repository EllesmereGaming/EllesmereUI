if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Colors.lua
--  Class, power and resource colour defaults, the custom-colour cache and
--  getters, Dark Mode palette and toggles. Loads right after EllesmereUI_Popups.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI

local CLASS_COLOR_MAP = EllesmereUI.CLASS_COLOR_MAP

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
-- PROFILE (db.profiles[name].customColors: class / power / classResource / resource).
-- Each colour SECTION of the Colors page picks its own palette source (class, power,
-- classResource; resource rides classResource):
--   "Apply to All Profiles" ON (default): ONE chosen profile's section (its "Pull
--        Colors From", default the first profile) shared across EVERY profile.
--   OFF (per-profile): the ACTIVE profile's own section.
-- The per-section keys (EllesmereUIDB.colorsSectionApplyAll / colorsSectionPullFrom,
-- keyed by section) are account-wide like the original pair (colorsApplyToAllProfiles
-- / colorsPullFrom), which a section with no key of its own still reads -- an account
-- from before the split resolves exactly as it did, nothing migrated.
-- Nothing is wiped/restored on a profile switch (the getter just resolves different
-- tables), so a spec-switch colour wipe cannot happen. Missing tables -> defaults.
EllesmereUI.COLOR_SECTIONS = { "class", "power", "classResource" }
EllesmereUI._COLOR_SECTION_OF = { class = "class", power = "power",
    classResource = "classResource", resource = "classResource" }
-- The palette GetCustomColorsDB hands out: its four category fields are the LIVE
-- tables of each section's source profile, so in-place writes (db.class[token] = c)
-- land where the section resolves and a DeepCopy of it is the effective palette.
-- One reused table, refreshed every call; callers never keep it.
EllesmereUI._ccComposite = {}

function EllesmereUI.ColorSectionApplyAll(section)
    local db = EllesmereUIDB
    local own = db and db.colorsSectionApplyAll and db.colorsSectionApplyAll[section]
    if own ~= nil then return own end
    return not (db and db.colorsApplyToAllProfiles == false)
end

-- The NAME of the profile a section pulls from in global mode. Dangling pointers
-- (a profile removed by a path that missed the DeleteProfile/RenameProfile cleanup,
-- or a DB saved before that cleanup existed) are dropped, so the section falls back
-- to the shared pointer, then the first profile, instead of the legacy table.
function EllesmereUI.ColorSectionPullFrom(section)
    local db = EllesmereUIDB
    if not (db and EllesmereUI.GetProfilesDB) then return nil end
    local pdb = EllesmereUI.GetProfilesDB()
    local profiles = pdb.profiles
    local t = db.colorsSectionPullFrom
    local own = t and t[section]
    if own and not (profiles and profiles[own]) then t[section] = nil; own = nil end
    local shared = db.colorsPullFrom
    if shared and not (profiles and profiles[shared]) then db.colorsPullFrom = nil; shared = nil end
    return own or shared or (pdb.profileOrder and pdb.profileOrder[1])
end

function EllesmereUI.SetColorSectionApplyAll(section, on)
    if not EllesmereUIDB then return end
    EllesmereUIDB.colorsSectionApplyAll = EllesmereUIDB.colorsSectionApplyAll or {}
    EllesmereUIDB.colorsSectionApplyAll[section] = on and true or false
end

function EllesmereUI.SetColorSectionPullFrom(section, name)
    if not EllesmereUIDB then return end
    EllesmereUIDB.colorsSectionPullFrom = EllesmereUIDB.colorsSectionPullFrom or {}
    EllesmereUIDB.colorsSectionPullFrom[section] = name
end

-- True while any section reads the active profile's own colours (a profile switch
-- then changes what renders).
function EllesmereUI.AnyColorSectionPerProfile()
    for _, s in ipairs(EllesmereUI.COLOR_SECTIONS) do
        if not EllesmereUI.ColorSectionApplyAll(s) then return true end
    end
    return false
end

-- Point every global-mode section at profile `name` (an import that carries colours
-- shows them): its own pointer when it has one, else the shared pointer it reads.
-- Per-profile sections already read the active profile.
function EllesmereUI.PointColorSectionsAt(name)
    if not EllesmereUIDB then return end
    local t = EllesmereUIDB.colorsSectionPullFrom
    local sharedUsed = false
    for _, s in ipairs(EllesmereUI.COLOR_SECTIONS) do
        if EllesmereUI.ColorSectionApplyAll(s) then
            if t and t[s] ~= nil then t[s] = name else sharedUsed = true end
        end
    end
    if sharedUsed then EllesmereUIDB.colorsPullFrom = name end
end

-- A deleted profile drops out of every source pointer (nil = the default); returns
-- true when one pointed at it. A renamed profile is followed (same palette tables).
function EllesmereUI.ColorSourcesProfileRemoved(name)
    if not EllesmereUIDB then return false end
    local hit = false
    if EllesmereUIDB.colorsPullFrom == name then EllesmereUIDB.colorsPullFrom = nil; hit = true end
    local t = EllesmereUIDB.colorsSectionPullFrom
    if t then
        for s, n in pairs(t) do
            if n == name then t[s] = nil; hit = true end
        end
    end
    return hit
end
function EllesmereUI.ColorSourcesProfileRenamed(oldName, newName)
    if not EllesmereUIDB then return end
    if EllesmereUIDB.colorsPullFrom == oldName then EllesmereUIDB.colorsPullFrom = newName end
    local t = EllesmereUIDB.colorsSectionPullFrom
    if t then
        for s, n in pairs(t) do
            if n == oldName then t[s] = newName end
        end
    end
end

-- The profile whose customColors feed `section` (nil without profiles).
function EllesmereUI._ColorSectionProfile(section)
    if not EllesmereUI.GetProfilesDB then return nil end
    local pdb = EllesmereUI.GetProfilesDB()
    local name
    if EllesmereUI.ColorSectionApplyAll(section) then
        name = EllesmereUI.ColorSectionPullFrom(section)
    else
        name = pdb.activeProfile or "Default"
    end
    return name and pdb.profiles and pdb.profiles[name]
end

function EllesmereUI.GetCustomColorsDB()
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.customColors then EllesmereUIDB.customColors = {} end
    local out = EllesmereUI._ccComposite
    for key, section in pairs(EllesmereUI._COLOR_SECTION_OF) do
        local prof = EllesmereUI._ColorSectionProfile(section)
        local cc
        if prof then
            prof.customColors = prof.customColors or {}
            cc = prof.customColors
        else
            cc = EllesmereUIDB.customColors
        end
        local cat = cc[key]
        if type(cat) ~= "table" then cat = {}; cc[key] = cat end
        out[key] = cat
    end
    return out
end

-- A section's colour editing locks ONLY in global mode while viewing a profile other
-- than its source (editing a dormant palette would mislead). Per-profile mode is always
-- editable; global mode is editable on the source profile. No section = Class.
function EllesmereUI.IsColorEditingLocked(section)
    section = section or "class"
    if not (EllesmereUIDB and EllesmereUI.GetProfilesDB) then return false end
    if not EllesmereUI.ColorSectionApplyAll(section) then return false end
    local pdb = EllesmereUI.GetProfilesDB()
    local src = EllesmereUI.ColorSectionPullFrom(section)
    return src ~= nil and src ~= (pdb.activeProfile or "Default")
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

-- Materialized Dark Mode palette. The fill and background quadruples are read on
-- every raid-frame and unit-frame health tick, so they are served from this cache
-- instead of walking to the active profile per read. Rebuilt lazily after an
-- invalidation; the generation is bumped by InvalidateColorCache, which every
-- writer reaches: the swatches and darken sliders (RefreshDarkMode), the master
-- toggle (RefreshDarkMode), every profile repoint (RefreshDarkMode in the profile
-- apply pass) and ApplyColorsToOUF. Lives on the namespace: this file sits at the
-- 200-local cap.
EllesmereUI._dmGen = 0
EllesmereUI._dmCache = { gen = -1 }

function EllesmereUI._RebuildDarkModeCache()
    local c = EllesmereUI._dmCache
    local d = EllesmereUI.GetDarkModeDB()
    local def = EllesmereUI.DEFAULT_DARK_MODE
    c.fr, c.fg, c.fb, c.fa = d.fillR or def.fillR, d.fillG or def.fillG, d.fillB or def.fillB, d.fillA or def.fillA
    c.br, c.bg, c.bb, c.ba = d.bgR or def.bgR, d.bgG or def.bgG, d.bgB or def.bgB, d.bgA or def.bgA
    c.gen = EllesmereUI._dmGen
end

-- Dark Mode fill colour (r, g, b, a). Opacity is honoured by Unit Frames and
-- Raid Frames; Resource Bars ignore the alpha and keep their own.
function EllesmereUI.GetDarkModeFill()
    local c = EllesmereUI._dmCache
    if c.gen ~= EllesmereUI._dmGen then EllesmereUI._RebuildDarkModeCache() end
    return c.fr, c.fg, c.fb, c.fa
end

-- Dark Mode background colour (r, g, b, a). Same opacity rules as the fill.
function EllesmereUI.GetDarkModeBg()
    local c = EllesmereUI._dmCache
    if c.gen ~= EllesmereUI._dmGen then EllesmereUI._RebuildDarkModeCache() end
    return c.br, c.bg, c.bb, c.ba
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
    -- The dark palette cache above shares every invalidation input.
    EllesmereUI._dmGen = EllesmereUI._dmGen + 1
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

-- Global Dark Mode providers. Each module stores its own flag in its own DB shape (UF
-- darkTheme; RB secondary.darkTheme; RF healthColorMode == "dark"), so each registers a
-- provider that reads/flips its flag AND repaints its frames. The Colors page's Dark Mode
-- dropdown is a pure view over them (one row each): no stored key, so it can never desync from the per-module toggles.
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
    -- RefreshDarkMode: SetDarkModeAll is only called by the Colors page's Dark Mode dropdown
    -- (pure user action), while RefreshDarkMode is also reached from the profile-apply pipeline
    -- where an extra recheck could interleave with the conditions establish choreography (cheap no-op with no darkmode group; self-defers in combat).
    if EllesmereUI.Conditions_Recheck then EllesmereUI.Conditions_Recheck() end
end

-- Class color (custom or default) with Class Color Darken baked in by the cache, so every consumer gets the adjusted colour with no per-module logic. Unknown -> white.
function EllesmereUI.GetClassColor(classToken)
    if EllesmereUI._colorCacheDirty then EllesmereUI._RebuildColorCache() end
    return EllesmereUI._colorCache.class[classToken] or EllesmereUI._COLOR_WHITE
end

-- Class token from a localized class name (friend list entries carry only that).
-- Male and female forms both map; built once on first use. Unknown or secret -> nil.
function EllesmereUI.ClassTokenFromLocalized(name)
    if type(name) ~= "string" or issecretvalue(name) then return nil end
    local map = EllesmereUI._classByLocalName
    if not map then
        map = {}
        if LOCALIZED_CLASS_NAMES_MALE then
            for token, n in pairs(LOCALIZED_CLASS_NAMES_MALE) do map[n] = token end
        end
        if LOCALIZED_CLASS_NAMES_FEMALE then
            for token, n in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do map[n] = token end
        end
        EllesmereUI._classByLocalName = map
    end
    return map[name]
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
        -- Friendly full plates repaint through the module, which respects Class
        -- Colored Health Bar being off and repaints class-coloured names and
        -- guild lines too.
        if ns_NP.RefreshFriendlyColors then ns_NP.RefreshFriendlyColors(true) end
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
