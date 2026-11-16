-- Behavioral coverage for offline Keyring snapshots and live keyring filtering.
local TARGET = KR_TARGET or "EllesmereUIBags/EllesmereUIBags_Offline.lua"
local function check(ok, message)
    if not ok then error(message, 2) end
end

local now, charKey, keyringOn = 1000, "A-Realm", false
local scans, queued = 0, {}
local containers = { [-1] = { size = 3, items = {} } }
local registered, frames = {}, {}
local function frame()
    local f = { events = {} }
    function f:SetScript(_, fn) self.handler = fn end
    function f:RegisterEvent(e) self.events[e] = true; registered[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil; registered[e] = nil end
    frames[#frames + 1] = f
    return f
end
local EUI = {
    IS_FOREVER = true,
    GetGoldLedger = function() return { CharKey = function() return charKey end } end,
    CharKey = function() return charKey end,
    CharGUID = function() return UnitGUID("player") end,
    RealmGroupName = function() return "Realm" end,
    GetClassColor = function() return nil end,
    HexColor = function() return "|cffffffff" end,
    WithSurname = function(a) return a end,
    L = function(s) return s end,
    Lf = function(s, ...) return string.format(s:gsub("%%1%$d", "%%d"), ...) end,
}
_G.EllesmereUIDB = { bagOfflineBank = true, bagTooltipCounts = true }
_G.EllesmereUIBagsInventoryDB = nil
_G.EllesmereUI = EUI
_G.EUI_CLIENT_BLOCKED = false
_G.EUI_Bags = {}
_G.Enum = { BagIndex = { Keyring = -1 }, PlayerInteractionType = {}, ItemBind = { ToWoWAccount = 2, ToBnetAccount = 3 }, TooltipDataType = { Item = 1 }, BankType = {} }
_G.CreateFrame = function() return frame() end
_G.C_Timer = { After = function(_, fn) queued[#queued + 1] = fn end }
_G.time = function() return now end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
_G.UnitGUID = function() return "guid-" .. charKey end
_G.UnitClass = function() return "Mage", "MAGE" end
_G.UnitName = function() return charKey:match("^[^-]+") end
_G.UnitNameUnmodified = _G.UnitName
_G.UnitLevel = function() return 60 end
_G.ItemLocation = { CreateEmpty = function()
    return { SetBagAndSlot = function(self, bag, slot) self.bag, self.slot = bag, slot end }
end }
_G.C_Item = {
    GetItemInfo = function()
        local r = {}; for i = 1, 13 do r[i] = nil end; r[14] = 1; return unpack(r)
    end,
    DoesItemExist = function() return true end,
    IsBoundToAccountUntilEquip = function() return false end,
}
_G.C_Container = {
    GetContainerNumSlots = function(bag)
        if bag == -1 then scans = scans + 1 end
        return (containers[bag] and containers[bag].size) or 0
    end,
    GetContainerItemInfo = function(bag, slot)
        local c = containers[bag]; return c and c.items[slot]
    end,
    GetContainerItemLink = function(bag, slot)
        local c, info = containers[bag], containers[bag] and containers[bag].items[slot]
        return info and info.hyperlink
    end,
}
_G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) _G.tipCall = fn end }
_G.GameTooltip, _G.ItemRefTooltip = {}, {}
local tooltip = { lines = {} }
function tooltip:IsForbidden() return false end
function tooltip:AddLine(s) self.lines[#self.lines + 1] = s end
function tooltip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. " " .. tostring(b) end
_G.GameTooltip = tooltip
_G.ItemRefTooltip = {}

local ns = {
    KeyringBagID = function() return keyringOn and -1 or nil end,
    _bagsInternals = { GetItemLevelAtLocation = function() return 10 end },
}
local chunk = assert(loadfile(TARGET))
setfenv(chunk, setmetatable({ select = select }, { __index = _G }))
chunk("EllesmereUIBags_Offline.lua", ns)
local offline = ns.Offline
local boot
for _, f in ipairs(frames) do if f.events.PLAYER_LOGIN then boot = f end end
check(boot ~= nil, "login frame registered")
boot.handler(boot, "PLAYER_LOGIN")
local function drain()
    local i = 1
    while queued[i] do local fn = queued[i]; i = i + 1; fn() end
    queued = {}
end
local function fire(event, arg)
    for _, f in ipairs(frames) do if f.events[event] then f.handler(f, event, arg) end end
    drain()
end

fire("BAG_UPDATE_DELAYED")
check(offline.Char("guid-A-Realm").keyring == nil, "never-recorded differs from empty")
keyringOn = true
offline.Sync(); drain()
local saved = offline.Char("guid-A-Realm")
check(type(saved.keyring) == "table" and saved.keyring.size == 3, "enabled empty keyring is captured")
check(next(saved.keyring.items) == nil and saved.keyringTime == now, "empty snapshot and timestamp saved")
now = 1100; fire("BAG_UPDATE_DELAYED")
check(saved.keyringTime == now, "unchanged observed snapshot advances freshness")
containers[-1].items[2] = { hyperlink = "|Hitem:7001:0|h[Test]|h", stackCount = 2, isBound = false }
now = 1200; fire("BAG_UPDATE", -1)
check(saved.keyring.items[2] == "item:7001:0" and saved.keyring.counts[2] == 2, "populated snapshot retains physical slot and stack")
check(saved.keyringTime == now, "keyring event records freshness")
tooltip.lines = {}
tipCall(tooltip, { id = 7001 })
local hasKeyringOwner = false
for _, line in ipairs(tooltip.lines) do if line:find("Keyring 2", 1, true) then hasKeyringOwner = true end end
check(hasKeyringOwner, "ownership tooltip includes saved Keyring items")
containers[-1].items[2] = nil
now = 1250; fire("BAG_UPDATE", -1)
check(saved.keyring.items[2] == nil and saved.keyringTime == now, "removal updates snapshot and freshness")
tooltip.lines = {}
tipCall(tooltip, { id = 7001 })
local staleOwner = false
for _, line in ipairs(tooltip.lines) do if line:find("Keyring", 1, true) then staleOwner = true end end
check(not staleOwner, "incremental ownership index removes a keyring item")
containers[-1].items[2] = { hyperlink = "|Hitem:7001:0|h[Test]|h", stackCount = 2, isBound = false }
now = 1275; fire("BAG_UPDATE", -1)

containers[-1].size = 0; now = 1280; fire("BAG_UPDATE_DELAYED")
check(saved.keyring.items[2] == "item:7001:0" and saved.keyringTime == 1275, "zero capacity preserves the last successful snapshot")
containers[-1].size = 3

local before = scans
_G.EllesmereUIDB.bagOfflineBank = nil; offline.Sync()
containers[-1].size = 0; now = 1300; fire("BAG_UPDATE_DELAYED")
check(scans == before, "disabled recording does not scan Keyring")
check(saved.keyring.items[2] == "item:7001:0" and saved.keyringTime == 1275, "disabled or unavailable capture preserves prior data")

_G.EllesmereUIDB.bagOfflineBank = true; keyringOn = true
containers[-1].size = 3; charKey = "B-Realm"; offline.Sync(); drain()
check(offline.Char("guid-B-Realm").keyring ~= nil, "character transition captures into the new character")
check(offline.Char("guid-A-Realm").keyring.items[2] == "item:7001:0", "character snapshots remain isolated")
offline.Forget("guid-A-Realm")
check(offline.Char("guid-A-Realm") == nil, "forget removes character and keyring snapshot")
offline.Wipe()
check(offline.Char("guid-B-Realm") == nil, "reset removes all saved character snapshots")
drain()
check(type(offline.Char("guid-B-Realm").keyring) == "table", "reset recaptures the enabled character keyring")

-- Both collector and custom keyword are run against live behavior: the custom
-- evaluator must get the first chance to clear Blizzard's filtered flag.
local refreshPath = "EllesmereUIBags/EUI_Bags_Refresh.lua"
local rf = assert(io.open(refreshPath, "rb")); local refresh = rf:read("*a"); rf:close()
local a = assert(refresh:find("function ns.CollectKeyringSlots", 1, true))
local b = assert(refresh:find("\nend\n", a, true)) + 4
local helper = refresh:sub(a, b)
local live = { [1] = { isFiltered = true }, [3] = { isFiltered = false } }
_G.C_Container.GetContainerNumSlots = function() return 4 end
_G.C_Container.GetContainerItemInfo = function(_, slot) return live[slot] end
_G.C_Container.GetContainerItemLink = function(_, slot) return "link" .. slot end
local filteredSeen = false
_G.EUI_Bags.ApplyBindKeyword = function(info, bag, slot)
    if slot == 1 then filteredSeen = info.isFiltered; info.isFiltered = false end
end
local env = setmetatable({ ns = { }, C_Container = _G.C_Container, EUI_Bags = _G.EUI_Bags }, { __index = _G })
env.ns.CollectKeyringSlots = nil
local f = assert(loadstring(helper)); setfenv(f, env); f()
local slots, used, capacity = env.ns.CollectKeyringSlots(-1, false)
check(filteredSeen and used == 2 and capacity == 4, "keyword override runs before filtering and counts physical slots")
check(#slots == 4 and slots[1].slot == 1 and slots[3].slot == 3 and slots[2].bag == -1, "collector preserves gaps and physical identities")
local _, searchedUsed, searchedCapacity = env.ns.CollectKeyringSlots(-1, true)
check(searchedUsed == used and searchedCapacity == capacity, "search leaves used and capacity counts unchanged")

print("Offline Keyring behavioral tests passed")
