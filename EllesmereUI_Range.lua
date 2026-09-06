if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Range.lua
--  Shared range-check engine for the suite's range consumers:
--    - Nameplates "Distance to Target Text"  (spell-ladder lower bound)
--    - Nameplates "Out of Range Alpha"       (class/spec cutoff probes)
--    - QoL "Target Distance Text"            (item bracket or spell lower bound)
--    - QoL crosshair out-of-range recolor    (cutoff probes + item fallback)
--
--  One spellbook ladder, one harm-item table, one set of invalidation events.
--  Everything is built lazily and the events are registered only while at
--  least one consumer has declared itself active (Range_SetActive), so the
--  engine costs nothing while every range feature is disabled. When several
--  features are enabled at once they share a single ladder build and a short
--  per-tick result cache, so the same question is never answered twice in
--  the same window.
--
--  No direct distance API exists for enemies, so everything here is inferred
--  from in-range answers: the player's own harmful spellbook spells (checked
--  live, so talent range extensions are reflected automatically) and a ladder
--  of fixed-range harm items.
-------------------------------------------------------------------------------
if not EllesmereUI then return end
if EllesmereUI.Range_SetActive then return end -- already loaded

local GetTime = GetTime

-- Fixed-range harm items for the item bracket. Desired display buckets:
--   1-10: 1 yd steps -- 10-50: 5 yd -- 50-80: 10 yd -- then 80+.
-- Yards with no reliable item (1, 6, 9) are omitted; neighboring checks form
-- the bracket. Multi-id rungs: any one answering suffices (some items are
-- invalid on some clients).
local RANGE_ITEMS = {
    { range = 2,  ids = { 37727, 168948, 194718 } }, -- Ruby Acorn / Dried Kelp / Salamander Feed
    { range = 3,  ids = { 42732, 200469 } },         -- Everfrost Razor / Khadgar's Rod
    { range = 4,  id  = 129055 },                    -- Shoe Shine Kit
    { range = 5,  ids = { 8149, 136605, 63427 } },   -- Voodoo Charm / Solendra's / Worgsaw
    { range = 7,  id  = 61323 },                     -- Ruby Seeds
    { range = 8,  ids = { 34368, 33278 } },          -- Attuned Crystal Cores / Burning Torch
    { range = 10, ids = { 32321, 17626, 10699 } },   -- Sparrowhawk Net / Frostwolf Muzzle / Yeh'kinya's
    { range = 15, ids = { 33069, 31129 } },          -- Sturdy Rope / Blackwhelp Net
    { range = 20, ids = { 10645, 21519 } },          -- Gnomish Death Ray / Mistletoe
    { range = 25, ids = { 13289, 24268, 41509, 31463 } },
    { range = 30, ids = { 17202, 835, 7734, 34191 } },
    { range = 35, ids = { 18904, 24269 } },
    { range = 40, ids = { 28767, 18640 } },          -- Decapitator / Happy Fun Rock
    { range = 45, ids = { 32698, 23836 } },          -- Wrangling Rope / Goblin Rocket Launcher
    { range = 50, id  = 116139 },                    -- Haunting Memento
    { range = 60, ids = { 32825, 37887 } },          -- Soul Cannon / Seeds of Nature's Wrath
    { range = 70, id  = 41265 },                     -- Eyesore Blaster
    { range = 80, id  = 35278 },                     -- Reinforced Net
}

local RG = {
    ladder = {},       -- ascending { range = yds, spells = { sid, ... } }
    ladderBuilt = false,
    dirty = false,
    active = {},       -- consumer key -> true
    activeCount = 0,
    evt = nil,         -- invalidation event frame (created on first activation)
    probeCutoff = nil, -- cutoff the cached probe list below was built for
    probes = {},       -- crosshair probe spells, longest range first
}

-- Some harmful spells answer nil on IsSpellInRange (ground-target only,
-- conditionally castable), so each rung keeps a few spares to stay
-- answerable instead of deduping to a single spell per range.
local MAX_SPELLS_PER_RUNG = 3
local MAX_PROBE_SPELLS = 4

-- Micro result cache: one slot per query shape. The TTL sits under every
-- consumer tick interval (0.15s / 0.2s), so concurrent features share one
-- walk per window while successive ticks of a single feature stay live.
local CACHE_TTL = 0.1
local lbCache = { unit = nil, t = 0, has = false, v = nil }
local brCache = { unit = nil, stop = nil, t = 0, has = false, mn = nil, mx = nil }

local function ResetCaches()
    lbCache.has = false
    brCache.has = false
    RG.probeCutoff = nil
end

local DRUID_MELEE_FORMS = { [1] = true, [2] = true } -- Bear, Cat

-- Spec-derived attack cutoff, form check NOT included (that is the one live
-- input; everything here only moves on spec/talent changes and is cached by
-- Range_GetAttackCutoff below).
local function SpecAttackCutoff(holyPaladinMelee)
    local _, classFile = UnitClass("player")
    local specIndex = GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex)
    if not specID then return 5 end

    if classFile == "DRUID" then
        if specID == 102 or specID == 105 then
            return IsPlayerSpell(197488) and 45 or 40 -- Astral Influence
        end
        return 5
    elseif classFile == "DEMONHUNTER" then
        return (specID == 577 or specID == 581) and 5 or 25
    elseif classFile == "EVOKER" then
        return specID == 1468 and 30 or 25
    elseif classFile == "HUNTER" then
        return (specID == 253 or specID == 254) and 40 or 5
    elseif classFile == "PALADIN" then
        return specID == 65 and not holyPaladinMelee and 40 or 5
    elseif classFile == "SHAMAN" then
        return specID == 263 and 5 or 40
    elseif classFile == "MONK" then
        return specID == 270 and 40 or 5
    elseif classFile == "PRIEST" or classFile == "MAGE" or classFile == "WARLOCK" then
        return 40
    end
    return 5
end

-- Attack range shared by range-aware UI. An explicit cutoff wins; otherwise
-- class/spec decides -- CACHED, invalidated by the engine's activation events
-- (spec/talent/spellbook churn): consumers call this at sweep/tick cadence and
-- per-call GetSpecializationInfo re-derivation was measurable. Druid melee
-- forms are the single live check. Holy Paladins can opt into melee range.
function EllesmereUI.Range_GetAttackCutoff(customCutoff, holyPaladinMelee)
    customCutoff = tonumber(customCutoff)
    if customCutoff then
        customCutoff = math.floor((customCutoff + 2.5) / 5) * 5
        return math.max(5, math.min(50, customCutoff))
    end

    local _, classFile = UnitClass("player")
    if classFile == "DRUID" and DRUID_MELEE_FORMS[GetShapeshiftForm()] then return 5 end

    if holyPaladinMelee then
        local v = RG.cutoffHolyMelee
        if v == nil then
            v = SpecAttackCutoff(true)
            RG.cutoffHolyMelee = v
        end
        return v
    end
    local v = RG.cutoffBase
    if v == nil then
        v = SpecAttackCutoff(false)
        RG.cutoffBase = v
    end
    return v
end

local function BuildLadder()
    RG.ladderBuilt = true
    RG.dirty = false
    ResetCaches()
    wipe(RG.ladder)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines
        and C_Spell and C_Spell.GetSpellInfo and Enum and Enum.SpellBookItemType) then
        return
    end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local byRange = {}
    for li = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(li)
        -- offSpecID is 0 (not nil) on active-spec lines.
        if line and not (line.offSpecID and line.offSpecID ~= 0)
            and not line.shouldHide
            and line.itemIndexOffset and line.numSpellBookItems then
            for si = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local itemType, actionID, spellID = C_SpellBook.GetSpellBookItemType(si, bank)
                local sid = spellID or actionID
                if itemType == Enum.SpellBookItemType.Spell and sid
                    and not (C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(sid))
                    and (not C_Spell.IsSpellHarmful or C_Spell.IsSpellHarmful(sid)) then
                    local sinfo = C_Spell.GetSpellInfo(sid)
                    local maxR = sinfo and sinfo.maxRange
                    -- A charge/leap-style spell with a nonzero minRange answers
                    -- IsSpellInRange false both beyond maxRange AND inside its
                    -- own dead zone (e.g. a gap-closer unusable under ~8yd) --
                    -- the ladder walk below treats any false as "beyond this
                    -- rung," so such a spell would falsely fade a target
                    -- standing well inside melee range. Exclude it; other
                    -- spells sharing its maxRange rung are unaffected.
                    if sinfo and sinfo.minRange and sinfo.minRange > 0 then
                        maxR = nil
                    end
                    if maxR and maxR > 0 and maxR <= 100 then
                        local rung = byRange[maxR]
                        if not rung then
                            rung = { range = maxR, spells = {} }
                            byRange[maxR] = rung
                            RG.ladder[#RG.ladder + 1] = rung
                        end
                        if #rung.spells < MAX_SPELLS_PER_RUNG then
                            rung.spells[#rung.spells + 1] = sid
                        end
                    end
                end
            end
        end
    end
    table.sort(RG.ladder, function(a, b) return a.range < b.range end)
end

local function EnsureLadder()
    if RG.dirty or not RG.ladderBuilt then BuildLadder() end
end

-- One rung's answer: first non-nil IsSpellInRange among its spells, checked
-- through the live override (a base id a talent replaced answers nil).
-- Secret results are skipped -- fail-open to nil, never an error.
local function RungInRange(rung, unit)
    local FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    local spells = rung.spells
    for i = 1, #spells do
        local sid = spells[i]
        local live = (FindOvr and FindOvr(sid)) or sid
        local res = C_Spell.IsSpellInRange(live, unit)
        if not (issecretvalue and issecretvalue(res)) and res ~= nil then
            return res
        end
    end
    return nil
end

-- One item rung's answer: true if any id answers in-range, false only on an
-- explicit out-of-range answer, nil when every id is secret/inapplicable.
local function ItemEntryInRange(entry, unit)
    local ids = entry.ids
    if ids then
        local sawFalse = false
        for i = 1, #ids do
            local res = C_Item.IsItemInRange(ids[i], unit)
            if not (issecretvalue and issecretvalue(res)) then
                if res == true then return true end
                if res == false then sawFalse = true end
            end
        end
        if sawFalse then return false end
        return nil
    end
    local res = C_Item.IsItemInRange(entry.id, unit)
    if issecretvalue and issecretvalue(res) then return nil end
    return res
end

-- In combat (and in protected instances, where protected-function restrictions persist
-- between pulls) C_Item.IsItemInRange is a PROTECTED call against units the player
-- cannot attack -- calling it there is an ADDON_ACTION_BLOCKED, not a secret result, so
-- it must be gated up front. Hostile checks stay legal. Fails toward skipping the walk:
-- a restricted query degrades to nil (no display) instead of a blocked action.
local function ItemChecksAllowed(unit)
    if not (InCombatLockdown()
        or (EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance())) then
        return true
    end
    local can = UnitCanAttack("player", unit)
    if issecretvalue and issecretvalue(can) then return false end
    return can == true
end

-------------------------------------------------------------------------------
--  Queries
-------------------------------------------------------------------------------

-- Largest spell-ladder rung the unit is BEYOND (0 = inside the smallest
-- rung), or nil when no rung produced a usable answer. Displayed as "N+".
function EllesmereUI.Range_LowerBound(unit)
    if not unit or not UnitExists(unit) then return nil end
    if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    local now = GetTime()
    if lbCache.has and lbCache.unit == unit and (now - lbCache.t) < CACHE_TTL then
        return lbCache.v
    end
    EnsureLadder()
    local ladder = RG.ladder
    local lower, result, answered = 0, nil, false
    for i = 1, #ladder do
        local res = RungInRange(ladder[i], unit)
        if res == true then
            answered = true
            result = lower
            break
        elseif res == false then
            answered = true
            lower = ladder[i].range
        end
    end
    if answered and result == nil then result = lower end
    lbCache.unit, lbCache.t, lbCache.has, lbCache.v = unit, now, true, result
    return result
end

-- Item-ladder bracket. Ascending walk; returns minYards, maxYards where min
-- is the last rung answered out-of-range and max the first answered in-range
-- (max nil = beyond every checked rung). Returns nil when no rung answered.
-- stopRange (optional) ends the walk after the first rung at or past it when
-- nothing has answered in-range yet -- a beyond/within verdict at stopRange
-- never needs the rungs past it. A cached full walk can serve a stopped
-- query (its verdict at any cutoff is identical), never the other way.
-- Bare item walk, no cache reads or writes: the single-unit consumers cache
-- through Range_ItemBracket below; the multi-unit plate sweep calls this
-- directly so its fan-out can never evict the "target" cache slot.
local function ItemWalk(unit, stopRange)
    local minY, maxY = 0, nil
    local answered = false
    for i = 1, #RANGE_ITEMS do
        local entry = RANGE_ITEMS[i]
        local res = ItemEntryInRange(entry, unit)
        if res == true then
            answered = true
            maxY = entry.range
            break
        elseif res == false then
            answered = true
            minY = entry.range
            -- Only stop once THIS entry actually answered: an unowned item
            -- sitting exactly at stopRange answers nil, not false, and must
            -- not silently truncate the walk before a farther rung the
            -- player DOES own gets a chance to give a real verdict.
            if stopRange and entry.range >= stopRange then break end
        end
    end
    if not answered then return nil end
    return minY, maxY
end

function EllesmereUI.Range_ItemBracket(unit, stopRange)
    if not unit or not UnitExists(unit) then return nil end
    if not (C_Item and C_Item.IsItemInRange) then return nil end
    if not ItemChecksAllowed(unit) then return nil end
    local now = GetTime()
    if brCache.has and brCache.unit == unit and (now - brCache.t) < CACHE_TTL
        and (brCache.stop == stopRange or brCache.stop == nil) then
        return brCache.mn, brCache.mx
    end
    local minY, maxY = ItemWalk(unit, stopRange)
    brCache.unit, brCache.stop, brCache.t, brCache.has = unit, stopRange, now, true
    brCache.mn, brCache.mx = minY, maxY
    return minY, maxY
end

-- Crosshair support: is the unit beyond `cutoff` yards? Probes the player's
-- own harmful spells with ranges in [cutoff, cutoff+10] (the window keeps
-- outlier long-range utility spells from widening the answer), CLOSEST to
-- cutoff first, first non-nil answer wins. Closest-first matters: a spell
-- wider than cutoff answers in-range out to ITS OWN max and silently widens
-- the cutoff -- a 40yd spell in a 30yd window answers true all the way to 40.
-- Returns true/false, or nil when no probe answered -- the caller falls back
-- to the item ladder.
function EllesmereUI.Range_BeyondCutoff(unit, cutoff)
    if not unit or not UnitExists(unit) then return nil end
    if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    EnsureLadder()
    if RG.probeCutoff ~= cutoff then
        RG.probeCutoff = cutoff
        wipe(RG.probes)
        local maxWindow = cutoff + 10
        local ladder = RG.ladder
        for i = 1, #ladder do -- ascending ladder walked forwards = closest-to-cutoff first
            local rung = ladder[i]
            if rung.range >= cutoff then
                if rung.range > maxWindow then break end
                local spells = rung.spells
                for j = 1, #spells do
                    if #RG.probes >= MAX_PROBE_SPELLS then break end
                    RG.probes[#RG.probes + 1] = spells[j]
                end
                if #RG.probes >= MAX_PROBE_SPELLS then break end
            end
        end
    end
    local FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    for i = 1, #RG.probes do
        local sid = RG.probes[i]
        local live = (FindOvr and FindOvr(sid)) or sid
        local res = C_Spell.IsSpellInRange(live, unit)
        if not (issecretvalue and issecretvalue(res)) and res ~= nil then
            return res == false
        end
    end
    return nil
end

-- True/false when the unit can be classified against the supplied (or normal
-- class/spec) attack range; nil when no spell or item probe answered.
-- Single-unit consumers only (crosshair "target"): the item fallback rides
-- the shared single-slot cache. Sweeps use Range_SweepBeyond below.
function EllesmereUI.Range_IsBeyondAttackRange(unit, cutoff)
    cutoff = cutoff or EllesmereUI.Range_GetAttackCutoff()
    if cutoff > 5 then
        local beyond = EllesmereUI.Range_BeyondCutoff(unit, cutoff)
        if beyond ~= nil then return beyond end
    end
    local minY, maxY = EllesmereUI.Range_ItemBracket(unit, cutoff)
    if minY == nil then return nil end
    return maxY == nil or maxY > cutoff
end

-- Sweep-facing variant for MANY-unit consumers (nameplate out-of-range fade):
-- verdicts ride a short-TTL per-unit map instead of the single-slot target
-- caches (a 40-plate fan-out through those evicted the crosshair/QoL hits
-- every tick), and the item fallback goes through the bare walk for the same
-- reason. Encoded 0/1/2 = nil/true/false so cached nil verdicts still hit.
-- NOTE the melee floor: at cutoff 5 the spell probes are skipped and the item
-- walk is protection-gated (ItemChecksAllowed) -- in instanced combat against
-- units whose attackability reads secret, melee verdicts degrade to nil (no
-- fade) by design rather than risking a blocked action.
local sweepCache = { t = 0, cutoff = nil, v = {} }
local SWEEP_TTL = 0.4
function EllesmereUI.Range_SweepBeyond(unit, cutoff)
    if not unit or not UnitExists(unit) then return nil end
    cutoff = cutoff or EllesmereUI.Range_GetAttackCutoff()
    local now = GetTime()
    if (now - sweepCache.t) > SWEEP_TTL or sweepCache.cutoff ~= cutoff then
        wipe(sweepCache.v)
        sweepCache.t = now
        sweepCache.cutoff = cutoff
    end
    local hit = sweepCache.v[unit]
    if hit ~= nil then
        if hit == 0 then return nil end
        return hit == 1
    end
    local beyond
    if cutoff > 5 then
        beyond = EllesmereUI.Range_BeyondCutoff(unit, cutoff)
    end
    if beyond == nil and C_Item and C_Item.IsItemInRange and ItemChecksAllowed(unit) then
        local minY, maxY = ItemWalk(unit, cutoff)
        if minY ~= nil then
            beyond = maxY == nil or maxY > cutoff
        end
    end
    sweepCache.v[unit] = beyond == nil and 0 or (beyond and 1 or 2)
    return beyond
end


-------------------------------------------------------------------------------
--  Activation
-------------------------------------------------------------------------------

-- Consumers declare themselves while their feature is enabled. The engine
-- registers its invalidation events only while at least one consumer is
-- active and drops them all at zero, so nothing here ever fires for users
-- with every range feature disabled. Idempotent and cheap on repeat calls.
function EllesmereUI.Range_SetActive(key, on)
    on = on and true or nil
    if RG.active[key] == on then return end
    RG.active[key] = on
    RG.activeCount = RG.activeCount + (on and 1 or -1)
    if on and RG.activeCount == 1 then
        if not RG.evt then
            RG.evt = CreateFrame("Frame")
            RG.evt:SetScript("OnEvent", function()
                RG.dirty = true
                RG.cutoffBase, RG.cutoffHolyMelee = nil, nil
            end)
        end
        RG.evt:RegisterEvent("SPELLS_CHANGED")
        RG.evt:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        RG.evt:RegisterEvent("TRAIT_CONFIG_UPDATED")
        RG.evt:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Events were unregistered until now; anything may have changed.
        RG.dirty = true
        RG.cutoffBase, RG.cutoffHolyMelee = nil, nil
    elseif not on and RG.activeCount == 0 then
        if RG.evt then RG.evt:UnregisterAllEvents() end
    end
end
