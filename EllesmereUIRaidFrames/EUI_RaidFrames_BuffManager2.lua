if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_RaidFrames_BuffManager2.lua
-- 12.1 Buff Manager v2: the spell -> filter -> indicator model.
-- FILTERS are named spell sets: presets ship with the addon (rename/delete
-- locked, curated lists), users add custom filters and spell IDs, every spell
-- has an on/off checkbox. INDICATORS consume filters and/or direct spells;
-- the runtime set is the UNION of direct spells and assigned filters' enabled
-- spells. Buff spellID filtering is engine-legal on friendly units (helpful
-- auras on assistable targets pass the identity gate). Class tags are UI
-- grouping ONLY: the runtime includes every enabled spell, since externals/
-- raid CDs are cast BY other classes. There is NO base grid for buffs (unlike
-- the Debuff Manager); three ordinary indicator groups seed per spec instead:
-- "Defensives & Utility" (Defensives + Raid CDs + Utility + Externals)
-- center, "Core Healing Buffs" top left, "Lesser Healing Buffs" top right.
-- The Defensives & Utility group's position migrates from the retired
-- defensives-row setting; brand-new profiles default to center.
--
-- WIPE STRATEGY: v2 reads ONLY p.bm2. The legacy BM keys (bmIndicators/
-- bmSimple/bmDisplayMode, override-banked configs) are LEFT INTACT and
-- ignored: profiles are shared with the 12.0 client through SavedVariables,
-- so wiping them here would destroy the user's retail Buff Manager. Physical
-- deletion belongs to the at-launch cleanup pass. This file also overrides
-- the coexistence shims: under v2 the simple grid is retired (BM_BaseActive
-- false) and indicators are always the system (BM_CustomActive true).

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

-------------------------------------------------------------------------------
-- Preset filter definitions
-------------------------------------------------------------------------------
-- Preset identity/order and the curated spell lists live in the parent's
-- shared catalogue (EllesmereUI_BuffPresets.lua) -- THE single curation
-- source, also consumed (alt-flattened) by Player Aura Bars' filter seed.
-- Add or edit curated ids THERE, never here.
local PRESET_FILTERS = EllesmereUI.BUFF_PRESETS.filters
ns.BM2_PRESET_FILTERS = PRESET_FILTERS

-- Curated spell lists: see the parent catalogue (shape documented there).
local DEFAULT_FILTER_SPELLS = EllesmereUI.BUFF_PRESETS.spells
ns.BM2_DEFAULT_FILTER_SPELLS = DEFAULT_FILTER_SPELLS

-- Primary -> alternates, built from the curated data at load. Resolution
-- expands every primary so alternates follow their primary's checkbox state.
local PRESET_ALTS = {}
-- Class tag per curated spell (alternates inherit the primary's); drives
-- class-aware display picks like the sidebar tile icon.
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

-- Sorted array of every curated spell id: the Search Spells popup universe.
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

-------------------------------------------------------------------------------
-- One-shot legacy import (only while the profile has no bm2 store): legacy
-- Buff Manager buckets that were customized carry into v2 as direct-spell
-- indicators, grouping preserved 1:1; default buckets go to SeedSpec instead.
-------------------------------------------------------------------------------

local function LegacyCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = LegacyCopy(x) end
    return t
end

-- Spell arrays compare as SETS: only membership is user-editable, not order.
local function SameSpellSet(a, b)
    a, b = a or {}, b or {}
    if #a ~= #b then return false end
    local set = {}
    for i = 1, #a do set[a[i]] = true end
    for i = 1, #b do
        if not set[b[i]] then return false end
    end
    return true
end

local function SameValue(a, b)
    if type(a) == "table" and type(b) == "table" then
        for k, v in pairs(a) do
            if not SameValue(v, b[k]) then return false end
        end
        for k in pairs(b) do
            if a[k] == nil then return false end
        end
        return true
    end
    return a == b
end

-- Untouched = every field the stored indicator carries matches the freshly
-- built default (fields the default lacks are ignored). When in doubt migrate:
-- copying a near-default setup is harmless, dropping a customized one is not.
local function IndMatchesDefault(ind, def)
    if (ind.type or "icon") ~= "icon" then return false end
    if ind.position ~= def.position then return false end
    if not SameSpellSet(ind.spells, def.spells) then return false end
    for k, v in pairs(ind) do
        if k ~= "id" and k ~= "spells" and k ~= "position" then
            local dv = def[k]
            if dv ~= nil and not SameValue(v, dv) then return false end
        end
    end
    return true
end

local function IsDefaultBucket(specKey, list)
    local newInd = ns.BM_NewIndicator
    local presets = ns.BM_DefaultIndicators and ns.BM_DefaultIndicators[specKey]
    if not newInd or not presets then return #list == 0 end
    if #list ~= #presets then return false end
    for i = 1, #presets do
        local def = newInd("icon", presets[i].spells)
        def.position = presets[i].pos
        if presets[i].pos == "TOPRIGHT" then def.growDirection = "LEFT" end
        if not IndMatchesDefault(list[i], def) then return false end
    end
    return true
end

-- Frame Alpha has no 12.1 renderer (fading needs per-aura presence, secret in
-- combat) so those indicators drop; Frame Border migrates (containers render).
local IMPORT_SKIP_TYPES = { framealpha = true }

-- Legacy indicator -> v2: same shape, empty filter assignments, spells kept
-- as direct spells. Own-only is per-INDICATOR in v2, so the legacy per-spell
-- resolution (ownOnlySpells, else ownOnly, nil = own-only) collapses by
-- MAJORITY (tie = any-caster). Removed per-icon size offsets never carry
-- over; nil return = retired type.
local function ImportLegacyInd(ind)
    if IMPORT_SKIP_TYPES[ind.type or "icon"] then return nil end
    local v = LegacyCopy(ind)
    v.filters = {}
    local ownSpells = ind.ownOnlySpells
    local ownFallback = ind.ownOnly ~= false
    local total, ownCount = 0, 0
    for i = 1, #(ind.spells or {}) do
        local sid = ind.spells[i]
        local own
        if ownSpells and ownSpells[sid] ~= nil then
            own = ownSpells[sid]
        else
            own = ownFallback
        end
        total = total + 1
        if own then ownCount = ownCount + 1 end
    end
    v.ownOnly = ownCount > (total - ownCount)
    v.ownOnlySpells = nil
    v.sizeOffsets = nil
    return v
end

-- Legacy indicator array -> v2 list (nil if nothing survives the type skip).
function ns.BM2_ImportLegacyBucket(list)
    local out
    for i = 1, #(list or {}) do
        local v = ImportLegacyInd(list[i])
        if v then
            out = out or {}
            out[#out + 1] = v
        end
    end
    return out
end

-- bmIndicators-shaped legacy set -> v2 fork data { specs, seeded }. Simple-
-- grid sets convert to empty (no v2 home; every spec takes the starter
-- groups). Used by the profile one-shot and by override-layer conversion.
function ns.BM2_ConvertLegacySet(src, displayMode)
    local out = { specs = {}, seeded = {} }
    if type(src) ~= "table" or displayMode == "simple" then return out end
    for specKey, list in pairs(src) do
        -- Any customized bucket migrates, INCLUDING one customized down to
        -- nothing (all indicators deleted, or only retired types left): an
        -- empty seeded bucket preserves "no buff display" intent, where
        -- leaving it unseeded would force the starter groups back on.
        if type(list) == "table" and not IsDefaultBucket(specKey, list) then
            local inds = ns.BM2_ImportLegacyBucket(list) or {}
            local maxId = 0
            for i = 1, #inds do
                local id = tonumber(inds[i].id) or 0
                if id > maxId then maxId = id end
            end
            out.specs[specKey] = {
                nextId = math.max(1000001, maxId + 1),
                inds = inds,
            }
            out.seeded[specKey] = true
        end
    end
    return out
end

-- Legacy truth is LIVE bmIndicators, deliberately even while a BM override
-- fork is applied: the runtime pointer says live IS the fork, so the store
-- must mirror it (the first harvest banks live v2 data into the fork's
-- layer). Baseline and other forks convert lazily in _ERF_BM2ApplyLayer.
local function ImportLegacyProfile(p, b)
    local fork = ns.BM2_ConvertLegacySet(p.bmIndicators, p.bmDisplayMode)
    b.specs = fork.specs
    b.seeded = fork.seeded
end

local function Store()
    local p = P()
    if not p then return nil end
    local b = p.bm2
    if not b then
        b = { filters = { nextId = 1, list = {} }, specs = {}, seeded = {} }
        p.bm2 = b
        ImportLegacyProfile(p, b)
    end
    return b
end

-------------------------------------------------------------------------------
-- Override-layer bridge (SpecOverrides BM layers). A fork's v2 payload is the
-- spec indicator sets + seeded map ONLY: the filter library stays shared
-- profile-wide, so custom filters and curated updates never diverge per fork.
-- Both hooks go through Store(), so the legacy one-shot always ran first.
-------------------------------------------------------------------------------

-- Snapshot of the live v2 fork data for layer harvests.
function _G._ERF_BM2HarvestFork()
    local b = Store()
    if not b then return nil end
    return { specs = LegacyCopy(b.specs), seeded = LegacyCopy(b.seeded) }
end

-- Applies a BM layer's v2 payload into the live store, converting legacy-only
-- layers in place on first touch. layer.bm2 doubles as the conversion marker:
-- layers already carrying v2 data are never re-derived from legacy fields.
function _G._ERF_BM2ApplyLayer(layer)
    local b = Store()
    if not b or not layer then return end
    if not layer.bm2 then
        layer.bm2 = ns.BM2_ConvertLegacySet(layer.indicators, layer.displayMode)
    end
    wipe(b.specs)
    for k, v in pairs(layer.bm2.specs or {}) do b.specs[k] = LegacyCopy(v) end
    wipe(b.seeded)
    for k, v in pairs(layer.bm2.seeded or {}) do b.seeded[k] = v end
    ns.BM2_Invalidate()
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

-- Seeds missing preset filters and merges only NEW curated ids: an id the
-- filter has already seen keeps the user's checkbox state.
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
                    f.spells[id] = not info.disabled
                end
            end
        end
        -- Prune the other way: a spell REMOVED from curated data must leave
        -- existing profiles too, or its seeded state lingers forever, still
        -- resolving onto frames and undeletable in the Filter Editor (no
        -- f.custom membership = no remove control). f.custom spells and
        -- still-curated states stay; clearing a key in pairs() is legal in 5.1.
        for id in pairs(f.spells) do
            if not (curated and curated[id]) and not f.custom[id] then
                f.spells[id] = nil
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

-- Checkbox state: true/false explicit; nil on a CUSTOM spell removes it.
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
-- ACTIVE config key: the healer spec key on a tracked healer spec, else the
-- shared "nonhealer" bucket -- every spec outside the editor's healer list
-- shares ONE config (class-agnostic display; filters resolve it at runtime).
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

-- Seeds the starter groups: group 1 center, healing corners top-left/right.
local function SeedSpec(b, specKey)
    if b.seeded[specKey] then return end
    b.seeded[specKey] = true
    local pf = PresetIdsByKey(b)
    local spec = b.specs[specKey]
    -- Id namespace offset: the legacy page's own global id counter is synced
    -- from LEGACY storage only, so v2 ids start far above its reachable range.
    if not spec then spec = { nextId = 1000001, inds = {} }; b.specs[specKey] = spec end

    -- Additive union buckets ("allspecs" + per-spec "spec<ID>") start EMPTY:
    -- nothing renders from them until the user builds something there, so
    -- existing setups are untouched by their arrival.
    if specKey == "allspecs" or specKey:match("^spec%d") then return end

    local g1 = {
        id = spec.nextId, enabled = true, type = "icon",
        name = "Defensives & Utility",
        -- Any-caster: externals/raid CDs are cast BY others.
        ownOnly = false,
        filters = {},
        spells = {},
        position = "CENTER", growDirection = "CENTER", size = 18,
    }
    if pf.defensives then g1.filters[pf.defensives] = true end
    if pf.raidcds then g1.filters[pf.raidcds] = true end
    if pf.utility then g1.filters[pf.utility] = true end
    if pf.externals then g1.filters[pf.externals] = true end
    spec.nextId = spec.nextId + 1
    spec.inds[#spec.inds + 1] = g1

    -- Healing-buff corners are healer-only and default own-only (the healer's
    -- OWN HoTs); the shared nonhealer bucket seeds group 1 alone.
    if specKey ~= "nonhealer" then
        local g2 = { id = spec.nextId, enabled = true, type = "icon",
            name = "Core Healing Buffs", ownOnly = true,
            filters = {}, spells = {},
            position = "TOPLEFT", growDirection = "RIGHT", size = 18 }
        if pf.coreheals then
            g2.filters[pf.coreheals] = true
        end
        spec.nextId = spec.nextId + 1
        spec.inds[#spec.inds + 1] = g2

        local g3 = { id = spec.nextId, enabled = true, type = "icon",
            name = "Lesser Healing Buffs", ownOnly = true,
            filters = {}, spells = {},
            position = "TOPRIGHT", growDirection = "LEFT", size = 18 }
        if pf.lesserheals then
            g3.filters[pf.lesserheals] = true
        end
        spec.nextId = spec.nextId + 1
        spec.inds[#spec.inds + 1] = g3
    end
end

-- key = healer spec key or "nonhealer" (editor); nil = player's ACTIVE key.
function ns.BM2_SpecInds(key)
    local b = EnsureFilters()
    if not b then return nil, nil end
    local specKey = key or ns.BM2_SpecKey()
    SeedSpec(b, specKey)
    local spec = b.specs[specKey]
    if spec then
        -- Token normalization: the BM machinery expects UPPERCASE position/
        -- growth tokens (lowercase breaks to defaults); healed on every read.
        for i = 1, #spec.inds do
            local ind = spec.inds[i]
            if ind.position then ind.position = string.upper(ind.position) end
            if ind.growDirection then ind.growDirection = string.upper(ind.growDirection) end
            -- Per-icon size offsets are removed: purge stale data.
            ind.sizeOffsets = nil
            -- Own-only is per-INDICATOR (per-source flags forced per-spell
            -- slot layout, which exploded at filter-union scale): collapse
            -- stale flags by MAJORITY of resolved own states, tie = any-caster.
            if ind.ownFilters or ind.ownExtras then
                local resolved, own = ns.BM2_ResolveSpellsOwn(ind)
                local ownCount = 0
                for j = 1, #resolved do
                    if own[resolved[j]] then ownCount = ownCount + 1 end
                end
                ind.ownOnly = ownCount > (#resolved - ownCount)
                ind.ownFilters = nil
                ind.ownExtras = nil
                ind.ownOnlySpells = nil
            elseif ind.ownOnly == nil then
                ind.ownOnly = false
            end
            -- Seed-name heal: rewrite only the untouched old group-1 name,
            -- never a user's own rename.
            if ind.name == "Defensive & Support CDs" then
                ind.name = "Defensives & Utility"
            end
        end
    end
    return spec and spec.inds or nil, specKey
end

-- key (optional) = the EDITED bucket; defaults to the player's active key.
function ns.BM2_AddIndicator(indType, key)
    local b = Store()
    if not b then return nil end
    local specKey = key or ns.BM2_SpecKey()
    SeedSpec(b, specKey)
    local spec = b.specs[specKey]
    -- Growth must match the position the way the Position dropdown derives it
    -- (TOPLEFT -> RIGHT): CENTER growth centers the run ON the anchor, so a
    -- corner + CENTER hangs half the icons off the frame (preview and live).
    local ind = { id = spec.nextId, enabled = true, type = indType or "icon",
        name = "New Indicator", filters = {}, spells = {},
        ownOnly = false,
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
-- Union of direct spells + enabled spells of assigned filters, plus per-spell
-- OWNERSHIP: each source (filter or direct extra) has its own flag (ind.ownFilters[fid]
-- / ind.ownExtras[sid]); a spell from several sources is own-only ONLY if all say so
-- (show-all wins, the less restrictive intent). Alternates inherit their primary's
-- state. Returns (sortedList, ownMap), stable-sorted for deterministic signatures.
-- Rebuilt every call (cheap: once per class per reload) because the LEGACY editor
-- mutates ind.spells without bumping the edit generation, so a generation-keyed cache
-- would serve stale unions after a spell edit.
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
    -- Alternates are deliberately NOT in the resolved list: one entry per buff
    -- FAMILY, else the preview/slot layer renders the same buff once per
    -- talent/rank id. Alt ids ride the engine include maps instead
    -- (BmIncludeMap consults BM2_PresetAlts) so they still match their slot.
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out, set
end

function ns.BM2_ResolveSpells(ind)
    local out = ns.BM2_ResolveSpellsOwn(ind)
    return out
end

-- Preferred DISPLAY spell (sidebar tile icon etc.): a resolved spell the
-- player knows (IsPlayerSpell, spec-accurate), else one curated for the
-- target class, else an "ALL" entry, else the first resolved spell.
-- classOverride = the EDITED bucket's class (dropdown selection), so tiles
-- face the spec being edited; nil = the player's class. The known-spell
-- pass only applies when the target class IS the player's -- IsPlayerSpell
-- can't speak for other classes.
function ns.BM2_PreferredSpell(ind, classOverride)
    local resolved = ns.BM2_ResolveSpells(ind)
    if #resolved == 0 then return nil end
    local _, playerClass = UnitClass("player")
    local classFile = classOverride or playerClass
    local useKnown = classFile == playerClass
    local classPick, allPick
    for i = 1, #resolved do
        local id = resolved[i]
        if useKnown and IsPlayerSpell then
            -- One PRIMARY per family: the player may know only an alternate.
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

-- Adapter for the containers runtime: legacy-shaped indicator list with
-- resolved spell arrays, recomputed per call (the legacy editor mutates
-- indicator tables directly, so an edit-generation cache is unsound).
-- Indicators resolving to EMPTY are skipped (empty include map = unverified
-- semantics). The views are STABLE, one per store indicator (weak keys) and
-- refreshed IN PLACE: the container machinery captures them in its per-button
-- meta at build time and re-reads them on every geometry fingerprint/anchor
-- pass, so a fresh table per call freezes position/growth edits until reload.
local bm2ViewCache = setmetatable({}, { __mode = "k" })

function ns.BM2_SpecIndicators()
    local inds, specKey = ns.BM2_SpecInds()
    -- Additive union buckets: "allspecs" renders for EVERY spec, and a spec
    -- outside the healer/Aug list also renders its own "spec<ID>" bucket on
    -- top of its active one (borrow specs keep their borrowed set AND gain
    -- their own bucket). Both are empty until the user fills them.
    local ownInds, allInds
    local specIdx = GetSpecialization and GetSpecialization()
    local specID = specIdx and GetSpecializationInfo and GetSpecializationInfo(specIdx)
    if specID and ns.BM_SpecKeyForSpecID and not ns.BM_SpecKeyForSpecID(specID) then
        ownInds = ns.BM2_SpecInds("spec" .. specID)
    end
    allInds = ns.BM2_SpecInds("allspecs")
    if not inds and not ownInds and not allInds then return nil, specKey, "custom" end
    local out = {}
    -- idOffset disambiguates slot/chain/style keys across unioned buckets
    -- (every bucket allocates ids from the same 1000001 base) and shifts
    -- anchorTo identically so Anchor To links stay bucket-internal.
    local function Append(list, idOffset)
        if not list then return end
        for i = 1, #list do
            local ind = list[i]
            local resolved = ns.BM2_ResolveSpells(ind)
            if #resolved > 0 then
                local v = bm2ViewCache[ind]
                if not v then v = {}; bm2ViewCache[ind] = v end
                for k in pairs(v) do v[k] = nil end
                for k, val in pairs(ind) do v[k] = val end
                v.spells = resolved
                -- Always explicit: the legacy nil-default (own-only TRUE)
                -- can't leak.
                v.ownOnly = ind.ownOnly == true
                v.ownOnlySpells = nil
                if idOffset then
                    if type(v.id) == "number" then v.id = v.id + idOffset end
                    if type(v.anchorTo) == "number" then v.anchorTo = v.anchorTo + idOffset end
                end
                out[#out + 1] = v
            end
        end
    end
    Append(inds, nil)
    Append(ownInds, 1000000)
    Append(allInds, 2000000)
    return out, specKey, "custom"
end

-------------------------------------------------------------------------------
-- Activation flag. ACTIVE: v2 runs INSIDE the legacy page shell (storage
-- accessor swap + Assigned Filters section + modal Filter Editor). Set false
-- and the runtime adapter and page redirect go inert, the legacy Buff Manager
-- (page + storage + Base Icons coexistence) runs untouched, and the
-- coexistence shims stay owned by the Debuff Manager file.
-------------------------------------------------------------------------------
ns.BM2_Enabled = true

-- Retirement overrides (simple grid off, indicators always on) apply only
-- while v2 is live: dormant v2 must not perturb the legacy coexistence.
if ns.BM2_Enabled then
    function ns.BM_BaseActive()
        return false
    end
    function ns.BM_CustomActive()
        return true
    end
end

-------------------------------------------------------------------------------
-- Cross-module filter bridge (parent-published): the ONE-TIME filter copies
-- between this library and Player Aura Bars ride it (both Filter Editors'
-- copy buttons). Absence of the table = this module (or v2) is off, and the
-- other side's button hides, so consumers must read it lazily at call time.
-- Mutators already Invalidate internally; Refresh repaints raid frames after
-- a copy lands new spell content here.
-------------------------------------------------------------------------------
if ns.BM2_Enabled then
    EllesmereUI._BM2FilterBridge = {
        Filters        = function() return ns.BM2_Filters() end,
        GetFilter      = function(id) return ns.BM2_GetFilter(id) end,
        AddFilter      = function(name) return ns.BM2_AddFilter(name) end,
        SetSpellState  = function(id, spellID, state) return ns.BM2_SetSpellState(id, spellID, state) end,
        AddCustomSpell = function(id, spellID) return ns.BM2_AddCustomSpell(id, spellID) end,
        PresetAlts     = function() return ns.BM2_PresetAlts end,
        CuratedSpells  = function(presetKey) return presetKey and DEFAULT_FILTER_SPELLS[presetKey] or nil end,
        Refresh        = function()
            if ns.BM2_Invalidate then ns.BM2_Invalidate() end
            if ns.ReloadFrames then ns.ReloadFrames() end
        end,
    }
end


