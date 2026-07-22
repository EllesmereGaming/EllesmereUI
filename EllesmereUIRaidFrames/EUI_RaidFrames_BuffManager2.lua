-- EUI_RaidFrames_BuffManager2.lua
-- 12.1 Buff Manager v2: the spell -> filter -> indicator model.
--
-- FILTERS are named spell sets: preset filters ship with the addon
-- (rename/delete locked; spell lists arrive as curated data), users add
-- custom filters and custom spell IDs, and every spell in a filter has an
-- on/off checkbox. INDICATORS consume filters and/or directly-assigned
-- spells; at runtime an indicator's spell set is the UNION of its direct
-- spells and the enabled spells of its assigned filters (buff spellID
-- filtering is engine-legal on friendly units -- helpful auras on
-- assistable targets pass the identity gate). Class tags on curated spells
-- are a UI grouping only: the runtime includes every enabled spell, since
-- externals/raid CDs are cast BY other classes onto the unit.
--
-- There is NO base grid for buffs (unlike the Debuff Manager): three
-- preset indicator groups seed per spec instead --
--   1. "Defensives & Utility" (Defensives + Raid CDs + Utility +
--      Externals), position migrated from the retired defensives row
--      settings; brand-new profiles default to center.
--   2. "Core Healing Buffs" at top left  (the old BM default corner).
--   3. "Lesser Healing Buffs" at top right (the old BM default corner).
-- Seeded groups are ordinary indicators: rename/edit/delete freely.
--
-- WIPE STRATEGY: v2 reads ONLY the new p.bm2 storage. The legacy BM keys
-- (bmIndicators/bmSimple/bmDisplayMode and the override-banked configs)
-- are deliberately LEFT INTACT and ignored: profiles are shared with the
-- 12.0 client through SavedVariables, so physically wiping them here would
-- destroy the user's retail Buff Manager. The logical wipe is total on
-- 12.1; physical deletion belongs to the at-launch cleanup pass.
--
-- This file overrides the coexistence shims: under v2 the simple grid is
-- retired (BM_BaseActive false) and indicators are always the system
-- (BM_CustomActive true).

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

-- 12.1 ONLY: inert on a 12.0 client.
if not (EllesmereUI and EllesmereUI.IS_121) then return end

-------------------------------------------------------------------------------
-- Preset filter definitions
-------------------------------------------------------------------------------
-- Order = display order. Keys are stable identifiers (stored in
-- indicator.filters assignments via numeric filter ids, but preset
-- identity rides the `preset` field so curated-data updates can find them).
local PRESET_FILTERS = {
    { key = "defensives",  name = "Defensives" },
    { key = "raidcds",     name = "Raid CDs" },
    { key = "externals",   name = "Externals" },
    { key = "coreheals",   name = "Core Healing Buffs" },
    { key = "lesserheals", name = "Lesser Healing Buffs" },
    { key = "support",     name = "Support" },
    { key = "offensive",   name = "Offensive CDs" },
    { key = "movement",    name = "Movement" },
    { key = "utility",     name = "Utility" },
    { key = "consumables", name = "Consumables" },
}
ns.BM2_PRESET_FILTERS = PRESET_FILTERS

-- Curated spell lists per preset filter (maintainer data, 2026-07-21):
-- [primaryID] = { class = "CLASSFILE"|"ALL", disabled = true|nil,
--                 alts = { id, ... } }.
-- Everything is enabled by default unless disabled is set. The PRIMARY id
-- is the checkbox row; alternates are the same buff under different ids
-- (talent/rank variants) and ride the engine include maps at slot
-- construction (BmIncludeMap) -- they follow the primary's on/off state
-- and never appear as separate entries anywhere.
-- EnsureFilters() merges NEW ids into existing profiles additively; a
-- user's explicit checkbox choice is never overwritten.
local DEFAULT_FILTER_SPELLS = {
    defensives = {
        -- Death Knight
        [48707] = { class = "DEATHKNIGHT", alts = { 444741 } },
        [48792] = { class = "DEATHKNIGHT" },
        [49039] = { class = "DEATHKNIGHT", disabled = true },
        -- Demon Hunter
        [442715] = { class = "DEMONHUNTER", disabled = true },
        [212800] = { class = "DEMONHUNTER" },
        [1266616] = { class = "DEMONHUNTER", alts = { 394933 }, disabled = true },
        [427912] = { class = "DEMONHUNTER", alts = { 258920 }, disabled = true },
        -- Druid
        [22812] = { class = "DRUID" },
        [22842] = { class = "DRUID" },
        [192081] = { class = "DRUID", disabled = true },
        [61336] = { class = "DRUID" },
        [393903] = { class = "DRUID", disabled = true },
        -- Evoker
        [404381] = { class = "EVOKER" },
        [363916] = { class = "EVOKER" },
        [374349] = { class = "EVOKER" },
        -- Hunter
        [186265] = { class = "HUNTER" },
        [472708] = { class = "HUNTER", disabled = true },
        [264735] = { class = "HUNTER" },
        -- Mage
        [342246] = { class = "MAGE" },
        [235313] = { class = "MAGE", disabled = true },
        [11426] = { class = "MAGE", disabled = true },
        [45438] = { class = "MAGE" },
        [414658] = { class = "MAGE" },
        [235450] = { class = "MAGE", disabled = true },
        -- Monk
        [122783] = { class = "MONK" },
        [115203] = { class = "MONK", alts = { 120954 } },
        -- Paladin
        [498] = { class = "PALADIN", alts = { 403876 } },
        [642] = { class = "PALADIN" },
        [184662] = { class = "PALADIN", disabled = true },
        -- Priest
        [114216] = { class = "PRIEST", alts = { 114214 }, disabled = true },
        [19236] = { class = "PRIEST" },
        [47585] = { class = "PRIEST" },
        [586] = { class = "PRIEST" },
        [45242] = { class = "PRIEST", alts = { 426401 }, disabled = true },
        [193065] = { class = "PRIEST" },
        -- Rogue
        [31224] = { class = "ROGUE" },
        [5277] = { class = "ROGUE" },
        [1966] = { class = "ROGUE" },
        -- Shaman
        [108271] = { class = "SHAMAN" },
        -- Warlock
        [108416] = { class = "WARLOCK" },
        [104773] = { class = "WARLOCK" },
        -- Warrior
        [118038] = { class = "WARRIOR" },
        [184364] = { class = "WARRIOR" },
        [190456] = { class = "WARRIOR", alts = { 1277297 } },
        [147833] = { class = "WARRIOR" },
        [23920] = { class = "WARRIOR", alts = { 385391 } },
    },
    raidcds = {
        [145629] = { class = "DEATHKNIGHT", alts = { 51052 } },
        [209426] = { class = "DEMONHUNTER", alts = { 196718 } },
        [740] = { class = "DRUID", alts = { 157982, 1264623 }, disabled = true },
        [359816] = { class = "EVOKER", alts = { 362361 }, disabled = true },
        [363534] = { class = "EVOKER", disabled = true },
        [374227] = { class = "EVOKER" },
        [31821] = { class = "PALADIN", alts = { 317929 } },
        [64843] = { class = "PRIEST", alts = { 64844 }, disabled = true },
        [81782] = { class = "PRIEST", alts = { 62618 } },
        [325174] = { class = "SHAMAN", alts = { 98008 } },
        [97463] = { class = "WARRIOR", alts = { 97462 } },
    },
    externals = {
        [102342] = { class = "DRUID" },
        [357170] = { class = "EVOKER" },
        [53480] = { class = "HUNTER" },
        [116849] = { class = "MONK" },
        [1022] = { class = "PALADIN", alts = { 1309794 } },
        [6940] = { class = "PALADIN" },
        [204018] = { class = "PALADIN" },
        [387804] = { class = "PALADIN" },
        [47788] = { class = "PRIEST" },
        [33206] = { class = "PRIEST" },
    },
    coreheals = {
        -- Druid
        [1278914] = { class = "DRUID", disabled = true },
        [33763] = { class = "DRUID", alts = { 419207, 1227806 } },
        [8936] = { class = "DRUID", alts = { 419287 }, disabled = true },
        [774] = { class = "DRUID", alts = { 419204 }, disabled = true },
        [155777] = { class = "DRUID", disabled = true },
        [439530] = { class = "DRUID", disabled = true },
        [474754] = { class = "DRUID", alts = { 474750 } },
        [48438] = { class = "DRUID", alts = { 419344 }, disabled = true },
        -- Evoker
        [409678] = { class = "EVOKER", disabled = true },
        [355941] = { class = "EVOKER", alts = { 355936, 382614 }, disabled = true },
        [376788] = { class = "EVOKER", disabled = true },
        [363502] = { class = "EVOKER", disabled = true },
        [364343] = { class = "EVOKER" },
        [445740] = { class = "EVOKER", disabled = true },
        [373267] = { class = "EVOKER" },
        [366155] = { class = "EVOKER", disabled = true },
        [367364] = { class = "EVOKER", disabled = true },
        [373862] = { class = "EVOKER", disabled = true },
        [1291636] = { class = "EVOKER", disabled = true },
        [409895] = { class = "EVOKER", disabled = true },
        -- Monk
        [450769] = { class = "MONK", alts = { 450521, 450711, 450526, 450531 }, disabled = true },
        [1292922] = { class = "MONK", disabled = true },
        [124682] = { class = "MONK", disabled = true },
        [467281] = { class = "MONK", alts = { 427296 }, disabled = true },
        [388513] = { class = "MONK", disabled = true },
        [450805] = { class = "MONK", disabled = true },
        [119611] = { class = "MONK" },
        [115175] = { class = "MONK", alts = { 1260617, 198533 }, disabled = true },
        -- Paladin
        [156910] = { class = "PALADIN" },
        [53563] = { class = "PALADIN" },
        [200025] = { class = "PALADIN" },
        [1244893] = { class = "PALADIN", alts = { 1245369 } },
        [431381] = { class = "PALADIN", alts = { 431522 }, disabled = true },
        [156322] = { class = "PALADIN", alts = { 461432 }, disabled = true },
        [432502] = { class = "PALADIN", disabled = true },
        [469703] = { class = "PALADIN", disabled = true },
        -- Priest
        [194384] = { class = "PRIEST" },
        [77489] = { class = "PRIEST", disabled = true },
        [17] = { class = "PRIEST", alts = { 1246768, 1254306, 1300008 }, disabled = true },
        [41635] = { class = "PRIEST", disabled = true },
        [139] = { class = "PRIEST", disabled = true },
        [453846] = { class = "PRIEST", alts = { 453850 }, disabled = true },
        [1253593] = { class = "PRIEST", alts = { 1300009 }, disabled = true },
        -- Shaman
        [207400] = { class = "SHAMAN", disabled = true },
        [383648] = { class = "SHAMAN", alts = { 974 } },
        [444490] = { class = "SHAMAN", disabled = true },
        [61295] = { class = "SHAMAN", disabled = true },
    },
    lesserheals = {
        -- Druid
        [1278914] = { class = "DRUID" },
        [33763] = { class = "DRUID", alts = { 419207, 1227806 }, disabled = true },
        [8936] = { class = "DRUID", alts = { 419287 } },
        [774] = { class = "DRUID", alts = { 419204 } },
        [155777] = { class = "DRUID" },
        [439530] = { class = "DRUID", disabled = true },
        [474754] = { class = "DRUID", alts = { 474750 }, disabled = true },
        [48438] = { class = "DRUID", alts = { 419344 } },
        -- Evoker
        [409678] = { class = "EVOKER", disabled = true },
        [355941] = { class = "EVOKER", alts = { 355936, 382614 } },
        [376788] = { class = "EVOKER" },
        [363502] = { class = "EVOKER", disabled = true },
        [364343] = { class = "EVOKER" },
        [445740] = { class = "EVOKER", disabled = true },
        [373267] = { class = "EVOKER" },
        [366155] = { class = "EVOKER" },
        [367364] = { class = "EVOKER" },
        [373862] = { class = "EVOKER", disabled = true },
        [1291636] = { class = "EVOKER", disabled = true },
        [409895] = { class = "EVOKER" },
        -- Monk
        [450769] = { class = "MONK", alts = { 450521, 450711, 450526, 450531 } },
        [1292922] = { class = "MONK" },
        [124682] = { class = "MONK" },
        [467281] = { class = "MONK", alts = { 427296 }, disabled = true },
        [388513] = { class = "MONK", disabled = true },
        [450805] = { class = "MONK", disabled = true },
        [119611] = { class = "MONK", disabled = true },
        [115175] = { class = "MONK", alts = { 1260617, 198533 } },
        -- Paladin
        [156910] = { class = "PALADIN", disabled = true },
        [53563] = { class = "PALADIN", disabled = true },
        [200025] = { class = "PALADIN", disabled = true },
        [1244893] = { class = "PALADIN", alts = { 1245369 }, disabled = true },
        [431381] = { class = "PALADIN", alts = { 431522 } },
        [156322] = { class = "PALADIN", alts = { 461432 } },
        [432502] = { class = "PALADIN" },
        [469703] = { class = "PALADIN" },
        -- Priest
        [194384] = { class = "PRIEST", disabled = true },
        [77489] = { class = "PRIEST" },
        [17] = { class = "PRIEST", alts = { 1246768, 1254306, 1300008 } },
        [41635] = { class = "PRIEST" },
        [139] = { class = "PRIEST" },
        [453846] = { class = "PRIEST", alts = { 453850 }, disabled = true },
        [1253593] = { class = "PRIEST", alts = { 1300009 } },
        -- Shaman
        [207400] = { class = "SHAMAN", disabled = true },
        [383648] = { class = "SHAMAN", alts = { 974 }, disabled = true },
        [444490] = { class = "SHAMAN" },
        [61295] = { class = "SHAMAN" },
    },
    support = {
        [360827] = { class = "EVOKER" },
        [395152] = { class = "EVOKER", alts = { 395296 } },
        [410263] = { class = "EVOKER", disabled = true },
        [410089] = { class = "EVOKER" },
        [413984] = { class = "EVOKER", disabled = true },
        [369459] = { class = "EVOKER", disabled = true },
    },
    offensive = {
        [1249658] = { class = "DEATHKNIGHT", alts = { 152279 } },
        [42650] = { class = "DEATHKNIGHT" },
        [191427] = { class = "DEMONHUNTER", alts = { 187827, 321067, 321068 } },
        [471306] = { class = "DEMONHUNTER", alts = { 1217605, 1225789, 473671, 1217607 } },
        [194223] = { class = "DRUID" },
        [106951] = { class = "DRUID" },
        [50334] = { class = "DRUID" },
        [403631] = { class = "EVOKER" },
        [375087] = { class = "EVOKER" },
        [186254] = { class = "HUNTER", alts = { 1235388, 1285912, 19574 } },
        [288613] = { class = "HUNTER" },
        [190319] = { class = "MAGE" },
        [365350] = { class = "MAGE" },
        [1249625] = { class = "MONK" },
        [10060] = { class = "PRIEST" },
        [114050] = { class = "SHAMAN", alts = { 114051, 114052 } },
        [107574] = { class = "WARRIOR" },
    },
    movement = {
        [48265] = { class = "DEATHKNIGHT" },
        [212552] = { class = "DEATHKNIGHT" },
        [1850] = { class = "DRUID", alts = { 61684 } },
        [106898] = { class = "DRUID", alts = { 77761, 77764 } },
        [252216] = { class = "DRUID" },
        [186257] = { class = "HUNTER", alts = { 186258 } },
        [118922] = { class = "HUNTER" },
        [444754] = { class = "MAGE" },
        [119085] = { class = "MONK" },
        [443569] = { class = "MONK" },
        [101545] = { class = "MONK", disabled = true },
        [276111] = { class = "PALADIN", alts = { 221886, 221883, 276112, 254474,
            254472, 254471, 221885, 254473, 363608, 294133, 221887, 1272854,
            453804, 1253874, 1253723, 1253881 } },
        [121557] = { class = "PRIEST" },
        [2983] = { class = "ROGUE" },
        [192082] = { class = "SHAMAN" },
        [79206] = { class = "SHAMAN" },
        [58875] = { class = "SHAMAN", alts = { 90328 } },
        [111400] = { class = "WARLOCK" },
        [202164] = { class = "WARRIOR" },
    },
    utility = {
        [3714] = { class = "DEATHKNIGHT" },
        [29166] = { class = "DRUID" },
        [406732] = { class = "EVOKER", alts = { 406789 } },
        [390386] = { class = "EVOKER", disabled = true },
        [408233] = { class = "EVOKER", disabled = true },
        [1224810] = { class = "HUNTER", alts = { 54216, 62305 } },
        [466904] = { class = "HUNTER", disabled = true },
        [264667] = { class = "HUNTER", alts = { 357650 }, disabled = true },
        [80353] = { class = "MAGE", disabled = true },
        [116841] = { class = "MONK" },
        [1044] = { class = "PALADIN", alts = { 299256 } },
        [115834] = { class = "ROGUE", alts = { 114018 } },
        [2825] = { class = "SHAMAN", disabled = true },
        [32182] = { class = "SHAMAN", disabled = true },
    },
    consumables = {
        [1236998] = { class = "ALL" },
        [1236616] = { class = "ALL" },
        [1239479] = { class = "ALL" },
        [1236994] = { class = "ALL" },
    },
}
ns.BM2_DEFAULT_FILTER_SPELLS = DEFAULT_FILTER_SPELLS

-- Alternate-id expansion map (primary -> array of alternates), built from
-- the curated data at load. Resolution expands every primary in the final
-- union so alternates always follow their primary's checkbox state.
local PRESET_ALTS = {}
-- Class tag per curated spell (alternates inherit the primary's tag) --
-- drives class-aware display picks like the sidebar tile icon.
local SPELL_CLASS = {}
for _, spells in pairs(DEFAULT_FILTER_SPELLS) do
    for id, info in pairs(spells) do
        if info.alts then PRESET_ALTS[id] = info.alts end
        if info.class then
            SPELL_CLASS[id] = info.class
            if info.alts then
                for i = 1, #info.alts do SPELL_CLASS[info.alts[i]] = info.class end
            end
        end
    end
end
ns.BM2_PresetAlts = PRESET_ALTS
ns.BM2_SpellClass = SPELL_CLASS

-- Sorted array of every curated ("preset") friendly spell id across all
-- preset filters -- the universe the Search Spells popup offers. Empty
-- until the curated data lands.
function ns.BM2_AllPresetSpells()
    local set = {}
    for _, spells in pairs(DEFAULT_FILTER_SPELLS) do
        for id in pairs(spells) do set[id] = true end
    end
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

-------------------------------------------------------------------------------
-- Storage
-------------------------------------------------------------------------------
local function P()
    return ns.db and ns.db.profile
end

local function Store()
    local p = P()
    if not p then return nil end
    local b = p.bm2
    if not b then
        b = { filters = { nextId = 1, list = {} }, specs = {}, seeded = {} }
        p.bm2 = b
    end
    return b
end

-- Resolution cache generation: any filter/indicator edit bumps it.
local gen = 1
function ns.BM2_Invalidate()
    gen = gen + 1
end

-------------------------------------------------------------------------------
-- Filter registry
-------------------------------------------------------------------------------
local function FindPreset(b, key)
    for i = 1, #b.filters.list do
        if b.filters.list[i].preset == key then return b.filters.list[i] end
    end
end

-- Seeds missing preset filters and merges NEW curated spell ids (a user's
-- explicit checkbox state is never overwritten -- only ids the filter has
-- never seen get their curated default).
local function EnsureFilters()
    local b = Store()
    if not b then return nil end
    for i = 1, #PRESET_FILTERS do
        local def = PRESET_FILTERS[i]
        local f = FindPreset(b, def.key)
        if not f then
            f = { id = b.filters.nextId, name = def.name, preset = def.key,
                spells = {}, custom = {} }
            b.filters.nextId = b.filters.nextId + 1
            b.filters.list[#b.filters.list + 1] = f
        end
        local curated = DEFAULT_FILTER_SPELLS[def.key]
        if curated then
            for id, info in pairs(curated) do
                if f.spells[id] == nil and not f.custom[id] then
                    -- Enabled by default unless the curated data says
                    -- disabled (maintainer rule).
                    f.spells[id] = not info.disabled
                end
            end
        end
    end
    return b
end

function ns.BM2_Filters()
    local b = EnsureFilters()
    return b and b.filters.list or nil
end

function ns.BM2_GetFilter(id)
    local b = Store()
    if not b then return nil end
    for i = 1, #b.filters.list do
        if b.filters.list[i].id == id then return b.filters.list[i] end
    end
end

function ns.BM2_AddFilter(name)
    local b = Store()
    if not b then return nil end
    local f = { id = b.filters.nextId, name = name or "New Filter",
        spells = {}, custom = {} }
    b.filters.nextId = b.filters.nextId + 1
    b.filters.list[#b.filters.list + 1] = f
    ns.BM2_Invalidate()
    return f
end

function ns.BM2_RenameFilter(id, name)
    local f = ns.BM2_GetFilter(id)
    if f and not f.preset and name and name ~= "" then f.name = name end
end

-- Presets cannot be deleted; deleting a custom filter also strips its
-- assignments from every indicator on every spec.
function ns.BM2_DeleteFilter(id)
    local b = Store()
    if not b then return end
    for i = #b.filters.list, 1, -1 do
        local f = b.filters.list[i]
        if f.id == id and not f.preset then
            table.remove(b.filters.list, i)
        end
    end
    for _, spec in pairs(b.specs) do
        for j = 1, #spec.inds do
            local ind = spec.inds[j]
            if ind.filters then ind.filters[id] = nil end
        end
    end
    ns.BM2_Invalidate()
end

-- Checkbox state: true/false = explicit; setting a CUSTOM spell to nil
-- removes it entirely.
function ns.BM2_SetSpellState(filterId, spellID, state)
    local f = ns.BM2_GetFilter(filterId)
    if not f then return end
    if state == nil and f.custom[spellID] then
        f.custom[spellID] = nil
        f.spells[spellID] = nil
    else
        f.spells[spellID] = state and true or false
    end
    ns.BM2_Invalidate()
end

function ns.BM2_AddCustomSpell(filterId, spellID)
    local f = ns.BM2_GetFilter(filterId)
    if not (f and spellID and spellID > 0) then return false end
    if f.spells[spellID] ~= nil then return false end -- already present
    f.custom[spellID] = true
    f.spells[spellID] = true
    ns.BM2_Invalidate()
    return true
end

-------------------------------------------------------------------------------
-- Spec indicators (seeding + access)
-------------------------------------------------------------------------------
-- The ACTIVE config key: the legacy healer spec key when the player is on
-- a tracked healer spec, otherwise the shared "nonhealer" bucket -- every
-- spec NOT in the editing dropdown's healer list uses ONE config (the
-- defensives/support display is class-agnostic; filters resolve the right
-- spells at runtime).
function ns.BM2_SpecKey()
    return (ns.BM_CurrentSpecKey and ns.BM_CurrentSpecKey()) or "nonhealer"
end

local function PresetIdsByKey(b)
    local map = {}
    for i = 1, #b.filters.list do
        local f = b.filters.list[i]
        if f.preset then map[f.preset] = f.id end
    end
    return map
end

-- Seeds the three starter groups for a spec. Group 1's anchor migrates
-- from the retired defensives-row settings so existing users' externals
-- land where their defensives row was; new profiles default to center.
local function SeedSpec(b, specKey)
    if b.seeded[specKey] then return end
    b.seeded[specKey] = true
    local p = P()
    local pf = PresetIdsByKey(b)
    local spec = b.specs[specKey]
    -- Id namespace offset: the legacy page creates indicators through its
    -- own global id counter (synced from LEGACY storage only), so v2 ids
    -- start far above anything that counter can realistically reach.
    if not spec then spec = { nextId = 1000001, inds = {} }; b.specs[specKey] = spec end

    local hadLegacyDefs = p and (p.defPosition ~= nil or p.defOffsetX ~= nil
        or p.defOffsetY ~= nil or p.defGrowDirection ~= nil)
    local g1 = {
        id = spec.nextId, enabled = true, type = "icon",
        name = "Defensives & Utility",
        -- Own-only rides per-source flags (ownFilters/ownExtras); none here:
        -- externals/raid CDs are cast BY others.
        ownFilters = {}, ownExtras = {},
        filters = {},
        spells = {},
        position = string.upper((hadLegacyDefs and p.defPosition) or "center"),
        growDirection = (hadLegacyDefs and p.defGrowDirection) or "CENTER",
        offsetX = (hadLegacyDefs and p.defOffsetX) or 0,
        offsetY = (hadLegacyDefs and p.defOffsetY) or 0,
        size = (hadLegacyDefs and p.defSize) or 20,
    }
    if pf.defensives then g1.filters[pf.defensives] = true end
    if pf.raidcds then g1.filters[pf.raidcds] = true end
    if pf.utility then g1.filters[pf.utility] = true end
    if pf.externals then g1.filters[pf.externals] = true end
    spec.nextId = spec.nextId + 1
    spec.inds[#spec.inds + 1] = g1

    -- The healing-buff corners are healer-centric (own-only HoT tracking);
    -- the shared Non-Healer bucket seeds only the defensives/support group.
    if specKey ~= "nonhealer" then
        local g2 = { id = spec.nextId, enabled = true, type = "icon",
            name = "Core Healing Buffs", ownFilters = {}, ownExtras = {},
            filters = {}, spells = {},
            position = "TOPLEFT", growDirection = "RIGHT", size = 18 }
        if pf.coreheals then
            g2.filters[pf.coreheals] = true
            g2.ownFilters[pf.coreheals] = true -- healing presets default own-only
        end
        spec.nextId = spec.nextId + 1
        spec.inds[#spec.inds + 1] = g2

        local g3 = { id = spec.nextId, enabled = true, type = "icon",
            name = "Lesser Healing Buffs", ownFilters = {}, ownExtras = {},
            filters = {}, spells = {},
            position = "TOPRIGHT", growDirection = "LEFT", size = 18 }
        if pf.lesserheals then
            g3.filters[pf.lesserheals] = true
            g3.ownFilters[pf.lesserheals] = true -- healing presets default own-only
        end
        spec.nextId = spec.nextId + 1
        spec.inds[#spec.inds + 1] = g3
    end
end

-- key = a healer spec key or "nonhealer" (the editing dropdown's choice);
-- nil = the player's ACTIVE key (runtime path).
function ns.BM2_SpecInds(key)
    local b = EnsureFilters()
    if not b then return nil, nil end
    local specKey = key or ns.BM2_SpecKey()
    SeedSpec(b, specKey)
    local spec = b.specs[specKey]
    if spec then
        -- Token normalization: the first-cut seeds wrote lowercase corner
        -- tokens ("center"/"topleft"); the BM machinery expects the legacy
        -- UPPERCASE set, and mismatches fell through to broken defaults.
        -- Heals already-persisted data on every read (cheap).
        for i = 1, #spec.inds do
            local ind = spec.inds[i]
            if ind.position then ind.position = string.upper(ind.position) end
            -- Own-only model heal: first-cut seeds carried a single
            -- ind.ownOnly boolean; the shipped model is per-SOURCE flags
            -- (one per assigned filter / extra spell). Expand the old
            -- boolean once; afterwards the legacy field is inert here.
            if not ind.ownFilters then
                ind.ownFilters = {}
                ind.ownExtras = {}
                if ind.ownOnly == true then
                    for fid in pairs(ind.filters or {}) do
                        ind.ownFilters[fid] = true
                    end
                    if ind.spells then
                        for j = 1, #ind.spells do
                            ind.ownExtras[ind.spells[j]] = true
                        end
                    end
                end
            elseif not ind.ownExtras then
                ind.ownExtras = {}
            end
            -- Seed-name heal: group 1 was renamed after the first PTR
            -- builds; only the untouched old name is rewritten, a user's
            -- own rename is left alone.
            if ind.name == "Defensive & Support CDs" then
                ind.name = "Defensives & Utility"
            end
        end
    end
    return spec and spec.inds or nil, specKey
end

-- key (optional): the EDITED bucket (healer spec key or "nonhealer");
-- defaults to the player's active key.
function ns.BM2_AddIndicator(indType, key)
    local b = Store()
    if not b then return nil end
    local specKey = key or ns.BM2_SpecKey()
    SeedSpec(b, specKey)
    local spec = b.specs[specKey]
    -- Growth must match the position the way the Position dropdown derives
    -- it (TOPLEFT -> RIGHT): CENTER growth centers the run ON the anchor
    -- point, so pairing it with a corner hangs half the icons off the
    -- frame -- in the preview AND on live frames alike.
    local ind = { id = spec.nextId, enabled = true, type = indType or "icon",
        name = "New Indicator", filters = {}, spells = {},
        ownFilters = {}, ownExtras = {},
        position = "TOPLEFT", growDirection = "RIGHT", size = 18 }
    spec.nextId = spec.nextId + 1
    spec.inds[#spec.inds + 1] = ind
    ns.BM2_Invalidate()
    return ind
end

function ns.BM2_DeleteIndicator(id)
    local b = Store()
    if not b then return end
    local spec = b.specs[ns.BM2_SpecKey()]
    if not spec then return end
    for i = #spec.inds, 1, -1 do
        if spec.inds[i].id == id then table.remove(spec.inds, i) end
    end
    ns.BM2_Invalidate()
end

-------------------------------------------------------------------------------
-- Resolution: indicator -> effective spell array
-------------------------------------------------------------------------------
-- Union of direct spells + enabled spells of assigned filters. Built fresh
-- on every call: the LEGACY editor mutates ind.spells directly without
-- bumping the edit generation, so any generation-keyed cache here would
-- serve stale unions after a spell edit (field lesson from the first
-- integration round). Callers run once per class per reload -- cheap.
-- Returned arrays are stable-sorted so downstream signatures stay
-- deterministic.
-- Same union, plus per-spell OWNERSHIP: each contributing source (an
-- assigned filter or a direct extra spell) carries its own own-only flag
-- (ind.ownFilters[fid] / ind.ownExtras[sid]); a spell contributed by
-- several sources is own-only ONLY if every source says so (show-all
-- wins -- the less restrictive intent). Alternates inherit their
-- primary's state. Returns (sortedList, ownMap).
function ns.BM2_ResolveSpellsOwn(ind)
    local set = {} -- id -> own-only boolean
    local function Add(id, own)
        local cur = set[id]
        if cur == nil then
            set[id] = own and true or false
        elseif cur and not own then
            set[id] = false
        end
    end
    if ind.spells then
        local oe = ind.ownExtras
        for i = 1, #ind.spells do
            local id = ind.spells[i]
            Add(id, oe and oe[id])
        end
    end
    if ind.filters then
        local of = ind.ownFilters
        for fid in pairs(ind.filters) do
            local f = ns.BM2_GetFilter(fid)
            if f then
                local fOwn = of and of[fid]
                for id, on in pairs(f.spells) do
                    if on then Add(id, fOwn) end
                end
            end
        end
    end
    -- Alternates are deliberately NOT part of the resolved list: one entry
    -- per buff FAMILY, or the preview/slot layer renders the same buff once
    -- per talent/rank id. Alt ids ride the engine include maps instead
    -- (BmIncludeMap consults BM2_PresetAlts), so an aura present under an
    -- alternate id still matches its primary's slot.
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out, set
end

function ns.BM2_ResolveSpells(ind)
    local out = ns.BM2_ResolveSpellsOwn(ind)
    return out
end

-- Preferred DISPLAY spell for an indicator (sidebar tile icon etc.):
-- prefer a resolved spell the player actually knows (spec-accurate via
-- IsPlayerSpell), then one curated for the player's class, then an
-- all-class entry, then the first resolved spell.
function ns.BM2_PreferredSpell(ind)
    local resolved = ns.BM2_ResolveSpells(ind)
    if #resolved == 0 then return nil end
    local _, classFile = UnitClass("player")
    local classPick, allPick
    for i = 1, #resolved do
        local id = resolved[i]
        if IsPlayerSpell then
            -- The list holds one PRIMARY per buff family; the player may
            -- only know a talent/rank alternate, so check the whole family.
            if IsPlayerSpell(id) then return id end
            local alts = PRESET_ALTS[id]
            if alts then
                for j = 1, #alts do
                    if IsPlayerSpell(alts[j]) then return id end
                end
            end
        end
        local c = SPELL_CLASS[id]
        if not classPick and c == classFile then classPick = id end
        if not allPick and c == "ALL" then allPick = id end
    end
    return classPick or allPick or resolved[1]
end

-------------------------------------------------------------------------------
-- Per-source own-only (the Own Only dropdown's data layer)
-------------------------------------------------------------------------------
-- The healing-buff presets track the healer's OWN HoTs; everything else
-- (defensives, externals, raid CDs, ...) is cast by or on others, so only
-- these two default own-only when assigned.
function ns.BM2_FilterDefaultOwn(filterId)
    local f = ns.BM2_GetFilter(filterId)
    return f ~= nil and (f.preset == "coreheals" or f.preset == "lesserheals")
end

-- Items for the Own Only checkbox dropdown: one row per ASSIGNED filter
-- and per extra spell, grouped under headers. Pre-ordered (filter registry
-- order, then extras by name) -- callers must NOT re-sort, headers would
-- scatter. Keys are typed ("f<id>" / "s<id>") for BM2_OwnGet/OwnSet.
function ns.BM2_OwnSourceItems(ind)
    local items = {}
    local fl = ns.BM2_Filters() or {}
    local anyF = false
    for i = 1, #fl do
        local f = fl[i]
        if ind.filters and ind.filters[f.id] then
            if not anyF then
                items[#items + 1] = { isHeader = true, label = "Filters" }
                anyF = true
            end
            items[#items + 1] = { key = "f" .. f.id, label = f.name }
        end
    end
    if ind.spells and #ind.spells > 0 then
        local sp = {}
        for i = 1, #ind.spells do
            local id = ind.spells[i]
            local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            sp[#sp + 1] = { key = "s" .. id, label = nm or ("Spell " .. id),
                icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id),
                iconSize = 16 }
        end
        table.sort(sp, function(a, b) return a.label < b.label end)
        items[#items + 1] = { isHeader = true, label = "Extra Spells" }
        for i = 1, #sp do items[#items + 1] = sp[i] end
    end
    return items
end

local function OwnKeyParts(key)
    local kind, id = string.match(key or "", "^([fs])(%d+)$")
    return kind, tonumber(id)
end

function ns.BM2_OwnGet(ind, key)
    local kind, id = OwnKeyParts(key)
    if not id then return false end
    if kind == "f" then
        return ind.ownFilters and ind.ownFilters[id] and true or false
    end
    return ind.ownExtras and ind.ownExtras[id] and true or false
end

function ns.BM2_OwnSet(ind, key, v)
    local kind, id = OwnKeyParts(key)
    if not id then return end
    if kind == "f" then
        if not ind.ownFilters then ind.ownFilters = {} end
        ind.ownFilters[id] = v and true or nil
    else
        if not ind.ownExtras then ind.ownExtras = {} end
        ind.ownExtras[id] = v and true or nil
    end
    ns.BM2_Invalidate()
end

-- Adapter for the containers runtime: legacy-shaped indicator list with
-- resolved spell arrays, built fresh per call (see BM2_ResolveSpells --
-- the legacy editor mutates indicator tables directly, so caching against
-- the edit generation is unsound). Indicators whose resolution is EMPTY
-- are skipped (declaring a group with an empty include map has unverified
-- semantics).
-- STABLE adapter views, one per store indicator (weak keys). The container
-- machinery captures these tables in its per-button meta at build time and
-- re-reads them on every geometry fingerprint/anchor pass -- a fresh table
-- per call froze position/growth edits at their build-time values until a
-- reload (the legacy path never had this problem because its meta held the
-- live saved tables). Refreshed IN PLACE on every call.
local bm2ViewCache = setmetatable({}, { __mode = "k" })

function ns.BM2_SpecIndicators()
    local inds, specKey = ns.BM2_SpecInds()
    if not inds then return nil, specKey, "custom" end
    local PLACED_TYPES = { icon = true, square = true, bar = true }
    local out = {}
    for i = 1, #inds do
        local ind = inds[i]
        local resolved, own = ns.BM2_ResolveSpellsOwn(ind)
        if #resolved > 0 then
            -- Shallow view carrying the legacy fields the container BM
            -- machinery reads, with spells swapped for the resolved union.
            local v = bm2ViewCache[ind]
            if not v then v = {}; bm2ViewCache[ind] = v end
            for k in pairs(v) do v[k] = nil end
            for k, val in pairs(ind) do v[k] = val end
            v.spells = resolved
            -- Own-only synthesis into the legacy runtime fields (always
            -- explicit -- the legacy nil-default is own-only TRUE, and any
            -- stale ownOnly/ownOnlySpells copied above must not leak):
            -- uniform sets ride the chain group's PLAYER filter; MIXED
            -- placed sets fall to per-spell slot mode via ownOnlySpells;
            -- effect types can't split one slot per spell, so they are
            -- own-only only when EVERY source is.
            local ownCount = 0
            for j = 1, #resolved do
                if own[resolved[j]] then ownCount = ownCount + 1 end
            end
            v.ownOnlySpells = nil
            if ownCount == #resolved and ownCount > 0 then
                v.ownOnly = true
            else
                v.ownOnly = false
                if ownCount > 0 and PLACED_TYPES[v.type or "icon"] then
                    local map = {}
                    for j = 1, #resolved do
                        if own[resolved[j]] then map[resolved[j]] = true end
                    end
                    v.ownOnlySpells = map
                end
            end
            out[#out + 1] = v
        end
    end
    return out, specKey, "custom"
end

-------------------------------------------------------------------------------
-- Activation flag. v2 is DORMANT until the rebuilt UI ships (the first
-- from-scratch page was rejected in field review -- the rebuild integrates
-- v2 data into the polished legacy page shell instead). While dormant:
-- the runtime adapter and the page redirect are inert, the legacy Buff
-- Manager (page + storage + Base Icons coexistence) runs untouched, and
-- the coexistence shims stay owned by the Debuff Manager file.
-- Flip ns.BM2_Enabled = true ONLY together with the rebuilt UI.
-- ACTIVE since 2026-07-21: v2 runs INSIDE the legacy page shell (storage
-- accessor swap + Assigned Filters section + modal Filter Editor).
-------------------------------------------------------------------------------
ns.BM2_Enabled = true

-- Retirement overrides (simple grid off, indicators always on) apply only
-- once v2 is live; dormant v2 must not perturb the legacy coexistence.
if ns.BM2_Enabled then
    function ns.BM_BaseActive()
        return false
    end
    function ns.BM_CustomActive()
        return true
    end
end


