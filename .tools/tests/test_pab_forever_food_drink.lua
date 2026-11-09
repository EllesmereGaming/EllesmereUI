-- Stub harness: WoW Forever Food and Drink in Player Aura Bars filters.
-- Loads the real EllesmereUI_BuffPresets.lua and EUI_PlayerAuraBars_Filters.lua
-- (ExpandFamily cut from EllesmereUIUnitFrames_PlayerAuraBars.lua) and checks
-- that a custom filter holding rank 1 Food (433) or Drink (430) resolves every
-- eating and drinking aura, that an explicit false still wins, that the
-- Consumables preset seeds them unchecked, and that retail is unchanged.
--   lua .tools/tests/test_pab_forever_food_drink.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local PRESETS = ReadSource("EllesmereUI_BuffPresets.lua")
local FILTERS = ReadSource("EllesmereUIUnitFrames/EUI_PlayerAuraBars_Filters.lua")
local PAB_SRC = ReadSource("EllesmereUIUnitFrames/EllesmereUIUnitFrames_PlayerAuraBars.lua")

local a = assert(PAB_SRC:find("local function ExpandFamily(set, id, blocked)", 1, true), "ExpandFamily missing")
local e = assert(PAB_SRC:find("\nend\n", a, true), "end of ExpandFamily missing")
local EXPAND = PAB_SRC:sub(a, e + 4)

local FOOD = { 433, 434, 435, 1127, 1129, 1131, 29073 }
local DRINK = { 430, 431, 432, 1133, 1135, 1137, 22734 }

local function Load(forever)
    EllesmereUI = { IS_FOREVER = forever }
    assert(loadstring(PRESETS, "=EllesmereUI_BuffPresets.lua"))()
    local ns, store = {}, {}
    ns.db = { profile = { playerAuraBars = store } }
    local expand = assert(loadstring("local ns = ...\n" .. EXPAND .. "\nreturn ExpandFamily",
        "=EllesmereUIUnitFrames_PlayerAuraBars.lua"))(ns)
    ns._pabInternals = {
        ExpandFamily = expand,
        PAB = function() return store end,
        BuffBarHasContent = function() return true end,
        reloadAllSetters = {},
    }
    assert(loadstring(FILTERS, "=EUI_PlayerAuraBars_Filters.lua"))("EllesmereUIUnitFrames", ns)
    return ns, store
end

local function Resolved(ns, filterId)
    local set = {}
    for _, id in ipairs(ns.PAB_ResolveSpells({ showAllBuffs = false, filters = { [filterId] = true } })) do
        set[id] = true
    end
    return set
end

local function ExpectAll(set, ids, want, what)
    for _, id in ipairs(ids) do
        assert((set[id] == true) == want, what .. ": " .. id .. (want and " missing" or " resolved"))
    end
end

-- WoW Forever: a custom filter with rank 1 Food and Drink covers every rank.
do
    local ns = Load(true)
    local f = ns.PAB_AddFilter("Food and Drink")
    f.spells[433], f.spells[430] = true, true
    local set = Resolved(ns, f.id)
    ExpectAll(set, FOOD, true, "Forever custom filter, Food")
    ExpectAll(set, DRINK, true, "Forever custom filter, Drink")
    assert(not set[1248377] and not set[1249920], "a Nutritious Food or Drink channel joined the families")

    -- Holding a higher rank alone covers rank 1 and the rest.
    local g = ns.PAB_AddFilter("Rank 3")
    g.spells[435] = true
    ExpectAll(Resolved(ns, g.id), FOOD, true, "Forever custom filter holding rank 3")

    -- An explicit false in the filter still wins over the family.
    f.spells[434] = false
    set = Resolved(ns, f.id)
    assert(not set[434], "an unchecked rank resolved")
    assert(set[435] and set[1131], "unchecking one rank dropped the others")
end

-- WoW Forever: the Consumables preset seeds Food and Drink unchecked, so a bar
-- showing that preset shows nothing new.
do
    local ns = Load(true)
    ns.PAB_ImportBM2Filters()
    local consumables
    for _, f in ipairs(ns.PAB_Filters()) do
        if f.name == "Consumables" then consumables = f end
    end
    assert(consumables, "no Consumables preset")
    for _, id in ipairs(FOOD) do assert(consumables.spells[id] == false, "Consumables seeds " .. id .. " checked") end
    for _, id in ipairs(DRINK) do assert(consumables.spells[id] == false, "Consumables seeds " .. id .. " checked") end
    local set = Resolved(ns, consumables.id)
    ExpectAll(set, FOOD, false, "Consumables preset, Food")
    ExpectAll(set, DRINK, false, "Consumables preset, Drink")
    assert(set[17626], "the Consumables preset lost its flasks")
end

-- WoW Forever: no aura id belongs to two different curated families (the Raid
-- Frames Buff Manager maps every rank back to one primary).
do
    Load(true)
    local owner = {}
    for _, list in pairs(EllesmereUI.BUFF_PRESETS.spells) do
        for id, info in pairs(list) do
            for _, member in ipairs({ id, unpack(info.alts or {}) }) do
                assert(owner[member] == nil or owner[member] == id,
                    member .. " is in the families of " .. tostring(owner[member]) .. " and " .. id)
                owner[member] = id
            end
        end
    end
end

-- Retail: Food and Drink stay exact ids, as before.
do
    local ns = Load(false)
    assert(ns.PAB_SPELL_FAMILY[433] == nil and ns.PAB_SPELL_FAMILY[430] == nil, "retail gained a Food or Drink family")
    local f = ns.PAB_AddFilter("Food and Drink")
    f.spells[433], f.spells[430] = true, true
    local set = Resolved(ns, f.id)
    assert(set[433] and set[430], "retail lost the filter's own ids")
    assert(not set[434] and not set[431], "retail resolved another Food or Drink id")
end

print("test_pab_forever_food_drink: all passed")
