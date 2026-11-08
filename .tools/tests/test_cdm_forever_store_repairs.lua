-- Run from the repository root: lua .tools/tests/test_cdm_forever_store_repairs.lua
-- WoW Forever CDM spell store repairs (EllesmereUI_Migration.lua): a Forever
-- spec key bucket hiding a retail-keyed layout of its class is dropped, and the
-- ghost CD bar stops hiding another rank of a spell placed on a visible
-- cooldown bar. Drives the real migration runner and the repairs block, each
-- cut from the file.
local function ReadSource(name)
    local f = assert(io.open(name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local MIG = ReadSource("EllesmereUI_Migration.lua")
local r1 = assert(MIG:find("\n%-%-%s+Registered migrations\n"), "runner end missing")
local RUNNER = MIG:sub(1, r1)
local b0 = assert(MIG:find("-- WoW Forever CDM spell store repairs", 1, true), "repairs block missing")
local b1 = assert(MIG:find("\nend\n", b0, true), "repairs block end missing")
local BLOCK = MIG:sub(b0, b1 + 4)

EUI_CLIENT_BLOCKED = false
GetTime = function() return 0 end

local NAMES = {
    [2973] = "Raptor Strike", [14261] = "Raptor Strike",
    [1495] = "Mongoose Bite", [14269] = "Mongoose Bite",
    [2974] = "Wing Clip", [14267] = "Wing Clip",
    [99997] = "Feign Death", [5384] = "Feign Death",
    [99999] = "Arcane Shot", [3044] = "Arcane Shot",
    [689] = "Drain Life",
}
C_Spell = { GetSpellName = function(id) return NAMES[id] end }

local CLASS = { [1485] = "HUNTER", [253] = "HUNTER", [254] = "HUNTER", [255] = "HUNTER",
    [1491] = "WARRIOR", [71] = "WARRIOR", [72] = "WARRIOR", [73] = "WARRIOR" }
local SPECS = { HUNTER = { 253, 254, 255 }, WARRIOR = { 71, 72, 73 } }

local function Run(forever, db)
    EllesmereUI = {
        IS_FOREVER = forever,
        FOREVER_CLASS_SPEC = { HUNTER = 1485, WARRIOR = 1491 },
        SpecClassOf = function(id) return CLASS[id] end,
        ForeverClassSpecIDs = function(cls) return SPECS[cls] end,
    }
    EllesmereUIDB = db
    assert(loadstring(RUNNER, "=runner"))()
    assert(loadstring(BLOCK, "=repairs"))()
    EllesmereUI.RunRegisteredMigrations()
    for _, e in ipairs(EllesmereUI._migrationErrors) do print("migration error:", e.id, e.err) end
    assert(#EllesmereUI._migrationErrors == 0, "the repairs ran without errors")
end

local function Same(list, want)
    if #list ~= #want then return false end
    for i = 1, #want do if list[i] ~= want[i] then return false end end
    return true
end
local function Show(list) return "{" .. table.concat(list, ", ") .. "}" end

local function Layout(...) return { barSpells = { cooldowns = { assignedSpells = { ... } } } } end

local function MakeDB()
    -- As saved: the Cooldowns, Utility and Buffs bars lead and keep no field
    -- equal to its default.
    local bars = {
        {}, {}, {},
        { key = "bar4", barType = "cooldowns", enabled = false },
        { key = "bar5", barType = "utility", enabled = true },
        { key = "__ghost_cd", barType = "cooldowns", isGhostBar = true, enabled = true },
    }
    return {
        profiles = { G = { addons = { EllesmereUICooldownManager = { cdmBars = { bars = bars } } } } },
        spellAssignments = { profiles = {
            -- Imported layout under 253, shadowed by a 1485 bucket.
            B = { specProfiles = { ["1485"] = Layout(75, 3044), ["253"] = Layout(2973, 20572) } },
            -- No retail layout to restore: the Forever key stays.
            C = { specProfiles = { ["1485"] = Layout(75), ["254"] = Layout(),
                ["255"] = { barSpells = { __ghost_cd = { assignedSpells = { 3044 } } } } } },
            D = { specProfiles = { ["1485"] = Layout(75) } },
            -- Another class's retail layout hides nothing of the hunter's.
            E = { specProfiles = { ["1491"] = Layout(100), ["253"] = Layout(2973) } },
            -- A Tracking Bars layout counts too.
            F = { specProfiles = { ["1485"] = Layout(75), ["253"] = { trackedBuffBars = { bars = { {} } } } } },
            G = { specProfiles = { ["253"] = { barSpells = {
                cooldowns = { assignedSpells = { 2973, 99999 }, customSpellIDs = { [99999] = true } },
                bar4 = { assignedSpells = { 2974 } },
                bar5 = { assignedSpells = { 1495 } },
                buffs = { assignedSpells = { 99997 } },
                __ghost_cd = { assignedSpells = { 14261, 2973, 14269, 14267, 5384, 3044, 689 } },
            } } } },
        } },
    }
end

-------------------------------------------------------------------------------
-- WoW Forever
-------------------------------------------------------------------------------
local db = MakeDB()
Run(true, db)
local P = db.spellAssignments.profiles

assert(P.B.specProfiles["1485"] == nil, "a Forever key hiding the class's retail layout is dropped")
assert(P.B.specProfiles["253"] and P.B.specProfiles["253"].barSpells.cooldowns.assignedSpells[1] == 2973,
    "the retail layout is kept")
assert(P.C.specProfiles["1485"], "kept when no retail key holds a layout (empty lists and hidden spells only)")
assert(P.D.specProfiles["1485"], "kept when it is the class's only bucket")
assert(P.E.specProfiles["1491"], "kept when the retail layout is another class's")
assert(P.F.specProfiles["1485"] == nil, "dropped when the retail key holds Tracking Bars")

-- The other ranks of Raptor Strike (Cooldowns) and Mongoose Bite (a custom bar)
-- go. Raptor Strike under its placed ID (an explicit hide), Wing Clip (a
-- disabled bar), Feign Death (the Buffs bar), Arcane Shot (a custom spell ID)
-- and Drain Life stay hidden.
local ghost = P.G.specProfiles["253"].barSpells.__ghost_cd.assignedSpells
local WANT = { 2973, 14267, 5384, 3044, 689 }
assert(Same(ghost, WANT), "ghost after the repair: " .. Show(ghost))

-- Idempotent: a second session changes nothing.
EllesmereUI.RunRegisteredMigrations()
assert(Same(ghost, WANT), "a second run changes nothing: " .. Show(ghost))

-------------------------------------------------------------------------------
-- Retail: nothing registers, nothing changes
-------------------------------------------------------------------------------
db = MakeDB()
Run(false, db)
P = db.spellAssignments.profiles
assert(P.B.specProfiles["1485"], "retail keeps every bucket")
assert(#P.G.specProfiles["253"].barSpells.__ghost_cd.assignedSpells == 7, "retail keeps the ghost list")

print("test_cdm_forever_store_repairs: all checks passed")
