-- Run from the repository root: lua .tools/tests/test_loot_feed_rolls.lua
CreateColor = function() return {} end
issecretvalue = function() return false end
EllesmereUI = { IS_FOREVER = true, _Pool = {},
    L = function(s) return s end, Lf = function(s, ...) return s:format(...) end }
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
local function Stub(root, name, fn)
    local _, owner, index = Upvalue(root, name)
    assert(owner, name .. " not reachable")
    debug.setupvalue(owner, index, fn)
end

local apply = EllesmereUI._LootFeed.Apply
local onEvent = assert(Upvalue(apply, "OnEvent"), "OnEvent not reachable")
local onLoot = assert(Upvalue(apply, "CHAT_EVENTS")).CHAT_MSG_LOOT.handler
local rows, items = {}, {}
Stub(onEvent, "Emit", function(key, data) rows[#rows + 1] = { key = key, data = data } end)
Stub(onLoot, "ShowItem", function(link) items[#items + 1] = link end)

ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" }, [3] = { hex = "|cff0070dd" } }
RAID_CLASS_COLORS = { DRUID = { colorStr = "ffff7c0a" } }
NEED, GREED = "Bedarf", "Gier"
Enum = { EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 } }
LOOT_ITEM_SELF = "You receive loot: %s"
local STAFF = "|cff0070dd|Hitem:7001::::::::20:::::|h[Odo's Ley Staff]|h|r"
local CLOAK = "|cff1eff00|Hitem:6566::::::::20::::1:740:|h[Shimmering Cloak of the Gorilla]|h|r"
local drops = {}
C_LootHistory = { GetSortedInfoForDrop = function(e, l) return drops[e .. ":" .. l] end }
C_Item = {
    GetItemInfoInstant = function() end,
    GetItemInfo = function(link)
        if link == STAFF then return "Odo's Ley Staff", STAFF, 3, 20, 0, 0, 0, 1, 0, 135150 end
        if link == CLOAK then return "Shimmering Cloak of the Gorilla", CLOAK, 2, 20, 0, 0, 0, 1, 0, 133762 end
    end,
}
local function Drop(e, l) onEvent(nil, "LOOT_HISTORY_UPDATE_DROP", e, l) end
local function Player(name, roll, state, extra)
    local p = { playerName = name, roll = roll, state = state, playerClass = "DRUID", isSelf = false }
    for k, v in pairs(extra or {}) do p[k] = v end
    return p
end

drops["2752:232866561"] = { itemHyperlink = STAFF, allPassed = false, rollInfos = {} }
Drop(2752, 232866561)
assert(#rows == 0, "a drop still being picked shows nothing")

drops["2752:232866561"].winner = Player("Esvi Emberfern", 92, 0)
Drop(2752, 232866561)
assert(#rows == 1, "a drop with a winner shows one row")
local d = rows[1].data
assert(d.text == "|cffff7c0aEsvi Emberfern|r won |cff0070ddOdo's Ley Staff|r", "class-colored winner, quality-colored item: " .. d.text)
assert(d.sub == "Bedarf 92" and d.badge == "92", "the winning roll in the client's words: " .. tostring(d.sub))
assert(d.icon == 135150 and d.link == STAFF, "the item's own icon and link")
Drop(2752, 232866561)
assert(#rows == 1, "later updates of a shown drop add nothing")

drops["0:7"] = { itemHyperlink = STAFF, winner = Player("Sylvaris Stormleaf", 98, 3) }
Drop(0, 7)
assert(#rows == 2 and rows[2].key ~= rows[1].key and rows[2].data.sub == "Gier 98",
    "a second copy of the same item is its own row; trash drops (encounter 0) count too")

drops["0:8"] = { itemHyperlink = STAFF, allPassed = true }
Drop(0, 8)
assert(#rows == 3 and rows[3].data.text == "Everyone passed on |cff0070ddOdo's Ley Staff|r" and not rows[3].data.sub,
    "everyone passing is one row without a roll")

drops["0:9"] = { itemHyperlink = CLOAK, winner = Player("Direktsaft Traube", 88, 0, { isSelf = true }) }
Drop(0, 9)
assert(#rows == 3, "your own win adds no roll row")
onLoot("You receive loot: [Shimmering Cloak of the Gorilla]")
assert(items[1] == CLOAK, "a random-suffix item you won resolves through the history's link")
assert(assert(Upvalue(onEvent, "wins"))["Shimmering Cloak of the Gorilla"] == "Bedarf 88",
    "the item's loot row picks up your roll")

drops["0:10"] = { itemHyperlink = "|[Broken]|r", winner = Player("Brunssi Kalja", nil, 3) }
Drop(0, 10)
assert(#rows == 4 and rows[4].data.icon:find("QuestionMark") and rows[4].data.sub == nil
    and rows[4].data.text:find("Brunssi Kalja|r won |cffffffffBroken|r", 1, true),
    "an unusable link and a winner without a roll still give a readable row")

print("loot feed roll results OK")
