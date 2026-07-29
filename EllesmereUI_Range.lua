-------------------------------------------------------------------------------
--  EllesmereUI_Range.lua
--  Shared range-check engine for the suite's three range consumers:
--    - Nameplates "Distance to Target Text"  (spell-ladder lower bound)
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

-- In combat (and in protected instances, where protected-function
-- restrictions persist between pulls) C_Item.IsItemInRange is a PROTECTED
-- call against units the player cannot attack -- calling it there is an
-- ADDON_ACTION_BLOCKED, not a secret result, so it must be gated up front.
-- Hostile checks stay legal. Fails toward skipping the walk: a restricted
-- query degrades to nil (no display) instead of a blocked action.
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
function EllesmereUI.Range_ItemBracket(unit, stopRange)
    if not unit or not UnitExists(unit) then return nil end
    if not (C_Item and C_Item.IsItemInRange) then return nil end
    if not ItemChecksAllowed(unit) then return nil end
    local now = GetTime()
    if brCache.has and brCache.unit == unit and (now - brCache.t) < CACHE_TTL
        and (brCache.stop == stopRange or brCache.stop == nil) then
        return brCache.mn, brCache.mx
    end
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
        end
        if stopRange and entry.range >= stopRange then break end
    end
    if not answered then
        brCache.unit, brCache.stop, brCache.t, brCache.has = unit, stopRange, now, true
        brCache.mn, brCache.mx = nil, nil
        return nil
    end
    brCache.unit, brCache.stop, brCache.t, brCache.has = unit, stopRange, now, true
    brCache.mn, brCache.mx = minY, maxY
    return minY, maxY
end

-- Crosshair support: is the unit beyond `cutoff` yards? Probes the player's
-- own harmful spells with ranges in [cutoff, cutoff+10] (the window keeps
-- outlier long-range utility spells from widening the answer), longest
-- first, first non-nil answer wins. Returns true/false, or nil when no
-- probe answered -- the caller falls back to the item ladder.
function EllesmereUI.Range_BeyondCutoff(unit, cutoff)
    if not unit or not UnitExists(unit) then return nil end
    if not (C_Spell and C_Spell.IsSpellInRange) then return nil end
    EnsureLadder()
    if RG.probeCutoff ~= cutoff then
        RG.probeCutoff = cutoff
        wipe(RG.probes)
        local maxWindow = cutoff + 10
        local ladder = RG.ladder
        for i = #ladder, 1, -1 do -- ascending ladder walked backwards = longest first
            local rung = ladder[i]
            if rung.range < cutoff then break end
            if rung.range <= maxWindow then
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

-- One-shot diagnostic support (/euirangedbg): every rung and each candidate
-- spell's live answer, through the caller's printer.
function EllesmereUI.Range_DebugDump(unit, out)
    EnsureLadder()
    out("ladder rungs=" .. #RG.ladder .. " activeConsumers=" .. RG.activeCount)
    local FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    for i = 1, #RG.ladder do
        local rung = RG.ladder[i]
        for j = 1, #rung.spells do
            local sid = rung.spells[j]
            local res = "no-unit"
            if unit then
                local live = (FindOvr and FindOvr(sid)) or sid
                local raw = C_Spell.IsSpellInRange and C_Spell.IsSpellInRange(live, unit)
                if issecretvalue and issecretvalue(raw) then
                    res = "SECRET"
                else
                    res = tostring(raw)
                end
            end
            out(("rung %d: %syd spell=%s -> %s"):format(i, tostring(rung.range), tostring(sid), res))
        end
    end
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
            end)
        end
        RG.evt:RegisterEvent("SPELLS_CHANGED")
        RG.evt:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        RG.evt:RegisterEvent("TRAIT_CONFIG_UPDATED")
        RG.evt:RegisterEvent("PLAYER_ENTERING_WORLD")
        -- Events were unregistered until now; anything may have changed.
        RG.dirty = true
    elseif not on and RG.activeCount == 0 then
        if RG.evt then RG.evt:UnregisterAllEvents() end
    end
end
