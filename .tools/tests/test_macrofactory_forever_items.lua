-- Stub harness: on WoW Forever the Macro Factory's item macros list only items in the
-- bags that the player's level can use, and the upkeep rewrites them on bag changes and
-- level-ups. On retail the item macro bodies stay as they were.
-- Run from the repository root: lua .tools/tests/test_macrofactory_forever_items.lua
local function Load(isForever, state)
    local frames = {}
    CreateFrame = function()
        local f = { ev = {} }
        frames[#frames + 1] = f
        function f:RegisterEvent(e) self.ev[e] = true end
        function f:RegisterUnitEvent(e) self.ev[e] = true end
        function f:UnregisterEvent(e) self.ev[e] = nil end
        function f:UnregisterAllEvents() self.ev = {} end
        function f:IsEventRegistered(e) return self.ev[e] end
        function f:SetScript(k, fn) self[k] = fn end
        return f
    end
    EUI_CLIENT_BLOCKED = false
    EllesmereUIDB = nil
    EllesmereUI = {
        IS_FOREVER = isForever, _Pool = {}, _ModuleNS = { EllesmereUIQoL = {} },
        L = function(s) return s end,
        RegisterOnShow = function() end, RegisterOnHide = function() end,
        CombatQueue = { Defer = function() end },
    }
    if isForever then
        EllesmereUI.FOREVER_HEALTHSTONES = { 9421, 19012, 19013, 5510, 19010, 19011, 5509,
            19008, 19009, 5511, 19006, 19007, 19004, 19005 }
    end
    C_Item = {
        GetItemCount = function(id) return state.bags[id] or 0 end,
        GetItemInfo = function(id) return "name", "link", 1, 1, state.minLevel[id] end,
    }
    C_SpellBook = { IsSpellKnown = function(id) return (state.known or {})[id] == true end }
    C_Spell = {
        GetSpellInfo = function(id) return state.spellNames and state.spellNames[id] and { name = state.spellNames[id] } end,
        RequestLoadSpellData = function() end,
    }
    UnitLevel = function() return state.level end
    UnitClass = function() return "Class", state.class or "WARLOCK" end
    InCombatLockdown = function() return false end
    GetMacroIndexByName = function(n) return state.macros[n] or 0 end
    EditMacro = function(i, _, _, body)
        for name, idx in pairs(state.macros) do
            if idx == i then state.bodies[name] = body end
        end
    end
    assert(loadfile("EUI_MacroFactory.lua"))()
    return frames[1]
end

local function Eq(got, want, what)
    if got ~= want then
        error(what .. ":\n  got:  " .. tostring(got) .. "\n  want: " .. tostring(want), 2)
    end
end

-- Forever
local state = {
    level = 30, bodies = {},
    macros = { EUI_Drink = 1, EUI_Healthstone = 2, EUI_Soulstone = 3, EUI_HealingPotion = 4, EUI_Food = 5 },
    bags = { [8079] = 5, [1645] = 3, [1205] = 10, [19013] = 1, [5512] = 1, [16896] = 1,
        [13446] = 2, [1710] = 4, [929] = 1, [8950] = 5, [4542] = 5, [3771] = 2 },
    minLevel = { [8079] = 55, [1645] = 35, [1205] = 15, [13446] = 45, [1710] = 21, [929] = 12,
        [8950] = 45, [4542] = 15, [3771] = 25 },
}
local up = Load(true, state)
up.OnEvent(up, "PLAYER_ENTERING_WORLD")
Eq(state.bodies.EUI_Drink, "#showtooltip item:1205\n/use item:1205", "drink: best usable, one line")
Eq(state.bodies.EUI_Food, "#showtooltip item:3771\n/use item:3771", "food: best usable vendor tier")
Eq(state.bodies.EUI_Healthstone, "#showtooltip item:19013\n/use item:19013\n/use item:5512", "healthstones owned")
Eq(state.bodies.EUI_Soulstone, "#showtooltip item:16896\n/use item:16896", "soulstone")
Eq(state.bodies.EUI_HealingPotion, "#showtooltip item:1710\n/use item:1710\n/use item:929", "potions above level skipped")
EllesmereUIDB.macroFactory.EUI_Soulstone.friendlyTarget = true
state.bodies = {}
state.bags[16896] = nil; state.bags[16895] = 1
up.OnEvent(up, "BAG_UPDATE_DELAYED")
Eq(state.bodies.EUI_Soulstone, "#showtooltip item:16895\n/use [@target,help,nodead][@player] item:16895", "soulstone friendly target toggle")
assert(up.ev.BAG_UPDATE_DELAYED and up.ev.PLAYER_LEVEL_UP, "upkeep armed with level-up on Forever")

state.bodies = {}
up.OnEvent(up, "PLAYER_LEVEL_UP", 35)
Eq(state.bodies.EUI_Drink, "#showtooltip item:1645\n/use item:1645", "drink after level-up")

state.bodies = {}
state.bags[1645] = nil
up.OnEvent(up, "BAG_UPDATE_DELAYED")
Eq(state.bodies.EUI_Drink, "#showtooltip item:1205\n/use item:1205", "drink after the last juice")
Eq(state.bodies.EUI_HealingPotion, nil, "unchanged macro not rewritten")

state.bodies = {}
state.bags = {}
up.OnEvent(up, "BAG_UPDATE_DELAYED")
Eq(state.bodies.EUI_Drink, "#showtooltip item:8079\n/use item:8079", "nothing owned: first enabled item")
Eq(state.bodies.EUI_Healthstone, "#showtooltip item:9421\n/use item:9421", "no healthstone: first enabled stone")

EllesmereUIDB.macroFactory.EUI_Healthstone.createWhenOut = true
state.known = { [6201] = true, [11730] = true }
state.spellNames = { [11730] = "Create Healthstone" }
state.bodies = {}
up.OnEvent(up, "SPELLS_CHANGED")
Eq(state.bodies.EUI_Healthstone, nil, "healthstone never creates")

local ssDB = EllesmereUIDB.macroFactory.EUI_Soulstone
ssDB.createWhenOut = true
state.bodies = {}
up.OnEvent(up, "SPELLS_CHANGED")
Eq(state.bodies.EUI_Soulstone, nil, "Create When Out, spell not known: unchanged")

state.known[20755] = true; state.known[20756] = true
state.spellNames[20756] = "Create Soulstone"
state.bags[16893] = 1
state.bodies = {}
up.OnEvent(up, "SPELLS_CHANGED")
Eq(state.bodies.EUI_Soulstone, "#showtooltip item:16893\n/use [@target,help,nodead][@player] item:16893\n/cast Create Soulstone",
    "soulstone held: use, then create")
state.bags[16893] = nil
up.OnEvent(up, "BAG_UPDATE_DELAYED")
Eq(state.bodies.EUI_Soulstone, "#showtooltip item:16895\n/use [@target,help,nodead][@player] item:16895\n/cast Create Soulstone",
    "no soulstone: the highest rank's stone, then create")

state.bodies = {}
ssDB.showTooltip = false
up.OnEvent(up, "BAG_UPDATE_DELAYED")
Eq(state.bodies.EUI_Soulstone, "/use [@target,help,nodead][@player] item:16895\n/cast Create Soulstone", "create without tooltip line")

state.bodies = {}
state.macros = {}
up.OnEvent(up, "BAG_UPDATE_DELAYED")
assert(not up.ev.BAG_UPDATE_DELAYED and not up.ev.PLAYER_LEVEL_UP, "no macro left: upkeep disarmed")

-- Forever imbue stones, and the Warlock-only macros on another class
state = {
    level = 60, bodies = {}, macros = { EUI_Firestone = 1, EUI_Spellstone = 2 },
    bags = {}, minLevel = {}, known = { [6366] = true, [17951] = true }, spellNames = { [17951] = "Create Firestone" },
}
up = Load(true, state)
up.OnEvent(up, "PLAYER_ENTERING_WORLD")
Eq(state.bodies.EUI_Firestone, "#showtooltip item:13701\n/use item:13701\n/use 16", "firestone: imbue the main hand")
EllesmereUIDB.macroFactory.EUI_Firestone.createWhenOut = true
up.OnEvent(up, "SPELLS_CHANGED")
Eq(state.bodies.EUI_Firestone, "#showtooltip item:13699\n/use item:13699\n/use 16\n/cast Create Firestone",
    "firestone: the known rank's stone, imbue, then create")
state.bags[13699] = 1
state.bodies = {}
up.OnEvent(up, "BAG_UPDATE_DELAYED")
Eq(state.bodies.EUI_Firestone, nil, "firestone created: the macro already uses it")

state = { level = 60, class = "MAGE", bodies = {}, macros = { EUI_Soulstone = 1, EUI_Firestone = 2 },
    bags = { [16896] = 1 }, minLevel = {} }
up = Load(true, state)
up.OnEvent(up, "PLAYER_ENTERING_WORLD")
Eq(state.bodies.EUI_Soulstone, nil, "no Warlock macros on a Mage")
Eq(state.bodies.EUI_Firestone, nil, "no Warlock macros on a Mage")

-- Retail
local retail = {
    level = 80, bodies = {}, macros = { EUI_Food = 1 },
    bags = { [260263] = 1 }, minLevel = { [260263] = 90 },
}
up = Load(false, retail)
up.OnEvent(up, "PLAYER_ENTERING_WORLD")
Eq(retail.bodies.EUI_Food, "#showtooltip item:260263\n/use item:113509\n/use item:260262\n/use item:260263"
    .. "\n/use item:260264\n/use item:242297\n/use item:260260\n/use item:1226196\n/use item:242299"
    .. "\n/use item:242301\n/use item:242298\n/use item:260259", "retail food unchanged, no level check")
assert(not up.ev.PLAYER_LEVEL_UP, "retail upkeep has no level-up event")

print("test_macrofactory_forever_items: OK")
