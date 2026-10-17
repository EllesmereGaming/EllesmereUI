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
-- Label hues, shared with Forever Essentials' Simplified Stats.
local HUE = EllesmereUI.FOREVER_STAT_HUES

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
        S("ap",     "Attack Power", "AP",      HUE.ap, NUM, function() return Sum(UnitAttackPower("player")) end, true),
        S("rap",    "Ranged AP",    "RAP",     HUE.ap, NUM, function() return Sum(UnitRangedAttackPower("player")) end),
        S("mcrit",  "Melee Crit",   "M.Crit",  HUE.crit, PCT, GetCritChance),
        S("rcrit",  "Ranged Crit",  "R.Crit",  HUE.crit, PCT, GetRangedCritChance),
        S("mhaste", "Melee Haste",  "M.Haste", HUE.haste, PCT, GetMeleeHaste),
        -- Base and ammo haste, as the character pane adds them.
        S("rhaste", "Ranged Haste", "R.Haste", HUE.haste, PCT, function() return Sum(GetRangedHaste()) end),
        S("mhit",   "Melee Hit",    "Hit",     HUE.hit, PCT, GetHitModifier),
        -- Off-hand hit, as the character pane shows it ("?" on a client
        -- without the getter).
        S("ohit",   "Off-hand Hit", "OH Hit",  HUE.hit, PCT, function()
            if GetOffhandHitModifier then return GetOffhandHitModifier() end
        end),
    } },
    { title = "Spell", stats = {
        -- The highest school's bonus, so school-specific gear counts.
        S("sp", "Spell Power", "SP", HUE.sp, NUM, function()
            local best = 0
            for i = 2, 7 do
                local v = GetSpellBonusDamage(i)
                if issecretvalue(v) then return nil end
                if v > best then best = v end
            end
            return best
        end),
        S("healing", "Healing Power", "Heal",    HUE.healing, NUM, GetSpellBonusHealing),
        S("scrit",   "Spell Crit",    "S.Crit",  HUE.crit, PCT, GetSpellCritChance),
        S("shaste",  "Spell Haste",   "S.Haste", HUE.haste, PCT, function() return UnitSpellHaste("player") end),
        S("shit",    "Spell Hit",     "S.Hit",   HUE.hit, PCT, GetSpellHitModifier),
        S("spen",    "Spell Pen",     "S.Pen",   HUE.spen, NUM, GetSpellPenetration),
    } },
    { title = "Spell Power / School", stats = {
        S("sp_holy",   "Holy SP",   "Holy",   HUE.holy, NUM, SchoolPower(2)),
        S("sp_fire",   "Fire SP",   "Fire",   HUE.fire, NUM, SchoolPower(3)),
        S("sp_frost",  "Frost SP",  "Frost",  HUE.frost, NUM, SchoolPower(5)),
        S("sp_nature", "Nature SP", "Nature", HUE.nature, NUM, SchoolPower(4)),
        S("sp_shadow", "Shadow SP", "Shadow", HUE.shadow, NUM, SchoolPower(6)),
        S("sp_arcane", "Arcane SP", "Arcane", HUE.arcane, NUM, SchoolPower(7)),
    } },
    { title = "Defensive", stats = {
        S("armor",    "Armor",       "Armor", HUE.armor, NUM, function() return (select(2, UnitArmor("player"))) end),
        S("defense",  "Defense",     "Def",   HUE.armor, NUM, function() return Sum(UnitDefenseSkill("player")) end),
        S("dodge",    "Dodge",       "Dodge", HUE.avoid, PCT, GetDodgeChance),
        S("parry",    "Parry",       "Parry", HUE.avoid, PCT, GetParryChance),
        S("block",    "Block",       "Block", HUE.avoid, PCT, GetBlockChance),
        S("blockval", "Block Value", "Blk V", HUE.avoid, NUM, GetShieldBlock),
    } },
    -- No Holy: resistance index 1 is no player stat (always 0, not on the pane).
    { title = "Resistances", stats = {
        S("res_fire",   "Fire Resist",   "Fire R",  HUE.fire, NUM, Resist(2)),
        S("res_frost",  "Frost Resist",  "Frost R", HUE.frost, NUM, Resist(4)),
        S("res_nature", "Nature Resist", "Nat R",   HUE.nature, NUM, Resist(3)),
        S("res_shadow", "Shadow Resist", "Shad R",  HUE.shadow, NUM, Resist(5)),
        S("res_arcane", "Arcane Resist", "Arc R",   HUE.arcane, NUM, Resist(6)),
    } },
    { title = "Regen & Utility", stats = {
        S("mp5", "Mana Regen", "MP5", HUE.mp5, NUM, function()
            local regen = GetManaRegen()
            if issecretvalue(regen) then return nil end
            return floor(regen * 5)
        end, true),
        S("hp5", "Health Regen", "HP5", HUE.hp5, NUM, function()
            local regen = GetHealthRegen()
            if issecretvalue(regen) then return nil end
            return floor(regen * 5)
        end, true),
        -- Run speed against the base 7 yards a second.
        S("movespeed", "Movement Speed", "MS", HUE.speed, "%.0f%%", function()
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
