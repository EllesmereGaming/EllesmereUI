-- Run from the repository root: lua .tools/tests/test_cdm_forever_store_repairs.lua
-- WoW Forever CDM spell store repairs (EllesmereUI_Migration.lua): a Forever
-- spec key bucket hiding a retail-keyed layout of its class is dropped while
-- it holds only Blizzard's layout, and the ghost CD bar stops hiding another
-- rank of a spell placed on a visible cooldown bar. Drives the real migration
-- runner and the repairs block, each cut from the file.
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
-- Spells that exist but have no name yet.
local UNNAMED = {}
C_Spell = {
    GetSpellName = function(id) return not UNNAMED[id] and NAMES[id] or nil end,
    DoesSpellExist = function(id) return NAMES[id] ~= nil end,
}

local CLASS = { [1485] = "HUNTER", [253] = "HUNTER", [254] = "HUNTER", [255] = "HUNTER",
    [1491] = "WARRIOR", [71] = "WARRIOR", [72] = "WARRIOR", [73] = "WARRIOR" }
local SPECS = { HUNTER = { 253, 254, 255 }, WARRIOR = { 71, 72, 73 } }

local function Run(forever, db, allowErrors)
    EllesmereUI = {
        IS_FOREVER = forever,
        FOREVER_CLASS_SPEC = { HUNTER = 1485, WARRIOR = 1491 },
        SpecClassOf = function(id) return CLASS[id] end,
        ForeverClassSpecIDs = function(cls) return SPECS[cls] end,
        -- EllesmereUI_Presets.lua without the legacy ID: the first retail spec
        -- pred accepts, else the class's first.
        ForeverClassSpec = function(cls, pred, arg)
            local ids = SPECS[cls]
            for i = 1, #ids do
                if pred(ids[i], arg) then return ids[i] end
            end
            return ids[1]
        end,
        SpecHasStringEntry = function(id, tbl) return tbl ~= nil and tbl[tostring(id)] ~= nil end,
    }
    EllesmereUIDB = db
    assert(loadstring(RUNNER, "=runner"))()
    assert(loadstring(BLOCK, "=repairs"))()
    EllesmereUI.RunRegisteredMigrations()
    if allowErrors then return end
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

-- Blizzard's layout as the reseed or a Repopulate writes it, with the potion
-- row it marks as its own.
local function Reseeded(edit)
    local prof = { spellSettingsCD = {}, barSpells = {
        cooldowns = { assignedSpells = { 75, 3044, -5512 }, nativeItems = { [-5512] = true } },
        utility = { assignedSpells = { 781 } },
        buffs = { assignedSpells = {} },
    } }
    if edit then edit(prof, prof.barSpells) end
    return prof
end
local function Add(bs, id) bs.assignedSpells[#bs.assignedSpells + 1] = id end

-- What a player made on the Forever key keeps it.
local KEPT = {
    customBar = function(_, b) b.bar4 = { assignedSpells = { 2974 } } end,
    buffsBar = function(_, b) Add(b.buffs, 99997) end,
    customBuffBar = function(_, b) b.bar6 = { assignedSpells = { 99997 } } end,
    hiddenCD = function(_, b) b.__ghost_cd = { assignedSpells = { 5384 } } end,
    trinket = function(_, b) Add(b.cooldowns, -13) end,
    potion = function(_, b) Add(b.utility, -5512) end,
    emptySlot = function(_, b) Add(b.utility, -(1000000000 + 1)) end,
    hostedBuff = function(_, b) Add(b.cooldowns, -(2000000000 + 1130)) end,
    legacyHostedBuff = function(_, b) b.cooldowns.hostedBuffSpellIDs = { [3044] = true } end,
    cdClaim = function(_, b) Add(b.utility, -(3000000000 + 4242)) end,
    customSpell = function(_, b) b.cooldowns.customSpellIDs = { [3044] = true } end,
    legacyPreset = function(_, b) b.cooldowns.customSpellDurations = { [3044] = 20 } end,
    spellDurations = function(_, b) b.utility.spellDurations = { [781] = 10 } end,
    spellSettingsCD = function(p) p.spellSettingsCD[75] = { iconZoom = 0 } end,
    spellSettingsBuff = function(p) p.spellSettingsBuff = { [99997] = { iconZoom = 0 } } end,
    barSpellSettings = function(_, b) b.cooldowns.spellSettings = { [75] = { iconZoom = 0 } } end,
    barSettings = function(_, b) b.utility.barSettings = { iconZoom = 0 } end,
    trackingBars = function(p) p.trackedBuffBars = { bars = { {} } } end,
    barGlows = function(p)
        p.barGlows = { enabled = true, selectedBar = "cooldowns", assignments = { ["1_1"] = { { spellID = 99997 } } } }
    end,
    buffOrder = function(_, b)
        b.buffs.buffDisplayOrder = { "s99997", "s5384" }
        b.buffs._buffDisplayOrderUserModified = true
    end,
}

local function MakeDB()
    -- As saved: the Cooldowns, Utility and Buffs bars lead and keep no field
    -- equal to its default.
    local bars = {
        {}, {}, {},
        { key = "bar4", barType = "cooldowns", enabled = false },
        { key = "bar5", barType = "utility", enabled = true },
        { key = "__ghost_cd", barType = "cooldowns", isGhostBar = true, enabled = true },
    }
    local db = {
        profiles = { G = { addons = { EllesmereUICooldownManager = { cdmBars = { bars = bars } } } } },
        spellAssignments = { profiles = {
            -- Imported layout under 253, shadowed by a 1485 bucket.
            B = { specProfiles = { ["1485"] = Layout(75, 3044), ["253"] = Layout(2973, 20572) } },
            -- Only what the reseed writes, with the empty glow table and the
            -- buff order it seeds: still dropped.
            R = { specProfiles = { ["1485"] = Reseeded(function(p, b)
                p.barGlows = { enabled = true, selectedBar = "cooldowns", assignments = {} }
                b.buffs.buffDisplayOrder = { "s99997" }
            end), ["253"] = Layout(2973) } },
            -- The class would read the empty 253 next, not the 254 layout.
            S = { specProfiles = { ["1485"] = Layout(75), ["253"] = { barSpells = {} }, ["254"] = Layout(2973) } },
            -- An imported Forever key is the sharer's layout.
            I = { specProfiles = { ["1485"] = Reseeded(function(p) p._importGhostMode = true end),
                ["253"] = Layout(2973) } },
            -- No saved CDM bars for the profile: the default bars apply.
            N = { specProfiles = { ["253"] = { barSpells = {
                cooldowns = { assignedSpells = { 2973 } },
                __ghost_cd = { assignedSpells = { 14261 } },
            } } } },
            -- No retail layout to restore: the Forever key stays.
            C = { specProfiles = { ["1485"] = Layout(75), ["254"] = Layout(),
                ["255"] = { barSpells = { __ghost_cd = { assignedSpells = { 3044 } } } } } },
            D = { specProfiles = { ["1485"] = Layout(75) } },
            -- The key the class reads next holds only Hidden CDs: no layout.
            H = { specProfiles = { ["1485"] = Layout(75),
                ["253"] = { barSpells = { __ghost_cd = { assignedSpells = { 3044 } } } } } },
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
    for name, edit in pairs(KEPT) do
        db.spellAssignments.profiles[name] = { specProfiles = { ["1485"] = Reseeded(edit), ["253"] = Layout(2973) } }
    end
    return db
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
assert(P.H.specProfiles["1485"], "kept when the key the class reads next holds only Hidden CDs")
assert(P.D.specProfiles["1485"], "kept when it is the class's only bucket")
assert(P.E.specProfiles["1491"], "kept when the retail layout is another class's")
assert(P.F.specProfiles["1485"] == nil, "dropped when the retail key holds Tracking Bars")
assert(P.R.specProfiles["1485"] == nil, "dropped when it holds only Blizzard's layout and its item rows")
assert(P.S.specProfiles["1485"], "kept when the key the class reads next holds no layout")
assert(P.I.specProfiles["1485"], "kept when it is an imported bucket")
for name in pairs(KEPT) do
    assert(P[name].specProfiles["1485"], "kept when it holds the player's " .. name)
end

-- The other ranks of Raptor Strike (Cooldowns) and Mongoose Bite (a custom bar)
-- go. Raptor Strike under its placed ID (an explicit hide), Wing Clip (a
-- disabled bar), Feign Death (the Buffs bar), Arcane Shot (a custom spell ID)
-- and Drain Life stay hidden.
local ghost = P.G.specProfiles["253"].barSpells.__ghost_cd.assignedSpells
local WANT = { 2973, 14267, 5384, 3044, 689 }
assert(Same(ghost, WANT), "ghost after the repair: " .. Show(ghost))
assert(#P.N.specProfiles["253"].barSpells.__ghost_cd.assignedSpells == 0,
    "without saved bars the default Cooldowns bar counts")

-- Idempotent: running both bodies again over the repaired data changes nothing.
for _, bucket in pairs(P) do
    for _, prof in pairs(bucket.specProfiles) do prof._migrations = nil end
end
EllesmereUI.RunRegisteredMigrations()
assert(#EllesmereUI._migrationErrors == 0, "the second run ran without errors")
assert(Same(ghost, WANT), "a second run changes nothing: " .. Show(ghost))
assert(P.C.specProfiles["1485"] and P.S.specProfiles["1485"] and P.I.specProfiles["1485"],
    "a second run keeps the kept Forever keys")
for name in pairs(KEPT) do
    assert(P[name].specProfiles["1485"], "a second run keeps the player's " .. name)
end

-- A spell that exists but has no name yet fails the body, unstamped, and the
-- next load repairs it.
db = MakeDB()
UNNAMED[14261] = true
Run(true, db, true)
P = db.spellAssignments.profiles
local nghost = P.N.specProfiles["253"].barSpells.__ghost_cd.assignedSpells
assert(#nghost == 1 and not (P.N.specProfiles["253"]._migrations or {}).cdm_forever_ghost_rank_aliases_v1,
    "an unnamed ghost entry leaves the repair unstamped")
UNNAMED[14261] = nil
EllesmereUI.RunRegisteredMigrations()
assert(#nghost == 0, "the next load repairs it")

-------------------------------------------------------------------------------
-- Retail: nothing registers, nothing changes
-------------------------------------------------------------------------------
db = MakeDB()
Run(false, db)
P = db.spellAssignments.profiles
assert(P.B.specProfiles["1485"] and P.R.specProfiles["1485"], "retail keeps every bucket")
assert(#P.G.specProfiles["253"].barSpells.__ghost_cd.assignedSpells == 7, "retail keeps the ghost list")

print("test_cdm_forever_store_repairs: all checks passed")
