EUI_CLIENT_BLOCKED = false
time = os.time
C_Item = {}

for index, name in ipairs({
    "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "BACKSLOT", "CHESTSLOT", "WRISTSLOT",
    "HANDSSLOT", "WAISTSLOT", "LEGSSLOT", "FEETSLOT", "FINGER0SLOT", "FINGER1SLOT",
    "TRINKET0SLOT", "TRINKET1SLOT", "MAINHANDSLOT", "SECONDARYHANDSLOT",
}) do
    _G[name] = name
end

for index, name in ipairs({
    "INVSLOT_HEAD", "INVSLOT_NECK", "INVSLOT_SHOULDER", "INVSLOT_BACK", "INVSLOT_CHEST",
    "INVSLOT_WRIST", "INVSLOT_HAND", "INVSLOT_WAIST", "INVSLOT_LEGS", "INVSLOT_FEET",
    "INVSLOT_FINGER1", "INVSLOT_FINGER2", "INVSLOT_TRINKET1", "INVSLOT_TRINKET2",
    "INVSLOT_MAINHAND", "INVSLOT_OFFHAND",
}) do
    _G[name] = index
end

local data = { goals = {} }
local ns = { PRIORITY_BIS = 3 }
local function GoalKey(sourceKey, itemID) return sourceKey .. ":" .. itemID end

function ns.GetSpecData() return data end
function ns.GetGoal(sourceKey, itemID) return data.goals[GoalKey(sourceKey, itemID)] end
function ns.AddGoal(source, item, priority)
    local goal = { priority = priority, sourceKey = source.key, itemID = item.itemID }
    data.goals[GoalKey(source.key, item.itemID)] = goal
    return goal
end
function ns.SetPriority(sourceKey, itemID, priority)
    data.goals[GoalKey(sourceKey, itemID)].priority = priority
end
function ns.RemoveGoal(sourceKey, itemID) data.goals[GoalKey(sourceKey, itemID)] = nil end
function ns.NotifyChanged() end
function ns.RegisterSource() end
function ns.DungeonKey(id) return "dungeon:" .. id end
function ns.RaidKey(id, difficultyID) return "raid:" .. id .. ":" .. difficultyID end
function ns.GetSourceKey(source, difficultyID)
    if source.kind == "raid" then return ns.RaidKey(source.encounterID, difficultyID) end
    if source.kind == "dungeon" then return ns.DungeonKey(source.challengeModeID) end
    return source.key
end
function ns.GetProfile() return { craftedTargetLevel = 318 } end

assert(loadfile("EllesmereUILootTracker/EllesmereUILootTracker_Planner.lua"))(
    "EllesmereUILootTracker", ns)

local source = { kind = "dungeon", challengeModeID = 1, key = "dungeon:1", name = "Test" }
ns.SetPlannedItem("overall", "OFFHAND", {
    source = source,
    item = { itemID = 1, name = "Shield", equipLoc = "INVTYPE_SHIELD" },
    targetLevel = 311,
    keyLevel = 10,
}, 1)
ns.SetPlannedItem("overall", "MAINHAND", {
    source = source,
    item = { itemID = 2, name = "Two-Hand", equipLoc = "INVTYPE_2HWEAPON" },
    targetLevel = 311,
    keyLevel = 10,
}, 1)

local plan = ns.GetPlan("overall", 1)
assert(plan.slots.MAINHAND and not plan.slots.OFFHAND, "two-hand selection must clear off-hand")
assert(not data.goals["dungeon:1:1"], "orphaned planner-only goal must be removed")
assert(data.goals["dungeon:1:2"].priority == 3, "planner selection must be Best in Slot")
local export = ns.GetSimCPlan("overall", 1)
assert(export:find("main_hand=two_hand,id=2,ilevel=311", 1, true), "SimC gear export is incomplete")

data.goals["dungeon:1:3"] = { priority = 1 }
local ring = {
    source = source,
    item = { itemID = 3, name = "Ring", equipLoc = "INVTYPE_FINGER" },
    targetLevel = 311,
    keyLevel = 10,
}
ns.SetPlannedItem("raid:16", "FINGER1", ring, 1)
assert(data.goals["dungeon:1:3"].priority == 3, "existing goal must become Best in Slot")
ns.SetPlannedItem("raid:16", "FINGER1", nil, 1)
assert(data.goals["dungeon:1:3"].priority == 1, "manual goal priority must be restored")

local catalyst = { kind = "catalyst", key = "catalyst", sourceID = 1, name = "Catalyst" }
local tierItem = { itemID = 4, name = "Tier Helm", equipLoc = "INVTYPE_HEAD" }
ns.SetPlannedItem("mplus", "HEAD", {
    source=catalyst, item=tierItem, targetLevel=311, keyLevel=10, linkKind="dungeon",
}, 1)
ns.SetPlannedItem("raid:16", "HEAD", {
    source=catalyst, item=tierItem, targetLevel=318, difficultyID=16, linkKind="catalyst",
}, 1)
assert(data.goals["catalyst:4"].minItemLevel == 318, "shared goal must keep the highest target")
ns.SetPlannedItem("raid:16", "HEAD", nil, 1)
assert(data.goals["catalyst:4"].minItemLevel == 311, "shared goal must fall back to remaining target")

print("loot planner model ok")
