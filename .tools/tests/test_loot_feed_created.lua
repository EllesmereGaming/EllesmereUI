-- Run from the repository root: lua .tools/tests/test_loot_feed_created.lua
CreateColor = function() return {} end
EllesmereUI = { IS_FOREVER = true, _Pool = {} }
local module = {
    Feature = function()
        return { Get = function() return true end, Cfg = function() return {} end,
            Enabled = function() return true end, Start = function() end }
    end,
}
assert(loadfile("EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_LootFeed.lua"))("test", module)

local function Upvalue(fn, name, seen)
    seen = seen or {}
    if type(fn) ~= "function" or seen[fn] then return end
    seen[fn] = true
    for i = 1, math.huge do
        local key, value = debug.getupvalue(fn, i)
        if not key then return end
        if key == name then return value, fn, i end
        if type(value) == "function" then
            local found, owner, index = Upvalue(value, name, seen)
            if owner then return found, owner, index end
        end
    end
end

local events = assert(Upvalue(EllesmereUI._LootFeed.Apply, "CHAT_EVENTS"), "CHAT_EVENTS not reachable")
local onLoot = events.CHAT_MSG_LOOT.handler
local shown
local _, owner, index = Upvalue(onLoot, "ShowItem")
assert(owner, "ShowItem not reachable from OnLoot")
debug.setupvalue(owner, index, function(...) shown = { ... } end)
local function Loot(text)
    shown = nil
    onLoot(text)
    return shown
end

LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_CREATED_SELF = "You create: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
local kit = "|cffffffff|Hitem:1251::::::::60:::::|h[Linen Bandage]|h|r"
C_Item = { GetItemInfoInstant = function(name)
    if name == "Bolt of Woolen Cloth" then return 2997 end
end }

local s = Loot("You create: [Bolt of Woolen Cloth].")
assert(s and s[1] == "item:2997" and s[2] == 1 and s[4] == true and s[5] == false,
    "a plain crafted item resolves by name without counting as tracker income")

s = Loot("You create: [Bolt of Woolen Cloth]x2.")
assert(s and s[1] == "item:2997" and s[2] == 2 and s[5] == false, "a plain crafted multiple keeps its count")

s = Loot("You create: " .. kit .. ".")
assert(s and s[1] == kit and s[2] == 1 and s[4] == true and s[5] == false,
    "a crafted item shows without counting as tracker income")

s = Loot("You create: " .. kit .. "x5.")
assert(s and s[1] == kit and s[2] == 5 and s[5] == false, "a crafted multiple keeps its count")

s = Loot("You receive loot: " .. kit .. ".")
assert(s and s[5] == true, "looted items still count as income")

print("loot feed crafted items OK")
