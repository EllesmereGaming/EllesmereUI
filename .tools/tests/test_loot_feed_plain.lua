-- Run from the repository root: lua .tools/tests/test_loot_feed_plain.lua
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
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
local lookups = 0
C_Item = { GetItemInfoInstant = function(name)
    lookups = lookups + 1
    if name == "Raw Longjaw Mud Snapper" then return 6289 end
    if name == "Box of Explosives x2" then return 4242 end
end }

local s = Loot("You receive loot: [Raw Longjaw Mud Snapper].")
assert(s and s[1] == "item:6289" and s[2] == 1 and s[4] == true and s[5] == true,
    "a plain fishing catch resolves by name and counts as loot")

s = Loot("You receive loot: [Raw Longjaw Mud Snapper]x3.")
assert(s and s[1] == "item:6289" and s[2] == 3, "a plain multiple keeps its count")

s = Loot("You receive loot: [Box of Explosives x2]x4.")
assert(s and s[1] == "item:4242" and s[2] == 4, "a name containing x and digits keeps its own count")

assert(Loot("You receive loot: [Unknown Thing].") == nil, "an unresolvable name shows nothing")

lookups = 0
local link = "|cffffffff|Hitem:6289::::::::60:::::|h[Raw Longjaw Mud Snapper]|h|r"
s = Loot("You receive loot: " .. link .. ".")
assert(s and s[1] == link and lookups == 0, "a linked line keeps its link without a name lookup")

print("loot feed plain item names OK")
