if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ForeverStats.lua
--  WoW Forever has none of retail's ratings, so its Secondary Stats block
--  shows the character pane's stats instead. This is that catalog, grouped as
--  the Choose Stats window lists it. Loads before EllesmereUIQoL.lua, which
--  reads ns.FvStats (nil on every other client) for the block's rows, their
--  default order and the default hidden set.
-------------------------------------------------------------------------------
local _, ns = ...
local floor = math.floor

-- A sum or a scale is arithmetic, which a secret refuses: those getters
-- hand back nil (drawn as "?") rather than error.
local function Sum(...)
    local total = 0
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if issecretvalue(v) then return nil end
        total = total + (v or 0)
    end
    return total
end
local function SchoolPower(i) return function() return GetSpellBonusDamage(i) end end
local function Resist(i) return function() return (select(2, UnitResistance("player", i))) end end

local NUM, PCT = "%.0f", "%.2f%%"

-- key, label, abbreviated label, label hue, figure format, getter, shown by default
local function S(key, label, short, hex, fmt, get, on)
    return { key = key, label = label, short = short, hex = hex, fmt = fmt, get = get, on = on }
end

local GROUPS = {
    { title = "Offensive", stats = {
        S("ap",     "Attack Power", "AP",      "ff8c42", NUM, function() return Sum(UnitAttackPower("player")) end, true),
        S("rap",    "Ranged AP",    "RAP",     "ff8c42", NUM, function() return Sum(UnitRangedAttackPower("player")) end),
        S("mcrit",  "Melee Crit",   "M.Crit",  "ffd100", PCT, GetCritChance),
        S("rcrit",  "Ranged Crit",  "R.Crit",  "ffd100", PCT, GetRangedCritChance),
        S("mhaste", "Melee Haste",  "M.Haste", "7fe3d4", PCT, GetMeleeHaste),
        -- Base and ammo haste, as the character pane adds them.
        S("rhaste", "Ranged Haste", "R.Haste", "7fe3d4", PCT, function() return Sum(GetRangedHaste()) end),
        S("mhit",   "Melee Hit",    "Hit",     "ffa94d", PCT, GetHitModifier),
    } },
    { title = "Spell", stats = {
        -- The highest school's bonus, so school-specific gear counts.
        S("sp", "Spell Power", "SP", "c77dff", NUM, function()
            local best = 0
            for i = 2, 7 do
                local v = GetSpellBonusDamage(i)
                if issecretvalue(v) then return nil end
                if v > best then best = v end
            end
            return best
        end),
        S("healing", "Healing Power", "Heal",    "4ec9b0", NUM, GetSpellBonusHealing),
        S("scrit",   "Spell Crit",    "S.Crit",  "ffd100", PCT, GetSpellCritChance),
        S("shaste",  "Spell Haste",   "S.Haste", "7fe3d4", PCT, function() return UnitSpellHaste("player") end),
        S("shit",    "Spell Hit",     "S.Hit",   "ffa94d", PCT, GetSpellHitModifier),
        S("spen",    "Spell Pen",     "S.Pen",   "b39ddb", NUM, GetSpellPenetration),
    } },
    { title = "Spell Power / School", stats = {
        S("sp_holy",   "Holy SP",   "Holy",   "fff2b0", NUM, SchoolPower(2)),
        S("sp_fire",   "Fire SP",   "Fire",   "ff6b35", NUM, SchoolPower(3)),
        S("sp_frost",  "Frost SP",  "Frost",  "3fc7eb", NUM, SchoolPower(5)),
        S("sp_nature", "Nature SP", "Nature", "4caf50", NUM, SchoolPower(4)),
        S("sp_shadow", "Shadow SP", "Shadow", "a335ee", NUM, SchoolPower(6)),
        S("sp_arcane", "Arcane SP", "Arcane", "ff7eb6", NUM, SchoolPower(7)),
    } },
    { title = "Defensive", stats = {
        S("armor",    "Armor",       "Armor", "b0bec5", NUM, function() return (select(2, UnitArmor("player"))) end),
        S("defense",  "Defense",     "Def",   "b0bec5", NUM, function() return Sum(UnitDefenseSkill("player")) end),
        S("dodge",    "Dodge",       "Dodge", "64b5f6", PCT, GetDodgeChance),
        S("parry",    "Parry",       "Parry", "64b5f6", PCT, GetParryChance),
        S("block",    "Block",       "Block", "64b5f6", PCT, GetBlockChance),
        S("blockval", "Block Value", "Blk V", "64b5f6", NUM, GetShieldBlock),
    } },
    -- No Holy: resistance index 1 is no player stat (always 0, not on the pane).
    { title = "Resistances", stats = {
        S("res_fire",   "Fire Resist",   "Fire R",  "ff6b35", NUM, Resist(2)),
        S("res_frost",  "Frost Resist",  "Frost R", "3fc7eb", NUM, Resist(4)),
        S("res_nature", "Nature Resist", "Nat R",   "4caf50", NUM, Resist(3)),
        S("res_shadow", "Shadow Resist", "Shad R",  "a335ee", NUM, Resist(5)),
        S("res_arcane", "Arcane Resist", "Arc R",   "ff7eb6", NUM, Resist(6)),
    } },
    { title = "Regen & Utility", stats = {
        S("mp5", "Mana Regen", "MP5", "4fc3f7", NUM, function()
            local regen = GetManaRegen()
            if issecretvalue(regen) then return nil end
            return floor(regen * 5)
        end, true),
        S("hp5", "Health Regen", "HP5", "e57373", NUM, function()
            local regen = GetHealthRegen()
            if issecretvalue(regen) then return nil end
            return floor(regen * 5)
        end, true),
        -- Run speed against the base 7 yards a second.
        S("movespeed", "Movement Speed", "MS", "81c784", "%.0f%%", function()
            local run = select(2, GetUnitSpeed("player"))
            if issecretvalue(run) then return nil end
            return floor(run / 7 * 100 + 0.5)
        end, true),
    } },
}

-- order: every key, group by group (the block's default order). hidden: the
-- profile default for secondaryStatsHidden, every stat not shown by default.
local byKey, order, hidden = {}, {}, {}
for _, g in ipairs(GROUPS) do
    for _, s in ipairs(g.stats) do
        byKey[s.key] = s
        order[#order + 1] = s.key
        if not s.on then hidden[s.key] = true end
    end
end

ns.FvStats = { groups = GROUPS, byKey = byKey, order = order, hidden = hidden }
