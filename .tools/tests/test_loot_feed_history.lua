-- Run from the repository root: lua .tools/tests/test_loot_feed_history.lua
local FALSE = { IsMouseOver = true, IsPlaying = true, IsShown = true, IsForbidden = true }
local NUMBER = { GetWidth = true, GetHeight = true, GetEffectiveScale = true, GetStringWidth = true }
local Fake
local mt = {
    __call = function() return Fake() end,
    __index = function(t, k)
        if FALSE[k] then return function() return false end end
        if NUMBER[k] then return function() return 1 end end
        if k:match("^%l") then return nil end
        local v = Fake()
        rawset(t, k, v)
        return v
    end,
}
Fake = function() return setmetatable({}, mt) end
CreateFrame = function() return Fake() end
CreateColor = function() return Fake() end
issecretvalue = function() return false end
UnitName = function() return "Direktsaft Traube" end
local shift = true
IsShiftKeyDown = function() return shift end
EllesmereUI = { IS_FOREVER = true, _Pool = {}, PP = Fake(),
    L = function(s) return s end, Lf = function(s, ...) return s:format(...) end,
    CharKey = function(sep) return "Direktsaft Traube" .. sep .. "Forever" end,
    ApplyModuleFont = function() end, GetBorderCompanion = function() end }
setmetatable(EllesmereUI, { __index = function() return function() end end })
local cfg = { enabled = true, history = true, maxRows = 3 }
EllesmereUIDB = { lootFeed = cfg }
local module = {
    Feature = function(_, defaults)
        return { Get = function(k) if cfg[k] == nil then return defaults[k] end return cfg[k] end,
            Cfg = function() return cfg end, Enabled = function() return true end, Start = function() end,
            Place = function() end, Read = function() return cfg end }
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
        if key == name then return value end
        if type(value) == "function" then
            local found = Upvalue(value, name, seen)
            if found ~= nil then return found end
        end
    end
end
local apply = EllesmereUI._LootFeed.Apply
apply()
local push = assert(Upvalue(apply, "Push"), "Push not reachable")
local onWheel = assert(Upvalue(apply, "OnWheel"), "OnWheel not reachable")
local onEvent = assert(Upvalue(apply, "OnEvent"), "OnEvent not reachable")
local active = assert(Upvalue(push, "active"))
local QUALITY = { r = 0, g = 0.44, b = 0.87, hex = "|cff0070dd", color = { GetRGB = function() end } }

local function Row(key, text) return { text = text, icon = 1, border = QUALITY, link = "link:" .. key } end

push("item:a", Row("a", "Staff"))
push("money", Row("m", "Money 1"))
push("money", Row("m", "Money 2"))
assert(cfg.historyByChar == nil, "the history stays out of the settings")
local list = EllesmereUIDB.lootFeedHistory["Direktsaft Traube - Forever"]
assert(list and #list == 2, "kept per character; a refilled row updates its entry")
assert(list[1].text == "Money 2" and list[1].key == "money" and list[2].text == "Staff", "newest first")
assert(list[2].border.r == 0 and list[2].border.color == nil and list[2].border.hex == nil,
    "the quality color is kept as plain rgb")

for i = 1, 205 do push("item:" .. i, Row(i, "Item " .. i)) end
assert(#list == 200 and list[1].text == "Item 205", "the oldest rows beyond the default 200 drop")

local sampling = Upvalue(push, "sampling")
assert(sampling == nil, "not sampling outside Show Samples")

onWheel(nil, 1)
assert(#active == 3 and active[1].data.text == "Item 205" and active[1].history, "Shift + wheel up shows the newest rows")
onWheel(nil, 1)
onWheel(nil, 1)
assert(active[1].data.text == "Item 203", "each step goes one row further back")

for _ = 1, 300 do onWheel(nil, 1) end
assert(#active == 3 and active[3].data == list[#list], "the furthest step back still fills every row")
for _ = 1, 195 do onWheel(nil, -1) end
assert(active[1].data.text == "Item 203", "and steps forward again")

push("item:new", Row("new", "Fresh Loot"))
assert(active[1].data.text == "Item 203" and list[1].text == "Fresh Loot", "loot while looking back is kept without moving the view")

shift = false
onWheel(nil, -1)
assert(active[1].data.text == "Item 203", "without Shift the wheel does nothing")
onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
assert(#active == 1 and active[1].data.text == "Fresh Loot" and not active[1].history,
    "letting go of Shift returns to the live feed with what was looted meanwhile")
assert(#list == 200 and list[1].text == "Fresh Loot", "returning adds no second entry")

cfg.historyMax = 50
apply()
assert(#list == 50 and list[1].text == "Fresh Loot", "a lower Rows to Keep trims the oldest rows")
push("item:after", Row("after", "After"))
assert(#list == 50 and list[1].text == "After", "and keeps to the new length")

EllesmereUI.CharKey = function() return nil end
apply()
push("item:nokey", Row("nokey", "No Key"))
local stores = 0
for _ in pairs(EllesmereUIDB.lootFeedHistory) do stores = stores + 1 end
assert(stores == 1 and list[1].text == "After", "nothing is kept while the character key is unknown")

print("loot feed history OK")
