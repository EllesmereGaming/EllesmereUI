if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_PlayerAuraBars_Filters.lua
--
--  The custom bar store, the buff filters and their copies, the buff
--  manager import and the spec buckets.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._pabInternals
-- EllesmereUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not I or I.broken then return end
I.broken = true

local ExpandFamily, PAB, BuffBarHasContent = I.ExpandFamily, I.PAB, I.BuffBarHasContent

local ReloadAllCustomBars
I.reloadAllSetters[#I.reloadAllSetters + 1] = function(v) ReloadAllCustomBars = v end

-------------------------------------------------------------------------------
--  Custom bars (free bar creator)
--
--  Buffs: SpellID-based -- customBuffBars entries carry filters={[filterId]=true},
--  spells={id,...}, ownOnlySpells={[id]=bool}. Same shape and same
--  PAB_ResolveSpells() union the default Buffs bar uses: default Buffs and custom
--  Buff Bars are ONE model, not two. Rendering is one candidateFilters-restricted
--  GROUP into the bar's own dedicated container with a signature-gated rebuild (see
--  PAB_ReloadCustomBuffBar for why a group, not per-spell slots). This section is
--  the CRUD data layer; engine wiring is in EUI_PlayerAuraBars_CustomBars.lua.
--
--  Debuffs: category-based (same as RaidFrames) -- customDebuffBars entries carry
--  classFilters={[classKey]=true} and render through the EXISTING
--  BuildChain/ApplyGroupConfig path, no new engine machinery.
--
--  ID scheme mirrors ns.BM2_AddFilter: a single monotonically increasing counter,
--  never reused, so a deleted bar's engine-side declarations (ADD-ONLY on the
--  container) never collide with a later bar.
-------------------------------------------------------------------------------

-- Ensures db.profile.playerAuraBars exists before writing: PAB() alone is read-only
-- and may return nil, and `PAB() or {}` silently writes into a throwaway table that
-- never persists. Only CRUD (write) functions call this.
local function PABEnsure()
    local db = ns.db
    if not (db and db.profile) then return nil end
    db.profile.playerAuraBars = db.profile.playerAuraBars or {}
    return db.profile.playerAuraBars
end
-- WoW Forever: returns through the checked reader above, so a table created
-- here passes the one-time buff clear before anything writes to it.
if EllesmereUI.FvBW then
    PABEnsure = function()
        local db = ns.db
        if not (db and db.profile) then return nil end
        db.profile.playerAuraBars = db.profile.playerAuraBars or {}
        return PAB()
    end
end

local function NextBarId(s)
    s.nextBarId = (s.nextBarId or 1)
    local id = s.nextBarId
    s.nextBarId = id + 1
    return id
end

-------------------------------------------------------------------------------
--  Buff Filters (BM2-style named spell sets)
--
--  Global registry (db.profile.playerAuraBars.pabFilters), same shape as
--  RaidFrames' ns.BM2_Filters storage ({ nextId = 1, list = {} }), id/name/nextId
--  counter pattern mirrored 1:1. User-created filters are fully renameable/deletable;
--  the 10 curated presets imported via ns.PAB_ImportBM2Filters carry `f.preset = true`
--  and are NOT renameable or deletable (Filter Editor sidebar/detail-header guards).
--  Spell-level checkboxes stay editable in a preset -- only its name/existence is
--  protected.
--
--  Referenced by id from any buff-side cfg's `filters` table ([filterId]=true): the
--  default Buffs bar and every custom buff bar share ONE filter registry. Own-only
--  tracking (BM2's ownFilters/ownExtras) is NOT implemented here; bar.ownOnlySpells
--  stays reserved-but-unused.
-------------------------------------------------------------------------------

local function FilterStore(s)
    s.pabFilters = s.pabFilters or { nextId = 1, list = {} }
    return s.pabFilters
end

-- The filter list every picker and editor shows: the stored list itself, or,
-- on a client missing presets the other one offers, a fresh copy without them
-- (ns.PAB_OtherClientPreset).
function ns.PAB_Filters()
    local s = PAB()
    local store = s and s.pabFilters
    local list = store and store.list or nil
    if not list or next(ns.PAB_OTHER_ONLY_PRESETS) == nil then return list end
    local out = {}
    for i = 1, #list do
        if not ns.PAB_OtherClientPreset(list[i]) then out[#out + 1] = list[i] end
    end
    return out
end

-- Scans the stored list (no copy per lookup); nil for a preset only the other
-- client offers, so every resolver treats an assignment to it as a dangling id.
function ns.PAB_GetFilter(id)
    local s = PAB()
    local store = s and s.pabFilters
    local list = store and store.list
    if not list then return nil end
    for i = 1, #list do
        local f = list[i]
        if f.id == id then
            if ns.PAB_OtherClientPreset(f) then return nil end
            return f
        end
    end
end

-- Profiles travel between retail and WoW Forever. A preset filter only the
-- other client offers stays stored untouched (bars and states intact for the
-- next visit there) but is hidden here. Seeded filters carry the catalogue's
-- preset name, so the name identifies the preset.
function ns.PAB_OtherClientPreset(f)
    return f.preset and ns.PAB_OTHER_ONLY_PRESETS[f.name] or false
end

-- An id a preset filter keeps only for the other client: never shown or
-- resolved here, its stored state waits for that client. On WoW Forever that
-- is every id only the retail catalogue curates under the preset. On retail
-- it is an id the Forever seed added (f.foreverSeeded, see
-- ns.PAB_ImportBM2Filters) that retail does not curate there: a retail user
-- may add such an id by hand, so only the seed's own note tells them apart.
function ns.PAB_OtherClientSpell(f, id)
    local key = f.preset and ns.PAB_PRESET_KEY[f.name]
    if not key then return false end
    local here = EllesmereUI.BUFF_PRESET_IDS[key]
    if here and here[id] then return false end
    if EllesmereUI.IS_FOREVER == true then
        local other = EllesmereUI.BUFF_PRESET_OTHER_IDS[key]
        return (other and other[id]) == true
    end
    local m = f.foreverSeeded
    return (m and m[id]) == true
end

-- True for a stored filter id that belongs to a preset only the other client
-- offers (ns.PAB_GetFilter returns nil for it); false for every other id,
-- dangling ones included. Always false while this client offers every preset.
function ns.PAB_HiddenPresetFilter(id)
    if next(ns.PAB_OTHER_ONLY_PRESETS) == nil then return false end
    local s = PAB()
    local store = s and s.pabFilters
    local list = store and store.list
    if not list then return false end
    for i = 1, #list do
        if list[i].id == id then return ns.PAB_OtherClientPreset(list[i]) == true end
    end
    return false
end

function ns.PAB_AddFilter(name)
    local s = PABEnsure()
    if not s then return nil end
    local store = FilterStore(s)
    local f = { id = store.nextId, name = name or "New Filter", spells = {} }
    store.nextId = store.nextId + 1
    store.list[#store.list + 1] = f
    return f
end

function ns.PAB_RenameFilter(id, name)
    local f = ns.PAB_GetFilter(id)
    if f and name and name ~= "" then f.name = name end
end

-- Also strips the filter's assignment from every buff-side cfg that could reference
-- it: default Buffs bar + every custom buff bar (both lanes), plus the player UNIT
-- FRAME's buff filter lanes -- it shares this registry through its own keys
-- (buffFilters/buffNegFilters, see PlayerBuffChain in EUI_UnitFrames_AuraContainers.lua).
function ns.PAB_DeleteFilter(id)
    local s = PAB()
    if not (s and s.pabFilters) then return end
    local list = s.pabFilters.list
    for i = #list, 1, -1 do
        if list[i].id == id then table.remove(list, i) end
    end
    local function Strip(bar, isDefault)
        if bar.filters then bar.filters[id] = nil end
        if bar.negFilters then bar.negFilters[id] = nil end
        -- No-empty rule: deleting an ENABLED bar's last content source falls
        -- back to All Buffs, same as unchecking it in the Filters dropdown
        -- would. Disabled bars keep their stored state untouched (the
        -- EnsureBarEnable invariant).
        if bar.enabled ~= false and not BuffBarHasContent(bar, isDefault) then
            bar.showAllBuffs = nil
        end
    end
    if s.defaultBuffs then Strip(s.defaultBuffs, true) end
    local customBuffBars = s.customBuffBars
    if customBuffBars then
        for i = 1, #customBuffBars do
            Strip(customBuffBars[i], false)
        end
    end
    -- Editing-spec bucket bars share the same filter registry.
    if s.pabSpecBars then
        for _, b in pairs(s.pabSpecBars) do
            local bl = b.buffBars
            if bl then
                for i = 1, #bl do Strip(bl[i], false) end
            end
        end
    end
    local ps = ns.db and ns.db.profile and ns.db.profile.player
    if ps then
        if ps.buffFilters then ps.buffFilters[id] = nil end
        if ps.buffNegFilters then ps.buffNegFilters[id] = nil end
        -- Same fallback for the player frame's buff filter (shared registry).
        if ps.buffShowAll == false and ps.buffHasDuration ~= true
            and not (ps.buffFilters and next(ps.buffFilters))
            and not (ps.buffSpells and #ps.buffSpells > 0) then
            ps.buffShowAll = nil
        end
        -- The player FRAME's buff container resolves this registry through the
        -- UF reload pass, not through the PAB apply the caller runs.
        if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    end
end

-- Checkbox state for one spell within one filter. state=nil removes the spell
-- entirely: every PAB filter spell is "custom", no curated/preset spell to fall back to.
-- The write applies to the whole SAME-NAME FAMILY within the filter: PAB flattens
-- curated alternates into their own keys, and the Filter Editor shows one row per
-- NAME (lowest id), so a click on the visible row must carry the hidden alternates
-- with it -- otherwise a disabled-seeded family like Divine Hymn (64843 + alt
-- 64844) checks only the primary while the buff that actually lands is the alt
-- (field report 2026-08-16: "64844 not tracked"). Name-matching mirrors the
-- editor's dedup exactly (both fall back to the id when the name is uncached).
-- Ids kept only for the other client (ns.PAB_OtherClientSpell) are never
-- rewritten from here.
function ns.PAB_SetSpellState(filterId, spellID, state)
    local f = ns.PAB_GetFilter(filterId)
    if not f then return end
    local function Write(id)
        if state == nil then
            f.spells[id] = nil
        else
            f.spells[id] = state and true or false
        end
    end
    Write(spellID)
    -- Members of a curated family follow the clicked row, deletes included: the editor
    -- shows one row per NAME, so a member under a different name has a row of its own
    -- but is still the same buff, and would otherwise linger as a tracked id with no
    -- row left to clear it from. Only ids the filter already holds are rewritten.
    local fam = ns.PAB_SPELL_FAMILY and ns.PAB_SPELL_FAMILY[spellID]
    if fam then
        for i = 1, #fam do
            if fam[i] ~= spellID and f.spells[fam[i]] ~= nil
                and not ns.PAB_OtherClientSpell(f, fam[i]) then Write(fam[i]) end
        end
    end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if name then
        for id in pairs(f.spells) do
            if id ~= spellID and not ns.PAB_OtherClientSpell(f, id)
                and C_Spell.GetSpellName(id) == name then Write(id) end
        end
    end
end

-- On retail, a Forever-seeded id kept inert here (ns.PAB_OtherClientSpell)
-- counts as absent, and every add drops the id's seed note (one can outlive
-- its id after a delete): the added id is an ordinary row on both clients.
function ns.PAB_AddSpellToFilter(filterId, spellID)
    local f = ns.PAB_GetFilter(filterId)
    if not (f and spellID and spellID > 0) then return false end
    local m = EllesmereUI.IS_FOREVER ~= true and f.foreverSeeded or nil
    if f.spells[spellID] ~= nil and not (m and ns.PAB_OtherClientSpell(f, spellID)) then
        return false -- already present
    end
    if m then m[spellID] = nil end
    f.spells[spellID] = true
    return true
end

-- Union of a buff-side cfg's direct spells (cfg.spells) and the enabled spells of
-- every filter it references (cfg.filters), minus own-only tracking (see above).
-- Sorted so the caller's signature diffing stays deterministic.
function ns.PAB_ResolveSpells(cfg)
    local set = {}
    local direct
    local spells = cfg.spells
    if spells then
        direct = {}
        for i = 1, #spells do
            set[spells[i]] = true
            direct[spells[i]] = true
            ExpandFamily(direct, spells[i])
            ExpandFamily(set, spells[i])
        end
    end
    -- Under the broad modes (All Buffs / Has Duration) the hide-lane filters leave via
    -- the catch-all's excludeSpellIDs (see BuffBarChain), so the spells group carries
    -- only Extra Spells there. In add mode the show-lane filters union in, minus the
    -- hide lane. Extra Spells stay additive in both modes and win over the hide lane.
    local addMode = cfg.showAllBuffs == false and cfg.hasDuration ~= true
    local filters = addMode and cfg.filters or nil
    if filters then
        for filterId in pairs(filters) do
            local f = ns.PAB_GetFilter(filterId)
            if f then
                for id, on in pairs(f.spells) do
                    if on and not ns.PAB_OtherClientSpell(f, id) then
                        set[id] = true
                        ExpandFamily(set, id, f.spells)
                    end
                end
            end
        end
    end
    local negFilters = addMode and cfg.negFilters or nil
    if negFilters then
        local hide = {}
        for filterId in pairs(negFilters) do
            local f = ns.PAB_GetFilter(filterId)
            if f then
                for id, on in pairs(f.spells) do
                    if on and not ns.PAB_OtherClientSpell(f, id) then
                        hide[id] = true
                        ExpandFamily(hide, id, f.spells)
                    end
                end
            end
        end
        for id in pairs(hide) do
            if not (direct and direct[id]) then set[id] = nil end
        end
    end
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

-------------------------------------------------------------------------------
--  One-time filter copies between this registry and the Raid Frames Buff
--  Manager library (via the parent-published EllesmereUI._BM2FilterBridge --
--  absent when that module is disabled, and both editor buttons hide). The
--  registries stay fully independent: a copy matches filters by NAME in the
--  TARGET's own id space (missing filters are created, same-named ones have
--  their spell content replaced), so no assignment on either side ever needs
--  remapping and nothing stays linked afterward.
-------------------------------------------------------------------------------

local function NameToId(list)
    local m = {}
    for i = 1, #list do
        local f = list[i]
        if m[f.name] == nil then m[f.name] = f.id end
    end
    return m
end

-- "Copy Raid & Party Filters" (our Filter Editor): one-time copy of the Buff
-- Manager library into this registry. The library stores curated PRIMARY ids
-- and expands talent/rank alternates at resolution; this registry flattens
-- alternates into their own keys (seed convention), so each copied primary
-- fans out to its alternates with the same state.
function ns.PAB_CopyBM2FiltersIn()
    local br = EllesmereUI._BM2FilterBridge
    local s = PABEnsure()
    if not (br and s) then return false end
    local src = br.Filters() or {}
    local altsMap = br.PresetAlts and br.PresetAlts() or nil
    local nameToId = NameToId(FilterStore(s).list)
    for i = 1, #src do
        local sf = src[i]
        local tid = nameToId[sf.name]
        local tf = tid and ns.PAB_GetFilter(tid)
        if not tf then
            tf = ns.PAB_AddFilter(sf.name)
        end
        if tf then
            local spells = {}
            for id, on in pairs(sf.spells) do
                -- Ids the library keeps only for the other client are not
                -- this client's to copy.
                if not br.OtherClientSpell(sf, id) then
                    local state = on and true or false
                    spells[id] = state
                    local a = altsMap and altsMap[id]
                    if a then
                        for j = 1, #a do spells[a[j]] = state end
                    end
                end
            end
            -- Retail: a copied id is the library's live content, no longer a
            -- Forever-seed note.
            local m = tf.foreverSeeded
            if m and EllesmereUI.IS_FOREVER ~= true then
                for id in pairs(spells) do m[id] = nil end
            end
            -- The copy overwrites what this editor shows; ids kept only for
            -- the other client are not shown, so they stay.
            for id, on in pairs(tf.spells) do
                if spells[id] == nil and ns.PAB_OtherClientSpell(tf, id) then spells[id] = on end
            end
            tf.spells = spells
        end
    end
    -- The player FRAME's buff container resolves this registry through the UF
    -- reload pass, not through the PAB apply the caller runs.
    if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    return true
end

-- "Copy Player Auras Filters" (Buff Manager side): one-time copy of this
-- registry's filter setups INTO the Buff Manager library by name -- same-
-- named filters take our spell states wholesale, missing filters are created.
-- Library ids never change, so indicator assignments and banked spec-override
-- forks stay valid.
function ns.PAB_CopyOwnFiltersIntoBM2()
    local br = EllesmereUI._BM2FilterBridge
    local s = PAB()
    if not (br and s) then return false end
    -- Alt id -> primary: our registry flattens talent/rank alternates into
    -- their own keys; the Buff Manager library stores primaries and expands
    -- alternates at resolution, so alternates fold onto their primary here.
    local altToPrimary = {}
    local altsMap = br.PresetAlts and br.PresetAlts() or nil
    if altsMap then
        for primary, alts in pairs(altsMap) do
            for i = 1, #alts do altToPrimary[alts[i]] = primary end
        end
    end
    -- Presets only the other client offers stay out (ns.PAB_Filters' view).
    local own = ns.PAB_Filters() or FilterStore(s).list
    local nameToId = NameToId(br.Filters() or {})
    for i = 1, #own do
        local of = own[i]
        local tid = nameToId[of.name]
        if not tid then
            local nf = br.AddFilter(of.name)
            tid = nf and nf.id
        end
        local tf = tid and br.GetFilter(tid)
        if tf then
            local desired = {}
            for id, on in pairs(of.spells) do
                -- Ids kept only for the other client are not this client's to copy.
                if not ns.PAB_OtherClientSpell(of, id) then
                    local p = altToPrimary[id]
                    if p then
                        -- Primary's own explicit state wins over an alternate's.
                        if of.spells[p] == nil and desired[p] == nil then desired[p] = on and true or false end
                    else
                        desired[id] = on and true or false
                    end
                end
            end
            local curated = tf.preset and br.CuratedSpells and br.CuratedSpells(tf.preset) or nil
            for id, on in pairs(desired) do
                -- An id the library keeps only for the other client counts as
                -- absent (BM2_AddCustomSpell takes it over).
                if (tf.spells[id] == nil or br.OtherClientSpell(tf, id))
                    and not (curated and curated[id]) then
                    -- New non-curated id must carry the custom marker or the
                    -- library's curation prune strips it on the next merge.
                    br.AddCustomSpell(tid, id)
                end
                br.SetSpellState(tid, id, on)
            end
            -- Our version is authoritative: ids we don't carry go unchecked
            -- (false, not nil -- a nil curated id gets re-seeded to its
            -- default) and foreign custom ids are removed. Ids the library
            -- keeps only for the other client are left as they are.
            for id in pairs(tf.spells) do
                if desired[id] == nil and not br.OtherClientSpell(tf, id) then
                    if tf.custom and tf.custom[id] then
                        br.SetSpellState(tid, id, nil)
                    else
                        br.SetSpellState(tid, id, false)
                    end
                end
            end
        end
    end
    br.Refresh()
    return true
end

-- Parent-published counterpart of _BM2FilterBridge: lets the Buff Manager's
-- Filter Editor drive its one-time copy from its side. Absent = this module
-- is disabled, and its button hides.
EllesmereUI._PABFilterBridge = {
    CopyIntoBM2 = function() return ns.PAB_CopyOwnFiltersIntoBM2() end,
}

function ns.PAB_CustomBuffBars()
    local s = PAB()
    return s and s.customBuffBars or nil
end

-------------------------------------------------------------------------------
-- Buff Manager filter import: the 10 curated preset filters (Defensives, Raid CDs,
--  Externals, Core/Lesser Healing Buffs, Support, Offensive CDs, Movement, Utility,
--  Consumables) as a starting point for PAB Filters.
--
--  Both tables below derive AT LOAD from the parent's canonical
--  EllesmereUI.BUFF_PRESETS catalogue (EllesmereUI_BuffPresets.lua -- THE
--  single curation source, bound directly by the RF Buff Manager, so the two
--  systems can never drift). PAB flattens `alts` into their own rows (PAB
--  Filters have no primary/alt grouping: every id is its own checkbox row);
--  alts inherit their primary's disabled state and class hint. `disabled`
--  entries import unchecked here too. One pass over ~250 entries at load.
-------------------------------------------------------------------------------

-- Display-only hint: which class a curated (imported) spell belongs to, so the
-- Filter Editor can group/color rows. Purely cosmetic -- PAB_ResolveSpells/
-- PAB_SetSpellState never consult it; a filter's spells are always a flat {id=bool}
-- set. "ALL"-class spells get no hint (no class header row for them).
local SPELL_CLASS_HINTS = {}
local BM2_FILTER_SEED = {}
-- Curated primary -> alts (own copy: the RF bridge is absent when that
-- module is disabled, and the family heal below must not depend on it).
local PRESET_ALTS = {}
do
    local BP = EllesmereUI.BUFF_PRESETS
    for i = 1, #BP.filters do
        local def = BP.filters[i]
        local list = BP.spells[def.key]
        local enabled, disabled = {}, {}
        if list then
            for id, info in pairs(list) do
                local dst = info.disabled and disabled or enabled
                dst[#dst + 1] = id
                if info.class ~= "ALL" then SPELL_CLASS_HINTS[id] = info.class end
                if info.alts then
                    PRESET_ALTS[id] = info.alts
                    for j = 1, #info.alts do
                        local alt = info.alts[j]
                        dst[#dst + 1] = alt
                        if info.class ~= "ALL" then SPELL_CLASS_HINTS[alt] = info.class end
                    end
                end
            end
        end
        table.sort(enabled)
        table.sort(disabled)
        BM2_FILTER_SEED[#BM2_FILTER_SEED + 1] =
            { key = def.key, name = def.name, enabled = enabled, disabled = disabled }
    end
    -- Every member of a curated family (primary + its alternates) maps to the whole
    -- member list, so PAB_ResolveSpells can expand from whichever id the user has.
    -- Families are disjoint, so one carried by two preset filters rewrites an equal entry.
    local fams = {}
    for primary, alts in pairs(PRESET_ALTS) do
        local fam = { primary }
        for i = 1, #alts do fam[#fam + 1] = alts[i] end
        for i = 1, #fam do fams[fam[i]] = fam end
    end
    ns.PAB_SPELL_FAMILY = fams
    -- Preset name -> key across both clients' catalogues, and the names of the
    -- presets only the other client offers (ns.PAB_OtherClientPreset,
    -- ns.PAB_OtherClientSpell): seeded filters carry the catalogue's name.
    local keyByName, offered, otherOnly = {}, {}, {}
    for i = 1, #BP.filters do
        keyByName[BP.filters[i].name] = BP.filters[i].key
        offered[BP.filters[i].key] = true
    end
    local other = EllesmereUI.BUFF_PRESET_OTHER_FILTERS
    for i = 1, #other do
        local def = other[i]
        if keyByName[def.name] == nil then keyByName[def.name] = def.key end
        if not offered[def.key] then otherOnly[def.name] = true end
    end
    ns.PAB_PRESET_KEY = keyByName
    ns.PAB_OTHER_ONLY_PRESETS = otherOnly
end
ns.PAB_SPELL_CLASS_HINTS = SPELL_CLASS_HINTS

-- PAB_ImportBM2Filters (below) is idempotent: it skips any seed entry whose exact
-- name already exists, so re-clicking Import creates no duplicates, and returns the
-- number of filters actually created.
--
-- PAB_AllPresetSpells returns every spell ID across all 10 curated presets (enabled
-- AND disabled entries both count). Because BM2_FILTER_SEED already has `alts`
-- flattened into its lists, this is a superset of what BM2_AllPresetSpells returns --
-- intended, alts ARE valid trackable buff IDs.
function ns.PAB_AllPresetSpells()
    local set = {}
    for i = 1, #BM2_FILTER_SEED do
        local seed = BM2_FILTER_SEED[i]
        for j = 1, #seed.enabled do set[seed.enabled[j]] = true end
        for j = 1, #seed.disabled do set[seed.disabled[j]] = true end
    end
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

function ns.PAB_ImportBM2Filters()
    local byName = {}
    local list = ns.PAB_Filters() or {}
    for i = 1, #list do byName[list[i].name] = list[i] end

    -- WoW Forever: every id this seed adds that the retail catalogue does not
    -- curate under the preset is noted on the filter (f.foreverSeeded), so
    -- retail keeps it inert when the profile goes back there
    -- (ns.PAB_OtherClientSpell). Nothing is noted on retail.
    local retailIds = EllesmereUI.IS_FOREVER == true and EllesmereUI.BUFF_PRESET_OTHER_IDS or nil
    local function NoteSeed(f, key, id)
        if not retailIds then return end
        local cur = retailIds[key]
        if cur and cur[id] then return end
        local m = f.foreverSeeded
        if not m then m = {}; f.foreverSeeded = m end
        m[id] = true
    end

    local created = 0
    for i = 1, #BM2_FILTER_SEED do
        local seed = BM2_FILTER_SEED[i]
        local f = byName[seed.name]
        if not f then
            f = ns.PAB_AddFilter(seed.name)
            if f then
                for j = 1, #seed.enabled do f.spells[seed.enabled[j]] = true end
                for j = 1, #seed.disabled do f.spells[seed.disabled[j]] = false end
                if retailIds then
                    for j = 1, #seed.enabled do NoteSeed(f, seed.key, seed.enabled[j]) end
                    for j = 1, #seed.disabled do NoteSeed(f, seed.key, seed.disabled[j]) end
                end
                created = created + 1
            end
        end
        -- Runs every call, not just on fresh creation, so filters the idempotent-by-name
        -- skip would otherwise leave unflagged forever still get the protection flag.
        if f then
            f.preset = true
            -- Additive curation merge (mirrors BM2's EnsureFilters): curated ids
            -- NEW since this filter was created join it with their seed state;
            -- ids the user already has (either state) are never overwritten.
            -- No prune counterpart: PAB has no custom-vs-curated marker, so
            -- removing non-seed ids would delete user additions.
            for j = 1, #seed.enabled do
                local id = seed.enabled[j]
                if f.spells[id] == nil then f.spells[id] = true; NoteSeed(f, seed.key, id) end
            end
            for j = 1, #seed.disabled do
                local id = seed.disabled[j]
                if f.spells[id] == nil then f.spells[id] = false; NoteSeed(f, seed.key, id) end
            end
            -- Family heal: a checked PRIMARY whose curated alternates were left
            -- unchecked (the pre-fix editor toggled only the visible row) pulls
            -- its alternates up. Enable-only, primary->alt only, curated
            -- families only: never disables, never touches user-added ids.
            for primary, alts in pairs(PRESET_ALTS) do
                if f.spells[primary] == true then
                    for k = 1, #alts do
                        if f.spells[alts[k]] == false then f.spells[alts[k]] = true end
                    end
                end
            end
        end
    end
    return created
end

function ns.PAB_CustomDebuffBars()
    local s = PAB()
    return s and s.customDebuffBars or nil
end

-- Both lookups search the legacy array first, then every editing-spec
-- bucket (ids are globally unique). Second return = the owning bucket key
-- ("allspecs" for the legacy array) for callers that gate on applicability.
function ns.PAB_GetCustomBuffBar(id)
    local list = ns.PAB_CustomBuffBars()
    if list then
        for i = 1, #list do
            if list[i].id == id then return list[i], "allspecs" end
        end
    end
    local s = PAB()
    local st = s and s.pabSpecBars
    if st then
        for key, b in pairs(st) do
            local bl = b.buffBars
            if bl then
                for i = 1, #bl do
                    if bl[i].id == id then return bl[i], key end
                end
            end
        end
    end
end

function ns.PAB_GetCustomDebuffBar(id)
    local list = ns.PAB_CustomDebuffBars()
    if list then
        for i = 1, #list do
            if list[i].id == id then return list[i], "allspecs" end
        end
    end
    local s = PAB()
    local st = s and s.pabSpecBars
    if st then
        for key, b in pairs(st) do
            local bl = b.debuffBars
            if bl then
                for i = 1, #bl do
                    if bl[i].id == id then return bl[i], key end
                end
            end
        end
    end
end

-- Bar objects (both kinds) also carry the same shared+category cfg fields as
-- DefaultBuffsCfg/DefaultDebuffsCfg (iconSize, durationShow/stackShow,
-- durationPosition/TextSize/OffsetX/Y/ColorR/G/B, stackPosition/TextSize/OffsetX/
-- Y/ColorR/G/B; buff/debuff bars additionally borderSize/R/G/B/A, borderTexture and
-- optional texture offset/shift/layer fields, iconZoom, padding,
-- iconsPerRow, maxRows, maxTotal; debuff bars additionally dispelColorMagic/Curse/
-- Disease/Poison/Bleed). NOT pre-populated, same as those two starting as {}:
-- BuildStyle/ComputeGrid apply the same `or <default>` fallbacks either way, so a
-- fresh bar renders with sane defaults and Options only writes fields the user touches.
function ns.PAB_AddCustomBuffBar(name, bucketKey)
    local s = PABEnsure()
    if not s then return nil end
    s.customBuffBars = s.customBuffBars or {}
    local bar = {
        id = NextBarId(s),
        name = name or "New Buff Bar",
        enabled = true,
        filters = {},         -- [filterId] = true (BM2-style assigned filters)
        spells = {},           -- {spellID, ...} direct/custom spells
        ownOnlySpells = {},    -- [spellID] = bool
        growDirection = "LEFT",
        -- Starting grid: a compact single row, deliberately distinct from the default
        -- bars' ComputeGrid fallback (11x3 for buffs) -- a fresh custom bar starts
        -- small rather than inheriting the larger grid.
        iconsPerRow = 8,
        maxRows = 1,
        maxTotal = 8,
    }
    -- The edited editing-spec bucket owns the new bar; ids come from the ONE
    -- shared counter regardless of bucket.
    local target = ns.PAB_BucketBars(true, bucketKey, true) or s.customBuffBars
    target[#target + 1] = bar
    return bar
end

function ns.PAB_AddCustomDebuffBar(name, bucketKey)
    local s = PABEnsure()
    if not s then return nil end
    s.customDebuffBars = s.customDebuffBars or {}
    local bar = {
        id = NextBarId(s),
        name = name or "New Debuff Bar",
        enabled = true,
        classFilters = {},    -- [classKey] = true, same vocabulary as BuildChain
        growDirection = "LEFT",
        -- Same starting-grid reasoning as PAB_AddCustomBuffBar above.
        iconsPerRow = 8,
        maxRows = 1,
        maxTotal = 8,
    }
    local target = ns.PAB_BucketBars(false, bucketKey, true) or s.customDebuffBars
    target[#target + 1] = bar
    return bar
end

-- Deletion only strips the DB entry; it deliberately does NOT remove the bar's
-- engine-side group/slots (containers are add-only). The engine-wiring layer must
-- instead detect the missing DB entry and set maxFrameCount = 0 / hide the bar's
-- frames, like disabled default groups.
-- Deep-copies a custom bar into another editing-spec bucket (the right-click
-- "Add To" menu): full settings clone -- position included -- under a fresh
-- global id; the source is untouched.
function ns.PAB_CopyCustomBar(isBuff, src, bucketKey)
    local s = PABEnsure()
    if not (s and src) then return nil end
    local target = ns.PAB_BucketBars(isBuff, bucketKey, true)
    if not target then return nil end
    local bar = CopyTable(src)
    bar.id = NextBarId(s)
    target[#target + 1] = bar
    return bar
end

-- Shared by both deletes: strip the id from every editing-spec bucket and
-- sweep its per-spec disable keys (ids are global and never reused, so a
-- deleted bar's key could only leak).
local function DeleteFromSpecBuckets(s, id, listField)
    local st = s.pabSpecBars
    if not st then return end
    for _, b in pairs(st) do
        local bl = b[listField]
        if bl then
            for i = #bl, 1, -1 do
                if bl[i].id == id then table.remove(bl, i) end
            end
        end
        if b.inhDis then b.inhDis[id] = nil end
    end
end

function ns.PAB_DeleteCustomBuffBar(id)
    local s = PABEnsure()
    if not s then return end
    -- WoW Forever: a delete can empty the bucket the player's class renders
    -- (its bars, or the per-spec disables the sweep clears), which moves it
    -- to the next class spec with data (ns.PAB_ForeverSpecID); a move
    -- re-drives every custom bar once.
    local fvSid = EllesmereUI.IS_FOREVER and ns.PAB_ForeverSpecID() or nil
    if s.customBuffBars then
        for i = #s.customBuffBars, 1, -1 do
            if s.customBuffBars[i].id == id then table.remove(s.customBuffBars, i) end
        end
    end
    DeleteFromSpecBuckets(s, id, "buffBars")
    if fvSid and ns.PAB_ForeverSpecID() ~= fvSid then ReloadAllCustomBars() end
end

function ns.PAB_DeleteCustomDebuffBar(id)
    local s = PABEnsure()
    if not s then return end
    -- WoW Forever: same bucket-move check as ns.PAB_DeleteCustomBuffBar.
    local fvSid = EllesmereUI.IS_FOREVER and ns.PAB_ForeverSpecID() or nil
    if s.customDebuffBars then
        for i = #s.customDebuffBars, 1, -1 do
            if s.customDebuffBars[i].id == id then table.remove(s.customDebuffBars, i) end
        end
    end
    DeleteFromSpecBuckets(s, id, "debuffBars")
    if fvSid and ns.PAB_ForeverSpecID() ~= fvSid then ReloadAllCustomBars() end
end

-------------------------------------------------------------------------------
--  Editing-spec buckets. The legacy arrays (s.customBuffBars /
--  s.customDebuffBars) ARE the "All Specs" bucket, in place: zero migration,
--  and profiles opened by older builds keep rendering them. Every other
--  bucket lives under s.pabSpecBars[key] = { buffBars, debuffBars, inhDis },
--  key = "nonhealer"/"tanks"/"dps"/"healers" (group buckets) or "spec<ID>"
--  (a concrete spec; healer specs included). Bar ids stay globally unique
--  across buckets (the one shared s.nextBarId), so per-spec disables key on
--  the bare id. Absent pabSpecBars = feature unused = every path below
--  degenerates to the legacy behavior at zero cost.
-------------------------------------------------------------------------------

-- Role group for a specialization ID. Mirrors the RaidFrames helper
-- (ns.BM_RoleBucketForSpecID lives in a different addon namespace, hence a
-- local twin): healers/Aug = HEALER role or Augmentation (1473), keeping
-- "All Non Healers/Aug" its exact complement.
local function RoleBucketForSpecID(specID)
    -- WoW Forever specs carry no role (same rule as the RaidFrames twin).
    if EllesmereUI.IS_FOREVER then return nil end
    if not specID then return nil end
    if specID == 1473 then return "healers" end
    local role = GetSpecializationInfoByID and select(5, GetSpecializationInfoByID(specID))
    if role == "HEALER" then return "healers" end
    if role == "TANK" then return "tanks" end
    if role then return "dps" end
    -- Unknown spec/unavailable API: no role bucket beats a wrong one.
    return nil
end
ns.PAB_RoleBucketForSpecID = RoleBucketForSpecID

local function CurrentSpecID()
    -- WoW Forever: the retail spec the player's class acts as.
    if EllesmereUI.IS_FOREVER then return ns.PAB_ForeverSpecID() end
    local idx = GetSpecialization and GetSpecialization()
    return idx and GetSpecializationInfo and GetSpecializationInfo(idx) or nil
end

-- Group buckets a concrete "spec<ID>" view inherits from, in display order.
-- nil for group views and unknown keys.
function ns.PAB_InheritedGroupsFor(bucketKey)
    local m = type(bucketKey) == "string" and bucketKey:match("^spec(%d+)$")
    local sid = m and tonumber(m)
    if not sid then return nil end
    -- WoW Forever has no spec roles: a class view inherits All Specs only.
    if EllesmereUI.IS_FOREVER then return { "allspecs" } end
    local out = { "allspecs" }
    local roleKey = RoleBucketForSpecID(sid)
    if roleKey ~= "healers" then out[#out + 1] = "nonhealer" end
    if roleKey then out[#out + 1] = roleKey end
    return out
end

local function SpecBarBucket(s, key, create)
    local st = s.pabSpecBars
    if not st then
        if not create then return nil end
        st = {}; s.pabSpecBars = st
    end
    local b = st[key]
    if not b then
        if not create then return nil end
        b = { buffBars = {}, debuffBars = {}, inhDis = {} }
        st[key] = b
    end
    b.buffBars = b.buffBars or {}
    b.debuffBars = b.debuffBars or {}
    b.inhDis = b.inhDis or {}
    return b
end

-- WoW Forever: a class acts as the first of its retail specs (class order)
-- whose "spec<ID>" bucket holds data (buff bars, debuff bars or per-spec
-- disables of All Specs bars), else its first spec. token nil = the player's
-- class. Resolved per reload / page build / removal, never per frame.
function ns.PAB_BucketHasData(id, st)
    local b = st and st["spec" .. id]
    if b == nil then return false end
    if (b.buffBars and #b.buffBars > 0) or (b.debuffBars and #b.debuffBars > 0) then return true end
    local dis = b.inhDis
    if not (dis and next(dis) ~= nil) then return false end
    if not EllesmereUI.IS_FOREVER then return true end
    -- WoW Forever renders All Specs and the class's own bucket only, so only
    -- a disable of an All Specs bar counts. Scans the bar arrays in place.
    local s = PAB()
    local list = s and s.customBuffBars
    for i = 1, (list and #list or 0) do
        if dis[list[i].id] then return true end
    end
    list = s and s.customDebuffBars
    for i = 1, (list and #list or 0) do
        if dis[list[i].id] then return true end
    end
    return false
end
function ns.PAB_ForeverSpecID(token)
    local s = PAB()
    return EllesmereUI.ForeverClassSpec(token, ns.PAB_BucketHasData, s and s.pabSpecBars)
end
-- The bucket a Forever class row edits: the one that class renders.
function ns.PAB_ForeverKey(token)
    local sid = ns.PAB_ForeverSpecID(token)
    return sid and ("spec" .. sid) or nil
end

-- Bucket bar array for an EDITED view ("allspecs"/nil = the legacy arrays).
function ns.PAB_BucketBars(isBuff, key, create)
    local s = create and PABEnsure() or PAB()
    if not s then return nil end
    if not key or key == "allspecs" then
        if isBuff then
            if create then s.customBuffBars = s.customBuffBars or {} end
            return s.customBuffBars
        end
        if create then s.customDebuffBars = s.customDebuffBars or {} end
        return s.customDebuffBars
    end
    local b = SpecBarBucket(s, key, create)
    if not b then return nil end
    if isBuff then return b.buffBars end
    return b.debuffBars
end

-- Per-spec disable of a GROUP bucket's bar, stored on the viewing spec's
-- concrete "spec<ID>" bucket (ids are global, the bare id suffices).
function ns.PAB_InhDisabled(concreteKey, id)
    local s = PAB()
    local b = s and SpecBarBucket(s, concreteKey, false)
    return (b and b.inhDis and b.inhDis[id]) and true or false
end

function ns.PAB_SetInhDisabled(concreteKey, id, disabled)
    local s = PABEnsure()
    if not (s and concreteKey and id) then return end
    -- WoW Forever: clearing the last per-spec disable can move the bucket
    -- the player's class renders (see ns.PAB_DeleteCustomBuffBar).
    local fvSid = EllesmereUI.IS_FOREVER and ns.PAB_ForeverSpecID() or nil
    local b = SpecBarBucket(s, concreteKey, true)
    b.inhDis[id] = disabled and true or nil
    if fvSid and ns.PAB_ForeverSpecID() ~= fvSid then ReloadAllCustomBars() end
end

-- Does bucketKey's content render for the given spec?
local function BucketApplies(bucketKey, sid)
    if not bucketKey or bucketKey == "allspecs" then return true end
    local m = bucketKey:match("^spec(%d+)$")
    if m then return sid == tonumber(m) end
    -- WoW Forever has no spec roles: no group bucket applies there.
    if EllesmereUI.IS_FOREVER then return false end
    if not sid then return false end
    local roleKey = RoleBucketForSpecID(sid)
    if bucketKey == "nonhealer" then return roleKey ~= "healers" end
    return bucketKey == roleKey
end

-- Render verdict for a custom bar: the MODULE is on (Disable All is a full
-- stand-down, custom bars included -- the field bug was custom bars
-- lingering), the bar's own toggle is on, its owning bucket applies to the
-- CURRENT spec, and (group buckets, All Specs included) this spec hasn't
-- per-spec disabled it. bucketKey nil = legacy = "allspecs".
function ns.PAB_BarActive(bar, bucketKey)
    if not bar or bar.enabled == false then return false end
    local sMaster = PAB()
    if not sMaster or sMaster.enabled ~= true then return false end
    local sid = CurrentSpecID()
    if not BucketApplies(bucketKey, sid) then return false end
    local isOwn = bucketKey and bucketKey:match("^spec%d") and true or false
    if not isOwn and sid then
        local s = PAB()
        local con = s and s.pabSpecBars and s.pabSpecBars["spec" .. sid]
        if con and con.inhDis and con.inhDis[bar.id] then return false end
    end
    return true
end

I.broken = false
