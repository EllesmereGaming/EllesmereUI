-- Stub harness: Nameplates Simple Coloring When Not In M+ on neutral enemies.
-- Cuts the health-bar color chain (GetReactionColor with ResolveNeutralColor) from
-- EUI_Nameplates_Colors.lua and the out-of-combat darkening (MaybeDarken) from
-- EUI_Nameplates_ClassPower.lua, and drives:
--   1. outside 5-man dungeons with Simple Coloring on, a neutral enemy in combat takes All Enemies,
--      as a hostile enemy does, with and without health-bar threat data;
--   2. a neutral enemy out of combat keeps the Neutral color;
--   3. inside a 5-man dungeon, or with Simple Coloring off or unset, a neutral enemy in combat keeps
--      the Enemies color;
--   4. the other enemies keep their colors: hostile mobs, mob types with Simple Coloring off, enemy
--      players (class color, or the enemy color with Enemy Players Use Enemy Color), tapped mobs.
--   lua .tools/tests/test_np_simple_coloring_neutral.lua        (from the repository root)
local COLORS = NP_COLORS or "EllesmereUINameplates/EUI_Nameplates_Colors.lua"
local CLASSPOWER = NP_CLASSPOWER or "EllesmereUINameplates/EUI_Nameplates_ClassPower.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    return s
end

local function Cut(src, what, from, to)
    local a = assert(src:find(from, 1, true), what .. ": start not found")
    local b = assert(src:find(to, a, true), what .. ": end not found")
    return src:sub(a, b - 1)
end

local colorsSrc = Read(COLORS)
local cpSrc = Read(CLASSPOWER)
local chainCut = Cut(colorsSrc, "the color chain", "local function _C(key)", "\nI._C, I.GetReactionColor")
local darkenCut = Cut(cpSrc, "MaybeDarken", "local function DarkenColor(", "\nI.ApplyClassPowerSetting")

-------------------------------------------------------------------------------
--  Stubs: one unit at a time, described by a table
-------------------------------------------------------------------------------
local U = {}
function issecretvalue() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function UnitIsTapDenied() return U.tapped == true end
function UnitIsUnit(a, b)
    if b == "target" then return U.isTarget == true end
    if b == "focus" then return U.isFocus == true end
    return false
end
function UnitReaction() return U.reaction end
function UnitCanAttack() return U.canAttack ~= false end
function UnitIsEnemy() return U.reaction ~= nil and U.reaction <= 3 end
function UnitIsPlayer() return U.player == true end
function UnitClass() return nil, U.class end
function UnitAffectingCombat() return U.combat == true end
function UnitClassification() return U.classification or "normal" end
function UnitEffectiveLevel(unit) if unit == "player" then return 60 end return U.level or 60 end
function UnitIsLieutenant() return false end
function UnitHasPowerType() return U.mana == true end
function UnitThreatSituation() return U.threat end
function UnitExists() return false end
function UnitGroupRolesAssigned() return "NONE" end
Enum = { PowerType = { Mana = 0 } }
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
EllesmereUI = {}

local RED = { r = 0.800, g = 0.137, b = 0.137 }
local defaults = {
    enemyInCombat = RED,
    owBasicColoring = false,
    owBasicColor = { r = 0.800, g = 0.137, b = 0.137 },
    neutral = { r = 0.81, g = 0.72, b = 0.19 },
    tapped = { r = 0.50, g = 0.50, b = 0.50 },
    caster = { r = 0.231, g = 0.510, b = 0.965 },
    miniboss = { r = 0.518, g = 0.243, b = 0.984 },
    boss = { r = 0.518, g = 0.243, b = 0.984 },
    target = { r = 0.459, g = 0.890, b = 0.580 },
    targetColorEnabled = false,
    focus = { r = 0.051, g = 0.820, b = 0.620 },
    focusColorEnabled = true,
    miniColoringMPlusOnly = false,
    darkenEnemiesOOC = true,
    darkenOOCRecolor = false,
    darkenOOCColor = { r = 0.5, g = 0.5, b = 0.5 },
    enemyPlayerEnemyColor = false,
    threatColorHealth = true,
    dpsNoAggroEnabled = false,
    tankHasAggroEnabled = false,
    classicTankAggro = false,
    offTankAggroEnabled = true,
}

local ns = { _inDungeon = false, _npThreatColorsOn = false }
local chunk = assert(loadstring(
    "local ns, defaults, ThreatShared, InRealInstancedContent, IsQuestMob = ...\n"
    .. "local p\nlocal _isTankRole = false\n"
    .. darkenCut .. "\n" .. chainCut
    .. "\nreturn GetReactionColor, function(v) p = v end\n", "=cut"))
local GetReactionColor, SetProfile = chunk(ns, defaults,
    function() return false end,      -- solo, no pet out
    function() return false end,      -- open world
    function() return false end)      -- no quest mob

local BLUE = { r = 0.10, g = 0.30, b = 0.90 }
local GREEN = { r = 0.20, g = 0.80, b = 0.20 }

local function Same(r, g, b, c, f)
    f = f or 1
    local eps = 1e-6
    return math.abs(r - c.r * f) < eps and math.abs(g - c.g * f) < eps and math.abs(b - c.b * f) < eps
end
local function Expect(unit, c, f, label)
    for k in pairs(U) do U[k] = nil end
    for k, v in pairs(unit) do U[k] = v end
    local r, g, b = GetReactionColor("nameplate1", nil)
    check(Same(r, g, b, c, f), label .. ": got " .. string.format("%.3f %.3f %.3f", r, g, b))
end

local HOSTILE = 2
local NEUTRAL = 4

-------------------------------------------------------------------------------
--  1. Simple Coloring on, outside 5-man dungeons
-------------------------------------------------------------------------------
SetProfile({ owBasicColoring = true, owBasicColor = BLUE, enemyInCombat = GREEN })
ns._inDungeon = false
ns._npThreatColorsOn = false
Expect({ reaction = HOSTILE, combat = true }, BLUE, 1, "hostile mob in combat")
Expect({ reaction = HOSTILE, combat = false }, BLUE, 0.6, "hostile mob out of combat (darkened)")
Expect({ reaction = HOSTILE, combat = true, mana = true }, BLUE, 1, "hostile caster in combat")
Expect({ reaction = HOSTILE, combat = true, classification = "elite", level = 62 }, BLUE, 1,
    "hostile elite two levels up in combat")
Expect({ reaction = NEUTRAL, combat = true }, BLUE, 1, "neutral mob in combat, no threat colors")
Expect({ reaction = NEUTRAL, combat = true, mana = true }, BLUE, 1, "neutral caster in combat")
Expect({ reaction = NEUTRAL, combat = false }, defaults.neutral, 1, "neutral mob out of combat")
-- health-bar threat data on (WoW Forever's default, Group or Pet), solo without a pet
ns._npThreatColorsOn = true
Expect({ reaction = NEUTRAL, combat = true, threat = 3 }, BLUE, 1, "neutral mob in combat with threat data")
Expect({ reaction = NEUTRAL, combat = false, threat = 0 }, defaults.neutral, 1,
    "neutral mob out of combat with threat data")
Expect({ reaction = HOSTILE, combat = true, threat = 3 }, BLUE, 1, "hostile mob in combat with threat data")
ns._npThreatColorsOn = false

-------------------------------------------------------------------------------
--  2. Simple Coloring on, inside a 5-man dungeon: it does not apply
-------------------------------------------------------------------------------
ns._inDungeon = true
Expect({ reaction = NEUTRAL, combat = true }, GREEN, 1, "dungeon: neutral mob in combat")
Expect({ reaction = NEUTRAL, combat = true, classification = "elite" }, GREEN, 1,
    "dungeon: neutral elite in combat")
Expect({ reaction = HOSTILE, combat = true }, GREEN, 1, "dungeon: hostile mob in combat")
Expect({ reaction = HOSTILE, combat = true, mana = true, classification = "elite" }, defaults.caster, 1,
    "dungeon: hostile elite caster")
ns._inDungeon = false

-------------------------------------------------------------------------------
--  3. Simple Coloring off, or unset
-------------------------------------------------------------------------------
SetProfile({ owBasicColoring = false, owBasicColor = BLUE, enemyInCombat = GREEN })
Expect({ reaction = NEUTRAL, combat = true }, GREEN, 1, "off: neutral mob in combat")
Expect({ reaction = NEUTRAL, combat = false }, defaults.neutral, 1, "off: neutral mob out of combat")
Expect({ reaction = HOSTILE, combat = true }, GREEN, 1, "off: hostile mob in combat")
Expect({ reaction = HOSTILE, combat = true, mana = true, classification = "elite" }, defaults.caster, 1,
    "off: hostile elite caster")
SetProfile({ owBasicColor = BLUE, enemyInCombat = GREEN })
Expect({ reaction = NEUTRAL, combat = true }, GREEN, 1, "unset: neutral mob in combat")
SetProfile(nil)
Expect({ reaction = NEUTRAL, combat = true }, RED, 1, "no profile: neutral mob in combat")

-------------------------------------------------------------------------------
--  4. Enemy players and tapped mobs
-------------------------------------------------------------------------------
SetProfile({ owBasicColoring = true, owBasicColor = BLUE, enemyInCombat = GREEN })
Expect({ reaction = HOSTILE, combat = true, player = true, class = "MAGE" }, RAID_CLASS_COLORS.MAGE, 1,
    "enemy player: class color")
SetProfile({ owBasicColoring = true, owBasicColor = BLUE, enemyInCombat = GREEN, enemyPlayerEnemyColor = true })
Expect({ reaction = HOSTILE, combat = true, player = true, class = "MAGE" }, BLUE, 1,
    "enemy player with Enemy Players Use Enemy Color")
Expect({ reaction = NEUTRAL, combat = true, tapped = true }, defaults.tapped, 1, "tapped neutral mob")

print(string.format("simple coloring neutral: %d checks, %d failed", count, fails))
if fails > 0 then error(fails .. " check(s) failed") end
