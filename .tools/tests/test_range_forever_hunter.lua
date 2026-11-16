-- Stub harness: the shared range engine (EllesmereUI_Range.lua) and spells with a minimum range.
-- A WoW Forever Hunter's shots all have a minimum range, and the ladder skips such spells (their
-- "out of range" also means "too close"), which left a Hunter on the melee cutoff, 5 yd. Now, on
-- WoW Forever only: the shots are kept aside, a Hunter's attack cutoff is the longest of them, and
-- when nothing else answers the shot itself is asked: "in range" is exact, "out of range" is told
-- apart from "too close" by the item ladder up to the minimum range. Retail runs none of it.
-- The real file is loaded whole, once per case, over a model: a target at a distance, spells and
-- items that answer by their ranges. Asserted: the cutoff, the verdict at every distance (items
-- known and unknown), one shot asked per minimum range, and that retail never asks one.
--   lua .tools/tests/test_range_forever_hunter.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local SRC = ReadSource("EllesmereUI_Range.lua")
local CHUNK = assert(loadstring(SRC, "=EllesmereUI_Range.lua"))

-- The engine's own harm items, read from its table: item id -> its range in yards.
local ITEM_RANGE = {}
do
    local block = assert(SRC:match("local RANGE_ITEMS = (%b{})"), "the item table was not found")
    for range, rest in block:gmatch("{ range = (%d+),%s*([^\n]*)") do
        local ids = rest:match("ids%s*=%s*(%b{})") or rest:match("id%s*=%s*(%d+)")
        for id in ids:gmatch("%d+") do ITEM_RANGE[tonumber(id)] = tonumber(range) end
    end
    check(ITEM_RANGE[8149] == 5 and ITEM_RANGE[34368] == 8 and ITEM_RANGE[18904] == 35, "the item table was not read")
end

-- A client: forever, class, spec, spells = { { id, min, max, silent = true }, ... } in spellbook
-- order (max 0 = a melee ability). W.dist is the target's distance; W.items, whether the harm
-- items answer. Returns the world and the engine's namespace.
local function NewClient(o)
    local W = { dist = 10, items = true, now = 100, asked = {}, spellCalls = 0, itemCalls = 0, spells = o.spells }
    local byId = {}
    for _, s in ipairs(o.spells) do byId[s[1]] = s end
    local EUI = { IS_FOREVER = o.forever or nil, InProtectedInstance = function() return false end }
    local env = setmetatable({
        EllesmereUI = EUI,
        GetTime = function() return W.now end,
        UnitClass = function() return o.class, o.class end,
        UnitExists = function() return true end,
        UnitCanAttack = function() return true end,
        InCombatLockdown = function() return false end,
        GetShapeshiftFormID = function() return nil end,
        GetShapeshiftForm = function() return 0 end,
        issecretvalue = function() return false end,
        wipe = function(t) for k in pairs(t) do t[k] = nil end return t end,
        CreateFrame = function()
            local f = { events = {} }
            function f:SetScript(_, fn) W.onEvent = fn end
            function f:RegisterEvent(e) self.events[e] = true end
            function f:UnregisterAllEvents() self.events = {} end
            return f
        end,
        Enum = { SpellBookItemType = { Spell = 1 }, SpellBookSpellBank = { Player = 0 } },
        C_SpecializationInfo = {
            GetSpecialization = function() return o.spec and 1 or nil end,
            GetSpecializationInfo = function() return o.spec end,
        },
        C_SpellBook = {
            GetNumSpellBookSkillLines = function() return 1 end,
            GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #W.spells, offSpecID = 0 } end,
            GetSpellBookItemType = function(i) return 1, W.spells[i][1], W.spells[i][1] end,
            FindSpellOverrideByID = function(id) return id end,
            IsSpellKnown = function() return false end,
        },
        C_Spell = {
            GetSpellInfo = function(id) local s = byId[id]; return s and { maxRange = s[3], minRange = s[2] } end,
            IsSpellPassive = function() return false end,
            IsSpellHarmful = function() return true end,
            IsSpellInRange = function(id)
                local s = byId[id]
                W.spellCalls = W.spellCalls + 1
                W.asked[id] = (W.asked[id] or 0) + 1
                if s.silent then return nil end
                return W.dist >= s[2] and W.dist <= s[3]
            end,
        },
        C_Item = {
            IsItemInRange = function(id)
                W.itemCalls = W.itemCalls + 1
                local r = ITEM_RANGE[id]
                if not (W.items and r) then return nil end
                return W.dist <= r
            end,
        },
    }, { __index = _G })
    setfenv(CHUNK, env)
    CHUNK()
    W.byId = byId
    return W, EUI
end
-- One query at a distance, past every cache window. Returns the verdict and how many times a
-- spell with a minimum range was asked.
local function At(W, EUI, dist, fn, cutoff)
    W.dist = dist
    W.now = W.now + 5
    for id in pairs(W.asked) do W.asked[id] = nil end
    local v = EUI[fn]("target", cutoff)
    local n = 0
    for id, c in pairs(W.asked) do
        if W.byId[id][2] > 0 then n = n + c end
    end
    return v, n
end
local function S(v) return tostring(v) end

-- A Hunter's book: four shots of 8 to 35 yd, a melee strike, a mark with no minimum range.
local function HunterBook(maxR)
    maxR = maxR or 35
    return { { 9001, 8, maxR }, { 9002, 8, maxR }, { 9003, 0, 0 }, { 9004, 8, maxR }, { 9005, 0, 100 }, { 9006, 8, maxR } }
end

-------------------------------------------------------------------------------
-- 1. WoW Forever Hunter: the cutoff is the shots' range
-------------------------------------------------------------------------------
do
    local _, EUI = NewClient({ forever = true, class = "HUNTER", spells = HunterBook() })
    check(EUI.Range_GetAttackCutoff() == 35, "a WoW Forever Hunter's attack cutoff is " .. S(EUI.Range_GetAttackCutoff()) .. ", not 35")
    -- level 1: Auto Shot alone
    _, EUI = NewClient({ forever = true, class = "HUNTER", spells = { { 9001, 8, 35 } } })
    check(EUI.Range_GetAttackCutoff() == 35, "a Hunter with one shot does not get its range")
    -- no shot at all (no spell with a minimum range): the melee floor
    _, EUI = NewClient({ forever = true, class = "HUNTER", spells = { { 9003, 0, 0 }, { 9005, 0, 100 } } })
    check(EUI.Range_GetAttackCutoff() == 5, "a Hunter with no shot is not on the melee cutoff")
    -- the longest shot counts, a utility spell past 45 yd does not
    _, EUI = NewClient({ forever = true, class = "HUNTER", spells = { { 9001, 8, 15 }, { 9002, 8, 35 }, { 9007, 8, 60 }, { 9004, 8, 20 } } })
    check(EUI.Range_GetAttackCutoff() == 35, "the cutoff is not the longest shot within 45 yd: " .. S(EUI.Range_GetAttackCutoff()))
    -- a range the spellbook reports with float noise reads in whole yards
    _, EUI = NewClient({ forever = true, class = "HUNTER", spells = { { 9001, 8, 34.999998 } } })
    check(EUI.Range_GetAttackCutoff() == 35, "a noisy shot range is not rounded to whole yards")
    -- a talent's longer range is picked up when the spellbook changes
    local W
    W, EUI = NewClient({ forever = true, class = "HUNTER", spells = HunterBook() })
    EUI.Range_SetActive("test", true)
    check(EUI.Range_GetAttackCutoff() == 35, "the cutoff before the talent is not 35")
    for _, s in ipairs(W.spells) do if s[2] > 0 then s[3] = 41 end end
    check(EUI.Range_GetAttackCutoff() == 35, "the cached cutoff moved with no spellbook event")
    W.onEvent()
    check(EUI.Range_GetAttackCutoff() == 41, "a longer shot range after a spellbook change is not picked up: " .. S(EUI.Range_GetAttackCutoff()))
    -- an explicit cutoff still wins
    check(EUI.Range_GetAttackCutoff(20) == 20, "a custom cutoff does not win over the Hunter's")
    -- other WoW Forever classes are as before: a Warrior stays on 5, a caster on its longest spell
    _, EUI = NewClient({ forever = true, class = "WARRIOR", spells = { { 9101, 8, 25 }, { 9102, 0, 0 } } })
    check(EUI.Range_GetAttackCutoff() == 5, "a WoW Forever Warrior left the melee cutoff")
    _, EUI = NewClient({ forever = true, class = "MAGE", spells = { { 9201, 0, 30 }, { 9202, 0, 35 } } })
    check(EUI.Range_GetAttackCutoff() == 35, "a WoW Forever Mage's cutoff is not its longest spell")
end

-------------------------------------------------------------------------------
-- 2. WoW Forever Hunter: the verdict at every distance, one shot asked
-------------------------------------------------------------------------------
do
    local W, EUI = NewClient({ forever = true, class = "HUNTER", spells = HunterBook() })
    local cutoff = EUI.Range_GetAttackCutoff()
    -- distance -> beyond the cutoff? (3 and 6 yd are inside the shots' dead zone: too close, not beyond)
    local cases = { { 3, false }, { 6, false }, { 8, false }, { 20, false }, { 35, false }, { 36, true }, { 40, true }, { 60, true } }
    for _, fn in ipairs({ "Range_BeyondCutoff", "Range_SweepBeyond", "Range_IsBeyondAttackRange" }) do
        for _, c in ipairs(cases) do
            local v, n = At(W, EUI, c[1], fn, cutoff)
            check(v == c[2], fn .. " at " .. c[1] .. " yd: " .. S(v) .. ", not " .. S(c[2]))
            check(n == 1, fn .. " at " .. c[1] .. " yd asked " .. n .. " shots (one answers for all of the same range and minimum)")
        end
    end
    -- the harm items give no answer (not cached, or a protected check): in range is still known,
    -- and "out of range" alone is not taken for "too far"
    W.items = false
    check(At(W, EUI, 20, "Range_SweepBeyond", cutoff) == false, "in range is not known without the items")
    check(At(W, EUI, 40, "Range_SweepBeyond", cutoff) == nil, "a shot's out-of-range is taken for too far without the items")
    check(At(W, EUI, 3, "Range_SweepBeyond", cutoff) == nil, "too close reads as a verdict without the items")
    W.items = true

    -- the first shot gives no answer: the next one of the same range and minimum is asked
    W, EUI = NewClient({ forever = true, class = "HUNTER", spells = { { 9001, 8, 35, silent = true }, { 9002, 8, 35 }, { 9004, 8, 35 } } })
    local v, n = At(W, EUI, 40, "Range_BeyondCutoff", 35)
    check(v == true and n == 2, "a silent first shot: verdict " .. S(v) .. " after " .. n .. " shots asked, not true after 2")
    v, n = At(W, EUI, 20, "Range_BeyondCutoff", 35)
    check(v == false and n == 2, "a silent first shot in range: verdict " .. S(v) .. " after " .. n .. " asked")
    -- every shot silent: unknown
    W, EUI = NewClient({ forever = true, class = "HUNTER", spells = { { 9001, 8, 35, silent = true }, { 9002, 8, 35, silent = true } } })
    check(At(W, EUI, 20, "Range_BeyondCutoff", 35) == nil, "shots that give no answer produce a verdict")

    -- two minimum ranges at the cutoff, listed out of order: each is asked once, the shorter first
    W, EUI = NewClient({ forever = true, class = "HUNTER", spells = { { 9001, 8, 35 }, { 9008, 5, 35 }, { 9002, 8, 35 }, { 9004, 8, 35 } } })
    v, n = At(W, EUI, 6, "Range_BeyondCutoff", 35)
    check(v == false and n == 1, "6 yd with a 5 yd-minimum shot: " .. S(v) .. " after " .. n .. " asked, not false after 1")
    v, n = At(W, EUI, 3, "Range_BeyondCutoff", 35)
    check(v == false and n == 2, "3 yd with two minimum ranges: " .. S(v) .. " after " .. n .. " asked, not false after 2")
    v, n = At(W, EUI, 40, "Range_BeyondCutoff", 35)
    check(v == true and n == 2, "40 yd with two minimum ranges: " .. S(v) .. " after " .. n .. " asked, not true after 2")
    -- minimum ranges that differ only by float noise are one minimum range
    W, EUI = NewClient({ forever = true, class = "HUNTER", spells = { { 9001, 8, 35 }, { 9002, 7.999998, 35 }, { 9004, 8.000001, 35 } } })
    v, n = At(W, EUI, 40, "Range_BeyondCutoff", 35)
    check(v == true and n == 1, "noisy minimum ranges are asked " .. n .. " times")

    -- a shot of another range says nothing about this cutoff
    W, EUI = NewClient({ forever = true, class = "HUNTER", spells = HunterBook() })
    v, n = At(W, EUI, 33, "Range_BeyondCutoff", 30)
    check(v == nil and n == 0, "a custom cutoff of 30 is answered by 35 yd shots (" .. S(v) .. ", " .. n .. " asked)")
end

-------------------------------------------------------------------------------
-- 3. WoW Forever, another class with a custom cutoff on a min-range spell
-------------------------------------------------------------------------------
do
    local W, EUI = NewClient({ forever = true, class = "WARRIOR", spells = { { 9101, 8, 25 }, { 9102, 0, 0 } } })
    check(At(W, EUI, 20, "Range_BeyondCutoff", 25) == false, "a WoW Forever Warrior at 20 yd of a 25 yd cutoff is not in range")
    check(At(W, EUI, 30, "Range_BeyondCutoff", 25) == true, "a WoW Forever Warrior at 30 yd of a 25 yd cutoff is not beyond")
    check(At(W, EUI, 4, "Range_BeyondCutoff", 25) == false, "a WoW Forever Warrior inside the dead zone reads beyond")
end

-------------------------------------------------------------------------------
-- 4. retail: no spell with a minimum range is ever asked
-------------------------------------------------------------------------------
do
    -- a Warrior with a 25 yd custom cutoff and a charge of 8 to 25 yd; its 30 yd spell gives no answer
    local W, EUI = NewClient({ class = "WARRIOR", spec = 71, spells = { { 9101, 8, 25 }, { 9103, 0, 30, silent = true }, { 9102, 0, 0 } } })
    check(EUI.Range_GetAttackCutoff() == 5, "a retail Warrior's cutoff moved")
    for _, d in ipairs({ 4, 20, 30 }) do
        local v, n = At(W, EUI, d, "Range_BeyondCutoff", 25)
        check(v == nil, "retail: the probe window gave no answer, yet Range_BeyondCutoff at " .. d .. " yd says " .. S(v))
        check(n == 0, "retail asks a spell with a minimum range (" .. n .. " at " .. d .. " yd)")
    end
    -- the sweep still gets its answer from the items there, as before
    check(At(W, EUI, 20, "Range_SweepBeyond", 25) == false and At(W, EUI, 30, "Range_SweepBeyond", 25) == true, "retail: the item fallback no longer answers")
    -- a Marksmanship Hunter keeps the spec's 40 yd, whatever its shots read
    W, EUI = NewClient({ class = "HUNTER", spec = 254, spells = { { 9001, 8, 35 }, { 9005, 0, 40 } } })
    check(EUI.Range_GetAttackCutoff() == 40, "a retail Marksmanship Hunter's cutoff is " .. S(EUI.Range_GetAttackCutoff()) .. ", not 40")
    local v, n = At(W, EUI, 38, "Range_BeyondCutoff", 40)
    check(v == false and n == 0, "retail Hunter at 38 yd: " .. S(v) .. " with " .. n .. " min-range shots asked")
    -- both gates are in the file (either one alone already keeps retail silent)
    check(SRC:find("if forever and maxR and maxR > 0 and maxR <= 100", 1, true) ~= nil, "the min-range spells are collected on every client")
    check(SRC:find("if EllesmereUI.IS_FOREVER == true then return MinRangeBeyond(unit, cutoff) end", 1, true) ~= nil, "the min-range fallback is called on every client")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_range_forever_hunter (%d checks)"):format(count))
