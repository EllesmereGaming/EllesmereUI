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
    UnitLevel = function() return state.level end
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
    macros = { EUI_Drink = 1, EUI_Healthstone = 2, EUI_Soulstone = 3, EUI_HealingPotion = 4 },
    bags = { [8079] = 5, [1645] = 3, [1205] = 10, [19013] = 1, [5512] = 1, [16896] = 1,
        [13446] = 2, [1710] = 4, [929] = 1 },
    minLevel = { [8079] = 55, [1645] = 35, [1205] = 15, [13446] = 45, [1710] = 21, [929] = 12 },
}
local up = Load(true, state)
up.OnEvent(up, "PLAYER_ENTERING_WORLD")
Eq(state.bodies.EUI_Drink, "#showtooltip item:1205\n/use item:1205", "drink: best usable, one line")
Eq(state.bodies.EUI_Healthstone, "#showtooltip item:19013\n/use item:19013\n/use item:5512", "healthstones owned")
Eq(state.bodies.EUI_Soulstone, "#showtooltip item:16896\n/use item:16896", "soulstone")
Eq(state.bodies.EUI_HealingPotion, "#showtooltip item:1710\n/use item:1710\n/use item:929", "potions above level skipped")
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

state.bodies = {}
state.macros = {}
up.OnEvent(up, "BAG_UPDATE_DELAYED")
assert(not up.ev.BAG_UPDATE_DELAYED and not up.ev.PLAYER_LEVEL_UP, "no macro left: upkeep disarmed")

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
