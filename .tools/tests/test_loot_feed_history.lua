-- Run from the repository root: lua .tools/tests/test_loot_feed_history.lua
local FALSE = { IsMouseOver = true, IsPlaying = true, IsShown = true, IsForbidden = true }
local NUMBER = { GetWidth = true, GetHeight = true, GetEffectiveScale = true, GetStringWidth = true }
local Fake
local wheelCalls = 0 -- EnableMouseWheel calls on any frame
local mt = {
    __call = function() return Fake() end,
    __index = function(t, k)
        if k == "EnableMouseWheel" then return function() wheelCalls = wheelCalls + 1 end end
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
    ApplyModuleFont = function() end, GetBorderCompanion = function() end }
setmetatable(EllesmereUI, { __index = function() return function() end end })
local who = dofile(".tools/tests/char_roster_stub.lua")(EllesmereUI, { guid = "Player-1" })
local cfg = { enabled = true, history = true, maxRows = 3 }
EllesmereUIDB = { lootFeed = cfg }
local module = {
    Feature = function(_, defaults)
        return { Get = function(k) if cfg[k] == nil then return defaults[k] end return cfg[k] end,
            Cfg = function() return cfg end, Enabled = function() return true end, Start = function() end,
            Place = function() end, Read = function() return cfg end }
    end,
}
-- Items: none is cached until a test says so; a load the feed waits for is kept in `waiting`.
Enum = { ItemClass = { Weapon = 2, Armor = 4, Questitem = 12 }, ItemBind = { Quest = 4, OnAcquire = 1 } }
ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } }
local cached, waiting = {}, {}
C_Item = {
    GetItemInfo = function(link)
        if not cached[link] then return nil end
        return "Sample " .. link, link, 1, 1, nil, nil, nil, nil, nil, 134400, 0, 15, nil, 0
    end,
}
Item = {}
function Item:CreateFromItemLink(link)
    return { ContinueOnItemLoad = function(_, fn) waiting[#waiting + 1] = { link = link, fn = fn } end }
end
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
local list = EllesmereUIDB.chars["Player-1"].lootFeedHistory
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

-- Only a change of Shift arms or disarms the wheel: Ctrl and Alt fire the same event and touch no frame.
local calls = wheelCalls
onEvent(nil, "MODIFIER_STATE_CHANGED", "LCTRL", 1)
onEvent(nil, "MODIFIER_STATE_CHANGED", "LALT", 1)
assert(wheelCalls == calls, "Ctrl and Alt alone leave the wheel as it is")
shift = true
onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
assert(wheelCalls > calls, "Shift down arms the wheel")
calls = wheelCalls
onEvent(nil, "MODIFIER_STATE_CHANGED", "LCTRL", 1)
onEvent(nil, "MODIFIER_STATE_CHANGED", "LCTRL", 0)
assert(wheelCalls == calls, "another modifier while Shift is held arms nothing again")
shift = false
onEvent(nil, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
assert(wheelCalls > calls, "letting go of Shift disarms it")

-- Show Samples: a sample is never kept, also when the client loads its item only afterwards.
cfg.skills, cfg.reputation, cfg.money, cfg.rolls, cfg.items = false, false, false, false, true
local preview = EllesmereUI._LootFeed.Preview
local kept, top = #list, list[1].text
preview()
assert(#waiting == 3 and #list == kept, "the samples wait for their items and nothing is kept")
for _, w in ipairs(waiting) do
    cached[w.link] = true
    w.fn()
end
assert(#list == kept and list[1].text == top, "a sample whose item loads late is not kept")
assert(Upvalue(push, "sampling") == nil, "and the feed is live again afterwards")
preview()
assert(#list == kept, "nor are samples of cached items")

-- A real loot line whose item loads late is kept as before.
local showItem = assert(Upvalue(preview, "ShowItem"), "ShowItem not reachable")
waiting = {}
showItem("item:late", 1, nil, true)
assert(#waiting == 1 and #list == kept, "the loot line waits for its item")
cached["item:late"] = true
waiting[1].fn()
assert(#list == math.min(kept + 1, 50) and list[1].text ~= top, "and is kept once the item has loaded")

local newest = list[1].text
who.guid = nil
apply()
push("item:nokey", Row("nokey", "No Key"))
local stores = 0
for _ in pairs(EllesmereUIDB.chars) do stores = stores + 1 end
assert(stores == 1 and list[1].text == newest, "nothing is kept while the character key is unknown")

print("loot feed history OK")
