local specs = {
    { 269, "Windwalker" },
    { 268, "Brewmaster" },
    { 270, "Mistweaver" },
}
local lootSpecID = 0

function GetNumSpecializations() return #specs end
function GetSpecializationInfo(index)
    local spec = specs[index]
    return spec and spec[1], spec and spec[2]
end
function GetLootSpecialization() return lootSpecID end
C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function(index) return specs[index][1] end,
}

local ns = {}
assert(loadfile("EllesmereUILootTracker/EllesmereUILootTracker_Data.lua"))(
    "EllesmereUILootTracker", ns)

assert(not ns.IsPlayerSpecID(70), "Retribution must not be valid for a Monk")
assert(ns.NormalizePlayerSpecID(70) == 269,
    "foreign class selection must fall back to the active specialization")

lootSpecID = 268
assert(ns.NormalizePlayerSpecID(70) == 268,
    "foreign class selection must prefer a valid explicit loot specialization")
assert(ns.NormalizePlayerSpecID(270) == 270,
    "a valid specialization selection for the current class must be preserved")

print("loot specialization selection ok")
